# DIAGNÓSTICO E RECONSTRUÇÃO DE DISPOSITIVOS DE ENTRADA (MOUSE, TECLADO, CONTROLES E JOYSTICKS)

## 1. Diagnóstico Técnico dos Problemas no Software Original (`DeskView.exe`)

A auditoria das fronteiras nativas (`inspect_managed_native_boundaries` — `ev_02445d63550715cb2f08a0c26fbe333623e9ccc40bf4cc04e194734562f6a6b2`) e da implementação de `RemoteSessionTabControl` e `HostClientWorker` identificou cinco falhas estruturais no tratamento de periféricos:

### 1.1. Ausência Total de Detecção e Enumeração de Dispositivos Conectados
- O executável original **não possui nenhum subsistema de detecção de periféricos**. Ele apenas escuta eventos genéricos de janela (`Control.MouseMove`, `Control.KeyDown`) sem saber se há um mouse físico, teclado externo, controle de videogame (Xbox/PlayStation/Generic Gamepad) ou joystick conectado.
- Não há escuta de hotplug (`WM_DEVICECHANGE` no Windows ou `InputManager.InputDeviceListener` no Android).

### 1.2. Inexistência de Suporte a Controles de Videogame e Joysticks
- O binário original importa apenas `user32.dll` (`SetCursorPos`, `mouse_event`, `keybd_event`).
- **Não há importação** de `xinput1_4.dll`, `xinput9_1_0.dll`, `hid.dll` ou `dinput8.dll`.
- O enum `PacketType` original possui apenas `MouseInput = 20` e `KeyInput = 21`, não existindo pacote para transmitir botões de controle (`A, B, X, Y, LB, RB, Start, Select, L3, R3, D-Pad`), gatilhos analógicos (`LT, RT`) ou eixos (`LeftStickX/Y`, `RightStickX/Y`).

### 1.3. Falhas na Captura e Injeção de Teclado (`keybd_event`)
1. **Truncamento de KeyCode para 8 bits**:
   - Em `RemoteSessionTabControl.cs`: `SendKeyPacket((byte)e.KeyValue, true)`. Qualquer código de tecla acima de `255` ou modificador composto é truncado.
2. **Ausência de Hardware ScanCode (`bScan = 0`) e `KEYEVENTF_EXTENDEDKEY`**:
   - Em `HostClientWorker.cs`: `NativeMethods.keybd_event(vk, 0, isDown ? 0u : NativeMethods.KEYEVENTF_KEYUP, UIntPtr.Zero)`.
   - Como `bScan` é sempre `0` e a flag `KEYEVENTF_EXTENDEDKEY` (`0x0001`) nunca é enviada:
     - Teclas de seta (`Left`, `Up`, `Right`, `Down`), `Insert`, `Delete`, `Home`, `End`, `PageUp`, `PageDown`, `Right Ctrl` e `Right Alt` falham ou são interpretadas como teclas do Numpad em diversas aplicações e jogos DirectX/OpenGL/Vulkan.
     - Aplicações que leem ScanCodes físicos via RawInput/DirectInput ignoram completamente os eventos gerados por `keybd_event(vk, 0, ...)`.
3. **Incompatibilidade de Códigos de Tecla Entre Plataformas (Windows vs. Android)**:
   - O Windows utiliza `Virtual-Key Codes` (`VK_*`), enquanto o Android utiliza `KeyEvent.KEYCODE_*` e o Flutter utiliza `PhysicalKeyboardKey` (baseado em USB HID Usage IDs) e `LogicalKeyboardKey`.

### 1.4. Limitações na Captura e Injeção de Mouse (`mouse_event`)
- O protocolo original suportava apenas 3 botões (Esquerdo, Direito, Meio) e Scroll Vertical (`action` 0 a 7).
- Botões laterais (`XButton1` / `Back`, `XButton2` / `Forward`) e Scroll Horizontal (`MouseWheelTilt`) eram descartados.
- `SetCursorPos` seguido de `mouse_event` realiza duas chamadas de sistema separadas em vez de uma transação atômica via `SendInput` com coordenadas normalizadas no Virtual Desktop (`MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK`).

---

## 2. Nova Arquitetura de Periféricos e Entrada Remota no Flutter

A nova arquitetura separa rigorosamente **4 estágios** independentes:

```
+------------------------+     +-------------------------+     +------------------------+     +--------------------------+
| 1. DETECÇÃO & CAPTURA  | --> | 2. PROTOCOLO CANÔNICO   | --> | 3. TRANSPORTE ORDENADO | --> | 4. INJEÇÃO NATIVA        |
| (Hardware & Hotplug)   |     | (HID / USB Usage Norm.) |     | (SeqNum + Coalescência)|     | (Platform Channels OS)   |
+------------------------+     +-------------------------+     +------------------------+     +--------------------------+
```

### 2.1. Estágio 1 — Detecção Ativa e Hotplug de Periféricos (`PeripheralManagerService`)
O sistema monitora em tempo real todos os dispositivos conectados e emite atualizações de estado (` connected`, `disconnected`, `activeInput`):
1. **Mouse**: Detecção de presença, contagem de botões, suporte a scroll vertical/horizontal e coordenadas normalizadas/relativas.
2. **Teclado**: Detecção de teclados físicos e virtuais (em dispositivos móveis Android), rastreamento do conjunto de teclas pressionadas (`_pressedKeys`) para liberação segura automática em caso de perda de foco ou queda de sessão.
3. **Controles de Videogame (Gamepads) e Joysticks**:
   - No **Windows** (via Platform Channel C++ `deskview/peripherals` + `XInput1_4` / `RawInput` / `winmm`): detecta até 4 controles XInput e joysticks HID simultâneos, lendo estado a `120 Hz` com *deadzone* configurável nos eixos analógicos (`LX`, `LY`, `RX`, `RY`) e gatilhos (`LT`, `RT`).
   - No **Android** (via Platform Channel Kotlin `InputManager.getInputDeviceIds()` + `InputDevice.SOURCE_GAMEPAD` / `SOURCE_JOYSTICK`): detecta controles Bluetooth/USB OTG (Xbox, DualSense, DualShock, 8BitDo, controles genéricos) e escuta `InputManager.InputDeviceListener` para hotplug instantâneo.

