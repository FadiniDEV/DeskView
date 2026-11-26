# ARQUITETURA FLUTTER & MATERIAL DESIGN 3 (DESKVIEW)

## 1. Visão Geral da Arquitetura

A aplicação foi reconstruída do zero em **Flutter e Dart** seguindo os princípios de **Clean Architecture Modular** e **Separation of Concerns (SoC)**, garantindo desacoplamento total entre a camada visual (**Material Design 3**), as regras de domínio, o motor de rede híbrido e as integrações nativas de sistema operacional (**Windows C++** e **Android Kotlin** via *Platform Channels*).

```
lib/
├── main.dart                                   # Entry point e bootstrap de dependências
├── app.dart                                    # MaterialApp M3, Tema Global e Shell Responsivo
├── core/
│   ├── constants/
│   │   └── protocol_constants.dart             # Portas, tópicos MQTT, servidores STUN, limites e timeouts
│   ├── crypto/
│   │   └── session_cipher.dart                 # Criptografia autenticada, PBKDF2/HMAC-SHA256, Challenge-Response
│   ├── theme/
│   │   ├── app_colors.dart                     # Paleta Visual (Fundo Cinza-Azulado Claro, Contornos Escuros, Verde Vibrante)
│   │   └── app_theme.dart                      # Configuração completa do Material Design 3 customizado
│   └── utils/
│       └── desk_id_formatter.dart              # Formatação "000 000 000", sanitização de caminhos e helpers binários
├── domain/
│   ├── entities/
│   │   ├── connection_candidate.dart           # Candidatos de rota (LAN, STUN srflx, Direct WAN, Relay Tunnel)
│   │   ├── desk_identity.dart                  # Identidade local (DeskID, Fingerprint, configurações e senha desassistida)
│   │   ├── input_commands.dart                 # Comandos canônicos de Mouse, Teclado (ScanCode/HID) e Gamepad/Joystick
│   │   ├── peer_device.dart                    # Entidade de dispositivo remoto descoberto ou salvo
│   │   ├── peripheral_device.dart              # Entidade de periférico local ou remoto (Mouse, Teclado, Gamepad, Joystick)
│   │   └── session_models.dart                 # Metadados de tela, Dirty Tiles, Permissões, Chat, Arquivos e Telemetria
│   └── repositories/
│       └── identity_repository.dart            # Contrato de persistência de identidade, favoritos e logins salvos
├── data/
│   └── repositories/
│       └── local_identity_repository.dart      # Implementação de persistência segura compatível com deskview.conf
├── platform/
│   ├── native_platform_bridge.dart             # Abstração unificada de Platform Channels (MethodChannel & EventChannel)
│   ├── windows_platform_adapter.dart           # Adaptador específico para recursos nativos do Windows (SendInput, XInput, GDI)
│   └── android_platform_adapter.dart           # Adaptador específico para Android (AccessibilityService, MediaProjection, InputManager)
├── services/
│   ├── codec/
│   │   └── desk_rt_tile_codec.dart             # Codificador/Decodificador de Dirty Tiles 8x6 com hash FNV-1a em Dart
│   ├── communication/
│   │   ├── packet_frame_io.dart                # Serialização/Deserialização binária compatível e estendida (v1/v3)
│   │   ├── stun_client_service.dart            # Cliente STUN RFC 5389 nativo em Dart para descoberta de IP:Porta mapeados no NAT
│   │   ├── lan_discovery_service.dart          # Descoberta automática UDP Broadcast (Porta 50001)
│   │   ├── global_signaling_service.dart       # Cliente MQTT 3.1.1 assinado com HMAC-SHA256 e transporte Relay embutido
│   │   ├── session_transport.dart              # Abstração de transporte (DirectTcpSessionTransport & RelaySessionTransport)
│   │   ├── host_session_server.dart            # Servidor Host multi-cliente com validação de permissões e captura DeskRT
│   │   └── connection_orchestrator.dart        # Orquestrador de rotas (LAN -> P2P NAT/STUN -> Relay Fallback Automático)
│   └── input/
│       ├── key_mapping_table.dart              # Tabela de tradução USB HID <-> Win32 VK <-> ScanCode Set 1 <-> Android KeyCode
│       └── peripheral_manager_service.dart     # Detecção, hotplug, polling de Gamepad/Joystick e coalescência de entrada
└── presentation/
    ├── controllers/
    │   └── app_controller.dart                 # Gerenciamento de estado reativo centralizando Sessões, Rede e Periféricos
    ├── widgets/
    │   ├── neo_card.dart                       # Card M3 com contorno escuro definido, cantos arredondados e sombra estruturada
    │   ├── vibrant_button.dart                 # Botão de destaque (Verde Vibrante / Primário / Secundário com contorno nítido)
    │   ├── status_badge.dart                   # Indicadores visuais de rota (LAN, P2P STUN, Relay, Permissões, Periféricos)
    │   ├── peripheral_status_panel.dart        # Painel interativo de diagnóstico e teste de Mouse, Teclado e Controles/Joysticks
    │   └── accept_session_dialog.dart          # Modal de aprovação de conexão com toggles de permissão granulares
    └── screens/
        ├── adaptive_shell_screen.dart          # Shell responsivo: NavigationRail (Windows Desktop) / NavigationBar (Android Mobile)
        ├── home_dashboard_screen.dart          # Tela Inicial: Esta Área de Trabalho, Conectar a Outro Dispositivo, Recentes/Favoritos
        ├── remote_session_screen.dart          # Visualizador de Sessão Remota (Canvas DeskRT, Toolbar, Chat, Arquivos, Gamepad HUD)
        ├── peripherals_hub_screen.dart         # Central de Periféricos: Detecção em tempo real, visualização de eixos/botões e mapeamento
        └── network_security_screen.dart        # Diagnóstico de Rede (STUN/NAT/MQTT/LAN) e Configurações de Segurança Desassistida
```

