extends "res://docs/handoff-2026-10-18/checks/playtest.gd"

func run() -> void:
	game = load("res://game.tscn").instantiate()
	game.player_count = 2
	game.avatar_selection = {"id":"possessed", "difficulty":"apprentice"}
	game.enable_beta_hud = false
	game.run_tests_on_ready = true
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	root.add_child(game)
	await process_frame
	await process_frame
	reset_case()
	var citrine := QuestState.new(game.quest_database.get_quest("citrine_star"), 0)
	game.players[0].active_quests.append(citrine)
	preferred["druidic_branch"] = "branch:druidic_branch:summon"
	await cast("pact_of_the_jaws", false)
	expect(not citrine.completed, "Contingency outside Observatory leaves Citrine Star active")
	locate(0, "observatory")
	await cast("pact_of_the_jaws", false)
	expect(citrine.completed, "Contingency resolved in Observatory completes Citrine Star")
	expect(game.ReferenceCardPreview.card_texture("quests", "extinct_sun").resource_path == "res://assets/quests/restored/extinct_sun.png" and game.ReferenceCardPreview.quest_progress_centers("extinct_sun", Vector2(1024,1536)).size() == 3, "Extinct Sun loads its restored art and three cube positions")
	reset_case()
	locate(0, "pleasures_room")
	var task: Dictionary = game.quest_database.get_quest("purple_star").task
	for spell_type in ["combat", "contingency", "trap", "protection"]:
		expect(game.quest_manager._task_matches(game, 0, task, {"type":"spell_resolved", "caster_room_id":"pleasures_room", "spell_type":spell_type, "spell_element":"air"}) == (spell_type in ["combat", "contingency"]), "Purple Star checks type " + spell_type)
	var purple := QuestState.new(game.quest_database.get_quest("purple_star"), 0)
	game.players[0].active_quests.append(purple)
	locate(1, "pleasures_room")
	game.summon_evocation(0, "pestis", "pleasures_room")
	await cast("proliferate", false)
	expect(purple.completed, "Proliferate Light in Pleasures Room completes Purple Star")
	expect(game.ReferenceCardPreview.card_texture("quests", "invisible_sun").resource_path == "res://assets/quests/restored/invisible_sun.png", "Invisible Sun selects restored artwork")
	game.forced_school_ids.assign(["pestilence", "oracle"])
	game.select_active_schools()
	expect(game.active_school_ids.has("pestilence") and game.active_school_ids.has("oracle"), "Forced Schools are included")
	expect(game.active_school_ids.size() == 6, "Exactly six active Schools")
	reset_case()
	locate(0, "arena")
	var own = game.summon_evocation(0, "cadaver", "arena")
	var enemy = game.summon_evocation(1, "cadaver", "arena")
	var pandemic: Dictionary = game.spell_database.get_spell("pandemic").dark_side.effects[2]
	var options: Array = SchoolEffects.model_options(game, pandemic, {"game":game, "caster_id":0, "target_room_id":"arena", "spell_target_type":"room"})
	expect(options.any(func(o): return o.value.get("evocation") == own), "Pandemic can remove own Evocation")
	expect(options.any(func(o): return o.value.get("evocation") == enemy), "Pandemic can remove enemy Evocation")
	preferred["school_model"] = "evocation:0:0"
	await cast("pandemic", true)
	expect(not game.is_evocation_in_play(own), "Pandemic Dark removes explicitly selected own Cadaver")
	preferred.erase("school_model")
	for source_id in ["cadaver", "bellum"]:
		reset_case()
		var origin: String = game._beta_adjacent_room_ids("sanctuary")[0]
		locate(0, origin)
		own = game.summon_evocation(0, source_id, origin)
		enemy = game.summon_evocation(1, "colossus", "sanctuary")
		var plans: Array = game._beta_evocation_activation_plans(own, 0)
		if source_id == "cadaver":
			var attacks: Array = plans.filter(func(plan): return plan.context.get("evocation_target_model_type") == "evocation" and plan.context.get("evocation_attack_timing") == "after" and plan.path == ["sanctuary"])
			expect(not attacks.is_empty(), source_id + " offers attack after move")
			if not attacks.is_empty():
				game.activate_evocation(own, 0, attacks[0].context.duplicate(true))
		else:
			preferred["order"] = "after"
			preferred["attack_target"] = "evocation:1:0"
			move_rooms.assign(["sanctuary", "sanctuary"])
			game.activate_evocation(own, 0, {"extended_activation":true})
		await drive()
		expect(enemy.get_damage() > 0 or not game.is_evocation_in_play(enemy), source_id + " damages Avatar Evocation after movement")
	reset_case()
	var first = game.summon_evocation(0, "pestis", "arena")
	var second = game.summon_evocation(0, "pestis", "arena")
	expect(first.get_token_number() == 1 and second.get_token_number() == 2, "Pestis displays copy numbers from one")
	reset_case()
	locate(0, "arena")
	locate(1, "arena")
	var room = game.get_room_by_id("arena")
	room.add_instability_cube(1, false)
	room.add_instability_cube(1, false)
	await cast("endemia", false)
	expect(room.get_instability_by_owner(0) == 2, "Endemia Light replaces both eligible cubes")
	for dark in [false, true]:
		reset_case()
		locate(0, "arena")
		locate(1, "arena")
		await cast("contaminate", dark)
		expect(room.get_instability_by_owner(0) == 1, "Contaminate places its printed Instability on either side")
	reset_case()
	locate(0, "arena")
	locate(1, "crypt")
	var pest = game.summon_evocation(0, "pestis", "arena")
	decisions.clear()
	game.activate_evocation(pest, 0, {"evocation_attack_timing":"before", "evocation_move_room_ids":[]})
	await drive()
	expect(decisions.is_empty(), "Pestis skips attack prompts in an empty Room")
	for loss in ["defeated", "removed"]:
		reset_case()
		var lost = game.summon_evocation(1, "nigredo", "crypt")
		game.summon_evocation(0, "nigredo", "arena")
		game.summon_evocation(0, "nigredo", "arena")
		expect(game.get_available_evocation_copies("nigredo") == 0, "Last Nigredo is on the Lodge")
		await cast("stone_phoenix", true)
		if loss == "defeated":
			game.deal_damage_to_evocation(0, lost, 4)
		else:
			game.effect_resolver._remove_evocation(game, lost, {"game":game,"caster_id":0})
		await drive()
		expect(not game.is_evocation_in_play(lost) and game.players[0].evocations.any(func(e): return e.evocation_id == "nigredo" and e.room_id == "crypt"), "Stone Phoenix resummons last copy after " + loss)
		expect(decisions.any(func(d): return d.get("choice_kind") == "evocation_activation_plan"), "Stone Phoenix activates new copy after " + loss)
	reset_case()
	own = game.summon_evocation(0, "cadaver", "arena")
	enemy = game.summon_evocation(1, "colossus", "arena")
	var before_plans: Array = game._beta_evocation_activation_plans(own, 0).filter(func(p): return p.context.get("choose_move_after_attack", false) and p.context.get("evocation_target_model_type") == "evocation")
	expect(before_plans.size() == 1, "Attack first offers one decision per target")
	game.activate_evocation(own, 0, before_plans[0].context)
	expect(enemy.get_damage() == 2 and own.room_id == "arena" and game.pending_input.get("context_key") == "post_attack_path", "Attack resolves before selecting a path")
	var destination: String = game._beta_adjacent_room_ids("arena")[0]
	var paths: Array = game.pending_input.options.filter(func(o): return o.path == [destination])
	expect(game.submit_effect_choice(0, paths[0].token) and own.room_id == destination, "Post-attack path moves the attacker")
	for branch in ["0", "1"]:
		reset_case()
		var totem = game.summon_evocation(0, "totem", "arena")
		locate(0, "arena" if branch == "0" else destination)
		game.players[0].mage.damage_cubes.append(1)
		game.players[1].take_cubes(1)
		preferred["school_model"] = "mage:0"
		preferred["chaos_branch"] = "branch:chaos_branch:" + branch
		game.activate_evocation(totem, 0, {})
		await drive()
		expect(game.players[0].mage.damage_cubes == ([] if branch == "0" else [0]), "Totem resolves chosen effect on its controller, branch " + branch)
		var far_rooms: Array = game.room_id_by_coord.values().filter(func(id): return not game.is_room_within_effect_range("arena", id, 1))
		locate(0, far_rooms[0])
		var totem_effect: Dictionary = totem.definition.abilities[0].effects[0]
		var targets := SchoolEffects.model_options(game, totem_effect, {"caster_id":0, "source_evocation":totem})
		expect(not targets.any(func(o): return o.token == "mage:0"), "Totem range measured from its own Room")
	print("NOV13 CHECKS: %d; FAILURES: %d" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
