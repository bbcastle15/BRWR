extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/spells.json"))
	var forgotten_count := 0
	for definition in definitions:
		if not bool(definition.get("forgotten", false)):
			continue
		var id: String = definition["id"]
		assert(VisualAssets.load_spell_texture(id) != null, "Missing Forgotten art: " + id)
		assert(SpellArtResolver.get_texture(id, "forgotten") != null, "Missing inspector art: " + id)
		print("Forgotten texture OK: ", id)
		forgotten_count += 1
	assert(forgotten_count == 3)
	root.size = Vector2i(1200, 760)
	var colors: Array[Color] = [Color.RED, Color.BLUE, Color.YELLOW, Color.GREEN, Color.WHITE, Color.BLACK]
	for i in colors.size():
		var cell = load("res://cell.tscn").instantiate()
		cell.radius = 190.0
		cell.cell_color = colors[i]
		cell.position = Vector2(205 + (i % 3) * 395, 195 + (i / 3) * 370)
		root.add_child(cell)
		assert(not cell.get_node("CellName").visible)
		assert(cell.get_node("OwnerBorder").default_color == colors[i])
		assert(cell.get_node("Background").material.get_shader_parameter("owner_color") == colors[i])
	for frame in range(4):
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/cell-colors-preview.png")
	print("CELL / FORGOTTEN ASSETS CHECK PASSED")
	quit()
