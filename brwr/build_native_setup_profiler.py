"""Generate an isolated setup-timing Godot worker from the CURRENT native worker.

Run from the BRWR project root (where project.godot is located), after
make_native_worker.py. Never edits game.gd or the source runner/policy/bridge.
"""
from pathlib import Path

root = Path.cwd()
source = root / 'ai' / 'ai_policy_native_match.gd'
target = root / 'ai' / 'ai_policy_native_setup_profile.gd'
if not (root / 'project.godot').is_file() or not source.is_file():
    raise SystemExit('Run in BRWR/brwr after make_native_worker.py (project.godot missing).')

s = source.read_text(encoding='utf-8-sig')

def replace_once(old: str, new: str, label: str):
    global s
    found = s.count(old)
    if found != 1:
        raise ValueError(f'SETUP_PROFILE_BUILD_STOP {label}: expected 1 anchor, got {found}; originals unchanged.')
    s = s.replace(old, new, 1)

replace_once('func _initialize() -> void:', '''# Setup-only profiler: independent from the regular policy worker.
# All fields are observational and never change gameplay choices.
var _setup_profile_initialize_us: int = 0
var _setup_profile_run_us: int = 0
var _setup_profile_legacy_start_us: int = 0
var _setup_profile_legacy_end_us: int = 0
var _setup_profile_done_us: int = 0
var _setup_profile_first_input_us: int = -1
var _setup_profile_first_step_us: int = -1
var _setup_profile_stages_us: Dictionary = {}
var _setup_profile_frames_count: int = 0
var _setup_profile_frame_min_us: int = 9223372036854775807
var _setup_profile_frame_max_us: int = 0

func _setup_profile_mark(label: String, since_us: int) -> void:
    _setup_profile_stages_us[label] = int(_setup_profile_stages_us.get(label, 0)) + Time.get_ticks_usec() - since_us

func _setup_profile_stages_ms() -> Dictionary:
    var out: Dictionary = {}
    for name in _setup_profile_stages_us:
        out[name] = float(_setup_profile_stages_us[name]) / 1000.0
    return out

func _setup_profile_emit(decisions: int, seed: int, bots: int, avatar: String, winner: int) -> void:
    var setup_sum_us: int = 0
    for val in _setup_profile_stages_us.values():
        setup_sum_us += int(val)
    var end_us: int = Time.get_ticks_usec()
    print("NATIVE_SETUP_PROFILE_JSON " + JSON.stringify({
        "seed": seed,
        "bots": bots,
        "avatar": avatar,
        "winner": winner,
        "decisions": decisions,
        "game_internal_wall_ms": float(end_us - _setup_profile_run_us) / 1000.0,
        "initialize_to_run_ms": float(_setup_profile_run_us - _setup_profile_initialize_us) / 1000.0,
        "legacy_setup_ms": float(_setup_profile_legacy_end_us - _setup_profile_legacy_start_us) / 1000.0,
        "legacy_setup_unclassified_ms": float(_setup_profile_legacy_end_us - _setup_profile_legacy_start_us - setup_sum_us + int(_setup_profile_stages_us.get("arguments", 0)) + int(_setup_profile_stages_us.get("episode_start_record", 0))) / 1000.0,
        "setup_to_first_input_ms": float(_setup_profile_first_input_us - _setup_profile_done_us) / 1000.0 if _setup_profile_first_input_us >= 0 else -1.0,
        "setup_to_first_step_ms": float(_setup_profile_first_step_us - _setup_profile_done_us) / 1000.0 if _setup_profile_first_step_us >= 0 else -1.0,
        "setup_20_frames_count": _setup_profile_frames_count,
        "setup_frame_min_ms": float(_setup_profile_frame_min_us) / 1000.0 if _setup_profile_frames_count > 0 else 0.0,
        "setup_frame_max_ms": float(_setup_profile_frame_max_us) / 1000.0,
        "stages_ms": _setup_profile_stages_ms()
    }))

func _initialize() -> void:''', 'class instrumentation')

replace_once('''func _initialize() -> void:
	call_deferred("_run")''', '''func _initialize() -> void:
    _setup_profile_initialize_us = Time.get_ticks_usec()
    call_deferred("_run")''', 'initialize timestamp')

replace_once('''func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()''', '''func _run() -> void:
    _setup_profile_run_us = Time.get_ticks_usec()
    var _setup_profile_tick_us: int = _setup_profile_run_us
    var args: PackedStringArray = OS.get_cmdline_user_args()''', 'run timestamp')

