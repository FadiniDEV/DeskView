import 'dart:typed_data';

/// Ações de mouse compatíveis com o protocolo original (0..7) + extensões v3 (8..12).
enum MouseActionType {
  move(0),
  leftDown(1),
  leftUp(2),
  rightDown(3),
  rightUp(4),
  middleDown(5),
  middleUp(6),
  wheelVertical(7),
  wheelHorizontal(8),
  xButton1Down(9),
  xButton1Up(10),
  xButton2Down(11),
  xButton2Up(12);

  final int code;
  const MouseActionType(this.code);

  static MouseActionType fromCode(int code) {
    for (final MouseActionType t in MouseActionType.values) {
      if (t.code == code) return t;
    }
    return MouseActionType.move;
  }
}

/// Comando de Mouse com suporte retrocompatível (13 bytes v1) e estendido (19 bytes v3).
class MouseInputCommand {
  final MouseActionType action;
  final double normX;
  final double normY;
  final int wheelDeltaY;
  final int wheelDeltaX;
  final int buttonsMask;
  final int sequenceNumber;

  const MouseInputCommand({
    required this.action,
    required this.normX,
    required this.normY,
    this.wheelDeltaY = 0,
    this.wheelDeltaX = 0,
    this.buttonsMask = 0,
    this.sequenceNumber = 0,
  });

  double get clampedX => normX.isNaN || normX.isInfinite ? 0.5 : normX.clamp(0.0, 1.0);
  double get clampedY => normY.isNaN || normY.isInfinite ? 0.5 : normY.clamp(0.0, 1.0);

  /// Serializa em 19 bytes (primeiros 13 bytes são 100% compatíveis com o DeskView v1).
  Uint8List toBytes() {
    final Uint8List buf = Uint8List(19);
    final ByteData bd = ByteData.sublistView(buf);
    bd.setUint8(0, action.code);
    bd.setFloat32(1, clampedX, Endian.little);
    bd.setFloat32(5, clampedY, Endian.little);
    bd.setInt32(9, wheelDeltaY, Endian.little);
    // Campos estendidos v3 (bytes 13..18)
    bd.setInt16(13, wheelDeltaX.clamp(-32768, 32767), Endian.little);
    bd.setUint8(15, buttonsMask & 0xff);
    bd.setUint16(16, sequenceNumber & 0xffff, Endian.little);
    bd.setUint8(18, 3); // Versão 3
    return buf;
  }

  factory MouseInputCommand.fromBytes(Uint8List payload) {
    if (payload.length < 13) {
      return const MouseInputCommand(action: MouseActionType.move, normX: 0.5, normY: 0.5);
    }
    final ByteData bd = ByteData.sublistView(payload);
    final MouseActionType act = MouseActionType.fromCode(bd.getUint8(0));
    final double nx = bd.getFloat32(1, Endian.little);
    final double ny = bd.getFloat32(5, Endian.little);
    final int wy = bd.getInt32(9, Endian.little);

    int wx = 0;
    int mask = 0;
    int seq = 0;
    if (payload.length >= 19) {
      wx = bd.getInt16(13, Endian.little);
      mask = bd.getUint8(15);
      seq = bd.getUint16(16, Endian.little);
    }

    return MouseInputCommand(
      action: act,
      normX: nx.isNaN || nx.isInfinite ? 0.5 : nx.clamp(0.0, 1.0),
      normY: ny.isNaN || ny.isInfinite ? 0.5 : ny.clamp(0.0, 1.0),
      wheelDeltaY: wy,
      wheelDeltaX: wx,
      buttonsMask: mask,
      sequenceNumber: seq,
    );
  }
}

/// Comando de Teclado retrocompatível (3 bytes v1) e estendido (12 bytes v3 com ScanCode Set 1 e ExtendedKey).
class KeyInputCommand {
  final int winVirtualKey;
  final bool isDown;
  final int hardwareScanCode;
  final bool isExtendedKey;
  final int usbHidUsageId;
  final int modifiersMask; // bit0=Shift, bit1=Ctrl, bit2=Alt, bit3=Meta
  final int sequenceNumber;

