extends SceneTree

# Run with: Godot --headless --path . --script res://player_board_playtest.gd
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func click_control(control: Control) -> void:
	var position: Vector2 = control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
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
	var board = game.player_boards[0]
	check(board.get_node("SheetArt").size == Vector2(600, 500), "Board art must fit the physical sheet instead of its source pixel dimensions")
	check(board.get_node("SheetArt").texture != null, "Physical board artwork must load")
	var saved_mage_id: String = game.players[0].mage.mage_id
	for mage_id in ["rikkart", "angela"]:
		game.players[0].mage.mage_id = mage_id
		board.refresh_mage_card()
		var mage_art: TextureRect = board.get_node("MageCardSlot/MageArt")
		check(mage_art.texture != null and mage_art.texture.resource_path.ends_with(mage_id + ".png"), "Each playable Mage loads its own card")
		check(absf(mage_art.texture.get_size().aspect() - board.MAGE_CARD_SIZE.aspect()) < 0.01, "Mage art must fit slot without cropping or letterboxing")
	game.players[0].mage.mage_id = saved_mage_id
	board.refresh_mage_card()
	check(game.ReferenceCardPreview.card_texture("quests", "conspirator_mage") != null, "Conspirator Mage image must load")
	var saved_color: Color = game.players[0].color
	for color in board.SHEET_VARIANTS:
		game.players[0].color = color
		board.refresh_sheet_art()
		var art: TextureRect = board.get_node("SheetArt")
		check(art.texture != null and art.texture.resource_path.ends_with(board.SHEET_VARIANTS[color]), "Player colour must select its own board texture")
		check(art.size == Vector2(600, 500), "Colour variants must preserve slot geometry")
	game.players[0].color = saved_color
	board.refresh_sheet_art()
	board.position = Vector2(40, 40)
	board.scale = Vector2.ONE
	for other in game.player_boards:
		other.visible = other == board
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	hud.setup(game)
	var spell = game.spell_database.spells["shared_torture"]
	game._set_player_board_spell_slot(0, "I", spell, false, "prepared")
	game.request_player_input({"player_index": 0, "type": "board_test"})
	await process_frame
	await process_frame
	var button = board.get_node("SpellSlots/SpellSlotI/CardClickButton")
	click_control(button)
	await process_frame
	var preview = game.get_node_or_null("SpellCardPreview")
	check(preview != null and preview.root.visible, "Owner click must open prepared card preview through HUD")
	game.clear_player_input()
	game.request_player_input({"player_index": 1, "type": "board_test"})
	click_control(button)
	await process_frame
	preview = game.get_node_or_null("SpellCardPreview")
	check(preview == null or not preview.root.visible, "Other viewer cannot inspect hidden card")
	game._set_player_board_spell_state(0, spell, "revealed")
	click_control(button)
	await process_frame
	preview = game.get_node_or_null("SpellCardPreview")
	check(preview != null and preview.root.visible, "Other viewer click must open revealed card preview through HUD")
	if preview != null:
		check(preview.image.size.y > 400, "Inspection must display a readable enlarged card")
		var close_buttons = preview.root.find_children("*", "Button", true, false)
		click_control(close_buttons[0])
		await process_frame
		check(not preview.root.visible, "Preview Close button must receive mouse clicks")
	game.clear_player_input()
	# Lethal damage must preserve defeat result while restoring HP and cube pools.
	var target = game.players[0].mage
	target.in_cell = false
	var owner_pool: int = game.players[1].available_cubes
	var rose_pool: int = game.get_node("EventBoard").black_rose_cube_count
	game.deal_damage(-1, 0, 1)
	check(target.get_remaining_health() == target.health - 1, "Nonlethal damage must remain on the track")
	var context: Dictionary = {"test": true}
	game.active_effect_context = context
	game.deal_damage(1, 0, target.health)
	game.active_effect_context = {}
	check(bool(context.get("last_damage_defeated_target", false)), "Defeat result must survive HP recovery")
	check(target.in_cell, "Defeated mage must return to Cell")
	check(target.get_remaining_health() == target.health, "Defeated mage must recover full HP")
	check(target.damage_cubes.is_empty(), "Defeat must clear damage cubes")
	check(game.players[1].available_cubes == owner_pool, "Damage cubes must return to their owner")
	check(game.get_node("EventBoard").black_rose_cube_count == rose_pool, "Black Rose damage cubes must return to their pool")
	check(board.get_node("HealthLabel").text == "HP: " + str(target.health) + "/" + str(target.health), "PlayerBoard HP label must refresh after defeat")
	for damage_slot in board.get_node("DamageTrack").get_children():
		check(damage_slot.get_node_or_null("DamageCube") == null, "Defeat must remove displayed damage cubes")
	print("PLAYER BOARD PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
