#include "deskview_native_plugin.h"
#include <cmath>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "xinput.lib")

namespace deskview_native {

namespace {
BOOL CALLBACK MonitorEnumProc(HMONITOR hMonitor,
                              HDC hdcMonitor,
                              LPRECT lprcMonitor,
                              LPARAM dwData) {
  auto* list = reinterpret_cast<std::vector<MonitorDescriptor>*>(dwData);
  MONITORINFO mi = {};
  mi.cbSize = sizeof(MONITORINFO);
  if (GetMonitorInfo(hMonitor, &mi)) {
    MonitorDescriptor desc;
    desc.index = static_cast<int>(list->size());
    desc.left = mi.rcMonitor.left;
    desc.top = mi.rcMonitor.top;
    desc.width = mi.rcMonitor.right - mi.rcMonitor.left;
    desc.height = mi.rcMonitor.bottom - mi.rcMonitor.top;
    desc.is_primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;
    list->push_back(desc);
  }
  return TRUE;
}
}  // namespace

std::vector<MonitorDescriptor> DeskViewWindowsInputEngine::EnumerateMonitors() {
  std::vector<MonitorDescriptor> monitors;
  EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc,
                      reinterpret_cast<LPARAM>(&monitors));
  return monitors;
}

bool DeskViewWindowsInputEngine::InjectMouseEvent(int action,
                                                  int abs_x,
                                                  int abs_y,
                                                  int wheel_y,
                                                  int wheel_x) {
  int v_left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  int v_top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  int v_width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  int v_height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (v_width <= 0) v_width = 1920;
  if (v_height <= 0) v_height = 1080;

  // Coordenadas normalizadas 0..65535 para MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK
  LONG norm_dx = static_cast<LONG>(((abs_x - v_left) * 65535LL) / v_width);
  LONG norm_dy = static_cast<LONG>(((abs_y - v_top) * 65535LL) / v_height);

  INPUT input = {};
  input.type = INPUT_MOUSE;
  input.mi.dx = norm_dx;
  input.mi.dy = norm_dy;
  input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;

  switch (action) {
    case 1: input.mi.dwFlags |= MOUSEEVENTF_LEFTDOWN; break;
    case 2: input.mi.dwFlags |= MOUSEEVENTF_LEFTUP; break;
    case 3: input.mi.dwFlags |= MOUSEEVENTF_RIGHTDOWN; break;
    case 4: input.mi.dwFlags |= MOUSEEVENTF_RIGHTUP; break;
    case 5: input.mi.dwFlags |= MOUSEEVENTF_MIDDLEDOWN; break;
    case 6: input.mi.dwFlags |= MOUSEEVENTF_MIDDLEUP; break;
    case 7:
      input.mi.dwFlags |= MOUSEEVENTF_WHEEL;
      input.mi.mouseData = static_cast<DWORD>(wheel_y);
      break;
    case 8:
      input.mi.dwFlags |= MOUSEEVENTF_HWHEEL;
      input.mi.mouseData = static_cast<DWORD>(wheel_x);
      break;
    case 9:
      input.mi.dwFlags |= MOUSEEVENTF_XDOWN;
      input.mi.mouseData = XBUTTON1;
      break;
    case 10:
      input.mi.dwFlags |= MOUSEEVENTF_XUP;
      input.mi.mouseData = XBUTTON1;
      break;
    case 11:
      input.mi.dwFlags |= MOUSEEVENTF_XDOWN;
      input.mi.mouseData = XBUTTON2;
      break;
    case 12:
      input.mi.dwFlags |= MOUSEEVENTF_XUP;
      input.mi.mouseData = XBUTTON2;
      break;
    default:
      break;
  }

  return SendInput(1, &input, sizeof(INPUT)) == 1;
}

bool DeskViewWindowsInputEngine::InjectKeyboardEvent(uint16_t virtual_key,
                                                     uint16_t hardware_scan_code,
                                                     bool is_down,
                                                     bool is_extended_key) {
  uint16_t scan = hardware_scan_code;
  if (scan == 0 && virtual_key != 0) {
    scan = static_cast<uint16_t>(MapVirtualKeyW(virtual_key, MAPVK_VK_TO_VSC));
  }

  INPUT input = {};
  input.type = INPUT_KEYBOARD;
  input.ki.wVk = virtual_key;
  input.ki.wScan = scan;
  input.ki.dwFlags = 0;

  if (scan != 0) {
    input.ki.dwFlags |= KEYEVENTF_SCANCODE;
  }
  if (is_extended_key) {
    input.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
  }
  if (!is_down) {
    input.ki.dwFlags |= KEYEVENTF_KEYUP;
  }

  return SendInput(1, &input, sizeof(INPUT)) == 1;
}

void DeskViewWindowsInputEngine::ReleaseAllHeldInputs() {
  const uint16_t modifier_vks[] = {VK_CONTROL, VK_LCONTROL, VK_RCONTROL,
                                   VK_MENU,    VK_LMENU,    VK_RMENU,
                                   VK_SHIFT,   VK_LSHIFT,   VK_RSHIFT,
                                   VK_LWIN,    VK_RWIN};
  for (uint16_t vk : modifier_vks) {
    InjectKeyboardEvent(vk, 0, false, (vk == VK_RCONTROL || vk == VK_RMENU || vk == VK_LWIN || vk == VK_RWIN));
  }

  INPUT mouse_up[3] = {};
  mouse_up[0].type = INPUT_MOUSE;
  mouse_up[0].mi.dwFlags = MOUSEEVENTF_LEFTUP;
  mouse_up[1].type = INPUT_MOUSE;
  mouse_up[1].mi.dwFlags = MOUSEEVENTF_RIGHTUP;
  mouse_up[2].type = INPUT_MOUSE;
  mouse_up[2].mi.dwFlags = MOUSEEVENTF_MIDDLEUP;
  SendInput(3, mouse_up, sizeof(INPUT));
}

GamepadSnapshot DeskViewWindowsInputEngine::PollXInputController(int controller_index) {
  GamepadSnapshot snap = {};
  snap.controller_index = controller_index;
  if (controller_index < 0 || controller_index > 3) {
    snap.is_connected = false;
    return snap;
  }

  XINPUT_STATE state = {};
  DWORD res = XInputGetState(static_cast<DWORD>(controller_index), &state);
  if (res != ERROR_SUCCESS) {
    snap.is_connected = false;
    return snap;
  }

  snap.is_connected = true;
  snap.buttons_mask = state.Gamepad.wButtons;
  snap.left_trigger = state.Gamepad.bLeftTrigger / 255.0;
  snap.right_trigger = state.Gamepad.bRightTrigger / 255.0;
  snap.left_stick_x = std::fmax(-1.0, state.Gamepad.sThumbLX / 32767.0);
  snap.left_stick_y = std::fmax(-1.0, state.Gamepad.sThumbLY / 32767.0);
  snap.right_stick_x = std::fmax(-1.0, state.Gamepad.sThumbRX / 32767.0);
  snap.right_stick_y = std::fmax(-1.0, state.Gamepad.sThumbRY / 32767.0);
  return snap;
}

}  // namespace deskview_native
