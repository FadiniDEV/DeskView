import 'package:flutter/services.dart';

/// Resultado do mapeamento completo de uma tecla física/lógica para injeção remota.
class MappedKeyDescriptor {
  final int winVirtualKey;
  final int hardwareScanCode;
  final bool isExtendedKey;
  final int usbHidUsageId;
  final String label;

  const MappedKeyDescriptor({
    required this.winVirtualKey,
    required this.hardwareScanCode,
    this.isExtendedKey = false,
    required this.usbHidUsageId,
    required this.label,
  });
}

/// Tabela canônica de mapeamento entre `PhysicalKeyboardKey` / `LogicalKeyboardKey` (Flutter),
/// `Win32 Virtual-Key (VK_*)`, `Hardware ScanCode Set 1` e flag `KEYEVENTF_EXTENDEDKEY`.
class KeyMappingTable {
  KeyMappingTable._();

  static const Map<int, ({int vk, int scan, bool ext, String label})> _hidToWin32 =
      <int, ({int vk, int scan, bool ext, String label})>{
    // Letras A..Z (USB HID 0x00070004 .. 0x0007001D)
    0x00070004: (vk: 0x41, scan: 0x1E, ext: false, label: 'A'),
    0x00070005: (vk: 0x42, scan: 0x30, ext: false, label: 'B'),
    0x00070006: (vk: 0x43, scan: 0x2E, ext: false, label: 'C'),
    0x00070007: (vk: 0x44, scan: 0x20, ext: false, label: 'D'),
    0x00070008: (vk: 0x45, scan: 0x12, ext: false, label: 'E'),
    0x00070009: (vk: 0x46, scan: 0x21, ext: false, label: 'F'),
    0x0007000A: (vk: 0x47, scan: 0x22, ext: false, label: 'G'),
    0x0007000B: (vk: 0x48, scan: 0x23, ext: false, label: 'H'),
    0x0007000C: (vk: 0x49, scan: 0x17, ext: false, label: 'I'),
    0x0007000D: (vk: 0x4A, scan: 0x24, ext: false, label: 'J'),
    0x0007000E: (vk: 0x4B, scan: 0x25, ext: false, label: 'K'),
    0x0007000F: (vk: 0x4C, scan: 0x26, ext: false, label: 'L'),
    0x00070010: (vk: 0x4D, scan: 0x32, ext: false, label: 'M'),
    0x00070011: (vk: 0x4E, scan: 0x31, ext: false, label: 'N'),
    0x00070012: (vk: 0x4F, scan: 0x18, ext: false, label: 'O'),
    0x00070013: (vk: 0x50, scan: 0x19, ext: false, label: 'P'),
    0x00070014: (vk: 0x51, scan: 0x10, ext: false, label: 'Q'),
    0x00070015: (vk: 0x52, scan: 0x13, ext: false, label: 'R'),
    0x00070016: (vk: 0x53, scan: 0x1F, ext: false, label: 'S'),
    0x00070017: (vk: 0x54, scan: 0x14, ext: false, label: 'T'),
    0x00070018: (vk: 0x55, scan: 0x16, ext: false, label: 'U'),
    0x00070019: (vk: 0x56, scan: 0x2F, ext: false, label: 'V'),
    0x0007001A: (vk: 0x57, scan: 0x11, ext: false, label: 'W'),
    0x0007001B: (vk: 0x58, scan: 0x2D, ext: false, label: 'X'),
    0x0007001C: (vk: 0x59, scan: 0x15, ext: false, label: 'Y'),
    0x0007001D: (vk: 0x5A, scan: 0x2C, ext: false, label: 'Z'),

    // Dígitos 1..9 e 0
    0x0007001E: (vk: 0x31, scan: 0x02, ext: false, label: '1'),
    0x0007001F: (vk: 0x32, scan: 0x03, ext: false, label: '2'),
    0x00070020: (vk: 0x33, scan: 0x04, ext: false, label: '3'),
    0x00070021: (vk: 0x34, scan: 0x05, ext: false, label: '4'),
    0x00070022: (vk: 0x35, scan: 0x06, ext: false, label: '5'),
    0x00070023: (vk: 0x36, scan: 0x07, ext: false, label: '6'),
    0x00070024: (vk: 0x37, scan: 0x08, ext: false, label: '7'),
    0x00070025: (vk: 0x38, scan: 0x09, ext: false, label: '8'),
    0x00070026: (vk: 0x39, scan: 0x0A, ext: false, label: '9'),
    0x00070027: (vk: 0x30, scan: 0x0B, ext: false, label: '0'),

    // Controle e edição
    0x00070028: (vk: 0x0D, scan: 0x1C, ext: false, label: 'Enter'),
    0x00070029: (vk: 0x1B, scan: 0x01, ext: false, label: 'Escape'),
    0x0007002A: (vk: 0x08, scan: 0x0E, ext: false, label: 'Backspace'),
    0x0007002B: (vk: 0x09, scan: 0x0F, ext: false, label: 'Tab'),
    0x0007002C: (vk: 0x20, scan: 0x39, ext: false, label: 'Space'),

    // Teclas de Função F1..F12
    0x0007003A: (vk: 0x70, scan: 0x3B, ext: false, label: 'F1'),
    0x0007003B: (vk: 0x71, scan: 0x3C, ext: false, label: 'F2'),
    0x0007003C: (vk: 0x72, scan: 0x3D, ext: false, label: 'F3'),
    0x0007003D: (vk: 0x73, scan: 0x3E, ext: false, label: 'F4'),
    0x0007003E: (vk: 0x74, scan: 0x3F, ext: false, label: 'F5'),
    0x0007003F: (vk: 0x75, scan: 0x40, ext: false, label: 'F6'),
    0x00070040: (vk: 0x76, scan: 0x41, ext: false, label: 'F7'),
    0x00070041: (vk: 0x77, scan: 0x42, ext: false, label: 'F8'),
    0x00070042: (vk: 0x78, scan: 0x43, ext: false, label: 'F9'),
    0x00070043: (vk: 0x79, scan: 0x44, ext: false, label: 'F10'),
    0x00070044: (vk: 0x7A, scan: 0x57, ext: false, label: 'F11'),
    0x00070045: (vk: 0x7B, scan: 0x58, ext: false, label: 'F12'),

    // Navegação (EXTENDED KEYS — Críticas para funcionamento em aplicações e jogos DirectX)
    0x00070049: (vk: 0x2D, scan: 0x52, ext: true, label: 'Insert'),
    0x0007004A: (vk: 0x24, scan: 0x47, ext: true, label: 'Home'),
    0x0007004B: (vk: 0x21, scan: 0x49, ext: true, label: 'PageUp'),
    0x0007004C: (vk: 0x2E, scan: 0x53, ext: true, label: 'Delete'),
    0x0007004D: (vk: 0x23, scan: 0x4F, ext: true, label: 'End'),
    0x0007004E: (vk: 0x22, scan: 0x51, ext: true, label: 'PageDown'),
    0x0007004F: (vk: 0x27, scan: 0x4D, ext: true, label: 'ArrowRight'),
    0x00070050: (vk: 0x25, scan: 0x4B, ext: true, label: 'ArrowLeft'),
    0x00070051: (vk: 0x28, scan: 0x50, ext: true, label: 'ArrowDown'),
    0x00070052: (vk: 0x26, scan: 0x48, ext: true, label: 'ArrowUp'),

    // Modificadores
    0x000700E0: (vk: 0xA2, scan: 0x1D, ext: false, label: 'LeftCtrl'),
    0x000700E1: (vk: 0xA0, scan: 0x2A, ext: false, label: 'LeftShift'),
    0x000700E2: (vk: 0xA4, scan: 0x38, ext: false, label: 'LeftAlt'),
    0x000700E3: (vk: 0x5B, scan: 0x5B, ext: true, label: 'LeftWin'),
    0x000700E4: (vk: 0xA3, scan: 0x1D, ext: true, label: 'RightCtrl'),
    0x000700E5: (vk: 0xA1, scan: 0x36, ext: false, label: 'RightShift'),
    0x000700E6: (vk: 0xA5, scan: 0x38, ext: true, label: 'RightAlt'),
    0x000700E7: (vk: 0x5C, scan: 0x5C, ext: true, label: 'RightWin'),
  };

