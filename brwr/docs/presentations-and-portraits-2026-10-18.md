# Presentazioni, Potere e ritratti — 18 ottobre 2026

## Comportamento

- Ogni spell in risoluzione viene presentata a schermo intero e aspetta un
  click prima di proseguire. Il lato attivo è indicato da una cornice dorata;
  le carte a effetto singolo usano la carta intera. Una risorsa mancante mostra
  le regole del lato selezionato anziché una finestra vuota.
- Settare una Trap/Protection mostra la PlayerBoard e anima il segnalino sul
  retro della carta, mantenendo privata la sua identità. La spell viene
  presentata pubblicamente quando si innesca. Anche il marker Permanent usa
  l'animazione di piazzamento.
- I segnalini Potere scorrono tra le caselle, conservando la disposizione
  centrata quando più giocatori condividono un punteggio. Se una finestra
  copre il tavolo, il movimento visivo aspetta che sia chiusa; il punteggio
  del gioco è aggiornato immediatamente.
- Un guadagno della Rosa Nera richiama temporaneamente la PowerBoard con lo
  zoom, poi ripristina la visuale precedente. Zoom e trascinamento manuali
  interrompono il richiamo.
- Tutte le 45 definizioni di evocazioni che sono modelli dispongono di un
  ritratto circolare: i tre ritratti dedicati esistenti e 42 inquadrature delle
  illustrazioni già fornite. Cornice del proprietario, numero della copia,
  tooltip, ispezione e selezione dei bersagli restano operativi. Gli
  Equipment continuano a non produrre pedine sulla Loggia.
- Heka è completa e inclusa nelle nove scuole selezionabili. Ogni partita ne
  estrae sei; Heka non è quindi obbligatoriamente presente in ogni partita.

## Implementazione

La pausa usa gli stessi frame di risoluzione e `card_presentation` esistenti
in `game.gd`, senza uno stato delle spell parallelo. `tabletop_shell.gd`
gestisce sovrimpressioni, evidenziatura e animazioni dei marker.

In online, `online_session.gd` accetta la conferma soltanto dal giocatore
associato alla presentazione e per il suo numero seriale corrente. Gli altri
giocatori possono chiudere localmente l'immagine senza avanzare gli effetti.
La prima proiezione di rete posiziona direttamente i segnalini Potere;
gli aggiornamenti successivi vengono animati da `power_board.gd`.

`evocation_token.gd` usa le immagini originali tramite `AtlasTexture`, senza
duplicare o alterare le PNG. Le inquadrature normalizzate sono in
`assets/tokens/evocations/portraits.json`, incluso esplicitamente nell'export.
Lo shader circolare tiene conto della regione nell'atlante. Gaea usa la carta
evocazione già presente in `assets/spells/gaea.png`; Janara usa il ritratto
sulla spell Woodland Spirit. Le immagini delle carte rimangono intatte.

## Verifiche

Godot 4.7.2:

- 156 controlli su Heka, pausa e click reale sulla spell, lato attivo,
  identità privata delle Trap, animazione del marker, conferme online
  autorizzate/scadute, percorso dei segnalini Potere, ripristino della camera
  e disponibilità/limiti delle inquadrature: nessun errore.
- Regressioni di gioco già esistenti: 115 controlli, nessun errore.
- Integrazione delle scuole: 56 controlli, nessun errore.
- Import/parser, JSON e `git diff --check` verificati.
- Render nativo a 1600×900 di spell, piazzamento Trap, Rosa Nera e tutti i
  ritratti ispezionato; non è stato simulato un intero playtest umano online.
- Pacchetto browser rigenerato in `output/web`: controllo risorse superato
  e gli stessi 156 controlli ripetuti sul PCK esportato senza errori.

Diagnostica e catture: `%TEMP%/BRWR_presentations_20261018`.
Le verifiche del protocollo usano il percorso di ricezione dell'host; resta
da provare questa interazione su due PC collegati via Internet.
