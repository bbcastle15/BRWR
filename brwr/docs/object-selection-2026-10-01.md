# Selezione degli oggetti — 1 ottobre 2026

## Modifiche di questo intervento

- `game.gd`: `request_effect_choice()` aggiunge tipo di carta e indirizzo pubblico della scelta; conserva i riferimenti reali soltanto nella mappa dei valori runtime. `_request_stepwise_action_activation()` indirizza Momentum allo slot dell'istanza preparata e la risoluzione Quest alla carta completata. `request_next_trigger_decision()` e `advance_cleanup_phase()` indirizzano le scelte alle carte attive. `show_board_target_choice()` evidenzia anche slot Spell e carte Quest, controllando la visibilità tramite le API esistenti.
- `player_board.gd`: `refresh_quests()` associa il riferimento della Quest alla sua rappresentazione per individuare la carta esatta, anche con copie dello stesso ID.
- `beta_hud.gd`: nuovo `_add_object_choice()` condiviso. `_render_action_root()`, `_render_trigger_decision()`, `_render_cleanup_active_spells()`, `_render_optional_quest_discard()` e `_render_index_multiselect()` usano le carte sulla plancia quando disponibili. `_render_effect_choice()` usa anche le immagini delle carte fuori plancia e riconosce destinazioni con `room_id` senza dipendere dal prefisso del token. `_render_optional_hand_discard()`, `_render_starting_mage_choice()`, `_render_starting_school_choice()`, `_render_starting_grimoire_choice()` e `_render_study_schools()` mostrano carte o tessere selezionabili e scorrevoli. `_render_current_request()` indirizza anche la scelta del vincitore al modello. `_clear_content()` stacca subito i vecchi controlli prima di accodarne la distruzione; `_center_choice_panel()` ripristina le dimensioni compatte.
- `object_choices_playtest.gd`: regressioni per identità delle copie, privacy, indirizzi serializzabili, Quest attive/completate, cleanup, galleria della mano e scelta della stanza.

Lo stato autorevole e la validazione rimangono in Game. Nessun cambiamento alle regole. Nessun JSON modificato. Le modifiche precedenti già presenti nel working tree sono state conservate.

## Verifiche

- Godot 4.7.2, import/parser headless: nessun errore.
- PASS: object_choices, hand_targets, board_actions, quest_table, hand_layout, tabletop_ui, player_board.
- event_rules: 39/39 eventi, 287 controlli, zero errori.
- spell_event: due controlli falliscono su Soul Transfer (consumo della carta con target illegale; Construct avversario). Entrambi riprodotti caricando la copia di game.gd salvata prima di questo intervento. Non risolti in questa modifica della UI.
- Render reale con gl_compatibility ispezionato; corretta l'altezza della finestra per mostrare le carte intere. Screenshot e log in `output/object-choices/` (ignorato da Git).
- Diff completo ispezionato, `git diff --check`.

## Limiti / prova manuale

Le decisioni astratte (tipo di azione, tempistica, accetta/rifiuta, conferma, passa) mantengono pulsanti. Le scuole senza artwork e le risorse mancanti usano tessere con etichetta. I bersagli fisici non rappresentati da un nodo disponibile mantengono un ripiego selezionabile anziché bloccare la partita.

Da provare in partita: selezioni sulla plancia a diversi zoom; scroll delle Quest e delle gallerie; combinazioni di bersagli diversi nello stesso effetto; handoff hot-seat; host/client online. Gli indirizzi delle scelte sono serializzabili, ma non è stata eseguita una sessione tra due PC.

Nessun commit creato.
