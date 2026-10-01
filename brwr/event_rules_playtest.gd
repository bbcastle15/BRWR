extends SceneTree

var failures := 0
var checks := 0
var covered: Dictionary = {}
var game

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func reset() -> void:
	check(game.resolution_stack.is_empty(), "Previous event must have finished")
	game.clear_player_input()
	game.resolution_stack.clear()
	game.active_events.assign([null, null, null])
	game.current_phase = game.PHASE_ACTION
	game.current_moon = 3
	game.crown_owner_id = 0
	game.black_rose_power = 0
	game.black_rose_trophies.clear()
	game.get_node("EventBoard").black_rose_cube_count = 30
	for p in game.players:
		p.power = 5
		p.available_cubes = 25
		p.mage.damage_cubes.clear()
		p.mage.in_cell = false
		p.mage.room_id = "forge"
		p.mage.room_coord = game.room_id_to_coord("forge")
		p.evocations.clear()
		p.active_spells.clear()
		p.active_quests.clear()
		p.completed_quests.clear()
		p.trophies.clear()
		p.hand.clear()
		p.revealed_spells.clear()
	for room_id in game.room_id_by_coord.values():
		var room = game.get_room_by_id(room_id)
		room.clear_instability()
		room.flipped = false

func resolve(id: String) -> void:
	covered[id] = true
	check(game.resolve_event(game.event_database.events[id], {"play_order": [0, 1], "drawing_player_index": 0}), id + " must dispatch")

func active(id: String) -> void:
	covered[id] = true
	game.active_events.assign([game.event_database.events[id], null, null])

func choose(token: String) -> void:
	check(game.waiting_for_player_input, "Expected choice: " + token)
	if game.waiting_for_player_input:
		check(game.submit_effect_choice(game.pending_input.player_index, [token]), "Choice must be accepted: " + token)

func first_token() -> String:
	return str(game.pending_input.get("options", [{}])[0].get("token", ""))

func quest(owner: int, solved: bool) -> QuestState:
	var q := QuestState.new(game.quest_database.quests.values()[0], owner)
	q.complete()
	if solved:
		q.solve()
	game.players[owner].completed_quests.append(q)
	return q

