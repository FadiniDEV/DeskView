# CHANGELOG — REENGENHARIA COMPLETA DO DESKVIEW PARA FLUTTER & DART

## [3.0.0] — 2026-11-16 — Reengenharia Completa e Migração para Flutter (Material Design 3)

### 1. Engenharia Reversa e Diagnóstico (REA & Ghidra)
- **Análise Estática Completa do Binário Original (`DeskView.exe`)**:
  - Inspecionado o executável original do commit `d6243d10cf420f8f37505c2d1259d86a0e9f23ab` (`SHA-256: c91116246b4ef128233f9dd0424a513e068f2bad05511f2f34a85109022a2598`, `79.360 bytes`, `MVID: 94160f5a-fe04-4c3d-85a7-1fa819d10c96`).
  - Mapeadas todas as `43 TypeDefs`, `287 MethodDefs`, `168 User Strings` e as `6` declarações P/Invoke de `user32.dll` (`SetProcessDPIAware`, `SetCursorPos`, `mouse_event`, `keybd_event`, `GetCursorInfo`, `DrawIcon`).
  - Preservado o arquivo `DeskView.exe` original intacto sem qualquer modificação destrutiva.

### 2. Reconstrução do Motor de Comunicação Multi-Rede (`lib/services/communication/`)
- **Cliente STUN RFC 5389 Nativo (`stun_client_service.dart`)**:
  - Implementada construção de `Binding Request (0x0001)` e decodificação de `XOR-MAPPED-ADDRESS (0x0020)` e `MAPPED-ADDRESS (0x0001)` sobre UDP, além de detecção automática de CGNAT (`100.64.0.0/10`) e NAT Simétrico.
- **Sinalização Global Assinada e Túnel Relay Criptografado (`global_signaling_service.dart` & `session_transport.dart`)**:
  - Assinatura `HMAC-SHA256` e validação de janela temporal anti-replay (2 minutos) em todos os pacotes `REQ`, `ACK` e `REJ`.
  - Implementado **`RelaySessionTransport`** (`deskview/v3/tunnel/<sessionId>/<c2h|h2c>`) como fallback automático quando a corrida de conexões diretas (`LAN` e `WAN P2P STUN`) sofre bloqueio por CGNAT, NAT Simétrico ou Firewall.
- **Criptografia de Ponta a Ponta na Sessão (`session_cipher.dart` & `packet_frame_io.dart`)**:
  - Implementação pura em Dart de `SHA-256`, `HMAC-SHA256` e cifragem autenticada por pacote (`sealPacket` / `openPacket`) com derivação de chave efêmera durante o Handshake.

### 3. Reconstrução do Subsistema de Periféricos: Mouse, Teclado, Gamepads e Joysticks (`lib/services/input/`)
- **Tabela Canônica de Mapeamento de Teclado (`key_mapping_table.dart`)**:
  - Tradução entre `PhysicalKeyboardKey` (USB HID Usage ID), `Win32 Virtual-Key (VK_*)`, `Hardware ScanCode Set 1` e flag `KEYEVENTF_EXTENDEDKEY`, corrigindo a falha de teclas de seta, navegação e jogos DirectX.
- **Suporte Completo a Controles de Videogame e Joysticks (`input_commands.dart` & `peripheral_manager_service.dart`)**:
  - Adicionado `PacketType.gamepadInput (24)` de 20 bytes com suporte a 16 botões (`A, B, X, Y, LB, RB, Start, Select, L3, R3, D-Pad, Guide`), 2 gatilhos analógicos (`LT, RT`) e 5 eixos analógicos (`LX, LY, RX, RY, Rudder Z`) com filtro de *deadzone* configurável.
  - Rastreamento de teclas/botões retidos com liberação automática (`releaseAllLocalHeldStates`) em caso de desconexão física do periférico (hotplug) ou encerramento da sessão.
- **Integrações Nativas Windows C++ e Android Kotlin (`windows/` & `android/`)**:
  - Windows (`deskview_native_plugin.cpp`): injeção atômica via `SendInput` (`MOUSEEVENTF_VIRTUALDESK` + `KEYEVENTF_SCANCODE`) e leitura de controles via `XInputGetState` (`xinput1_4.dll`).
  - Android (`DeskViewNativePlugin.kt` & `DeskViewAccessibilityService.kt`): detecção e hotplug via `InputManager` e injeção autorizada de gestos via `AccessibilityService.dispatchGesture`.

### 4. Nova Identidade Visual com Material Design 3 (`lib/core/theme/` & `lib/presentation/`)
- Implementado tema global Material Design 3 com fundo em cinza-azulado claro (`#E5ECF4`), cartões brancos contrastantes (`#FFFFFF`), contornos escuros bem definidos (`#1E293B`), cantos arredondados e verde vibrante (`#00D66C`) como cor de destaque.
- Layout responsivo adaptativo (`AdaptiveShellScreen`) alternando entre `NavigationRail` lateral no Windows Desktop e `NavigationBar` inferior no Android Mobile.
