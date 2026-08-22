extends Control

var cube_scene = preload("res://cube.tscn")

const BLACK_ROSE_MAX_CUBES: int = 30

var black_rose_cube_count: int = BLACK_ROSE_MAX_CUBES

var active_events: Array = [
	null,
	null,
	null
]

var event_discard: Array = []
var quest_discard: Array = []


func _ready():
	create_cube_pool_ui()
	update_black_rose_cube_pool()
	
func create_cube_pool_ui():
	var pool = $BlackRoseCubePool

	# Un singolo cubo grafico rappresentativo.
	var cube = cube_scene.instantiate()
	cube.name = "CubePreview"
	cube.owner_type = cube.OwnerType.BLACK_ROSE
	cube.cube_color = Color.BLACK
	cube.position = Vector2(15, 15)

	pool.add_child(cube)

	# Contatore.
	var label = Label.new()
	label.name = "CountLabel"
	label.position = Vector2(45, 12)
	label.text = "× 0"

	pool.add_child(label)
	
func update_black_rose_cube_pool():
	var label = $BlackRoseCubePool.get_node_or_null("CountLabel")

	if label != null:
		label.text = "× " + str(black_rose_cube_count)
		
		
func set_black_rose_cube_count(value: int):
	black_rose_cube_count = max(value, 0)
	update_black_rose_cube_pool()


func take_black_rose_cubes(amount: int) -> int:
	var taken = min(amount, black_rose_cube_count)

	black_rose_cube_count -= taken
	update_black_rose_cube_pool()

	return taken


func return_black_rose_cubes(amount: int):
	black_rose_cube_count = min(
		black_rose_cube_count + max(amount, 0),
		BLACK_ROSE_MAX_CUBES
	)

	update_black_rose_cube_pool()
