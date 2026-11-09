"""Opt-in AI-only optimization of school-cache variant generator.

Adds a guard to refresh_all_player_boards() *only in the generated AI
copy* of game.gd, leaving the production game and all model files untouched.

Usage (from BRWR/brwr):
    python apply_ai_board_refresh_guard.py
    python apply_ai_board_refresh_guard.py --undo
"""
from pathlib import Path
import argparse
import ast
import shutil
import sys

ROOT = Path.cwd()
BUILDER = ROOT / 'build_school_cache_variant.py'
BACKUP = ROOT / 'build_school_cache_variant.py.before_ai_ui_guard.bak'
MARKER = 'BRWR_AI_ONLY_BOARD_REFRESH_GUARD_V1'
ANCHOR = 'game_new = game[:start] + original_impl + wrapper + game[end:]\n'
INSERT = '''\n# BRWR_AI_ONLY_BOARD_REFRESH_GUARD_V1: Only the generated AI copy is changed.\n# Production game.gd and the baseline comparison worker remain untouched.\n_guard_sig = 'func refresh_all_player_boards() -> void:\\n'\nif game_new.count(_guard_sig) != 1:\n    sys.exit('AI_UI_GUARD_STOP: refresh_all_player_boards signature not unique; originals untouched')\ngame_new = game_new.replace(\n    _guard_sig,\n    _guard_sig + '\\tif not enable_beta_hud:\\n\\t\\treturn\\n',\n    1,\n)\nprint('BRWR_AI_BOARD_REFRESH_GUARD_GENERATED disabled_when_enable_beta_hud_false=1')\n'''

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--undo', action='store_true', help='Restore original builder from backup')
    args = parser.parse_args()
    if args.undo:
        if not BACKUP.is_file():
            sys.exit(f'AI_UI_GUARD_UNDO_STOP: no backup at {BACKUP}')
        if not BUILDER.is_file() or MARKER not in BUILDER.read_text(encoding='utf-8-sig'):
            sys.exit('AI_UI_GUARD_UNDO_STOP: builder changed or not patched; refusing overwrite')
        shutil.copy2(BACKUP, BUILDER)
        print('AI_UI_GUARD_UNDONE: builder restored; original game.gd was never changed')
        return

    if not BUILDER.is_file():
        sys.exit('AI_UI_GUARD_STOP: cannot find build_school_cache_variant.py (run from brwr root)')
    contents = BUILDER.read_text(encoding='utf-8-sig')
    if MARKER in contents:
        print('AI_UI_GUARD_ALREADY_APPLIED; no changes made')
        return
    if contents.count(ANCHOR) != 1:
        sys.exit('AI_UI_GUARD_STOP: unsupported builder revision; expected unique anchor not found')
    modified = contents.replace(ANCHOR, ANCHOR + INSERT, 1)
    ast.parse(modified, filename=str(BUILDER))
    if BACKUP.exists():
        sys.exit('AI_UI_GUARD_STOP: existing backup from another revision; refusing to overwrite')
    shutil.copy2(BUILDER, BACKUP)
    BUILDER.write_text(modified, encoding='utf-8', newline='\n')
    print('AI_UI_GUARD_PATCH_OK: generated game_school_cached.gd only')
    print('BACKUP:', BACKUP)
    print('Production game.gd and checkpoint not touched.')

if __name__ == '__main__':
    main()
