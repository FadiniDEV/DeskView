import '../domain/entities/input_commands.dart';
import '../domain/entities/session_models.dart';
import 'native_platform_bridge.dart';

/// Adaptador específico de integração com o sistema operacional Android:
/// - Injeção autorizada de toques, cliques e swipes via `DeskViewAccessibilityService` (`dispatchGesture`).
/// - Ações globais do sistema Android (`GLOBAL_ACTION_BACK`, `GLOBAL_ACTION_HOME`, `GLOBAL_ACTION_RECENTS`).
/// - Captura de tela mediante autorização explícita do usuário via `MediaProjectionManager`.
/// - Detecção de mouses OTG/Bluetooth, teclados e controles de videogame via `InputManager`.
class AndroidPlatformAdapter {
  final NativePlatformBridge _bridge;

  const AndroidPlatformAdapter(this._bridge);

  bool get isAccessibilityEnabled => _bridge.isAndroidAccessibilityEnabled;
  bool get isMediaProjectionGranted => _bridge.isAndroidMediaProjectionAuthorized;

  Future<bool> requestAccessibilityServiceAuthorization() {
    return _bridge.requestAndroidAccessibilityPermission();
  }

  Future<bool> requestScreenCaptureAuthorization() {
    return _bridge.requestAndroidMediaProjectionPermission();
  }

  Future<bool> dispatchGestureFromMouseCommand(
    MouseInputCommand cmd,
    ScreenMetadata screen,
  ) {
    return _bridge.injectMouseCommand(cmd, screen);
  }
}
