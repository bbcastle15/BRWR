"""Create separate, instrumented native Godot policy, bridge and runner.

Usage: from BRWR/brwr: python .\build_native_profiler.py
Requires make_native_worker.py to have generated ai/ai_policy_native_match.gd.
Does not overwrite the ordinary worker, neural policy, AI bridge, or game rules.
"""
from pathlib import Path

ROOT = Path.cwd()
AI = ROOT / 'ai'
FILES = (
    AI / 'ai_policy_native_match.gd',
    AI / 'ai_native_policy_v4.gd',
    AI / 'ai_bridge.gd',
)
if not (ROOT / 'project.godot').is_file() or not all(p.is_file() for p in FILES):
    raise SystemExit('Run from BRWR/brwr after make_native_worker.py; required Godot sources not found.')


def patch_one(s, old, new, label):
    n = s.count(old)
    if n != 1:
        raise ValueError(f'Cannot patch {label}: expected 1 occurrence, found {n}; originals untouched.')
    return s.replace(old, new, 1)


src_worker, src_policy, src_bridge = (p.read_text(encoding='utf-8-sig') for p in FILES)

# ---------- Bridge: wrap public methods instead of matching the body of step(). ----------
# The active project may change how a stage is committed. Profiling by wrapping
# existing functions is resilient to these changes and preserves original calls.
b = src_bridge
b = patch_one(b, 'var _stages: Dictionary = {}', '''var _stages: Dictionary = {}

# Profiling counters; only used in the generated ai_bridge_native_profile.gd.
var profile_fresh_decision_us: int = 0
var profile_fresh_decision_calls: int = 0
var profile_stage_commit_us: int = 0
var profile_stage_commit_calls: int = 0
var profile_submit_us: int = 0
var profile_submit_calls: int = 0
var _profile_inside_step: bool = false''', 'bridge counters')

# decision() invoked from step() is revalidation, while a call from the worker
# creates the next choice. Count only calls inside step().
b = patch_one(b, 'func decision(player_index: int) -> Dictionary:', '''func decision(player_index: int) -> Dictionary:
	var _p_started: int = Time.get_ticks_usec()
	var _p_result: Dictionary = _profile_original_decision(player_index)
	if _profile_inside_step:
		profile_fresh_decision_us += Time.get_ticks_usec() - _p_started
		profile_fresh_decision_calls += 1
	return _p_result

func _profile_original_decision(player_index: int) -> Dictionary:''', 'bridge decision wrapper')

# No assumptions whatsoever about stage handling within step(). The wrapper
# only brackets its execution; the worker measures total step() separately.
b = patch_one(b, 'func step(player_index: int, choice_id: int, signature: String) -> bool:', '''func step(player_index: int, choice_id: int, signature: String) -> bool:
	var _p_previous_inside_step: bool = _profile_inside_step
	_profile_inside_step = true
	var _p_result: bool = _profile_original_step(player_index, choice_id, signature)
	_profile_inside_step = _p_previous_inside_step
	return _p_result

func _profile_original_step(player_index: int, choice_id: int, signature: String) -> bool:''', 'bridge step wrapper')

# Optional deeper counters: if _advance_stage() differs in the live branch,
# the main benchmark still runs and reports zero calls for this subcategory.
_stage_sig = 'func _advance_stage(player_index: int, state: Dictionary, choice: Dictionary) -> bool:'
if b.count(_stage_sig) == 1:
    b = b.replace(_stage_sig, '''func _advance_stage(player_index: int, state: Dictionary, choice: Dictionary) -> bool:
	var _p_started: int = Time.get_ticks_usec()
	var _p_result: bool = _profile_original_advance_stage(player_index, state, choice)
	profile_stage_commit_us += Time.get_ticks_usec() - _p_started
	profile_stage_commit_calls += 1
	return _p_result

func _profile_original_advance_stage(player_index: int, state: Dictionary, choice: Dictionary) -> bool:''', 1)
else:
    print('NATIVE_PROFILE_WARNING: _advance_stage signature differs; stage sub-timing unavailable')

# A lightweight wrapper around direct game submits. Stage commits call the
# same method, so the submit counter includes both direct and staged actions.
_submit_call = '_game.submit_beta_input(player_index, payload)'
_submit_count = b.count(_submit_call)
if _submit_count:
    b = b.replace(_submit_call, '_profile_submit_input(player_index, payload)')
    b += '''

func _profile_submit_input(player_index: int, payload: Dictionary) -> bool:
	var _p_started: int = Time.get_ticks_usec()
	var _p_result: bool = _game.submit_beta_input(player_index, payload)
	profile_submit_us += Time.get_ticks_usec() - _p_started
	profile_submit_calls += 1
	return _p_result
'''
    print('NATIVE_PROFILE_SUBMIT_WRAPPED', _submit_count)
else:
    print('NATIVE_PROFILE_WARNING: direct submit call form differs; submit sub-timing unavailable')

