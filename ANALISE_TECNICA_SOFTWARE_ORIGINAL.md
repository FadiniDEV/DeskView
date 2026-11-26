# ANÁLISE TÉCNICA DO SOFTWARE ORIGINAL (DESKVIEW)

## 1. Identificação do Artefato e Repositório Analisados

A investigação técnica foi conduzida combinando a análise estática de binário via **REA (Reverse Engineer Anything / Análise de Metadados PE/CLI, CIL e Fronteiras Nativas P/Invoke)** sobre o executável original preservado no histórico do Git e a inspeção do repositório `https://github.com/FadiniDEV/DeskView.git`.

| Propriedade | Valor Observado no Executável Original (Git `HEAD`) | Valor Observado na Versão Auditada Local |
|---|---|---|
| **Caminho do Executável** | `C:\Users\conta\Documents\Programas Autorais\DeskView\DeskView.exe` | Backup preservado sem sobrescrever o original |
| **Commit Git Original** | `d6243d10cf420f8f37505c2d1259d86a0e9f23ab` | Working Tree (pré-restauração) |
| **SHA-256** | `c91116246b4ef128233f9dd0424a513e068f2bad05511f2f34a85109022a2598` | `dc6887439ba23c0bd5f0d4b9552c1afadbd09c37405663758e747f6d4324eaa3` |
| **Tamanho do Binário** | `79.360 bytes` | `87.552 bytes` |
| **Formato / Arquitetura** | PE32 (`x86`), CLI `.NET Framework v4.0.30319` (`IL-only`) | PE32 (`x86`), CLI `.NET Framework v4.0.30319` |
| **MVID (Module Version ID)** | `94160f5a-fe04-4c3d-85a7-1fa819d10c96` | `b1ee02a6-ab6f-4a4f-915f-79fe3bb16c37` |
| **Tabelas de Metadados** | `43 TypeDefs`, `236 Fields`, `287 MethodDefs`, `2.536 Call Edges`, `168 User Strings` | `44 TypeDefs`, `250 Fields`, `300 MethodDefs`, `2.796 Call Edges`, `206 User Strings` |
| **Módulos Nativos Importados** | `user32.dll` (6 importações P/Invoke) | `user32.dll` (6 importações P/Invoke) |

---

## 2. Descrição Geral do Funcionamento do Software

O **DeskView** é uma aplicação monolítica de acesso remoto e compartilhamento de área de trabalho (inspirada no modelo operacional do AnyDesk), onde uma mesma instância atua simultaneamente como:
1. **Host (Servidor de Área de Trabalho Remota)**: escuta conexões TCP de entrada, autentica operadores remotos (por aprovação interativa na tela ou senha de acesso não supervisionado), captura a tela em blocos (*dirty tiles*), transmite posição de cursor, recebe eventos de entrada (mouse/teclado), sincroniza área de transferência, recebe arquivos e processa mensagens de chat.
2. **Client / Operador (Visualizador de Sessão Remota)**: descobre computadores na LAN ou via sinalização MQTT, solicita conexão pelo código DeskID de 9 dígitos ou `IP:Porta`, renderiza os blocos de vídeo em abas (`TabControl`), captura eventos locais de mouse/teclado sobre o canvas e os envia ao host remoto.

---

## 3. Mapeamento Completo das Funcionalidades Existentes

A partir da tabela `TypeDef` e `MethodDef` extraída do binário (`ev_72916d99532986c07675ff544794f09a92b0962bba27a46e681724a5e214313b`), foram identificadas as seguintes funcionalidades reais:

1. **Identidade e Configuração Persistente (`DeskView.IdentityManager`)**:
   - Geração de código **DeskID de 9 dígitos** formatado como `000 000 000`.
   - Geração de `Fingerprint` SHA-256 de 64 caracteres hexadecimais.
   - Armazenamento em `%AppData%\DeskView\deskview.conf` e `%AppData%\DeskView\saved_logins.dat`.
   - Gerenciamento de **Senha de Acesso Desassistido** com salt aleatório e hash `HMAC-SHA256`.
   - Histórico de **Sessões Recentes** (até 12 entradas) e **Logins Salvos / Favoritos** (até 30 entradas para acesso em 1 clique).
   - Seleção dinâmica da porta de escuta TCP (padrão `7070`, ou via argumento de linha de comando `--port <numero>`).

