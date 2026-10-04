extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in range(3): await process_frame

func run() -> void:
	create_timer(35).timeout.connect(func(): push_error("School UI playtest timed out"); quit(1))
	root.size = Vector2i(1600, 900)
	var game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	game.enable_beta_hud = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(12): await process_frame
	game.beta_hud = load("res://beta_hud.gd").new()
	game.add_child(game.beta_hud)
	game.beta_hud.setup(game)
	game.local_viewer_index = 0
	var hud = game.beta_hud
	hud.present_pending_request({"type": "starting_school_choice", "player_index": 0,
		"available_schools": [{"id": "agony", "name": "Agony"}, {"id": "alchemy", "name": "Alchemy"}]})
	await settle()
	var row = hud.content.get_node("ObjectChoices").get_child(0)
	check(row.get_child_count() == 2 and hud.panel.visible, "School setup displays both cards")
	for i in range(2):
		var button = row.get_child(i).get_child(0)
		var texture: Texture2D = button.get_child(0).texture
		check(texture != null and texture.resource_path.contains("assets/schools/"), "School choice loads its real image")
		check(is_equal_approx(texture.get_size().aspect(), 2.0 / 3.0), "School card keeps portrait proportions")
	row.get_child(1).get_node("InspectSchool").pressed.emit()
	await settle()
	var preview = game.get_node("ReferenceCardPreview")
	check(preview.root.visible and preview.title_label.text == "Alchemy", "Inspect opens the selected School")
	check(preview.art.custom_minimum_size.y >= 700 and not preview.description.visible, "School rules fill the enlarged preview")
	check(game.players[0].school_id.is_empty(), "Inspection does not choose a School")
	preview.hide_preview()
	hud.present_pending_request({"type": "study_choose_schools", "player_index": 0,
		"active_school_ids": ["agony", "alchemy"]})
	for i in range(4):
		row = hud.content.get_node("ObjectChoices").get_child(0)
		row.get_child(1).get_node("InspectSchool").pressed.emit()
		await settle()
		check(hud.school_draft.size() == i, "Inspect must not consume a Library draw")
		preview.hide_preview()
		row.get_child(i % 2).get_child(0).pressed.emit()
		await settle()
	check(hud.school_draft == ["agony", "alchemy", "agony", "alchemy"], "Study keeps four independent School choices")
	check(not hud.decision_actions.get_child(0).disabled, "Study confirmation is available after four choices")
	preview.show_card("events", "growth", "Growth", "Event rules")
	check(preview.description.visible and preview.art.custom_minimum_size == Vector2(480, 460), "Other card previews retain their layout")
	preview.hide_preview()
	game.summon_evocation(0, "nigredo", "forge")
	game.summon_evocation(0, "nigredo", "garden")
	game.current_phase = game.PHASE_EVOCATION
	game.current_phase_play_order.assign([0, 1])
	game.advance_evocation_phase()
	await settle()
	check(game.pending_input.get("type") == "evocation_phase_activations", "Evocation phase has a real pending choice")
	check(hud.content.get_child_count() == 0 and not hud.panel.visible, "No empty modal covers selectable Evocations")
	check(not hud.decision_bar.visible, "No description banner covers the Lodge during Evocation selection")
	hud._toggle_panel()
	check(not hud.panel.visible, "F10 does not reopen an empty modal")
	var choices = get_nodes_in_group("board_target_choices").filter(func(node): return not node.is_queued_for_deletion())
	check(not choices.is_empty(), "Evocation tokens remain clickable")
	if not choices.is_empty():
		choices[0].pressed.emit()
		await settle()
		check(not hud.panel.visible and hud.content.get_child_count() == 0, "Evocation movement uses the Lodge without a lower modal")
		check(get_nodes_in_group("lodge_room_choices").size() > 0, "Movement Rooms stay selectable")
		var back = hud.decision_actions.get_children().filter(func(button): return button.text == "← Back")
		check(back.size() == 1, "Back is available in the top bar")
		if not back.is_empty():
			back[0].pressed.emit()
			await settle()
			check(not hud.panel.visible and not get_nodes_in_group("board_target_choices").is_empty(), "Back returns to token selection without an empty modal")
	game.clear_player_input()
	game.queue_free()
	await process_frame
	print("SCHOOL UI PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
