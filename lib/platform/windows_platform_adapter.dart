import '../domain/entities/input_commands.dart';
import '../domain/entities/session_models.dart';
import 'native_platform_bridge.dart';

/// Adaptador específico de integração com o sistema operacional Windows:
/// - Injeção de Mouse via `SendInput` (`MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK`).
/// - Injeção de Teclado via `SendInput` (`KEYEVENTF_SCANCODE | KEYEVENTF_EXTENDEDKEY`).
/// - Leitura e emulação de Controles XInput (`XInputGetState` em `xinput1_4.dll`).
class WindowsPlatformAdapter {
  final NativePlatformBridge _bridge;

  const WindowsPlatformAdapter(this._bridge);

  Future<bool> executeMouseCommand(MouseInputCommand cmd, ScreenMetadata screen) {
    return _bridge.injectMouseCommand(cmd, screen);
  }

  Future<bool> executeKeyCommand(KeyInputCommand cmd) {
    return _bridge.injectKeyCommand(cmd);
  }

  Future<bool> executeGamepadCommand(GamepadInputCommand cmd) {
    return _bridge.injectGamepadCommand(cmd);
  }

  Future<void> releaseStuckKeysAndButtons() {
    return _bridge.releaseAllHeldInputs();
  }
}
