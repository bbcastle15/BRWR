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
		for i in range(capacity):
			check(room.add_instability_cube(i % 2), "Cannot fill room")
		check(not room.add_instability_cube(0), "Room exceeded capacity")
		check(room.remove_instability_cube(0), "Cannot remove cube")
		room.clear_instability()
		room.flipped = true
		check(room.get_node("RoomName").visible, "Rebuilt state must cover destroyed rule")
		check(room.get_effects() == definition.rebuilt_effects, "Artwork changed room rules")
		room.queue_free()
	var cell = load("res://cell.tscn").instantiate()
	cell.radius = 78.0
	root.add_child(cell)
	check(cell.get_node("Background").texture != null, "Missing Cell artwork")
	cell.queue_free()
	print("ROOM ART PLAYTEST: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
