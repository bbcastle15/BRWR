extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func top(id: String) -> void:
	var card: SpellCardState = cards["possessed_" + id]
	game.current_moon = int(card.avatar_command.moon)
	game.avatar.active_deck().clear()
	game.avatar.commands_used = 0
	game.avatar.active_deck().append(card)
	game.avatar_board.refresh()

func incoming(trigger: String, spell_target: String = "mage", target: int = AVATAR) -> GameEvent:
	var event := GameEvent.new(trigger)
	event.source_player_index = 0
	event.source_model_type = "mage"
	event.target_player_index = target
	event.target_model_type = "mage"
	event.amount = 2
	var context := {"spell_type": "combat", "spell_target_type": spell_target, "target_player_index": target, "target_model_type": "mage"}
	event.set_meta("source_spell_context", context)
	event.set_meta("source_spell_type", "combat")
	event.set_meta("affected_player_indices", [AVATAR])
	return event

func triggers(event: GameEvent) -> Array:
	var result: Array = []
	AvatarRules.append_reaction(game, event, result)
	return result

func run():
	root.size = Vector2i(1600, 1000)
	game = await create_game()
	game.table_shell.set_process(false)
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card
	reset_case()
	game.table_shell._cancel_animation()
	game.table_shell.world_placements.clear()
	game.suppress_placement_feedback = false
	var mappings := {
		"energy_of_the_rose": "command_back_1_protection_damage",
		"revenge_of_the_thorn": "command_back_1_protection_damage",
		"sap_of_the_black_rose": "command_back_2_protection_damage",
		"revenge_embodied": "command_back_2_protection_combat",
		"explosion_of_dark_petals": "command_back_3_protection_damage",
		"dark_hammer": "command_back_3_protection_combat"}
	for id in mappings:
		top(id)
		var back_id: String = mappings[id]
		var state: Dictionary = game.avatar.public_data()
		expect(AvatarArt.command_back_id(game.current_moon, state) == back_id, id + ": correct back")
		var art := AvatarArt.texture(back_id)
		expect(art != null and art.get_size() == Vector2(1024, 1536), id + ": HD art loaded")
		var hand_card = game.avatar_board.cards_root.get_node("AvatarHand")
		expect(hand_card.get_meta("back_id") == back_id, id + ": top back on board")
		var token = game.avatar_board.cards_root.get_node_or_null("AvatarProtection")
		expect(token != null and token.get_meta("reaction") == state.reaction, id + ": distinct live token")
		var suffix := "combat" if state.reaction == "combat_spell" else "damage"
		expect(token.texture.resource_path.ends_with("avatar_protection_" + suffix + ".png"), id + ": correct glyph")
		hand_card.pressed.emit()
		expect(game._reference_card_preview().art.texture == art, id + ": inspection shows same back")
		game._reference_card_preview().hide_preview()

	top("energy_of_the_rose")
	var energy_public: Dictionary = game.avatar.public_data()
	top("revenge_of_the_thorn")
	expect(energy_public == game.avatar.public_data(), "Identical printed backs do not leak hidden effect or identity")
	game.avatar.commands_used = 3
	game.avatar_board.refresh()
	expect(not game.avatar.public_data().reaction_available, "Apprentice command limit disables reaction")
	expect(game.avatar_board.cards_root.get_node_or_null("AvatarProtection") == null, "No live token beyond limit")
	expect(game.avatar_board.cards_root.get_node("AvatarHand").get_meta("back_id") == "command_back_1_protection_damage", "Printed back stays visible beyond limit")
	game.avatar.difficulty = "master"
	expect(game.avatar.public_data().reaction_available, "Master may resolve fourth Command")
	game.avatar.commands_used = 4
	expect(not game.avatar.public_data().reaction_available, "Master stops at four Commands")
	game.avatar.difficulty = "apprentice"

	for id in ["revenge_embodied", "dark_hammer"]:
		top(id)
		expect(triggers(incoming("spell_effect_about_to_resolve")).size() == 1, id + ": Mage-target Combat activates")
		expect(triggers(incoming("spell_effect_about_to_resolve", "model")).size() == 1, id + ": Model-target Combat activates")
		for target_kind in ["room", "area", "special", "self", "evocation"]:
			expect(triggers(incoming("spell_effect_about_to_resolve", target_kind)).is_empty(), id + ": no trigger from " + target_kind)
		expect(triggers(incoming("damage_about_to_be_inflicted")).is_empty(), id + ": physical Damage is not Combat targeting")
		expect(triggers(incoming("spell_effect_about_to_resolve", "mage", 1)).is_empty(), id + ": another Mage is not Avatar")
		var data_event := incoming("spell_effect_about_to_resolve")
		var context: Dictionary = data_event.get_meta("source_spell_context")
		data_event.remove_meta("source_spell_context")
		data_event.remove_meta("source_spell_type")
		data_event.target_player_index = -1
		data_event.data = {"targets": [AVATAR], "spell_context": context}
		expect(triggers(data_event).size() == 1, id + ": alternate existing announcement path")
		context.spell_type = "contingency"
		expect(triggers(data_event).is_empty(), id + ": Contingency does not activate Combat shield")

	for id in ["energy_of_the_rose", "sap_of_the_black_rose", "explosion_of_dark_petals"]:
		top(id)
		var event := incoming("damage_about_to_be_inflicted")
		expect(triggers(event).size() == 1, id + ": any incoming Damage arms prevention")
		var active: ActiveSpellState = triggers(event)[0].active_spell
		event.amount = 0
		expect(triggers(event).is_empty(), id + ": zero Damage does not activate")
		AvatarRules.trigger_reaction(game, active, event)
		expect(game.avatar.commands_used == 0 and game.avatar.active_deck().size() == 1, id + ": rechecks Damage after earlier Protection")
		event.amount = 2
		event.suppressed_trigger_types.assign(["protection"])
		expect(triggers(event).is_empty(), id + ": suppressed Protection does not activate")
		event.suppressed_trigger_types.clear()
		event.source_player_index = -1
		expect(triggers(event).is_empty(), id + ": no reaction to immune Black Rose Damage")

	top("revenge_of_the_thorn")
	expect(triggers(incoming("damage_about_to_be_inflicted")).is_empty(), "Revenge waits until Damage is actually suffered")
	expect(triggers(incoming("damage_inflicted")).size() == 1, "Revenge triggers after actual Damage")
	game.avatar.active_deck().append(cards.possessed_release_energy)
	expect(triggers(incoming("damage_inflicted")).is_empty(), "Buried Protection cannot trigger")
	game.avatar_board.refresh()
	expect(game.avatar_board.cards_root.get_node_or_null("AvatarProtection") == null, "Non-reactive top removes token")
	expect(game.avatar_board.cards_root.get_node("AvatarHand").get_meta("back_id") == "command_back_1", "Non-reactive top uses ordinary Moon back")
	game.avatar.active_deck().clear()
	expect(not game.avatar.public_data().reaction_available, "Empty deck has no active reaction")

	# Real placement animation on the real board, with cancellation and no state mutation.
	top("release_energy")
	game.table_shell._observe(false)
	top("energy_of_the_rose")
	game.table_shell._observe(true)
	expect(game.table_shell.animation_queue.size() == 1, "New reactive top queues one placement")
	game.table_shell._observe(true)
	expect(game.table_shell.animation_queue.size() == 1, "Repeated refresh does not repeat placement")
	game.table_shell._play_next_animation()
	expect(game.avatar_board.expanded and game.table_shell.animated_avatar_marker, "Placement opens actual Avatar Board")
	await create_timer(1.05).timeout
	expect(game.table_shell.animation != null, "Token remains visible long enough to read")
	await capture("oct29-avatar-damage-token")
	await create_timer(1.8).timeout
	expect(game.table_shell.animation == null and not game.avatar_board.expanded, "Placement completes and restores Lodge")
	expect(game.avatar.commands_used == 0, "Visual placement consumes no Command")
	game.avatar.active_deck().append(cards.possessed_revenge_of_the_thorn)
	game.table_shell._observe(true)
	expect(game.table_shell.animation_queue.size() == 1, "Next identical-symbol top gets its own placement")
	game.table_shell._play_next_animation()
	game.table_shell.close_board(true)
	expect(game.table_shell.animation == null and game.avatar_board.cards_root.get_node("AvatarProtection").visible, "Closing placement restores live token")

	# Projection carries only the public back and availability, never the hidden face.
	var client = await create_game(true)
	client.table_shell.set_process(false)
	client.table_shell._cancel_animation()
	top("release_energy")
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	client.table_shell._observe(false)
	top("dark_hammer")
	var snapshot := NetworkSnapshot.build(game, 1)
	NetworkSnapshot.apply(client, snapshot)
	client.table_shell._observe(true)
	expect(client.avatar_board.cards_root.get_node("AvatarHand").get_meta("back_id") == "command_back_3_protection_combat", "Client sees full-Moon Combat back")
	expect(client.table_shell.animation_queue.size() == 1, "Client queues token placement")
	NetworkSnapshot.apply(client, snapshot)
	client.table_shell._observe(true)
	expect(client.table_shell.animation_queue.size() == 1, "Repeated snapshot does not replay placement")
	expect(not JSON.stringify(snapshot.avatar).contains("dark_hammer"), "Hidden top identity stays out of public Avatar projection")
	client.table_shell._play_next_animation()
	expect(client.table_shell.animated_node.get_meta("reaction") == "combat_spell", "Client animates correct glyph")
	client.table_shell.close_board(true)
	game.avatar.commands_used = 3
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	client.table_shell._observe(true)
	expect(client.avatar_board.cards_root.get_node_or_null("AvatarProtection") == null, "Client removes exhausted token")
	client.queue_free()
	await process_frame
	game.avatar.commands_used = 0
	game.avatar_board.refresh()
	game.table_shell.open_board(AVATAR)
	await capture("oct29-avatar-combat-token")
	game.table_shell.close_board()
	print("OCT29 AVATAR REACTIONS: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
