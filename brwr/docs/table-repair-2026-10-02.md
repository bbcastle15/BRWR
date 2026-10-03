# Correzioni del tavolo, Fountain e conferme

## Modifiche

- `room_art.gd`: `apply()` espande l'artwork del 3,5% entro l'esagono, compensando il margine trasparente degli asset. Centri e adiacenze logiche restano quelli della loggia.
- `room.gd`: `get_art_instability_slots()` segue la stessa trasformazione dell'artwork.
- `lodge_room_choice.gd`: hitbox sull'intero esagono, contorno largo 4 unità e arretrato di 4; eliminato il riempimento colorato sull'effetto della stanza.
- `power_board.gd`: asset completo ricostruito dal riferimento fornito, coordinate delle 36 caselle e dei quattro mazzi associate ai dettagli dell'immagine. Proporzioni del riferimento, incastro agganciato alla rientranza tra le due punte. `game.gd:update_table_layout()` usa il nuovo punto di incastro. Le soglie configurate 6/18/35 restano invariate; la stella stampata a 30 nell'immagine è parte della grafica originale.
- `power_marker.gd`, `mage_token.gd`: immagini restaurate di mago e Rosa Nera; segnalini Potere 22×22 invece di 14 unità di diametro, maghi sulla loggia 46×46. Shader cambia il bordo viola nei colori dei giocatori e conserva simbolo bianco e fondo nero.
- `effect_resolver.gd:_summon()` registra l'evocazione riuscita nei metadati dell'effetto. `game.gd:process_effect_sequence_resolution()` azzera questo dato per ogni effetto e lo include nel rilevamento di Summon. Fountain Dark ora fa progredire Summoner Wizard anche senza un nome dell'effetto che cominci con `summon_`.
- `beta_hud.gd`: barra indipendente nella parte alta dello schermo per istruzioni, feedback e conferme. Le conferme non sono figlie della HUD nascondibile. Le carte selezionate nel cleanup conservano una conferma accessibile dopo ogni refresh.
- `hand_overlay.gd`: segnale `confirmation_changed` per mantenere aggiornata nella barra alta la conferma di Preparation/Study; spazio superiore riservato alla barra.
- Asset nuovi: `assets/boards/power_board_reference.png`, `assets/tokens/mage_power.png`, `assets/tokens/black_rose_power.png`, `assets/tokens/player_token.gdshader` e rispettivi import.

## Verifiche eseguite

Godot 4.7.2: import/parser senza errori, render gl_compatibility ispezionato (`output/table-repair/table.png`). Diff ispezionato e `git diff --check`.

11 suite PASS: table_repair, power_board, object_choices, board_actions, quest_table, hand_targets, room_art, screen_layout, hand_layout, tabletop_ui, evocation_quest_rules.

Il nuovo `table_repair_playtest.gd` verifica il cast reale di Fountain Dark, Nigredo evocato, un solo cubo di Summoner Wizard, assenza del keyword su un effetto successivo, conferma cleanup a 720p dopo selezione e HUD nascosta, clic mouse effettivo sulla barra e contorno interno dell'esagono. `power_board_playtest.gd` verifica anche che gli asset ad alta risoluzione restino 22×22 nel gioco.

Da verificare manualmente: partita completa PvP, zoom e leggibilità sul monitor del playtest, accumulo di molti token sullo stesso punteggio. Nessun commit; modifiche precedenti conservate.
