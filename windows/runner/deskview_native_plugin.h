#ifndef FLUTTER_RUNNER_DESKVIEW_NATIVE_PLUGIN_H_
#define FLUTTER_RUNNER_DESKVIEW_NATIVE_PLUGIN_H_

#include <windows.h>
#include <xinput.h>
#include <vector>
#include <string>
#include <cstdint>

namespace deskview_native {

struct MonitorDescriptor {
  int index;
  int left;
  int top;
  int width;
  int height;
  bool is_primary;
};

struct GamepadSnapshot {
  int controller_index;
  bool is_connected;
  uint16_t buttons_mask;
  double left_trigger;
  double right_trigger;
  double left_stick_x;
  double left_stick_y;
  double right_stick_x;
  double right_stick_y;
};

class DeskViewWindowsInputEngine {
 public:
  // Enumera todos os monitores ativos usando EnumDisplayMonitors
  static std::vector<MonitorDescriptor> EnumerateMonitors();

  // Injeta movimento, cliques (5 botões) e scroll (vertical/horizontal) via Win32 SendInput
  static bool InjectMouseEvent(int action, int abs_x, int abs_y, int wheel_y, int wheel_x);

  // Injeta tecla com Virtual-Key + Hardware ScanCode Set 1 + flag KEYEVENTF_EXTENDEDKEY via SendInput
  static bool InjectKeyboardEvent(uint16_t virtual_key,
                                  uint16_t hardware_scan_code,
                                  bool is_down,
                                  bool is_extended_key);

  // Libera todas as teclas modificadoras (Ctrl, Alt, Shift, Win) e botões de mouse retidos
  static void ReleaseAllHeldInputs();

  // Lê o estado de um controle de videogame (0..3) via XInputGetState (xinput1_4.dll)
  static GamepadSnapshot PollXInputController(int controller_index);
};

}  // namespace deskview_native

#endif  // FLUTTER_RUNNER_DESKVIEW_NATIVE_PLUGIN_H_
