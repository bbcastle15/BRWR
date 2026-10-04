extends SceneTree

var game
var failures := 0
var checks := 0
var coverage: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func reset() -> void:
	game.clear_player_input()
	game.resolution_stack.clear()
	game.trigger_window_active = false
	game.trigger_window_stack.clear()
	game.trigger_window_queue.clear()
	game.processing_resolution_stack = false
	game.active_effect_context = {}
	game.current_phase = game.PHASE_ACTION
	game.current_phase_play_order.assign([0, 1, 2])
	game.crown_owner_id = 0
	game.black_rose_power = 0
	game.black_rose_trophies.clear()
	game.active_events = [null, null, null]
	game.player_board_spell_slots.clear()
	for player in game.players:
		for evocation in player.evocations.duplicate():
			game.finalize_evocation_removal(evocation)
		player.power = 0
		player.available_cubes = 25
		player.trophies.clear()
		player.mage.health = 11
		player.mage.damage_cubes.clear()
		player.mage.destiny_tokens.clear()
		player.mage.in_cell = false
		player.mage.room_id = "forge"
		player.mage.room_coord = game.room_id_to_coord("forge")
		player.active_spells.clear()
		player.revealed_spells.clear()
		player.ready_spells.clear()
		player.quick_spell = null
		player.active_quests.clear()
		player.completed_quests.clear()
	for room_id in game.room_id_by_coord.values():
		var room = game.get_room_by_id(room_id)
		for owner in room.instability_cubes.duplicate():
			room.remove_instability_cube(owner)
		room.flipped = false
	game.refresh_all_player_boards()

func damage(target: int, owner: int, amount: int) -> void:
	var taken: int = game.take_owner_cubes(owner, amount)
	game.players[target].mage.add_damage(owner, taken)

func destiny(target: int, owner: int, amount: int) -> void:
	game.effect_resolver.resolve_effect({"type": "assign_destiny", "amount": amount},
		{"game": game, "caster_id": owner, "target_player_index": target})

func cast(id: String, dark: bool = false, caster: int = 0, target: int = 1, room: String = "forge") -> void:
	var card: SpellCardState = game.clone_spell_card(game.spell_database.get_spell(id))
	if card.school_id == "death" or card.id == "consuming_soul":
		coverage[id + (":dark" if dark else ":light")] = true
	var context: Dictionary = {"target_room_id": room}
	if card.get_side(dark).target in ["mage", "model"]:
		context["target_player_index"] = target
		context["target_model_type"] = "mage"
	check(game.cast_ready_spell_state(caster, ReadySpellState.new(card, dark), context), "Cast accepted: " + id)

func drain(preferences: Dictionary = {}) -> void:
	for iteration in range(200):
		if not game.waiting_for_player_input:
			check(game.resolution_stack.is_empty(), "Resolution drained")
			return
		var request: Dictionary = game.pending_input
		var player: int = int(request.player_index)
		if request.type == "trigger_decision":
			check(game.submit_trigger_decision(player, int(request.options[0].queue_index)), "Trigger accepted")
			continue
		if request.type != "effect_choice":
			check(false, "Unexpected request: " + str(request.type))
			return
		var options: Array = request.options
		var key: String = str(request.context_key)
		var preferred: String = str(preferences.get(key, ""))
		if key == "destiny_count" and preferred.is_empty():
			preferred = "destiny:0"
		if key == "activation_plan" and preferred.is_empty():
			for option in options:
				if option.get("path", []).is_empty() and option.get("board_target", {}).is_empty():
					preferred = option.token
		var tokens: Array[String] = []
		if not preferred.is_empty():
			for option in options:
				if option.token == preferred:
					tokens.append(option.token)
			check(not tokens.is_empty(), "Choice offered: " + preferred)
		else:
			for i in range(mini(int(request.max_select), options.size())):
				tokens.append(options[i].token)
		check(game.submit_effect_choice(player, tokens), "Effect choice accepted: " + key)
	check(false, "Choice loop did not finish")

func emit(type: String, source: int) -> void:
	var event := GameEvent.new(type)
	event.source_player_index = source
	event.source_model_type = "mage"
	game.queue_resolution({"type": "game_event", "event": event})

