extends SceneTree

var failures := 0
var game
var screenshot_mode := false
var selected := false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in range(6): await process_frame

func shot(filename: String) -> void:
	if not screenshot_mode: return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/tabletop-shell/" + filename + ".png")

func run() -> void:
	create_timer(75).timeout.connect(func(): push_error("Tabletop shell test timed out"); quit(1))
	screenshot_mode = OS.get_cmdline_user_args().has("screenshots")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 1000)
	game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.enable_beta_hud = false
	game.beta_force_fullscreen = false
	game.game_seed = 1232
	root.add_child(game)
	await settle()
	game.local_viewer_index = 0
	game.table_shell = load("res://tabletop_shell.gd").new()
	game.add_child(game.table_shell)
	game.table_shell.setup(game)
	game.beta_hud = load("res://beta_hud.gd").new()
	game.add_child(game.beta_hud)
	game.beta_hud.setup(game)
	game.enable_beta_hud = true
	game._apply_beta_table_layout()
	root.size_changed.connect(game._on_beta_viewport_resized)
	await settle()
	var shell = game.table_shell
	var hud = game.beta_hud
	var hand = hud.hand_overlay
	var board = game.player_boards[0]
	game.assign_mage_to_player(0, "rikkart")
	game.assign_mage_to_player(1, "angela")
	game.players[0].mage.damage_cubes.assign([1, 1])
	game.players[0].mage.in_cell = false
	game.players[0].mage.room_id = "garden"
	game.players[1].mage.in_cell = false
	game.players[1].mage.room_id = "forge"
	game.refresh_model_tokens()
	game.current_phase = game.PHASE_ACTION
	game.current_round = 2
	game.action_activation_active = true
	game.action_activation_player_index = 0
	game.action_activation_actions_used = 1
	game.request_player_input({"type": "action_activation_step", "player_index": 0, "actions_used": 1, "options": []})
	var spell = game.spell_database.get_spell("heart_of_ice")
	game._set_player_board_spell_slot(0, "I", spell, true, "revealed")
	game._set_player_board_spell_slot(0, "II", spell, false, "prepared")
	var trap = game.spell_database.get_spell("liquefy_the_pain")
	game._set_player_board_spell_slot(0, "Q", trap, false, "active_hidden")
	game.players[0].active_spells.append(ActiveSpellState.new(trap, 0, false))
	game.summon_evocation(0, "nigredo", "garden")
	var quest := QuestState.new(game.quest_database.get_quest("warrior_wizard"), 0)
	quest.progress = 1
	quest.revealed = true
	game.players[0].active_quests.append(quest)
	var done := QuestState.new(game.quest_database.get_quest("channeling_instability"), 0)
	done.complete()
	done.progress = done.get_cube_slots()
	game.players[0].completed_quests.append(done)
	var solved := QuestState.new(game.quest_database.get_quest("guarding_wisdom"), 0)
	solved.solve()
	game.players[0].completed_quests.append(solved)
	game.refresh_all_player_boards()
	await settle()
	shell.close_board()
	shell._observe(false)
	check(shell.banners.size() == 2, "One banner per actual player")
	check(shell.banners[0].get_node("Count").text == "1/2", "Current player displays the authoritative activation counter")
	game.pending_input.player_index = 1
	check(game.get_turn_presentation().player_index == 0 and game.get_turn_presentation().actions_used == 1, "A reaction does not move the active turn banner")
	game.pending_input.player_index = 0
	check(not hud.decision_info.text.contains("Actions used"), "No duplicate action counter in announcements")
	check(not hud.decision_bar.visible, "Turn selection leaves the top of the table clear")
	check(game.playmat.texture != null and Rect2(game.playmat.position, game.playmat.size).encloses(game.get_lodge_table_bounds()), "Playmat contains every room and common board")
	check(game.player_boards.all(func(item): return item.get_parent() == shell.board_stage), "Boards moved into one screen overlay, not duplicated")
	await shot("01-lodge")
	shell.banners[0].pressed.emit()
	await settle()
	check(shell.board_overlay.visible and shell.shown_player == 0, "Player banner opens its board")
	check(board.get_node("SpellSlots/SpellSlotI/ActiveSide").visible, "Public spell highlights its active half")
	check(board.get_node("SpellSlots/SpellSlotI/CardArt").rotation == 0 and board.get_node("SpellSlots/SpellSlotI/ActiveSide").position.y > 0, "Dark half is highlighted without rotating upright source text")
	check(board.get_node("SpellSlots/QuickSpellSlot/SpellMarker").texture != null, "Armed card has a graphical trap marker")
	check(board.get_node("SpellSlots/SpellSlotII/CardBack").visible, "Prepared spells remain face down")
	game.open_player_board_spell(0, "II")
	check(game.get_node("SpellCardPreview").root.visible, "Owner can inspect a private prepared spell")
	game._close_player_board_spell_preview()
	await shot("02-player-board")
	# Opening a board must preserve the actual choice callback on its damage cube.
	shell.close_board()
	game.show_board_target_choice({"token": "damage:1:0", "cube_player_index": 0}, func(): selected = true)
	check(shell.board_overlay.visible, "Damage conversion opens the corresponding board")
	shell.open_board(1)
	shell.open_board(0)
	var choices = get_nodes_in_group("board_target_choices")
	check(choices.size() == 1 and choices[0].is_visible_in_tree(), "Switching boards preserves a pending cube choice")
	choices[0].pressed.emit()
	await settle()
	check(selected, "Cube selection still dispatches its original callback")
	game.clear_board_target_choices()
	game.show_lodge_room_choices({"garden": func(): pass})
	check(not shell.board_overlay.visible, "Room choices return to the Lodge")
	game.clear_lodge_room_choices()
	for i in range(8): game.players[0].hand.append(spell)
	hand.open_preparation({"player_index": 0, "type": "preparation", "hand": [{"id": "heart_of_ice", "name": "Heart of Ice", "hand_index": 0}, {"id": "liquefy_the_pain", "name": "Liquefy the Pain", "hand_index": 1}], "min_spells": 2})
	hand._select_card(0)
	hand._assign_selected_numbered()
	hand.tabs.current_tab = 1
	await settle()
	check(hand.quest_columns.get_node("Active").get_child_count() > 1, "Active Quest section populated")
	check(game.get_player_quest_cards(0, "completed").size() == 1 and game.get_player_quest_cards(0, "solved").size() == 1, "Completed and Solved quests are distinct")
	check(hand.quest_columns.find_children("QuestProgress", "HBoxContainer", true, false).size() > 0, "Quest cubes visible without inspection")
	await shot("03-quests")
	hand._select_cards_tab()
	check(hand.ready_hand_indices == [0] and hand.prep_controls.visible, "Tab switch preserves Preparation draft")
	check(hand.title_label.text == "PLAYER 1 — PREPARATION", "Back to cards restores Preparation heading")
	hand.open_browse(0)
	check(hand._assignment_badge(0).is_empty(), "Browse does not show previous Preparation draft labels")
	await settle()
	await shot("04-cards")
	check(hand.card_row.columns == 8, "Hand stays in one scrollable row")
	game.local_viewer_index = 1
	await settle()
	check(not hand.visible and not shell.board_overlay.visible, "Viewer change dismisses private UI")
	hand.open_browse(0)
	check(not hand.visible, "Cannot open another player's hand by API")
	shell.open_board(0)
	check(board.get_node("SpellSlots/SpellSlotII/CardClickButton").disabled, "Nonowner cannot inspect prepared spell")
	check(board.get_node("SpellSlots/QuickSpellSlot/SpellMarker").visible, "Opponents still see the armed marker")
	check(not game.get_player_board_spell_slot_data(0, "Q").has("id"), "Trap animation never reveals private identity")
	shell.close_board()
	shell._observe(false)
	game.players[0].available_physical_actions = 1
	board.refresh_action_tokens()
	await settle()
	check(shell.animation != null and shell.board_overlay.visible, "Committed physical action opens board and animates token")
	await shot("05-action-feedback")
	await create_timer(1.3).timeout
	check(not shell.board_overlay.visible, "Animation returns to the table without requiring confirmation")
	var state: Dictionary = load("res://network_projection.gd").build(game, 1)
	check(state.turn_presentation.actions_used == 1 and not state.slots[0]["II"].has("id"), "Online turn counter and hidden card privacy use public projection")
	check(not hud.decision_bar.is_ancestor_of(hud.prompt_label) and not hud.decision_bar.is_ancestor_of(hud.decision_info), "Floating controls contain no description banner")
	game.clear_player_input()
	game.resolve_event(game.event_database.get_event("black_thorns"), {"play_order": [0, 1]})
	var evocation: EvocationState = game.players[0].evocations[0]
	check(shell.card_overlay.visible and evocation.damage_cubes.is_empty(), "Event card appears before its damage is applied")
	var event_serial: int = game.card_presentation.serial
	game.process_resolution_stack()
	check(evocation.damage_cubes.is_empty(), "Re-entering resolution cannot bypass presentation")
	state = load("res://network_projection.gd").build(game, 1)
	check(state.card_presentation.id == "black_thorns" and state.players[0].evocations[0].damage_cubes.is_empty(), "Online projection sends the public Event before the effect")
	await shot("06-event")
	await create_timer(game.CARD_PRESENTATION_SECONDS + 0.1).timeout
	check(evocation.damage_cubes.size() == 2 and not shell.card_overlay.visible and game.resolution_stack.is_empty(), "Event resumes automatically and inflicts damage once")
	game._finish_card_presentation(event_serial)
	check(evocation.damage_cubes.size() == 2, "Stale animation completion cannot repeat an Event")
	var resolving_quest := QuestState.new(game.quest_database.get_quest("rest_the_limbs"), 0)
	resolving_quest.complete()
	game.players[0].completed_quests.append(resolving_quest)
	game.crown_owner_id = 1
	var prior_power: int = game.players[0].power
	game.quest_manager.solve_quest(game, 0, resolving_quest)
	check(shell.card_overlay.visible and game.card_presentation.kind == "quests" and game.crown_owner_id == 1, "Quest card appears before taking the Crown or choosing targets")
	check(not game.waiting_for_player_input and not resolving_quest.solved, "Quest decisions and reward wait for its presentation")
	await shot("07-quest")
	await create_timer(game.CARD_PRESENTATION_SECONDS + 0.1).timeout
	check(game.crown_owner_id == 0, "Quest first effect runs after its presentation")
	for i in range(4):
		if not game.waiting_for_player_input: break
		var options: Array = game.pending_input.get("options", [])
		check(not options.is_empty() and game.submit_effect_choice(0, [str(options[0].token)]), "Quest target remains selectable after presentation")
	check(resolving_quest.solved and game.players[0].power == prior_power + resolving_quest.get_power_reward(), "Quest finishes and awards its Power exactly once")
	var token_proof := PanelContainer.new()
	token_proof.position = Vector2(400, 340)
	token_proof.theme = load("res://tabletop_style.gd").make_theme()
	shell.root.add_child(token_proof)
	var token_row := HBoxContainer.new()
	token_row.add_theme_constant_override("separation", 24)
	token_proof.add_child(token_row)
	for slot in ["Q", "I", "II", "III"]:
		var token = load("res://tabletop_style.gd").marker("permanent", Color("834aaa"), Vector2(140, 140), slot)
		token_row.add_child(token)
		check(token.has_node("QuickSlot") if slot == "Q" else token.get_node("SpellSlot").text == slot, "Persistence marker identifies " + slot)
	await shot("08-persistence-tokens")
	token_proof.queue_free()
	for extent in [Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(1280, 800)]:
		root.size = extent
		root.content_scale_size = extent
		await settle()
		game.get_node("TableCamera").reset_view()
		var view: Rect2 = game.get_table_view_rect()
		var bounds: Rect2 = game.get_tabletop_bounds()
		var transform: Transform2D = game.get_canvas_transform()
		var drawn := Rect2(transform * bounds.position, bounds.size * game.get_node("TableCamera").zoom)
		check(view.grow(1).encloses(drawn), "Lodge fits beside rail and below announcements at " + str(extent))
		shell.open_board(0)
		check(shell.board_stage.position.y + shell.board_stage.size.y * shell.board_stage.scale.y <= shell.board_overlay.size.y, "Fullscreen board stays within viewport")
		shell.close_board()
	game.queue_free()
	await process_frame
	print("TABLETOP SHELL PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(failures)
