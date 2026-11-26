import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../core/constants/protocol_constants.dart';
import '../../core/crypto/session_cipher.dart';
import '../../core/utils/desk_id_formatter.dart';
import '../../domain/entities/connection_candidate.dart';
import '../../domain/entities/desk_identity.dart';
import '../../domain/entities/input_commands.dart';
import '../../domain/entities/session_models.dart';
import '../../domain/repositories/identity_repository.dart';
import '../../platform/native_platform_bridge.dart';
import '../codec/desk_rt_tile_codec.dart';
import 'packet_frame_io.dart';
import 'session_transport.dart';

/// Callback invocado quando um operador remoto sem senha desassistida solicita acesso ao Host.
typedef AuthorizeSessionCallback = Future<({bool approved, SessionPermissions permissions})>
    Function({
  required String clientDeskId,
  required String clientHostName,
  required String remoteAddress,
});

/// Servidor Host DeskView Multi-Operador capaz de atender sessões via Socket TCP Direto,
/// Conexão Reversa NAT e Túnel Relay Criptografado.
class HostSessionServer {
  final IdentityRepository _identityRepository;
  final NativePlatformBridge _platformBridge;
  final List<ActiveHostWorker> _activeWorkers = <ActiveHostWorker>[];

  ServerSocket? _tcpServer;
  DeskIdentity? _identity;
  bool _running = false;
  int _boundPort = ProtocolConstants.defaultListenPort;

  AuthorizeSessionCallback? onAuthorizeSessionRequest;
  void Function(String logMessage)? onServerLog;
  void Function(int activeCount)? onActiveSessionCountChanged;
  void Function(SessionChatMessage message)? onChatMessageReceived;

  HostSessionServer({
    required IdentityRepository identityRepository,
    required NativePlatformBridge platformBridge,
  })  : _identityRepository = identityRepository,
        _platformBridge = platformBridge;

  int get boundPort => _boundPort;
  List<ActiveHostWorker> get activeWorkers => List<ActiveHostWorker>.unmodifiable(_activeWorkers);

  Future<int> start(DeskIdentity identity) async {
    _identity = identity;
    if (_running) return _boundPort;
    _running = true;

    int candidatePort = identity.listenPort;
    for (int attempt = 0; attempt < ProtocolConstants.maxPortRetryAttempts; attempt++) {
      try {
        _tcpServer = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          candidatePort,
          shared: true,
        );
        _boundPort = candidatePort;
        break;
      } catch (_) {
        candidatePort++;
      }
    }

    if (_tcpServer != null) {
      onServerLog?.call(
        'Servidor Host DeskView ativo em 0.0.0.0:$_boundPort (ID: ${identity.formattedDeskId})',
      );
      _tcpServer!.listen(
        (Socket clientSocket) {
          final String remoteIp = clientSocket.remoteAddress.address;
          final TransportRouteType route = (remoteIp == '127.0.0.1' || remoteIp == '::1')
              ? TransportRouteType.loopback
              : TransportRouteType.lanDirect;
          acceptTransportConnection(
            DirectTcpSessionTransport(clientSocket, routeType: route),
          );
        },
        onError: (_) {},
      );
    } else {
      onServerLog?.call('Modo Host operando exclusivamente via Túnel Relay Global.');
    }