func edge_cases() -> void:
	reset()
	var construct = game.summon_evocation(1, "nigredo", "forge")
	construct.add_damage(2, 3)
	var first = game.summon_evocation(1, "succubus", "forge")
	var second = game.summon_evocation(1, "succubus", "forge")
	cast("tearing")
	check(game.pending_input.get("player_index") == 1, "Defending Mage chooses Tearing removal")
	check(game.pending_input.get("options", []).size() == 2, "Tearing tests maximum Health, not remaining Health")
	var chosen: String = "remove:%d" % second.board_number
	check(not game.submit_effect_choice(0, [chosen]), "Caster cannot submit defender's choice")
	drain({"target_owned_evocation": chosen})
	check(game.is_evocation_in_play(construct) and game.is_evocation_in_play(first) and not game.is_evocation_in_play(second), "Chosen instance removed; other duplicates survive")
	reset()
	game.players[0].available_cubes = 0
	destiny(1, 0, 1)
	check(game.players[1].mage.destiny_tokens.is_empty(), "No unbacked Destiny when cube pool empty")
	reset()
	cast("annihilation", true)
	drain()
	check(game.players[1].mage.get_damage() == 0, "Annihilation Dark requires two Destiny")
	cast("dark_omens")
	drain()
	check(not game.players[1].mage.in_cell, "Automatic defeat requires three Destiny")
	destiny(1, 0, 1)
	cast("annihilation")
	drain()
	check(game.players[0].trophies.is_empty() and game.players[1].mage.destiny_tokens.size() == 2, "Annihilation does not count its newly assigned token for Trophy")
	reset()
	destiny(1, 0, 1)
	cast("lethal_touch", true)
	drain()
	check(game.players[1].mage.get_damage() == 0, "Unpaid Trophy cost produces no damage")
	game.players[0].trophies.append(2)
	cast("sacrificial_pyre", true)
	drain({"spent_trophy_index": "trophy:decline"})
	check(game.players[1].mage.get_damage() == 2 and game.players[0].trophies == [2], "Optional Trophy can be kept")
	reset()
	game.players[0].trophies.append(1)
	game.place_instability(1, "forge", 3)
	cast("martyrdom", true)
	drain()
	var forge = game.get_room_by_id("forge")
	check(forge.instability_cubes.count(0) == 3 and forge.instability_cubes.count(1) == 1, "One Trophy pays only first Martyrdom conversion")
	reset()
	game.place_instability(1, "forge", 2)
	cast("bone_shield", true)
	game.deal_damage(1, 0, 1)
	drain({"death_branch": "branch:1"})
	check(forge.instability_cubes == [0, 0], "Bone Shield Dark conversion branch preserves positions")
	reset()
	cast("bone_shield")
	cast("arcane_barrage", false, 1, 0)
	drain()
	check(game.players[0].mage.get_damage() == 6 and game.players[0].active_spells.size() == 1, "Bone Shield excludes Forgotten Spells")
	reset()
	cast("bone_shield")
	game.players[1].trophies.append(2)
	cast("martyrdom", false, 1)
	check(game.pending_input.get("choice_kind") == "trophy_cost", "No protection trigger before optional cost is paid")
	drain()
	check(game.players[0].mage.get_damage() == 0 and game.players[2].mage.get_damage() == 3, "Bone Shield protects only its Mage from an area Spell")
	reset()
	cast("bone_shield")
	for i in range(2):
		game.players[1].revealed_spells.append(RevealedSpellState.new(game.clone_spell_card(game.spell_database.get_spell("liquid_fire")), false))
	cast("marbling", false, 1)
	drain()
	check(game.players[0].mage.get_damage() == 0 and game.players[2].mage.get_damage() > 0, "Bone Shield catches global Special effects")
	reset()
	destiny(1, 0, 2)
	damage(1, 2, 6)
	damage(1, 0, 3)
	cast("annihilation", true)
	drain()
	check(game.players[1].mage.in_cell and game.players[0].power == 4 and game.players[2].power == 2, "Annihilation converts before lethal damage awards Power")
	check(game.players[0].available_cubes == 23, "Lethal conversion returns cubes, retaining two Destiny")
	reset()
	destiny(1, 0, 1)
	destiny(2, 0, 1)
	game.players[1].mage.health = 1
	game.players[2].mage.health = 1
	cast("consuming_soul")
	check(game.players[2].mage.is_defeated() and not game.players[2].mage.in_cell, "One sentence damages all Mages before resolving first defeat")
	drain()
	check(game.players[1].mage.in_cell and game.players[2].mage.in_cell, "Multiple defeats resolve without blocking")
	reset()
	destiny(1, 0, 3)
	cast("consuming_soul", true)
	drain({"death_branch": "branch:1"})
	check(game.players[1].mage.in_cell and game.players[0].trophies == [1, 1], "Consuming Soul automatic-defeat alternative")
	reset()
	destiny(1, 0, 3)
	damage(1, 2, 10)
	game.deal_damage(2, 1, 1)
	drain({"destiny_count": "destiny:3"})
	check(game.players[1].mage.destiny_tokens.is_empty() and game.players[0].available_cubes == 25, "All Destiny may resolve; their cubes return")
	reset()
	cast("dark_omens", true)
	game.place_mage_in_cell(0)
	drain()
	check(game.players[0].power == 1, "Dark Omens also counts its owner's Cell placement")
	game.place_mage_in_cell(0)
	drain()
	check(game.players[0].power == 1, "Already in Cell does not emit another placement")
	reset()
	cast("repentance", true)
	var evocation = game.summon_evocation(1, "cadaver", "forge")
	game.activate_evocation(evocation, 1, {"evocation_attack_timing": "before", "evocation_target_model_type": "mage", "evocation_target_player_index": 0, "evocation_move_room_ids": []})
	check(game.pending_input.get("type") == "trigger_decision", "Repentance sees Evocation damage")
	game.submit_trigger_decision(0, int(game.pending_input.options[0].queue_index))
	check(game.pending_input.get("choice_kind") == "evocation_activation_plan" and game.pending_input.player_index == 0, "Protected Mage chooses the new activation")
	var attack_owner: String = ""
	for option in game.pending_input.get("options", []):
		if option.get("board_target", {}).get("player_index", -1) == 1 and option.get("path", []).is_empty():
			attack_owner = option.token
			break
	check(not attack_owner.is_empty(), "New controller can target the Evocation's owner")
	drain({"activation_plan": attack_owner})
	check(game.players[1].mage.get_damage_from(0) == evocation.strength and evocation.owner_id == 1, "Controlled retaliation uses controller's cubes without changing ownership")

