# Plancia Potere e cubetti Quest

Riferimento: `../materials/BRWR_CORE_rulebook_ENG_v1.2.pdf`, pagina 12.

- `power_board.gd`: tracciato di 36 caselle in tre file da 12, ruotato in senso orario per l'incastro a destra della loggia; ordine corretto Quest/Evocazione/Jinx/Upgrade; texture decorativa ritagliata sulla sagoma esistente; soglie rappresentate con i cubi esistenti; posizioni separate per sei giocatori e Rosa Nera. Funzioni: create_power_track, create_board_shape, setup_card_slots, setup_card_slot, create_threshold_markers, update_threshold_markers, update_player_marker, update_black_rose_marker, get_marker_offset.
- `power_board.tscn`: PowerTrack diventa Control per mantenere l'ordine logico 0–35 con disposizione esplicita.
- `power_marker.gd`: medaglioni a rosa disegnati in vettoriale, colori dei giocatori e Rosa Nera; tooltip con proprietario e punteggio; indicazione dei punti oltre la soglia mantenuta. Funzioni: _ready, _draw, _has_point.
- `assets/boards/power_board_stone.png`: nuova texture generata. La struttura viene disegnata dal gioco, non affidata ai numeri generati nell'immagine.
- `player_board.gd`, refresh_quests: riga dei cubetti centrata sulla carta tramite ancoraggi, anche al ridimensionamento.
- `power_board_playtest.gd`: verifica ordine, mazzi, sei giocatori, Rosa Nera e punteggi oltre soglia.

La geometria esterna della plancia e le soglie configurate 6/18/35 sono conservate. Non sono state cambiate regole, punti o stato autorevole. Le immagini dei dorsi dei quattro mazzi non sono state aggiunte; gli spazi mantengono le rispettive etichette.

Verifiche: parser/import Godot 4.7.2; power_board_playtest PASS; screen_layout_playtest PASS; quest_table_playtest PASS; render gl_compatibility ispezionato in output/power-board/preview.png; git diff --check. online_rules_check si ferma all'asserzione sulla conversione di Albify Dark mentre è pendente un effect_choice, prima della verifica di rete; il processo è stato terminato. Sessione PvP e leggibilità a tutti gli zoom richiedono prova manuale.

Nessun commit. Le modifiche precedenti del working tree sono state conservate.
