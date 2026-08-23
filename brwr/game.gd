extends Node2D
@export var game_seed: int = 0
@export_range(2, 6) var player_count: int = 4
var players: Array[PlayerState] = []
var rng = RandomNumberGenerator.new()

var room_scene = preload("res://room.tscn")
var cell_scene = preload("res://cell.tscn")
var layout_database = {}
const HEX_RADIUS = 70.0
var board_center: Vector2
var room_database = []
var cell_database = []
const BOARD_CENTER = Vector2(576, 324)

func load_cells():
	var file = FileAccess.open("res://data/cells.json", FileAccess.READ)

	if file == null:
		print("ERRORE: impossibile aprire cells.json")
		return []

	var text = file.get_as_text()
	var data = JSON.parse_string(text)

	if data == null:
		print("ERRORE: cells.json non è valido")
		return []

	return data
func load_layouts():
	var file = FileAccess.open("res://data/layouts.json", FileAccess.READ)

	if file == null:
		print("ERRORE: impossibile aprire layouts.json")
		return {}

	var text = file.get_as_text()
	var data = JSON.parse_string(text)

	if data == null:
		print("ERRORE: layouts.json non è valido")
		return {}

	return data
	
func create_cell(cell_data, hex_position: Vector2i):
	var cell = cell_scene.instantiate()

	cell.cell_id = cell_data["id"]
	cell.cell_name = cell_data["name"]
	cell.cell_color = Color(cell_data["color"])
	cell.radius = HEX_RADIUS
	cell.position = hex_to_pixel(hex_position)

	add_child(cell)
	
func _ready():
	if game_seed == 0:
		rng.randomize()
	else:
		rng.seed = game_seed

	board_center = get_viewport_rect().size / 2.0

	room_database = load_rooms()
	layout_database = load_layouts()
	cell_database = load_cells()

	print("PLAYER COUNT: ", player_count)
	print("GAME SEED: ", game_seed)

	create_lodge()
	create_players()
	deal_damage(0, 1, 3)
	deal_damage(-1, 1, 2)

	print("Before healing")
	print("P1 cubes: ", players[0].available_cubes)
	print("BR cubes: ", $EventBoard.black_rose_cube_count)
	print("P2 damage: ", players[1].mage.damage_cubes)

	heal_damage(1, 0, 2)
	heal_damage(1, -1, 10)
	print("After healing")
	print("P1 cubes: ", players[0].available_cubes)
	print("BR cubes: ", $EventBoard.black_rose_cube_count)
	print("P2 damage: ", players[1].mage.damage_cubes)
	await $PowerBoard.initialize(player_count)
	


func load_rooms():
	var file = FileAccess.open("res://data/rooms.json", FileAccess.READ)

	if file == null:
		print("ERRORE: impossibile aprire rooms.json")
		return []

	var text = file.get_as_text()
	var data = JSON.parse_string(text)

	if data == null:
		print("ERRORE: rooms.json non è valido")
		return []

	return data


func get_room(room_id: String):
	for room_data in room_database:
		if room_data["id"] == room_id:
			return room_data

	print("ERRORE: stanza non trovata: ", room_id)
	return null


func create_lodge():
	var black_rose = get_room("black_rose")
	var throne = get_room("throne")

	# Black Rose sempre al centro
	create_room(
		black_rose,
		Vector2i(0, 0)
	)

	# Throne Room sempre adiacente alla Black Rose
	create_room(
		throne,
		Vector2i(1, 0)
	)
	create_cells()
	# Tutte le altre stanze Core
	var room_pool = []

	for room_data in room_database:
		if room_data["core"] == true and room_data["fixed"] == false:
			room_pool.append(room_data)

	# Mischia le 17 stanze
	shuffle_with_rng(room_pool)

	# Tutte le posizioni della Lodge tranne:
	# (0,0) = Black Rose
	# (1,0) = Throne Room
	var available_positions = get_lodge_positions()

	for i in range(room_pool.size()):
		create_room(
			room_pool[i],
			available_positions[i]
		)
	print("Rooms in database: ", room_database.size())
	print("Random rooms: ", room_pool.size())
	print("Available positions: ", available_positions.size())