2. **Descoberta Automática em Rede Local (`DeskView.LanDiscoveryService`)**:
   - Broadcast UDP periódico (a cada `3.000 ms`) na porta `50001` para `255.255.255.255` e `127.0.0.1`.
   - Formato do pacote de anúncio: `DESKVIEW_V1|<DeskId>|<MachineName>|<UserName>|<LocalIp>|<ListenPort>|<MonitorCount>`.
   - Resolução instantânea de `DeskId` de 9 dígitos para o par `IP:Porta` quando ambos os dispositivos estão na mesma sub-rede local.

3. **Sinalização Global e Descoberta de IP Público (`DeskView.GlobalRendezvousClient`)**:
   - Consulta de IP WAN via HTTP GET em `https://api.ipify.org`, `https://icanhazip.com` e `https://ifconfig.me/ip` com User-Agent `DeskView/7.0`.
   - Implementação própria de cliente **MQTT 3.1.1** sobre TCP na porta `1883` conectando aos brokers públicos `broker.hivemq.com` e `broker.emqx.io` (em failover).
   - Publicação de presença retida no tópico `deskview/v2/peers/<DeskId>` a cada `20.000 ms` e `PINGREQ` (`0xC0 0x00`) a cada `25.000 ms`.
   - Subscrição ao tópico `deskview/v2/signal/<DeskId>` para receber comandos `REQ` (pedido de conexão), `ACK` (conexão aceita) e `REJ` (conexão recusada).

4. **Servidor Host Multi-Sessão (`DeskView.DeskViewHostServer` & `DeskView.HostClientWorker`)**:
   - `TcpListener` escutando em `0.0.0.0:7070` (com fallback incremental de até 15 portas: `7070..7084`).
   - Handshake de autenticação (`HandshakeAuthRequest` -> `HandshakeAuthResponse`).
   - Três modos de autorização:
     1. Senha de acesso desassistido válida (`VerifyUnattendedPassword`).
     2. Conexão de loopback (`127.0.0.1` / `::1`).
     3. Modal interativo `AcceptSessionDialog` com 3 checkboxes de permissão granular em tempo real:
        - `AllowInputControl` (Permitir controle de mouse e teclado).
        - `AllowClipboard` (Permitir sincronização da Área de Transferência).
        - `AllowFileTransfer` (Permitir envio e transferência de arquivos).

5. **Codec de Vídeo Baseado em Dirty Tiles (`DeskView.DeskRtTileEncoder`)**:
   - Captura da tela via GDI+ (`Graphics.CopyFromScreen` / `BitBlt`).
   - Suporte a **Monitor Principal** (`-1`), **Todos os Monitores Combinados / VirtualScreen** (`-2`) ou **Monitor Específico por Índice** (`>= 0`).
   - Divisão do frame em uma grade de **8x6 (48 blocos/tiles)**.
   - Cálculo de hash rápido **FNV-1a** em modo `unsafe` (amostrando linhas a cada 2px verticalmente e 2px horizontalmente).
   - Compressão JPEG individual apenas dos blocos cujo hash mudou desde o quadro anterior, com KeyFrame completo forçado a cada 90 quadros (~3 segundos a 30 FPS).
   - Três perfis de qualidade selecionáveis pelo cliente: **Ultra (90%)**, **Balanceado (70%)** e **Alta Velocidade (45%)**.

6. **Canal Rápido de Cursor (`PacketType.CursorUpdate`)**:
   - Transmissão independente das coordenadas `(X, Y)` do cursor do host sempre que se movem, desacoplada da codificação de imagem dos tiles.

7. **Captura e Injeção de Comandos de Mouse e Teclado**:
   - No cliente (`RemoteSessionTabControl`): captura `MouseMove`, `MouseDown`, `MouseUp`, `MouseWheel`, `KeyDown` e `KeyUp` sobre o `DoubleBufferedCanvas`. Normaliza coordenadas `(normX, normY)` em `float` (`0.0f` a `1.0f`) relativas ao retângulo de renderização.
   - No host (`HostClientWorker`): converte `(normX, normY)` para coordenadas absolutas do monitor ativo e invoca `user32.dll!SetCursorPos`, `user32.dll!mouse_event` e `user32.dll!keybd_event`.

