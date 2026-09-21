extends Node2D

const Tests = preload("res://tests.gd")

@export var run_tests_on_ready: bool = false
@export var auto_start_game_flow: bool = true
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
var trigger_window_stack: Array[Dictionary] = []
# =========================================================
# RESOLUTION STACK
# =========================================================

var resolution_stack: Array[Dictionary] = []
var processing_resolution_stack: bool = false
var next_resolution_id: int = 1
var active_effect_context: Dictionary = {}

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
# EVOCATION / CLEAN-UP PHASE STATE
# =========================================================
var evocation_phase_cursor: int = 0
var cleanup_phase_cursor: int = 0
# =========================================================
# STUDY PHASE STATE
# =========================================================

var study_phase_cursor: int = 0

# Le 4 carte temporaneamente pescate dalla Library
# dal giocatore che sta risolvendo lo Study.
var study_drawn_cards: Array[SpellCardState] = []

# =========================================================
# GAME FLOW / BOARD STATE
# =========================================================
signal phase_completed(phase: String)
signal game_over(winner_data: Dictionary)
var game_flow_active: bool = false
var game_has_ended: bool = false
var player_entrance_room_ids: Dictionary = {}
var player_entrance_room_coords: Dictionary = {}
var cancelled_physical_action_players: Dictionary = {}
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
var mage_database = MageDatabase.new()
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
var quest_database := QuestDatabase.new()
var quest_manager := QuestManager.new()
var black_rose_quest_step: int = 0
var black_rose_quest_cursor: int = 0
var quest_decks: Dictionary = {
	1: [],
	2: [],
	3: []
}

var quest_discard: Array[QuestCardState] = []

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
	mage_database.load_database()
	quest_database.load_from_file(
	"res://data/quests.json"
	)

	create_quest_decks()
	event_database.load_database()
	create_event_decks()

	evocation_database.load_database()
	
	create_players()
	assign_initial_crown()
	create_lodge()
	create_player_boards()

	for board in player_boards:
		if board != null:
			board.refresh()

	await $PowerBoard.initialize(player_count)
	$EventBoard.refresh_event_slots()
	update_table_layout()
	await get_tree().process_frame

	if run_tests_on_ready:
		Tests.run(self)

	if auto_start_game_flow:
		start_game_flow()

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

	player_entrance_room_ids.clear()
	player_entrance_room_coords.clear()

	for i in range(cell_slots.size()):
		var slot_data = cell_slots[i]
		var position_array = slot_data["position"]
		var hex_position = Vector2i(
			int(position_array[0]),
			int(position_array[1])
		)

		var cell_data = selected_cells[i]
		create_cell(cell_data, hex_position)

		var entrance_array = slot_data["entrance_room"]
		var entrance_room = Vector2i(
			int(entrance_array[0]),
			int(entrance_array[1])
		)
		var entrance_room_id: String = coord_to_room_id(entrance_room)

		if i < players.size():
			player_entrance_room_coords[i] = entrance_room
			player_entrance_room_ids[i] = entrance_room_id

			players[i].mage.room_coord = entrance_room
			players[i].mage.room_id = entrance_room_id
			players[i].mage.in_cell = true

			print(
				"Player ", i + 1,
				" entrance room: ", entrance_room,
				" (", entrance_room_id, ")",
				" | starts in Cell: true"
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

	var test_mages: Array[String] = [
		"rikkart",
		"angela"
	]

	for i in range(player_count):

		var player = PlayerState.new(
			i,
			"Player " + str(i + 1),
			colors[i]
		)

		players.append(player)

		if i < test_mages.size():

			var mage_id: String = test_mages[i]

			if assign_mage_to_player(
				i,
				mage_id
			):

				give_initial_personal_spell(i)

	print(
		"Players created: ",
		players.size()
	)

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
) -> int:
	if target_player_index < 0 \
	or target_player_index >= players.size():
		print("deal_damage: invalid target player")
		return 0

	if amount <= 0:
		return 0

	var capacity: int = players[target_player_index].mage.get_remaining_health()
	if capacity <= 0:
		return 0

	var requested: int = min(amount, capacity)
	var result_context: Dictionary = {}

	# When called by an EffectResolver, keep a reference to the currently
	# resolving context so the asynchronous Damage frame can overwrite the
	# optimistic result with the real post-Protection result before the next
	# Effect is resolved.
	if not active_effect_context.is_empty():
		result_context = active_effect_context

	queue_resolution({
		"type": "damage",
		"step": "pre_event",
		"attacker_id": attacker_id,
		"target_player_index": target_player_index,
		"amount": requested,
		"action_type": action_type,
		"suppressed_trigger_types": suppressed_trigger_types.duplicate(),
		"source_model_type": "black_rose" if attacker_id == -1 else "mage",
		"source_evocation": null,
		"event": null,
		"actual_damage": 0,
		"result_context": result_context
	})

	# Compatibility with EffectResolver handlers that use the return value to
	# register the damaged target. The authoritative value is written back to
	# result_context when the Damage frame completes.
	return requested

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
	var highest_power: int = black_rose_power

	for player in players:
		highest_power = max(
			highest_power,
			player.power
		)

	var new_moon: int = current_moon

	if highest_power >= $PowerBoard.third_moon_threshold:
		new_moon = 3

	elif highest_power >= $PowerBoard.second_moon_threshold:
		new_moon = 2

	else:
		new_moon = 1

	# La Moon non può regredire.
	if new_moon <= current_moon:
		return

	var old_moon: int = current_moon

	# Gestiamo anche l'eventuale salto diretto
	# Moon I -> Moon III.
	for moon in range(
		old_moon + 1,
		new_moon + 1
	):
		current_moon = moon

		print(
			"GAME: Moon changed to ",
			current_moon
		)

		$EventBoard.set_moon(
			current_moon
		)

		distribute_personal_spells_for_moon(
			current_moon
		)
	
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
	if evocation == null or amount <= 0:
		return 0

	if evocation.is_defeated():
		return 0

	var requested: int = min(amount, evocation.get_remaining_health())
	if requested <= 0:
		return 0

	var result_context: Dictionary = {}
	if not active_effect_context.is_empty():
		result_context = active_effect_context

	queue_resolution({
		"type": "evocation_damage",
		"step": "apply",
		"attacker_id": attacker_id,
		"evocation": evocation,
		"amount": requested,
		"suppressed_trigger_types": suppressed_trigger_types.duplicate(),
		"actual_damage": 0,
		"result_context": result_context
	})

	return requested

func process_game_event(
	event: GameEvent
) -> bool:
	if event == null:
		return true

	var triggered = triggered_spell_manager.get_triggered_spells(
		event,
		players
	)

	if triggered.is_empty():
		return true

	var ordered: Array = order_optional_triggers(triggered)
	if ordered.is_empty():
		return true

	_push_trigger_window(event, ordered)
	request_next_trigger_decision()

	return (
		not trigger_window_active
		and not waiting_for_player_input
	)

func handle_triggered_spell(
	trigger_data: Dictionary
) -> bool:
	var active_spell: ActiveSpellState = trigger_data.get("active_spell", null)
	var event: GameEvent = trigger_data.get("event", null)

	if active_spell == null or event == null:
		return false

	return queue_resolution({
		"type": "trigger_spell",
		"step": "start",
		"active_spell": active_spell,
		"event": event,
		"context": {}
	})

func handle_triggered_trap(
	active_spell: ActiveSpellState,
	event: GameEvent
):
	resolve_triggered_spell(active_spell, event)

func handle_triggered_protection(
	active_spell: ActiveSpellState,
	event: GameEvent
):
	resolve_triggered_spell(active_spell, event)

func handle_triggered_permanent(
	active_spell: ActiveSpellState,
	event: GameEvent
):
	resolve_triggered_spell(active_spell, event)

func resolve_triggered_spell(
	active_spell: ActiveSpellState,
	event: GameEvent
) -> bool:
	if active_spell == null or event == null:
		return false

	return queue_resolution({
		"type": "trigger_spell",
		"step": "start",
		"active_spell": active_spell,
		"event": event,
		"context": {}
	})

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

	if target_player_index < 0 \
	or target_player_index >= players.size():
		return 0

	if amount <= 0:
		return 0

	var capacity: int = players[target_player_index].mage.get_remaining_health()
	if capacity <= 0:
		return 0

	var requested: int = min(amount, capacity)
	var result_context: Dictionary = {}
	if not active_effect_context.is_empty():
		result_context = active_effect_context

	queue_resolution({
		"type": "damage",
		"step": "pre_event",
		"attacker_id": evocation.controller_id,
		"target_player_index": target_player_index,
		"amount": requested,
		"action_type": "evocation_attack",
		"suppressed_trigger_types": [],
		"source_model_type": "evocation",
		"source_evocation": evocation,
		"event": null,
		"actual_damage": 0,
		"result_context": result_context
	})

	return requested

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
	if spell == null:
		return false

	var caster_id: int = int(context.get("caster_id", -1))
	if caster_id < 0 or caster_id >= players.size():
		return false

	return queue_resolution({
		"type": "spell_resolution",
		"step": "prepare",
		"spell": spell,
		"use_dark_side": use_dark_side,
		"context": context,
		"sequence_index": 0
	})

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
	max_distance: int = 1
) -> bool:
	if player_index < 0 or player_index >= players.size() or max_distance < 0:
		return false

	var mage = players[player_index].mage
	if mage == null:
		return false

	var destination_coord: Vector2i = room_id_to_coord(destination_room_id)
	if destination_coord == Vector2i(9999, 9999):
		return false

	if mage.in_cell:
		var entrance_room_id: String = str(
			player_entrance_room_ids.get(player_index, mage.room_id)
		)
		if destination_room_id != entrance_room_id:
			print(
				"Player ", player_index + 1,
				" must enter through ", entrance_room_id
			)
			return false

		mage.room_id = destination_room_id
		mage.room_coord = destination_coord
		mage.in_cell = false
		print(
			"Player ", player_index + 1,
			" entered the Lodge through ", destination_room_id
		)
		return true

	if get_hex_distance(mage.room_coord, destination_coord) > max_distance:
		return false

	mage.room_id = destination_room_id
	mage.room_coord = destination_coord
	mage.in_cell = false
	print("Player ", player_index + 1, " moved to ", destination_room_id)
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

	var event := _make_evocation_lost_event(evocation, event_reason)
	process_game_event(event)

	# Direct removal handlers do not have an evocation-damage frame to resume.
	# Puppeteer is therefore applied here exactly once, regardless of whether
	# the loss event opened an optional trigger window. Stack-driven defeat
	# paths use _apply_puppeteer_after_evocation_loss() in their own frame and
	# do not call this helper.
	_apply_puppeteer_after_evocation_loss(evocation.room_id)

