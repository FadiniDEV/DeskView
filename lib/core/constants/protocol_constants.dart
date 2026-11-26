/// Constantes globais de protocolo, rede, portas, limites e timeouts do DeskView.
class ProtocolConstants {
  ProtocolConstants._();

  /// Porta TCP padrão do servidor Host DeskView (com fallback incremental até +15 portas).
  static const int defaultListenPort = 7070;
  static const int maxPortRetryAttempts = 15;

  /// Porta UDP de descoberta automática na rede local (compatível com DESKVIEW_V1).
  static const int lanDiscoveryUdpPort = 50001;
  static const String lanDiscoveryMagicPrefix = 'DESKVIEW_V1';

  /// Limites operacionais e de segurança.
  static const int maxConcurrentHostSessions = 16;
  static const int maxPacketPayloadBytes = 64 * 1024 * 1024; // 64 MB
  static const int maxFileTransferBytes = 500 * 1024 * 1024; // 500 MB
  static const int fileTransferChunkBytes = 32768; // 32 KB
  static const int relayMaxFragmentBytes = 24576; // 24 KB por fragmento de túnel

  /// Grade do Codec DeskRT-Lite (8x6 = 48 blocos/tiles).
  static const int tileGridCols = 8;
  static const int tileGridRows = 6;
  static const int keyFrameIntervalFrames = 90;

  /// Perfis de qualidade JPEG do Codec DeskRT.
  static const int qualityUltra = 90;
  static const int qualityBalanced = 70;
  static const int qualityHighSpeed = 45;

  /// Brokers MQTT públicos em cluster de alta disponibilidade para sinalização global e Relay fallback.
  static const List<String> signalingBrokers = <String>[
    'broker.hivemq.com',
    'broker.emqx.io',
    'test.mosquitto.org',
  ];
  static const int mqttTcpPort = 1883;

  /// Prefixos de tópicos MQTT (compatibilidade v2 + extensão de túnel criptografado v3).
  static const String signalTopicPrefix = 'deskview/v2/signal/';
  static const String peersTopicPrefix = 'deskview/v2/peers/';
  static const String relayTunnelTopicPrefix = 'deskview/v3/tunnel/';

  /// Servidores STUN RFC 5389 públicos para descoberta real de IP e Porta mapeados pelo NAT.
  static const List<StunServerEndpoint> stunServers = <StunServerEndpoint>[
    StunServerEndpoint('stun.l.google.com', 19302),
    StunServerEndpoint('stun1.l.google.com', 19302),
    StunServerEndpoint('stun.cloudflare.com', 3478),
  ];

  /// Endpoints HTTPS de fallback para consulta de IP público caso UDP/STUN esteja bloqueado.
  static const List<String> publicIpHttpFallbacks = <String>[
    'https://api.ipify.org',
    'https://icanhazip.com',
    'https://ifconfig.me/ip',
  ];

  /// Timeouts de rede e corrida de candidatos.
  static const Duration lanBroadcastInterval = Duration(seconds: 3);
  static const Duration globalPresenceInterval = Duration(seconds: 20);
  static const Duration mqttKeepAliveInterval = Duration(seconds: 25);
  static const Duration directConnectionRaceTimeout = Duration(milliseconds: 2600);
  static const Duration sessionApprovalTimeout = Duration(seconds: 20);
  static const Duration signalReplayWindow = Duration(minutes: 2);
}

class StunServerEndpoint {
  final String host;
  final int port;
  const StunServerEndpoint(this.host, this.port);
}
