extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1600, 900)
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/main-menu-preview.png")
	menu._solo()
	for i in range(15): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/turn-banner-preview.png")
	quit()
