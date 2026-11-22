extends SceneTree

func _initialize():
	call_deferred("render_rooms")

func render_rooms():
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = Vector2i(1800, 1100)
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/rooms.json"))
	var container := Node2D.new()
	root.add_child(container)
	var rooms: Array = []
	for definition in definitions:
		if not definition.get("wrecks_on_completion", false): continue
		var i := rooms.size()
		var room = load("res://room.tscn").instantiate()
		room.radius = 205.0
		room.setup_room(definition)
		room.position = Vector2(230 + (i % 4) * 445, 290 + int(i / 4) * 490)
		container.add_child(room)
		rooms.append(room)
		for n in room.get_instability_resistance(): room.add_instability_cube(n % 4, false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build-user-data/kami_rooms_intact.png"))
	for room in rooms:
		room.clear_instability()
		room.activated_this_turn = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build-user-data/kami_rooms_used.png"))
	for room in rooms: room.set_rebuilt(true, false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build-user-data/kami_rooms_wrecked.png"))
	quit()
