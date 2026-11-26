import '../../core/utils/desk_id_formatter.dart';

enum PeerDiscoverySource {
  localLan,
  globalSignaling,
  savedHistory,
  loopback,
}

/// Representa um computador/dispositivo remoto descoberto na rede ou salvo no histórico (1-Clique).
class PeerDevice {
  final String key;
  final String deskId;
  final String hostName;
  final String userName;
  final String ipAddress;
  final String localIpAddress;
  final int port;
  final int monitorCount;
  final String savedPassword;
  final DateTime lastSeen;
  final bool isFavorite;
  final bool isOnline;
  final PeerDiscoverySource source;
  final String platformName;

  const PeerDevice({
    required this.key,
    required this.deskId,
    required this.hostName,
    this.userName = '',
    required this.ipAddress,
    this.localIpAddress = '',
    required this.port,
    this.monitorCount = 1,
    this.savedPassword = '',
    required this.lastSeen,
    this.isFavorite = false,
    this.isOnline = false,
    this.source = PeerDiscoverySource.savedHistory,
    this.platformName = 'Windows',
  });

  String get formattedId =>
      deskId.isNotEmpty ? DeskIdFormatter.format(deskId) : endpoint;

  String get endpoint => '$ipAddress:$port';

  String get localEndpoint =>
      localIpAddress.isNotEmpty ? '$localIpAddress:$port' : endpoint;

  PeerDevice copyWith({
    String? key,
    String? deskId,
    String? hostName,
    String? userName,
    String? ipAddress,
    String? localIpAddress,
    int? port,
    int? monitorCount,
    String? savedPassword,
    DateTime? lastSeen,
    bool? isFavorite,
    bool? isOnline,
    PeerDiscoverySource? source,
    String? platformName,
  }) {
    return PeerDevice(
      key: key ?? this.key,
      deskId: deskId ?? this.deskId,
      hostName: hostName ?? this.hostName,
      userName: userName ?? this.userName,
      ipAddress: ipAddress ?? this.ipAddress,
      localIpAddress: localIpAddress ?? this.localIpAddress,
      port: port ?? this.port,
      monitorCount: monitorCount ?? this.monitorCount,
      savedPassword: savedPassword ?? this.savedPassword,
      lastSeen: lastSeen ?? this.lastSeen,
      isFavorite: isFavorite ?? this.isFavorite,
      isOnline: isOnline ?? this.isOnline,
      source: source ?? this.source,
      platformName: platformName ?? this.platformName,
    );
  }
}
