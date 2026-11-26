enum TransportRouteType {
  loopback('Loopback Local', 100),
  lanDirect('LAN Direta (Sub-ms)', 90),
  stunReflexiveP2P('WAN P2P (STUN/ICE)', 75),
  wanDirect('WAN TCP Direta', 60),
  encryptedRelay('Relay Criptografado (Travessia CGNAT)', 40);

  final String label;
  final int priority;
  const TransportRouteType(this.label, this.priority);
}

enum NatTopologyType {
  unknown('Detectando...'),
  openInternet('Internet Direta (Sem NAT)'),
  fullConeNat('NAT Cone Completo (P2P Favorável)'),
  restrictedConeNat('NAT Restrito por Porta'),
  symmetricOrCgNat('NAT Simétrico / CGNAT (Requer STUN ou Relay)');

  final String description;
  const NatTopologyType(this.description);
}

/// Representa um candidato de rota (inspirado em ICE Candidate RFC 8445) para estabelecimento de sessão.
class ConnectionCandidate {
  final TransportRouteType routeType;
  final String address;
  final int port;
  final String? relaySessionId;
  final String? relayBrokerHost;

  const ConnectionCandidate({
    required this.routeType,
    required this.address,
    required this.port,
    this.relaySessionId,
    this.relayBrokerHost,
  });

  String get endpoint => '$address:$port';

  Map<String, dynamic> toMap() => <String, dynamic>{
        'routeType': routeType.name,
        'address': address,
        'port': port,
        if (relaySessionId != null) 'relaySessionId': relaySessionId,
        if (relayBrokerHost != null) 'relayBrokerHost': relayBrokerHost,
      };

  factory ConnectionCandidate.fromMap(Map<String, dynamic> map) {
    final String typeName = (map['routeType'] as String?) ?? 'wanDirect';
    final TransportRouteType type = TransportRouteType.values.firstWhere(
      (TransportRouteType e) => e.name == typeName,
      orElse: () => TransportRouteType.wanDirect,
    );
    return ConnectionCandidate(
      routeType: type,
      address: (map['address'] as String?) ?? '127.0.0.1',
      port: (map['port'] as int?) ?? 7070,
      relaySessionId: map['relaySessionId'] as String?,
      relayBrokerHost: map['relayBrokerHost'] as String?,
    );
  }
}