# ---------- Policy: separate feature encoding, network forward, sampling overhead. ----------
p = src_policy
p = patch_one(p, 'var _loaded := false', '''var _loaded := false

# These counters are not used to influence action selection.
var profile_encode_us: int = 0
var profile_encode_calls: int = 0
var profile_score_us: int = 0
var profile_score_calls: int = 0''', 'native policy counters')
p = patch_one(p, '''\tfor i in range(options.size()):
\t\tlogits.append(score(encode_action(obs, decision, options[i], i, options.size())))''', '''\tfor i in range(options.size()):
\t\tvar _p_encode_started: int = Time.get_ticks_usec()
\t\tvar _p_features: PackedFloat32Array = encode_action(obs, decision, options[i], i, options.size())
\t\tprofile_encode_us += Time.get_ticks_usec() - _p_encode_started
\t\tprofile_encode_calls += 1
\t\tvar _p_score_started: int = Time.get_ticks_usec()
\t\tlogits.append(score(_p_features))
\t\tprofile_score_us += Time.get_ticks_usec() - _p_score_started
\t\tprofile_score_calls += 1''', 'native policy encode/score')

# ---------- Worker: per-step and per-frame counters. ----------
w = src_worker
w = patch_one(w, 'const Bridge = preload("res://ai/ai_bridge.gd")',
    'const Bridge = preload("res://ai/ai_bridge_native_profile.gd")', 'worker profiled bridge preload')
w = patch_one(w, 'const NativePolicy = preload("res://ai/ai_native_policy_v4.gd")',
    'const NativePolicy = preload("res://ai/ai_native_policy_profile.gd")', 'worker profiled policy preload')