func activate_room(
	player_index: int,
	room_id: String,
	allow_reactivate_flipped: bool = false,
	context: Dictionary = {}
) -> bool:
	if player_index < 0 or player_index >= players.size():
		return false

	var room = get_room_by_id(room_id)
	if room == null:
		print("activate_room: Room not found: ", room_id)
		return false

	if not room.can_activate(allow_reactivate_flipped):
		print(
			"activate_room: ",
			room.room_name,
			" already activated this turn"
		)
		return false

	return queue_resolution({
		"type": "room_activation",
		"step": "prepare",
		"player_index": player_index,
		"room_id": room_id,
		"allow_reactivate_flipped": allow_reactivate_flipped,
		"context": context
	})

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
	if player_index < 0 or player_index >= players.size():
		return false

	var player = players[player_index]
	var ready_spell: ReadySpellState = player.get_next_ready_spell()
	if ready_spell == null:
		print("cast_next_ready_spell: no Ready Spell")
		return false

	return queue_resolution({
		"type": "spell_cast",
		"step": "start",
		"player_index": player_index,
		"ready_spell": ready_spell,
		"source": "ready",
		"context": context
	})

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
	controller_id: int = -1,
	context: Dictionary = {},
	strength_bonus: int = 0
) -> bool:
	if evocation == null:
		return false

	if controller_id < 0:
		controller_id = evocation.owner_id

	if controller_id < 0 or controller_id >= players.size():
		return false

	if evocation.is_defeated():
		return false

	return queue_resolution({
		"type": "evocation_activation",
		"step": "start",
		"evocation": evocation,
		"controller_id": controller_id,
		"context": context,
		"strength_bonus": strength_bonus,
		"move_index": 0
	})

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

	var mage = players[player_index].mage
	if mage == null:
		return false

	# A defeated Mage returns to THEIR Cell. room_id/room_coord while in
	# Cell therefore point to the entrance associated with that Cell.
	if player_entrance_room_ids.has(player_index):
		mage.room_id = str(player_entrance_room_ids[player_index])

	if player_entrance_room_coords.has(player_index):
		mage.room_coord = player_entrance_room_coords[player_index]

	mage.in_cell = true

	print(
		"Player ",
		player_index + 1,
		" Mage placed in Cell | entrance ",
		mage.room_id
	)

	if is_event_active("hidden_resources"):
		add_player_power(player_index, 1)
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

	if players.is_empty() or waiting_for_player_input:
		return false

	if not start_phase(PHASE_BLACK_ROSE):
		return false

	print("")
	print("==============================================")
	print("             BLACK ROSE PHASE")
	print("==============================================")

	current_phase_play_order = get_play_order()

	if current_phase_play_order.is_empty():
		return false

	var first_mage_index: int = (
		current_phase_play_order[0]
	)

	var drawing_player_index: int = (
		first_mage_index
		- 1
		+ players.size()
	) % players.size()

	var event_context: Dictionary = (
		context.duplicate(true)
	)

	event_context["game"] = self
	event_context["drawing_player_index"] = (
		drawing_player_index
	)
	event_context["play_order"] = (
		current_phase_play_order.duplicate()
	)

	# =====================================================
	# STEPS 1-3: EVENTS
	# =====================================================

	shift_active_events()

	var drawn_event: EventCardState = draw_event(
		drawing_player_index,
		event_context
	)

	if drawn_event == null:
		print(
			"Black Rose Phase: Event draw failed"
		)
		return false

	if not resolve_events_for_phase(
		PHASE_BLACK_ROSE,
		event_context
	):
		return false

	# =====================================================
	# STEPS 4-6: QUESTS
	# =====================================================

	black_rose_quest_step = 4
	black_rose_quest_cursor = 0

	return advance_black_rose_quest_steps()

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
	print("ROUND ", current_round, " COMPLETE")
	current_round += 1
	current_phase = ""
	cancelled_physical_action_players.clear()
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

	# A Mage in a Cell cannot cast Ready/Quick Spells or perform Fight/
	# Command. During the Action Phase the meaningful available Action is
	# a Physical Action that can move them out of the Cell (Explore).
	if player.mage != null and player.mage.in_cell:
		return (
			player.has_physical_action()
			and player.mage.speed > 0
		)

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
	return queue_resolution({
		"type": "explore",
		"step": "start",
		"player_index": player_index,
		"destination_room_ids": destination_room_ids.duplicate(),
		"activate_before": activate_room_before_movement,
		"activate_after": activate_room_after_movement,
		"move_index": 0,
		"context": context
	})

func perform_fight_action(
	player_index: int,
	target_player_index: int = -1,
	activate_room_first: bool = false,
	perform_attack: bool = true,
	perform_room_activation: bool = true,
	context: Dictionary = {}
) -> bool:
	return queue_resolution({
		"type": "fight",
		"step": "start",
		"player_index": player_index,
		"target_player_index": target_player_index,
		"activate_room_first": activate_room_first,
		"perform_attack": perform_attack,
		"perform_room_activation": perform_room_activation,
		"context": context
	})

func perform_command_action(
	player_index: int,
	evocation_index: int,
	context: Dictionary = {}
) -> bool:
	return queue_resolution({
		"type": "command",
		"step": "start",
		"player_index": player_index,
		"evocation_index": evocation_index,
		"context": context
	})

func cast_quick_spell(
	player_index: int,
	context: Dictionary = {}
) -> bool:
	if player_index < 0 or player_index >= players.size():
		return false

	var player = players[player_index]
	if player.quick_spell == null:
		print("cast_quick_spell: no Quick Spell")
		return false

	return queue_resolution({
		"type": "spell_cast",
		"step": "start",
		"player_index": player_index,
		"ready_spell": player.quick_spell,
		"source": "quick",
		"context": context
	})

func perform_player_action(
	player_index: int,
	action: Dictionary
) -> bool:
	if player_index < 0 or player_index >= players.size():
		return false
	if action.is_empty():
		return false

	var action_type: String = str(action.get("type", ""))
	var action_context: Dictionary = action.get("context", {})

	match action_type:
		"spell":
			return cast_next_ready_spell(player_index, action_context)
		"quick":
			return cast_quick_spell(player_index, action_context)
		"explore":
			return perform_explore_action(
				player_index,
				action.get("destination_room_ids", []),
				bool(action.get("activate_room_before_movement", false)),
				bool(action.get("activate_room_after_movement", false)),
				action_context
			)
		"fight":
			return perform_fight_action(
				player_index,
				int(action.get("target_player_index", -1)),
				bool(action.get("activate_room_first", false)),
				bool(action.get("perform_attack", true)),
				bool(action.get("perform_room_activation", true)),
				action_context
			)
		"command":
			return perform_command_action(
				player_index,
				int(action.get("evocation_index", -1)),
				action_context
			)
		_:
			print("perform_player_action: unknown action type ", action_type)
			return false

func resolve_player_activation(
	player_index: int,
	actions: Array
) -> bool:
	if not _validate_player_activation(player_index, actions):
		return false

	return queue_resolution({
		"type": "activation",
		"step": "actions",
		"player_index": player_index,
		"actions": actions.duplicate(true),
		"action_index": 0
	})

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
	if waiting_for_player_input:
		return false

	if not start_phase(PHASE_EVOCATION):
		return false

	print("")
	print("==============================================")
	print("              EVOCATION PHASE")
	print("==============================================")

	current_phase_play_order = get_play_order()
	if current_phase_play_order.is_empty():
		return false

	var phase_context: Dictionary = context.duplicate(true)
	phase_context["game"] = self
	phase_context["play_order"] = current_phase_play_order.duplicate()

	# Black Rose Evocations are not represented in the current game state.
	# Player Evocations are therefore the first represented activations.
	if not resolve_events_for_phase(PHASE_EVOCATION, phase_context):
		return false

	evocation_phase_cursor = 0
	return advance_evocation_phase()

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
	if not waiting_for_player_input:
		print("submit_action_activation: no input requested")
		return false

	if str(pending_input.get("type", "")) != "action_activation":
		print("submit_action_activation: wrong pending input type")
		return false

	var expected_player_index: int = int(
		pending_input.get("player_index", -1)
	)
	if player_index != expected_player_index:
		print("submit_action_activation: wrong player")
		return false

	if not _validate_player_activation(player_index, actions):
		return false

	clear_player_input()

	return queue_resolution({
		"type": "activation",
		"step": "actions",
		"player_index": player_index,
		"actions": actions.duplicate(true),
		"action_index": 0,
		"on_complete": "advance_action_phase"
	})

func finish_action_phase() -> bool:
	if current_phase != PHASE_ACTION or waiting_for_player_input:
		return false

	print("")
	print("==============================================")
	print("             ACTION PHASE COMPLETE")
	print("==============================================")
	print("")

	action_phase_cursor = 0
	action_phase_activation_round = 0
	current_phase_play_order.clear()
	return _complete_phase(PHASE_ACTION)

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
	if current_phase != PHASE_PREPARATION or waiting_for_player_input:
		return false

	print("")
	print("==============================================")
	print("          PREPARATION PHASE COMPLETE")
	print("==============================================")
	print("")

	preparation_phase_cursor = 0
	current_phase_play_order.clear()
	return _complete_phase(PHASE_PREPARATION)

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
	if current_phase != PHASE_STUDY or waiting_for_player_input:
		return false

	study_phase_cursor = 0
	study_drawn_cards.clear()
	current_phase_play_order.clear()

	print("")
	print("==============================================")
	print("             STUDY PHASE COMPLETE")
	print("==============================================")
	print("")

	return _complete_phase(PHASE_STUDY)

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
	if player_index < 0 or player_index >= players.size():
		return false
	if ready_spell == null or ready_spell.spell == null:
		return false

	return queue_resolution({
		"type": "spell_cast",
		"step": "start",
		"player_index": player_index,
		"ready_spell": ready_spell,
		"source": "external",
		"context": context
	})

