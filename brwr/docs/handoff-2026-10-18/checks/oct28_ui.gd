extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func run():
	root.size = Vector2i(1296, 589)
	game = await create_game()
	reset_case()
	var hud = game.beta_hud
	hud.set_process(false)
	hud._on_player_input_requested({"type":"study_choose_schools","player_index":0,"active_school_ids":["death","chaos","druidic","agony","forge","lex"]})
	for i in 12: await process_frame
	var row = hud.content.get_node("StudyRow")
	expect(row.get_child(1) is VBoxContainer and row.get_child(1).get_child_count() == 3, "Study controls on right")
	var inspect = row.get_child(0).get_child(0).get_child(0).get_node("InspectSchool")
	expect(inspect.get_global_rect().end.y < hud.content.get_parent().get_global_rect().end.y, "Inspect fits short Web canvas")
	expect(hud.content.get_parent().get_v_scroll_bar().max_value <= hud.content.get_parent().get_v_scroll_bar().page, "No vertical Study scrolling")
	await capture("oct28-study-web")
	hud.current_request = {"cards":[{"draw_index":0,"name":"Keep me"},{"draw_index":1,"name":"Discard me"}]}
	hud._confirm_study_keep([0])
	expect(hud.choice_confirmation.dialog_text.contains("Keep me") and not hud.choice_confirmation.dialog_text.contains("Discard me"), "Study confirmation lists kept cards")
	hud.choice_confirmation.hide()
	var frame = preload("res://tabletop_style.gd").spell_side_frame()
	expect(not frame.get_theme_stylebox("panel").draw_center and frame.get_theme_stylebox("panel").shadow_size == 0, "Neon border has no central fill or filled shadow")
	frame.free()
	for room_id in ["arena","black_rose","forge"]:
		var room = game.get_room_by_id(room_id)
		var slots = room.get_art_instability_slots()
		var middle = slots[slots.size()/2]
		expect(is_zero_approx(room.get_art_instability_slot_rotation(middle)), room_id + " bottom cubes upright")
		if slots.size() > 5:
			expect(is_equal_approx(room.get_art_instability_slot_rotation(slots[0]), deg_to_rad(-30)), room_id + " left edge cubes tilted")
	var description = preload("res://effect_description.gd").describe({"type":"room_effect","effects":[{"type":"convert_instability","amount":1}]})
	expect(description.begins_with("Convert 1"), "Room target prompt describes nested conversion")
	for effect_type in ["convert_instability", "place_instability"]:
		game.clear_player_input()
		game.effect_resolver.resolve_effect({"type":"room_effect","range":0,"effects":[{"type":effect_type,"amount":1}]}, {"game":game,"caster_id":0,"caster_room_id":"black_rose"})
		var verb := "Convert 1" if effect_type == "convert_instability" else "Place 1"
		expect(str(game.pending_input.get("effect_description", "")).begins_with(verb), "Actual room choice identifies " + verb)
	game.clear_player_input()
	var history = load("res://action_history.gd").new()
	history.game = game
	expect(history.humanize("Player 1 moved to sacrificial_altar").contains("Sacrificial Altar"), "Log resolves room identifier")
	history.free()
	print("OCT28 UI: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
