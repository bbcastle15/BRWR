# BRWR AI v4 - live PyTorch self-play Godot worker.
# Run with ai/python/train.py; do not execute standalone without a Python policy.
# No changes to Game rules. All choices are validated through ai_bridge.gd.
extends SceneTree

const Bridge = preload("res://ai/ai_bridge.gd")
const NativePolicy = preload("res://ai/ai_native_policy_prefix_v4.gd")
const MAX_DECISIONS_PER_HUMAN := 1200
const MAX_IDLE_FRAMES := 2000
const FLUSH_EVERY := 25
const RESPONSE_TIMEOUT_MS := 120000

var _brwr_batch_scene: PackedScene = null
var _brwr_batch_policy: Variant = null

func _run_batch() -> void:
	var cli_args: PackedStringArray = OS.get_cmdline_user_args()
	if cli_args.size() != 1:
		_fail("Usage: -- res://ai/persistent_batch_<id>.json")
		return
	var manifest_path: String = cli_args[0]
	if not FileAccess.file_exists(manifest_path):
		_fail("Persistent manifest missing: " + manifest_path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		_fail("Invalid persistent manifest JSON")
		return
	var entries: Variant = parsed.get("episodes", [])
	if not entries is Array or entries.size() == 0 or entries.size() > 128:
		_fail("Persistent manifest must contain 1..128 episodes")
		return

	_brwr_batch_scene = load("res://ai/game_school_cached.tscn")
	if _brwr_batch_scene == null:
		_fail("Cannot load cached AI scene")
		return
	_brwr_batch_policy = NativePolicy.new()
	if not _brwr_batch_policy.load_model("res://ai/model/native_policy_v4.json"):
		_fail("Cannot load prefix policy model")
		return
	print("BRWR_PERSISTENT_BATCH_START episodes=", entries.size())
	for i in range(entries.size()):
		var episode: Variant = entries[i]
		if not episode is Dictionary:
			_fail("Malformed episode manifest entry " + str(i))
			return
		for required_key in ["seed", "bots", "avatar"]:
			if not episode.has(required_key):
				_fail("Missing " + required_key + " in manifest entry " + str(i))
				return
		# Godot JSON.parse_string can decode JSON numeric literals as float.
		# CLI arguments are strings and the episode parser requires valid integers.
		# Cast BOTH seed and bots: otherwise "20270491.0" or "4.0" is rejected.
		var episode_seed: int = int(episode["seed"])
		var episode_bots: int = int(episode["bots"])
		if float(episode_seed) != float(episode["seed"]) or float(episode_bots) != float(episode["bots"]):
			_fail("Persistent manifest requires integral seed and bots at index " + str(i))
			return
		var episode_args := PackedStringArray([
			str(episode_seed), str(episode_bots), str(episode["avatar"]),
			str(episode.get("difficulty", "apprentice")), str(episode.get("mode", "normal"))
		])
		var start_us: int = Time.get_ticks_usec()
		var completed: bool = await _run_episode(episode_args)
		if not completed:
			_fail("Persistent batch episode failed: " + str(episode_seed))
			return
		var duration_ms: float = float(Time.get_ticks_usec() - start_us) / 1000.0
		print("BRWR_PERSISTENT_EPISODE_OK index=", i + 1, " seed=", episode_seed, " wall_ms=", snappedf(duration_ms, 0.001))
	print("BRWR_PERSISTENT_BATCH_COMPLETE episodes=", entries.size())
	quit(0)


func _initialize() -> void:
	call_deferred("_run_batch")


func _run_episode(episode_args: PackedStringArray) -> bool:
	var args: PackedStringArray = episode_args
	var match_seed: int = 20261108
	if args.size() >= 1:
		if not args[0].is_valid_int():
			_fail("Invalid seed: " + args[0])
			return false
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
			return false
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
		return false
	var use_avatar: bool = avatar_id != "none"
	var total_seats: int = human_count + (1 if use_avatar else 0)
	if human_count < 2 or total_seats > 6:
		_fail("Invalid AI training setup: %d Mage bots + %d Avatar; requires 2..6 Mage bots and at most 6 seats total" % [human_count, 1 if use_avatar else 0])
		return false

	var packed: PackedScene = _brwr_batch_scene
	if packed == null:
		_fail("Missing game.tscn")
		return false
	var game: Variant = packed.instantiate()
	game.auto_start_game_flow = false
	game.run_tests_on_ready = false # Normal mage -> school -> grimoire choice order.
	game.enable_beta_hud = false
	game.player_count = total_seats
	game.game_seed = match_seed
	if use_avatar:
		game.avatar_selection = {"id": avatar_id, "difficulty": avatar_difficulty}
	var _brwr_children_before: int = root.get_child_count()
	root.add_child(game)
	for _n in range(20):
		await process_frame
	if game.players.size() != total_seats:
		_fail("Game initialization failed")
		return false
	if use_avatar and (game.avatar == null or int(game.avatar.player_index) != total_seats - 1):
		_fail("Avatar was requested but was not initialized in the last seat")
		return false
	if not use_avatar and game.avatar != null:
		_fail("Avatar initialized in a normal match")
		return false
	var actual_avatar_id: String = str(game.avatar.definition.get("id", "")) if game.avatar != null else "none"

	var session_dir: String = ProjectSettings.globalize_path("res://ai/runtime")
	var session_error: Error = DirAccess.make_dir_recursive_absolute(session_dir)
	if session_error != OK:
		_fail("Cannot create IPC directory: " + session_dir)
		return false
	var output_dir: String = ProjectSettings.globalize_path("res://ai/datasets")
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	if mkdir_error != OK:
		_fail("Cannot create dataset folder: " + output_dir + " (" + str(mkdir_error) + ")")
		return false
	var mode: String = "swap" if swap_styles else "normal"
	var scenario: String = "h%d_av%s_%s_%s" % [human_count, actual_avatar_id, avatar_difficulty if use_avatar else "na", mode]
	var output_path: String = output_dir.path_join("batch_prefix_episode_%d_%s.jsonl" % [match_seed, scenario])
	var output_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		_fail("Cannot write " + output_path + " (" + str(FileAccess.get_open_error()) + ")")
		return false

	# All Mage seats share the same trainable Python policy. Avatar stays native.
	var policy = _brwr_batch_policy
	policy.set_seed(match_seed + 812341)
	var bridge = Bridge.new(game)
	if not game.start_game_flow():
		output_file.close()
		_fail("start_game_flow() failed")
		return false

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
				var decision: Dictionary = bridge.decision(i)
				if decision.is_empty():
					continue
				if not bool(decision.get("supported", false)):
					output_file.close()
					_fail("Unsupported request " + str(decision.get("type", "")))
					return false
				var observation: Dictionary = bridge.observation(i)
				var choice: int = policy.choose(observation, decision)
				if choice < 0:
					output_file.close()
					_fail("Native policy failed to choose for decision " + str(decisions + 1))
					return false
				var before_round: int = int(game.current_round)
				var before_phase: String = str(game.current_phase)
				# Write only accepted actions. Every field comes from the player's
				# permission-filtered observation and legal action candidates.
				if not bridge.step(i, choice, str(decision.get("signature", ""))):
					output_file.close()
					_fail("Rejected choice " + str(choice) + " for " + str(decision.get("type", "")))
					return false
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
					output_file.flush()
				idle_frames = 0
				acted = true
				break
			if not acted:
				output_file.close()
				_fail("Waiting for a choice, but no human-seat bot has a decision (Avatar may need handling)")
				return false
		else:
			idle_frames += 1
			if idle_frames > MAX_IDLE_FRAMES:
				output_file.close()
				_fail("Game idle for too many frames")
				return false
		await process_frame

	if not game.game_has_ended:
		output_file.close()
		_fail("Decision cap reached: " + str(max_decisions))
		return false

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
	print("AI_EPISODE_COMPLETE seed=", match_seed, " scenario=", scenario,
		" decisions=", decisions, " winner=", winner)
	print("AI_EPISODE_FILE ", output_path)
	# Finish queued scene changes before starting the next independent match.
	game.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(game):
		_fail("Persistent worker: old Game instance survived queue_free")
		return false
	if root.get_child_count() != _brwr_children_before:
		_fail("Persistent worker: leaked root nodes; before=%d after=%d" % [_brwr_children_before, root.get_child_count()])
		return false
	return true


func _store(target: FileAccess, entry: Dictionary) -> void:
	target.store_line(JSON.stringify(entry))


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
