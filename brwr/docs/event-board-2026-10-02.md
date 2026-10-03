# Event Board — 2 ottobre 2026

Plancia ricreata dallo screenshot dell'utente usando lo strumento imagegen integrato: PNG RGBA 1081 × 1455, salvato in `assets/boards/event_board_reference.png`. Rotazione antioraria di 90° per il lato sinistro della Loggia. La grafica conserva tre alloggiamenti eventi, mazzo, scarti eventi, scarti quest, riserva cubi e trofei. Nessuna modifica alle stanze o alle regole degli eventi.

## Implementazione

- `event_board.gd`: sostituita la geometria visibile provvisoria con la texture; mantenuto un contorno per camera e ingombri. `create_board_shape`, `setup_event_slots`, `setup_lower_slots`, `setup_card_slot` allineano le aree alla grafica. `show_event_in_slot` e `_rotate_card_view` riutilizzano ReferenceCardPreview con orientamento coerente; `_remove_view` rimuove i vecchi controlli con queue_free. I contatori di mazzo/scarti leggono Game. `create_cube_pool_ui` e `update_black_rose_cube_pool` proiettano tutti i cubi della riserva, mantenendo invariata l'API esistente di consumo/restituzione. `refresh_support_slots` mostra i trofei e la prima carta degli scarti quest; le cache sono solo visuali.
- `game.gd`: `update_table_layout` usa il punto d'incastro dichiarato dalla plancia; `refresh_all_player_boards` aggiorna anche gli spazi di supporto; `open_discarded_quest_card` apre solo carte effettivamente presenti negli scarti pubblici.
- `event_board_playtest.gd`: test degli slot, dell'incastro, delle anteprime, dei trofei e dei cubi.
- `tabletop_ui_playtest.gd`: verifica dell'orientamento antiorario e dei limiti della carta rispetto alle dimensioni effettive dello slot, al posto delle precedenti misure provvisorie 80 × 52.
- Asset PNG e relativo file `.import`; nessuna modifica ai JSON o a `event_board.tscn`.

## Verifiche

Godot 4.7.2: import/editor headless senza errori; PASS per `event_board_playtest`, `tabletop_ui_playtest`, `screen_layout_playtest`, `player_board_playtest`. `event_rules_playtest`: 39/39 eventi, 287 controlli, zero fallimenti. Diff verificato.

Rendering GL Compatibility ispezionato: `output/event-board/detail.png` e `output/event-board/table.png`. Il primo tentativo del solo script di cattura richiedeva una camera non creata quando la HUD è disabilitata; corretto lo script di cattura e completata la verifica visiva.

Da verificare manualmente una partita PvP completa e l'usabilità alle diverse risoluzioni. Nessun commit.

## Prompt imagegen

Use case: precise-object-edit. Create a high-resolution faithful restored game-board texture from the supplied reference. Isolate ONLY the ornate Event Board at the TOP of the screenshot; completely remove the three hexagonal rooms below and all table/background. Orthographic flat top-down scan, restored sharp engraved ivory ornament on dark brown-black stone, preserve exact layout, icons and silhouette. Rotate the extracted board exactly 90 degrees COUNTERCLOCKWISE for use on the LEFT side of a digital Lodge: straight outside edge at LEFT, two pointed lobes pointing RIGHT with a central inward notch. In this orientation, LEFT column top to bottom: printed pale event discard card silhouette, three EMPTY outlined landscape card recesses with the existing hourglass emblems, printed ornate event-deck back with the three moon symbols at bottom. RIGHT half: EMPTY trophy basin at top with its trophy icon by rightmost point, printed quest-discard rose card back in centre, EMPTY cube basin at bottom with cube icon by rightmost point. Do not add any actual tokens, cubes, cards, numbers, labels or lettering. Preserve printed decorative card backs shown in source. Preserve the two lobe tips and central notch precisely; no cropping. Transparent outside silhouette, no cast shadow. Tight canvas around complete silhouette with approximately 1% margins. Portrait asset approximately 1100x1480 or matching aspect ratio of reference after rotation. Crisp fine detail, consistent with a deluxe dark fantasy tabletop component; faithful restoration rather than redesign.
