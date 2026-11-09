# BRWR AI v4 - live PyTorch self-play Godot worker.
# Run with ai/python/train.py; do not execute standalone without a Python policy.
# No changes to Game rules. All choices are validated through ai_bridge.gd.
extends SceneTree

const Bridge = preload("res://ai/ai_bridge.gd")
const NativePolicy = preload("res://ai/ai_native_policy_v4.gd")
const MAX_DECISIONS_PER_HUMAN := 1200
const MAX_IDLE_FRAMES := 2000
const FLUSH_EVERY := 25
const RESPONSE_TIMEOUT_MS := 120000


# Profiling-only counters. All times measured on the same Godot clock.
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

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var match_seed: int = 20261108
	if args.size() >= 1:
		if not args[0].is_valid_int():
			_fail("Invalid seed: " + args[0])
			return
		match_seed = int(args[0])
	# CLI: seed human_players avatar_id difficulty [swap|normal]
	# Legacy CLI: seed [swap]
	var human_count: int = 2
	var avatar_id: String = "none"
	var avatar_difficulty: String = "apprentice"
	var swap_styles: bool = false
	if args.size() >= 2:
		if args[1].to_lower() in ["swap", "true"]:
			swap_styles = true
		elif args[1].is_valid_int():
			human_count = int(args[1])
		else:
			_fail("Invalid human-player count: " + args[1])
			return
	if args.size() >= 3:
		avatar_id = args[2].to_lower()
	if avatar_id in ["off", "disabled", "no", "-"]:
		avatar_id = "none"
	if args.size() >= 4:
		avatar_difficulty = args[3].to_lower()
	if args.size() >= 5:
		swap_styles = args[4].to_lower() in ["swap", "1", "true"]
	if not (avatar_difficulty in ["apprentice", "master"]):
		_fail("Unknown Avatar difficulty: " + avatar_difficulty)
		return
	var use_avatar: bool = avatar_id != "none"
	var total_seats: int = human_count + (1 if use_avatar else 0)
	if human_count < 2 or total_seats > 6:
		_fail("Invalid AI training setup: %d Mage bots + %d Avatar; requires 2..6 Mage bots and at most 6 seats total" % [human_count, 1 if use_avatar else 0])
		return

	var _rt_t_load: int = Time.get_ticks_usec()
	var packed: PackedScene = load("res://ai/game_school_cached.tscn")
	_rt_scene_load_us += Time.get_ticks_usec() - _rt_t_load
	if packed == null:
		_fail("Missing game.tscn")
		return
	var _rt_t_instantiate: int = Time.get_ticks_usec()
	var game: Variant = packed.instantiate()
	_rt_instantiate_us += Time.get_ticks_usec() - _rt_t_instantiate
	game.auto_start_game_flow = false
	game.run_tests_on_ready = false # Normal mage -> school -> grimoire choice order.
	game.enable_beta_hud = false
	game.player_count = total_seats
	game.game_seed = match_seed
	if use_avatar:
		game.avatar_selection = {"id": avatar_id, "difficulty": avatar_difficulty}
	var _rt_t_add_child: int = Time.get_ticks_usec()
	root.add_child(game)
	_rt_add_child_us += Time.get_ticks_usec() - _rt_t_add_child
	var _rt_t_bootstrap: int = Time.get_ticks_usec()
	for _n in range(20):
		await process_frame
	_rt_bootstrap_frames_us += Time.get_ticks_usec() - _rt_t_bootstrap
	if game.players.size() != total_seats:
		_fail("Game initialization failed")
		return
	if use_avatar and (game.avatar == null or int(game.avatar.player_index) != total_seats - 1):
		_fail("Avatar was requested but was not initialized in the last seat")
		return
	if not use_avatar and game.avatar != null:
		_fail("Avatar initialized in a normal match")
		return
	var actual_avatar_id: String = str(game.avatar.definition.get("id", "")) if game.avatar != null else "none"

	var session_dir: String = ProjectSettings.globalize_path("res://ai/runtime")
	var session_error: Error = DirAccess.make_dir_recursive_absolute(session_dir)
	if session_error != OK:
		_fail("Cannot create IPC directory: " + session_dir)
		return
	var output_dir: String = ProjectSettings.globalize_path("res://ai/datasets")
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	if mkdir_error != OK:
		_fail("Cannot create dataset folder: " + output_dir + " (" + str(mkdir_error) + ")")
		return
	var mode: String = "swap" if swap_styles else "normal"
	var scenario: String = "h%d_av%s_%s_%s" % [human_count, actual_avatar_id, avatar_difficulty if use_avatar else "na", mode]
	var output_path: String = output_dir.path_join("runtime_breakdown_episode_%d_%s.jsonl" % [match_seed, scenario])
	var output_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		_fail("Cannot write " + output_path + " (" + str(FileAccess.get_open_error()) + ")")
		return

	# All Mage seats share the same trainable Python policy. Avatar stays native.
	var policy = NativePolicy.new()
	if not policy.load_model("res://ai/model/native_policy_v4.json"):
		output_file.close()
		_fail("Native model load failed")
		return
	policy.set_seed(match_seed + 812341)
	var bridge = Bridge.new(game)
	var _rt_t_start_flow: int = Time.get_ticks_usec()
	var _rt_start_ok: bool = game.start_game_flow()
	_rt_start_flow_us += Time.get_ticks_usec() - _rt_t_start_flow
	if not _rt_start_ok:
		output_file.close()
		_fail("start_game_flow() failed")
		return

	_store(output_file, {
		"record_type": "episode_start",
		"schema_version": 4,
		"seed": match_seed,
		"player_count": total_seats,
		"human_player_count": human_count,
		"avatar_id": actual_avatar_id,
		"avatar_difficulty": avatar_difficulty if use_avatar else "none",
		"avatar_seat": total_seats - 1 if use_avatar else -1,
		"policy": "native_gdscript_policy_v4",
		"active_schools": game.active_school_ids.duplicate()
	})

	var decisions: int = 0
	var idle_frames: int = 0
	var max_decisions: int = MAX_DECISIONS_PER_HUMAN * human_count
	while decisions < max_decisions and not game.game_has_ended:
		if game.waiting_for_player_input:
			var acted: bool = false
			for i in range(human_count):
				var _rt_t_decision: int = Time.get_ticks_usec()
				var decision: Dictionary = bridge.decision(i)
				_rt_decision_us += Time.get_ticks_usec() - _rt_t_decision
				_rt_decision_calls += 1
				if decision.is_empty():
					continue
				if not bool(decision.get("supported", false)):
					output_file.close()
					_fail("Unsupported request " + str(decision.get("type", "")))
					return
				var _rt_t_observation: int = Time.get_ticks_usec()
				var observation: Dictionary = bridge.observation(i)
				_rt_observation_us += Time.get_ticks_usec() - _rt_t_observation
				_rt_observation_calls += 1
				var _rt_t_choose: int = Time.get_ticks_usec()
				var choice: int = policy.choose(observation, decision)
				_rt_choose_us += Time.get_ticks_usec() - _rt_t_choose
				_rt_choose_calls += 1
				if choice < 0:
					output_file.close()
					_fail("Native policy failed to choose for decision " + str(decisions + 1))
					return
				var before_round: int = int(game.current_round)
				var before_phase: String = str(game.current_phase)
				# Write only accepted actions. Every field comes from the player's
				# permission-filtered observation and legal action candidates.
				var _rt_t_step: int = Time.get_ticks_usec()
				var _rt_step_ok: bool = bridge.step(i, choice, str(decision.get("signature", "")))
				_rt_step_us += Time.get_ticks_usec() - _rt_t_step
				_rt_step_calls += 1
				if not _rt_step_ok:
					output_file.close()
					_fail("Rejected choice " + str(choice) + " for " + str(decision.get("type", "")))
					return
				decisions += 1
				_store(output_file, {
					"record_type": "transition",
					"seed": match_seed,
					"step": decisions,
					"player_index": i,
					"policy": "native_gdscript_policy_v4",
					"substep": str(decision.get("substep", "")),
					"round": before_round,
					"phase": before_phase,
					"request_type": str(decision.get("type", "")),
					"observation": observation,
					"legal_candidates": decision.get("candidates", []),
					"selected_candidate_id": choice
				})
				if decisions % FLUSH_EVERY == 0:
					var _rt_t_flush: int = Time.get_ticks_usec()
					output_file.flush()
					_rt_flush_us += Time.get_ticks_usec() - _rt_t_flush
				idle_frames = 0
				acted = true
				break
			if not acted:
				output_file.close()
				_fail("Waiting for a choice, but no human-seat bot has a decision (Avatar may need handling)")
				return
		else:
			idle_frames += 1
			if idle_frames > MAX_IDLE_FRAMES:
				output_file.close()
				_fail("Game idle for too many frames")
				return
		var _rt_waiting_for_player: bool = game.waiting_for_player_input
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

	if not game.game_has_ended:
		output_file.close()
		_fail("Decision cap reached: " + str(max_decisions))
		return

	var finished: Dictionary = bridge.result()
	var results: Dictionary = finished.get("result", {})
	var winner: int = int(results.get("winner", -1))
	var player_rewards: Array = []
	for i in range(human_count):
		player_rewards.append(1.0 if winner == i else -1.0)
	_store(output_file, {
		"record_type": "episode_end",
		"seed": match_seed,
		"scenario": scenario,
		"player_count": total_seats,
		"human_player_count": human_count,
		"avatar_id": actual_avatar_id,
		"decisions": decisions,
		"round": int(results.get("round", game.current_round)),
		"winner": winner,
		"scores": results.get("scores", []),
		"terminal_win_loss_rewards": player_rewards
	})
	output_file.close()
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
	print("AI_EPISODE_COMPLETE seed=", match_seed, " scenario=", scenario,
		" decisions=", decisions, " winner=", winner)
	print("AI_EPISODE_FILE ", output_path)
	quit(0)


