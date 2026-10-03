extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in range(8):
		await process_frame

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	await settle()
	game.enable_beta_hud = true
	game._apply_beta_table_layout()
	root.size_changed.connect(game._on_beta_viewport_resized)
	await settle()
	var camera = game.get_node("TableCamera")
	check(camera.zoom.x > camera.minimum_zoom(), "Initial view focuses the Lodge for readable Rooms")
	camera.reset_view()
	for screen_size in [Vector2i(1366, 768), Vector2i(1920, 1200), Vector2i(2560, 1080), Vector2i(1280, 800)]:
		root.size = screen_size
		root.content_scale_size = screen_size
		await settle()
		var bounds: Rect2 = game.get_tabletop_bounds()
		check(camera.position.is_equal_approx(bounds.get_center()), "Resizing must keep the whole table centered")
		check(is_equal_approx(camera.zoom.x, camera.minimum_zoom()), "Overview must refit in both zoom directions")
		var drawn_size: Vector2 = bounds.size * camera.zoom
		var view: Vector2 = root.get_visible_rect().size
		check(drawn_size.x <= view.x + 1 and drawn_size.y <= view.y + 1, "All boards must fit on screen")
		check(absf(drawn_size.x - view.x) < 1 or absf(drawn_size.y - view.y) < 1, "Overview must fill at least one screen dimension")
	camera.zoom_at(root.get_visible_rect().size * 0.5, 1.5)
	var ratio: float = camera.zoom.x / camera.minimum_zoom()
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	await settle()
	check(is_equal_approx(camera.zoom.x / camera.minimum_zoom(), ratio), "Resize must preserve manual relative zoom")
	camera.reset_view()
	check(is_equal_approx(camera.zoom.x, camera.minimum_zoom()), "Home must restore automatic fit")
	print("SCREEN LAYOUT PLAYTEST: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
