extends SceneTree

var failures := 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func choose(token: String, owner: int = 0) -> void:
	check(game.submit_effect_choice(owner, token), "Choice accepted: " + token)

func run() -> void:
	game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(8): await process_frame
	for p in game.players:
		p.mage.in_cell = false
		p.mage.room_id = "forge"
		p.mage.room_coord = game.room_id_to_coord("forge")
	var player = game.players[0]
	var room = game.get_room_by_id("forge")
	# Real Emet-Met data: base summon survives, enhancement cannot count itself.
	var emet = game.clone_spell_card(game.spell_database.get_spell("emet_met"))
	player.revealed_spells.clear()
	player.quick_spell = ReadySpellState.new(emet, false)
	check(game.cast_quick_spell(0, {"target_room_id": "forge"}), "Emet-Met first cast")
	check(player.evocations.size() == 1, "Emet-Met summons its Nigredo")
	check(not game.waiting_for_player_input and game.resolution_stack.is_empty(), "First Emet-Met must not activate a Construct")
	check(not game.can_apply_enhancement(0, ["fire", "earth"], emet), "Current wildcard does not enhance itself")
	var prior = SpellCardState.new("elements", "Elements", "alchemy", {"element": "fire"}, {"element": "earth"})
	player.revealed_spells.append(RevealedSpellState.new(prior, false))
	check(not game.can_apply_enhancement(0, ["fire", "earth"], emet), "Inactive Earth side cannot complete enhancement")
	player.revealed_spells.append(RevealedSpellState.new(game.clone_spell_card(prior), true))
	var second = game.clone_spell_card(emet)
	player.quick_spell = ReadySpellState.new(second, false)
	check(game.cast_quick_spell(0, {"target_room_id": "forge"}), "Enhanced Emet-Met cast")
	check(game.waiting_for_player_input, "Other revealed Fire/Earth cards enable activation")
	if game.waiting_for_player_input:
		choose(str(game.pending_input.options[0].token))
	check(str(game.pending_input.get("choice_kind", "")) == "evocation_activation_plan", "Enhanced Construct asks for its activation")
	check(str(game.pending_input.get("movement_origin_room_id", "")) == "forge", "Activation exposes Construct origin")
	if game.waiting_for_player_input:
		choose(str(game.pending_input.options[0].token))
	check(game.resolution_stack.is_empty(), "Enhanced cast completes")
	var nigredo = player.evocations[0]
	# Ability happens on actual Mage damage and may be skipped.
	game.deal_damage_from_evocation(nigredo, 1, 1)
	check(str(game.pending_input.get("choice_kind", "")) == "evocation_damage_ability", "Nigredo damage requests its ability")
	choose("ability:0")
	check(room.instability_cubes.count(0) == 1, "Nigredo places one cube in its own Room")
	game.deal_damage_from_evocation(nigredo, 1, 1)
	choose("")
	check(room.get_instability_count() == 1, "Optional ability may be skipped")
	game.deal_damage_from_evocation(nigredo, 1, 0)
	check(not game.waiting_for_player_input, "Zero damage does not trigger Nigredo")
	# Damage to another Evocation also triggers; controller owns the new cube.
	var target = game.summon_evocation(1, "cadaver", "forge")
	game.place_instability(-1, "forge", 1)
	nigredo.controller_id = 1
	game.deal_damage_to_evocation(1, player.evocations[1], 1, [], "evocation_attack", "evocation", nigredo)
	check(int(game.pending_input.get("player_index", -1)) == 1, "Current controller chooses Nigredo ability")
	choose("ability:1", 1)
	if game.waiting_for_player_input:
		choose("instability:-1:0", 1)
	check(room.instability_cubes.count(-1) == 0 and room.instability_cubes.count(1) == 1, "Conversion replaces Black Rose cube with controller cube")
	nigredo.controller_id = 0
	# Prevented Evocation damage cannot trigger the ability.
	game.active_events.assign([game.event_database.get_event("immortals"), null, null])
	game.deal_damage_to_evocation(0, target, 1, [], "evocation_attack", "evocation", nigredo)
	check(not game.waiting_for_player_input, "Immortals prevents damage and Nigredo ability")
	game.active_events.assign([null, null, null])
	# Separate Quest sentences: range 2 conversion, then explicit range 0 placement.
	var other: String = game._beta_adjacent_room_ids("forge")[0]
	game.place_instability(-1, other, 2)
	var quest := QuestState.new(game.quest_database.get_quest("channeling_instability"), 0)
	quest.complete()
	player.completed_quests.append(quest)
	check(game.quest_manager.solve_quest(game, 0, quest, {"target_room_id": other}), "Quest solve queued")
	check(str(game.pending_input.get("choice_kind", "")) == "target_room", "Quest asks first target despite stale context")
	choose("room:" + other)
	check(str(game.pending_input.get("choice_kind", "")) == "target_room", "Quest asks its second target separately")
	check(game.pending_input.get("options", []).size() == 1 and str(game.pending_input.options[0].room_id) == "forge", "Second sentence is range 0 only")
	var before: int = room.get_instability_count()
	choose("room:forge")
	check(room.get_instability_count() == before + 1 and quest.is_solved(), "Placement and Quest reward finish once")
	check(game.get_room_by_id(other).instability_cubes.count(0) == 2, "Conversion used the first target Room")
	# Core rulebook p.28: summoned Evocations remain when their Mage is defeated.
	game.deal_damage(1, 0, player.mage.get_remaining_health())
	check(player.mage.in_cell and player.evocations.has(nigredo), "Mage defeat preserves summoned Nigredo")
	check(game.resolution_stack.is_empty() and not game.waiting_for_player_input, "All resolutions complete")
	print("EVOCATION QUEST RULES: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
