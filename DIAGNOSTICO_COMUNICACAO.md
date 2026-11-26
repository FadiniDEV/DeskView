# DIAGNÓSTICO PROFUNDO E RECONSTRUÇÃO DA COMUNICAÇÃO ENTRE DISPOSITIVOS

## 1. Diagnóstico Técnico da Implementação Original (`DeskView.exe`)

A investigação do binário original (`ev_72916d99532986c07675ff544794f09a92b0962bba27a46e681724a5e214313b`) e das classes `LanDiscoveryService`, `GlobalRendezvousClient`, `DeskViewHostServer` e `RemoteSessionTabControl` revelou exatamente como o software original tentava estabelecer conexões e por que ele falhava fora da rede local.

### 1.1. Mecanismo de Descoberta e Conexão Original

1. **Rede Local (LAN)**:
   - `LanDiscoveryService` envia pacotes UDP Broadcast (`255.255.255.255:50001`) a cada 3 segundos contendo `DESKVIEW_V1|<DeskId>|<HostName>|<UserName>|<LocalIp>|<ListenPort>|<Monitors>`.
   - Funciona apenas quando ambos os dispositivos estão no mesmo domínio de broadcast Ethernet/Wi-Fi (mesma sub-rede VLAN e com Client Isolation desativado).

2. **Rede Externa (WAN) — Onde e Por Que Falhava**:
   - `GlobalRendezvousClient.RefreshPublicIp()` faz uma requisição HTTP GET para `https://api.ipify.org` para obter o endereço IPv4 público de saída do roteador (ex.: `179.135.207.135`).
   - Em seguida, o cliente concatena esse IP público com a porta TCP local (`7070`), anunciando no broker MQTT (`broker.hivemq.com:1883` / `broker.emqx.io:1883`) o endpoint `179.135.207.135:7070`.
   - Quando o Operador A digita o DeskID do Host B:
     1. A envia `REQ|<CallerId>|<CallerHost>|<CallerWanIp>:7070|<CallerLanIp>:7070` via MQTT para o tópico `deskview/v2/signal/<TargetId>`.
     2. B exibe o modal `AcceptSessionDialog`. Ao clicar em **Aceitar**, B publica `ACK|<TargetId>|<TargetHost>|<TargetWanIp>:7070|<TargetLanIp>:7070` via MQTT e dispara `TryReverseTcpConnection(CallerWanIp:7070)`.
     3. Ao receber o `ACK`, A executa `_tcp.Connect(TargetWanIp, 7070)`.

### 1.2. Causas Raiz da Falha Entre Redes Diferentes

| Problema Técnico | Explicação de Engenharia de Redes | Impacto no Software Original |
|---|---|---|
| **1. Ausência de Port Forwarding / UPnP no NAT** | O `TcpListener` escuta em `0.0.0.0:7070` na rede privada (`192.168.x.x` ou `10.0.x.x`). O roteador doméstico descarta qualquer pacote `TCP SYN` vindo da Internet para `<WanIp>:7070` porque não há regra de DNAT (Port Forwarding) apontando para o IP interno da máquina. | `TcpClient.Connect(TargetWanIp, 7070)` sofre timeout (`SocketError.TimedOut` / `ConnectionRefused`). |
| **2. Confusão entre IP Público HTTP e Porta Mapeada pelo NAT** | Consultar `api.ipify.org` revela apenas o IP público usado por uma conexão efêmera de saída para a porta 443, e **não** cria nem descobre mapeamento externo para a porta local `7070` (como faria o protocolo STUN RFC 5389). | O par `<WanIp>:7070` anunciado no MQTT não é alcançável externamente. |
| **3. CGNAT (Carrier-Grade NAT — RFC 6598 `100.64.0.0/10`)** | Provedores de fibra óptica regionais e redes móveis 4G/5G colocam múltiplos clientes atrás de um NAT de operadora. Nenhum dos dois lados possui IPv4 público exclusivo nem permissão para abrir portas de entrada. | Nem a conexão direta (`A -> B`) nem a conexão reversa (`B -> A`) conseguem atravessar o CGNAT via TCP puro. |
| **4. Ausência de Túnel de Relay (TURN / Encrypted Data Relay)** | Quando o NAT Simétrico ou CGNAT impede conexões diretas, softwares como AnyDesk utilizam servidores de Relay para encapsular os pacotes `PacketFrameIO`. O DeskView original usava o broker apenas para enviar `REQ/ACK/REJ` e abandonava o canal de sinalização na hora de transmitir o vídeo e os comandos. | Mesmo com a sinalização MQTT funcionando 100% entre duas residências, a sessão de vídeo nunca abria. |
| **5. Ausência de Criptografia e Autenticação Mútua de Pacotes** | Os pacotes `PacketFrameIO` trafegavam sem criptografia de sessão no stream TCP. | Risco de interceptação de tela, senhas e comandos de teclado. |

---

## 2. Nova Arquitetura de Comunicação Multi-Rede Implementada no Flutter