  const KeyInputCommand({
    required this.winVirtualKey,
    required this.isDown,
    this.hardwareScanCode = 0,
    this.isExtendedKey = false,
    this.usbHidUsageId = 0,
    this.modifiersMask = 0,
    this.sequenceNumber = 0,
  });

  /// Serializa em 12 bytes (os primeiros 3 bytes mantêm layout v1: [vk, isDown, flags]).
  Uint8List toBytes() {
    final Uint8List buf = Uint8List(12);
    final ByteData bd = ByteData.sublistView(buf);
    bd.setUint8(0, winVirtualKey & 0xff);
    bd.setUint8(1, isDown ? 1 : 0);
    final int flags = (isExtendedKey ? 0x01 : 0x00) | ((modifiersMask & 0x0f) << 1);
    bd.setUint8(2, flags);
    // Campos estendidos v3 (bytes 3..11)
    bd.setUint16(3, hardwareScanCode & 0xffff, Endian.little);
    bd.setUint16(5, winVirtualKey & 0xffff, Endian.little);
    bd.setUint32(7, usbHidUsageId & 0xffffffff, Endian.little);
    bd.setUint8(11, sequenceNumber & 0xff);
    return buf;
  }

  factory KeyInputCommand.fromBytes(Uint8List payload) {
    if (payload.length < 2) {
      return const KeyInputCommand(winVirtualKey: 0, isDown: false);
    }
    final ByteData bd = ByteData.sublistView(payload);
    final int vk8 = bd.getUint8(0);
    final bool down = bd.getUint8(1) == 1;
    final int flags = payload.length >= 3 ? bd.getUint8(2) : 0;
    final bool ext = (flags & 0x01) != 0;
    final int mods = (flags >> 1) & 0x0f;

    int scan = 0;
    int vk16 = vk8;
    int hid = 0;
    int seq = 0;
    if (payload.length >= 12) {
      scan = bd.getUint16(3, Endian.little);
      vk16 = bd.getUint16(5, Endian.little);
      hid = bd.getUint32(7, Endian.little);
      seq = bd.getUint8(11);
    }

    return KeyInputCommand(
      winVirtualKey: vk16,
      isDown: down,
      hardwareScanCode: scan,
      isExtendedKey: ext,
      usbHidUsageId: hid,
      modifiersMask: mods,
      sequenceNumber: seq,
    );
  }
}

/// Bitmask de botões padrão de controle de videogame (compatível com XInput e Gamepad W3C/Android).
class GamepadButtons {
  GamepadButtons._();

  static const int dpadUp = 0x0001;
  static const int dpadDown = 0x0002;
  static const int dpadLeft = 0x0004;
  static const int dpadRight = 0x0008;
  static const int start = 0x0010;
  static const int backSelect = 0x0020;
  static const int leftThumbL3 = 0x0040;
  static const int rightThumbR3 = 0x0080;
  static const int leftShoulderLB = 0x0100;
  static const int rightShoulderRB = 0x0200;
  static const int guideHome = 0x0400;
  static const int buttonA = 0x1000;
  static const int buttonB = 0x2000;
  static const int buttonX = 0x4000;
  static const int buttonY = 0x8000;
}

/// Comando completo de Controle de Videogame (Gamepad) ou Joystick (20 bytes binários).
class GamepadInputCommand {
  final int controllerIndex; // 0..3
  final bool isConnected;
  final int buttonsMask; // 16 bits (GamepadButtons)
  final double leftTrigger; // 0.0 .. 1.0
  final double rightTrigger; // 0.0 .. 1.0
  final double leftStickX; // -1.0 .. 1.0
  final double leftStickY; // -1.0 .. 1.0
  final double rightStickX; // -1.0 .. 1.0
  final double rightStickY; // -1.0 .. 1.0
  final double rudderAxisZ; // -1.0 .. 1.0 (eixo extra para Joysticks)
  final int sequenceNumber;