w = patch_one(w, 'func _initialize() -> void:\n', '''# All times in microseconds from a monotonic clock. Wall time is NOT a sum of
# components: game logic, frame waiting and I/O interact across phases.
var _p_started_us: int = Time.get_ticks_usec()
var _p_decision_us: int = 0
var _p_decision_calls: int = 0
var _p_observation_us: int = 0
var _p_policy_us: int = 0
var _p_step_us: int = 0
var _p_store_us: int = 0
var _p_flush_us: int = 0
var _p_frame_us: int = 0
var _p_frame_idle_us: int = 0
var _p_frame_active_us: int = 0
var _p_frames: int = 0
var _p_idle_frames: int = 0
var _p_active_frames: int = 0
var _p_setup_us: int = 0
var _p_action_type: Dictionary = {}

func _initialize() -> void:
''', 'worker counters')
w = patch_one(w, '''\tvar packed: PackedScene = load("res://game.tscn")''', '''\tvar _p_setup_started: int = Time.get_ticks_usec()
\tvar packed: PackedScene = load("res://game.tscn")''', 'setup begin')
w = patch_one(w, '''\tif not game.start_game_flow():
\t\toutput_file.close()
\t\t_fail("start_game_flow() failed")
\t\treturn''', '''\tif not game.start_game_flow():
\t\toutput_file.close()
\t\t_fail("start_game_flow() failed")
\t\treturn
\t_p_setup_us += Time.get_ticks_usec() - _p_setup_started''', 'setup end')
w = patch_one(w, '''\t\t\t\tvar decision: Dictionary = bridge.decision(i)
''', '''\t\t\t\tvar _p_tick: int = Time.get_ticks_usec()
\t\t\t\tvar decision: Dictionary = bridge.decision(i)
\t\t\t\t_p_decision_us += Time.get_ticks_usec() - _p_tick
\t\t\t\t_p_decision_calls += 1
''', 'worker decision timing')
w = patch_one(w, '''\t\t\t\tvar observation: Dictionary = bridge.observation(i)
''', '''\t\t\t\t_p_tick = Time.get_ticks_usec()
\t\t\t\tvar observation: Dictionary = bridge.observation(i)
\t\t\t\t_p_observation_us += Time.get_ticks_usec() - _p_tick
''', 'worker observation timing')
w = patch_one(w, '''\t\t\t\tvar choice: int = policy.choose(observation, decision)
''', '''\t\t\t\t_p_tick = Time.get_ticks_usec()
\t\t\t\tvar choice: int = policy.choose(observation, decision)
\t\t\t\t_p_policy_us += Time.get_ticks_usec() - _p_tick
''', 'worker policy timing')
w = patch_one(w, '''\t\t\t\tif not bridge.step(i, choice, str(decision.get("signature", ""))):
''', '''\t\t\t\t_p_tick = Time.get_ticks_usec()
\t\t\t\tvar _p_step_ok: bool = bridge.step(i, choice, str(decision.get("signature", "")))
\t\t\t\tvar _p_step_elapsed: int = Time.get_ticks_usec() - _p_tick
\t\t\t\t_p_step_us += _p_step_elapsed
\t\t\t\tvar _p_request_type: String = str(decision.get("type", ""))
\t\t\t\tvar _p_type_record: Dictionary = _p_action_type.get(_p_request_type, {"count": 0, "step_us": 0})
\t\t\t\t_p_type_record["count"] = int(_p_type_record["count"]) + 1
\t\t\t\t_p_type_record["step_us"] = int(_p_type_record["step_us"]) + _p_step_elapsed
\t\t\t\t_p_action_type[_p_request_type] = _p_type_record
\t\t\t\tif not _p_step_ok:
''', 'worker bridge step timing')
w = patch_one(w, '''\t\t\t\tif decisions % FLUSH_EVERY == 0:
\t\t\t\t\toutput_file.flush()''', '''\t\t\t\tif decisions % FLUSH_EVERY == 0:
\t\t\t\t\tvar _p_flush_started: int = Time.get_ticks_usec()
\t\t\t\t\toutput_file.flush()
\t\t\t\t\t_p_flush_us += Time.get_ticks_usec() - _p_flush_started''', 'worker flush timing')
w = patch_one(w, '''\t\tawait process_frame

\tif not game.game_has_ended:''', '''\t\tvar _p_frame_idle: bool = not game.waiting_for_player_input
\t\tvar _p_frame_started: int = Time.get_ticks_usec()
\t\tawait process_frame
\t\tvar _p_frame_elapsed: int = Time.get_ticks_usec() - _p_frame_started
\t\t_p_frame_us += _p_frame_elapsed
\t\t_p_frames += 1
\t\tif _p_frame_idle:
\t\t\t_p_idle_frames += 1
\t\t\t_p_frame_idle_us += _p_frame_elapsed
\t\telse:
\t\t\t_p_active_frames += 1
\t\t\t_p_frame_active_us += _p_frame_elapsed

\tif not game.game_has_ended:''', 'worker frame wait')
w = patch_one(w, '''\toutput_file.close()
\tprint("AI_EPISODE_COMPLETE seed=",''', '''\toutput_file.close()
\tvar _p_total_us: int = Time.get_ticks_usec() - _p_started_us
\tprint("NATIVE_PROFILE_JSON " + JSON.stringify({
\t\t"wall_ms": _p_total_us / 1000.0,
\t\t"setup_ms": _p_setup_us / 1000.0,
\t\t"decision_ms": _p_decision_us / 1000.0,
\t\t"decision_calls": _p_decision_calls,
\t\t"observation_ms": _p_observation_us / 1000.0,
\t\t"policy_ms": _p_policy_us / 1000.0,
\t\t"policy_encode_ms": policy.profile_encode_us / 1000.0,
\t\t"policy_encode_calls": policy.profile_encode_calls,
\t\t"policy_score_ms": policy.profile_score_us / 1000.0,
\t\t"policy_score_calls": policy.profile_score_calls,
\t\t"step_ms": _p_step_us / 1000.0,
\t\t"step_fresh_decision_ms": bridge.profile_fresh_decision_us / 1000.0,
\t\t"step_fresh_decision_calls": bridge.profile_fresh_decision_calls,
\t\t"step_stage_commit_ms": bridge.profile_stage_commit_us / 1000.0,
\t\t"step_stage_commit_calls": bridge.profile_stage_commit_calls,
\t\t"step_game_submit_ms": bridge.profile_submit_us / 1000.0,
\t\t"step_game_submit_calls": bridge.profile_submit_calls,
\t\t"dataset_store_ms": _p_store_us / 1000.0,
\t\t"dataset_flush_ms": _p_flush_us / 1000.0,
\t\t"frame_wait_ms": _p_frame_us / 1000.0,
\t\t"frame_idle_wait_ms": _p_frame_idle_us / 1000.0,
\t\t"frame_active_wait_ms": _p_frame_active_us / 1000.0,
\t\t"frame_count": _p_frames,
\t\t"idle_frame_count": _p_idle_frames,
\t\t"active_frame_count": _p_active_frames,
\t\t"action_types": _p_action_type,
\t\t"decisions": decisions,
\t\t"seed": match_seed,
\t\t"bots": human_count,
\t\t"avatar": avatar_id,
\t\t"winner": winner
\t}))
\tprint("AI_EPISODE_COMPLETE seed=",''', 'worker profile output')
w = patch_one(w, '''func _store(target: FileAccess, entry: Dictionary) -> void:
\ttarget.store_line(JSON.stringify(entry))''', '''func _store(target: FileAccess, entry: Dictionary) -> void:
\tvar _p_store_started: int = Time.get_ticks_usec()
\ttarget.store_line(JSON.stringify(entry))
\t_p_store_us += Time.get_ticks_usec() - _p_store_started''', 'worker store timing')
w = patch_one(w, '"native_episode_%d_%s.jsonl" % [match_seed, scenario]',
    '"native_profile_episode_%d_%s.jsonl" % [match_seed, scenario]', 'dataset isolated')

# Files are written only after all required anchors were validated.
output_files = {
    AI / 'ai_bridge_native_profile.gd': b,
    AI / 'ai_native_policy_profile.gd': p,
    AI / 'ai_policy_native_profile.gd': w,
}
for path, content in output_files.items():
    path.write_text(content, encoding='utf-8', newline='\n')
    print('NATIVE_PROFILE_FILE_OK', path)
print('NATIVE_PROFILE_BUILD_OK originals_unchanged=1')
