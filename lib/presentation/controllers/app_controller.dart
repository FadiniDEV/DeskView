import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/constants/protocol_constants.dart';
import '../../core/crypto/session_cipher.dart';
import '../../core/utils/desk_id_formatter.dart';
import '../../domain/entities/connection_candidate.dart';
import '../../domain/entities/desk_identity.dart';
import '../../domain/entities/input_commands.dart';
import '../../domain/entities/peer_device.dart';
import '../../domain/entities/session_models.dart';
import '../../domain/repositories/identity_repository.dart';
import '../../platform/native_platform_bridge.dart';
import '../../services/communication/connection_orchestrator.dart';
import '../../services/communication/global_signaling_service.dart';
import '../../services/communication/host_session_server.dart';
import '../../services/communication/lan_discovery_service.dart';
import '../../services/communication/session_transport.dart';
import '../../services/communication/stun_client_service.dart';
import '../../services/input/peripheral_manager_service.dart';

/// Controlador principal de estado da aplicação DeskView em Flutter.
class AppController extends ChangeNotifier {
  final IdentityRepository identityRepository;
  final NativePlatformBridge platformBridge;
  late final PeripheralManagerService peripheralManager;
  late final StunClientService stunService;
  late final LanDiscoveryService lanDiscovery;
  late final GlobalSignalingService globalSignaling;
  late final HostSessionServer hostServer;
  late final ConnectionOrchestrator connectionOrchestrator;

  DeskIdentity _identity = const DeskIdentity(
    deskId: '000000000',
    fingerprint: '',
    machineName: 'Inicializando...',
    userName: 'Operador',
    listenPort: ProtocolConstants.defaultListenPort,
    unattendedPasswordHash: '',
    unattendedSalt: '',
    localLoopbackNonce: '',
  );

  NetworkEndpointsSnapshot _networkSnapshot = NetworkEndpointsSnapshot(
    primaryLocalIp: '127.0.0.1',
    allLocalIps: const <String>['127.0.0.1'],
    publicWanIp: 'Detectando...',
    mappedExternalPort: ProtocolConstants.defaultListenPort,
    natTopology: NatTopologyType.unknown,
    resolvedAt: DateTime.now(),
  );

  bool _initialized = false;
  bool _isCloudConnected = false;
  String _networkStatusLabel = 'Inicializando serviços de rede...';
  bool _isConnectingBannerVisible = false;
  String _connectingBannerText = '';
  int _selectedNavIndex = 0;
  int _activeHostClientCount = 0;

  final List<PeerDevice> _savedPeers = <PeerDevice>[];
  final List<RemoteSessionClientController> _openSessions = <RemoteSessionClientController>[];
  int _activeSessionTabIndex = -1; // -1 = Painel Principal, >= 0 = Índice da aba de sessão

  final List<String> _diagnosticLogs = <String>[];
  final List<SessionChatMessage> _hostChatMessages = <SessionChatMessage>[];

  /// Fila / trava para solicitações de conexão entrantes (evita empilhamento de modais).
  IncomingConnectionRequest? _activeIncomingModalRequest;
  Completer<({bool approved, SessionPermissions permissions})>? _incomingModalCompleter;

  AppController({
    required this.identityRepository,
    required this.platformBridge,
  }) {
    peripheralManager = PeripheralManagerService(platformBridge);
    stunService = StunClientService();
    lanDiscovery = LanDiscoveryService();
    globalSignaling = GlobalSignalingService();
    hostServer = HostSessionServer(
      identityRepository: identityRepository,
      platformBridge: platformBridge,
    );
    connectionOrchestrator = ConnectionOrchestrator(
      lanDiscovery: lanDiscovery,
      globalSignaling: globalSignaling,
      hostServer: hostServer,
    );

    _wireSubsystems();
  }

