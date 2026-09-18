extends Node2D

const Tests = preload("res://tests.gd")
# =========================================================
# INTERACTIVE PHASE STATE
# =========================================================

signal player_input_requested(request: Dictionary)
signal player_input_resolved(request: Dictionary)


var waiting_for_player_input: bool = false
var pending_input: Dictionary = {}


# Snapshot dell'ordine della Phase corrente.
var current_phase_play_order: Array[int] = []
# =========================================================
# TRIGGER WINDOW STATE
# =========================================================

var trigger_window_active: bool = false

var trigger_window_event: GameEvent = null

var trigger_window_queue: Array = []

var trigger_window_cursor: int = 0
# =========================================================
# RESOLUTION STACK
# =========================================================

var resolution_stack: Array[Dictionary] = []
var processing_resolution_stack: bool = false

# =========================================================
# ACTION PHASE STATE
# =========================================================

var action_phase_cursor: int = 0
var action_phase_activation_round: int = 0
# =========================================================
# PREPARATION PHASE STATE
# =========================================================

var preparation_phase_cursor: int = 0
# =========================================================
# STUDY PHASE STATE
# =========================================================

var study_phase_cursor: int = 0

# Le 4 carte temporaneamente pescate dalla Library
# dal giocatore che sta risolvendo lo Study.
var study_drawn_cards: Array[SpellCardState] = []
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
var room_effect_resolver = RoomEffectResolver.new()
var event_effect_resolver := EventEffectResolver.new()
const BOARD_CENTER = Vector2(576, 324)
var room_id_by_coord: Dictionary = {}
var suppressed_trigger_types: Array[String] = []
var school_libraries: Dictionary = {}
var school_discards: Dictionary = {}
const ACTIVE_SCHOOL_COUNT: int = 6
var active_school_ids: Array[String] = []
var forgotten_deck: Array[SpellCardState] = []
var forgotten_discard: Array[SpellCardState] = []
var crown_owner_id: int = -1
var event_database := EventDatabase.new()
var current_round: int = 1


# Fase corrente della partita.
var current_phase: String = ""

const PHASE_BLACK_ROSE: String = "black_rose"
const PHASE_STUDY: String = "study"
const PHASE_PREPARATION: String = "preparation"
const PHASE_ACTION: String = "action"
const PHASE_EVOCATION: String = "evocation"
const PHASE_CLEANUP: String = "cleanup"
var event_decks: Dictionary = {
	1: [],
	2: [],
	3: []
}

var event_discard: Array[EventCardState] = []

var active_events: Array = [
	null,
	null,
	null
]

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
	select_active_schools()
	create_school_libraries()
	create_forgotten_deck()
	event_database.load_database()
	create_event_decks()
	evocation_database.load_database()
	create_players()
	assign_initial_crown()
	create_lodge()
	create_player_boards()
	player_boards[0].refresh()
	player_boards[1].refresh()
	await $PowerBoard.initialize(player_count)
	$EventBoard.refresh_event_slots()	
	update_table_layout()
	await get_tree().process_frame
	Tests.run(self)
	

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

func create_room(
	room_data: Dictionary,
	hex_position: Vector2i
):
	var room = room_scene.instantiate()

	# -----------------------------------------------------
	# ROOM DEFINITION
	# -----------------------------------------------------

	room.setup_room(room_data)

	room.room_color = get_room_color(
		room_data["color"]
	)

	room.radius = HEX_RADIUS

	# -----------------------------------------------------
	# POSITION
	# -----------------------------------------------------

	room.position = hex_to_pixel(
		hex_position
	)

	add_child(room)

	# -----------------------------------------------------
	# COORDINATE -> ROOM ID
	# -----------------------------------------------------

	room_id_by_coord[hex_position] = str(
		room_data["id"]
	)


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

		# =================================================
		# POSIZIONE DELLA CELL
		# =================================================

		var position_array = slot_data["position"]

		var hex_position = Vector2i(
			int(position_array[0]),
			int(position_array[1])
		)


		# =================================================
		# CELL RANDOM
		# =================================================

		var cell_data = selected_cells[i]

		create_cell(
			cell_data,
			hex_position
		)


		# =================================================
		# ENTRANCE ROOM
		#
		# Questa NON è la posizione attuale del Mage.
		# È la Room attraverso cui entra nella Lodge.
		# =================================================

		var entrance_array = slot_data[
			"entrance_room"
		]

		var entrance_room = Vector2i(
			int(entrance_array[0]),
			int(entrance_array[1])
		)


		if i < players.size():

			players[i].mage.room_coord = (
				entrance_room
			)

			players[i].mage.room_id = (
				coord_to_room_id(
					entrance_room
				)
			)

			# Il Mage comincia fisicamente nella Cell.
			players[i].mage.in_cell = true


			print(
				"Player ",
				i + 1,
				" entrance room: ",
				entrance_room,
				" | starts in Cell: ",
				players[i].mage.in_cell
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
	
func place_black_rose_instability(
	room_id: String,
	amount: int = 1
):

	var placed: int = place_instability(
		-1,
		room_id,
		amount
	)


	print(
		"Black Rose placed ",
		placed,
		" instability in ",
		room_id
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

func place_player_instability(
	player_index: int,
	room_id: String,
	amount: int = 1
):

	if player_index < 0 \
	or player_index >= players.size():

		print(
			"ERRORE: player_index non valido: ",
			player_index
		)

		return


	var placed: int = place_instability(
		player_index,
		room_id,
		amount
	)


	print(
		players[player_index].player_name,
		" placed ",
		placed,
		" instability",
		" | Cubes left: ",
		players[player_index].available_cubes
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
	action_type: String = "",
	suppressed_trigger_types: Array = []
) -> bool:

	if target_player_index < 0 \
	or target_player_index >= players.size():

		print(
			"deal_damage: invalid target player"
		)

		return false


	if amount <= 0:
		return true


	var resolution: Dictionary = {

		"type":
			"damage",

		"step":
			"pre_event",

		"attacker_id":
			attacker_id,

		"target_player_index":
			target_player_index,

		"amount":
			amount,

		"action_type":
			action_type,

		"suppressed_trigger_types":
			suppressed_trigger_types.duplicate(),

		"event":
			null
	}


	return queue_resolution(
		resolution
	)
		
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
	amount: int,
	suppressed_trigger_types: Array[String] = []
) -> int:

	if evocation == null:
		return 0

	if amount <= 0:
		return 0


	# =====================================================
	# STATE BEFORE DAMAGE
	#
	# Serve per evitare di emettere più volte l'evento
	# "defeated" se, per qualche motivo, viene applicato
	# altro Damage a una Evocation già sconfitta.
	# =====================================================

	var was_defeated = evocation.is_defeated()


	# =====================================================
	# APPLY DAMAGE
	# =====================================================

	var damage_dealt = evocation.add_damage(
		attacker_id,
		amount
	)


	# =====================================================
	# DEBUG
	# =====================================================

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


	# =====================================================
	# EVOCATION DEFEATED
	#
	# L'evento viene emesso soltanto nel momento esatto
	# in cui passa da viva -> defeated.
	#
	# IMPORTANTE:
	# lo facciamo mentre l'oggetto Evocation esiste ancora,
	# così Stone Phoenix può leggere:
	#
	# - owner_id
	# - room_id
	# - evocation_id
	# - evocation_name
	# =====================================================

	if not was_defeated \
	and evocation.is_defeated():

		emit_evocation_defeated_or_removed(
			evocation,
			"defeated"
		)


	return damage_dealt

func process_game_event(
	event: GameEvent
) -> bool:

	if event == null:
		return true


	var triggered = (
		triggered_spell_manager
		.get_triggered_spells(
			event,
			players
		)
	)


	if triggered.is_empty():
		return true


	# =====================================================
	# SEPARATE AUTOMATIC / OPTIONAL TRIGGERS
	# =====================================================

	var automatic_triggers: Array = []
	var optional_triggers: Array = []


	for trigger_data in triggered:

		var active_spell: ActiveSpellState = (
			trigger_data.get(
				"active_spell",
				null
			)
		)


		if active_spell == null:
			continue


		var spell_type: String = (
			active_spell.get_spell_type()
		)


		match spell_type:

			"permanent":

				automatic_triggers.append(
					trigger_data
				)


			"trap", "protection":

				optional_triggers.append(
					trigger_data
				)


			_:

				print(
					"Unsupported triggered spell type: ",
					spell_type
				)


	# =====================================================
	# AUTOMATIC TRIGGERS
	#
	# Permanents don't require a player decision.
	# =====================================================

	for trigger_data in automatic_triggers:

		handle_triggered_spell(
			trigger_data
		)


	# =====================================================
	# NO OPTIONAL TRIGGERS
	# =====================================================

	if optional_triggers.is_empty():
		return true


	# =====================================================
	# OPEN OPTIONAL TRIGGER WINDOW
	# =====================================================

	if trigger_window_active:

		print(
			"process_game_event: nested optional trigger window"
		)

		return false


	trigger_window_active = true

	trigger_window_event = event

	trigger_window_queue = (
		order_optional_triggers(
			optional_triggers
		)
	)

	trigger_window_cursor = 0


	# IMPORTANT:
	#
	# false means:
	# resolution CANNOT continue yet.
	#
	# A player decision is required.
	return false
		
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
		"PROTECTION TRIGGERED: ",
		active_spell.spell.card_name,
		" | Player ",
		active_spell.owner_id + 1
	)

	resolve_triggered_spell(
		active_spell,
		event
	)

	# Una Protection rivelata non è più Active.
	active_spell.active = false
	
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

	# =====================================================
	# BASE RESOLUTION CONTEXT
	# =====================================================

	var context = {
		"game": self,

		"caster_id":
			active_spell.owner_id,

		"caster_room_id":
			players[
				active_spell.owner_id
			].mage.room_id,

		# Original event.
		# Effects such as Silver of the Sages can modify
		# event.amount before Damage is actually applied.
		"trigger_event":
			event,


		# =================================================
		# STORED TARGET
		# =================================================

		"marked_player_index":
			active_spell.target_player_index,


		# =================================================
		# TRIGGER SOURCE
		# =================================================

		"triggering_model_type":
			event.source_model_type,

		"triggering_player_index":
			event.source_player_index,

		"triggering_evocation":
			event.source_evocation,

		"triggering_room_id":
			event.source_room_id,

		"trigger_damage_amount":
			event.amount,


		# =================================================
		# TRIGGER TARGET
		# =================================================

		"trigger_evocation":
			event.target_evocation,

		"trigger_evocation_owner":
			event.target_player_index,

		"trigger_evocation_room_id":
			event.target_room_id,

		"trigger_evocation_reason":
			event.action_type
	}


	# =====================================================
	# RESTORE ACTIVE SPELL CONTEXT
	#
	# Active spells may need to remember choices/targets
	# selected before the trigger occurs.
	#
	# Examples:
	# - Silver choice
	# - selected Evocation
	# - future Trap/Protection choices
	# =====================================================

	for key in active_spell.context:

		context[key] = (
			active_spell.context[key]
		)


	# =====================================================
	# RESOLVE EFFECTS
	# =====================================================
		# =====================================================
	# REVEAL INSTABILITY
	#
	# Trap / Protection were not revealed when cast.
	# They are revealed NOW.
	# =====================================================

	if not resolve_spell_reveal_instability(
		active_spell.owner_id,
		active_spell.spell
	):

		print(
			"Failed to resolve reveal Instability for ",
			active_spell.spell.card_name
		)

		return
		
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


	# =====================================================
	# SAVE RESOLUTION CONTEXT
	#
	# Keep results produced by the EffectResolver available
	# on the ActiveSpellState.
	#
	# We intentionally do not store references to Game
	# or the triggering GameEvent.
	# =====================================================

	for key in context:

		if key == "game":
			continue

		if key == "trigger_event":
			continue

		active_spell.context[key] = (
			context[key]
		)


	# =====================================================
	# TRAP LIFECYCLE
	#
	# Existing behaviour:
	# a triggered Trap is no longer Active.
	#
	# Protection lifecycle is handled by
	# handle_triggered_protection().
	# =====================================================

	if active_spell.get_spell_type() == "trap":

		active_spell.active = false


	# =====================================================
	# LOG
	# =====================================================

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

func get_revealed_element_counts(
	player_index: int
) -> Dictionary:

	var counts: Dictionary = {}

	if player_index < 0 \
	or player_index >= players.size():
		return counts

	for revealed in players[player_index].revealed_spells:
		var element = revealed.get_element()

		if element == "":
			continue

		if element == "all":
			counts["all"] = (
				int(counts.get("all", 0))
				+ 1
			)
		else:
			counts[element] = (
				int(counts.get(element, 0))
				+ 1
			)

	return counts
	
func can_apply_enhancement(
	player_index: int,
	required_elements: Array
) -> bool:

	var counts = get_revealed_element_counts(
		player_index
	)

	var wildcards = int(
		counts.get("all", 0)
	)

	for required_element in required_elements:
		var element = str(
			required_element
		)

		var available = int(
			counts.get(element, 0)
		)

		if available > 0:
			counts[element] = available - 1
			continue

		if wildcards > 0:
			wildcards -= 1
			continue

		return false

	return true

func resolve_spell(
	spell: SpellCardState,
	use_dark_side: bool,
	context: Dictionary
) -> bool:

	var caster_id = int(
		context.get("caster_id", -1)
	)

	if caster_id < 0 \
	or caster_id >= players.size():
		return false


	var side = spell.get_side(
		use_dark_side
	)
	context["spell_target_type"] = str(
		side.get("target", "")
	)

	context["spell_range"] = side.get(
		"range",
		null
	)

	# Ogni risoluzione di Spell parte con una nuova lista.
	context["models_damaged_by_effect"] = []
	var enhancement = side.get(
		"enhancement",
		{}
	)

	var enhancement_active = false


	# =====================================================
	# VERIFICA ENHANCEMENT
	# =====================================================

	if not enhancement.is_empty():
		var required_elements: Array = (
			enhancement.get(
				"requires",
				[]
			)
		)

		enhancement_active = can_apply_enhancement(
			caster_id,
			required_elements
		)


	context["enhancement_active"] = (
		enhancement_active
	)


	# =====================================================
	# ORDINE DI RISOLUZIONE
	# =====================================================

	var resolution_order: Array = side.get(
		"resolution_order",
		[
			"base",
			"enhancement"
		]
	)


	for step in resolution_order:

		match str(step):

			"base":
				if not effect_resolver.resolve_effects(
					spell.get_effects(
						use_dark_side
					),
					context
				):
					return false


			"enhancement":
				if not enhancement_active:
					continue

				var enhancement_effects: Array = (
					enhancement.get(
						"effects",
						[]
					)
				)

				if not effect_resolver.resolve_effects(
					enhancement_effects,
					context
				):
					return false


			_:
				print(
					"Unknown resolution step: ",
					step
				)

				return false


	# =====================================================
	# SPELL REVEALED
	# =====================================================

	var revealed = RevealedSpellState.new(
		spell,
		use_dark_side
	)

	players[caster_id].add_revealed_spell(
		revealed
	)


	return true