func create_room(room_data, hex_position: Vector2i):
	var room = room_scene.instantiate()
	room.set_meta("room_id", room_data["id"])
	room.room_name = room_data["name"]
	room.room_color = get_room_color(room_data["color"])
	room.radius = HEX_RADIUS
	room.position = hex_to_pixel(hex_position)

	add_child(room)


func get_room_color(color_name: String) -> Color:
	match color_name:
		"black":
			return Color(0.15, 0.15, 0.15)
		"grey":
			return Color(0.4, 0.4, 0.4)
		"red":
			return Color(0.55, 0.15, 0.15)
		"yellow":
			return Color(0.65, 0.55, 0.15)
		"green":
			return Color(0.15, 0.5, 0.2)
		"blue":
			return Color(0.15, 0.3, 0.6)
		"purple":
			return Color(0.45, 0.2, 0.55)
		_:
			return Color.DIM_GRAY


func hex_to_pixel(hex_position: Vector2i) -> Vector2:
	var q = hex_position.x
	var r = hex_position.y

	var x = HEX_RADIUS * 1.5 * q
	var y = HEX_RADIUS * sqrt(3.0) * (r + q / 2.0)

	return board_center + Vector2(x, y)
	
func get_lodge_positions() -> Array[Vector2i]:
	var positions: Array[Vector2i] = []

	for q in range(-2, 3):
		for r in range(-2, 3):
			var s = -q - r

			if abs(q) <= 2 and abs(r) <= 2 and abs(s) <= 2:
				var position = Vector2i(q, r)

				# Black Rose
				if position == Vector2i(0, 0):
					continue

				# Throne Room
				if position == Vector2i(1, 0):
					continue

				positions.append(position)

	return positions

func create_cells():
	var layout = layout_database[str(player_count)]
	var cell_slots = layout["cells"]

	var available_cells = cell_database.duplicate(true)

	shuffle_with_rng(available_cells)

	var selected_cells = available_cells.slice(0, player_count)

	for i in range(cell_slots.size()):
		var slot_data = cell_slots[i]
		var position_array = slot_data["position"]

		var hex_position = Vector2i(
			int(position_array[0]),
			int(position_array[1])
		)

		create_cell(
			selected_cells[i],
			hex_position
		)

	print("Cells created: ", cell_slots.size())
	
func shuffle_with_rng(array: Array):
	for i in range(array.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)

		var temp = array[i]
		array[i] = array[j]
		array[j] = temp

func find_room(room_id: String):
	for child in get_children():
		if child.has_meta("room_id"):
			if child.get_meta("room_id") == room_id:
				return child

	return null
	
func place_black_rose_instability(room_id: String, amount: int = 1):
	var room = find_room(room_id)

	if room == null:
		print("ERRORE: stanza non trovata: ", room_id)
		return

	var taken = $EventBoard.take_black_rose_cubes(amount)

	for i in range(taken):
		room.add_instability_cube(-1)

	print(
		"Black Rose placed ",
		taken,
		" instability in ",
		room.room_name
	)

func remove_black_rose_instability(room_id: String, amount: int = 1):
	var room = find_room(room_id)

	if room == null:
		print("ERRORE: stanza non trovata: ", room_id)
		return

	var removed = 0

	for i in range(amount):
		if room.remove_instability_cube(-1):
			removed += 1
		else:
			break

	$EventBoard.return_black_rose_cubes(removed)

	print(
		"Removed ",
		removed,
		" Black Rose instability from ",
		room.room_name
	)
