import 'dart:convert';
import 'dart:io';

import '../../core/constants/protocol_constants.dart';
import '../../core/crypto/session_cipher.dart';
import '../../core/utils/desk_id_formatter.dart';
import '../../domain/entities/desk_identity.dart';
import '../../domain/entities/peer_device.dart';
import '../../domain/repositories/identity_repository.dart';

/// Implementação concreta de [IdentityRepository] compatível com `deskview.conf` e `saved_logins.dat`.
class LocalIdentityRepository implements IdentityRepository {
  final String? customStorageDirectory;
  final bool inMemoryOnly;

  DeskIdentity? _cachedIdentity;
  final List<PeerDevice> _cachedPeers = <PeerDevice>[];

  LocalIdentityRepository({
    this.customStorageDirectory,
    this.inMemoryOnly = false,
  });

  Directory _resolveConfigDirectory() {
    if (customStorageDirectory != null && customStorageDirectory!.isNotEmpty) {
      return Directory(customStorageDirectory!);
    }
    if (Platform.isWindows) {
      final String? appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return Directory('$appData\\DeskView');
      }
    }
    final String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      return Directory('$home/.deskview');
    }
    return Directory('${Directory.systemTemp.path}/DeskView');
  }

  File get _configFile => File('${_resolveConfigDirectory().path}${Platform.pathSeparator}deskview.conf');
  File get _loginsFile => File('${_resolveConfigDirectory().path}${Platform.pathSeparator}saved_logins.dat');

  @override
  Future<DeskIdentity> loadOrCreateIdentity({int? overridePort}) async {
    if (_cachedIdentity != null && overridePort == null) {
      return _cachedIdentity!;
    }

    String deskId = '';
    String fingerprint = '';
    String pwdHash = '';
    String pwdSalt = '';
    int port = overridePort ?? ProtocolConstants.defaultListenPort;
    List<String> favorites = <String>[];
    List<String> recents = <String>[];

    final String machineName = _safeHostname();
    final String userName = _safeUsername();
    final String loopbackNonce = SessionCipher.generateNonceHex(16);

    if (!inMemoryOnly) {
      try {
        final Directory dir = _resolveConfigDirectory();
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }

        if (_configFile.existsSync()) {
          final List<String> lines = _configFile.readAsLinesSync(encoding: utf8);
          for (final String rawLine in lines) {
            final String line = rawLine.trim();
            if (line.isEmpty || line.startsWith('#')) continue;
            final int eqIdx = line.indexOf('=');
            if (eqIdx <= 0) continue;
            final String key = line.substring(0, eqIdx).trim();
            final String val = line.substring(eqIdx + 1).trim();

            switch (key) {
              case 'ad.deskview.id':
                deskId = DeskIdFormatter.extractDigits(val);
                break;
              case 'ad.deskview.fpr':
                fingerprint = val;
                break;
              case 'ad.deskview.pwd_hash':
                pwdHash = val;
                break;
              case 'ad.deskview.pwd_salt':
                pwdSalt = val;
                break;
              case 'ad.deskview.port':
                if (overridePort == null) {
                  final int? parsed = int.tryParse(val);
                  if (parsed != null && parsed > 1024 && parsed < 65535) {
                    port = parsed;
                  }
                }
                break;
              case 'ad.deskview.favorites':
                favorites = val.split(';').where((String s) => s.trim().isNotEmpty).toSet().toList();
                break;
              case 'ad.deskview.recent':
                recents = val.split(';').where((String s) => s.trim().isNotEmpty).toSet().toList();
                break;
            }
          }
        }
      } catch (_) {}
    }

    if (deskId.length != 9) {
      deskId = SessionCipher.generateDeterministicDeskId(
        '$machineName|$userName|${Platform.operatingSystem}',
      );
    }

    if (fingerprint.isEmpty) {
      fingerprint = SessionCipher.bytesToHex(
        SessionCipher.sha256Bytes(
          utf8.encode('$deskId|$machineName|${DateTime.now().toUtc().microsecondsSinceEpoch}'),
        ),
      );
    }

    _cachedIdentity = DeskIdentity(
      deskId: deskId,
      fingerprint: fingerprint,
      machineName: machineName,
      userName: userName,
      listenPort: port,
      unattendedPasswordHash: pwdHash,
      unattendedSalt: pwdSalt,
      localLoopbackNonce: loopbackNonce,
      favorites: favorites,
      recentSessions: recents,
    );

    await saveIdentity(_cachedIdentity!);
    await loadSavedPeers();
    return _cachedIdentity!;
  }

  @override
  Future<void> saveIdentity(DeskIdentity identity) async {
    _cachedIdentity = identity;
    if (inMemoryOnly) return;
    try {
      final Directory dir = _resolveConfigDirectory();
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final StringBuffer sb = StringBuffer()
        ..writeln('# DeskView Configuration File')
        ..writeln('ad.deskview.id=${identity.deskId}')
        ..writeln('ad.deskview.fpr=${identity.fingerprint}')
        ..writeln('ad.deskview.pwd_hash=${identity.unattendedPasswordHash}')
        ..writeln('ad.deskview.pwd_salt=${identity.unattendedSalt}')
        ..writeln('ad.deskview.port=${identity.listenPort}')
        ..writeln('ad.deskview.favorites=${identity.favorites.join(";")}')
        ..writeln('ad.deskview.recent=${identity.recentSessions.join(";")}');
      _configFile.writeAsStringSync(sb.toString(), encoding: utf8);
    } catch (_) {}
  }

  @override
  Future<DeskIdentity> updateUnattendedPassword(DeskIdentity current, String plainPassword) async {
    DeskIdentity updated;
    if (plainPassword.trim().isEmpty) {
      updated = current.copyWith(unattendedPasswordHash: '', unattendedSalt: '');
    } else {
      final String salt = SessionCipher.generateRandomSalt(16);
      final String hash = SessionCipher.hashPasswordWithSalt(plainPassword, salt);
      updated = current.copyWith(unattendedPasswordHash: hash, unattendedSalt: salt);
    }
    await saveIdentity(updated);
    return updated;
  }

  @override
  bool verifyUnattendedPassword(DeskIdentity identity, String candidatePassword) {
    if (!identity.hasUnattendedPassword || candidatePassword.isEmpty) {
      return false;
    }
    final String expectedHash = SessionCipher.hashPasswordWithSalt(
      candidatePassword,
      identity.unattendedSalt,
    );
    return SessionCipher.constantTimeEquals(identity.unattendedPasswordHash, expectedHash);
  }

  @override
  Future<List<PeerDevice>> loadSavedPeers() async {
    if (inMemoryOnly) return List<PeerDevice>.unmodifiable(_cachedPeers);

    _cachedPeers.clear();
    try {
      if (_loginsFile.existsSync()) {
        final List<String> lines = _loginsFile.readAsLinesSync(encoding: utf8);
        for (final String rawLine in lines) {
          final String line = rawLine.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final List<String> parts = line.split('|');
          if (parts.length < 7) continue;

          final String deskId = _decodeBase64Field(parts[0]);
          final String hostName = _decodeBase64Field(parts[1]);
          final String endpoint = _decodeBase64Field(parts[2]);
          final String password = SessionCipher.decryptLocalSecret(parts[3]);
          final int monitors = (int.tryParse(parts[4]) ?? 1).clamp(1, 16);
          final bool isFav = parts[6].trim() == '1';

          final ({String host, int port})? ep = DeskIdFormatter.parseEndpoint(endpoint);
          if (ep == null) continue;

          _cachedPeers.add(
            PeerDevice(
              key: endpoint,
              deskId: deskId,
              hostName: hostName.isNotEmpty ? hostName : 'Computador Remoto',
              ipAddress: ep.host,
              port: ep.port,
              monitorCount: monitors,
              savedPassword: password,
              lastSeen: DateTime.now(),
              isFavorite: isFav,
              source: PeerDiscoverySource.savedHistory,
            ),
          );
        }
      }
    } catch (_) {}

    return List<PeerDevice>.unmodifiable(_cachedPeers);
  }

  @override
  Future<List<PeerDevice>> saveOrUpdatePeer(PeerDevice peer) async {
    final int existingIdx = _cachedPeers.indexWhere(
      (PeerDevice p) =>
          p.endpoint.toLowerCase() == peer.endpoint.toLowerCase() ||
          (peer.deskId.isNotEmpty && p.deskId == peer.deskId),
    );

    if (existingIdx >= 0) {
      final PeerDevice old = _cachedPeers.removeAt(existingIdx);
      _cachedPeers.insert(
        0,
        peer.copyWith(
          savedPassword: peer.savedPassword.isNotEmpty ? peer.savedPassword : old.savedPassword,
          isFavorite: peer.isFavorite || old.isFavorite,
          lastSeen: DateTime.now(),
        ),
      );
    } else {
      _cachedPeers.insert(0, peer.copyWith(lastSeen: DateTime.now()));
    }

    if (_cachedPeers.length > 30) {
      _cachedPeers.removeRange(30, _cachedPeers.length);
    }

    _persistSavedPeersToDisk();
    return List<PeerDevice>.unmodifiable(_cachedPeers);
  }

  @override
  Future<List<PeerDevice>> removeSavedPeer(String keyOrEndpoint) async {
    _cachedPeers.removeWhere(
      (PeerDevice p) =>
          p.key.toLowerCase() == keyOrEndpoint.toLowerCase() ||
          p.endpoint.toLowerCase() == keyOrEndpoint.toLowerCase() ||
          p.deskId == keyOrEndpoint,
    );
    _persistSavedPeersToDisk();
    return List<PeerDevice>.unmodifiable(_cachedPeers);
  }

  @override
  Future<List<PeerDevice>> toggleFavoritePeer(String keyOrEndpoint) async {
    for (int i = 0; i < _cachedPeers.length; i++) {
      final PeerDevice p = _cachedPeers[i];
      if (p.key.toLowerCase() == keyOrEndpoint.toLowerCase() ||
          p.endpoint.toLowerCase() == keyOrEndpoint.toLowerCase() ||
          p.deskId == keyOrEndpoint) {
        _cachedPeers[i] = p.copyWith(isFavorite: !p.isFavorite);
        break;
      }
    }
    _persistSavedPeersToDisk();
    return List<PeerDevice>.unmodifiable(_cachedPeers);
  }

  void _persistSavedPeersToDisk() {
    if (inMemoryOnly) return;
    try {
      final StringBuffer sb = StringBuffer()..writeln('# DeskView Saved Logins (1-Click Access)');
      for (final PeerDevice entry in _cachedPeers) {
        final String f0 = _encodeBase64Field(entry.deskId);
        final String f1 = _encodeBase64Field(entry.hostName);
        final String f2 = _encodeBase64Field(entry.endpoint);
        final String f3 = SessionCipher.encryptLocalSecret(entry.savedPassword);
        final int f4 = entry.monitorCount;
        final int f5 = entry.lastSeen.millisecondsSinceEpoch * 10000;
        final String f6 = entry.isFavorite ? '1' : '0';
        sb.writeln('$f0|$f1|$f2|$f3|$f4|$f5|$f6');
      }
      _loginsFile.writeAsStringSync(sb.toString(), encoding: utf8);
    } catch (_) {}
  }

  static String _encodeBase64Field(String text) => base64Encode(utf8.encode(text));

  static String _decodeBase64Field(String b64) {
    try {
      return utf8.decode(base64Decode(b64));
    } catch (_) {
      return '';
    }
  }

  static String _safeHostname() {
    try {
      return Platform.localHostname.isNotEmpty ? Platform.localHostname : 'DeskView-Device';
    } catch (_) {
      return 'DeskView-Device';
    }
  }

  static String _safeUsername() {
    try {
      return Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? 'Operador';
    } catch (_) {
      return 'Operador';
    }
  }
}
