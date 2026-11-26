import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../core/constants/protocol_constants.dart';
import '../../domain/entities/connection_candidate.dart';

/// Resultado da resolução de topologia de rede local e externa (STUN RFC 5389 + Interfaces Locais).
class NetworkEndpointsSnapshot {
  final String primaryLocalIp;
  final List<String> allLocalIps;
  final String publicWanIp;
  final int mappedExternalPort;
  final NatTopologyType natTopology;
  final DateTime resolvedAt;

  const NetworkEndpointsSnapshot({
    required this.primaryLocalIp,
    required this.allLocalIps,
    required this.publicWanIp,
    required this.mappedExternalPort,
    required this.natTopology,
    required this.resolvedAt,
  });

  String get formattedPublicEndpoint => '$publicWanIp:$mappedExternalPort';
}

/// Cliente STUN RFC 5389 nativo em Dart para descoberta real de IP e Porta mapeados pelo NAT,
/// complementado por enumeração de interfaces locais e fallback HTTPS.
class StunClientService {
  static const int _stunBindingRequest = 0x0001;
  static const int _stunBindingResponse = 0x0101;
  static const int _stunMagicCookie = 0x2112A442;
  static const int _attrMappedAddress = 0x0001;
  static const int _attrXorMappedAddress = 0x0020;

  NetworkEndpointsSnapshot? _cachedSnapshot;

  NetworkEndpointsSnapshot? get cachedSnapshot => _cachedSnapshot;

  /// Descobre todos os IPs locais, consulta servidores STUN RFC 5389 para identificar
  /// o par `IP Público : Porta Externa NAT` e classifica o tipo de NAT/CGNAT.
  Future<NetworkEndpointsSnapshot> discoverNetworkTopology({required int localListenPort}) async {
    final List<String> localIps = await listActiveLocalIpv4Addresses();
    final String primaryLocal = localIps.isNotEmpty ? localIps.first : '127.0.0.1';

    final List<({String ip, int port})> stunResults = <({String ip, int port})>[];

    for (final StunServerEndpoint server in ProtocolConstants.stunServers) {
      final ({String ip, int port})? mapped = await _performStunBindingQuery(
        server.host,
        server.port,
      );
      if (mapped != null) {
        stunResults.add(mapped);
        if (stunResults.length >= 2) break;
      }
    }

    String publicIp = '';
    int mappedPort = localListenPort;
    NatTopologyType topology = NatTopologyType.unknown;

    if (stunResults.isNotEmpty) {
      publicIp = stunResults.first.ip;
      mappedPort = stunResults.first.port;

      if (localIps.contains(publicIp)) {
        topology = NatTopologyType.openInternet;
      } else if (stunResults.length >= 2 && stunResults[0].port != stunResults[1].port) {
        // Porta externa mudou conforme o destino STUN -> NAT Simétrico ou CGNAT
        topology = NatTopologyType.symmetricOrCgNat;
      } else if (_isCarrierGradeNatIp(primaryLocal)) {
        topology = NatTopologyType.symmetricOrCgNat;
      } else {
        topology = NatTopologyType.fullConeNat;
      }
    } else {
      // Fallback HTTP caso UDP 19302/3478 esteja bloqueado por firewall corporativo
      publicIp = await _fetchPublicIpOverHttp() ?? primaryLocal;
      mappedPort = localListenPort;
      topology = _isCarrierGradeNatIp(primaryLocal)
          ? NatTopologyType.symmetricOrCgNat
          : NatTopologyType.restrictedConeNat;
    }

    _cachedSnapshot = NetworkEndpointsSnapshot(
      primaryLocalIp: primaryLocal,
      allLocalIps: localIps,
      publicWanIp: publicIp,
      mappedExternalPort: mappedPort,
      natTopology: topology,
      resolvedAt: DateTime.now(),
    );
    return _cachedSnapshot!;
  }

  /// Constrói um pacote STUN Binding Request (20 bytes) RFC 5389.
  static Uint8List buildStunBindingRequest(List<int> transactionId12Bytes) {
    final Uint8List packet = Uint8List(20);
    final ByteData bd = ByteData.sublistView(packet);
    bd.setUint16(0, _stunBindingRequest, Endian.big);
    bd.setUint16(2, 0, Endian.big); // Message Length = 0
    bd.setUint32(4, _stunMagicCookie, Endian.big);
    for (int i = 0; i < 12 && i < transactionId12Bytes.length; i++) {
      packet[8 + i] = transactionId12Bytes[i] & 0xff;
    }
    return packet;
  }

