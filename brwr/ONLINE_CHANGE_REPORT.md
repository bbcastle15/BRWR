# Modifiche e verifiche del 29 settembre 2026

## Implementazione

- `main_menu.gd`, `main_menu.tscn`, `project.godot`: menu iniziale, solo-test
  locale 2–6 giocatori, creazione/ingresso PvP a due giocatori.
- `online_session.gd`: host ENet, codice stanza e verifica versione, assegnazione
  fissa P1/P2, inoltro delle scelte, controllo mittente/turno/revisione,
  invio snapshot filtrati, arresto delle interazioni alla disconnessione.
- `network_projection.gd`, `build/apply`: proiezione filtrata dello stato esistente;
  ricostruzione della sola vista client usando le classi esistenti. Nessun motore
  di regole parallelo, nessuna trasmissione dei mazzi o delle mani avversarie.
- `game.gd`: `get_ui_viewer_player_index`, API degli slot/azioni PlayerBoard,
  `submit_beta_input` / `_submit_beta_input_authoritative`, revisione delle richieste,
  avvio senza flusso autonomo sul client; `_create_turn_banner` / `_process`;
  `deal_damage_to_evocation` protegge anche l'ingresso comune dai danni del controllore.
- `beta_hud.gd`, `_on_player_input_requested`: le richieste altrui non aprono
  finestre di scelta; il viewer online resta il giocatore locale.
- `table_camera.gd`: `minimum_zoom`, `reset_view`, `zoom_at`, `_process`;
  lo zoom minimo deriva dai confini di loggia, side board e PlayerBoard.
- `tools/package_windows.ps1`, `DEVELOPMENT_AND_ONLINE.md`, `GODOT_LICENSES.txt`:
  pacchetto Windows portabile, istruzioni laptop/Git/Tailscale e licenze del runtime.
  `.gitignore` esclude gli output generati, lo ZIP e la copia estratta di verifica.

## Richieste precedenti completate

`assets/rooms/cell.png`, `cell.gd` e `cell_owner_color.gdshader`: unica stanza
con pergamena superiore, senza nomi; mago e bordo colorati dal proprietario.
`cell_assets_check.gd` verifica tutte le sei varianti e le tre Forgotten:
Arcane Barrage, Killer Fog, Supreme Fireball, caricate da entrambi i resolver.
Le PNG Forgotten fornite dall'utente non sono state modificate.
Prompt imagegen: `output/imagegen/cell-scroll-correction.md`.

## Test eseguiti

- Godot 4.7.2: controllo parser del menu e dipendenze; import editor; rendering
  effettivo di menu, banner e celle.
- Due processi Godot con ENet su localhost: setup maghi/scuole/grimori, Study,
  Preparation, movimento di entrambi i giocatori; controllo mano/slot nascosti,
  rifiuto dell'invio per l'avversario e di una revisione scaduta.
- `online_rules_check.gd`: Albify Dark su mago ed evocazione avversari, con e
  senza Enhancement; selezione stanza interattiva; immunità dei propri modelli;
  snapshot/applicazione client; limite zoom.
- PASS: `board_actions_playtest`, `player_board_playtest`, `playtest_regressions`,
  `room_damage_playtest`, `quest_table_playtest`, `tabletop_ui_playtest`,
  `evocation_phase_playtest`, `room_art_playtest`, `cell_assets_check`.
- `git diff --check` senza errori. Nessuna modifica JSON in questo intervento.

## Limiti e casi ancora aperti

La connessione fra due reti fisiche tramite Tailscale e una partita completa
fino a fine gioco richiedono ancora il vostro playtest. Non sono implementati
riconnessione, migrazione host e salvataggio online.

**Albify Dark non riprodotto:** nel caso controllato converte tre cubi di altro
colore sul mago avversario; con Enhancement infligge anche il danno previsto.
Non è stata introdotta una modifica speculativa alla carta. Servirà il log della
partita problematica (`playtest.log` accanto al launcher del pacchetto), per
distinguere cubi già del colore del caster, sconfitta/uscita dalla stanza durante
l'Enhancement, e un errore di risoluzione ancora sconosciuto.

L'immunità è confermata dalla sezione **Immunity** del
[regolamento Rebirth](https://www.rulespal.com/black-rose-wars-rebirth/rulebook):
salvo eccezioni esplicite, il mago e le evocazioni controllate ignorano danni
inflitti/convertiti dai suoi effetti.

La suite generale aveva già un'aspettativa obsoleta su Momentum e le due uscite
delle celle; non viene dichiarata interamente verde. Le verifiche qui elencate
sono quelle mirate eseguite in questo intervento.

Nessun commit o push. Le modifiche locali preesistenti sono state preservate.
