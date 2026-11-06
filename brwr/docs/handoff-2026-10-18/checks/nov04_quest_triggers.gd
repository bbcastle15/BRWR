extends "res://docs/handoff-2026-10-18/checks/playtest.gd"

func run():
	game = await make_game(4)
	reset_case()
	locate(0, "arena")
	var nigredo = game.summon_evocation(0, "nigredo", "arena")
	var targets: Array = game._spell_primary_target_options(0, game.spell_database.get_spell("emet_met").dark_side)
	expect(targets.any(func(option): return option.value.get("evocation") == nigredo), "Emet-Met Dark may select the caster's Nigredo")
	game.players[0].mage.in_cell = true
	game.players[0].mage.jinxes.append({"id":"slowness","progress":0})
	var exits: Array = game._beta_explore_paths(0)
	expect(not exits.is_empty() and exits.all(func(path): return path.size() == 1 and game.get_player_cell_exit_room_ids(0).has(path[0])), "Slowness offers only one-step legal Cell exits")
	reset_case()
	game.players[1].mage.destiny_tokens.assign([0])
	game.players[1].mage.damage_cubes.assign([0, 1, -1])
	DeathEffectResolver.process_destiny(game, {"victim":1,"order":[0],"index":0})
	expect(game.pending_input.get("focus_damage_board") == 1 and "Last Damage cube: Black Rose" in str(game.pending_input.get("prompt")), "Destiny identifies the victim's board and last damage owner")
	game.clear_player_input()
	game._prepare_damage_conversion_choices({"type":"convert_damage","amount":1}, {"caster_id":0,"target_player_index":1,"spell_target_type":"mage"})
	expect(game.pending_input.get("focus_damage_board") == 1, "Damage conversion opens the recipient's board")
	reset_case()
	var side := {"trigger_target":"event_room", "target":"room"}
	var event := GameEvent.new("instability_placed")
	event.source_player_index = 1
	event.source_room_id = "arena"
	event.amount = 2
	var context := {"caster_id":0, "target_room_id":"crypt", "target_player_index":3}
	DeathEffectResolver.apply_trigger_target(side, context, event)
	expect(context.target_room_id == "arena", "Bad Luck uses the Room of the placement event")
	expect(not context.has("target_player_index"), "Room trigger removes an old Mage target")
	event.target_room_id = "forge"
	DeathEffectResolver.apply_trigger_target(side, context, event)
	expect(context.target_room_id == "forge", "Explicit event target takes precedence")
	var card: SpellCardState = game.spell_database.get_spell("bad_luck")
	var active := ActiveSpellState.new(card, 0, false)
	active.context = {"triggering_player_index":3, "triggering_room_id":"crypt", "trigger_damage_amount":99, "caster_id":2}
	var resolution := {"active_spell":active, "event":event}
	game.process_trigger_spell_resolution(resolution)
	var current: Dictionary = resolution.context
	expect(current.caster_id == 0, "Saved context cannot replace the current caster")
	expect(current.triggering_player_index == 1, "Saved context cannot replace the triggering player")
	expect(current.triggering_room_id == "arena", "Saved context cannot replace the current source Room")
	expect(current.trigger_damage_amount == 2, "Saved context cannot replace the current event amount")
	expect(current.target_room_id == "forge", "Bad Luck resolution retains its event Room")
	reset_case()
	var forge = game.get_room_by_id("forge")
	var arena = game.get_room_by_id("arena")
	arena.add_instability_cube(2, false)
	for i in 2:
		var copy := ActiveSpellState.new(card, 0, false)
		copy.context = {"target_room_id":"arena", "triggering_player_index":2}
		game.players[0].active_spells.append(copy)
	game.place_player_instability(1, "forge", 3)
	await drive()
	expect(forge.get_instability_by_owner(0) == 3 and forge.get_instability_count() == 3, "Two Bad Luck copies convert three available cubes in the triggering Room")
	expect(arena.get_instability_by_owner(2) == 1, "Saved Room of earlier trigger is untouched")
	expect(game.players[0].active_spells.is_empty(), "Each revealed trap is consumed once")
	reset_case()
	await effects(game.quest_database.quests.master_of_death.effects, {"game":game, "caster_id":0, "selected_mage_indices":[1,2,2]})
	expect(game.players[0].trophies == [1,2], "Master of Death grants one Trophy for each distinct chosen Mage")
	var texture = game.ReferenceCardPreview.card_texture("quests", "holy_corruption")
	expect(texture != null and texture.resource_path == "res://assets/quests/restored/holy_corruption.png", "Runtime selects the corrected HD Quest")
	reset_case()
	var quest := QuestState.new(game.quest_database.quests.elementalist, 0)
	game.players[0].active_quests.append(quest)
	for i in 4:
		game.quest_manager.process_event(game, {"type":"effect_resolved", "player_index":0, "source_kind":"spell", "spell_element":"fire"})
	expect(quest.progress == 0, "Atomic effects cannot prematurely complete Elementalist")
	game.quest_manager.process_event(game, {"type":"spell_resolved", "player_index":0, "source_kind":"spell", "spell_element":"profane"})
	expect(quest.progress == 0, "Profane is not an Elementalist element")
	for element in ["fire", "water", "earth"]:
		game.quest_manager.process_event(game, {"type":"spell_resolved", "player_index":0, "source_kind":"spell", "spell_element":element})
		expect(quest.progress == ["fire", "water", "earth"].find(element) + 1, "One Elementalist cube per resolved Spell")
	expect(not quest.is_completed(), "Three cubes leave the fourth printed slot empty")
	game.quest_manager.process_event(game, {"type":"spell_resolved", "player_index":0, "source_kind":"spell", "spell_element":"air"})
	expect(quest.is_completed(), "The fourth qualifying Spell completes Elementalist")
	var pain := ActiveSpellState.new(game.spell_database.get_spell("ineluctable_pain"), 0, true)
	var damage := GameEvent.new("damage_inflicted")
	damage.source_model_type = "evocation"
	damage.source_player_index = -1
	damage.target_model_type = "mage"
	damage.target_player_index = 0
	damage.amount = 1
	var triggers := TriggeredSpellManager.new()
	expect(triggers.trigger_matches(pain.get_trigger(), damage, pain), "Black Rose Umbra damage triggers Ineluctable Pain")
	damage.source_player_index = 1
	expect(not triggers.trigger_matches(pain.get_trigger(), damage, pain), "Player-controlled Umbra damage does not count as Black Rose damage")
	var card_button: Button = game.ReferenceCardPreview.make_card("jinxs", "weakness", "Weakness", Vector2(112,154), func(): pass)
	game.ReferenceCardPreview.add_jinx_progress(card_button, "weakness", 2, Color.RED)
	expect(card_button.get_node("JinxProgress").get_child_count() == 2, "Jinx cubes overlay the printed card instead of an external progress bar")
	card_button.free()
	print("QUEST/TRIGGER REGRESSION: %d checks; %d failures" % [checks, failures.size()])
	game.resolution_stack.clear()
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

