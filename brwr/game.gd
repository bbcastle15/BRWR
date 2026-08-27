extends Node2D
@export var game_seed: int = 0
@export_range(2, 6) var player_count: int = 4
var players: Array[PlayerState] = []
var rng = RandomNumberGenerator.new()
var current_moon: int = 1
var black_rose_power: int = 0
var room_scene = preload("res://room.tscn")
var cell_scene = preload("res://cell.tscn")
var mage_token_scene = preload("res://mage_token.tscn")
var mage_tokens: Array = []
var player_board_scene = preload("res://player_board.tscn")
var spell_database = SpellDatabase.new()
var evocation_database = EvocationDatabase.new()
var triggered_spell_manager = TriggeredSpellManager.new()
var layout_database = {}
const HEX_RADIUS = 70.0
var board_center: Vector2
var room_database = []
var cell_database = []
var player_boards: Array = []
var effect_resolver = EffectResolver.new()
const BOARD_CENTER = Vector2(576, 324)
var room_id_by_coord: Dictionary = {}


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
	
func create_cell(
	cell_data,
	hex_position: Vector2i
):
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
	spell_database.load_database()
	evocation_database.load_database()
	create_players()
	create_lodge()
	create_player_boards()
	player_boards[0].refresh()
	player_boards[1].refresh()
	await $PowerBoard.initialize(player_count)
	$EventBoard.initialize_events(rng)
	update_table_layout()
	

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

	# Salva la corrispondenza coordinata -> room_id
	room_id_by_coord[hex_position] = str(room_data["id"])


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

	var selected_cells = available_cells.slice(
		0,
		player_count
	)

	for i in range(cell_slots.size()):
		var slot_data = cell_slots[i]

		# Posizione della Cell
		var position_array = slot_data["position"]

		var hex_position = Vector2i(
			int(position_array[0]),
			int(position_array[1])
		)

		# Quale Cell random usare
		var cell_data = selected_cells[i]

		create_cell(
			cell_data,
			hex_position
		)

		# Posizione iniziale del Mage
		var entrance_array = slot_data["entrance_room"]

		var entrance_room = Vector2i(
			int(entrance_array[0]),
			int(entrance_array[1])
		)

		if i < players.size():
			players[i].mage.room_coord = entrance_room
			players[i].mage.room_id = coord_to_room_id(
				entrance_room
			)
			print(
				"Player ",
				i + 1,
				" entrance room: ",
				entrance_room
			)

	print(
		"Cells created: ",
		cell_slots.size()
	)
	
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
	amount: int,
	action_type: String = ""
) -> int:

	# =====================================================
	# VALIDAZIONE
	# =====================================================

	if target_player_index < 0 \
	or target_player_index >= players.size():
		print(
			"ERRORE: target_player_index non valido: ",
			target_player_index
		)
		return 0

	if amount <= 0:
		return 0


	var target_player = players[target_player_index]
	var target_mage = target_player.mage


	# =====================================================
	# QUANTO DAMAGE PUÒ RICEVERE IL MAGE
	# =====================================================

	var damage_capacity = (
		target_mage.get_remaining_health()
	)

	if damage_capacity <= 0:
		return 0

	var requested_damage = min(
		amount,
		damage_capacity
	)


	# =====================================================
	# PRE-DAMAGE EVENT
	#
	# Qui possono intervenire:
	# - Protection
	# - Permanent
	# - effetti di redirect / replacement
	#
	# Il Damage NON è ancora stato applicato.
	# =====================================================

	var pre_event = GameEvent.new(
		"damage_about_to_be_inflicted"
	)


	# -----------------------------------------------------
	# SOURCE
	# -----------------------------------------------------

	if attacker_id == -1:
		pre_event.source_model_type = "black_rose"
		pre_event.source_player_index = -1
		pre_event.source_room_id = ""

	else:
		pre_event.source_model_type = "mage"
		pre_event.source_player_index = attacker_id

		pre_event.source_room_id = (
			players[attacker_id]
			.mage
			.room_id
		)


	# -----------------------------------------------------
	# TARGET
	# -----------------------------------------------------

	pre_event.target_model_type = "mage"
	pre_event.target_player_index = target_player_index
	pre_event.target_room_id = target_mage.room_id


	# -----------------------------------------------------
	# DAMAGE / CAUSA
	# -----------------------------------------------------

	pre_event.amount = requested_damage
	pre_event.action_type = action_type


	# -----------------------------------------------------
	# TRIGGER PRE-DAMAGE
	# -----------------------------------------------------

	process_game_event(
		pre_event
	)


	# =====================================================
	# EVENTO CANCELLATO
	# =====================================================

	if pre_event.cancelled:
		print(
			"Damage cancelled on Player ",
			target_player_index + 1
		)

		return 0


	# =====================================================
	# REDIRECT VERSO EVOCATION
	#
	# Esempio:
	# Pain Mark Dark
	# =====================================================

	if pre_event.redirected_evocation != null:
		var redirected_evocation = (
			pre_event.redirected_evocation
		)

		var redirected_amount = min(
			pre_event.amount,
			redirected_evocation.get_remaining_health()
		)

		if redirected_amount <= 0:
			return 0


		# -------------------------------------------------
		# PRENDI I CUBI DALL'ATTACCANTE
		# -------------------------------------------------

		var redirected_cubes = take_owner_cubes(
			attacker_id,
			redirected_amount
		)

		if redirected_cubes <= 0:
			return 0


		# -------------------------------------------------
		# APPLICA DAMAGE ALL'EVOCATION
		# -------------------------------------------------

		var redirected_damage = (
			redirected_evocation.add_damage(
				attacker_id,
				redirected_cubes
			)
		)


		print(
			"Damage redirected: attacker ",
			attacker_id,
			" -> Evocation ",
			redirected_evocation.evocation_name,
			" | ",
			redirected_damage,
			" damage",
			" | HP: ",
			redirected_evocation.get_remaining_health(),
			"/",
			redirected_evocation.health
		)


		# -------------------------------------------------
		# NOTA
		#
		# Per ora il redirect sostituisce completamente
		# il Damage al Mage.
		#
		# Se l'Evocation ha meno Health del Damage totale,
		# l'eccesso NON torna sul Mage.
		#
		# Inoltre, essendo stato rediretto, questo Damage
		# NON può sconfiggere il Mage originale.
		# -------------------------------------------------

		return redirected_damage


	# =====================================================
	# DAMAGE NORMALE AL MAGE
	# =====================================================

	var final_damage_amount = min(
		pre_event.amount,
		target_mage.get_remaining_health()
	)

	if final_damage_amount <= 0:
		return 0


	# -----------------------------------------------------
	# PRENDI I CUBI DALLA RISERVA DELL'ATTACCANTE
	# -----------------------------------------------------

	var cubes_available = take_owner_cubes(
		attacker_id,
		final_damage_amount
	)

	if cubes_available <= 0:
		return 0


	# =====================================================
	# STATO DEL MAGE PRIMA DEL DAMAGE
	#
	# Serve per generare mage_defeated UNA SOLA VOLTA:
	#
	# false -> true = nuova sconfitta
	# true  -> true = nessun nuovo evento
	# =====================================================

	var was_defeated = target_mage.is_defeated()


	# -----------------------------------------------------
	# APPLICA DAMAGE
	# -----------------------------------------------------

	var damage_dealt = target_mage.add_damage(
		attacker_id,
		cubes_available
	)


	# =====================================================
	# REFRESH UI
	# =====================================================

	if target_player_index < player_boards.size():
		player_boards[
			target_player_index
		].refresh()


	if attacker_id >= 0 \
	and attacker_id < player_boards.size():

		player_boards[
			attacker_id
		].refresh()


	# =====================================================
	# DEBUG
	# =====================================================

	print(
		"Damage: attacker ",
		attacker_id,
		" -> Player ",
		target_player_index + 1,
		" | ",
		damage_dealt,
		" damage",
		" | Target HP: ",
		target_mage.get_remaining_health(),
		"/",
		target_mage.health
	)


	# =====================================================
	# POST-DAMAGE EVENT
	#
	# Qui reagiscono effetti del tipo:
	# - Torment
	# - Pain Mark Light
	# - Master of Pleasure Dark
	# - "after a Mage inflicts Damage..."
	# - "another Mage suffers Damage..."
	# =====================================================

	if damage_dealt > 0:
		var post_event = GameEvent.new(
			"damage_inflicted"
		)


		# -------------------------------------------------
		# SOURCE
		# -------------------------------------------------

		if attacker_id == -1:
			post_event.source_model_type = (
				"black_rose"
			)

			post_event.source_player_index = -1
			post_event.source_room_id = ""

		else:
			post_event.source_model_type = "mage"
			post_event.source_player_index = attacker_id

			post_event.source_room_id = (
				players[attacker_id]
				.mage
				.room_id
			)


		# -------------------------------------------------
		# TARGET
		# -------------------------------------------------

		post_event.target_model_type = "mage"

		post_event.target_player_index = (
			target_player_index
		)

		post_event.target_room_id = (
			target_mage.room_id
		)


		# -------------------------------------------------
		# DAMAGE EFFETTIVAMENTE INFLITTO
		# -------------------------------------------------

		post_event.amount = damage_dealt
		post_event.action_type = action_type


		# -------------------------------------------------
		# TRIGGER POST-DAMAGE
		# -------------------------------------------------

		process_game_event(
			post_event
		)


	# =====================================================
	# MAGE DEFEATED EVENT
	#
	# IMPORTANTE:
	#
	# Viene generato solamente quando il Mage passa
	# effettivamente da:
	#
	#     non sconfitto -> sconfitto
	#
	# Questo evento servirà a:
	# - Liquefy the Pain Light
	# - Liquefy the Pain Dark
	# - future carte "when X is defeated"
	# =====================================================

	var is_defeated_now = (
		target_mage.is_defeated()
	)

	if not was_defeated \
	and is_defeated_now:

		var defeat_event = GameEvent.new(
			"mage_defeated"
		)


		# -------------------------------------------------
		# SOURCE = chi ha inflitto il Damage decisivo
		# -------------------------------------------------

		if attacker_id == -1:
			defeat_event.source_model_type = (
				"black_rose"
			)

			defeat_event.source_player_index = -1
			defeat_event.source_room_id = ""

		else:
			defeat_event.source_model_type = "mage"

			defeat_event.source_player_index = (
				attacker_id
			)

			defeat_event.source_room_id = (
				players[attacker_id]
				.mage
				.room_id
			)


		# -------------------------------------------------
		# TARGET = Mage sconfitto
		# -------------------------------------------------

		defeat_event.target_model_type = "mage"

		defeat_event.target_player_index = (
			target_player_index
		)

		# Questa è particolarmente importante per
		# Liquefy the Pain Dark.
		defeat_event.target_room_id = (
			target_mage.room_id
		)


		# -------------------------------------------------
		# DAMAGE DECISIVO / CAUSA
		# -------------------------------------------------

		defeat_event.amount = damage_dealt
		defeat_event.action_type = action_type


		# -------------------------------------------------
		# DEBUG
		# -------------------------------------------------

		if attacker_id == -1:
			print(
				"MAGE DEFEATED: Player ",
				target_player_index + 1,
				" | defeated by Black Rose",
				" | Room: ",
				target_mage.room_id
			)

		else:
			print(
				"MAGE DEFEATED: Player ",
				target_player_index + 1,
				" | defeated by Player ",
				attacker_id + 1,
				" | Room: ",
				target_mage.room_id
			)


		# -------------------------------------------------
		# TRIGGER DELLE SPELL LEGATE ALLA SCONFITTA
		# -------------------------------------------------

		process_game_event(
			defeat_event
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

func create_player_boards():
	for board in player_boards:
		if board != null:
			board.queue_free()

	player_boards.clear()

	for i in range(players.size()):
		var board = player_board_scene.instantiate()

		board.setup(players[i])

		add_child(board)
		player_boards.append(board)

	update_player_board_positions()
	
func update_player_board_positions():
	var board_scale = 0.34

	var left_x = 0.0
	var right_x = 1390.0

	var y_positions = [
		20.0,
		325.0,
		630.0
	]

	for i in range(player_boards.size()):
		var board = player_boards[i]

		board.scale = Vector2(board_scale, board_scale)

		# P1, P3, P5 a sinistra
		if i % 2 == 0:
			var row = int(i / 2)

			board.position = Vector2(
				left_x,
				y_positions[row]
			)

		# P2, P4, P6 a destra
		else:
			var row = int(i / 2)

			board.position = Vector2(
				right_x,
				y_positions[row]
			)
			
func update_table_layout():
	# -------------------------
	# POWER BOARD
	# -------------------------

	var right_center_room = hex_to_pixel(Vector2i(2, -1))

	var power_connection_point = (
		right_center_room
		+ Vector2(HEX_RADIUS, 0)
	)

	var power_notch = Vector2(35, 325)

	$PowerBoard.position = (
		power_connection_point
		- power_notch
	)


	# -------------------------
	# EVENT BOARD
	# -------------------------

	var left_center_room = hex_to_pixel(Vector2i(-2, 1))

	var event_connection_point = (
		left_center_room
		- Vector2(HEX_RADIUS, 0)
	)

	# La Event Board è specchiata:
	# il suo rientro centrale è vicino al bordo destro.
	var event_board_width = 306.0
	var event_notch = Vector2(
		event_board_width - 35.0,
		325.0
	)

	$EventBoard.position = (
		event_connection_point
		- event_notch
	)


	update_player_board_positions()


func set_player_power(player_index: int, value: int):
	if player_index < 0 or player_index >= players.size():
		print("ERRORE: player_index non valido: ", player_index)
		return

	value = clamp(
		value,
		0,
		$PowerBoard.end_game_threshold
	)

	players[player_index].power = value

	$PowerBoard.set_player_power(
		player_index,
		value
	)

	if player_index < player_boards.size():
		player_boards[player_index].refresh()

	check_moon_phase()
func add_player_power(
	player_index: int,
	amount: int
):
	if player_index < 0 \
	or player_index >= players.size():
		print(
			"ERRORE: player_index non valido: ",
			player_index
		)
		return

	if amount == 0:
		return

	# Power prima della modifica
	var old_power = players[player_index].power

	# set_player_power continua a occuparsi di:
	# - aggiornamento del valore
	# - eventuali limiti
	# - Power Board / UI
	set_player_power(
		player_index,
		old_power + amount
	)

	# Power realmente ottenuto dopo set_player_power()
	var new_power = players[player_index].power

	var actual_change = (
		new_power - old_power
	)

	# Nessuna variazione reale:
	# non deve esistere alcun trigger.
	if actual_change == 0:
		return


	# =====================================================
	# POWER GAINED
	# =====================================================

	if actual_change > 0:
		print(
			"Player ",
			player_index + 1,
			" gained ",
			actual_change,
			" Power"
		)

		var event = GameEvent.new(
			"power_gained"
		)

		event.source_model_type = "mage"
		event.source_player_index = player_index

		event.source_room_id = (
			players[player_index]
			.mage
			.room_id
		)

		event.amount = actual_change

		process_game_event(
			event
		)

		return


	# =====================================================
	# POWER LOST
	# =====================================================

	print(
		"Player ",
		player_index + 1,
		" lost ",
		abs(actual_change),
		" Power"
	)

	var event = GameEvent.new(
		"power_lost"
	)

	event.source_model_type = "mage"
	event.source_player_index = player_index

	event.source_room_id = (
		players[player_index]
		.mage
		.room_id
	)

	event.amount = abs(actual_change)

	process_game_event(
		event
	)
	
func set_black_rose_power(value: int):
	value = clamp(
		value,
		0,
		$PowerBoard.end_game_threshold
	)

	black_rose_power = value

	$PowerBoard.set_black_rose_power(value)

	check_moon_phase()
	
func add_black_rose_power(amount: int):
	set_black_rose_power(
		black_rose_power + amount
	)
func check_moon_phase():
	var highest_power = black_rose_power

	for player in players:
		highest_power = max(
			highest_power,
			player.power
		)

	var new_moon = current_moon

	if highest_power >= $PowerBoard.third_moon_threshold:
		new_moon = 3

	elif highest_power >= $PowerBoard.second_moon_threshold:
		new_moon = 2

	else:
		new_moon = 1

	# La Moon non può regredire.
	if new_moon > current_moon:
		current_moon = new_moon

		print(
			"GAME: Moon changed to ",
			current_moon
		)

		$EventBoard.set_moon(current_moon)
	
func summon_evocation(
	owner_id: int,
	evocation_id: String,
	room_id: String
) -> EvocationState:

	if owner_id < 0 or owner_id >= players.size():
		print("ERRORE: owner_id non valido")
		return null

	var player = players[owner_id]

	if not player.has_free_evocation_slot():
		print(
			"Player ",
			owner_id + 1,
			" has no free Evocation slots"
		)
		return null

	var data = evocation_database.get_evocation(
		evocation_id
	)

	if data.is_empty():
		print(
			"Unknown Evocation: ",
			evocation_id
		)
		return null

	var evocation = EvocationState.new(
		data["id"],
		data["name"],
		data["archetype"],
		int(data["health"]),
		int(data["strength"]),
		int(data["speed"]),
		owner_id
	)

	evocation.room_id = room_id

	if not player.add_evocation(evocation):
		return null

	print(
		"Player ",
		owner_id + 1,
		" summoned ",
		evocation.evocation_name,
		" in room ",
		room_id
	)

	return evocation

func deal_damage_to_model(
	attacker_id: int,
	model: Dictionary,
	amount: int
) -> int:

	if model.is_empty():
		return 0

	var kind = str(model.get("kind", ""))

	match kind:
		"mage":
			var player_index = int(
				model.get("player_index", -1)
			)

			return deal_damage(
				attacker_id,
				player_index,
				amount
			)

		"evocation":
			var evocation = model.get("state")

			if evocation == null:
				return 0

			var damage_dealt = evocation.add_damage(
				attacker_id,
				amount
			)

			print(
				"Damage: attacker ",
				attacker_id,
				" -> Evocation ",
				evocation.evocation_name,
				" | ",
				damage_dealt,
				" damage"
			)

			return damage_dealt

		_:
			print(
				"Unknown model kind: ",
				kind
			)

			return 0
			
func deal_damage_to_evocation(
	attacker_id: int,
	evocation: EvocationState,
	amount: int
) -> int:

	if evocation == null:
		return 0

	if amount <= 0:
		return 0

	var damage_dealt = evocation.add_damage(
		attacker_id,
		amount
	)

	print(
		"Damage: attacker ",
		attacker_id,
		" -> Evocation ",
		evocation.evocation_name,
		" | ",
		damage_dealt,
		" damage",
		" | HP: ",
		evocation.get_remaining_health(),
		"/",
		evocation.health
	)

	return damage_dealt

func process_game_event(
	event: GameEvent
):
	var triggered = (
		triggered_spell_manager
		.get_triggered_spells(
			event,
			players
		)
	)

	for trigger_data in triggered:
		handle_triggered_spell(
			trigger_data
		)
		
func handle_triggered_spell(
	trigger_data: Dictionary
):
	var active_spell = (
		trigger_data["active_spell"]
	)

	var event = trigger_data["event"]

	var spell_type = (
		active_spell.get_spell_type()
	)

	match spell_type:
		"trap":
			handle_triggered_trap(
				active_spell,
				event
			)

		"protection":
			handle_triggered_protection(
				active_spell,
				event
			)

		"permanent":
			handle_triggered_permanent(
				active_spell,
				event
			)

		_:
			print(
				"Unsupported triggered spell type: ",
				spell_type
			)
			
func handle_triggered_trap(
	active_spell: ActiveSpellState,
	event: GameEvent
):
	print(
		"TRAP TRIGGERED: ",
		active_spell.spell.card_name,
		" | Player ",
		active_spell.owner_id + 1
	)

	resolve_triggered_spell(
		active_spell,
		event
	)
	
func handle_triggered_protection(
	active_spell: ActiveSpellState,
	event: GameEvent
):
	print(
		"PROTECTION TRIGGERED but not implemented: ",
		active_spell.spell.card_name
	)
	
func handle_triggered_permanent(
	active_spell: ActiveSpellState,
	event: GameEvent
):
	print(
		"PERMANENT TRIGGERED: ",
		active_spell.spell.card_name,
		" | Player ",
		active_spell.owner_id + 1
	)

	resolve_triggered_spell(
		active_spell,
		event
	)
	
func resolve_triggered_spell(
	active_spell: ActiveSpellState,
	event: GameEvent
):
	var context = {
	"game": self,
	"caster_id": active_spell.owner_id,
	"caster_room_id":
		players[active_spell.owner_id].mage.room_id,
	"trigger_event": event,

	"marked_player_index":
		active_spell.target_player_index,

	"triggering_model_type":
		event.source_model_type,

	"triggering_player_index":
		event.source_player_index,

	"triggering_evocation":
		event.source_evocation,

	"triggering_room_id":
		event.source_room_id,

	"trigger_damage_amount":
		event.amount
}

	var success = effect_resolver.resolve_effects(
		active_spell.get_effects(),
		context
	)

	if not success:
		print(
			"Failed to resolve triggered spell: ",
			active_spell.spell.card_name
		)
		return

	# Per ora questo comportamento vale per le Trap.
	# Permanent/Protection avranno il loro lifecycle quando
	# le implementeremo.
	if active_spell.get_spell_type() == "trap":
		active_spell.active = false

	print(
		"Triggered spell resolved: ",
		active_spell.spell.card_name
	)

func set_mage_starting_position(
	player_index: int,
	room_id: String,
	room_coord: Vector2i
):
	if player_index < 0 or player_index >= players.size():
		return

	var mage = players[player_index].mage

	mage.room_id = room_id
	mage.room_coord = room_coord

	print(
		"Player ",
		player_index + 1,
		" starts in ",
		room_id,
		" at ",
		room_coord
	)
func coord_to_room_id(coord: Vector2i) -> String:
	if room_id_by_coord.has(coord):
		return room_id_by_coord[coord]

	print(
		"WARNING: no Room found at coord ",
		coord
	)

	return ""

func deal_damage_from_evocation(
	evocation: EvocationState,
	target_player_index: int,
	amount: int
) -> int:

	if evocation == null:
		return 0

	if target_player_index < 0 or target_player_index >= players.size():
		return 0

	if amount <= 0:
		return 0

	var target_mage = players[target_player_index].mage

	var damage_capacity = target_mage.get_remaining_health()

	if damage_capacity <= 0:
		return 0

	var requested_damage = min(
		amount,
		damage_capacity
	)

	# I cubi appartengono al controller dell'Evocation
	var attacker_id = evocation.controller_id

	var cubes_available = take_owner_cubes(
		attacker_id,
		requested_damage
	)

	if cubes_available <= 0:
		return 0

	var damage_dealt = target_mage.add_damage(
		attacker_id,
		cubes_available
	)

	# Refresh UI
	if target_player_index < player_boards.size():
		player_boards[target_player_index].refresh()

	if attacker_id >= 0 and attacker_id < player_boards.size():
		player_boards[attacker_id].refresh()

	print(
		"Damage: Evocation ",
		evocation.evocation_name,
		" (P",
		attacker_id + 1,
		") -> Player ",
		target_player_index + 1,
		" | ",
		damage_dealt,
		" damage"
	)

	# GameEvent generato dalla Evocation
	if damage_dealt > 0:
		var event = GameEvent.new(
			"damage_inflicted"
		)

		event.source_model_type = "evocation"
		event.source_player_index = attacker_id
		event.source_evocation = evocation
		event.source_room_id = evocation.room_id

		event.target_model_type = "mage"
		event.target_player_index = target_player_index
		event.target_room_id = target_mage.room_id

		event.amount = damage_dealt

		process_game_event(event)

	return damage_dealt
