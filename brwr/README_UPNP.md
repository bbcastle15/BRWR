# Patch UPnP per BRWR

Questa patch aggiunge il tentativo automatico di port mapping quando premi
**Crea sala PvP**.

BRWR prova ad aprire sul router:

- TCP 8080 -> HTTPS della build browser
- TCP 27847 -> WSS multiplayer

Se UPnP non è disponibile, la creazione della sala **non fallisce**: resta
utilizzabile in LAN e viene mostrato un messaggio esplicito.

## File

Copia/sovrascrivi nella root `brwr`:

- `upnp_manager.gd` (nuovo)
- `main_menu.gd` (aggiornato)
- `tools/setup_tls.ps1` (aggiornato)

La patch presuppone la patch HTTPS/WSS già applicata (`tls_config.gd`,
`web_host.gd`, `online_session.gd`, ecc.).

## Test Internet con l'IP pubblico attuale

Nel tuo caso l'IPv4 pubblico rilevato esternamente era:

```text
93.34.226.155
```

Prima di avviare il test Internet, rigenera il certificato includendo
quell'indirizzo:

```powershell
cd C:\Users\bigba\Desktop\BRWR\brwr

powershell -ExecutionPolicy Bypass -File .\tools\setup_tls.ps1 `
    -Force `
    -PublicAddress 93.34.226.155
```

La CA mkcert resta la stessa. Se il laptop client l'ha già installata non
serve reinstallarla, salvo che tu abbia cancellato/rigenerato la CA mkcert.

Poi avvia:

```text
Ospita-Online.cmd
```

e premi **Crea sala PvP**.

Se UPnP funziona, nella UI dovresti vedere qualcosa come:

```text
UPnP OK · TCP 8080 e 27847 aperte · IP pubblico router: 93.34.226.155
```

e il link dovrebbe iniziare con:

```text
https://93.34.226.155:8080/#code=...
```

Aprilo dal laptop collegato a un'altra rete.

## Possibili risultati

### UPnP OK + IP pubblico

Le porte sono state richieste al router automaticamente. Prova il link dal
client esterno.

### Router non trovato / mapping rifiutato

UPnP non è disponibile o è disabilitato sul router. Senza accesso al router,
un server/relay pubblico o una connessione direttamente raggiungibile non c'è
un modo per forzare dall'esterno il NAT ad accettare le connessioni.

### WAN IP privato o 100.64.0.0/10

Possibile CGNAT/doppio NAT. Anche con UPnP sul router locale l'IPv4 pubblico
potrebbe non essere direttamente raggiungibile.

## Nota TLS

Se l'IP pubblico cambia, il certificato non corrisponde più al nuovo IP.
Rileva il nuovo indirizzo e riesegui:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\setup_tls.ps1 `
    -Force `
    -PublicAddress NUOVO_IP
```
