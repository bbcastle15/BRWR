extends SceneTree

var failures := 0
var clicked := ""
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	root.size = Vector2i(1920, 1080)
	var game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	game.enable_beta_hud = false
	root.add_child(game)
	for i in range(10):
		await process_frame
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	hud.setup(game)
	var cards: Array = []
	for i in range(8):
		cards.append({"id": "cross_and_delight", "name": "Cross and Delight", "hand_index": i})
	var request := {"type": "preparation", "player_index": 0, "hand": cards}
	game.request_player_input(request)
	hud.current_request = request
	var hand = hud.hand_overlay
	hand.open_preparation(request)
	for i in range(6):
		await process_frame
	check(hand.card_row.columns == 8, "Eight cards must occupy one row")
	var first = hand.card_row.get_child(0)
	var last = hand.card_row.get_child(7)
	check(absf(first.global_position.y - last.global_position.y) < 1, "All cards must share a row")
	check(hand.card_scroll.get_h_scroll_bar().visible, "Cards beyond six must be accessible by horizontal scrolling")
	first.get_meta("card_button").pressed.emit()
	check(hand.selected_hand_index == 0, "Click must safely rebuild cards during signal emission")
	hand.ready_hand_indices.assign([0])
	hand.ready_dark_sides.assign([false])
	hand.close_overlay()
	check(not hand.visible, "Preparation must be hideable")
	hud._open_hand_overlay()
	check(hand.visible and hand.ready_hand_indices == [0], "Reopening must preserve draft")
	hand.close_overlay(true)
	game.clear_player_input()
	var room = game.get_room_by_id(game.player_entrance_room_ids[0])
	room.add_instability_cube(1)
	room.add_instability_cube(1)
	check(game.show_board_target_choice({"token": "instability:1:1", "cube_room_id": room.room_id}, func(): clicked = "cube"), "Second same-owner cube must map to physical cube")
	var button = room.instability_cube_nodes[1].get_child(room.instability_cube_nodes[1].get_child_count()-1)
	button.pressed.emit()
	await process_frame
	check(clicked == "cube", "Cube click must execute deferred choice")
	game.clear_board_target_choices()
	var evocation = game.summon_evocation(1, "nigredo", room.room_id)
	game.refresh_model_tokens()
	check(game.show_board_target_choice({"token": "evocation:1:0", "owner_id": 1, "evocation_index": 0}, func(): clicked = "evocation"), "Evocation target must be clickable")
	game.clear_board_target_choices()
	for player in game.players:
		player.quick_spell = ReadySpellState.new(game.spell_database.spells["cross_and_delight"], false)
	game.players[1].mage.in_cell = false
	game.players[1].mage.room_id = room.room_id
	game.players[1].mage.damage_cubes.assign([1, -1, 1])
	var conversion_context := {"game": game, "caster_id": 0, "spell_target_type": "mage", "target_model_type": "mage", "target_player_index": 1}
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "effects": [{"type": "convert_damage", "amount": 1}], "context": conversion_context})
	check(game.pending_input.get("choice_kind") == "convert_damage_cubes", "Conversion must let the caster choose cubes")
	check(game.submit_effect_choice(0, ["damage:-1:0"]), "Choose Black Rose damage rather than first player cube")
	check(game.players[1].mage.damage_cubes == [1, 0, 1], "Only selected damage owner must convert")
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "effects": [{"type": "heal", "amount": 2}], "context": conversion_context})
	check(game.pending_input.get("choice_kind") == "heal_damage", "Healing must offer physical cubes")
	check(game.submit_effect_choice(0, ["damage:1:1"]), "Select just one cube to heal")
	check(game.players[1].mage.damage_cubes == [0, 1], "Healing must remove only the selected number of cubes")
	check(game.resolution_stack.is_empty(), "Cube choices must resume resolution")
	evocation.damage_cubes.assign([1, -1])
	var evocation_context := {"game": game, "caster_id": 0, "spell_target_type": "evocation", "target_model_type": "evocation", "target_evocation": evocation}
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "effects": [{"type": "convert_damage", "amount": 1}], "context": evocation_context})
	for option in game.pending_input.options:
		check(game.show_board_target_choice(option, func(): pass), "Evocation damage cube must be selectable")
	game.clear_board_target_choices()
	for option in game.pending_input.options:
		check(game.show_board_target_choice(option, func(): pass), "Repeated cube rendering must not reuse freed visuals")
	check(game.submit_effect_choice(0, ["damage:-1:0"]), "Convert Evocation damage")
	check(evocation.damage_cubes == [1, 0], "Evocation conversion respects selected owner")
	game.active_events = [game.event_database.events["tribute_of_the_command"]]
	check(game.resolve_action_phase(), "Tribute must start without unsupported Event failure")
	var first_player: int = game.pending_input.player_index
	var damage_before: int = game.players[first_player].mage.damage_cubes.size()
	check(game.submit_effect_choice(first_player, ["accept"]), "Accept Tribute")
	check(game.players[first_player].mage.damage_cubes.size() == damage_before + 1, "Tribute must apply damage once")
	check(game.pending_input.choice_kind == "target_evocation", "Tribute must request the Evocation")
	check(game.submit_effect_choice(first_player, [game.pending_input.options[0].token]), "Choose Evocation")
	check(game.pending_input.choice_kind == "evocation_activation_plan", "Tribute must activate before next Mage decides")
	var plan_token := ""
	for option in game.pending_input.options:
		var plan: Dictionary = game.pending_effect_choice_values[option.token]
		if plan.get("evocation_attack_timing") == "none":
			plan_token = option.token
			break
	check(game.submit_effect_choice(first_player, [plan_token]), "Activation must finish")
	check(game.pending_input.choice_kind == "event_tribute" and game.pending_input.player_index != first_player, "Next Mage decides only after activation")
	check(game.submit_effect_choice(game.pending_input.player_index, ["decline"]), "Decline Tribute")
	check(game.pending_input.get("type") == "action_activation_step", "Action phase resumes after Event")
	check(game.players[first_player].mage.damage_cubes.size() == damage_before + 1, "Resuming must not repeat damage")
	print("HAND / TARGETS / TRIBUTE: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)

