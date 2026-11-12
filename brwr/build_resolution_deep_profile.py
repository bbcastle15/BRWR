"""Build isolated timing-only BRWR profile variant from CURRENT cached AI Game.

Run after build_school_cache_variant.py. Never edits original game.gd or ai/ai_bridge.gd.
"""
from pathlib import Path
import re
import sys

ROOT = Path.cwd()
GAME = ROOT / 'ai' / 'game_school_cached.gd'
SCENE = ROOT / 'ai' / 'game_school_cached.tscn'
WORKER = ROOT / 'ai' / 'ai_policy_school_cached_match.gd'
for f in (GAME, SCENE, WORKER):
    if not f.is_file():
        sys.exit(f'SUBMIT_PROFILE_BUILD_STOP missing {f}; run school cache generator first')

game = GAME.read_text(encoding='utf-8-sig')
scene = SCENE.read_text(encoding='utf-8-sig')
worker = WORKER.read_text(encoding='utf-8-sig')

# These are synchronous Game methods. The profiler measures inclusive and exclusive
# execution; a method may include nested instrumented calls. No game-logic code
# is changed, only method wrappers on a GENERATED copy of Game.
methods = [
    'submit_beta_input', '_submit_beta_input_authoritative', '_dispatch_beta_input', '_log_phase_choice',
    '_submit_parallel_preparation', '_submit_parallel_study_input',
    '_submit_parallel_study_keep', '_submit_parallel_study_optional_discard',
    '_submit_parallel_study_hand_limit',
    'submit_effect_choice', 'submit_action_activation_step', 'submit_action_activation',
    'submit_preparation', 'submit_study_school_choices', 'submit_study_keep_cards',
    'submit_study_optional_discard', 'submit_study_hand_limit', 'submit_trigger_decision',
    'submit_evocation_phase_activations', 'submit_cleanup_active_spells',
    'submit_starting_mage_choice', 'submit_starting_school_choice',
    'submit_starting_grimoire_choice', 'submit_black_rose_optional_quest_discard',
    'submit_black_rose_active_quest_limit', 'submit_black_rose_completed_quest_limit',
    'queue_resolution', 'process_resolution_stack', 'process_game_event',
    'process_damage_resolution', 'process_evocation_damage_resolution',
    'process_effect_sequence_resolution', 'process_spell_resolution_frame',
    'process_spell_cast_resolution', 'process_trigger_spell_resolution',
    'process_activation_resolution', 'process_action_events_resolution',
    'process_room_activation_resolution', 'process_explore_resolution',
    'process_fight_resolution', 'process_command_resolution',
    '_handle_resolution_completion', '_present_resolution_card', '_visuals_busy',
    'request_player_input', 'clear_player_input', 'refresh_all_player_boards', 'refresh_player_board',
    '_refresh_damage_boards', 'update_table_layout',
    # Resolution/phase internals: safe synchronous wrappers only.
    'advance_study_phase',
    'advance_action_phase',
    '_request_stepwise_action_activation',
    'advance_evocation_phase',
    'advance_cleanup_phase',
    'finish_cleanup_phase',
    '_continue_black_rose_after_event',
    'advance_black_rose_quest_steps',
    '_finish_black_rose_phase_after_upgrades',
    '_queue_evocation_damage_abilities',
    'request_next_trigger_decision',
    'process_cleanup_finish_resolution',
    'move_mage_to_room_id',
    'record_physical_action_feedback',
    'clear_lodge_room_choices',
    'clear_board_target_choices',
    '_clear_direct_lodge_effect_choice',
    '_hide_chaos_wildcard_overlay',
    'append_public_log',
]

if '_brwr_submit_prof_enter' in game:
    sys.exit('SUBMIT_PROFILE_BUILD_STOP source is already instrumented')

