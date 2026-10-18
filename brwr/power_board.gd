extends Control
const SMALL_CARD_SIZE = Vector2(74, 48)
const ART_SIZE = Vector2(240, 312)
const ART_ORIGIN = Vector2(0, 173)
const LODGE_NOTCH = Vector2(44, 325)
const TRACK_MAX_POWER: int = 35

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
@export var end_game_threshold: int = 30

var black_rose_power: int = 0
var marker_tweens: Dictionary = {}
var markers_dirty := false
var instant_updates := false


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
		marker.visible = not AvatarRules.is_avatar(get_parent(), i)

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
	marker.set_meta("total_power", value)
	marker.set_meta("display_power", value % TRACK_MAX_POWER if value > TRACK_MAX_POWER else value)
	marker.get_node("Label").text = "+" + str(int(value / TRACK_MAX_POWER) * TRACK_MAX_POWER) if value > TRACK_MAX_POWER else ""

	_layout_power_markers()
	marker.tooltip_text = "Player %d · %d Power" % [player_index + 1, value]
	
func get_marker_offset(player_index: int) -> Vector2:
	var marker = player_markers[player_index]
	return marker.position - get_power_position(int(marker.get_meta("display_power", 0)))

func _layout_power_markers() -> void:
	# Scores are already authoritative. Wait only for a clear view of the table
	# before playing the visual change, coalescing updates received together.
	if not instant_updates and _presentation_covered():
		markers_dirty = true
		return
	markers_dirty = false
	var groups: Dictionary = {}
	for marker in player_markers + [black_rose_marker]:
		if not is_instance_valid(marker) or not marker.visible:
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
			_move_marker(markers[i], int(score), offset)


func _presentation_covered() -> bool:
	var game = get_parent()
	var camera = game.get_node_or_null("TableCamera")
	return camera != null and camera._table_covered()


func _process(_delta: float) -> void:
	if markers_dirty and not _presentation_covered():
		_layout_power_markers()


func _move_marker(marker: Control, score: int, offset: Vector2) -> void:
	var destination := get_power_position(score) + offset
	var total: int = black_rose_power if marker == black_rose_marker else int(marker.get_meta("total_power", score))
	var previous: int = int(marker.get_meta("animated_power", total))
	var first := not marker.has_meta("animated_power")
	var old_destination: Vector2 = marker.get_meta("destination", marker.position)
	marker.set_meta("animated_power", total)
	marker.set_meta("destination", destination)
	if not first and previous == total and old_destination.is_equal_approx(destination):
		return
	if marker_tweens.has(marker):
		marker_tweens[marker].kill()
		marker_tweens.erase(marker)
	if first or instant_updates or not is_inside_tree():
		marker.position = destination
		return
	var tween := create_tween()
	marker_tweens[marker] = tween
	var distance := absi(total - previous)
	if marker == black_rose_marker and total > previous:
		var camera = get_parent().get_node_or_null("TableCamera")
		if camera != null:
			camera.focus_power_board()
		# Let the camera approach before the Rose starts sliding.
		tween.tween_interval(0.25)
	if distance > 0 and distance <= TRACK_MAX_POWER:
		var direction := 1 if total > previous else -1
		for step in range(1, distance + 1):
			var value := previous + step * direction
			var cell := value % TRACK_MAX_POWER if value > TRACK_MAX_POWER else value
			var target := destination if step == distance else get_power_position(cell)
			tween.tween_property(marker, "position", target, clampf(0.65 / distance, 0.025, 0.18))
	else:
		tween.tween_property(marker, "position", destination, 0.25).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func(): marker_tweens.erase(marker))
	
func update_black_rose_marker():
	if not is_instance_valid(black_rose_marker):
		return

	black_rose_marker.set_meta(
		"display_power",
		black_rose_power % TRACK_MAX_POWER
		if black_rose_power > TRACK_MAX_POWER
		else black_rose_power
	)

	black_rose_marker.get_node("Label").text = (
		"+" + str(
			int(black_rose_power / TRACK_MAX_POWER)
			* TRACK_MAX_POWER
		)
		if black_rose_power > TRACK_MAX_POWER
		else ""
	)

	_layout_power_markers()

	black_rose_marker.tooltip_text = (
		"Black Rose · %d Power"
		% black_rose_power
	)

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
	setup_forgotten_evocation_deck()


func setup_forgotten_evocation_deck() -> void:
	if $EvocationSlot.has_node("ForgottenEvocationDeck"):
		return
	# Reuse the red Evocation back printed on the supplied board artwork.
	# Normalized UVs also work with the smaller texture imported for Web.
	var back := AtlasTexture.new()
	back.atlas = preload("res://assets/boards/power_board_reference.png")
	back.region = Rect2(Vector2(0.163, 0.315) * back.atlas.get_size(), Vector2(0.300, 0.158) * back.atlas.get_size())
	back.filter_clip = true
	var deck := Button.new()
	deck.name = "ForgottenEvocationDeck"
	deck.size = SMALL_CARD_SIZE
	deck.custom_minimum_size = SMALL_CARD_SIZE
	deck.tooltip_text = "Forgotten Evocations · Browse cards and available copies"
	deck.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	deck.pressed.connect(_inspect_forgotten_evocations, CONNECT_DEFERRED)
	for style_name in ["normal", "hover", "pressed", "focus"]:
		var edge := StyleBoxFlat.new()
		edge.bg_color = Color(0, 0, 0, 0.3)
		edge.set_corner_radius_all(2)
		if style_name in ["hover", "focus"]:
			edge.set_border_width_all(1)
			edge.border_color = Color("e4c884")
		deck.add_theme_stylebox_override(style_name, edge)
	$EvocationSlot.add_child(deck)
	for layer_index in range(3, -1, -1):
		var card := TextureRect.new()
		card.name = "CardBack" if layer_index == 0 else "Stack%d" % layer_index
		card.texture = back
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.position = Vector2.ONE * (1.0 + layer_index * 1.2)
		card.size = SMALL_CARD_SIZE - Vector2(6, 6)
		card.modulate = Color.WHITE * (1.0 - layer_index * 0.12)
		card.modulate.a = 1.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck.add_child(card)


func _inspect_forgotten_evocations() -> void:
	var game = get_parent()
	game.inspected_quest = null
	var cards: Array = game.evocation_database.get_all_evocations().filter(func(data): return bool(data.get("forgotten", false)))
	cards.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	game._reference_card_preview().show_reference_pile("evocations", cards, "Forgotten Evocations", _describe_evocation)


func _describe_evocation(data: Dictionary) -> String:
	var game = get_parent()
	var text := "Available copies: %d / %d · %s\nHealth %d · Strength %d · Speed %d" % [
		game.get_available_evocation_copies(str(data.id)), int(data.get("copies", 0)),
		str(data.get("archetype", "")).capitalize(), int(data.health), int(data.strength), int(data.speed)]
	if game.ReferenceCardPreview.card_texture("evocations", str(data.id)) == null:
		text += "\n\n" + game.ReferenceCardPreview.describe_rules(data.get("abilities", []))
	return text


func setup_card_slot(slot: Control, slot_position: Vector2, label_text: String):
	slot.position = slot_position
	slot.size = SMALL_CARD_SIZE
	slot.custom_minimum_size = SMALL_CARD_SIZE
	slot.tooltip_text = label_text
	slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
