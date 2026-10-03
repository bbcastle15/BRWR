extends SceneTree

var failures := 0
var clicked := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(1600, 900)
	var game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.enable_beta_hud = false
	game.beta_force_fullscreen = false
	root.add_child(game)
	for i in range(10):
		await process_frame
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	hud.setup(game)
	game.local_viewer_index = 0
	hud.current_player_index = 0
	var spell = game.spell_database.spells["ineluctable_pain"]
	var copy := SpellCardState.new(spell.id, spell.card_name, spell.school_id, spell.light_side, spell.dark_side)
	game._set_player_board_spell_slot(0, "I", spell, false, "prepared")
	game._set_player_board_spell_slot(0, "II", copy, false, "prepared")
	game.request_effect_choice(0, "test", {}, "selected", [{"token": "copy", "value": copy}])
	var option: Dictionary = game.pending_input.options[0]
	check(option.slot_id == "II", "Physical instance, not card ID, determines the slot")
	check(not option.has("value"), "Requests must contain public addresses, never runtime references")
	check(game.show_board_target_choice(option, func(): clicked = true), "Owner can select prepared card")
	var targets = get_nodes_in_group("board_target_choices")
	check(targets[-1].get_parent().name == "SpellSlotII", "Choice overlay must attach to actual slot II")
	targets[-1].pressed.emit()
	await process_frame
	check(clicked, "Board choice invokes deferred callback")
	game.clear_board_target_choices()
	game.local_viewer_index = 1
	check(not game.show_board_target_choice(option, func(): pass), "Hidden opponent card cannot be selected")
	game.local_viewer_index = 0
	game.clear_player_input()
	var quest := QuestState.new(game.quest_database.quests.values()[0], 0)
	game.players[0].active_quests.append(quest)
	game.player_boards[0].refresh_quests()
	game.request_effect_choice(0, "test", {}, "selected", [{"token": "quest", "value": quest}])
	check(game.show_board_target_choice(game.pending_input.options[0], func(): pass), "Hidden own Quest maps to its physical card")
	game.clear_player_input()
	hud.current_request = {"type": "study_optional_discard", "player_index": 0, "hand": [{"id": spell.id, "hand_index": 0}, {"id": spell.id, "hand_index": 1}]}
	hud._render_current_request()
	var row = hud.content.get_node("ObjectChoices").get_child(0)
	check(row.get_child_count() == 2, "Duplicate hand cards remain separate choices")
	check(row.get_child(1).get_meta("choice_option").hand_index == 1, "Gallery retains hand index")
	check(row.get_child(0).get_child(0).texture != null, "Spell choice displays actual card image")
	hud.current_request = {"type": "effect_choice", "options": [{"token": "destination", "room_id": game.player_entrance_room_ids[0]}]}
	hud._render_current_request()
	check(get_nodes_in_group("lodge_room_choices").size() > 0, "Room choices work without a room token prefix")
	hud._clear_content()
	check(hud.content.get_child_count() == 0, "Rebuild immediately detaches old choice controls")
	game.clear_player_input()
	quest.completed = true
	game.players[0].active_quests.erase(quest)
	game.players[0].completed_quests.append(quest)
	game.player_boards[0].refresh_quests()
	game.request_effect_choice(0, "test", {}, "selected", [{"token": "completed", "value": quest}])
	check(game.pending_input.options[0].quest_section == "completed", "Completed Quest uses the right-hand strip")
	check(game.show_board_target_choice(game.pending_input.options[0], func(): pass), "Completed Quest choice maps to the existing card")
	game.clear_player_input()
	hud.current_request = {"type": "cleanup_active_spells", "active_spells": [{"active_index": 0, "spell_id": copy.id, "board_player_index": 0, "slot_id": "II"}]}
	hud._render_current_request()
	var overlays = get_nodes_in_group("board_target_choices").filter(func(n): return not n.is_queued_for_deletion())
	check(overlays.size() == 1, "Cleanup chooses the actual armed slot")
	overlays[0].pressed.emit()
	await process_frame
	check(hud.generic_selection == [0], "Cleanup toggles the authoritative request index")
	check(hud.content.get_node_or_null("ObjectChoices") == null, "Board choices do not duplicate cards in a gallery")
	game.queue_free()
	await process_frame
	print("OBJECT CHOICES: ", "PASS" if failures == 0 else "FAIL " + str(failures))
	quit(0 if failures == 0 else 1)
