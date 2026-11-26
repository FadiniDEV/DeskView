import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/input_commands.dart';
import '../../domain/entities/peripheral_device.dart';
import '../../platform/native_platform_bridge.dart';
import 'key_mapping_table.dart';

/// Serviço central de detecção, hotplug, estado em tempo real e transmissão de Mouse,
/// Teclado, Controles de Videogame (Gamepads) e Joysticks.
class PeripheralManagerService extends ChangeNotifier {
  final NativePlatformBridge _bridge;

  final List<PeripheralDevice> _devices = <PeripheralDevice>[];
  final Set<int> _pressedVirtualKeys = <int>{};
  int _pressedMouseButtonsMask = 0;

  GamepadInputCommand _currentGamepadState = const GamepadInputCommand(controllerIndex: 0);
  MouseInputCommand _lastMouseCommand =
      const MouseInputCommand(action: MouseActionType.move, normX: 0.5, normY: 0.5);
  String _lastKeyboardEventSummary = 'Nenhuma tecla pressionada';

  int _sequenceCounter = 0;
  int _lastMouseMoveEpochMs = 0;
  double _stickDeadzone = 0.08;
  bool _emulateMouseWithGamepadOnHost = false;

  Timer? _gamepadPollingTimer;
  StreamSubscription<Map<String, dynamic>>? _hotplugSubscription;

  /// Callbacks para envio imediato à sessão remota ativa.
  void Function(MouseInputCommand command)? onMouseCommandReady;
  void Function(KeyInputCommand command)? onKeyCommandReady;
  void Function(GamepadInputCommand command)? onGamepadCommandReady;

  PeripheralManagerService(this._bridge);

  List<PeripheralDevice> get devices => List<PeripheralDevice>.unmodifiable(_devices);
  Set<int> get pressedVirtualKeys => Set<int>.unmodifiable(_pressedVirtualKeys);
  int get pressedMouseButtonsMask => _pressedMouseButtonsMask;
  GamepadInputCommand get currentGamepadState => _currentGamepadState;
  MouseInputCommand get lastMouseCommand => _lastMouseCommand;
  String get lastKeyboardEventSummary => _lastKeyboardEventSummary;
  double get stickDeadzone => _stickDeadzone;
  bool get emulateMouseWithGamepadOnHost => _emulateMouseWithGamepadOnHost;

