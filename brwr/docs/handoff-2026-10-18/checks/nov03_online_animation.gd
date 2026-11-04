extends "res://docs/handoff-2026-10-18/checks/nov03_online_playtest.gd"

class ClientWire extends "res://online_session.gd":
	var host_wire
	func _send_game_to_host(payload: Dictionary) -> Error:
		host_wire._handle_game_message("friend", Marshalls.base64_to_variant(Marshalls.variant_to_base64(payload, false), false))
		return OK

var remote_game

func click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)
		await process_frame

func settle(seconds: float = 18.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		for instance in [game, remote_game]:
			var shell = instance.table_shell
			if shell.damage_waiting: shell._acknowledge_damage_and_close()
		# The third Mage is a simulated reader of the same damage receipt.
		for serial in game.damage_acknowledgements:
			if game.damage_acknowledgements[serial].has(2): game.acknowledge_damage(int(serial), 2)
		await create_timer(0.05).timeout
		if not game._visuals_busy() and not remote_game._visuals_busy() and not game.visual_poll_pending and not game.resolution_visual_yield_active:
			return
	expect(false, "Visual queues settle: host=%s client=%s" % [game.table_shell.animation_queue, remote_game.table_shell.animation_queue])

func run():
	root.size = Vector2i(1600, 900)
	game = await create_game()
	quiet(game)
	reset_case()
	game.players[0].player_name = "Host"
	game.players[1].player_name = "Friend"
	game.local_viewer_index = 0
	game.players[1].mage.damage_cubes.assign([0,0,0,0,0,0,0,0,0,0])
	game.refresh_all_player_boards()
	remote_game = await create_game(true)
	quiet(remote_game)
	remote_game.local_viewer_index = 1
	var receiver := ClientWire.new()
	var sender := Transport.new()
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
	for instance in [game, remote_game]:
		instance.table_shell.set_process(true)
		instance.beta_hud.set_process(true)
	# Rendering refreshes happen while the last lethal cube is being animated.
	game.deal_damage(0, 1, 1, "spell")
	await create_timer(0.6).timeout
	for i in 3:
		game.players[0].available_cubes -= 1
		sender.publish()
		await create_timer(0.1).timeout
	expect(remote_game.table_shell.animated_damage_ghost, "Remote lethal Damage ghost survives repeated snapshots")
	await settle()
	expect(game.players[1].mage.in_cell and remote_game.players[1].mage.in_cell, "Live defeat resolves into Cell on both peers")
	expect(remote_game.table_shell.damage_display.is_empty() and not remote_game.table_shell.damage_waiting, "Remote damage overlay releases its override and input blocker")
	game.players[1].ready_spells.assign([ReadySpellState.new(game.spell_database.get_spell("tearing"), false)])
	game._start_stepwise_action_activation(1)
	await settle()
	await create_timer(0.3).timeout
	expect(remote_game.get_beta_pending_input(1).get("type") == "action_activation_step", "Next activation after live defeat reaches remote HUD")
	expect(not remote_game.table_shell.board_overlay.visible, "Turn banner does not open remote board automatically")
	remote_game.table_shell.open_board(1)
	expect(remote_game.table_shell.board_overlay.visible, "Remote board opens after complete defeat playback")
	remote_game.table_shell.close_board(true)
	remote_game._on_mage_token_action(1)
	expect(remote_game.beta_hud.action_menu_mode == "physical", "Own Mage token shortcut opens physical Actions from Cell")
	var explore: Dictionary = {}
	for option in remote_game.get_player_board_action_options(1, "physical"):
		if option.action.type == "explore": explore = option
	expect(not explore.is_empty() and receiver.submit_local(1, {"token":explore.get("token", "")}), "Remote Explore submission passes through the real input protocol")
	await settle()
	expect(not game.players[1].mage.in_cell and game.players[1].mage.room_id == remote_game.players[1].mage.room_id, "Remote Explore actually leaves the Cell on both peers")
	game.clear_player_input()
	game.resolution_stack.clear()
	game.action_activation_active = false
	for instance in [game, remote_game]: instance.beta_hud.hand_overlay.hide()
	game.summon_evocation(1, "cadaver", "arena")
	var cadaver: EvocationState = game.players[1].evocations.back()
	await settle()
	game.summon_evocation(1, "pupa", "crypt")
	await settle()
	cadaver.room_id = "crypt"
	game.refresh_model_tokens()
	game.get_room_by_id("black_rose").add_instability_cube(1)
	game.deal_damage(0, AVATAR, 2, "spell")
	await settle()
	await create_timer(0.3).timeout
	for instance in [game, remote_game]:
		# Two games share this test window: only this peer's surfaces may receive input.
		for surface in [game, remote_game]:
			surface.visible = surface == instance
			for canvas in surface.find_children("*", "CanvasLayer", true, false):
				canvas.visible = surface == instance
		instance.table_shell.close_board(true)
		instance.table_shell.card_overlay.hide()
		instance.beta_hud.hand_overlay.hide()
		instance.beta_hud.panel.hide()
		var ev: EvocationState = instance.players[1].evocations[0]
		var token: Node2D = instance.evocation_tokens[ev.get_instance_id()]
		expect(ev.room_id == "crypt" and token.visible and token.modulate.a > 0.99, "Cadaver remains visible after sharing another Evocation's Room")
		if instance.evocation_inspection != null: instance.evocation_inspection.hide()
		var camera = instance.get_node("TableCamera")
		camera.make_current()
		camera.position = token.global_position
		camera.zoom = Vector2.ONE * 2.0
		for i in 4: await process_frame
		var inspect_button = token.get_node("InspectButton")
		await click_at(inspect_button.get_global_transform_with_canvas() * (inspect_button.size * 0.5))
		expect(instance.inspected_evocation == ev and instance.evocation_inspection != null and instance.evocation_inspection.visible, "Real click on moved Cadaver inspects the live model")
		if instance.evocation_inspection != null: instance.evocation_inspection.hide()
		expect(instance.get_room_by_id("black_rose").instability_cubes == [1], "Final Black Rose Room cube stays authoritative after playback")
		expect(instance.players[AVATAR].mage.damage_cubes == [0,0] and instance.avatar_board.damage_track.get_child_count() == 2, "Avatar damage is visible after both presentation queues finish")
	expect(remote_game.table_shell.damage_display.is_empty(), "No stale damage preview hides the Avatar's final cubes")
	print("NOV03 ONLINE ANIMATION: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
