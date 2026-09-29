extends SceneTree

# Godot --headless --path . --script res://room_damage_playtest.gd
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	for i in range(10):
		await process_frame
	var enemy := EvocationState.new("enemy", "Enemy", "beast", 5, 1, 1, 1)
	var ally := EvocationState.new("ally", "Ally", "beast", 5, 1, 1, 0)
	enemy.room_id = game.player_entrance_room_ids[0]
	ally.room_id = enemy.room_id
	game.players[1].evocations.append(enemy)
	game.players[0].evocations.append(ally)
	var pool_before: int = game.players[0].available_cubes
	var context: Dictionary = {"game": game, "player_index": 0, "target_room_id": enemy.room_id}
	var resolved: bool = game.room_effect_resolver.resolve_effect(
		{"type": "damage", "target": "room", "amount": 1}, context
	)
	var passed: bool = resolved and enemy.get_damage() == 1 and ally.get_damage() == 0
	passed = passed and game.players[0].available_cubes == pool_before - 1
	# Dictionary/JSON-derived arrays and typed callers must both be supported.
	var untyped: Array = ["trap", "protection"]
	var typed: Array[String] = ["trap"]
	game.processing_resolution_stack = true
	game.deal_damage_to_evocation(0, enemy, 1, untyped)
	var stored: Array = game.resolution_stack[0].suppressed_trigger_types
	passed = passed and stored.is_typed() and stored == untyped
	untyped.clear()
	passed = passed and stored.size() == 2
	game.deal_damage_to_evocation(0, enemy, 1, typed)
	game.processing_resolution_stack = false
	game.process_resolution_stack()
	passed = passed and enemy.get_damage() == 3
	print("ROOM DAMAGE PLAYTEST: ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
