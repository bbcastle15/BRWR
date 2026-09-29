extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1770, 919)
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = true
	game.beta_force_fullscreen = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(8):
		await process_frame
	game.clear_player_input()
	game.get_node("TableCamera").reset_view()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/table-preview.png")
	game.request_player_input({"type": "study_keep_cards", "player_index": 0, "cards": [
		{"draw_index": 0, "id": "emet_met", "name": "Emet-Met"},
		{"draw_index": 1, "id": "soul_transfer", "name": "Soul Transfer"},
		{"draw_index": 2, "id": "pain_mark", "name": "Pain Mark"},
		{"draw_index": 3, "id": "cube_of_lamentations", "name": "Cube of Lamentations"}]})
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/study-preview.png")
	quit()