# Anchor at column zero; never rewrite a call, signal connection or original body.
# Process one function at a time so method order/format is irrelevant.
wrapped = []
for name in methods:
    pat = re.compile(r'(?m)^func ' + re.escape(name) + r'\((.*?)\)\s*(?:->\s*([A-Za-z0-9_\[\]]+))?\s*:\s*\n', re.S)
    hits = list(pat.finditer(game))
    if len(hits) != 1:
        sys.exit(f'SUBMIT_PROFILE_BUILD_STOP function {name} matched {len(hits)} times')
    match = hits[0]
    args_def = match.group(1)
    ret = match.group(2) or ''
    if ret not in ('bool', 'void', ''):
        sys.exit(f'SUBMIT_PROFILE_BUILD_STOP unexpected return type {name}: {ret}')
    # For methods returning an implicit Variant, preserve that return exactly.
    argnames = []
    for item in args_def.split(','):
        item = item.strip()
        if not item:
            continue
        found = re.match(r'^([A-Za-z_][A-Za-z_0-9]*)\b', item)
        if not found:
            sys.exit(f'SUBMIT_PROFILE_BUILD_STOP cannot parse param {name}: {item}')
        argnames.append(found.group(1))
    # Safety: only wrap synchronous methods. GDScript coroutine wrappers require
    # explicitly propagating awaits and cannot be safely auto-generated here.
    next_func = re.search(r'(?m)^func |^@', game[match.end():])
    body = game[match.end(): match.end() + next_func.start()] if next_func else game[match.end():]
    if re.search(r'\bawait\s', body):
        sys.exit(f'SUBMIT_PROFILE_BUILD_STOP async method not safe to wrap: {name}')

    definition = match.group(0)
    renamed = definition.replace('func ' + name + '(', 'func _brwr_original_' + name + '(', 1)
    invocation = f'_brwr_original_{name}(' + ', '.join(argnames) + ')'
    wrapper = definition
    wrapper += '\t_brwr_submit_prof_enter("' + name + '")\n'
    if ret in ('void', ''):
        wrapper += f'\t{invocation}\n'
        wrapper += '\t_brwr_submit_prof_leave()\n\n'
    else:
        wrapper += f'\tvar _brwr_profile_result: bool = {invocation}\n'
        wrapper += '\t_brwr_submit_prof_leave()\n'
        wrapper += '\treturn _brwr_profile_result\n\n'
    game = game[:match.start()] + wrapper + renamed + game[match.end():]
    wrapped.append(name)

profiler = '''\n# AI-only timing instrumentation: no changes to BRWR rules or data.\nvar _brwr_submit_prof_stack: Array[Dictionary] = []\nvar _brwr_submit_prof_stats: Dictionary = {}\n\nfunc _brwr_submit_prof_enter(label: String) -> void:\n\t_brwr_submit_prof_stack.append({"label": label, "start": Time.get_ticks_usec(), "children": 0})\n\nfunc _brwr_submit_prof_leave() -> void:\n\tvar stamp: int = Time.get_ticks_usec()\n\tvar frame: Dictionary = _brwr_submit_prof_stack.pop_back()\n\tvar elapsed: int = max(0, stamp - int(frame["start"]))\n\tvar exclusive: int = max(0, elapsed - int(frame["children"]))\n\tvar name: String = str(frame["label"])\n\tvar item: Dictionary = _brwr_submit_prof_stats.get(name, {"calls": 0, "inclusive_us": 0, "exclusive_us": 0})\n\titem["calls"] = int(item["calls"]) + 1\n\titem["inclusive_us"] = int(item["inclusive_us"]) + elapsed\n\titem["exclusive_us"] = int(item["exclusive_us"]) + exclusive\n\t_brwr_submit_prof_stats[name] = item\n\tif not _brwr_submit_prof_stack.is_empty():\n\t\tvar parent: Dictionary = _brwr_submit_prof_stack[-1]\n\t\tparent["children"] = int(parent["children"]) + elapsed\n\nfunc _brwr_submit_prof_report() -> Dictionary:\n\treturn _brwr_submit_prof_stats.duplicate(true)\n'''
game += '\n' + profiler

