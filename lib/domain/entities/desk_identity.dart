import '../../core/utils/desk_id_formatter.dart';

/// Representa a identidade local do dispositivo, configurações de porta e credenciais de acesso desassistido.
class DeskIdentity {
  final String deskId;
  final String fingerprint;
  final String machineName;
  final String userName;
  final int listenPort;
  final String unattendedPasswordHash;
  final String unattendedSalt;
  final String localLoopbackNonce;
  final List<String> favorites;
  final List<String> recentSessions;

  const DeskIdentity({
    required this.deskId,
    required this.fingerprint,
    required this.machineName,
    required this.userName,
    required this.listenPort,
    required this.unattendedPasswordHash,
    required this.unattendedSalt,
    required this.localLoopbackNonce,
    this.favorites = const <String>[],
    this.recentSessions = const <String>[],
  });

  String get formattedDeskId => DeskIdFormatter.format(deskId);

  String get shortFingerprint =>
      fingerprint.length >= 16 ? fingerprint.substring(0, 16) : fingerprint;

  bool get hasUnattendedPassword =>
      unattendedPasswordHash.isNotEmpty && unattendedSalt.isNotEmpty;

  DeskIdentity copyWith({
    String? deskId,
    String? fingerprint,
    String? machineName,
    String? userName,
    int? listenPort,
    String? unattendedPasswordHash,
    String? unattendedSalt,
    String? localLoopbackNonce,
    List<String>? favorites,
    List<String>? recentSessions,
  }) {
    return DeskIdentity(
      deskId: deskId ?? this.deskId,
      fingerprint: fingerprint ?? this.fingerprint,
      machineName: machineName ?? this.machineName,
      userName: userName ?? this.userName,
      listenPort: listenPort ?? this.listenPort,
      unattendedPasswordHash: unattendedPasswordHash ?? this.unattendedPasswordHash,
      unattendedSalt: unattendedSalt ?? this.unattendedSalt,
      localLoopbackNonce: localLoopbackNonce ?? this.localLoopbackNonce,
      favorites: favorites ?? this.favorites,
      recentSessions: recentSessions ?? this.recentSessions,
    );
  }
}