func run() -> void:
	game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(8):
		await process_frame
	reset()
	active("hidden_resources")
	game.place_mage_in_cell(0)
	check(game.players[0].power == 6, "Hidden Resources Cell reward")
	reset()
	var evocation = game.summon_evocation(0, "nigredo", "forge")
	var enemy = game.summon_evocation(1, "nigredo", "forge")
	resolve("black_thorns")
	check(evocation.get_damage() == 2 and enemy.get_damage() == 2, "Black Thorns hits every Evocation")
	for id in ["rebirth_at_sunset", "rebirth_at_noon", "rebirth_at_dawn"]:
		reset()
		resolve(id)
		var colors: Array = game.event_database.events[id].effects[0].colors
		for room_id in game.room_id_by_coord.values():
			var room = game.get_room_by_id(room_id)
			check(room.get_instability_count() == (1 if room.room_data.color in colors else 0), id + " exact colors: " + room_id)
	for id in ["awakening", "midnight_rebirth"]:
		reset()
		resolve(id)
		check(game.get_room_by_id("black_rose").get_instability_count() == (5 if id == "awakening" else 2), id + " cube count")
	reset()
	resolve("gift_to_fools")
	check(game.pending_input.player_index == 0, "Gift starts with first Mage")
	choose("school:" + game.active_school_ids[0])
	check(game.players[0].hand.size() == 1 and game.pending_input.player_index == 1, "Gift draws before next Mage")
	choose("decline")
	check(game.players[1].hand.is_empty(), "Gift decline")
	reset()
	game.players[0].mage.in_cell = true
	resolve("dislocation")
	check(game.pending_input.options.size() == game.room_id_by_coord.size() + 1, "Dislocation offers all rooms")
	choose("room:black_rose")
	choose("decline")
	check(not game.players[0].mage.in_cell and game.players[0].mage.room_id == "black_rose", "Dislocation places from Cell anywhere")
	reset()
	resolve("a_hard_lesson")
	check(game.players[0].power == 4 and game.players[1].power == 5, "Hard Lesson resolves per Mage")
	check(not game.submit_effect_choice(0, ["room:invalid"]), "Invalid event choice rejected")
	choose(first_token())
	check(game.players[1].power == 4, "Hard Lesson next Mage charged once")
	choose(first_token())
	check(game.players[0].power == 4 and game.players[1].power == 4, "Hard Lesson no repeated costs")
	reset()
	resolve("undead_army")
	choose("summon")
	choose("decline")
	check(game.players[0].evocations.size() == 1 and game.players[1].evocations.is_empty(), "Undead Army optional summon")
	check(game.players[0].evocations[0].room_id == "forge", "Undead Army range zero")
	game.summon_evocation(0, "nigredo", "forge")
	var replaced = game.summon_evocation(0, "succubus", "forge")
	resolve("undead_army")
	choose("summon")
	check(game.pending_input.choice_kind == "event_replace_evocation", "Full slots must offer replacement")
	choose("evocation:0:2")
	choose("decline")
	check(game.players[0].evocations.size() == 3 and not replaced in game.players[0].evocations, "Undead Army replaces chosen Evocation")
	reset()
	active("puppeteer")
	resolve("puppeteer")
	evocation = game.summon_evocation(0, "cadaver", "forge")
	game.finalize_evocation_removal(evocation)
	game.emit_evocation_defeated_or_removed(evocation)
	check(game.get_room_by_id("forge").get_instability_count() == 1, "Puppeteer removal in Action")
	game.current_phase = game.PHASE_EVOCATION
	game._apply_puppeteer_after_evocation_loss("forge")
	check(game.get_room_by_id("forge").get_instability_count() == 1, "Puppeteer ignored outside Action")
	reset()
	active("black_overload")
	game.place_instability(0, "forge", 2)
	check(game.get_room_by_id("forge").instability_cubes == [0, 0, -1], "Black Overload once per placement")
	for id in ["abandonment", "battle", "knowledge", "clairvoyance", "growth", "instinct"]:
		reset()
		active(id)
		resolve(id)
		check(game.black_rose_power == 0, id + " passive at phase start")
		var color: String = game.event_database.events[id].effects[0].color
		var room_id: String = ""
		for candidate in game.room_id_by_coord.values():
			if game.get_room_by_id(candidate).room_data.color == color:
				room_id = candidate
				break
		game.process_room_activation_resolution({"step": "after_effects", "player_index": 0, "room_id": room_id})
		check(game.black_rose_power == 1, id + " matching room")
		game.current_phase = game.PHASE_BLACK_ROSE
		game.process_room_activation_resolution({"step": "after_effects", "player_index": 0, "room_id": room_id})
		check(game.black_rose_power == 1, id + " ignored outside Action")
	reset()
	resolve("illness")
	check(game.get_room_by_id("forge").get_instability_count() == 2, "Illness once per room")
	check(game.players[0].mage.in_cell and game.players[1].mage.in_cell, "Illness returns all Mages")
	reset()
	game.current_moon = 1
	resolve("vision")
	check(game.current_moon == 1, "Vision keeps Moon")
	check(game.players[0].active_quests[0].get_moon() == 3 and game.players[1].active_quests[0].get_moon() == 3, "Vision draws Third Moon")
	reset()
	var card = game.clone_spell_card(game.spell_database.spells.cross_and_delight)
	var other = game.clone_spell_card(card)
	game.players[0].hand.assign([card, other])
	resolve("wave_of_fatigue")
	choose("card:1")
	check(game.players[0].hand == [card] and other in game.players[0].memories, "Wave discards selected instance")
	check(game.players[1].power == 4 and game.players[0].power == 5, "Wave Power loss only if no card")
	reset()
	evocation = game.summon_evocation(0, "nigredo", "forge")
	resolve("revolt_of_the_servants")
	check(game.players[0].mage.get_damage() == evocation.strength and game.players[1].power == 4, "Revolt Strength or loss")
	reset()
	game.players[0].trophies.assign([1])
	resolve("renovation")
	choose("trophy:0")
	check(game.black_rose_trophies == [1] and game.players[0].trophies.is_empty(), "Renovation transfers trophy")
	check(game.get_room_by_id("forge").instability_cubes == [0, 0], "Renovation owner cubes")
	reset()
	quest(0, true)
	quest(1, false)
	resolve("reward_the_slothful")
	check(game.players[0].power == 6 and game.players[1].power == 5, "Reward distinguishes Solved and Completed")
	reset()
	var solved = quest(0, true)
	var completed = quest(0, false)
	resolve("manipulating_the_past")
	check(not solved in game.players[0].completed_quests and completed in game.players[0].completed_quests, "Past only discards Solved")
	check(game.players[1].power == 2, "Past loses three without Solved")
	reset()
	resolve("pledge")
	check(game.players[0].mage.get_damage() == 3 and game.players[1].mage.get_damage() == 3, "Pledge damages all Mages")
	reset()
	game.crown_owner_id = 1
	resolve("gold_to_the_king")
	check(game.players[1].power == 7 and game.players[0].power == 5, "Gold only Crown owner")
	reset()
	game.players[0].mage.damage_cubes.assign([1, -1, 1])
	game.players[1].mage.damage_cubes.assign([0, 0])
	resolve("false_mercy")
	check(game.players[0].mage.damage_cubes == [-1] and game.players[1].mage.damage_cubes == [-1, -1], "False Mercy heals non-BR, hits only without BR")
	reset()
	game.players[0].mage.damage_cubes.assign([1, -1, 1])
	game.players[1].mage.damage_cubes.assign([-1])
	resolve("woe")
	game.refresh_all_player_boards()
	for option in game.pending_input.options:
		check(game.show_board_target_choice(option, func(): pass), "Woe cubes must be clickable")
	game.clear_board_target_choices()
	choose("damage:1:1")
	check(game.players[0].mage.damage_cubes == [1, -1, -1], "Woe selected conversion")
	check(game.players[1].mage.damage_cubes == [-1, -1, -1], "Woe damage if none converted")
	check(game.get_node("EventBoard").black_rose_cube_count == 27, "Woe uses cube pool")
	reset()
	active("infinite_knowledge")
	var q = quest(0, false)
	game.quest_manager.finalize_quest_solve(game, 0, q)
	check(game.players[0].power == 7 + q.get_power_reward() and game.black_rose_power == 1, "Infinite Knowledge rewards")
	game.quest_manager.finalize_quest_solve(game, 0, q)
	check(game.black_rose_power == 1, "Infinite Knowledge no double reward")
	reset()
	evocation = game.summon_evocation(0, "nigredo", "forge")
	evocation.damage_cubes.assign([1, -1])
	game.event_decks[3] = [game.event_database.events.immortals]
	covered["immortals"] = true
	game.draw_event(0)
	check(evocation.damage_cubes.is_empty(), "Immortals heals on entry")
	check(game.deal_damage_to_evocation(1, evocation, 2) == 0 and evocation.get_damage() == 0, "Immortals immunity")
	game.discard_event(game.event_database.events.immortals, false)
	game.active_events.assign([null, null, null])
	game.deal_damage_to_evocation(1, evocation, 1)
	check(evocation.get_damage() == 1, "Immortals ends on leaving")
	reset()
	resolve("power_infusion")
	choose("accept")
	choose("decline")
	check(game.players[0].power == 3 and game.players[0].hand.size() == 1 and game.players[0].hand[0].forgotten, "Power Infusion pays once and draws Forgotten")
	check(game.players[1].power == 5, "Power Infusion decline")
	reset()
	active("dominion")
	game.deal_damage(0, 1, game.players[1].mage.health, "spell")
	check(game.black_rose_trophies == [1] and game.players[0].trophies.is_empty(), "Dominion takes trophy")
	for id in ["only_war", "only_peace"]:
		reset()
		active(id)
		var type: String = "contingency" if id == "only_war" else "combat"
		var test_spell := SpellCardState.new("event_test", "Event Test", "alchemy", {"type": type, "target": "self", "element": "fire", "effects": [{"type": "gain_power", "amount": 1}, {"type": "gain_power", "amount": 1}]}, {})
		game.players[0].quick_spell = ReadySpellState.new(test_spell, false)
		game.cast_quick_spell(0)
		check(game.players[0].mage.get_damage() == (2 if id == "only_war" else 1), id + " once after full Spell Effect")
		check(game.players[0].power == 7 and game.players[0].revealed_spells.size() == 1, id + " no replay after nested damage")
		game.current_phase = game.PHASE_EVOCATION
		var before: int = game.players[0].mage.get_damage()
		game._apply_event_after_spell(0, type)
		check(game.players[0].mage.get_damage() == before, id + " ignored outside Action")
	reset()
	active("assault")
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "effects": [{"type": "damage", "amount": 1}], "context": {"game": game, "caster_id": 0, "spell_type": "combat", "spell_target_type": "mage", "target_player_index": 1}})
	check(game.players[1].mage.get_damage() == 2, "Assault boosts Combat Spell damage")
	game.deal_damage(0, 1, 1, "fight")
	check(game.players[1].mage.get_damage() == 3, "Assault ignores physical damage")
	enemy = game.summon_evocation(1, "nigredo", "forge")
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "effects": [{"type": "damage", "amount": 1}], "context": {"game": game, "caster_id": 0, "spell_type": "combat", "spell_target_type": "evocation", "target_evocation": enemy}})
	check(enemy.get_damage() == 2, "Assault also boosts damage to Evocations")
	reset()
	game.event_decks[1] = [game.event_database.events.dislocation]
	game.event_decks[2] = [game.event_database.events.vision]
	game.event_decks[3] = [game.event_database.events.remembrance]
	covered["remembrance"] = true
	var count_before: int = game.event_discard.size()
	game.draw_event(0)
	check(game.pending_input.choice_kind == "event_room_destination", "Remembrance pauses for nested Instant")
	check(game.event_decks[2].size() == 1, "Remembrance waits before next draw")
	choose("decline")
	choose("decline")
	check(game.event_decks[2].is_empty() and game.current_moon == 3, "Remembrance keeps Moon")
	check(game.event_discard.size() == count_before + 3 and game.resolution_stack.is_empty(), "Nested Instants each discard once")
	reset()
	active("tribute_of_the_command")
	resolve("tribute_of_the_command")
	choose("decline")
	choose("decline")
	# Accept + full activation is covered by hand_targets_playtest.gd.
	reset()
	game.get_node("EventBoard").black_rose_cube_count = 0
	resolve("tribute_of_the_command")
	choose("accept")
	check(game.pending_input.player_index == 1 and game.pending_input.choice_kind == "event_tribute", "Tribute cannot activate if Damage cost was not paid")
	choose("decline")
	for type in ["trap", "protection"]:
		reset()
		active("only_peace" if type == "trap" else "only_war")
		var triggered := SpellCardState.new("event_trigger", "Event Trigger", "alchemy", {"type": type, "target": "self", "effects": [{"type": "gain_power", "amount": 1}, {"type": "gain_power", "amount": 1}]}, {})
		var state := ActiveSpellState.new(triggered, 0, false)
		game.players[0].active_spells.append(state)
		game.queue_resolution({"type": "trigger_spell", "active_spell": state, "event": GameEvent.new("test")})
		check(game.players[0].mage.get_damage() == (1 if type == "trap" else 2), "Event damage after triggered " + type)
		check(game.players[0].power == 7 and game.players[0].revealed_spells.size() == 1, "Triggered spell is not replayed")
	reset()
	active("immortals")
	evocation = game.summon_evocation(1, "nigredo", "forge")
	game.queue_resolution({"type": "damage", "step": "apply_redirect", "redirected_evocation": evocation, "amount": 2, "attacker_id": 0, "target_player_index": 1})
	check(evocation.get_damage() == 0, "Immortals also blocks redirected Damage")
	game.queue_resolution({"type": "evocation_damage", "step": "apply", "evocation": evocation, "amount": 2, "attacker_id": 0})
	check(evocation.get_damage() == 0, "Immortals blocks Damage queued before immunity")
	reset()
	game.players[0].power = 1
	game.players[1].power = 0
	resolve("power_infusion")
	check(not game.waiting_for_player_input and game.players[0].hand.is_empty(), "Power Infusion cannot pay partial cost")
	reset()
	game.current_phase_play_order.assign([1, 0])
	game.event_decks[3] = [game.event_database.events.power_infusion]
	game.draw_event(0)
	check(game.crown_owner_id == 0 and game.pending_input.player_index == 1, "New Crown does not change current phase order")
	choose("decline")
	choose("decline")
	game.current_phase_play_order.clear()
	reset()
	# Black Rose board events must complete before Quest draw/discard decisions.
	game.event_decks[3] = [game.event_database.events.gift_to_fools]
	game.resolve_black_rose_phase()
	check(game.pending_input.choice_kind == "event_choice" and game.players[0].active_quests.is_empty(), "Black Rose phase waits for Gift choices before Quests")
	choose("school:" + game.active_school_ids[0])
	check(game.players[0].active_quests.is_empty() and game.players[1].active_quests.is_empty(), "No Quest draw between Event choices")
	choose("decline")
	check(game.players[0].active_quests.size() == 1 and game.players[1].active_quests.size() == 1, "Quest step resumes after board Event")
	reset()
	active("gift_to_fools")
	evocation = game.summon_evocation(0, "nigredo", "forge")
	evocation.damage_cubes.assign([1, -1])
	game.event_decks[3] = [game.event_database.events.immortals]
	# Emulate entry from the Clean-up completion callback inside the live stack.
	game.processing_resolution_stack = true
	game.resolve_black_rose_phase()
	game.processing_resolution_stack = false
	game.process_resolution_stack()
	check(evocation.get_damage() == 0 and game.pending_input.choice_kind == "event_choice", "Always entry effect must precede board events even inside stack")
	choose("decline")
	choose("decline")
	check(covered.size() == game.event_database.events.size(), "Cover all 39 event IDs")
	check(game.resolution_stack.is_empty(), "Final event finished")
	print("EVENT COVERAGE: ", covered.size(), "/39 events; ", checks, " checks; ", failures, " failures")
	quit(0 if failures == 0 else 1)
