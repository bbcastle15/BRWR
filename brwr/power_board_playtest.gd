extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var board = load("res://power_board.tscn").instantiate()
	root.add_child(board)
	await process_frame
	await board.initialize(6)
	check(board.player_markers[0].get_node("TokenArt").size == Vector2(22, 22), "Imported high-resolution token must retain its tabletop size")
	check(board.get_node("PowerTrack").get_child_count() == 36, "Physical track has 36 spaces, 0 through 35")
	check(is_equal_approx(board.get_power_position(0).x, board.get_power_position(11).x), "First twelve spaces share a column after clockwise rotation")
	check(board.get_power_position(12).x < board.get_power_position(0).x, "Second row is left of the first after rotation")
	check(absf(board.get_power_position(12).y - board.get_power_position(0).y) < 2.0, "Each column restarts at the top of the slightly irregular printed grid")
	check(board.get_node("QuestSlot").position.y < board.get_node("EvocationSlot").position.y, "Decks follow Quest, Evocation, Jinx, Upgrade")
	check(board.get_node("EvocationSlot").position.y < board.get_node("JinxSlot").position.y, "Evocation precedes Jinx")
	for i in range(6):
		board.set_player_power(i, 18)
		check(board.player_markers[i].position == board.get_power_position(18) + board.get_marker_offset(i), "Player marker follows its score")
	board.set_black_rose_power(18)
	var centroid := Vector2.ZERO
	for marker in board.player_markers + [board.black_rose_marker]:
		centroid += marker.position
	check((centroid / 7.0).is_equal_approx(board.get_power_position(18)), "Shared markers remain centered as a group")
	board.set_player_power(0, 42)
	check(board.player_markers[0].position == board.get_power_position(7), "Unshared player marker is centered exactly")
	board.set_black_rose_power(9)
	check(board.black_rose_marker.position == board.get_power_position(9), "Unshared Rose marker is centered exactly")
	check(board.player_markers[0].get_node("Label").text == "+35", "Final scoring overflow remains visible")
	board.end_game_threshold = 30
	board.update_threshold_markers()
	check(board.get_node("PowerTrack").get_child_count() == 36, "Changing trigger does not truncate physical track")
	board.queue_free()
	await process_frame
	print("POWER BOARD: ", "PASS" if failures == 0 else "FAIL " + str(failures))
	quit(0 if failures == 0 else 1)
