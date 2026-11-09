"""Extend existing BRWR AI-only refresh guard without changing production game.gd.
Run from project root BRWR/brwr.
"""
from pathlib import Path
import argparse
import ast
import shutil
import sys

ROOT = Path.cwd()
BUILDER = ROOT / 'build_school_cache_variant.py'
BACKUP = ROOT / 'build_school_cache_variant.py.before_targeted_ui_guards_v2.bak'
MARKER = 'BRWR_AI_TARGETED_UI_GUARDS_V2'
PREVIOUS_MARKER = 'BRWR_AI_ONLY_BOARD_REFRESH_GUARD_V1'
ANCHOR = "print('BRWR_AI_BOARD_REFRESH_GUARD_GENERATED disabled_when_enable_beta_hud_false=1')\n"

INSERT = r'''
# BRWR_AI_TARGETED_UI_GUARDS_V2: only in AI generated script.
# Do not skip gameplay/state mutation; suppress only render-only entry points.
_brwr_player_sig = 'func refresh_player_board(\n\tplayer_index: int\n) -> void:\n'
_brwr_damage_sig = 'func _refresh_damage_boards(\n\ttarget_player_index: int,\n\tattacker_id: int\n):\n'
for _brwr_name, _brwr_signature in (
    ('refresh_player_board', _brwr_player_sig),
    ('_refresh_damage_boards', _brwr_damage_sig),
):
    if game_new.count(_brwr_signature) != 1:
        sys.exit('BRWR_AI_TARGETED_GUARD_STOP: signature mismatch for ' + _brwr_name)
    game_new = game_new.replace(
        _brwr_signature,
        _brwr_signature + '\tif not enable_beta_hud:\n\t\treturn\n',
        1,
    )
print('BRWR_AI_TARGETED_UI_GUARDS_GENERATED refresh_player_board=1 damage_boards=1')
'''

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--undo', action='store_true', help='Restore generator to V1')
    args = parser.parse_args()
    if not BUILDER.is_file():
        sys.exit('BRWR_AI_TARGETED_GUARD_STOP: missing build_school_cache_variant.py; run from BRWR/brwr')
    contents = BUILDER.read_text(encoding='utf-8-sig')
    if args.undo:
        if MARKER not in contents:
            sys.exit('BRWR_AI_TARGETED_GUARD_UNDO_STOP: V2 marker not found')
        if not BACKUP.is_file():
            sys.exit('BRWR_AI_TARGETED_GUARD_UNDO_STOP: backup missing; refusing to modify')
        older = BACKUP.read_text(encoding='utf-8-sig')
        if PREVIOUS_MARKER not in older or MARKER in older:
            sys.exit('BRWR_AI_TARGETED_GUARD_UNDO_STOP: backup does not match V1')
        shutil.copy2(BACKUP, BUILDER)
        print('BRWR_AI_TARGETED_GUARD_UNDONE: V1 preserved; production game.gd untouched')
        return
    if MARKER in contents:
        print('BRWR_AI_TARGETED_GUARD_ALREADY_APPLIED; no changes made')
        return
    if PREVIOUS_MARKER not in contents:
        sys.exit('BRWR_AI_TARGETED_GUARD_STOP: apply original board-refresh guard V1 first')
    if contents.count(ANCHOR) != 1:
        sys.exit('BRWR_AI_TARGETED_GUARD_STOP: incompatible builder; expected one V1 insertion point')
    if BACKUP.exists():
        sys.exit('BRWR_AI_TARGETED_GUARD_STOP: prior backup exists; refusing overwrite')
    modified = contents.replace(ANCHOR, ANCHOR + INSERT, 1)
    ast.parse(modified, filename=str(BUILDER))
    shutil.copy2(BUILDER, BACKUP)
    BUILDER.write_text(modified, encoding='utf-8', newline='\n')
    print('BRWR_AI_TARGETED_GUARD_PATCH_OK: generated AI game only')
    print('BACKUP:', BACKUP)
    print('Production game.gd, rules and neural checkpoint unchanged.')

if __name__ == '__main__':
    main()
