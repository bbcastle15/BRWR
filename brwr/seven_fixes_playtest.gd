extends SceneTree

var failures := 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func choose(token: String) -> void:
	check(game.submit_effect_choice(0, token), "Accept choice: " + token)

func run() -> void:
	game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(8): await process_frame
	game.active_events.assign([null, null, null])
	for player in game.players:
		player.mage.in_cell = false
		player.mage.room_id = "forge"
		player.mage.room_coord = game.room_id_to_coord("forge")
	var player = game.players[0]
	var room = game.get_room_by_id("forge")
	for owner in [1, -1, 1]: game.place_instability(owner, "forge", 1)
	var nodes: Array = room.instability_cube_nodes.duplicate()
	var last_position: Vector2 = nodes[2].position
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "index": 0,
		"effects": [{"type": "convert_instability", "amount": 1}],
		"context": {"game": game, "caster_id": 0, "target_room_id": "forge"}})
	choose("instability:1:1")
	check(room.instability_cubes == [1, -1, 0], "Convert the clicked duplicate-owner cube in place")
	check(room.instability_cube_nodes == nodes and nodes[2].position == last_position, "Cube nodes and positions are unchanged")
	var damage: Array[int] = [1, -1, 1]
	game.effect_resolver.convert_damage_cubes(damage, 0, 1, [{"owner_id": 1, "cube_index": 2}])
	check(damage == [1, -1, 0], "Damage conversion preserves order and selected index")

	var quest := QuestState.new(game.quest_database.get_quest("indigo_star"), 0)
	player.active_quests.append(quest)
	player.mage.room_id = "oracle_room"
	player.mage.room_coord = game.room_id_to_coord("oracle_room")
	var spell := SpellCardState.new("test_combat", "Combat", "test",
		{"type": "combat", "target": "self", "element": "fire", "effects": [{"type": "gain_power", "amount": 1}]}, {})
	player.quick_spell = ReadySpellState.new(spell, false)
	check(game.cast_quick_spell(0), "Combat cast from Oracle Room")
	check(quest.is_completed(), "Indigo Star completes for Combat regardless of element")
	check(not game.quest_manager._task_matches(game, 0, quest.get_task(), {"type": "spell_resolved", "caster_room_id": "forge", "spell_type": "combat"}), "Indigo requires Oracle Room")
	check(not game.quest_manager._task_matches(game, 0, quest.get_task(), {"type": "spell_resolved", "caster_room_id": "oracle_room", "spell_type": "trap", "spell_element": "air"}), "Air Trap does not satisfy Indigo")
	check(game.quest_manager._task_matches(game, 0, quest.get_task(), {"type": "spell_resolved", "caster_room_id": "oracle_room", "spell_type": "contingency"}), "Indigo accepts Contingency")

	player.revealed_spells.clear()
	var elements := SpellCardState.new("elements", "Elements", "alchemy", {"element": "fire"}, {"element": "earth"})
	player.revealed_spells.append(RevealedSpellState.new(elements, false))
	check(game.can_apply_enhancement(0, ["fire"]), "Enhancement counts active Fire")
	check(not game.can_apply_enhancement(0, ["earth"]), "Enhancement ignores inactive Earth")
	check(not game.can_apply_enhancement(0, ["fire"], elements), "Enhancement excludes its own card instance")
	check(not game.quest_manager._check_revealed_spell_elements(game, 0, {"elements": ["earth"], "required": 1}), "Quest ignores inactive Earth")
	check(game.quest_manager._check_revealed_spell_elements(game, 0, {"elements": ["fire"], "required": 1}), "Quest counts active Fire")

	player.mage.room_id = "summoner_room"
	player.mage.room_coord = game.room_id_to_coord("summoner_room")
	var target_room: String = game._beta_adjacent_room_ids("summoner_room")[0]
	var enemy = game.summon_evocation(1, "cadaver", target_room)
	var own = game.summon_evocation(0, "nigredo", target_room)
	check(game.activate_room(0, "summoner_room"), "Activate Summoner Room")
	check(game.waiting_for_player_input, "Summoner Room requests target room")
	choose("room:" + target_room)
	check(enemy.get_damage() == 1, "Summoner Room damages enemy Evocation in chosen room")
	check(own.get_damage() == 0, "Own Evocation remains immune to its Mage's effect")
	check(game.resolution_stack.is_empty(), "Room damage finishes its resolution")

	var second = game.summon_evocation(0, "cadaver", "forge")
	var third = game.summon_evocation(0, "succubus", "forge")
	var summon_context := {"game": game, "caster_id": 0, "target_room_id": "forge"}
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "index": 0,
		"effects": [{"type": "summon_evocation", "evocation_id": "nigredo"}], "context": summon_context})
	check(str(game.pending_input.get("choice_kind", "")) == "summon_replacement", "Full board offers a replacement")
	check(player.evocations.size() == 3 and player.evocations.has(second), "Choice does not remove anything prematurely")
	choose("secondary_evocation:0:1")
	check(player.evocations.size() == 3 and not player.evocations.has(second) and player.evocations.has(third) and player.evocations.has(own), "Replace exactly the selected instance")
	check(game.resolution_stack.is_empty(), "Replacement resumes and finishes the summon")
	var before: Array = player.evocations.duplicate()
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "index": 0,
		"effects": [{"type": "summon_evocation", "evocation_id": "cadaver"}, {"type": "gain_power", "amount": 1}],
		"context": {"game": game, "caster_id": 0, "target_room_id": "forge"}})
	choose("")
	check(player.evocations == before and game.resolution_stack.is_empty(), "Decline preserves Evocations and continues the next effect")
	# The same replacement flow is used by Room summons and choice-based spells.
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "room", "index": 0,
		"effects": [{"type": "summon_evocation", "evocation_id": "cadaver"}],
		"context": {"game": game, "caster_id": 0, "player_index": 0, "room_id": "forge"}})
	check(str(game.pending_input.get("choice_kind", "")) == "summon_replacement", "Room summon offers replacement too")
	choose("secondary_evocation:0:0")
	check(player.evocations.size() == 3 and not player.evocations.has(own), "Room replaces the chosen instance")
	game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell", "index": 0,
		"effects": [{"type": "fountain_construct_or_nigredo"}],
		"context": {"game": game, "caster_id": 0, "target_room_id": "forge", "fountain_choice": "summon_nigredo"}})
	check(str(game.pending_input.get("choice_kind", "")) == "summon_replacement", "Fountain summon branch offers replacement")
	choose("secondary_evocation:0:0")
	check(player.evocations.size() == 3 and game.resolution_stack.is_empty(), "Fountain replacement completes once")
	var survivors: Array = player.evocations.duplicate()
	var survivor_state: Array = []
	for evocation in survivors:
		survivor_state.append([evocation.room_id, evocation.damage_cubes.duplicate(), evocation.board_number])
	game.deal_damage(1, 0, player.mage.get_remaining_health())
	check(player.mage.in_cell and player.evocations == survivors, "Defeat preserves every summoned Evocation instance and slot order")
	for i in range(survivors.size()):
		var evocation = survivors[i]
		check([evocation.room_id, evocation.damage_cubes, evocation.board_number] == survivor_state[i], "Defeat preserves Evocation location, damage and board number")
	check(game.players[1].evocations.has(enemy), "Defeat leaves opponent Evocations intact")
	check(game.resolution_stack.is_empty() and not game.waiting_for_player_input, "No unresolved choices remain")
	print("SEVEN FIXES: ", "PASS" if failures == 0 else "FAIL " + str(failures))
	quit(0 if failures == 0 else 1)
