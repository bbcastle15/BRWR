# Interfaccia del tavolo — 3 ottobre 2026

## Risultato

- Playmat proporzionato ai limiti effettivi della Loggia e delle due plance comuni.
- Plance personali rimosse dal tavolo: il banner a sinistra apre la plancia corrispondente in una vista ampia. Sono riutilizzati gli stessi nodi PlayerBoard, con gli stessi bersagli e gli stessi callback.
- Giocatore di turno evidenziato nella lista, con contatore x/2 durante l'Action Phase. Una reazione di un altro giocatore non cambia l'indicatore del turno.
- Mano con schede Cards / Quests. Le quest sono divise in Active, Completed e Solved; la preparazione provvisoria sopravvive al cambio scheda. La risoluzione usa le opzioni già convalidate dal motore.
- Dorso generico per le carte nascoste, evidenziazione della metà Light/Dark delle magie pubbliche e token colorati Trap / Protection / Persistent.
- Il Persistent riproduce gli otto raggi del riferimento e identifica lo slot con fulmine, I, II o III. Lo slot deriva dalla specifica carta nella proiezione di Game, anche per i segnalini nelle stanze.
- Animazione della plancia e del token fisico dopo l'azione; animazione di rivelazione delle magie pubbliche. Una carta ancora nascosta resta coperta.
- Eliminata la barra descrittiva superiore. Conferme e ritorno rimangono piccoli pulsanti sovrapposti; le istruzioni delle finestre di scelta rimangono nella rispettiva finestra.
- Eventi e quest in risoluzione compaiono al centro dello schermo prima degli effetti, per 2,3 secondi; poi la risoluzione prosegue automaticamente.

## Stato e flusso

PlayerState, ReadySpellState, ActiveSpellState, RevealedSpellState e QuestState restano lo stato di gioco. `player_board_spell_slots` mantiene le posizioni delle singole carte. `Game.get_player_board_spell_slot_data()` filtra le informazioni per il viewer; la nuova interfaccia non decide autonomamente i permessi.

Le animazioni di plancia osservano solo occupazione, visibilità pubblica, tipo di token e disponibilità delle azioni fisiche. Non conservano identità private. Cambiare viewer chiude le viste private e annulla le animazioni della plancia.

Per eventi e quest, il frame già presente nella pila di risoluzione viene sospeso prima del suo primo effetto. Game pubblica una descrizione esclusivamente pubblica della carta da mostrare e fa ripartire lo stesso frame dopo il timer. Un identificatore impedisce a una vecchia conclusione dell'animazione di ripetere l'effetto. La logica non dipende dalla durata effettiva di un Tween o da una conferma del client.

`NetworkProjection` trasmette il turno pubblico e la carta attualmente in presentazione. Prima invia la carta con lo stato precedente all'effetto, poi lo stato risultante. Le quest private non sono incluse in questa presentazione: il punto di ingresso è la risoluzione di una quest completata.

## File e funzioni

| File | Modifiche dell'intervento |
| --- | --- |
| `tabletop_shell.gd` (nuovo) | `setup`, costruzione banner/plancia/overlay carte, `_layout`, `open_board`, `close_board`, `reveal_board_choice`, `_refresh_banners`, osservazione e animazione delle azioni, `sync_card_presentation`, navigazione e gestione privacy. |
| `tabletop_style.gd` (nuovo) | `panel`, `make_theme`, `marker`: stile condiviso e segnalini con colore e slot del proprietario. |
| `game.gd` | `_ready`, `_process`, `get_turn_presentation`, azioni/cast da plancia, `get_player_quest_cards`, `_refresh_permanent_room_markers`, limiti/layout/sfondo del tavolo, esposizione dei bersagli, `_present_resolution_card`, `_finish_card_presentation`, `process_resolution_stack`. Rimossa la vecchia etichetta del turno in alto. |
| `player_board.gd` | `_configure_spell_slot`, `_render_spell_slot`: dorso, token, metà attiva; autorizzazione sempre delegata a Game. |
| `hand_overlay.gd` | `_build_ui`, apertura delle modalità, `_select_cards_tab`, `_change_tab`, `_render_quests`, `_resolve_quest`, `_process`, `_assignment_badge`: schede, progresso, privacy e conservazione della preparazione. |
| `beta_hud.gd` | `_build_ui`, `_build_decision_bar`, `_sync_hand_confirmation`, `_add_confirmation`, `_open_hand_overlay`, `_add_info`, rendering richiesta/azione: barra descrittiva rimossa e conferme compatte. |
| `table_camera.gd` | `minimum_zoom`, `reset_view`, `adapt_to_viewport`, `focus_lodge`, `_view_center`, `_table_covered` e input: spazio della lista giocatori rispettato e camera bloccata sotto le viste sovrapposte. |
| `network_projection.gd` | `build`, `apply`: metadati pubblici di turno e presentazione carta. |
| `tabletop_shell_playtest.gd` (nuovo) | Test funzionali della nuova interfaccia e acquisizione delle schermate reali. |
| `tabletop_presentation_network_playtest.gd` (nuovo) | Trasferimento serializzato di due eventi consecutivi tra host e vista client; verifica ordine, danni, guarigione, privacy e ripresa. |
| `school_ui_playtest.gd` | Fixture avviata dopo il setup asincrono; controllo dell'assenza della barra e della finestra vuota nelle evocazioni. |
| `screen_layout_playtest.gd` | Aspettativa aggiornata al tavolo senza plance personali. |
| `playtest_regressions.gd` | Layout 2–6 giocatori e fixture Soul Transfer allineata alla scelta del costrutto già prevista dal codice corrente. |
| `tools/check_web_export.gd` | Controllo della nuova interfaccia e delle cinque nuove texture nel PCK esportato. |

