# Correzioni Geomancy, Chaos e interazione con il tavolo

## Comportamento

| Segnalazione | Correzione |
| --- | --- |
| Cemetarial Mist durante Explore | La trappola si risolve subito. Explore riprende dalla posizione effettiva del mago, permette il movimento rimanente e attiva la stanza finale. La stanza corrente permette di fermarsi; viene consumato un solo token fisico. |
| Disorder Light | I Vastum rimossi scompaiono definitivamente, anche dopo un aggiornamento del tavolo o della vista remota. |
| Mano e menu laterale | I pannelli intercettano i clic e sono su livelli superiori al tavolo. Non si aprono più carte o riserve sottostanti. |
| Dark Path | Dopo il modello viene chiesta la stanza con Vastum in cui posizionarlo. La scelta funziona anche sul client. |
| Cauda Draconis Dark | La scuola viene chiesta separatamente per ciascuna delle due carte, conservando la prima pesca durante la seconda scelta. |
| Chaos | La carta fisica rimane fuori dalle pile durante la risoluzione, poi torna in fondo al Grimoire. Non viene scartata né eliminata se Forgotten. Riferimento: Codex Arcanum, pagina 10. |
| Ethereal Tentacles | Il posizionamento usa direttamente le stanze con Vastum selezionabili. |
| Bersagli Vastum | Anello dorato quando selezionabili, verde quando selezionati. I token senza una scelta attiva non intercettano i clic. |
| Carcer e posizione Vastum | Carcer usa il sistema persistente esistente, con segnalino pubblico e rimozione al cleanup. I Vastum sono più in basso e lasciano leggibile l'effetto della stanza. |
| Theurge | Il bersaglio comprende qualsiasi modello e il mago stesso. Aggiornati selezione, guarigione e simboli della ricompensa nell'immagine. |

## Implementazione

- `game.gd`, `effect_resolver.gd`: ripresa di Explore, stato autorevole dei Vastum, pescate successive e risoluzione sospendibile di Chaos. Rimossi i due percorsi paralleli di stato per Carcer e per le carte rivelate da Chaos.
- `triggered_spell_manager.gd`, `data/spells.json`: Carcer usa `ActiveSpellState` e gli stessi trigger e marker delle altre spell persistenti.
- `network_projection.gd`, `beta_hud.gd`: il client ricostruisce i Vastum dallo stato dell'host e usa le opzioni serializzate per le scelte dirette sul tavolo, la rivelazione Chaos e la scelta dell'elemento jolly.
- `hand_overlay.gd`, `tabletop_shell.gd`: ordine dei livelli e intercettazione dei clic.
- `room.gd`: posizione del token Vastum sotto la pergamena.
- `data/quests.json`, `assets/quests/theurge.png`: bersaglio Model/Self. Prompt della modifica grafica in `tabletop-art-2026-10-10.json`.

Le posizioni, le carte e i Vastum restano nello stato di gioco. I nodi grafici ne mostrano il contenuto senza ricrearlo durante gli aggiornamenti.

## Verifiche

- Godot 4.7.2: importazione e parser senza errori.
- **82 controlli sulle regole superati**, inclusa l'intera sequenza Explore → Cemetarial Mist → movimento residuo → attivazione, e la variante che termina il movimento nella stanza corrente.
- **24 controlli UI/rete superati**, eseguiti sia headless sia con rendering nativo: clic reali sui pannelli e sui Vastum, selezioni sul client, marker Carcer pubblici e Chaos. Le due esecuzioni verificano gli stessi 24 casi.
- Ispezione visiva del tavolo con Vastum selezionabili, della mano e della Player Board con Carcer.
- JSON e riferimenti alle immagini delle spell validati.
- **533 controlli di regressione** su intestazione, layout da 2 a 6 e attivazione delle stanze superati. Test separato sulle presentazioni host/client: **PASS**.
- `git diff --check`: nessun errore.
- Pacchetto browser aggiornato in `output/web`: **68,2 MiB**, circa **67,2 MiB** con gzip. Importazioni ottimizzate solo nella copia di esportazione; originali conservati. Controllo del pacchetto: **EXPORTED PACK CHECK PASS**.

I test di rete utilizzano snapshot serializzati fra host e client locali. Non è stato effettuato un nuovo playtest Internet fra PC distinti. I controlli mirati non attestano che tutte le vecchie suite generali siano prive di errori; i risultati precedenti rimangono documentati in `tabletop-2026-10-10.md`.

Script, log e screenshot diagnostici sono fuori dal progetto: `C:/Users/bigba/AppData/Local/Temp/BRWR_validation_20261010/geomancy-chaos/`. Nessun commit automatico.
