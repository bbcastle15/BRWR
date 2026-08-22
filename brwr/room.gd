extends Node2D
var cube_scene = preload("res://cube.tscn")
@export var room_name: String = "Room"
@export var room_color: Color = Color.DIM_GRAY
@export var radius: float = 150.0
var instability_cubes: Array = []
var instability_cube_nodes: Array = []
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
func add_instability_cube(owner_id: int):
	instability_cubes.append(owner_id)

	var cube = cube_scene.instantiate()

	if owner_id == -1:
		cube.owner_type = cube.OwnerType.BLACK_ROSE
		cube.cube_color = Color.BLACK
	else:
		cube.owner_type = cube.OwnerType.PLAYER
		cube.player_index = owner_id
		cube.cube_color = get_player_color(owner_id)

	add_child(cube)
	instability_cube_nodes.append(cube)

	update_instability_cube_positions()

	print(
		room_name,
		" received instability from owner ",
		owner_id,
		" | Total: ",
		instability_cubes.size()
	)


func remove_instability_cube(owner_id: int) -> bool:
	var index = instability_cubes.find(owner_id)

	if index == -1:
		return false

	instability_cubes.remove_at(index)

	var cube = instability_cube_nodes[index]
	instability_cube_nodes.remove_at(index)
	cube.queue_free()

	update_instability_cube_positions()

	return true


func get_instability_count() -> int:
	return instability_cubes.size()


func get_instability_by_owner(owner_id: int) -> int:
	return instability_cubes.count(owner_id)

func get_player_color(player_index: int) -> Color:
	var colors = [
		Color.RED,
		Color.BLUE,
		Color.GREEN,
		Color.PURPLE,
		Color.YELLOW,
		Color.WHITE
	]

	if player_index < 0 or player_index >= colors.size():
		return Color.GRAY

	return colors[player_index]
	
func update_instability_cube_positions():
	var start_position = Vector2(-25, 25)
	var spacing = 16

	for i in range(instability_cube_nodes.size()):
		var cube = instability_cube_nodes[i]

		var column = i % 4
		var row = int(i / 4)

		cube.position = start_position + Vector2(
			column * spacing,
			row * spacing
		)
