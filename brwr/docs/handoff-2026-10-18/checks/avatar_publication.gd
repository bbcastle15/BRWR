extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func _initialize():
	call_deferred("run")
	create_timer(180).timeout.connect(func(): push_error("Avatar publication timeout"); quit(2))

func run():
	root.size = Vector2i(1737,1000)
	game = await create_game()
	reset_case()
	game.local_viewer_index = 0
	var board = game.avatar_board
	expect(board.get_node("BoardFrame").texture.resource_path.ends_with("production/board.svg"), "Board renders native vector asset, not source screenshot")
	for moon in [1,2,3]:
		game.current_moon = moon
		board.refresh()
		var deck = board.cards_root.get_children()[1]
		expect(deck.get_child(0).texture == AvatarArt.texture("command_back_%d" % moon), "Unrevealed deck uses corresponding Moon back")
		var back: Texture2D = AvatarArt.texture("command_back_%d" % moon)
		expect(back != null and back.get_width() >= 1000, "Moon back restored at publication resolution")
	game.current_moon = 1
	game.players[AVATAR].mage.destiny_tokens.assign([0,1])
	game.players[AVATAR].mage.infectio_tokens.assign([2])
	damage(AVATAR,[0,1,2,0,1,2,0,1,2,0,1,2])
	board.refresh()
	expect(board.cards_root.get_node_or_null("DestinyToken0") != null and board.cards_root.get_node_or_null("DestinyToken1") != null, "Destiny tokens are on Avatar sheet")
	expect(board.cards_root.get_node_or_null("InfectioToken0") != null, "Infectio token is on Avatar sheet")
	expect(board.get_node("HealthLimit").get_child(0) is Line2D, "Health limit is hollow, preserving last damage cube")
	expect(board.damage_track.get_child(11).get_node("DamageCube").cube_color == game.players[2].color, "Last damage retains its owning player's color")
	for i in 3: await process_frame
	game.table_shell.open_board(AVATAR)
	await capture("avatar-production-board")
	expect(board.expanded and game.table_shell.board_overlay.visible, "Portrait publication board stays open for consultation")
	game.table_shell.close_board()
	var ev = game.summon_evocation(AVATAR,"colossus","black_rose")
	await drive()
	expect(game.show_board_target_choice({"token":"evocation:3:0", "owner_id":AVATAR,"evocation_index":0},func():pass), "Avatar Evocation can be targeted")
	expect(not game.table_shell.board_overlay.visible, "Targeting Avatar Evocation leaves Lodge visible")
	game.clear_board_target_choices()

	reset_case()
	game.current_phase = game.PHASE_PREPARATION
	game.current_phase_play_order.assign([0])
	game.preparation_phase_cursor = 0
	game.players[0].hand.assign([game.spell_database.get_spell("raging_lash"),game.spell_database.get_spell("empathy")])
	game.request_player_input(game._make_parallel_preparation_request(0))
	var overlay = game.beta_hud.hand_overlay
	overlay.ready_hand_indices.assign([0,1])
	overlay.ready_dark_sides.assign([false,true])
	overlay._update_controls()
	for owner in [0,AVATAR]:
		game.beta_hud.open_public_memories(owner)
		expect(overlay.mode == overlay.MODE_PREPARATION and overlay.current_request.get("type") == "preparation", "Memories inspection preserves Preparation mode and request")
		expect(overlay.ready_hand_indices == [0,1] and overlay.ready_dark_sides == [false,true], "Memories inspection preserves prepared spell draft")
		game._reference_card_preview().hide_preview()
	game.beta_hud._open_hand_overlay()
	expect(overlay.visible and overlay.confirm_button.visible, "Preparation can be reopened and confirmed after inspecting Memories")
	overlay._confirm_preparation()
	expect(game.players[0].ready_spells.size() == 2, "Preparation accepts draft after Memories inspection")

	for id in ["possessed_release_energy","possessed_revenge_of_the_thorn","avatar_traces_of_texture"]:
		var texture: Texture2D = AvatarArt.texture(id)
		expect(not texture is AtlasTexture and texture.resource_path.contains("/approved/"), "Runtime uses restored HD face")
	print("AVATAR PUBLICATION: ",checks," assertions; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
