"""Generate an isolated BRWR _ready deep profiler from the CURRENT project.

No changes to original game.gd, game.tscn, AI bridge, policy or PyTorch.
The builder fails closed if the current source does not match expected anchors.
"""
from pathlib import Path
import re
import sys

ROOT = Path.cwd()
GAME = ROOT / 'game.gd'
SCENE = ROOT / 'game.tscn'
NATIVE = ROOT / 'ai' / 'ai_policy_native_match.gd'
DEST_GAME = ROOT / 'ai' / 'game_ready_deep_profile.gd'
DEST_SCENE = ROOT / 'ai' / 'game_ready_deep_profile.tscn'
DEST_WORKER = ROOT / 'ai' / 'ai_policy_native_ready_deep_profile.gd'

for p in (ROOT / 'project.godot', GAME, SCENE, NATIVE):
    if not p.is_file():
        sys.exit(f'READY_DEEP_BUILD_STOP missing {p}; originals untouched')

raw = GAME.read_text(encoding='utf-8-sig')
worker = NATIVE.read_text(encoding='utf-8-sig')
scene = SCENE.read_text(encoding='utf-8-sig')

if 'func _brwr_ready_deep_mark(' in raw:
    sys.exit('READY_DEEP_BUILD_STOP game.gd already has profiler instrumentation; originals untouched')

start_match = re.search(r'(?m)^func _ready\(\)\s*(?:->\s*void)?\s*:\s*$', raw)
if not start_match:
    sys.exit('READY_DEEP_BUILD_STOP _ready() not found; originals untouched')
next_match = re.search(r'(?m)^func\s+\w+\s*\(', raw[start_match.end():])
if not next_match:
    sys.exit('READY_DEEP_BUILD_STOP cannot determine end of _ready; originals untouched')
end = start_match.end() + next_match.start()
ready = raw[start_match.end():end]
lines = ready.splitlines(keepends=True)
first_real = next((l for l in lines if l.strip() and not l.lstrip().startswith('#')), None)
if not first_real:
    sys.exit('READY_DEEP_BUILD_STOP empty _ready; originals untouched')
indent = re.match(r'^[ \t]+', first_real).group(0)

# Each boundary reports the time since the preceding boundary. All anchors
# refer to top-level statements of game._ready (not similarly named functions).
# This automatically counts multiline calls and nested if/for bodies as groups.
BOUNDARIES = [
    ('rng_and_viewport', 'room_database = load_rooms()'),
    ('load_rooms', 'layout_database = load_layouts()'),
    ('load_layouts', 'cell_database = load_cells()'),
    ('load_cells_and_initial_logging', 'spell_database.load_database()'),
    ('load_spell_database', 'school_specialization_database = load_school_specializations()'),
    ('load_school_specializations', 'evocation_database.load_database()'),
    ('load_evocation_database', 'select_active_schools()'),
    ('select_active_schools', 'create_school_libraries()'),
    ('create_school_libraries', 'create_forgotten_deck()'),
    ('create_forgotten_deck', 'mage_database.load_database()'),
    ('load_mage_database', 'quest_database.load_from_file('),
    ('load_quest_database', 'create_quest_decks()'),
    ('create_quest_decks', 'event_database.load_database()'),
    ('load_event_database', 'create_event_decks()'),
    ('create_event_decks', 'create_players()'),
    ('create_players', 'AvatarRules.setup(self)'),
    ('avatar_rules_setup', 'assign_initial_crown()'),
    ('assign_initial_crown', 'create_lodge()'),
    ('create_lodge', 'AvatarRules.place_at_setup(self)'),
    ('avatar_rules_place_at_setup_and_avatar_board', 'create_model_tokens()'),
    ('create_model_tokens', 'create_player_boards()'),
    ('create_player_boards', 'for board in player_boards:'),
    ('refresh_player_boards', 'await $PowerBoard.initialize(player_count)'),
    ('powerboard_initialize', '$EventBoard.refresh_event_slots()'),
    ('eventboard_refresh', 'update_table_layout()'),
    ('update_table_layout', 'await get_tree().process_frame'),
    ('await_visual_frame', '# The first beta UI is created entirely from code, so no scene-tree changes'),
]

# Check all boundaries before writing anything.
locations = []
last_ix = -1
for label, anchor in BOUNDARIES:
    found = [i for i, line in enumerate(lines) if line.startswith(indent) and line[len(indent):].strip() == anchor]
    if len(found) != 1:
        sys.exit(f'READY_DEEP_BUILD_STOP anchor for {label} = {anchor!r}; found {len(found)}; originals untouched')
    i = found[0]
    if i <= last_ix:
        sys.exit(f'READY_DEEP_BUILD_STOP boundary order conflict {label}; originals untouched')
    locations.append((i, label, anchor))
    last_ix = i

# Build an augmented copy. The raw source is never altered.
marks = {}
for i, label, anchor in locations:
    prefix = ''
    if anchor == 'await $PowerBoard.initialize(player_count)':
        prefix = f'{indent}_brwr_ready_deep_pre_await_us = Time.get_ticks_usec()\n'
    marks[i] = f'{indent}_brwr_ready_deep_mark("{label}")\n' + prefix

open_lines = (
    f'\n{indent}_brwr_ready_deep_started_us = Time.get_ticks_usec()\n'
    f'{indent}_brwr_ready_deep_last_us = _brwr_ready_deep_started_us\n'
)
ready_new = open_lines + ''.join(marks.get(i, '') + line for i, line in enumerate(lines))
# Final marker: place in the still-open _ready function, before the next func.
ready_new += f'{indent}_brwr_ready_deep_mark("ui_optional_and_ready_end")\n'