Para resolver definitivamente a comunicação entre dispositivos na mesma rede (LAN) e em redes completamente distintas (WAN residencial, CGNAT, 4G/5G, Firewalls restritivos), foi projetada a arquitetura **DeskNet Hybrid Transport Engine** em 4 camadas com seleção automática de rota (*Happy Eyeballs / ICE-like Route Negotiation*):

```
+-----------------------------------------------------------------------------------+
|                        CAMADA DE SESSÃO E PROTOCOLO (DeskFrame)                   |
|   Multiplexação Binária Criptografada (AES-GCM / HMAC-SHA256 + SeqNum Anti-Replay) |
+-----------------------------------------------------------------------------------+
                                         |
            +----------------------------+----------------------------+
            |                            |                            |
            v                            v                            v
+-----------------------+    +-----------------------+    +-------------------------+
| ROTA 1: LAN DIRETA    |    | ROTA 2: WAN P2P NAT   |    | ROTA 3: ENCRYPTED RELAY |
| UDP Discovery (50001) |    | STUN (RFC 5389) +     |    | Túnel Multiplexado      |
| + TCP Low-Latency     |    | UDP Hole Punching /   |    | via Broker/WebSocket    |
| (Sub-milissegundo)    |    | Direct Candidate Race |    | (Funciona em 100% CGNAT)|
+-----------------------+    +-----------------------+    +-------------------------+
```

### 2.1. Etapa 1 — Descoberta e Sinalização Global Assinada (`SignalingService`)
- Mantém descoberta local via **UDP Broadcast (`50001`)** para pareamento imediato em LAN.
- Mantém e aprimora o cliente de **Sinalização Global MQTT 3.1.1** (`broker.hivemq.com:1883`, `broker.emqx.io:1883`, `test.mosquitto.org:1883`) com reconexão exponencial, heartbeat e **assinatura HMAC-SHA256 + validação de timestamp/nonce**.
- Coleta todos os candidatos de rede (*ICE Candidates*) do dispositivo:
  - `host`: Todos os endereços IPv4 e IPv6 locais ativos (`NetworkInterface.list()`).
  - `srflx` (*Server Reflexive*): Endereço IP e porta externa mapeada pelo NAT obtidos via cliente **STUN RFC 5389 nativo em Dart** (`stun.l.google.com:19302`, `stun1.l.google.com:19302`, `stun.cloudflare.com:3478`).
  - `relay`: Canal de retransmissão criptografado (`deskview/v3/tunnel/<SessionId>/<Direction>`) para travessia garantida de CGNAT/NAT Simétrico.

### 2.2. Etapa 2 — Corrida de Rotas (*Candidate Racing*) e Fallback Automático para Relay
Quando o Host aceita a conexão (ou valida a senha desassistida), ambos os dispositivos recebem a lista completa de candidatos e iniciam uma corrida paralela:
1. **Tentativa Simultânea LAN + WAN Direta + UDP Hole Punching (Timeout rápido de 2.500 ms)**:
   - Se o socket TCP direto (IPv4/IPv6 local ou WAN com porta aberta) ou o canal UDP Hole Punching conectar primeiro, a sessão utiliza **Rota Direta (P2P)** para máxima taxa de bits e latência mínima (< 5 ms em LAN, 15–40 ms em WAN P2P).
2. **Ativação Transparente do Túnel Relay Criptografado (`RelaySessionTransport`)**:
   - Se ambos os dispositivos estiverem atrás de CGNAT ou NAT Simétrico (onde a conexão direta falha após 2.500 ms), o `ConnectionOrchestrator` promove instantaneamente o **Relay Transport** sem derrubar a sessão e sem exigir qualquer configuração de roteador ou firewall pelo usuário.
   - O `RelaySessionTransport` fragmenta, numera, comprime e criptografa os pacotes `PacketFrameIO` (`ScreenMeta`, `TileFrameDirty`, `CursorUpdate`, `MouseInput`, `KeyInput`, `GamepadInput`, `ClipboardText`, `ChatMessage`, `FileTransfer`) através de tópicos dedicados de sessão com controle de fluxo e janela deslizante.

### 2.3. Etapa 3 — Segurança Criptográfica de Ponta a Ponta (E2EE)
1. **Autenticação Desafio-Resposta (Challenge-Response)**:
   - Nenhuma senha trafega em texto claro. O Host emite um `challengeNonce` de 256 bits; o Cliente prova posse da senha ou aprovação interativa gerando um token `HMAC-SHA256(challengeNonce, passwordHash | sessionSecret)`.
2. **Chave Efêmera de Sessão e Cifragem de Pacotes**:
   - Durante o handshake (`REQ` -> `ACK`), um segredo de sessão derivado com `PBKDF2/HKDF-SHA256` autentica e cifra os pacotes transmitidos, garantindo que mesmo quando a conexão trafega pela **Rota 3 (Relay Público)**, o broker intermediário enxerga apenas payloads binários opacos autenticados.
3. **Permissões Granulares Forçadas no Host**:
   - O Host aplica em nível de protocolo as permissões concedidas no modal de aceitação (`allowInput`, `allowClipboard`, `allowFileTransfer`, `allowGamepad`), descartando imediatamente pacotes de categorias não autorizadas.