func order_optional_triggers(
	triggers: Array
) -> Array:
	var result: Array = []
	var play_order: Array[int] = current_phase_play_order.duplicate()

	if play_order.is_empty():
		play_order = get_play_order()

	for player_index in play_order:
		for trigger_data in triggers:
			var active_spell: ActiveSpellState = trigger_data.get(
				"active_spell",
				null
			)
			if active_spell == null:
				continue
			if active_spell.owner_id != player_index:
				continue
			result.append(trigger_data)

	return result

func request_next_trigger_decision() -> bool:
	while trigger_window_active and not waiting_for_player_input:
		if trigger_window_cursor >= trigger_window_queue.size():
			finish_trigger_window()
			continue

		var current_data: Dictionary = trigger_window_queue[trigger_window_cursor]
		var current_spell: ActiveSpellState = current_data.get("active_spell", null)

		if current_spell == null or not current_spell.active:
			trigger_window_queue.remove_at(trigger_window_cursor)
			continue

		var spell_type: String = current_spell.get_spell_type()
		var optional: bool = spell_type == "trap" or spell_type == "protection"

		# Permanents are mandatory. Remove them from this trigger queue before
		# pushing their resolution so they cannot be selected twice.
		if not optional:
			trigger_window_queue.remove_at(trigger_window_cursor)
			handle_triggered_spell(current_data)
			return true

		var player_index: int = current_spell.owner_id
		var options: Array = []

		for i in range(trigger_window_cursor, trigger_window_queue.size()):
			var trigger_data: Dictionary = trigger_window_queue[i]
			var active_spell: ActiveSpellState = trigger_data.get("active_spell", null)
			if active_spell == null:
				continue
			if active_spell.owner_id != player_index:
				break
			var candidate_type: String = active_spell.get_spell_type()
			if candidate_type != "trap" and candidate_type != "protection":
				break
			if not active_spell.active:
				continue

			options.append({
				"queue_index": i,
				"spell_id": active_spell.spell.id,
				"spell_name": active_spell.spell.card_name,
				"spell_type": candidate_type
			})

		if options.is_empty():
			trigger_window_queue.remove_at(trigger_window_cursor)
			continue

		return request_player_input({
			"type": "trigger_decision",
			"phase": current_phase,
			"player_index": player_index,
			"optional": true,
			"options": options
		})

	return true

func submit_trigger_decision(
	player_index: int,
	queue_index: int = -1
) -> bool:
	if not trigger_window_active or not waiting_for_player_input:
		return false

	if str(pending_input.get("type", "")) != "trigger_decision":
		return false

	if player_index != int(pending_input.get("player_index", -1)):
		return false

	var options: Array = pending_input.get("options", [])

	if queue_index == -1:
		# Pass declines all currently offered optional triggers for this owner,
		# but leaves later trigger opportunities / other players untouched.
		var indices_to_remove: Array[int] = []
		for option_value in options:
			indices_to_remove.append(int(option_value.get("queue_index", -1)))
		indices_to_remove.sort()
		indices_to_remove.reverse()
		for idx in indices_to_remove:
			if idx >= 0 and idx < trigger_window_queue.size():
				trigger_window_queue.remove_at(idx)

		clear_player_input()
		request_next_trigger_decision()
		if waiting_for_player_input:
			return true
		return process_resolution_stack()

	var valid_option: bool = false
	for option_value in options:
		if int(option_value.get("queue_index", -1)) == queue_index:
			valid_option = true
			break

	if not valid_option:
		return false

	if queue_index < 0 or queue_index >= trigger_window_queue.size():
		return false

	var trigger_data: Dictionary = trigger_window_queue[queue_index]
	trigger_window_queue.remove_at(queue_index)
	clear_player_input()

	handle_triggered_spell(trigger_data)
	return process_resolution_stack()

func finish_trigger_window() -> bool:
	if not trigger_window_active:
		return true

	if waiting_for_player_input:
		return false

	print("Trigger window complete")

	if not trigger_window_stack.is_empty():
		var previous: Dictionary = trigger_window_stack.pop_back()
		trigger_window_event = previous.get("event", null)
		trigger_window_queue = previous.get("queue", [])
		trigger_window_cursor = int(previous.get("cursor", 0))
		trigger_window_active = true
		return true

	trigger_window_active = false
	trigger_window_event = null
	trigger_window_queue.clear()
	trigger_window_cursor = 0
	return true

func queue_resolution(
	resolution: Dictionary
) -> bool:
	if resolution.is_empty() or not resolution.has("type"):
		return false

	var frame: Dictionary = resolution.duplicate(false)
	frame["_rid"] = next_resolution_id
	next_resolution_id += 1
	resolution_stack.push_front(frame)

	if processing_resolution_stack:
		return true

	return process_resolution_stack()

func process_resolution_stack() -> bool:
	if processing_resolution_stack:
		return true

	processing_resolution_stack = true

	while true:
		if waiting_for_player_input:
			processing_resolution_stack = false
			return true

		if trigger_window_active:
			request_next_trigger_decision()
			if waiting_for_player_input:
				processing_resolution_stack = false
				return true

		# request_next_trigger_decision may have queued a mandatory trigger.
		if resolution_stack.is_empty():
			if trigger_window_active:
				continue
			processing_resolution_stack = false
			return true

		var frame: Dictionary = resolution_stack[0]
		var frame_id: int = int(frame.get("_rid", -1))
		var resolution_type: String = str(frame.get("type", ""))
		var completed: bool = false

		match resolution_type:
			"damage":
				completed = process_damage_resolution(frame)
			"evocation_damage":
				completed = process_evocation_damage_resolution(frame)
			"effect_sequence":
				completed = process_effect_sequence_resolution(frame)
			"spell_resolution":
				completed = process_spell_resolution_frame(frame)
			"spell_cast":
				completed = process_spell_cast_resolution(frame)
			"trigger_spell":
				completed = process_trigger_spell_resolution(frame)
			"room_activation":
				completed = process_room_activation_resolution(frame)
			"activation":
				completed = process_activation_resolution(frame)
			"explore":
				completed = process_explore_resolution(frame)
			"fight":
				completed = process_fight_resolution(frame)
			"command":
				completed = process_command_resolution(frame)
			"evocation_activation":
				completed = process_evocation_activation_resolution(frame)
			"evocation_phase_player":
				completed = process_evocation_phase_player_resolution(frame)
			_:
				print("Unsupported resolution type: ", resolution_type)
				resolution_stack.pop_front()
				processing_resolution_stack = false
				return false

		if waiting_for_player_input:
			processing_resolution_stack = false
			return true

		if resolution_stack.is_empty():
			continue

		# A nested resolution was pushed in front of this frame.
		if int(resolution_stack[0].get("_rid", -2)) != frame_id:
			continue

		if completed:
			var finished_frame: Dictionary = resolution_stack.pop_front()
			_handle_resolution_completion(finished_frame)
			continue

		# The frame advanced one internal step. If it did not create a nested
		# resolution or input request, simply run its next step now.
		continue
	return true

func process_damage_resolution(
	resolution: Dictionary
) -> bool:
	var step: String = str(resolution.get("step", "pre_event"))

	match step:
		"pre_event":
			var target_player_index: int = int(resolution.get("target_player_index", -1))
			if target_player_index < 0 or target_player_index >= players.size():
				_sync_damage_result_context(resolution, 0)
				return true

			var target_mage = players[target_player_index].mage
			var requested: int = min(
				int(resolution.get("amount", 0)),
				target_mage.get_remaining_health()
			)
			if requested <= 0:
				_sync_damage_result_context(resolution, 0)
				return true

			resolution["amount"] = requested
			var event := GameEvent.new("damage_about_to_be_inflicted")
			_fill_damage_event_source(event, resolution)
			event.target_model_type = "mage"
			event.target_player_index = target_player_index
			event.target_room_id = target_mage.room_id
			event.amount = requested
			event.action_type = str(resolution.get("action_type", ""))
			event.suppressed_trigger_types = _to_string_array(
				resolution.get("suppressed_trigger_types", [])
			)

			resolution["event"] = event
			resolution["step"] = "after_pre_event"

			if not process_game_event(event):
				return false
			return false

		"after_pre_event":
			var event: GameEvent = resolution.get("event", null)
			if event == null or event.cancelled:
				_sync_damage_result_context(resolution, 0)
				return true

			resolution["amount"] = max(0, int(event.amount))
			resolution["target_player_index"] = event.target_player_index

			if int(resolution["amount"]) <= 0:
				_sync_damage_result_context(resolution, 0)
				return true

			if event.redirected_evocation != null:
				resolution["redirected_evocation"] = event.redirected_evocation
				resolution["step"] = "apply_redirect"
				return false

			resolution["step"] = "apply_damage"
			return false

		"apply_redirect":
			var redirected_evocation = resolution.get("redirected_evocation", null)
			if redirected_evocation == null or redirected_evocation.is_defeated():
				_sync_damage_result_context(resolution, 0)
				return true

			var amount: int = min(
				int(resolution.get("amount", 0)),
				redirected_evocation.get_remaining_health()
			)
			var attacker_id: int = int(resolution.get("attacker_id", -1))
			var cubes: int = take_owner_cubes(attacker_id, amount)
			if cubes <= 0:
				_sync_damage_result_context(resolution, 0)
				return true

			var was_defeated: bool = redirected_evocation.is_defeated()
			var dealt: int = redirected_evocation.add_damage(attacker_id, cubes)
			resolution["actual_damage"] = dealt
			_sync_damage_result_context(resolution, dealt)

			print(
				"Damage redirected: attacker ", attacker_id,
				" -> Evocation ", redirected_evocation.evocation_name,
				" | ", dealt, " damage"
			)

			if not was_defeated and redirected_evocation.is_defeated():
				var defeat_event := _make_evocation_lost_event(
					redirected_evocation,
					"defeated"
				)
				resolution["step"] = "after_redirect_defeat"
				if not process_game_event(defeat_event):
					return false
				_apply_puppeteer_after_evocation_loss(redirected_evocation.room_id)
				return true

			return true

		"after_redirect_defeat":
			var redirected_evocation = resolution.get("redirected_evocation", null)
			if redirected_evocation != null:
				_apply_puppeteer_after_evocation_loss(redirected_evocation.room_id)
			return true

		"apply_damage":
			var target_player_index: int = int(resolution.get("target_player_index", -1))
			if target_player_index < 0 or target_player_index >= players.size():
				_sync_damage_result_context(resolution, 0)
				return true

			var target_mage = players[target_player_index].mage
			var amount: int = min(
				int(resolution.get("amount", 0)),
				target_mage.get_remaining_health()
			)
			if amount <= 0:
				_sync_damage_result_context(resolution, 0)
				return true

			var attacker_id: int = int(resolution.get("attacker_id", -1))
			var cubes_available: int = take_owner_cubes(attacker_id, amount)
			if cubes_available <= 0:
				_sync_damage_result_context(resolution, 0)
				return true

			resolution["was_defeated"] = target_mage.is_defeated()
			var damage_dealt: int = target_mage.add_damage(attacker_id, cubes_available)
			resolution["actual_damage"] = damage_dealt
			_sync_damage_result_context(resolution, damage_dealt)
			_refresh_damage_boards(target_player_index, attacker_id)

			print(
				"Damage: attacker ", attacker_id,
				" -> Player ", target_player_index + 1,
				" | ", damage_dealt,
				" damage | Target HP: ",
				target_mage.get_remaining_health(), "/", target_mage.health
			)

			if damage_dealt <= 0:
				return true

			resolution["step"] = "post_event"
			return false

		"post_event":
			var post_event := GameEvent.new("damage_inflicted")
			_fill_damage_event_source(post_event, resolution)
			var target_player_index: int = int(resolution.get("target_player_index", -1))
			post_event.target_model_type = "mage"
			post_event.target_player_index = target_player_index
			post_event.target_room_id = players[target_player_index].mage.room_id
			post_event.amount = int(resolution.get("actual_damage", 0))
			post_event.action_type = str(resolution.get("action_type", ""))
			post_event.suppressed_trigger_types = _to_string_array(
				resolution.get("suppressed_trigger_types", [])
			)
			resolution["step"] = "after_post_event"
			if not process_game_event(post_event):
				return false
			return false

		"after_post_event":
			var target_player_index: int = int(resolution.get("target_player_index", -1))
			var target_mage = players[target_player_index].mage
			var was_defeated: bool = bool(resolution.get("was_defeated", false))

			if not was_defeated and target_mage.is_defeated():
				var defeat_event := GameEvent.new("mage_defeated")
				_fill_damage_event_source(defeat_event, resolution)
				defeat_event.target_model_type = "mage"
				defeat_event.target_player_index = target_player_index
				defeat_event.target_room_id = target_mage.room_id
				defeat_event.amount = int(resolution.get("actual_damage", 0))
				defeat_event.action_type = str(resolution.get("action_type", ""))
				resolution["step"] = "after_defeat_event"
				if not process_game_event(defeat_event):
					return false
				return false

			return true

		"after_defeat_event":
			var target_player_index: int = int(resolution.get("target_player_index", -1))
			# A defeated Mage is sent to their Cell after defeat-triggered Effects
			# have had their window. Physical Actions are not resumed afterwards.
			cancelled_physical_action_players[target_player_index] = true
			place_mage_in_cell(target_player_index)
			return true

		_:
			print("Unknown Damage resolution step: ", step)
			return true

