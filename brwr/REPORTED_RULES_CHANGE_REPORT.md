# Correzioni playtest — 29 settembre 2026

## Modifiche

- `game.gd`: `get_revealed_element_counts`, `can_apply_enhancement`,
  `_spell_effective_target_side`, `process_spell_resolution_frame`,
  `process_spell_cast_resolution`, `_beta_spell_cast_descriptor` escludono
  esplicitamente l'istanza della spell in risoluzione dal suo Enhancement.
  Un'altra copia fisica dello stesso ID continua a contare.
- `event_effect_resolver.gd`: `resolve_effect` riconosce gli Eventi passivi
  di Potere per colore della stanza. `game.gd/process_room_activation_resolution`
  applica l'effetto alla conclusione di ciascuna attivazione corrispondente.
  Growth e gli altri cinque Eventi dello stesso tipo non bloccano piu la fase.
- `data/spells.json`: Marbling Light ha target Special e scope Lodge su entrambi
  gli effetti. `effect_resolver.gd/_resolve_damage_variant` supporta questo scope:
  base sulle Evocazioni, Enhancement sui Maghi, mantenendo immunita e Celle.
- `cube.gd/_draw`: bordo chiaro per distinguere cubi neri dagli slot neri.
- `quest_manager.gd/get_completed_excess`: conta solo le Completate non Risolte.
  `game.gd/request_black_rose_completed_quest_limit` e
  `submit_black_rose_completed_quest_limit` escludono e proteggono le Risolte.
  Il limite si applica nella fase Rosa Nera, non durante la pesca da effetti.
- `player_state.gd`: trofei conservati nello stato del giocatore.
  `game.gd/process_damage_resolution`: trofeo all'ultimo attaccante (alla Rosa
  Nera con Dominion), punti secondo contributi di danno e parita; le finestre
  di trigger possono interrompere il pagamento senza duplicarlo. Dopo un
  trigger che salva il Mago, non assegna sconfitta/punti/trofeo.
- `game.gd/ranked_power_rewards`, `check_end_game`, `submit_final_winner_choice`:
  bonus Quest/Trofei/Corona, spareggi e decisione del Primo Mago se persistono.
  `set_player_power` e `set_black_rose_power` conservano i punti oltre 35.
  `power_board.gd/set_player_power`, `set_black_rose_power`, `update_player_marker`,
  `update_black_rose_marker`: giro aggiuntivo del tracciato e indicazione +35.
- `beta_hud.gd/_on_game_over`, `_render_current_request`, `get_supported_input_types`:
  riepilogo finale leggibile e scelta di spareggio. `game.gd/_process` mostra
  Fine partita nel banner. `get_beta_game_state`, `get_beta_supported_input_types`,
  `_submit_beta_input_authoritative` e `network_projection.gd/apply` trasmettono
  risultati e decisione anche al client.
- `main_menu.gd/_ready`, `online_session.gd/_ready`, `DEVELOPMENT_AND_ONLINE.md`:
  PvP diretto tramite IP e UDP 27847, senza Tailscale. Nessuna modifica automatica
  al router o firewall.
- `reported_rules_playtest.gd`: regressioni sui casi sopra, terza Quest,
  risoluzione/premio Quest, Fountain e attivazione nella fase Evocazioni.

## Verifiche eseguite

- Importazione/editor headless Godot 4.7.2 senza errori parser.
- JSON spell valido; revisione diff e `git diff --check`.
- PASS: reported_rules_playtest, online_rules_check, evocation_phase_playtest,
  quest_table_playtest, room_decks_playtest, player_board_playtest,
  playtest_regressions.
- PASS: online_playtest con host/client in due processi, connessione diretta
  localhost, scelte private e rigetto delle revisioni obsolete.
- Rendering OpenGL reale: cubo nero con bordo, scelta spareggio e riepilogo finale.
- `spell_event_playtest`: due fallimenti su Soul Transfer (target precompilato
  non valido e fixture di proprieta del Costrutto). Riprodotti anche nel vecchio
  pacchetto estratto, prima delle modifiche di questo intervento.

## Limiti e verifiche manuali

- Il regolamento p. 13 distingue Attive, Completate non Risolte e Risolte:
  il limite vale separatamente per le prime due categorie, mai per le Risolte.
  Mantenuta questa distinzione; non introdotta una variante con limite solo Attive.
- Terza Quest e riattivazione di Nigredo dopo Fountain funzionano nei test:
  non e stata identificata una causa ulteriore da correggere. Serve il percorso
  esatto del playtest se il problema ricompare.
- La segnalazione generica “risoluzione quest” non indica una carta o un errore:
  verificati il flusso e il premio senza duplicazioni; non dichiarata risolta
  una casistica specifica ancora sconosciuta.
- PvP tra reti diverse da verificare sui PC reali dopo port forwarding UDP,
  firewall e disponibilita di IP pubblico (CGNAT puo impedirlo).
- Verificare leggibilita dei cubi alla scala di gioco e partite complete con
  trigger annidati, spareggi e conteggio finale.
- Modifiche locali: nessun commit/push o aggiornamento degli ZIP precedenti
  effettuato in questo intervento.