  /// Inicializa a enumeração de periféricos, escuta hotplug e inicia polling de Gamepads/Joysticks.
  Future<void> initialize() async {
    await refreshPeripherals();

    _hotplugSubscription?.cancel();
    _hotplugSubscription = _bridge.peripheralHotplugStream.listen((_) {
      refreshPeripherals();
    });

    _gamepadPollingTimer?.cancel();
    _gamepadPollingTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _pollNativeGamepads();
    });
  }

  /// Atualiza a lista de mouses, teclados, controles e joysticks conectados.
  Future<void> refreshPeripherals() async {
    final List<PeripheralDevice> queried = await _bridge.queryConnectedPeripherals();
    final Map<String, bool> previousToggleState = <String, bool>{
      for (final PeripheralDevice d in _devices) d.id: d.isTransmitEnabled,
    };

    _devices
      ..clear()
      ..addAll(
        queried.map(
          (PeripheralDevice d) => d.copyWith(
            isTransmitEnabled: previousToggleState[d.id] ?? d.isTransmitEnabled,
          ),
        ),
      );
    notifyListeners();
  }

  /// Ativa ou desativa a transmissão de um periférico específico.
  void setPeripheralTransmitEnabled(String deviceId, bool enabled) {
    final int idx = _devices.indexWhere((PeripheralDevice d) => d.id == deviceId);
    if (idx < 0) return;
    _devices[idx] = _devices[idx].copyWith(isTransmitEnabled: enabled);
    notifyListeners();
  }

  /// Simula ou registra a conexão/desconexão física (hotplug) de um periférico.
  void setPeripheralConnectionState(String deviceId, bool connected) {
    final int idx = _devices.indexWhere((PeripheralDevice d) => d.id == deviceId);
    if (idx < 0) return;
    _devices[idx] = _devices[idx].copyWith(
      isConnected: connected,
      lastActivity: DateTime.now(),
    );
    if (!connected) {
      // Se um periférico foi desconectado durante o uso, libera teclas/botões retidos por segurança
      releaseAllLocalHeldStates();
    }
    notifyListeners();
  }

  void setStickDeadzone(double value) {
    _stickDeadzone = value.clamp(0.0, 0.35);
    notifyListeners();
  }

  void setEmulateMouseWithGamepadOnHost(bool enabled) {
    _emulateMouseWithGamepadOnHost = enabled;
    notifyListeners();
  }

  bool isCategoryEnabled(PeripheralCategory category) {
    return _devices.any(
      (PeripheralDevice d) => d.category == category && d.isConnected && d.isTransmitEnabled,
    );
  }

  /// Captura e transmite um evento de Mouse (com throttling inteligente de 60 Hz apenas para Move).
  MouseInputCommand? handleLocalMouseEvent({
    required MouseActionType action,
    required double normX,
    required double normY,
    int wheelDeltaY = 0,
    int wheelDeltaX = 0,
  }) {
    if (!isCategoryEnabled(PeripheralCategory.mouse)) return null;

    if (action == MouseActionType.move) {
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastMouseMoveEpochMs < 15) {
        return null;
      }
      _lastMouseMoveEpochMs = nowMs;
    } else {
      _updateMouseButtonsBitmask(action);
    }

    final int seq = (++_sequenceCounter) & 0xffff;
    final MouseInputCommand cmd = MouseInputCommand(
      action: action,
      normX: normX.clamp(0.0, 1.0),
      normY: normY.clamp(0.0, 1.0),
      wheelDeltaY: wheelDeltaY,
      wheelDeltaX: wheelDeltaX,
      buttonsMask: _pressedMouseButtonsMask,
      sequenceNumber: seq,
    );

    _lastMouseCommand = cmd;
    _markCategoryActivity(PeripheralCategory.mouse);
    onMouseCommandReady?.call(cmd);
    notifyListeners();
    return cmd;
  }

  void _updateMouseButtonsBitmask(MouseActionType action) {
    switch (action) {
      case MouseActionType.leftDown:
        _pressedMouseButtonsMask |= 0x01;
        break;
      case MouseActionType.leftUp:
        _pressedMouseButtonsMask &= ~0x01;
        break;
      case MouseActionType.rightDown:
        _pressedMouseButtonsMask |= 0x02;
        break;
      case MouseActionType.rightUp:
        _pressedMouseButtonsMask &= ~0x02;
        break;
      case MouseActionType.middleDown:
        _pressedMouseButtonsMask |= 0x04;
        break;
      case MouseActionType.middleUp:
        _pressedMouseButtonsMask &= ~0x04;
        break;
      case MouseActionType.xButton1Down:
        _pressedMouseButtonsMask |= 0x08;
        break;
      case MouseActionType.xButton1Up:
        _pressedMouseButtonsMask &= ~0x08;
        break;
      case MouseActionType.xButton2Down:
        _pressedMouseButtonsMask |= 0x10;
        break;
      case MouseActionType.xButton2Up:
        _pressedMouseButtonsMask &= ~0x10;
        break;
      default:
        break;
    }
  }

  /// Captura e transmite um evento de Teclado (`KeyEvent` do Flutter) com ScanCode e ExtendedKey.
  KeyInputCommand? handleFlutterKeyEvent(KeyEvent event) {
    if (!isCategoryEnabled(PeripheralCategory.keyboard)) return null;
    final bool isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final bool isUp = event is KeyUpEvent;
    if (!isDown && !isUp) return null;

    final MappedKeyDescriptor mapped = KeyMappingTable.mapFlutterKeyEvent(event);
    return emitVirtualKey(
      winVirtualKey: mapped.winVirtualKey,
      hardwareScanCode: mapped.hardwareScanCode,
      isExtendedKey: mapped.isExtendedKey,
      usbHidUsageId: mapped.usbHidUsageId,
      isDown: isDown,
      label: mapped.label,
    );
  }

  /// Emite diretamente uma tecla mapeada (útil para atalhos como Ctrl+Alt+Del, teclado virtual Android e testes).
  KeyInputCommand? emitVirtualKey({
    required int winVirtualKey,
    int? hardwareScanCode,
    bool? isExtendedKey,
    int usbHidUsageId = 0,
    required bool isDown,
    String? label,
  }) {
    if (!isCategoryEnabled(PeripheralCategory.keyboard)) return null;

    final MappedKeyDescriptor fallback = KeyMappingTable.fromWinVirtualKey(winVirtualKey);
    final int resolvedScan = hardwareScanCode ?? fallback.hardwareScanCode;
    final bool resolvedExt = isExtendedKey ?? fallback.isExtendedKey;
    final String resolvedLabel = label ?? fallback.label;

    if (isDown) {
      _pressedVirtualKeys.add(winVirtualKey);
    } else {
      _pressedVirtualKeys.remove(winVirtualKey);
    }

    int mods = 0;
    if (_pressedVirtualKeys.contains(0x10) ||
        _pressedVirtualKeys.contains(0xA0) ||
        _pressedVirtualKeys.contains(0xA1)) {
      mods |= 0x01; // Shift
    }
    if (_pressedVirtualKeys.contains(0x11) ||
        _pressedVirtualKeys.contains(0xA2) ||
        _pressedVirtualKeys.contains(0xA3)) {
      mods |= 0x02; // Ctrl
    }
    if (_pressedVirtualKeys.contains(0x12) ||
        _pressedVirtualKeys.contains(0xA4) ||
        _pressedVirtualKeys.contains(0xA5)) {
      mods |= 0x04; // Alt
    }
    if (_pressedVirtualKeys.contains(0x5B) || _pressedVirtualKeys.contains(0x5C)) {
      mods |= 0x08; // Meta/Win
    }

    final int seq = (++_sequenceCounter) & 0xff;
    final KeyInputCommand cmd = KeyInputCommand(
      winVirtualKey: winVirtualKey,
      isDown: isDown,
      hardwareScanCode: resolvedScan,
      isExtendedKey: resolvedExt,
      usbHidUsageId: usbHidUsageId != 0 ? usbHidUsageId : fallback.usbHidUsageId,
      modifiersMask: mods,
      sequenceNumber: seq,
    );

    _lastKeyboardEventSummary =
        '$resolvedLabel (VK: 0x${winVirtualKey.toRadixString(16).toUpperCase()}, '
        'Scan: 0x${resolvedScan.toRadixString(16).toUpperCase()}, '
        '${isDown ? "DOWN" : "UP"}${resolvedExt ? ", EXT" : ""})';

    _markCategoryActivity(PeripheralCategory.keyboard);
    onKeyCommandReady?.call(cmd);
    notifyListeners();
    return cmd;
  }

  /// Atualiza e transmite o estado de um Controle de Videogame (Gamepad) ou Joystick,
  /// aplicando filtro de deadzone nos eixos analógicos.
  GamepadInputCommand? updateGamepadState({
    int controllerIndex = 0,
    int? buttonsMask,
    double? leftTrigger,
    double? rightTrigger,
    double? leftStickX,
    double? leftStickY,
    double? rightStickX,
    double? rightStickY,
    double? rudderAxisZ,
  }) {
    if (!isCategoryEnabled(PeripheralCategory.gamepad) &&
        !isCategoryEnabled(PeripheralCategory.joystick)) {
      return null;
    }

    final int seq = (++_sequenceCounter) & 0xffff;
    final GamepadInputCommand next = _currentGamepadState.copyWith(
      controllerIndex: controllerIndex,
      isConnected: true,
      buttonsMask: buttonsMask ?? _currentGamepadState.buttonsMask,
      leftTrigger: (leftTrigger ?? _currentGamepadState.leftTrigger).clamp(0.0, 1.0),
      rightTrigger: (rightTrigger ?? _currentGamepadState.rightTrigger).clamp(0.0, 1.0),
      leftStickX: NativePlatformBridge.applyDeadzone(
        leftStickX ?? _currentGamepadState.leftStickX,
        _stickDeadzone,
      ),
      leftStickY: NativePlatformBridge.applyDeadzone(
        leftStickY ?? _currentGamepadState.leftStickY,
        _stickDeadzone,
      ),
      rightStickX: NativePlatformBridge.applyDeadzone(
        rightStickX ?? _currentGamepadState.rightStickX,
        _stickDeadzone,
      ),
      rightStickY: NativePlatformBridge.applyDeadzone(
        rightStickY ?? _currentGamepadState.rightStickY,
        _stickDeadzone,
      ),
      rudderAxisZ: NativePlatformBridge.applyDeadzone(
        rudderAxisZ ?? _currentGamepadState.rudderAxisZ,
        _stickDeadzone,
      ),
      sequenceNumber: seq,
    );

    _currentGamepadState = next;
    _markCategoryActivity(PeripheralCategory.gamepad);
    onGamepadCommandReady?.call(next);
    notifyListeners();
    return next;
  }

  Future<void> _pollNativeGamepads() async {
    final GamepadInputCommand? polled = await _bridge.pollNativeGamepadState(0);
    if (polled == null) return;
    if (polled.buttonsMask != _currentGamepadState.buttonsMask ||
        (polled.leftStickX - _currentGamepadState.leftStickX).abs() > 0.02 ||
        (polled.leftStickY - _currentGamepadState.leftStickY).abs() > 0.02 ||
        (polled.rightStickX - _currentGamepadState.rightStickX).abs() > 0.02 ||
        (polled.rightStickY - _currentGamepadState.rightStickY).abs() > 0.02 ||
        (polled.leftTrigger - _currentGamepadState.leftTrigger).abs() > 0.02 ||
        (polled.rightTrigger - _currentGamepadState.rightTrigger).abs() > 0.02) {
      updateGamepadState(
        controllerIndex: polled.controllerIndex,
        buttonsMask: polled.buttonsMask,
        leftTrigger: polled.leftTrigger,
        rightTrigger: polled.rightTrigger,
        leftStickX: polled.leftStickX,
        leftStickY: polled.leftStickY,
        rightStickX: polled.rightStickX,
        rightStickY: polled.rightStickY,
        rudderAxisZ: polled.rudderAxisZ,
      );
    }
  }

  /// Libera todas as teclas e botões retidos localmente e envia os respectivos pacotes UP.
  void releaseAllLocalHeldStates() {
    final List<int> heldKeys = _pressedVirtualKeys.toList();
    for (final int vk in heldKeys) {
      emitVirtualKey(winVirtualKey: vk, isDown: false);
    }
    _pressedVirtualKeys.clear();
    _pressedMouseButtonsMask = 0;
    _currentGamepadState = const GamepadInputCommand(controllerIndex: 0);
    notifyListeners();
  }

  void _markCategoryActivity(PeripheralCategory category) {
    for (int i = 0; i < _devices.length; i++) {
      if (_devices[i].category == category) {
        _devices[i] = _devices[i].copyWith(lastActivity: DateTime.now());
      }
    }
  }

  @override
  void dispose() {
    _gamepadPollingTimer?.cancel();
    _hotplugSubscription?.cancel();
    super.dispose();
  }
}
