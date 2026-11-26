# COMPATIBILIDADE E PRESERVAÇÃO DE DADOS

## 1. Diretórios de Persistência

A versão Flutter mantém compatibilidade total com os diretórios e arquivos do software original:

- **Windows**: `%AppData%\DeskView\` (`C:\Users\<Usuario>\AppData\Roaming\DeskView\`)
  - `deskview.conf` (Configurações gerais e identidade da máquina)
  - `saved_logins.dat` (Logins salvos para acesso rápido em 1 clique)
- **Área de Trabalho**: `%UserProfile%\Desktop\DeskView_Recebidos\` (Diretório padrão para arquivos recebidos)

---

## 2. Estrutura do Arquivo `deskview.conf`

Arquivo texto em formato `chave=valor`, codificado em UTF-8:

```properties
# DeskView Configuration File
ad.deskview.id=482910375
ad.deskview.fpr=a9f4c2e18b7304d2f9e1c0a5b8d23f109e8a7c6b5d4e3f2a1b0c9d8e7f6a5b4c
ad.deskview.pwd_hash=rV0p2...==
ad.deskview.pwd_salt=xYz12...==
ad.deskview.port=7070
ad.deskview.favorites=192.168.1.100:7070;482910375
ad.deskview.recent=192.168.1.100:7070;10.0.0.15:7070
```

### Especificação dos Campos:
| Campo | Tipo | Descrição |
|---|---|---|
| `ad.deskview.id` | String (9 dígitos numéricos) | Identificador DeskID permanente da máquina. |
| `ad.deskview.fpr` | String (64 chars hex) | Hash SHA-256 único (*fingerprint* criptográfico). |
| `ad.deskview.pwd_hash` | String Base64 | Hash HMAC-SHA256 da senha de acesso desassistido. |
| `ad.deskview.pwd_salt` | String Base64 (16 bytes) | Salt criptográfico aleatório gerado para a senha. |
| `ad.deskview.port` | Inteiro (1024..65535) | Porta TCP primária para escuta do servidor host (padrão `7070`). |
| `ad.deskview.favorites` | String (separada por `;`) | Lista de endpoints/DeskIDs marcados como favoritos. |
| `ad.deskview.recent` | String (separada por `;`) | Histórico das últimas até 12 sessões conectadas. |

---

## 3. Estrutura do Arquivo `saved_logins.dat`

Cada linha representa um login salvo, composto por 7 campos delimitados por pipe (`|`):

```
<DeskId_B64>|<HostName_B64>|<Endpoint_B64>|<SavedPassword_Cipher>|<MonitorCount>|<LastConnectedTicks>|<IsFavorite>
```

### Exemplo:
```
NDgyOTEwMzc1|Q29tcHV0YWRvciBSZW1vdG8=|MTkyLjE2OC4xLjEwMDo3MDcw|DPAPI:AQAAANCMnd8BF...|2|638549128000000000|1
```

### Especificação dos Campos:
1. **DeskId**: String Base64 do código de 9 dígitos.
2. **HostName**: String Base64 do nome amigável do computador.
3. **Endpoint**: String Base64 do par `IP:Porta` ou DeskID.
4. **SavedPassword**: Criptografada com prefixo identificador:
   - `DPAPI:<Base64>`: Cifrada com a API `ProtectedData` do Windows com entropia `DeskView.V2.Entropy.Salt.2026`.
   - `B64:<Base64>`: Fallback seguro quando executado em plataformas sem DPAPI.
5. **MonitorCount**: Inteiro indicando quantos monitores a máquina remota possui.
6. **LastConnectedTicks**: Data/hora no padrão Windows Ticks (`DateTime.Ticks`).
7. **IsFavorite**: `"1"` para favorito, `"0"` para normal.

---

## 4. Garantia de Inalterabilidade dos Dados

- **Interoperabilidade Bidirecional**: Tanto o `DeskView.exe` em C# quanto o novo `DeskView` em Flutter leem e gravam os mesmos arquivos sem corromper nenhuma entrada pré-existente.
- **Migração Transparente**: Se um usuário já utilizava o DeskView original, ao abrir a versão Flutter ele verá imediatamente seu mesmo DeskID, sua mesma senha desassistida configurada e todo o histórico de sessões recentes preservado intacto.
