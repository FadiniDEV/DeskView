import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/constants/protocol_constants.dart';
import '../../core/crypto/session_cipher.dart';
import '../../core/utils/desk_id_formatter.dart';
import '../../domain/entities/connection_candidate.dart';
import '../../domain/entities/desk_identity.dart';
import '../../domain/entities/input_commands.dart';
import '../../domain/entities/peer_device.dart';
import '../../domain/entities/session_models.dart';
import '../codec/desk_rt_tile_codec.dart';
import 'global_signaling_service.dart';
import 'host_session_server.dart';
import 'lan_discovery_service.dart';
import 'packet_frame_io.dart';
import 'session_transport.dart';

/// Controlador reativo de uma sessão remota ativa (Aba de Visualização e Controle).
class RemoteSessionClientController extends ChangeNotifier {
  final String sessionId;
  final String targetTitle;
  final String targetDeskId;
  final String password;
  final DeskIdentity localIdentity;
  final SessionTransport transport;

  bool _isConnected = false;
  bool _isConnecting = true;
  String _statusMessage = 'Autenticando sessão...';
  String _remoteHostName = '';
  String _remoteFingerprint = '';

  ScreenMetadata _screenMeta = const ScreenMetadata(
    monitorCount: 1,
    selectedMonitorIndex: -1,
    width: 1280,
    height: 720,
  );

  // Estado visual dos 48 blocos (Grade 8x6) para renderização rápida no CustomPainter
  final Map<String, DirtyTileBlock> _renderedTiles = <String, DirtyTileBlock>{};
  int _cursorX = 640;
  int _cursorY = 360;

  bool _controlInputEnabled = true;
  bool _stretchToWindow = true;
  bool _virtualGamepadVisible = false;
  bool _chatPanelVisible = false;
  int _selectedQuality = ProtocolConstants.qualityBalanced;
  int _selectedMonitorOption = 0; // 0 = Primário (-1), 1 = Todos (-2), >=2 = Índice

  final List<SessionChatMessage> _chatMessages = <SessionChatMessage>[];
  SessionTelemetry _telemetry = const SessionTelemetry();

  // Contadores de telemetria por segundo
  int _framesThisSec = 0;
  int _tilesThisSec = 0;
  int _bytesThisSec = 0;
  int _lastRttMs = 4;
  int _lastPingSentEpochMs = 0;

  StreamSubscription<DecodedPacketFrame>? _sub;
  Timer? _telemetryTimer;

  RemoteSessionClientController({
    required this.sessionId,
    required this.targetTitle,
    required this.targetDeskId,
    required this.password,
    required this.localIdentity,
    required this.transport,
  }) {
    _remoteHostName = targetTitle;
    _telemetry = SessionTelemetry(activeRoute: transport.routeType);
  }

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get statusMessage => _statusMessage;
  String get remoteHostName => _remoteHostName;
  String get remoteFingerprint => _remoteFingerprint;
  ScreenMetadata get screenMeta => _screenMeta;
  List<DirtyTileBlock> get activeTiles => _renderedTiles.values.toList(growable: false);
  int get cursorX => _cursorX;
  int get cursorY => _cursorY;
  bool get controlInputEnabled => _controlInputEnabled;
  bool get stretchToWindow => _stretchToWindow;
  bool get virtualGamepadVisible => _virtualGamepadVisible;
  bool get chatPanelVisible => _chatPanelVisible;
  int get selectedQuality => _selectedQuality;
  int get selectedMonitorOption => _selectedMonitorOption;
  List<SessionChatMessage> get chatMessages => List<SessionChatMessage>.unmodifiable(_chatMessages);
  SessionTelemetry get telemetry => _telemetry;

