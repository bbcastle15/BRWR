# Stanze alternative

Dal menu principale, **Stanze della Loggia · originali / alternative** permette
di scegliere una variante per ciascuna famiglia, ripristinare tutte le originali
o sorteggiare tra originale e alternative compatibili. La configurazione si
applica alla modalità solo-test e alle partite create dall'host online.

## Contenuto

| Stanza originale | Alternative giocabili |
| --- | --- |
| Black Rose Room | Deep Black Rose Room, Emerald Rose, Occult Black Rose Room |
| Crypt | Crypt of the Saint |
| Sacrificial Altar | Sacrificial Altar of Madness |
| Cemetery | Whales Cemetery |
| Summoner Room | Crusaders' Summoner Room |
| Alchemical Laboratory | Lost Alchemical Laboratory |
| Arena | Ludus Arena |
| Observatory | Abyssal Observatory |
| Bibliotheca | Bibliotheca of the Order |
| Sanctuary | Sanctuary of Anubis |
| Forge | Forge of the Void, Thorny Clearing |
| Treasure Room | Indoor Forest, Templars' Treasure Room |
| Garden | Life Fountain, Zen Garden |
| The Abyss | Abyss of Faith, Abyss of Hel |
| Oracle Room | Blasphemous Oracle Room |
| Pleasures Room | Ancient Pleasures Room |
| Throne Room | Skulls' Throne Room |
| Armory | Templars' Armory |

Sono presenti anche le definizioni grafiche di **Black Rose Room – Apocalypse**
e **Room of Rebirth**. Queste due stanze non sono selezionabili: le modalità
Libreria personale e Famigli Phoenix verranno implementate successivamente.

Aruspice, Pharaoh e Dagon sono stati aggiunti al database delle Evocazioni,
con le capacità necessarie alle nuove stanze. Le altre Evocazioni richiamate
riutilizzano le definizioni già esistenti.

## Identità e risoluzione

La stanza conserva l'identità della famiglia nella Loggia: Ludus Arena mantiene
`arena` come `room_id`, mentre `get_art_id()` restituisce `ludus_arena`.
Quest, coordinate, distanze e regole delle stanze fisse usano quindi gli stessi
identificativi di prima. Nome, effetti, ricompense e grafica provengono dalla
definizione scelta. Anche la proiezione di rete trasmette la variante.

`alternative_room_rules.gd` aggiunge clausole riutilizzabili alla pila di
risoluzione esistente. Non crea uno stato di gioco parallelo. I costi combinati
vengono verificati prima di consumare carte o Potere; i bersagli condivisi o
separati seguono il testo stampato. Le attivazioni ripetute di un'Evocazione
hanno scelte indipendenti. I movimenti avanzano un passo alla volta, lasciando
risolvere le reazioni tra i passi.

## Grafica e fonti

- Specifiche delle 26 stanze: `assets/rooms/alternatives_specs.json`.
- Inventario dei 104 file prodotti, stato e prompt: `assets/rooms/alternatives_manifest.json`.
- Percorsi: `assets/rooms/<id>.png`, `rebuilt/<id>.png`,
  `tokens/<id>_available.png`, `tokens/<id>_used.png`.
- Grafica generata con lo strumento integrato ImageGen a partire dal Codex e
  dai template già usati dal progetto: 26 set completi, ciascuno con tessera
  distrutta, tessera ricostruita e token di attivazione disponibile/esaurito.
  Testi in inglese, simboli di bersaglio, tipo stanza e slot Instabilità sono
  stati controllati visivamente. Gli originali PNG conservano la trasparenza;
  la compressione della versione Web viene applicata soltanto alla copia di esportazione.
- Fonte degli effetti: Codex Arcanum pp. 84–99; delle nuove Evocazioni:
  relative sezioni del Codex. Corrispondenze verificate anche nei regolamenti
  delle espansioni disponibili nella pagina ufficiale
  <https://app.ludusmagnusstudio.com/pages/_BRWR/brwrRules.php>.

## Verifiche eseguite

Con Godot 4.7.2: entrambi i lati delle 24 varianti giocabili, costi combinati,
conversioni con un bersaglio condiviso, bersagli indipendenti, doppia attivazione
di Dagon, tre clausole di movimento di Zen Garden, capacità di Aruspice/Pharaoh/
Dagon e sostituzione di un'Evocazione senza attivare gli effetti di rimozione.

Verificati inoltre: equivalenza con le Quest, configurazioni casuali da 2 a 6
giocatori, proiezione di rete, selezione e chiusura del nuovo menu, JSON e ID
univoci. La schermata di configurazione è stata renderizzata e ispezionata.

Il 15 ottobre 2026 è stata rigenerata la versione browser in `output/web`
con lo script di esportazione ottimizzata esistente. Importazione Godot e
controlli del pacchetto esportato superati: 104 texture caricate, 24 varianti
giocabili, due modalità rinviate e metadati della build aggiornati.
Dimensione del pacchetto: 91,4 MiB, circa 90 MiB compresso.

Non è stato eseguito un playtest remoto completo con più persone.