# =============================================================================
# INTEGRATED RESOLUTION / PHASE ENGINE
# =============================================================================

func _to_string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result


func _push_trigger_window(event: GameEvent, queue: Array):
	if trigger_window_active:
		trigger_window_stack.append({
			"event": trigger_window_event,
			"queue": trigger_window_queue,
			"cursor": trigger_window_cursor
		})

	trigger_window_active = true
	trigger_window_event = event
	trigger_window_queue = queue.duplicate(false)
	trigger_window_cursor = 0


func _make_evocation_lost_event(
	evocation: EvocationState,
	reason: String
) -> GameEvent:
	var event := GameEvent.new("evocation_defeated_or_removed")
	event.target_model_type = "evocation"
	event.target_player_index = evocation.owner_id
	event.target_evocation = evocation
	event.target_room_id = evocation.room_id
	event.action_type = reason
	return event


func _apply_puppeteer_after_evocation_loss(room_id: String):
	if is_event_active("puppeteer"):
		place_instability(-1, room_id, 1)


func _fill_damage_event_source(
	event: GameEvent,
	resolution: Dictionary
):
	var attacker_id: int = int(resolution.get("attacker_id", -1))
	var source_model_type: String = str(
		resolution.get(
			"source_model_type",
			"black_rose" if attacker_id == -1 else "mage"
		)
	)

	event.source_model_type = source_model_type
	event.source_player_index = attacker_id

	if source_model_type == "evocation":
		var evocation = resolution.get("source_evocation", null)
		event.source_evocation = evocation
		if evocation != null:
			event.source_room_id = evocation.room_id
		return

	if source_model_type == "mage" \
	and attacker_id >= 0 \
	and attacker_id < players.size():
		event.source_room_id = players[attacker_id].mage.room_id
	else:
		event.source_room_id = ""


func _refresh_damage_boards(
	target_player_index: int,
	attacker_id: int
):
	if target_player_index >= 0 \
	and target_player_index < player_boards.size():
		player_boards[target_player_index].refresh()

	if attacker_id >= 0 and attacker_id < player_boards.size():
		player_boards[attacker_id].refresh()


func _sync_damage_result_context(
	resolution: Dictionary,
	actual_damage: int
):
	var context: Dictionary = resolution.get(
		"result_context",
		{}
	)

	if context.is_empty():
		return

	var target_player_index: int = int(
		resolution.get(
			"target_player_index",
			-1
		)
	)

	var attacker_id: int = int(
		resolution.get(
			"attacker_id",
			-999
		)
	)

	context["last_damage_dealt"] = actual_damage
	context["last_damage_attacker_id"] = attacker_id

	context["last_damage_source_model_type"] = str(
		resolution.get(
			"source_model_type",
			""
		)
	)

	context["last_damage_target_player_index"] = (
		target_player_index
	)

	# IMPORTANT:
	# true soltanto se il target è sconfitto DOPO
	# la risoluzione effettiva del Damage.
	if target_player_index >= 0 \
	and target_player_index < players.size():

		context["last_damage_defeated_target"] = (
			actual_damage > 0
			and players[
				target_player_index
			].mage.is_defeated()
		)

	else:
		context["last_damage_defeated_target"] = false

	# Corregge la registrazione ottimistica fatta
	# dall'EffectResolver nel caso in cui una Protection
	# abbia ridotto/annullato il Damage.
	var damaged_models: Array = context.get(
		"models_damaged_by_effect",
		[]
	)

	if actual_damage <= 0:

		for i in range(
			damaged_models.size() - 1,
			-1,
			-1
		):

			var model: Dictionary = (
				damaged_models[i]
			)

			if str(
				model.get("type", "")
			) == "mage" \
			and int(
				model.get(
					"player_index",
					-1
				)
			) == target_player_index:

				damaged_models.remove_at(i)

		context["models_damaged_by_effect"] = (
			damaged_models
		)

		return

	context["last_damaged_model_type"] = "mage"

	context["last_damaged_player_index"] = (
		target_player_index
	)

func process_evocation_damage_resolution(
	resolution: Dictionary
) -> bool:
	var step: String = str(resolution.get("step", "apply"))
	var evocation: EvocationState = resolution.get("evocation", null)

	if evocation == null:
		return true

	match step:
		"apply":
			if evocation.is_defeated():
				_sync_evocation_damage_result_context(resolution, 0)
				return true

			var attacker_id: int = int(resolution.get("attacker_id", -1))
			var amount: int = min(
				int(resolution.get("amount", 0)),
				evocation.get_remaining_health()
			)
			if amount <= 0:
				_sync_evocation_damage_result_context(resolution, 0)
				return true

			var was_defeated: bool = evocation.is_defeated()
			var damage_dealt: int = evocation.add_damage(attacker_id, amount)
			resolution["actual_damage"] = damage_dealt
			_sync_evocation_damage_result_context(resolution, damage_dealt)

			print(
				"Damage: attacker ", attacker_id,
				" -> Evocation ", evocation.evocation_name,
				" | ", damage_dealt, " damage | HP: ",
				evocation.get_remaining_health(), "/", evocation.health
			)

			if not was_defeated and evocation.is_defeated():
				resolution["step"] = "after_defeat_event"
				var event := _make_evocation_lost_event(evocation, "defeated")
				if not process_game_event(event):
					return false
				return false

			return true

		"after_defeat_event":
			_apply_puppeteer_after_evocation_loss(evocation.room_id)
			return true

		_:
			return true


func _sync_evocation_damage_result_context(
	resolution: Dictionary,
	actual_damage: int
):
	var context: Dictionary = resolution.get("result_context", {})
	if context.is_empty():
		return

	var evocation = resolution.get("evocation", null)
	context["last_damage_dealt"] = actual_damage

	if actual_damage <= 0 or evocation == null:
		return

	context["last_damaged_model_type"] = "evocation"
	context["last_damaged_evocation"] = evocation


func process_effect_sequence_resolution(
	resolution: Dictionary
) -> bool:

	var effects: Array = resolution.get(
		"effects",
		[]
	)

	var index: int = int(
		resolution.get(
			"index",
			0
		)
	)

	if index >= effects.size():
		return true


	var effect: Dictionary = effects[index]

	resolution["index"] = index + 1


	var context: Dictionary = resolution.get(
		"context",
		{}
	)

	var resolver_kind: String = str(
		resolution.get(
			"resolver_kind",
			"spell"
		)
	)


	active_effect_context = context

	var success: bool = false


	match resolver_kind:

		"spell":
			success = effect_resolver.resolve_effect(
				effect,
				context
			)

		"room":
			success = room_effect_resolver.resolve_effect(
				effect,
				context
			)

		_:
			print(
				"Unknown resolver_kind: ",
				resolver_kind
			)

			success = false


	active_effect_context = {}


	if not success:

		print(
			"Effect resolution failed | kind ",
			resolver_kind,
			" | effect ",
			str(effect.get("type", ""))
		)

		resolution["failed"] = true

		return true


	# =====================================================
	# QUEST EVENT
	#
	# Only successfully resolved Spell Effects generate
	# this Quest event.
	#
	# Room Effects are intentionally excluded.
	# =====================================================

	if resolver_kind == "spell":

		var caster_id: int = int(
			context.get(
				"caster_id",
				-1
			)
		)

		if (
			caster_id >= 0
			and caster_id < players.size()
		):

			var quest_event: Dictionary = {
				"type": "effect_resolved",
				"player_index": caster_id,
				"effect_type": str(
					effect.get(
						"type",
						""
					)
				),
				"element": str(
					context.get(
						"spell_element",
						""
					)
				),
				"effect": effect
			}

			quest_manager.process_event(
				self,
				quest_event
			)


	return (
		int(
			resolution.get(
				"index",
				0
			)
		)
		>= effects.size()
	)