func room_id_to_coord(
	room_id: String
) -> Vector2i:

	for coord in room_id_by_coord.keys():

		if str(
			room_id_by_coord[coord]
		) == room_id:
			return coord

	print(
		"room_id_to_coord: Room not found: ",
		room_id
	)

	return Vector2i(
		9999,
		9999
	)
func get_hex_distance(
	a: Vector2i,
	b: Vector2i
) -> int:

	var dq = a.x - b.x
	var dr = a.y - b.y

	return int(
		(
			abs(dq)
			+ abs(dr)
			+ abs(dq + dr)
		) / 2
	)
func move_mage_to_room_id(
	player_index: int,
	destination_room_id: String,
	max_distance: int
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	if max_distance < 0:
		return false


	var mage = players[
		player_index
	].mage


	if mage == null:
		return false


	var destination_coord: Vector2i = (
		room_id_to_coord(
			destination_room_id
		)
	)


	if destination_coord == Vector2i(
		9999,
		9999
	):

		print(
			"move_mage_to_room_id: invalid destination Room: ",
			destination_room_id
		)

		return false


	# =====================================================
	# CELL -> LODGE
	#
	# Quando il Mage è nella Cell:
	#
	# mage.room_id
	# mage.room_coord
	#
	# rappresentano la sua Entrance Room.
	#
	# Il primo Move può quindi portarlo SOLAMENTE
	# nella propria Entrance Room.
	# =====================================================

	if mage.in_cell:

		var entrance_room_id: String = (
			mage.room_id
		)


		if destination_room_id != entrance_room_id:

			print(
				"move_mage_to_room_id: Player ",
				player_index + 1,
				" must enter through ",
				entrance_room_id,
				", not ",
				destination_room_id
			)

			return false


		mage.room_coord = destination_coord
		mage.in_cell = false


		print(
			"Player ",
			player_index + 1,
			" entered the Lodge through ",
			destination_room_id
		)


		return true


	# =====================================================
	# NORMAL LODGE MOVEMENT
	# =====================================================

	var distance: int = get_hex_distance(
		mage.room_coord,
		destination_coord
	)


	if distance > max_distance:

		print(
			"move_mage_to_room_id: destination too far | ",
			distance,
			" > ",
			max_distance
		)

		return false


	mage.room_id = destination_room_id
	mage.room_coord = destination_coord
	mage.in_cell = false


	print(
		"Player ",
		player_index + 1,
		" moved to ",
		destination_room_id
	)


	return true
	
func move_evocation_to_room_id(
	evocation: EvocationState,
	destination_room_id: String,
	max_distance: int
) -> bool:

	if evocation == null:
		return false

	var from_coord = room_id_to_coord(
		evocation.room_id
	)

	var to_coord = room_id_to_coord(
		destination_room_id
	)

	if from_coord == Vector2i(9999, 9999) \
	or to_coord == Vector2i(9999, 9999):
		return false

	if get_hex_distance(
		from_coord,
		to_coord
	) > max_distance:

		print(
			"Movement exceeds range"
		)

		return false

	evocation.room_id = destination_room_id

	print(
		evocation.evocation_name,
		" moved to ",
		destination_room_id
	)

	return true

func is_lodge_room_id(room_id: String) -> bool:

	if room_id == "":
		return false

	return room_id in room_id_by_coord.values()

func is_mage_in_cell(
	player_index: int
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():
		return false

	return players[player_index].mage.in_cell

func emit_evocation_defeated_or_removed(
	evocation: EvocationState,
	event_reason: String = "defeated"
):

	if evocation == null:
		return


	# =====================================================
	# SAVE LOCATION
	#
	# Puppeteer deve usare la Room in cui si trovava
	# l'Evocation al momento della sconfitta/rimozione.
	# =====================================================

	var evocation_room_id: String = (
		evocation.room_id
	)


	# =====================================================
	# CREATE EVENT
	# =====================================================

	var event = GameEvent.new(
		"evocation_defeated_or_removed"
	)


	event.target_model_type = "evocation"

	event.target_player_index = (
		evocation.owner_id
	)

	event.target_evocation = (
		evocation
	)

	event.target_room_id = (
		evocation_room_id
	)


	# =====================================================
	# REASON
	# =====================================================

	event.action_type = event_reason


	print(
		"Evocation defeated/removed event: ",
		evocation.evocation_name,
		" | owner P",
		evocation.owner_id + 1,
		" | room ",
		evocation_room_id,
		" | reason ",
		event_reason
	)


	# =====================================================
	# SPELL TRIGGERS
	# =====================================================

	process_game_event(
		event
	)


	# =====================================================
	# PUPPETEER
	#
	# Whenever an Evocation is defeated or removed,
	# Black Rose places 1 Instability in the Room
	# that Model was in.
	# =====================================================

	if is_event_active(
		"puppeteer"
	):

		place_instability(
			-1,
			evocation_room_id,
			1
		)

func activate_room(
	player_index: int,
	room_id: String,
	allow_reactivate_flipped: bool = false,
	context: Dictionary = {}
) -> bool:

	var room = get_room_by_id(
		room_id
	)

	if room == null:

		print(
			"activate_room: Room not found: ",
			room_id
		)

		return false


	if not room.can_activate(
		allow_reactivate_flipped
	):

		print(
			"activate_room: ",
			room.room_name,
			" already activated this turn"
		)

		return false


	var success = (
		room_effect_resolver.resolve_room(
			self,
			player_index,
			room,
			context
		)
	)


	if not success:

		print(
			"activate_room: effect resolution failed for ",
			room.room_name
		)

		return false


	room.mark_activated()


	print(
		"Player ",
		player_index + 1,
		" activated ",
		room.room_name,
		" [",
		room.get_current_side_name(),
		"]"
	)


	return true
	


func reset_room_activations():

	for child in get_children():

		if not child.has_meta("room_id"):
			continue

		child.reset_activation()


	print(
		"Room activation limits reset"
	)
	
func get_evocation_copies_in_play(
	evocation_id: String
) -> int:

	var count = 0

	for player in players:

		for evocation in player.evocations:

			if evocation == null:
				continue

			if evocation.evocation_id == evocation_id:
				count += 1

	return count
	
func get_available_evocation_copies(
	evocation_id: String
) -> int:

	var data = evocation_database.get_evocation(
		evocation_id
	)

	if data.is_empty():
		return 0


	var total_copies = int(
		data.get(
			"copies",
			0
		)
	)

	var copies_in_play = (
		get_evocation_copies_in_play(
			evocation_id
		)
	)


	return max(
		0,
		total_copies - copies_in_play
	)
	
func get_available_evocations_with_max_health(
	max_health: int
) -> Array:

	var result: Array = []


	for data in (
		evocation_database
		.get_evocations_with_max_health(
			max_health
		)
	):

		var evocation_id = str(
			data.get(
				"id",
				""
			)
		)

		if evocation_id == "":
			continue


		if get_available_evocation_copies(
			evocation_id
		) <= 0:
			continue


		result.append(
			data
		)


	return result


func get_room_by_id(
	room_id: String
):
	for child in get_children():

		if not child.has_meta("room_id"):
			continue

		if str(
			child.get_meta("room_id")
		) == room_id:

			return child

	return null



func resolve_completed_rooms():

	print("")
	print("==============================================")
	print("          RESOLVING COMPLETED ROOMS")
	print("==============================================")

	var completed_count := 0

	for child in get_children():

		if not child.has_meta("room_id"):
			continue

		if child.flipped:
			continue

		if not child.is_instability_complete():
			continue

		if resolve_room_completion(child):
			completed_count += 1

	print(
		"Completed Rooms resolved: ",
		completed_count
	)

	print("==============================================")
	print("")


func resolve_room_completion(
	room
) -> bool:

	if room == null:
		return false

	if room.flipped:
		print(
			"Room completion skipped: ",
			room.room_name,
			" is already rebuilt"
		)
		return false

	if not room.is_instability_complete():
		print(
			"Room completion skipped: ",
			room.room_name,
			" is not full | ",
			room.get_instability_count(),
			"/",
			room.get_instability_resistance()
		)
		return false


	var rewards = room.get_completion_rewards()

	if rewards.size() < 3:
		print(
			"Room completion failed: ",
			room.room_name,
			" has invalid completion rewards"
		)
		return false


	# -----------------------------------------------------
	# CALCULATE REWARDS BEFORE CHANGING ROOM STATE
	# -----------------------------------------------------

	var reward_result = calculate_room_completion_rewards(
		room
	)


	print("")
	print(
		"ROOM COMPLETED: ",
		room.room_name
	)

	print(
		"Instability: ",
		room.get_instability_count(),
		"/",
		room.get_instability_resistance()
	)


	# -----------------------------------------------------
	# APPLY POWER REWARDS
	# -----------------------------------------------------

	for owner_id in reward_result.keys():	

		var power_reward = int(
			reward_result[owner_id]
		)

		if power_reward <= 0:
			continue

		if int(owner_id) == -1:

			add_black_rose_power(
				power_reward
			)

			print(
				"  Black Rose gains ",
				power_reward,
				" Power"
			)

		else:

			add_player_power(
				int(owner_id),
				power_reward
			)

			print(
				"  Player ",
				int(owner_id) + 1,
				" gains ",
				power_reward,
				" Power"
			)


	# -----------------------------------------------------
	# RETURN ALL INSTABILITY CUBES
	# -----------------------------------------------------

	for owner_id in room.instability_cubes.duplicate():

		return_owner_cubes(
			int(owner_id),
			1
		)


	# -----------------------------------------------------
	# CLEAR ROOM
	# -----------------------------------------------------

	room.clear_instability()


	# -----------------------------------------------------
	# REBUILD ROOM
	# -----------------------------------------------------

	room.flipped = true
	room.activated_this_turn = false


	print(
		room.room_name,
		" rebuilt"
	)


	return true


# =========================================================
# ROOM COMPLETION REWARD CALCULATION
# =========================================================

func calculate_room_completion_rewards(
	room
) -> Dictionary:

	var result: Dictionary = {}

	if room == null:
		return result


	var rewards = room.get_completion_rewards()

	if rewards.size() < 3:
		return result


	# -----------------------------------------------------
	# COUNT INSTABILITY BY OWNER
	#
	# owner_id:
	#   -1 = Black Rose
	#    0+ = Player
	# -----------------------------------------------------

	var counts: Dictionary = {}

	for owner_id in room.instability_cubes:

		var id = int(owner_id)

		counts[id] = int(
			counts.get(
				id,
				0
			)
		) + 1


	if counts.is_empty():
		return result


	# -----------------------------------------------------
	# SPECIAL CASE:
	# ONLY ONE OWNER CONTRIBUTED
	#
	# First reward + 1.
	# -----------------------------------------------------

	if counts.size() == 1:

		var only_owner = counts.keys()[0]

		result[only_owner] = (
			int(rewards[0]) + 1
		)

		return result


	# -----------------------------------------------------
	# GROUP OWNERS BY NUMBER OF CUBES
	#
	# Example:
	#
	# P1 = 3
	# P2 = 3
	# P3 = 1
	#
	# becomes:
	#
	# 3 -> [P1, P2]
	# 1 -> [P3]
	# -----------------------------------------------------

	var owners_by_count: Dictionary = {}

	for owner_id in counts.keys():

		var cube_count = int(
			counts[owner_id]
		)

		if not owners_by_count.has(
			cube_count
		):

			owners_by_count[cube_count] = []

		owners_by_count[cube_count].append(
			int(owner_id)
		)


	# -----------------------------------------------------
	# SORT CONTRIBUTION LEVELS DESCENDING
	# -----------------------------------------------------

	var contribution_levels: Array = (
		owners_by_count.keys()
	)

	contribution_levels.sort()

	contribution_levels.reverse()


	# -----------------------------------------------------
	# ASSIGN RANKED REWARDS
	#
	# Ranking uses occupied positions.
	#
	# Example:
	#
	# 3 cubes: P1, P2
	# 1 cube : P3
	#
	# P1/P2 tie for first.
	# P3 is third, not second.
	# -----------------------------------------------------

	var ranking_position := 0

	for contribution in contribution_levels:

		var tied_owners: Array = (
			owners_by_count[contribution]
		)

		var reward_index = min(
			ranking_position,
			2
		)

		var base_reward = int(
			rewards[reward_index]
		)

		var final_reward = base_reward


		# -------------------------------------------------
		# TIE PENALTY
		#
		# A tied reward is reduced by 1,
		# except rewards of 1 or less.
		# -------------------------------------------------

		if tied_owners.size() > 1 \
		and base_reward > 1:

			final_reward -= 1


		for owner_id in tied_owners:

			result[int(owner_id)] = (
				final_reward
			)


		# A tie occupies multiple ranking positions.
		ranking_position += (
			tied_owners.size()
		)


	return result
func create_school_libraries():
	school_libraries.clear()
	school_discards.clear()


	for school_id in active_school_ids:

		var library: Array[SpellCardState] = []

		var school_spells: Array[SpellCardState] = (
			spell_database.get_school_spells(
				school_id
			)
		)


		for spell in school_spells:

			if spell.personal:
				continue

			if spell.forgotten:
				continue


			for i in range(spell.copies):

				library.append(
					spell
				)


		shuffle_with_rng(
			library
		)


		school_libraries[school_id] = library
		school_discards[school_id] = []


	print("")
	print("SCHOOL LIBRARIES:")

	for school_id in active_school_ids:

		print(
			"  ",
			school_id,
			": ",
			school_libraries[school_id].size(),
			" cards"
		)
		
func select_active_schools():
	active_school_ids.clear()

	var available_school_ids: Array[String] = []


	# Recuperiamo automaticamente tutte le scuole
	# presenti nello SpellDatabase.
	for spell in spell_database.spells.values():

		if spell == null:
			continue

		var school_id: String = str(
			spell.school_id
		)

		if school_id.is_empty():
			continue

		if school_id in available_school_ids:
			continue

		available_school_ids.append(
			school_id
		)


	# Usiamo lo stesso RNG deterministico della partita.
	shuffle_with_rng(
		available_school_ids
	)


	var amount_to_select: int = min(
		ACTIVE_SCHOOL_COUNT,
		available_school_ids.size()
	)


	for i in range(amount_to_select):

		active_school_ids.append(
			available_school_ids[i]
		)


	print("")
	print("ACTIVE SCHOOLS:")

	for school_id in active_school_ids:
		print(
			"  - ",
			school_id
		)

	print(
		"Selected ",
		active_school_ids.size(),
		" / ",
		available_school_ids.size(),
		" available schools"
	)

func is_school_active(
	school_id: String
) -> bool:

	return school_id in active_school_ids


func get_school_library(
	school_id: String
) -> Array:

	if not school_libraries.has(
		school_id
	):
		return []

	return school_libraries[
		school_id
	]


func get_school_discard(
	school_id: String
) -> Array:

	if not school_discards.has(
		school_id
	):
		return []

	return school_discards[
		school_id
	]


func draw_from_school_library(
	school_id: String
) -> SpellCardState:

	if not is_school_active(
		school_id
	):
		print(
			"draw_from_school_library: inactive school ",
			school_id
		)

		return null


	var library: Array = school_libraries[
		school_id
	]


	if library.is_empty():

		reshuffle_school_library(
			school_id
		)


	if library.is_empty():

		print(
			"draw_from_school_library: no cards available in ",
			school_id
		)

		return null


	var spell: SpellCardState = library.pop_back()


	return spell


func discard_to_school(
	school_id: String,
	spell: SpellCardState
) -> bool:

	if spell == null:
		return false


	if not school_discards.has(
		school_id
	):
		return false


	school_discards[
		school_id
	].append(
		spell
	)


	return true


func reshuffle_school_library(
	school_id: String
) -> bool:

	if not school_libraries.has(
		school_id
	):
		return false


	if not school_discards.has(
		school_id
	):
		return false


	var library: Array = school_libraries[
		school_id
	]

	var discard: Array = school_discards[
		school_id
	]


	if discard.is_empty():
		return false


	library.append_array(
		discard
	)

	discard.clear()


	shuffle_with_rng(
		library
	)


	print(
		"School Library reshuffled: ",
		school_id,
		" | ",
		library.size(),
		" cards"
	)


	return true

func add_spell_to_player_grimoire(
	player_index: int,
	spell: SpellCardState
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	if spell == null:
		return false


	players[player_index].add_spell_to_grimoire(
		spell
	)


	print(
		"Player ",
		player_index + 1,
		" added ",
		spell.card_name,
		" to Grimoire"
	)


	return true

func draw_player_spell(
	player_index: int
) -> SpellCardState:

	if player_index < 0 \
	or player_index >= players.size():

		return null


	var player = players[
		player_index
	]


	if player.grimoire.is_empty():

		if player.memories.is_empty():

			print(
				"draw_player_spell: Player ",
				player_index + 1,
				" has no cards to draw"
			)

			return null


		player.grimoire.append_array(
			player.memories
		)

		player.memories.clear()


		shuffle_with_rng(
			player.grimoire
		)


		print(
			"Player ",
			player_index + 1,
			" shuffled Memories into Grimoire"
		)


	var spell: SpellCardState = (
		player.draw_from_grimoire()
	)


	if spell != null:

		print(
			"Player ",
			player_index + 1,
			" drew ",
			spell.card_name
		)


	return spell
	
func discard_player_spell(
	player_index: int,
	spell: SpellCardState
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	if spell == null:
		return false


	var success = (
		players[player_index]
		.discard_spell_from_hand(
			spell
		)
	)


	if success:

		print(
			"Player ",
			player_index + 1,
			" discarded ",
			spell.card_name,
			" to Memories"
		)


	return success
	
func discard_player_spell_by_id(
	player_index: int,
	spell_id: String
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var spell = (
		players[player_index]
		.get_spell_from_hand(
			spell_id
		)
	)


	if spell == null:

		print(
			"discard_player_spell_by_id: ",
			spell_id,
			" not found in Player ",
			player_index + 1,
			" hand"
		)

		return false


	return discard_player_spell(
		player_index,
		spell
	)
	
func draw_random_memory(
	player_index: int
) -> SpellCardState:

	if player_index < 0 \
	or player_index >= players.size():

		return null


	var player = players[
		player_index
	]


	if player.memories.is_empty():

		print(
			"draw_random_memory: Player ",
			player_index + 1,
			" has no Memories"
		)

		return null


	var index: int = rng.randi_range(
		0,
		player.memories.size() - 1
	)


	var spell: SpellCardState = (
		player.memories[index]
	)


	player.memories.remove_at(
		index
	)


	player.hand.append(
		spell
	)


	print(
		"Player ",
		player_index + 1,
		" recovered ",
		spell.card_name,
		" from Memories"
	)


	return spell
func discard_player_spells_by_id(
	player_index: int,
	spell_ids: Array
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	# Prima verifichiamo che TUTTE le carte richieste
	# siano realmente presenti nella mano.
	#
	# Usiamo una copia perché possono esserci
	# più copie della stessa Spell.
	var available_hand: Array = (
		player.hand.duplicate()
	)


	for spell_id_value in spell_ids:

		var spell_id: String = str(
			spell_id_value
		)

		var found_index := -1


		for i in range(
			available_hand.size()
		):

			if available_hand[i].id == spell_id:
				found_index = i
				break


		if found_index == -1:

			print(
				"discard_player_spells_by_id: ",
				spell_id,
				" not available in Player ",
				player_index + 1,
				" hand"
			)

			return false


		available_hand.remove_at(
			found_index
		)


	# Tutta la selezione è valida.
	# Ora possiamo realmente scartare le carte.
	for spell_id_value in spell_ids:

		var spell_id: String = str(
			spell_id_value
		)

		var spell = player.get_spell_from_hand(
			spell_id
		)


		if spell == null:
			return false


		var success = discard_player_spell(
			player_index,
			spell
		)


		if not success:
			return false


	return true

func create_forgotten_deck():
	forgotten_deck.clear()
	forgotten_discard.clear()

	for spell in spell_database.spells.values():

		if not spell.forgotten:
			continue

		for i in range(spell.copies):
			forgotten_deck.append(
				spell
			)

	shuffle_with_rng(
		forgotten_deck
	)

	print(
		"Forgotten deck created: ",
		forgotten_deck.size(),
		" cards"
	)
func get_summon_spells_from_grimoire(
	player_index: int
) -> Array[SpellCardState]:

	var result: Array[SpellCardState] = []


	if player_index < 0 \
	or player_index >= players.size():

		return result


	for spell in players[
		player_index
	].grimoire:

		if spell == null:
			continue


		if spell.has_summon_effect():

			result.append(
				spell
			)


	return result
func draw_specific_spell_from_grimoire(
	player_index: int,
	spell_id: String
) -> SpellCardState:

	if player_index < 0 \
	or player_index >= players.size():

		return null


	var player = players[
		player_index
	]


	for i in range(
		player.grimoire.size()
	):

		var spell: SpellCardState = (
			player.grimoire[i]
		)


		if spell.id != spell_id:
			continue


		player.grimoire.remove_at(
			i
		)

		player.hand.append(
			spell
		)


		print(
			"Player ",
			player_index + 1,
			" searched and drew ",
			spell.card_name,
			" from Grimoire"
		)


		return spell


	print(
		"draw_specific_spell_from_grimoire: ",
		spell_id,
		" not found"
	)


	return null
func shuffle_player_grimoire(
	player_index: int
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	shuffle_with_rng(
		players[player_index].grimoire
	)


	print(
		"Player ",
		player_index + 1,
		" shuffled Grimoire"
	)


	return true
func search_personal_spell(
	player_index: int,
	spell_id: String,
	source: String
) -> SpellCardState:

	if player_index < 0 \
	or player_index >= players.size():

		return null


	var player = players[
		player_index
	]


	match source:

		"grimoire":

			for i in range(
				player.grimoire.size()
			):

				var spell: SpellCardState = (
					player.grimoire[i]
				)


				if spell.id != spell_id:
					continue


				player.grimoire.remove_at(
					i
				)

				player.hand.append(
					spell
				)


				print(
					"Player ",
					player_index + 1,
					" searched ",
					spell.card_name,
					" from Grimoire"
				)


				return spell


		"memories":

			for i in range(
				player.memories.size()
			):

				var spell: SpellCardState = (
					player.memories[i]
				)


				if spell.id != spell_id:
					continue


				player.memories.remove_at(
					i
				)

				player.hand.append(
					spell
				)


				print(
					"Player ",
					player_index + 1,
					" searched ",
					spell.card_name,
					" from Memories"
				)


				return spell


		_:

			print(
				"search_personal_spell: invalid source ",
				source
			)


	return null
	
func shuffle_memories_into_grimoire(
	player_index: int
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	for spell in player.memories:

		player.grimoire.append(
			spell
		)


	player.memories.clear()


	shuffle_with_rng(
		player.grimoire
	)


	print(
		"Player ",
		player_index + 1,
		" shuffled Memories into Grimoire"
	)


	return true

func replace_revealed_spell_from_hand(
	player_index: int,
	revealed_spell_id: String,
	hand_spell_id: String
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	# =====================================================
	# FIND REVEALED SPELL
	# =====================================================

	var revealed_index: int = -1
	var revealed_state = null


	for i in range(
		player.revealed_spells.size()
	):

		var current = (
			player.revealed_spells[i]
		)


		if current.spell.id == revealed_spell_id:

			revealed_index = i
			revealed_state = current
			break


	if revealed_index < 0:

		print(
			"replace_revealed_spell_from_hand: "
			+ "revealed Spell not found: ",
			revealed_spell_id
		)

		return false


	# =====================================================
	# FIND SPELL IN HAND
	# =====================================================

	var hand_index: int = -1
	var replacement_spell: SpellCardState = null


	for i in range(
		player.hand.size()
	):

		var current_spell: SpellCardState = (
			player.hand[i]
		)


		if current_spell.id == hand_spell_id:

			hand_index = i
			replacement_spell = current_spell
			break


	if hand_index < 0:

		print(
			"replace_revealed_spell_from_hand: "
			+ "replacement Spell not found in Hand: ",
			hand_spell_id
		)

		return false


	# =====================================================
	# PRESERVE ACTIVE SIDE
	# =====================================================

	var use_dark_side: bool = (
		revealed_state.use_dark_side
	)


	# =====================================================
	# OLD REVEALED SPELL -> HAND
	# =====================================================

	player.hand.append(
		revealed_state.spell
	)


	# =====================================================
	# NEW SPELL LEAVES HAND
	# =====================================================

	player.hand.remove_at(
		hand_index
	)


	# =====================================================
	# REPLACE REVEALED STATE
	# =====================================================

	var new_revealed = RevealedSpellState.new(
		replacement_spell,
		use_dark_side
	)


	player.revealed_spells[
		revealed_index
	] = new_revealed


	print(
		"Player ",
		player_index + 1,
		" replaced revealed ",
		revealed_state.spell.card_name,
		" with ",
		replacement_spell.card_name
	)


	return true

func cast_next_ready_spell(
	player_index: int,
	context: Dictionary = {}
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	var ready_spell: ReadySpellState = (
		player.get_next_ready_spell()
	)


	if ready_spell == null:

		print(
			"cast_next_ready_spell: Player ",
			player_index + 1,
			" has no Ready Spell"
		)

		return false


	# =====================================================
	# CAST FIRST
	#
	# Do not remove the card until the casting operation
	# has succeeded.
	# =====================================================

	if not cast_ready_spell_state(
		player_index,
		ready_spell,
		context
	):

		return false


	# =====================================================
	# REMOVE FROM READY SLOT
	# =====================================================

	player.remove_next_ready_spell()


	return true

func heal_evocation_damage(
	evocation: EvocationState,
	owner_id: int,
	amount: int
) -> int:

	if evocation == null:
		return 0

	if amount <= 0:
		return 0


	var removed: int = 0


	while removed < amount:

		var cube_index: int = (
			evocation.damage_cubes.find(
				owner_id
			)
		)


		if cube_index == -1:
			break


		evocation.damage_cubes.remove_at(
			cube_index
		)


		return_owner_cubes(
			owner_id,
			1
		)


		removed += 1


	return removed
	
func return_all_mages_to_cells() -> bool:

	for player_index in range(
		players.size()
	):

		var mage = players[
			player_index
		].mage


		if mage == null:
			continue


		if not place_mage_in_cell(
			player_index
		):

			return false


	return true
	
func take_crown(
	player_index: int
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		print(
			"take_crown: invalid player ",
			player_index
		)

		return false


	if crown_owner_id == player_index:

		print(
			"Player ",
			player_index + 1,
			" already has the Crown"
		)

		return true


	var previous_owner: int = crown_owner_id

	crown_owner_id = player_index


	if previous_owner >= 0:

		print(
			"Player ",
			previous_owner + 1,
			" loses the Crown"
		)


	print(
		"Player ",
		player_index + 1,
		" takes the Crown"
	)


	return true

func activate_evocation(
	evocation: EvocationState,
	controller_id: int,
	context: Dictionary = {},
	strength_bonus: int = 0
) -> bool:

	if evocation == null:
		return false

	if evocation.is_defeated():

		print(
			"activate_evocation: Evocation is defeated"
		)

		return false

	if controller_id < 0 \
	or controller_id >= players.size():

		print(
			"activate_evocation: invalid controller ",
			controller_id
		)

		return false


	# =====================================================
	# ACTIVATION VALUES
	# =====================================================

	var activation_strength: int = (
		evocation.strength
		+ strength_bonus
	)

	var speed: int = evocation.speed


	# =====================================================
	# CONTEXT
	#
	# evocation_attack_timing:
	#   "before"
	#   "after"
	#   "none"
	#
	# evocation_move_room_ids:
	#   percorso dell'Evocation.
	#   Ogni elemento = UN Move 1.
	#
	# evocation_target_player_index:
	#   Mage bersaglio dell'Attack.
	# =====================================================

	var attack_timing: String = str(
		context.get(
			"evocation_attack_timing",
			"none"
		)
	)


	var move_room_ids: Array = (
		context.get(
			"evocation_move_room_ids",
			[]
		)
	)


	var target_player_index: int = int(
		context.get(
			"evocation_target_player_index",
			-1
		)
	)


	# =====================================================
	# VALIDATE ATTACK TIMING
	# =====================================================

	if attack_timing != "before" \
	and attack_timing != "after" \
	and attack_timing != "none":

		print(
			"activate_evocation: invalid attack timing: ",
			attack_timing
		)

		return false


	# =====================================================
	# VALIDATE MOVEMENT COUNT
	#
	# Speed N = maximum N consecutive Move 1 effects.
	# =====================================================

	if move_room_ids.size() > speed:

		print(
			"activate_evocation: too many Move effects | ",
			move_room_ids.size(),
			" > Speed ",
			speed
		)

		return false


	# =====================================================
	# ATTACK BEFORE MOVEMENT
	# =====================================================

	if attack_timing == "before":

		if target_player_index < 0 \
		or target_player_index >= players.size():

			print(
				"activate_evocation: attack target missing"
			)

			return false


		var target_mage = players[
			target_player_index
		].mage


		if target_mage.in_cell:

			print(
				"activate_evocation: target Mage is in Cell"
			)

			return false


		if target_mage.room_id != evocation.room_id:

			print(
				"activate_evocation: target Mage is not in Evocation Room"
			)

			return false


		deal_damage_from_evocation(
			evocation,
			target_player_index,
			activation_strength
		)


	# =====================================================
	# MOVEMENT
	#
	# Ogni elemento dell'Array è UN Move 1.
	# Devono essere consecutivi.
	# =====================================================

	for room_id_value in move_room_ids:

		var room_id: String = str(
			room_id_value
		)


		if not move_evocation_to_room_id(
			evocation,
			room_id,
			1
		):

			print(
				"activate_evocation: movement failed"
			)

			return false


	# =====================================================
	# ATTACK AFTER MOVEMENT
	# =====================================================

	if attack_timing == "after":

		if target_player_index < 0 \
		or target_player_index >= players.size():

			print(
				"activate_evocation: attack target missing"
			)

			return false


		var target_mage = players[
			target_player_index
		].mage


		if target_mage.in_cell:

			print(
				"activate_evocation: target Mage is in Cell"
			)

			return false


		if target_mage.room_id != evocation.room_id:

			print(
				"activate_evocation: target Mage is not in Evocation Room"
			)

			return false


		deal_damage_from_evocation(
			evocation,
			target_player_index,
			activation_strength
		)


	# =====================================================
	# STORE RESULT
	# =====================================================

	context[
		"last_activated_evocation"
	] = evocation

	context[
		"last_evocation_activation_controller"
	] = controller_id

	context[
		"last_evocation_activation_strength"
	] = activation_strength

	context[
		"last_evocation_activation_strength_bonus"
	] = strength_bonus


	print(
		"Evocation activated: ",
		evocation.evocation_name,
		" | controller P",
		controller_id + 1,
		" | Moves ",
		move_room_ids.size(),
		"/",
		speed,
		" | attack ",
		attack_timing,
		" | Strength ",
		activation_strength
	)


	return true
	
func create_event_decks():

	event_discard.clear()

	active_events = [
		null,
		null,
		null
	]


	for moon in [
		1,
		2,
		3
	]:

		var deck: Array[EventCardState] = (
			event_database.get_events_for_moon(
				moon
			)
		)


		shuffle_with_rng(
			deck
		)


		event_decks[moon] = deck


		print(
			"Event Deck Moon ",
			moon,
			": ",
			deck.size()
		)
		
func shift_active_events():

	print("Shifting active Events")


	# =====================================================
	# SLOT 3 -> DISCARD
	# =====================================================

	var leaving_event = (
		active_events[2]
	)


	if leaving_event != null:

		print(
			"Event leaving Slot 3: ",
			leaving_event.event_name
		)


		# Normale uscita dall'Event Board:
		# concede il discard Power.

		discard_event(
			leaving_event,
			true
		)


	# =====================================================
	# SHIFT
	# =====================================================

	active_events[2] = (
		active_events[1]
	)

	active_events[1] = (
		active_events[0]
	)

	active_events[0] = null


	# =====================================================
	# UI
	# =====================================================

	$EventBoard.refresh_event_slots()
	
func discard_event(
	event: EventCardState,
	gain_discard_power: bool = false
):

	if event == null:
		return


	event_discard.append(
		event
	)


	print(
		"Event discarded: ",
		event.event_name
	)


	# =====================================================
	# DISCARD POWER
	#
	# Si applica quando la carta lascia normalmente
	# l'Event Board.
	#
	# Gli Instant gestiscono separatamente i due valori
	# in draw_event().
	# =====================================================

	if gain_discard_power \
	and event.discard_power > 0:

		print(
			"Black Rose gains ",
			event.discard_power,
			" Power from Event discard"
		)


		add_black_rose_power(
			event.discard_power
		)


	$EventBoard.refresh_event_slots()
	
func place_event_on_board(
	event: EventCardState
) -> bool:

	if event == null:
		return false


	if event.slot < 1 \
	or event.slot > 3:

		print(
			"place_event_on_board: invalid slot ",
			event.slot,
			" for ",
			event.event_name
		)

		return false


	var index: int = (
		event.slot - 1
	)


	var displaced: EventCardState = (
		event
	)


	while displaced != null:


		# =================================================
		# PUSHED OUT OF SLOT 3
		# =================================================

		if index >= 3:

			print(
				"Event pushed out of board: ",
				displaced.event_name
			)


			discard_event(
				displaced,
				true
			)


			break


		# =================================================
		# SAVE CURRENT EVENT
		# =================================================

		var next_event = (
			active_events[index]
		)


		# =================================================
		# PLACE EVENT
		# =================================================

		active_events[index] = (
			displaced
		)


		print(
			displaced.event_name,
			" placed in Event Slot ",
			index + 1
		)


		# =================================================
		# PUSH OLD EVENT RIGHT
		# =================================================

		displaced = (
			next_event
		)

		index += 1


	# =====================================================
	# UI
	# =====================================================

	$EventBoard.refresh_event_slots()


	return true
	
func draw_event(
	drawing_player_index: int,
	context: Dictionary = {}
) -> EventCardState:

	if drawing_player_index < 0 \
	or drawing_player_index >= players.size():

		return null


	var moon: int = (
		current_moon
	)


	if not event_decks.has(
		moon
	):

		return null


	var deck: Array = (
		event_decks[moon]
	)


	if deck.is_empty():

		print(
			"Event Deck Moon ",
			moon,
			" is empty"
		)

		return null


	# =====================================================
	# DRAW
	# =====================================================

	var event: EventCardState = (
		deck.pop_back()
	)


	print(
		"EVENT DRAWN: ",
		event.event_name,
		" | Moon ",
		moon
	)


	# =====================================================
	# REVEAL POWER
	# =====================================================

	if event.reveal_power > 0:

		print(
			"Black Rose gains ",
			event.reveal_power,
			" Power from Event reveal"
		)


		add_black_rose_power(
			event.reveal_power
		)


	# =====================================================
	# CROWN
	# =====================================================

	if event.crown:

		take_crown(
			drawing_player_index
		)


	# =====================================================
	# INSTANT EVENT
	#
	# - resolves immediately
	# - never enters an Event slot
	# - never pushes another Event
	# - BR receives both Power values
	# - then Event is discarded
	# =====================================================

	if event.is_instant():

		print(
			"Resolving Instant Event: ",
			event.event_name
		)


		var event_context: Dictionary = (
			context.duplicate()
		)


		event_context["game"] = self
		event_context["event"] = event

		event_context[
			"drawing_player_index"
		] = drawing_player_index


		if not resolve_event(
			event,
			event_context
		):

			print(
				"Instant Event failed: ",
				event.event_name
			)

			return null


		if event.discard_power > 0:

			print(
				"Black Rose gains ",
				event.discard_power,
				" additional Power from Instant Event"
			)


			add_black_rose_power(
				event.discard_power
			)


		# Non usare gain_discard_power=true:
		# lo abbiamo appena assegnato esplicitamente.

		discard_event(
			event,
			false
		)


		return event


	# =====================================================
	# NORMAL EVENT
	# =====================================================

	if not place_event_on_board(
		event
	):

		return null


	return event
	
func resolve_events_for_phase(
	phase: String,
	context: Dictionary = {}
) -> bool:

	for event in active_events:

		if event == null:
			continue


		# -------------------------------------------------
		# Solo gli Event appartenenti esplicitamente
		# alla fase richiesta vengono risolti.
		#
		# "always" e trigger come Puppeteer NON passano qui.
		# -------------------------------------------------

		if event.phase != phase:
			continue


		print(
			"Resolving Event from board: ",
			event.event_name
		)


		var event_context: Dictionary = (
			context.duplicate()
		)


		event_context["event"] = event
		event_context["game"] = self


		if not resolve_event(
			event,
			event_context
		):

			print(
				"Failed to resolve Event: ",
				event.event_name
			)

			return false


	return true
	
func resolve_event(
	event: EventCardState,
	context: Dictionary = {}
) -> bool:

	if event == null:
		return false


	var event_context: Dictionary = (
		context.duplicate()
	)


	event_context["game"] = self
	event_context["event"] = event


	return event_effect_resolver.resolve_event(
		event,
		event_context
	)

func get_active_event_by_id(
	event_id: String
) -> EventCardState:

	for event in active_events:

		if event == null:
			continue

		if event.id == event_id:
			return event

	return null


func is_event_active(
	event_id: String
) -> bool:

	return get_active_event_by_id(
		event_id
	) != null
	
func place_mage_in_cell(
	player_index: int
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var mage = players[
		player_index
	].mage


	if mage == null:
		return false


	# =====================================================
	# PLACE IN CELL
	#
	# room_id e room_coord NON vengono cancellati.
	# Nel nostro modello rappresentano l'Entrance Room
	# associata alla Cell e servono per il successivo
	# ingresso nella Lodge.
	# =====================================================

	mage.in_cell = true


	print(
		"Player ",
		player_index + 1,
		" Mage placed in Cell"
	)


	# =====================================================
	# HIDDEN RESOURCES
	#
	# Quando un Mage viene placed nella propria Cell,
	# quel Mage guadagna 1 Power.
	# =====================================================

	if is_event_active(
		"hidden_resources"
	):

		add_player_power(
			player_index,
			1
		)


		print(
			"Hidden Resources: Player ",
			player_index + 1,
			" gains 1 Power"
		)


	return true
func place_instability(
	owner_id: int,
	room_id: String,
	amount: int = 1
) -> int:

	if amount <= 0:
		return 0


	var room = get_room_by_id(
		room_id
	)


	if room == null:

		print(
			"place_instability: Room not found: ",
			room_id
		)

		return 0


	if room.flipped:
		return 0


	var available_slots: int = (
		room.get_instability_resistance()
		- room.get_instability_count()
	)


	if available_slots <= 0:
		return 0


	var requested: int = min(
		amount,
		available_slots
	)


	var taken: int = take_owner_cubes(
		owner_id,
		requested
	)


	var placed: int = 0


	for i in range(taken):

		if not room.add_instability_cube(
			owner_id
		):

			# Se per qualsiasi motivo il cubo non entra,
			# restituiamolo immediatamente.
			return_owner_cubes(
				owner_id,
				1
			)

			continue


		placed += 1


	print(
		"Owner ",
		owner_id,
		" placed ",
		placed,
		" Instability in ",
		room.room_name
	)


	# =====================================================
	# BLACK OVERLOAD
	#
	# Parte UNA volta se un Mage ha effettivamente
	# piazzato almeno 1 Instability.
	# =====================================================

	if placed > 0 \
	and owner_id >= 0 \
	and is_event_active(
		"black_overload"
	):

		# La Room potrebbe essersi riempita con
		# l'Instability appena piazzata.

		if room.has_free_instability_slot():

			var black_rose_cube: int = (
				take_owner_cubes(
					-1,
					1
				)
			)


			if black_rose_cube > 0:

				if room.add_instability_cube(
					-1
				):

					print(
						"Black Overload: Black Rose places 1 Instability in ",
						room.room_name
					)

				else:

					return_owner_cubes(
						-1,
						black_rose_cube
					)


	return placed
func resolve_black_rose_phase(
	context: Dictionary = {}
) -> bool:

	if players.is_empty():
		return false


	if crown_owner_id < 0 \
	or crown_owner_id >= players.size():

		print(
			"Black Rose Phase: no valid Crown owner"
		)

		return false


	# =====================================================
	# START PHASE
	# =====================================================

	if not start_phase(
		PHASE_BLACK_ROSE
	):
		return false


	print("")
	print("==============================================")
	print("             BLACK ROSE PHASE")
	print("==============================================")


	# =====================================================
	# SNAPSHOT PLAY ORDER
	#
	# IMPORTANT:
	# questo Array rimane invariato per TUTTA la Phase.
	#
	# Se un Event cambia il possessore della Crown,
	# il nuovo First Mage avrà effetto solamente
	# dalla Phase successiva.
	# =====================================================

	var play_order: Array[int] = (
		get_play_order()
	)


	if play_order.is_empty():

		print(
			"Black Rose Phase: invalid play order"
		)

		return false


	var first_mage_index: int = (
		play_order[0]
	)


	print(
		"Round ",
		current_round,
		" | First Mage: Player ",
		first_mage_index + 1
	)


	# =====================================================
	# EVENT DRAWER
	#
	# Il Mage alla DESTRA del First Mage pesca l'Event.
	#
	# Usiamo first_mage_index dello snapshot,
	# NON crown_owner_id dopo l'inizio della Phase.
	# =====================================================

	var drawing_player_index: int = (
		first_mage_index
		- 1
		+ players.size()
	) % players.size()


	print(
		"Player ",
		drawing_player_index + 1,
		" draws the Event"
	)


	# =====================================================
	# EVENT CONTEXT
	# =====================================================

	var event_context: Dictionary = (
		context.duplicate()
	)


	event_context["game"] = self

	event_context[
		"drawing_player_index"
	] = drawing_player_index

	event_context[
		"play_order"
	] = play_order


	# =====================================================
	# 1. SHIFT ACTIVE EVENTS
	# =====================================================

	print("")
	print("--- SHIFT EVENTS ---")


	shift_active_events()


	# =====================================================
	# 2. DRAW CURRENT MOON EVENT
	#
	# ATTENZIONE:
	# draw_event() può cambiare crown_owner_id.
	#
	# Non importa per questa Phase:
	# play_order è già stato salvato sopra.
	# =====================================================

	print("")
	print("--- DRAW EVENT ---")


	var drawn_event: EventCardState = (
		draw_event(
			drawing_player_index,
			event_context
		)
	)


	if drawn_event == null:

		print(
			"Black Rose Phase: Event draw failed"
		)

		return false


	# =====================================================
	# 3. RESOLVE BLACK ROSE PHASE EVENTS
	#
	# active_events:
	#
	# [0] = Slot 1
	# [1] = Slot 2
	# [2] = Slot 3
	#
	# Gli Instant sono già stati risolti
	# direttamente da draw_event().
	#
	# event_context contiene il play_order originale
	# della Phase.
	# =====================================================

	print("")
	print("--- RESOLVE BLACK ROSE EVENTS ---")


	if not resolve_events_for_phase(
		PHASE_BLACK_ROSE,
		event_context
	):

		print(
			"Black Rose Phase: Event resolution failed"
		)

		return false


	print("")
	print("==============================================")
	print("          BLACK ROSE PHASE COMPLETE")
	print("==============================================")
	print("")


	return true

func start_phase(
	phase: String
) -> bool:

	if crown_owner_id < 0 \
	or crown_owner_id >= players.size():

		print(
			"start_phase: no valid Crown owner"
		)

		return false


	current_phase = phase


	print(
		"Phase started: ",
		current_phase,
		" | First Mage: Player ",
		crown_owner_id + 1
	)


	return true


func get_play_order() -> Array[int]:

	var order: Array[int] = []


	if players.is_empty():
		return order


	if crown_owner_id < 0 \
	or crown_owner_id >= players.size():

		print(
			"get_play_order: no valid Crown owner"
		)

		return order


	for offset in range(
		players.size()
	):

		var player_index: int = (
			crown_owner_id
			+ offset
		) % players.size()


		order.append(
			player_index
		)


	return order


func get_player_right_of_first_mage() -> int:

	if players.is_empty():
		return -1


	if crown_owner_id < 0 \
	or crown_owner_id >= players.size():

		print(
			"get_player_right_of_first_mage: no valid Crown owner"
		)

		return -1


	return (
		crown_owner_id
		- 1
		+ players.size()
	) % players.size()


func finish_round():

	print("")
	print(
		"ROUND ",
		current_round,
		" COMPLETE"
	)


	current_round += 1
	current_phase = ""


	print(
		"Starting Round ",
		current_round,
		" | Crown owner: Player ",
		crown_owner_id + 1
	)

func assign_initial_crown() -> bool:

	if players.is_empty():

		print(
			"assign_initial_crown: no players"
		)

		return false


	var player_index: int = rng.randi_range(
		0,
		players.size() - 1
	)


	print(
		"Initial Crown assigned to Player ",
		player_index + 1
	)


	return take_crown(
		player_index
	)
func discard_library_spell(
	spell: SpellCardState
) -> bool:

	if spell == null:
		return false


	var school_id: String = str(
		spell.school_id
	)


	if not school_discards.has(
		school_id
	):

		print(
			"discard_library_spell: invalid school ",
			school_id
		)

		return false


	school_discards[
		school_id
	].append(
		spell
	)


	return true


func discard_hand_spell_to_library(
	player_index: int,
	hand_index: int
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	if hand_index < 0 \
	or hand_index >= player.hand.size():

		return false


	var spell: SpellCardState = (
		player.hand[
			hand_index
		]
	)


	if spell == null:
		return false


	# Personal e Forgotten non appartengono
	# alla Library.

	if spell.personal \
	or spell.forgotten:

		print(
			"Cannot discard ",
			spell.id,
			" to Library"
		)

		return false


	if not school_discards.has(
		spell.school_id
	):

		return false


	player.hand.remove_at(
		hand_index
	)


	school_discards[
		spell.school_id
	].append(
		spell
	)


	print(
		"Player ",
		player_index + 1,
		" discards ",
		spell.id,
		" to ",
		spell.school_id,
		" Library discard"
	)


	return true
func resolve_study_library_draw(
	player_index: int,
	school_choices: Array,
	keep_indices: Array
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	# Devono essere pescate esattamente 4 carte.

	if school_choices.size() != 4:

		print(
			"Study Phase: Player ",
			player_index + 1,
			" must choose 4 Library draws"
		)

		return false


	# Di quelle 4 ne deve tenere esattamente 2.

	if keep_indices.size() != 2:

		print(
			"Study Phase: Player ",
			player_index + 1,
			" must keep exactly 2 Library cards"
		)

		return false


	var drawn_cards: Array[SpellCardState] = []


	# =====================================================
	# DRAW 4
	# =====================================================

	for school_value in school_choices:

		var school_id: String = str(
			school_value
		)


		if not active_school_ids.has(
			school_id
		):

			print(
				"Study Phase: inactive School ",
				school_id
			)

			return false


		var spell: SpellCardState = (
			draw_from_school_library(
				school_id
			)
		)


		if spell == null:

			print(
				"Study Phase: cannot draw from ",
				school_id
			)

			return false


		drawn_cards.append(
			spell
		)


	# =====================================================
	# VALIDATE KEEP INDICES
	# =====================================================

	var keep_a: int = int(
		keep_indices[0]
	)

	var keep_b: int = int(
		keep_indices[1]
	)


	if keep_a < 0 \
	or keep_a >= 4 \
	or keep_b < 0 \
	or keep_b >= 4 \
	or keep_a == keep_b:

		print(
			"Study Phase: invalid Library keep indices"
		)

		return false


	# =====================================================
	# KEEP 2 / DISCARD 2
	# =====================================================

	for i in range(
		drawn_cards.size()
	):

		var spell: SpellCardState = (
			drawn_cards[i]
		)


		if i == keep_a \
		or i == keep_b:

			players[
				player_index
			].hand.append(
				spell
			)

			print(
				"Player ",
				player_index + 1,
				" keeps Library Spell ",
				spell.id
			)

			continue


		discard_library_spell(
			spell
		)


		print(
			"Player ",
			player_index + 1,
			" discards Library Spell ",
			spell.id
		)


	return true
func resolve_study_phase(
	context: Dictionary = {}
) -> bool:

	if waiting_for_player_input:

		print(
			"Study Phase: game is already waiting for player input"
		)

		return false


	if not start_phase(
		PHASE_STUDY
	):

		return false


	print("")
	print("==============================================")
	print("                 STUDY PHASE")
	print("==============================================")


	# =====================================================
	# SNAPSHOT PLAY ORDER
	# =====================================================

	current_phase_play_order = (
		get_play_order()
	)


	if current_phase_play_order.is_empty():

		print(
			"Study Phase: invalid play order"
		)

		return false


	var phase_context: Dictionary = (
		context.duplicate(true)
	)


	phase_context["game"] = self

	phase_context[
		"play_order"
	] = current_phase_play_order.duplicate()


	# =====================================================
	# 1. STUDY EVENT EFFECTS
	# =====================================================

	if not resolve_events_for_phase(
		PHASE_STUDY,
		phase_context
	):

		print(
			"Study Phase: Event resolution failed"
		)

		return false


	# =====================================================
	# 2. EVERY MAGE DRAWS 2 FROM PERSONAL GRIMOIRE
	# =====================================================

	for player_index in current_phase_play_order:

		for i in range(2):

			var spell: SpellCardState = (
				draw_player_spell(
					player_index
				)
			)


			if spell == null:

				print(
					"Study Phase: Player ",
					player_index + 1,
					" could not draw from Grimoire"
				)

				break


	# =====================================================
	# 3. START INTERACTIVE STUDY
	# =====================================================

	study_phase_cursor = 0
	study_drawn_cards.clear()


	return advance_study_phase()

func resolve_hand_limit(
	player_index: int,
	discard_indices: Array
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	var excess: int = (
		player.hand.size()
		- player.get_hand_limit()
	)


	# Nessuna carta da scartare.

	if excess <= 0:
		return true


	if discard_indices.size() != excess:

		print(
			"Hand Limit: Player ",
			player_index + 1,
			" must discard ",
			excess,
			" Spell(s)"
		)

		return false


	# =====================================================
	# VALIDATE INDICES
	# =====================================================

	var validated_indices: Array[int] = []


	for value in discard_indices:

		var index: int = int(
			value
		)


		if index < 0 \
		or index >= player.hand.size():

			print(
				"Hand Limit: invalid hand index ",
				index
			)

			return false


		if validated_indices.has(
			index
		):

			print(
				"Hand Limit: duplicate hand index ",
				index
			)

			return false


		validated_indices.append(
			index
		)


	# =====================================================
	# REMOVE FROM HIGHEST INDEX TO LOWEST
	#
	# In questo modo remove_at() non modifica gli indici
	# delle carte che dobbiamo ancora rimuovere.
	# =====================================================

	validated_indices.sort()

	validated_indices.reverse()


	for index in validated_indices:

		var spell: SpellCardState = (
			player.hand[
				index
			]
		)


		player.hand.remove_at(
			index
		)


		player.memories.append(
			spell
		)


		print(
			"Player ",
			player_index + 1,
			" discards ",
			spell.id,
			" to Memories due to Hand Limit"
		)


	return true
func prepare_player_spells(
	player_index: int,
	ready_spell_ids: Array,
	ready_dark_sides: Array,
	quick_spell_id: String = "",
	quick_dark_side: bool = false
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	# =====================================================
	# VALIDATE NUMBER OF SPELLS
	#
	# 2-4 total.
	# Maximum:
	# - 3 Ready Spells
	# - 1 Quick Spell
	# =====================================================

	var total_spells: int = (
		ready_spell_ids.size()
	)


	if not quick_spell_id.is_empty():
		total_spells += 1


	if total_spells < 2 \
	or total_spells > 4:

		print(
			"Preparation: Player ",
			player_index + 1,
			" must prepare between 2 and 4 Spells"
		)

		return false


	if ready_spell_ids.size() > 3:

		print(
			"Preparation: Player ",
			player_index + 1,
			" cannot prepare more than 3 numbered Spells"
		)

		return false


	if ready_dark_sides.size() \
	!= ready_spell_ids.size():

		print(
			"Preparation: side choices do not match Ready Spells"
		)

		return false


	# =====================================================
	# CANNOT PREPARE OVER EXISTING READY SPELLS
	# =====================================================

	if not player.ready_spells.is_empty() \
	or player.quick_spell != null:

		print(
			"Preparation: Player ",
			player_index + 1,
			" already has prepared Spells"
		)

		return false


	# =====================================================
	# VALIDATE ALL CARDS BEFORE MODIFYING HAND
	# =====================================================

	var used_ids: Array[String] = []


	for spell_id_value in ready_spell_ids:

		var spell_id: String = str(
			spell_id_value
		)


		if used_ids.has(
			spell_id
		):

			print(
				"Preparation: duplicate Spell ",
				spell_id
			)

			return false


		var spell: SpellCardState = (
			player.get_spell_from_hand(
				spell_id
			)
		)


		if spell == null:

			print(
				"Preparation: Spell ",
				spell_id,
				" not found in Player ",
				player_index + 1,
				" Hand"
			)

			return false


		used_ids.append(
			spell_id
		)


	if not quick_spell_id.is_empty():

		if used_ids.has(
			quick_spell_id
		):

			print(
				"Preparation: Quick Spell already used in numbered slots"
			)

			return false


		var quick_spell: SpellCardState = (
			player.get_spell_from_hand(
				quick_spell_id
			)
		)


		if quick_spell == null:

			print(
				"Preparation: Quick Spell ",
				quick_spell_id,
				" not found in Hand"
			)

			return false


	# =====================================================
	# PREPARE I / II / III
	#
	# Array order IS slot order:
	#
	# index 0 = I
	# index 1 = II
	# index 2 = III
	# =====================================================

	for i in range(
		ready_spell_ids.size()
	):

		var spell_id: String = str(
			ready_spell_ids[
				i
			]
		)


		var spell: SpellCardState = (
			player.get_spell_from_hand(
				spell_id
			)
		)


		var use_dark_side: bool = bool(
			ready_dark_sides[
				i
			]
		)


		if not player.add_ready_spell(
			spell,
			use_dark_side
		):

			print(
				"Preparation: failed to prepare ",
				spell_id
			)

			return false


	# =====================================================
	# PREPARE QUICK
	# =====================================================

	if not quick_spell_id.is_empty():

		var quick_spell: SpellCardState = (
			player.get_spell_from_hand(
				quick_spell_id
			)
		)


		if not player.set_quick_spell(
			quick_spell,
			quick_dark_side
		):

			print(
				"Preparation: failed to prepare Quick Spell ",
				quick_spell_id
			)

			return false


	# =====================================================
	# LOG
	# =====================================================

	print(
		"Player ",
		player_index + 1,
		" prepared ",
		total_spells,
		" Spells"
	)


	for i in range(
		player.ready_spells.size()
	):

		var ready: ReadySpellState = (
			player.ready_spells[
				i
			]
		)


		print(
			"  Slot ",
			i + 1,
			": ",
			ready.spell.card_name,
			" | ",
			"Dark" if ready.use_dark_side else "Light"
		)


	if player.quick_spell != null:

		print(
			"  Quick: ",
			player.quick_spell.spell.card_name,
			" | ",
			"Dark" if player.quick_spell.use_dark_side else "Light"
		)


	return true
func resolve_preparation_phase(
	context: Dictionary = {}
) -> bool:

	if waiting_for_player_input:

		print(
			"Preparation Phase: game is already waiting for player input"
		)

		return false


	if not start_phase(
		PHASE_PREPARATION
	):

		return false


	print("")
	print("==============================================")
	print("             PREPARATION PHASE")
	print("==============================================")


	# =====================================================
	# SNAPSHOT PLAY ORDER
	# =====================================================

	current_phase_play_order = (
		get_play_order()
	)


	if current_phase_play_order.is_empty():

		print(
			"Preparation Phase: invalid play order"
		)

		return false


	# =====================================================
	# PREPARATION PHASE EVENTS
	# =====================================================

	var phase_context: Dictionary = (
		context.duplicate(true)
	)


	phase_context["game"] = self

	phase_context[
		"play_order"
	] = current_phase_play_order.duplicate()


	if not resolve_events_for_phase(
		PHASE_PREPARATION,
		phase_context
	):

		print(
			"Preparation Phase: Event resolution failed"
		)

		return false


	# =====================================================
	# INITIALIZE INTERACTIVE LOOP
	# =====================================================

	preparation_phase_cursor = 0


	return advance_preparation_phase()

func player_has_available_action(
	player_index: int
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():
		return false

	var player = players[player_index]

	if not player.ready_spells.is_empty():
		return true

	if player.quick_spell != null:
		return true

	if player.has_physical_action():
		return true

	return false
	
func perform_explore_action(
	player_index: int,
	destination_room_ids: Array,
	activate_room_before_movement: bool = false,
	activate_room_after_movement: bool = false,
	context: Dictionary = {}
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	if not player.has_physical_action():

		print(
			"Explore: Player ",
			player_index + 1,
			" has no Physical Action Tokens"
		)

		return false


	if activate_room_before_movement \
	and activate_room_after_movement:

		print(
			"Explore: Room can only be activated once"
		)

		return false


	var speed: int = (
		player.mage.speed
	)


	if destination_room_ids.size() > speed:

		print(
			"Explore: Player ",
			player_index + 1,
			" cannot perform more than ",
			speed,
			" Move(s)"
		)

		return false


	# =====================================================
	# CONSUME PHYSICAL ACTION
	# =====================================================

	if not player.exhaust_physical_action():
		return false


	# =====================================================
	# ROOM BEFORE MOVEMENT
	# =====================================================

	if activate_room_before_movement:

		if player.mage.in_cell:

			print(
				"Explore: cannot activate a Room while in Cell"
			)

			return false


		if not activate_room(
			player_index,
			player.mage.room_id,
			false,
			context
		):

			return false


	# =====================================================
	# MOVEMENT
	#
	# Ogni elemento = un Move di distanza 1.
	# =====================================================

	for room_id_value in destination_room_ids:

		var room_id: String = str(
			room_id_value
		)


		if not move_mage_to_room_id(
			player_index,
			room_id,
			1
		):

			print(
				"Explore: movement failed"
			)

			return false


	# =====================================================
	# ROOM AFTER MOVEMENT
	# =====================================================

	if activate_room_after_movement:

		if player.mage.in_cell:
			return false


		if not activate_room(
			player_index,
			player.mage.room_id,
			false,
			context
		):

			return false


	print(
		"Player ",
		player_index + 1,
		" performed Explore"
	)


	return true
	
func perform_fight_action(
	player_index: int,
	target_player_index: int = -1,
	activate_room_first: bool = false,
	perform_attack: bool = true,
	perform_room_activation: bool = true,
	context: Dictionary = {}
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	if not player.has_physical_action():
		return false


	# =====================================================
	# ROOM FIRST
	# =====================================================

	if perform_room_activation \
	and activate_room_first:

		if player.mage.in_cell:
			return false


		if not activate_room(
			player_index,
			player.mage.room_id,
			false,
			context
		):

			return false


	# =====================================================
	# PHYSICAL ATTACK
	# =====================================================

	if perform_attack:

		if target_player_index < 0 \
		or target_player_index >= players.size():

			return false


		if target_player_index == player_index:
			return false


		var target = players[
			target_player_index
		]


		if player.mage.in_cell \
		or target.mage.in_cell:

			return false


		if player.mage.room_id \
		!= target.mage.room_id:

			print(
				"Fight: target is not in the same Room"
			)

			return false


		deal_damage(
			player_index,
			target_player_index,
			player.mage.strength,
			"physical_attack"
		)


	# =====================================================
	# ROOM AFTER ATTACK
	# =====================================================

	if perform_room_activation \
	and not activate_room_first:

		if player.mage.in_cell:
			return false


		if not activate_room(
			player_index,
			player.mage.room_id,
			false,
			context
		):

			return false


	if not player.exhaust_physical_action():
		return false


	print(
		"Player ",
		player_index + 1,
		" performed Fight"
	)


	return true

func perform_command_action(
	player_index: int,
	evocation_index: int,
	context: Dictionary = {}
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	if not player.has_physical_action():

		print(
			"Command: Player ",
			player_index + 1,
			" has no Physical Action Tokens"
		)

		return false


	if evocation_index < 0 \
	or evocation_index >= player.evocations.size():

		print(
			"Command: invalid Evocation index ",
			evocation_index
		)

		return false


	var evocation: EvocationState = (
		player.evocations[
			evocation_index
		]
	)


	if evocation == null:
		return false


	if not activate_evocation(
		evocation,
		player_index,
		context
	):

		print(
			"Command: Evocation activation failed"
		)

		return false


	if not player.exhaust_physical_action():
		return false


	print(
		"Player ",
		player_index + 1,
		" performed Command with ",
		evocation.evocation_name
	)


	return true
func cast_quick_spell(
	player_index: int,
	context: Dictionary = {}
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	var player = players[
		player_index
	]


	var quick_spell: ReadySpellState = (
		player.quick_spell
	)


	if quick_spell == null:

		print(
			"cast_quick_spell: Player ",
			player_index + 1,
			" has no Quick Spell"
		)

		return false


	if not cast_ready_spell_state(
		player_index,
		quick_spell,
		context
	):

		return false


	player.quick_spell = null


	return true
	
func perform_player_action(
	player_index: int,
	action: Dictionary
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	if action.is_empty():

		print(
			"perform_player_action: empty action"
		)

		return false


	var action_type: String = str(
		action.get(
			"type",
			""
		)
	)


	var action_context: Dictionary = (
		action.get(
			"context",
			{}
		)
	)


	match action_type:

		# =================================================
		# NORMAL READY SPELL
		# =================================================

		"spell":

			return cast_next_ready_spell(
				player_index,
				action_context
			)


		# =================================================
		# QUICK SPELL
		# =================================================

		"quick":

			return cast_quick_spell(
				player_index,
				action_context
			)


		# =================================================
		# EXPLORE
		# =================================================

		"explore":

			var destination_room_ids: Array = (
				action.get(
					"destination_room_ids",
					[]
				)
			)


			var activate_before: bool = bool(
				action.get(
					"activate_room_before_movement",
					false
				)
			)


			var activate_after: bool = bool(
				action.get(
					"activate_room_after_movement",
					false
				)
			)


			return perform_explore_action(
				player_index,
				destination_room_ids,
				activate_before,
				activate_after,
				action_context
			)


		# =================================================
		# FIGHT
		# =================================================

		"fight":

			var target_player_index: int = int(
				action.get(
					"target_player_index",
					-1
				)
			)


			var activate_room_first: bool = bool(
				action.get(
					"activate_room_first",
					false
				)
			)


			var perform_attack: bool = bool(
				action.get(
					"perform_attack",
					true
				)
			)


			var perform_room_activation: bool = bool(
				action.get(
					"perform_room_activation",
					true
				)
			)


			return perform_fight_action(
				player_index,
				target_player_index,
				activate_room_first,
				perform_attack,
				perform_room_activation,
				action_context
			)


		# =================================================
		# COMMAND
		# =================================================

		"command":

			var evocation_index: int = int(
				action.get(
					"evocation_index",
					-1
				)
			)


			return perform_command_action(
				player_index,
				evocation_index,
				action_context
			)


		_:

			print(
				"perform_player_action: unknown action type ",
				action_type
			)

			return false

func resolve_player_activation(
	player_index: int,
	actions: Array
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	# =====================================================
	# NUMBER OF ACTIONS
	#
	# Ogni Activation contiene 1 o 2 Actions.
	# Il Quick Spell CONTA come una Action.
	# =====================================================

	if actions.is_empty():

		print(
			"Activation: Player ",
			player_index + 1,
			" selected no Actions"
		)

		return false


	if actions.size() > 2:

		print(
			"Activation: Player ",
			player_index + 1,
			" cannot perform more than 2 Actions"
		)

		return false


	# =====================================================
	# CAST SPELL VALIDATION
	#
	# Nella stessa Activation:
	#
	# OK:
	#   Spell + Quick
	#   Quick + Spell
	#
	# NOT OK:
	#   Spell + Spell
	#
	# Quick resta comunque una delle due Actions.
	# =====================================================

	var normal_spell_count: int = 0
	var quick_spell_count: int = 0


	for action_value in actions:

		var action: Dictionary = action_value

		var action_type: String = str(
			action.get(
				"type",
				""
			)
		)


		if action_type == "spell":

			normal_spell_count += 1


		elif action_type == "quick":

			quick_spell_count += 1


	# Non può esistere più di un Quick preparato.
	if quick_spell_count > 1:

		print(
			"Activation: Quick Spell selected more than once"
		)

		return false


	# Due Ready Spell numerati nella stessa Activation
	# non possono essere lanciati.
	if normal_spell_count > 1:

		print(
			"Activation: cannot cast two numbered Ready Spells ",
			"in the same Activation"
		)

		return false


	# =====================================================
	# RESOLVE ACTIONS
	# =====================================================

	print("")
	print(
		"--- PLAYER ",
		player_index + 1,
		" ACTIVATION ---"
	)


	for action_value in actions:

		var action: Dictionary = action_value


		if not perform_player_action(
			player_index,
			action
		):

			print(
				"Activation: Action failed for Player ",
				player_index + 1,
				" | type ",
				str(
					action.get(
						"type",
						""
					)
				)
			)

			return false


	print(
		"Player ",
		player_index + 1,
		" Activation complete"
	)


	return true

func resolve_action_phase(
	context: Dictionary = {}
) -> bool:

	if waiting_for_player_input:

		print(
			"Action Phase: game is already waiting for player input"
		)

		return false


	if not start_phase(
		PHASE_ACTION
	):

		return false


	print("")
	print("==============================================")
	print("                ACTION PHASE")
	print("==============================================")


	# =====================================================
	# SNAPSHOT PLAY ORDER
	#
	# Se la Crown cambia durante questa Phase,
	# questo ordine NON cambia.
	# =====================================================

	current_phase_play_order = (
		get_play_order()
	)


	if current_phase_play_order.is_empty():

		print(
			"Action Phase: invalid play order"
		)

		return false


	# =====================================================
	# ACTION PHASE EVENTS
	# =====================================================

	var phase_context: Dictionary = (
		context.duplicate(true)
	)


	phase_context["game"] = self

	phase_context[
		"play_order"
	] = current_phase_play_order.duplicate()


	if not resolve_events_for_phase(
		PHASE_ACTION,
		phase_context
	):

		print(
			"Action Phase: Event resolution failed"
		)

		return false


	# =====================================================
	# INITIALIZE INTERACTIVE LOOP
	# =====================================================

	action_phase_cursor = 0
	action_phase_activation_round = 1


	return advance_action_phase()
	
func resolve_evocation_phase(
	context: Dictionary = {}
) -> bool:

	if not start_phase(
		PHASE_EVOCATION
	):
		return false


	print("")
	print("==============================================")
	print("              EVOCATION PHASE")
	print("==============================================")


	# =====================================================
	# SNAPSHOT PLAY ORDER
	# =====================================================

	var play_order: Array[int] = (
		get_play_order()
	)


	if play_order.is_empty():

		print(
			"Evocation Phase: invalid play order"
		)

		return false


	var phase_context: Dictionary = (
		context.duplicate()
	)


	phase_context["game"] = self
	phase_context["play_order"] = play_order


	# =====================================================
	# PLAYER EVOCATION CHOICES
	#
	# Example:
	#
	# "evocation_activations": {
	#
	#     0: [
	#         {
	#             "evocation_index": 1,
	#             "context": {...}
	#         },
	#         {
	#             "evocation_index": 0,
	#             "context": {...}
	#         }
	#     ]
	# }
	#
	# Array order = activation order chosen by owner.
	# =====================================================

	var activation_choices: Dictionary = (
		context.get(
			"evocation_activations",
			{}
		)
	)


	# =====================================================
	# BLACK ROSE EVOCATIONS
	#
	# According to the rules these activate first.
	#
	# Our current game state has no Black Rose Evocation
	# collection, therefore there is nothing to resolve
	# here yet.
	# =====================================================


	# =====================================================
	# PLAYER EVOCATIONS
	# =====================================================

	for player_index in play_order:

		var player = players[
			player_index
		]


		# No Evocations = nothing to do.
		if player.evocations.is_empty():
			continue


		if not activation_choices.has(
			player_index
		):

			print(
				"Evocation Phase: choices missing for Player ",
				player_index + 1
			)

			return false


		var player_choices: Array = (
			activation_choices[
				player_index
			]
		)


		# Every Evocation must activate exactly once.
		if player_choices.size() \
		!= player.evocations.size():

			print(
				"Evocation Phase: Player ",
				player_index + 1,
				" must activate ",
				player.evocations.size(),
				" Evocation(s)"
			)

			return false


		var used_indices: Array[int] = []


		# =================================================
		# VALIDATE ORDER FIRST
		# =================================================

		for choice_value in player_choices:

			var choice: Dictionary = (
				choice_value
			)


			var evocation_index: int = int(
				choice.get(
					"evocation_index",
					-1
				)
			)


			if evocation_index < 0 \
			or evocation_index >= player.evocations.size():

				print(
					"Evocation Phase: invalid Evocation index ",
					evocation_index
				)

				return false


			if used_indices.has(
				evocation_index
			):

				print(
					"Evocation Phase: Evocation ",
					evocation_index,
					" selected more than once"
				)

				return false


			used_indices.append(
				evocation_index
			)


		# =================================================
		# ACTIVATE IN OWNER'S CHOSEN ORDER
		# =================================================

		for choice_value in player_choices:

			var choice: Dictionary = (
				choice_value
			)


			var evocation_index: int = int(
				choice.get(
					"evocation_index",
					-1
				)
			)


			var evocation: EvocationState = (
				player.evocations[
					evocation_index
				]
			)


			var activation_context: Dictionary = (
				choice.get(
					"context",
					{}
				)
			)


			activation_context = (
				activation_context.duplicate()
			)


			activation_context["game"] = self
			activation_context["play_order"] = play_order


			print(
				"Player ",
				player_index + 1,
				" activates ",
				evocation.evocation_name
			)


			if not activate_evocation(
				evocation,
				player_index,
				activation_context
			):

				print(
					"Evocation Phase: activation failed for ",
					evocation.evocation_name
				)

				return false


	print("")
	print("==============================================")
	print("           EVOCATION PHASE COMPLETE")
	print("==============================================")
	print("")


	return true
func request_player_input(
	request: Dictionary
) -> bool:

	if waiting_for_player_input:

		print(
			"request_player_input: already waiting for input"
		)

		return false


	if not request.has("player_index"):

		print(
			"request_player_input: player_index missing"
		)

		return false


	var player_index: int = int(
		request["player_index"]
	)


	if player_index < 0 \
	or player_index >= players.size():

		print(
			"request_player_input: invalid player_index"
		)

		return false


	pending_input = request.duplicate(
		true
	)

	waiting_for_player_input = true


	print(
		"Waiting for Player ",
		player_index + 1,
		" | input type: ",
		str(
			pending_input.get(
				"type",
				""
			)
		)
	)


	player_input_requested.emit(
		pending_input.duplicate(true)
	)


	return true


func clear_player_input():

	var resolved_request: Dictionary = (
		pending_input.duplicate(true)
	)


	pending_input.clear()
	waiting_for_player_input = false


	player_input_resolved.emit(
		resolved_request
	)
func advance_action_phase() -> bool:

	if current_phase != PHASE_ACTION:

		print(
			"advance_action_phase: not in Action Phase"
		)

		return false


	if waiting_for_player_input:

		return true


	if current_phase_play_order.is_empty():

		print(
			"advance_action_phase: play order missing"
		)

		return false


	# =====================================================
	# IS THE ACTION PHASE OVER?
	# =====================================================

	var somebody_can_act: bool = false


	for player_index in current_phase_play_order:

		if player_has_available_action(
			player_index
		):

			somebody_can_act = true
			break


	if not somebody_can_act:

		return finish_action_phase()


	# =====================================================
	# SEARCH NEXT PLAYER
	# =====================================================

	var checked_players: int = 0


	while checked_players < current_phase_play_order.size():

		if action_phase_cursor \
		>= current_phase_play_order.size():

			action_phase_cursor = 0
			action_phase_activation_round += 1


		var player_index: int = (
			current_phase_play_order[
				action_phase_cursor
			]
		)


		action_phase_cursor += 1
		checked_players += 1


		# This Mage has finished all Actions.
		if not player_has_available_action(
			player_index
		):

			continue


		# =================================================
		# THIS PLAYER MUST PERFORM AN ACTIVATION
		# =================================================

		var request: Dictionary = {

			"type":
				"action_activation",

			"phase":
				PHASE_ACTION,

			"player_index":
				player_index,

			"activation_round":
				action_phase_activation_round,

			"min_actions":
				1,

			"max_actions":
				2,

			"ready_spell_count":
				players[
					player_index
				].ready_spells.size(),

			"has_quick_spell":
				players[
					player_index
				].quick_spell != null,

			"physical_actions":
				players[
					player_index
				].available_physical_actions
		}


		return request_player_input(
			request
		)


	# =====================================================
	# We skipped every player.
	#
	# Re-evaluate phase state rather than waiting for input.
	# =====================================================

	return advance_action_phase()
	
func submit_action_activation(
	player_index: int,
	actions: Array
) -> bool:

	# =====================================================
	# MUST BE WAITING
	# =====================================================

	if not waiting_for_player_input:

		print(
			"submit_action_activation: no input requested"
		)

		return false


	# =====================================================
	# CORRECT INPUT TYPE
	# =====================================================

	if str(
		pending_input.get(
			"type",
			""
		)
	) != "action_activation":

		print(
			"submit_action_activation: wrong pending input type"
		)

		return false


	# =====================================================
	# CORRECT PLAYER
	# =====================================================

	var expected_player_index: int = int(
		pending_input.get(
			"player_index",
			-1
		)
	)


	if player_index != expected_player_index:

		print(
			"submit_action_activation: expected Player ",
			expected_player_index + 1,
			", received Player ",
			player_index + 1
		)

		return false


	# =====================================================
	# RESOLVE ACTIVATION
	#
	# resolve_player_activation() already validates:
	#
	# - 1 or 2 Actions
	# - Quick counts as an Action
	# - no Spell + Spell
	# - Spell + Quick is legal
	# - Quick + Spell is legal
	# =====================================================

	if not resolve_player_activation(
		player_index,
		actions
	):

		print(
			"submit_action_activation: invalid Activation"
		)

		# IMPORTANT:
		#
		# We remain waiting for the SAME player.
		#
		# The UI can therefore let them correct
		# their choice.
		return false


	# =====================================================
	# INPUT SUCCESSFULLY RESOLVED
	# =====================================================

	clear_player_input()


	# =====================================================
	# CONTINUE AUTOMATICALLY
	# =====================================================

	return advance_action_phase()
func finish_action_phase() -> bool:

	if current_phase != PHASE_ACTION:

		return false


	if waiting_for_player_input:

		print(
			"finish_action_phase: still waiting for input"
		)

		return false


	print("")
	print("==============================================")
	print("             ACTION PHASE COMPLETE")
	print("==============================================")
	print("")


	action_phase_cursor = 0
	action_phase_activation_round = 0

	current_phase_play_order.clear()


	return true
func advance_preparation_phase() -> bool:

	if current_phase != PHASE_PREPARATION:

		print(
			"advance_preparation_phase: not in Preparation Phase"
		)

		return false


	if waiting_for_player_input:
		return true


	if current_phase_play_order.is_empty():

		print(
			"advance_preparation_phase: play order missing"
		)

		return false


	# =====================================================
	# ALL PLAYERS COMPLETED PREPARATION
	# =====================================================

	if preparation_phase_cursor \
	>= current_phase_play_order.size():

		return finish_preparation_phase()


	# =====================================================
	# CURRENT PLAYER
	# =====================================================

	var player_index: int = (
		current_phase_play_order[
			preparation_phase_cursor
		]
	)


	var player = players[
		player_index
	]


	# =====================================================
	# REQUEST PREPARATION
	#
	# The UI receives the actual Hand information required
	# to build the selection.
	#
	# The Game will still validate everything when the
	# choice is submitted.
	# =====================================================

	var hand_data: Array = []


	for spell in player.hand:

		if spell == null:
			continue


		hand_data.append(
			{
				"id": spell.id,
				"name": spell.card_name,
				"school_id": spell.school_id
			}
		)


	var request: Dictionary = {

		"type":
			"preparation",

		"phase":
			PHASE_PREPARATION,

		"player_index":
			player_index,

		"min_spells":
			2,

		"max_spells":
			4,

		"max_numbered_spells":
			3,

		"quick_allowed":
			true,

		"hand":
			hand_data
	}


	return request_player_input(
		request
	)
func submit_preparation(
	player_index: int,
	ready_spell_ids: Array,
	ready_dark_sides: Array,
	quick_spell_id: String = "",
	quick_dark_side: bool = false
) -> bool:

	# =====================================================
	# MUST BE WAITING
	# =====================================================

	if not waiting_for_player_input:

		print(
			"submit_preparation: no input requested"
		)

		return false


	# =====================================================
	# CORRECT INPUT TYPE
	# =====================================================

	if str(
		pending_input.get(
			"type",
			""
		)
	) != "preparation":

		print(
			"submit_preparation: wrong pending input type"
		)

		return false


	# =====================================================
	# CORRECT PLAYER
	# =====================================================

	var expected_player_index: int = int(
		pending_input.get(
			"player_index",
			-1
		)
	)


	if player_index != expected_player_index:

		print(
			"submit_preparation: expected Player ",
			expected_player_index + 1,
			", received Player ",
			player_index + 1
		)

		return false


	# =====================================================
	# RESOLVE CHOICE
	#
	# Existing function performs the authoritative
	# validation and moves cards Hand -> Ready/Quick.
	# =====================================================

	if not prepare_player_spells(
		player_index,
		ready_spell_ids,
		ready_dark_sides,
		quick_spell_id,
		quick_dark_side
	):

		print(
			"submit_preparation: invalid preparation for Player ",
			player_index + 1
		)

		# Keep waiting for the same player.
		return false


	# =====================================================
	# CHOICE ACCEPTED
	# =====================================================

	clear_player_input()


	preparation_phase_cursor += 1


	# =====================================================
	# NEXT PLAYER
	# =====================================================

	return advance_preparation_phase()

func finish_preparation_phase() -> bool:

	if current_phase != PHASE_PREPARATION:

		return false


	if waiting_for_player_input:

		print(
			"finish_preparation_phase: still waiting for input"
		)

		return false


	print("")
	print("==============================================")
	print("          PREPARATION PHASE COMPLETE")
	print("==============================================")
	print("")


	preparation_phase_cursor = 0

	current_phase_play_order.clear()


	return true
func advance_study_phase() -> bool:

	if current_phase != PHASE_STUDY:

		print(
			"advance_study_phase: not in Study Phase"
		)

		return false


	if waiting_for_player_input:
		return true


	# =====================================================
	# ALL PLAYERS COMPLETED STUDY
	# =====================================================

	if study_phase_cursor \
	>= current_phase_play_order.size():

		return finish_study_phase()


	# =====================================================
	# CURRENT PLAYER
	# =====================================================

	var player_index: int = (
		current_phase_play_order[
			study_phase_cursor
		]
	)


	study_drawn_cards.clear()


	# =====================================================
	# REQUEST FOUR LIBRARY DRAWS
	# =====================================================

	var request: Dictionary = {

		"type":
			"study_choose_schools",

		"phase":
			PHASE_STUDY,

		"player_index":
			player_index,

		"draw_count":
			4,

		"active_school_ids":
			active_school_ids.duplicate()
	}


	return request_player_input(
		request
	)
	
func submit_study_school_choices(
	player_index: int,
	school_ids: Array
) -> bool:

	if not waiting_for_player_input:

		print(
			"submit_study_school_choices: no input requested"
		)

		return false


	if str(
		pending_input.get(
			"type",
			""
		)
	) != "study_choose_schools":

		print(
			"submit_study_school_choices: wrong pending input type"
		)

		return false


	var expected_player_index: int = int(
		pending_input.get(
			"player_index",
			-1
		)
	)


	if player_index != expected_player_index:

		print(
			"submit_study_school_choices: expected Player ",
			expected_player_index + 1
		)

		return false


	# =====================================================
	# EXACTLY FOUR DRAWS
	# =====================================================

	if school_ids.size() != 4:

		print(
			"Study: exactly 4 Library draws are required"
		)

		return false


	# =====================================================
	# VALIDATE ALL SCHOOLS BEFORE DRAWING
	# =====================================================

	for school_value in school_ids:

		var school_id: String = str(
			school_value
		)


		if not is_school_active(
			school_id
		):

			print(
				"Study: inactive School: ",
				school_id
			)

			return false


	# =====================================================
	# DRAW
	# =====================================================

	study_drawn_cards.clear()


	for school_value in school_ids:

		var school_id: String = str(
			school_value
		)


		var spell: SpellCardState = (
			draw_from_school_library(
				school_id
			)
		)


		if spell == null:

			print(
				"Study: could not draw from ",
				school_id
			)

			return false


		study_drawn_cards.append(
			spell
		)


	# =====================================================
	# FIRST INPUT COMPLETED
	# =====================================================

	clear_player_input()


	# =====================================================
	# NOW ASK WHICH TWO TO KEEP
	# =====================================================

	return request_study_keep_cards(
		player_index
	)
func request_study_keep_cards(
	player_index: int
) -> bool:

	if study_drawn_cards.size() != 4:

		print(
			"request_study_keep_cards: expected 4 drawn cards"
		)

		return false


	var card_data: Array = []


	for i in range(
		study_drawn_cards.size()
	):

		var spell: SpellCardState = (
			study_drawn_cards[i]
		)


		card_data.append(
			{
				"draw_index": i,
				"id": spell.id,
				"name": spell.card_name,
				"school_id": spell.school_id
			}
		)


	var request: Dictionary = {

		"type":
			"study_keep_cards",

		"phase":
			PHASE_STUDY,

		"player_index":
			player_index,

		"keep_count":
			2,

		"cards":
			card_data
	}


	return request_player_input(
		request
	)

func submit_study_keep_cards(
	player_index: int,
	keep_indices: Array
) -> bool:

	if not waiting_for_player_input:

		print(
			"submit_study_keep_cards: no input requested"
		)

		return false


	if str(
		pending_input.get(
			"type",
			""
		)
	) != "study_keep_cards":

		print(
			"submit_study_keep_cards: wrong pending input type"
		)

		return false


	var expected_player_index: int = int(
		pending_input.get(
			"player_index",
			-1
		)
	)


	if player_index != expected_player_index:
		return false


	if study_drawn_cards.size() != 4:

		print(
			"Study: invalid temporary Library draw"
		)

		return false


	# =====================================================
	# MUST KEEP EXACTLY TWO
	# =====================================================

	if keep_indices.size() != 2:

		print(
			"Study: exactly 2 cards must be kept"
		)

		return false


	var first_index: int = int(
		keep_indices[0]
	)

	var second_index: int = int(
		keep_indices[1]
	)


	if first_index < 0 \
	or first_index >= study_drawn_cards.size():

		return false


	if second_index < 0 \
	or second_index >= study_drawn_cards.size():

		return false


	if first_index == second_index:

		print(
			"Study: the same card cannot be kept twice"
		)

		return false


	# =====================================================
	# KEEP 2, DISCARD 2
	# =====================================================

	var player = players[
		player_index
	]


	for i in range(
		study_drawn_cards.size()
	):

		var spell: SpellCardState = (
			study_drawn_cards[i]
		)


		if i == first_index \
		or i == second_index:

			player.add_spell_to_hand(
				spell
			)

			print(
				"Study: Player ",
				player_index + 1,
				" keeps ",
				spell.card_name
			)


		else:

			if not discard_to_school(
				spell.school_id,
				spell
			):

				print(
					"Study: could not discard ",
					spell.card_name,
					" to ",
					spell.school_id
				)

				return false


	study_drawn_cards.clear()


	clear_player_input()


	# =====================================================
	# OPTIONAL STUDY DISCARD
	# =====================================================

	return request_study_optional_discard(
		player_index
	)
func request_study_optional_discard(
	player_index: int
) -> bool:

	var player = players[
		player_index
	]


	var hand_data: Array = []


	for i in range(
		player.hand.size()
	):

		var spell: SpellCardState = (
			player.hand[i]
		)


		hand_data.append(
			{
				"hand_index": i,
				"id": spell.id,
				"name": spell.card_name,
				"school_id": spell.school_id
			}
		)


	var request: Dictionary = {

		"type":
			"study_optional_discard",

		"phase":
			PHASE_STUDY,

		"player_index":
			player_index,

		"optional":
			true,

		"max_discard":
			1,

		"hand":
			hand_data
	}


	return request_player_input(
		request
	)

func submit_study_optional_discard(
	player_index: int,
	hand_index: int = -1
) -> bool:

	if not waiting_for_player_input:

		print(
			"submit_study_optional_discard: no input requested"
		)

		return false


	if str(
		pending_input.get(
			"type",
			""
		)
	) != "study_optional_discard":

		print(
			"submit_study_optional_discard: wrong pending input type"
		)

		return false


	var expected_player_index: int = int(
		pending_input.get(
			"player_index",
			-1
		)
	)


	if player_index != expected_player_index:
		return false


	var player = players[
		player_index
	]


	# =====================================================
	# OPTIONAL: -1 MEANS SKIP
	# =====================================================

	if hand_index != -1:

		if hand_index < 0 \
		or hand_index >= player.hand.size():

			print(
				"Study: invalid Hand index"
			)

			return false


		var spell: SpellCardState = (
			player.hand[
				hand_index
			]
		)


		if not is_school_active(
			spell.school_id
		):

			print(
				"Study: cannot discard ",
				spell.card_name,
				" to an inactive Library"
			)

			return false


		player.hand.remove_at(
			hand_index
		)


		if not discard_to_school(
			spell.school_id,
			spell
		):

			# Restore card if discard unexpectedly fails.
			player.hand.insert(
				hand_index,
				spell
			)

			return false


		print(
			"Study: Player ",
			player_index + 1,
			" discards ",
			spell.card_name,
			" to ",
			spell.school_id
		)


	clear_player_input()


	# =====================================================
	# HAND LIMIT
	# =====================================================

	return continue_study_after_optional_discard(
		player_index
	)
	
func continue_study_after_optional_discard(
	player_index: int
) -> bool:

	var player = players[
		player_index
	]


	var excess: int = (
		player.get_hand_size()
		- player.get_hand_limit()
	)


	if excess > 0:

		return request_study_hand_limit(
			player_index,
			excess
		)


	return complete_player_study(
		player_index
	)
func request_study_hand_limit(
	player_index: int,
	discard_count: int
) -> bool:

	var player = players[
		player_index
	]


	var hand_data: Array = []


	for i in range(
		player.hand.size()
	):

		var spell: SpellCardState = (
			player.hand[i]
		)


		hand_data.append(
			{
				"hand_index": i,
				"id": spell.id,
				"name": spell.card_name,
				"school_id": spell.school_id
			}
		)


	var request: Dictionary = {

		"type":
			"study_hand_limit",

		"phase":
			PHASE_STUDY,

		"player_index":
			player_index,

		"discard_count":
			discard_count,

		"hand":
			hand_data
	}


	return request_player_input(
		request
	)
func submit_study_hand_limit(
	player_index: int,
	hand_indices: Array
) -> bool:

	if not waiting_for_player_input:

		print(
			"submit_study_hand_limit: no input requested"
		)

		return false


	if str(
		pending_input.get(
			"type",
			""
		)
	) != "study_hand_limit":

		print(
			"submit_study_hand_limit: wrong pending input type"
		)

		return false


	var expected_player_index: int = int(
		pending_input.get(
			"player_index",
			-1
		)
	)


	if player_index != expected_player_index:
		return false


	var required_count: int = int(
		pending_input.get(
			"discard_count",
			0
		)
	)


	if hand_indices.size() != required_count:

		print(
			"Study: must move exactly ",
			required_count,
			" card(s) to Memories"
		)

		return false


	var player = players[
		player_index
	]


	# =====================================================
	# VALIDATE UNIQUE INDICES
	# =====================================================

	var validated_indices: Array[int] = []


	for index_value in hand_indices:

		var hand_index: int = int(
			index_value
		)


		if hand_index < 0 \
		or hand_index >= player.hand.size():

			return false


		if validated_indices.has(
			hand_index
		):

			print(
				"Study: duplicate Hand index"
			)

			return false


		validated_indices.append(
			hand_index
		)


	# =====================================================
	# REMOVE FROM HIGHEST INDEX TO LOWEST
	#
	# This prevents Array indices shifting underneath us.
	# =====================================================

	validated_indices.sort()
	validated_indices.reverse()


	for hand_index in validated_indices:

		var spell: SpellCardState = (
			player.hand[
				hand_index
			]
		)


		player.hand.remove_at(
			hand_index
		)


		player.add_spell_to_memories(
			spell
		)


		print(
			"Study: ",
			spell.card_name,
			" -> Memories"
		)


	clear_player_input()


	return complete_player_study(
		player_index
	)
func complete_player_study(
	player_index: int
) -> bool:

	var player = players[
		player_index
	]


	if player.get_hand_size() \
	> player.get_hand_limit():

		print(
			"complete_player_study: Player ",
			player_index + 1,
			" is still above Hand limit"
		)

		return false


	print(
		"Player ",
		player_index + 1,
		" completed Study | Hand: ",
		player.get_hand_size()
	)


	study_phase_cursor += 1


	return advance_study_phase()
func finish_study_phase() -> bool:

	if current_phase != PHASE_STUDY:
		return false


	if waiting_for_player_input:

		print(
			"finish_study_phase: still waiting for input"
		)

		return false


	study_phase_cursor = 0
	study_drawn_cards.clear()

	current_phase_play_order.clear()


	print("")
	print("==============================================")
	print("             STUDY PHASE COMPLETE")
	print("==============================================")
	print("")


	return true
	
func resolve_spell_reveal_instability(
	player_index: int,
	spell: SpellCardState
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	if spell == null:
		return false


	# Nessun simbolo Instability centrale.
	if not spell.has_instability():
		return true


	var mage = players[
		player_index
	].mage


	# Un Mage nella Cell non è in una Room della Lodge.
	if mage.in_cell:

		print(
			"Spell reveal instability: Player ",
			player_index + 1,
			" is in Cell"
		)

		return true


	# place_instability() gestisce già:
	# - disponibilità cubi
	# - slot disponibili
	# - GameEvent relativo all'Instability
	#
	# Se la Room è piena, semplicemente non viene
	# piazzato il cubo.
	place_instability(
		player_index,
		mage.room_id,
		1
	)


	print(
		"Spell Instability: Player ",
		player_index + 1,
		" | ",
		spell.card_name,
		" | Room ",
		mage.room_id
	)


	return true
func cast_ready_spell_state(
	player_index: int,
	ready_spell: ReadySpellState,
	context: Dictionary = {}
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():

		return false


	if ready_spell == null:
		return false


	if ready_spell.spell == null:
		return false


	var player = players[
		player_index
	]


	var spell: SpellCardState = (
		ready_spell.spell
	)


	var use_dark_side: bool = (
		ready_spell.use_dark_side
	)


	var side: Dictionary = (
		spell.get_side(
			use_dark_side
		)
	)


	var spell_type: String = str(
		side.get(
			"type",
			""
		)
	)


	var spell_context: Dictionary = (
		context.duplicate(true)
	)


	spell_context["game"] = self
	spell_context["caster_id"] = player_index

	spell_context[
		"caster_room_id"
	] = player.mage.room_id


	# =====================================================
	# TRAP / PROTECTION
	#
	# They are cast FACE DOWN.
	# Their effects are NOT resolved now.
	# =====================================================

	if spell_type == "trap" \
	or spell_type == "protection":

		var target_player_index: int = int(
			spell_context.get(
				"target_player_index",
				-1
			)
		)


		var active_spell := ActiveSpellState.new(
			spell,
			player_index,
			use_dark_side,
			target_player_index
		)


		# Store all choices that may be required later
		# when the Trigger Condition occurs.
		for key in spell_context:

			if key == "game":
				continue

			active_spell.context[
				key
			] = spell_context[key]


		player.add_active_spell(
			active_spell
		)


		print(
			"Player ",
			player_index + 1,
			" activates ",
			spell.card_name,
			" [",
			spell_type,
			"]"
		)


		return true


	# =====================================================
	# NORMAL SPELL
	#
	# Combat / Contingency are revealed immediately.
	# =====================================================

	if spell_type != "combat" \
	and spell_type != "contingency":

		print(
			"cast_ready_spell_state: unsupported Spell type: ",
			spell_type
		)

		return false


	# =====================================================
	# REVEAL INSTABILITY
	#
	# This happens BEFORE resolving the Spell.
	# =====================================================

	if not resolve_spell_reveal_instability(
		player_index,
		spell
	):

		return false


	# =====================================================
	# RESOLVE SPELL
	# =====================================================

	if not resolve_spell(
		spell,
		use_dark_side,
		spell_context
	):

		print(
			"Failed to resolve Spell: ",
			spell.card_name
		)

		return false


	print(
		"Player ",
		player_index + 1,
		" cast ",
		spell.card_name,
		" | side: ",
		"Dark" if use_dark_side else "Light"
	)


	return true
func order_optional_triggers(
	triggers: Array
) -> Array:

	var result: Array = []


	var play_order: Array[int] = (
		current_phase_play_order.duplicate()
	)


	if play_order.is_empty():

		play_order = get_play_order()


	# =====================================================
	# GROUP BY PLAYER IN PLAY ORDER
	# =====================================================

	for player_index in play_order:

		for trigger_data in triggers:

			var active_spell: ActiveSpellState = (
				trigger_data.get(
					"active_spell",
					null
				)
			)


			if active_spell == null:
				continue


			if active_spell.owner_id \
			!= player_index:

				continue


			result.append(
				trigger_data
			)


	return result
	
func request_next_trigger_decision() -> bool:

	if not trigger_window_active:
		return true


	if waiting_for_player_input:
		return true


	if trigger_window_cursor \
	>= trigger_window_queue.size():

		return finish_trigger_window()


	var current_data: Dictionary = (
		trigger_window_queue[
			trigger_window_cursor
		]
	)


	var current_spell: ActiveSpellState = (
		current_data.get(
			"active_spell",
			null
		)
	)


	if current_spell == null:

		trigger_window_cursor += 1

		return request_next_trigger_decision()


	var player_index: int = (
		current_spell.owner_id
	)


	# =====================================================
	# ALL CURRENT OPTIONS FOR THIS PLAYER
	# =====================================================

	var options: Array = []


	for i in range(
		trigger_window_cursor,
		trigger_window_queue.size()
	):

		var trigger_data: Dictionary = (
			trigger_window_queue[i]
		)


		var active_spell: ActiveSpellState = (
			trigger_data.get(
				"active_spell",
				null
			)
		)


		if active_spell == null:
			continue


		# Next player's block reached.
		if active_spell.owner_id != player_index:
			break


		options.append(
			{
				"queue_index": i,

				"spell_id":
					active_spell.spell.id,

				"spell_name":
					active_spell.spell.card_name,

				"spell_type":
					active_spell.get_spell_type()
			}
		)


	var request: Dictionary = {

		"type":
			"trigger_decision",

		"phase":
			current_phase,

		"player_index":
			player_index,

		"optional":
			true,

		"options":
			options
	}


	return request_player_input(
		request
	)
func submit_trigger_decision(
	player_index: int,
	queue_index: int = -1
) -> bool:

	if not trigger_window_active:

		print(
			"submit_trigger_decision: no active trigger window"
		)

		return false


	if not waiting_for_player_input:

		print(
			"submit_trigger_decision: no input requested"
		)

		return false


	if str(
		pending_input.get(
			"type",
			""
		)
	) != "trigger_decision":

		print(
			"submit_trigger_decision: wrong pending input type"
		)

		return false


	var expected_player_index: int = int(
		pending_input.get(
			"player_index",
			-1
		)
	)


	if player_index != expected_player_index:

		print(
			"submit_trigger_decision: wrong player"
		)

		return false


	# =====================================================
	# PASS
	# =====================================================

	if queue_index == -1:

		clear_player_input()


		while trigger_window_cursor \
		< trigger_window_queue.size():

			var trigger_data: Dictionary = (
				trigger_window_queue[
					trigger_window_cursor
				]
			)


			var active_spell: ActiveSpellState = (
				trigger_data.get(
					"active_spell",
					null
				)
			)


			if active_spell == null:

				trigger_window_cursor += 1
				continue


			if active_spell.owner_id != player_index:
				break


			trigger_window_cursor += 1


		# Continue with the next player, if any.
		request_next_trigger_decision()


		# If another decision was requested, stop here.
		if waiting_for_player_input:
			return true


		# Otherwise the Trigger Window has finished.
		return process_resolution_stack()


	# =====================================================
	# VALIDATE CHOSEN TRIGGER
	# =====================================================

	var valid_option: bool = false


	var options: Array = (
		pending_input.get(
			"options",
			[]
		)
	)


	for option_value in options:

		var option: Dictionary = (
			option_value
		)


		if int(
			option.get(
				"queue_index",
				-1
			)
		) == queue_index:

			valid_option = true
			break


	if not valid_option:

		print(
			"submit_trigger_decision: invalid trigger option"
		)

		return false


	# =====================================================
	# REMOVE CHOSEN TRIGGER FROM QUEUE
	# =====================================================

	var trigger_data: Dictionary = (
		trigger_window_queue[
			queue_index
		]
	)


	trigger_window_queue.remove_at(
		queue_index
	)


	clear_player_input()


	# =====================================================
	# REVEAL + RESOLVE TRIGGERED SPELL
	# =====================================================

	handle_triggered_spell(
		trigger_data
	)


	# =====================================================
	# SAME PLAYER MAY HAVE ANOTHER TRIGGER
	# =====================================================

	request_next_trigger_decision()


	if waiting_for_player_input:
		return true


	# =====================================================
	# WINDOW COMPLETE → RESUME INTERRUPTED RESOLUTION
	# =====================================================

	return process_resolution_stack()
	
func finish_trigger_window() -> bool:

	if not trigger_window_active:
		return true


	if waiting_for_player_input:
		return false


	trigger_window_active = false

	trigger_window_event = null

	trigger_window_queue.clear()

	trigger_window_cursor = 0


	print(
		"Trigger window complete"
	)


	return true
func queue_resolution(
	resolution: Dictionary
) -> bool:

	if resolution.is_empty():

		print(
			"queue_resolution: empty resolution"
		)

		return false


	if not resolution.has("type"):

		print(
			"queue_resolution: missing type"
		)

		return false


	# Insert at the front.
	#
	# This means a nested resolution is handled before
	# returning to the operation that generated it.

	resolution_stack.push_front(
		resolution.duplicate(true)
	)


	return process_resolution_stack()
func process_resolution_stack() -> bool:

	if processing_resolution_stack:
		return true


	processing_resolution_stack = true


	while not resolution_stack.is_empty():

		# =================================================
		# PLAYER DECISION REQUIRED
		# =================================================

		if waiting_for_player_input:

			processing_resolution_stack = false
			return true


		# =================================================
		# OPTIONAL TRIGGER WINDOW CURRENTLY OPEN
		# =================================================

		if trigger_window_active:

			if not request_next_trigger_decision():

				processing_resolution_stack = false
				return false


			if waiting_for_player_input:

				processing_resolution_stack = false
				return true


			if trigger_window_active:

				processing_resolution_stack = false
				return true


		# =================================================
		# CURRENT RESOLUTION
		# =================================================

		var resolution: Dictionary = (
			resolution_stack[0]
		)


		var resolution_type: String = str(
			resolution.get(
				"type",
				""
			)
		)


		var completed: bool = false


		match resolution_type:

			"damage":

				completed = (
					process_damage_resolution(
						resolution
					)
				)


			_:

				print(
					"process_resolution_stack: unsupported resolution type: ",
					resolution_type
				)

				resolution_stack.pop_front()

				processing_resolution_stack = false
				return false


		# =================================================
		# RESOLUTION PAUSED
		# =================================================

		if not completed:

			processing_resolution_stack = false
			return true


		# =================================================
		# RESOLUTION COMPLETE
		# =================================================

		resolution_stack.pop_front()


	processing_resolution_stack = false

	return true
func process_damage_resolution(
	resolution: Dictionary
) -> bool:

	var step: String = str(
		resolution.get(
			"step",
			"pre_event"
		)
	)


	match step:

		# =================================================
		# STEP 1 — CREATE PRE-DAMAGE EVENT
		# =================================================

		"pre_event":

			var attacker_id: int = int(
				resolution.get(
					"attacker_id",
					-1
				)
			)


			var target_player_index: int = int(
				resolution.get(
					"target_player_index",
					-1
				)
			)


			var amount: int = int(
				resolution.get(
					"amount",
					0
				)
			)


			var action_type: String = str(
				resolution.get(
					"action_type",
					""
				)
			)


			var event := GameEvent.new(
				"damage_about_to_be_inflicted"
			)


			event.source_player_index = attacker_id
			event.target_player_index = target_player_index
			event.amount = amount

			event.context[
				"action_type"
			] = action_type

			event.context[
				"suppressed_trigger_types"
			] = resolution.get(
				"suppressed_trigger_types",
				[]
			)


			resolution["event"] = event

			# IMPORTANT:
			# Set the next step BEFORE processing triggers.
			#
			# If trigger resolution pauses the Game, when
			# we resume we continue from after_pre_event.

			resolution["step"] = "after_pre_event"


			var event_complete: bool = (
				process_game_event(
					event
				)
			)


			if not event_complete:

				# Optional trigger window exists.
				#
				# The Damage resolution remains at the
				# top of the stack.

				request_next_trigger_decision()

				return false


			# No pause required.
			return process_damage_resolution(
				resolution
			)


		# =================================================
		# STEP 2 — READ MODIFIED PRE-DAMAGE EVENT
		# =================================================

		"after_pre_event":

			var event: GameEvent = (
				resolution.get(
					"event",
					null
				)
			)


			if event == null:

				print(
					"Damage resolution: pre-event missing"
				)

				resolution["step"] = "complete"
				return true


			# Protection may have cancelled the Damage.
			if event.cancelled:

				print(
					"Damage cancelled"
				)

				resolution["step"] = "complete"

				return true


			# Protection may have modified amount or target.
			resolution[
				"amount"
			] = max(
				0,
				int(event.amount)
			)


			resolution[
				"target_player_index"
			] = event.target_player_index


			if int(
				resolution["amount"]
			) <= 0:

				print(
					"Damage reduced to 0"
				)

				resolution["step"] = "complete"

				return true


			resolution["step"] = "apply_damage"


			return process_damage_resolution(
				resolution
			)


		# =================================================
		# STEP 3 — APPLY ACTUAL DAMAGE
		# =================================================

		"apply_damage":

			var target_player_index: int = int(
				resolution[
					"target_player_index"
				]
			)


			if target_player_index < 0 \
			or target_player_index >= players.size():

				print(
					"Damage resolution: invalid final target"
				)

				resolution["step"] = "complete"

				return true


			var amount: int = int(
				resolution[
					"amount"
				]
			)


			var attacker_id: int = int(
				resolution[
					"attacker_id"
				]
			)


			var target_player = players[
				target_player_index
			]


			# =================================================
			# USE THE EXISTING MAGE DAMAGE METHOD
			# =================================================

			target_player.mage.take_damage(
				attacker_id,
				amount
			)


			print(
				"Player ",
				target_player_index + 1,
				" takes ",
				amount,
				" Damage from ",
				attacker_id
			)


			resolution["step"] = "post_event"


			return process_damage_resolution(
				resolution
			)


		# =================================================
		# STEP 4 — POST-DAMAGE EVENT
		# =================================================

		"post_event":

			var post_event := GameEvent.new(
				"damage_inflicted"
			)


			post_event.source_player_index = int(
				resolution[
					"attacker_id"
				]
			)


			post_event.target_player_index = int(
				resolution[
					"target_player_index"
				]
			)


			post_event.amount = int(
				resolution[
					"amount"
				]
			)


			post_event.context[
				"action_type"
			] = str(
				resolution.get(
					"action_type",
					""
				)
			)


			post_event.context[
				"suppressed_trigger_types"
			] = resolution.get(
				"suppressed_trigger_types",
				[]
			)


			resolution["event"] = post_event

			resolution["step"] = "after_post_event"


			var event_complete: bool = (
				process_game_event(
					post_event
				)
			)


			if not event_complete:

				request_next_trigger_decision()

				return false


			return process_damage_resolution(
				resolution
			)


		# =================================================
		# STEP 5 — POST EVENT FINISHED
		# =================================================

		"after_post_event":

			resolution["step"] = "complete"

			return true


		# =================================================
		# COMPLETE
		# =================================================

		"complete":

			return true


		_:

			print(
				"Unknown Damage resolution step: ",
				step
			)

			return true
