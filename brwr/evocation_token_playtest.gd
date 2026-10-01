extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func click(control: Control) -> void:
	var point: Vector2 = control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func run() -> void:
	root.size = Vector2i(1600, 900)
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	for i in range(10):
		await process_frame
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	hud.setup(game)
	var room_id: String = game.player_entrance_room_ids[0]
	var first = game.summon_evocation(0, "succubus", room_id)
	var second = game.summon_evocation(0, "succubus", room_id)
	check(first.board_number == 1 and second.board_number == 2, "Duplicate types need distinct physical numbers")
	var cards = game.player_boards[0].get_node("EvocationCards")
	check(cards.get_node("EvocationSlot2").get_meta("evocation") == second, "Board card must reference the particular evocation instance")
	var second_position: Vector2 = cards.get_node("EvocationSlot2").position
	for id in game.evocation_database.evocations:
		check(game.ReferenceCardPreview.card_texture("evocations", id) != null, "Every playable evocation must have card art: " + id)
	var token = game.evocation_tokens[second.get_instance_id()]
	token.position = Vector2(120, 120)
	for board in game.player_boards:
		board.hide()
	await process_frame
	click(token.get_node("InspectButton"))
	await process_frame
	check(game.evocation_inspection != null and game.evocation_inspection.visible, "Token must be clickable through HUD")
	if game.evocation_inspection != null:
		check(game.evocation_inspection.title.contains("#2"), "Inspector must identify the specific copy")
		game.deal_damage_to_evocation(1, second, 1)
		await process_frame
		await process_frame
		check(game.evocation_inspection.dialog_text.contains("Health: 2 / 3"), "Inspector must show live remaining health")
		check(game.evocation_inspection.dialog_text.contains("Damage: 1"), "Inspector must show live damage")
		check(game.evocation_inspection.dialog_text.contains("Movement speed: " + str(second.speed)), "Inspector must show movement speed")
		check(game.evocation_inspection.dialog_text.contains("Attack: " + str(second.strength)), "Inspector must show attack")
	game.effect_resolver._remove_evocation(game, first, {})
	check(second.board_number == 2, "Removal must not renumber the remaining instance")
	check(not cards.has_node("EvocationSlot1") and cards.get_node("EvocationSlot2").position == second_position, "Removing a card must leave its physical board slot empty")
	var replacement = game.summon_evocation(0, "nigredo", room_id)
	check(replacement.board_number == 1 and second.board_number == 2, "New summon must reuse only the freed number")
	check(cards.get_node("EvocationSlot1").get_meta("evocation") == replacement, "Replacement must update the card in the reused slot")
	game.effect_resolver._remove_evocation(game, second, {})
	await process_frame
	await process_frame
	check(game.evocation_inspection == null or not game.evocation_inspection.visible, "Inspector must close when its instance leaves play")
	print("EVOCATION TOKEN PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
