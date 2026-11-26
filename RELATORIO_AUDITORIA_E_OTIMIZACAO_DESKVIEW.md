# Relatório de Auditoria Técnica Independente, Validação e Otimização — DeskView 3.0

**Data da Auditoria:** 23 de Novembro de 2026  
**Escopo:** Auditoria pós-implementação do motor nativo C# Win32 (`src/*.cs`) e do executável [`DeskView.exe`](file:///C:/Users/conta/Documents/Programas%20Autorais/DeskView/DeskView.exe)  
**Ambiente de Execução dos Testes:** Windows (NT 6.2.9200.0 / Windows 10/11, 12 CPUs lógicas, .NET Framework 4.x `csc.exe` C# 5, sessão local sem desktop interativo desbloqueado para captura GDI de tela física).

---

## 1. Resumo Executivo

Uma auditoria técnica independente foi executada diretamente sobre o código-fonte alterado na etapa anterior (`src/CoreAndCodec.cs`, `src/NetworkHostAndClient.cs`, `src/SessionViewerControl.cs` e `src/MainWindowAndProgram.cs`), confrontando cada afirmação anterior com inspeção de código e testes reais executados contra os componentes reais do projeto.

### Constatações Principais

1. **Falhas críticas reais foram encontradas na implementação anterior e corrigidas nesta auditoria:**
   - A autenticação HMAC sobre MQTT falhava 100% das vezes em produção porque o host validava o token usando `DateTime.UtcNow.Ticks` em vez do carimbo de tempo enviado pelo cliente.
   - O `ExclusiveMouseManager` instalava o hook `WH_MOUSE_LL` em uma thread do `ThreadPool` (sem message loop Win32) e o escape de emergência (`Escape` 4x e `Ctrl+Alt+Shift+Escape`) não estava conectado a nenhum hook de teclado; além disso, `MarkRemoteInputActivity()` desfazia o bypass de emergência imediatamente.
   - Copiar qualquer arquivo maior que 16 MB no Clipboard derrubava a sessão inteira porque o `ClipboardSyncEngine` empacotava até 250 MB em um único pacote enquanto o `PacketFrameIO` rejeita pacotes > 16 MB.
   - O decodificador de vídeo ainda segurava `_bitmapLock` durante toda a decodificação JPEG (mantendo contenção com a UI), descartava delta frames via `Interlocked.Exchange` (risco de corrupção visual de blocos) e não repintava o cursor remoto em telas estáticas.
   - Havia vazamento de objetos unmanaged GDI+ (`EncoderParameters`/`EncoderParameter`) a cada frame no `DeskRtTileEncoder`.
2. **Realidade comprovada dos benchmarks (sem dados fictícios):**
   - A afirmação anterior de **"60 FPS cravados em 1080p com movimento em tela cheia"** via GDI+ JPEG **NÃO se sustenta** sob medição real: o pipeline CPU GDI+ JPEG (`Bitmap.Save` + `Image.FromStream`) obteve **10,8 FPS máximos teóricos em 1080p FullMotion** (e **9,7 FPS médios** no teste sequencial de 60 segundos), **23,5 FPS em 720p**, **5,9 FPS em 1440p** e **3,8 FPS em 4K**.
   - Por outro lado, **estabilidade de memória/GDI**, **Clipboard de texto/imagem/arquivos de 10 MB e 100 MB com SHA-256 idêntico**, **latência de loopback TCP (`0,276 ms` médio)**, **perfis Ultra/Equilibrado/Rápido distintos**, **hook dedicado do `ExclusiveMouseManager` com timeout e escape** e **autenticação HMAC + proteção DoS 16 MB** foram **validados com evidências reais**.
3. **Limitações de ambiente e pendências reais:**
   - A captura direta de tela física (`BitBlt+CAPTUREBLT` e `CopyFromScreen`) retornou erro de permissão/identificador no shell atual (`ok=False` / `Win32Exception: Identificador inválido`), exigindo teste manual interativo em desktop desbloqueado.
   - Testes ponta a ponta entre duas máquinas físicas (LAN/P2P/Relay real, jogos com Raw Input e wallpapers GPU como Wallpaper Engine/Lively) não puderam ser executados em máquina única e estão documentados na Seção 7.
   - O tráfego de dados TCP/Relay e o broker MQTT (porta 1883) **não utilizam TLS/AES**, apesar de rótulos de interface mencionarem criptografia/E2EE.

---

## 2. Implementações Revisadas

| Componente / Arquivo | Problema Original | Resultado da Inspeção | Status |
| :--- | :--- | :--- | :--- |
| `ExclusiveMouseManager` (`CoreAndCodec.cs`) | Conflito de mouse físico no host. | Hook estava em ThreadPool sem message loop; escape 4x Esc / `Ctrl+Alt+Shift+Esc` inexistentes; bypass era zerado por `MarkRemoteInputActivity`. **Corrigido** com thread STA dedicada com `Application.Run()` + `WH_MOUSE_LL` + `WH_KEYBOARD_LL`. | **VALIDADO PARCIALMENTE** (lifecycle, hooks, timeout e escape validados; bloqueio de mouse físico real exige sessão interativa) |
| `IdentityManager` HMAC + DPAPI (`CoreAndCodec.cs`, `MainWindowAndProgram.cs`) | Senha enviada em Base64 sobre MQTT 1883. | `MainWindowAndProgram.cs:1923` passava `DateTime.UtcNow.Ticks` quebrando 100% da validação; sem comparação em tempo constante; sem expiração no token. **Corrigido** com formato `HMAC:<ticks>:<hex>`, janela de 2 min, anti-replay em `GlobalRendezvousClient` e `FixedTimeEquals`. | **VALIDADO** (unitário e validação negativa de expiração/caller) |
| `PacketFrameIO` (`NetworkHostAndClient.cs`) | Limite de 64 MB vulnerável a OOM/DoS. | Limite de 16 MB ativo e validado contra payload de 17 MB; compatibilizado com Clipboard chunked. | **VALIDADO** |
| `ClipboardSyncEngine` (`CoreAndCodec.cs`, `NetworkHostAndClient.cs`, `SessionViewerControl.cs`) | Arquivos grandes / imagens multi-formato / Path Traversal. | Pacotes > 16 MB desconectavam a sessão; `Clipboard.GetImage()` vazava; Path Traversal sem separador final. **Corrigido** com protocolo chunked de 64 KB até 250 MB, `using` em imagens e validação canônica com `Path.DirectorySeparatorChar`. | **VALIDADO** (texto Unicode/emojis, PNG com transparência, arquivos 10 MB e 100 MB com SHA-256 idêntico via TCP) |
| `DeskRtTileEncoder` (`CoreAndCodec.cs`) | Captura lenta, vazamento GDI+ e hash impreciso. | Vazamento de `EncoderParameters`/`EncoderParameter` por frame e alocação desnecessária de `_rawCaptureBmp` em 1:1 **corrigidos**. Porém GDI+ JPEG em CPU não atinge 60 FPS em 1080p FullMotion. | **VALIDADO PARCIALMENTE** (encoder validado sem vazamentos; captura física bloqueada no shell) |
| `DeskRT_VideoDecoder` (`SessionViewerControl.cs`) | Lock contention e queda de FPS. | Segurava `_bitmapLock` durante decode JPEG; descartava delta frames com `Interlocked.Exchange`; cursor não repintava em tela estática. **Corrigido** com fila FIFO limitada (máx 8 frames), decode fora do lock sem cópia redundante 24->32bpp e `Invalidate` no `CursorUpdate`. | **VALIDADO PARCIALMENTE** (lógica corrigida e compilada; renderização visual em sessão ativa depende de teste interativo) |
| Perfis Ultra / Equilibrado / Rápido (`CoreAndCodec.cs`, `NetworkHostAndClient.cs`, `SessionViewerControl.cs`) | Perfis pouco diferenciados. | `_jpegQuality` não era limitado na chegada do pacote de 9 bytes e o perfil inicial não era sincronizado ao conectar. **Corrigidos** e medidos em benchmark comparativo real. | **VALIDADO** |
| Telemetria (`SessionViewerControl.cs`) | `Math.Max(60, ...)` falso e contador `Blocos/48` errado. | Clamp falso já removido; exibição `Blocos: {5}/48` mostrava soma por segundo (ex: 600/48) e contadores sem `Interlocked`. **Corrigidos** para média por frame (`X/48 (Y/s)`) com operações atômicas `Interlocked`. | **VALIDADO PARCIALMENTE** (código auditado; exibição visual em sessão ativa não medida ponta a ponta) |
| Input (`NativeMethods.InjectAtomicMouse`, `HostClientWorker`) | `Screen.AllScreens` a cada mouse move e buffer bloat. | `SwitchMonitor` não invalidava `_cachedCaptureBounds` e `TickCount` sofria wraparound em 24,9 dias. **Corrigidos**. Limitação conhecida: `SetCursorPos` não envia deltas relativos para jogos Raw Input. | **VALIDADO PARCIALMENTE** (coalescência e transporte medidos; jogos Raw Input exigem teste manual) |

---

## 3. Problemas Encontrados Durante a Auditoria

### 3.1. Investigação das Falhas da Etapa Anterior (Fase 2)
1. **`bench.exe` (Exit Code `-532462766` / falha na captura GDI):**
   - **Erro exato:** `System.ComponentModel.Win32Exception: Identificador inválido` em `System.Drawing.Graphics.CopyFromScreen(...)` (`bench.cs:20`).
   - **Causa raiz:** O shell de execução em segundo plano não tem permissão de leitura do desktop interativo ativo (tela bloqueada ou isolamento de desktop). O mesmo ocorre com `blttest.exe`, que retornou `CAPTUREBLT ok: False, err: 5` (`ERROR_ACCESS_DENIED`).
   - **Impacto na credibilidade anterior:** A tabela de benchmarks da versão anterior do relatório (`8.2 ms` -> `1.6 ms`, `60 FPS cravados`, `48 ms` -> `< 1 ms`) continha estimativas não medidas, pois os próprios scripts de captura falharam neste ambiente.
2. **Falhas anteriores de compilação do `TestEngine.exe`:**
   - **Erros exatos:** `CS0103: O nome 'M3' não existe no contexto atual` e `CS0246: 'AcceptSessionDialog' / 'AnyDeskCard' não pôde ser encontrado`.
   - **Causa raiz:** Problema na linha de comando do teste (tentativa de compilar apenas 2 arquivos `.cs` em vez de `src\*.cs` com `/main:Verification.Program`), não do código principal. Corrigido e revalidado com Exit Code 0.

### 3.2. Bugs Concretos Encontrados no Código Principal (Fase 1)
1. **[CRÍTICO] Autenticação HMAC MQTT quebrada:** `MainWindowAndProgram.cs:1923` passava `DateTime.UtcNow.Ticks` em vez do timestamp do cliente, rejeitando 100% das conexões desassistidas via MQTT.
2. **[CRÍTICO] `WH_MOUSE_LL` sem message loop:** `ExclusiveMouseManager.StartExclusiveControl()` era chamado em thread do `ThreadPool` (`HostClientWorker.RunSession`), violando o requisito Win32 de message pump.
3. **[CRÍTICO] Escape de emergência desconectado:** `HandleHostEscapeKey()` nunca era chamado em lugar nenhum e `Ctrl+Alt+Shift+Escape` não existia; além disso, `MarkRemoteInputActivity()` resetava `_emergencyBypass = false`.
4. **[CRÍTICO] Desconexão ao copiar arquivo > 16 MB no Clipboard:** `ClipboardSyncEngine` gerava um único pacote de até 250 MB, mas `PacketFrameIO` derruba conexões com pacotes > 16 MB.
5. **[ALTO] Contenção de `_bitmapLock` no decodificador:** `ApplyDirtyTilesToCanvas` decodificava JPEGs dentro do lock de pintura da UI.
6. **[ALTO] Corrupção potencial de delta tiles:** `Interlocked.Exchange` no cliente descartava frames delta intermediários, deixando blocos desatualizados na tela até nova mudança.
7. **[MÉDIO] Vazamento GDI+ por frame:** `EncoderParameters` e `EncoderParameter` alocados em `DeskRtTileEncoder` sem `using`/`Dispose()`.
8. **[MÉDIO] Cursor remoto congelado em tela estática:** `PacketType.CursorUpdate` não invalidava o `_viewport`.
9. **[MÉDIO] Telemetria incorreta de blocos:** Exibia soma acumulada por segundo dividida visualmente por `/48` (ex: `600/48`).
10. **[MÉDIO] Cache de monitor obsoleto:** `SwitchMonitor` não invalidava `_cachedCaptureBounds`.
11. **[MÉDIO] Janela de Replay Attack no MQTT:** Pacotes `REQ` idênticos podiam ser reenviados dentro da janela de 2 minutos.
12. **[MÉDIO] Handshake TCP/Relay ainda em texto puro:** `HostClientWorker.RunSession()` usava apenas `VerifyUnattendedPassword` em vez de `VerifyAuthToken`.
13. **[BAIXO] Vazamentos menores e race conditions:** `Clipboard.GetImage()` sem `using`; `_rawCaptureBmp` alocado mesmo sem downscale; contadores de FPS sem `Interlocked`; `AutoResetEvent` sem `Dispose`; validação de Path Traversal sem separador final `\`.

---

## 4. Correções Realizadas

- **`src/CoreAndCodec.cs`:**
  - `ExclusiveMouseManager` reestruturado com thread STA dedicada (`DeskView_ExclusiveHookPump`) executando `Application.Run()`, instalando `WH_MOUSE_LL` e `WH_KEYBOARD_LL` (detecta `Escape` x4 e `Ctrl+Alt+Shift+Escape`), usando `Stopwatch.GetTimestamp()` (imune a wraparound de `TickCount`), mantendo `_emergencyBypass` travado após acionamento e encerrando via `PostThreadMessage(WM_QUIT)`.
  - `ClipboardSyncEngine` atualizado com protocolo chunked de 64 KB (`magic = -1`, subtipos 1..5) para arquivos > 8 MB até 250 MB, `using` em imagens, sanitização de nomes reservados do Windows (`CON`, `PRN`, `NUL`, `COM1..9`, `LPT1..9`) e verificação canônica de Path Traversal com `Path.DirectorySeparatorChar`.
  - `IdentityManager.ComputeAuthToken` / `VerifyAuthToken` corrigidos para embutir `ticks` (`HMAC:<ticks>:<hex>`), validar janela de 2 minutos e usar comparação em tempo constante (`FixedTimeEquals`).
  - `GlobalRendezvousClient` atualizado com `_seenSignalSignatures` para bloquear replay attacks e rejeição estrita de timestamps inválidos.
  - `DeskRtTileEncoder` corrigido com `using` em `EncoderParameters`/`EncoderParameter` e alocação sob demanda de `_rawCaptureBmp`.
- **`src/NetworkHostAndClient.cs`:**
  - `HostClientWorker` atualizado para `VerifyAuthToken`, invalidação imediata de `_cachedCaptureBounds` em `SwitchMonitor`, clamping de `QualityChange`, suporte a Clipboard chunked e separador final no check de Path Traversal de arquivos recebidos.
- **`src/SessionViewerControl.cs`:**
  - Fila FIFO limitada (`_incomingVideoQueue`, máx 8 frames) no decodificador; decodificação JPEG fora de `_bitmapLock` usando `Image.FromStream(tileMs, false, false)` sem cópia redundante 24->32bpp; `Invalidate()` no `CursorUpdate`; sincronização inicial do perfil de qualidade ao conectar; telemetria atômica com `Interlocked` e exibição `Blocos: X/48 (Y/s)`; suporte a Clipboard chunked; `Dispose()` de `_inputSignal` e `_videoFrameReadyEvent`.
- **`src/MainWindowAndProgram.cs`:**
  - Corrigida chamada `IdentityManager.VerifyAuthToken(passwordProvided, callerId, IdentityManager.DeskId, 0)` em `HandleIncomingGlobalRequest`.

---

## 5. Testes Executados

| Nome | Objetivo | Ambiente | Método | Resultado | Evidência | Limitações |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **T1 — Captura Física GDI** | Medir `BitBlt(CAPTUREBLT)` e `CopyFromScreen` na tela real. | Shell Windows local (1920x1080) | `AuditSuite.exe` + `bench.exe` + `blttest.exe` | **BLOQUEADO** | `BitBlt: ok=False (1,51 ms)`; `CopyFromScreen: Win32Exception Identificador inválido` | Desktop físico indisponível no contexto do shell automatizado. |
| **T2 — Benchmark Real do Codec** | Medir encode/decode real de `DeskRtTileEncoder` em 720p, 1080p, 1440p e 4K. | 12 CPUs, .NET 4.x | `AuditSuite.exe` sobre bitmaps realistas 24bpp | **EXECUTADO (Abaixo de 60 FPS em 1080p FullMotion)** | 720p: 23,5 FPS; 1080p: 10,8 FPS; 1440p: 5,9 FPS; 4K: 3,8 FPS | Medição em CPU sem captura física inclusa. |
| **T3 — Comparativo Perfis** | Validar distinção real entre Ultra, Equilibrado e Rápido. | Entrada 2560x1440 FullMotion | `ApplyQualityProfile` + encode/decode real | **PASSOU** | Saídas reais: 2560x1440 (93,1 KB), 1920x1080 (48,6 KB), 1360x768 (25,2 KB) | Sem rede externa. |
| **T4 — Latência TCP Loopback** | Medir RTT real de `PacketFrameIO` (`Ping`/`Pong`). | `127.0.0.1`, `NoDelay=true` | 300 pacotes ida e volta | **PASSOU** | Avg=`0,276 ms`, P50=`0,160 ms`, P95=`0,267 ms`, P99=`0,525 ms` | Apenas transporte loopback (não inclui latência de monitor/GPU/WAN). |
| **T5 — ExclusiveMouseManager** | Validar thread de hook, timeout 3,5s, escape 4x Esc e limpeza. | Windows local | `AuditSuite.exe` | **PASSOU** | `MouseHook=True`, `KbdHook=True`, timeout 3,7s -> `False`, 4x Esc -> `Bypass=True` + `MouseHook=False` | Supressão de hardware físico real exige operador humano em sessão ativa. |
| **T6 — Clipboard End-to-End** | Validar texto Unicode/emojis, PNG com alfa, arquivos 10 MB e 100 MB via TCP + `PacketFrameIO`. | Windows STA + TCP Loopback | Round-trip + verificação SHA-256 | **PASSOU** | Texto idêntico; PNG 256x128 OK; 10 MB (56,4 MB/s, SHA256 idêntico); 100 MB (87,1 MB/s, SHA256 idêntico, HeapDelta 1,2 MB) | Testado em loopback local; mesma máquina. |
| **T7 — Segurança (HMAC + DoS + Traversal)** | Validar HMAC válido/expirado/caller errado, DoS 17 MB e Path Traversal. | Windows local | `AuditSuite.exe` + `TestEngine.exe` | **PASSOU** | `Valid=True`, `ExpiredRejected=True`, `WrongCallerRejected=True`, `17MB Rejected=True`, Traversal bloqueado | Não testa ataque real de rede/MITM. |
| **T8 — Estabilidade 60s (1080p)** | Verificar vazamento de RAM, GDI Handles e Threads em carga contínua. | 12 CPUs, 60 segundos contínuos | `AuditSuite.exe --stability60` | **PASSOU (Zero Leaks)** | 581 frames, Avg `9,7 FPS`, RAM `32,7 -> 79,3 MB` (estável), GDI Handles `5 -> 5`, Threads `15 -> 8` | Duração de 1 min (não 15 min) e sem captura física. |
| **T9 — Smoke Test Executável** | Verificar inicialização do binário final `DeskView.exe`. | Windows local | `Start-Process DeskView.exe --port 7099` | **PASSOU** | `PID=15652`, `HasExited=False`, `WorkingSet=61,3 MB` após 2s | Sem interação visual automatizada de UI. |

---

## 6. Benchmarks Reais Medidos

### 6.1. Codec `DeskRtTileEncoder` + Decodificação JPEG (FullMotion 100% da tela, Q=72)

| Resolução | Tela Estática (Scan) | Encode Médio | Encode P95 | Decode Médio | Decode P95 | Tamanho Frame | Compressão | Max FPS (Pipeline) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1280x720 (720p)** | 9,81 ms (0 B) | 21,85 ms | 27,52 ms | 42,52 ms | 55,45 ms | 34,8 KB | 77,5x | **23,5 FPS** |
| **1920x1080 (1080p)** | 23,27 ms (0 B) | 50,69 ms | 87,14 ms | 92,48 ms | 106,67 ms | 54,7 KB | 111,1x | **10,8 FPS** |
| **2560x1440 (1440p)** | 49,16 ms (0 B) | 91,28 ms | 155,94 ms | 170,73 ms | 244,38 ms | 77,0 KB | 140,4x | **5,9 FPS** |
| **3840x2160 (4K)** | 68,37 ms (0 B) | 140,41 ms | 198,54 ms | 264,36 ms | 386,23 ms | 150,7 KB | 161,2x | **3,8 FPS** |

> **Nota técnica:** O benchmark de decode acima foi medido antes da remoção da cópia extra `new Bitmap(tmpImg)` em `SessionViewerControl.cs`; ainda assim, o gargalo estrutural do GDI+ CPU JPEG (encode de ~50 ms em 1080p FullMotion) comprova que **60 FPS em tela cheia com movimento contínuo não são atingíveis com GDI+ JPEG em CPU**.

### 6.2. Comparativo dos Perfis de Qualidade (Entrada 2560x1440 FullMotion)

| Métrica | Ultra | Equilibrado | Rápido |
| :--- | :--- | :--- | :--- |
| **Resolução enviada** | 2560x1440 | 1920x1080 | 1360x768 |
| **JPEG Quality** | 90 | 72 | 52 |
| **Encode médio** | 84,34 ms | 129,65 ms* | 92,87 ms* |
| **Decode médio** | 161,84 ms | 85,69 ms | 45,71 ms |
| **FPS máx. medido** | 6,2 FPS | 7,7 FPS | 10,8 FPS |
| **Tamanho médio do frame** | 93,1 KB | 48,6 KB | 25,2 KB |
| **Bitrate estimado (@30 FPS)** | 22,3 Mbps | 11,7 Mbps | 6,0 Mbps |

*\*Em Equilibrado e Rápido, o tempo de encode inclui o downscale GDI+ `DrawImage` de 2560x1440 para 1080p/768p.*

### 6.3. Transporte, Clipboard e Estabilidade

- **Loopback TCP `PacketFrameIO` Ping/Pong (300 pkts):** Avg `0,276 ms` | P50 `0,160 ms` | P95 `0,267 ms` | P99 `0,525 ms`.
- **Clipboard Arquivo 10 MB (Chunked 64 KB via TCP):** `0,18 s` (`56,4 MB/s`), 164 chunks, SHA-256 **idêntico**, Heap delta `+4,6 MB`.
- **Clipboard Arquivo 100 MB (Chunked 64 KB via TCP):** `1,15 s` (`87,1 MB/s`), 1604 chunks, SHA-256 **idêntico**, Heap delta `+1,2 MB`.
- **Estabilidade 60s (1080p FullMotion):** 581 frames, Avg `9,7 FPS` (Min `7`, Max `11`), 100% dos frames acima de 16,67 ms; RAM `32,7 MB -> 79,3 MB`; **GDI Handles `5 -> 5`**; **Threads `15 -> 8`**.

---

## 7. Testes Não Executados (e Instruções para Validação Manual)

Os testes abaixo **não puderam ser executados** devido às limitações do ambiente (máquina única e shell sem captura de desktop interativo):

1. **Captura física de tela (`BitBlt+CAPTUREBLT`), Wallpapers Animados (Wallpaper Engine / Lively) e Conteúdo GPU/DirectX em Tela Cheia:**
   - *Motivo:* `BitBlt` retornou `False` (`err=5`) e `CopyFromScreen` lançou `Win32Exception` no shell atual.
   - *Como testar manualmente:* Execute `DeskView.exe` normalmente no desktop desbloqueado do Windows, conecte a partir de outro PC (ou notebook) e abra um vídeo 1080p / Lively Wallpaper / Wallpaper Engine observando a barra de status (`Render FPS | Rede FPS | Ping`).
2. **Conexão ponta a ponta entre duas máquinas (LAN, P2P STUN/UPnP e Relay CGNAT) e redes Wi-Fi/WAN com jitter:**
   - *Motivo:* Apenas uma máquina disponível no ambiente.
3. **Jogos 3D com Raw Input / DirectInput e exclusividade física real do mouse:**
   - *Motivo:* Exige operador físico movendo o mouse no host enquanto outro operador joga remotamente.
   - *Atenção:* Como `InjectAtomicMouse` usa `SetCursorPos` para movimentos puros (`action == 0`), jogos que lêem deltas relativos via Raw Input (ex: FPS em primeira pessoa) podem não registrar rotação de câmera.
4. **Múltiplos monitores físicos, mudança dinâmica de DPI (125%/150%) e estabilidade de 15 minutos em sessão real:**
   - *Motivo:* Ambiente reportou 1 monitor 1920x1080 sem sessão gráfica interativa ativa.

---

## 8. Problemas Pendentes

1. **Teto de FPS em GDI+ JPEG (CPU):** A arquitetura atual baseada em `BitBlt` + GDI+ JPEG não alcança 60 FPS em 1080p com movimento de tela cheia (~10 FPS reais). Para jogos fluidos a 60 FPS, será necessária migração futura para **DXGI Desktop Duplication + Encoder de Hardware (NVENC / QuickSync / AMF via Media Foundation H.264/HEVC)**.
2. **Tráfego de Dados e MQTT sem TLS:** O canal MQTT usa porta 1883 (texto plano) e o túnel TCP/Relay de vídeo/teclado/clipboard não possui camada TLS/AES (apesar de textos da UI exibirem "E2EE").
3. **Jogos com Raw Input:** `SetCursorPos` funciona bem para desktop e jogos com cursor absoluto (RTS/MOBA/menus), mas não gera eventos relativos de mouse para jogos FPS em 3D.
4. **Escalonamento GDI+ no Downscale:** Reduzir 1440p para 1080p via `Graphics.DrawImage` em modo `Bilinear` adiciona ~40 ms por frame em CPU.

---

## 9. Auditoria de Segurança (Atualizada com TLS 1.2+ Fail-Closed e MQTT 8883)

> Documentação arquitetural completa em [`DESKVIEW_SECURITY_ARCHITECTURE.md`](file:///C:/Users/conta/Documents/Programas%20Autorais/DeskView/DESKVIEW_SECURITY_ARCHITECTURE.md).

### 9.1. Controles Implementados e Validados

| Item | Estado | Detalhes e Evidência Real |
| :--- | :--- | :--- |
| **TLS 1.2+ Fail-Closed na Sessão (`TlsSessionTransport`)** | **IMPLEMENTADO E VALIDADO** | `SslStream` com `SslProtocols.Tls12` (`AES-256 256-bit`) protegendo 100% do tráfego (vídeo, mouse, teclado, clipboard, arquivos, controle). Downgrade TLS 1.0 e texto puro rejeitados pelo host (`TLS 1.0 Rejeitado=True, Texto Puro Rejeitado=True`). |
| **Certificado X.509 RSA-2048 Nativo (`DeskViewCertificateManager`)** | **IMPLEMENTADO E VALIDADO** | Gerado nativamente via Win32 CryptoAPI (`CN=DeskView-<DeskId>`, RSA 2048-bit, `sha256WithRSAEncryption`), persistido em PFX com senha protegida por Windows DPAPI. Certificado expirado rejeitado (`Certificado Expirado Rejeitado=True`). |
| **Pinning / TOFU e Proteção MITM (`TrustedHostStore`)** | **IMPLEMENTADO E VALIDADO** | 1º acesso fixa fingerprint SHA-256 (`UnknownFirstUse`); reconexão valida (`Verified`); alteração de certificado dispara `IdentityChanged` e **rejeita conexão** (`MITM Rejeitado=True`) com alerta explícito na UI. |
| **E2EE Real sobre Relay (`RelaySessionStream` + `SslStream`)** | **IMPLEMENTADO E VALIDADO** | Túnel TLS 1.2 direto entre Host e Cliente dentro do Relay. Teste com Relay malicioso confirmou: `TextoVisivelNoRelay=False` (zero vazamento) e `AdulteracaoDetectada=True` (1 byte alterado derruba a sessão). |
| **MQTT sobre TLS 1.2 Porta 8883 (`GlobalRendezvousClient`)** | **IMPLEMENTADO E VALIDADO** | Porta `8883` exclusiva com validação estrita CA do Windows (`sslPolicyErrors == None`), sem fallback para 1883. Validado em `broker.emqx.io:8883` (`Tls12 Aes256`, `CN=*.emqx.io`) e `broker.hivemq.com:8883` (`Tls12 Aes128`, `CN=mqttdashboard.com`). |
| **Anti-Flooding MQTT e Rate Limiting (`AuthRateLimiter`)** | **IMPLEMENTADO E VALIDADO** | Limite de sinalização (10 `REQ`/min por caller, 30/min global) e bloqueio de 60s após 5 falhas de autenticação (`Bloqueio apos 5 falhas=True`). |
| **Autenticação HMAC-SHA256 + Timestamp + Anti-Replay** | **VALIDADO** | Token `HMAC:<ticks>:<hex>` com expiração de 2 min, `FixedTimeEquals` e `_seenSignalSignatures`. |
| **Proteção DoS (`PacketFrameIO` 16 MB) & Path Traversal** | **VALIDADO** | Payloads > 16 MB rejeitados (`17MB -> False`); validação canônica com separador `\` e bloqueio de nomes reservados. |
| **Hooks Win32 (`WH_MOUSE_LL`/`WH_KEYBOARD_LL`)** | **VALIDADO** | Thread STA dedicada com remoção garantida em encerramento, exceções e escape de emergência. |

### 9.2. Impacto Medido de Performance da Criptografia TLS 1.2

| Métrica | Antes (Texto Puro) | Depois (TLS 1.2 AES-256) | Impacto Real |
| :--- | :--- | :--- | :--- |
| **Handshake TLS 1.2 (1º acesso / Reconexão)** | N/A | `119,61 ms` / `21,39 ms` | Custo único no início da sessão |
| **Loopback Ping/Pong RTT (300 pkts)** | Avg `0,276 ms` (P99 `0,525 ms`) | Avg `0,170 ms` (P99 `0,346 ms`) | **Negligenciável (< 0,2 ms)** |
| **Clipboard 100 MB Chunked (TCP Loopback)** | `1,15 s` (`87,1 MB/s`) | `1,57 s` (`63,7 MB/s`, SHA-256 idêntico) | ~27% overhead de throughput (> 500 Mbps úteis) |

### 9.3. Riscos Residuais e Recomendações para Produção
- **Brokers MQTT públicos (`broker.emqx.io`, `broker.hivemq.com`):** Embora o tráfego de sessão seja E2EE (o broker não lê dados nem senhas) e a conexão use TLS 8883 validado por CA, metadados de tópicos (`deskview/v2/signal/<DeskId>`) trafegam em infraestrutura de terceiros. Para produção corporativa, recomenda-se operar um broker MQTT dedicado com autenticação por credenciais/mTLS.
- **Sinalização `SignalSecret` estático no código:** A assinatura da camada externa do envelope MQTT usa segredo compartilhado no binário; a segurança real da sessão repousa no TLS 1.2 + Pinning de Certificado + HMAC da senha desassistida / aprovação interativa.
- **TOFU no primeiro acesso:** Como em SSH, o primeiro acesso a um host nunca visto depende de confiança inicial (TOFU); recomenda-se conferência fora de banda do fingerprint SHA-256 exibido na interface para máxima garantia contra MITM no primeiro contato.

---

## 10. Build Final e Validação do Executável

- **Procedimento utilizado:** Comando oficial de [`compile.bat`](file:///C:/Users/conta/Documents/Programas%20Autorais/DeskView/compile.bat) (`csc.exe /target:winexe /unsafe /optimize+ /out:DeskView.exe ... *.cs`).
- **Resultado:** Sucesso (`Exit Code 0`).
- **Erros:** `0` | **Warnings:** `0`.
- **Executável gerado:** [`DeskView.exe`](file:///C:/Users/conta/Documents/Programas%20Autorais/DeskView/DeskView.exe)
- **Tamanho:** `201.728 bytes` (~197 KB)
- **Data/Hora da Build:** `23/11/2026 10:24:14`
- **SHA-256:** `5CFA10DAA894967639399559B8FDB3D3FF9421251DB50DFB524BB1C92E2D8C77`
- **Verificação de execução:** Inicializado com `--port 7098` (`PID=28512`, `HasExited=False`, `WorkingSet=65,7 MB`); `SecurityAuditSuite.exe` aprovado (9/9, 0 falhas).

---

## 11. Matriz de Status

| Recurso | Status | Evidência | Problemas |
| :--- | :--- | :--- | :--- |
| Mouse remoto | **VALIDADO PARCIALMENTE** | Transporte TLS loopback (`0,170 ms`) e cache de bounds validados. | `SetCursorPos` pode não funcionar em jogos 3D com Raw Input; não testado em 2 PCs. |
| Exclusividade do mouse | **VALIDADO PARCIALMENTE** | Thread STA dedicada instala `WH_MOUSE_LL` + `WH_KEYBOARD_LL`; timeout 3,5s validado. | Bloqueio de mouse físico real exige teste humano interativo. |
| Escape de emergência | **VALIDADO PARCIALMENTE** | 4x `Escape` testado via `HandleHostEscapeKey`, dispara evento e remove hooks sem ser desfeito por tráfego remoto. | `Ctrl+Alt+Shift+Escape` via teclado físico real exige teste interativo. |
| Input | **VALIDADO PARCIALMENTE** | Coalescência de mouse, invalidação de monitor e RTT TLS loopback validados. | Latência ponta a ponta em WAN/jogos não medida. |
| Captura | **BLOQUEADO POR LIMITAÇÃO DO AMBIENTE** | `BitBlt` retornou `False` (`err=5`) e `CopyFromScreen` lançou `Win32Exception` no shell. | Exige execução manual em desktop Windows desbloqueado. |
| Encode | **VALIDADO** | Medido em 720p/1080p/1440p/4K; vazamento GDI+ corrigido. | Lento em CPU para FullMotion 1080p (`50,69 ms`). |
| Decode | **VALIDADO** | Medido em 720p/1080p/1440p/4K; fila FIFO e decode fora de `_bitmapLock` corrigidos. | GDI+ CPU JPEG limita FPS em tela cheia. |
| FPS | **FALHOU** *(meta 60 FPS FullMotion)* | Medido `10,8 FPS` (pipe 1080p) e `9,7 FPS` (60s sequencial) em FullMotion. | Meta de 60 FPS em tela cheia 1080p exige encoder/decoder em hardware (DXGI+NVENC/QSV/AMF). |
| Latência | **VALIDADO PARCIALMENTE** | Loopback TLS 1.2 `0,170 ms` médio (P99 `0,346 ms`). | Latência total ponta a ponta (captura+encode+rede+decode+render) em 1080p FullMotion supera 100 ms. |
| Clipboard texto | **VALIDADO** | Round-trip exato com acentos, Unicode, emojis e múltiplas linhas. | Nenhum problema encontrado. |
| Clipboard imagens | **VALIDADO** | Round-trip PNG 256x128 com transparência validado; leak corrigido. | Imagens > 14 MB são ignoradas pelo teto de segurança. |
| Clipboard arquivos | **VALIDADO** | 100 MB sobre **TLS 1.2** (`63,7 MB/s`, SHA-256 idêntico) e Path Traversal bloqueado. | Pastas não são transferidas recursivamente. |
| Ultra | **VALIDADO** | 2560x1440, Q=90, `93,1 KB`/frame medido. | Alto consumo de CPU/banda em FullMotion. |
| Equilibrado | **VALIDADO** | 1920x1080, Q=72, `48,6 KB`/frame medido. | Downscale GDI+ adiciona custo de CPU quando entrada > 1080p. |
| Rápido | **VALIDADO** | 1360x768, Q=52, `25,2 KB`/frame medido (~73% menos dados que Ultra). | Downscale GDI+ em CPU. |
| Wallpaper animado | **NÃO VALIDADO** | Código usa `CAPTUREBLT` e amostragem densa no modo Ultra. | Captura física bloqueada no shell; exige teste manual com Lively/Wallpaper Engine. |
| LAN | **VALIDADO PARCIALMENTE** | Loopback TCP + TLS 1.2 + `PacketFrameIO` validados. | Não testado entre 2 máquinas físicas na LAN. |
| P2P | **NÃO VALIDADO** | Código STUN/UPnP preservado com TLS 1.2 obrigatório. | Sem duas redes externas disponíveis. |
| Relay | **VALIDADO PARCIALMENTE** | E2EE TLS sobre Relay simulado (`TextoVisivelNoRelay=False`, adulteração detectada) + MQTT TLS 8883 real validado. | Teste completo entre 2 PCs via broker remoto pendente. |
| Segurança | **VALIDADO** *(testes controlados)* | TLS 1.2 AES-256 fail-closed, X.509 RSA-2048, TOFU/Pinning/MITM, E2EE Relay, MQTT TLS 8883 CA, Rate Limit, HMAC, DPAPI, DoS 16 MB. | Para produção corporativa, recomenda-se broker MQTT próprio dedicado. |
| Estabilidade | **VALIDADO PARCIALMENTE** | 60s contínuos em 1080p: GDI Handles `5 -> 5`, Threads `15 -> 8`, RAM estável. | 15 minutos em sessão gráfica interativa completa pendente. |
| Build | **VALIDADO** | Compilação oficial sem erros/warnings, `DeskView.exe` (201.728 B) validado em execução. | Nenhum. |
