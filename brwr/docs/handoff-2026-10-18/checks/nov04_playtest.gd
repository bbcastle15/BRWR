extends "res://docs/handoff-2026-10-18/checks/nov03_online_animation.gd"

var sender: Transport
var receiver: ClientWire

func show_peer(instance) -> void:
	for surface in [game, remote_game]:
		var hidden: bool = surface.get_meta("test_surface_hidden", false)
		if surface != instance and not hidden:
			surface.hide()
			for canvas in surface.find_children("*", "CanvasLayer", true, false):
				canvas.set_meta("test_prior_visible", canvas.visible)
				canvas.hide()
			surface.set_meta("test_surface_hidden", true)
		elif surface == instance and hidden:
			surface.show()
			for canvas in surface.find_children("*", "CanvasLayer", true, false):
				canvas.visible = canvas.get_meta("test_prior_visible", canvas.visible)
			surface.set_meta("test_surface_hidden", false)
	instance.get_node("TableCamera").make_current()

func run():
	root.size = Vector2i(1600, 1000)
	game = await create_game()
	quiet(game)
	reset_case()
	game.players[0].player_name = "Host"
	game.players[1].player_name = "Friend"
	game.local_viewer_index = 0
	game.suppress_placement_feedback = true
	remote_game = await create_game(true)
	quiet(remote_game)
	remote_game.local_viewer_index = 1
	receiver = ClientWire.new()
	sender = Transport.new()
	root.add_child(receiver)
	root.add_child(sender)
	sender.hosting = true
	sender.connected = true
	sender.game = game
	sender.peer_players = {"friend": 1}
	sender.receiving = {"friend": true}
	sender.remote = receiver
	receiver.host_wire = sender
	receiver.game = remote_game
	receiver.connected = true
	receiver.local_player = 1
	remote_game.network_session = receiver
	game.network_session = sender
	sender.publish()
	show_peer(game)
	await check_waiting()
	await check_umbra()
	await check_moons()
	await check_attack()
	await check_damage_confirmations()
	for instance in [game, remote_game]:
		quiet(instance)
		instance.network_session = null
		instance.resolution_stack.clear()
		instance.queue_free()
	sender.game = null
	receiver.game = null
	sender.remote = null
	receiver.host_wire = null
	sender.queue_free()
	receiver.queue_free()
	for i in 4: await process_frame
	print("NOV04 PLAYTEST: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)

func check_waiting():
	game.summon_evocation(0, "cadaver", "arena")
	game.summon_evocation(1, "pupa", "crypt")
	for chooser in [0, 1]:
		game.clear_player_input()
		game.current_effect_description = "Draw Spells from the Library."
		var context := {"game": game, "caster_id": chooser}
		expect(not SchoolEffects.resolve({"type":"remove_many_evocations", "amount":1}, context), "Removal suspends for the real SchoolEffects choice")
		sender.publish()
		for instance in [game, remote_game]:
			var request: Dictionary = instance.get_beta_pending_input(instance.local_viewer_index)
			expect(instance.public_choice_description(request) == "Choose an Evocation to remove.", "Current removal description matches on owner/observer")
			instance.beta_hud._process(0)
			expect(instance.beta_hud.effect_text.text.contains("Evocation") and not instance.beta_hud.effect_text.text.contains("Library"), "Visible HUD does not reuse Library text")
			if instance.local_viewer_index != chooser:
				expect(not request.has("options") and not request.has("prompt"), "Observer receives no private options or prompt")
	game.clear_player_input()
	game.request_effect_choice(0, "target_evocation", {}, "school_generic", [{"token":"ev", "value":game.players[0].evocations[0]}])
	expect(not game.pending_input.effect_description.contains("Library"), "An empty prompt cannot reuse the previous effect")
	expect(game._public_effect_choice_description("druidic_choice", {}, "Choose an Upgrade to discard.", "school_upgrade_remove") == "Choose an Upgrade.", "Upgrade helper remains specific")
	expect(game._public_effect_choice_description("unknown", {}, "Secret Card", "school_private") == "Choose how to resolve the effect.", "Unknown private effect has a safe neutral fallback")
	game.clear_player_input()
	sender.publish()
	for instance in [game, remote_game]:
		quiet(instance)
		instance.beta_hud._process(0)

func check_umbra():
	for target in [1, AVATAR]:
		game.summon_evocation(target, "cadaver", "arena")
		game.summon_evocation(target, "colossus", "crypt")
		for slot in range(1, 4):
			ForgottenEvocations.resolve_assignment(game, {"type":"assign_nightmare", "evocation_id":"umbra"},
				{"game":game,"caster_id":0,"target_player_index":target,"nightmare_slot":slot})
	sender.publish()
	for instance in [game, remote_game]:
		quiet(instance)
		show_peer(instance)
		instance.table_shell.open_board(1)
		var board = instance.player_boards[1]
		for ev in instance.players[1].evocations:
			if ev.assigned_mage < 0: continue
			var card = instance._evocation_board_card(1, ev)
			var partner = board.get_node_or_null("EvocationCards/EvocationSlot%d" % ev.assigned_slot)
			expect(card != null and is_equal_approx(card.position.x, 196 + (ev.assigned_slot - 1) * 169), "Umbra renders in its assigned column")
			if partner != null:
				expect(card.position.y > partner.position.y + partner.size.y + 14 and partner.position.y >= 504, "Paired cards and status text do not overlap Spells or each other")
			expect(card.position.y + card.size.y + 18 <= board.get_display_size().y, "Assigned card fits the expanded PlayerBoard")
			card.pressed.emit()
			expect(instance.inspected_evocation == ev, "Assigned Umbra card opens the correct live model")
			instance.evocation_inspection.hide()
		if instance == game: await capture("nov04-player-umbra")
		instance.table_shell.open_board(AVATAR)
		var avatar: AvatarBoard = instance.avatar_board
		for ev in instance.players[AVATAR].evocations:
			if ev.assigned_mage < 0: continue
			var card = instance._evocation_board_card(AVATAR, ev)
			var partner = avatar.cards_root.get_node("EvocationSlot%d" % ev.assigned_slot)
			var a: Vector2 = card.get_global_transform_with_canvas() * (card.size * 0.5)
			var b: Vector2 = partner.get_global_transform_with_canvas() * (partner.size * 0.5)
			expect(is_equal_approx(a.y, b.y) and a.x > b.x, "Possessed shows Umbra beside its corresponding Evocation")
			expect(card.get_meta("evocation_slot") == partner.get_meta("evocation_slot"), "Both Possessed cards share the same slot number")
			card.pressed.emit()
			expect(instance.inspected_evocation == ev, "Possessed Umbra inspection targets the actual assigned model")
			instance.evocation_inspection.hide()
		if instance == game: await capture("nov04-avatar-umbra")
		instance.table_shell.close_board(true)
		for slot in 3:
			var card = avatar.cards_root.get_node("AssignedEvocationSlot%d" % (slot + 1))
			var partner = avatar.cards_root.get_node("EvocationSlot%d" % (slot + 1))
			expect(card.position.x >= partner.position.x + partner.size.x and is_equal_approx(card.position.y, partner.position.y), "Table Avatar layout also pairs cards side by side")
	show_peer(game)

func check_moons():
	for player in game.players: player.power = 0
	game.current_moon = 1
	game.players[0].power = game.get_node("PowerBoard").third_moon_threshold
	game.check_moon_phase()
	sender.publish()
	for instance in [game, remote_game]:
		var moons: Array = instance.table_shell.phase_queue.filter(func(e): return e.kind == "moon").map(func(e): return e.moon)
		expect(moons == [2, 3], "A Moon I→III jump announces both transitions in order")
	var serial: int = game.table_feedback_serial
	game.check_moon_phase()
	sender.publish()
	expect(game.table_feedback_serial == serial and remote_game.table_shell.phase_queue.size() == 2, "Repeated checks/snapshots do not repeat Moon banners")
	game.table_shell._play_phase_notice()
	await create_timer(0.55).timeout
	await capture("nov04-moon-banner")
	await create_timer(1.8).timeout
	for instance in [game, remote_game]: quiet(instance)

func check_attack():
	game.refresh_model_tokens()
	var source_ev: EvocationState = game.players[1].evocations[0]
	var target_ev: EvocationState = game.players[0].evocations[0]
	game.run_tests_on_ready = false
	game.animate_model_attack(1, -1, target_ev, source_ev)
	sender.publish()
	remote_game.replay_attack_feedback(game.table_feedback_events.back())
	for instance in [game, remote_game]:
		var ghost = instance.get_node_or_null("AttackGhost")
		expect(ghost != null and ghost.get_script() != null and ghost.has_portrait(), "Attack copy retains procedural medallion drawing")
		expect(ghost.owner_color == instance.players[1].color and ghost._state == null, "Attack copy keeps ownership color without model state")
		for control in ghost.find_children("*", "Control", true, false):
			expect(control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Attack copy does not intercept input")
	game.run_tests_on_ready = true
	await create_timer(1.4).timeout
	for instance in [game, remote_game]:
		var ev: EvocationState = instance.players[1].evocations[0]
		expect(instance.evocation_tokens[ev.get_instance_id()].visible, "Original token returns after the lunge")
		quiet(instance)
	if DisplayServer.get_name() != "headless":
		var viewport := SubViewport.new()
		viewport.size = Vector2i(200, 200)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var token = game.evocation_tokens[source_ev.get_instance_id()].create_visual_copy()
		viewport.add_child(token)
		token.position = Vector2(100, 100)
		token.scale = Vector2.ONE * 3.0
		for i in 4: await process_frame
		RenderingServer.force_draw(false)
		var image := viewport.get_texture().get_image()
		var pixel := image.get_pixel(157, 100)
		expect(pixel.b > 0.8 and pixel.r < 0.25, "Rendered attack token includes the blue owner ring")
		image.save_png("res://docs/handoff-2026-10-18/evidence/nov04-attack-ring.png")
		viewport.queue_free()

func check_damage_confirmations():
	game.clear_player_input()
	game.resolution_stack.clear()
	for instance in [game, remote_game]:
		quiet(instance)
		instance.table_shell.set_process(true)
		instance.table_shell.observed_avatar_reaction = str([instance.current_moon, 0, instance.avatar.commands_used, "", "", false])
	for first in [game, remote_game]:
		game.deal_damage(0, AVATAR, 1, "spell")
		sender.publish()
		var deadline := Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < deadline and not (game.table_shell.damage_waiting and remote_game.table_shell.damage_waiting):
			await create_timer(0.05).timeout
		expect(game.table_shell.damage_waiting and remote_game.table_shell.damage_waiting, "Both peers reach the Avatar damage receipt")
		show_peer(first)
		await process_frame
		var confirm: Button = first.table_shell.receipt_buttons.get_child(0)
		await click_at(confirm.get_global_transform_with_canvas() * (confirm.size * 0.5))
		await create_timer(0.1).timeout
		expect(not game.damage_acknowledgements[str(first.table_shell.damage_event.serial)].has(first.local_viewer_index), "Real Continue click acknowledges only its reader")
		for instance in [game, remote_game]:
			expect(instance.table_shell.board_overlay.visible and instance.avatar_board.expanded, "Avatar board stays open while another reader has not confirmed")
			expect(instance.avatar_board.get_parent() == instance.table_shell.board_stage, "Expanded Avatar remains on the visible presentation stage")
			expect(instance.avatar_board.damage_track.get_child_count() == instance.players[AVATAR].mage.get_damage(), "Damage remains visible during staggered acknowledgements")
		show_peer(first)
		if first == game: await capture("nov04-avatar-waiting")
		var serial: int = first.table_shell.damage_event.serial
		game.acknowledge_damage(serial, 2)
		var other = remote_game if first == game else game
		other.table_shell._acknowledge_damage_and_close()
		await settle()
		for instance in [game, remote_game]:
			expect(not instance.avatar_board.expanded and instance.avatar_board.get_parent() == instance, "After all confirmations Avatar returns to the Lodge")
			expect(instance.avatar_board.visible and not instance.table_shell.damage_waiting, "No invisible Avatar or stale acknowledgement blocker remains")
