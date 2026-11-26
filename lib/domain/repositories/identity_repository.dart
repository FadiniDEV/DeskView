import '../entities/desk_identity.dart';
import '../entities/peer_device.dart';

/// Contrato de persistência para Identidade Local, Senha Desassistida e Histórico de Logins Salvos.
abstract class IdentityRepository {
  Future<DeskIdentity> loadOrCreateIdentity({int? overridePort});
  Future<void> saveIdentity(DeskIdentity identity);
  Future<DeskIdentity> updateUnattendedPassword(DeskIdentity current, String plainPassword);
  bool verifyUnattendedPassword(DeskIdentity identity, String candidatePassword);

  Future<List<PeerDevice>> loadSavedPeers();
  Future<List<PeerDevice>> saveOrUpdatePeer(PeerDevice peer);
  Future<List<PeerDevice>> removeSavedPeer(String keyOrEndpoint);
  Future<List<PeerDevice>> toggleFavoritePeer(String keyOrEndpoint);
}