func process_spell_resolution_frame(
	resolution: Dictionary
) -> bool:

	var spell: SpellCardState = resolution.get(
		"spell",
		null
	)

	if spell == null:
		return true


	var use_dark_side: bool = bool(
		resolution.get(
			"use_dark_side",
			false
		)
	)

	var context: Dictionary = resolution.get(
		"context",
		{}
	)

	var caster_id: int = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= players.size():
		return true


	match str(
		resolution.get(
			"step",
			"prepare"
		)
	):

		# =================================================
		# PREPARE
		# =================================================

		"prepare":

			var side: Dictionary = spell.get_side(
				use_dark_side
			)


			context["spell_target_type"] = str(
				side.get(
					"target",
					""
				)
			)

			context["spell_range"] = side.get(
				"range",
				null
			)

			# Used by Quest tasks and other systems that
			# need to know which element is currently
			# being resolved.
			context["spell_element"] = str(
				side.get(
					"element",
					""
				)
			)

			context["spell_id"] = spell.id

			context["models_damaged_by_effect"] = []


			# ---------------------------------------------
			# ENHANCEMENT
			# ---------------------------------------------

			var enhancement: Dictionary = side.get(
				"enhancement",
				{}
			)

			var enhancement_active: bool = false


			if not enhancement.is_empty():

				enhancement_active = (
					can_apply_enhancement(
						caster_id,
						enhancement.get(
							"requires",
							[]
						)
					)
				)


			context["enhancement_active"] = (
				enhancement_active
			)


			# ---------------------------------------------
			# RESOLUTION ORDER
			# ---------------------------------------------

			var sequences: Array = []

			var resolution_order: Array = side.get(
				"resolution_order",
				[
					"base",
					"enhancement"
				]
			)


			for order_step in resolution_order:

				match str(order_step):

					"base":

						sequences.append(
							spell.get_effects(
								use_dark_side
							)
						)


					"enhancement":

						if enhancement_active:

							sequences.append(
								enhancement.get(
									"effects",
									[]
								)
							)


					_:

						print(
							"Unknown spell resolution step: ",
							order_step
						)


			resolution["sequences"] = sequences
			resolution["sequence_index"] = 0
			resolution["step"] = "next_sequence"

			return false


		# =================================================
		# NEXT EFFECT SEQUENCE
		# =================================================

		"next_sequence":

			var sequences: Array = resolution.get(
				"sequences",
				[]
			)

			var sequence_index: int = int(
				resolution.get(
					"sequence_index",
					0
				)
			)


			if sequence_index >= sequences.size():

				resolution["step"] = "reveal"

				return false


			resolution["sequence_index"] = (
				sequence_index + 1
			)


			queue_resolution(
				{
					"type": "effect_sequence",
					"resolver_kind": "spell",
					"effects": sequences[
						sequence_index
					],
					"index": 0,
					"context": context
				}
			)


			return false


		# =================================================
		# REVEAL
		# =================================================

		"reveal":

			var revealed = RevealedSpellState.new(
				spell,
				use_dark_side
			)

			players[
				caster_id
			].add_revealed_spell(
				revealed
			)

			# A newly Revealed Spell may satisfy a
			# state-based Quest.
			quest_manager.check_state_quests(
				self,
				caster_id
			)

			return true


		_:
			return true


func process_spell_cast_resolution(
	resolution: Dictionary
) -> bool:
	var player_index: int = int(resolution.get("player_index", -1))
	if player_index < 0 or player_index >= players.size():
		return true

	var player = players[player_index]
	var ready_spell: ReadySpellState = resolution.get("ready_spell", null)
	if ready_spell == null or ready_spell.spell == null:
		return true

	var spell: SpellCardState = ready_spell.spell
	var use_dark_side: bool = ready_spell.use_dark_side
	var source: String = str(resolution.get("source", "external"))
	var context: Dictionary = resolution.get("context", {}).duplicate(true)

	match str(resolution.get("step", "start")):
		"start":
			if player.mage.in_cell:
				print("A Mage in Cell cannot cast a Ready/Quick Spell")
				return true

			context["game"] = self
			context["caster_id"] = player_index
			context["caster_room_id"] = player.mage.room_id
			resolution["context"] = context

			var side: Dictionary = spell.get_side(use_dark_side)
			var spell_type: String = str(side.get("type", ""))

			if spell_type != "combat" \
			and spell_type != "contingency" \
			and spell_type != "trap" \
			and spell_type != "protection":
				print("Unsupported Spell type: ", spell_type)
				return true

			# The card leaves its prepared slot only after the Cast Action itself
			# has been validated. This avoids consuming a prepared card on an
			# invalid/unsupported cast request.
			if source == "ready":
				if player.get_next_ready_spell() != ready_spell:
					return true
				player.remove_next_ready_spell()
			elif source == "quick":
				if player.quick_spell != ready_spell:
					return true
				player.quick_spell = null

			if spell_type == "trap" or spell_type == "protection":
				var target_player_index: int = int(
					context.get("target_player_index", -1)
				)
				var active_spell := ActiveSpellState.new(
					spell,
					player_index,
					use_dark_side,
					target_player_index
				)
				for key in context:
					if key != "game":
						active_spell.context[key] = context[key]
				player.add_active_spell(active_spell)
				print(
					"Player ", player_index + 1,
					" activates ", spell.card_name,
					" [", spell_type, "]"
				)
				return true

			if not resolve_spell_reveal_instability(player_index, spell):
				return true

			resolution["step"] = "after_spell"
			queue_resolution({
				"type": "spell_resolution",
				"step": "prepare",
				"spell": spell,
				"use_dark_side": use_dark_side,
				"context": context,
				"sequence_index": 0
			})
			return false

		"after_spell":
			print(
				"Player ", player_index + 1,
				" cast ", spell.card_name,
				" | side: ", "Dark" if use_dark_side else "Light"
			)
			return true

		_:
			return true


func process_trigger_spell_resolution(
	resolution: Dictionary
) -> bool:
	var active_spell: ActiveSpellState = resolution.get("active_spell", null)
	var event: GameEvent = resolution.get("event", null)
	if active_spell == null or event == null:
		return true

	var owner_id: int = active_spell.owner_id
	if owner_id < 0 or owner_id >= players.size():
		return true

	match str(resolution.get("step", "start")):
		"start":
			var spell_type: String = active_spell.get_spell_type()
			print(
				spell_type.to_upper(), " TRIGGERED: ",
				active_spell.spell.card_name,
				" | Player ", owner_id + 1
			)

			# Trap/Protection stop being Active as soon as they are revealed. This
			# prevents a nested event from triggering the same card again.
			if spell_type == "trap" or spell_type == "protection":
				active_spell.active = false
				players[owner_id].active_spells.erase(active_spell)

			var context: Dictionary = {
				"game": self,
				"caster_id": owner_id,
				"caster_room_id": players[owner_id].mage.room_id,
				"trigger_event": event,
				"marked_player_index": active_spell.target_player_index,
				"triggering_model_type": event.source_model_type,
				"triggering_player_index": event.source_player_index,
				"triggering_evocation": event.source_evocation,
				"triggering_room_id": event.source_room_id,
				"trigger_damage_amount": event.amount,
				"trigger_evocation": event.target_evocation,
				"trigger_evocation_owner": event.target_player_index,
				"trigger_evocation_room_id": event.target_room_id,
				"trigger_evocation_reason": event.action_type
			}
			for key in active_spell.context:
				context[key] = active_spell.context[key]

			resolution["context"] = context

			if spell_type == "trap" or spell_type == "protection":
				resolve_spell_reveal_instability(owner_id, active_spell.spell)

			resolution["step"] = "after_effects"
			queue_resolution({
				"type": "effect_sequence",
				"resolver_kind": "spell",
				"effects": active_spell.get_effects(),
				"index": 0,
				"context": context
			})
			return false

		"after_effects":
			var context: Dictionary = resolution.get("context", {})
			for key in context:
				if key != "game" and key != "trigger_event":
					active_spell.context[key] = context[key]

			var spell_type: String = active_spell.get_spell_type()
			if spell_type == "trap" or spell_type == "protection":
				var revealed := RevealedSpellState.new(
					active_spell.spell,
					active_spell.use_dark_side
				)
				players[owner_id].add_revealed_spell(revealed)

			print("Triggered spell resolved: ", active_spell.spell.card_name)
			return true

		_:
			return true


func process_room_activation_resolution(
	resolution: Dictionary
) -> bool:
	var player_index: int = int(resolution.get("player_index", -1))
	var room_id: String = str(resolution.get("room_id", ""))
	var room = get_room_by_id(room_id)
	if room == null or player_index < 0 or player_index >= players.size():
		return true

	match str(resolution.get("step", "prepare")):
		"prepare":
			if not room.can_activate(
				bool(resolution.get("allow_reactivate_flipped", false))
			):
				return true

			var room_context: Dictionary = resolution.get("context", {}).duplicate(true)
			room_context["game"] = self
			room_context["player_index"] = player_index
			room_context["caster_id"] = player_index
			room_context["room"] = room
			room_context["room_id"] = room.get_room_id()
			if not room_context.has("target_room_id"):
				room_context["target_room_id"] = room.get_room_id()

			resolution["context"] = room_context
			resolution["step"] = "after_effects"
			queue_resolution({
				"type": "effect_sequence",
				"resolver_kind": "room",
				"effects": room.get_effects(),
				"index": 0,
				"context": room_context
			})
			return false

		"after_effects":
			room.mark_activated()
			print(
				"Player ", player_index + 1,
				" activated ", room.room_name,
				" [", room.get_current_side_name(), "]"
			)
			return true

		_:
			return true


func _validate_player_activation(
	player_index: int,
	actions: Array
) -> bool:
	if player_index < 0 or player_index >= players.size():
		return false

	if actions.is_empty() or actions.size() > 2:
		return false

	var normal_spell_count: int = 0
	var quick_spell_count: int = 0

	for action_value in actions:
		if not action_value is Dictionary:
			return false
		var action_type: String = str(action_value.get("type", ""))
		if action_type == "spell":
			normal_spell_count += 1
		elif action_type == "quick":
			quick_spell_count += 1

	if normal_spell_count > 1 or quick_spell_count > 1:
		return false

	# Quick + numbered Ready is legal, but Quick still consumes the second
	# Action slot. Two numbered Ready Spells are not legal in one Activation.
	return true