func run() -> void:
	game = load("res://game.tscn").instantiate()
	game.player_count = 3
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	game.game_seed = 1232
	root.add_child(game)
	await process_frame
	check(game.active_school_ids.has("death"), "Death selectable")
	check(game.school_libraries.death.size() == 36, "Death library has 36 distinct copies")
	check(game.school_libraries.death[0] != game.school_libraries.death[1], "Cards retain instance identity")
	check(game.assign_mage_to_player(0, "mors"), "Mors selectable")
	check(game.players[0].mage.health == 11 and game.players[0].hand_limit == 7 and game.players[0].personal_spell_id == "consuming_soul", "Mors Codex statistics and personal Spell")
	game.players[0].school_id = "death"
	check(game.build_starting_grimoire(0, "death", "oblivion"), "Oblivion starting Grimoire")
	game.players[1].school_id = "death"
	game.players[1].personal_spell_id = "emet_met"
	check(game.build_starting_grimoire(1, "death", "the_end"), "The End starting Grimoire")
	check(game.players[0].personal_spell_copies_received == 1, "Mors receives initial Consuming Soul")
	check(game.give_personal_spell_for_moon(0, 2), "Mors receives second Consuming Soul")
	reset()
	destiny(1, 0, 2)
	destiny(1, 2, 2)
	check(game.players[1].mage.destiny_tokens == [0, 0, 2], "Destiny cap is three across owners")
	check(game.players[0].available_cubes == 23 and game.players[2].available_cubes == 24, "Destiny reserves real cubes")
	game.heal_damage(1, 0, 20)
	check(game.players[1].mage.destiny_tokens.size() == 3, "Heal does not remove Destiny")
	reset()
	var summon = game.summon_evocation(1, "succubus", "forge")
	cast("tearing")
	drain()
	check(not game.is_evocation_in_play(summon) and game.players[1].mage.destiny_tokens == [0], "Tearing Light assigns then removes eligible target-owned Evocation")
	reset()
	damage(1, 2, 1)
	cast("tearing", true)
	drain()
	check(game.players[1].mage.damage_cubes == [0, 0, 0] and game.players[1].mage.destiny_tokens == [0], "Tearing Dark all three sentences, cube position preserved")
	check(game.players[0].available_cubes == 21 and game.players[2].available_cubes == 25, "Conversion and Destiny conserve cubes")
	reset()
	cast("entropy")
	var forge = game.get_room_by_id("forge")
	game.place_instability(1, "forge", forge.get_instability_resistance())
	drain()
	check(forge.instability_cubes.count(0) == 1, "Entropy Light reacts to last placed Instability")
	reset()
	cast("entropy", true)
	game.players[2].mage.health = 2
	game.deal_damage(1, 2, 2)
	drain()
	check(game.players[2].mage.in_cell and game.players[2].mage.destiny_tokens == [0, 0], "Entropy Dark assigns before defeat; declined Destiny remains assigned")
	reset()
	cast("bone_shield")
	cast("tearing", true, 1, 0)
	drain()
	check(game.players[0].mage.get_damage() == 0 and game.players[0].mage.destiny_tokens.is_empty(), "Bone Shield ignores entire incoming Spell on protected Mage")
	check(game.players[1].mage.get_damage() == 2, "Bone Shield retaliates against caster")
	reset()
	cast("bone_shield", true)
	game.deal_damage(1, 0, 1)
	drain({"death_branch": "branch:0"})
	check(forge.instability_cubes.size() == 2, "Bone Shield Dark places in caster Room")
	reset()
	cast("lugubrious_toll")
	drain()
	check(game.players[0].mage.get_damage() == 0 and game.players[1].mage.get_damage() == 1 and game.players[2].mage.destiny_tokens == [0], "Lugubrious Toll Light affects opposing Mages around Room")
	damage(1, 2, 2)
	cast("lugubrious_toll", true)
	drain()
	check(game.players[1].mage.damage_cubes == [0, 0, 0], "Lugubrious Toll Dark converts marked Mages")
	reset()
	damage(0, 1, 3)
	destiny(1, 2, 3)
	cast("lethal_touch")
	drain()
	check(game.players[0].mage.get_damage() == 2, "Lethal Touch heals for actually assigned tokens, respecting cap")
	game.players[0].trophies.append(1)
	cast("lethal_touch", true)
	drain()
	check(game.players[1].mage.get_damage() == 3 and game.players[2].mage.get_damage() == 3 and game.players[0].trophies.is_empty(), "Lethal Touch Dark spends Trophy and damages all marked Mages")
	reset()
	destiny(1, 0, 3)
	cast("dark_omens")
	drain()
	check(game.players[1].mage.in_cell and game.players[0].trophies == [1, 1], "Destiny auto-defeat awards two Trophies without inventing damage")
	check(game.players[0].power == 0, "No damage contributions means no defeat points")
	reset()
	cast("dark_omens", true)
	check(game.players[0].power == 0, "Dark Omens grants no Power on initial cast")
	game.place_mage_in_cell(1)
	drain()
	check(game.players[0].power == 1, "Dark Omens reacts to Cell placement")
	reset()
	destiny(1, 0, 2)
	cast("annihilation")
	drain()
	check(game.players[0].trophies == [1] and game.players[1].mage.destiny_tokens.size() == 3, "Annihilation checks two Destiny before assigning third")
	damage(1, 2, 2)
	cast("annihilation", true)
	drain()
	check(game.players[1].mage.damage_cubes == [0, 0, 0, 0], "Annihilation Dark inflicts then converts")
	reset()
	cast("final_judgment")
	var quest := QuestState.new(game.quest_database.get_quest("shattered_illusion"), 1)
	game.players[1].active_quests.append(quest)
	game.quest_manager.complete_active_quest(game, 1, quest)
	drain()
	check(game.players[0].trophies == [1] and game.players[0].power == 1, "Final Judgment Light triggers on actual Quest completion")
	reset()
	damage(0, 1, 4)
	cast("final_judgment", true)
	game.place_mage_in_cell(1)
	drain()
	check(game.players[0].mage.get_damage() == 1 and game.players[0].trophies == [1], "Final Judgment Dark heals self and gains placed Mage's Trophy")
	reset()
	destiny(1, 0, 3)
	cast("sacrificial_pyre")
	drain()
	check(game.players[0].mage.get_damage_from(-1) == 3 and game.players[1].mage.in_cell, "Sacrificial Pyre Light pays Black Rose damage then defeats")
	reset()
	game.players[0].trophies.append(2)
	cast("sacrificial_pyre", true)
	drain()
	check(game.players[1].mage.get_damage() == 4 and game.players[0].trophies.is_empty(), "Sacrificial Pyre Dark optional Trophy adds two damage")
	reset()
	cast("despair")
	emit("quest_solved", 1)
	drain()
	check(game.players[1].mage.destiny_tokens == [0] and game.players[0].power == 1, "Despair Light reacts to Quest solve")
	reset()
	cast("despair", true)
	game.deal_damage(1, 2, 1)
	drain()
	check(game.players[0].trophies == [1], "Despair Dark gains damaging Mage's Trophy")
	reset()
	game.players[0].trophies.append(1)
	cast("martyrdom")
	drain()
	check(game.players[0].mage.get_damage() == 0 and game.players[1].mage.get_damage() == 3 and game.players[2].mage.get_damage() == 3, "Martyrdom Light room damage and immunity")
	reset()
	game.players[0].trophies.assign([1, 2])
	game.place_instability(1, "forge", 3)
	cast("martyrdom", true)
	drain()
	check(forge.instability_cubes.count(0) == 4 and game.players[0].trophies.is_empty(), "Martyrdom Dark pays two separate costs, converts 2 then 1, plus reveal Instability")
	reset()
	cast("repentance")
	game.deal_damage(1, 0, 3)
	drain()
	check(game.players[0].mage.get_damage() == 2 and game.players[0].trophies == [1], "Repentance Light ignores one and gains attacker's Trophy")
	reset()
	cast("repentance", true)
	summon = game.summon_evocation(1, "cadaver", "forge")
	var neighbor: String = ""
	for room_id in game.room_id_by_coord.values():
		if game.get_hex_distance(game.room_id_to_coord("forge"), game.room_id_to_coord(room_id)) == 1:
			neighbor = room_id
			break
	game.activate_evocation(summon, 1, {"evocation_attack_timing": "before", "evocation_target_model_type": "mage",
		"evocation_target_player_index": 0, "evocation_move_room_ids": [neighbor]})
	drain()
	check(summon.room_id == "forge" and summon.owner_id == 1, "Repentance Dark ends interrupted activation without transferring ownership")
	reset()
	destiny(1, 0, 2)
	destiny(2, 0, 3)
	cast("consuming_soul")
	drain()
	check(game.players[1].mage.get_damage() == 2 and game.players[2].mage.get_damage() == 3, "Consuming Soul Light scales per target's Destiny")
	cast("consuming_soul", true)
	drain({"death_branch": "branch:0"})
	check(game.players[0].trophies == [1], "Consuming Soul Dark Trophy branch")
	reset()
	destiny(1, 0, 2)
	destiny(1, 2, 1)
	damage(1, 1, 5)
	damage(1, 2, 5)
	game.deal_damage(2, 1, 1)
	check(game.pending_input.get("choice_kind") == "destiny_resolution" and game.pending_input.player_index == 0, "Destiny resolves in play order before points")
	drain({"destiny_count": "destiny:1"})
	check(game.players[1].mage.destiny_tokens == [0], "Only selected Destiny consumed across owners")
	check(game.players[0].power == 0 and game.players[2].power == 4, "Later Destiny conversion can erase first owner's contribution before ranking")
	check(game.players[0].available_cubes == 24 and game.players[2].available_cubes == 25, "Defeat returns damage and resolved Destiny cubes")
	var projection: Dictionary = load("res://network_projection.gd").build(game, 2)
	check(projection.players[1].mage.destiny_tokens == [0], "Destiny public network projection")
	edge_cases()
	check(coverage.size() == 26, "All 26 Death / Mors card sides exercised")
	print("DEATH SCHOOL: %d checks; %d sides; %d failures" % [checks, coverage.size(), failures])
	quit(1 if failures else 0)