8. **Sincronização de Área de Transferência, Chat e Transferência de Arquivos**:
   - **Clipboard (`PacketType.ClipboardText`)**: envio de texto UTF-8 aplicado no host via `Clipboard.SetText`.
   - **Chat (`PacketType.ChatMessage`)**: mensagens de texto em tempo real com timestamp `[HH:mm:ss]`.
   - **Transferência de Arquivos (`FileTransferOffer` / `FileTransferChunk` / `FileTransferEnd`)**: transmissão em blocos de `32.768 bytes` (32 KB) salvos na Área de Trabalho do host.

9. **Telemetria em Tempo Real**:
   - Cálculo a cada 1 segundo de **FPS**, **Tiles/s** e **Taxa de bits (kbps)** exibidos na barra de ferramentas da sessão.

---

## 4. Fluxo de Funcionamento e Protocolo Binário (`PacketFrameIO`)

Todas as mensagens da sessão ativa trafegam sobre um stream TCP utilizando framing binário de **5 bytes de cabeçalho**:

```
+-------------------+-----------------------------------+--------------------------------+
| Byte 0 (uint8)    | Bytes 1..4 (int32 Little-Endian)  | Bytes 5..N                     |
| PacketType        | PayloadLength (0 .. 64 MB)        | Payload Bruto                  |
+-------------------+-----------------------------------+--------------------------------+
```

### Tabela de Tipos de Pacote (`DeskView.PacketType`)

| Código | Enum | Direção | Estrutura do Payload |
|---|---|---|---|
| `1` | `HandshakeHello` | Reservado | Não utilizado no fluxo principal |
| `2` | `HandshakeAuthRequest` | Cliente -> Host | UTF-8: `<ClientId>|<MachineName>|<Password>[|<LoopbackNonce>]` |
| `3` | `HandshakeAuthResponse` | Host -> Cliente | UTF-8: `ACCEPTED|<DeskId>|<HostName>|<Fingerprint16>|<MonCount>` ou `REJECTED|<Motivo>` |
| `10` | `ScreenMeta` | Host -> Cliente | 24 bytes: `int32 MonCount`, `int32 SelectedMon`, `int32 Left`, `int32 Top`, `int32 Width`, `int32 Height` |
| `11` | `TileFrameDirty` | Host -> Cliente | Header (`int32 fullW`, `int32 fullH`, `uint16 tileCount`) + `N`×(`uint16 tx, ty, tw, th`, `int32 jpgLen`, `byte[] jpg`) |
| `12` | `CursorUpdate` | Host -> Cliente | 8 bytes: `int32 cursorX`, `int32 cursorY` |
| `20` | `MouseInput` | Cliente -> Host | 13 bytes: `uint8 action` (0=Move, 1=LDown, 2=LUp, 3=RDown, 4=RUp, 5=MDown, 6=MUp, 7=Wheel), `float32 normX`, `float32 normY`, `int32 wheelDelta` |
| `21` | `KeyInput` | Cliente -> Host | 3 bytes: `uint8 virtualKey`, `uint8 isDown` (1/0), `uint8 reserved` |
| `22` | `SwitchMonitor` | Cliente -> Host | 4 bytes: `int32 monitorIndex` (`-1`=Primário, `-2`=Todos, `>=0`=Monitor específico) |
| `23` | `QualityChange` | Cliente -> Host | 4 bytes: `int32 jpegQuality` (`90`, `70` ou `45`) |
| `30` | `ClipboardText` | Cliente -> Host | UTF-8: conteúdo textual da área de transferência |
| `40` | `ChatMessage` | Bidirecional | UTF-8: mensagem de chat |
| `50` | `FileTransferOffer` | Cliente -> Host | UTF-8: nome do arquivo |
| `51` | `FileTransferChunk` | Cliente -> Host | Bytes brutos do bloco (até 32 KB) |
| `52` | `FileTransferEnd` | Cliente -> Host | 0 bytes (sinaliza fechamento do arquivo) |
| `90` | `Ping` | Bidirecional | Timestamp / payload eco |
| `91` | `Pong` | Bidirecional | Resposta imediata ao `Ping` |
| `99` | `Disconnect` | Bidirecional | Encerramento gracioso da sessão |

---

## 5. Fronteiras Nativas (P/Invoke) e Dependências Identificadas no Ghidra/REA

A análise `inspect_managed_native_boundaries` comprovou que o executável original referencia apenas 5 assemblies da BCL (`.NET 4.0`: `mscorlib`, `System`, `System.Drawing`, `System.Windows.Forms`, `System.Core`) e um único módulo nativo Win32 (`user32.dll`):

