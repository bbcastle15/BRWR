extends "res://docs/handoff-2026-10-18/checks/avatar_flow.gd"

var seat_count := 4

func create_game(client: bool = false):
	var instance = load("res://game.tscn").instantiate()
	instance.player_count = seat_count
	instance.game_seed = 182026
	instance.enable_beta_hud = true
	instance.run_tests_on_ready = true
	instance.auto_start_game_flow = false
	instance.beta_force_fullscreen = false
	instance.network_client = client
	instance.avatar_selection = {"id":"possessed", "difficulty":"apprentice"}
	root.add_child(instance)
	for i in 6: await process_frame
	instance.table_shell = load("res://tabletop_shell.gd").new()
	instance.add_child(instance.table_shell)
	instance.table_shell.setup(instance)
	instance.beta_hud = load("res://beta_hud.gd").new()
	instance.add_child(instance.beta_hud)
	instance.beta_hud.setup(instance, instance.beta_sidebar_width)
	instance.run_tests_on_ready = false
	instance._apply_beta_table_layout()
	instance.run_tests_on_ready = true
	return instance

func capture(label: String):
	if DisplayServer.get_name() == "headless": return
	for i in 5: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://docs/handoff-2026-10-18/evidence/" + label + ".png")

func run():
	root.size = Vector2i(1600,1000)
	game = await create_game()
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card
	reset_case()
	game.local_viewer_index = 0
	game.players[AVATAR].memories.append(cards.possessed_book_of_nature)
	game.players[AVATAR].memories.append(cards.possessed_corrupted_ray)
	game.summon_evocation(AVATAR, "cadaver", "black_rose")
	await drive()
	damage(AVATAR, [0,1,2])
	game.avatar_board.refresh()
	expect(game.player_boards[AVATAR] == game.avatar_board, "Avatar uses its actual Board, never a PlayerBoard")
	expect(game.avatar_board.visible, "Avatar Board stays visible on table")
	game.table_shell.open_board(AVATAR)
	expect(game.avatar_board.expanded and game.avatar_board.get_parent() == game.table_shell.board_stage, "Actual Avatar Board opens fullscreen")
	expect(game.avatar_board.cards_root.get_node("AvatarMemories") != null, "Discard pile is clickable")
	expect(game.avatar_board.damage_track.get_child_count() == 3, "Damage cube choices have nodes on Avatar Board")
	expect(game._evocation_board_card(AVATAR, game.players[AVATAR].evocations[0]) != null, "Evocation card belongs to Avatar Board")
	expect(game.show_board_target_choice({"token":"damage:0:0", "cube_player_index":AVATAR}, func(): pass), "Cube choices target the actual Avatar damage track")
	game.clear_board_target_choices()
	await capture("avatar-board-fullscreen")
	game.avatar_board.open_memories()
	var preview = game._reference_card_preview()
	expect(preview.pile_cards.size() == 2, "All discarded Commands are browsable")
	expect(preview.art.texture == AvatarArt.texture("possessed_corrupted_ray"), "Discard inspection uses HD Command art")
	await capture("avatar-memories-fullscreen")
	preview.hide_preview()
	game.table_shell.close_board()
	expect(not game.avatar_board.expanded and game.avatar_board.get_parent() == game, "Closing restores same Board to table")
	await capture("avatar-board-table")
	print("AVATAR BOARD UI: ",checks," assertions; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
