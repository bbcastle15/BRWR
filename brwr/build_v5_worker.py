#!/usr/bin/env python3
"""Produce a v5 native worker from the CURRENT vetted cached + UI guarded worker.
Never touch main game scene, the original Python trainer or v4 worker.
Compatible with Python 3.8+ (no Path.write_text(newline=...)).
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parent
source = root / 'ai/ai_policy_school_prefix_match.gd'
cached = root / 'ai/game_school_cached.gd'
if not source.is_file() or not cached.is_file():
    sys.exit('V5_WORKER_BUILD_STOP: missing cached v4 worker/Game; run optimized v4 setup first')
game = cached.read_text(encoding='utf-8-sig')
for method in ('refresh_all_player_boards', 'refresh_player_board', '_refresh_damage_boards'):
    anchor = 'func ' + method + '('
    i = game.find(anchor)
    if i < 0 or 'if not enable_beta_hud:\n\t\treturn' not in game[i:i + 340]:
        sys.exit('V5_WORKER_BUILD_STOP: missing UI guard ' + method)
worker = source.read_text(encoding='utf-8-sig')
changes = (
    ('res://ai/ai_native_policy_prefix_v4.gd', 'res://ai/ai_native_policy_v5.gd'),
    ('res://ai/model/native_policy_v4.json', 'res://ai/model/native_policy_v5.json'),
    ('school_prefix_episode_', 'v5_semantic_episode_'),
)
for before, after in changes:
    if worker.count(before) != 1:
        sys.exit('V5_WORKER_BUILD_STOP: expected one worker anchor ' + before)
    worker = worker.replace(before, after, 1)
if worker.count('load("res://ai/game_school_cached.tscn")') != 1:
    sys.exit('V5_WORKER_BUILD_STOP: worker not using cached game scene')
worker = worker.replace('native_gdscript_policy_v4', 'native_gdscript_policy_v5_semantic')
target = root / 'ai/ai_policy_school_v5_match.gd'
target.write_bytes(worker.encode('utf-8'))
print('V5_WORKER_BUILD_OK isolated=1 cached_game=1 three_UI_guards=1 original_worker_unchanged=1')
print('V5_WORKER_FILE ' + str(target))
