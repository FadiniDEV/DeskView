import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/protocol_constants.dart';
import '../../core/utils/desk_id_formatter.dart';
import '../../domain/entities/desk_identity.dart';
import '../../domain/entities/peer_device.dart';

/// Serviço de descoberta automática de computadores na Rede Local (LAN) via UDP Broadcast (Porta 50001).
/// Mantém 100% de compatibilidade com o formato `DESKVIEW_V1|<DeskId>|<Host>|<User>|<Ip>|<Port>|<Monitors>`.
class LanDiscoveryService {
  final Map<String, PeerDevice> _discoveredPeers = <String, PeerDevice>{};
  RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;
  bool _running = false;

  void Function(List<PeerDevice> peers)? onPeersUpdated;

  List<PeerDevice> get discoveredPeers =>
      List<PeerDevice>.unmodifiable(_discoveredPeers.values);

  Future<void> start({
    required DeskIdentity identity,
    required String Function() localIpProvider,
    required int Function() monitorCountProvider,
  }) async {
    if (_running) return;
    _running = true;

    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        ProtocolConstants.lanDiscoveryUdpPort,
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final Datagram? dg = _udpSocket?.receive();
          if (dg != null) {
            _handleIncomingDatagram(dg, identity.deskId);
          }
        }
      });
    } catch (_) {}

    _broadcastTimer = Timer.periodic(ProtocolConstants.lanBroadcastInterval, (_) {
      broadcastPresence(
        identity: identity,
        localIp: localIpProvider(),
        monitorCount: monitorCountProvider(),
      );
    });

    // Primeiro broadcast imediato
    broadcastPresence(
      identity: identity,
      localIp: localIpProvider(),
      monitorCount: monitorCountProvider(),
    );
  }

  void broadcastPresence({
    required DeskIdentity identity,
    required String localIp,
    required int monitorCount,
  }) {
    if (!_running) return;
    final String payload = buildDiscoveryPacket(
      deskId: identity.deskId,
      machineName: identity.machineName,
      userName: identity.userName,
      localIp: localIp,
      listenPort: identity.listenPort,
      monitorCount: monitorCount,
    );
    final List<int> bytes = utf8.encode(payload);
    try {
      _udpSocket?.send(
        bytes,
        InternetAddress('255.255.255.255'),
        ProtocolConstants.lanDiscoveryUdpPort,
      );
      _udpSocket?.send(
        bytes,
        InternetAddress.loopbackIPv4,
        ProtocolConstants.lanDiscoveryUdpPort,
      );
    } catch (_) {}
  }

  static String buildDiscoveryPacket({
    required String deskId,
    required String machineName,
    required String userName,
    required String localIp,
    required int listenPort,
    required int monitorCount,
  }) {
    return '${ProtocolConstants.lanDiscoveryMagicPrefix}|$deskId|$machineName|$userName|$localIp|$listenPort|$monitorCount';
  }

  static PeerDevice? parseDiscoveryPacket(
    String rawMessage, {
    String? senderDatagramIp,
  }) {
    if (!rawMessage.startsWith('${ProtocolConstants.lanDiscoveryMagicPrefix}|')) {
      return null;
    }
    final List<String> parts = rawMessage.split('|');
    if (parts.length < 7) return null;

    final String deskId = DeskIdFormatter.extractDigits(parts[1]);
    if (deskId.length != 9) return null;

    final String host = parts[2].trim();
    final String user = parts[3].trim();
    String ip = parts[4].trim();
    final int port = int.tryParse(parts[5].trim()) ?? ProtocolConstants.defaultListenPort;
    final int monitors = (int.tryParse(parts[6].trim()) ?? 1).clamp(1, 16);

    if (senderDatagramIp != null &&
        senderDatagramIp.isNotEmpty &&
        senderDatagramIp != '127.0.0.1' &&
        senderDatagramIp != '0.0.0.0') {
      ip = senderDatagramIp;
    }

    return PeerDevice(
      key: '$deskId@$ip:$port',
      deskId: deskId,
      hostName: host.isNotEmpty ? host : 'Dispositivo LAN',
      userName: user,
      ipAddress: ip,
      localIpAddress: ip,
      port: port,
      monitorCount: monitors,
      lastSeen: DateTime.now(),
      isOnline: true,
      source: PeerDiscoverySource.localLan,
    );
  }

  void _handleIncomingDatagram(Datagram dg, String myDeskId) {
    try {
      final String msg = utf8.decode(dg.data, allowMalformed: true);
      final PeerDevice? peer = parseDiscoveryPacket(
        msg,
        senderDatagramIp: dg.address.address,
      );
      if (peer == null || peer.deskId == myDeskId) return;

      final bool isNew = !_discoveredPeers.containsKey(peer.deskId);
      _discoveredPeers[peer.deskId] = peer;
      if (isNew) {
        onPeersUpdated?.call(discoveredPeers);
      }
    } catch (_) {}
  }

  PeerDevice? resolveByDeskId(String rawCode) {
    final String clean = DeskIdFormatter.extractDigits(rawCode);
    if (clean.length != 9) return null;
    return _discoveredPeers[clean];
  }

  void dispose() {
    _running = false;
    _broadcastTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
  }
}
