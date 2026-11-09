"""Generate an isolated, instrumentation-only runner from CURRENT cached AI worker.

Run after build_school_cache_variant.py. Does not edit game.gd, policies,
bridge, cached worker, JSON rules, or neural checkpoint.
"""
from pathlib import Path
import sys

root = Path.cwd()
source = root / 'ai' / 'ai_policy_school_cached_match.gd'
output = root / 'ai' / 'ai_policy_runtime_breakdown.gd'
if not (root / 'project.godot').is_file() or not source.is_file():
    sys.exit('RUNTIME_BREAKDOWN_BUILD_STOP run from BRWR/brwr after generating cached worker')

s = source.read_text(encoding='utf-8-sig')

def replace_once(old, new, name):
    global s
    count = s.count(old)
    if count != 1:
        sys.exit(f'RUNTIME_BREAKDOWN_BUILD_STOP anchor {name}: expected 1, found {count}; no files changed')
    s = s.replace(old, new, 1)

# Measure only the running worker. No inference, bridge, or Game logic is changed.
replace_once('func _initialize() -> void:', '''# Profiling-only counters. All times measured on the same Godot clock.
var _rt_start_us: int = Time.get_ticks_usec()
var _rt_scene_load_us: int = 0
var _rt_instantiate_us: int = 0
var _rt_add_child_us: int = 0
var _rt_bootstrap_frames_us: int = 0
var _rt_start_flow_us: int = 0
var _rt_decision_us: int = 0
var _rt_decision_calls: int = 0
var _rt_observation_us: int = 0
var _rt_observation_calls: int = 0
var _rt_choose_us: int = 0
var _rt_choose_calls: int = 0
var _rt_step_us: int = 0
var _rt_step_calls: int = 0
var _rt_store_us: int = 0
var _rt_store_calls: int = 0
var _rt_flush_us: int = 0
var _rt_frame_wait_us: int = 0
var _rt_frame_count: int = 0
var _rt_idle_wait_us: int = 0
var _rt_idle_count: int = 0
var _rt_active_wait_us: int = 0
var _rt_active_count: int = 0

func _initialize() -> void:''', 'globals')

replace_once('var packed: PackedScene = load("res://ai/game_school_cached.tscn")',
 '''var _rt_t_load: int = Time.get_ticks_usec()
	var packed: PackedScene = load("res://ai/game_school_cached.tscn")
	_rt_scene_load_us += Time.get_ticks_usec() - _rt_t_load''', 'load')
replace_once('var game: Variant = packed.instantiate()',
 '''var _rt_t_instantiate: int = Time.get_ticks_usec()
	var game: Variant = packed.instantiate()
	_rt_instantiate_us += Time.get_ticks_usec() - _rt_t_instantiate''', 'instantiate')
replace_once('\troot.add_child(game)\n\tfor _n in range(20):\n\t\tawait process_frame',
 '''	var _rt_t_add_child: int = Time.get_ticks_usec()
	root.add_child(game)
	_rt_add_child_us += Time.get_ticks_usec() - _rt_t_add_child
	var _rt_t_bootstrap: int = Time.get_ticks_usec()
	for _n in range(20):
		await process_frame
	_rt_bootstrap_frames_us += Time.get_ticks_usec() - _rt_t_bootstrap''', 'add_child and bootstrap')
replace_once('''	if not game.start_game_flow():
		output_file.close()
		_fail("start_game_flow() failed")
		return''', '''	var _rt_t_start_flow: int = Time.get_ticks_usec()
	var _rt_start_ok: bool = game.start_game_flow()
	_rt_start_flow_us += Time.get_ticks_usec() - _rt_t_start_flow
	if not _rt_start_ok:
		output_file.close()
		_fail("start_game_flow() failed")
		return''', 'start_game_flow')
replace_once('''				var decision: Dictionary = bridge.decision(i)''',
 '''				var _rt_t_decision: int = Time.get_ticks_usec()
				var decision: Dictionary = bridge.decision(i)
				_rt_decision_us += Time.get_ticks_usec() - _rt_t_decision
				_rt_decision_calls += 1''', 'decision')
replace_once('''				var observation: Dictionary = bridge.observation(i)''',
 '''				var _rt_t_observation: int = Time.get_ticks_usec()
				var observation: Dictionary = bridge.observation(i)
				_rt_observation_us += Time.get_ticks_usec() - _rt_t_observation
				_rt_observation_calls += 1''', 'observation')
replace_once('''				var choice: int = policy.choose(observation, decision)''',
 '''				var _rt_t_choose: int = Time.get_ticks_usec()
				var choice: int = policy.choose(observation, decision)
				_rt_choose_us += Time.get_ticks_usec() - _rt_t_choose
				_rt_choose_calls += 1''', 'policy.choose')