    return _boundPort;
  }

  void updateIdentity(DeskIdentity updated) {
    _identity = updated;
  }

  /// Aceita uma nova sessão entrante sobre qualquer implementação de [SessionTransport]
  /// (TCP Direto, Conexão Reversa, Relay Criptografado ou Loopback em Memória).
  void acceptTransportConnection(
    SessionTransport transport, {
    SessionPermissions? preApprovedPermissions,
  }) {
    if (_identity == null) {
      transport.close();
      return;
    }

    if (_activeWorkers.length >= ProtocolConstants.maxConcurrentHostSessions) {
      transport.close();
      return;
    }

    late final ActiveHostWorker worker;
    worker = ActiveHostWorker(
      transport: transport,
      identity: _identity!,
      identityRepository: _identityRepository,
      platformBridge: _platformBridge,
      preApprovedPermissions: preApprovedPermissions,
      onAuthorizeRequest: onAuthorizeSessionRequest,
      onLog: (String msg) => onServerLog?.call(msg),
      onChat: (SessionChatMessage chat) => onChatMessageReceived?.call(chat),
      onClosed: () {
        _activeWorkers.remove(worker);
        onActiveSessionCountChanged?.call(_activeWorkers.length);
      },
    );

    _activeWorkers.add(worker);
    onActiveSessionCountChanged?.call(_activeWorkers.length);
    worker.start();
  }

  /// Envia uma mensagem de chat do Host para todos os operadores conectados.
  void broadcastHostChatMessage(String text) {
    if (text.trim().isEmpty) return;
    final Uint8List payload = Uint8List.fromList(utf8.encode(text.trim()));
    for (final ActiveHostWorker w in _activeWorkers.toList()) {
      w.sendChatFromHost(payload);
    }
  }

  Future<void> stopAllSessions() async {
    for (final ActiveHostWorker w in _activeWorkers.toList()) {
      await w.stop();
    }
    _activeWorkers.clear();
    onActiveSessionCountChanged?.call(0);
  }

  Future<void> dispose() async {
    _running = false;
    await stopAllSessions();
    try {
      await _tcpServer?.close();
    } catch (_) {}
    _tcpServer = null;
  }
}

/// Worker dedicado a uma sessão de operador conectado ao Host.
class ActiveHostWorker {
  final SessionTransport transport;
  final DeskIdentity identity;
  final IdentityRepository identityRepository;
  final NativePlatformBridge platformBridge;
  final AuthorizeSessionCallback? onAuthorizeRequest;
  final void Function(String message)? onLog;
  final void Function(SessionChatMessage chat)? onChat;
  final void Function()? onClosed;

  SessionPermissions permissions;
  String remoteClientId = '';
  String remoteClientHost = 'Operador Remoto';

  final DeskRtTileCodec _encoder = DeskRtTileCodec();
  StreamSubscription<DecodedPacketFrame>? _subscription;
  Timer? _captureTimer;
  bool _authenticated = false;
  bool _alive = true;

  int _selectedMonitorIndex = -1;
  int _jpegQuality = ProtocolConstants.qualityBalanced;
  int _frameTick = 0;
  int _lastCursorX = -1;
  int _lastCursorY = -1;
  ScreenMetadata _currentScreenMeta = const ScreenMetadata(
    monitorCount: 1,
    selectedMonitorIndex: -1,
    width: 1920,
    height: 1080,
  );

  // Estado de recebimento seguro de arquivo
  IOSink? _incomingFileSink;
  File? _incomingTempFile;
  String? _incomingSanitizedFileName;
  int _incomingFileBytes = 0;

  ActiveHostWorker({
    required this.transport,
    required this.identity,
    required this.identityRepository,
    required this.platformBridge,
    SessionPermissions? preApprovedPermissions,
    this.onAuthorizeRequest,
    this.onLog,
    this.onChat,
    this.onClosed,
  }) : permissions = preApprovedPermissions ?? const SessionPermissions();

  void start() {
    _subscription = transport.incomingFrames.listen(
      _onFrameReceived,
      onError: (_) => stop(),
      onDone: stop,
    );
  }