func _store(target: FileAccess, entry: Dictionary) -> void:
	var _rt_t_store: int = Time.get_ticks_usec()
	target.store_line(JSON.stringify(entry))
	_rt_store_us += Time.get_ticks_usec() - _rt_t_store
	_rt_store_calls += 1


func _fail(message: String) -> void:
	printerr("AI_EPISODE_STOP: ", message)
	quit(1)


func _choose_from_python(session_dir: String, step_id: int, player_index: int,
	observation: Dictionary, decision: Dictionary) -> int:
	var suffix: String = "%06d" % step_id
	var request_path: String = session_dir.path_join("request_" + suffix + ".json")
	var response_path: String = session_dir.path_join("response_" + suffix + ".json")
	if FileAccess.file_exists(response_path):
		DirAccess.remove_absolute(response_path)
	var request_file: FileAccess = FileAccess.open(request_path, FileAccess.WRITE)
	if request_file == null:
		printerr("AI_IPC_ERROR: cannot write ", request_path)
		return -1
	request_file.store_string(JSON.stringify({"step": step_id, "player_index": player_index,
		"observation": observation, "decision": decision}))
	request_file.close()
	var deadline_ms: int = Time.get_ticks_msec() + RESPONSE_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline_ms:
		if FileAccess.file_exists(response_path):
			var raw_response: String = FileAccess.get_file_as_string(response_path)
			var value: Variant = JSON.parse_string(raw_response)
			if value is Dictionary and int(value.get("step", -1)) == step_id:
				var picked: int = int(value.get("choice_id", -1))
				DirAccess.remove_absolute(request_path)
				DirAccess.remove_absolute(response_path)
				return picked
		await process_frame
	printerr("AI_IPC_TIMEOUT: step ", step_id)
	return -1