members = (
    "# Isolated startup profiler. This declaration exists only in ai/game_ready_deep_profile.gd.\n"
    "var _brwr_ready_deep_started_us: int = -1\n"
    "var _brwr_ready_deep_pre_await_us: int = -1\n"
    "var _brwr_ready_deep_last_us: int = -1\n\n"
    "func _brwr_ready_deep_mark(stage: String) -> void:\n"
    f"{indent}var stamp: int = Time.get_ticks_usec()\n"
    f"{indent}if _brwr_ready_deep_last_us >= 0:\n"
    f"{indent}{indent}print(\"BRWR_READY_DEEP_STAGE_JSON \" + JSON.stringify({{\n"
    f"{indent}{indent}{indent}\"stage\": stage,\n"
    f"{indent}{indent}{indent}\"duration_ms\": float(stamp - _brwr_ready_deep_last_us) / 1000.0\n"
    f"{indent}{indent}}}))\n"
    f"{indent}_brwr_ready_deep_last_us = Time.get_ticks_usec()\n\n"
)
game_new = raw[:start_match.start()] + members + raw[start_match.start():start_match.end()] + ready_new + raw[end:]

# Create a second copy of game.tscn, replacing only its main game.gd script.
# Remove the old UID from this resource reference: otherwise Godot could load
# game.gd via its original UID and silently skip our profiler copy.
script_lines = []
for line in scene.splitlines(keepends=True):
    if '[ext_resource ' in line and 'path="res://game.gd"' in line:
        script_lines.append(line)
if len(script_lines) != 1:
    sys.exit(f'READY_DEEP_BUILD_STOP scene root script resource missing or duplicated ({len(script_lines)}); originals untouched')
original_script_line = script_lines[0]
profile_script_line = original_script_line.replace('path="res://game.gd"', 'path="res://ai/game_ready_deep_profile.gd"')
profile_script_line = re.sub(r'\suid="[^"]+"', '', profile_script_line)
scene_new = scene.replace(original_script_line, profile_script_line, 1)
# Unique local scene copy, avoiding collisions with the original scene UID.
scene_new = re.sub(r'(?m)^(\[gd_scene[^\n\]]*)\suid="[^"]+"', r'\1', scene_new, count=1)

source_scene = 'load("res://game.tscn")'
if worker.count(source_scene) != 1:
    sys.exit('READY_DEEP_BUILD_STOP expected exactly one game scene load in native worker; originals untouched')
worker_new = worker.replace(source_scene, 'load("res://ai/game_ready_deep_profile.tscn")', 1)

old = '\troot.add_child(game)\n'
if worker_new.count(old) != 1:
    sys.exit('READY_DEEP_BUILD_STOP cannot locate root.add_child(game) in native worker; originals untouched')
replacement = '''\tvar _brwr_deep_add_started_us: int = Time.get_ticks_usec()
\troot.add_child(game)
\tvar _brwr_deep_add_end_us: int = Time.get_ticks_usec()
\tvar _brwr_ready_entry_us: int = int(game.get("_brwr_ready_deep_started_us"))
\tvar _brwr_before_await_us: int = int(game.get("_brwr_ready_deep_pre_await_us"))
\tprint("BRWR_READY_DEEP_ROOT_JSON " + JSON.stringify({
\t\t"root_add_ms": float(_brwr_deep_add_end_us - _brwr_deep_add_started_us) / 1000.0,
\t\t"before_game_ready_ms": float(_brwr_ready_entry_us - _brwr_deep_add_started_us) / 1000.0 if _brwr_ready_entry_us >= _brwr_deep_add_started_us else -1.0,
\t\t"game_ready_to_first_await_ms": float(_brwr_before_await_us - _brwr_ready_entry_us) / 1000.0 if _brwr_before_await_us >= _brwr_ready_entry_us else -1.0,
\t\t"after_first_await_until_add_returns_ms": float(_brwr_deep_add_end_us - _brwr_before_await_us) / 1000.0 if _brwr_before_await_us >= 0 else -1.0
\t}))
'''
worker_new = worker_new.replace(old, replacement, 1)
# A malformed generated GDScript may leave game.tscn with a bare Node2D.
# Fail immediately rather than hanging after property assignments.
assignment = '\tgame.auto_start_game_flow = false\n'
if worker_new.count(assignment) != 1:
    sys.exit('READY_DEEP_BUILD_STOP cannot locate startup assignment; originals untouched')
worker_new = worker_new.replace(assignment,
    '\tif game.get_script() == null:\n'
    '\t\t_fail("Profiled game script did not load; inspect GDScript parse errors")\n'
    '\t\treturn\n' + assignment, 1)
worker_new = worker_new.replace('native_episode_', 'native_ready_deep_episode_')

# All validations passed. Only write isolated copies.
for p, content in ((DEST_GAME, game_new), (DEST_SCENE, scene_new), (DEST_WORKER, worker_new)):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding='utf-8', newline='\n')
print('READY_DEEP_BUILD_OK originals_unchanged=1 generated=' + ','.join(str(x) for x in (DEST_GAME,DEST_SCENE,DEST_WORKER)))
print(f'READY_DEEP_STAGE_COUNT {len(BOUNDARIES)+1}')