func process_activation_resolution(
	resolution: Dictionary
) -> bool:
	var player_index: int = int(resolution.get("player_index", -1))
	var actions: Array = resolution.get("actions", [])
	var action_index: int = int(resolution.get("action_index", 0))

	if player_index < 0 or player_index >= players.size():
		return true

	if action_index >= actions.size():
		print("Player ", player_index + 1, " Activation complete")
		return true

	var action: Dictionary = actions[action_index]
	resolution["action_index"] = action_index + 1
	if not perform_player_action(player_index, action):
		print("Activation Action failed: ", action.get("type", ""))
		return true

	return false


func _physical_action_cancelled(player_index: int) -> bool:
	if not bool(cancelled_physical_action_players.get(player_index, false)):
		return false
	cancelled_physical_action_players.erase(player_index)
	return true


func process_explore_resolution(
	resolution: Dictionary
) -> bool:
	var player_index: int = int(resolution.get("player_index", -1))
	if player_index < 0 or player_index >= players.size():
		return true

	if _physical_action_cancelled(player_index):
		print("Explore interrupted by Mage defeat")
		return true

	var player = players[player_index]
	var context: Dictionary = resolution.get("context", {})

	match str(resolution.get("step", "start")):
		"start":
			if not player.has_physical_action():
				return true

			var path: Array = resolution.get("destination_room_ids", [])
			if path.size() > player.mage.speed:
				return true

			if bool(resolution.get("activate_before", false)) \
			and bool(resolution.get("activate_after", false)):
				return true

			if not player.exhaust_physical_action():
				return true

			if bool(resolution.get("activate_before", false)):
				if player.mage.in_cell:
					return true
				resolution["step"] = "move"
				activate_room(player_index, player.mage.room_id, false, context)
				return false

			resolution["step"] = "move"
			return false

		"move":
			var path: Array = resolution.get("destination_room_ids", [])
			var move_index: int = int(resolution.get("move_index", 0))
			if move_index < path.size():
				if not move_mage_to_room_id(player_index, str(path[move_index]), 1):
					return true
				resolution["move_index"] = move_index + 1
				return false

			if bool(resolution.get("activate_after", false)):
				if player.mage.in_cell:
					return true
				resolution["step"] = "done"
				activate_room(player_index, player.mage.room_id, false, context)
				return false

			resolution["step"] = "done"
			return false

		"done":
			print("Player ", player_index + 1, " performed Explore")
			return true

		_:
			return true


func process_fight_resolution(
	resolution: Dictionary
) -> bool:
	var player_index: int = int(resolution.get("player_index", -1))
	if player_index < 0 or player_index >= players.size():
		return true

	if _physical_action_cancelled(player_index):
		print("Fight interrupted by Mage defeat")
		return true

	var player = players[player_index]
	var context: Dictionary = resolution.get("context", {})

	match str(resolution.get("step", "start")):
		"start":
			if player.mage.in_cell or not player.has_physical_action():
				return true
			if not player.exhaust_physical_action():
				return true

			if bool(resolution.get("perform_room_activation", true)) \
			and bool(resolution.get("activate_room_first", false)):
				resolution["step"] = "attack"
				activate_room(player_index, player.mage.room_id, false, context)
				return false

			resolution["step"] = "attack"
			return false

		"attack":
			if bool(resolution.get("perform_attack", true)):
				var target_player_index: int = int(
					resolution.get("target_player_index", -1)
				)
				if target_player_index < 0 or target_player_index >= players.size():
					return true
				if target_player_index == player_index:
					return true

				var target = players[target_player_index]
				if target.mage.in_cell or target.mage.room_id != player.mage.room_id:
					return true

				resolution["step"] = "room_after"
				deal_damage(
					player_index,
					target_player_index,
					player.mage.strength,
					"physical_attack"
				)
				return false

			resolution["step"] = "room_after"
			return false

		"room_after":
			if bool(resolution.get("perform_room_activation", true)) \
			and not bool(resolution.get("activate_room_first", false)):
				resolution["step"] = "done"
				activate_room(player_index, player.mage.room_id, false, context)
				return false

			resolution["step"] = "done"
			return false

		"done":
			print("Player ", player_index + 1, " performed Fight")
			return true

		_:
			return true


func process_command_resolution(
	resolution: Dictionary
) -> bool:
	var player_index: int = int(resolution.get("player_index", -1))
	if player_index < 0 or player_index >= players.size():
		return true

	if _physical_action_cancelled(player_index):
		print("Command interrupted by Mage defeat")
		return true

	var player = players[player_index]
	match str(resolution.get("step", "start")):
		"start":
			if player.mage.in_cell or not player.has_physical_action():
				return true
			var evocation_index: int = int(resolution.get("evocation_index", -1))
			if evocation_index < 0 or evocation_index >= player.evocations.size():
				return true
			if not player.exhaust_physical_action():
				return true

			var evocation: EvocationState = player.evocations[evocation_index]
			resolution["step"] = "done"
			activate_evocation(
				evocation,
				player_index,
				resolution.get("context", {})
			)
			return false

		"done":
			print("Player ", player_index + 1, " performed Command")
			return true

		_:
			return true


func process_evocation_activation_resolution(
	resolution: Dictionary
) -> bool:
	var evocation: EvocationState = resolution.get("evocation", null)
	if evocation == null or evocation.is_defeated():
		return true

	var controller_id: int = int(resolution.get("controller_id", evocation.owner_id))
	var context: Dictionary = resolution.get("context", {})
	var strength_bonus: int = int(resolution.get("strength_bonus", 0))
	var activation_strength: int = evocation.strength + strength_bonus
	var attack_timing: String = str(context.get("evocation_attack_timing", "none"))
	var move_room_ids: Array = context.get("evocation_move_room_ids", [])
	var target_player_index: int = int(context.get("evocation_target_player_index", -1))

	match str(resolution.get("step", "start")):
		"start":
			if attack_timing != "before" and attack_timing != "after" and attack_timing != "none":
				return true
			if move_room_ids.size() > evocation.speed:
				return true
			resolution["step"] = "attack_before"
			return false

		"attack_before":
			resolution["step"] = "move"
			if attack_timing == "before":
				if not _valid_evocation_attack_target(evocation, target_player_index):
					return true
				deal_damage_from_evocation(
					evocation,
					target_player_index,
					activation_strength
				)
				return false
			return false

		"move":
			var move_index: int = int(resolution.get("move_index", 0))
			if move_index < move_room_ids.size():
				if not move_evocation_to_room_id(
					evocation,
					str(move_room_ids[move_index]),
					1
				):
					return true
				resolution["move_index"] = move_index + 1
				return false
			resolution["step"] = "attack_after"
			return false

		"attack_after":
			resolution["step"] = "done"
			if attack_timing == "after":
				if not _valid_evocation_attack_target(evocation, target_player_index):
					return true
				deal_damage_from_evocation(
					evocation,
					target_player_index,
					activation_strength
				)
				return false
			return false

		"done":
			context["last_activated_evocation"] = evocation
			context["last_evocation_activation_controller"] = controller_id
			context["last_evocation_activation_strength"] = activation_strength
			context["last_evocation_activation_strength_bonus"] = strength_bonus
			print(
				"Evocation activated: ", evocation.evocation_name,
				" | controller P", controller_id + 1,
				" | Strength ", activation_strength
			)
			return true

		_:
			return true


func _valid_evocation_attack_target(
	evocation: EvocationState,
	target_player_index: int
) -> bool:
	if target_player_index < 0 or target_player_index >= players.size():
		return false
	var target_mage = players[target_player_index].mage
	return (
		not target_mage.in_cell
		and target_mage.room_id == evocation.room_id
	)


func _handle_resolution_completion(frame: Dictionary):
	match str(frame.get("on_complete", "")):
		"advance_action_phase":
			advance_action_phase()
		"advance_evocation_phase":
			evocation_phase_cursor += 1
			advance_evocation_phase()
		_:
			pass


# =============================================================================
# EVOCATION PHASE - INTERACTIVE
# =============================================================================

func advance_evocation_phase() -> bool:
	if current_phase != PHASE_EVOCATION:
		return false
	if waiting_for_player_input:
		return true

	while evocation_phase_cursor < current_phase_play_order.size():
		var player_index: int = current_phase_play_order[evocation_phase_cursor]
		var player = players[player_index]

		if player.evocations.is_empty():
			evocation_phase_cursor += 1
			continue

		var evocation_data: Array = []
		for i in range(player.evocations.size()):
			var evocation: EvocationState = player.evocations[i]
			if evocation == null:
				continue
			evocation_data.append({
				"evocation_index": i,
				"id": evocation.evocation_id,
				"name": evocation.evocation_name,
				"room_id": evocation.room_id,
				"speed": evocation.speed,
				"strength": evocation.strength
			})

		return request_player_input({
			"type": "evocation_phase_activations",
			"phase": PHASE_EVOCATION,
			"player_index": player_index,
			"evocations": evocation_data,
			"required_count": player.evocations.size()
		})

	return finish_evocation_phase()


func submit_evocation_phase_activations(
	player_index: int,
	choices: Array
) -> bool:
	if not waiting_for_player_input:
		return false
	if str(pending_input.get("type", "")) != "evocation_phase_activations":
		return false
	if player_index != int(pending_input.get("player_index", -1)):
		return false

	var player = players[player_index]
	if choices.size() != player.evocations.size():
		return false

	var used_indices: Array[int] = []
	for choice_value in choices:
		if not choice_value is Dictionary:
			return false
		var index: int = int(choice_value.get("evocation_index", -1))
		if index < 0 or index >= player.evocations.size() or used_indices.has(index):
			return false
		used_indices.append(index)

	clear_player_input()
	return queue_resolution({
		"type": "evocation_phase_player",
		"player_index": player_index,
		"choices": choices.duplicate(true),
		"choice_index": 0,
		"on_complete": "advance_evocation_phase"
	})