  DeskIdentity get identity => _identity;
  NetworkEndpointsSnapshot get networkSnapshot => _networkSnapshot;
  bool get initialized => _initialized;
  bool get isCloudConnected => _isCloudConnected;
  String get networkStatusLabel => _networkStatusLabel;
  bool get isConnectingBannerVisible => _isConnectingBannerVisible;
  String get connectingBannerText => _connectingBannerText;
  int get selectedNavIndex => _selectedNavIndex;
  int get activeHostClientCount => _activeHostClientCount;
  List<RemoteSessionClientController> get openSessions =>
      List<RemoteSessionClientController>.unmodifiable(_openSessions);
  int get activeSessionTabIndex => _activeSessionTabIndex;
  RemoteSessionClientController? get activeSession =>
      (_activeSessionTabIndex >= 0 && _activeSessionTabIndex < _openSessions.length)
          ? _openSessions[_activeSessionTabIndex]
          : null;
  List<String> get diagnosticLogs => List<String>.unmodifiable(_diagnosticLogs);
  List<SessionChatMessage> get hostChatMessages =>
      List<SessionChatMessage>.unmodifiable(_hostChatMessages);
  IncomingConnectionRequest? get activeIncomingModalRequest => _activeIncomingModalRequest;

  /// Lista unificada de computadores recentes, favoritos e descobertos na LAN/WAN.
  List<PeerDevice> get combinedPeers {
    final Map<String, PeerDevice> merged = <String, PeerDevice>{};

    for (final PeerDevice saved in _savedPeers) {
      merged[saved.deskId.isNotEmpty ? saved.deskId : saved.endpoint] = saved;
    }

    for (final PeerDevice lan in lanDiscovery.discoveredPeers) {
      final PeerDevice? existing = merged[lan.deskId];
      merged[lan.deskId] = lan.copyWith(
        savedPassword: existing?.savedPassword ?? '',
        isFavorite: existing?.isFavorite ?? false,
        isOnline: true,
        source: PeerDiscoverySource.localLan,
      );
    }

    for (final PeerDevice global in globalSignaling.globalPeers) {
      final PeerDevice? existing = merged[global.deskId];
      if (existing == null || existing.source != PeerDiscoverySource.localLan) {
        merged[global.deskId] = global.copyWith(
          savedPassword: existing?.savedPassword ?? '',
          isFavorite: existing?.isFavorite ?? false,
          isOnline: true,
        );
      }
    }

    if (merged.isEmpty && _identity.deskId != '000000000') {
      merged[_identity.deskId] = PeerDevice(
        key: '127.0.0.1:${_identity.listenPort}',
        deskId: _identity.deskId,
        hostName: '${_identity.machineName} (Loopback Local)',
        userName: _identity.userName,
        ipAddress: '127.0.0.1',
        localIpAddress: '127.0.0.1',
        port: _identity.listenPort,
        monitorCount: 1,
        lastSeen: DateTime.now(),
        isFavorite: true,
        isOnline: true,
        source: PeerDiscoverySource.loopback,
      );
    }

    return merged.values.toList(growable: false);
  }

  void _wireSubsystems() {
    // Encaminha eventos capturados pelo PeripheralManagerService para a sessão remota ativa
    peripheralManager.onMouseCommandReady = (MouseInputCommand cmd) {
      activeSession?.sendMouseCommand(cmd);
    };
    peripheralManager.onKeyCommandReady = (KeyInputCommand cmd) {
      activeSession?.sendKeyCommand(cmd);
    };
    peripheralManager.onGamepadCommandReady = (GamepadInputCommand cmd) {
      activeSession?.sendGamepadCommand(cmd);
    };

    hostServer.onServerLog = _appendLog;
    hostServer.onActiveSessionCountChanged = (int count) {
      _activeHostClientCount = count;
      notifyListeners();
    };
    hostServer.onChatMessageReceived = (SessionChatMessage msg) {
      _hostChatMessages.add(msg);
      notifyListeners();
    };
    hostServer.onAuthorizeSessionRequest = _promptInteractiveApproval;

    lanDiscovery.onPeersUpdated = (_) => notifyListeners();

    globalSignaling.onStatusChanged = (String msg, bool connected) {
      _isCloudConnected = connected;
      _networkStatusLabel = msg;
      _appendLog(msg);
      notifyListeners();
    };
    globalSignaling.onPeerDiscovered = (_) => notifyListeners();
    globalSignaling.onIncomingConnectionRequested = _handleIncomingGlobalRequest;
    globalSignaling.onConnectionAccepted = ({
      required String targetDeskId,
      required String targetHostName,
      required String targetPublicEndpoint,
      required String targetLocalEndpoint,
      String? relaySessionId,
    }) {
      connectionOrchestrator.notifyGlobalConnectionAccepted(
        targetDeskId: targetDeskId,
        targetHostName: targetHostName,
        targetPublicEndpoint: targetPublicEndpoint,
        targetLocalEndpoint: targetLocalEndpoint,
        relaySessionId: relaySessionId,
      );
    };
    globalSignaling.onConnectionRejected = ({
      required String targetDeskId,
      required String targetHostName,
      required String reason,
    }) {
      connectionOrchestrator.notifyGlobalConnectionRejected(
        targetDeskId: targetDeskId,
        targetHostName: targetHostName,
        reason: reason,
      );
    };
  }

