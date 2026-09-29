extends Control
const SMALL_CARD_SIZE = Vector2(80, 52)

const RECT_X = 145.0
const RECT_WIDTH = 161.0
const CARD_GAP = 5.0
const CARD_X = 35.0
const UPPER_HEX_Y = 185.0
const LOWER_HEX_Y = 355.0

var marker_scene = preload("res://power_marker.tscn")
var threshold_markers: Array = []
var black_rose_marker
var player_markers: Array = []
@export var second_moon_threshold: int = 6
@export var third_moon_threshold: int = 18
@export var end_game_threshold: int = 35

var black_rose_power: int = 0


func _ready():
	create_board_shape()
	create_power_track()

	await get_tree().process_frame

	setup_card_slots()
	center_power_track()


func initialize(player_count: int):
	create_power_markers(player_count)
	create_threshold_markers()

	await get_tree().process_frame

	update_all_markers()
	update_threshold_markers()

	print("Power Board initialized for ", player_count, " players")

func update_all_markers():
	update_black_rose_marker()

	for i in range(player_markers.size()):
		update_player_marker(i, 0)

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
		label.custom_minimum_size = Vector2(48, 34)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		power_track.add_child(label)

func set_player_power(player_index: int, value: int):
	if player_index < 0 or player_index >= player_markers.size():
		print("ERRORE: player_index non valido: ", player_index)
		return

	value = maxi(0, value)

	update_player_marker(player_index, value)


func set_black_rose_power(value: int):
	value = maxi(0, value)

	black_rose_power = value
	update_black_rose_marker()
	
func update_player_marker(player_index: int, value: int):
	var marker = player_markers[player_index]
	var slot_position = get_power_position(value % end_game_threshold if value > end_game_threshold else value)
	marker.get_node("Label").text = "+" + str(int(value / end_game_threshold) * end_game_threshold) if value > end_game_threshold else marker.marker_name

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
	var slot_position = get_power_position(black_rose_power % end_game_threshold if black_rose_power > end_game_threshold else black_rose_power)
	black_rose_marker.get_node("Label").text = "+" + str(int(black_rose_power / end_game_threshold) * end_game_threshold) if black_rose_power > end_game_threshold else "BR"

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
	
func create_board_shape():
	var shape = $BoardShape

	# Geometria dell'incastro: NON TOCCARE
	var r = 70.0
	var half_r = r / 2.0
	var hex_h = sqrt(3.0) * r

	# Connessione più corta del 30%
	var rect_x = 145.0

	# Manteniamo fisso il centro
	var center_y = 325.0

	var upper_center_y = center_y - hex_h / 2.0
	var lower_center_y = center_y + hex_h / 2.0

	# Rettangolo più stretto del 30%
	var rect_width = 161.0

	# Altezza del rettangolo invariata
	var rect_top = 60.0
	var rect_bottom = 590.0

	var rect_right = rect_x + rect_width

	var points = PackedVector2Array([
		Vector2(rect_x, rect_top),
		Vector2(rect_right, rect_top),

		Vector2(rect_right, rect_bottom),
		Vector2(rect_x, rect_bottom),

		Vector2(rect_x, lower_center_y + hex_h / 2.0),

		Vector2(half_r, lower_center_y + hex_h / 2.0),

		Vector2(0, lower_center_y),

		Vector2(half_r, center_y),

		Vector2(0, upper_center_y),

		Vector2(half_r, upper_center_y - hex_h / 2.0),

		Vector2(rect_x, upper_center_y - hex_h / 2.0)
	])

	shape.polygon = points
	shape.color = Color(0.07, 0.12, 0.13)

func center_power_track():
	var power_track = $PowerTrack

	var rect_center_x = (
		RECT_X
		+ RECT_WIDTH / 2.0
	)

	power_track.position.x = (
		rect_center_x
		- power_track.size.x / 2.0
	)
	
func setup_card_slots():
	var r = 70.0
	var hex_h = sqrt(3.0) * r

	var center_y = 325.0
	var upper_center_y = center_y - hex_h / 2.0
	var lower_center_y = center_y + hex_h / 2.0

	# Altezza totale della coppia di carte
	var pair_height = (
		SMALL_CARD_SIZE.y * 2.0
		+ CARD_GAP
	)

	# Centro orizzontale della zona esagonale.
	# Questo è il valore da calibrare se serve spostare
	# tutto leggermente a destra/sinistra.
	var card_center_x = 105.0

	var card_x = (
		card_center_x
		- SMALL_CARD_SIZE.x / 2.0
	)

	var upper_start_y = (
		upper_center_y
		- pair_height / 2.0
	)

	var lower_start_y = (
		lower_center_y
		- pair_height / 2.0
	)

	# Primo esagono
	setup_card_slot(
		$QuestSlot,
		Vector2(
			card_x,
			upper_start_y
		),
		"QUEST"
	)

	setup_card_slot(
		$JinxSlot,
		Vector2(
			card_x,
			upper_start_y
			+ SMALL_CARD_SIZE.y
			+ CARD_GAP
		),
		"JINX"
	)

	# Secondo esagono
	setup_card_slot(
		$EvocationSlot,
		Vector2(
			card_x,
			lower_start_y
		),
		"EVOC"
	)

	setup_card_slot(
		$UpgradeSlot,
		Vector2(
			card_x,
			lower_start_y
			+ SMALL_CARD_SIZE.y
			+ CARD_GAP
		),
		"UPGRADE"
	)
	
func setup_card_slot(
	slot: Control,
	slot_position: Vector2,
	label_text: String
):
	slot.position = slot_position
	slot.size = SMALL_CARD_SIZE
	slot.custom_minimum_size = SMALL_CARD_SIZE

	var label = slot.get_node_or_null("Label")

	if label == null:
		label = Label.new()
		label.name = "Label"
		slot.add_child(label)

	label.position = Vector2.ZERO
	label.size = SMALL_CARD_SIZE

	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
