extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func quiet(instance) -> void:
	instance.table_shell.set_process(false)
	instance.table_shell._cancel_animation()
	instance.table_shell.animation_queue.clear()
	instance.table_shell.world_placements.clear()
	instance.table_shell.world_removals.clear()
	instance.table_shell.attack_queue.clear()
	instance.table_shell.phase_queue.clear()
	instance.beta_hud.set_process(false)
	instance.visual_motion_until = 0

func top(id: String) -> void:
	game.current_moon = 1
	game.avatar.commands_used = 0
	game.avatar.active_deck().clear()
	game.avatar.active_deck().append(cards["possessed_" + id])
	game.avatar_board.refresh()

func verify_opacity(kind: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var marker = preload("res://tabletop_style.gd").marker(kind, Color.BLACK, Vector2(96,96))
	marker.position = Vector2(16,16)
	viewport.add_child(marker)
	for i in 3: await process_frame
	RenderingServer.force_draw(false)
	var opaque := viewport.get_texture().get_image()
	marker.modulate.a = 0.25
	for i in 3: await process_frame
	RenderingServer.force_draw(false)
	var faded := viewport.get_texture().get_image()
	var peak_before := 0.0
	var peak_after := 0.0
	for y in range(20, 108, 4):
		for x in range(20, 108, 4):
			peak_before = maxf(peak_before, opaque.get_pixel(x,y).a)
			peak_after = maxf(peak_after, faded.get_pixel(x,y).a)
	expect(peak_before > 0.95, kind + ": token rendered opaque")
	expect(peak_after > 0.20 and peak_after < 0.30, kind + ": actual shader pixels follow placement opacity")
	viewport.queue_free()

func run():
	root.size = Vector2i(1600, 1000)
	game = await create_game()
	quiet(game)
	reset_case()
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card
	var shell = game.table_shell
	# The resolver observes the new top before the UI notices the prior Mage's
	# decision has ended. This is the actual ordering, absent in manual preview tests.
	top("release_energy")
	shell._observe(false)
	shell.observed_viewer = 1
	game.local_viewer_index = -1
	top("energy_of_the_rose")
	expect(game._visuals_busy(), "Resolver registers the pending Avatar placement")
	shell._process(0)
	expect(shell.animated_avatar_marker and shell.animation != null, "Viewer change cannot erase the queued Avatar placement")
	quiet(game)
	top("release_energy")
	shell._observe(false)
	top("energy_of_the_rose")
	shell._observe(true)
	shell._on_request({"type":"action_activation_step", "player_index":1})
	expect(shell.animation_queue.size() == 1, "A new request preserves an unplayed Avatar placement")
	shell._play_next_animation()
	await create_timer(0.4).timeout
	expect(shell.animated_avatar_marker and game.avatar_board.expanded, "Placement opens the actual Avatar board")
	shell._on_request({"type":"effect_choice", "player_index":1})
	expect(shell.animation == null and shell.animation_queue.size() == 1, "An interrupted placement is retained once for resumption")
	shell._play_next_animation()
	await create_timer(1.3).timeout
	expect(shell.animated_avatar_marker and shell.animated_node.visible, "Placement remains visible long enough to read")
	var fit_scale: float = minf((shell.board_overlay.size.x-28)/1300.0, (shell.board_overlay.size.y-64)/1500.0)
	expect(shell.board_stage.scale.x > fit_scale * 2.3, "Avatar placement zooms in on the Hand slot")
	var token_center: Vector2 = shell.animated_node.get_global_transform() * (shell.animated_node.size * 0.5)
	var focus_center: Vector2 = shell.board_overlay.get_global_transform() * (shell.board_overlay.size * Vector2(0.5,0.52))
	expect(token_center.distance_to(focus_center) < 4, "Zoom keeps the reaction token in the presentation center")
	await capture("nov02-avatar-protection-placement")
	shell.close_board(true)
	expect(shell.animation == null and shell.animation_queue.is_empty(), "Explicit Close skips the active presentation without a replay loop")
	expect(game.avatar_board.cards_root.get_node("AvatarProtection").visible and game.avatar.commands_used == 0, "Close restores the token without spending a Command")
	expect(is_equal_approx(shell.board_stage.scale.x, fit_scale), "Skipping a placement restores board scale")
	quiet(game)
	var client = await create_game(true)
	quiet(client)
	client.hide()
	client.table_shell.hide()
	client.table_shell.board_layer.hide()
	client.table_shell.notice_layer.hide()
	client.beta_hud.hide()
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	client.table_shell._process(0)
	expect(client.table_shell.animated_avatar_marker or client.table_shell.animation_queue.any(func(e): return e.kind == "avatar_marker"), "Initial snapshot queues the public token even while model movement is finishing")
	await create_timer(0.85).timeout
	client.table_shell._process(0)
	expect(client.table_shell.animated_avatar_marker, "First online snapshot presents the current reactive top once")
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	client.table_shell._observe(true)
	expect(client.table_shell.animation_queue.is_empty() and client.table_shell.animated_avatar_marker, "Duplicate snapshot does not duplicate the running placement")
	client.table_shell.close_board(true)
	quiet(client)
	# Public Trap projection is exercised without inventing a Possessed Trap card.
	var synthetic := NetworkSnapshot.build(game, 1)
	synthetic.avatar.reaction_type = "trap"
	NetworkSnapshot.apply(client, synthetic)
	client.table_shell._process(0)
	expect(client.table_shell.animated_avatar_marker and client.table_shell.animated_node.name == "AvatarTrap", "The same placement path supports an Avatar Trap token")
	client.table_shell.close_board(true)
	quiet(client)
	game.avatar.commands_used = game.avatar.command_limit()
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	client.table_shell._observe(true)
	expect(client.table_shell.animation_queue.is_empty() and client.avatar_board.cards_root.get_node_or_null("AvatarProtection") == null, "No active token is presented beyond the Command limit")
	client.queue_free()
	await process_frame
	quiet(game)
	game.current_moon = 3
	game.avatar.commands_used = 0
	game.avatar.active_deck().assign([cards.possessed_dark_hammer])
	shell._observe(true)
	shell._play_next_animation()
	await create_timer(1.05).timeout
	expect(shell.animated_node.get_meta("reaction") == "combat_spell", "Combat Protection uses the lightning symbol")
	await capture("nov02-avatar-combat-placement")
	await create_timer(1.8).timeout
	expect(shell.animation == null and not game.avatar_board.expanded, "Playback finishes and restores the Lodge")
	await verify_opacity("avatar_protection_damage")
	await verify_opacity("trap")
	print("NOV02 AVATAR MARKER: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
