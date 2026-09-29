# Laptop Windows e playtest online

## Giocare con un amico

Usate `BRWR-Windows-auto-update.zip`. Installate Git per Windows, estraete tutto
e avviate `Gioca.cmd`: prima di ogni avvio scarica il branch `master` da GitHub,
poi Godot importa le immagini e apre il menu. Se il repository e privato,
entrambi gli account GitHub devono avere accesso al repository.
Il clone del playtest sta in `%LOCALAPPDATA%\BRWR\playtest`, separato dallo sviluppo.
Il log sta in `%LOCALAPPDATA%\BRWR\playtest.log`.
Gli aggiornamenti comprendono soltanto modifiche committate e pubblicate con push.
Non avvengono durante una partita. Se il download fallisce, il gioco non parte
con una vecchia versione senza avvisare. Modifiche e commit locali nel clone
del playtest bloccano l'aggiornamento e non vengono sovrascritti.
Il motore Godot resta quello incluso nello ZIP: un cambio di motore richiede
un nuovo pacchetto. I vecchi ZIP senza questo launcher non si aggiornano.
Godot è incluso, non serve installarlo. La modalità solo-test mantiene il
controllo locale di tutti i giocatori (da 2 a 6).

Per il PvP non servono Tailscale, VPN o server intermedi.

1. In LAN l'amico usa l'IP locale dell'host. Su Internet usa il suo IP pubblico.
2. Per Internet, sul router dell'host inoltra **UDP 27847** all'IP locale del PC
   host e consenti Godot nel firewall Windows. La porta e UDP, non TCP.
3. L'host sceglie **Crea partita PvP** e comunica IP e codice di sei cifre.
4. L'amico inserisce IP e codice e sceglie **Entra nella partita PvP**.
5. L'host gioca P1, l'amico P2. L'ordine di turno viene deciso dal gioco.

Con CGNAT la connessione entrante IPv4 non arriva al router: richiedi un IP
pubblico al provider. Il gioco non apre automaticamente porte o regole firewall.
La connessione diretta tra reti diverse richiede una prova sui vostri due PC.

Ogni PC consulta la propria mano e le proprie carte nascoste anche fuori turno.
Le carte pubbliche rimangono consultabili da entrambi. Solo il giocatore che
deve rispondere riceve le opzioni private e può inviare la scelta. Le regole
girano sull'host; il client riceve una proiezione filtrata, senza il mazzo o la
mano dell'avversario. L'host è fidato e mantiene lo stato completo.

La prima versione supporta **due giocatori**, senza riconnessione/salvataggio:
se uno si disconnette la partita si ferma. Tornate al menu per una nuova partita.
Il banner superiore mostra fase e giocatore chiamato a decidere.
Tasto destro: trascina la visuale; rotella: zoom; Home: tavolo completo.

## Continuare lo sviluppo sul laptop

Il repository esistente è `https://github.com/bbcastle15/BRWR.git`.

Sul laptop, installa Git per Windows e clona:

```powershell
git clone https://github.com/bbcastle15/BRWR.git
```

Se il repository è privato, accedi con il tuo account GitHub quando richiesto.
Apri `BRWR/brwr/project.godot` con il Godot 4.7.2 incluso nello ZIP.
Usa questo clone per sviluppare, non quello automatico in LocalAppData.

Per lavorare regolarmente su due PC, dopo la revisione fai commit e push sul
PC di partenza, poi pull sull'altro. Evita due sessioni che modificano gli stessi
file contemporaneamente. Per ricevere aggiornamenti usa `git pull --ff-only`.

## Ricreare il pacchetto

Da PowerShell, nella cartella del progetto:

```powershell
./tools/package_windows.ps1 -GodotDirectory 'C:/percorso/Godot_v4.7.2-stable_win64.exe'
```

La directory deve contenere il Godot Windows originale. Il pacchetto include i
file del progetto, compresi gli asset nuovi non ancora tracciati; esclude cache,
output, backup e log. Non include la cartella Git o credenziali.

Documentazione: [multiplayer Godot e port forwarding UDP](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html).