  Future<void> _onFrameReceived(DecodedPacketFrame frame) async {
    if (!_alive) return;

    if (!_authenticated) {
      if (frame.type != PacketType.handshakeAuthRequest) {
        await stop();
        return;
      }
      await _handleHandshakeAuth(frame.payload);
      return;
    }

    switch (frame.type) {
      case PacketType.mouseInput:
        if (permissions.allowMouseAndKeyboard && frame.payload.length >= 13) {
          final MouseInputCommand cmd = MouseInputCommand.fromBytes(frame.payload);
          await platformBridge.injectMouseCommand(cmd, _currentScreenMeta);
        }
        break;

      case PacketType.keyInput:
        if (permissions.allowMouseAndKeyboard && frame.payload.length >= 2) {
          final KeyInputCommand cmd = KeyInputCommand.fromBytes(frame.payload);
          await platformBridge.injectKeyCommand(cmd);
        }
        break;

      case PacketType.gamepadInput:
        if (permissions.allowGamepadAndJoystick && frame.payload.length >= 20) {
          final GamepadInputCommand cmd = GamepadInputCommand.fromBytes(frame.payload);
          await platformBridge.injectGamepadCommand(cmd);
        }
        break;

      case PacketType.switchMonitor:
        if (frame.payload.length >= 4) {
          final ByteData bd = ByteData.sublistView(frame.payload);
          _selectedMonitorIndex = bd.getInt32(0, Endian.little);
          _encoder.forceFullKeyFrame();
          await _sendScreenMetadata();
        }
        break;

      case PacketType.qualityChange:
        if (frame.payload.length >= 4) {
          final ByteData bd = ByteData.sublistView(frame.payload);
          _jpegQuality = bd.getInt32(0, Endian.little).clamp(20, 95);
          _encoder.forceFullKeyFrame();
        }
        break;

      case PacketType.clipboardText:
        if (permissions.allowClipboardSync) {
          final String text = utf8.decode(frame.payload, allowMalformed: true);
          try {
            await Clipboard.setData(ClipboardData(text: text));
          } catch (_) {}
        }
        break;

      case PacketType.chatMessage:
        final String chatText = utf8.decode(frame.payload, allowMalformed: true);
        onLog?.call('[Chat de $remoteClientHost]: $chatText');
        onChat?.call(
          SessionChatMessage(
            senderName: remoteClientHost,
            text: chatText,
            timestamp: DateTime.now(),
            isLocalSender: false,
          ),
        );
        break;

      case PacketType.fileTransferOffer:
        if (permissions.allowFileTransfer) {
          await _startIncomingFileTransfer(frame.payload);
        }
        break;

      case PacketType.fileTransferChunk:
        if (permissions.allowFileTransfer) {
          await _appendIncomingFileChunk(frame.payload);
        }
        break;

      case PacketType.fileTransferEnd:
        if (permissions.allowFileTransfer) {
          await _finalizeIncomingFileTransfer();
        }
        break;

      case PacketType.ping:
        transport.sendPacket(PacketType.pong, frame.payload);
        break;

      case PacketType.disconnect:
        await stop();
        break;

      default:
        break;
    }
  }

  Future<void> _handleHandshakeAuth(Uint8List payload) async {
    final String authStr = utf8.decode(payload, allowMalformed: true);
    final List<String> parts = authStr.split('|');
    remoteClientId = parts.isNotEmpty ? DeskIdFormatter.extractDigits(parts[0]) : '000000000';
    remoteClientHost = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : 'Operador';
    final String passwordProvided = parts.length > 2 ? parts[2] : '';
    final String loopbackNonce = parts.length > 3 ? parts[3] : '';
    final String clientSessionNonce = parts.length > 4 ? parts[4] : '';

    bool authorized = false;

    // 1. Verifica senha de acesso desassistido
    if (passwordProvided.isNotEmpty &&
        identityRepository.verifyUnattendedPassword(identity, passwordProvided)) {
      authorized = true;
      onLog?.call('Sessão autenticada por senha desassistida: $remoteClientHost ($remoteClientId)');
    }
    // 2. Verifica loopback com nonce criptográfico legítimo do próprio processo
    else if (loopbackNonce.isNotEmpty && loopbackNonce == identity.localLoopbackNonce) {
      authorized = true;
    }
    // 3. Solicita aprovação interativa na tela do Host
    else if (onAuthorizeRequest != null) {
      final ({bool approved, SessionPermissions permissions}) decision =
          await onAuthorizeRequest!(
        clientDeskId: remoteClientId,
        clientHostName: remoteClientHost,
        remoteAddress: transport.remoteAddressDescription,
      );
      authorized = decision.approved;
      permissions = decision.permissions;
    }

    if (!authorized) {
      final List<int> denyBytes =
          utf8.encode('REJECTED|Sessão recusada pelo usuário remoto.');
      transport.sendPacket(PacketType.handshakeAuthResponse, denyBytes);
      await stop();
      return;
    }

    _authenticated = true;
    final List<ScreenMetadata> monitors = await platformBridge.getAvailableMonitors();
    final int monitorCount = monitors.isNotEmpty ? monitors.length : 1;

    final String hostSessionNonce = SessionCipher.generateNonceHex(8);
    final String okResponse =
        'ACCEPTED|${identity.deskId}|${identity.machineName}|${identity.shortFingerprint}|$monitorCount|$hostSessionNonce';
    transport.sendPacket(
      PacketType.handshakeAuthResponse,
      utf8.encode(okResponse),
    );

    // Se o cliente enviou um nonce de sessão v3, ativa criptografia autenticada no transporte
    if (clientSessionNonce.isNotEmpty) {
      final String derivedKey =
          '${identity.deskId}|$remoteClientId|$clientSessionNonce|$hostSessionNonce';
      transport.setSessionEncryptionKey(derivedKey);
    }

    await _sendScreenMetadata();
    _startCaptureLoop();
  }

