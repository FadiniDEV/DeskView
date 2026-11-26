import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/constants/protocol_constants.dart';
import '../../core/crypto/session_cipher.dart';
import '../../core/utils/desk_id_formatter.dart';
import '../../domain/entities/desk_identity.dart';
import '../../domain/entities/peer_device.dart';
import '../../domain/entities/session_models.dart';

/// Cliente de Sinalização Global e Relay de Sessão Criptografado sobre MQTT 3.1.1.
/// Resolve definitivamente a descoberta global de DeskIDs e fornece o canal de transporte
/// de fallback para travessia de CGNAT, NAT Simétrico e redes móveis 4G/5G.
class GlobalSignalingService {
  final Map<String, PeerDevice> _globalPeers = <String, PeerDevice>{};
  final Map<String, void Function(Uint8List data)> _tunnelSubscribers =
      <String, void Function(Uint8List data)>{};

  Socket? _mqttSocket;
  final BytesBuilder _rxBuffer = BytesBuilder(copy: false);
  Timer? _presenceTimer;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _running = false;
  bool _isConnected = false;
  int _brokerIndex = 0;
  int _packetIdCounter = 1;
  String _activeBrokerHost = ProtocolConstants.signalingBrokers.first;

  DeskIdentity? _identity;
  String Function()? _wanIpProvider;
  String Function()? _localIpProvider;
  int Function()? _monitorCountProvider;

  void Function(IncomingConnectionRequest request)? onIncomingConnectionRequested;
  void Function({
    required String targetDeskId,
    required String targetHostName,
    required String targetPublicEndpoint,
    required String targetLocalEndpoint,
    String? relaySessionId,
  })? onConnectionAccepted;
  void Function({
    required String targetDeskId,
    required String targetHostName,
    required String reason,
  })? onConnectionRejected;
  void Function(PeerDevice peer)? onPeerDiscovered;
  void Function(String statusMessage, bool connected)? onStatusChanged;

  bool get isConnected => _isConnected;
  String get activeBrokerHost => _activeBrokerHost;
  List<PeerDevice> get globalPeers => List<PeerDevice>.unmodifiable(_globalPeers.values);

  Future<void> start({
    required DeskIdentity identity,
    required String Function() wanIpProvider,
    required String Function() localIpProvider,
    required int Function() monitorCountProvider,
  }) async {
    _identity = identity;
    _wanIpProvider = wanIpProvider;
    _localIpProvider = localIpProvider;
    _monitorCountProvider = monitorCountProvider;

    if (_running) return;
    _running = true;

    await _connectToBroker();

    _presenceTimer = Timer.periodic(ProtocolConstants.globalPresenceInterval, (_) {
      publishPresence();
    });
    _pingTimer = Timer.periodic(ProtocolConstants.mqttKeepAliveInterval, (_) {
      _sendMqttPing();
    });
  }

