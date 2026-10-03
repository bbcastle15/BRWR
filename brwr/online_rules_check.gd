extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func choose_conversion(game) -> void:
	# Damage selection pauses resolution independently for each affected model.
	for i in range(2):
		if game.pending_input.get("choice_kind") != "convert_damage_cubes":
			return
		var tokens: Array = []
		for option in game.pending_input.options.slice(0, int(game.pending_input.max_select)):
			tokens.append(option.token)
		assert(game.submit_effect_choice(0, tokens))

func run() -> void:
	create_timer(20).timeout.connect(func(): push_error("Online rules check timed out"); quit(1))
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(8): await process_frame
	for player in game.players:
		player.mage.in_cell = false
		player.mage.room_id = "forge"
		player.mage.room_coord = game.room_id_to_coord("forge")
	var own = game.summon_evocation(0, "nigredo", "forge")
	var enemy = game.summon_evocation(1, "nigredo", "forge")
	assert(game.deal_damage_to_evocation(0, own, 1) == 0)
	assert(own.get_damage() == 0)
	game.players[0].mage.damage_cubes.assign([-1, -1])
	game.players[1].mage.damage_cubes.assign([-1, -1, -1, -1])
	own.damage_cubes.assign([-1])
	enemy.health = 8
	enemy.damage_cubes.assign([-1, -1, -1, -1])
	game.players[0].quick_spell = ReadySpellState.new(game.spell_database.get_spell("albify"), true)
	assert(game.cast_quick_spell(0))
	assert(game.waiting_for_player_input)
	for option in game.pending_input.options:
		if option.get("room_id") == "forge":
			assert(game.submit_effect_choice(0, [option.token]))
			break
	choose_conversion(game)
	assert(game.players[1].mage.damage_cubes.count(0) == 3, "Albify Dark must convert three damage on the opposing Mage")
	assert(enemy.damage_cubes.count(0) == 3, "Albify Dark must convert three on each opposing Evocation")
	assert(game.players[0].mage.damage_cubes == [-1, -1])
	assert(own.damage_cubes == [-1])
	game.players[0].revealed_spells.append(RevealedSpellState.new(game.spell_database.get_spell("athanor_eruption"), false))
	game.players[1].mage.damage_cubes.assign([-1, -1, -1, -1])
	enemy.damage_cubes.assign([-1, -1, -1, -1])
	game.players[0].quick_spell = ReadySpellState.new(game.spell_database.get_spell("albify"), true)
	assert(game.cast_quick_spell(0, {"target_room_id": "forge"}))
	choose_conversion(game)
	assert(game.players[1].mage.damage_cubes.count(0) == 4, "Albify Enhancement plus three converted cubes")
	assert(enemy.damage_cubes.count(0) == 4)
	var state: Dictionary = load("res://network_projection.gd").build(game, 1)
	assert(not state.players[0].has("hand"))
	assert(not state.players[0].has("ready_spells"))
	assert(not state.players[0].has("active_spells"))
	var replica = load("res://game.tscn").instantiate()
	replica.network_client = true
	replica.local_viewer_index = 1
	replica.enable_beta_hud = false
	replica.auto_start_game_flow = false
	root.add_child(replica)
	for i in range(8): await process_frame
	load("res://network_projection.gd").apply(replica, state)
	assert(replica.players[0].hand.all(func(card): return card == null))
	assert(replica.players[1].mage.damage_cubes == game.players[1].mage.damage_cubes)
	var camera = load("res://table_camera.gd").new()
	game.add_child(camera)
	camera.zoom_at(Vector2.ZERO, 0.001)
	assert(is_equal_approx(camera.zoom.x, camera.minimum_zoom()))
	print("ONLINE RULES / PROJECTION / ZOOM CHECK PASS")
	quit()
