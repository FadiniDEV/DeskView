# MAPEAMENTO DE PARIDADE FUNCIONAL (ORIGINAL vs. FLUTTER)

## 1. Matriz Geral de Rastreabilidade

| ID | Funcionalidade Original | Localização Original (C# / Win32) | Implementação Flutter (Dart / Core) | Status de Paridade |
|---|---|---|---|---|
| **FN-01** | Geração Determinística de DeskID | `IdentityManager.GenerateDeterministicHardwareId` | `lib/core/identity/identity_manager.dart` | Validado |
| **FN-02** | Formatação Visual do DeskID (`000 000 000`) | `IdentityManager.FormatDeskId` | `lib/core/identity/identity_manager.dart` | Validado |
| **FN-03** | Fingerprint Criptográfico de 64 caracteres | `IdentityManager.Fingerprint` (SHA-256) | `lib/core/identity/identity_manager.dart` | Validado |
| **FN-04** | Senha de Acesso Desassistido (HMAC-SHA256) | `IdentityManager.SetUnattendedPassword` / `Verify` | `lib/core/identity/identity_manager.dart` | Validado |
| **FN-05** | Persistência do `deskview.conf` | `IdentityManager.Save` / `Initialize` | `lib/data/repositories/config_repository_impl.dart` | Validado |
| **FN-06** | Armazenamento de Logins Salvos (1-Clique) | `IdentityManager.SaveOrUpdateLogin` (`saved_logins.dat`)| `lib/data/repositories/config_repository_impl.dart` | Validado |
| **FN-07** | Favoritos e Histórico Recente | `Favorites` / `RecentSessions` | `lib/domain/entities/saved_login.dart` | Validado |
| **FN-08** | Criptografia DPAPI / Base64 para senhas salvas | `IdentityManager.EncryptSecret` / `DecryptSecret` | `lib/core/security/secret_vault.dart` | Validado |
| **FN-09** | Descoberta em Rede Local (UDP Broadcast 50001) | `LanDiscoveryService` | `lib/services/lan_discovery_service.dart` | Validado |
| **FN-10** | Detecção de IP Público WAN (HTTP GET) | `GlobalRendezvousClient.RefreshPublicIp` | `lib/services/global_rendezvous_client.dart` | Validado |
| **FN-11** | Cliente MQTT 3.1.1 Nativo sobre TCP (1883) | `GlobalRendezvousClient.MqttWorkerLoop` | `lib/services/mqtt_rendezvous_client.dart` | Validado |
| **FN-12** | Assinatura Criptográfica de Sinalização MQTT | `GlobalRendezvousClient.SignSignal` (HMAC-SHA256) | `lib/services/mqtt_rendezvous_client.dart` | Validado |
| **FN-13** | Sinalização de Presença Retida (`peers/#`) | `GlobalRendezvousClient.PublishPresence` | `lib/services/global_rendezvous_client.dart` | Validado |
| **FN-14** | Servidor TCP Host com Fallback de Portas | `DeskViewHostServer` (Portas 7070 a 7084) | `lib/services/host_server_service.dart` | Validado |
| **FN-15** | Protocolo Binário de Framing de 5 Bytes | `PacketFrameIO.WritePacket` / `ReadPacket` | `lib/data/network/packet_frame_io.dart` | Validado |
| **FN-16** | Handshake de Autenticação (`AuthRequest/Response`)| `HostClientWorker.RunSession` | `lib/services/host_client_session.dart` | Validado |
| **FN-17** | Modal Interativo de Aceitação de Sessão | `AcceptSessionDialog` (Input, Clipboard, Arquivos)| `lib/presentation/widgets/accept_session_dialog.dart` | Validado |
| **FN-18** | Codec DeskRT-Tile (Grade 8×6 Dirty Tiles JPEG) | `DeskRtTileEncoder.CaptureAndEncodeDirtyTiles` | `lib/services/codec/dirty_tile_codec.dart` | Validado |
| **FN-19** | Hash Rápido FNV-1a de Blocos | `DeskRtTileEncoder` (Algoritmo FNV-1a) | `lib/services/codec/fnv1a_hash.dart` | Validado |
| **FN-20** | Envio de Keyframe Periódico Forçado (90 frames) | `DeskRtTileEncoder.ForceFullKeyFrame` | `lib/services/codec/dirty_tile_codec.dart` | Validado |
| **FN-21** | Seleção de Perfis de Qualidade (90%, 70%, 45%) | `PacketType.QualityChange` | `lib/services/codec/dirty_tile_codec.dart` | Validado |
| **FN-22** | Suporte Multi-Monitor (Primário, Todos, Específico)| `PacketType.SwitchMonitor` | `lib/platform/windows/windows_screen_capture.dart` | Validado |
| **FN-23** | Canal Rápido de Posição de Cursor Remoto | `PacketType.CursorUpdate` | `lib/presentation/widgets/remote_canvas_painter.dart`| Validado |
| **FN-24** | Injeção de Mouse Remoto com Coordenadas Normalizadas| `PacketType.MouseInput` (`SetCursorPos`/`mouse_event`)| `lib/platform/windows/windows_input_injector.dart` | Validado |
| **FN-25** | Injeção de Teclado Remoto e Teclas Modificadoras | `PacketType.KeyInput` (`keybd_event`) | `lib/platform/windows/windows_input_injector.dart` | Validado |
| **FN-26** | Liberação Automática de Teclas Presas | `HostClientWorker.ReleaseHeldInputs` | `lib/platform/windows/windows_input_injector.dart` | Validado |
| **FN-27** | Sincronização de Área de Transferência (Clipboard)| `PacketType.ClipboardText` | `lib/services/clipboard_sync_service.dart` | Validado |
| **FN-28** | Chat em Tempo Real Bidirecional | `PacketType.ChatMessage` | `lib/presentation/widgets/session_chat_panel.dart` | Validado |
| **FN-29** | Transferência de Arquivos Segura (Blocos 32 KB) | `PacketType.FileTransferOffer/Chunk/End` | `lib/services/file_transfer_service.dart` | Validado |
| **FN-30** | Sanitização Rigorosa de Arquivos e Nomes Proibidos | `HostClientWorker.SanitizeFileName` | `lib/services/file_transfer_service.dart` | Validado |
| **FN-31** | Telemetria em Tempo Real (FPS, Tiles/s, Bitrate) | `RemoteSessionTabControl.UpdateRealtimeTelemetry` | `lib/presentation/widgets/session_toolbar.dart` | Validado |
| **FN-32** | Gerenciador de Sessões em Múltiplas Abas | `MainWindow._tabControl` | `lib/presentation/screens/home_screen.dart` | Validado |
| **FN-33** | Diálogo de Configuração de Senha Desassistida | `MainWindow.PromptUnattendedPassword` | `lib/presentation/widgets/unattended_password_modal.dart`| Validado |

---

## 2. Detalhamento Específico por Módulo

### FN-01 & FN-02: Identidade DeskID
- **Objetivo**: Garantir que o identificador numérico de 9 dígitos seja único, determinístico e estável para a máquina do usuário.
- **Entrada**: `MachineName` e `MachineGuid` do Windows Registry (ou identificador UUID estável do hardware).
- **Processamento**: Hash SHA-256 da semente -> leitura dos primeiros 4 bytes como unsigned 32-bit int -> módulo $900.000.000 + 100.000.000$.
- **Saída**: String de 9 dígitos (ex.: `"482910375"`) formatada como `"482 910 375"`.
- **Casos Excepcionais**: Caso o registro não esteja acessível, utiliza UUID aleatório persistido em `%AppData%\DeskView\deskview.conf`.

### FN-09: Descoberta em Rede Local (LAN Discovery)
- **Objetivo**: Permitir que duas máquinas na mesma rede se encontrem instantaneamente sem necessidade de servidor intermediário.
- **Entrada**: Socket UDP escutando em `0.0.0.0:50001`.
- **Processamento**: Transmissão a cada 3.000 ms do anúncio de broadcast contendo ID, Hostname, Usuário, IP e Porta. No receptor, faz parsing do prefixo `DESKVIEW_V1|` e atualiza o mapa reativo de computadores locais.
- **Saída**: Objeto `PeerDiscoveryInfo` atualizado na interface.

### FN-11 & FN-12: Sinalização Global (MQTT 3.1.1)
- **Objetivo**: Viabilizar conexões entre computadores situados em redes geograficamente separadas através da troca segura de mensagens de sinalização.
- **Entrada**: Conexão TCP na porta `1883` com `broker.hivemq.com` ou `broker.emqx.io`.
- **Processamento**: Codificação e decodificação do protocolo MQTT 3.1.1 (CONNECT, CONNACK, PUBLISH, SUBSCRIBE, PINGREQ, PINGRESP). Cada mensagem de sinalização no tópico `deskview/v2/signal/<DeskId>` inclui assinatura truncada HMAC-SHA256 de 16 caracteres e timestamp em ticks UTC.
- **Saída**: Validação de autenticidade, descarte de pacotes com data superior a 2 minutos (ataque de repetição) e emissão de eventos reativos (`OnIncomingRequest`, `OnAccepted`, `OnRejected`).

### FN-18 & FN-19: Codec DeskRT-Tile (Grade 8×6)
- **Objetivo**: Transmitir a tela com baixíssimo consumo de banda e latência mínima.
- **Entrada**: Buffer da área de trabalho ativa em resolução completa.
- **Processamento**: Grade lógica de 8 colunas por 6 linhas (48 retângulos). Cálculo do hash FNV-1a com amostragem 2x2. Compara cada hash com o quadro anterior. Se houver diferença, extrai o recorte e comprime isoladamente em JPEG. A cada 90 quadros, redefine os hashes para forçar envio de keyframe completo.
- **Saída**: Pacote binário `PacketType.TileFrameDirty` estruturado contendo largura total, altura total, contagem de blocos e blocos codificados.

### FN-29 & FN-30: Transferência de Arquivos
- **Objetivo**: Permitir envio de arquivos diretamente para a Área de Trabalho do host de forma segura.
- **Entrada**: Arquivo selecionado no cliente (até 500 MB).
- **Processamento**:
  - `PacketType.FileTransferOffer`: Inicia stream em arquivo temporário `.part`.
  - `PacketType.FileTransferChunk`: Grava blocos de até 32 KB. Monitora limite cumulativo de 500 MB.
  - `PacketType.FileTransferEnd`: Fecha stream, sanitiza nome de arquivo (remove caracteres ilegais, bloqueia nomes de dispositivos DOS como `NUL`, `CON`, `COM1..9`, trunca comprimento em 100 caracteres) e move para `Desktop\DeskView_Recebidos` garantindo nome único caso já exista.
- **Saída**: Arquivo final íntegro gravado no disco do host.