  /// Inicializa identidade, periféricos, servidor Host, descoberta LAN, STUN e sinalização global.
  Future<void> initialize({bool enableNetworkSockets = true}) async {
    if (_initialized) return;
    _identity = await identityRepository.loadOrCreateIdentity();
    _savedPeers
      ..clear()
      ..addAll(await identityRepository.loadSavedPeers());

    await peripheralManager.initialize();

    if (enableNetworkSockets) {
      final int boundPort = await hostServer.start(_identity);
      if (boundPort != _identity.listenPort) {
        _identity = _identity.copyWith(listenPort: boundPort);
        await identityRepository.saveIdentity(_identity);
      }

      unawaited(_refreshNetworkTopology());

      await lanDiscovery.start(
        identity: _identity,
        localIpProvider: () => _networkSnapshot.primaryLocalIp,
        monitorCountProvider: () => 1,
      );

      await globalSignaling.start(
        identity: _identity,
        wanIpProvider: () => _networkSnapshot.publicWanIp,
        localIpProvider: () => _networkSnapshot.primaryLocalIp,
        monitorCountProvider: () => 1,
      );
    } else {
      _networkStatusLabel = 'Modo Pronto (Simulação Local Ativa)';
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> _refreshNetworkTopology() async {
    _networkSnapshot = await stunService.discoverNetworkTopology(
      localListenPort: _identity.listenPort,
    );
    _appendLog(
      'Topologia STUN resolvida: LAN ${_networkSnapshot.primaryLocalIp}:${_identity.listenPort} | '
      'WAN ${_networkSnapshot.formattedPublicEndpoint} (${_networkSnapshot.natTopology.description})',
    );
    globalSignaling.publishPresence();
    notifyListeners();
  }

  Future<void> refreshNetworkDiagnostics() async {
    await _refreshNetworkTopology();
  }

  void setSelectedNavIndex(int index) {
    _selectedNavIndex = index;
    _activeSessionTabIndex = -1;
    notifyListeners();
  }

  void selectSessionTab(int tabIndex) {
    if (tabIndex >= -1 && tabIndex < _openSessions.length) {
      _activeSessionTabIndex = tabIndex;
      notifyListeners();
    }
  }

  /// Inicia conexão com outro dispositivo por DeskID de 9 dígitos ou IP:Porta.
  Future<String?> initiateConnection(String rawTarget, String password) async {
    if (rawTarget.trim().isEmpty) {
      return 'Informe o código DeskView de 9 dígitos ou IP:Porta.';
    }

    _isConnectingBannerVisible = true;
    _connectingBannerText = 'Iniciando conexão com ${DeskIdFormatter.format(rawTarget)}...';
    notifyListeners();

    final ({RemoteSessionClientController? session, String? errorMessage}) res =
        await connectionOrchestrator.connectToTarget(
      rawTarget: rawTarget,
      password: password,
      localIdentity: _identity,
      myPublicEndpoint: _networkSnapshot.formattedPublicEndpoint,
      myLocalEndpoint: '${_networkSnapshot.primaryLocalIp}:${_identity.listenPort}',
      onProgress: (String msg) {
        _connectingBannerText = msg;
        notifyListeners();
      },
    );

    _isConnectingBannerVisible = false;

    if (res.session == null) {
      notifyListeners();
      return res.errorMessage ?? 'Não foi possível estabelecer a sessão remota.';
    }

    final RemoteSessionClientController session = res.session!;
    _openSessions.add(session);
    _activeSessionTabIndex = _openSessions.length - 1;

    // Salva no histórico de logins 1-Clique
    final PeerDevice savedEntry = PeerDevice(
      key: session.targetDeskId.isNotEmpty
          ? session.targetDeskId
          : session.transport.remoteAddressDescription,
      deskId: session.targetDeskId,
      hostName: session.remoteHostName,
      ipAddress: session.transport.remoteAddressDescription.split(':').first,
      port: _identity.listenPort,
      monitorCount: session.screenMeta.monitorCount,
      savedPassword: password,
      lastSeen: DateTime.now(),
      isOnline: true,
    );
    _savedPeers
      ..clear()
      ..addAll(await identityRepository.saveOrUpdatePeer(savedEntry));

    notifyListeners();
    return null;
  }

  void cancelOngoingConnection() {
    connectionOrchestrator.cancelPendingConnection();
    _isConnectingBannerVisible = false;
    notifyListeners();
  }

  Future<void> closeSessionTab(RemoteSessionClientController session) async {
    final int idx = _openSessions.indexOf(session);
    if (idx < 0) return;
    await session.disconnect();
    session.dispose();
    _openSessions.removeAt(idx);
    if (_openSessions.isEmpty) {
      _activeSessionTabIndex = -1;
    } else if (_activeSessionTabIndex >= _openSessions.length) {
      _activeSessionTabIndex = _openSessions.length - 1;
    }
    notifyListeners();
  }

  Future<void> updateUnattendedPassword(String plainPassword) async {
    _identity = await identityRepository.updateUnattendedPassword(_identity, plainPassword);
    hostServer.updateIdentity(_identity);
    _appendLog(
      _identity.hasUnattendedPassword
          ? 'Senha de acesso desassistido atualizada com segurança (HMAC-SHA256).'
          : 'Acesso desassistido desativado.',
    );
    notifyListeners();
  }

  Future<void> removeSavedPeer(String keyOrEndpoint) async {
    _savedPeers
      ..clear()
      ..addAll(await identityRepository.removeSavedPeer(keyOrEndpoint));
    notifyListeners();
  }

  Future<void> toggleFavoritePeer(String keyOrEndpoint) async {
    _savedPeers
      ..clear()
      ..addAll(await identityRepository.toggleFavoritePeer(keyOrEndpoint));
    notifyListeners();
  }

  void sendHostChatReply(String text) {
    if (text.trim().isEmpty) return;
    hostServer.broadcastHostChatMessage(text.trim());
    _hostChatMessages.add(
      SessionChatMessage(
        senderName: 'Host (${_identity.machineName})',
        text: text.trim(),
        timestamp: DateTime.now(),
        isLocalSender: true,
      ),
    );
    notifyListeners();
  }

  /// Tratamento de pedido de conexão entrante via Sinalização Global MQTT.
  Future<void> _handleIncomingGlobalRequest(IncomingConnectionRequest req) async {
    if (_activeIncomingModalRequest != null) {
      globalSignaling.sendConnectReject(
        callerDeskId: req.callerDeskId,
        targetDeskId: _identity.deskId,
        targetHostName: _identity.machineName,
        reason: 'O host está ocupado avaliando outra solicitação de acesso.',
      );
      return;
    }

    final ({bool approved, SessionPermissions permissions}) decision =
        await _promptInteractiveApproval(
      clientDeskId: req.callerDeskId,
      clientHostName: req.callerHostName,
      remoteAddress: req.callerPublicEndpoint,
    );

    if (!decision.approved) {
      globalSignaling.sendConnectReject(
        callerDeskId: req.callerDeskId,
        targetDeskId: _identity.deskId,
        targetHostName: _identity.machineName,
        reason: 'Sessão recusada pelo usuário remoto.',
      );
      return;
    }

    final String relayId =
        req.relaySessionId ?? 'rv3_${req.callerDeskId}_${_identity.deskId}_${SessionCipher.generateNonceHex(3)}';

    // Registra o endpoint Relay no Host para garantir conectividade caso o P2P direto falhe no CGNAT
    final RelaySessionTransport relayHostTransport = RelaySessionTransport(
      signaling: globalSignaling,
      sessionId: relayId,
      isHostSide: true,
    );
    hostServer.acceptTransportConnection(
      relayHostTransport,
      preApprovedPermissions: decision.permissions,
    );

    // Envia ACK assinado ao operador remoto
    globalSignaling.sendConnectAccept(
      callerDeskId: req.callerDeskId,
      targetDeskId: _identity.deskId,
      targetHostName: _identity.machineName,
      targetPublicEndpoint: _networkSnapshot.formattedPublicEndpoint,
      targetLocalEndpoint: '${_networkSnapshot.primaryLocalIp}:${_identity.listenPort}',
      relaySessionId: relayId,
    );

    // Tenta conexão TCP reversa em paralelo (para furar NAT quando o operador possui porta acessível)
    unawaited(_tryReverseTcpConnect(req.callerLocalEndpoint, decision.permissions));
    unawaited(_tryReverseTcpConnect(req.callerPublicEndpoint, decision.permissions));
  }

  Future<void> _tryReverseTcpConnect(
    String endpoint,
    SessionPermissions permissions,
  ) async {
    final ({String host, int port})? ep = DeskIdFormatter.parseEndpoint(endpoint);
    if (ep == null || ep.host == '127.0.0.1') return;
    try {
      final Socket socket = await Socket.connect(
        ep.host,
        ep.port,
        timeout: const Duration(milliseconds: 2500),
      );
      hostServer.acceptTransportConnection(
        DirectTcpSessionTransport(socket, routeType: TransportRouteType.stunReflexiveP2P),
        preApprovedPermissions: permissions,
      );
    } catch (_) {}
  }

  Future<({bool approved, SessionPermissions permissions})> _promptInteractiveApproval({
    required String clientDeskId,
    required String clientHostName,
    required String remoteAddress,
  }) async {
    if (_activeIncomingModalRequest != null && _incomingModalCompleter != null) {
      return (approved: false, permissions: const SessionPermissions());
    }

    _activeIncomingModalRequest = IncomingConnectionRequest(
      requestId: SessionCipher.generateNonceHex(4),
      callerDeskId: clientDeskId,
      callerHostName: clientHostName,
      callerPublicEndpoint: remoteAddress,
      callerLocalEndpoint: remoteAddress,
      requestedAt: DateTime.now(),
    );
    _incomingModalCompleter = Completer<({bool approved, SessionPermissions permissions})>();
    notifyListeners();

    return _incomingModalCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _activeIncomingModalRequest = null;
        _incomingModalCompleter = null;
        notifyListeners();
        return (approved: false, permissions: const SessionPermissions());
      },
    );
  }

  /// Resolve a decisão do usuário no modal de aceitação de sessão (`AcceptSessionDialog`).
  void resolveIncomingSessionDecision({
    required bool approved,
    required SessionPermissions permissions,
  }) {
    if (_incomingModalCompleter != null && !_incomingModalCompleter!.isCompleted) {
      _incomingModalCompleter!.complete((approved: approved, permissions: permissions));
    }
    _activeIncomingModalRequest = null;
    _incomingModalCompleter = null;
    notifyListeners();
  }

  void _appendLog(String line) {
    final DateTime now = DateTime.now();
    final String ts =
        '${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}:${now.second.toString().padLeft(2, "0")}';
    _diagnosticLogs.insert(0, '[$ts] $line');
    if (_diagnosticLogs.length > 80) {
      _diagnosticLogs.removeRange(80, _diagnosticLogs.length);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final RemoteSessionClientController s in _openSessions) {
      s.dispose();
    }
    lanDiscovery.dispose();
    globalSignaling.dispose();
    hostServer.dispose();
    peripheralManager.dispose();
    super.dispose();
  }
}
