# Forgotten — implementazione del 13 ottobre 2026

Implementate le 42 Forgotten del Codex Arcanum, con entrambi i lati dove presenti, e le 31 tipologie di evocazioni Forgotten. Aggiunte anche Templarii e Umbra, necessarie alle carte, 13 Upgrade e 10 Jinx.

Fonti: Codex Arcanum pp. 60–67, 108–109 e sezioni sugli archetipi; regolamento Rebirth v1.2; FAQ ufficiali v1.2 del 5 febbraio 2026. Applicate le correzioni di Cursed Bond Dark (punti da Quest o Eventi) e Nocturnus (Forza per gli altri Incubi nella Loggia).

## Correzioni richieste

- Vial Sun, chiamata Vital Sun nel playtest: l'Instabilità effettivamente piazzata dall'effetto di una stanza verde contribuisce alla Quest. Conservato l'ID esistente `vial_sun`. Anche l'Instabilità centrale di una spell conserva i dati della stanza.
- Awareness Dark: primo piazzamento, attacco fisico facoltativo a un Modello a distanza 0 con Forza +4, secondo piazzamento indipendente.
- Sun Wukong: piazzamento facoltativo prima dell'attacco; scelta del bersaglio dalla nuova stanza; secondo piazzamento dopo l'attacco, anche quando non c'era un bersaglio attaccabile.

## Implementazione

Le definizioni restano in `data/spells.json` e `data/evocations.json`; `data/attachments.json` descrive Upgrade e Jinx. I nuovi moduli `forgotten_rules.gd`, `forgotten_evocations.gd`, `forgotten_passives.gd` e `forgotten_attachments.gd` estendono la pila di risoluzione, gli eventi e le scelte già esistenti.

Assegnazioni, Upgrade, Jinx e trofei conservati appartengono agli stati di maghi ed evocazioni. La plancia e la proiezione di rete leggono questi stati. Gli Incubi assegnati non occupano i tre slot per le evocazioni evocate; seguono il mago e hanno gestione distinta durante la fase Evocazione e la sconfitta. Sostituire un'evocazione non genera rimozione o sconfitta.

Fhtagn si risolve durante la pesca e scarta le altre Forgotten pescate insieme; non entra nella mano né tra le spell rivelate. Requiem può tornare in mano quando Mors viene sconfitto, anche durante la risoluzione di Requiem stessa. Le spell persistenti usano gli `ActiveSpellState` esistenti. Tendon Implant conclude il movimento prima della fine della fase Rosa Nera. Draco sostituisce anche le evocazioni concesse dagli Eventi.

## Carte incluse

A Burning World; Ancient Rebirth; Ancient's Symbol; Arcane Barrage; Awareness; Cursed Bond; Cursed Lantern; Denutrition; Dracaris; Epic Finale; Fhtagn; Final Formula; Gungnir; Inhabitant of Carcosa; Keeper of the Tomb; Keepers of the Temple; Killer Fog; Lava Flow; Manifestation; Moskstraumen; Nature's Fury; Night Falls; Opera; Prismatic Cage; Ragnarok; Requiem; Return to the Origins; Ruling the Heavens; Savage Fury; Shadow Form; Shapeless Mass; Spawn of Echidna; Supreme Fireball; The Colour Out of Space; Titan's Attack; Touch of the Old Ones; Violent Epidemic; Weaving the Destiny; Wish; Woodland Spirit; Word of Death; Wrath of the Jackal God.

## Verifiche

Eseguiti con Godot 4.7.2 in modalità headless, con script diagnostici esterni al repository:

| Suite | Controlli superati |
|---|---:|
| Vial Sun | 6 |
| Lati giocabili delle Forgotten, Awareness e Wukong | 317 |
| Evocazioni, Incubi, Jinx, Upgrade e sconfitta | 203 |
| Pesca, Requiem, fine fase, immunità e proiezione client | 32 |
| Persistenti, rami di Prismatic Cage e Upgrade | 36 |
| Eventi, sostituzione evocazioni e completamento fasi | 10 |
| Regressione scuola Druidic | 191 |
| Regressione precedenti otto correzioni | 105 |
| Regressione interfaccia e sincronizzazione client Druidic | 30 |
| **Totale** | **930** |

Controllati sintassi JSON, unicità e riferimenti degli ID, parser GDScript, diff e contenuto esportato Web. Le definizioni delle spell non Forgotten sono rimaste invariate rispetto all'inizio di questo intervento. I test automatici non sostituiscono una partita completa tra più PC; non è stato verificato ogni possibile abbinamento di reazioni.

## Immagini e build

Nessuna nuova immagine generata: le PNG vengono lette dal sistema esistente e, dove assenti, rimane il segnaposto con il nome. Per il caricamento diretto, il nome del file deve corrispondere all'ID JSON in `assets/spells` o `assets/evocations`. Ad esempio `return_to_the_origins.png` e `the_colour_out_of_space.png`.

La build in `output/web` include i nuovi dati e le regole. Dopo l'aggiornamento, riavviare l'host e ricaricare i browser dei partecipanti prima di cominciare una nuova partita, così tutti usano la stessa versione.

## Consultazione del mazzo e controllo del playtest

- `power_board.gd`: nello slot Evocation compare una pila cliccabile con il retro rosso già presente nell'illustrazione della Power Board. Non cambia la geometria della plancia.
- `reference_card_preview.gd`: il visualizzatore esistente permette di scorrere le 31 evocazioni Forgotten, in ordine alfabetico, con immagini grandi e copie disponibili calcolate dalla riserva effettiva. La consultazione non pesca carte e non modifica la partita. Restano utilizzabili i mazzi degli scarti delle scuole.
- `table_camera.gd`: la camera resta ferma mentre la finestra di consultazione è aperta. Si chiude con Close o Esc.
- `data/quests.json`: Summoner Wizard richiede 3 cubi; prima ne richiedeva erroneamente 2. Un effetto Summon aggiunge un solo progresso; completamento e risoluzione restano distinti.
- Rubedo: verificato il percorso già implementato, senza cambiare le regole. Prima si sceglie il modello da attaccare, poi si convertono fino a 3 dei suoi danni esistenti, mantenendo l'ordine dei cubi, e infine si infliggono i danni dell'attacco. Nessuna conversione su altri modelli nella stanza o nella stanza di partenza; nessuna conversione rinunciando all'attacco.

Verifiche aggiuntive con Godot 4.7.2: 30 controlli sulle regole e 53 sull'interfaccia e sulla proiezione client, tutti superati. Controllati parser, JSON, diff, immagini renderizzate della plancia e della consultazione, ed esportazione Web. La sincronizzazione è stata verificata con host/client locali simulati; nessuna nuova partita completa tra PC distinti.

Stato della presentazione di Jinx e Upgrade: implementati 10 Jinx e 13 Upgrade con relativi dati, effetti e stato di rete. Al momento i Jinx assegnati sono mostrati con nome e progresso sulla plancia; gli Upgrade sono elencati nell'ispezione dell'evocazione. Le illustrazioni e i mazzi consultabili di queste due categorie non sono ancora integrati. L'archetipo distinto Equipment non è implementato.