| Token ImplMap | Função Nativa (`user32.dll`) | Finalidade no Código Original | Limitação Técnica Identificada |
|---|---|---|---|
| `0x1c000001` | `SetProcessDPIAware` | Evitar virtualização de DPI em telas High-DPI | API legada do Windows Vista (substituída por Per-Monitor DPI v2) |
| `0x1c000002` | `SetCursorPos` | Mover cursor para `(absX, absY)` | Não funciona em telas de UAC/Lock Screen sem privilégio `uiAccess`/Serviço |
| `0x1c000003` | `mouse_event` | Injetar cliques e rolagem de mouse | Obsoleta frente a `SendInput`; não reporta coordenadas sub-pixel nem dispositivos touch/pen |
| `0x1c000004` | `keybd_event` | Injetar pressionamento/liberação de tecla (`bVk`) | Passa `bScan = 0` e ignora `KEYEVENTF_EXTENDEDKEY` / `KEYEVENTF_SCANCODE`; falha em jogos DirectX e teclas especiais |
| `0x1c000005` | `GetCursorInfo` | Declarada em `NativeMethods` | **Código morto**: declarada mas nunca chamada em `CaptureLoop` (que usa `Cursor.Position`) |
| `0x1c000006` | `DrawIcon` | Declarada em `NativeMethods` | **Código morto**: declarada mas nunca chamada |

---

## 6. Mapeamento dos Dispositivos de Entrada Suportados vs. Ausentes

| Dispositivo | Estado no Software Original (`DeskView.exe`) | Causa Raiz / Evidência no Binário |
|---|---|---|
| **Mouse (3 botões + Scroll)** | Parcialmente suportado (Apenas Windows) | Captura via eventos WinForms e injeção via `SetCursorPos` + `mouse_event`. Sem suporte a botões laterais (`XButton1`/`XButton2`), scroll horizontal ou captura de periférico físico. |
| **Teclado** | Parcialmente suportado (Com falhas de mapeamento) | Trunca `KeyEventArgs.KeyValue` (`int32`) para `byte` (`uint8`); não envia ScanCode físico nem flag de tecla estendida (`ExtendedKey`); não sincroniza modificadores ou layouts ABNT2/US. |
| **Controles de Videogame (Gamepad / XInput)** | **Inexistente (0% implementado)** | Nenhuma importação de `xinput1_4.dll`, `xinput9_1_0.dll` ou `Windows.Gaming.Input`. Nenhum `PacketType` para botões/gatilhos/analógicos. |
| **Joysticks / Dispositivos HID** | **Inexistente (0% implementado)** | Nenhuma importação de `hid.dll`, `setupapi.dll` ou `RegisterRawInputDevices`. |
| **Enumeração e Hotplug de Periféricos** | **Inexistente (0% implementado)** | O programa não detecta quais mouses, teclados ou controles estão conectados nem reage a eventos de conexão/desconexão física. |

---

## 7. Divergências Identificadas entre a Versão Original (`d6243d1`) e a Versão Local (`src/`)

Durante a auditoria cruzada entre o binário original do commit `d6243d1` (`79.360 bytes`) e o código em `src/`:
1. **Bug do Encoder JPEG no Binário Original**: Em `d6243d1`, o construtor de `DeskRtTileEncoder` chamava `ImageCodecInfo.GetImageDecoders()` em vez de `GetImageEncoders()`, fazendo com que `_jpegEncoder` fosse sempre `null` e o seletor de qualidade (90%/70%/45%) não tivesse efeito real.
2. **Geração de DeskID Instável no Binário Original**: Em `d6243d1`, `GenerateDeterministicHardwareId()` concatenava `GetPrimaryLocalIp()` na semente SHA-256. Sempre que o computador mudava de rede Wi-Fi ou recebia outro IP via DHCP, o código DeskID de 9 dígitos mudava caso `deskview.conf` fosse recriado.
3. **Sinalização MQTT Sem Assinatura no Binário Original**: Em `d6243d1`, os pacotes `REQ|{0}|{1}|{2}|{3}` no tópico público `deskview/v2/signal/<id>` não possuíam assinatura HMAC nem timestamp.
4. **Chat Unidirecional na Prática**: Embora `RemoteSessionTabControl` tratasse `PacketType.ChatMessage` vindo do host, a janela principal (`MainWindow` / `DeskViewHostServer`) apenas registrava a mensagem no log interno (`_server.Log("[Chat de ...]: " + chat)`) e não possuía interface para o usuário do Host responder ao chat para os clientes conectados.

