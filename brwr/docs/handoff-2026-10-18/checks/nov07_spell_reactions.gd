extends "res://docs/handoff-2026-10-18/checks/playtest.gd"

const BoardProjection = preload("res://network_projection.gd")

func run() -> void:
	game = await make_game(4)
	await check_hieroglyphics(false)
	await check_hieroglyphics(true)
	await check_duplicate_jinx()
	await check_pain(false)
	await check_pain(true)
	await check_pain_on_guarded_target()
	await check_peak()
	await check_peak_evocation()
	await check_entropy()
	await check_entropy_sources()
	await check_deferred_last_damage()
	print("NOV07 SPELL REACTIONS: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)

func check_hieroglyphics(dark: bool) -> void:
	reset_case()
	var neighbors: Array = game._beta_adjacent_room_ids("garden")
	var start: String = neighbors[0]
	var finish: String = neighbors[1]
	locate(0, start if dark else "garden")
	locate(1, start)
	locate(2, "garden")
	locate(3, finish)
	game.players[1].mage.damage_cubes.assign([-1, -1, -1, -1, -1, -1])
	await cast("cursed_hieroglyphics", dark)
	preferred["explore_destination"] = "room:" + finish
	game.perform_explore_action(1, ["garden", finish])
	await drive()
	expect(game.players[1].mage.room_id == finish, "Explore completes its second movement")
	var state: Dictionary = BoardProjection.build(game, 3)
	for index in [1, 2]:
		expect(game.players[index].mage.damage_cubes.count(0) == 2, "Trap deals two Damage in Garden")
		expect(game.players[index].mage.jinxes.size() == 1, "Trap assigns one Jinx to each opposing Mage in Garden")
		expect(state.players[index].mage.jinxes.size() == 1, "Remote observer sees the Jinx after Explore")
		if state.players[index].mage.jinxes.size() == 1:
			var item := ForgottenAttachments.definition("jinxes", state.players[index].mage.jinxes[0].id)
			expect(state.public_action_log.any(func(line): return line.contains("%s receives the Jinx %s" % [game.player_display_name(index), item.name])), "Public log identifies the actual Jinx and recipient")
	expect(game.players[0].mage.jinxes.is_empty() and game.players[3].mage.jinxes.is_empty(), "Caster and Mage outside Garden receive no Jinx")

func check_duplicate_jinx() -> void:
	reset_case()
	locate(0, "arena")
	var start: String = game._beta_adjacent_room_ids("garden")[0]
	locate(1, start)
	# Pin the draw without bypassing the Trap: copies of just one name remain.
	for jinx in ForgottenAttachments.database().jinxes:
		var owners: Array = [1] if jinx.id == "slowness" else [0, 2, 3].slice(0, int(jinx.copies))
		for owner in owners:
			game.players[owner].mage.jinxes.append({"id":jinx.id, "progress":0})
	var before: Array = game.players[1].mage.jinxes.map(func(jinx): return jinx.id)
	await cast("cursed_hieroglyphics", false)
	game.perform_explore_action(1, ["garden"])
	await drive()
	expect(game.players[1].mage.jinxes.map(func(jinx): return jinx.id) == before, "A duplicate draw neither adds a second copy nor redraws")
	expect(game.public_action_log.any(func(line): return line.contains("already has Slowness")), "Duplicate Jinx draw reports its name and outcome")
	for owner in [0, 2]:
		game.players[owner].mage.jinxes.append({"id":"slowness", "progress":0})
	await effects([{"type":"assign_jinx"}], mage_context(1))
	expect(game.public_action_log.back().contains("No Jinx cards remain"), "A depleted deck reports the actual outcome")

func check_pain(redirect: bool) -> void:
	reset_case()
	var room: String = game._beta_adjacent_room_ids("arena")[0]
	for i in [1, 2, 3]:
		locate(i, "arena")
	locate(1, room)
	var card: SpellCardState = game.spell_database.get_spell("cross_and_delight")
	var ready := ReadySpellState.new(card, false)
	game.cast_ready_spell_state(0, ready, {"target_room_id":room})
	for i in 30:
		if game.waiting_for_player_input: break
		await process_frame
	expect(game.pending_input.get("choice_kind") == "succubus_redirect" and game.pending_input.get("player_index") == 0, "Caster chooses where to take Pain before the Succubus activates")
	if game.pending_input.get("choice_kind") == "succubus_redirect":
		var token := "succubus:0:0" if redirect else "keep_damage"
		expect(game.pending_input.options.any(func(o): return o.token == "keep_damage" and o.player_index == 0), "Pain visibly offers the caster's Mage")
		expect(game.submit_effect_choice(0, token), "Caster may give Pain to Succubus or keep it")
	await drive()
	expect(game.players[0].evocations.size() == 1, "Cross and Delight summoned one Succubus")
	if not game.players[0].evocations.is_empty():
		expect(game.players[0].evocations[0].damage_cubes.count(-1) == int(redirect), "Succubus only takes redirected Black Rose Damage")
	expect(game.players[0].mage.damage_cubes.count(-1) == int(not redirect), "Caster takes exactly the Pain they kept")
	expect(game.players[1].mage.damage_cubes.count(-1) == 0, "Other Mage in the summon Room takes no Pain")
	expect(game.public_action_log.any(func(line): return line.contains("Pain") and line.contains("Target: " + game.player_display_name(0))), "Pain history names the caster rather than the summon Room")

func check_pain_on_guarded_target() -> void:
	reset_case()
	var room: String = game._beta_adjacent_room_ids("arena")[0]
	var immune: EvocationState = game.summon_evocation(1, "albedo", room)
	var context := {"game":game, "caster_id":0, "caster_room_id":"arena", "target_room_id":room,
		"target_evocation":immune, "spell_target_type":"evocation", "target_model_type":"evocation"}
	await effects([{"type":"pain", "amount":1}, {"type":"damage", "amount":3}], context)
	expect(game.players[0].mage.damage_cubes == [-1] and immune.damage_cubes.is_empty(), "A primary target's Spell immunity does not cancel the caster's Pain")
	expect(context.target_evocation == immune and context.target_room_id == room, "Pain preserves the target of later sentences")

func check_peak() -> void:
	reset_case()
	var primary_room: String = game._beta_adjacent_room_ids("arena")[0]
	var far_room := ""
	for room in game.room_id_by_coord.values():
		if not game.is_room_within_effect_range(primary_room, room, 1):
			far_room = room
			break
	locate(1, primary_room)
	locate(2, primary_room)
	locate(3, far_room)
	game.players[0].mage.damage_cubes.assign([-1, -1, -1, -1])
	var ev: EvocationState = game.summon_evocation(1, "colossus", primary_room)
	var card: SpellCardState = game.spell_database.get_spell("peak_of_agony")
	game.cast_ready_spell_state(0, ReadySpellState.new(card, true), {"target_model_type":"mage", "target_player_index":1})
	var options: Array = game.pending_input.get("options", [])
	expect(options.any(func(o): return o.get("player_index", -1) == 2), "Second effect offers a nearby different Mage")
	expect(options.all(func(o): return o.get("player_index", -1) not in [0, 1, 3]), "Second effect excludes caster, primary Mage and out-of-range Mage")
	var targets: Array = options.filter(func(o): return o.get("owner_id", -1) == 1 and o.get("evocation_index", -1) == 0)
	expect(targets.size() == 1, "Second effect offers a different eligible Evocation")
	if targets.size() == 1:
		game.submit_effect_choice(0, targets[0].token)
	await drive()
	expect(game.players[1].mage.damage_cubes.count(0) == 3, "Primary target takes 3 Damage")
	expect(ev.damage_cubes.count(0) == 2, "Secondary model takes 1 Damage per 2 on the caster")

func check_peak_evocation() -> void:
	reset_case()
	var room: String = game._beta_adjacent_room_ids("arena")[0]
	var beyond := ""
	for next_room in game._beta_adjacent_room_ids(room):
		if not game.is_room_within_effect_range("arena", next_room, 1):
			beyond = next_room
			break
	expect(not beyond.is_empty(), "Fixture has a second target one step from the Evocation but out of range of the caster")
	locate(2, beyond)
	game.players[0].mage.damage_cubes.assign([-1, -1, -1, -1, -1, -1, -1, -1])
	var primary: EvocationState = game.summon_evocation(1, "colossus", room)
	var card: SpellCardState = game.spell_database.get_spell("peak_of_agony")
	game.cast_ready_spell_state(0, ReadySpellState.new(card, true), {"target_model_type":"evocation", "target_evocation":primary})
	var options: Array = game.pending_input.get("options", [])
	expect(options.all(func(o): return o.get("token") != "evocation:1:0" and o.get("player_index", -1) != 0), "Primary Evocation and caster are both excluded")
	expect(options.any(func(o): return o.get("player_index", -1) == 1), "Controller of the first Evocation remains a different Model")
	expect(not game.submit_effect_choice(0, "mage:0"), "Host rejects a forged caster target")
	expect(game.submit_effect_choice(0, "mage:2"), "Range is measured from the primary Evocation")
	await drive()
	expect(primary.damage_cubes.count(0) == 3 and game.players[2].mage.damage_cubes.count(0) == 3, "Secondary damage is capped at three")

func check_entropy() -> void:
	reset_case()
	var cards: Array[SpellCardState] = []
	for slot in ["I", "II"]:
		var card: SpellCardState = game.clone_spell_card(game.spell_database.get_spell("entropy"))
		cards.append(card)
		game._ensure_player_board_spell_slots(0)[slot] = {"spell":card, "state":"prepared", "use_dark_side":true}
		game.cast_ready_spell_state(0, ReadySpellState.new(card, true))
		await drive()
	game.players[2].mage.health = 1
	game.players[3].mage.health = 1
	game.deal_damage(1, 2, 1, "physical_attack")
	var options: Array = game.pending_input.get("options", [])
	expect(options.size() == 2 and options[0].slot_id != options[1].slot_id, "First lethal hit offers both distinct Entropy slots")
	if options.size() != 2: return
	game.submit_trigger_decision(0, options[0].queue_index)
	expect(game.pending_input.get("type") == "trigger_decision" and game.pending_input.options.size() == 1, "Second copy may pass on the first lethal hit")
	if game.pending_input.get("type") == "trigger_decision":
		game.submit_trigger_decision(0, -1)
	await drive()
	expect(game.players[2].mage.in_cell, "First defeat completed")
	expect(game.players[0].active_spells.size() == 1 and game.players[0].active_spells[0].spell == cards[1], "Passing leaves the other physical copy armed")
	game.deal_damage(1, 3, 1, "spell")
	options = game.pending_input.get("options", [])
	expect(options.size() == 1 and options[0].get("slot_id") == "II", "Next lethal hit offers the passed Entropy again")
	expect(game.pending_input.get("prompt", "").contains(game.player_display_name(3)), "New trigger names the new victim")
	await drive()
	expect(game.players[3].mage.in_cell and game.players[0].active_spells.is_empty(), "Second copy resolves on the next victim")

func check_entropy_sources() -> void:
	reset_case()
	await cast("entropy", true)
	var attacker: EvocationState = game.summon_evocation(1, "cadaver", "arena")
	for source in ["evocation", "black_rose", "owner"]:
		locate(2, "arena")
		game.players[2].mage.health = 1
		var source_id := 1 if source == "evocation" else (-1 if source == "black_rose" else 0)
		game.deal_damage(source_id, 2, 1, "evocation_attack" if source == "evocation" else "spell", [], attacker if source == "evocation" else null)
		await drive()
		expect(game.players[2].mage.in_cell and game.players[0].active_spells.size() == 1, "Non-qualifying last Damage leaves Entropy armed: " + source)
	expect(decisions.all(func(r): return r.type != "trigger_decision"), "Only another Mage can trigger Entropy Dark")

func check_deferred_last_damage() -> void:
	reset_case()
	await cast("entropy", true)
	game.players[2].mage.health = 2
	# Two sources reach the same period. Only the second one placed the last cube.
	var sentence := {"sentence_damage_frames":[]}
	game.active_effect_context = sentence
	game.deal_damage(0, 2, 1, "spell")
	game.deal_damage(1, 2, 1, "spell")
	game.active_effect_context = {}
	expect(sentence.sentence_damage_frames.size() == 2, "Both Damage receipts wait for the end of the sentence")
	while not sentence.sentence_damage_frames.is_empty():
		DeathEffectResolver.finish_sentence(game, sentence)
		await drive()
	expect(decisions.any(func(d): return d.type == "trigger_decision"), "Entropy reacts to the actual last cube even when an earlier hit shares the sentence")
	expect(game.players[0].active_spells.is_empty() and game.players[2].mage.in_cell, "Destiny resolves before the deferred defeat")