  /// Inicia o Handshake autenticado e o loop de recepção de pacotes.
  Future<bool> startHandshakeAndSession({bool enableSessionEncryption = true}) async {
    final Completer<bool> authCompleter = Completer<bool>();
    final String clientSessionNonce =
        enableSessionEncryption ? SessionCipher.generateNonceHex(8) : '';

    _sub = transport.incomingFrames.listen(
      (DecodedPacketFrame frame) {
        _bytesThisSec += frame.payload.length + 5;

        if (!_isConnected && frame.type == PacketType.handshakeAuthResponse) {
          final String resp = utf8.decode(frame.payload, allowMalformed: true);
          if (!resp.startsWith('ACCEPTED|')) {
            final String reason = resp.replaceFirst('REJECTED|', '');
            _isConnecting = false;
            _isConnected = false;
            _statusMessage = 'Acesso negado: $reason';
            notifyListeners();
            if (!authCompleter.isCompleted) authCompleter.complete(false);
            return;
          }

          final List<String> parts = resp.split('|');
          final String hostDeskId = parts.length > 1 ? parts[1] : targetDeskId;
          _remoteHostName = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : targetTitle;
          _remoteFingerprint = parts.length > 3 ? parts[3] : '';
          final int monCount = parts.length > 4 ? (int.tryParse(parts[4]) ?? 1) : 1;
          final String hostSessionNonce = parts.length > 5 ? parts[5] : '';

          if (clientSessionNonce.isNotEmpty && hostSessionNonce.isNotEmpty) {
            final String derivedKey =
                '$hostDeskId|${localIdentity.deskId}|$clientSessionNonce|$hostSessionNonce';
            transport.setSessionEncryptionKey(derivedKey);
          }

          _screenMeta = ScreenMetadata(
            monitorCount: monCount.clamp(1, 16),
            selectedMonitorIndex: -1,
            width: _screenMeta.width,
            height: _screenMeta.height,
          );

          _isConnecting = false;
          _isConnected = true;
          _statusMessage =
              'Conectado a $_remoteHostName (${DeskIdFormatter.format(hostDeskId)}) via ${transport.routeType.label}';
          _appendSystemLog(
            'Sessão estabelecida com $_remoteHostName • Rota: ${transport.routeType.label} • Fingerprint: $_remoteFingerprint',
          );
          _startTelemetryTicker();
          notifyListeners();
          if (!authCompleter.isCompleted) authCompleter.complete(true);
          return;
        }

        if (_isConnected) {
          _handleAuthenticatedFrame(frame);
        }
      },
      onError: (_) => _onDisconnected('Conexão interrompida na rota ${transport.routeType.label}.'),
      onDone: () => _onDisconnected('Sessão encerrada pelo host remoto.'),
    );

    final String authPayload =
        '${localIdentity.deskId}|${localIdentity.machineName}|$password|${localIdentity.localLoopbackNonce}|$clientSessionNonce';
    transport.sendPacket(
      PacketType.handshakeAuthRequest,
      utf8.encode(authPayload),
    );

    return authCompleter.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        _isConnecting = false;
        _statusMessage = 'Tempo esgotado no Handshake com o host.';
        notifyListeners();
        return false;
      },
    );
  }

  void _handleAuthenticatedFrame(DecodedPacketFrame frame) {
    switch (frame.type) {
      case PacketType.screenMeta:
        _screenMeta = ScreenMetadata.fromBytes(frame.payload);
        notifyListeners();
        break;

      case PacketType.cursorUpdate:
        if (frame.payload.length >= 8) {
          final ByteData bd = ByteData.sublistView(frame.payload);
          _cursorX = bd.getInt32(0, Endian.little);
          _cursorY = bd.getInt32(4, Endian.little);
          notifyListeners();
        }
        break;

      case PacketType.tileFrameDirty:
        final DirtyTileFrame? decoded = DeskRtTileCodec.unpackDirtyTileFrame(frame.payload);
        if (decoded != null) {
          if (decoded.fullWidth != _screenMeta.width ||
              decoded.fullHeight != _screenMeta.height) {
            _renderedTiles.clear();
            _screenMeta = ScreenMetadata(
              monitorCount: _screenMeta.monitorCount,
              selectedMonitorIndex: _screenMeta.selectedMonitorIndex,
              left: _screenMeta.left,
              top: _screenMeta.top,
              width: decoded.fullWidth,
              height: decoded.fullHeight,
            );
          }
          for (final DirtyTileBlock tile in decoded.tiles) {
            _renderedTiles['${tile.x}_${tile.y}'] = tile;
          }
          _tilesThisSec += decoded.tiles.length;
          _framesThisSec++;
          notifyListeners();
        }
        break;

      case PacketType.chatMessage:
        final String text = utf8.decode(frame.payload, allowMalformed: true);
        _chatMessages.add(
          SessionChatMessage(
            senderName: _remoteHostName,
            text: text,
            timestamp: DateTime.now(),
            isLocalSender: false,
          ),
        );
        notifyListeners();
        break;

      case PacketType.pong:
        if (_lastPingSentEpochMs > 0) {
          _lastRttMs =
              (DateTime.now().millisecondsSinceEpoch - _lastPingSentEpochMs).clamp(1, 9999);
        }
        break;

      case PacketType.disconnect:
        _onDisconnected('Sessão encerrada pelo host remoto.');
        break;

      default:
        break;
    }
  }

  void _startTelemetryTicker() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isConnected) return;

      _lastPingSentEpochMs = DateTime.now().millisecondsSinceEpoch;
      final Uint8List pingPayload = Uint8List(4);
      ByteData.sublistView(pingPayload)
          .setInt32(0, _lastPingSentEpochMs & 0x7fffffff, Endian.little);
      transport.sendPacket(PacketType.ping, pingPayload);

      final double kbps = (_bytesThisSec * 8.0) / 1000.0;
      _telemetry = SessionTelemetry(
        fps: _framesThisSec,
        dirtyTilesPerSecond: _tilesThisSec,
        kbps: kbps,
        latencyMs: _lastRttMs,
        activeRoute: transport.routeType,
        isEncrypted: true,
      );
      _statusMessage =
          '$_remoteHostName • ${_telemetry.fps} FPS (${_telemetry.dirtyTilesPerSecond} tiles/s) • '
          '${_telemetry.kbps.toStringAsFixed(0)} kbps • ${_telemetry.latencyMs} ms • ${transport.routeType.label}';

      _framesThisSec = 0;
      _tilesThisSec = 0;
      _bytesThisSec = 0;
      notifyListeners();
    });
  }

  void setControlInputEnabled(bool value) {
    _controlInputEnabled = value;
    notifyListeners();
  }

  void setStretchToWindow(bool value) {
    _stretchToWindow = value;
    notifyListeners();
  }

  void toggleVirtualGamepad() {
    _virtualGamepadVisible = !_virtualGamepadVisible;
    notifyListeners();
  }

  void toggleChatPanel() {
    _chatPanelVisible = !_chatPanelVisible;
    notifyListeners();
  }

  void selectMonitorOption(int optionIndex) {
    _selectedMonitorOption = optionIndex;
    int protoIndex = -1;
    if (optionIndex == 0) {
      protoIndex = -1; // Monitor Principal
    } else if (optionIndex == 1) {
      protoIndex = -2; // Todos os Monitores
    } else {
      protoIndex = optionIndex - 2;
    }
    final Uint8List payload = Uint8List(4);
    ByteData.sublistView(payload).setInt32(0, protoIndex, Endian.little);
    transport.sendPacket(PacketType.switchMonitor, payload);
    notifyListeners();
  }

  void selectQuality(int quality) {
    _selectedQuality = quality;
    final Uint8List payload = Uint8List(4);
    ByteData.sublistView(payload).setInt32(0, quality, Endian.little);
    transport.sendPacket(PacketType.qualityChange, payload);
    notifyListeners();
  }

  void sendMouseCommand(MouseInputCommand cmd) {
    if (!_isConnected || !_controlInputEnabled) return;
    transport.sendPacket(PacketType.mouseInput, cmd.toBytes());
  }

  void sendKeyCommand(KeyInputCommand cmd) {
    if (!_isConnected || !_controlInputEnabled) return;
    transport.sendPacket(PacketType.keyInput, cmd.toBytes());
  }

  void sendGamepadCommand(GamepadInputCommand cmd) {
    if (!_isConnected || !_controlInputEnabled) return;
    transport.sendPacket(PacketType.gamepadInput, cmd.toBytes());
  }

  void sendChatMessage(String text) {
    if (!_isConnected || text.trim().isEmpty) return;
    final String clean = text.trim();
    transport.sendPacket(PacketType.chatMessage, utf8.encode(clean));
    _chatMessages.add(
      SessionChatMessage(
        senderName: 'Você',
        text: clean,
        timestamp: DateTime.now(),
        isLocalSender: true,
      ),
    );
    notifyListeners();
  }

  void sendClipboardText(String text) {
    if (!_isConnected || text.isEmpty) return;
    transport.sendPacket(PacketType.clipboardText, utf8.encode(text));
    _appendSystemLog('Área de transferência sincronizada (${text.length} caracteres).');
  }

  /// Envia um arquivo real ou simulado em chunks de 32 KB com verificação de limite de 500 MB.
  Future<void> sendFileBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!_isConnected) return;
    if (bytes.length > ProtocolConstants.maxFileTransferBytes) {
      _appendSystemLog('Erro: Arquivo excede o limite de 500 MB.');
      return;
    }
    final String safeName = DeskIdFormatter.sanitizeFileName(fileName);
    transport.sendPacket(PacketType.fileTransferOffer, utf8.encode(safeName));

    int offset = 0;
    while (offset < bytes.length) {
      final int end =
          (offset + ProtocolConstants.fileTransferChunkBytes).clamp(0, bytes.length);
      transport.sendPacket(PacketType.fileTransferChunk, bytes.sublist(offset, end));
      offset = end;
    }
    transport.sendPacket(PacketType.fileTransferEnd, const <int>[]);
    _appendSystemLog('Arquivo enviado com sucesso: $safeName (${bytes.length} bytes)');
  }

  void _appendSystemLog(String text) {
    _chatMessages.add(
      SessionChatMessage(
        senderName: 'Sistema',
        text: text,
        timestamp: DateTime.now(),
        isSystemLog: true,
      ),
    );
    notifyListeners();
  }

  void _onDisconnected(String reason) {
    if (!_isConnected && !_isConnecting) return;
    _isConnected = false;
    _isConnecting = false;
    _statusMessage = reason;
    _telemetryTimer?.cancel();
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (_isConnected && transport.isOpen) {
      transport.sendPacket(PacketType.disconnect, const <int>[]);
    }
    _isConnected = false;
    _isConnecting = false;
    _telemetryTimer?.cancel();
    await _sub?.cancel();
    await transport.close();
    notifyListeners();
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _sub?.cancel();
    transport.close();
    super.dispose();
  }
}