func create_players():
	players.clear()

	var colors = [
		Color.RED,
		Color.BLUE,
		Color.GREEN,
		Color.PURPLE,
		Color.YELLOW,
		Color.WHITE
	]

	for i in range(player_count):
		var player = PlayerState.new(
			i,
			"Player " + str(i + 1),
			colors[i]
		)

		players.append(player)

	print("Players created: ", players.size())

func place_player_instability(player_index: int, room_id: String, amount: int = 1):
	if player_index < 0 or player_index >= players.size():
		print("ERRORE: player_index non valido: ", player_index)
		return

	var room = find_room(room_id)

	if room == null:
		print("ERRORE: stanza non trovata: ", room_id)
		return

	var player = players[player_index]
	var taken = player.take_cubes(amount)

	for i in range(taken):
		room.add_instability_cube(player_index)

	print(
		player.player_name,
		" placed ",
		taken,
		" instability in ",
		room.room_name,
		" | Cubes left: ",
		player.available_cubes
	)
func remove_player_instability(player_index: int, room_id: String, amount: int = 1):
	if player_index < 0 or player_index >= players.size():
		print("ERRORE: player_index non valido: ", player_index)
		return

	var room = find_room(room_id)

	if room == null:
		print("ERRORE: stanza non trovata: ", room_id)
		return

	var player = players[player_index]
	var removed = 0

	for i in range(amount):
		if room.remove_instability_cube(player_index):
			removed += 1
		else:
			break

	player.return_cubes(removed)

	print(
		"Removed ",
		removed,
		" instability of ",
		player.player_name,
		" from ",
		room.room_name,
		" | Cubes available: ",
		player.available_cubes
	)
	
func take_owner_cubes(owner_id: int, amount: int) -> int:
	if owner_id == -1:
		return $EventBoard.take_black_rose_cubes(amount)

	if owner_id < 0 or owner_id >= players.size():
		print("ERRORE: owner_id non valido: ", owner_id)
		return 0

	return players[owner_id].take_cubes(amount)
	
func return_owner_cubes(owner_id: int, amount: int):
	if owner_id == -1:
		$EventBoard.return_black_rose_cubes(amount)
		return

	if owner_id < 0 or owner_id >= players.size():
		print("ERRORE: owner_id non valido: ", owner_id)
		return

	players[owner_id].return_cubes(amount)
	
func deal_damage(
	attacker_id: int,
	target_player_index: int,
	amount: int
) -> int:

	if target_player_index < 0 or target_player_index >= players.size():
		print("ERRORE: target_player_index non valido")
		return 0

	if amount <= 0:
		return 0

	var target_mage = players[target_player_index].mage

	# Il regolamento non piazza Damage oltre la Health.
	var damage_capacity = target_mage.get_remaining_health()
	var requested_damage = min(amount, damage_capacity)

	# L'attaccante deve avere fisicamente i cubi.
	var cubes_available = take_owner_cubes(
		attacker_id,
		requested_damage
	)

	var damage_dealt = target_mage.add_damage(
		attacker_id,
		cubes_available
	)

	print(
		"Damage: attacker ", attacker_id,
		" -> Player ", target_player_index + 1,
		" | ", damage_dealt,
		" damage",
		" | Target HP: ",
		target_mage.get_remaining_health(),
		"/",
		target_mage.health
	)

	return damage_dealt

func heal_damage(
	target_player_index: int,
	owner_id: int,
	amount: int
) -> int:

	if target_player_index < 0 or target_player_index >= players.size():
		print("ERRORE: target_player_index non valido")
		return 0

	if amount <= 0:
		return 0

	var target_mage = players[target_player_index].mage

	var removed = target_mage.remove_damage(
		owner_id,
		amount
	)

	return_owner_cubes(
		owner_id,
		removed
	)

	print(
		"Healed ",
		removed,
		" damage from owner ",
		owner_id,
		" on Player ",
		target_player_index + 1,
		" | Target HP: ",
		target_mage.get_remaining_health(),
		"/",
		target_mage.health
	)

	return removed