  /// Converte um evento de teclado do Flutter (`KeyEvent`) em um [MappedKeyDescriptor] completo.
  static MappedKeyDescriptor mapFlutterKeyEvent(KeyEvent event) {
    final int hidUsage = event.physicalKey.usbHidUsage;
    final ({int vk, int scan, bool ext, String label})? direct = _hidToWin32[hidUsage];
    if (direct != null) {
      return MappedKeyDescriptor(
        winVirtualKey: direct.vk,
        hardwareScanCode: direct.scan,
        isExtendedKey: direct.ext,
        usbHidUsageId: hidUsage,
        label: direct.label,
      );
    }

    // Fallback por LogicalKeyboardKey
    final int keyId = event.logicalKey.keyId;
    if (keyId >= 0x61 && keyId <= 0x7A) {
      final int upperVk = keyId - 0x20;
      return MappedKeyDescriptor(
        winVirtualKey: upperVk,
        hardwareScanCode: 0,
        isExtendedKey: false,
        usbHidUsageId: hidUsage,
        label: String.fromCharCode(upperVk),
      );
    }

    return MappedKeyDescriptor(
      winVirtualKey: keyId & 0xff,
      hardwareScanCode: 0,
      isExtendedKey: false,
      usbHidUsageId: hidUsage,
      label: event.logicalKey.keyLabel.isNotEmpty ? event.logicalKey.keyLabel : 'Key',
    );
  }

  /// Resolve um código Virtual-Key Win32 (`VK_*`) para seu ScanCode Set 1 e flag ExtendedKey.
  static MappedKeyDescriptor fromWinVirtualKey(int vk) {
    for (final MapEntry<int, ({int vk, int scan, bool ext, String label})> entry
        in _hidToWin32.entries) {
      if (entry.value.vk == vk) {
        return MappedKeyDescriptor(
          winVirtualKey: entry.value.vk,
          hardwareScanCode: entry.value.scan,
          isExtendedKey: entry.value.ext,
          usbHidUsageId: entry.key,
          label: entry.value.label,
        );
      }
    }
    // Verifica códigos genéricos VK_CONTROL (0x11), VK_SHIFT (0x10), VK_MENU (0x12)
    switch (vk) {
      case 0x10:
        return const MappedKeyDescriptor(
          winVirtualKey: 0x10,
          hardwareScanCode: 0x2A,
          usbHidUsageId: 0x000700E1,
          label: 'Shift',
        );
      case 0x11:
        return const MappedKeyDescriptor(
          winVirtualKey: 0x11,
          hardwareScanCode: 0x1D,
          usbHidUsageId: 0x000700E0,
          label: 'Ctrl',
        );
      case 0x12:
        return const MappedKeyDescriptor(
          winVirtualKey: 0x12,
          hardwareScanCode: 0x38,
          usbHidUsageId: 0x000700E2,
          label: 'Alt',
        );
      default:
        return MappedKeyDescriptor(
          winVirtualKey: vk,
          hardwareScanCode: 0,
          usbHidUsageId: 0,
          label: 'VK_0x${vk.toRadixString(16).toUpperCase()}',
        );
    }
  }
}