replace_once('''	var packed: PackedScene = load("res://game.tscn")''', '''    _setup_profile_mark("arguments", _setup_profile_tick_us)
    _setup_profile_legacy_start_us = Time.get_ticks_usec()
    _setup_profile_tick_us = Time.get_ticks_usec()
    var packed: PackedScene = load("res://game.tscn")''', 'scene load start')

replace_once('''	var game: Variant = packed.instantiate()''', '''    _setup_profile_mark("scene_load", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()
    var game: Variant = packed.instantiate()
    _setup_profile_mark("scene_instantiate", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()''', 'scene instantiate')

replace_once('''	root.add_child(game)
	for _n in range(20):
		await process_frame''', '''    _setup_profile_mark("game_config", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()
    root.add_child(game)
    _setup_profile_mark("root_add_child_and_ready", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()
    for _n in range(20):
        var _setup_profile_frame_started_us: int = Time.get_ticks_usec()
        await process_frame
        var _setup_profile_frame_elapsed_us: int = Time.get_ticks_usec() - _setup_profile_frame_started_us
        _setup_profile_frames_count += 1
        _setup_profile_frame_min_us = mini(_setup_profile_frame_min_us, _setup_profile_frame_elapsed_us)
        _setup_profile_frame_max_us = maxi(_setup_profile_frame_max_us, _setup_profile_frame_elapsed_us)
    _setup_profile_mark("initial_20_frames", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()''', 'initial twenty frames')

replace_once('''	var session_dir: String = ProjectSettings.globalize_path("res://ai/runtime")''', '''    _setup_profile_mark("player_avatar_ready_checks", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()
    var session_dir: String = ProjectSettings.globalize_path("res://ai/runtime")''', 'setup directories begin')

replace_once('''	var policy = NativePolicy.new()''', '''    _setup_profile_mark("directories_and_dataset_open", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()
    var policy = NativePolicy.new()
    _setup_profile_mark("policy_construct", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()''', 'policy construct')

replace_once('''	policy.set_seed(match_seed + 812341)
	var bridge = Bridge.new(game)
	if not game.start_game_flow():''', '''    _setup_profile_mark("policy_load_json_and_weights", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()
    policy.set_seed(match_seed + 812341)
    _setup_profile_mark("policy_set_seed", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()
    var bridge = Bridge.new(game)
    _setup_profile_mark("bridge_construct", _setup_profile_tick_us)
    _setup_profile_tick_us = Time.get_ticks_usec()
    if not game.start_game_flow():''', 'model load and game start')

replace_once('''		_fail("start_game_flow() failed")
		return

	_store(output_file, {''', '''        _fail("start_game_flow() failed")
        return
    _setup_profile_mark("start_game_flow", _setup_profile_tick_us)
    _setup_profile_legacy_end_us = Time.get_ticks_usec()
    _setup_profile_tick_us = Time.get_ticks_usec()

    _store(output_file, {''', 'game start success')

replace_once('''	var decisions: int = 0''', '''    _setup_profile_mark("episode_start_record", _setup_profile_tick_us)
    _setup_profile_done_us = Time.get_ticks_usec()
    var decisions: int = 0''', 'finish setup')

replace_once('''		if game.waiting_for_player_input:
			var acted: bool = false''', '''        if game.waiting_for_player_input:
            if _setup_profile_first_input_us < 0:
                _setup_profile_first_input_us = Time.get_ticks_usec()
            var acted: bool = false''', 'first input timestamp')

replace_once('''				if not bridge.step(i, choice, str(decision.get("signature", ""))):''', '''                if _setup_profile_first_step_us < 0:
                    _setup_profile_first_step_us = Time.get_ticks_usec()
                if not bridge.step(i, choice, str(decision.get("signature", ""))):''', 'first step timestamp')

replace_once('''	print("AI_EPISODE_COMPLETE seed=", match_seed, " scenario=", scenario,''', '''    _setup_profile_emit(decisions, match_seed, human_count, avatar_id, winner)
    print("AI_EPISODE_COMPLETE seed=", match_seed, " scenario=", scenario,''', 'emit setup report')

# Isolate output datasets, leaving ordinary benchmark recordings untouched.
replace_once('''"native_episode_%d_%s.jsonl"''', '''"native_setup_episode_%d_%s.jsonl"''', 'dataset isolation')

# Original source uses tabs; generated GDScript must use a single indentation
# style per block. We injected 4-space indents, so normalize all tabs to spaces.
s = s.replace('\t', '    ')
# Keep CRLF/windows-friendly UTF-8, and write only after *all* anchor checks.
target.write_text(s, encoding='utf-8')
print(f'NATIVE_SETUP_BUILD_OK isolated_worker={target} originals_unchanged=1')
