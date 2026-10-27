extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func run():
	game = await create_game()
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card
	reset_case()
	game.beta_hud.panel.hide()
	game.suppress_placement_feedback = true
	game.table_shell.animation_queue.clear()
	game.table_shell.world_placements.clear()
	arm("energy_of_the_rose")
	game.avatar_board.refresh()
	expect(game.avatar_board.cards_root.get_node_or_null("AvatarProtection") != null, "Top reactive Command shows protection token")
	arm("release_energy")
	game.avatar_board.refresh()
	expect(game.avatar_board.cards_root.get_node_or_null("AvatarProtection") == null, "Nonreactive Command has no protection token")
	locate(AVATAR, "arena")
	AvatarRules.begin_activation(game, false, false)
	expect(game.avatar.commands_used == 0, "Avatar does not reveal immediately")
	await create_timer(1.5).timeout
	expect(game.avatar.commands_used == 0, "Avatar still waits after 1.5 seconds")
	await create_timer(0.8).timeout
	expect(game.avatar.commands_used == 1, "Avatar reveals after two-second pause")
	game.resolution_stack.clear()
	game.card_presentation.clear()
	game.table_shell.set_process(false)
	var client = await create_game(true)
	client.table_shell.set_process(false)
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	game.run_tests_on_ready = false
	game.animate_model_attack(0, 1)
	var event = game.table_feedback_events.back()
	expect(event.kind == "attack" and event.origin is Vector2 and event.destination is Vector2, "Attack feedback carries source and destination")
	expect(game.visual_motion_until > Time.get_ticks_msec() + 900, "Attack keeps resolution waiting for visible motion")
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	expect(client.table_shell.attack_queue.size() == 1, "Client receives attack animation")
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	expect(client.table_shell.attack_queue.size() == 1, "Repeated snapshot does not duplicate attack")
	print("OCT27 PACING: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
