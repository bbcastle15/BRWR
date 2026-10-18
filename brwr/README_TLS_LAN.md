# BRWR – TLS LAN patch

Questa patch trasforma il test browser multiplayer da:

- HTTP `:8080`
- WebSocket `ws://:27847`

a:

- HTTPS `:8080`
- WebSocket sicuro `wss://:27847`

senza cambiare l'architettura autoritativa della partita.

## File da copiare nel repository

Copia il contenuto della patch nella root `brwr`, sovrascrivendo i file omonimi:

- `main_menu.gd`
- `online_invite.gd`
- `online_session.gd`
- `web_host.gd`
- `tls_config.gd` (nuovo)
- `tools/host_web.ps1`
- `tools/setup_tls.ps1` (nuovo)
- `tools/install_client_ca.ps1` (nuovo)
- `.tls/.gitignore` (nuovo)

## 1. Host: installa mkcert

Da PowerShell:

```powershell
winget install FiloSottile.mkcert
```

Chiudi e riapri PowerShell se `mkcert` non viene trovato subito.

## 2. Host: genera certificato e CA di sviluppo

Dalla root `brwr`:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\setup_tls.ps1
```

Vengono creati localmente:

- `.tls\brwr-local.crt`
- `.tls\brwr-local.key`  **PRIVATA**
- `.tls\brwr-dev-rootCA.crt`  **pubblica, da installare sul client**

`.tls\.gitignore` impedisce di aggiungere questi file a Git.

Se l'IP LAN dell'host cambia:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\setup_tls.ps1 -Force
```

## 3. Client: installa SOLO la CA pubblica

Copia sul secondo laptop **solo**:

```text
brwr-dev-rootCA.crt
```

Non copiare mai `brwr-local.key`.

Sul client, dalla cartella dove hai copiato il certificato:

```powershell
powershell -ExecutionPolicy Bypass -File C:\percorso\BRWR\brwr\tools\install_client_ca.ps1 -CaFile .\brwr-dev-rootCA.crt
```

Chiudi completamente Chrome e riaprilo.

## 4. Host: avvia BRWR online

Usa il normale:

```text
Ospita-Online.cmd
```

oppure:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\host_web.ps1
```

Poi premi `Crea sala PvP`.

Il link deve iniziare con, per esempio:

```text
https://192.168.1.231:8080/#code=...
```

e il browser userà automaticamente:

```text
wss://192.168.1.231:27847
```

## 5. Firewall

Per il test LAN devono essere raggiungibili sul PC host le porte TCP:

- `8080`
- `27847`

## Nota importante

Questa configurazione con `mkcert` è adatta al test LAN/dev. Per Internet pubblico non conviene distribuire una CA di sviluppo agli utenti: servirà un dominio con certificato pubblico valido (o un reverse proxy/server pubblico).
