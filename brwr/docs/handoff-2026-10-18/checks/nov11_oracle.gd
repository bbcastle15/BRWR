extends "res://docs/handoff-2026-10-18/checks/playtest.gd"

func card(id: String) -> EventCardState:
	return game.event_database.get_event(id)

func run() -> void:
	game = await make_game(4)
	reset_case()
	game.current_moon = 1
	check_search()
	await check_slots()
	await check_payments()
	await check_pneuma()
	game.queue_free()
	await process_frame
	for seats in [2, 4]:
		await check_avatar_turn(seats)
	print("NOV11 ORACLE: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)

func check_search() -> void:
	var deck: Array = game.event_decks[1]
	var power: int = game.black_rose_power
	var crown: int = game.crown_owner_id
	var next_moon := card("vision")
	for initially_empty in [true, false]:
		deck.clear()
		game.event_discard.assign([next_moon, card("gift_to_fools")])
		if not initially_empty: deck.append(card("black_thorns"))
		expect(OracleRules.draw_prophecy(game) == card("gift_to_fools"), "Prophecy reaches current Moon discard after exhaustion")
		expect(game.event_discard == [next_moon], "Other Moons keep their own discards")
		expect(deck.size() == int(not initially_empty), "Successful search shuffles each revealed Instant back once")
	deck.assign([card("hidden_resources"), card("black_thorns")])
	game.event_discard.assign([card("awakening")])
	expect(OracleRules.draw_prophecy(game) == card("hidden_resources") and game.event_discard == [card("awakening")], "Deck takes precedence over discard")
	deck.assign([card("black_thorns")])
	game.event_discard.assign([next_moon, card("awakening")])
	expect(OracleRules.draw_prophecy(game) == null and deck.is_empty(), "Only Instants leaves deck empty")
	expect(game.event_discard.size() == 3 and game.event_discard.has(card("black_thorns")) and game.event_discard.has(card("awakening")), "Every Instant ends in discard exactly once")
	expect(OracleRules.draw_prophecy(game) == null and game.event_discard.size() == 3, "A second all-Instant search terminates and conserves cards")
	game.event_discard.assign([next_moon])
	expect(OracleRules.draw_prophecy(game) == null and game.event_discard == [next_moon], "No current-Moon cards still terminates")
	expect(game.black_rose_power == power and game.crown_owner_id == crown, "No Crown or Power is awarded during search")

func check_slots() -> void:
	var board = game.get_node("EventBoard")
	var first := card("hidden_resources")
	var second := card("gift_to_fools")
	game.event_discard.clear()
	game.active_events = [[first], [], []]
	game.event_decks[1].assign([second])
	preferred.prophecy_slot = "slot:0"
	await effects([{"type": "prophecy"}], mage_context())
	expect(game.active_events[0] == [first, second] and game.event_discard.is_empty(), "Prophecy stacks without ejecting a card")
	expect(game.get_active_event_effects("mage_enters_cell_gain_power").size() == 1 and ForgottenRules.event_count(game) == 2, "Covered Event is active and counts")
	expect(game.black_rose_power == 0 and game.crown_owner_id == 0, "Prophecy placement ignores printed Power and Crown")
	board.refresh_event_slots(false)
	var bottom: Button = board._event_views[first.id]
	var top: Button = board._event_views[second.id]
	expect(top.get_parent() == bottom.get_parent() and top.position.x > bottom.position.x and top.position.y > bottom.position.y, "Two offset faces in the same slot")
	top.pressed.emit()
	var preview = game._reference_card_preview()
	expect(preview.pile_cards.size() == 2 and preview.pile_cards[0].id == second.id and preview.root.visible, "Click opens the real slot, top first")
	preview._browse_pile(1)
	expect(preview.pile_index == 1 and preview.pile_cards[1].id == first.id, "Buried card is browsable")
	preview.hide_preview()
	game.shift_active_events()
	expect(game.active_events[1] == [first, second] and bottom.get_parent() == board.get_node("ActiveEvent2"), "Advance carries the whole stack")
	expect(bottom.get_meta("slide").is_running() and bottom.position != Vector2.ZERO, "Card visibly starts at its old position")
	await create_timer(0.65).timeout
	expect(bottom.position.is_equal_approx(Vector2.ZERO) and top.position.x > 0, "Slide lands in the printed sockets with the offset intact")
	expect(game.place_event_on_board(card("rebirth_at_sunset")), "Regular draw pushes an occupied slot")
	expect(game.active_events[2] == [first, second] and game.active_events[1] == [card("rebirth_at_sunset")], "A pushed stack stays in order")
	game.shift_active_events()
	expect(game.event_discard == [first, second] and game.black_rose_power == second.discard_power, "III pays discard Power for each departing card exactly once")
	top.pressed.emit()
	expect(preview.pile_cards.size() == 2 and preview.pile_cards[0].id == second.id, "Discard pile opens with the newest Event first")
	preview._browse_pile(1)
	expect(preview.pile_cards[preview.pile_index].id == first.id, "Older discard is browsable")
	preview.hide_preview()

func check_payments() -> void:
	game.active_events = [[card("hidden_resources"), card("gift_to_fools")], [], [card("puppeteer"), card("rebirth_at_dawn")]]
	game.event_discard.clear()
	var context := mage_context()
	expect(not OracleRules.prepare_revelation(game, 0, {"revelation": true}, context), "Revelation requests physical cards")
	expect(game.pending_input.options.size() == 4, "All four Events across two slots can be selected")
	game.submit_effect_choice(0, ["event:hidden_resources", "event:puppeteer"])
	expect(OracleRules.prepare_revelation(game, 0, {"revelation": true}, context) and context.revelation_count == 2, "Revelation counts exactly two chosen cards")
	expect(game.active_events[0] == [card("gift_to_fools")] and game.active_events[2] == [card("rebirth_at_dawn")], "Selecting covered cards leaves other cards in their slots")
	game.active_events = [[card("hidden_resources"), card("gift_to_fools")], [], [card("puppeteer"), card("rebirth_at_dawn")]]
	game.event_discard.clear()
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "context": mage_context(),
		"effects": [{"type": "discard_events_for_effect", "amount": 3, "effects": [{"type": "gain_power", "amount": 1}]}]})
	expect(game.submit_effect_choice(0, "discard"), "Thirst for Knowledge payment accepted")
	expect(game.submit_effect_choice(0, ["event:hidden_resources", "event:puppeteer", "event:rebirth_at_dawn"]), "May choose three of four Events")
	await drive()
	expect(EventTrack.all_cards(game.active_events) == [card("gift_to_fools")] and game.event_discard.size() == 3, "Payment preserves the fourth Event")

