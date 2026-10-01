extends Node2D


var cube_scene = preload("res://cube.tscn")


@export var room_name: String = "Room"
@export var room_color: Color = Color.DIM_GRAY
@export var radius: float = 150.0


# =========================================================
# ROOM DEFINITION
# =========================================================

var room_id: String = ""
var room_data: Dictionary = {}


# =========================================================
# RUNTIME STATE
# =========================================================

var instability_cubes: Array = []
var instability_cube_nodes: Array = []

var flipped: bool = false:
	set(value):
		flipped = value
		if is_node_ready():
			refresh_art()
var activated_this_turn: bool = false:
	set(value):
		activated_this_turn = value
		if is_node_ready():
			_refresh_activation_token()


# =========================================================
# INITIALIZATION
# =========================================================

func _ready():

	var background = $Background

	var points = PackedVector2Array()

	for i in range(6):

		var angle = deg_to_rad(60 * i)

		var point = Vector2(
			cos(angle) * radius,
			sin(angle) * radius
		)

		points.append(point)

	background.polygon = points
	background.color = room_color

	$RoomName.text = room_name
	refresh_art()


func refresh_art() -> void:
	$Background.color = room_color
	var has_art := preload("res://room_art.gd").apply($Background, room_id, radius, flipped)
	$RoomName.visible = not has_art
	$RoomName.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_activation_token()


func _refresh_activation_token() -> void:
	var token := get_node_or_null("ActivationToken") as TextureRect
	if token == null:
		token = TextureRect.new()
		token.name = "ActivationToken"
		token.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		token.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		token.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		token.z_index = 20
		add_child(token)
	token.visible = flipped
	if not flipped:
		return
	token.position = Vector2(-radius * 0.60, -radius * 0.77)
	token.size = Vector2(radius * 1.20, radius * 0.40)
	token.texture = preload("res://room_art.gd").activation_token(room_id, activated_this_turn)


func setup_room(
	data: Dictionary
):

	room_data = data.duplicate(true)

	room_id = str(
		data.get(
			"id",
			""
		)
	)

	room_name = str(
		data.get(
			"name",
			"Room"
		)
	)

	set_meta(
		"room_id",
		room_id
	)

	if is_node_ready():
		$RoomName.text = room_name
		refresh_art()


# =========================================================
# ROOM DATA
# =========================================================

func get_room_id() -> String:
	return room_id


func get_room_data() -> Dictionary:
	return room_data


func get_effects() -> Array:

	if flipped:
		return room_data.get(
			"rebuilt_effects",
			[]
		)

	return room_data.get(
		"destroyed_effects",
		[]
	)


func get_current_side_name() -> String:

	if flipped:
		return "rebuilt"

	return "destroyed"


# =========================================================
# ACTIVATION
# =========================================================

func can_activate(
	allow_reactivate_flipped: bool = false
) -> bool:

	# Destroyed Rooms can be activated any number
	# of times during the same turn.
	if not flipped:
		return true

	# Rebuilt Rooms can normally be activated
	# only once per turn.
	if not activated_this_turn:
		return true

	return allow_reactivate_flipped


func mark_activated():

	if flipped:
		activated_this_turn = true


func reset_activation():
	activated_this_turn = false


# =========================================================
# INSTABILITY
# =========================================================

func add_instability_cube(
	owner_id: int
) -> bool:

	if flipped:
		print(
			room_name,
			": cannot place Instability, Room is rebuilt"
		)
		return false

	if not has_free_instability_slot():
		print(
			room_name,
			": cannot place Instability, Room is full"
		)
		return false

	instability_cubes.append(
		owner_id
	)

	var cube = cube_scene.instantiate()

	if owner_id == -1:

		cube.owner_type = (
			cube.OwnerType.BLACK_ROSE
		)

		cube.cube_color = Color.BLACK

	else:

		cube.owner_type = (
			cube.OwnerType.PLAYER
		)

		cube.player_index = owner_id

		cube.cube_color = (
			get_player_color(
				owner_id
			)
		)

	add_child(
		cube
	)

	instability_cube_nodes.append(
		cube
	)

	update_instability_cube_positions()

	print(
		room_name,
		" received instability from owner ",
		owner_id,
		" | ",
		get_instability_count(),
		"/",
		get_instability_resistance()
	)

	return true


func remove_instability_cube(
	owner_id: int
) -> bool:

	var index = (
		instability_cubes.find(
			owner_id
		)
	)

	if index == -1:
		return false

	instability_cubes.remove_at(
		index
	)

	var cube = (
		instability_cube_nodes[index]
	)

	instability_cube_nodes.remove_at(
		index
	)

	cube.queue_free()

	update_instability_cube_positions()

	return true


func get_instability_count() -> int:
	return instability_cubes.size()


func get_instability_by_owner(
	owner_id: int
) -> int:

	return instability_cubes.count(
		owner_id
	)


func update_instability_cube_positions():
	if $Background.texture != null:
		var slots := get_art_instability_slots()
		for i in range(instability_cube_nodes.size()):
			var cube = instability_cube_nodes[i]
			cube.scale = Vector2.ONE * radius / 130.0
			cube.position = slots[i] - cube.size * cube.scale * 0.5
		return

	var start_position = Vector2(
		-25,
		25
	)

	var spacing = 16

	for i in range(
		instability_cube_nodes.size()
	):

		var cube = (
			instability_cube_nodes[i]
		)

		var column = i % 4
		var row = int(i / 4)

		cube.position = (
			start_position
			+ Vector2(
				column * spacing,
				row * spacing
			)
		)


# =========================================================
# PLAYER COLORS
# =========================================================

func get_art_instability_slots() -> PackedVector2Array:
	var count := get_instability_resistance()
	var slots := PackedVector2Array()
	var bottom_count := mini(count, 4) if count != 5 else 5
	var size := Vector2(radius * 2.0, radius * sqrt(3.0))
	for i in range(bottom_count):
		slots.append((Vector2(0.5 + (i - (bottom_count - 1) * 0.5) * 0.10, 0.91) - Vector2.ONE * 0.5) * size)
	var side_count := int((count - bottom_count) / 2)
	for i in range(side_count):
		var offset := Vector2(0.25 - i * 0.05, 0.81 - i * 0.10)
		slots.append((offset - Vector2.ONE * 0.5) * size)
		slots.append((Vector2(1.0 - offset.x, offset.y) - Vector2.ONE * 0.5) * size)
	return slots

func get_player_color(
	player_index: int
) -> Color:

	var colors = [
		Color.RED,
		Color.BLUE,
		Color.GREEN,
		Color.PURPLE,
		Color.YELLOW,
		Color.WHITE
	]

	if player_index < 0 \
	or player_index >= colors.size():

		return Color.GRAY

	return colors[player_index]
	
func get_instability_resistance() -> int:
	return int(
		room_data.get(
			"instability_resistance",
			0
		)
	)


func has_free_instability_slot() -> bool:
	return (
		get_instability_count()
		< get_instability_resistance()
	)


func is_instability_complete() -> bool:
	return (
		get_instability_count()
		== get_instability_resistance()
	)

func get_completion_rewards() -> Array:
	return room_data.get(
		"completion_rewards",
		[]
	)

func clear_instability():
	for cube in instability_cube_nodes:
		if cube != null:
			cube.queue_free()

	instability_cubes.clear()
	instability_cube_nodes.clear()
