extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func _initialize():
	call_deferred("run")
	create_timer(240).timeout.connect(func(): push_error("Avatar layouts timeout"); quit(2))

func run():
	root.size = Vector2i(1600,1000)
	for count in [2,3,4,5,6]:
		seat_count = count
		game = await create_game()
		var actor: int = game.avatar.player_index
		expect(actor == count - 1, "%d seats: Avatar is last participant" % count)
		expect(game.player_boards[actor] == game.avatar_board and game.avatar_board.visible, "%d seats: Avatar Board visible, no PlayerBoard" % count)
		game.table_shell.open_board(actor)
		expect(game.avatar_board.expanded, "%d seats: fullscreen opens" % count)
		var modal_transform: Transform2D = game.avatar_board.transform
		game.update_table_layout()
		expect(game.avatar_board.transform == modal_transform, "%d seats: layout refresh preserves fullscreen transform" % count)
		game.table_shell.close_board()
		expect(game.avatar_board.get_parent() == game and game.avatar_board.visible, "%d seats: Board returns to Lodge" % count)
		await capture("avatar-layout-%d-seats" % count)
		game.queue_free()
		await process_frame
	print("AVATAR LAYOUTS: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
