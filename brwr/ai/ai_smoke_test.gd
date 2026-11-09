# Run from the Godot project folder:
# godot --headless --path . --script res://ai/ai_smoke_test.gd
extends SceneTree

const Bridge = preload("res://ai/ai_bridge.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_scene: PackedScene = load("res://game.tscn")
	if game_scene == null:
		_fail("Missing game.tscn")
		return
	var game: Variant = game_scene.instantiate()
	game.run_tests_on_ready = false
	game.auto_start_game_flow = false
	game.enable_beta_hud = false
	game.game_seed = 20261107
	game.player_count = 2
	root.add_child(game)
	for i in range(20):
		await process_frame
	if game.players.size() != 2:
		_fail("Game setup did not initialize 2 players")
		return
	var bridge = Bridge.new(game)
	# Privacy regression: a physically present owner Hand card must NOT be
	# available to the other bot through NetworkProjection.
	var spell = game.spell_database.spells.values()[0]
	game.players[0].hand.append(spell)
	var owner: Dictionary = bridge.observation(0)
	var opponent: Dictionary = bridge.observation(1)
	if not owner.get("players", [])[0].has("hand"):
		_fail("Owner cannot see own Hand")
		return
	if opponent.get("players", [])[0].has("hand"):
		_fail("PRIVACY BREACH: opponent can see Hand")
		return
	if opponent.get("players", [])[0].has("ready_spells"):
		_fail("PRIVACY BREACH: opponent can see prepared cards")
		return
	game.players[0].hand.clear()

	if not game.start_game_flow():
		_fail("start_game_flow failed")
		return
	if not game.waiting_for_player_input:
		_fail("Setup did not request input")
		return
	var actor: int = int(game.pending_input.get("player_index", -1))
	var turn: Dictionary = bridge.decision(actor)
	if str(turn.get("type", "")) != "starting_mage_choice":
		_fail("Expected starting_mage_choice")
		return
	if turn.get("candidates", []).is_empty():
		_fail("No legal starting Mages")
		return
	var signature := str(turn.get("signature", ""))
	if bridge.step(actor, -1, signature):
		_fail("Invalid choice was accepted")
		return
	if bridge.step(1 - actor, 0, signature):
		_fail("Other player was allowed to answer")
		return
	if bridge.step(actor, 0, "stale-signature"):
		_fail("Stale choice was accepted")
		return
	if not bridge.step(actor, 0, signature):
		_fail("Legal Mage choice was rejected")
		return
	if bridge.step(actor, 0, signature):
		_fail("Old choice was accepted twice")
		return
	print("AI_SMOKE_TEST_PASS: privacy, legal choice, actor, and stale-request checks")
	quit(0)


func _fail(message: String) -> void:
	printerr("AI_SMOKE_TEST_FAIL: ", message)
	quit(1)
