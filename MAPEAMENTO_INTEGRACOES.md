# MAPEAMENTO DE INTEGRAÇÕES EXTERNAS E NATIVAS

## 1. Integrações de Rede

### 1.1. Comunicação Peer-to-Peer Direta (TCP)
- **Protocolo**: TCP Streaming com framing binário de 5 bytes (Big/Little Endian estruturado).
- **Porta Padrão**: `7070` TCP (com range de fallback incremental até `7084`).
- **Flags de Socket**: `NoDelay = true` (desativação do algoritmo de Nagle para latência sub-milissegundo).
- **Buffer de Leitura**: Alocação dinâmica com limite estrito de segurança de 64 MB para prevenção contra estouro de memória (*out of memory*).

### 1.2. Descoberta em Rede Local (LAN UDP Broadcast)
- **Porta**: `50001` UDP.
- **Endereço de Envio**: `255.255.255.255` (Broadcast geral) e `127.0.0.1` (Loopback).
- **Frequência**: Intervalo fixo de 3.000 ms.
- **Payload**: Formato delimitado por barras verticais:
  `DESKVIEW_V1|<DeskId>|<MachineName>|<UserName>|<LocalIp>|<ListenPort>|<MonitorCount>`

### 1.3. Sinalização Global e Rendezvous (MQTT 3.1.1)
- **Protocolo**: MQTT 3.1.1 sobre TCP padrão (sem WebSocket para máxima leveza).
- **Brokers de Produção**:
  1. `broker.hivemq.com` (Porta `1883`) - Primário
  2. `broker.emqx.io` (Porta `1883`) - Secundário com failover automático
- **Tópicos Assinados**:
  - `deskview/v2/signal/<DeskId>` (QoS 0) - Canal privado de controle e solicitação de sessão.
  - `deskview/v2/peers/#` (QoS 0) - Descoberta de outros dispositivos conectados no mundo.
- **Tópicos Publicados**:
  - `deskview/v2/peers/<DeskId>` (Retain = true) - Presença e metadados globais.
  - `deskview/v2/signal/<TargetDeskId>` - Comandos `REQ`, `ACK`, `REJ`.
- **Autenticação e Assinatura**:
  - Chave secreta de integridade compartilhada (`DeskView.V2.Signal.HMAC.2026`).
  - Cada mensagem é assinada com os primeiros 16 caracteres hexadecimais do hash `HMAC-SHA256(Secret, Body)`.
  - Validação de janela de tempo: mensagens com desvio superior a 2 minutos em relação ao horário UTC são descartadas para evitar ataques de replay.

### 1.4. Serviços de Resolução de IP Público (WAN)
- `https://api.ipify.org`
- `https://icanhazip.com`
- `https://ifconfig.me/ip`
- User-Agent de chamada: `DeskView/7.0` (idêntico ao original).

---

## 2. Integrações Nativas de Sistema Operacional

### 2.1. Plataforma Windows (P/Invoke / FFI)
| Biblioteca Win32 | Função | Finalidade no DeskView |
|---|---|---|
| `user32.dll` | `SetProcessDPIAware` | Previne borrões e virtualização de coordenadas em telas High-DPI. |
| `user32.dll` | `SetCursorPos(x, y)` | Move o cursor para as coordenadas absolutas calculadas. |
| `user32.dll` | `mouse_event(flags, dx, dy, data, extra)` | Injeta cliques (esquerdo, direito, meio) e rolagem de scroll. |
| `user32.dll` | `keybd_event(bVk, bScan, dwFlags, extra)` | Injeta pressionamento e soltura de teclas de teclado. |
| `user32.dll` | `SendInput` | Versão modernizada para envio com suporte a scan codes físicos. |
| `gdi32.dll` | `BitBlt` / `CreateCompatibleDC` | Captura ultrarrápida da tela com acesso direto à memória gráfica. |

### 2.2. Plataforma Android
| API do Android | Classe / Serviço | Finalidade no DeskView |
|---|---|---|
| `MediaProjection` | `MediaProjectionManager` | Captura de quadros da tela do dispositivo móvel sem necessidade de root. |
| `Accessibility` | `AccessibilityService` | Injeção de gestos de toque, rolagem e cliques permitidos pelo usuário. |
| `KeyEvents` | `InputManager` | Emulação de teclas físicas e virtuais em sessões ativas. |
| `ClipData` | `ClipboardManager` | Sincronização em tempo real da área de transferência com o operador remoto. |