replace_once('''				if not bridge.step(i, choice, str(decision.get("signature", ""))):''',
 '''				var _rt_t_step: int = Time.get_ticks_usec()
				var _rt_step_ok: bool = bridge.step(i, choice, str(decision.get("signature", "")))
				_rt_step_us += Time.get_ticks_usec() - _rt_t_step
				_rt_step_calls += 1
				if not _rt_step_ok:''', 'bridge.step')
replace_once('''				if decisions % FLUSH_EVERY == 0:
					output_file.flush()''',
 '''				if decisions % FLUSH_EVERY == 0:
					var _rt_t_flush: int = Time.get_ticks_usec()
					output_file.flush()
					_rt_flush_us += Time.get_ticks_usec() - _rt_t_flush''', 'flush')
replace_once('''		await process_frame

	if not game.game_has_ended:''',
 '''		var _rt_waiting_for_player: bool = game.waiting_for_player_input
		var _rt_t_frame: int = Time.get_ticks_usec()
		await process_frame
		var _rt_dt_frame: int = Time.get_ticks_usec() - _rt_t_frame
		_rt_frame_wait_us += _rt_dt_frame
		_rt_frame_count += 1
		if _rt_waiting_for_player:
			_rt_active_wait_us += _rt_dt_frame
			_rt_active_count += 1
		else:
			_rt_idle_wait_us += _rt_dt_frame
			_rt_idle_count += 1

	if not game.game_has_ended:''', 'frame wait')
replace_once('''func _store(target: FileAccess, entry: Dictionary) -> void:
	target.store_line(JSON.stringify(entry))''',
 '''func _store(target: FileAccess, entry: Dictionary) -> void:
	var _rt_t_store: int = Time.get_ticks_usec()
	target.store_line(JSON.stringify(entry))
	_rt_store_us += Time.get_ticks_usec() - _rt_t_store
	_rt_store_calls += 1''', 'dataset store')
replace_once('school_cached_episode_', 'runtime_breakdown_episode_', 'isolated dataset filename')
# The profile is kept as a sidecar, not printed as a large JSON log message.
replace_once('''	output_file.close()
	print("AI_EPISODE_COMPLETE seed=", match_seed''', '''	output_file.close()
	var _rt_total_us: int = Time.get_ticks_usec() - _rt_start_us
	var _rt_report: Dictionary = {
		"seed": match_seed, "decisions": decisions, "winner": winner,
		"total_us": _rt_total_us,
		"scene_load_us": _rt_scene_load_us,
		"scene_instantiate_us": _rt_instantiate_us,
		"root_add_child_us": _rt_add_child_us,
		"bootstrap_frames_us": _rt_bootstrap_frames_us,
		"start_game_flow_us": _rt_start_flow_us,
		"bridge_decision_us": _rt_decision_us,
		"bridge_observation_us": _rt_observation_us,
		"native_choose_us": _rt_choose_us,
		"bridge_step_us": _rt_step_us,
		"dataset_store_us": _rt_store_us,
		"dataset_flush_us": _rt_flush_us,
		"frame_wait_us": _rt_frame_wait_us,
		"frame_idle_wait_us": _rt_idle_wait_us,
		"frame_active_wait_us": _rt_active_wait_us,
		"frame_count": _rt_frame_count,
		"frame_idle_count": _rt_idle_count,
		"frame_active_count": _rt_active_count,
		"bridge_decision_calls": _rt_decision_calls,
		"bridge_observation_calls": _rt_observation_calls,
		"native_choose_calls": _rt_choose_calls,
		"bridge_step_calls": _rt_step_calls,
		"dataset_store_calls": _rt_store_calls
	}
	var _rt_report_path: String = output_path + ".runtime_profile.json"
	var _rt_report_file: FileAccess = FileAccess.open(_rt_report_path, FileAccess.WRITE)
	if _rt_report_file == null:
		_fail("RUNTIME_BREAKDOWN_WRITE_ERROR " + _rt_report_path + " " + str(FileAccess.get_open_error()))
		return
	_rt_report_file.store_string(JSON.stringify(_rt_report))
	_rt_report_file.close()
	print("BRWR_RUNTIME_BREAKDOWN_FILE ", _rt_report_path)
	print("AI_EPISODE_COMPLETE seed=", match_seed''', 'profile footer')

output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(s, encoding='utf-8', newline='\n')
print('RUNTIME_BREAKDOWN_BUILD_OK isolated=1 original_game_unchanged=1 worker_unchanged=1')