  Future<void> _sendScreenMetadata() async {
    final List<ScreenMetadata> monitors = await platformBridge.getAvailableMonitors();
    if (monitors.isNotEmpty) {
      final ScreenMetadata chosen = (_selectedMonitorIndex >= 0 &&
              _selectedMonitorIndex < monitors.length)
          ? monitors[_selectedMonitorIndex]
          : monitors.first;
      _currentScreenMeta = ScreenMetadata(
        monitorCount: monitors.length,
        selectedMonitorIndex: _selectedMonitorIndex,
        left: chosen.left,
        top: chosen.top,
        width: chosen.width,
        height: chosen.height,
      );
    }
    transport.sendPacket(PacketType.screenMeta, _currentScreenMeta.toBytes());
  }

  void _startCaptureLoop() {
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(const Duration(milliseconds: 33), (_) async {
      if (!_alive || !_authenticated || !transport.isOpen) return;
      final ({int width, int height, int cursorX, int cursorY, Uint8List rgbaPixels})
          captured = await platformBridge.captureMonitorRgba(
        _selectedMonitorIndex,
        _frameTick++,
      );

      // 1. Canal rápido de cursor
      if (captured.cursorX != _lastCursorX || captured.cursorY != _lastCursorY) {
        _lastCursorX = captured.cursorX;
        _lastCursorY = captured.cursorY;
        final Uint8List curBytes = Uint8List(8);
        final ByteData cbd = ByteData.sublistView(curBytes);
        cbd.setInt32(0, captured.cursorX, Endian.little);
        cbd.setInt32(4, captured.cursorY, Endian.little);
        transport.sendPacket(PacketType.cursorUpdate, curBytes);
      }

      // 2. Canal de Dirty Tiles DeskRT
      final Uint8List? dirtyPayload = _encoder.encodeDirtyTiles(
        rgbaBuffer: captured.rgbaPixels,
        width: captured.width,
        height: captured.height,
        quality: _jpegQuality,
      );
      if (dirtyPayload != null) {
        transport.sendPacket(PacketType.tileFrameDirty, dirtyPayload);
      }
    });
  }

  void sendChatFromHost(Uint8List utf8Text) {
    if (_alive && _authenticated && transport.isOpen) {
      transport.sendPacket(PacketType.chatMessage, utf8Text);
    }
  }