  /// Faz o parse de um pacote STUN Binding Response RFC 5389 extraindo `XOR-MAPPED-ADDRESS` ou `MAPPED-ADDRESS`.
  static ({String ip, int port})? parseStunBindingResponse(Uint8List packet) {
    if (packet.length < 20) return null;
    final ByteData bd = ByteData.sublistView(packet);
    final int msgType = bd.getUint16(0, Endian.big);
    final int msgLen = bd.getUint16(2, Endian.big);
    final int cookie = bd.getUint32(4, Endian.big);

    if (msgType != _stunBindingResponse || cookie != _stunMagicCookie) {
      return null;
    }

    int offset = 20;
    final int endOffset = (20 + msgLen).clamp(20, packet.length);

    while (offset + 4 <= endOffset) {
      final int attrType = bd.getUint16(offset, Endian.big);
      final int attrLen = bd.getUint16(offset + 2, Endian.big);
      offset += 4;
      if (offset + attrLen > endOffset) break;

      if ((attrType == _attrXorMappedAddress || attrType == _attrMappedAddress) && attrLen >= 8) {
        final int family = packet[offset + 1];
        if (family == 0x01) {
          // IPv4
          int port = bd.getUint16(offset + 2, Endian.big);
          int ipUint32 = bd.getUint32(offset + 4, Endian.big);
          if (attrType == _attrXorMappedAddress) {
            port ^= (_stunMagicCookie >>> 16) & 0xffff;
            ipUint32 ^= _stunMagicCookie;
          }
          final int b1 = (ipUint32 >>> 24) & 0xff;
          final int b2 = (ipUint32 >>> 16) & 0xff;
          final int b3 = (ipUint32 >>> 8) & 0xff;
          final int b4 = ipUint32 & 0xff;
          return (ip: '$b1.$b2.$b3.$b4', port: port);
        }
      }

      // Atributos STUN são alinhados em múltiplos de 4 bytes
      final int paddedLen = (attrLen + 3) & ~3;
      offset += paddedLen;
    }

    return null;
  }

  Future<({String ip, int port})?> _performStunBindingQuery(String host, int port) async {
    RawDatagramSocket? socket;
    try {
      final List<InternetAddress> addrs = await InternetAddress.lookup(host)
          .timeout(const Duration(milliseconds: 1200));
      final InternetAddress targetAddr = addrs.firstWhere(
        (InternetAddress a) => a.type == InternetAddressType.IPv4,
        orElse: () => addrs.first,
      );

      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final Completer<({String ip, int port})?> completer =
          Completer<({String ip, int port})?>();

      final Random rng = Random();
      final List<int> txId = List<int>.generate(12, (_) => rng.nextInt(256));
      final Uint8List reqBytes = buildStunBindingRequest(txId);

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final Datagram? dg = socket?.receive();
          if (dg != null && !completer.isCompleted) {
            final ({String ip, int port})? parsed = parseStunBindingResponse(dg.data);
            if (parsed != null) {
              completer.complete(parsed);
            }
          }
        }
      });

      socket.send(reqBytes, targetAddr, port);
      return await completer.future.timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  static Future<List<String>> listActiveLocalIpv4Addresses() async {
    final List<String> ips = <String>[];
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final NetworkInterface ni in interfaces) {
        final String lowerName = ni.name.toLowerCase();
        if (lowerName.contains('loopback') || lowerName.contains('vethernet')) {
          continue;
        }
        for (final InternetAddress addr in ni.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    if (ips.isEmpty) {
      ips.add('127.0.0.1');
    }
    return ips;
  }

  Future<String?> _fetchPublicIpOverHttp() async {
    for (final String url in ProtocolConstants.publicIpHttpFallbacks) {
      final HttpClient client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 2000);
      try {
        final HttpClientRequest req = await client.getUrl(Uri.parse(url));
        req.headers.set(HttpHeaders.userAgentHeader, 'DeskView/3.0');
        final HttpClientResponse resp =
            await req.close().timeout(const Duration(milliseconds: 2000));
        if (resp.statusCode == 200) {
          final String body = await resp.transform(const SystemEncoding().decoder).join();
          final String clean = body.trim();
          if (InternetAddress.tryParse(clean) != null) {
            return clean;
          }
        }
      } catch (_) {
      } finally {
        client.close(force: true);
      }
    }
    return null;
  }

  /// Verifica se um endereço pertence ao bloco RFC 6598 de CGNAT (`100.64.0.0/10`).
  static bool _isCarrierGradeNatIp(String ip) {
    final List<String> parts = ip.split('.');
    if (parts.length != 4) return false;
    final int? first = int.tryParse(parts[0]);
    final int? second = int.tryParse(parts[1]);
    if (first == 100 && second != null && second >= 64 && second <= 127) {
      return true;
    }
    return false;
  }
}