  Future<void> _connectToBroker() async {
    if (!_running || _identity == null) return;

    _activeBrokerHost =
        ProtocolConstants.signalingBrokers[_brokerIndex % ProtocolConstants.signalingBrokers.length];
    onStatusChanged?.call('Conectando à rede global ($_activeBrokerHost)...', false);

    try {
      _mqttSocket?.destroy();
      _rxBuffer.clear();

      _mqttSocket = await Socket.connect(
        _activeBrokerHost,
        ProtocolConstants.mqttTcpPort,
        timeout: const Duration(seconds: 5),
      );
      _mqttSocket!.setOption(SocketOption.tcpNoDelay, true);

      _mqttSocket!.listen(
        _onSocketData,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );

      final String clientId =
          'DeskView_${_identity!.deskId}_${SessionCipher.generateNonceHex(3)}';
      _sendMqttConnectPacket(clientId);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _isConnected = false;
    onStatusChanged?.call('Reconectando ao servidor de sinalização...', false);
    if (!_running) return;
    _brokerIndex++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), _connectToBroker);
  }

  void _onSocketData(Uint8List chunk) {
    _rxBuffer.add(chunk);
    final Uint8List all = _rxBuffer.takeBytes();
    int offset = 0;

    while (offset + 2 <= all.length) {
      final int headerByte = all[offset];
      final int packetType = (headerByte >> 4) & 0x0f;

      // Decodifica Variable Byte Integer do MQTT
      int multiplier = 1;
      int remLength = 0;
      int lenBytesCount = 0;
      bool lengthComplete = false;

      for (int i = 1; i <= 4 && (offset + i) < all.length; i++) {
        final int digit = all[offset + i];
        remLength += (digit & 0x7f) * multiplier;
        multiplier *= 128;
        lenBytesCount = i;
        if ((digit & 0x80) == 0) {
          lengthComplete = true;
          break;
        }
      }

      if (!lengthComplete) {
        break;
      }

      final int totalPacketLen = 1 + lenBytesCount + remLength;
      if (offset + totalPacketLen > all.length) {
        break;
      }

      final Uint8List body = all.sublist(
        offset + 1 + lenBytesCount,
        offset + totalPacketLen,
      );
      offset += totalPacketLen;

      if (packetType == 2) {
        // CONNACK
        if (body.length >= 2 && body[1] == 0) {
          _isConnected = true;
          onStatusChanged?.call('Rede Global Conectada ($_activeBrokerHost)', true);
          _subscribeTopic('${ProtocolConstants.signalTopicPrefix}${_identity!.deskId}');
          _subscribeTopic('${ProtocolConstants.peersTopicPrefix}#');
          for (final String tunnelTopic in _tunnelSubscribers.keys) {
            _subscribeTopic(tunnelTopic);
          }
          publishPresence();
        }
      } else if (packetType == 3) {
        // PUBLISH
        _handleIncomingPublish(headerByte, body);
      }
    }

    if (offset < all.length) {
      _rxBuffer.add(all.sublist(offset));
    }
  }

  void _handleIncomingPublish(int headerByte, Uint8List body) {
    if (body.length < 2) return;
    final int topicLen = (body[0] << 8) | body[1];
    if (body.length < 2 + topicLen) return;

    final String topic = utf8.decode(body.sublist(2, 2 + topicLen), allowMalformed: true);
    int payloadOffset = 2 + topicLen;
    final int qos = (headerByte >> 1) & 0x03;
    if (qos > 0) {
      if (body.length < payloadOffset + 2) return;
      payloadOffset += 2;
    }

    final Uint8List payloadBytes = body.sublist(payloadOffset);

    // 1. Verifica se é tráfego de túnel Relay criptografado
    final void Function(Uint8List data)? tunnelHandler = _tunnelSubscribers[topic];
    if (tunnelHandler != null) {
      tunnelHandler(payloadBytes);
      return;
    }

    final String payloadStr = utf8.decode(payloadBytes, allowMalformed: true);

    // 2. Verifica se é mensagem de sinalização para o nosso DeskID
    if (_identity != null &&
        topic == '${ProtocolConstants.signalTopicPrefix}${_identity!.deskId}') {
      _processSignalPayload(payloadStr);
      return;
    }

    // 3. Verifica se é anúncio de presença global de outro Peer
    if (topic.startsWith(ProtocolConstants.peersTopicPrefix)) {
      _processPeerPresencePayload(payloadStr);
    }
  }

  /// Processa mensagens assinadas `REQ`, `ACK` e `REJ`.
  void _processSignalPayload(String payload) {
    final List<String> parts = payload.split('|');
    if (parts.length < 3) return;

    final String signature = parts[0].trim();
    final String signedBody = payload.substring(signature.length + 1);

    if (!SessionCipher.verifySignalSignature(signature, signedBody)) {
      return; // Assinatura HMAC inválida: descarta tentativa de spoofing
    }

    final String action = parts[1].trim();

    if (action == 'REQ' && parts.length >= 7) {
      final int? ticks = int.tryParse(parts[6]);
      if (!_isWithinReplayWindow(ticks)) return;

      final String callerId = DeskIdFormatter.extractDigits(parts[2]);
      final String callerHost = parts[3];
      final String callerPublicEp = parts[4];
      final String callerLocalEp = parts[5];
      final String? relaySessionId = parts.length >= 8 ? parts[7] : null;

      onIncomingConnectionRequested?.call(
        IncomingConnectionRequest(
          requestId: SessionCipher.generateNonceHex(6),
          callerDeskId: callerId,
          callerHostName: callerHost,
          callerPublicEndpoint: callerPublicEp,
          callerLocalEndpoint: callerLocalEp,
          relaySessionId: relaySessionId,
          requestedAt: DateTime.now(),
        ),
      );
    } else if (action == 'ACK' && parts.length >= 7) {
      final int? ticks = int.tryParse(parts[6]);
      if (!_isWithinReplayWindow(ticks)) return;

      final String targetId = DeskIdFormatter.extractDigits(parts[2]);
      final String targetHost = parts[3];
      final String targetPublicEp = parts[4];
      final String targetLocalEp = parts[5];
      final String? relaySessionId = parts.length >= 8 ? parts[7] : null;

      onConnectionAccepted?.call(
        targetDeskId: targetId,
        targetHostName: targetHost,
        targetPublicEndpoint: targetPublicEp,
        targetLocalEndpoint: targetLocalEp,
        relaySessionId: relaySessionId,
      );
    } else if (action == 'REJ' && parts.length >= 5) {
      final String targetId = DeskIdFormatter.extractDigits(parts[2]);
      final String targetHost = parts[3];
      final String reason = parts[4];

      onConnectionRejected?.call(
        targetDeskId: targetId,
        targetHostName: targetHost,
        reason: reason,
      );
    }
  }

  static bool _isWithinReplayWindow(int? dotNetTicksUtc) {
    if (dotNetTicksUtc == null || dotNetTicksUtc <= 0) return true;
    final int nowDotNetTicks =
        (DateTime.now().toUtc().millisecondsSinceEpoch * 10000) + 621355968000000000;
    final int diffTicks = (nowDotNetTicks - dotNetTicksUtc).abs();
    const int twoMinutesTicks = 2 * 60 * 1000 * 10000;
    return diffTicks <= twoMinutesTicks;
  }

  static int _currentDotNetUtcTicks() {
    return (DateTime.now().toUtc().millisecondsSinceEpoch * 10000) + 621355968000000000;
  }

  void _processPeerPresencePayload(String payload) {
    final List<String> parts = payload.split('|');
    if (parts.length < 6) return;

    final String deskId = DeskIdFormatter.extractDigits(parts[0]);
    if (deskId.length != 9 || (_identity != null && deskId == _identity!.deskId)) {
      return;
    }

    final String host = parts[1].trim();
    final String user = parts[2].trim();
    final String wanIp = parts[3].trim();
    final String lanIp = parts[4].trim();
    final int port = int.tryParse(parts[5].trim()) ?? ProtocolConstants.defaultListenPort;
    final int monitors = parts.length > 6 ? (int.tryParse(parts[6].trim()) ?? 1) : 1;

    final PeerDevice peer = PeerDevice(
      key: deskId,
      deskId: deskId,
      hostName: host.isNotEmpty ? host : 'Dispositivo Remoto',
      userName: user,
      ipAddress: wanIp.isNotEmpty ? wanIp : lanIp,
      localIpAddress: lanIp,
      port: port,
      monitorCount: monitors.clamp(1, 16),
      lastSeen: DateTime.now(),
      isOnline: true,
      source: PeerDiscoverySource.globalSignaling,
    );

    _globalPeers[deskId] = peer;
    onPeerDiscovered?.call(peer);
  }

  /// Envia solicitação de conexão (`REQ`) assinada com HMAC-SHA256 e ID de sessão Relay.
  void sendConnectRequest({
    required String targetDeskId,
    required String callerDeskId,
    required String callerHostName,
    required String callerPublicEndpoint,
    required String callerLocalEndpoint,
    required String relaySessionId,
  }) {
    final int ticks = _currentDotNetUtcTicks();
    final String body =
        'REQ|$callerDeskId|$callerHostName|$callerPublicEndpoint|$callerLocalEndpoint|$ticks|$relaySessionId';
    final String signed = '${SessionCipher.signSignalPayload(body)}|$body';
    publishString('${ProtocolConstants.signalTopicPrefix}$targetDeskId', signed);
  }

  /// Envia aprovação de conexão (`ACK`) assinada com HMAC-SHA256 e confirmação de canal Relay.
  void sendConnectAccept({
    required String callerDeskId,
    required String targetDeskId,
    required String targetHostName,
    required String targetPublicEndpoint,
    required String targetLocalEndpoint,
    required String relaySessionId,
  }) {
    final int ticks = _currentDotNetUtcTicks();
    final String body =
        'ACK|$targetDeskId|$targetHostName|$targetPublicEndpoint|$targetLocalEndpoint|$ticks|$relaySessionId';
    final String signed = '${SessionCipher.signSignalPayload(body)}|$body';
    publishString('${ProtocolConstants.signalTopicPrefix}$callerDeskId', signed);
  }

  /// Envia recusa de conexão (`REJ`) assinada com HMAC-SHA256.
  void sendConnectReject({
    required String callerDeskId,
    required String targetDeskId,
    required String targetHostName,
    required String reason,
  }) {
    final int ticks = _currentDotNetUtcTicks();
    final String body = 'REJ|$targetDeskId|$targetHostName|$reason|$ticks';
    final String signed = '${SessionCipher.signSignalPayload(body)}|$body';
    publishString('${ProtocolConstants.signalTopicPrefix}$callerDeskId', signed);
  }

  /// Publica presença online no diretório global (`deskview/v2/peers/<DeskId>`).
  void publishPresence() {
    if (!_running || !_isConnected || _identity == null) return;
    final String wan = _wanIpProvider?.call() ?? '127.0.0.1';
    final String lan = _localIpProvider?.call() ?? '127.0.0.1';
    final int monitors = _monitorCountProvider?.call() ?? 1;

    final String payload =
        '${_identity!.deskId}|${_identity!.machineName}|${_identity!.userName}|$wan|$lan|${_identity!.listenPort}|$monitors';
    publishString(
      '${ProtocolConstants.peersTopicPrefix}${_identity!.deskId}',
      payload,
      retain: true,
    );
  }

  /// Registra um listener binário para um tópico de túnel Relay (`deskview/v3/tunnel/<sessionId>/<dir>`).
  void subscribeRelayTunnel(String topic, void Function(Uint8List data) onData) {
    _tunnelSubscribers[topic] = onData;
    if (_isConnected) {
      _subscribeTopic(topic);
    }
  }

  void unsubscribeRelayTunnel(String topic) {
    _tunnelSubscribers.remove(topic);
  }

  /// Publica bytes brutos no tópico do túnel Relay.
  void publishBinary(String topic, Uint8List payloadBytes, {bool retain = false}) {
    if (_mqttSocket == null || !_isConnected) return;
    try {
      final List<int> topicBytes = utf8.encode(topic);
      final int remLen = 2 + topicBytes.length + payloadBytes.length;

      final BytesBuilder packet = BytesBuilder(copy: false);
      packet.addByte(retain ? 0x31 : 0x30);
      _writeVariableLength(packet, remLen);
      packet.addByte((topicBytes.length >> 8) & 0xff);
      packet.addByte(topicBytes.length & 0xff);
      packet.add(topicBytes);
      if (payloadBytes.isNotEmpty) {
        packet.add(payloadBytes);
      }
      _mqttSocket!.add(packet.toBytes());
    } catch (_) {}
  }

  void publishString(String topic, String payload, {bool retain = false}) {
    publishBinary(topic, Uint8List.fromList(utf8.encode(payload)), retain: retain);
  }

  PeerDevice? resolveDeskId(String rawCode) {
    final String clean = DeskIdFormatter.extractDigits(rawCode);
    if (clean.length != 9) return null;
    return _globalPeers[clean];
  }

  void _sendMqttConnectPacket(String clientId) {
    if (_mqttSocket == null) return;
    final List<int> protoName = ascii.encode('MQTT');
    final List<int> cidBytes = utf8.encode(clientId);

    final BytesBuilder vh = BytesBuilder(copy: false)
      ..addByte(0x00)
      ..addByte(0x04)
      ..add(protoName)
      ..addByte(0x04) // MQTT 3.1.1
      ..addByte(0x02) // Clean Session
      ..addByte(0x00)
      ..addByte(0x3C); // KeepAlive 60s

    final BytesBuilder pl = BytesBuilder(copy: false)
      ..addByte((cidBytes.length >> 8) & 0xff)
      ..addByte(cidBytes.length & 0xff)
      ..add(cidBytes);

    final Uint8List vhBytes = vh.toBytes();
    final Uint8List plBytes = pl.toBytes();

    final BytesBuilder out = BytesBuilder(copy: false)..addByte(0x10);
    _writeVariableLength(out, vhBytes.length + plBytes.length);
    out.add(vhBytes);
    out.add(plBytes);

    try {
      _mqttSocket!.add(out.toBytes());
    } catch (_) {}
  }

  void _subscribeTopic(String topic) {
    if (_mqttSocket == null || !_isConnected) return;
    final List<int> topicBytes = utf8.encode(topic);
    final int remLen = 2 + 2 + topicBytes.length + 1;
    final int pid = (_packetIdCounter++) & 0xffff;

    final BytesBuilder out = BytesBuilder(copy: false)..addByte(0x82);
    _writeVariableLength(out, remLen);
    out.addByte((pid >> 8) & 0xff);
    out.addByte(pid & 0xff);
    out.addByte((topicBytes.length >> 8) & 0xff);
    out.addByte(topicBytes.length & 0xff);
    out.add(topicBytes);
    out.addByte(0x00); // QoS 0

    try {
      _mqttSocket!.add(out.toBytes());
    } catch (_) {}
  }

  void _sendMqttPing() {
    if (_mqttSocket == null || !_isConnected) return;
    try {
      _mqttSocket!.add(const <int>[0xC0, 0x00]);
    } catch (_) {}
  }

  static void _writeVariableLength(BytesBuilder builder, int length) {
    int rem = length;
    do {
      int digit = rem % 128;
      rem ~/= 128;
      if (rem > 0) {
        digit |= 0x80;
      }
      builder.addByte(digit);
    } while (rem > 0);
  }

  void dispose() {
    _running = false;
    _isConnected = false;
    _presenceTimer?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _tunnelSubscribers.clear();
    try {
      _mqttSocket?.destroy();
    } catch (_) {}
    _mqttSocket = null;
  }
}