### 2.2. Estágio 2 — Protocolo Binário Canônico de Entrada (`PacketType` 20, 21, 24, 25)
Para garantir compatibilidade universal entre **Windows <-> Windows**, **Windows <-> Android** e **Android <-> Android**, os pacotes de entrada foram padronizados:

1. **`MouseInput` (`PacketType = 20`, 19 bytes)**:
   - `uint16 seqNum` (ordem de sequência).
   - `uint8 action` (`0`=Move, `1`=LeftDown, `2`=LeftUp, `3`=RightDown, `4`=RightUp, `5`=MiddleDown, `6`=MiddleUp, `7`=WheelVertical, `8`=WheelHorizontal, `9`=XButton1Down, `10`=XButton1Up, `11`=XButton2Down, `12`=XButton2Up).
   - `uint8 buttonsMask` (estado simultâneo de todos os 5 botões para evitar dessincronização).
   - `float32 normX` (`0.0..1.0`), `float32 normY` (`0.0..1.0`).
   - `int32 wheelDeltaX`, `int32 wheelDeltaY` (compactados em `int16` cada + `uint8 deviceId`).

2. **`KeyInput` (`PacketType = 21`, 12 bytes)**:
   - `uint16 seqNum`.
   - `uint8 isDown` (`1`=Pressed, `0`=Released).
   - `uint8 flags` (`bit0`=ExtendedKey, `bit1`=Repeat, `bit2`=Shift, `bit3`=Ctrl, `bit4`=Alt, `bit5`=Meta/Win).
   - `uint16 winVirtualKey` (`VK_*` mapeado automaticamente).
   - `uint16 hardwareScanCode` (ScanCode Set 1 para compatibilidade com jogos/DirectX).
   - `uint32 usbHidUsageId` (Código físico universal USB HID do Flutter `PhysicalKeyboardKey`).

3. **`GamepadInput` (`PacketType = 24`, 20 bytes)**:
   - `uint16 seqNum`.
   - `uint8 controllerIndex` (`0..3`).
   - `uint8 connected` (`1`/`0`).
   - `uint16 buttonsBitmask` (16 botões: `A/Cross`, `B/Circle`, `X/Square`, `Y/Triangle`, `LB/L1`, `RB/R1`, `Back/Select`, `Start/Options`, `LS/L3`, `RS/R3`, `DPadUp`, `DPadDown`, `DPadLeft`, `DPadRight`, `Guide/Home`, `Touchpad/Misc`).
   - `uint8 leftTrigger` (`0..255`), `uint8 rightTrigger` (`0..255`).
   - `int16 leftStickX` (`-32768..32767`), `int16 leftStickY` (`-32768..32767`).
   - `int16 rightStickX` (`-32768..32767`), `int16 rightStickY` (`-32768..32767`).
   - `int16 auxAxisZ` / `rudder` (suporte a eixo adicional de Joystick).

4. **`PeripheralInventorySync` (`PacketType = 25`)**:
   - Sincroniza a lista de periféricos detectados no operador com o host remoto.

### 2.3. Estágio 4 — Injeção Nativa e Limitações Reais de Plataforma

| Plataforma Alvo (Host) | Mecanismo Nativo Implementado | Capacidades e Limitações Técnicas Documentadas |
|---|---|---|
| **Windows (Host)** | **Win32 `SendInput`** (`INPUT_MOUSE` com `MOUSEEVENTF_ABSOLUTE \| MOUSEEVENTF_VIRTUALDESK`, `INPUT_KEYBOARD` com `KEYEVENTF_SCANCODE` e `KEYEVENTF_EXTENDEDKEY`) + Mapeamento de Gamepad (ViGEm / Simulação XInput-para-Teclado/Mouse configurável quando driver virtual não estiver instalado). | Controle global total da área de trabalho, aplicativos Win32/UWP e jogos DirectX. Telas protegidas do sistema (UAC Prompt / Ctrl+Alt+Del) exigem execução como Administrador/Serviço com `uiAccess=true`. |
| **Android (Host)** | **`AccessibilityService` (`dispatchGesture` + `performGlobalAction`)** e eventos dentro do app. | Por restrição de segurança do kernel Android (SELinux / InputDispatcher), aplicativos comuns **não podem** injetar `KeyEvent` arbitrários de baixo nível em outros apps via `/dev/uinput` sem Root. A solução oficial e suportada pelo Android é o **`DeskViewAccessibilityService`**, que injeta toques, cliques, arrastos (swipes/scrolls), ações globais (Home, Back, Recents, Notifications) e inserção de texto em campos editáveis (`ACTION_SET_TEXT`) após autorização explícita do usuário nas Configurações de Acessibilidade do Android. |
| **Android (Operador -> Windows Host)** | Captura de toque (convertido em cursor/cliques), teclado virtual/físico e controles Bluetooth/USB via `InputManager` / `Focus` do Flutter. | Permite que um celular ou tablet Android controle 100% do mouse, teclado e gamepad de um computador Windows remoto com baixa latência. |