  Future<void> _startIncomingFileTransfer(Uint8List payload) async {
    await _cleanupIncomingTempFile();
    try {
      final String rawName = utf8.decode(payload, allowMalformed: true);
      _incomingSanitizedFileName = DeskIdFormatter.sanitizeFileName(rawName);
      final Directory safeDir = _resolveSafeTransferDirectory();
      if (!safeDir.existsSync()) {
        safeDir.createSync(recursive: true);
      }
      final String tempPath =
          '${safeDir.path}${Platform.pathSeparator}temp_${SessionCipher.generateNonceHex(6)}.part';
      _incomingTempFile = File(tempPath);
      _incomingFileSink = _incomingTempFile!.openWrite();
      _incomingFileBytes = 0;
      onLog?.call('Recebendo arquivo remoto: $_incomingSanitizedFileName');
    } catch (e) {
      onLog?.call('Erro ao iniciar recebimento de arquivo: $e');
      await _cleanupIncomingTempFile();
    }
  }

  Future<void> _appendIncomingFileChunk(Uint8List chunk) async {
    if (_incomingFileSink == null || _incomingTempFile == null) return;
    if (_incomingFileBytes + chunk.length > ProtocolConstants.maxFileTransferBytes) {
      onLog?.call('Transferência cancelada: arquivo excedeu o limite de 500 MB.');
      await _cleanupIncomingTempFile();
      return;
    }
    _incomingFileSink!.add(chunk);
    _incomingFileBytes += chunk.length;
  }

  Future<void> _finalizeIncomingFileTransfer() async {
    if (_incomingFileSink == null ||
        _incomingTempFile == null ||
        _incomingSanitizedFileName == null) {
      return;
    }
    try {
      await _incomingFileSink!.flush();
      await _incomingFileSink!.close();
      _incomingFileSink = null;

      final Directory safeDir = _resolveSafeTransferDirectory();
      final String finalPath = _resolveUniqueFilePath(safeDir, _incomingSanitizedFileName!);
      await _incomingTempFile!.rename(finalPath);
      _incomingTempFile = null;
      onLog?.call('Arquivo salvo com segurança em: $finalPath');
    } catch (e) {
      onLog?.call('Erro ao finalizar arquivo recebido: $e');
      await _cleanupIncomingTempFile();
    }
  }

  Future<void> _cleanupIncomingTempFile() async {
    try {
      await _incomingFileSink?.close();
    } catch (_) {}
    _incomingFileSink = null;
    if (_incomingTempFile != null) {
      try {
        if (_incomingTempFile!.existsSync()) {
          _incomingTempFile!.deleteSync();
        }
      } catch (_) {}
      _incomingTempFile = null;
    }
  }

  static Directory _resolveSafeTransferDirectory() {
    final String? userProfile =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (userProfile != null && userProfile.isNotEmpty) {
      final Directory desktop =
          Directory('$userProfile${Platform.pathSeparator}Desktop');
      if (desktop.existsSync()) {
        return Directory('${desktop.path}${Platform.pathSeparator}DeskView_Recebidos');
      }
      return Directory('$userProfile${Platform.pathSeparator}DeskView_Recebidos');
    }
    return Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}DeskView_Recebidos',
    );
  }

  static String _resolveUniqueFilePath(Directory dir, String fileName) {
    final String candidate0 = '${dir.path}${Platform.pathSeparator}$fileName';
    if (!File(candidate0).existsSync()) return candidate0;

    final int dot = fileName.lastIndexOf('.');
    final String baseName = dot > 0 ? fileName.substring(0, dot) : fileName;
    final String ext = dot > 0 ? fileName.substring(dot) : '';
    for (int i = 1; i < 1000; i++) {
      final String candidate =
          '${dir.path}${Platform.pathSeparator}$baseName ($i)$ext';
      if (!File(candidate).existsSync()) return candidate;
    }
    return '${dir.path}${Platform.pathSeparator}${baseName}_${SessionCipher.generateNonceHex(3)}$ext';
  }

  Future<void> stop() async {
    if (!_alive) return;
    _alive = false;
    _captureTimer?.cancel();
    await _subscription?.cancel();
    await platformBridge.releaseAllHeldInputs();
    await _cleanupIncomingTempFile();
    await transport.close();
    onClosed?.call();
  }
}
