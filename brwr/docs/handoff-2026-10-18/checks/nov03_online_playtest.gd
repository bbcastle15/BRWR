extends "res://docs/handoff-2026-10-18/checks/nov02_avatar_marker_playtest.gd"

class Transport extends "res://online_session.gd":
	var remote
	var packets: Array = []
	func _send_game_to_peer(_id: String, payload: Dictionary) -> Error:
		# The real wire codec, including typed Arrays and Vector2i coordinates.
		var packet = Marshalls.base64_to_variant(Marshalls.variant_to_base64(payload, false), false)
		packets.append(packet)
		if remote != null:
			remote._handle_game_message("host", packet)
		return OK

func run():
	root.size = Vector2i(1600, 900)
	game = await create_game()
	quiet(game)
	reset_case()
	game.local_viewer_index = 0
	game.players[0].player_name = "Host"
	game.players[1].player_name = "Friend"
	var client = await create_game(true)
	quiet(client)
	client.local_viewer_index = 1
	var receiver = load("res://online_session.gd").new()
	receiver.game = client
	receiver.connected = true
	receiver.local_player = 1
	client.network_session = receiver
	root.add_child(receiver)
	var sender := Transport.new()
	root.add_child(sender)
	sender.hosting = true
	sender.connected = true
	sender.game = game
	sender.peer_players = {"friend": 1}
	sender.receiving = {"friend": true}
	sender.remote = receiver
	game.network_session = sender
	sender.publish()
	var packet_count := sender.packets.size()
	sender.publish()
	expect(sender.packets.size() == packet_count, "Identical projections do not flood the relay")
	var spell = game.spell_database.get_spell("emet_met")
	game._present_resolution_card({"type":"spell_resolution","spell":spell,"use_dark_side":true,"context":{"caster_id":0}})
	expect(sender.packets.back().op == "card_reveal" and client.card_presentation.id == spell.id, "Public face reaches guest before the next snapshot")
	expect(client.table_shell.card_overlay.visible and client.table_shell.card_overlay.modulate.a == 1.0 and client.card_presentation.dark, "Guest sees the active side at full opacity immediately")
	game._finish_card_presentation(game.card_presentation_serial)
	sender.publish()
	expect(client.players[1].player_name == "Friend", "Username reaches the remote authoritative PlayerState")
	expect(game.player_reference_text("Player 1 chose Player 2; Player 20 stays literal.") == "Host chose Friend; Player 20 stays literal.", "Legacy UI labels use names without altering longer identifiers")
	# No input request/feedback between these mutations and the scheduled sync.
	game.suppress_placement_feedback = true
	game.summon_evocation(1, "cadaver", "arena")
	var cadaver: EvocationState = game.players[1].evocations.back()
	game.summon_evocation(1, "pupa", "crypt")
	quiet(game)
	game.clear_player_input()
	game.resolution_stack.clear()
	sender._process(0.3)
	expect(client.players[1].evocations.size() == game.players[1].evocations.size(), "Unprompted summon reaches client")
	var remote_cadaver: EvocationState = client.players[1].evocations[0]
	var remote_id := remote_cadaver.get_instance_id()
	cadaver.room_id = "crypt"
	game.refresh_model_tokens()
	game.get_room_by_id("black_rose").add_instability_cube(1, false)
	game.players[AVATAR].mage.damage_cubes.assign([0, 1, 1, 2])
	sender._process(0.3)
	expect(client.players[1].evocations[0].get_instance_id() == remote_id and remote_cadaver.room_id == "crypt", "Movement preserves Evocation instance and inspection binding")
	expect(client.get_room_by_id("black_rose").instability_cubes == [1], "Last Instability is sent without another choice")
	expect(client.players[AVATAR].mage.damage_cubes == [0, 1, 1, 2], "Avatar authoritative Damage is identical")
	expect(client.avatar_board.damage_track.get_child_count() == 4, "Avatar board displays all authoritative Damage")
	client.table_shell._cancel_animation()
	client.table_shell.close_board()
	client.open_evocation_inspection(remote_cadaver)
	expect(client.inspected_evocation == remote_cadaver and client.evocation_inspection.visible, "Moved Cadaver remains inspectable")
	client.evocation_inspection.hide()
	# Defeat, Cell and subsequent Action input use the actual rules and transport.
	locate(1, "arena")
	var shell = game.table_shell
	game.table_shell = null
	game.deal_damage(0, 1, 30, "spell")
	await drive()
	game.table_shell = shell
	quiet(game)
	expect(game.players[1].mage.in_cell, "Lethal Damage returns remote Mage to Cell")
	game.players[1].ready_spells.assign([ReadySpellState.new(game.spell_database.get_spell("tearing"), false)])
	game.table_shell = null
	game._start_stepwise_action_activation(1)
	game.table_shell = shell
	sender._process(0.3)
	quiet(client)
	client.beta_hud.present_pending_request(client.get_beta_pending_input(1))
	expect(client.players[1].mage.in_cell, "Cell location reaches client")
	expect(not client.table_shell.board_overlay.visible, "A new Action does not automatically open the board")
	client.table_shell.open_board(1)
	expect(client.table_shell.board_overlay.visible, "Remote Mage can open its board after defeat")
	expect(not client.get_player_board_action_options(1, "physical").is_empty(), "Explore remains available from Cell")
	expect(client.get_beta_pending_input(1).get("type") == "action_activation_step", "Remote Action request remains actionable")
	expect(not game._beta_momentum_destinations(1).has(""), "Momentum must leave the Cell")
	locate(1, "arena")
	expect(game._beta_momentum_destinations(1).has(""), "Momentum may stay in an ordinary Room")
	expect(client.beta_hud.hand_overlay._resolve_card_texture({"id":"natural_invocation","school_id":"druidic"}) != null, "Natural Invocation uses shared art fallback in Hand")
	expect(game._public_effect_choice_description("druidic_choice", {}, "Choose an Upgrade.", "school_upgrade") == "Choose an Upgrade.", "Upgrade waiting does not claim Druidic")
	expect(not game._public_effect_choice_description("unknown_resolver", {}, "Secret Card").contains("Secret"), "Waiting fallback never leaks a hidden name")
	var before: int = game.table_feedback_serial
	game.clear_player_input()
	game.resolution_stack.clear()
	game._start_stepwise_action_activation(1)
	expect(game.table_feedback_serial > before and game.table_feedback_events.back().kind == "turn", "Consecutive activation records a fresh turn banner")
	print("NOV03 ONLINE: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
