# EXPERIMENTAL: baseline-vs-baseline offline match, without the visual HUD.
# Run: godot --headless --path . --script res://ai/ai_baseline_match.gd
# This is a diagnostic run, not reinforcement-learning training.
extends SceneTree

const Bridge = preload("res://ai/ai_bridge.gd")
const Baseline = preload("res://ai/ai_baseline_policy.gd")
const MAX_DECISIONS := 1200
const MAX_IDLE_FRAMES := 2000

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://game.tscn")
	if packed == null:
		_fail("game.tscn missing")
		return
	var game: Variant = packed.instantiate()
	game.auto_start_game_flow = false
	game.run_tests_on_ready = false
	game.enable_beta_hud = false
	game.player_count = 2
	var args := OS.get_cmdline_user_args()
	var match_seed := 20261107

	if not args.is_empty():
		match_seed = int(args[0])

	game.game_seed = match_seed
	print("AI_MATCH_SEED=", match_seed)
	root.add_child(game)
	for n in range(20):
		await process_frame
	if game.players.size() != 2:
		_fail("Game not initialized")
		return
	var bridge = Bridge.new(game)
	var bots: Array = [
		Baseline.new(match_seed * 2 + 1, "aggressive"),
		Baseline.new(match_seed * 2 + 2, "balanced")
	]
	if not game.start_game_flow():
		_fail("Failed to start game flow")
		return

	var decisions := 0
	var idle_frames := 0
	while decisions < MAX_DECISIONS and not game.game_has_ended:
		if game.waiting_for_player_input:
			var acted := false
			for i in range(game.players.size()):
				var d: Dictionary = bridge.decision(i)
				if d.is_empty():
					continue
				if not bool(d.get("supported", false)):
					_fail("Unsupported input type " + str(d.get("type", "")) + " for bot " + str(i))
					return
				var obs: Dictionary = bridge.observation(i)
				var choice: int = bots[i].choose(obs, d)
				if not bridge.step(i, choice, str(d.get("signature", ""))):
					_fail("Rejected choice in " + str(d.get("type", "")) + " for bot " + str(i))
					return
				decisions += 1
				idle_frames = 0
				acted = true
				print("AI_DECISION ", decisions, " player=", i, " type=", d.get("type", ""), " choice=", choice)
				break
			if not acted:
				_fail("Input is pending but no bot has a private decision")
				return
		else:
			idle_frames += 1
			if idle_frames > MAX_IDLE_FRAMES:
				_fail("Game stalled without pending input")
				return
		await process_frame

	if game.game_has_ended:
		print("AI_MATCH_COMPLETE decisions=", decisions, " result=", JSON.stringify(bridge.result()))
		quit(0)
	else:
		printerr("AI_MATCH_INCOMPLETE: decision cap ", MAX_DECISIONS, " reached")
		quit(2)


func _fail(message: String) -> void:
	printerr("AI_MATCH_STOP: ", message)
	quit(1)
