The previous installer already updated game.gd, then failed before writing player_board.gd.

Do NOT restore game.gd.board_spells.bak.

Copy fix_player_board_spells.py into the project root and run:

    python .\fix_player_board_spells.py

This creates:
    player_board.gd.board_spells_fix.bak

The fix anchors on the unique function create_damage_track() instead of the repeated
'DAMAGE TRACK' comment that caused the previous error.
