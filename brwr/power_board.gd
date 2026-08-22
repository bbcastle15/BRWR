extends Control
var marker_scene = preload("res://power_marker.tscn")
var threshold_markers: Array = []
var black_rose_marker
var player_markers: Array = []
@export var second_moon_threshold: int = 6
@export var third_moon_threshold: int = 18
@export var end_game_threshold: int = 30

var black_rose_power: int = 0
var player_power: Array[int] = []


func _ready():
	create_power_track()


func initialize(player_count: int):
	player_power.clear()

	for i in range(player_count):
		player_power.append(0)

	black_rose_power = 0

	create_power_markers(player_count)
	create_threshold_markers()

	await get_tree().process_frame

	update_all_markers()
	update_threshold_markers()

	print("Power Board initialized for ", player_count, " players")

func update_all_markers():
	update_black_rose_marker()

	for i in range(player_markers.size()):
		update_player_marker(i)
		
func get_power_position(value: int) -> Vector2:
	var power_track = $PowerTrack

	if value < 0 or value >= power_track.get_child_count():
		return Vector2.ZERO

	var slot = power_track.get_child(value)

	return power_track.position + slot.position + slot.size / 2.0
	
func create_power_markers(player_count: int):
	if black_rose_marker != null:
		black_rose_marker.queue_free()

	for marker in player_markers:
		if marker != null:
			marker.queue_free()

	player_markers.clear()

	black_rose_marker = marker_scene.instantiate()
	black_rose_marker.marker_name = "BR"
	black_rose_marker.marker_color = Color.BLACK
	add_child(black_rose_marker)

	var colors = [
		Color.RED,
		Color.BLUE,
		Color.GREEN,
		Color.PURPLE,
		Color.YELLOW,
		Color.WHITE
	]

	for i in range(player_count):
		var marker = marker_scene.instantiate()

		marker.marker_name = str(i + 1)
		marker.marker_color = colors[i]

		add_child(marker)
		player_markers.append(marker)
func create_power_track():
	var power_track = $PowerTrack

	for child in power_track.get_children():
		child.free()

	for value in range(end_game_threshold + 1):
		var label = Label.new()

		label.text = str(value)
		label.custom_minimum_size = Vector2(38, 30)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		power_track.add_child(label)

func set_player_power(player_index: int, value: int):
	if player_index < 0 or player_index >= player_power.size():
		print("ERRORE: player_index non valido: ", player_index)
		return

	value = clamp(value, 0, end_game_threshold)

	player_power[player_index] = value
	update_player_marker(player_index)


func set_black_rose_power(value: int):
	value = clamp(value, 0, end_game_threshold)

	black_rose_power = value
	update_black_rose_marker()
	
func update_player_marker(player_index: int):
	var value = player_power[player_index]
	var marker = player_markers[player_index]

	var slot_position = get_power_position(value)

	marker.position = slot_position + get_marker_offset(player_index)

func get_marker_offset(player_index: int) -> Vector2:
	var offsets = [
		Vector2(-4, -12),
		Vector2(4, -12),
		Vector2(-4, -4),
		Vector2(4, -4),
		Vector2(-4, 4),
		Vector2(4, 4)
	]

	return offsets[player_index]
	
func update_black_rose_marker():
	var slot_position = get_power_position(black_rose_power)

	black_rose_marker.position = slot_position + Vector2(-12, -12)

func create_threshold_markers():
	for marker in threshold_markers:
		if marker != null:
			marker.free()

	threshold_markers.clear()

	var second_moon_marker = marker_scene.instantiate()
	second_moon_marker.marker_name = "II"
	second_moon_marker.marker_color = Color.GRAY
	add_child(second_moon_marker)
	threshold_markers.append(second_moon_marker)

	var third_moon_marker = marker_scene.instantiate()
	third_moon_marker.marker_name = "III"
	third_moon_marker.marker_color = Color.YELLOW
	add_child(third_moon_marker)
	threshold_markers.append(third_moon_marker)

	var end_game_marker = marker_scene.instantiate()
	end_game_marker.marker_name = "END"
	end_game_marker.marker_color = Color.DARK_RED
	add_child(end_game_marker)
	threshold_markers.append(end_game_marker)
	
func update_threshold_markers():
	if threshold_markers.size() < 3:
		return

	threshold_markers[0].position = (
		get_power_position(second_moon_threshold)
		+ Vector2(-12, -12)
	)

	threshold_markers[1].position = (
		get_power_position(third_moon_threshold)
		+ Vector2(-12, -12)
	)

	threshold_markers[2].position = (
		get_power_position(end_game_threshold)
		+ Vector2(-12, -12)
	)