  const GamepadInputCommand({
    this.controllerIndex = 0,
    this.isConnected = true,
    this.buttonsMask = 0,
    this.leftTrigger = 0.0,
    this.rightTrigger = 0.0,
    this.leftStickX = 0.0,
    this.leftStickY = 0.0,
    this.rightStickX = 0.0,
    this.rightStickY = 0.0,
    this.rudderAxisZ = 0.0,
    this.sequenceNumber = 0,
  });

  bool isButtonPressed(int mask) => (buttonsMask & mask) != 0;

  Uint8List toBytes() {
    final Uint8List buf = Uint8List(20);
    final ByteData bd = ByteData.sublistView(buf);
    bd.setUint16(0, sequenceNumber & 0xffff, Endian.little);
    bd.setUint8(2, controllerIndex.clamp(0, 3));
    bd.setUint8(3, isConnected ? 1 : 0);
    bd.setUint16(4, buttonsMask & 0xffff, Endian.little);
    bd.setUint8(6, (leftTrigger.clamp(0.0, 1.0) * 255).round());
    bd.setUint8(7, (rightTrigger.clamp(0.0, 1.0) * 255).round());
    bd.setInt16(8, (leftStickX.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    bd.setInt16(10, (leftStickY.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    bd.setInt16(12, (rightStickX.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    bd.setInt16(14, (rightStickY.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    bd.setInt16(16, (rudderAxisZ.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    bd.setUint16(18, 0, Endian.little); // Reservado
    return buf;
  }

  factory GamepadInputCommand.fromBytes(Uint8List payload) {
    if (payload.length < 20) {
      return const GamepadInputCommand(isConnected: false);
    }
    final ByteData bd = ByteData.sublistView(payload);
    return GamepadInputCommand(
      sequenceNumber: bd.getUint16(0, Endian.little),
      controllerIndex: bd.getUint8(2),
      isConnected: bd.getUint8(3) == 1,
      buttonsMask: bd.getUint16(4, Endian.little),
      leftTrigger: bd.getUint8(6) / 255.0,
      rightTrigger: bd.getUint8(7) / 255.0,
      leftStickX: (bd.getInt16(8, Endian.little) / 32767.0).clamp(-1.0, 1.0),
      leftStickY: (bd.getInt16(10, Endian.little) / 32767.0).clamp(-1.0, 1.0),
      rightStickX: (bd.getInt16(12, Endian.little) / 32767.0).clamp(-1.0, 1.0),
      rightStickY: (bd.getInt16(14, Endian.little) / 32767.0).clamp(-1.0, 1.0),
      rudderAxisZ: (bd.getInt16(16, Endian.little) / 32767.0).clamp(-1.0, 1.0),
    );
  }

  GamepadInputCommand copyWith({
    int? controllerIndex,
    bool? isConnected,
    int? buttonsMask,
    double? leftTrigger,
    double? rightTrigger,
    double? leftStickX,
    double? leftStickY,
    double? rightStickX,
    double? rightStickY,
    double? rudderAxisZ,
    int? sequenceNumber,
  }) {
    return GamepadInputCommand(
      controllerIndex: controllerIndex ?? this.controllerIndex,
      isConnected: isConnected ?? this.isConnected,
      buttonsMask: buttonsMask ?? this.buttonsMask,
      leftTrigger: leftTrigger ?? this.leftTrigger,
      rightTrigger: rightTrigger ?? this.rightTrigger,
      leftStickX: leftStickX ?? this.leftStickX,
      leftStickY: leftStickY ?? this.leftStickY,
      rightStickX: rightStickX ?? this.rightStickX,
      rightStickY: rightStickY ?? this.rightStickY,
      rudderAxisZ: rudderAxisZ ?? this.rudderAxisZ,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
    );
  }
}