# Isolate the scene from regular gameplay and previously tested school cache.
old = 'path="res://ai/game_school_cached.gd"'
if scene.count(old) != 1:
    sys.exit('SUBMIT_PROFILE_BUILD_STOP expected exactly one cached Game script in scene')
scene = scene.replace(old, 'path="res://ai/game_resolution_deep.gd"', 1)

# Separate worker writing independent JSONL files. Its game instance has the
# profiler function because it uses our isolated variant scene.
old_scene = 'load("res://ai/game_school_cached.tscn")'
if worker.count(old_scene) != 1:
    sys.exit('SUBMIT_PROFILE_BUILD_STOP expected exactly one cached scene load in worker')
worker = worker.replace(old_scene, 'load("res://ai/game_resolution_deep.tscn")', 1)
if worker.count('school_cached_episode_') != 1:
    sys.exit('SUBMIT_PROFILE_BUILD_STOP dataset filename anchor not unique')
worker = worker.replace('school_cached_episode_', 'resolution_deep_episode_', 1)
oldstep = 'if not bridge.step(i, choice, str(decision.get("signature", ""))):'
if worker.count(oldstep) != 1:
    sys.exit('SUBMIT_PROFILE_BUILD_STOP bridge.step anchor missing/nonunique')
newstep = ('var _brwr_step_start_us: int = Time.get_ticks_usec()\n'
           '\t\t\t\tvar _brwr_step_accepted: bool = bridge.step(i, choice, str(decision.get("signature", "")))\n'
           '\t\t\t\t_brwr_step_total_us += Time.get_ticks_usec() - _brwr_step_start_us\n'
           '\t\t\t\tif not _brwr_step_accepted:')
worker = worker.replace(oldstep, newstep, 1)
old_decs = 'var decisions: int = 0'
if worker.count(old_decs) != 1:
    sys.exit('SUBMIT_PROFILE_BUILD_STOP decisions variable anchor missing/nonunique')
worker = worker.replace(old_decs, 'var _brwr_step_total_us: int = 0\n\t' + old_decs, 1)
old_end = 'print("AI_EPISODE_COMPLETE seed=", match_seed'
if worker.count(old_end) != 1:
    sys.exit('SUBMIT_PROFILE_BUILD_STOP end marker missing/nonunique')
# Emit a compact marker and write structured profiling data to a sidecar file.
# A large JSON payload printed as one stdout line may be lost or truncated by
# the Godot/PowerShell logging pipeline, which then leaves the summary empty.
profile_footer = (
    'var _brwr_prof_path: String = output_path + ".submit_profile.json"\n'
    '\tvar _brwr_prof_file: FileAccess = FileAccess.open(_brwr_prof_path, FileAccess.WRITE)\n'
    '\tif _brwr_prof_file == null:\n'
    '\t\t_fail("SUBMIT_PROFILE_WRITE_ERROR " + _brwr_prof_path + " (" + str(FileAccess.get_open_error()) + ")")\n'
    '\t\treturn\n'
    '\t_brwr_prof_file.store_string(JSON.stringify({"seed": match_seed, '
    '"decisions": decisions, "bridge_step_us": _brwr_step_total_us, '
    '"functions": game._brwr_submit_prof_report()}))\n'
    '\t_brwr_prof_file.close()\n'
    '\tprint("BRWR_SUBMIT_PROFILE_FILE ", _brwr_prof_path)\n'
    '\t'
)
worker = worker.replace(old_end, profile_footer + old_end, 1)

out = [
    (ROOT / 'ai' / 'game_resolution_deep.gd', game),
    (ROOT / 'ai' / 'game_resolution_deep.tscn', scene),
    (ROOT / 'ai' / 'ai_policy_resolution_deep.gd', worker),
]
for path, contents in out:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding='utf-8')
print(f'RESOLUTION_DEEP_BUILD_OK isolated=1 wrappers={len(wrapped)} checkpoint_unchanged=1')
print('RESOLUTION_DEEP_COMPONENTS ' + ','.join(wrapped))