func run_to_next_action() -> void:
	for step in 240:
		if game.waiting_for_player_input:
			var req: Dictionary = game.pending_input
			if req.type == "action_activation_step": return
			if req.type == "effect_choice":
				var options: Array = req.board_options if req.board_only else req.options
				game.submit_effect_choice(req.player_index, options[0].token)
			else:
				expect(false, "Unexpected decision " + str(req.type))
				return
		else: game.process_resolution_stack()
		await process_frame
	expect(false, "Next Action missing")

func choose_action(kind: String) -> bool:
	for option in game.pending_input.get("options", []):
		if option.get("action", {}).get("type") == kind:
			return game.submit_action_activation_step(0, option.token)
	return false

func check_pneuma() -> void:
	for first_action in [true, false]:
		reset_case()
		game.school_libraries["oracle"] = [game.spell_database.get_spell("omphalos"), game.spell_database.get_spell("poisoned_words")]
		game.players[0].ready_spells.assign([ReadySpellState.new(game.spell_database.get_spell("pneuma"), false)])
		game.event_decks[1].assign([card("gift_to_fools")])
		game.current_phase_play_order.assign([0, 1, 2, 3])
		game.action_phase_cursor = 1
		game._start_stepwise_action_activation(0)
		if not first_action:
			expect(choose_action("explore"), "Explore consumes the first Action")
			await run_to_next_action()
		expect(choose_action("spell"), "Pneuma is a legal numbered Spell")
		await run_to_next_action()
		expect(game.players[0].hand.size() == 1, "Pneuma completes the Library choice")
		if first_action:
			expect(game.pending_input.player_index == 0 and game.pending_input.actions_remaining == 1, "Pneuma first leaves a second Action")
		else:
			expect(game.pending_input.player_index == 1 and game.pending_input.actions_used == 0, "Explore then Pneuma passes to the next Mage")

func check_avatar_turn(seats: int) -> void:
	game = load("res://game.tscn").instantiate()
	game.player_count = seats
	game.enable_beta_hud = false
	game.run_tests_on_ready = true
	game.auto_start_game_flow = false
	game.avatar_selection = {"id": "possessed", "difficulty": "apprentice"}
	root.add_child(game)
	for i in 4: await process_frame
	var avatar_id: int = game.avatar.player_index
	game.current_phase = game.PHASE_ACTION
	game.current_phase_play_order.assign(range(seats))
	game.crown_owner_id = 0
	locate(0, "black_rose")
	locate(avatar_id, "black_rose")
	var command = game.spell_database.get_spell("possessed_tomb_reinforcements")
	var reaction = game.spell_database.get_spell("possessed_revenge_of_the_thorn")
	for before in [0, 2]:
		game.clear_player_input()
		game.resolution_stack.clear()
		game._reset_stepwise_action_activation()
		game.avatar.commands_used = before
		game.avatar.active_deck().assign([command, reaction])
		game.players[avatar_id].memories.clear()
		game.players[0].available_physical_actions = 2
		game.deal_damage(0, avatar_id, 1, "physical")
		await drive()
		expect(game.avatar.commands_used == before + 1 and game.players[avatar_id].memories == [reaction], "%d seats: reaction spends one Command immediately" % seats)
		game.action_phase_cursor = avatar_id
		game.advance_action_phase()
		await run_to_next_action()
		expect(game.players[avatar_id].memories.has(command) == (before == 0), "%d seats: next activation follows remaining budget" % seats)
		expect(game.pending_input.player_index == 0 and game.avatar.commands_used == mini(3, before + 2), "%d seats: turn returns to the Mage in order" % seats)
	game.queue_free()
	await process_frame