/// Orquestrador de Conexão Multi-Rede (LAN -> STUN P2P -> WAN Direct -> Relay Criptografado).
class ConnectionOrchestrator {
  final LanDiscoveryService _lanDiscovery;
  final GlobalSignalingService _globalSignaling;
  final HostSessionServer _hostServer;

  Completer<
      ({
        bool accepted,
        String targetHost,
        String publicEp,
        String localEp,
        String? relaySessionId,
        String? rejectReason,
      })>? _pendingSignalingAck;
  String? _pendingTargetDeskId;

  ConnectionOrchestrator({
    required LanDiscoveryService lanDiscovery,
    required GlobalSignalingService globalSignaling,
    required HostSessionServer hostServer,
  })  : _lanDiscovery = lanDiscovery,
        _globalSignaling = globalSignaling,
        _hostServer = hostServer;

  /// Processa o `ACK` recebido da sinalização global.
  void notifyGlobalConnectionAccepted({
    required String targetDeskId,
    required String targetHostName,
    required String targetPublicEndpoint,
    required String targetLocalEndpoint,
    String? relaySessionId,
  }) {
    if (_pendingTargetDeskId == targetDeskId &&
        _pendingSignalingAck != null &&
        !_pendingSignalingAck!.isCompleted) {
      _pendingSignalingAck!.complete((
        accepted: true,
        targetHost: targetHostName,
        publicEp: targetPublicEndpoint,
        localEp: targetLocalEndpoint,
        relaySessionId: relaySessionId,
        rejectReason: null,
      ));
    }
  }

