extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func choose_room(game, room_id: String) -> void:
	for option in game.pending_input.get("options", []):
		if option.get("room_id") == room_id:
			game.submit_effect_choice(int(game.pending_input.player_index), [option.token])
			return
	check(false, "Missing room option: " + room_id)

func run() -> void:
	root.size = Vector2i(1770, 919)
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	await process_frame
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	game.beta_hud = hud
	hud.setup(game)
	var player = game.players[0]
	player.mage.in_cell = false
	player.mage.room_id = "forge"
	player.mage.room_coord = game.room_id_to_coord("forge")
	var spell = game.spell_database.spells.soul_transfer
	check(spell.light_side.target == "special", "Soul Transfer Light has a Special target")
	var construct = game.summon_evocation(1, "nigredo", "forge")
	var far_room := ""
	for room_id in game.room_id_by_coord.values():
		if game.get_hex_distance(game.room_id_to_coord("forge"), game.room_id_to_coord(room_id)) > 2:
			far_room = room_id
			break
	player.mage.room_id = far_room
	player.mage.room_coord = game.room_id_to_coord(far_room)
	player.quick_spell = ReadySpellState.new(spell, false)
	game._sync_player_board_prepared_spells(0)
	game._start_stepwise_action_activation(0)
	check(game.get_player_board_cast_token(0, "Q") != "", "Special Quick must be castable, including via another player's Construct")
	game.activate_player_board_spell(0, "Q")
	check(player.quick_spell == null, "Quick Soul Transfer must commit")
	check(game.pending_input.get("choice_kind") == "construct_room", "Soul Transfer explicitly asks which Construct Room to activate")
	choose_room(game, "forge")
	check(game.pending_input.get("choice_kind") == "room_effect_room_target", "Soul Transfer must reach Forge's effect")
	check(not game.pending_input.options.is_empty(), "Forge must offer target rooms")
	for option in game.pending_input.get("options", []):
		check(game.get_hex_distance(game.room_id_to_coord("forge"), game.room_id_to_coord(option.room_id)) <= 1, "Forge offered out-of-range room")
	check(get_nodes_in_group("lodge_room_choices").size() > 0, "Room target choices must highlight the Lodge")
	var forge = game.get_room_by_id("forge")
	var cubes: int = forge.get_instability_count()
	choose_room(game, "forge")
	check(forge.get_instability_count() == cubes + 1, "Forge must actually place a cube using Construct origin")
	game.clear_player_input()
	game._reset_stepwise_action_activation()
	game.finalize_evocation_removal(construct)
	player.mage.room_id = "forge"
	player.mage.room_coord = game.room_id_to_coord("forge")
	var redirect_recipient = game.summon_evocation(0, "nigredo", "forge")
	player.quick_spell = ReadySpellState.new(game.spell_database.spells.pain_mark, true)
	game.cast_quick_spell(0)
	check(not game.waiting_for_player_input, "Pain Mark Dark must not ask for another Mage")
	check(player.active_spells.size() == 1, "Pain Mark must register ongoing self effect")
	player.active_spells.clear()
	game.finalize_evocation_removal(redirect_recipient)
	var target: String = game._beta_adjacent_room_ids("forge")[0]
	var enemy := EvocationState.new("test", "Durable", "beast", 8, 1, 1, 1)
	enemy.room_id = target
	game.players[1].add_evocation(enemy)
	game.players[1].mage.in_cell = false
	game.players[1].mage.room_id = target
	game.players[1].mage.room_coord = game.room_id_to_coord(target)
	var hp: int = player.mage.get_remaining_health()
	player.quick_spell = ReadySpellState.new(game.spell_database.spells.cube_of_lamentations, false)
	game.cast_quick_spell(0)
	check(game.pending_input.get("choice_kind") == "spell_target", "Cube must request its Area")
	check(game.pending_input.options.all(func(o): return o.get("target_type") == "room"), "Cube must offer Rooms, never individual Models")
	choose_room(game, target)
	check(enemy.get_damage() == 2 and game.players[1].mage.get_damage() == 2, "Cube must damage every opposing Model in the room")
	check(player.evocations.any(func(e): return e.evocation_id == "succubus" and e.room_id == target), "Cube must summon after inflicting damage")
	check(player.mage.get_remaining_health() == hp - 2, "Cube must resolve Pain after summoning")
	check(game.resolution_stack.is_empty(), "Cube resolution must finish")
	game.deal_damage(1, 0, player.mage.get_remaining_health() - 2)
	player.quick_spell = ReadySpellState.new(game.spell_database.spells.cube_of_lamentations, false)
	game.cast_quick_spell(0, {"target_room_id": target})
	check(player.mage.in_cell, "Cube's Pain must defeat a caster with two HP")
	check(game.pending_input.get("choice_kind") == "evocation_activation_plan", "Cube must activate the summoned Succubus after Black Rose defeat")
	if game.pending_input.get("choice_kind") == "evocation_activation_plan":
		var token := ""
		for option in game.pending_input.options:
			var plan: Dictionary = game.pending_effect_choice_values[option.token]
			if plan.get("evocation_attack_timing") == "none" and plan.get("evocation_move_room_ids", []).is_empty():
				token = option.token
				break
		game.submit_effect_choice(0, [token])
	check(game.resolution_stack.is_empty(), "Defeat-triggered Cube activation must complete")
	check(VisualAssets.load_spell_texture("emet_met") != null and SpellArtResolver.get_texture("emet_met") != null, "Emet-Met must load through both render paths")
	check(hud.hand_overlay._resolve_card_texture({"id": "emet_met"}) != null, "Emet-Met must load in Hand")
	game.request_player_input({"player_index": 0, "type": "study_keep_cards", "cards": [
		{"draw_index": 0, "id": "emet_met", "name": "Emet-Met"},
		{"draw_index": 1, "id": "soul_transfer", "name": "Soul Transfer"},
		{"draw_index": 2, "id": "pain_mark", "name": "Pain Mark"},
		{"draw_index": 3, "id": "cube_of_lamentations", "name": "Cube of Lamentations"}]})
	check(hud.hand_overlay.visible and hud.hand_overlay.card_row.get_child_count() == 4, "Study must show four actual card widgets")
	hud.hand_overlay._select_card(0)
	hud.hand_overlay._select_card(2)
	hud.hand_overlay._select_card(3)
	check(hud.hand_overlay.study_selection == [0, 2], "Study can select exactly two card instances")
	hud._toggle_panel()
	hud._toggle_panel()
	check(hud.hand_overlay.visible and hud.hand_overlay.study_selection == [0, 2], "Hiding Study must preserve choices")
	game.clear_player_input()
	check(not hud.hand_overlay.visible, "Handoff must hide Study's private cards")
	for count in [1, 2, 3, 6, 12, 24]:
		for offset in game._model_token_offsets(count):
			check(absf(offset.y) <= 24, "Models must stay away from room title/effect and instability track")
	game.queue_free()
	await process_frame
	for count in range(2, 7):
		var table = load("res://game.tscn").instantiate()
		table.player_count = count
		table.enable_beta_hud = false
		table.auto_start_game_flow = false
		table.game_seed = 1232
		root.add_child(table)
		await process_frame
		table.update_table_layout()
		var central: Rect2 = table.get_lodge_table_bounds()
		for cell in table.get_children():
			if cell.has_meta("owner_index"):
				check(cell.get_node("OwnerBorder").default_color == table.players[cell.get_meta("owner_index")].color, "Cell border must match its actual player")
		for board in table.player_boards:
			check(not board.visible, "Personal boards stay off the shared table for %d players" % count)
		table.queue_free()
		await process_frame
	print("PLAYTEST REGRESSIONS: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