---

## 2. Identidade Visual e Material Design 3 Customizado

Seguindo rigorosamente as diretrizes estéticas da Etapa 3:
- **Superfície de Fundo (`ScaffoldBackground`)**: Cinza-azulado claro suave (`#E6ECF5`), proporcionando conforto visual e alto contraste com os cartões de conteúdo.
- **Áreas de Conteúdo e Painéis (`Surface` / `Card`)**: Branco puro (`#FFFFFF`) e cinza-gelo estruturado (`#F8FAFC`).
- **Contornos Escuros Bem Definidos**: Todos os cartões, campos de entrada, badges e botões possuem borda sólida de `1.5px` a `2.0px` em tom ardósia escuro (`#1E293B`), conferindo precisão visual e hierarquia imediata.
- **Cor de Destaque Principal (Verde Vibrante)**: `#10B981` (Esmeralda Vibrante) e `#00E676` (Verde Ação) aplicados em botões principais de conexão, indicadores de sessão ativa, badges de periféricos conectados e estados de aprovação.
- **Tipografia Forte e Hierarquizada**: Títulos em peso `w800` (`#0F172A`), subtítulos técnicos em peso `w600` (`#334155`) e códigos `DeskID` / telemetria em fonte monoespaçada de alto destaque.

---

## 3. Responsividade Multiplataforma (Windows Desktop vs. Android Mobile)

1. **Layout Desktop (Windows — largura `>= 900px`)**:
   - **Navegação Lateral (`NavigationRail`)** fixa à esquerda com acesso instantâneo a: *Painel Principal*, *Sessões Ativas (Abas)*, *Periféricos & Controles* e *Rede & Segurança*.
   - **Grid 2 Colunas Balanceado (50% / 50%)** na tela inicial para os cartões *"Esta Área de Trabalho"* e *"Conectar a Outro Dispositivo"*, mantendo os cartões de *Sessões Recentes e Favoritos* logo abaixo em `Wrap`/`Grid` adaptativo.
   - **Barra Superior de Sessão Completa** com seletores de monitor, qualidade, controle de entrada, envio de arquivos, sincronização de área de transferência e painel lateral retrátil de Chat e Telemetria.

2. **Layout Mobile (Android — largura `< 900px`)**:
   - **Barra de Navegação Inferior (`NavigationBar`)** padrão Material 3 para fácil alcance com o polegar.
   - **Empilhamento Vertical Inteligente** dos cartões principais sem cortes laterais.
   - **Modo Operador Mobile na Sessão Remota**:
     - Suporte a gestos de toque na tela remota (toque simples = clique esquerdo, toque longo = clique direito, pinça = zoom/pan, arrasto com dois dedos = scroll).
     - **Overlay de Gamepad Virtual Opcional** na tela para quando o celular Android não tiver um controle Bluetooth físico conectado, além de suporte nativo automático a controles Bluetooth/USB OTG conectados ao aparelho.
     - **Banner de Permissão Android (`AccessibilityService` & `MediaProjection`)** integrado quando o Android atua como Host.

---

## 4. Integrações Nativas via Platform Channels

O canal `com.autoral.deskview/native` (MethodChannel) e `com.autoral.deskview/peripherals_stream` (EventChannel) conectam o código Dart às implementações nativas incluídas no projeto:
- **Windows (`windows/runner/deskview_native_plugin.cpp` & `.h`)**:
  - Captura rápida de tela multimonitor via `GetDC` / `BitBlt` / `GetDIBits`.
  - Injeção atômica de mouse e teclado via `SendInput` (com `MOUSEEVENTF_VIRTUALDESK` e `KEYEVENTF_SCANCODE`).
  - Leitura nativa de até 4 controles de videogame via `XInputGetState` (`xinput1_4.dll`) e enumeração de periféricos conectados via `GetRawInputDeviceList`.
- **Android (`android/app/src/main/kotlin/com/autoral/deskview/DeskViewNativePlugin.kt` & `DeskViewAccessibilityService.kt`)**:
  - Enumeração e escuta de hotplug de mouses, teclados, gamepads e joysticks via `android.hardware.input.InputManager`.
  - Injeção autorizada de toques, swipes e ações globais via `AccessibilityService.dispatchGesture`.
  - Captura de tela via `MediaProjectionManager` quando o usuário autoriza o compartilhamento da tela do Android.
