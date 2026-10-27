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

# Chaos School: a Room can contain at most one Vastum token.  The boolean is
# authoritative game state; the TextureRect below is only its projection.
var vastum_present: bool = false
static var _vastum_texture_cache: Texture2D = null
static var _vastum_texture_checked: bool = false

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
	_refresh_vastum_token()


func refresh_art() -> void:
	$Background.color = room_color
	var has_art := preload("res://room_art.gd").apply($Background, get_art_id(), radius, flipped)
	$RoomName.visible = not has_art
	$RoomName.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_activation_token()
	_refresh_vastum_token()


func _find_vastum_texture_recursive(
	directory_path: String,
	depth: int = 0
) -> Texture2D:
	if depth > 7:
		return null

	var dir := DirAccess.open(directory_path)
	if dir == null:
		return null

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path := directory_path.path_join(entry)
			if dir.current_is_dir():
				if entry != ".godot" and entry != ".git":
					var nested := _find_vastum_texture_recursive(full_path, depth + 1)
					if nested != null:
						dir.list_dir_end()
						return nested
			elif entry.to_lower().contains("vastum") and entry.to_lower().ends_with(".png"):
				if ResourceLoader.exists(full_path):
					var texture := load(full_path) as Texture2D
					if texture != null:
						dir.list_dir_end()
						return texture
		entry = dir.get_next()

	dir.list_dir_end()
	return null


func _vastum_texture() -> Texture2D:
	if _vastum_texture_checked:
		return _vastum_texture_cache

	_vastum_texture_checked = true
	for path in [
		"res://assets/tokens/vastum_token.png",
		"res://assets/tokens/vastum.png",
		"res://assets/vastum_token.png",
		"res://assets/vastum.png"
	]:
		if ResourceLoader.exists(path):
			_vastum_texture_cache = load(path) as Texture2D
			if _vastum_texture_cache != null:
				return _vastum_texture_cache

	_vastum_texture_cache = _find_vastum_texture_recursive("res://")
	return _vastum_texture_cache


func _refresh_vastum_token() -> void:
	var token := get_node_or_null("VastumToken") as TextureRect

	if token == null:
		token = TextureRect.new()
		token.name = "VastumToken"
		token.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		token.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		token.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		token.z_index = 24
		add_child(token)

	token.visible = vastum_present
	if not vastum_present:
		return

	token.position = Vector2(radius * 0.32, -radius * 0.08)
	token.size = Vector2(radius * 0.46, radius * 0.46)
	token.texture = _vastum_texture()

	# Keep the state visible even if a local checkout uses a different token
	# filename.  The actual project asset is used as soon as one of the paths
	# above exists.
	if token.texture == null:
		token.tooltip_text = "Vastum"


func has_vastum_token() -> bool:
	return vastum_present


func set_vastum_present(value: bool) -> void:
	vastum_present = value
	if is_node_ready():
		_refresh_vastum_token()


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
	token.texture = preload("res://room_art.gd").activation_token(get_art_id(), activated_this_turn)


func setup_room(
	data: Dictionary
):

	room_data = data.duplicate(true)

	# A variant occupies the same Lodge identity as its corresponding core Room.
	# Quests, movement, range and fixed-Room rules keep that identity; the selected
	# definition supplies its own name, effects, rewards and artwork.
	room_id = str(data.get("replaces", data.get("id", "")))

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


func get_art_id() -> String:
	return str(room_data.get("id", room_id))


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
	owner_id: int,
	animate: bool = true
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
	var game = get_parent()
	if animate and game.get("table_shell") != null:
		game.table_shell.queue_world_placement(cube)

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


func convert_instability_cube(owner_id: int, new_owner_id: int, index: int = -1) -> bool:
	if index < 0:
		index = instability_cubes.find(owner_id)
	if index < 0 or index >= instability_cubes.size() or instability_cubes[index] != owner_id:
		return false
	var old_color: Color = instability_cube_nodes[index].cube_color
	instability_cubes[index] = new_owner_id
	var cube = instability_cube_nodes[index]
	cube.owner_type = cube.OwnerType.BLACK_ROSE if new_owner_id == -1 else cube.OwnerType.PLAYER
	cube.player_index = new_owner_id
	cube.cube_color = Color.BLACK if new_owner_id == -1 else get_player_color(new_owner_id)
	cube.queue_redraw()
	var game = get_parent()
	if game.get("table_shell") != null and not game.suppress_placement_feedback:
		cube.set_meta("conversion_from", old_color)
		game.table_shell.queue_world_placement(cube)
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
			# Rotate and scale about the cube's centre, keeping it on the socket.
			cube.pivot_offset = cube.size * 0.5
			cube.scale = Vector2.ONE * radius / 130.0
			cube.rotation = get_art_instability_slot_rotation(slots[i])
			cube.position = slots[i] - cube.pivot_offset
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
		cube.rotation = 0.0
		cube.pivot_offset = Vector2.ZERO
		cube.scale = Vector2.ONE

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

func get_art_instability_slot_rotation(slot_center: Vector2) -> float:
	# Bottom sockets are horizontal; side sockets follow the two sloping edges.
	if slot_center.y >= radius * sqrt(3.0) * 0.40:
		return 0.0
	return deg_to_rad(-30.0 if slot_center.x < 0.0 else 30.0)


static var art_sockets: Dictionary = {}

func get_art_instability_slots() -> PackedVector2Array:
	var count := get_instability_resistance()
	var slots := PackedVector2Array()
	var bottom_count := mini(count, 4) if count != 5 else 5
	var bounds := Vector2(radius * 2.0, radius * sqrt(3.0))
	var texture_size: Vector2 = $Background.texture.get_size()
	var size := texture_size * maxf(bounds.x / texture_size.x, bounds.y / texture_size.y) * preload("res://room_art.gd").ART_BLEED
	if art_sockets.is_empty(): art_sockets = JSON.parse_string(FileAccess.get_file_as_string("res://data/room_art_sockets.json"))
	if art_sockets.has(get_art_id()):
		for point in art_sockets[get_art_id()]:
			slots.append((Vector2(point[0], point[1]) - Vector2.ONE * 0.5) * size)
		return slots
	for i in range(bottom_count):
		slots.append((Vector2(0.5 + (i - (bottom_count - 1) * 0.5) * 0.10, 0.903) - Vector2.ONE * 0.5) * size)
	var side_count := int((count - bottom_count) / 2)
	for i in range(side_count):
		var offset := Vector2(0.245 - i * 0.05, 0.818 - i * 0.10)
		slots.append((offset - Vector2.ONE * 0.5) * size)
		slots.append((Vector2(1.0 - offset.x, offset.y) - Vector2.ONE * 0.5) * size)
	# The slanted left edge precedes the bottom row; the right edge follows it.
	# Keep coordinates aligned with the art, changing only placement order.
	var ordered: Array[Vector2] = []
	for point in slots:
		ordered.append(point)
	ordered.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
	return PackedVector2Array(ordered)

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