func process_evocation_phase_player_resolution(
	resolution: Dictionary
) -> bool:
	var player_index: int = int(resolution.get("player_index", -1))
	if player_index < 0 or player_index >= players.size():
		return true

	var choices: Array = resolution.get("choices", [])
	var choice_index: int = int(resolution.get("choice_index", 0))
	if choice_index >= choices.size():
		return true

	var choice: Dictionary = choices[choice_index]
	resolution["choice_index"] = choice_index + 1
	var evocation_index: int = int(choice.get("evocation_index", -1))
	if evocation_index < 0 or evocation_index >= players[player_index].evocations.size():
		return true

	var evocation: EvocationState = players[player_index].evocations[evocation_index]
	var activation_context: Dictionary = choice.get("context", {}).duplicate(true)
	activation_context["game"] = self
	activation_context["play_order"] = current_phase_play_order.duplicate()
	activate_evocation(evocation, player_index, activation_context)
	return false


func finish_evocation_phase() -> bool:
	if current_phase != PHASE_EVOCATION or waiting_for_player_input:
		return false

	evocation_phase_cursor = 0
	current_phase_play_order.clear()
	print("")
	print("==============================================")
	print("           EVOCATION PHASE COMPLETE")
	print("==============================================")
	print("")
	return _complete_phase(PHASE_EVOCATION)


# =============================================================================
# CLEAN-UP PHASE
# =============================================================================

func resolve_cleanup_phase(
	context: Dictionary = {}
) -> bool:
	if waiting_for_player_input:
		return false
	if not start_phase(PHASE_CLEANUP):
		return false

	current_phase_play_order = get_play_order()
	if current_phase_play_order.is_empty():
		return false

	print("")
	print("==============================================")
	print("              CLEAN-UP PHASE")
	print("==============================================")

	cleanup_phase_cursor = 0
	return advance_cleanup_phase(context)


func advance_cleanup_phase(
	context: Dictionary = {}
) -> bool:
	if current_phase != PHASE_CLEANUP:
		return false
	if waiting_for_player_input:
		return true

	while cleanup_phase_cursor < current_phase_play_order.size():
		var player_index: int = current_phase_play_order[cleanup_phase_cursor]
		var player = players[player_index]
		var active_options: Array = []

		for i in range(player.active_spells.size()):
			var active_spell: ActiveSpellState = player.active_spells[i]
			if active_spell == null or not active_spell.active:
				continue
			var spell_type: String = active_spell.get_spell_type()
			if spell_type != "trap" and spell_type != "protection":
				continue
			active_options.append({
				"active_index": i,
				"spell_id": active_spell.spell.id,
				"spell_name": active_spell.spell.card_name,
				"spell_type": spell_type
			})

		if not active_options.is_empty():
			return request_player_input({
				"type": "cleanup_active_spells",
				"phase": PHASE_CLEANUP,
				"player_index": player_index,
				"active_spells": active_options,
				"return_to_hand_indices": []
			})

		_cleanup_player_mage_sheet(player_index, [])
		cleanup_phase_cursor += 1

	return _finish_cleanup_after_players(context)


func submit_cleanup_active_spells(
	player_index: int,
	return_to_hand_indices: Array
) -> bool:
	if not waiting_for_player_input:
		return false
	if str(pending_input.get("type", "")) != "cleanup_active_spells":
		return false
	if player_index != int(pending_input.get("player_index", -1)):
		return false

	var offered: Array = pending_input.get("active_spells", [])
	var allowed_indices: Array[int] = []
	for option_value in offered:
		allowed_indices.append(int(option_value.get("active_index", -1)))

	var validated: Array[int] = []
	for index_value in return_to_hand_indices:
		var index: int = int(index_value)
		if not allowed_indices.has(index) or validated.has(index):
			return false
		validated.append(index)

	clear_player_input()
	_cleanup_player_mage_sheet(player_index, validated)
	cleanup_phase_cursor += 1
	return advance_cleanup_phase()


func _cleanup_player_mage_sheet(
	player_index: int,
	return_active_indices: Array[int]
):
	var player = players[player_index]

	# Active Trap/Protection: chosen cards return to Hand, all other Active
	# cards go to Memories.
	for i in range(player.active_spells.size()):
		var active_spell: ActiveSpellState = player.active_spells[i]
		if active_spell == null:
			continue
		if not active_spell.active:
			continue

		if return_active_indices.has(i):
			player.add_spell_to_hand(active_spell.spell)
		else:
			player.add_spell_to_memories(active_spell.spell)

	player.active_spells.clear()

	# All remaining prepared cards on the Mage Sheet go to Memories.
	for ready in player.ready_spells:
		if ready != null and ready.spell != null:
			player.add_spell_to_memories(ready.spell)
	player.ready_spells.clear()

	if player.quick_spell != null and player.quick_spell.spell != null:
		player.add_spell_to_memories(player.quick_spell.spell)
	player.quick_spell = null

	# Revealed Spells also leave the Mage Sheet for Memories.
	for revealed in player.revealed_spells:
		if revealed != null and revealed.spell != null:
			player.add_spell_to_memories(revealed.spell)
	player.revealed_spells.clear()

	player.refresh_physical_actions()

	if player_index < player_boards.size():
		player_boards[player_index].refresh()


func _finish_cleanup_after_players(
	context: Dictionary = {}
) -> bool:
	var phase_context: Dictionary = context.duplicate(true)
	phase_context["game"] = self
	phase_context["play_order"] = current_phase_play_order.duplicate()

	if not resolve_events_for_phase(PHASE_CLEANUP, phase_context):
		return false

	resolve_completed_rooms()
	reset_room_activations()

	if check_end_game():
		return true

	return finish_cleanup_phase()


func finish_cleanup_phase() -> bool:
	if current_phase != PHASE_CLEANUP or waiting_for_player_input:
		return false

	cleanup_phase_cursor = 0
	current_phase_play_order.clear()

	print("")
	print("==============================================")
	print("           CLEAN-UP PHASE COMPLETE")
	print("==============================================")
	print("")

	finish_round()
	return _complete_phase(PHASE_CLEANUP)


func check_end_game() -> bool:
	var threshold: int = int($PowerBoard.end_game_threshold)
	var reached: Array = []

	if black_rose_power >= threshold:
		reached.append({"type": "black_rose", "power": black_rose_power})

	for player in players:
		if player.power >= threshold:
			reached.append({
				"type": "player",
				"player_index": player.player_index,
				"power": player.power
			})

	if reached.is_empty():
		return false

	game_has_ended = true
	game_flow_active = false
	var result := {
		"round": current_round,
		"reached_threshold": reached,
		"threshold": threshold
	}
	game_over.emit(result)
	print("GAME OVER: end-game threshold reached")
	return true


# =============================================================================
# WHOLE TURN FLOW
# =============================================================================

func start_game_flow() -> bool:
	if game_has_ended:
		return false
	if waiting_for_player_input or not resolution_stack.is_empty():
		return false

	game_flow_active = true
	return resolve_black_rose_phase()


func stop_game_flow():
	game_flow_active = false


func _complete_phase(phase: String) -> bool:
	phase_completed.emit(phase)
	if not game_flow_active or game_has_ended:
		return true
	return advance_game_flow(phase)


func advance_game_flow(completed_phase: String = "") -> bool:
	if not game_flow_active or game_has_ended:
		return false
	if waiting_for_player_input:
		return true

	match completed_phase:
		PHASE_BLACK_ROSE:
			return resolve_study_phase()
		PHASE_STUDY:
			return resolve_preparation_phase()
		PHASE_PREPARATION:
			return resolve_action_phase()
		PHASE_ACTION:
			return resolve_evocation_phase()
		PHASE_EVOCATION:
			return resolve_cleanup_phase()
		PHASE_CLEANUP:
			return resolve_black_rose_phase()
		_:
			return resolve_black_rose_phase()