---

## 8. Problemas Técnicos Críticos que Motivam a Reengenharia

1. **Falha Estrutural na Comunicação Entre Redes Diferentes (WAN / NAT / CGNAT)**:
   - O software usa MQTT apenas para trocar a string `<PublicWanIp>:<ListenPort>` (ex.: `179.135.207.135:7070`) e, em seguida, tenta abrir um socket TCP direto (`TcpClient.Connect`) para esse IP público.
   - Como roteadores domésticos e operadoras móveis bloqueiam conexões TCP de entrada não mapeadas na tabela NAT (e o programa não implementa UPnP, STUN RFC 5389, UDP Hole Punching, WebRTC ICE/TURN nem Relay de pacotes), **100% das conexões entre redes distintas sem redirecionamento manual de porta no roteador falham por timeout**.
2. **Ausência de Criptografia de Ponta a Ponta no Fluxo de Dados**:
   - O socket TCP transmite frames de tela, teclas digitadas, área de transferência e arquivos em texto claro (sem TLS/DTLS ou cifragem AEAD).
3. **Falha na Detecção e Transmissão de Periféricos (Mouse, Teclado, Gamepads e Joysticks)**:
   - Inexistência total de detecção de periféricos conectados, ausência de suporte a controles/joysticks e uso de APIs Win32 legadas (`keybd_event`/`mouse_event`) sem scan codes.
4. **Acoplamento Total ao Windows Forms / GDI+**:
   - Impossibilidade de execução no Android ou em outras plataformas modernas.

---

## 9. Funcionalidades que Devem Ser Preservadas vs. Reconstruídas

### Funcionalidades a Preservar Integralmente:
- Identidade de 9 dígitos (`DeskID` formatado `000 000 000`) e `Fingerprint` criptográfico.
- Acesso supervisionado (modal de aprovação com permissões granulares de Entrada, Clipboard e Arquivos) e Acesso Desassistido por senha.
- Sessões recentes, favoritos e logins salvos para reconexão rápida.
- Visualização remota em múltiplas abas simultâneas, seleção de monitor (Primário, Todos, Específico) e seletor de qualidade (Ultra 90%, Balanceado 70%, Alta Velocidade 45%).
- Canal dedicado de cursor remoto, sincronização de Área de Transferência, Chat em tempo real (agora verdadeiramente bidirecional) e Transferência de Arquivos segura.
- Telemetria em tempo real (FPS, Tiles/s, Bitrate kbps, Latência ms e Modo de Rota: LAN / P2P ICE / Relay).

### Funcionalidades a Reconstruir e Expandir na Nova Arquitetura Flutter:
- **Motor de Comunicação Híbrido Multi-Rede**: Descoberta LAN (UDP) + Sinalização Global Assinada + Resolução STUN (RFC 5389) + Negociação WebRTC/ICE P2P + **Túnel de Relay Seguro (Fallback Automático)** para garantir conectividade mesmo sob NAT Simétrico, CGNAT e redes móveis 4G/5G sem abrir portas no roteador.
- **Segurança Criptográfica**: Handshake autenticado com troca de chaves, verificação de nonce/timestamp e criptografia de payload nas sessões remotas.
- **Subsistema Completo de Periféricos (Mouse, Teclado, Gamepad e Joystick)**:
  - Detecção ativa e monitoramento de hotplug (conexão/desconexão) de mouses, teclados, controles (XInput/HID) e joysticks.
  - Transmissão estruturada de eventos de alta frequência com número de sequência, preservando ordem, pressão/liberação de teclas com ScanCode + Physical/Logical Key, botões extras de mouse, eixos analógicos (`LX`, `LY`, `RX`, `RY`), gatilhos (`LT`, `RT`), D-Pad e botões de controle.
  - Integração nativa via **Platform Channels** para **Windows** (`SendInput` com `KEYEVENTF_SCANCODE`, `XInputGetState`, enumeração HID/RawInput, captura GDI/DXGI) e **Android** (`InputManager`, `AccessibilityService` para gestos/injeção autorizada, `MediaProjection` para captura de tela e eventos de Gamepad/KeyEvent).