  /// Processa o `REJ` recebido da sinalização global.
  void notifyGlobalConnectionRejected({
    required String targetDeskId,
    required String targetHostName,
    required String reason,
  }) {
    if (_pendingTargetDeskId == targetDeskId &&
        _pendingSignalingAck != null &&
        !_pendingSignalingAck!.isCompleted) {
      _pendingSignalingAck!.complete((
        accepted: false,
        targetHost: targetHostName,
        publicEp: '',
        localEp: '',
        relaySessionId: null,
        rejectReason: reason,
      ));
    }
  }

  void cancelPendingConnection() {
    if (_pendingSignalingAck != null && !_pendingSignalingAck!.isCompleted) {
      _pendingSignalingAck!.complete((
        accepted: false,
        targetHost: '',
        publicEp: '',
        localEp: '',
        relaySessionId: null,
        rejectReason: 'Conexão cancelada pelo operador.',
      ));
    }
    _pendingTargetDeskId = null;
  }

  /// Estabelece conexão com o dispositivo alvo selecionando automaticamente a melhor rota:
  /// 1. Loopback Local (`127.0.0.1` ou próprio `DeskID`)
  /// 2. LAN Direta (UDP Discovery `50001` -> TCP Low-Latency)
  /// 3. WAN P2P / STUN (`targetPublicEndpoint` / `targetLocalEndpoint`)
  /// 4. Relay Criptografado (`RelaySessionTransport` — funciona em 100% de CGNAT / Redes Diferentes)
  Future<({RemoteSessionClientController? session, String? errorMessage})> connectToTarget({
    required String rawTarget,
    required String password,
    required DeskIdentity localIdentity,
    required String myPublicEndpoint,
    required String myLocalEndpoint,
    required void Function(String progressBanner) onProgress,
  }) async {
    final String cleanTarget = rawTarget.trim();
    if (cleanTarget.isEmpty) {
      return (session: null, errorMessage: 'Informe um código DeskView ou IP:Porta.');
    }

    // Caso 1: O usuário digitou um código DeskID de 9 dígitos
    if (DeskIdFormatter.isValidDeskId(cleanTarget)) {
      final String targetDigits = DeskIdFormatter.extractDigits(cleanTarget);

      // 1A. Verifica se é Loopback (próprio computador)
      if (targetDigits == localIdentity.deskId) {
        onProgress('Conectando à própria estação (Loopback)...');
        final SessionTransport transport = await _openLoopbackOrLocalTcpTransport(
          port: _hostServer.boundPort,
        );
        return _initializeSessionController(
          transport: transport,
          targetDeskId: targetDigits,
          targetTitle: '${localIdentity.machineName} (Loopback)',
          password: password,
          localIdentity: localIdentity,
        );
      }

      // 1B. Verifica se o peer foi descoberto na Rede Local (LAN)
      final PeerDevice? lanPeer = _lanDiscovery.resolveByDeskId(targetDigits);
      if (lanPeer != null) {
        onProgress(
          'Dispositivo encontrado na LAN (${lanPeer.endpoint}). Conectando diretamente...',
        );
        final SessionTransport? lanTransport = await _tryDirectTcpConnect(
          lanPeer.ipAddress,
          lanPeer.port,
          TransportRouteType.lanDirect,
          timeout: const Duration(milliseconds: 2200),
        );
        if (lanTransport != null) {
          return _initializeSessionController(
            transport: lanTransport,
            targetDeskId: targetDigits,
            targetTitle: lanPeer.hostName,
            password: password,
            localIdentity: localIdentity,
          );
        }
      }

      // 1C. Negociação Global Entre Redes Diferentes (Sinalização Assinada + Corrida P2P STUN + Relay Fallback)
      final String relaySessionId =
          'rv3_${localIdentity.deskId}_${targetDigits}_${SessionCipher.generateNonceHex(4)}';

      _pendingTargetDeskId = targetDigits;
      _pendingSignalingAck = Completer<
          ({
            bool accepted,
            String targetHost,
            String publicEp,
            String localEp,
            String? relaySessionId,
            String? rejectReason,
          })>();

      onProgress(
        'Solicitando aprovação em ${DeskIdFormatter.format(targetDigits)} via Rede Global...',
      );

      _globalSignaling.sendConnectRequest(
        targetDeskId: targetDigits,
        callerDeskId: localIdentity.deskId,
        callerHostName: localIdentity.machineName,
        callerPublicEndpoint: myPublicEndpoint,
        callerLocalEndpoint: myLocalEndpoint,
        relaySessionId: relaySessionId,
      );

      // Se já conhecemos o endpoint público pelo cache global e o usuário informou senha desassistida,
      // tentamos paralelamente uma conexão direta rápida
      final PeerDevice? cachedGlobalPeer = _globalSignaling.resolveDeskId(targetDigits);
      if (cachedGlobalPeer != null && password.isNotEmpty) {
        final SessionTransport? fastDirect = await _tryDirectTcpConnect(
          cachedGlobalPeer.ipAddress,
          cachedGlobalPeer.port,
          TransportRouteType.stunReflexiveP2P,
          timeout: const Duration(milliseconds: 1800),
        );
        if (fastDirect != null) {
          _pendingTargetDeskId = null;
          return _initializeSessionController(
            transport: fastDirect,
            targetDeskId: targetDigits,
            targetTitle: cachedGlobalPeer.hostName,
            password: password,
            localIdentity: localIdentity,
          );
        }
      }

      final ({
        bool accepted,
        String targetHost,
        String publicEp,
        String localEp,
        String? relaySessionId,
        String? rejectReason,
      }) ackResult = await _pendingSignalingAck!.future.timeout(
        ProtocolConstants.sessionApprovalTimeout,
        onTimeout: () => (
          accepted: false,
          targetHost: '',
          publicEp: '',
          localEp: '',
          relaySessionId: null,
          rejectReason:
              'O dispositivo ${DeskIdFormatter.format(targetDigits)} não respondeu a tempo.',
        ),
      );
      _pendingTargetDeskId = null;

      if (!ackResult.accepted) {
        return (
          session: null,
          errorMessage: ackResult.rejectReason ?? 'Conexão recusada pelo usuário remoto.',
        );
      }

      onProgress('Aprovado por ${ackResult.targetHost}! Negociando rota P2P / Relay...');

      // Corrida de Candidatos:
      // 1) Tenta conexão direta ao endpoint Local (caso estejam na mesma rede sem broadcast)
      // 2) Tenta conexão direta ao endpoint Público STUN/WAN
      // 3) Se ambos falharem (CGNAT / NAT Simétrico), promove automaticamente o Túnel Relay Criptografado!
      final SessionTransport transport = await _negotiateBestCrossNetworkTransport(
        publicEndpoint: ackResult.publicEp,
        localEndpoint: ackResult.localEp,
        relaySessionId: ackResult.relaySessionId ?? relaySessionId,
      );

      return _initializeSessionController(
        transport: transport,
        targetDeskId: targetDigits,
        targetTitle: ackResult.targetHost,
        password: password,
        localIdentity: localIdentity,
      );
    }

    // Caso 2: O usuário digitou IP:Porta diretamente
    final ({String host, int port})? ep = DeskIdFormatter.parseEndpoint(
      cleanTarget,
      defaultPort: localIdentity.listenPort,
    );
    if (ep == null) {
      return (session: null, errorMessage: 'Formato de endereço inválido: $cleanTarget');
    }

    onProgress('Conectando diretamente a ${ep.host}:${ep.port}...');
    if (ep.host == '127.0.0.1' || ep.host == 'localhost' || ep.host == '::1') {
      final SessionTransport loopTransport =
          await _openLoopbackOrLocalTcpTransport(port: ep.port);
      return _initializeSessionController(
        transport: loopTransport,
        targetDeskId: localIdentity.deskId,
        targetTitle: '${localIdentity.machineName} (Local)',
        password: password,
        localIdentity: localIdentity,
      );
    }

    final SessionTransport? directTransport = await _tryDirectTcpConnect(
      ep.host,
      ep.port,
      TransportRouteType.wanDirect,
      timeout: const Duration(seconds: 4),
    );
    if (directTransport == null) {
      return (
        session: null,
        errorMessage:
            'Não foi possível conectar via TCP direto a ${ep.host}:${ep.port}. '
            'Use o código DeskID de 9 dígitos para ativar a travessia automática de NAT/Relay.',
      );
    }

    return _initializeSessionController(
      transport: directTransport,
      targetDeskId: '',
      targetTitle: '${ep.host}:${ep.port}',
      password: password,
      localIdentity: localIdentity,
    );
  }

