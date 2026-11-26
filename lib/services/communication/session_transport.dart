import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/constants/protocol_constants.dart';
import '../../domain/entities/connection_candidate.dart';
import '../../domain/entities/session_models.dart';
import 'global_signaling_service.dart';
import 'packet_frame_io.dart';

/// Abstração de canal de transporte de sessão que permite alternar de forma transparente
/// entre Socket TCP Direto (LAN / WAN P2P) e Túnel Relay Criptografado (Travessia de CGNAT).
abstract class SessionTransport {
  TransportRouteType get routeType;
  String get remoteAddressDescription;
  bool get isOpen;
  Stream<DecodedPacketFrame> get incomingFrames;

  void setSessionEncryptionKey(String key);
  void sendPacket(PacketType type, List<int>? payload);
  Future<void> close();
}

/// Implementação de [SessionTransport] sobre Socket TCP nativo de baixa latência.
class DirectTcpSessionTransport implements SessionTransport {
  final Socket _socket;
  @override
  final TransportRouteType routeType;
  final PacketStreamDecoder _decoder = PacketStreamDecoder();
  final StreamController<DecodedPacketFrame> _controller =
      StreamController<DecodedPacketFrame>.broadcast();

  String? _encryptionKey;
  bool _isOpen = true;
  late final String _remoteDesc;

  DirectTcpSessionTransport(this._socket, {this.routeType = TransportRouteType.lanDirect}) {
    _socket.setOption(SocketOption.tcpNoDelay, true);
    try {
      _remoteDesc = '${_socket.remoteAddress.address}:${_socket.remotePort}';
    } catch (_) {
      _remoteDesc = 'TCP-Peer';
    }

    _socket.listen(
      (Uint8List chunk) {
        for (final DecodedPacketFrame frame in _decoder.addChunk(chunk)) {
          if (!_controller.isClosed) {
            _controller.add(frame);
          }
        }
      },
      onError: (_) => close(),
      onDone: close,
      cancelOnError: true,
    );
  }

  @override
  String get remoteAddressDescription => _remoteDesc;

  @override
  bool get isOpen => _isOpen;

  @override
  Stream<DecodedPacketFrame> get incomingFrames => _controller.stream;

  @override
  void setSessionEncryptionKey(String key) {
    _encryptionKey = key;
    _decoder.encryptionKey = key;
  }

