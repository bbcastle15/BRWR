# Correzioni del playtest — 1 ottobre 2026

## Regole verificate

- Codex Arcanum, pagina PDF 7: Enhancement considera le **altre** magie già
  rivelate, sul lato precedentemente risolto. La carta in risoluzione è esclusa
  per riferimento; un'altra copia della stessa carta può contribuire.
- Codex Arcanum, pagina PDF 69: Emet-Met è Contingency / elemento universale su
  entrambi i lati. Light evoca Nigredo; l'attivazione con Forza +1 e Movimento +1
  è subordinata a Enhancement Fuoco + Terra.
- Regolamento Rebirth inglese v1.2, pagina 28, passo 3 della sconfitta: vengono
  rimosse le evocazioni **assegnate** al mago (es. Umbras). Le evocazioni evocate,
  comprese le quattro attualmente implementate, non muoiono automaticamente.
- Nigredo: dopo danno effettivamente inflitto, il controllore può piazzare oppure
  convertire 1 Instabilità nella stanza del Nigredo, oppure rinunciare.

## File e funzioni modificati in questo intervento

- `data/spells.json`: definizione `emet_met`; Enhancement separato dalla base,
  tipo ed elemento corretti da Codex. Gli altri cambiamenti preesistenti restano.
- `game.gd`: `request_effect_choice` pubblica l'origine del modello per il
  movimento; `_movement_destination_choice_options` include la stanza attuale;
  `_prepare_spell_secondary_effect_choice` trasmette l'origine corretta.
  `_quest_request_single_choice`, `_prepare_quest_target_choice` e
  `process_effect_sequence_resolution` richiedono bersagli distinti per ogni
  effetto di quest, compresi quelli a distanza 0. Le risposte restano valide
  durante la sospensione dello stesso effetto.
  `_sync_damage_result_context`, `_sync_evocation_damage_result_context` e la
  nuova `_queue_evocation_damage_abilities` attivano le abilità dai dati.
  `process_resolution_stack` gestisce il nuovo frame;
  `process_evocation_damage_ability` offre la scelta e la applica una volta sola.
  `process_damage_resolution` riprende dopo danno rediretto senza ripeterlo.
- `effect_resolver.gd`: `_resolve_move_damaged_model` tratta la stanza attuale
  come arresto, senza generare un nuovo ingresso nella stanza.
- `beta_hud.gd`: `_render_lodge_paths`, `_render_command_paths`,
  `_render_effect_choice`, `_render_evocation_movement`: stanza attuale cliccabile
  per restare o fermarsi; origine dell'evocazione distinta da quella del mago.
- `hand_overlay.gd`: `_build_ui`, `_card_display_size`, `_layout_cards`: unica
  fila, dimensionamento per sei carte, scorrimento orizzontale per le ulteriori.
- `table_camera.gd`: `_ready` e nuova `focus_lodge`: apertura sulla Loggia;
  `Home` e limite dello zoom indietro conservano la vista dell'intero tavolo.
  Raggio e disposizione degli esagoni restano quelli esistenti.
- `player_board.gd`: `refresh_action_tokens`: token allineati ai due riquadri
  delle nuove carte mago, adattate al rapporto 330:190 dello slot.
- Nuove immagini: `assets/mages/rikkart.png`, `assets/mages/angela.png`,
  `assets/quests/conspirator_mage.png`; caricate dal resolver già esistente.

Le immagini sono state generate con imagegen. Rikkart deriva dalla carta in
`assets/mages/screen_3.png`; Angela dal ritratto e dalle statistiche del Codex,
pagina 69, con il layout della carta Rikkart. Entrambe riportano 11/7/2/2/2 e
mantengono i riquadri azione e trofeo. Conspirator Mage riprende la cornice di
`guardian_mage.png`, con testo ed effetti della definizione `quests.json`.
Gli screenshot sorgente sono conservati. Lo stato di gioco continua a provenire
dai database e dagli stati runtime, non dalle immagini.

## Verifiche

Godot 4.7.2: importazione/editor headless senza errori di parser; JSON delle
magie valido, identificativi univoci; diff e whitespace controllati.

13 playtest headless superati:

- `evocation_quest_rules_playtest.gd` (nuovo): Emet-Met base e potenziata,
  esclusione della carta corrente e del lato inattivo, Nigredo contro maghi ed
  evocazioni, controllore diverso dal proprietario, conversione dei cubi,
  rinuncia, danno nullo/prevenuto/rediretto, due bersagli della quest, sconfitta.
- `hand_layout_playtest.gd` (aggiornato): 1–12 carte, 1280×720 e 1600×900.
- `hand_targets_playtest.gd` (aggiornato): scorrimento, preparazione nascondibile,
  selezione dei cubi/conversione danni anche sulle evocazioni e Tribute.
- `tabletop_ui_playtest.gd` (aggiornato): clic reale sulla stanza attuale e arresto
  dopo un passo, oltre ai controlli esistenti.
- `player_board_playtest.gd` (aggiornato): entrambe le immagini mago caricate con
  proporzioni compatibili con lo slot, Conspirator Mage caricata.
- `screen_layout_playtest.gd` (aggiornato): apertura sulla Loggia, panoramica,
  ridimensionamento e zoom.
- `reported_rules_playtest.gd`, `athanor_enhancement_playtest.gd`,
  `liquid_fire_playtest.gd`, `evocation_token_playtest.gd`,
  `board_actions_playtest.gd`, `quest_table_playtest.gd`, `room_art_playtest.gd`.

Ispezionata anche un'immagine renderizzata da Godot delle due plance con le
nuove carte mago. Log e screenshot locali in `output/emet-met/` (ignorati da Git).

Restano da verificare con un playtest interattivo completo: comodità di lettura
e navigazione alla risoluzione effettiva del giocatore, partita online con due
client, combinazioni di Nigredo con catene di trappole/protezioni non coperte dai
test. Nessun commit creato.