  Future<SessionTransport> _negotiateBestCrossNetworkTransport({
    required String publicEndpoint,
    required String localEndpoint,
    required String relaySessionId,
  }) async {
    final ({String host, int port})? localEp = DeskIdFormatter.parseEndpoint(localEndpoint);
    final ({String host, int port})? publicEp = DeskIdFormatter.parseEndpoint(publicEndpoint);

    // Tenta rota LAN / Sub-rede privada primeiro
    if (localEp != null && localEp.host != '127.0.0.1') {
      final SessionTransport? lanCandidate = await _tryDirectTcpConnect(
        localEp.host,
        localEp.port,
        TransportRouteType.lanDirect,
        timeout: const Duration(milliseconds: 1100),
      );
      if (lanCandidate != null) return lanCandidate;
    }

    // Tenta rota WAN P2P / STUN
    if (publicEp != null && publicEp.host != '127.0.0.1') {
      final SessionTransport? wanCandidate = await _tryDirectTcpConnect(
        publicEp.host,
        publicEp.port,
        TransportRouteType.stunReflexiveP2P,
        timeout: ProtocolConstants.directConnectionRaceTimeout,
      );
      if (wanCandidate != null) return wanCandidate;
    }

    // Fallback garantido: Túnel Relay Criptografado sobre o canal de sinalização global
    return RelaySessionTransport(
      signaling: _globalSignaling,
      sessionId: relaySessionId,
      isHostSide: false,
    );
  }

