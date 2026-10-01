extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(640, 480)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2200, 1520)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/rooms.json"))
	var rooms: Array = []
	for i in range(definitions.size()):
		var room = load("res://room.tscn").instantiate()
		room.radius = 200.0
		room.setup_room(definitions[i])
		room.position = Vector2(220 + (i % 5) * 440, 190 + (i / 5) * 375)
		viewport.add_child(room)
		room.flipped = true
		rooms.append(room)
	DirAccess.make_dir_recursive_absolute("res://output")
	for used in [false, true]:
		for room in rooms:
			room.activated_this_turn = used
		await process_frame
		await RenderingServer.frame_post_draw
		var state: String = "used" if used else "available"
		viewport.get_texture().get_image().save_png("res://output/rooms-rebuilt-%s.png" % state)
	quit()
