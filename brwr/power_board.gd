extends Control
const SMALL_CARD_SIZE = Vector2(74, 48)
const ART_SIZE = Vector2(240, 312)
const ART_ORIGIN = Vector2(0, 173)
const LODGE_NOTCH = Vector2(44, 325)

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
	var track = $PowerTrack
	for child in track.get_children():
		track.remove_child(child)
		child.queue_free()
	track.position = ART_ORIGIN
	track.size = ART_SIZE
	# Measured inner grid lines in the 1100 x 1430 texture. Its three rows
	# are slightly irregular, so each column needs its own cell centres.
	var borders := [
		[57, 165, 274, 382, 494, 608, 720, 826, 936, 1043, 1148, 1253, 1366],
		[58, 175, 282, 395, 504, 615, 721, 825, 936, 1039, 1147, 1254, 1366],
		[58, 176, 283, 397, 509, 617, 724, 825, 927, 1037, 1148, 1254, 1367]]
	var columns := [988.5, 803.5, 631.5]
	for value in range(36):
		var slot := Control.new()
		var column: int = value / 12
		var row: int = value % 12
		var top: float = borders[column][row]
		var bottom: float = borders[column][row + 1]
		slot.size = Vector2(36, (bottom - top) / 1430.0 * ART_SIZE.y)
		slot.position = Vector2(columns[column] / 1100.0 * ART_SIZE.x, (top + bottom) * 0.5 / 1430.0 * ART_SIZE.y) - slot.size * 0.5
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(slot)


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
	marker.set_meta("display_power", value % end_game_threshold if value > end_game_threshold else value)
	marker.get_node("Label").text = "+" + str(int(value / end_game_threshold) * end_game_threshold) if value > end_game_threshold else ""

	_layout_power_markers()
	marker.tooltip_text = "Player %d · %d Power" % [player_index + 1, value]
	
func get_marker_offset(player_index: int) -> Vector2:
	var marker = player_markers[player_index]
	return marker.position - get_power_position(int(marker.get_meta("display_power", 0)))

func _layout_power_markers() -> void:
	var groups: Dictionary = {}
	for marker in player_markers + [black_rose_marker]:
		if not is_instance_valid(marker):
			continue
		var score: int = int(marker.get_meta("display_power", 0))
		if not groups.has(score):
			groups[score] = []
		groups[score].append(marker)
	for score in groups:
		var markers: Array = groups[score]
		for i in range(markers.size()):
			var offset := Vector2.ZERO
			if markers.size() > 1:
				# A compact, symmetric fan remains inside the score cell.
				var angle: float = TAU * i / markers.size()
				offset = Vector2(cos(angle) * 7.0, sin(angle) * 3.0)
			markers[i].position = get_power_position(int(score)) + offset
	
func update_black_rose_marker():
	black_rose_marker.set_meta("display_power", black_rose_power % end_game_threshold if black_rose_power > end_game_threshold else black_rose_power)
	black_rose_marker.get_node("Label").text = "+" + str(int(black_rose_power / end_game_threshold) * end_game_threshold) if black_rose_power > end_game_threshold else ""

	_layout_power_markers()
	black_rose_marker.tooltip_text = "Black Rose · %d Power" % black_rose_power

func create_threshold_markers():
	for marker in threshold_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	threshold_markers.clear()
	for color in [Color.GRAY, Color.GOLD, Color.BLACK]:
		var marker = preload("res://cube.tscn").instantiate()
		marker.cube_color = color
		marker.scale = Vector2.ONE * 0.55
		add_child(marker)
		threshold_markers.append(marker)

func update_threshold_markers():
	var values := [second_moon_threshold, third_moon_threshold, end_game_threshold]
	for i in range(mini(3, threshold_markers.size())):
		threshold_markers[i].position = get_power_position(values[i]) + Vector2(12, -4)


func create_board_shape():
	var shape = $BoardShape
	var normalized := PackedVector2Array([Vector2(0.493, 0.008), Vector2(0.99, 0.008),
		Vector2(0.99, 0.993), Vector2(0.51, 0.993), Vector2(0.427, 0.878),
		Vector2(0.146, 0.878), Vector2(0, 0.701), Vector2(0.181, 0.487),
		Vector2(0, 0.265), Vector2(0.151, 0.099), Vector2(0.427, 0.099)])
	var points := PackedVector2Array()
	for point in normalized:
		points.append(ART_ORIGIN + point * ART_SIZE)
	shape.polygon = points
	shape.hide()
	var art := TextureRect.new()
	art.name = "PowerBoardArt"
	art.texture = preload("res://assets/boards/power_board_reference.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.position = ART_ORIGIN
	art.size = ART_SIZE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	move_child(art, 0)


func center_power_track():
	$PowerTrack.position = ART_ORIGIN


func setup_card_slots():
	var slots := [$QuestSlot, $EvocationSlot, $JinxSlot, $UpgradeSlot]
	var y_positions := [0.136, 0.315, 0.504, 0.690]
	for i in range(slots.size()):
		setup_card_slot(slots[i], ART_ORIGIN + Vector2(0.162, y_positions[i]) * ART_SIZE, ["QUEST", "EVOCATION", "JINX", "UPGRADE"][i])


func setup_card_slot(slot: Control, slot_position: Vector2, label_text: String):
	slot.position = slot_position
	slot.size = SMALL_CARD_SIZE
	slot.custom_minimum_size = SMALL_CARD_SIZE
	slot.tooltip_text = label_text
	slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