  Future<SessionTransport> _openLoopbackOrLocalTcpTransport({required int port}) async {
    final SessionTransport? tcp = await _tryDirectTcpConnect(
      '127.0.0.1',
      port,
      TransportRouteType.loopback,
      timeout: const Duration(milliseconds: 900),
    );
    if (tcp != null) return tcp;

    // Se o socket local estiver restrito em sandbox de teste, usa par em memória
    final ({InMemoryLoopbackTransport client, InMemoryLoopbackTransport host}) pair =
        InMemoryLoopbackTransport.createPair(simulatedRoute: TransportRouteType.loopback);
    _hostServer.acceptTransportConnection(pair.host);
    return pair.client;
  }

  Future<SessionTransport?> _tryDirectTcpConnect(
    String host,
    int port,
    TransportRouteType routeType, {
    required Duration timeout,
  }) async {
    try {
      final Socket socket = await Socket.connect(host, port, timeout: timeout);
      return DirectTcpSessionTransport(socket, routeType: routeType);
    } catch (_) {
      return null;
    }
  }

  Future<({RemoteSessionClientController? session, String? errorMessage})>
      _initializeSessionController({
    required SessionTransport transport,
    required String targetDeskId,
    required String targetTitle,
    required String password,
    required DeskIdentity localIdentity,
  }) async {
    final RemoteSessionClientController controller = RemoteSessionClientController(
      sessionId: SessionCipher.generateNonceHex(6),
      targetTitle: targetTitle,
      targetDeskId: targetDeskId,
      password: password,
      localIdentity: localIdentity,
      transport: transport,
    );

    final bool ok = await controller.startHandshakeAndSession();
    if (!ok) {
      final String err = controller.statusMessage;
      await controller.disconnect();
      return (session: null, errorMessage: err);
    }

    return (session: controller, errorMessage: null);
  }
}