  @override
  void sendPacket(PacketType type, List<int>? payload) {
    if (!_isOpen) return;
    try {
      final Uint8List frame = PacketFrameIO.encodeFrame(
        type,
        payload,
        encryptionKey: _encryptionKey,
      );
      _socket.add(frame);
    } catch (_) {
      close();
    }
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    try {
      _socket.destroy();
    } catch (_) {}
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

/// Implementação de [SessionTransport] sobre Túnel Relay Criptografado (`deskview/v3/tunnel/<sessionId>`).
/// Garante comunicação bidirecional completa mesmo quando ambos os dispositivos estão atrás de CGNAT ou NAT Simétrico.
class RelaySessionTransport implements SessionTransport {
  final GlobalSignalingService _signaling;
  final String sessionId;
  final bool isHostSide;
  final PacketStreamDecoder _decoder = PacketStreamDecoder();
  final StreamController<DecodedPacketFrame> _controller =
      StreamController<DecodedPacketFrame>.broadcast();

  String? _encryptionKey;
  bool _isOpen = true;

  late final String _txTopic;
  late final String _rxTopic;

  RelaySessionTransport({
    required GlobalSignalingService signaling,
    required this.sessionId,
    required this.isHostSide,
    String? initialEncryptionKey,
  }) : _signaling = signaling {
    _txTopic =
        '${ProtocolConstants.relayTunnelTopicPrefix}$sessionId/${isHostSide ? "h2c" : "c2h"}';
    _rxTopic =
        '${ProtocolConstants.relayTunnelTopicPrefix}$sessionId/${isHostSide ? "c2h" : "h2c"}';

    if (initialEncryptionKey != null && initialEncryptionKey.isNotEmpty) {
      setSessionEncryptionKey(initialEncryptionKey);
    }

    _signaling.subscribeRelayTunnel(_rxTopic, (Uint8List chunk) {
      if (!_isOpen) return;
      for (final DecodedPacketFrame frame in _decoder.addChunk(chunk)) {
        if (!_controller.isClosed) {
          _controller.add(frame);
        }
      }
    });
  }

  @override
  TransportRouteType get routeType => TransportRouteType.encryptedRelay;

  @override
  String get remoteAddressDescription => 'Relay://$sessionId';

  @override
  bool get isOpen => _isOpen;

  @override
  Stream<DecodedPacketFrame> get incomingFrames => _controller.stream;

  @override
  void setSessionEncryptionKey(String key) {
    _encryptionKey = key;
    _decoder.encryptionKey = key;
  }

  @override
  void sendPacket(PacketType type, List<int>? payload) {
    if (!_isOpen) return;
    final Uint8List fullFrame = PacketFrameIO.encodeFrame(
      type,
      payload,
      encryptionKey: _encryptionKey,
    );

    // Fragmenta automaticamente em blocos de até 24 KB para transporte eficiente pelo broker
    int offset = 0;
    while (offset < fullFrame.length) {
      final int end = (offset + ProtocolConstants.relayMaxFragmentBytes)
          .clamp(0, fullFrame.length);
      final Uint8List slice = fullFrame.sublist(offset, end);
      _signaling.publishBinary(_txTopic, slice);
      offset = end;
    }
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    _signaling.unsubscribeRelayTunnel(_rxTopic);
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

/// Par de transportes em memória para sessões de loopback instantâneas e testes automatizados.
class InMemoryLoopbackTransport implements SessionTransport {
  @override
  final TransportRouteType routeType;
  @override
  final String remoteAddressDescription;

  final PacketStreamDecoder _decoder = PacketStreamDecoder();
  final StreamController<DecodedPacketFrame> _controller =
      StreamController<DecodedPacketFrame>.broadcast();

  InMemoryLoopbackTransport? _peer;
  String? _encryptionKey;
  bool _isOpen = true;

  InMemoryLoopbackTransport({
    this.routeType = TransportRouteType.loopback,
    this.remoteAddressDescription = '127.0.0.1 (Loopback)',
  });

  /// Cria um par conectado `(clientTransport, hostTransport)`.
  static ({InMemoryLoopbackTransport client, InMemoryLoopbackTransport host}) createPair({
    TransportRouteType simulatedRoute = TransportRouteType.loopback,
  }) {
    final InMemoryLoopbackTransport a = InMemoryLoopbackTransport(
      routeType: simulatedRoute,
      remoteAddressDescription: 'Host-Loopback',
    );
    final InMemoryLoopbackTransport b = InMemoryLoopbackTransport(
      routeType: simulatedRoute,
      remoteAddressDescription: 'Client-Loopback',
    );
    a._peer = b;
    b._peer = a;
    return (client: a, host: b);
  }

  @override
  bool get isOpen => _isOpen;

  @override
  Stream<DecodedPacketFrame> get incomingFrames => _controller.stream;

  @override
  void setSessionEncryptionKey(String key) {
    _encryptionKey = key;
    _decoder.encryptionKey = key;
  }

  @override
  void sendPacket(PacketType type, List<int>? payload) {
    if (!_isOpen || _peer == null || !_peer!._isOpen) return;
    final Uint8List encoded = PacketFrameIO.encodeFrame(
      type,
      payload,
      encryptionKey: _encryptionKey,
    );
    scheduleMicrotask(() {
      if (_peer != null && _peer!._isOpen) {
        for (final DecodedPacketFrame f in _peer!._decoder.addChunk(encoded)) {
          if (!_peer!._controller.isClosed) {
            _peer!._controller.add(f);
          }
        }
      }
    });
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