Sono stati creati/importati anche i relativi `.uid` e `.png.import`.

Le modifiche presenti o sopraggiunte in `main_menu.gd`, `online_session.gd`, `online_invite.gd`, `web_host.gd`, negli script TLS/UPnP/Render e nel relay appartengono al lavoro online già presente nel workspace: questo intervento non le ha riscritte né annullate.

## Asset

- `assets/tabletop/playmat.png`
- `assets/tabletop/card_back.png`
- `assets/tokens/trap.png`
- `assets/tokens/protection.png`
- `assets/tokens/permanent.png`

Creati con il tool integrato image_gen, preservando l'alpha dei token. Prompt e riferimenti completi: [tabletop-art-prompts-2026-10-03.md](tabletop-art-prompts-2026-10-03.md). Il riferimento dei Persistent è pagina 20 di `../materials/BRWR_CORE_rulebook_ENG_v1.2.pdf`.

## Verifiche eseguite

Godot 4.7.2 effettivamente eseguito, sia headless sia con rendering OpenGL per le immagini di verifica.

Ultima revisione:

- Import/editor headless: nessun errore di parser.
- `tabletop_shell_playtest.gd`: PASS, anche renderizzato. Verifica cambio viewer, ispezione owner/non-owner, bersagli cubo conservati passando tra plance, schede, timer, effetto singolo, carte quest/evento e adattamento a 1280×800, 1366×768, 1920×1080.
- `tabletop_presentation_network_playtest.gd`: PASS. Verifica snapshot serializzati, non una connessione esterna.
- `school_ui_playtest.gd`, `hand_targets_playtest.gd`, `object_choices_playtest.gd`, `playtest_regressions.gd`: PASS.
- `event_rules_playtest.gd`: 39/39 eventi, 287 controlli, zero errori.
- `tools/build_web_render.ps1`: esportazione Web riuscita in `output/web`. `tools/check_web_export.gd` eseguito sul PCK appena esportato: `EXPORTED PACK CHECK PASS`, incluse tutte le magie, le carte scuola e le nuove texture. Il controllo è nativo/headless sul pacchetto Web; non equivale a una partita manuale in Chrome.
- `git diff --check`: nessun errore di whitespace; Git segnala soltanto la normale conversione CRLF/LF.

Eseguiti durante la prima parte dell'intervento anche `evocation_phase_playtest.gd`, `tabletop_ui_playtest.gd`, `five_fixes_playtest.gd`, `player_board_playtest.gd` e `screen_layout_playtest.gd`: PASS. Il test di trasporto host/client era passato prima delle modifiche al relay sopraggiunte nel workspace; non costituisce una verifica end-to-end del nuovo relay.

Schermate native in `output/tabletop-shell/`: `01-lodge.png`, `02-player-board.png`, `03-quests.png`, `04-cards.png`, `05-action-feedback.png`, `06-event.png`, `07-quest.png`, `08-persistence-tokens.png`. I log dei controlli sono nella stessa cartella.

## Verifiche manuali rimanenti

- Partita completa in browser fra due PC attraverso l'attuale relay e verifica di riconnessioni/alta latenza.
- Ritmo delle animazioni in una partita reale con molte reazioni; durata attuale delle presentazioni evento/quest: 2,3 secondi.
- Comfort visivo e navigazione con 5–6 giocatori e molte carte/evocazioni, oltre alle geometrie già verificate automaticamente.

La build Web corrente contiene ancora circa 669 MB di PCK: l'ottimizzazione del peso complessivo e della distribuzione degli asset resta un lavoro separato. Nessun commit creato.