func assign_mage_to_player(
	player_index: int,
	mage_id: String
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():
		print(
			"assign_mage_to_player: invalid player ",
			player_index
		)
		return false

	var data: Dictionary = (
		mage_database.get_mage_data(mage_id)
	)

	if data.is_empty():
		return false

	var player: PlayerState = players[player_index]

	player.mage_id = str(data["id"])

	player.mage = MageState.new(
		str(data["id"]),
		int(data.get("health", 10)),
		int(data.get("strength", 0)),
		int(data.get("speed", 0))
	)

	player.hand_limit = int(
		data.get("hand_limit", 6)
	)

	player.max_active_quests = int(
		data.get("max_active_quests", 2)
	)

	player.personal_spell_id = str(
		data.get("personal_spell_id", "")
	)

	player.personal_spell_copies_received = 0

	print(
		"Player ",
		player_index + 1,
		" assigned Mage: ",
		data.get("name", mage_id),
		" | HP ",
		player.mage.health,
		" | Hand ",
		player.hand_limit,
		" | STR ",
		player.mage.strength,
		" | SPD ",
		player.mage.speed
	)

	return true
	
func create_personal_spell_copy(
	spell_id: String
) -> SpellCardState:

	if spell_id.is_empty():
		return null

	if not spell_database.spells.has(spell_id):
		print(
			"Personal Spell not found: ",
			spell_id
		)
		return null

	var spell: SpellCardState = (
		spell_database.spells[spell_id]
	)

	var copy := SpellCardState.new(
		spell.id,
		spell.card_name,
		spell.school_id,
		spell.light_side.duplicate(true),
		spell.dark_side.duplicate(true),
		spell.copies,
		spell.personal
	)

	copy.forgotten = spell.forgotten
	copy.instability = spell.instability

	return copy
func give_initial_personal_spell(
	player_index: int
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():
		return false

	var player: PlayerState = players[player_index]

	if player.personal_spell_id.is_empty():
		return false

	if player.personal_spell_copies_received >= 1:
		return true

	var spell := create_personal_spell_copy(
		player.personal_spell_id
	)

	if spell == null:
		return false

	player.grimoire.append(spell)
	player.personal_spell_copies_received = 1

	print(
		"Player ",
		player_index + 1,
		" received ",
		spell.card_name,
		" copy 1 in Grimoire"
	)

	return true


func give_personal_spell_for_moon(
	player_index: int,
	moon: int
) -> bool:

	if player_index < 0 \
	or player_index >= players.size():
		return false

	if moon < 2 or moon > 3:
		return false

	var player: PlayerState = players[player_index]

	if player.personal_spell_id.is_empty():
		return false

	if player.personal_spell_copies_received >= moon:
		return true

	# Sicurezza: non distribuiamo Moon III se per qualche
	# motivo non è stata ancora distribuita Moon II.
	if player.personal_spell_copies_received != moon - 1:
		print(
			"Personal Spell distribution out of sequence for Player ",
			player_index + 1
		)
		return false

	var spell := create_personal_spell_copy(
		player.personal_spell_id
	)

	if spell == null:
		return false

	player.hand.append(spell)
	player.personal_spell_copies_received = moon

	print(
		"Player ",
		player_index + 1,
		" received ",
		spell.card_name,
		" copy ",
		moon,
		" directly in Hand"
	)

	return true


func distribute_personal_spells_for_moon(
	moon: int
):
	for player_index in range(players.size()):
		give_personal_spell_for_moon(
			player_index,
			moon
		)

	for board in player_boards:
		if board != null:
			board.refresh()
func create_quest_decks() -> void:

	for moon in range(1, 4):

		var deck: Array[QuestCardState] = (
			quest_database.create_deck_for_moon(
				moon
			)
		)

		shuffle_with_rng(deck)

		quest_decks[moon] = deck

		print(
			"Quest Deck Moon ",
			moon,
			": ",
			deck.size()
		)
func advance_black_rose_quest_steps() -> bool:

	if current_phase != PHASE_BLACK_ROSE:
		return false

	if waiting_for_player_input:
		return true

	if current_phase_play_order.is_empty():
		return false

	match black_rose_quest_step:

		4:
			return advance_black_rose_quest_discard()

		5:
			return advance_black_rose_quest_draw()

		6:
			return advance_black_rose_quest_limits()

		7:
			return finish_black_rose_phase()

		_:
			print(
				"Invalid Black Rose Quest step: ",
				black_rose_quest_step
			)
			return false
func advance_black_rose_quest_discard() -> bool:

	while black_rose_quest_cursor \
	< current_phase_play_order.size():

		var player_index: int = (
			current_phase_play_order[
				black_rose_quest_cursor
			]
		)

		var player = players[player_index]

		# Nessuna Active Quest:
		# non c'è niente da scegliere.
		if player.active_quests.is_empty():
			black_rose_quest_cursor += 1
			continue

		var quest_data: Array = []

		for i in range(
			player.active_quests.size()
		):
			var quest: QuestState = (
				player.active_quests[i]
			)

			quest_data.append(
				{
					"quest_index": i,
					"id": quest.get_id(),
					"name": quest.get_name(),
					"moon": quest.get_moon(),
					"revealed": quest.revealed,
					"progress": quest.progress,
					"cube_slots":
						quest.get_cube_slots()
				}
			)

		return request_player_input(
			{
				"type":
					"black_rose_optional_quest_discard",

				"phase":
					PHASE_BLACK_ROSE,

				"player_index":
					player_index,

				"optional":
					true,

				"quests":
					quest_data
			}
		)

	# Tutti hanno effettuato/ignorato lo step 4.
	black_rose_quest_step = 5
	black_rose_quest_cursor = 0

	return advance_black_rose_quest_steps()
	
func submit_black_rose_optional_quest_discard(
	player_index: int,
	quest_index: int = -1
) -> bool:

	if not waiting_for_player_input:
		print(
			"submit_black_rose_optional_quest_discard: "
			+ "no input requested"
		)
		return false

	if str(
		pending_input.get(
			"type",
			""
		)
	) != "black_rose_optional_quest_discard":

		print(
			"submit_black_rose_optional_quest_discard: "
			+ "wrong pending input type"
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

	var player = players[player_index]

	# -1 = il giocatore sceglie di non scartare.
	if quest_index != -1:

		if quest_index < 0 \
		or quest_index >= player.active_quests.size():

			print(
				"Black Rose Quest discard: "
				+ "invalid Quest index"
			)
			return false

		var quest: QuestState = (
			player.active_quests[quest_index]
		)

		# IMPORTANT:
		# la BR guadagna Power in base alla Moon
		# DELLA QUEST, non necessariamente current_moon.
		var black_rose_reward: int = (
			quest.get_moon()
		)

		if not quest_manager.discard_active_quest(
			self,
			player_index,
			quest
		):
			return false

		add_black_rose_power(
			black_rose_reward
		)

		print(
			"Black Rose gains ",
			black_rose_reward,
			" Power from discarded Quest ",
			quest.get_name()
		)

	clear_player_input()

	black_rose_quest_cursor += 1

	return advance_black_rose_quest_steps()
func advance_black_rose_quest_draw() -> bool:

	while black_rose_quest_cursor \
	< current_phase_play_order.size():

		var player_index: int = (
			current_phase_play_order[
				black_rose_quest_cursor
			]
		)

		var player = players[player_index]

		if player.active_quests.is_empty():

			var quest: QuestState = (
				quest_manager.draw_quest(
					self,
					player_index
				)
			)

			if quest == null:
				print(
					"Black Rose Phase: "
					+ "Player ",
					player_index + 1,
					" could not draw a Quest"
				)

		black_rose_quest_cursor += 1

	black_rose_quest_step = 6
	black_rose_quest_cursor = 0

	return advance_black_rose_quest_steps()
func advance_black_rose_quest_limits() -> bool:

	while black_rose_quest_cursor \
	< current_phase_play_order.size():

		var player_index: int = (
			current_phase_play_order[
				black_rose_quest_cursor
			]
		)

		var active_excess: int = (
			quest_manager.get_active_excess(
				self,
				player_index
			)
		)

		if active_excess > 0:
			return request_black_rose_active_quest_limit(
				player_index,
				active_excess
			)

		var completed_excess: int = (
			quest_manager.get_completed_excess(
				self,
				player_index
			)
		)

		if completed_excess > 0:
			return request_black_rose_completed_quest_limit(
				player_index,
				completed_excess
			)

		black_rose_quest_cursor += 1

	black_rose_quest_step = 7
	black_rose_quest_cursor = 0

	return advance_black_rose_quest_steps()
	
func request_black_rose_active_quest_limit(
	player_index: int,
	discard_count: int
) -> bool:

	var player = players[player_index]

	var quest_data: Array = []

	for i in range(
		player.active_quests.size()
	):
		var quest: QuestState = (
			player.active_quests[i]
		)

		quest_data.append(
			{
				"quest_index": i,
				"id": quest.get_id(),
				"name": quest.get_name(),
				"moon": quest.get_moon(),
				"revealed": quest.revealed,
				"progress": quest.progress,
				"cube_slots":
					quest.get_cube_slots()
			}
		)

	return request_player_input(
		{
			"type":
				"black_rose_active_quest_limit",

			"phase":
				PHASE_BLACK_ROSE,

			"player_index":
				player_index,

			"discard_count":
				discard_count,

			"quests":
				quest_data
		}
	)
func submit_black_rose_active_quest_limit(
	player_index: int,
	quest_indices: Array
) -> bool:

	if not waiting_for_player_input:
		return false

	if str(
		pending_input.get(
			"type",
			""
		)
	) != "black_rose_active_quest_limit":
		return false

	if player_index != int(
		pending_input.get(
			"player_index",
			-1
		)
	):
		return false

	var required_count: int = int(
		pending_input.get(
			"discard_count",
			0
		)
	)

	if quest_indices.size() != required_count:
		print(
			"Black Rose: must discard exactly ",
			required_count,
			" Active Quests"
		)
		return false

	var player = players[player_index]

	var selected: Array[QuestState] = []

	var seen_indices: Dictionary = {}

	for value in quest_indices:

		var index: int = int(value)

		if index < 0 \
		or index >= player.active_quests.size():
			return false

		if seen_indices.has(index):
			return false

		seen_indices[index] = true

		selected.append(
			player.active_quests[index]
		)

	# IMPORTANT:
	# nessun Power alla Black Rose per questi scarti.
	for quest in selected:

		if not quest_manager.discard_active_quest(
			self,
			player_index,
			quest
		):
			return false

	clear_player_input()

	# Non avanziamo ancora il player.
	# Potrebbe avere Completed Quest in eccesso.
	return advance_black_rose_quest_steps()
	
func request_black_rose_completed_quest_limit(
	player_index: int,
	discard_count: int
) -> bool:

	var player = players[player_index]

	var quest_data: Array = []

	for i in range(
		player.completed_quests.size()
	):
		var quest: QuestState = (
			player.completed_quests[i]
		)

		quest_data.append(
			{
				"quest_index": i,
				"id": quest.get_id(),
				"name": quest.get_name(),
				"moon": quest.get_moon(),
				"solved": quest.solved
			}
		)

	return request_player_input(
		{
			"type":
				"black_rose_completed_quest_limit",

			"phase":
				PHASE_BLACK_ROSE,

			"player_index":
				player_index,

			"discard_count":
				discard_count,

			"quests":
				quest_data
		}
	)
func submit_black_rose_completed_quest_limit(
	player_index: int,
	quest_indices: Array
) -> bool:

	if not waiting_for_player_input:
		return false

	if str(
		pending_input.get(
			"type",
			""
		)
	) != "black_rose_completed_quest_limit":
		return false

	if player_index != int(
		pending_input.get(
			"player_index",
			-1
		)
	):
		return false

	var required_count: int = int(
		pending_input.get(
			"discard_count",
			0
		)
	)

	if quest_indices.size() != required_count:
		print(
			"Black Rose: must discard exactly ",
			required_count,
			" Completed Quests"
		)
		return false

	var player = players[player_index]

	var selected: Array[QuestState] = []

	var seen_indices: Dictionary = {}

	for value in quest_indices:

		var index: int = int(value)

		if index < 0 \
		or index >= player.completed_quests.size():
			return false

		if seen_indices.has(index):
			return false

		seen_indices[index] = true

		selected.append(
			player.completed_quests[index]
		)

	for quest in selected:

		if not quest_manager.discard_completed_quest(
			self,
			player_index,
			quest
		):
			return false

	clear_player_input()

	# Ora questo stesso player verrà ricontrollato.
	# Siccome non ha più eccessi, advance incrementerà
	# automaticamente il cursor.
	return advance_black_rose_quest_steps()
	
func finish_black_rose_phase() -> bool:

	if current_phase != PHASE_BLACK_ROSE:
		return false

	if waiting_for_player_input:
		return false

	print("")
	print("==============================================")
	print("          BLACK ROSE PHASE COMPLETE")
	print("==============================================")
	print("")

	black_rose_quest_step = 0
	black_rose_quest_cursor = 0

	current_phase_play_order.clear()

	return _complete_phase(
		PHASE_BLACK_ROSE
	)
	
