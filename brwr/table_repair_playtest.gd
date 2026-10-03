extends SceneTree

var failures := 0
var confirmed := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(1280, 720)
	var game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.enable_beta_hud = false
	game.beta_force_fullscreen = false
	root.add_child(game)
	for i in range(8): await process_frame
	var player = game.players[0]
	player.mage.in_cell = false
	player.mage.room_id = "forge"
	player.active_quests.clear()
	var quest := QuestState.new(game.quest_database.quests["summoner_wizard"], 0)
	player.active_quests.append(quest)
	player.quick_spell = ReadySpellState.new(game.clone_spell_card(game.spell_database.get_spell("fountain_of_the_three")), true)
	check(game.cast_quick_spell(0, {"target_room_id": "forge", "fountain_choice": "summon_nigredo"}), "Fountain Dark cast commits")
	check(player.evocations.size() == 1, "Fountain summons Nigredo")
	check(quest.progress == 1, "Summoner Wizard gains exactly one cube for the chosen summon branch")
	var context := {"game": game, "caster_id": 0, "target_room_id": "forge", "fountain_choice": "summon_nigredo", "effect_summoned_evocation": true}
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "effects": [{"type": "gain_power", "amount": 1}], "index": 0, "context": context})
	check(quest.progress == 1, "Unrelated effect must not inherit summon keyword")
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	hud.setup(game)
	game.local_viewer_index = 0
	hud.current_player_index = 0
	var spell = game.spell_database.get_spell("shared_torture")
	game._set_player_board_spell_slot(0, "I", spell, false, "prepared")
	hud.current_request = {"type": "cleanup_active_spells", "active_spells": [{"active_index": 0, "spell_id": spell.id, "board_player_index": 0, "slot_id": "I"}]}
	hud._render_current_request()
	for i in range(3): await process_frame
	var confirm: Button = hud.decision_actions.get_child(0)
	check(confirm.text == "Confirm Clean-up", "Cleanup confirm belongs to the top action bar")
	check(confirm.get_global_rect().end.y < 160, "Confirm stays at top even at 720p")
	hud._toggle_generic_value(0)
	for i in range(3): await process_frame
	check(hud.decision_actions.get_child_count() == 1, "Selection rebuild keeps one live confirmation")
	hud.panel.hide()
	check(hud.decision_actions.get_child(0).is_visible_in_tree(), "Hiding HUD cannot hide confirmation")
	hud._clear_content()
	confirm = hud._add_confirmation("Confirm", func(): confirmed = true)
	await process_frame
	var point := confirm.get_global_rect().get_center()
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = pressed
		root.push_input(click, true)
	await process_frame
	check(confirmed, "Real mouse click reaches top confirmation")
	var choice = load("res://lodge_room_choice.gd").new()
	choice.setup(game.HEX_RADIUS)
	check(choice.polygon[0].x == 2.0 * game.HEX_RADIUS, "Hit shape preserves the full room radius")
	check(choice.outline_polygon[0].x + 2.0 < choice.polygon[0].x, "Highlight stroke stays inside the hex")
	choice.free()
	game.queue_free()
	await process_frame
	print("TABLE REPAIR: ", "PASS" if failures == 0 else "FAIL " + str(failures))
	quit(0 if failures == 0 else 1)
