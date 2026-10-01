extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/rooms.json"))
	for definition in definitions:
		var room = load("res://room.tscn").instantiate()
		room.radius = 78.0
		room.setup_room(definition)
		root.add_child(room)
		check(room.get_node("Background").texture != null, "Missing art: " + room.room_id)
		check(room.get_node("Background").polygon.size() == 6, "Room hex geometry changed")
		check(not room.get_node("RoomName").visible, "Duplicate name over artwork")
		var capacity: int = room.get_instability_resistance()
		check(room.get_art_instability_slots().size() == capacity, "Wrong slot projection")
		var slots: PackedVector2Array = room.get_art_instability_slots()
		for i in range(1, slots.size()):
			check(slots[i - 1].x < slots[i].x, "Slots must fill left to right, including slanted edges: " + room.room_id)
		for i in range(capacity):
			check(room.add_instability_cube(i % 2), "Cannot fill room")
		for i in range(capacity):
			var cube: Control = room.instability_cube_nodes[i]
			check((cube.get_transform() * (cube.size * 0.5)).is_equal_approx(slots[i]), "Cube centre must stay on its socket after scaling/rotation: " + room.room_id)
			var expected_angle := 0.0
			if capacity > 5 and i < (capacity - 4) / 2:
				expected_angle = -30.0
			elif capacity > 5 and i >= (capacity + 4) / 2:
				expected_angle = 30.0
			check(is_equal_approx(cube.rotation_degrees, expected_angle), "Cube must follow socket orientation: " + room.room_id)
		check(not room.flipped, "Filling instability must not flip the room before cleanup")
		check(not room.add_instability_cube(0), "Room exceeded capacity")
		check(room.remove_instability_cube(0), "Cannot remove cube")
		for i in range(room.instability_cube_nodes.size()):
			var cube: Control = room.instability_cube_nodes[i]
			check((cube.get_transform() * (cube.size * 0.5)).is_equal_approx(slots[i]), "Removed cube must leave remaining cubes centred in their new slots")
			check(is_equal_approx(cube.rotation, room.get_art_instability_slot_rotation(slots[i])), "Repacking must also update the cube's angle")
		room.clear_instability()
		var destroyed_texture = room.get_node("Background").texture
		check(not room.get_node("ActivationToken").visible, "Destroyed rooms must not show activation tokens")
		room.flipped = true
		var token = room.get_node("ActivationToken")
		check(token.visible and token.texture != null, "Rebuilt room must have an available token: " + room.room_id)
		check(not room.get_node("RoomName").visible, "Rebuilt artwork must not have duplicate labels")
		check(room.get_node("Background").texture != destroyed_texture, "Rebuilt room must swap tile: " + room.room_id)
		var available_texture = token.texture
		room.mark_activated()
		check(token.texture != null and token.texture != available_texture, "Using room must flip token")
		check(not room.can_activate(), "Used rebuilt room must reject normal reactivation")
		room.reset_activation()
		check(token.texture == available_texture and room.can_activate(), "Reset must restore available face")
		room.activated_this_turn = true
		check(token.texture != available_texture, "Network state assignment must update token")
		check(room.get_effects() == definition.rebuilt_effects, "Artwork changed room rules")
		room.flipped = false
		check(not token.visible and room.get_node("Background").texture == destroyed_texture, "Restoring destroyed state must restore art and hide token")
		room.queue_free()
	var cell = load("res://cell.tscn").instantiate()
	cell.radius = 78.0
	root.add_child(cell)
	check(cell.get_node("Background").texture != null, "Missing Cell artwork")
	cell.queue_free()
	print("ROOM ART PLAYTEST: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
