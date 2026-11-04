extends "res://docs/handoff-2026-10-18/checks/nov03_school_draw.gd"

class LobbyWire extends "res://online_session.gd":
	var other
	func _send_game_to_peer(_id: String, packet: Dictionary) -> Error:
		other._handle_game_message("host", Marshalls.base64_to_variant(Marshalls.variant_to_base64(packet,false),false))
		return OK
	func _send_game_to_host(packet: Dictionary) -> Error:
		other._handle_game_message("friend", Marshalls.base64_to_variant(Marshalls.variant_to_base64(packet,false),false))
		return OK

func run():
	root.size = Vector2i(1280, 720)
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._solo()
	expect(menu.menu.visible and menu.session.game == null, "No game starts before the player enters a name")
	expect(menu.message.text.contains("Enter your name"), "Empty username receives an explicit instruction")
	menu.username.text = "  [Alessandro]  "
	expect(menu._accept_username() and menu.session.display_name == "Alessandro", "Main menu accepts and sanitizes the player name")
	await capture("nov03-playtest-name-entry")
	menu.queue_free()
	await process_frame
	var host_wire := LobbyWire.new()
	var client_wire := LobbyWire.new()
	root.add_child(host_wire)
	root.add_child(client_wire)
	host_wire.other = client_wire
	client_wire.other = host_wire
	host_wire.hosting = true
	host_wire.connected = true
	host_wire.peer_players = {"friend":1}
	host_wire.seat_names = {0:"Host"}
	client_wire.display_name = "  Friend [1]  "
	expect(not host_wire.can_start(), "Lobby waits for the remote player profile")
	host_wire._update_lobby()
	expect(host_wire.can_start() and host_wire.seat_names[1] == "Friend 1", "Name exchange enables Start with sanitized seat names")
	expect(client_wire.seat_names == host_wire.seat_names, "Both peers see the same roster names")
	host_wire._handle_game_message("unknown", {"op":"profile","name":"Intruder"})
	expect(host_wire.seat_names.size() == 2, "Only an assigned peer can set a player name")
	host_wire.queue_free()
	client_wire.queue_free()
	seat_count = 6
	game = await create_game()
	quiet(game)
	reset_case()
	game.local_viewer_index = 0
	var shell = game.table_shell
	for i in game.players.size()-1:
		game.players[i].player_name = ["Alessandro", "Beatrice", "Carlo", "Diana", "Elena"][i]
		game.players[i].school_id = ["technomancy", "druidic", "death", "nightmare", "hex"][i]
	game.players[0].mage_id = "bartholomaus"
	shell._layout()
	shell._refresh_banners()
	for i in 5: await process_frame
	var column = shell.sidebar.get_parent().get_parent()
	var sizes: Array[Vector2] = []
	for child in column.get_children():
		if child is Button: sizes.append(child.size)
	expect(sizes.size() == 6 and sizes.all(func(size):return size.is_equal_approx(sizes[0])), "All six sidebar controls have identical dimensions")
	expect(shell.banners[0].get_node("Detail").text.contains("◇ Technomancy"), "Mage and School are shown together with a diamond")
	expect(shell.banners.all(func(b): return b.get_node("Detail").visible), "Six-player layout retains Mage/School details in the scrollable rail")
	await capture("nov03-playtest-sidebar-720p")
	game.players[0].hand.assign([game.spell_database.get_spell("natural_invocation")])
	game.beta_hud.hand_overlay.open_browse(0)
	game.beta_hud.hand_overlay.hide()
	game.beta_hud.current_request = {"type":"preparation"}
	game.beta_hud._sync_hand_confirmation(game.beta_hud.hand_overlay.confirm_button)
	expect(not game.beta_hud.decision_bar.visible, "Hidden Hand leaves no redundant Show cards button")
	for kind in ["jinxs", "upgrades"]:
		expect(game.ReferenceCardPreview.card_texture(kind,"back") != null, "High quality deck back loads: " + kind)
	for id in game.quest_database.quests:
		var texture = game.ReferenceCardPreview.card_texture("quests", id)
		expect(texture != null and texture.resource_path.contains("/symbols/"), "Quest uses the new symbols: " + id)
	game._reference_card_preview().show_card("quests", "magic_stem", "Magic Steam", "")
	await capture("nov03-playtest-quest-symbols")
	game._reference_card_preview().hide_preview()
	for index in [1, game.avatar.player_index]:
		DeathEffectResolver.resolve({"type":"assign_destiny","amount":1}, {"game":game,"caster_id":0,"target_player_index":index})
		shell._play_next_animation()
		await create_timer(0.6).timeout
		expect(shell.animated_trophy_ghost and is_instance_valid(shell.animated_node), "Destiny placement animates on the correct board: " + str(index))
		shell.animation.pause()
		expect(shell.animated_node.is_visible_in_tree() and shell.animated_node.modulate.a > 0.5, "Destiny placement is visible before the pause: " + str(index))
		if index == 1: expect(game.player_boards[index].get_node("DestinyTokens").get_child(0).size == Vector2(42,42), "Mage Destiny token is slightly larger")
		await capture("nov03-playtest-destiny-"+str(index))
		shell.animation.play()
		await create_timer(1.4).timeout
		expect(shell.animation == null and game.players[index].mage.destiny_tokens == [0], "Destiny presentation ends without altering its ownership")
	quiet(game)
	game.players[0].ready_spells.assign([ReadySpellState.new(game.spell_database.get_spell("tearing"), false)])
	game._start_stepwise_action_activation(0)
	shell._process(0)
	expect(shell.phase_notice != null, "An activation emits the player turn banner")
	await create_timer(0.5).timeout
	await capture("nov03-playtest-turn-banner")
	await create_timer(1.3).timeout
	shell._process(0)
	game.beta_hud.present_pending_request(game.get_beta_pending_input(0))
	expect(not shell.board_overlay.visible, "Action input leaves the PlayerBoard closed")
	game.get_node("TableCamera").make_current()
	game.get_node("TableCamera").position = game.mage_tokens[0].position
	game.get_node("TableCamera").zoom = Vector2.ONE * 2.0
	for i in 4: await process_frame
	var button: Button = game.mage_tokens[0].get_node("ActionButton")
	await click_at(button.get_global_transform_with_canvas() * (button.size*0.5))
	expect(game.beta_hud.action_menu_mode == "physical", "Real left click on own Mage token opens Physical Actions")
	print("NOV03 PLAYTEST UI: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
