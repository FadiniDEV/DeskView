import 'dart:typed_data';
import 'connection_candidate.dart';

/// Tipos de pacote binário do protocolo DeskView (100% compatíveis com o enum original + extensões v3).
enum PacketType {
  handshakeHello(1),
  handshakeAuthRequest(2),
  handshakeAuthResponse(3),
  screenMeta(10),
  tileFrameDirty(11),
  cursorUpdate(12),
  mouseInput(20),
  keyInput(21),
  switchMonitor(22),
  qualityChange(23),
  gamepadInput(24),
  peripheralInventorySync(25),
  clipboardText(30),
  chatMessage(40),
  fileTransferOffer(50),
  fileTransferChunk(51),
  fileTransferEnd(52),
  ping(90),
  pong(91),
  disconnect(99);

  final int code;
  const PacketType(this.code);

  static PacketType fromCode(int code) {
    for (final PacketType p in PacketType.values) {
      if (p.code == code) return p;
    }
    return PacketType.disconnect;
  }
}

/// Permissões granulares concedidas pelo usuário do Host ao aceitar uma sessão remota.
class SessionPermissions {
  final bool allowMouseAndKeyboard;
  final bool allowGamepadAndJoystick;
  final bool allowClipboardSync;
  final bool allowFileTransfer;

  const SessionPermissions({
    this.allowMouseAndKeyboard = true,
    this.allowGamepadAndJoystick = true,
    this.allowClipboardSync = true,
    this.allowFileTransfer = true,
  });

  SessionPermissions copyWith({
    bool? allowMouseAndKeyboard,
    bool? allowGamepadAndJoystick,
    bool? allowClipboardSync,
    bool? allowFileTransfer,
  }) {
    return SessionPermissions(
      allowMouseAndKeyboard: allowMouseAndKeyboard ?? this.allowMouseAndKeyboard,
      allowGamepadAndJoystick: allowGamepadAndJoystick ?? this.allowGamepadAndJoystick,
      allowClipboardSync: allowClipboardSync ?? this.allowClipboardSync,
      allowFileTransfer: allowFileTransfer ?? this.allowFileTransfer,
    );
  }
}

/// Metadados de tela remota (`PacketType.screenMeta`).
class ScreenMetadata {
  final int monitorCount;
  final int selectedMonitorIndex; // -1 = primário, -2 = todos (VirtualScreen), >= 0 = índice
  final int left;
  final int top;
  final int width;
  final int height;

  const ScreenMetadata({
    required this.monitorCount,
    required this.selectedMonitorIndex,
    this.left = 0,
    this.top = 0,
    required this.width,
    required this.height,
  });

  Uint8List toBytes() {
    final Uint8List buf = Uint8List(24);
    final ByteData bd = ByteData.sublistView(buf);
    bd.setInt32(0, monitorCount, Endian.little);
    bd.setInt32(4, selectedMonitorIndex, Endian.little);
    bd.setInt32(8, left, Endian.little);
    bd.setInt32(12, top, Endian.little);
    bd.setInt32(16, width, Endian.little);
    bd.setInt32(20, height, Endian.little);
    return buf;
  }

  factory ScreenMetadata.fromBytes(Uint8List payload) {
    if (payload.length < 24) {
      return const ScreenMetadata(monitorCount: 1, selectedMonitorIndex: -1, width: 1920, height: 1080);
    }
    final ByteData bd = ByteData.sublistView(payload);
    return ScreenMetadata(
      monitorCount: bd.getInt32(0, Endian.little).clamp(1, 16),
      selectedMonitorIndex: bd.getInt32(4, Endian.little),
      left: bd.getInt32(8, Endian.little),
      top: bd.getInt32(12, Endian.little),
      width: bd.getInt32(16, Endian.little).clamp(64, 16384),
      height: bd.getInt32(20, Endian.little).clamp(64, 16384),
    );
  }
}

/// Representa um bloco retangular alterado (Dirty Tile) dentro de um frame DeskRT.
class DirtyTileBlock {
  final int x;
  final int y;
  final int width;
  final int height;
  final Uint8List encodedBytes;

  const DirtyTileBlock({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.encodedBytes,
  });
}

/// Pacote completo de Dirty Tiles decodificado (`PacketType.tileFrameDirty`).
class DirtyTileFrame {
  final int fullWidth;
  final int fullHeight;
  final List<DirtyTileBlock> tiles;

  const DirtyTileFrame({
    required this.fullWidth,
    required this.fullHeight,
    required this.tiles,
  });
}

/// Mensagem de chat bidirecional da sessão.
class SessionChatMessage {
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool isLocalSender;
  final bool isSystemLog;

  const SessionChatMessage({
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.isLocalSender = false,
    this.isSystemLog = false,
  });

  String get formattedTime {
    final String hh = timestamp.hour.toString().padLeft(2, '0');
    final String mm = timestamp.minute.toString().padLeft(2, '0');
    final String ss = timestamp.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

/// Telemetria em tempo real da sessão ativa.
class SessionTelemetry {
  final int fps;
  final int dirtyTilesPerSecond;
  final double kbps;
  final int latencyMs;
  final TransportRouteType activeRoute;
  final bool isEncrypted;

  const SessionTelemetry({
    this.fps = 0,
    this.dirtyTilesPerSecond = 0,
    this.kbps = 0.0,
    this.latencyMs = 1,
    this.activeRoute = TransportRouteType.lanDirect,
    this.isEncrypted = true,
  });
}

/// Solicitação de conexão entrante (via LAN, TCP direto ou Sinalização Global MQTT).
class IncomingConnectionRequest {
  final String requestId;
  final String callerDeskId;
  final String callerHostName;
  final String callerPublicEndpoint;
  final String callerLocalEndpoint;
  final String? relaySessionId;
  final DateTime requestedAt;

  const IncomingConnectionRequest({
    required this.requestId,
    required this.callerDeskId,
    required this.callerHostName,
    required this.callerPublicEndpoint,
    required this.callerLocalEndpoint,
    this.relaySessionId,
    required this.requestedAt,
  });
}
