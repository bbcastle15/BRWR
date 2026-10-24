extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

var accepted := 0

func settle():
	for i in 5: await process_frame

func clean_ui():
	game.clear_player_input()
	game.resolution_stack.clear()
	game.table_shell.close_board()
	game.beta_hud.hand_overlay.close_overlay()
	game.beta_hud.panel.hide()
	game._reference_card_preview().hide_preview()

func sorted_names(items: Array) -> bool:
	for i in range(1, items.size()):
		if str(items[i-1].name).naturalnocasecmp_to(str(items[i].name)) > 0: return false
	return true

func run():
	root.size = Vector2i(1600, 1000)
	game = await create_game()
	game.local_viewer_index = 0
	game.table_shell.set_process(false)
	reset_case()
	var hud = game.beta_hud
	var shell = game.table_shell
	var preview = game._reference_card_preview()
	var power = game.get_node("PowerBoard")

	# All public catalogs use definitions, never a remaining deck or private Hand.
	for slot in ["QuestSlot", "JinxSlot", "UpgradeSlot"]:
		expect(power.get_node_or_null(slot + "/AvailableDeck/CardBack") != null, slot + " has an illustrated clickable deck")
	for moon in [1,2,3]:
		game.current_moon = moon
		power._inspect_available("quests")
		var expected: Array = game.quest_database.quests.values().filter(func(q): return q.moon == moon)
		expect(preview.pile_cards.size() == expected.size(), "Quest catalog covers current Moon " + str(moon))
		expect(sorted_names(preview.pile_cards) and preview.pile_title == "Available quests", "Quest catalog is alphabetical and named")
		var before: Array = preview.pile_cards.duplicate(true)
		var deck: Array = game.quest_decks[moon].duplicate()
		game.quest_decks[moon].clear()
		power._inspect_available("quests")
		expect(preview.pile_cards == before, "Drawn Quests remain in catalog")
		game.quest_decks[moon].assign(deck)
	for kind in ["jinxs", "upgrades"]:
		power._inspect_available(kind)
		expect(preview.pile_cards.size() == ForgottenAttachments.database()["jinxes" if kind == "jinxs" else kind].size(), "Complete " + kind + " catalog")
		expect(sorted_names(preview.pile_cards), kind + " alphabetical")
	preview.show_school_library("alchemy")
	expect(preview.pile_cards.size() == 13 and preview.pile_cards[0].card_kind == "schools", "School card precedes all twelve Spells")
	expect(sorted_names(preview.pile_cards.slice(1)), "School Spells alphabetical")
	for item in preview.pile_cards.slice(1):
		expect(not game.spell_database.get_spell(item.id).personal, "Personal excluded from School library: " + item.id)
	preview._browse_pile(1)
	expect(preview.art.texture == SpellArtResolver.get_texture(str(preview.pile_cards[1].id), "alchemy"), "School browser actually advances to Spell art")
	preview.hide_preview()
	game.current_moon = 1

	# Specialization has a fixed question and exactly two named choices.
	var options: Array = game.get_starting_grimoire_options("alchemy")
	game.request_player_input({"type":"starting_grimoire_choice", "player_index":0, "options":options, "school_id":"alchemy"})
	await settle()
	var header = hud.prompt_label.get_parent().get_node("SpecializationChoice")
	var buttons = header.get_child(0).get_child(1)
	expect(buttons.get_child_count() == 2, "Two explicit specialization buttons")
	expect(buttons.get_child(0).text == options[0].name and buttons.get_child(1).text == options[1].name, "Buttons use actual specialization names")
	for option in options:
		var row = hud.content.get_node("Grimoire_" + str(option.id))
		expect(row.get_child_count() == 6, "Six named cards in " + str(option.name))
		for i in row.get_child_count():
			expect(row.get_child(i).get_child(0).text == option.spells[i].name, "Specialization card name is readable")
		expect(row.get_child(5).get_global_rect().end.x <= hud.panel.get_global_rect().end.x - 20, "Last specialization card fits without horizontal clipping")
	await capture("ui23-specializations")
	clean_ui()

	# Confirmation is cancelable, cannot accept a stale request, and runs once.
	hud.confirm_choice("Confirm test", func(): accepted += 1)
	expect(hud.choice_confirmation.visible and accepted == 0, "Confirmation precedes mutation")
	hud.choice_confirmation.canceled.emit()
	hud._accept_confirmation()
	await settle()
	expect(accepted == 0, "Cancel keeps state unchanged")
	hud.confirm_choice("Stale test", func(): accepted += 1)
	game.input_revision += 1
	hud._accept_confirmation()
	await settle()
	expect(accepted == 0, "Stale confirmation rejected")
	hud.confirm_choice("Accept test", func(): accepted += 1)
	hud._accept_confirmation()
	hud._accept_confirmation()
	await settle()
	expect(accepted == 1, "Confirmed action runs exactly once")
	hud._submit_starting_mage("mors")
	expect(hud.choice_confirmation.visible and hud.choice_confirmation.dialog_text.contains("Mors"), "Mage selection requires named confirmation")
	hud._submit_starting_school("alchemy")
	expect(hud.choice_confirmation.dialog_text.contains("Alchemy"), "School selection requires named confirmation")
	hud.choice_confirmation.hide()
	hud.confirmation_action = Callable()

	# Real Study request: card remains in Hand until Confirm; inspection is read-only.
	game.current_phase = game.PHASE_STUDY
	game.players[0].hand.append(game.clone_spell_card(game.spell_database.get_spell("tearing")))
	game.request_study_optional_discard(0)
	hud._submit_optional_hand_discard(0)
	expect(game.players[0].hand.size() == 1 and hud.choice_confirmation.dialog_text.contains("Tearing"), "Post-draw discard waits for confirmation")
	hud.choice_confirmation.canceled.emit()
	hud.choice_confirmation.hide()
	expect(game.players[0].hand.size() == 1, "Canceled discard preserves Spell")
	hud._submit_optional_hand_discard(0)
	hud._accept_confirmation()
	await settle()
	expect(game.players[0].hand.is_empty(), "Confirmed discard reaches engine")
	clean_ui()
	for i in 4: game.study_drawn_cards.append(game.clone_spell_card(game.spell_database.get_spell("tearing")))
	game.request_study_keep_cards(0)
	hud.hand_overlay.study_confirmed.emit([0,1])
	expect(hud.choice_confirmation.visible and game.study_drawn_cards.size() == 4, "Study keep/discard confirmation preserves drawn cards")
	expect(hud.choice_confirmation.dialog_text.count("Tearing") == 2, "Draw confirmation identifies only the two discarded cards")
	clean_ui()
	game.study_drawn_cards.clear()
	game.players[0].hand.append(game.clone_spell_card(game.spell_database.get_spell("tearing")))
	game.request_study_hand_limit(0,1)
	hud.generic_selection.assign([0])
	hud._submit_study_hand_limit()
	expect(hud.choice_confirmation.visible and hud.choice_confirmation.dialog_text.contains("Tearing"), "Hand-limit discard also requires named confirmation")
	clean_ui()
	game.players[0].hand.clear()
	game.current_phase = game.PHASE_ACTION
	var click_count := [0]
	var inspect_button := Button.new()
	hud.add_child(inspect_button)
	game.connect_card_choice(inspect_button, {"card_kind":"spells", "id":"tearing", "name":"Tearing"}, func(): click_count[0] += 1)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	inspect_button.gui_input.emit(right)
	await settle()
	expect(preview.root.visible and click_count[0] == 0, "Right click inspects without selecting/casting")
	preview.hide_preview()
	inspect_button.pressed.emit()
	await settle()
	expect(click_count[0] == 1, "Left click selects once")
	inspect_button.queue_free()
	hud.current_request = {"options":[{"token":"cast_test", "label":"Cast Tearing", "spell":{"name":"Tearing"}, "action":{"type":"spell"}}]}
	hud._submit_action_token("cast_test")
	expect(hud.choice_confirmation.visible and hud.choice_confirmation.dialog_text == "Vuoi lanciare Tearing?", "Spell cast has named confirmation")
	hud.choice_confirmation.hide()
	hud.confirmation_action = Callable()

	# Preparation uses the same shared active-side frame, including Dark changes.
	var hand_view = hud.hand_overlay
	hand_view.open_preparation({"player_index":0,"hand":[{"hand_index":0,"id":"tearing","name":"Tearing","school_id":"death"}]})
	hand_view._select_card(0)
	await settle()
	var frames: Array = hand_view.find_children("ActiveSide", "Panel", true, false)
	expect(frames.size() == 1 and frames[0].position.y + frames[0].size.y * 0.5 < frames[0].get_parent().size.y * 0.5, "Preparation highlights Light half")
	hand_view._set_selected_side(true)
	await settle()
	frames = hand_view.find_children("ActiveSide", "Panel", true, false)
	expect(frames.size() == 1 and frames[0].position.y > 100, "Preparation highlights Dark half after toggle")
	await capture("ui23-preparation-dark")
	clean_ui()

	game.avatar_board.refresh()
	game.avatar_board.cards_root.get_child(0).pressed.emit()
	await settle()
	expect(game.avatar_board.expanded and shell.shown_player == AVATAR, "Avatar card click opens Avatar Board")
	clean_ui()

	# The next effect can request Avatar cubes while damage is still presented.
	reset_case()
	damage(AVATAR, [1,1])
	game.avatar_board.refresh()
	game.queue_resolution({"type":"effect_sequence", "resolver_kind":"spell", "index":0,
		"effects":[{"type":"damage", "amount":1},{"type":"convert_damage", "amount":1}],
		"context":{"game":game,"caster_id":0,"caster_room_id":"black_rose","target_player_index":AVATAR,"target_model_type":"mage","spell_target_type":"mage","spell_type":"combat"}})
	await settle()
	expect(game.waiting_for_player_input and shell._has_damage_presentation(), "Conversion is requested without an artificial rule delay")
	if not shell.animation_queue.is_empty(): shell._play_next_animation()
	await create_timer(1.1).timeout
	var cube_buttons: Array = get_nodes_in_group("board_target_choices").filter(func(n): return n is Button and is_instance_valid(n) and not n.is_queued_for_deletion())
	expect(shell.animation == null and game.avatar_board.expanded and not cube_buttons.is_empty(), "Avatar conversion is clickable immediately after damage feedback")
	await capture("ui23-avatar-after-damage")
	await drive()
	expect(game.players[AVATAR].mage.damage_cubes.count(0) == 2, "Second effect converts Avatar damage correctly")
	clean_ui()

	# Late join skips old feedback, future snapshots replay even already-cleared lethal damage.
	reset_case()
	var client = await create_game(true)
	client.local_viewer_index = 1
	client.table_shell.set_process(false)
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	expect(not client.table_shell._has_damage_presentation() and client.table_shell.world_placements.is_empty(), "Initial snapshot has no stale animations")
	game.players[1].mage.damage_cubes.assign([2,2,2,2,2,2,2,2,2])
	game.deal_damage(0,1,2,"spell")
	await drive()
	var state: Dictionary = NetworkSnapshot.build(game,1)
	NetworkSnapshot.apply(client, state)
	expect(client.players[1].mage.in_cell and client.players[1].mage.damage_cubes.is_empty(), "Client receives final defeated state")
	expect(client.table_shell.animation_queue.filter(func(e): return e.kind == "damage").size() == 2, "Client replays both lethal damage cubes")
	expect(client.table_shell.animation_queue.back().defeated, "Client feedback retains lethal hit")
	NetworkSnapshot.apply(client,state)
	expect(client.table_shell.animation_queue.size() == 2, "Repeated snapshot does not duplicate damage")
	client.table_shell.close_board()
	shell.close_board()

	# Every human sees the same active side and independently closes the public spell.
	var session = load("res://online_session.gd").new()
	root.add_child(session)
	session.game = game
	session.hosting = true
	session.connected = true
	session.peer_players = {"remote":1}
	session.receiving = {"remote":true}
	game.network_session = session
	game._present_resolution_card({"type":"spell_resolution", "spell":game.spell_database.get_spell("tearing"), "use_dark_side":true, "context":{"caster_id":0}})
	var serial: int = game.card_presentation.serial
	state = NetworkSnapshot.build(game,1)
	NetworkSnapshot.apply(client,state)
	expect(client.table_shell.card_overlay.visible and client.table_shell.presentation_side.visible, "Remote player sees cast Spell and active side")
	expect(game.card_presentation.awaiting_players == [0,1,2], "Spell waits for humans, excluding Avatar")
	expect(not game.dismiss_card_presentation(serial,3) and not game.dismiss_card_presentation(serial-1,1), "Avatar/stale acknowledgements rejected")
	expect(game.dismiss_card_presentation(serial,0) and not game.card_presentation.is_empty(), "Caster closing does not hide others' Spell")
	expect(state.card_presentation.awaiting_players == [0,1,2], "Snapshot is immutable after host acknowledgement")
	session._handle_game_message("remote", {"op":"ack_presentation","serial":serial})
	expect(game.card_presentation.awaiting_players == [2] and not game.dismiss_card_presentation(serial,1), "Authenticated remote acknowledgement accepted only once")
	NetworkSnapshot.apply(client,NetworkSnapshot.build(game,1))
	expect(not client.table_shell.card_overlay.visible, "Acknowledged client closes its own overlay")
	expect(game.dismiss_card_presentation(serial,2) and game.card_presentation.is_empty(), "Final human acknowledgement continues resolution")
	game.network_session = null
	session.connected = false
	session.queue_free()
	NetworkSnapshot.apply(client,NetworkSnapshot.build(game,1))

	# Added instability and models animate on both host and client, once uncovered.
	clean_ui()
	game.get_room_by_id("garden").add_instability_cube(0)
	game.summon_evocation(0,"cadaver","garden")
	await drive()
	NetworkSnapshot.apply(client,NetworkSnapshot.build(game,1))
	expect(shell.world_placements.size() >= 2 and client.table_shell.world_placements.size() >= 2, "Instability and summon placements queued locally and remotely")
	var fresh_nodes: Array = client.table_shell.world_placements.duplicate()
	client.beta_hud.panel.hide()
	client.beta_hud.hand_overlay.close_overlay()
	client.table_shell.close_board()
	client.table_shell._play_world_placements()
	expect(client.table_shell.world_placements.is_empty(), "World placements start when visible")
	await create_timer(1.5).timeout
	for node in fresh_nodes:
		if is_instance_valid(node): expect(is_equal_approx(node.modulate.a,1.0), "Placed object ends fully visible")
	client.queue_free()
	clean_ui()
	print("UI ONLINE OCT23: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
