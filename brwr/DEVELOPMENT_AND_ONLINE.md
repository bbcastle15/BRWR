# Laptop Windows e partita dal browser

## Avvio dell'host

Sul PC di sviluppo apri **Ospita-Online.cmd** nella cartella `brwr`.
Il comando esporta le modifiche attuali, verifica il pacchetto e apre il gioco.
Servono Godot **4.7.2** e i suoi template Web ufficiali, già presenti su questo PC.
Gli amici hanno bisogno solamente di un browser desktop con WebGL 2, come Chrome.
Non devono installare Godot, Git, Tailscale o altre applicazioni.

1. Scegli **Crea sala PvP**.
2. Per amici su Internet inserisci il tuo **IPv4 pubblico** nel campo dedicato.
   Per una prova sulla stessa rete domestica lascia il campo vuoto: viene
   proposto l'IP locale del PC. Con più schede di rete controlla che sia quello
   della connessione al router, oppure inseriscilo manualmente.
3. Premi **Copia link d'invito** e invialo ai partecipanti.
4. Aspetta che compaiano in sala, poi premi **Avvia partita**.
5. Lascia aperto il gioco sul PC host per tutta la partita.

Il link ha la forma `http://IP:8080/#code=CODICE_SALA&port=27847`.
Il codice cambia a ogni nuova sala. Il frammento dopo `#` viene letto dal gioco
e non viene incluso nella richiesta HTTP dei file.

Il menu limita attualmente il PvP a **2 giocatori** perché il database contiene
solo due maghi e due scuole implementati. Il trasporto e la sala gestiscono da
2 a 6 posti; le partite con più di due giocatori richiedono ulteriori contenuti.
La modalità solo-test mantiene il flusso locale precedente.

Se il launcher non trova il motore:

```powershell
./tools/host_web.ps1 -Godot 'C:/percorso/Godot_v4.7.2-stable_win64_console.exe'
```

Sul laptop installa i template da **Editor > Gestisci modelli di esportazione**.
Per esportare senza avviare una sala aggiungi `-BuildOnly`.
File generati: `output/web`; log: `output/web-export.log` e
`output/web-export-check.log`. Il vecchio ZIP Windows non contiene questa build
browser: per ospitare usa il nuovo launcher dal repository aggiornato.

## Cosa fanno gli amici

1. Aprono il link completo in Chrome sul PC e aspettano il caricamento.
2. Premono **Entra nella partita**: indirizzo e codice sono già compilati.
3. Aspettano che l'host avvii e scelgono il proprio mago/scuola quando richiesto.

La build attuale comprende circa **460 MB** di download compresso, soprattutto
immagini: il primo caricamento dipende dalla velocità di upload dell'host.
Il browser usa le stesse scene, carte e risolutori del gioco. L'host conserva
lo stato autorevole; ogni ospite riceve solo la propria mano e le proprie carte
nascoste, più le informazioni pubbliche. L'host è fidato e conosce lo stato completo.
Le scelte fuori turno o appartenenti a una richiesta superata vengono rifiutate.

Tasto destro: trascina la visuale. Rotella: zoom. Home: tavolo completo.
Il banner superiore indica il giocatore che deve rispondere. In browser
**Torna al menu** abbandona la partita; la scheda si chiude con i comandi di Chrome.
Mantieni la scheda attiva: la sospensione delle schede in background può
interrompere la connessione. Non sono ancora disponibili riconnessione o
salvataggio: una disconnessione sospende la partita per tutti.

## Fastweb: rendere il link raggiungibile su Internet

Chrome è il browser; il modello del router non è ancora stato identificato.
Il server integrato ascolta su queste due porte del PC host:

| Servizio | Protocollo | Porta esterna e interna |
| --- | --- | --- |
| Download del gioco | TCP | 8080 |
| Connessione alla partita | TCP | 27847 |

1. Trova l'IPv4 **locale** del PC con `ipconfig` (scheda Ethernet/Wi-Fi in uso).
   Prenota quell'indirizzo nel DHCP del router, per evitare che cambi.
2. Nel port mapping inoltra entrambe le porte TCP a quell'IPv4 locale.
   Le vecchie istruzioni UDP 27847 appartenevano al trasporto ENet precedente.
3. Consenti il programma Godot nel firewall Windows per queste connessioni.
   Non serve disabilitare il firewall né mettere il PC in DMZ.
4. Verifica con Fastweb che la linea abbia un IPv4 pubblico raggiungibile,
   senza CGNAT. Se è condiviso, richiedi un IPv4 pubblico all'operatore.
   Il solo inoltro delle porte non supera il CGNAT.
5. Inserisci l'IPv4 pubblico nel menu e prova il link da un'altra rete,
   per esempio dal PC dell'amico. Una prova dalla stessa LAN non verifica
   l'accessibilità da Internet; alcuni router non supportano il ritorno verso
   il proprio IP pubblico dall'interno della rete.

Percorsi ufficiali, secondo il modem:

- **NeXXt:** da MyFastweb nel browser, Gestisci NeXXt → La mia rete / Impostazioni
  → Altre impostazioni → Internet → Port Mapping.
  [Guida Fastweb NeXXt](https://www.fastweb.it/myfastweb/assistenza/guide/configurazione-fastweb-nexxt/).
- **FASTGate:** da casa apri `http://myfastgate`, poi Avanzate → Configurazione
  manuale porte → Associa nuovo port mapping.
  [Guida Fastweb FASTGate](https://fastweb.it/myfastweb/assistenza/guide/FASTGate).

Questa configurazione serve solo all'host. Agli amici basta il link.
Se l'IP pubblico cambia, aggiorna il campo e invia il nuovo link.
Non sono state modificate automaticamente impostazioni del router o del firewall.
La raggiungibilità esterna deve ancora essere provata sulla tua linea Fastweb.

Il server integrato usa **HTTP e WebSocket senza TLS**: il traffico non è cifrato.
HTTPS/WSS richiederebbe una configurazione aggiuntiva con un certificato;
non basta sostituire `http` con `https` nel link.

## Aggiornamenti

Chiudi la partita e riapri **Ospita-Online.cmd** dopo le modifiche. Il launcher
esporta il working tree attuale, compresi gli asset nuovi non ancora committati.
Host e browser caricano lo stesso pacchetto; una versione diversa viene rifiutata.
Gli amici ricaricano il nuovo link e ricevono i file aggiornati. Non avvengono
aggiornamenti durante una partita e il launcher non esegue commit, push o pull.

Per usare modifiche fatte sull'altro PC, sincronizza prima il repository come
descritto sotto. I vecchi ZIP rimangono fermi alla versione con cui sono stati
prodotti; il vecchio `Gioca.cmd` con auto-update vede solo i commit pubblicati.

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

Documentazione: [esportazione Web di Godot](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html),
[WebSocketMultiplayerPeer](https://docs.godotengine.org/en/stable/classes/class_websocketmultiplayerpeer.html).
