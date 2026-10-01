extends Node2D

const Tests = preload("res://tests.gd")
const BetaHUDScript = preload("res://beta_hud.gd")

@export var run_tests_on_ready: bool = false
@export var auto_start_game_flow: bool = true
@export var enable_beta_hud: bool = true

var beta_hud = null
var network_session = null
var network_client := false
var local_viewer_index := -1
var network_slot_views: Dictionary = {}
var network_cast_tokens: Dictionary = {}
var input_revision := 0
var turn_banner: Label
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

# Interactive choices requested while resolving an Effect.  The public
# request only exposes serializable option data; runtime values such as
# RevealedSpellState / EvocationState stay here until the player answers.
var pending_effect_choice_context: Dictionary = {}
var pending_effect_choice_values: Dictionary = {}

# =========================================================
# ACTION PHASE STATE
# =========================================================

var action_phase_cursor: int = 0
var action_phase_activation_round: int = 0

# During the beta UI flow an Activation is resolved one decision at a time.
# This is necessary because Action 1 may change the legal options for Action 2
# (for example Explore into a Room and then Fight a Model there).
var action_activation_active: bool = false
var action_activation_player_index: int = -1
var action_activation_actions_used: int = 0
var action_activation_numbered_spells_cast: int = 0
var action_activation_quick_spells_cast: int = 0
# =========================================================
# PREPARATION PHASE STATE
# =========================================================

var preparation_phase_cursor: int = 0
# =========================================================
# EVOCATION / CLEAN-UP PHASE STATE
# =========================================================
var evocation_phase_cursor: int = 0
var evocation_phase_activated: Array[EvocationState] = []
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
var final_result: Dictionary = {}
var black_rose_trophies: Array[int] = []
var player_entrance_room_ids: Dictionary = {}
var player_entrance_room_coords: Dictionary = {}

# A Cell touches two Lodge Rooms in the standard layouts. Keep the historic
# single entrance as a deterministic primary exit for backwards compatibility,
# but expose every legal exit to movement/UI.
var player_cell_exit_room_ids: Dictionary = {}
var player_cell_exit_room_coords: Dictionary = {}

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
var evocation_token_scene = preload("res://evocation_token.tscn")
var evocation_tokens: Dictionary = {}
var evocation_inspection: AcceptDialog
var inspected_evocation: EvocationState
const ReferenceCardPreview = preload("res://reference_card_preview.gd")
var inspected_quest: QuestState
var tabletop_projection_signature: String = ""
var player_cell_coords: Dictionary = {}
var player_board_scene = preload("res://player_board.tscn")

var spell_database = SpellDatabase.new()
var evocation_database = EvocationDatabase.new()
var triggered_spell_manager = TriggeredSpellManager.new()
var mage_database = MageDatabase.new()
var layout_database = {}
const HEX_RADIUS = 78.0
var board_center: Vector2
var room_database = []
var cell_database = []
var player_boards: Array = []
var player_board_spell_slots: Dictionary = {}
var spell_preview_script = preload("res://spell_card_preview.gd")
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

# Setup step: unique School choice + one of its two Starting Grimoires.
var school_specialization_database: Dictionary = {}
var starting_setup_complete: bool = false
var starting_setup_order: Array[int] = []
var starting_setup_cursor: int = 0
var starting_setup_stage: String = "mage"

# Decision overlays reserve no permanent sidebar space.
@export var beta_sidebar_width: float = 0.0
@export var beta_force_fullscreen: bool = true
const TABLE_LOGICAL_SIZE := Vector2(1600.0, 900.0)
var beta_background_layer: CanvasLayer = null
var forgotten_deck: Array[SpellCardState] = []
var forgotten_discard: Array[SpellCardState] = []
var forgotten_removed_from_game: Array[SpellCardState] = []
var crown_owner_id: int = -1
var event_database := EventDatabase.new()
var current_round: int = 1
var quest_database := QuestDatabase.new()
var quest_manager := QuestManager.new()
var black_rose_quest_step: int = 0
var black_rose_quest_cursor: int = 0
var black_rose_instant_event_queued: bool = false
var quest_decks: Dictionary = {
	1: [],
	2: [],
	3: []
}

var quest_discard: Array[QuestCardState] = []

# Fase corrente della partita.
var current_phase: String = ""

const PHASE_SETUP: String = "setup"
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
	

func _builtin_school_specializations() -> Dictionary:
	return {
		"agony": {
			"name": "Agony",
			"starting_grimoires": [
				{
					"id": "sadistic_fury",
					"name": "Sadistic Fury",
					"spell_ids": [
						"shared_torture",
						"grim_torment",
						"cross_and_delight",
						"torment",
						"visceral_fire",
						"peak_of_agony"
					]
				},
				{
					"id": "algolagnia",
					"name": "Algolagnia",
					"spell_ids": [
						"pain_mark",
						"master_of_pleasure",
						"liquefy_the_pain",
						"submission",
						"ineluctable_pain",
						"heart_of_ice"
					]
				}
			]
		},
		"alchemy": {
			"name": "Alchemy",
			"starting_grimoires": [
				{
					"id": "scourge",
					"name": "Scourge",
					"spell_ids": [
						"azoth_bomb",
						"viatorium_spagyricum",
						"deflagrate",
						"athanor_eruption",
						"marbling",
						"stone_phoenix"
					]
				},
				{
					"id": "auromancer",
					"name": "Auromancer",
					"spell_ids": [
						"soul_transfer",
						"liquid_fire",
						"fountain_of_the_three",
						"purifying_aludel",
						"albify",
						"silver_of_the_sages"
					]
				}
			]
		}
	}


func load_school_specializations() -> Dictionary:
	var candidate_paths: Array[String] = [
		"res://data/school_specializations.json",
		"res://school_specializations.json"
	]

	for path in candidate_paths:
		if not FileAccess.file_exists(path):
			continue

		var file := FileAccess.open(
			path,
			FileAccess.READ
		)

		if file == null:
			continue

		var data = JSON.parse_string(
			file.get_as_text()
		)

		if data is Dictionary:
			print(
				"Loaded Starting Grimoires from ",
				path
			)
			return data

		print(
			"WARNING: invalid Starting Grimoire JSON at ",
			path
		)

	print(
		"WARNING: school_specializations.json not found; "
		+ "using built-in Agony/Alchemy Starting Grimoires"
	)

	return _builtin_school_specializations()


func get_school_display_name(
	school_id: String
) -> String:
	if school_specialization_database.has(school_id):
		return str(
			school_specialization_database[school_id].get(
				"name",
				school_id.capitalize()
			)
		)

	return school_id.capitalize()


func get_starting_grimoire_options(
	school_id: String
) -> Array:
	var result: Array = []

	if not school_specialization_database.has(school_id):
		return result

	var school_data: Dictionary = school_specialization_database[
		school_id
	]

	for grimoire_value in school_data.get(
		"starting_grimoires",
		[]
	):
		if not grimoire_value is Dictionary:
			continue

		var grimoire: Dictionary = grimoire_value
		var public_spells: Array = []

		for spell_id_value in grimoire.get("spell_ids", []):
			var spell_id: String = str(spell_id_value)
			var spell_name: String = spell_id

			if spell_database.spells.has(spell_id):
				var spell: SpellCardState = spell_database.spells[
					spell_id
				]

				if spell != null:
					spell_name = spell.card_name

			public_spells.append({
				"id": spell_id,
				"name": spell_name
			})

		result.append({
			"id": str(grimoire.get("id", "")),
			"name": str(grimoire.get("name", "")),
			"spells": public_spells
		})

	return result

func create_cell(
	cell_data,
	hex_position: Vector2i,
	owner_index: int = -1
):
	var cell = cell_scene.instantiate()

	cell.cell_id = cell_data["id"]
	cell.cell_name = cell_data["name"]
	cell.cell_color = Color(cell_data["color"])
	if owner_index >= 0 and owner_index < players.size():
		cell.cell_color = players[owner_index].color
		cell.cell_name = "Cell P%d" % (owner_index + 1)
		cell.set_meta("owner_index", owner_index)
	cell.radius = HEX_RADIUS
	cell.set_meta("hex_coord", hex_position)
	cell.position = hex_to_pixel(hex_position)

	add_child(cell)
	
func _ready():
	if game_seed == 0:
		rng.randomize()
	else:
		rng.seed = game_seed

	# Use the full viewport; decisions are floating overlays on the tabletop.
	var initial_viewport_size: Vector2 = get_viewport_rect().size
	var initial_play_width: float = initial_viewport_size.x

	if enable_beta_hud and not run_tests_on_ready:
		initial_play_width = max(
			640.0,
			initial_viewport_size.x - beta_sidebar_width
		)

	board_center = Vector2(
		initial_play_width * 0.5,
		initial_viewport_size.y * 0.54
	)

	room_database = load_rooms()
	layout_database = load_layouts()
	cell_database = load_cells()

	print("PLAYER COUNT: ", player_count)
	print("GAME SEED: ", game_seed)

	spell_database.load_database()
	school_specialization_database = load_school_specializations()
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
	create_model_tokens()
	create_player_boards()

	for board in player_boards:
		if board != null:
			board.refresh()

	await $PowerBoard.initialize(player_count)
	$EventBoard.refresh_event_slots()
	update_table_layout()
	await get_tree().process_frame

	# The first beta UI is created entirely from code, so no scene-tree changes
	# are required. Tests keep it disabled to avoid user-interface side effects.
	if enable_beta_hud and not run_tests_on_ready:
		if beta_force_fullscreen:
			get_window().mode = Window.MODE_FULLSCREEN

		beta_hud = BetaHUDScript.new()
		add_child(beta_hud)
		beta_hud.setup(
			self,
			beta_sidebar_width
		)

		var viewport := get_viewport()
		if not viewport.size_changed.is_connected(
			_on_beta_viewport_resized
		):
			viewport.size_changed.connect(
				_on_beta_viewport_resized
			)

		_apply_beta_table_layout()

	if run_tests_on_ready:
		Tests.run(self)

	if not run_tests_on_ready \
	and enable_beta_hud:
		_create_turn_banner()
		if not network_client and network_session == null:
			call_deferred(
				"_ensure_interactive_beta_started"
			)
	elif auto_start_game_flow:
		start_game_flow()

func _create_turn_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	turn_banner = Label.new()
	turn_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	turn_banner.offset_top = 8
	turn_banner.offset_bottom = 38
	turn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	turn_banner.add_theme_constant_override("outline_size", 6)
	layer.add_child(turn_banner)

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

	# Cell entrance IDs depend on coord_to_room_id(). Therefore the complete
	# Lodge coordinate map must exist before Cells are assigned to players.
	# Previously create_cells() ran before the 17 random Rooms were registered,
	# leaving entrance Room IDs empty for Cells whose entrance was not Black Rose
	# or Throne.
	create_cells()

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

	room.set_meta("hex_coord", hex_position)
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

func _cell_adjacent_lodge_rooms(
	cell_coord: Vector2i
) -> Dictionary:
	var ids: Array[String] = []
	var coords: Array[Vector2i] = []

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(1, -1),
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1)
	]

	for direction in directions:
		var candidate_coord: Vector2i = (
			cell_coord + direction
		)

		if not room_id_by_coord.has(
			candidate_coord
		):
			continue

		var room_id: String = str(
			room_id_by_coord[
				candidate_coord
			]
		)

		if room_id == "":
			continue

		if not is_lodge_room_id(room_id):
			continue

		if ids.has(room_id):
			continue

		ids.append(room_id)
		coords.append(candidate_coord)

	return {
		"ids": ids,
		"coords": coords
	}


func get_player_cell_exit_room_ids(
	player_index: int
) -> Array[String]:
	var result: Array[String] = []

	if not player_cell_exit_room_ids.has(
		player_index
	):
		return result

	for room_id_value in player_cell_exit_room_ids[
		player_index
	]:
		result.append(
			str(room_id_value)
		)

	return result


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
	player_cell_exit_room_ids.clear()
	player_cell_exit_room_coords.clear()
	player_cell_coords.clear()

	for i in range(cell_slots.size()):
		var slot_data = cell_slots[i]
		var position_array = slot_data["position"]
		var hex_position = Vector2i(
			int(position_array[0]),
			int(position_array[1])
		)

		var cell_data = selected_cells[i]
		create_cell(cell_data, hex_position, i)

		var exit_data: Dictionary = (
			_cell_adjacent_lodge_rooms(
				hex_position
			)
		)
		var exit_ids: Array[String] = []
		var exit_coords: Array[Vector2i] = []

		for room_id_value in exit_data.get(
			"ids",
			[]
		):
			exit_ids.append(
				str(room_id_value)
			)

		for coord_value in exit_data.get(
			"coords",
			[]
		):
			exit_coords.append(
				Vector2i(coord_value)
			)

		# Preserve the layout's historical entrance as the primary exit when
		# possible, purely for deterministic old code/tests.
		var entrance_array = slot_data["entrance_room"]
		var primary_coord = Vector2i(
			int(entrance_array[0]),
			int(entrance_array[1])
		)
		var primary_id: String = coord_to_room_id(
			primary_coord
		)

		if primary_id == "" \
		or not exit_ids.has(primary_id):
			if not exit_ids.is_empty():
				primary_id = exit_ids[0]
				primary_coord = exit_coords[0]

		if i < players.size():
			player_cell_coords[i] = hex_position
			player_entrance_room_coords[i] = primary_coord
			player_entrance_room_ids[i] = primary_id
			player_cell_exit_room_ids[i] = exit_ids
			player_cell_exit_room_coords[i] = exit_coords

			players[i].mage.room_coord = primary_coord
			players[i].mage.room_id = primary_id
			players[i].mage.in_cell = true

			print(
				"Player ", i + 1,
				" Cell exits: ", exit_ids,
				" | primary: ", primary_id,
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

		# Lodge/Cell setup and PlayerBoard rendering require a MageState object
		# even before the real Mage has been selected.
		player.mage = MageState.new()

		players.append(player)

		# Automated tests keep deterministic Mages so all older rule tests
		# continue to operate on their known baseline.
		if run_tests_on_ready \
		and i < test_mages.size():

			assign_mage_to_player(
				i,
				test_mages[i]
			)

	print(
		"Players created: ",
		players.size()
	)


func create_model_tokens() -> void:
	for token in mage_tokens:
		if is_instance_valid(token):
			token.queue_free()

	mage_tokens.clear()

	for token_value in evocation_tokens.values():
		if is_instance_valid(token_value):
			token_value.queue_free()

	evocation_tokens.clear()

	for player_index in range(players.size()):
		var token = mage_token_scene.instantiate()
		token.name = "MageToken_P" + str(player_index + 1)
		token.setup(
			player_index,
			players[player_index].color
		)
		add_child(token)
		mage_tokens.append(token)

	refresh_model_tokens()


func _sync_evocation_tokens() -> void:
	var live_ids: Dictionary = {}

	for owner_index in range(players.size()):
		var owner = players[owner_index]

		for evocation in owner.evocations:
			if evocation == null:
				continue

			var instance_id: int = int(
				evocation.get_instance_id()
			)
			live_ids[instance_id] = true

			if evocation_tokens.has(instance_id):
				continue

			var token = evocation_token_scene.instantiate()
			token.name = (
				"EvocationToken_"
				+ evocation.evocation_id
				+ "_P"
				+ str(owner_index + 1)
			)
			token.setup(
				evocation.evocation_id,
				evocation.evocation_name,
				owner_index,
				players[owner_index].color,
				evocation.board_number
			)
			token.inspect_requested.connect(open_evocation_inspection.bind(evocation))
			add_child(token)
			evocation_tokens[instance_id] = token

	var stale_ids: Array = []

	for instance_id_value in evocation_tokens.keys():
		var instance_id: int = int(instance_id_value)

		if live_ids.has(instance_id):
			continue

		var old_token = evocation_tokens[
			instance_id
		]

		if is_instance_valid(old_token):
			old_token.queue_free()

		stale_ids.append(instance_id)

	for instance_id in stale_ids:
		evocation_tokens.erase(instance_id)


func open_evocation_inspection(evocation: EvocationState) -> void:
	if not is_evocation_in_play(evocation):
		return
	if evocation_inspection == null:
		evocation_inspection = AcceptDialog.new()
		evocation_inspection.name = "EvocationInspection"
		evocation_inspection.ok_button_text = "Close"
		add_child(evocation_inspection)
		var content := VBoxContainer.new()
		content.name = "Content"
		content.add_theme_constant_override("separation", 12)
		evocation_inspection.add_child(content)
		var stats := Label.new()
		stats.name = "Stats"
		content.add_child(stats)
		var art := TextureRect.new()
		art.name = "CardArt"
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(650, 430)
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(art)
	inspected_evocation = evocation
	_update_evocation_inspection()
	evocation_inspection.popup_centered(Vector2i(760, 680))


func _process(_delta: float) -> void:
	if turn_banner != null:
		var decision := int(pending_input.get("player_index", -1))
		var turn := "Risoluzione" if decision < 0 else "Turno: Player %d" % (decision + 1)
		turn_banner.text = "Round %d · %s · %s" % [current_round, current_phase.capitalize(), turn]
		if game_has_ended:
			turn_banner.text = "Fine partita" + (" · " + turn if waiting_for_player_input else "")
	if evocation_inspection != null and evocation_inspection.visible:
		_update_evocation_inspection()
	if inspected_quest != null and not can_inspect_quest(inspected_quest):
		_close_reference_card_preview()
	var signature := ""
	for player in players:
		for quest in player.active_quests + player.completed_quests:
			signature += str([quest.get_instance_id(), quest.revealed, quest.completed, quest.solved, quest.progress])
		for active in player.active_spells:
			signature += str([active.get_instance_id(), active.active, active.context.get("target_room_id", "")])
	if signature != tabletop_projection_signature:
		tabletop_projection_signature = signature
		for board in player_boards:
			if is_instance_valid(board):
				board.refresh()
		_refresh_permanent_room_markers()


func _update_evocation_inspection() -> void:
	if inspected_evocation == null or not is_evocation_in_play(inspected_evocation):
		evocation_inspection.hide()
		inspected_evocation = null
		return
	var evocation := inspected_evocation
	evocation_inspection.get_node("Content/CardArt").texture = ReferenceCardPreview.card_texture("evocations", evocation.evocation_id)
	evocation_inspection.title = evocation.get_display_name() + " · P" + str(evocation.owner_id + 1)
	evocation_inspection.dialog_text = (
		"Health: %d / %d\nDamage: %d\nMovement speed: %d\nAttack: %d\nRoom: %s\nController: P%d"
		% [evocation.get_remaining_health(), evocation.health, evocation.get_damage(),
			evocation.speed, evocation.strength, evocation.room_id, get_evocation_controller_id(evocation) + 1]
	)
	evocation_inspection.get_label().hide()
	evocation_inspection.get_node("Content/Stats").text = evocation_inspection.dialog_text


func refresh_model_tokens() -> void:
	if players.is_empty():
		return

	_sync_evocation_tokens()
	for board in player_boards:
		if is_instance_valid(board):
			board.refresh_evocations()

	var groups: Dictionary = {}
	var group_centers: Dictionary = {}

	for player_index in range(players.size()):
		if player_index >= mage_tokens.size():
			continue

		var mage = players[player_index].mage
		var token = mage_tokens[player_index]

		if mage == null or not is_instance_valid(token):
			continue

		var location_key: String = ""
		var center: Vector2 = Vector2.ZERO

		if mage.in_cell:
			var cell_coord: Vector2i = mage.room_coord

			if player_cell_coords.has(player_index):
				cell_coord = player_cell_coords[
					player_index
				]

			location_key = "cell:" + str(player_index)
			center = hex_to_pixel(cell_coord)
		else:
			if mage.room_id == "":
				token.visible = false
				continue

			var room_coord: Vector2i = room_id_to_coord(
				mage.room_id
			)

			if room_coord == Vector2i(9999, 9999):
				token.visible = false
				continue

			location_key = "room:" + mage.room_id
			center = hex_to_pixel(room_coord)

		token.visible = true

		if not groups.has(location_key):
			groups[location_key] = []
			group_centers[location_key] = center

		groups[location_key].append({
			"node": token,
			"sort": player_index * 100
		})

	for owner_index in range(players.size()):
		for evocation_index in range(
			players[owner_index].evocations.size()
		):
			var evocation = players[
				owner_index
			].evocations[
				evocation_index
			]

			if evocation == null:
				continue

			if evocation.room_id == "":
				continue

			var instance_id: int = int(
				evocation.get_instance_id()
			)

			if not evocation_tokens.has(instance_id):
				continue

			var token = evocation_tokens[
				instance_id
			]

			if not is_instance_valid(token):
				continue

			var room_coord: Vector2i = room_id_to_coord(
				evocation.room_id
			)

			if room_coord == Vector2i(9999, 9999):
				token.visible = false
				continue

			token.visible = true

			var location_key: String = (
				"room:"
				+ evocation.room_id
			)

			if not groups.has(location_key):
				groups[location_key] = []
				group_centers[location_key] = hex_to_pixel(
					room_coord
				)

			groups[location_key].append({
				"node": token,
				"sort":
					10000
					+ owner_index * 100
					+ evocation_index
			})

	for location_key_value in groups.keys():
		var location_key: String = str(
			location_key_value
		)
		var entries: Array = groups[
			location_key
		]

		entries.sort_custom(
			func(a, b):
				return int(a["sort"]) < int(b["sort"])
		)

		var offsets: Array[Vector2] = (
			_model_token_offsets(
				entries.size()
			)
		)
		var center: Vector2 = group_centers[
			location_key
		]

		for i in range(entries.size()):
			var node = entries[i]["node"]

			if not is_instance_valid(node):
				continue

			node.position = center + offsets[i]


func _model_token_offsets(
	count: int
) -> Array[Vector2]:
	var result: Array[Vector2] = []

	if count <= 0:
		return result

	if count == 1:
		return [Vector2.ZERO]

	if count == 2:
		return [
			Vector2(-22, 0),
			Vector2(22, 0)
		]

	if count == 3:
		return [
			Vector2(-34, 0),
			Vector2(0, 0),
			Vector2(34, 0)
		]

	var columns: int = mini(3, count)
	var spacing_x: float = 35.0
	var spacing_y: float = minf(30.0, 48.0 / maxf(1.0, ceilf(float(count) / 3.0) - 1.0))
	var rows: int = int(
		ceil(
			float(count)
			/ float(columns)
		)
	)
	var start_y: float = (
		-float(rows - 1) * spacing_y * 0.5
	)

	for i in range(count):
		var row: int = int(i / columns)
		var column: int = i % columns

		var items_in_row: int = mini(
			columns,
			count - row * columns
		)

		var start_x: float = (
			-float(items_in_row - 1)
			* spacing_x
			* 0.5
		)

		result.append(
			Vector2(
				start_x
				+ float(column)
				* spacing_x,
				start_y
				+ float(row)
				* spacing_y
			)
		)

	return result


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

	amount = _event_spell_damage_amount(attacker_id, amount, action_type)
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


func refresh_player_board(
	player_index: int
) -> void:
	_close_player_board_spell_preview()
	if player_index < 0 	or player_index >= player_boards.size():
		return

	if player_boards[player_index] == null:
		return

	player_boards[player_index].refresh()


func refresh_all_player_boards() -> void:
	_close_player_board_spell_preview()
	for board in player_boards:
		if board != null:
			board.refresh()


func get_ui_viewer_player_index() -> int:
	if local_viewer_index >= 0:
		return local_viewer_index
	if waiting_for_player_input:
		return int(
			pending_input.get(
				"player_index",
				-1
			)
		)

	return -1


func can_view_private_player_board_spells(
	owner_player_index: int
) -> bool:
	return (
		get_ui_viewer_player_index()
		== owner_player_index
	)


func _ensure_player_board_spell_slots(
	player_index: int
) -> Dictionary:
	if not player_board_spell_slots.has(player_index):
		player_board_spell_slots[player_index] = {
			"Q": {},
			"I": {},
			"II": {},
			"III": {}
		}

	return player_board_spell_slots[player_index]


func _set_player_board_spell_slot(
	player_index: int,
	slot_id: String,
	spell: SpellCardState,
	use_dark_side: bool,
	state: String
) -> void:
	if spell == null:
		return

	var slots: Dictionary = _ensure_player_board_spell_slots(
		player_index
	)

	slots[slot_id] = {
		"spell": spell,
		"use_dark_side": use_dark_side,
		"state": state
	}


func _clear_player_board_spell_slots(
	player_index: int
) -> void:
	player_board_spell_slots[player_index] = {
		"Q": {},
		"I": {},
		"II": {},
		"III": {}
	}

	refresh_player_board(player_index)


func _sync_player_board_prepared_spells(
	player_index: int
) -> void:
	if player_index < 0 	or player_index >= players.size():
		return

	var player = players[player_index]
	var slots: Dictionary = {
		"Q": {},
		"I": {},
		"II": {},
		"III": {}
	}

	var numbered_ids: Array[String] = [
		"I",
		"II",
		"III"
	]

	for i in range(
		min(
			3,
			player.ready_spells.size()
		)
	):
		var ready = player.ready_spells[i]

		if ready == null 		or ready.spell == null:
			continue

		slots[numbered_ids[i]] = {
			"spell": ready.spell,
			"use_dark_side": ready.use_dark_side,
			"state": "prepared"
		}

	if player.quick_spell != null 	and player.quick_spell.spell != null:
		slots["Q"] = {
			"spell": player.quick_spell.spell,
			"use_dark_side": player.quick_spell.use_dark_side,
			"state": "prepared"
		}

	player_board_spell_slots[player_index] = slots
	refresh_player_board(player_index)


func _find_player_board_slot_for_spell(
	player_index: int,
	spell: SpellCardState
) -> String:
	if spell == null:
		return ""

	var slots: Dictionary = _ensure_player_board_spell_slots(
		player_index
	)

	for slot_id_value in [
		"Q",
		"I",
		"II",
		"III"
	]:
		var slot_id: String = str(slot_id_value)
		var entry: Dictionary = slots.get(
			slot_id,
			{}
		)

		if entry.get(
			"spell",
			null
		) == spell:
			return slot_id

	return ""


func _set_player_board_spell_state(
	player_index: int,
	spell: SpellCardState,
	state: String
) -> void:
	var slot_id: String = _find_player_board_slot_for_spell(
		player_index,
		spell
	)

	if slot_id == "":
		return

	var slots: Dictionary = _ensure_player_board_spell_slots(
		player_index
	)
	var entry: Dictionary = slots.get(
		slot_id,
		{}
	)

	if entry.is_empty():
		return

	entry["state"] = state
	slots[slot_id] = entry
	refresh_player_board(player_index)


func _clear_player_board_spell_by_spell(
	player_index: int,
	spell: SpellCardState
) -> void:
	var slot_id: String = _find_player_board_slot_for_spell(
		player_index,
		spell
	)

	if slot_id == "":
		return

	var slots: Dictionary = _ensure_player_board_spell_slots(
		player_index
	)
	slots[slot_id] = {}
	refresh_player_board(player_index)


func get_player_board_spell_slot_data(
	player_index: int,
	slot_id: String,
	viewer: int = -2
) -> Dictionary:
	if network_client:
		return network_slot_views.get(player_index, {}).get(slot_id, {})
	if player_index < 0 	or player_index >= players.size():
		return {}

	var slots: Dictionary = _ensure_player_board_spell_slots(
		player_index
	)
	var entry: Dictionary = slots.get(
		slot_id,
		{}
	)

	if entry.is_empty():
		return {}

	var spell: SpellCardState = entry.get(
		"spell",
		null
	)

	if spell == null:
		return {}

	var state: String = str(
		entry.get(
			"state",
			"prepared"
		)
	)

	var public_card: bool = state == "revealed"
	var can_inspect: bool = public_card or player_index == (get_ui_viewer_player_index() if viewer == -2 else viewer)
	var result: Dictionary = {
		"occupied": true,
		"public": public_card,
		"can_inspect": can_inspect,
		"slot_id": slot_id
	}
	# Hidden occupancy is public; identity, side and armed status are not.
	if can_inspect:
		result["state"] = state
		result["id"] = spell.id
		result["name"] = spell.card_name
		result["school_id"] = spell.school_id
		result["use_dark_side"] = bool(entry.get("use_dark_side", false))
	# Activation markers are public even when the card itself remains hidden.
	for active in players[player_index].active_spells:
		if active.active and active.spell == spell:
			var type: String = active.get_spell_type()
			if type in ["trap", "protection"]:
				result["marker"] = type.to_upper()
			elif str(active.get_side().get("target", "")) not in ["room", "area"]:
				result["marker"] = "PERMANENT"
	return result


func get_player_board_action_request(player_index: int, viewer: int = -2) -> Dictionary:
	if not waiting_for_player_input or (get_ui_viewer_player_index() if viewer == -2 else viewer) != player_index:
		return {}
	if str(pending_input.get("type", "")) != "action_activation_step":
		return {}
	if int(pending_input.get("player_index", -1)) != player_index:
		return {}
	return pending_input


func get_player_board_cast_token(player_index: int, slot_id: String, viewer: int = -2) -> String:
	if network_client:
		return str(network_cast_tokens.get(player_index, {}).get(slot_id, ""))
	var request := get_player_board_action_request(player_index, viewer)
	if request.is_empty():
		return ""
	var entry: Dictionary = _ensure_player_board_spell_slots(player_index).get(slot_id, {})
	var spell = entry.get("spell")
	if spell == null or str(entry.get("state", "")) != "prepared":
		return ""
	var player = players[player_index]
	var action_type := ""
	if slot_id == "Q" and player.quick_spell != null and player.quick_spell.spell == spell:
		action_type = "quick"
	elif not player.ready_spells.is_empty() and player.ready_spells[0].spell == spell:
		action_type = "spell"
	for option in request.get("options", []):
		if action_type != "" and str(option.get("action", {}).get("type", "")) == action_type:
			return str(option.get("token", ""))
	return ""


func get_player_board_action_options(player_index: int, category: String) -> Array:
	var result: Array = []
	for option in get_player_board_action_request(player_index).get("options", []):
		var type: String = str(option.get("action", {}).get("type", ""))
		if (category == "physical" and type in ["explore", "fight", "command"]) \
		or (category == "momentum" and type == "momentum") \
		or (category == "quests" and option.get("kind") == "quest") \
		or (category == "finish" and option.get("kind") == "finish"):
			result.append(option)
	return result


func open_player_board_action(player_index: int, category: String) -> void:
	var options := get_player_board_action_options(player_index, category)
	if options.is_empty():
		return
	if category == "finish":
		submit_beta_input(player_index, {"token": str(options[0].token)})
	elif beta_hud != null:
		beta_hud.open_board_actions(category)


func activate_player_board_spell(player_index: int, slot_id: String, inspect_only: bool = false) -> void:
	var token := get_player_board_cast_token(player_index, slot_id)
	if not inspect_only and token != "":
		submit_beta_input(player_index, {"token": token})
	else:
		open_player_board_spell(player_index, slot_id)


func open_player_board_spell(
	player_index: int,
	slot_id: String
) -> void:
	var data: Dictionary = get_player_board_spell_slot_data(
		player_index,
		slot_id
	)

	if data.is_empty():
		return

	var public_card: bool = bool(
		data.get(
			"public",
			false
		)
	)

	if not bool(data.get("can_inspect", false)):
		return

	var preview = get_node_or_null(
		"SpellCardPreview"
	)

	if preview == null:
		preview = spell_preview_script.new()
		preview.name = "SpellCardPreview"
		add_child(preview)

	preview.show_spell(
		str(data.get("id", "")),
		str(data.get("name", "Spell")),
		str(data.get("school_id", "")),
		bool(data.get("use_dark_side", false)),
		public_card
	)


func _close_player_board_spell_preview() -> void:
	# Input handoffs and slot mutations refresh boards. Dismiss any old snapshot.
	var preview = get_node_or_null("SpellCardPreview")
	if preview != null:
		preview.hide_preview()
	_close_reference_card_preview()


func can_inspect_quest(quest: QuestState) -> bool:
	if quest == null or quest.owner_id < 0 or quest.owner_id >= players.size():
		return false
	var player = players[quest.owner_id]
	if not player.active_quests.has(quest) and not player.completed_quests.has(quest):
		return false
	return quest.revealed or quest.completed or quest.solved or get_ui_viewer_player_index() == quest.owner_id


func get_player_quest_cards(player_index: int, section: String) -> Array:
	var result: Array = []
	if player_index < 0 or player_index >= players.size():
		return result
	var player = players[player_index]
	for quest in player.active_quests + player.completed_quests:
		var matches: bool = (section == "private" and not quest.revealed and not quest.completed) or (section == "revealed" and quest.revealed and not quest.completed) or (section == "completed" and quest.completed and not quest.solved)
		if matches and can_inspect_quest(quest):
			result.append({"id": quest.get_id(), "name": quest.get_name(), "quest": quest})
	return result


func get_player_board_quest_cards(player_index: int, section: String) -> Array:
	var result: Array = []
	if player_index < 0 or player_index >= players.size():
		return result
	var player = players[player_index]
	for quest in player.active_quests + player.completed_quests:
		if (section == "revealed" and quest.completed) or (section == "completed" and not quest.completed):
			continue
		if not can_inspect_quest(quest):
			result.append({"can_inspect": false})
		else:
			result.append({"can_inspect": true, "id": quest.get_id(), "name": quest.get_name(), "quest": quest})
	return result


func open_quest_card(quest: QuestState) -> void:
	if not can_inspect_quest(quest):
		return
	inspected_quest = quest
	var preview = _reference_card_preview()
	preview.show_card("quests", quest.get_id(), quest.get_name(),
		"Moon %d · Progress %d/%d · Reward %d Power\n\nTask:\n%s\n\nEffects:\n%s"
		% [quest.get_moon(), quest.progress, quest.get_cube_slots(), quest.get_power_reward(),
			ReferenceCardPreview.describe_rules(quest.get_task()), ReferenceCardPreview.describe_rules(quest.get_effects())])


func open_event_card(event: EventCardState) -> void:
	if event == null or (not active_events.has(event) and not event_discard.has(event)):
		return
	inspected_quest = null
	_reference_card_preview().show_card("events", event.id, event.event_name,
		"Moon %d · %s\n%s\n\nEffects:\n%s" % [event.moon, event.phase, event.text, ReferenceCardPreview.describe_rules(event.effects)])


func _reference_card_preview():
	var preview = get_node_or_null("ReferenceCardPreview")
	if preview == null:
		preview = ReferenceCardPreview.new()
		preview.name = "ReferenceCardPreview"
		add_child(preview)
	return preview


func _close_reference_card_preview() -> void:
	inspected_quest = null
	var preview = get_node_or_null("ReferenceCardPreview")
	if preview != null:
		preview.hide_preview()


func _refresh_permanent_room_markers() -> void:
	for room_id in room_id_by_coord.values():
		var room = get_room_by_id(str(room_id))
		if room == null:
			continue
		var old = room.get_node_or_null("PermanentMarkers")
		if old != null:
			old.free()
		var markers := VBoxContainer.new()
		markers.name = "PermanentMarkers"
		markers.position = Vector2(-90, 55)
		markers.z_index = 80
		room.add_child(markers)
		for player in players:
			for active in player.active_spells:
				if not active.active or not _is_ongoing_revealed_spell(active.get_side()):
					continue
				if str(active.get_side().get("target", "")) not in ["room", "area"] or str(active.context.get("target_room_id", "")) != str(room_id):
					continue
				var button := Button.new()
				button.text = "P%d · PERMANENT" % [active.owner_id + 1]
				button.tooltip_text = active.spell.card_name
				button.pressed.connect(open_player_board_spell.bind(active.owner_id, _find_player_board_slot_for_spell(active.owner_id, active.spell)))
				markers.add_child(button)


func create_player_boards():
	for board in player_boards:
		if board != null:
			board.queue_free()

	player_boards.clear()

	for i in range(players.size()):
		var board = player_board_scene.instantiate()

		board.setup(players[i], self, i)

		add_child(board)
		player_boards.append(board)

	update_player_board_positions()
	
func get_lodge_table_bounds() -> Rect2:
	var bounds := Rect2(board_center, Vector2.ZERO)
	for child in get_children():
		if child.has_meta("hex_coord"):
			bounds = bounds.merge(Rect2(child.position - Vector2(HEX_RADIUS, HEX_RADIUS), Vector2.ONE * HEX_RADIUS * 2.0))
	for side_board in [$PowerBoard, $EventBoard]:
		var shape: Polygon2D = side_board.get_node("BoardShape")
		for point in shape.polygon:
			bounds = bounds.expand(side_board.position + shape.position + point)
	return bounds


func get_tabletop_bounds() -> Rect2:
	var bounds := get_lodge_table_bounds()
	for board in player_boards:
		bounds = bounds.merge(Rect2(board.position, board.BOARD_SIZE * board.scale))
	return bounds.grow(24.0)


func update_player_board_positions():
	# Keep the tuned Lodge/side-board geometry. Place PlayerBoards outside
	# its real bounds, using their full footprint including external cards for every player count.
	var bounds := get_lodge_table_bounds()
	var board_scale := 0.65
	var gap := 24.0
	for i in range(player_boards.size()):
		var board = player_boards[i]
		board.scale = Vector2.ONE * board_scale
		var extent: Vector2 = board.BOARD_SIZE * board_scale
		var rows := ceili(float(player_boards.size() - i % 2) / 2.0)
		var total_height: float = rows * extent.y + (rows - 1) * gap
		var y: float = bounds.get_center().y - total_height * 0.5 + (i / 2) * (extent.y + gap)
		var x: float = bounds.position.x - gap - extent.x if i % 2 == 0 else bounds.end.x + gap
		board.position = Vector2(x, y)


func _ensure_beta_background() -> void:
	if beta_background_layer != null:
		return

	beta_background_layer = CanvasLayer.new()
	beta_background_layer.layer = -100
	beta_background_layer.name = "BetaBackgroundLayer"
	add_child(beta_background_layer)

	var background := ColorRect.new()
	background.name = "BetaBackground"
	background.color = Color(0.29, 0.29, 0.29, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	beta_background_layer.add_child(background)


func _reposition_hex_nodes() -> void:
	for child in get_children():
		if not child.has_meta("hex_coord"):
			continue

		var coord_value = child.get_meta(
			"hex_coord"
		)

		if not coord_value is Vector2i:
			continue

		child.position = hex_to_pixel(
			coord_value
		)


func _apply_beta_table_layout() -> void:
	scale = Vector2.ONE
	position = Vector2.ZERO

	if not enable_beta_hud or run_tests_on_ready:
		return

	_ensure_beta_background()
	if get_node_or_null("TableCamera") == null:
		var camera = preload("res://table_camera.gd").new()
		camera.name = "TableCamera"
		add_child(camera)

	var viewport_size: Vector2 = get_viewport_rect().size
	var usable_width: float = max(
		640.0,
		viewport_size.x - beta_sidebar_width
	)

	board_center = Vector2(
		usable_width * 0.5,
		viewport_size.y * 0.54
	)

	_reposition_hex_nodes()
	update_table_layout()
	get_node("TableCamera").call_deferred("adapt_to_viewport")


func _on_beta_viewport_resized() -> void:
	_apply_beta_table_layout()

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
	refresh_model_tokens()


func set_player_power(player_index: int, value: int):
	if player_index < 0 or player_index >= players.size():
		print("ERRORE: player_index non valido: ", player_index)
		return

	value = maxi(0, value)

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
	value = maxi(0, value)

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

	refresh_model_tokens()
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
	suppressed_trigger_types: Array = [],
	action_type: String = "",
	source_model_type: String = "",
	source_evocation: EvocationState = null
) -> int:
	if evocation == null or amount <= 0 or is_event_active("immortals"):
		return 0
	amount = _event_spell_damage_amount(attacker_id, amount, action_type)
	# Rebirth, Immunity: controlled Evocations ignore their Mage's damage.
	if attacker_id >= 0 and get_evocation_controller_id(evocation) == attacker_id:
		return 0

	if evocation.is_defeated():
		return 0

	var requested: int = min(amount, evocation.get_remaining_health())
	if requested <= 0:
		return 0

	var result_context: Dictionary = {}
	if not active_effect_context.is_empty():
		result_context = active_effect_context

	if source_model_type == "":
		source_model_type = (
			"black_rose"
			if attacker_id == -1
			else "mage"
		)

	queue_resolution({
		"type": "evocation_damage",
		"step": "pre_event",
		"attacker_id": attacker_id,
		"evocation": evocation,
		"amount": requested,
		"action_type": action_type,
		"source_model_type": source_model_type,
		"source_evocation": source_evocation,
		"suppressed_trigger_types": _to_string_array(suppressed_trigger_types),
		"actual_damage": 0,
		"result_context": result_context
	})

	return requested

func process_game_event(
	event: GameEvent
) -> bool:
	if event == null:
		return true

	if quest_manager != null:
		quest_manager.process_game_event(
			self,
			event
		)

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

	refresh_model_tokens()

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
		"attacker_id": get_evocation_controller_id(evocation),
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
	player_index: int,
	excluded_spell: SpellCardState = null
) -> Dictionary:

	var counts: Dictionary = {}

	if player_index < 0 \
	or player_index >= players.size():
		return counts

	for revealed in players[player_index].revealed_spells:
		if revealed.spell == excluded_spell:
			continue
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
	required_elements: Array,
	excluded_spell: SpellCardState = null
) -> bool:

	var counts = get_revealed_element_counts(
		player_index, excluded_spell
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


func _enhancement_required_elements(
	enhancement: Dictionary
) -> Array:
	if enhancement.has("requires"):
		var required = enhancement.get("requires", [])
		if required is Array:
			return required.duplicate()
		return [required]

	if enhancement.has("elements"):
		var elements = enhancement.get("elements", [])
		if elements is Array:
			return elements.duplicate()
		return [elements]

	var single_element: String = str(
		enhancement.get("element", "")
	)

	if single_element != "":
		return [single_element]

	return []


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
# =============================================================================
# TARGETING: RANGE + LINE OF SIGHT
# =============================================================================
# BRWR numeric Range requires Line of Sight. On the axial hex grid used by the
# Lodge, two Room centres lie on the same straight row iff q, r, or q+r is
# equal. Range "*" ignores Line of Sight.
# =============================================================================

func has_line_of_sight_between_coords(
	a: Vector2i,
	b: Vector2i
) -> bool:
	if a == b:
		return true

	return (
		a.x == b.x
		or a.y == b.y
		or (a.x + a.y) == (b.x + b.y)
	)


func has_line_of_sight_between_rooms(
	from_room_id: String,
	to_room_id: String
) -> bool:
	if not is_lodge_room_id(from_room_id) \
	or not is_lodge_room_id(to_room_id):
		return false

	var from_coord: Vector2i = room_id_to_coord(from_room_id)
	var to_coord: Vector2i = room_id_to_coord(to_room_id)

	if from_coord == Vector2i(9999, 9999) \
	or to_coord == Vector2i(9999, 9999):
		return false

	return has_line_of_sight_between_coords(
		from_coord,
		to_coord
	)


func is_room_within_effect_range(
	caster_room_id: String,
	target_room_id: String,
	range_value
) -> bool:
	if not is_lodge_room_id(caster_room_id) \
	or not is_lodge_room_id(target_room_id):
		return false

	# Unlimited Range can target anywhere in the Lodge and explicitly does
	# not require Line of Sight.
	if str(range_value) == "*":
		return true

	if range_value == null:
		return true

	var max_range: int = int(range_value)
	if max_range < 0:
		return false

	var caster_coord: Vector2i = room_id_to_coord(caster_room_id)
	var target_coord: Vector2i = room_id_to_coord(target_room_id)

	if caster_coord == Vector2i(9999, 9999) \
	or target_coord == Vector2i(9999, 9999):
		return false

	if get_hex_distance(caster_coord, target_coord) > max_range:
		return false

	return has_line_of_sight_between_coords(
		caster_coord,
		target_coord
	)


func validate_target_range_from_context(
	caster_id: int,
	target_type: String,
	range_value,
	context: Dictionary
) -> bool:
	if caster_id < 0 or caster_id >= players.size():
		return false

	if bool(context.get("target_is_dummy", false)) \
	or str(context.get("target_model_type", "")) == "dummy":
		return true

	var caster_mage = players[caster_id].mage
	if caster_mage == null:
		return false

	var normalized_target: String = target_type.strip_edges().to_lower()

	# Self and Special targets do not select another Room/Model whose Range
	# needs to be checked here.
	if normalized_target == "" \
	or normalized_target == "self" \
	or normalized_target == "activating_mage" \
	or normalized_target == "special":
		return true

	var target_room_id: String = ""

	match normalized_target:
		"room", "area", "choose_room":
			target_room_id = str(
				context.get("target_room_id", "")
			)

			# Some Effects determine their target later in their own resolver.
			if target_room_id == "":
				return true

		"mage":
			if not context.has("target_player_index"):
				return true

			var target_player_index: int = int(
				context.get("target_player_index", -1)
			)

			if target_player_index < 0 \
			or target_player_index >= players.size():
				return false

			var target_mage = players[target_player_index].mage
			if target_mage == null or target_mage.in_cell:
				return false

			target_room_id = target_mage.room_id

		"evocation":
			if not context.has("target_evocation"):
				return true

			var target_evocation = context.get("target_evocation")
			if target_evocation == null:
				return false

			target_room_id = str(target_evocation.room_id)

		"model", "choose_model":
			# A Model target may be a Mage or an Evocation.
			if context.has("target_player_index") \
			and int(context.get("target_player_index", -1)) >= 0:
				var model_player_index: int = int(
					context.get("target_player_index", -1)
				)

				if model_player_index >= players.size():
					return false

				var model_mage = players[model_player_index].mage
				if model_mage == null or model_mage.in_cell:
					return false

				target_room_id = model_mage.room_id

			elif context.has("target_evocation"):
				var model_evocation = context.get("target_evocation")
				if model_evocation == null:
					return false

				target_room_id = str(model_evocation.room_id)

			else:
				return true

		_:
			# Unknown/custom target types are resolved by their dedicated
			# Effect logic rather than rejected here.
			return true

	if target_room_id == "":
		return true

	return is_room_within_effect_range(
		caster_mage.room_id,
		target_room_id,
		range_value
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
		var legal_exits: Array[String] = (
			get_player_cell_exit_room_ids(
				player_index
			)
		)

		if not legal_exits.has(destination_room_id):
			print(
				"Player ", player_index + 1,
				" must exit Cell through one of ",
				legal_exits
			)
			return false

		mage.room_id = destination_room_id
		mage.room_coord = destination_coord
		mage.in_cell = false
		print(
			"Player ", player_index + 1,
			" entered the Lodge through ", destination_room_id
		)
		refresh_model_tokens()
		return true

	if get_hex_distance(mage.room_coord, destination_coord) > max_distance:
		return false

	mage.room_id = destination_room_id
	mage.room_coord = destination_coord
	mage.in_cell = false
	print("Player ", player_index + 1, " moved to ", destination_room_id)
	refresh_model_tokens()
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

	refresh_model_tokens()
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


func get_evocation_by_owner_index(
	owner_id: int,
	evocation_index: int
) -> EvocationState:
	if owner_id < 0 or owner_id >= players.size():
		return null

	if evocation_index < 0 \
	or evocation_index >= players[owner_id].evocations.size():
		return null

	return players[owner_id].evocations[evocation_index]


func is_evocation_in_play(
	evocation: EvocationState
) -> bool:
	if evocation == null:
		return false

	var owner_id: int = int(evocation.owner_id)
	if owner_id < 0 or owner_id >= players.size():
		return false

	return players[owner_id].evocations.has(evocation)


func get_evocation_controller_id(
	evocation: EvocationState
) -> int:
	if evocation == null:
		return -999

	var controller_id: int = int(evocation.controller_id)

	if controller_id < 0:
		controller_id = int(evocation.owner_id)

	return controller_id


func finalize_evocation_removal(
	evocation: EvocationState
) -> bool:
	if evocation == null:
		return false

	var owner_id: int = int(evocation.owner_id)
	if owner_id < 0 or owner_id >= players.size():
		return false

	var owner = players[owner_id]
	var index: int = owner.evocations.find(evocation)

	if index == -1:
		return false

	# Damage Cubes leave the card when the Evocation leaves play.
	var damage_snapshot: Array[int] = evocation.damage_cubes.duplicate()

	for cube_owner_id in damage_snapshot:
		return_owner_cubes(
			int(cube_owner_id),
			1
		)

	evocation.damage_cubes.clear()
	owner.evocations.remove_at(index)

	refresh_model_tokens()
	return true


func _valid_mage_physical_attack_evocation(
	attacker_id: int,
	evocation: EvocationState
) -> bool:
	if attacker_id < 0 or attacker_id >= players.size():
		return false

	if evocation == null \
	or evocation.is_defeated() \
	or not is_evocation_in_play(evocation):
		return false

	var attacker_mage = players[attacker_id].mage

	if attacker_mage == null or attacker_mage.in_cell:
		return false

	if evocation.room_id != attacker_mage.room_id:
		return false

	# A Mage and the Evocations they control ignore Damage resolved by that
	# Mage. Do not expose such a Model as a useful Physical Attack target.
	return get_evocation_controller_id(evocation) != attacker_id

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
func clone_spell_card(
	spell: SpellCardState
) -> SpellCardState:

	if spell == null:
		return null

	var copy := SpellCardState.new(
		spell.id,
		spell.card_name,
		spell.school_id,
		spell.light_side.duplicate(true),
		spell.dark_side.duplicate(true),
		spell.copies,
		spell.instability
	)

	copy.personal = spell.personal
	copy.forgotten = spell.forgotten
	copy.instability = spell.instability

	return copy


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

				var spell_copy: SpellCardState = clone_spell_card(spell)

				if spell_copy != null:
					library.append(spell_copy)


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

		# Forgotten Spells belong to their own deck. They are NOT a School of
		# Magic and must never appear among the active Study Libraries.
		if spell.forgotten 		or school_id == "forgotten":
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


	var player = players[
		player_index
	]

	var hand_index: int = player.hand.find(
		spell
	)

	if hand_index == -1:
		return false

	player.hand.remove_at(
		hand_index
	)

	move_spell_to_memories_or_remove(
		player_index,
		spell
	)

	print(
		"Player ",
		player_index + 1,
		" discarded ",
		spell.card_name,
		(
			" out of the game"
			if spell.forgotten
			else " to Memories"
		)
	)

	return true

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
	forgotten_removed_from_game.clear()

	for spell in spell_database.spells.values():

		if not spell.forgotten:
			continue

		for i in range(spell.copies):
			var spell_copy: SpellCardState = clone_spell_card(spell)

			if spell_copy != null:
				forgotten_deck.append(spell_copy)

	shuffle_with_rng(
		forgotten_deck
	)

	print(
		"Forgotten deck created: ",
		forgotten_deck.size(),
		" cards"
	)

func draw_forgotten_spell(
	player_index: int
) -> SpellCardState:
	if player_index < 0 \
	or player_index >= players.size():
		return null

	if forgotten_deck.is_empty():
		print("Forgotten Spell Deck is empty")
		return null

	var spell: SpellCardState = (
		forgotten_deck.pop_back()
	)

	players[player_index].hand.append(
		spell
	)

	print(
		"Player ",
		player_index + 1,
		" drew Forgotten Spell: ",
		spell.card_name
	)

	return spell


func remove_forgotten_from_game(
	spell: SpellCardState
) -> bool:
	if spell == null or not spell.forgotten:
		return false

	if not forgotten_removed_from_game.has(
		spell
	):
		forgotten_removed_from_game.append(
			spell
		)

	print(
		"Forgotten Spell removed from game: ",
		spell.card_name
	)

	return true


func move_spell_to_memories_or_remove(
	player_index: int,
	spell: SpellCardState
) -> bool:
	if player_index < 0 \
	or player_index >= players.size() \
	or spell == null:
		return false

	if spell.forgotten:
		return remove_forgotten_from_game(
			spell
		)

	players[player_index].add_spell_to_memories(
		spell
	)

	return true


func get_forgotten_hand_spells(
	player_index: int
) -> Array[SpellCardState]:
	var result: Array[SpellCardState] = []

	if player_index < 0 \
	or player_index >= players.size():
		return result

	for spell in players[player_index].hand:
		if spell != null and spell.forgotten:
			result.append(spell)

	return result
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

	var board_slot: String = _find_player_board_slot_for_spell(
		player_index, revealed_state.spell
	)
	var new_revealed = RevealedSpellState.new(
		replacement_spell,
		use_dark_side,
		board_slot if board_slot != "" else revealed_state.slot_id
	)


	player.revealed_spells[
		revealed_index
	] = new_revealed

	if board_slot != "":
		_set_player_board_spell_slot(
			player_index, board_slot, replacement_spell, use_dark_side, "revealed"
		)
		refresh_player_board(player_index)


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
	context: Dictionary = {},
	from_moon: int = 0
) -> EventCardState:

	if drawing_player_index < 0 \
	or drawing_player_index >= players.size():

		return null


	var moon: int = from_moon if from_moon > 0 else current_moon


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


		var resume_phase: bool = bool(event_context.get("resume_black_rose", false))
		event_context.erase("resume_black_rose")
		if resume_phase:
			black_rose_instant_event_queued = true
		queue_resolution({
			"type": "event_sequence", "event": event, "context": event_context,
			"discard_after": true,
			"on_complete": "continue_black_rose_event" if resume_phase else ""
		})

		return event


	# =====================================================
	# NORMAL EVENT
	# =====================================================

	if not place_event_on_board(
		event
	):

		return null


	if event.phase == "always":
		var entry_context: Dictionary = context.duplicate()
		entry_context["game"] = self
		entry_context["event"] = event
		var resume_phase: bool = bool(entry_context.get("resume_black_rose", false))
		entry_context.erase("resume_black_rose")
		if resume_phase:
			black_rose_instant_event_queued = true
		queue_resolution({"type": "event_sequence", "event": event, "context": entry_context,
			"on_complete": "continue_black_rose_event" if resume_phase else ""})
	return event
	
func resolve_events_for_phase(
	phase: String,
	context: Dictionary = {}
) -> bool:

	var phase_events: Array = active_events.filter(func(event): return event != null and event.phase == phase)
	if phase_events.is_empty():
		return true
	return queue_resolution({"type": "action_events", "events": phase_events, "context": context})
	
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

func get_active_event_effects(effect_type: String) -> Array:
	var effects: Array = []
	for event in active_events:
		if event == null or (event.phase != "always" and event.phase != current_phase):
			continue
		for effect in event.effects:
			if effect.get("type", "") == effect_type:
				effects.append(effect)
	return effects

func _event_spell_damage_amount(attacker_id: int, amount: int, action_type: String) -> int:
	if attacker_id < 0 or action_type != "spell" or active_effect_context.get("resolver_kind", "") != "spell" or active_effect_context.get("spell_type", "") != "combat":
		return amount
	for effect in get_active_event_effects("combat_spell_damage_bonus"):
		amount += int(effect.get("amount", 1))
	return amount

func _apply_event_after_spell(player_index: int, spell_type: String) -> void:
	for effect in get_active_event_effects("on_spell_types_resolved_black_rose_damage"):
		if spell_type in effect.get("spell_types", []):
			deal_damage(-1, player_index, int(effect.get("amount", 1)), "event")

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
	refresh_model_tokens()

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

	# Effect-resolution metadata used by Quest tasks.  Because
	# active_effect_context points to the same Dictionary used by the current
	# effect_sequence frame, the value remains available after the resolver
	# returns.
	if placed > 0 	and not active_effect_context.is_empty():
		active_effect_context["effect_instability_placed"] = (
			int(active_effect_context.get("effect_instability_placed", 0))
			+ placed
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

	black_rose_instant_event_queued = false
	event_context["resume_black_rose"] = true
	var drawn_event: EventCardState = draw_event(
		drawing_player_index,
		event_context
	)

	if drawn_event == null:
		print(
			"Black Rose Phase: Event draw failed"
		)
		return false

	if black_rose_instant_event_queued:
		return true
	return _continue_black_rose_after_event(event_context)


func _continue_black_rose_after_event(event_context: Dictionary) -> bool:
	return queue_resolution({
		"type": "action_events", "context": event_context,
		"events": active_events.filter(func(event): return event != null and event.phase == PHASE_BLACK_ROSE),
		"on_complete": "continue_black_rose_quests"
	})


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


		move_spell_to_memories_or_remove(
			player_index,
			spell
		)


		print(
			"Player ",
			player_index + 1,
			" discards ",
			spell.id,
			(
				" out of the game"
				if spell.forgotten
				else " to Memories"
			),
			" due to Hand Limit"
		)


	return true
func prepare_player_spells(
	player_index: int,
	ready_hand_indices: Array,
	ready_dark_sides: Array,
	quick_hand_index: int = -1,
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

	var total_spells: int = ready_hand_indices.size()

	if quick_hand_index != -1:
		total_spells += 1


	if total_spells < 2 \
	or total_spells > 4:

		print(
			"Preparation: Player ",
			player_index + 1,
			" must prepare between 2 and 4 Spells"
		)

		return false


	if ready_hand_indices.size() > 3:

		print(
			"Preparation: Player ",
			player_index + 1,
			" cannot prepare more than 3 numbered Spells"
		)

		return false


	if ready_dark_sides.size() != ready_hand_indices.size():

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
	#
	# Hand indices identify physical copies, so two cards
	# with the same Spell id can be prepared independently.
	# Store the object references now, before removals shift
	# the Hand indices.
	# =====================================================

	var used_hand_indices: Array[int] = []
	var ready_spells_to_prepare: Array[SpellCardState] = []

	for hand_index_value in ready_hand_indices:

		var hand_index: int = int(hand_index_value)

		if hand_index < 0 or hand_index >= player.hand.size():
			print(
				"Preparation: Hand index ",
				hand_index,
				" is invalid for Player ",
				player_index + 1
			)
			return false

		if used_hand_indices.has(hand_index):
			print(
				"Preparation: Hand card ",
				hand_index,
				" selected more than once"
			)
			return false

		var spell: SpellCardState = player.hand[hand_index]

		if spell == null:
			print(
				"Preparation: null Spell at Hand index ",
				hand_index
			)
			return false

		used_hand_indices.append(hand_index)
		ready_spells_to_prepare.append(spell)


	var quick_spell_to_prepare: SpellCardState = null

	if quick_hand_index != -1:

		if quick_hand_index < 0 or quick_hand_index >= player.hand.size():
			print(
				"Preparation: Quick Spell Hand index ",
				quick_hand_index,
				" is invalid"
			)
			return false

		if used_hand_indices.has(quick_hand_index):
			print(
				"Preparation: Quick Spell already used in numbered slots"
			)
			return false

		quick_spell_to_prepare = player.hand[quick_hand_index]

		if quick_spell_to_prepare == null:
			print(
				"Preparation: null Quick Spell at Hand index ",
				quick_hand_index
			)
			return false


	# =====================================================
	# PREPARE I / II / III
	# =====================================================

	for i in range(ready_spells_to_prepare.size()):

		var spell: SpellCardState = ready_spells_to_prepare[i]
		var use_dark_side: bool = bool(ready_dark_sides[i])

		if not player.add_ready_spell(spell, use_dark_side):
			print(
				"Preparation: failed to prepare ",
				spell.id
			)
			return false


	# =====================================================
	# PREPARE QUICK
	# =====================================================

	if quick_spell_to_prepare != null:

		if not player.set_quick_spell(
			quick_spell_to_prepare,
			quick_dark_side
		):
			print(
				"Preparation: failed to prepare Quick Spell ",
				quick_spell_to_prepare.id
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

	for i in range(player.ready_spells.size()):

		var ready: ReadySpellState = player.ready_spells[i]

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

	_sync_player_board_prepared_spells(player_index)
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
	# Command, but they may leave the Cell either through a Physical Action
	# that moves them or through Momentum by discarding a Ready Spell.
	if player.mage != null and player.mage.in_cell:
		return (
			(
				player.has_physical_action()
				and player.mage.speed > 0
			)
			or not player.ready_spells.is_empty()
			or player.quick_spell != null
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
	context: Dictionary = {},
	target_model_type: String = "",
	target_evocation: EvocationState = null
) -> bool:
	if target_model_type == "" 	and target_player_index >= 0:
		target_model_type = "mage"

	return queue_resolution({
		"type": "fight",
		"step": "start",
		"player_index": player_index,
		"target_model_type": target_model_type,
		"target_player_index": target_player_index,
		"target_evocation": target_evocation,
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


func _is_valid_momentum_destination(
	player_index: int,
	destination_room_id: String
) -> bool:
	if player_index < 0 or player_index >= players.size():
		return false

	var mage = players[player_index].mage
	if mage == null:
		return false

	# "You may Move 1": outside the Cell the movement is optional.
	if destination_room_id == "":
		return not mage.in_cell

	if not is_lodge_room_id(destination_room_id):
		return false

	if mage.in_cell:
		return get_player_cell_exit_room_ids(
			player_index
		).has(
			destination_room_id
		)

	var destination_coord: Vector2i = room_id_to_coord(
		destination_room_id
	)

	if destination_coord == Vector2i(9999, 9999):
		return false

	return get_hex_distance(
		mage.room_coord,
		destination_coord
	) <= 1

func perform_momentum_action(
	player_index: int,
	ready_index: int = -1,
	use_quick: bool = false,
	destination_room_id: String = "",
	context: Dictionary = {}
) -> bool:
	if player_index < 0 or player_index >= players.size():
		return false

	var player = players[player_index]

	if use_quick:
		if player.quick_spell == null:
			print("Momentum: no Quick Spell to discard")
			return false
	else:
		if ready_index < 0 or ready_index >= player.ready_spells.size():
			print("Momentum: invalid Ready Spell index")
			return false

	if not _is_valid_momentum_destination(
		player_index,
		destination_room_id
	):
		print("Momentum: invalid optional Move 1 destination")
		return false

	return queue_resolution({
		"type": "momentum",
		"step": "discard",
		"player_index": player_index,
		"ready_index": ready_index,
		"use_quick": use_quick,
		"destination_room_id": destination_room_id,
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
			var target_evocation: EvocationState = null

			if str(
				action.get(
					"target_model_type",
					""
				)
			) == "evocation":
				target_evocation = get_evocation_by_owner_index(
					int(
						action.get(
							"target_evocation_owner_id",
							-1
						)
					),
					int(
						action.get(
							"target_evocation_index",
							-1
						)
					)
				)

			return perform_fight_action(
				player_index,
				int(action.get("target_player_index", -1)),
				bool(action.get("activate_room_first", false)),
				bool(action.get("perform_attack", true)),
				bool(action.get("perform_room_activation", true)),
				action_context,
				str(action.get("target_model_type", "")),
				target_evocation
			)
		"command":
			return perform_command_action(
				player_index,
				int(action.get("evocation_index", -1)),
				action_context
			)
		"momentum":
			return perform_momentum_action(
				player_index,
				int(action.get("ready_index", -1)),
				bool(action.get("use_quick", false)),
				str(action.get("destination_room_id", "")),
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


	action_phase_cursor = 0
	action_phase_activation_round = 1
	_reset_stepwise_action_activation()
	# Events can suspend for choices, damage triggers and Evocation activation.
	return queue_resolution({
		"type": "action_events", "context": phase_context,
		"events": active_events.filter(func(event): return event != null and event.phase == PHASE_ACTION),
		"index": 0, "on_complete": "advance_action_phase"
	})
	

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
	evocation_phase_activated.clear()
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
	input_revision += 1
	refresh_all_player_boards()


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
	clear_lodge_room_choices()
	clear_board_target_choices()

	var resolved_request: Dictionary = (
		pending_input.duplicate(true)
	)


	pending_input.clear()
	waiting_for_player_input = false
	refresh_all_player_boards()


	player_input_resolved.emit(
		resolved_request
	)


# =========================================================
# EFFECT CHOICES
# =========================================================

func _set_interactive_effect_choice(
	context: Dictionary,
	context_key: String,
	value
) -> void:
	context[context_key] = value

	var keys: Array = context.get(
		"_interactive_choice_keys",
		[]
	)

	if not context_key in keys:
		keys.append(context_key)

	context["_interactive_choice_keys"] = keys


func _clear_interactive_effect_choices(
	context: Dictionary
) -> void:
	var keys: Array = context.get(
		"_interactive_choice_keys",
		[]
	)

	for key_value in keys:
		context.erase(str(key_value))

	context.erase("_interactive_choice_keys")


func request_effect_choice(
	player_index: int,
	choice_kind: String,
	context: Dictionary,
	context_key: String,
	options: Array,
	min_select: int = 1,
	max_select: int = 1,
	prompt: String = ""
) -> bool:
	if waiting_for_player_input:
		return false

	if player_index < 0 or player_index >= players.size():
		return false

	if context_key == "" or options.is_empty():
		return false

	if min_select < 0 or max_select < min_select:
		return false

	var public_options: Array = []
	var runtime_values: Dictionary = {}

	for option_value in options:
		if not option_value is Dictionary:
			continue

		var option: Dictionary = option_value
		var token: String = str(option.get("token", ""))

		if token == "" or runtime_values.has(token):
			continue

		runtime_values[token] = option.get("value")

		var public_option: Dictionary = option.duplicate(true)
		public_option.erase("value")
		# Public board addresses travel with choices, including remote clients.
		var value = option.get("value")
		var evocation = value if value is EvocationState else (value.get("evocation") if value is Dictionary else null)
		if evocation is EvocationState:
			public_option["owner_id"] = evocation.owner_id
			public_option["evocation_index"] = players[evocation.owner_id].evocations.find(evocation)
		if value is Dictionary and value.has("evocation_target_model_type"):
			var target: Dictionary = {}
			if str(value.evocation_target_model_type) == "mage":
				target["player_index"] = int(value.get("evocation_target_player_index", -1))
			elif str(value.evocation_target_model_type) == "evocation":
				target = {"owner_id": int(value.get("evocation_target_evocation_owner_id", -1)), "evocation_index": int(value.get("evocation_target_evocation_index", -1))}
			public_option["board_target"] = target
		if value is Dictionary and value.has("player_index"):
			public_option["player_index"] = value.player_index
		if token.begins_with("damage:") or token.begins_with("instability:"):
			public_option["cube_room_id"] = str(context.get("target_room_id", ""))
			public_option["cube_player_index"] = int(option.get("cube_player_index", context.get("target_player_index", player_index)))
			var target_evocation = context.get("target_evocation")
			if target_evocation is EvocationState:
				public_option["cube_evocation_owner"] = target_evocation.owner_id
				public_option["cube_evocation_index"] = players[target_evocation.owner_id].evocations.find(target_evocation)
		public_options.append(public_option)

	if public_options.is_empty():
		return false

	pending_effect_choice_context = context
	pending_effect_choice_values = runtime_values
	var movement_origin: String = str(context.get("movement_origin_room_id", ""))
	if choice_kind == "evocation_activation_plan" and context.get("evocation") is EvocationState:
		movement_origin = str(context.evocation.room_id)

	return request_player_input({
		"type": "effect_choice",
		"phase": current_phase,
		"player_index": player_index,
		"choice_kind": choice_kind,
		"context_key": context_key,
		"movement_origin_room_id": movement_origin,
		"prompt": prompt,
		"min_select": min_select,
		"max_select": max_select,
		"options": public_options
	})


func submit_effect_choice(
	player_index: int,
	selection
) -> bool:
	if not waiting_for_player_input:
		print("submit_effect_choice: no input requested")
		return false

	if str(pending_input.get("type", "")) != "effect_choice":
		print("submit_effect_choice: wrong pending input type")
		return false

	if player_index != int(pending_input.get("player_index", -1)):
		print("submit_effect_choice: wrong player")
		return false

	if pending_effect_choice_context.is_empty():
		print("submit_effect_choice: missing live Effect context")
		return false

	var min_select: int = int(pending_input.get("min_select", 1))
	var max_select: int = int(pending_input.get("max_select", 1))
	var tokens: Array = []

	if max_select <= 1:
		if selection is Array:
			var selection_array: Array = selection
			if selection_array.size() > 1:
				return false
			if not selection_array.is_empty():
				tokens.append(str(selection_array[0]))
		elif str(selection) != "":
			tokens.append(str(selection))
	else:
		if not selection is Array:
			return false

		for token_value in selection:
			tokens.append(str(token_value))

	if tokens.size() < min_select or tokens.size() > max_select:
		return false

	var seen_tokens: Dictionary = {}
	var runtime_selection: Array = []

	for token in tokens:
		if token == "" or seen_tokens.has(token):
			return false

		if not pending_effect_choice_values.has(token):
			return false

		seen_tokens[token] = true
		runtime_selection.append(
			pending_effect_choice_values[token]
		)

	var context_key: String = str(
		pending_input.get("context_key", "")
	)

	if context_key == "":
		return false

	if max_select <= 1:
		var selected_value = null
		if not runtime_selection.is_empty():
			selected_value = runtime_selection[0]

		_set_interactive_effect_choice(
			pending_effect_choice_context,
			context_key,
			selected_value
		)
	else:
		_set_interactive_effect_choice(
			pending_effect_choice_context,
			context_key,
			runtime_selection
		)

	pending_effect_choice_context = {}
	pending_effect_choice_values = {}

	clear_player_input()

	return process_resolution_stack()


func _quest_effect_room_in_range(
	caster_id: int,
	room_id: String,
	range_value
) -> bool:
	if caster_id < 0 or caster_id >= players.size():
		return false

	var mage = players[caster_id].mage
	if mage == null or mage.in_cell:
		return false

	return is_room_within_effect_range(
		mage.room_id,
		room_id,
		range_value
	)


func _quest_room_choice_options(
	caster_id: int,
	effect: Dictionary,
	origin_room_id: String = ""
) -> Array:
	var options: Array = []
	var range_value = effect.get("range", "*")

	for room_value in room_id_by_coord.values():
		var room_id: String = str(room_value)

		var in_range: bool = is_room_within_effect_range(origin_room_id, room_id, range_value) \
			if origin_room_id != "" else _quest_effect_room_in_range(caster_id, room_id, range_value)
		if not in_range:
			continue

		var room = get_room_by_id(room_id)
		var room_name: String = room_id

		if room != null:
			room_name = str(room.room_name)

		options.append({
			"token": "room:" + room_id,
			"value": room_id,
			"room_id": room_id,
			"name": room_name
		})

	return options


func _quest_mage_choice_options(
	caster_id: int,
	effect: Dictionary
) -> Array:
	var options: Array = []
	var range_value = effect.get("range", "*")

	for player_index in range(players.size()):
		if player_index == caster_id:
			continue

		var mage = players[player_index].mage
		if mage == null or mage.in_cell:
			continue

		if not _quest_effect_room_in_range(
			caster_id,
			mage.room_id,
			range_value
		):
			continue

		options.append({
			"token": "mage:" + str(player_index),
			"value": player_index,
			"player_index": player_index,
			"name": players[player_index].player_name,
			"room_id": mage.room_id
		})

	return options


func _quest_evocation_choice_options(
	caster_id: int,
	effect: Dictionary
) -> Array:
	var options: Array = []
	var range_value = effect.get("range", "*")
	var effect_type: String = str(effect.get("type", ""))
	var owner_filter: int = -999999

	if str(effect.get("target_owner", "")) == "self" \
	or effect_type == "activate_owned_evocation":
		owner_filter = caster_id

	var archetype_filter: String = str(
		effect.get(
			"target_archetype",
			effect.get("evocation_archetype", "")
		)
	)

	var max_health: int = int(effect.get("max_health", -1))

	for owner_index in range(players.size()):
		if owner_filter != -999999 and owner_index != owner_filter:
			continue

		var evocations: Array[EvocationState] = players[owner_index].evocations

		for evocation_index in range(evocations.size()):
			var evocation: EvocationState = evocations[evocation_index]

			if evocation == null or evocation.is_defeated():
				continue

			if archetype_filter != "" \
			and evocation.archetype != archetype_filter:
				continue

			if max_health >= 0 and evocation.health > max_health:
				continue

			if not _quest_effect_room_in_range(
				caster_id,
				evocation.room_id,
				range_value
			):
				continue

			options.append({
				"token":
					"evocation:"
					+ str(owner_index)
					+ ":"
					+ str(evocation_index),
				"value": evocation,
				"owner_id": owner_index,
				"evocation_index": evocation_index,
				"id": evocation.evocation_id,
				"name": evocation.get_display_name(),
				"archetype": evocation.archetype,
				"room_id": evocation.room_id,
				"health": evocation.health
			})

	return options



func _quest_model_choice_options(
	caster_id: int,
	effect: Dictionary
) -> Array:
	var options: Array = []

	for mage_option_value in _quest_mage_choice_options(
		caster_id,
		effect
	):
		var mage_option: Dictionary = mage_option_value
		var player_index: int = int(
			mage_option.get(
				"value",
				-1
			)
		)

		options.append({
			"token": "model:mage:" + str(player_index),
			"value": {
				"type": "mage",
				"player_index": player_index
			},
			"name": str(
				mage_option.get(
					"name",
					"Mage"
				)
			),
			"model_type": "mage",
			"player_index": player_index,
			"room_id": str(
				mage_option.get(
					"room_id",
					""
				)
			)
		})

	for evocation_option_value in _quest_evocation_choice_options(
		caster_id,
		effect
	):
		var evocation_option: Dictionary = evocation_option_value
		var evocation = evocation_option.get(
			"value"
		)

		options.append({
			"token": str(
				evocation_option.get(
					"token",
					""
				)
			).replace(
				"evocation:",
				"model:evocation:"
			),
			"value": {
				"type": "evocation",
				"evocation": evocation
			},
			"name": str(
				evocation_option.get(
					"name",
					"Evocation"
				)
			),
			"model_type": "evocation",
			"room_id": str(
				evocation_option.get(
					"room_id",
					""
				)
			)
		})

	return options


func _apply_quest_model_choice_to_context(
	context: Dictionary
) -> bool:
	if not context.has("quest_target_model"):
		return false

	var model_data = context.get(
		"quest_target_model"
	)

	if not model_data is Dictionary:
		return false

	var model: Dictionary = model_data
	var model_type: String = str(
		model.get(
			"type",
			""
		)
	)

	context["target_model_type"] = model_type

	if model_type == "mage":
		context["target_player_index"] = int(
			model.get(
				"player_index",
				-1
			)
		)
		return true

	if model_type == "evocation":
		context["target_evocation"] = model.get(
			"evocation"
		)
		return context.get(
			"target_evocation",
			null
		) != null

	return false

func _quest_side_has_any_element(
	side: Dictionary,
	required_elements: Array[String]
) -> bool:
	var symbols: Array[String] = []

	var main_element: String = str(side.get("element", ""))
	if main_element != "":
		symbols.append(main_element)

	var enhancement = side.get("enhancement", {})
	if enhancement is Dictionary:
		var enhancement_data: Dictionary = enhancement

		if enhancement_data.has("requires"):
			for value in enhancement_data.get("requires", []):
				symbols.append(str(value))
		elif enhancement_data.has("elements"):
			for value in enhancement_data.get("elements", []):
				symbols.append(str(value))
		elif enhancement_data.has("element"):
			symbols.append(
				str(enhancement_data.get("element", ""))
			)

	for symbol in symbols:
		if symbol == "all" or symbol in required_elements:
			return true

	return false


func _quest_request_single_choice(
	caster_id: int,
	choice_kind: String,
	context: Dictionary,
	context_key: String,
	options: Array,
	prompt: String,
	confirm_single: bool = false
) -> bool:
	if options.is_empty():
		# No legal target/choice exists.  Let the Effect resolver attempt the
		# sentence; the Quest rules will then skip the unapplicable part.
		return true

	if options.size() == 1 and not confirm_single:
		var only_option: Dictionary = options[0]
		_set_interactive_effect_choice(
			context,
			context_key,
			only_option.get("value")
		)
		return true

	request_effect_choice(
		caster_id,
		choice_kind,
		context,
		context_key,
		options,
		1,
		1,
		prompt
	)

	return false


func _prepare_quest_target_choice(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var caster_id: int = int(context.get("caster_id", -1))
	if caster_id < 0 or caster_id >= players.size():
		return true

	var target_type: String = str(effect.get("target", ""))
	if target_type == "":
		return true

	if target_type == "room":
		if str(context.get("target_room_id", "")) != "":
			return true

		return _quest_request_single_choice(
			caster_id,
			"target_room",
			context,
			"target_room_id",
			_quest_room_choice_options(caster_id, effect),
			"Choose a target Room for " + str(effect.get("type", "Effect")).replace("_", " ") + ".",
			true
		)

	if target_type == "mage":
		if int(context.get("target_player_index", -1)) >= 0:
			return true

		return _quest_request_single_choice(
			caster_id,
			"target_mage",
			context,
			"target_player_index",
			_quest_mage_choice_options(caster_id, effect),
			"Choose a target Mage."
		)

	if target_type == "model":
		if _apply_quest_model_choice_to_context(
			context
		):
			return true

		return _quest_request_single_choice(
			caster_id,
			"target_model",
			context,
			"quest_target_model",
			_quest_model_choice_options(
				caster_id,
				effect
			),
			"Choose a target Model."
		)

	if target_type == "evocation":
		var context_key: String = "target_evocation"

		if str(effect.get("type", "")) == "activate_owned_evocation":
			context_key = "selected_evocation_to_activate"

		if context.get(context_key, null) != null:
			return true

		return _quest_request_single_choice(
			caster_id,
			"target_evocation",
			context,
			context_key,
			_quest_evocation_choice_options(caster_id, effect),
			"Choose a target Evocation."
		)

	return true



func _quest_yes_no_options(
	yes_label: String = "Yes",
	no_label: String = "No"
) -> Array:
	return [
		{
			"token": "choice:yes",
			"value": true,
			"name": yes_label
		},
		{
			"token": "choice:no",
			"value": false,
			"name": no_label
		}
	]


func _quest_non_forgotten_evocation_id_options() -> Array:
	var options: Array = []

	for evocation_id in evocation_database.evocations.keys():
		var data: Dictionary = evocation_database.get_evocation(
			str(evocation_id)
		)

		if data.is_empty():
			continue

		options.append({
			"token": "evocation_type:" + str(evocation_id),
			"value": str(evocation_id),
			"id": str(evocation_id),
			"name": str(
				data.get(
					"name",
					evocation_id
				)
			)
		})

	return options


func _quest_all_live_evocation_options() -> Array:
	var options: Array = []

	for owner_index in range(players.size()):
		for evocation_index in range(
			players[owner_index].evocations.size()
		):
			var evocation = players[
				owner_index
			].evocations[
				evocation_index
			]

			if evocation == null \
			or evocation.is_defeated():
				continue

			options.append({
				"token":
					"live_evocation:"
					+ str(owner_index)
					+ ":"
					+ str(evocation_index),
				"value": evocation,
				"name": evocation.get_display_name(),
				"owner_id": owner_index,
				"room_id": evocation.room_id
			})

	return options

func _prepare_quest_special_choice(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var caster_id: int = int(context.get("caster_id", -1))
	if caster_id < 0 or caster_id >= players.size():
		return true

	var player = players[caster_id]
	var effect_type: String = str(effect.get("type", ""))

	match effect_type:
		"return_revealed_spell_to_hand":
			if context.get("selected_revealed_spell", null) != null \
			or context.has("selected_revealed_spell_index") \
			or str(context.get("selected_revealed_spell_id", "")) != "":
				return true

			var required_elements: Array[String] = []
			for value in effect.get("required_elements", []):
				required_elements.append(str(value))

			var legacy_symbol: String = str(
				effect.get("required_symbol", "")
			)
			if required_elements.is_empty() and legacy_symbol != "":
				required_elements.append(legacy_symbol)

			var options: Array = []

			for revealed_index in range(player.revealed_spells.size()):
				var revealed: RevealedSpellState = (
					player.revealed_spells[revealed_index]
				)

				if revealed == null or revealed.spell == null:
					continue

				if not _quest_side_has_any_element(
					revealed.get_active_side(),
					required_elements
				):
					continue

				options.append({
					"token": "revealed:" + str(revealed_index),
					"value": revealed,
					"revealed_index": revealed_index,
					"id": revealed.spell.id,
					"name": revealed.spell.card_name,
					"side": (
						"dark"
						if revealed.use_dark_side
						else "light"
					)
				})

			return _quest_request_single_choice(
				caster_id,
				"revealed_spell",
				context,
				"selected_revealed_spell",
				options,
				"Choose one eligible Revealed Spell to return to your Hand."
			)

		"search_grimoire_to_hand":
			if context.get("selected_grimoire_spell", null) != null \
			or str(context.get("selected_grimoire_spell_id", "")) != "":
				return true

			var options: Array = []

			for spell_index in range(player.grimoire.size()):
				var spell: SpellCardState = player.grimoire[spell_index]
				if spell == null:
					continue

				options.append({
					"token": "grimoire:" + str(spell_index),
					"value": spell,
					"grimoire_index": spell_index,
					"id": spell.id,
					"name": spell.card_name,
					"school_id": spell.school_id
				})

			return _quest_request_single_choice(
				caster_id,
				"grimoire_spell",
				context,
				"selected_grimoire_spell",
				options,
				"Choose a Spell from your Grimoire."
			)

		"draw_library":
			if str(context.get("selected_school_id", "")) != "":
				return true

			var options: Array = []

			for school_value in active_school_ids:
				var school_id: String = str(school_value)
				var library: Array = school_libraries.get(
					school_id,
					[]
				)
				var discard: Array = school_discards.get(
					school_id,
					[]
				)

				if library.is_empty() and discard.is_empty():
					continue

				options.append({
					"token": "school:" + school_id,
					"value": school_id,
					"school_id": school_id,
					"name": school_id
				})

			return _quest_request_single_choice(
				caster_id,
				"library_school",
				context,
				"selected_school_id",
				options,
				"Choose a School of Magic to draw from."
			)

		"draw_grimoire_or_heal":
			if player.mage.get_damage() <= 0:
				return true

			if context.has("selected_damage_owner_ids"):
				return true

			var heal_amount: int = maxi(
				0,
				int(effect.get("heal", 0))
			)
			var max_select: int = mini(
				heal_amount,
				player.mage.damage_cubes.size()
			)

			if max_select <= 0:
				return true

			var options: Array = []
			var owner_occurrences: Dictionary = {}

			for owner_value in player.mage.damage_cubes:
				var owner_id: int = int(owner_value)
				var ordinal: int = int(
					owner_occurrences.get(owner_id, 0)
				)
				owner_occurrences[owner_id] = ordinal + 1

				var owner_name: String = "Black Rose"
				if owner_id >= 0 and owner_id < players.size():
					owner_name = players[owner_id].player_name

				options.append({
					"token":
						"damage:"
						+ str(owner_id)
						+ ":"
						+ str(ordinal),
					"value": owner_id,
					"owner_id": owner_id,
					"owner_name": owner_name
				})

			request_effect_choice(
				caster_id,
				"heal_damage",
				context,
				"selected_damage_owner_ids",
				options,
				0,
				max_select,
				"Choose up to "
				+ str(max_select)
				+ " Damage cubes to heal."
			)
			return false

		"convert_instability":
			if context.has("selected_instability_owner_ids"):
				return true

			var room_id: String = str(
				context.get("target_room_id", "")
			)
			if room_id == "":
				return true

			var room = get_room_by_id(room_id)
			if room == null:
				return true

			var amount: int = maxi(
				0,
				int(effect.get("amount", 0))
			)
			var convertible_count: int = 0

			for owner_value in room.instability_cubes:
				if int(owner_value) != caster_id:
					convertible_count += 1

			var max_convert: int = mini(
				amount,
				convertible_count
			)
			max_convert = mini(
				max_convert,
				player.available_cubes
			)

			if max_convert <= 0:
				return true

			var options: Array = []
			var owner_occurrences: Dictionary = {}

			for owner_value in room.instability_cubes:
				var owner_id: int = int(owner_value)
				if owner_id == caster_id:
					continue

				var ordinal: int = int(
					owner_occurrences.get(owner_id, 0)
				)
				owner_occurrences[owner_id] = ordinal + 1

				var owner_name: String = "Black Rose"
				if owner_id >= 0 and owner_id < players.size():
					owner_name = players[owner_id].player_name

				options.append({
					"token":
						"instability:"
						+ str(owner_id)
						+ ":"
						+ str(ordinal),
					"value": owner_id,
					"owner_id": owner_id,
					"owner_name": owner_name
				})

			if options.size() <= max_convert:
				var selected_owners: Array = []
				for option_value in options:
					var option: Dictionary = option_value
					selected_owners.append(
						int(option.get("value", -999999))
					)

				_set_interactive_effect_choice(
					context,
					"selected_instability_owner_ids",
					selected_owners
				)
				return true

			request_effect_choice(
				caster_id,
				"instability_cubes",
				context,
				"selected_instability_owner_ids",
				options,
				max_convert,
				max_convert,
				"Choose "
				+ str(max_convert)
				+ " Instability cubes to convert."
			)
			return false


		"swap_with_target_mage_optional":
			if not context.has("quest_optional_yes"):
				if not _quest_request_single_choice(
					caster_id,
					"quest_optional",
					context,
					"quest_optional_yes",
					_quest_yes_no_options(
						"Swap positions",
						"Do not swap"
					),
					"Do you want to move into the target Mage's Room?"
				):
					return false

			if not bool(
				context.get(
					"quest_optional_yes",
					false
				)
			):
				return true

			if str(
				context.get(
					"secondary_room_id",
					""
				)
			) != "":
				return true

			return _quest_request_single_choice(
				caster_id,
				"secondary_room",
				context,
				"secondary_room_id",
				_quest_room_choice_options(
					caster_id,
					{
						"range": "*"
					}
				),
				"Choose the Room where the target Mage will be placed."
			)

		"draw_event_optional_gain_power":
			if context.has("quest_optional_yes"):
				return true

			return _quest_request_single_choice(
				caster_id,
				"quest_optional",
				context,
				"quest_optional_yes",
				_quest_yes_no_options(
					"Draw 1 Event",
					"Do not draw"
				),
				"Do you want to draw an Event?"
			)

		"draw_event_then_damage":
			if not context.has("quest_optional_yes"):
				if not _quest_request_single_choice(
					caster_id,
					"quest_optional",
					context,
					"quest_optional_yes",
					_quest_yes_no_options(
						"Draw 1 Event",
						"Do not draw"
					),
					"Do you want to draw an Event?"
				):
					return false

			if not bool(
				context.get(
					"quest_optional_yes",
					false
				)
			):
				return true

			if int(
				context.get(
					"target_player_index",
					-1
				)
			) >= 0:
				return true

			var target_effect: Dictionary = {
				"range": effect.get(
					"range",
					3
				)
			}

			return _quest_request_single_choice(
				caster_id,
				"target_mage",
				context,
				"target_player_index",
				_quest_mage_choice_options(
					caster_id,
					target_effect
				),
				"Choose the Mage who will suffer the Damage."
			)

		"damage_or_place_instability":
			if str(
				context.get(
					"quest_branch",
					""
				)
			) != "":
				return true

			return _quest_request_single_choice(
				caster_id,
				"quest_branch",
				context,
				"quest_branch",
				[
					{
						"token": "branch:damage",
						"value": "damage",
						"name": "Inflict "
							+ str(
								effect.get(
									"damage",
									0
								)
							)
							+ " Damage"
					},
					{
						"token": "branch:instability",
						"value": "instability",
						"name": "Place "
							+ str(
								effect.get(
									"instability",
									0
								)
							)
							+ " Instability"
					}
				],
				"Choose one Effect."
			)

		"complete_owned_quest_choice":
			if context.get(
				"selected_active_quest",
				null
			) != null:
				return true

			var quest_options: Array = []

			for quest_index in range(
				player.active_quests.size()
			):
				var quest_state: QuestState = (
					player.active_quests[
						quest_index
					]
				)

				if quest_state == null:
					continue

				quest_options.append({
					"token": "active_quest:" + str(quest_index),
					"value": quest_state,
					"name": quest_state.get_name(),
					"quest_index": quest_index
				})

			return _quest_request_single_choice(
				caster_id,
				"active_quest",
				context,
				"selected_active_quest",
				quest_options,
				"Choose one of your Active Quests to complete."
			)

		"black_rose_lose_power_or_target_mage_lose_power":
			if str(
				context.get(
					"quest_branch",
					""
				)
			) == "":
				if not _quest_request_single_choice(
					caster_id,
					"quest_branch",
					context,
					"quest_branch",
					[
						{
							"token": "branch:black_rose",
							"value": "black_rose",
							"name": "Black Rose loses "
								+ str(
									effect.get(
										"black_rose",
										0
									)
								)
								+ " Power"
						},
						{
							"token": "branch:mage",
							"value": "mage",
							"name": "A Mage loses "
								+ str(
									effect.get(
										"mage",
										0
									)
								)
								+ " Power"
						}
					],
					"Choose one Effect."
				):
					return false

			if str(
				context.get(
					"quest_branch",
					""
				)
			) != "mage":
				return true

			if int(
				context.get(
					"target_player_index",
					-1
				)
			) >= 0:
				return true

			return _quest_request_single_choice(
				caster_id,
				"target_mage",
				context,
				"target_player_index",
				_quest_mage_choice_options(
					caster_id,
					{
						"range": "*"
					}
				),
				"Choose the Mage who loses Power."
			)

		"give_forgotten_to_target":
			if context.get(
				"selected_forgotten_spell",
				null
			) != null:
				return true

			var forgotten_options: Array = []

			for spell_index in range(
				player.hand.size()
			):
				var spell: SpellCardState = player.hand[
					spell_index
				]

				if spell == null \
				or not spell.forgotten:
					continue

				forgotten_options.append({
					"token": "forgotten_hand:" + str(spell_index),
					"value": spell,
					"name": spell.card_name,
					"id": spell.id
				})

			return _quest_request_single_choice(
				caster_id,
				"forgotten_hand",
				context,
				"selected_forgotten_spell",
				forgotten_options,
				"Choose a Forgotten Spell from your Hand."
			)

		"draw_three_forgotten_keep_one":
			if context.get(
				"selected_forgotten_spell",
				null
			) != null:
				return true

			var draw_amount: int = mini(
				int(
					effect.get(
						"draw",
						3
					)
				),
				forgotten_deck.size()
			)

			var forgotten_options: Array = []

			for offset in range(draw_amount):
				var deck_index: int = (
					forgotten_deck.size()
					- 1
					- offset
				)

				var spell: SpellCardState = (
					forgotten_deck[
						deck_index
					]
				)

				forgotten_options.append({
					"token": "forgotten_draw:" + str(deck_index),
					"value": spell,
					"name": spell.card_name,
					"id": spell.id
				})

			return _quest_request_single_choice(
				caster_id,
				"forgotten_keep",
				context,
				"selected_forgotten_spell",
				forgotten_options,
				"Draw 3 Forgotten Spells: choose the one to keep."
			)

		"activate_evocation_or_summon_nigredo":
			var live_options: Array = (
				_quest_all_live_evocation_options()
			)

			if not live_options.is_empty():
				if context.get(
					"selected_evocation_to_activate",
					null
				) != null:
					return true

				return _quest_request_single_choice(
					caster_id,
					"target_evocation",
					context,
					"selected_evocation_to_activate",
					live_options,
					"Choose an Evocation to activate under your control."
				)

			if str(
				context.get(
					"target_room_id",
					""
				)
			) != "":
				return true

			return _quest_request_single_choice(
				caster_id,
				"target_room",
				context,
				"target_room_id",
				_quest_room_choice_options(
					caster_id,
					{
						"range": int(
							effect.get(
								"range",
								1
							)
						)
					}
				),
				"Choose where to summon the Nigredo."
			)

		"steal_power_from_up_to_mages":
			if context.has(
				"selected_mage_indices"
			):
				return true

			var mage_options: Array = (
				_quest_mage_choice_options(
					caster_id,
					{
						"range": "*"
					}
				)
			)

			request_effect_choice(
				caster_id,
				"multiple_mages",
				context,
				"selected_mage_indices",
				mage_options,
				0,
				mini(
					int(
						effect.get(
							"max_targets",
							3
						)
					),
					mage_options.size()
				),
				"Choose up to "
				+ str(
					effect.get(
						"max_targets",
						3
					)
				)
				+ " Mages."
			)

			return false

		"summon_non_forgotten_evocation_choice":
			if str(
				context.get(
					"chosen_evocation_id",
					""
				)
			) != "":
				return true

			return _quest_request_single_choice(
				caster_id,
				"evocation_type",
				context,
				"chosen_evocation_id",
				_quest_non_forgotten_evocation_id_options(),
				"Choose a non-Forgotten Evocation to summon."
			)

		"heal":
			if not context.has(
				"selected_damage_owner_ids"
			):
				var damage_cubes: Array = []

				if str(
					context.get(
						"target_model_type",
						"mage"
					)
				) == "mage":
					var target_player_index: int = int(
						context.get(
							"target_player_index",
							caster_id
						)
					)

					if target_player_index >= 0 \
					and target_player_index < players.size():
						damage_cubes = players[
							target_player_index
						].mage.damage_cubes

				elif str(
					context.get(
						"target_model_type",
						"mage"
					)
				) == "evocation":
					var target_evocation = context.get(
						"target_evocation"
					)

					if target_evocation != null:
						damage_cubes = target_evocation.damage_cubes

				if damage_cubes.is_empty():
					return true

				var max_select: int = mini(
					int(
						effect.get(
							"amount",
							0
						)
					),
					damage_cubes.size()
				)

				var options: Array = []
				var owner_occurrences: Dictionary = {}

				for owner_value in damage_cubes:
					var owner_id: int = int(
						owner_value
					)
					var ordinal: int = int(
						owner_occurrences.get(
							owner_id,
							0
						)
					)
					owner_occurrences[owner_id] = ordinal + 1

					options.append({
						"token":
							"damage:"
							+ str(owner_id)
							+ ":"
							+ str(ordinal),
						"value": owner_id,
						"owner_id": owner_id
					})

				request_effect_choice(
					caster_id,
					"heal_damage",
					context,
					"selected_damage_owner_ids",
					options,
					0,
					max_select,
					"Choose up to "
					+ str(max_select)
					+ " Damage cubes to heal."
				)

				return false

			return true

		_:
			return true


func _prepare_quest_effect_choice(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	if not _prepare_quest_target_choice(effect, context):
		return false

	return _prepare_quest_special_choice(
		effect,
		context
	)

# =========================================================
# SPELL PRIMARY TARGET CHOICES
# =========================================================


func _spell_effective_target_side(
	caster_id: int,
	side: Dictionary,
	spell: SpellCardState = null
) -> Dictionary:
	var effective: Dictionary = side.duplicate(true)

	# Some printed Effects constrain the legal primary target even though the
	# constraint lives inside the Effect rather than in the target header.
	for effect_value in side.get("effects", []):
		if not effect_value is Dictionary:
			continue

		var effect: Dictionary = effect_value
		var effect_type: String = str(effect.get("type", ""))

		if effect_type == "remove_evocation_with_max_health":
			effective["max_health"] = int(
				effect.get("max_health", -1)
			)

		if effect_type == "remove_owned_evocation_and_damage_around":
			effective["target_owner"] = "self"

	var enhancement: Dictionary = side.get(
		"enhancement",
		{}
	)

	if enhancement.is_empty():
		return effective

	var enhancement_active: bool = can_apply_enhancement(
		caster_id,
		_enhancement_required_elements(enhancement), spell
	)

	if not enhancement_active:
		return effective

	# A target-changing Enhancement changes what the player chooses when
	# casting the Spell, not after an obsolete target has already been chosen.
	for effect_value in enhancement.get("effects", []):
		if not effect_value is Dictionary:
			continue

		var effect: Dictionary = effect_value
		if str(effect.get("type", "")) != "modify_spell_target":
			continue

		if effect.has("target"):
			effective["target"] = effect.get("target")

		if effect.has("range"):
			effective["range"] = effect.get("range")

	return effective


func _is_ongoing_revealed_spell(
	side: Dictionary
) -> bool:
	var spell_type: String = str(side.get("type", ""))

	if spell_type == "trap" or spell_type == "protection":
		return false

	var trigger = side.get("trigger", {})
	return trigger is Dictionary and not trigger.is_empty()


func _register_ongoing_revealed_spell(
	player_index: int,
	spell: SpellCardState,
	use_dark_side: bool,
	context: Dictionary
) -> void:
	if player_index < 0 or player_index >= players.size():
		return

	if spell == null:
		return

	var side: Dictionary = spell.get_side(use_dark_side)
	if not _is_ongoing_revealed_spell(side):
		return

	# Prevent accidental duplicate registration of the same revealed card.
	for existing in players[player_index].active_spells:
		if existing == null:
			continue
		if existing.spell == spell \
		and existing.use_dark_side == use_dark_side \
		and existing.active:
			return

	var target_player_index: int = int(
		context.get("target_player_index", -1)
	)

	var ongoing := ActiveSpellState.new(
		spell,
		player_index,
		use_dark_side,
		target_player_index
	)

	for key in context:
		if key == "game":
			continue
		ongoing.context[key] = context[key]

	players[player_index].add_active_spell(ongoing)

	print(
		"Player ", player_index + 1,
		" keeps ongoing Effect active: ",
		spell.card_name
	)

func _spell_has_primary_target(
	target_type: String,
	context: Dictionary
) -> bool:
	if bool(context.get("target_is_dummy", false)):
		return true

	match target_type:
		"room", "area":
			return str(context.get("target_room_id", "")) != ""

		"mage":
			return int(context.get("target_player_index", -1)) >= 0

		"evocation":
			return context.get("target_evocation", null) != null

		"model":
			var model_type: String = str(
				context.get("target_model_type", "")
			)

			if model_type == "mage":
				return int(context.get("target_player_index", -1)) >= 0

			if model_type == "evocation":
				return context.get("target_evocation", null) != null

			return model_type == "dummy"

		"self", "special", "":
			return true

		_:
			return true


func _spell_materialize_primary_target(
	context: Dictionary
) -> bool:
	var selected = context.get("spell_primary_target", null)
	if not selected is Dictionary:
		return false

	var target_data: Dictionary = selected
	var target_type: String = str(
		target_data.get("target_type", "")
	)

	context.erase("target_is_dummy")
	context.erase("target_room_id")
	context.erase("target_player_index")
	context.erase("target_evocation")
	context.erase("target_model_type")

	match target_type:
		"dummy":
			context["target_is_dummy"] = true
			context["target_model_type"] = "dummy"
			return true

		"room":
			var room_id: String = str(
				target_data.get("room_id", "")
			)
			if room_id == "":
				return false

			context["target_room_id"] = room_id
			return true

		"mage":
			var player_index: int = int(
				target_data.get("player_index", -1)
			)
			if player_index < 0 or player_index >= players.size():
				return false

			context["target_player_index"] = player_index
			context["target_model_type"] = "mage"
			return true

		"evocation":
			var evocation = target_data.get("evocation", null)
			if evocation == null:
				return false

			context["target_evocation"] = evocation
			context["target_model_type"] = "evocation"
			return true

		_:
			return false


func _spell_room_target_allowed(caster_id: int, side: Dictionary, room_id: String) -> bool:
	for effect in side.get("effects", []):
		if str(effect.get("type", "")) != "activate_room_from_owned_evocation":
			continue
		if not is_lodge_room_id(room_id):
			return false
		if room_id in effect.get("excluded_rooms", []):
			return false
		var found: bool = false
		var candidates: Array = []
		for owner in range(players.size()):
			if str(effect.get("target_owner", "self")) == "self" and owner != caster_id:
				continue
			candidates.append_array(players[owner].evocations)
		for evocation in candidates:
			if evocation == null or evocation.is_defeated() or not is_lodge_room_id(evocation.room_id):
				continue
			if evocation.archetype != str(effect.get("evocation_archetype", "")):
				continue
			if get_hex_distance(room_id_to_coord(evocation.room_id), room_id_to_coord(room_id)) <= int(effect.get("distance", 0)):
				found = true
				break
		if not found:
			return false
	return true


func _spell_room_target_options(
	caster_id: int,
	side: Dictionary
) -> Array:
	var result: Array = []

	for option_value in _quest_room_choice_options(
		caster_id,
		side
	):
		var option: Dictionary = option_value
		if not _spell_room_target_allowed(caster_id, side, str(option.get("room_id", ""))):
			continue

		result.append({
			"token": str(option.get("token", "")),
			"value": {
				"target_type": "room",
				"room_id": str(option.get("room_id", ""))
			},
			"target_type": "room",
			"room_id": str(option.get("room_id", "")),
			"name": str(option.get("name", ""))
		})

	return result


func _spell_mage_target_options(
	caster_id: int,
	side: Dictionary,
	allow_dummy: bool = true
) -> Array:
	var result: Array = []

	for option_value in _quest_mage_choice_options(
		caster_id,
		side
	):
		var option: Dictionary = option_value
		var player_index: int = int(
			option.get("player_index", -1)
		)

		result.append({
			"token": "spell_mage:" + str(player_index),
			"value": {
				"target_type": "mage",
				"player_index": player_index
			},
			"target_type": "mage",
			"player_index": player_index,
			"name": str(option.get("name", "")),
			"room_id": str(option.get("room_id", ""))
		})

	if allow_dummy:
		result.append({
			"token": "spell_dummy",
			"value": {
				"target_type": "dummy"
			},
			"target_type": "dummy",
			"name": "Dummy Target"
		})

	return result


func _spell_evocation_target_options(
	caster_id: int,
	side: Dictionary,
	allow_dummy: bool = true
) -> Array:
	var result: Array = []

	for option_value in _quest_evocation_choice_options(
		caster_id,
		side
	):
		var option: Dictionary = option_value
		var evocation = option.get("value", null)
		if evocation == null:
			continue

		result.append({
			"token": str(option.get("token", "")),
			"value": {
				"target_type": "evocation",
				"evocation": evocation
			},
			"target_type": "evocation",
			"owner_id": int(option.get("owner_id", -1)),
			"evocation_index": int(
				option.get("evocation_index", -1)
			),
			"id": str(option.get("id", "")),
			"name": str(option.get("name", "")),
			"archetype": str(option.get("archetype", "")),
			"room_id": str(option.get("room_id", ""))
		})

	if allow_dummy:
		result.append({
			"token": "spell_dummy",
			"value": {
				"target_type": "dummy"
			},
			"target_type": "dummy",
			"name": "Dummy Target"
		})

	return result


func _spell_model_target_options(
	caster_id: int,
	side: Dictionary
) -> Array:
	var result: Array = []
	var archetype_filter: String = str(
		side.get("target_archetype", "")
	)

	# A Dummy has no Archetype, so it cannot be selected when the Effect
	# requires one.
	if archetype_filter == "":
		result.append_array(
			_spell_mage_target_options(
				caster_id,
				side,
				false
			)
		)

	result.append_array(
		_spell_evocation_target_options(
			caster_id,
			side,
			false
		)
	)

	if archetype_filter == "":
		result.append({
			"token": "spell_dummy",
			"value": {
				"target_type": "dummy"
			},
			"target_type": "dummy",
			"name": "Dummy Target"
		})

	return result


func _spell_primary_target_options(
	caster_id: int,
	side: Dictionary
) -> Array:
	var target_type: String = str(
		side.get("target", "")
	)

	match target_type:
		"room", "area":
			return _spell_room_target_options(
				caster_id,
				side
			)

		"mage":
			return _spell_mage_target_options(
				caster_id,
				side,
				true
			)

		"evocation":
			return _spell_evocation_target_options(
				caster_id,
				side,
				str(side.get("target_archetype", "")) == ""
				and str(side.get("target_owner", "")) != "self"
			)

		"model":
			return _spell_model_target_options(
				caster_id,
				side
			)

		_:
			return []


func _prepare_spell_primary_target_choice(
	caster_id: int,
	side: Dictionary,
	context: Dictionary
) -> bool:
	if caster_id < 0 or caster_id >= players.size():
		return true

	var target_type: String = str(
		side.get("target", "")
	)

	if target_type == "" \
	or target_type == "self" \
	or target_type == "special":
		return true

	# A Room at Range 0 is unambiguously the caster's Room.
	if (target_type == "room" or target_type == "area") \
	and str(side.get("range", "")) == "0":
		context["target_room_id"] = players[caster_id].mage.room_id
		return true

	if _spell_has_primary_target(
		target_type,
		context
	):
		return true

	# A previous input request stores a structured target here. Materialize it
	# into the legacy context keys used by EffectResolver.
	if context.get("spell_primary_target", null) is Dictionary:
		if _spell_materialize_primary_target(context):
			return true

	var options: Array = _spell_primary_target_options(
		caster_id,
		side
	)

	if options.is_empty():
		# No legal target exists. Effects that target Models normally still have
		# a Dummy Target option, unless an Archetype restriction forbids it.
		return true

	# Primary Spell targets are always an explicit player decision, even when
	# there is only one legal option. This is especially important for the
	# Dummy Target: choosing it is a meaningful casting decision and must not
	# happen automatically.
	request_effect_choice(
		caster_id,
		"spell_target",
		context,
		"spell_primary_target",
		options,
		1,
		1,
		"Choose the Spell target."
	)

	return false


# =========================================================
# SPELL SECONDARY EFFECT CHOICES
# =========================================================

func _forget_interactive_effect_choice_key(
	context: Dictionary,
	context_key: String
) -> void:
	context.erase(context_key)

	var keys: Array = context.get(
		"_interactive_choice_keys",
		[]
	)

	keys.erase(context_key)

	if keys.is_empty():
		context.erase("_interactive_choice_keys")
	else:
		context["_interactive_choice_keys"] = keys


func _spell_secondary_evocation_options(
	caster_id: int,
	owner_id: int = -999999,
	archetype: String = "",
	room_id: String = "",
	max_health: int = -1
) -> Array:
	var options: Array = []

	for owner_index in range(players.size()):
		if owner_id != -999999 and owner_index != owner_id:
			continue

		var evocations: Array[EvocationState] = players[owner_index].evocations

		for evocation_index in range(evocations.size()):
			var evocation: EvocationState = evocations[evocation_index]

			if evocation == null or evocation.is_defeated():
				continue

			if archetype != "" and evocation.archetype != archetype:
				continue

			if room_id != "" and evocation.room_id != room_id:
				continue

			if max_health >= 0 and evocation.health > max_health:
				continue

			options.append({
				"token":
					"secondary_evocation:"
					+ str(owner_index)
					+ ":"
					+ str(evocation_index),
				"value": evocation,
				"owner_id": owner_index,
				"evocation_index": evocation_index,
				"id": evocation.evocation_id,
				"name": evocation.get_display_name(),
				"archetype": evocation.archetype,
				"room_id": evocation.room_id
			})

	return options


func _spell_secondary_mage_options(
	excluded_players: Array
) -> Array:
	var options: Array = []

	for player_index in range(players.size()):
		if player_index in excluded_players:
			continue

		var mage = players[player_index].mage
		if mage == null or mage.in_cell:
			continue

		options.append({
			"token": "secondary_mage:" + str(player_index),
			"value": player_index,
			"player_index": player_index,
			"name": players[player_index].player_name,
			"room_id": mage.room_id
		})

	return options


func _damaged_model_choice_options(
	context: Dictionary
) -> Array:
	var options: Array = []
	var models: Array = context.get(
		"models_damaged_by_effect",
		[]
	)

	for model_index in range(models.size()):
		var model_value = models[model_index]

		if not model_value is Dictionary:
			continue

		var model: Dictionary = model_value
		var model_type: String = str(model.get("type", ""))
		var name: String = "Model"

		if model_type == "mage":
			var player_index: int = int(
				model.get("player_index", -1)
			)

			if player_index < 0 or player_index >= players.size():
				continue

			var mage = players[player_index].mage
			if mage == null or mage.in_cell:
				continue

			name = players[player_index].player_name

		elif model_type == "evocation":
			var evocation = model.get("evocation", null)
			if evocation == null or evocation.is_defeated():
				continue

			name = str(evocation.evocation_name)

		else:
			continue

		options.append({
			"token": "damaged_model:" + str(model_index),
			"value": model_index,
			"model_index": model_index,
			"player_index": int(model.get("player_index", -1)),
			"owner_id": int(model.evocation.owner_id) if model_type == "evocation" else -1,
			"evocation_index": players[model.evocation.owner_id].evocations.find(model.evocation) if model_type == "evocation" else -1,
			"model_type": model_type,
			"name": name
		})

	return options


func _damaged_model_room_id(
	context: Dictionary,
	model_index: int
) -> String:
	var models: Array = context.get(
		"models_damaged_by_effect",
		[]
	)

	if model_index < 0 or model_index >= models.size():
		return ""

	var model_value = models[model_index]
	if not model_value is Dictionary:
		return ""

	var model: Dictionary = model_value
	var model_type: String = str(model.get("type", ""))

	if model_type == "mage":
		var player_index: int = int(
			model.get("player_index", -1)
		)

		if player_index < 0 or player_index >= players.size():
			return ""

		var mage = players[player_index].mage
		if mage == null or mage.in_cell:
			return ""

		return mage.room_id

	if model_type == "evocation":
		var evocation = model.get("evocation", null)
		if evocation == null or evocation.is_defeated():
			return ""

		return str(evocation.room_id)

	return ""


func _movement_destination_choice_options(
	origin_room_id: String,
	distance: int
) -> Array:
	var options: Array = []

	if not is_lodge_room_id(origin_room_id):
		return options

	var origin_coord: Vector2i = room_id_to_coord(origin_room_id)
	if origin_coord == Vector2i(9999, 9999):
		return options

	for room_value in room_id_by_coord.values():
		var room_id: String = str(room_value)

		var room_coord: Vector2i = room_id_to_coord(room_id)
		if room_coord == Vector2i(9999, 9999):
			continue

		var room_distance: int = get_hex_distance(
			origin_coord,
			room_coord
		)

		if room_distance < 0 or room_distance > distance:
			continue

		var room = get_room_by_id(room_id)
		var room_name: String = room_id

		if room != null:
			room_name = str(room.room_name)

		options.append({
			"token": "movement_room:" + room_id,
			"value": room_id,
			"room_id": room_id,
			"path": [] if room_id == origin_room_id else [room_id],
			"name": "Stay here" if room_id == origin_room_id else room_name
		})

	return options


func _evocation_deck_choice_options(
	max_health: int
) -> Array:
	var options: Array = []

	for evocation_data_value in evocation_database.get_evocations_with_max_health(
		max_health
	):
		if not evocation_data_value is Dictionary:
			continue

		var evocation_data: Dictionary = evocation_data_value
		var evocation_id: String = str(
			evocation_data.get("id", "")
		)

		if evocation_id == "":
			continue

		if get_available_evocation_copies(evocation_id) <= 0:
			continue

		options.append({
			"token": "evocation_deck:" + evocation_id,
			"value": evocation_id,
			"id": evocation_id,
			"name": str(
				evocation_data.get(
					"name",
					evocation_id
				)
			),
			"health": int(evocation_data.get("health", 0)),
			"archetype": str(
				evocation_data.get("archetype", "")
			)
		})

	return options


func _apply_or_request_secondary_choice(
	caster_id: int,
	choice_kind: String,
	context: Dictionary,
	context_key: String,
	options: Array,
	prompt: String
) -> bool:
	if options.is_empty():
		# No legal choice exists. Let the resolver attempt the sentence;
		# normal Effect rules decide whether it is skipped or fails.
		return true

	if options.size() == 1:
		var only_option: Dictionary = options[0]

		_set_interactive_effect_choice(
			context,
			context_key,
			only_option.get("value")
		)

		return true

	request_effect_choice(
		caster_id,
		choice_kind,
		context,
		context_key,
		options,
		1,
		1,
		prompt
	)

	return false


func _prepare_damage_conversion_choices(effect: Dictionary, context: Dictionary) -> bool:
	var mode: String = str(effect.get("type", ""))
	if mode not in ["convert_damage", "convert_damage_on_caster", "convert_damage_each_other_mage"]:
		return true
	var caster: int = int(context.get("caster_id", -1))
	if caster < 0 or effect_resolver._is_dummy_target(context):
		return true
	var target_type: String = effect_resolver._target_type(context)
	var models: Array = []
	for i in range(players.size()):
		var mage = players[i].mage
		var include := false
		if mode == "convert_damage_on_caster":
			include = i == caster
		elif i != caster:
			if mode == "convert_damage_each_other_mage":
				include = i != int(context.get("target_player_index", -1)) and not mage.in_cell
			elif target_type == "room":
				include = not mage.in_cell and mage.room_id == str(context.get("target_room_id", ""))
			elif target_type == "mage":
				include = i == int(context.get("target_player_index", -1))
		if include:
			models.append({"key": "mage:%d" % i, "cubes": mage.damage_cubes, "cube_player_index": i})
		if mode != "convert_damage":
			continue
		for j in range(players[i].evocations.size()):
			var evocation: EvocationState = players[i].evocations[j]
			if evocation.is_defeated() or get_evocation_controller_id(evocation) == caster:
				continue
			if (target_type == "evocation" and context.get("target_evocation") == evocation) or (target_type == "room" and evocation.room_id == str(context.get("target_room_id", ""))):
				models.append({"key": "evocation:%d" % evocation.get_instance_id(), "cubes": evocation.damage_cubes, "cube_evocation_owner": i, "cube_evocation_index": j})
	var new_owner: int = int(effect.get("converter_owner_id", -1)) if mode == "convert_damage_on_caster" else caster
	for model in models:
		var key: String = "convert_" + str(model.key)
		if context.has(key):
			continue
		var options: Array = []
		var occurrences: Dictionary = {}
		for owner in model.cubes:
			var ordinal: int = int(occurrences.get(owner, 0))
			occurrences[owner] = ordinal + 1
			if int(owner) == new_owner:
				continue
			var option: Dictionary = model.duplicate()
			option.erase("cubes")
			option.erase("key")
			option.merge({"token": "damage:%d:%d" % [owner, ordinal], "value": owner})
			options.append(option)
		var amount := mini(int(effect.get("amount", 0)), options.size())
		if amount <= 0 or amount == options.size():
			continue
		request_effect_choice(caster, "convert_damage_cubes", context, key, options, amount, amount, "Choose Damage cubes to convert.")
		return false
	return true


func _prepare_spell_secondary_effect_choice(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var caster_id: int = int(
		context.get("caster_id", -1)
	)

	if caster_id < 0 or caster_id >= players.size():
		return true

	var effect_type: String = str(
		effect.get("type", "")
	)

	match effect_type:
		"heal", "convert_instability":
			return _prepare_quest_special_choice(effect, context)
		"activate_room_from_owned_evocation":
			if context.has("target_room_id"):
				return true
			var options := _spell_room_target_options(caster_id, {"range": "*", "effects": [effect]})
			for option in options:
				option["value"] = option.room_id
			return _apply_or_request_secondary_choice(caster_id, "construct_room", context,
				"target_room_id", options, "Choose the Room to activate from a Construct.")
		"damage_secondary_mage_per_self_damage":
			if context.has("secondary_target_player_index"):
				return true

			var primary_player: int = int(
				context.get("target_player_index", -1)
			)

			return _apply_or_request_secondary_choice(
				caster_id,
				"secondary_mage",
				context,
				"secondary_target_player_index",
				_spell_secondary_mage_options(
					[primary_player]
				),
				"Choose the secondary Mage."
			)

		"move_one_model_damaged_by_effect":
			var models: Array = context.get(
				"models_damaged_by_effect",
				[]
			)

			if models.is_empty():
				return true

			if not context.has("damaged_model_to_move_index"):
				if not _apply_or_request_secondary_choice(
					caster_id,
					"damaged_model",
					context,
					"damaged_model_to_move_index",
					_damaged_model_choice_options(context),
					"Choose one Model damaged by this Effect."
				):
					return false

			if context.has("movement_destination_room_id"):
				return true

			var model_index: int = int(
				context.get(
					"damaged_model_to_move_index",
					-1
				)
			)

			var origin_room_id: String = _damaged_model_room_id(
				context,
				model_index
			)

			if origin_room_id == "":
				return true

			context["movement_origin_room_id"] = origin_room_id
			return _apply_or_request_secondary_choice(
				caster_id,
				"movement_destination",
				context,
				"movement_destination_room_id",
				_movement_destination_choice_options(
					origin_room_id,
					int(effect.get("distance", 1))
				),
				"Choose where to move the selected Model."
			)

		"activate_owned_evocation", \
		"activate_owned_evocation_then_black_rose_damage":
			if context.get(
				"selected_evocation_to_activate",
				null
			) != null:
				return true

			return _apply_or_request_secondary_choice(
				caster_id,
				"owned_evocation",
				context,
				"selected_evocation_to_activate",
				_spell_secondary_evocation_options(
					caster_id,
					caster_id,
					str(
						effect.get(
							"evocation_archetype",
							""
						)
					)
				),
				"Choose one of your Evocations."
			)

		"remove_owned_evocation":
			if context.get(
				"selected_evocation_to_remove",
				null
			) != null:
				return true

			return _apply_or_request_secondary_choice(
				caster_id,
				"owned_evocation_to_remove",
				context,
				"selected_evocation_to_remove",
				_spell_secondary_evocation_options(
					caster_id,
					caster_id,
					str(
						effect.get(
							"evocation_archetype",
							""
						)
					)
				),
				"Choose one of your Evocations to remove."
			)

		"summon_evocation_from_deck":
			if str(
				context.get(
					"chosen_evocation_id",
					""
				)
			) != "":
				return true

			return _apply_or_request_secondary_choice(
				caster_id,
				"evocation_from_deck",
				context,
				"chosen_evocation_id",
				_evocation_deck_choice_options(
					int(effect.get("max_health", 3))
				),
				"Choose an Evocation from the Evocation Deck."
			)

		"redirect_damage_to_evocation":
			# The permanent is installed on cast; choose its recipient only
			# when Damage actually triggers it.
			if context.get("trigger_event") == null:
				return true
			if context.get(
				"selected_evocation_to_redirect",
				null
			) != null:
				return true

			return _apply_or_request_secondary_choice(
				caster_id,
				"damage_redirect_evocation",
				context,
				"selected_evocation_to_redirect",
				_spell_secondary_evocation_options(
					caster_id,
					caster_id
				),
				"Choose one of your Evocations to suffer the Damage."
			)

		"fountain_construct_or_nigredo":
			var target_room_id: String = str(
				context.get("target_room_id", "")
			)

			var construct_options: Array = (
				_spell_secondary_evocation_options(
					caster_id,
					-999999,
					"construct",
					target_room_id
				)
			)

			if str(
				context.get(
					"fountain_choice",
					""
				)
			) == "":
				var branch_options: Array = [
					{
						"token": "fountain:summon_nigredo",
						"value": "summon_nigredo",
						"name": "Summon a Nigredo"
					}
				]

				if not construct_options.is_empty():
					branch_options.append({
						"token": "fountain:activate_construct",
						"value": "activate_construct",
						"name": "Activate a Construct"
					})

				if not _apply_or_request_secondary_choice(
					caster_id,
					"fountain_choice",
					context,
					"fountain_choice",
					branch_options,
					"Choose the Fountain of the Three Effect."
				):
					return false

			if str(context.get("fountain_choice", "")) \
			!= "activate_construct":
				return true

			if context.get(
				"selected_evocation_to_activate",
				null
			) != null:
				return true

			return _apply_or_request_secondary_choice(
				caster_id,
				"construct_to_activate",
				context,
				"selected_evocation_to_activate",
				construct_options,
				"Choose the Construct to activate."
			)

		"silver_defeat_choice":
			var silver_constructs: Array = (
				_spell_secondary_evocation_options(
					caster_id,
					caster_id,
					"construct"
				)
			)

			if str(
				context.get(
					"silver_choice",
					""
				)
			) == "":
				var silver_options: Array = [
					{
						"token": "silver:summon_nigredo",
						"value": "summon_nigredo",
						"name": "Summon a Nigredo"
					}
				]

				if not silver_constructs.is_empty():
					silver_options.append({
						"token": "silver:activate_construct",
						"value": "activate_construct",
						"name": "Activate one of your Constructs"
					})

				if not _apply_or_request_secondary_choice(
					caster_id,
					"silver_choice",
					context,
					"silver_choice",
					silver_options,
					"Choose the Silver of the Sages Effect."
				):
					return false

			if str(context.get("silver_choice", "")) \
			!= "activate_construct":
				return true

			if context.get(
				"selected_evocation_to_activate",
				null
			) != null:
				return true

			return _apply_or_request_secondary_choice(
				caster_id,
				"construct_to_activate",
				context,
				"selected_evocation_to_activate",
				silver_constructs,
				"Choose one of your Constructs."
			)

		_:
			return true


func _clear_spell_secondary_effect_choices(
	effect: Dictionary,
	context: Dictionary
) -> void:
	var effect_type: String = str(
		effect.get("type", "")
	)

	var keys_to_clear: Array[String] = []

	match effect_type:
		"heal":
			keys_to_clear = ["selected_damage_owner_ids"]
		"convert_instability":
			keys_to_clear = ["selected_instability_owner_ids"]
		"damage_secondary_mage_per_self_damage":
			keys_to_clear = [
				"secondary_target_player_index"
			]

		"move_one_model_damaged_by_effect":
			keys_to_clear = [
				"damaged_model_to_move_index",
				"movement_destination_room_id"
			]

		"activate_owned_evocation", \
		"activate_owned_evocation_then_black_rose_damage":
			keys_to_clear = [
				"selected_evocation_to_activate"
			]

		"remove_owned_evocation":
			keys_to_clear = [
				"selected_evocation_to_remove"
			]

		"summon_evocation_from_deck":
			keys_to_clear = [
				"chosen_evocation_id"
			]

		"redirect_damage_to_evocation":
			keys_to_clear = [
				"selected_evocation_to_redirect"
			]

		"fountain_construct_or_nigredo":
			keys_to_clear = [
				"fountain_choice",
				"selected_evocation_to_activate"
			]

		"silver_defeat_choice":
			keys_to_clear = [
				"silver_choice",
				"selected_evocation_to_activate"
			]

	for context_key in keys_to_clear:
		_forget_interactive_effect_choice_key(
			context,
			context_key
		)


func _reset_stepwise_action_activation() -> void:
	action_activation_active = false
	action_activation_player_index = -1
	action_activation_actions_used = 0
	action_activation_numbered_spells_cast = 0
	action_activation_quick_spells_cast = 0


func _start_stepwise_action_activation(
	player_index: int
) -> bool:
	if player_index < 0 or player_index >= players.size():
		return false

	_reset_stepwise_action_activation()

	action_activation_active = true
	action_activation_player_index = player_index

	return _request_stepwise_action_activation()


func _stepwise_action_is_allowed(
	action: Dictionary
) -> bool:
	if action_activation_actions_used >= 2:
		return false

	var action_type: String = str(
		action.get("type", "")
	)

	if action_type == "spell" \
	and action_activation_numbered_spells_cast >= 1:
		return false

	if action_type == "quick" \
	and action_activation_quick_spells_cast >= 1:
		return false

	return true


func _request_stepwise_action_activation() -> bool:
	if not action_activation_active:
		return false

	var player_index: int = action_activation_player_index

	if player_index < 0 or player_index >= players.size():
		_reset_stepwise_action_activation()
		return false

	if waiting_for_player_input:
		return true

	var legal: Dictionary = get_beta_legal_actions(
		player_index
	)

	var options: Array = []
	var option_counter: int = 0

	# Recompute every Action from the CURRENT board state. This is the central
	# difference from the old batch Activation request.
	for action_value in legal.get("actions", []):
		if not action_value is Dictionary:
			continue

		var descriptor: Dictionary = action_value
		var action: Dictionary = descriptor.get(
			"action",
			{}
		)

		if action.is_empty() \
		or not _stepwise_action_is_allowed(action):
			continue

		options.append({
			"token": "action:" + str(option_counter),
			"kind": "action",
			"label": str(
				descriptor.get(
					"label",
					str(action.get("type", "Action"))
				)
			),
			"action": action.duplicate(true),
			"descriptor": descriptor.duplicate(true)
		})

		option_counter += 1

	# Completed Quests are timing windows, not Actions. They remain available
	# before Action 1, between the Actions, and after Action 2.
	for quest_value in legal.get("quests", []):
		if not quest_value is Dictionary:
			continue

		var quest_descriptor: Dictionary = quest_value
		var quest_action: Dictionary = quest_descriptor.get(
			"action",
			{}
		)

		if quest_action.is_empty():
			continue

		options.append({
			"token": "quest:" + str(
				quest_descriptor.get(
					"quest_index",
					-1
				)
			),
			"kind": "quest",
			"label": str(
				quest_descriptor.get(
					"label",
					"Resolve Quest"
				)
			),
			"action": quest_action.duplicate(true),
			"descriptor": quest_descriptor.duplicate(true)
		})

	# After at least one real Action the player may end the Activation.
	if action_activation_actions_used >= 1:
		options.append({
			"token": "finish",
			"kind": "finish",
			"label": "End Activation"
		})

	# If the second Action has been used and no Quest timing window remains,
	# ending the Activation requires no further user click.
	if action_activation_actions_used >= 2:
		var has_quest_option: bool = false

		for option_value in options:
			if str(option_value.get("kind", "")) == "quest":
				has_quest_option = true
				break

		if not has_quest_option:
			return _finish_stepwise_action_activation()

	# If one Action was used and nothing else can be done, finish immediately.
	if action_activation_actions_used >= 1 \
	and options.size() == 1 \
	and str(options[0].get("kind", "")) == "finish":
		return _finish_stepwise_action_activation()

	if options.is_empty():
		print(
			"Stepwise Activation has no legal option for Player ",
			player_index + 1
		)

		_reset_stepwise_action_activation()
		return advance_action_phase()

	return request_player_input({
		"type": "action_activation_step",
		"phase": PHASE_ACTION,
		"player_index": player_index,
		"activation_round": action_phase_activation_round,
		"actions_used": action_activation_actions_used,
		"actions_remaining": max(
			0,
			2 - action_activation_actions_used
		),
		"numbered_spells_cast":
			action_activation_numbered_spells_cast,
		"quick_spells_cast":
			action_activation_quick_spells_cast,
		"can_finish": action_activation_actions_used >= 1,
		"options": options,
		"legal_actions": legal
	})


func submit_action_activation_step(
	player_index: int,
	token: String
) -> bool:
	if not action_activation_active \
	or not waiting_for_player_input:
		return false

	if str(
		pending_input.get(
			"type",
			""
		)
	) != "action_activation_step":
		return false

	if player_index != action_activation_player_index \
	or player_index != int(
		pending_input.get(
			"player_index",
			-1
		)
	):
		return false

	var selected: Dictionary = {}

	for option_value in pending_input.get("options", []):
		if not option_value is Dictionary:
			continue

		var option: Dictionary = option_value

		if str(option.get("token", "")) == token:
			selected = option
			break

	if selected.is_empty():
		return false

	var kind: String = str(
		selected.get(
			"kind",
			""
		)
	)

	if kind == "finish":
		if action_activation_actions_used < 1:
			return false

		clear_player_input()
		return _finish_stepwise_action_activation()

	var action: Dictionary = selected.get(
		"action",
		{}
	).duplicate(true)

	if action.is_empty():
		return false

	clear_player_input()

	if kind == "quest":
		# Quest timing does not consume either Action slot.
		return queue_resolution({
			"type": "activation",
			"step": "actions",
			"player_index": player_index,
			"actions": [action],
			"action_index": 0,
			"on_complete": "continue_action_activation"
		})

	if kind != "action" \
	or not _stepwise_action_is_allowed(action):
		return false

	action_activation_actions_used += 1

	var action_type: String = str(
		action.get(
			"type",
			""
		)
	)

	if action_type == "spell":
		action_activation_numbered_spells_cast += 1
	elif action_type == "quick":
		action_activation_quick_spells_cast += 1

	return queue_resolution({
		"type": "activation",
		"step": "actions",
		"player_index": player_index,
		"actions": [action],
		"action_index": 0,
		"on_complete": "continue_action_activation"
	})


func _finish_stepwise_action_activation() -> bool:
	if not action_activation_active:
		return false

	var player_index: int = action_activation_player_index
	var actions_used: int = action_activation_actions_used

	print(
		"Player ",
		player_index + 1,
		" Activation complete | Actions: ",
		actions_used
	)

	_reset_stepwise_action_activation()

	return advance_action_phase()

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

		var momentum_options: Array = []

		for ready_index in range(
			players[player_index].ready_spells.size()
		):
			var ready: ReadySpellState = (
				players[player_index].ready_spells[
					ready_index
				]
			)

			if ready == null or ready.spell == null:
				continue

			momentum_options.append({
				"ready_index": ready_index,
				"use_quick": false,
				"spell_id": ready.spell.id,
				"spell_name": ready.spell.card_name
			})

		if players[player_index].quick_spell != null 		and players[player_index].quick_spell.spell != null:
			momentum_options.append({
				"ready_index": -1,
				"use_quick": true,
				"spell_id": players[player_index].quick_spell.spell.id,
				"spell_name": players[player_index].quick_spell.spell.card_name
			})

		return _start_stepwise_action_activation(
			player_index
		)


	# =====================================================
	# We skipped every player.
	#
	# Re-evaluate phase state rather than waiting for input.
	# =====================================================

	return advance_action_phase()
	
func _get_solvable_quest_activation_data(
	player_index: int
) -> Array:

	var result: Array = []

	if player_index < 0 \
	or player_index >= players.size():
		return result

	var player = players[player_index]

	for i in range(player.completed_quests.size()):
		var quest: QuestState = player.completed_quests[i]

		if quest == null or not quest.is_completed():
			continue

		result.append({
			"quest_index": i,
			"id": quest.get_id(),
			"name": quest.get_name(),
			"power_reward": quest.get_power_reward()
		})

	return result


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
	_reset_stepwise_action_activation()
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


	for hand_index in range(player.hand.size()):

		var spell: SpellCardState = player.hand[hand_index]

		if spell == null:
			continue


		hand_data.append(
			{
				"hand_index": hand_index,
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
	ready_hand_indices: Array,
	ready_dark_sides: Array,
	quick_hand_index: int = -1,
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
	# =====================================================

	if not prepare_player_spells(
		player_index,
		ready_hand_indices,
		ready_dark_sides,
		quick_hand_index,
		quick_dark_side
	):

		print(
			"submit_preparation: invalid preparation for Player ",
			player_index + 1
		)

		return false


	# =====================================================
	# CHOICE ACCEPTED
	# =====================================================

	clear_player_input()

	preparation_phase_cursor += 1

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


		move_spell_to_memories_or_remove(
			player_index,
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
	spell: SpellCardState,
	use_dark_side: bool = false
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
	var placed: int = place_instability(
		player_index,
		mage.room_id,
		1
	)

	# The central Instability icon is itself a Spell Effect (rulebook p.16).
	# It can therefore progress Quests such as Channeling Instability and the
	# element-symbol Quests if at least one cube was actually placed.
	if placed > 0:
		var side: Dictionary = spell.get_side(use_dark_side)
		quest_manager.process_event(
			self,
			{
				"type": "effect_resolved",
				"player_index": player_index,
				"source_kind": "spell",
				"effect_type": "place_instability",
				"spell_type": str(side.get("type", "")),
				"spell_element": str(side.get("element", "")),
				"spell_side": side,
				"instability_placed": placed,
				"keywords": []
			}
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
			"action_events":
				completed = process_action_events_resolution(frame)
			"event_tribute":
				completed = process_tribute_resolution(frame)
			"event_sequence":
				completed = event_effect_resolver.process_sequence(frame, self)
			"event_effect":
				completed = event_effect_resolver.process_effect(frame, self)
			"damage":
				completed = process_damage_resolution(frame)
			"evocation_damage":
				completed = process_evocation_damage_resolution(frame)
			"evocation_damage_ability":
				completed = process_evocation_damage_ability(frame)
			"effect_sequence":
				completed = process_effect_sequence_resolution(frame)
			"quest_resolution":
				completed = process_quest_resolution_frame(frame)
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
			"momentum":
				completed = process_momentum_resolution(frame)
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

func process_action_events_resolution(frame: Dictionary) -> bool:
	var events: Array = frame.get("events", [])
	var index: int = int(frame.get("index", 0))
	if index >= events.size():
		return true
	frame["index"] = index + 1
	if not resolve_event(events[index], frame.get("context", {})):
		push_error("Action Event could not resolve: " + events[index].event_name)
		frame["on_complete"] = ""
		return true
	return false


func process_tribute_resolution(frame: Dictionary) -> bool:
	var order: Array = frame.get("order", [])
	var cursor: int = int(frame.get("cursor", 0))
	if cursor >= order.size():
		return true
	var player_index: int = int(order[cursor])
	if not frame.has("accepted"):
		request_effect_choice(player_index, "event_tribute", frame, "accepted", [
			{"token": "accept", "value": true, "label": "Suffer 1 Damage and activate an Evocation"},
			{"token": "decline", "value": false, "label": "Decline"}
		], 1, 1, "Tribute of the Command")
		return false
	if bool(frame.accepted):
		if not bool(frame.get("damage_queued", false)):
			frame["damage_queued"] = true
			frame["damage_result"] = {"last_damage_dealt": 0}
			queue_resolution({"type": "damage", "attacker_id": -1,
				"target_player_index": player_index, "amount": int(frame.get("damage", 1)),
				"action_type": "event", "result_context": frame.damage_result})
			return false
		if int(frame.damage_result.get("last_damage_dealt", 0)) < int(frame.get("damage", 1)) or frame.damage_result.get("last_damage_redirected_evocation") != null or int(frame.damage_result.get("last_damage_target_player_index", -1)) != player_index:
			frame["accepted"] = false
			return false
		if not frame.has("evocation"):
			var options: Array = []
			for owner_index in range(players.size()):
				for i in range(players[owner_index].evocations.size()):
					var evocation: EvocationState = players[owner_index].evocations[i]
					if evocation != null and not evocation.is_defeated():
						options.append({"token": "evocation:%d:%d" % [owner_index, i], "value": evocation,
							"owner_id": owner_index, "evocation_index": i, "name": evocation.get_display_name()})
			if not options.is_empty():
				request_effect_choice(player_index, "target_evocation", frame, "evocation", options, 1, 1, "Choose an Evocation to activate under your control.")
				return false
			frame["evocation"] = null
		var chosen: EvocationState = frame.get("evocation")
		if chosen != null:
			activate_evocation(chosen, player_index)
	frame["cursor"] = cursor + 1
	frame.erase("accepted")
	frame.erase("damage_queued")
	frame.erase("damage_result")
	frame.erase("evocation")
	return false


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
			if redirected_evocation == null or redirected_evocation.is_defeated() or is_event_active("immortals"):
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

				return false

			return true

		"after_redirect_defeat":
			var redirected_evocation = resolution.get(
				"redirected_evocation",
				null
			)

			if redirected_evocation != null:
				var room_id: String = redirected_evocation.room_id

				finalize_evocation_removal(
					redirected_evocation
				)

				_apply_puppeteer_after_evocation_loss(
					room_id
				)

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
			var victim: int = int(resolution.get("target_player_index", -1))
			if not players[victim].mage.is_defeated():
				return true
			# Defeat interrupts only physical resolutions already in progress.
			# A player-level flag would incorrectly cancel the next Cell exit.
			for frame in resolution_stack:
				if str(frame.get("type", "")) in ["explore", "fight", "command"] and int(frame.get("player_index", -1)) == victim:
					frame["cancelled_by_defeat"] = true
			var killer: int = int(resolution.get("attacker_id", -1))
			if is_event_active("dominion"):
				killer = -1
			if killer == -1:
				black_rose_trophies.append(victim)
			elif killer >= 0 and killer < players.size():
				players[killer].trophies.append(victim)
			var counts: Dictionary = {}
			for owner in players[victim].mage.damage_cubes:
				counts[owner] = int(counts.get(owner, 0)) + 1
			resolution["defeat_rewards"] = ranked_power_rewards(counts, true)
			resolution["reward_owners"] = resolution.defeat_rewards.keys()
			resolution["step"] = "defeat_rewards"
			place_mage_in_cell(victim)
			return false

		"defeat_rewards":
			var owners: Array = resolution.get("reward_owners", [])
			if not owners.is_empty():
				var owner: int = int(owners.pop_front())
				var points: int = int(resolution.defeat_rewards[owner])
				if owner == -1:
					add_black_rose_power(points)
				else:
					add_player_power(owner, points)
				return false
			var victim: int = int(resolution.get("target_player_index", -1))
			var mage = players[victim].mage
			var cubes: Array[int] = mage.damage_cubes.duplicate()
			mage.damage_cubes.clear()
			for owner in cubes:
				return_owner_cubes(owner, 1)
			refresh_all_player_boards()
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
	if current_phase == PHASE_ACTION and is_event_active("puppeteer"):
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
	_queue_evocation_damage_abilities(resolution, actual_damage)
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
	context["last_damage_redirected_evocation"] = resolution.get("redirected_evocation")

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
	var step: String = str(
		resolution.get("step", "pre_event")
	)

	var evocation: EvocationState = resolution.get(
		"evocation",
		null
	)

	if evocation == null:
		return true
	# A trigger may have drawn Immortals after this Damage was queued.
	if step in ["pre_event", "after_pre_event", "apply"] and is_event_active("immortals"):
		_sync_evocation_damage_result_context(resolution, 0)
		return true

	match step:
		"pre_event":
			if evocation.is_defeated() \
			or not is_evocation_in_play(evocation):
				_sync_evocation_damage_result_context(
					resolution,
					0
				)
				return true

			var requested: int = min(
				int(resolution.get("amount", 0)),
				evocation.get_remaining_health()
			)

			if requested <= 0:
				_sync_evocation_damage_result_context(
					resolution,
					0
				)
				return true

			resolution["amount"] = requested
			resolution["was_defeated"] = evocation.is_defeated()

			var event := GameEvent.new(
				"damage_about_to_be_inflicted"
			)

			_fill_damage_event_source(
				event,
				resolution
			)

			event.target_model_type = "evocation"
			event.target_player_index = evocation.owner_id
			event.target_evocation = evocation
			event.target_room_id = evocation.room_id
			event.amount = requested
			event.action_type = str(
				resolution.get("action_type", "")
			)
			event.suppressed_trigger_types = _to_string_array(
				resolution.get(
					"suppressed_trigger_types",
					[]
				)
			)

			resolution["event"] = event
			resolution["step"] = "after_pre_event"

			if not process_game_event(event):
				return false

			return false

		"after_pre_event":
			var event: GameEvent = resolution.get(
				"event",
				null
			)

			if event == null or event.cancelled:
				_sync_evocation_damage_result_context(
					resolution,
					0
				)
				return true

			resolution["amount"] = max(
				0,
				int(event.amount)
			)

			if int(resolution["amount"]) <= 0:
				_sync_evocation_damage_result_context(
					resolution,
					0
				)
				return true

			resolution["step"] = "apply"
			return false

		"apply":
			if evocation.is_defeated() \
			or not is_evocation_in_play(evocation):
				_sync_evocation_damage_result_context(
					resolution,
					0
				)
				return true

			var attacker_id: int = int(
				resolution.get("attacker_id", -1)
			)

			var amount: int = min(
				int(resolution.get("amount", 0)),
				evocation.get_remaining_health()
			)

			if amount <= 0:
				_sync_evocation_damage_result_context(
					resolution,
					0
				)
				return true

			var cubes_available: int = take_owner_cubes(
				attacker_id,
				amount
			)

			if cubes_available <= 0:
				_sync_evocation_damage_result_context(
					resolution,
					0
				)
				return true

			var damage_dealt: int = evocation.add_damage(
				attacker_id,
				cubes_available
			)

			resolution["actual_damage"] = damage_dealt

			_sync_evocation_damage_result_context(
				resolution,
				damage_dealt
			)

			_refresh_damage_boards(
				evocation.owner_id,
				attacker_id
			)

			print(
				"Damage: attacker ",
				attacker_id,
				" -> Evocation ",
				evocation.evocation_name,
				" | ",
				damage_dealt,
				" damage | HP: ",
				evocation.get_remaining_health(),
				"/",
				evocation.health
			)

			if damage_dealt <= 0:
				return true

			resolution["step"] = "post_event"
			return false

		"post_event":
			var post_event := GameEvent.new(
				"damage_inflicted"
			)

			_fill_damage_event_source(
				post_event,
				resolution
			)

			post_event.target_model_type = "evocation"
			post_event.target_player_index = evocation.owner_id
			post_event.target_evocation = evocation
			post_event.target_room_id = evocation.room_id
			post_event.amount = int(
				resolution.get("actual_damage", 0)
			)
			post_event.action_type = str(
				resolution.get("action_type", "")
			)
			post_event.suppressed_trigger_types = _to_string_array(
				resolution.get(
					"suppressed_trigger_types",
					[]
				)
			)

			resolution["step"] = "after_post_event"

			if not process_game_event(post_event):
				return false

			return false

		"after_post_event":
			var was_defeated: bool = bool(
				resolution.get(
					"was_defeated",
					false
				)
			)

			if not was_defeated \
			and evocation.is_defeated():
				var defeat_event := _make_evocation_lost_event(
					evocation,
					"defeated"
				)

				resolution["step"] = "after_defeat_event"

				if not process_game_event(defeat_event):
					return false

				return false

			return true

		"after_defeat_event":
			var room_id: String = evocation.room_id

			finalize_evocation_removal(evocation)
			_apply_puppeteer_after_evocation_loss(room_id)

			return true

		_:
			return true


func _sync_evocation_damage_result_context(
	resolution: Dictionary,
	actual_damage: int
):
	_queue_evocation_damage_abilities(resolution, actual_damage)
	var context: Dictionary = resolution.get("result_context", {})
	if context.is_empty():
		return

	var evocation = resolution.get("evocation", null)
	context["last_damage_dealt"] = actual_damage

	if actual_damage <= 0 or evocation == null:
		return

	context["last_damaged_model_type"] = "evocation"
	context["last_damaged_evocation"] = evocation


func _queue_evocation_damage_abilities(resolution: Dictionary, actual_damage: int) -> void:
	if actual_damage <= 0 or bool(resolution.get("damage_abilities_queued", false)):
		return
	var source: EvocationState = resolution.get("source_evocation")
	if str(resolution.get("source_model_type", "")) != "evocation" or source == null:
		return
	resolution["damage_abilities_queued"] = true
	var abilities: Array = evocation_database.get_evocation(source.evocation_id).get("abilities", [])
	# Stack frames retain the controller and location at the moment damage occurs.
	for index in range(abilities.size() - 1, -1, -1):
		var ability: Dictionary = abilities[index]
		if str(ability.get("type", "")) != "on_inflict_damage":
			continue
		queue_resolution({
			"type": "evocation_damage_ability", "ability": ability,
			"name": source.get_display_name(),
			"context": {"game": self, "caster_id": int(resolution.get("attacker_id", -1)),
				"caster_room_id": source.room_id, "target_room_id": source.room_id}
		})


func process_evocation_damage_ability(resolution: Dictionary) -> bool:
	var context: Dictionary = resolution.context
	var controller: int = int(context.caster_id)
	if controller < 0 or controller >= players.size():
		return true
	var ability: Dictionary = resolution.ability
	if not context.has("ability_choice"):
		var options: Array = []
		for effect in ability.get("choices", []):
			options.append({"token": "ability:" + str(options.size()), "value": effect,
				"name": str(effect.get("type", "")).replace("_", " ").capitalize() + " " + str(effect.get("amount", 1))})
		if options.is_empty():
			return true
		request_effect_choice(controller, "evocation_damage_ability", context, "ability_choice", options,
			0 if bool(ability.get("optional", false)) else 1, 1,
			str(resolution.name) + ": choose an Instability effect in its Room, or skip.")
		return false
	var selected = context.get("ability_choice")
	if selected is Dictionary:
		queue_resolution({"type": "effect_sequence", "resolver_kind": "evocation",
			"effects": [selected], "index": 0, "context": context})
	return true


func process_quest_resolution_frame(
	resolution: Dictionary
) -> bool:
	var step: String = str(resolution.get("step", "start"))
	var player_index: int = int(resolution.get("player_index", -1))
	var quest: QuestState = resolution.get("quest", null)
	var context: Dictionary = resolution.get("context", {})

	if player_index < 0 or player_index >= players.size() or quest == null:
		return true

	match step:
		"start":
			if not quest.is_completed() or quest.is_solved():
				return true

			resolution["step"] = "finish"
			var effects: Array = quest.get_effects()

			if not effects.is_empty():
				queue_resolution({
					"type": "effect_sequence",
					"resolver_kind": "quest",
					"effects": effects,
					"index": 0,
					"context": context
				})

			return false

		"finish":
			if bool(context.get("quest_resolution_hard_failed", false)):
				print("Quest resolution failed due to an unsupported Effect")
				return true

			# Set the next step before awarding Power, because Power gain can open
			# a Trap/Protection window and temporarily pause the resolution stack.
			resolution["step"] = "emit_solved"
			resolution["finalized"] = quest_manager.finalize_quest_solve(
				self,
				player_index,
				quest
			)
			return false

		"emit_solved":
			# Same protection against re-entry: the event itself can open a trigger
			# window (e.g. Master of Pleasure).
			resolution["step"] = "done"
			if bool(resolution.get("finalized", false)):
				quest_manager.emit_quest_solved_event(
					self,
					player_index,
					quest
				)
			return false

		"done":
			return true

		_:
			return true



func _prepare_room_effect_choice(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var caster_id: int = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 or caster_id >= players.size():
		return true

	var effect_type: String = str(effect.get("type", ""))
	if effect_type == "draw_forgotten_choose":
		if context.has("selected_forgotten_spell"):
			return true
		var options: Array = []
		for offset in range(mini(int(effect.get("draw", 2)), forgotten_deck.size())):
			var index: int = forgotten_deck.size() - 1 - offset
			var spell: SpellCardState = forgotten_deck[index]
			options.append({"token": "forgotten:" + str(index), "value": spell, "id": spell.id, "name": spell.card_name})
		return _apply_or_request_secondary_choice(caster_id, "room_forgotten_keep", context,
			"selected_forgotten_spell", options, "Choose the Forgotten Spell to keep.")

	if effect_type in ["discard_quest", "discard_spells"]:
		var quest_choice: bool = effect_type == "discard_quest"
		var key: String = "room_discard_quests" if quest_choice else "discard_spell_ids"
		if context.has(key):
			return true
		var source: Array = players[caster_id].active_quests if quest_choice else players[caster_id].hand
		var amount: int = mini(maxi(0, int(effect.get("amount", 1))), source.size())
		var options: Array = []
		var all_values: Array = []
		for index in range(source.size()):
			var card = source[index]
			var value = card if quest_choice else card.id
			all_values.append(value)
			options.append({"token": "discard:" + str(index), "value": value,
				"name": card.get_name() if quest_choice else card.card_name})
		if amount == source.size() or amount == 0:
			_set_interactive_effect_choice(context, key, all_values if amount > 0 else [])
			return true
		return not request_effect_choice(caster_id, "room_discard", context, key, options,
			amount, amount, "Choose %d %s to discard." % [amount, "Quests" if quest_choice else "Spells"])

	var target_type: String = str(
		effect.get(
			"target",
			""
		)
	)

	if target_type != "room" \
	and target_type != "choose_room":
		return true

	if str(
		context.get(
			"target_room_id",
			""
		)
	) != "":
		return true

	var options: Array = _quest_room_choice_options(
		caster_id,
		effect,
		str(context.get("effect_origin_room_id", ""))
	)

	if options.is_empty():
		context["room_effect_no_target"] = true
		return true

	# request_effect_choice() returns true when the input request was created.
	# _prepare_* helpers use the opposite convention: false means "pause the
	# current resolution frame and wait for player input".
	if request_effect_choice(
		caster_id,
		"room_effect_room_target",
		context,
		"target_room_id",
		options,
		1,
		1,
		"Choose the target Room"
	):
		return false

	# If the request could not be created, do not deadlock the resolution
	# frame. Let the Room Effect resolver handle the sentence normally.
	return true

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

	context["resolver_kind"] = resolver_kind
	context.erase("effect_resolution_error")


	# Quest Effects may require a player decision.  Do this before applying
	# the Effect so no game state is changed until all required choices for
	# this sentence are known.
	if resolver_kind == "quest":
		# A target supplied to solve the Quest is not a target for every sentence.
		# Initialize once per Effect, retaining its choices while input is pending.
		if int(resolution.get("target_effect_index", -1)) != index:
			resolution["target_effect_index"] = index
			if not str(effect.get("target", "")).is_empty():
				for key in ["target_room_id", "target_player_index", "target_evocation", "target_model_type", "quest_target_model", "selected_evocation_to_activate"]:
					context.erase(key)
		if not _prepare_quest_effect_choice(
			effect,
			context
		):
			# The frame must retry the same Effect after submit_effect_choice()
			# stores the selected runtime value in the live context.
			resolution["index"] = index
			return false

	if resolver_kind in ["spell", "evocation"]:
		if not _prepare_spell_secondary_effect_choice(
			effect,
			context
		):
			# Secondary Spell decisions use the same live-context / resolution
			# stack mechanism as Quest choices.
			resolution["index"] = index
			return false

	if resolver_kind == "room":
		if not _prepare_room_effect_choice(
			effect,
			context
		):
			# Retry the same Room sentence after the player selects a target.
			resolution["index"] = index
			return false


	if not _prepare_damage_conversion_choices(effect, context):
		resolution["index"] = index
		return false

	# Per-effect runtime metadata. Individual low-level operations may update
	# these fields while this effect is being resolved.
	context["effect_instability_placed"] = 0
	context["effect_instability_converted"] = 0
	context["effect_damage_converted"] = 0
	context["effect_damage_healed"] = 0
	context["effect_target_room_id"] = ""
	context["effect_target_model_type"] = ""

	active_effect_context = context

	var success: bool = false


	match resolver_kind:

		"spell", "quest", "evocation":
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


	# Safety net: an Effect handler may itself request input in the future.
	# If that happens, retry the same Effect when the answer arrives.
	if waiting_for_player_input \
	and str(pending_input.get("type", "")) == "effect_choice":
		resolution["index"] = index
		return false



	if not success:

		# Unknown Effect types are implementation errors and must never be
		# silently treated as an in-game impossible phrase.
		if str(context.get("effect_resolution_error", "")) == "unknown_effect_type":
			if resolver_kind == "quest":
				context["quest_resolution_hard_failed"] = true
				_clear_interactive_effect_choices(context)

			print(
				"Resolution aborted: unknown Effect type ",
				str(effect.get("type", "")),
				" | kind ",
				resolver_kind
			)

			resolution["failed"] = true
			return true

		# If a phrase cannot be applied, skip that phrase and continue. This
		# applies to both Quest and Spell Effects.
		if resolver_kind in ["quest", "spell", "evocation"]:
			print(
				resolver_kind.capitalize(),
				" Effect could not be applied; skipped | effect ",
				str(effect.get("type", ""))
			)

			if resolver_kind == "quest":
				_clear_interactive_effect_choices(context)
			else:
				_clear_spell_secondary_effect_choices(
					effect,
					context
				)

			return (
				int(resolution.get("index", 0))
					>= effects.size()
			)

		print(
			"Effect resolution failed | kind ",
			resolver_kind,
			" | effect ",
			str(effect.get("type", ""))
		)

		resolution["failed"] = true
		return true


	# =====================================================
	# QUEST EVENT: EFFECT RESOLVED
	#
	# Any successfully resolved player-controlled Effect can be relevant to a
	# Quest. The event carries source metadata so each Quest can discriminate
	# Spell Effects, Room Effects, keywords and actual Instability placement.
	# =====================================================

	var caster_id: int = int(context.get("caster_id", -1))

	if caster_id >= 0 and caster_id < players.size():

		var effect_type: String = str(effect.get("type", ""))
		var keywords: Array[String] = []

		# Current data model represents the Summon keyword through summon_*
		# Effect types. Explicit keywords are also supported for future cards.
		if effect_type.begins_with("summon_"):
			keywords.append("summon")

		for keyword in effect.get("keywords", []):
			var keyword_string: String = str(keyword)
			if not keyword_string in keywords:
				keywords.append(keyword_string)

		var effect_room_id: String = str(
			context.get(
				"effect_target_room_id",
				context.get(
					"target_room_id",
					context.get(
						"caster_room_id",
						""
					)
				)
			)
		)

		var effect_room_color: String = ""

		if effect_room_id != "":
			var effect_room = get_room_by_id(
				effect_room_id
			)

			if effect_room != null:
				effect_room_color = str(
					effect_room.get_room_data().get(
						"color",
						""
					)
				)

		var quest_event: Dictionary = {
			"type": "effect_resolved",
			"player_index": caster_id,
			"source_kind": resolver_kind,
			"effect_type": effect_type,
			"spell_type": str(context.get("spell_type", "")),
			"spell_element": str(context.get("spell_element", "")),
			"spell_side": context.get("spell_side", {}),
			"caster_room_id": str(
				context.get(
					"caster_room_id",
					""
				)
			),
			"effect_target_room_id": effect_room_id,
			"effect_room_color": effect_room_color,
			"effect_target_model_type": str(
				context.get(
					"effect_target_model_type",
					context.get(
						"target_model_type",
						""
					)
				)
			),
			"instability_placed": int(
				context.get("effect_instability_placed", 0)
			),
			"instability_converted": int(
				context.get(
					"effect_instability_converted",
					0
				)
			),
			"damage_converted": int(
				context.get(
					"effect_damage_converted",
					0
				)
			),
			"damage_healed": int(
				context.get(
					"effect_damage_healed",
					0
				)
			),
			"keywords": keywords,
			"effect": effect
		}

		quest_manager.process_event(
			self,
			quest_event
		)


	for key in context.keys():
		if str(key).begins_with("convert_mage:") or str(key).begins_with("convert_evocation:"):
			_forget_interactive_effect_choice_key(context, key)

	if resolver_kind == "quest":
		# Choices belong to one sentence/Effect only. This is important for
		# cards such as Shattered Illusion, whose two separate "Place 1"
		# Effects may target two different Rooms.
		_clear_interactive_effect_choices(context)

	if resolver_kind == "room":
		_clear_interactive_effect_choices(context)
		context.erase("room_effect_no_target")

	if resolver_kind == "spell":
		# Primary target data belongs to the whole Spell, but secondary choices
		# belong only to the sentence that requested them.
		_clear_spell_secondary_effect_choices(
			effect,
			context
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

			context["spell_type"] = str(side.get("type", ""))
			context["spell_side"] = side
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
						_enhancement_required_elements(
							enhancement
						), spell
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

			resolution["step"] = "done"
			var revealed = RevealedSpellState.new(
				spell,
				use_dark_side
			)

			players[
				caster_id
			].add_revealed_spell(
				revealed
			)

			_set_player_board_spell_state(
				caster_id,
				spell,
				"revealed"
			)

			_register_ongoing_revealed_spell(
				caster_id,
				spell,
				use_dark_side,
				context
			)

			_apply_event_after_spell(caster_id, str(context.get("spell_type", "")))

			# The entire Spell has now resolved.  This is distinct from the
			# effect_resolved events emitted for its individual Effect entries.
			quest_manager.process_event(
				self,
				{
					"type": "spell_resolved",
					"player_index": caster_id,
					"source_kind": "spell",
					"spell_id": spell.id,
					"spell_type": str(context.get("spell_type", "")),
					"spell_element": str(context.get("spell_element", "")),
					"spell_side": context.get("spell_side", {}),
					"caster_room_id": players[
						caster_id
					].mage.room_id
				}
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
			var targeting_side: Dictionary = _spell_effective_target_side(
				player_index,
				side, spell
			)

			if spell_type != "combat" \
			and spell_type != "contingency" \
			and spell_type != "trap" \
			and spell_type != "protection":
				print("Unsupported Spell type: ", spell_type)
				return true

			# Combat and Contingency Spells choose their primary target when
			# cast. Trap/Protection targets are determined by their trigger
			# semantics and remain handled by the Active Spell system.
			if spell_type == "combat" or spell_type == "contingency":
				if not _prepare_spell_primary_target_choice(
					player_index,
					targeting_side,
					context
				):
					resolution["context"] = context
					return false

			# If the caller already supplied a target, enforce the common
			# Range + Line of Sight rules before consuming the prepared card.
			# Missing targets are allowed here because some Trap/Protection and
			# special Effects determine their target only when they resolve.
			if not validate_target_range_from_context(
				player_index,
				str(targeting_side.get("target", "")),
				targeting_side.get("range", null),
				context
			):
				print(
					"Illegal Spell target: outside Range or Line of Sight | ",
					spell.card_name
				)
				return true

			# The card leaves its prepared slot only after the Cast Action itself
			# has been validated. This avoids consuming a prepared card on an
			# invalid/unsupported cast request.
			if str(targeting_side.get("target", "")) in ["room", "area"] and not _spell_room_target_allowed(
				player_index, targeting_side, str(context.get("target_room_id", ""))
			):
				print("Illegal Spell Room target: ", spell.card_name)
				return true
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
				_set_player_board_spell_state(
					player_index,
					spell,
					"active_hidden"
				)
				print(
					"Player ", player_index + 1,
					" activates ", spell.card_name,
					" [", spell_type, "]"
				)
				return true

			# Cast validation and prepared-card consumption have committed the play.
			_set_player_board_spell_state(player_index, spell, "revealed")
			if not resolve_spell_reveal_instability(player_index, spell, use_dark_side):
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
				_set_player_board_spell_state(owner_id, active_spell.spell, "revealed")

			var active_side: Dictionary = active_spell.get_side()

			var context: Dictionary = {
				"game": self,
				"caster_id": owner_id,
				"caster_room_id": players[owner_id].mage.room_id,
				"spell_id": active_spell.spell.id,
				"spell_type": spell_type,
				"spell_element": str(active_side.get("element", "")),
				"spell_side": active_side,
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
				resolve_spell_reveal_instability(owner_id, active_spell.spell, active_spell.use_dark_side)

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
				_set_player_board_spell_state(
					owner_id,
					active_spell.spell,
					"revealed"
				)

			if spell_type == "trap" or spell_type == "protection":
				quest_manager.process_event(
					self,
					{
						"type": "spell_resolved",
						"player_index": owner_id,
						"source_kind": "spell",
						"spell_id": active_spell.spell.id,
						"spell_type": spell_type,
						"spell_element": str(context.get("spell_element", "")),
						"spell_side": context.get("spell_side", {})
					}
				)

			resolution["step"] = "done"
			_apply_event_after_spell(owner_id, active_spell.get_spell_type())
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

			# Explicit Area targets are selected interactively per Effect.
			# RoomEffectResolver still defaults untargeted Effects to room_id.
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
			# Passive Events are consumed at activation, never at phase start.
			for event in active_events:
				if event == null or event.phase != current_phase:
					continue
				for effect in event.effects:
					if effect.get("type", "") == "on_activate_room_color_black_rose_gain_power" and effect.get("color", "") == room.room_data.get("color", ""):
						add_black_rose_power(int(effect.get("amount", 1)))

			quest_manager.process_event(
				self,
				{
					"type": "room_effect_resolved",
					"player_index": player_index,
					"source_kind": "room",
					"room_id": room.get_room_id(),
					"room_color": str(
						room.get_room_data().get("color", "")
					)
				}
			)

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

	if actions.is_empty():
		return false

	var player = players[player_index]
	var actual_action_count: int = 0
	var normal_spell_count: int = 0
	var quick_spell_count: int = 0
	var seen_quest_indices: Dictionary = {}

	for action_value in actions:
		if not action_value is Dictionary:
			return false

		var action: Dictionary = action_value
		var action_type: String = str(action.get("type", ""))

		# Completed Quests are resolved during an Activation, but they are
		# not Actions and therefore do not count toward the 1-2 Action limit.
		if action_type == "quest":
			var quest_index: int = int(action.get("quest_index", -1))

			if quest_index < 0 \
			or quest_index >= player.completed_quests.size():
				return false

			if seen_quest_indices.has(quest_index):
				return false

			var quest: QuestState = player.completed_quests[quest_index]
			if quest == null or not quest.is_completed():
				return false

			seen_quest_indices[quest_index] = true
			continue

		actual_action_count += 1

		if action_type == "spell":
			normal_spell_count += 1
		elif action_type == "quick":
			quick_spell_count += 1

	if actual_action_count < 1 or actual_action_count > 2:
		return false

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

	# Quest resolution is an Activation timing window, not an Action.
	# It may therefore appear before, between or after the Mage's 1-2 Actions.
	if str(action.get("type", "")) == "quest":
		var player = players[player_index]

		# A Mage in their Cell may only perform the specific operations listed
		# by the Cell rules; resolving a Completed Quest is not one of them.
		if player.mage.in_cell:
			print(
				"Quest resolution skipped: Player ",
				player_index + 1,
				" is in their Cell"
			)
			return false

		var quest_index: int = int(action.get("quest_index", -1))
		if quest_index < 0 \
		or quest_index >= player.completed_quests.size():
			print("Quest resolution skipped: invalid Quest index")
			return false

		var quest: QuestState = player.completed_quests[quest_index]
		if quest == null or not quest.is_completed():
			print("Quest resolution skipped: Quest is no longer Completed")
			return false

		var quest_context: Dictionary = action.get("context", {}).duplicate(true)
		quest_context["activation_player_index"] = player_index

		if not quest_manager.solve_quest(
			self,
			player_index,
			quest,
			quest_context
		):
			print("Activation Quest resolution failed: ", quest.get_name())
			return true

		return false

	if not perform_player_action(player_index, action):
		print("Activation Action failed: ", action.get("type", ""))
		return true

	return false



func process_momentum_resolution(
	resolution: Dictionary
) -> bool:
	var player_index: int = int(
		resolution.get("player_index", -1)
	)

	if player_index < 0 or player_index >= players.size():
		return true

	var player = players[player_index]
	var context: Dictionary = resolution.get("context", {})

	match str(resolution.get("step", "discard")):
		"discard":
			var use_quick: bool = bool(
				resolution.get("use_quick", false)
			)

			var spell: SpellCardState = null

			if use_quick:
				if player.quick_spell == null:
					return true

				spell = player.quick_spell.spell
				player.quick_spell = null
			else:
				var ready_index: int = int(
					resolution.get("ready_index", -1)
				)

				if ready_index < 0 \
				or ready_index >= player.ready_spells.size():
					return true

				var ready: ReadySpellState = (
					player.ready_spells[ready_index]
				)

				if ready == null or ready.spell == null:
					return true

				spell = ready.spell
				player.ready_spells.remove_at(ready_index)

			if spell == null:
				return true

			move_spell_to_memories_or_remove(
				player_index,
				spell
			)

			_clear_player_board_spell_by_spell(
				player_index,
				spell
			)
			resolution["discarded_spell_id"] = spell.id
			resolution["step"] = "move"
			return false

		"move":
			var destination_room_id: String = str(
				resolution.get(
					"destination_room_id",
					""
				)
			)

			if destination_room_id != "":
				if not move_mage_to_room_id(
					player_index,
					destination_room_id,
					1
				):
					return true

			resolution["step"] = "done"
			return false

		"done":
			context["last_action_type"] = "momentum"

			print(
				"Player ",
				player_index + 1,
				" performed Momentum | discarded ",
				str(
					resolution.get(
						"discarded_spell_id",
						""
					)
				)
			)

			return true

		_:
			return true

func process_explore_resolution(
	resolution: Dictionary
) -> bool:
	var player_index: int = int(resolution.get("player_index", -1))
	if player_index < 0 or player_index >= players.size():
		return true

	if bool(resolution.get("cancelled_by_defeat", false)):
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

			refresh_player_board(player_index)
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

	if bool(resolution.get("cancelled_by_defeat", false)):
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

			refresh_player_board(player_index)
			if bool(resolution.get("perform_room_activation", true)) \
			and bool(resolution.get("activate_room_first", false)):
				resolution["step"] = "attack"
				activate_room(player_index, player.mage.room_id, false, context)
				return false

			resolution["step"] = "attack"
			return false

		"attack":
			resolution["step"] = "room_after"

			if not bool(
				resolution.get(
					"perform_attack",
					true
				)
			):
				return false

			var target_model_type: String = str(
				resolution.get(
					"target_model_type",
					""
				)
			)

			if target_model_type == "":
				if int(
					resolution.get(
						"target_player_index",
						-1
					)
				) >= 0:
					target_model_type = "mage"

			if target_model_type == "mage":
				var target_player_index: int = int(
					resolution.get(
						"target_player_index",
						-1
					)
				)

				if target_player_index < 0 				or target_player_index >= players.size() 				or target_player_index == player_index:
					return false

				var target = players[target_player_index]

				if target.mage.in_cell 				or target.mage.room_id != player.mage.room_id:
					return false

				deal_damage(
					player_index,
					target_player_index,
					player.mage.strength,
					"physical_attack"
				)

				return false

			if target_model_type == "evocation":
				var target_evocation: EvocationState = resolution.get(
					"target_evocation",
					null
				)

				if not _valid_mage_physical_attack_evocation(
					player_index,
					target_evocation
				):
					return false

				deal_damage_to_evocation(
					player_index,
					target_evocation,
					player.mage.strength,
					[],
					"physical_attack",
					"mage",
					null
				)

				return false

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

	if bool(resolution.get("cancelled_by_defeat", false)):
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

			refresh_player_board(player_index)
			var evocation: EvocationState = player.evocations[evocation_index]
			var controller_id: int = get_evocation_controller_id(
				evocation
			)
			var activation_context: Dictionary = resolution.get(
				"context",
				{}
			)

			if not _validate_evocation_activation_context(
				evocation,
				controller_id,
				activation_context
			):
				return true

			resolution["step"] = "done"
			activate_evocation(
				evocation,
				controller_id,
				activation_context
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
	var evocation: EvocationState = resolution.get(
		"evocation",
		null
	)

	if evocation == null \
	or evocation.is_defeated() \
	or not is_evocation_in_play(evocation):
		return true

	var controller_id: int = int(
		resolution.get(
			"controller_id",
			get_evocation_controller_id(evocation)
		)
	)

	var context: Dictionary = resolution.get(
		"context",
		{}
	)

	var strength_bonus: int = int(
		resolution.get(
			"strength_bonus",
			0
		)
	)

	var activation_strength: int = (
		evocation.strength
		+ strength_bonus
	)

	var attack_timing: String = str(
		context.get(
			"evocation_attack_timing",
			"none"
		)
	)

	var move_room_ids: Array = context.get(
		"evocation_move_room_ids",
		[]
	)

	match str(resolution.get("step", "start")):
		"start":
			# Spell-triggered activations need a plan just like Phase/Command activations.
			if not context.has("evocation_attack_timing") and not context.has("evocation_move_room_ids"):
				if not resolution.has("activation_plan"):
					var options: Array = []
					for plan in _beta_evocation_activation_plans(
						evocation, controller_id, int(context.get("evocation_activation_speed_bonus", 0))
					):
						options.append({
							"token": "activation_plan:" + str(options.size()),
							"label": str(plan.get("label", "Activate")) + " | " + " → ".join(plan.get("path", [])),
							"path": plan.get("path", []).duplicate(),
							"value": plan.get("context", {})
						})
					if not _apply_or_request_secondary_choice(
						controller_id, "evocation_activation_plan", resolution, "activation_plan", options,
						"Choose movement and attack for " + evocation.get_display_name() + "."
					):
						return false
				# Keep this activation's plan out of the parent spell's later Effects.
				context = context.duplicate(true)
				context.merge(resolution.get("activation_plan", {}), true)
				resolution["context"] = context
			if not _validate_evocation_activation_context(
				evocation,
				controller_id,
				context
			):
				return true

			resolution["step"] = "attack_before"
			return false

		"attack_before":
			resolution["step"] = "move"

			if attack_timing == "before":
				# The target could have disappeared because another pending
				# trigger resolved first. In that case only the attack is lost;
				# the rest of the Evocation activation still continues.
				if _perform_evocation_physical_attack(
					evocation,
					controller_id,
					activation_strength,
					context
				):
					return false

			return false

		"move":
			var move_index: int = int(
				resolution.get(
					"move_index",
					0
				)
			)

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
				if _perform_evocation_physical_attack(
					evocation,
					controller_id,
					activation_strength,
					context
				):
					return false

			return false

		"done":
			context["last_activated_evocation"] = evocation
			context["last_evocation_activation_controller"] = controller_id
			context["last_evocation_activation_strength"] = activation_strength
			context["last_evocation_activation_strength_bonus"] = strength_bonus

			print(
				"Evocation activated: ",
				evocation.evocation_name,
				" | controller P",
				controller_id + 1,
				" | Strength ",
				activation_strength
			)

			return true

		_:
			return true


func _handle_resolution_completion(frame: Dictionary):
	match str(frame.get("on_complete", "")):
		"advance_action_phase":
			advance_action_phase()
		"continue_action_activation":
			_request_stepwise_action_activation()
		"advance_evocation_phase":
			advance_evocation_phase()
		"continue_black_rose_event":
			_continue_black_rose_after_event(frame.get("context", {}))
		"continue_black_rose_quests":
			black_rose_quest_step = 4
			black_rose_quest_cursor = 0
			advance_black_rose_quest_steps()
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
		var evocation_data: Array = []
		for i in range(player.evocations.size()):
			var evocation: EvocationState = player.evocations[i]
			if evocation == null or evocation.is_defeated() or evocation_phase_activated.has(evocation):
				continue
			var controller_id: int = get_evocation_controller_id(evocation)
			evocation_data.append({
				"evocation_index": i,
				"id": evocation.evocation_id,
				"name": evocation.get_display_name(),
				"room_id": evocation.room_id,
				"speed": evocation.speed,
				"strength": evocation.strength,
				"controller_id": controller_id,
				"activation_plans": _beta_evocation_activation_plans(evocation, controller_id)
			})

		if evocation_data.is_empty():
			evocation_phase_cursor += 1
			continue

		# Rebuild legal plans after the previous activation and all its triggers.
		return request_player_input({
			"type": "evocation_phase_activations",
			"phase": PHASE_EVOCATION,
			"player_index": player_index,
			"evocations": evocation_data,
			"required_count": 1,
			"remaining_count": evocation_data.size()
		})

	return finish_evocation_phase()


func submit_evocation_phase_activations(
	player_index: int,
	choices: Array
) -> bool:
	if current_phase != PHASE_EVOCATION or not waiting_for_player_input:
		return false
	if str(pending_input.get("type", "")) != "evocation_phase_activations":
		return false
	if player_index != int(pending_input.get("player_index", -1)):
		return false
	if choices.size() != 1 or not choices[0] is Dictionary:
		return false

	var player = players[player_index]
	var choice: Dictionary = choices[0]
	var index: int = int(choice.get("evocation_index", -1))
	if index < 0 or index >= player.evocations.size():
		return false
	var evocation: EvocationState = player.evocations[index]
	if evocation == null or evocation.is_defeated() or evocation_phase_activated.has(evocation):
		return false
	var controller_id: int = get_evocation_controller_id(evocation)
	var activation_context: Dictionary = choice.get("context", {}).duplicate(true)
	if not _validate_evocation_activation_context(evocation, controller_id, activation_context):
		return false

	# Track the physical instance: removals may shift player.evocations indices.
	evocation_phase_activated.append(evocation)
	activation_context["game"] = self
	activation_context["play_order"] = current_phase_play_order.duplicate()
	clear_player_input()
	return queue_resolution({
		"type": "evocation_phase_player",
		"evocation": evocation,
		"controller_id": controller_id,
		"context": activation_context,
		"on_complete": "advance_evocation_phase"
	})


func process_evocation_phase_player_resolution(
	resolution: Dictionary
) -> bool:
	if bool(resolution.get("started", false)):
		return true
	resolution["started"] = true
	activate_evocation(
		resolution.get("evocation", null),
		int(resolution.get("controller_id", -1)),
		resolution.get("context", {})
	)
	# The child activation (including nested decisions) finishes before this
	# frame completes and requests the next choice for the same player.
	return false


func finish_evocation_phase() -> bool:
	if current_phase != PHASE_EVOCATION or waiting_for_player_input:
		return false

	evocation_phase_cursor = 0
	evocation_phase_activated.clear()
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
	# cards go to Memories. Ongoing revealed Effects are also tracked in
	# active_spells so TriggeredSpellManager can see them.
	var active_cards: Array[SpellCardState] = []

	for i in range(player.active_spells.size()):
		var active_spell: ActiveSpellState = player.active_spells[i]
		if active_spell == null:
			continue
		if not active_spell.active:
			continue

		if active_spell.spell != null 		and not active_cards.has(active_spell.spell):
			active_cards.append(active_spell.spell)

		var spell_type: String = active_spell.get_spell_type()
		var can_return_to_hand: bool = (
			spell_type == "trap"
			or spell_type == "protection"
		)

		if can_return_to_hand 		and return_active_indices.has(i):
			player.add_spell_to_hand(active_spell.spell)
		else:
			move_spell_to_memories_or_remove(
				player_index,
				active_spell.spell
			)

	player.active_spells.clear()

	# All remaining prepared cards on the Mage Sheet go to Memories.
	for ready in player.ready_spells:
		if ready != null and ready.spell != null:
			move_spell_to_memories_or_remove(
				player_index,
				ready.spell
			)
	player.ready_spells.clear()

	if player.quick_spell != null and player.quick_spell.spell != null:
		move_spell_to_memories_or_remove(
			player_index,
			player.quick_spell.spell
		)
	player.quick_spell = null

	# Revealed Spells also leave the Mage Sheet for Memories. Ongoing cards
	# already moved above must not be added twice.
	for revealed in player.revealed_spells:
		if revealed == null or revealed.spell == null:
			continue

		if active_cards.has(revealed.spell):
			continue

		move_spell_to_memories_or_remove(
			player_index,
			revealed.spell
		)

	player.revealed_spells.clear()
	_clear_player_board_spell_slots(player_index)

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


# Rulebook pp. 28/32: tied contribution levels share a reduced reward.
func ranked_power_rewards(counts: Dictionary, sole_contributor_bonus: bool = false) -> Dictionary:
	var groups: Dictionary = {}
	for owner in counts:
		var count: int = int(counts[owner])
		if count <= 0:
			continue
		if not groups.has(count):
			groups[count] = []
		groups[count].append(owner)
	var levels: Array = groups.keys()
	levels.sort()
	levels.reverse()
	var rewards: Dictionary = {}
	var rank: int = 0
	for count in levels:
		var owners: Array = groups[count]
		var points: int = [4, 2, 1][mini(rank, 2)]
		if sole_contributor_bonus and levels.size() == 1 and owners.size() == 1:
			points = 5
		elif owners.size() > 1 and points > 1:
			points -= 1
		for owner in owners:
			rewards[owner] = points
		rank += 1
	return rewards


func check_end_game() -> bool:
	if game_has_ended:
		return true
	var threshold: int = int($PowerBoard.end_game_threshold)
	var reached: bool = black_rose_power >= threshold
	for player in players:
		reached = reached or player.power >= threshold
	if not reached:
		return false
	game_has_ended = true
	game_flow_active = false
	var quest_counts: Dictionary = {}
	var trophy_counts: Dictionary = {-1: black_rose_trophies.size()}
	for player in players:
		quest_counts[player.player_index] = player.completed_quests.filter(func(quest): return quest.is_solved()).size()
		trophy_counts[player.player_index] = player.trophies.size()
	var quest_rewards: Dictionary = ranked_power_rewards(quest_counts)
	var trophy_rewards: Dictionary = ranked_power_rewards(trophy_counts)
	var scores: Array = []
	for owner in range(-1, players.size()):
		var base: int = black_rose_power if owner == -1 else players[owner].power
		var quest_bonus: int = int(quest_rewards.get(owner, 0))
		var trophy_bonus: int = int(trophy_rewards.get(owner, 0))
		var crown_bonus: int = 1 if owner >= 0 and owner == crown_owner_id else 0
		var total: int = base + quest_bonus + trophy_bonus + crown_bonus
		scores.append({"player_index": owner, "name": "Black Rose" if owner == -1 else "Player " + str(owner + 1), "base": base, "quests": quest_bonus, "trophies": trophy_bonus, "crown": crown_bonus, "total": total})
		# Final bonuses do not open gameplay trigger windows.
		if owner == -1:
			set_black_rose_power(total)
		else:
			set_player_power(owner, total)
	scores.sort_custom(func(a, b): return a.total > b.total)
	var contenders: Array = scores.filter(func(row): return row.total == scores[0].total)
	for counts in [quest_counts, trophy_counts]:
		var best: int = 0
		for row in contenders:
			best = maxi(best, int(counts.get(row.player_index, 0)))
		contenders = contenders.filter(func(row): return int(counts.get(row.player_index, 0)) == best)
	final_result = {"round": current_round, "scores": scores, "winner": -999}
	if contenders.size() > 1:
		request_player_input({"type": "final_winner_choice", "phase": current_phase, "player_index": crown_owner_id if crown_owner_id >= 0 else get_play_order()[0], "contenders": contenders})
	else:
		final_result["winner"] = contenders[0].player_index
		game_over.emit(final_result)
	return true


func submit_final_winner_choice(player_index: int, winner: int) -> bool:
	if pending_input.get("type", "") != "final_winner_choice" or int(pending_input.get("player_index", -1)) != player_index:
		return false
	for row in pending_input.get("contenders", []):
		if int(row.player_index) == winner:
			clear_player_input()
			final_result["winner"] = winner
			game_over.emit(final_result)
			return true
	return false


# =============================================================================
# BETA INTERACTION BRIDGE
# =============================================================================
#
# The UI should not call a different submit_* method for every Phase.
# These helpers expose a serializable view of the current game and route the
# current pending decision through one stable entry point.


func _beta_spell_public_data(
	spell: SpellCardState
) -> Dictionary:
	if spell == null:
		return {}

	return {
		"id": spell.id,
		"name": spell.card_name,
		"school_id": spell.school_id
	}


func _beta_ready_spell_data(
	ready: ReadySpellState
) -> Dictionary:
	if ready == null or ready.spell == null:
		return {}

	var result: Dictionary = _beta_spell_public_data(
		ready.spell
	)
	result["use_dark_side"] = ready.use_dark_side
	return result


func _beta_revealed_spell_data(
	revealed: RevealedSpellState
) -> Dictionary:
	if revealed == null or revealed.spell == null:
		return {}

	var result: Dictionary = _beta_spell_public_data(
		revealed.spell
	)
	result["use_dark_side"] = revealed.use_dark_side
	return result


func _beta_quest_data(
	quest: QuestState,
	reveal_private_data: bool
) -> Dictionary:
	if quest == null:
		return {}

	var visible: bool = (
		reveal_private_data
		or quest.revealed
		or quest.completed
		or quest.solved
	)

	var result: Dictionary = {
		"revealed": quest.revealed,
		"completed": quest.completed,
		"solved": quest.solved
	}

	if not visible:
		return result

	result["id"] = quest.get_id()
	result["name"] = quest.get_name()
	result["moon"] = quest.get_moon()
	result["progress"] = quest.progress
	result["cube_slots"] = quest.get_cube_slots()
	result["power_reward"] = quest.get_power_reward()

	return result


func _beta_evocation_data(
	evocation: EvocationState
) -> Dictionary:
	if evocation == null:
		return {}

	return {
		"id": evocation.evocation_id,
		"name": evocation.get_display_name(),
		"archetype": evocation.archetype,
		"owner_id": evocation.owner_id,
		"controller_id": evocation.controller_id,
		"health": evocation.health,
		"damage": evocation.get_damage(),
		"strength": evocation.strength,
		"speed": evocation.speed,
		"room_id": evocation.room_id,
		"defeated": evocation.is_defeated()
	}


func _beta_player_state(
	player_index: int,
	viewer_player_index: int
) -> Dictionary:
	if player_index < 0 or player_index >= players.size():
		return {}

	var player: PlayerState = players[player_index]
	var is_owner_view: bool = viewer_player_index == player_index
	var mage = player.mage

	var result: Dictionary = {
		"player_index": player_index,
		"name": player.player_name,
		"color": player.color.to_html(),
		"power": player.power,
		"school_id": player.school_id,
		"starting_grimoire_id": player.starting_grimoire_id,
		"starting_grimoire_name": player.starting_grimoire_name,
		"mage_id": player.mage_id,
		"available_cubes": player.available_cubes,
		"available_physical_actions": player.available_physical_actions,
		"hand_count": player.hand.size(),
		"grimoire_count": player.grimoire.size(),
		"memories_count": player.memories.size(),
		"ready_spell_count": player.ready_spells.size(),
		"has_quick_spell": player.quick_spell != null,
		"active_spell_count": player.active_spells.size(),
		"revealed_spell_count": player.revealed_spells.size(),
		"active_quest_count": player.active_quests.size(),
		"completed_quest_count": player.completed_quests.size()
	}

	if mage != null:
		result["mage"] = {
			"health": mage.health,
			"damage": mage.get_damage(),
			"remaining_health": mage.get_remaining_health(),
			"strength": mage.strength,
			"speed": mage.speed,
			"in_cell": mage.in_cell,
			"room_id": mage.room_id,
			"room_coord": {
				"q": mage.room_coord.x,
				"r": mage.room_coord.y
			},
			"damage_cubes": mage.damage_cubes.duplicate()
		}

	var evocations: Array = []
	for evocation in player.evocations:
		evocations.append(
			_beta_evocation_data(evocation)
		)
	result["evocations"] = evocations

	var public_revealed: Array = []
	for revealed in player.revealed_spells:
		var revealed_data: Dictionary = _beta_revealed_spell_data(
			revealed
		)
		if not revealed_data.is_empty():
			public_revealed.append(revealed_data)
	result["revealed_spells"] = public_revealed

	var active_quests: Array = []
	for quest in player.active_quests:
		active_quests.append(
			_beta_quest_data(
				quest,
				is_owner_view
			)
		)
	result["active_quests"] = active_quests

	var completed_quests: Array = []
	for quest in player.completed_quests:
		completed_quests.append(
			_beta_quest_data(
				quest,
				true
			)
		)
	result["completed_quests"] = completed_quests

	# Hidden information is exposed only to the player who owns it.
	if is_owner_view:
		var hand_data: Array = []
		for spell in player.hand:
			hand_data.append(
				_beta_spell_public_data(spell)
			)
		result["hand"] = hand_data

		var ready_data: Array = []
		for ready in player.ready_spells:
			ready_data.append(
				_beta_ready_spell_data(ready)
			)
		result["ready_spells"] = ready_data

		result["quick_spell"] = (
			_beta_ready_spell_data(player.quick_spell)
			if player.quick_spell != null
			else {}
		)

		var active_data: Array = []
		for active_spell in player.active_spells:
			if active_spell == null \
			or active_spell.spell == null \
			or not active_spell.active:
				continue

			var spell_data: Dictionary = _beta_spell_public_data(
				active_spell.spell
			)
			spell_data["spell_type"] = active_spell.get_spell_type()
			spell_data["use_dark_side"] = active_spell.use_dark_side
			active_data.append(spell_data)

		result["active_spells"] = active_data

	return result


func get_beta_pending_input(
	viewer_player_index: int = -1
) -> Dictionary:
	if not waiting_for_player_input:
		return {}

	var owner_id: int = int(
		pending_input.get("player_index", -1)
	)

	# The player who must answer receives the complete request.
	if viewer_player_index == owner_id:
		return pending_input.duplicate(true)

	# Everyone else sees only public turn/phase information. In particular,
	# Preparation and Study Hand information never leaks to another player.
	return {
		"type": str(pending_input.get("type", "")),
		"phase": str(pending_input.get("phase", current_phase)),
		"player_index": owner_id,
		"private": true
	}


func get_beta_game_state(
	viewer_player_index: int = -1
) -> Dictionary:
	var player_states: Array = []

	for player_index in range(players.size()):
		player_states.append(
			_beta_player_state(
				player_index,
				viewer_player_index
			)
		)

	return {
		"round": current_round,
		"moon": current_moon,
		"phase": current_phase,
		"setup_stage": starting_setup_stage,
		"game_flow_active": game_flow_active,
		"game_has_ended": game_has_ended,
		"final_result": final_result,
		"black_rose_power": black_rose_power,
		"crown_owner_id": crown_owner_id,
		"player_count": player_count,
		"players": player_states,
		"waiting_for_player_input": waiting_for_player_input,
		"pending_input": get_beta_pending_input(
			viewer_player_index
		)
	}



func _beta_room_public_data(
	room_id: String
) -> Dictionary:
	var room = get_room_by_id(room_id)
	if room == null:
		return {}

	return {
		"id": room_id,
		"name": str(room.room_name),
		"coord": {
			"q": room_id_to_coord(room_id).x,
			"r": room_id_to_coord(room_id).y
		},
		"can_activate": bool(room.can_activate(false))
	}


func _beta_adjacent_room_ids(
	room_id: String
) -> Array[String]:
	var result: Array[String] = []

	if not is_lodge_room_id(room_id):
		return result

	var origin: Vector2i = room_id_to_coord(room_id)
	if origin == Vector2i(9999, 9999):
		return result

	for room_value in room_id_by_coord.values():
		var candidate_id: String = str(room_value)

		if candidate_id == room_id:
			continue

		var candidate_coord: Vector2i = room_id_to_coord(
			candidate_id
		)

		if candidate_coord == Vector2i(9999, 9999):
			continue

		if get_hex_distance(
			origin,
			candidate_coord
		) == 1:
			result.append(candidate_id)

	result.sort()
	return result


func _beta_explore_paths(
	player_index: int
) -> Array:
	var result: Array = []

	if player_index < 0 or player_index >= players.size():
		return result

	var player = players[player_index]
	var mage = player.mage

	if mage == null or mage.speed <= 0:
		return result

	var frontier: Array = []

	if mage.in_cell:
		var exit_room_ids: Array[String] = (
			get_player_cell_exit_room_ids(
				player_index
			)
		)

		if exit_room_ids.is_empty():
			return result

		for exit_room_id in exit_room_ids:
			var first_path: Array = [
				exit_room_id
			]

			result.append(
				first_path.duplicate()
			)

			frontier.append({
				"room_id": exit_room_id,
				"path": first_path,
				"moves_used": 1
			})
	else:
		# Physical Actions may ignore some or all of their Effects, so an
		# Explore with no movement is legal.
		result.append([])

		frontier.append({
			"room_id": mage.room_id,
			"path": [],
			"moves_used": 0
		})

	while not frontier.is_empty():
		var node: Dictionary = frontier.pop_front()

		var moves_used: int = int(
			node.get("moves_used", 0)
		)

		if moves_used >= mage.speed:
			continue

		var current_room_id: String = str(
			node.get("room_id", "")
		)

		for next_room_id in _beta_adjacent_room_ids(
			current_room_id
		):
			var next_path: Array = (
				node.get("path", []).duplicate()
			)

			next_path.append(next_room_id)
			result.append(next_path)

			frontier.append({
				"room_id": next_room_id,
				"path": next_path,
				"moves_used": moves_used + 1
			})

	return result

func _beta_explore_action_variants(
	player_index: int
) -> Array:
	var result: Array = []

	if player_index < 0 or player_index >= players.size():
		return result

	var player = players[player_index]
	if not player.has_physical_action():
		return result

	var mage = player.mage
	if mage == null:
		return result

	for path_value in _beta_explore_paths(player_index):
		var path: Array = path_value

		var final_room_id: String = (
			str(path[path.size() - 1])
			if not path.is_empty()
			else mage.room_id
		)

		# Base Explore: movement only, or intentionally ignore all Effects.
		result.append({
			"kind": "explore",
			"label": "Explore",
			"action": {
				"type": "explore",
				"destination_room_ids": path.duplicate(),
				"activate_room_before_movement": false,
				"activate_room_after_movement": false
			},
			"path": path.duplicate(),
			"final_room_id": final_room_id,
			"room_activation_timing": "none"
		})

		# A Mage in their Cell cannot activate the Room before moving.
		if not mage.in_cell:
			var start_room = get_room_by_id(mage.room_id)

			if start_room != null \
			and start_room.can_activate(false):
				result.append({
					"kind": "explore",
					"label": "Explore + activate Room before movement",
					"action": {
						"type": "explore",
						"destination_room_ids": path.duplicate(),
						"activate_room_before_movement": true,
						"activate_room_after_movement": false
					},
					"path": path.duplicate(),
					"final_room_id": final_room_id,
					"room_activation_timing": "before"
				})

		var final_room = get_room_by_id(final_room_id)

		if final_room != null \
		and final_room.can_activate(false):
			# For a zero-move Explore this is the same physical Room as the
			# "before" option. Keep only one activation variant.
			if mage.in_cell or not path.is_empty():
				result.append({
					"kind": "explore",
					"label": "Explore + activate Room after movement",
					"action": {
						"type": "explore",
						"destination_room_ids": path.duplicate(),
						"activate_room_before_movement": false,
						"activate_room_after_movement": true
					},
					"path": path.duplicate(),
					"final_room_id": final_room_id,
					"room_activation_timing": "after"
				})

	return result


func _beta_fight_action_variants(
	player_index: int
) -> Array:
	var result: Array = []

	if player_index < 0 or player_index >= players.size():
		return result

	var player = players[player_index]
	var mage = player.mage

	if mage == null \
	or mage.in_cell \
	or not player.has_physical_action():
		return result

	var room = get_room_by_id(mage.room_id)
	var can_activate_room: bool = (
		room != null
		and room.can_activate(false)
	)

	var targets: Array = []

	for target_index in range(players.size()):
		if target_index == player_index:
			continue

		var target_mage = players[target_index].mage

		if target_mage == null \
		or target_mage.in_cell \
		or target_mage.room_id != mage.room_id:
			continue

		targets.append({
			"target_model_type": "mage",
			"target_player_index": target_index,
			"target_evocation_owner_id": -1,
			"target_evocation_index": -1,
			"name": players[target_index].player_name
		})

	for owner_id in range(players.size()):
		for evocation_index in range(
			players[owner_id].evocations.size()
		):
			var evocation: EvocationState = (
				players[owner_id].evocations[
					evocation_index
				]
			)

			if not _valid_mage_physical_attack_evocation(
				player_index,
				evocation
			):
				continue

			targets.append({
				"target_model_type": "evocation",
				"target_player_index": -1,
				"target_evocation_owner_id": owner_id,
				"target_evocation_index": evocation_index,
				"name": evocation.get_display_name(),
				"controller_id": get_evocation_controller_id(
					evocation
				),
				"evocation": _beta_evocation_data(evocation)
			})

	# A Physical Action may ignore some or all of its Effects.
	result.append({
		"kind": "fight",
		"label": "Fight",
		"action": {
			"type": "fight",
			"target_model_type": "",
			"target_player_index": -1,
			"target_evocation_owner_id": -1,
			"target_evocation_index": -1,
			"activate_room_first": false,
			"perform_attack": false,
			"perform_room_activation": false
		},
		"target_model_type": "",
		"room_activation_timing": "none"
	})

	if can_activate_room:
		result.append({
			"kind": "fight",
			"label": "Fight: activate Room",
			"action": {
				"type": "fight",
				"target_model_type": "",
				"target_player_index": -1,
				"target_evocation_owner_id": -1,
				"target_evocation_index": -1,
				"activate_room_first": false,
				"perform_attack": false,
				"perform_room_activation": true
			},
			"target_model_type": "",
			"room_activation_timing": "after"
		})

	for target_value in targets:
		var target: Dictionary = target_value
		var target_name: String = str(
			target.get("name", "Model")
		)

		var target_fields: Dictionary = {
			"target_model_type": str(
				target.get(
					"target_model_type",
					""
				)
			),
			"target_player_index": int(
				target.get(
					"target_player_index",
					-1
				)
			),
			"target_evocation_owner_id": int(
				target.get(
					"target_evocation_owner_id",
					-1
				)
			),
			"target_evocation_index": int(
				target.get(
					"target_evocation_index",
					-1
				)
			)
		}

		var attack_action: Dictionary = {
			"type": "fight",
			"activate_room_first": false,
			"perform_attack": true,
			"perform_room_activation": false
		}

		for key in target_fields:
			attack_action[key] = target_fields[key]

		result.append({
			"kind": "fight",
			"label": "Fight: attack " + target_name,
			"action": attack_action,
			"target": target.duplicate(true),
			"room_activation_timing": "none"
		})

		if can_activate_room:
			var before_action: Dictionary = attack_action.duplicate(true)
			before_action["activate_room_first"] = true
			before_action["perform_room_activation"] = true

			result.append({
				"kind": "fight",
				"label":
					"Fight: activate Room, then attack "
					+ target_name,
				"action": before_action,
				"target": target.duplicate(true),
				"room_activation_timing": "before"
			})

			var after_action: Dictionary = attack_action.duplicate(true)
			after_action["activate_room_first"] = false
			after_action["perform_room_activation"] = true

			result.append({
				"kind": "fight",
				"label":
					"Fight: attack "
					+ target_name
					+ ", then activate Room",
				"action": after_action,
				"target": target.duplicate(true),
				"room_activation_timing": "after"
			})

	return result



func _beta_evocation_movement_paths(
	evocation: EvocationState,
	speed_bonus: int = 0
) -> Array:
	var result: Array = []

	if evocation == null \
	or evocation.is_defeated() \
	or not is_evocation_in_play(evocation):
		return result

	# Using none of the Move 1 Effects is legal.
	result.append([])

	var frontier: Array = [{
		"room_id": evocation.room_id,
		"path": [],
		"moves_used": 0
	}]

	while not frontier.is_empty():
		var node: Dictionary = frontier.pop_front()
		var moves_used: int = int(
			node.get("moves_used", 0)
		)

		if moves_used >= evocation.speed + speed_bonus:
			continue

		var current_room_id: String = str(
			node.get("room_id", "")
		)

		for next_room_id in _beta_adjacent_room_ids(
			current_room_id
		):
			var next_path: Array = (
				node.get("path", []).duplicate()
			)

			next_path.append(next_room_id)
			result.append(next_path)

			frontier.append({
				"room_id": next_room_id,
				"path": next_path,
				"moves_used": moves_used + 1
			})

	return result


func _valid_evocation_attack_mage(
	evocation: EvocationState,
	controller_id: int,
	target_player_index: int,
	expected_room_id: String = ""
) -> bool:
	if evocation == null \
	or evocation.is_defeated() \
	or not is_evocation_in_play(evocation):
		return false

	if target_player_index < 0 \
	or target_player_index >= players.size():
		return false

	if target_player_index == controller_id:
		return false

	var target_mage = players[target_player_index].mage

	if target_mage == null or target_mage.in_cell:
		return false

	var room_id: String = (
		expected_room_id
		if expected_room_id != ""
		else evocation.room_id
	)

	return target_mage.room_id == room_id


func _valid_evocation_attack_evocation(
	evocation: EvocationState,
	controller_id: int,
	target_evocation: EvocationState,
	expected_room_id: String = ""
) -> bool:
	if evocation == null \
	or target_evocation == null \
	or evocation == target_evocation:
		return false

	if evocation.is_defeated() \
	or target_evocation.is_defeated():
		return false

	if not is_evocation_in_play(evocation) \
	or not is_evocation_in_play(target_evocation):
		return false

	# An Evocation never inflicts Damage on another Evocation controlled by
	# the Mage that controls the attacker.
	if get_evocation_controller_id(
		target_evocation
	) == controller_id:
		return false

	var room_id: String = (
		expected_room_id
		if expected_room_id != ""
		else evocation.room_id
	)

	return target_evocation.room_id == room_id


func _beta_evocation_attack_targets(
	evocation: EvocationState,
	controller_id: int,
	room_id: String
) -> Array:
	var result: Array = []

	for target_player_index in range(players.size()):
		if not _valid_evocation_attack_mage(
			evocation,
			controller_id,
			target_player_index,
			room_id
		):
			continue

		result.append({
			"target_model_type": "mage",
			"target_player_index": target_player_index,
			"target_evocation_owner_id": -1,
			"target_evocation_index": -1,
			"name": players[target_player_index].player_name,
			"room_id": room_id
		})

	for owner_id in range(players.size()):
		for evocation_index in range(
			players[owner_id].evocations.size()
		):
			var target_evocation: EvocationState = (
				players[owner_id].evocations[
					evocation_index
				]
			)

			if not _valid_evocation_attack_evocation(
				evocation,
				controller_id,
				target_evocation,
				room_id
			):
				continue

			result.append({
				"target_model_type": "evocation",
				"target_player_index": -1,
				"target_evocation_owner_id": owner_id,
				"target_evocation_index": evocation_index,
				"name": target_evocation.get_display_name(),
				"room_id": room_id,
				"controller_id": get_evocation_controller_id(
					target_evocation
				),
				"evocation": _beta_evocation_data(
					target_evocation
				)
			})

	return result


func _evocation_target_context(
	target: Dictionary
) -> Dictionary:
	return {
		"evocation_target_model_type": str(
			target.get("target_model_type", "")
		),
		"evocation_target_player_index": int(
			target.get("target_player_index", -1)
		),
		"evocation_target_evocation_owner_id": int(
			target.get(
				"target_evocation_owner_id",
				-1
			)
		),
		"evocation_target_evocation_index": int(
			target.get(
				"target_evocation_index",
				-1
			)
		)
	}


func _beta_evocation_activation_plans(
	evocation: EvocationState,
	controller_id: int,
	speed_bonus: int = 0
) -> Array:
	var result: Array = []

	if evocation == null \
	or evocation.is_defeated() \
	or not is_evocation_in_play(evocation):
		return result

	var origin_room_id: String = evocation.room_id

	for path_value in _beta_evocation_movement_paths(
		evocation, speed_bonus
	):
		var path: Array = path_value

		var final_room_id: String = (
			str(path[path.size() - 1])
			if not path.is_empty()
			else origin_room_id
		)

		# Move only / do nothing.
		result.append({
			"label": (
				"Activate " + evocation.get_display_name()
				if path.is_empty()
				else "Move " + evocation.get_display_name()
			),
			"context": {
				"evocation_attack_timing": "none",
				"evocation_move_room_ids": path.duplicate()
			},
			"path": path.duplicate(),
			"attack_timing": "none",
			"target": {}
		})

		# Physical Attack before all Move 1 Effects.
		for target_value in _beta_evocation_attack_targets(
			evocation,
			controller_id,
			origin_room_id
		):
			var target: Dictionary = target_value
			var before_context: Dictionary = {
				"evocation_attack_timing": "before",
				"evocation_move_room_ids": path.duplicate()
			}

			var target_context: Dictionary = _evocation_target_context(
				target
			)

			for key in target_context:
				before_context[key] = target_context[key]

			result.append({
				"label":
					"Attack "
					+ str(target.get("name", "Model"))
					+ (
						" then move"
						if not path.is_empty()
						else ""
					),
				"context": before_context,
				"path": path.duplicate(),
				"attack_timing": "before",
				"target": target.duplicate(true)
			})

		# With no movement, "before" and "after" are mechanically identical.
		if path.is_empty():
			continue

		# Physical Attack after all Move 1 Effects.
		for target_value in _beta_evocation_attack_targets(
			evocation,
			controller_id,
			final_room_id
		):
			var target: Dictionary = target_value
			var after_context: Dictionary = {
				"evocation_attack_timing": "after",
				"evocation_move_room_ids": path.duplicate()
			}

			var target_context: Dictionary = _evocation_target_context(
				target
			)

			for key in target_context:
				after_context[key] = target_context[key]

			result.append({
				"label":
					"Move then attack "
					+ str(target.get("name", "Model")),
				"context": after_context,
				"path": path.duplicate(),
				"attack_timing": "after",
				"target": target.duplicate(true)
			})

	return result


func _resolve_evocation_target_from_context(
	context: Dictionary
) -> EvocationState:
	if str(
		context.get(
			"evocation_target_model_type",
			""
		)
	) != "evocation":
		return null

	return get_evocation_by_owner_index(
		int(
			context.get(
				"evocation_target_evocation_owner_id",
				-1
			)
		),
		int(
			context.get(
				"evocation_target_evocation_index",
				-1
			)
		)
	)


func _validate_evocation_activation_context(
	evocation: EvocationState,
	controller_id: int,
	context: Dictionary
) -> bool:
	if evocation == null \
	or evocation.is_defeated() \
	or not is_evocation_in_play(evocation):
		return false

	var attack_timing: String = str(
		context.get(
			"evocation_attack_timing",
			"none"
		)
	)

	if attack_timing != "none" \
	and attack_timing != "before" \
	and attack_timing != "after":
		return false

	var move_room_ids: Array = context.get(
		"evocation_move_room_ids",
		[]
	)

	if move_room_ids.size() > evocation.speed + int(context.get("evocation_activation_speed_bonus", 0)):
		return false

	var previous_room_id: String = evocation.room_id

	for room_value in move_room_ids:
		var room_id: String = str(room_value)

		if not _beta_adjacent_room_ids(
			previous_room_id
		).has(room_id):
			return false

		previous_room_id = room_id

	if attack_timing == "none":
		return true

	var attack_room_id: String = (
		evocation.room_id
		if attack_timing == "before"
		else previous_room_id
	)

	var target_model_type: String = str(
		context.get(
			"evocation_target_model_type",
			""
		)
	)

	if target_model_type == "mage":
		return _valid_evocation_attack_mage(
			evocation,
			controller_id,
			int(
				context.get(
					"evocation_target_player_index",
					-1
				)
			),
			attack_room_id
		)

	if target_model_type == "evocation":
		return _valid_evocation_attack_evocation(
			evocation,
			controller_id,
			_resolve_evocation_target_from_context(
				context
			),
			attack_room_id
		)

	return false


func _perform_evocation_physical_attack(
	evocation: EvocationState,
	controller_id: int,
	activation_strength: int,
	context: Dictionary
) -> bool:
	var target_model_type: String = str(
		context.get(
			"evocation_target_model_type",
			""
		)
	)

	if target_model_type == "mage":
		var target_player_index: int = int(
			context.get(
				"evocation_target_player_index",
				-1
			)
		)

		if not _valid_evocation_attack_mage(
			evocation,
			controller_id,
			target_player_index
		):
			return false

		deal_damage_from_evocation(
			evocation,
			target_player_index,
			activation_strength
		)

		return true

	if target_model_type == "evocation":
		var target_evocation: EvocationState = (
			_resolve_evocation_target_from_context(
				context
			)
		)

		if not _valid_evocation_attack_evocation(
			evocation,
			controller_id,
			target_evocation
		):
			return false

		deal_damage_to_evocation(
			controller_id,
			target_evocation,
			activation_strength,
			[],
			"evocation_attack",
			"evocation",
			evocation
		)

		return true

	return false

func _beta_command_action_variants(
	player_index: int
) -> Array:
	var result: Array = []

	if player_index < 0 or player_index >= players.size():
		return result

	var player = players[player_index]

	if player.mage == null \
	or player.mage.in_cell \
	or not player.has_physical_action():
		return result

	for evocation_index in range(player.evocations.size()):
		var evocation: EvocationState = player.evocations[
			evocation_index
		]

		if evocation == null \
		or evocation.is_defeated() \
		or not is_evocation_in_play(evocation):
			continue

		var controller_id: int = get_evocation_controller_id(
			evocation
		)

		for plan_value in _beta_evocation_activation_plans(
			evocation,
			controller_id
		):
			var plan: Dictionary = plan_value

			result.append({
				"kind": "command",
				"label":
					"Command "
					+ evocation.evocation_name
					+ ": "
					+ str(plan.get("label", "Activate")),
				"action": {
					"type": "command",
					"evocation_index": evocation_index,
					"context": plan.get(
						"context",
						{}
					).duplicate(true)
				},
				"evocation_index": evocation_index,
				"controller_id": controller_id,
				"evocation": _beta_evocation_data(evocation),
				"activation_plan": plan.duplicate(true)
			})

	return result


func _beta_public_target_options(
	options: Array
) -> Array:
	var result: Array = []

	for option_value in options:
		if not option_value is Dictionary:
			continue

		var option: Dictionary = option_value
		var public_option: Dictionary = {}

		for key in option:
			if str(key) == "value":
				continue
			public_option[key] = option[key]

		result.append(public_option)

	return result


func _beta_spell_cast_descriptor(
	player_index: int,
	ready: ReadySpellState,
	source: String
) -> Dictionary:
	if ready == null or ready.spell == null:
		return {}

	var side: Dictionary = ready.spell.get_side(
		ready.use_dark_side
	)

	var targeting_side: Dictionary = _spell_effective_target_side(
		player_index,
		side, ready.spell
	)

	var spell_type: String = str(
		side.get("type", "")
	)

	var target_type: String = str(
		targeting_side.get("target", "")
	)

	var target_options: Array = []

	if spell_type == "combat" \
	or spell_type == "contingency":
		if target_type != "" \
		and target_type != "self" \
		and target_type != "special":
			# Range 0 Room target is automatically the caster's current Room.
			if not (
				(target_type == "room" or target_type == "area")
				and str(targeting_side.get("range", "")) == "0"
			):
				target_options = _beta_public_target_options(
					_spell_primary_target_options(
						player_index,
						targeting_side
					)
				)

				# A primary target is mandatory for this cast. Do not expose
				# a Cast action the engine cannot legally target.
				if target_options.is_empty():
					return {}

	var action_type: String = (
		"quick"
		if source == "quick"
		else "spell"
	)

	return {
		"kind": "cast",
		"label": "Cast " + ready.spell.card_name,
		"action": {
			"type": action_type
		},
		"source": source,
		"spell": _beta_ready_spell_data(ready),
		"spell_type": spell_type,
		"element": str(side.get("element", "")),
		"target_type": target_type,
		"range": targeting_side.get("range", null),
		"target_options": target_options,
		"target_selection_follows": not target_options.is_empty()
	}


func _beta_cast_action_variants(
	player_index: int
) -> Array:
	var result: Array = []

	if player_index < 0 or player_index >= players.size():
		return result

	var player = players[player_index]

	if player.mage == null or player.mage.in_cell:
		return result

	# Only the lowest numbered prepared Slot may currently be cast.
	if not player.ready_spells.is_empty():
		var ready_descriptor: Dictionary = _beta_spell_cast_descriptor(
			player_index,
			player.ready_spells[0],
			"ready"
		)

		if not ready_descriptor.is_empty():
			result.append(ready_descriptor)

	if player.quick_spell != null:
		var quick_descriptor: Dictionary = _beta_spell_cast_descriptor(
			player_index,
			player.quick_spell,
			"quick"
		)

		if not quick_descriptor.is_empty():
			result.append(quick_descriptor)

	return result


func _beta_momentum_destinations(
	player_index: int
) -> Array[String]:
	var result: Array[String] = []

	if player_index < 0 or player_index >= players.size():
		return result

	var mage = players[player_index].mage
	if mage == null:
		return result

	if mage.in_cell:
		for exit_room_id in get_player_cell_exit_room_ids(
			player_index
		):
			if _is_valid_momentum_destination(
				player_index,
				exit_room_id
			):
				result.append(exit_room_id)

		return result

	# Move 1 is optional outside the Cell.
	result.append("")

	for room_id in _beta_adjacent_room_ids(mage.room_id):
		if _is_valid_momentum_destination(
			player_index,
			room_id
		):
			result.append(room_id)

	return result

func _beta_momentum_action_variants(
	player_index: int
) -> Array:
	var result: Array = []

	if player_index < 0 or player_index >= players.size():
		return result

	var player = players[player_index]
	var destinations: Array[String] = _beta_momentum_destinations(
		player_index
	)

	if destinations.is_empty():
		return result

	for ready_index in range(player.ready_spells.size()):
		var ready: ReadySpellState = player.ready_spells[
			ready_index
		]

		if ready == null or ready.spell == null:
			continue

		for destination_room_id in destinations:
			result.append({
				"kind": "momentum",
				"label": "Momentum: discard " + ready.spell.card_name,
				"action": {
					"type": "momentum",
					"ready_index": ready_index,
					"use_quick": false,
					"destination_room_id": destination_room_id
				},
				"spell": _beta_ready_spell_data(ready),
				"destination_room_id": destination_room_id
			})

	if player.quick_spell != null \
	and player.quick_spell.spell != null:
		for destination_room_id in destinations:
			result.append({
				"kind": "momentum",
				"label":
					"Momentum: discard "
					+ player.quick_spell.spell.card_name,
				"action": {
					"type": "momentum",
					"ready_index": -1,
					"use_quick": true,
					"destination_room_id": destination_room_id
				},
				"spell": _beta_ready_spell_data(
					player.quick_spell
				),
				"destination_room_id": destination_room_id
			})

	return result


func _beta_quest_activation_variants(
	player_index: int
) -> Array:
	var result: Array = []

	if player_index < 0 or player_index >= players.size():
		return result

	var player = players[player_index]

	if player.mage == null or player.mage.in_cell:
		return result

	for quest_data_value in _get_solvable_quest_activation_data(
		player_index
	):
		if not quest_data_value is Dictionary:
			continue

		var quest_data: Dictionary = quest_data_value
		var quest_index: int = int(
			quest_data.get("quest_index", -1)
		)

		result.append({
			"kind": "quest",
			"label": "Resolve Quest " + str(
				quest_data.get("name", "")
			),
			"action": {
				"type": "quest",
				"quest_index": quest_index
			},
			"quest_index": quest_index,
			"id": str(quest_data.get("id", "")),
			"name": str(quest_data.get("name", "")),
			"power_reward": int(
				quest_data.get("power_reward", 0)
			),
			"consumes_action": false
		})

	return result


func get_beta_legal_actions(
	player_index: int
) -> Dictionary:
	if player_index < 0 or player_index >= players.size():
		return {}

	var player = players[player_index]
	var actions: Array = []

	var explore_actions: Array = _beta_explore_action_variants(
		player_index
	)
	var fight_actions: Array = _beta_fight_action_variants(
		player_index
	)
	var command_actions: Array = _beta_command_action_variants(
		player_index
	)
	var cast_actions: Array = _beta_cast_action_variants(
		player_index
	)
	var momentum_actions: Array = _beta_momentum_action_variants(
		player_index
	)

	actions.append_array(explore_actions)
	actions.append_array(fight_actions)
	actions.append_array(command_actions)
	actions.append_array(cast_actions)
	actions.append_array(momentum_actions)

	return {
		"player_index": player_index,
		"phase": current_phase,
		"in_cell": (
			player.mage != null
			and player.mage.in_cell
		),
		"can_act": not actions.is_empty(),
		"min_actions_per_activation": 1,
		"max_actions_per_activation": 2,
		"actions": actions,
		"explore": explore_actions,
		"fight": fight_actions,
		"command": command_actions,
		"cast": cast_actions,
		"momentum": momentum_actions,
		"quests": _beta_quest_activation_variants(
			player_index
		),
		"activation_constraints": {
			"max_numbered_spell_casts": 1,
			"max_quick_spell_casts": 1,
			"completed_quests_consume_actions": false
		}
	}

func get_beta_supported_input_types() -> Array[String]:
	return [
		"final_winner_choice",
		"starting_mage_choice",
		"starting_school_choice",
		"starting_grimoire_choice",
		"effect_choice",
		"action_activation",
		"action_activation_step",
		"preparation",
		"study_choose_schools",
		"study_keep_cards",
		"study_optional_discard",
		"study_hand_limit",
		"trigger_decision",
		"evocation_phase_activations",
		"cleanup_active_spells",
		"black_rose_optional_quest_discard",
		"black_rose_active_quest_limit",
		"black_rose_completed_quest_limit"
	]


func submit_beta_input(
	player_index: int,
	payload: Dictionary
) -> bool:
	if network_session != null:
		return network_session.submit_local(player_index, payload)
	return _submit_beta_input_authoritative(player_index, payload)

func _submit_beta_input_authoritative(player_index: int, payload: Dictionary) -> bool:
	if not waiting_for_player_input:
		print("submit_beta_input: no pending input")
		return false

	if player_index != int(
		pending_input.get("player_index", -1)
	):
		print("submit_beta_input: wrong player")
		return false

	var input_type: String = str(
		pending_input.get("type", "")
	)

	match input_type:
		"final_winner_choice":
			return submit_final_winner_choice(player_index, int(payload.get("winner", -999)))
		"starting_mage_choice":
			return submit_starting_mage_choice(
				player_index,
				str(payload.get("mage_id", ""))
			)

		"starting_school_choice":
			return submit_starting_school_choice(
				player_index,
				str(payload.get("school_id", ""))
			)

		"starting_grimoire_choice":
			return submit_starting_grimoire_choice(
				player_index,
				str(payload.get("grimoire_id", ""))
			)

		"effect_choice":
			return submit_effect_choice(
				player_index,
				payload.get("selection", null)
			)

		"action_activation":
			return submit_action_activation(
				player_index,
				payload.get("actions", [])
			)

		"action_activation_step":
			return submit_action_activation_step(
				player_index,
				str(payload.get("token", ""))
			)

		"preparation":
			return submit_preparation(
				player_index,
				payload.get("ready_hand_indices", []),
				payload.get("ready_dark_sides", []),
				int(payload.get("quick_hand_index", -1)),
				bool(payload.get("quick_dark_side", false))
			)

		"study_choose_schools":
			return submit_study_school_choices(
				player_index,
				payload.get("school_ids", [])
			)

		"study_keep_cards":
			return submit_study_keep_cards(
				player_index,
				payload.get("keep_indices", [])
			)

		"study_optional_discard":
			return submit_study_optional_discard(
				player_index,
				int(payload.get("hand_index", -1))
			)

		"study_hand_limit":
			return submit_study_hand_limit(
				player_index,
				payload.get("hand_indices", [])
			)

		"trigger_decision":
			return submit_trigger_decision(
				player_index,
				int(payload.get("queue_index", -1))
			)

		"evocation_phase_activations":
			return submit_evocation_phase_activations(
				player_index,
				payload.get("choices", [])
			)

		"cleanup_active_spells":
			return submit_cleanup_active_spells(
				player_index,
				payload.get("return_to_hand_indices", [])
			)

		"black_rose_optional_quest_discard":
			return submit_black_rose_optional_quest_discard(
				player_index,
				int(payload.get("quest_index", -1))
			)

		"black_rose_active_quest_limit":
			return submit_black_rose_active_quest_limit(
				player_index,
				payload.get("quest_indices", [])
			)

		"black_rose_completed_quest_limit":
			return submit_black_rose_completed_quest_limit(
				player_index,
				payload.get("quest_indices", [])
			)

		_:
			print(
				"submit_beta_input: unsupported input type ",
				input_type
			)
			return false


# =============================================================================
# STARTING SCHOOL / GRIMOIRE SETUP
# =============================================================================


func _mage_taken_by_other_player(
	mage_id: String,
	player_index: int
) -> bool:
	for other_index in range(players.size()):
		if other_index == player_index:
			continue

		if players[other_index].mage_id == mage_id:
			return true

	return false


func _available_starting_mages(
	player_index: int
) -> Array:
	var result: Array = []
	var mage_ids: Array[String] = mage_database.get_mage_ids()

	mage_ids.sort()

	for mage_id in mage_ids:
		if _mage_taken_by_other_player(
			mage_id,
			player_index
		):
			continue

		var data: Dictionary = (
			mage_database.get_mage_data(
				mage_id
			)
		)

		if data.is_empty():
			continue

		var personal_spell_id: String = str(
			data.get(
				"personal_spell_id",
				""
			)
		)
		var personal_spell_name: String = personal_spell_id

		if spell_database.spells.has(
			personal_spell_id
		):
			var personal_spell: SpellCardState = (
				spell_database.spells[
					personal_spell_id
				]
			)

			if personal_spell != null:
				personal_spell_name = personal_spell.card_name

		result.append({
			"id": mage_id,
			"name": str(
				data.get(
					"name",
					mage_id.capitalize()
				)
			),
			"health": int(
				data.get(
					"health",
					10
				)
			),
			"hand_limit": int(
				data.get(
					"hand_limit",
					6
				)
			),
			"strength": int(
				data.get(
					"strength",
					0
				)
			),
			"speed": int(
				data.get(
					"speed",
					0
				)
			),
			"personal_spell_id": personal_spell_id,
			"personal_spell_name": personal_spell_name
		})

	return result

func _school_taken_by_other_player(
	school_id: String,
	player_index: int
) -> bool:
	for other_index in range(players.size()):
		if other_index == player_index:
			continue

		if players[other_index].school_id == school_id:
			return true

	return false


func _available_starting_schools(
	player_index: int
) -> Array:
	var result: Array = []

	for school_id in active_school_ids:
		if not school_specialization_database.has(school_id):
			continue

		if _school_taken_by_other_player(
			school_id,
			player_index
		):
			continue

		result.append({
			"id": school_id,
			"name": get_school_display_name(school_id)
		})

	return result


func _find_starting_grimoire_data(
	school_id: String,
	grimoire_id: String
) -> Dictionary:
	if not school_specialization_database.has(school_id):
		return {}

	var school_data: Dictionary = (
		school_specialization_database[school_id]
	)

	for grimoire_value in school_data.get(
		"starting_grimoires",
		[]
	):
		if not grimoire_value is Dictionary:
			continue

		var grimoire: Dictionary = grimoire_value

		if str(grimoire.get("id", "")) == grimoire_id:
			return grimoire

	return {}


func _take_school_spell_for_starting_grimoire(
	school_id: String,
	spell_id: String
) -> SpellCardState:
	if not school_libraries.has(school_id):
		return null

	var library: Array = school_libraries[school_id]

	for i in range(library.size()):
		var spell: SpellCardState = library[i]

		if spell == null or spell.id != spell_id:
			continue

		library.remove_at(i)
		return spell

	return null


func build_starting_grimoire(
	player_index: int,
	school_id: String,
	grimoire_id: String
) -> bool:
	if player_index < 0 or player_index >= players.size():
		return false

	var player: PlayerState = players[player_index]

	if player.school_id != school_id:
		return false

	var grimoire_data: Dictionary = (
		_find_starting_grimoire_data(
			school_id,
			grimoire_id
		)
	)

	if grimoire_data.is_empty():
		return false

	var spell_ids: Array = grimoire_data.get(
		"spell_ids",
		[]
	)

	if spell_ids.size() != 6:
		print(
			"Starting Grimoire ",
			grimoire_id,
			" must contain exactly 6 School Spells"
		)
		return false

	# Validate all six cards before mutating the Library.
	var required_counts: Dictionary = {}

	for spell_id_value in spell_ids:
		var spell_id: String = str(spell_id_value)
		required_counts[spell_id] = int(
			required_counts.get(spell_id, 0)
		) + 1

	var available_counts: Dictionary = {}

	for spell_value in school_libraries.get(school_id, []):
		var spell: SpellCardState = spell_value

		if spell == null:
			continue

		available_counts[spell.id] = int(
			available_counts.get(spell.id, 0)
		) + 1

	for spell_id in required_counts:
		if int(
			available_counts.get(spell_id, 0)
		) < int(required_counts[spell_id]):
			print(
				"Starting Grimoire missing Library card: ",
				spell_id
			)
			return false

	player.hand.clear()
	player.grimoire.clear()
	player.memories.clear()
	player.ready_spells.clear()
	player.quick_spell = null
	player.active_spells.clear()
	player.revealed_spells.clear()

	for spell_id_value in spell_ids:
		var spell_id: String = str(spell_id_value)
		var school_spell: SpellCardState = (
			_take_school_spell_for_starting_grimoire(
				school_id,
				spell_id
			)
		)

		if school_spell == null:
			return false

		player.grimoire.append(school_spell)

	var personal_spell: SpellCardState = (
		create_personal_spell_copy(
			player.personal_spell_id
		)
	)

	if personal_spell == null:
		return false

	player.grimoire.append(personal_spell)
	player.personal_spell_copies_received = 1

	shuffle_with_rng(player.grimoire)

	# draw_from_grimoire() uses pop_back(), so this is the top/first card.
	var first_card: SpellCardState = player.grimoire.pop_back()
	player.memories.append(first_card)

	player.starting_grimoire_id = grimoire_id
	player.starting_grimoire_name = str(
		grimoire_data.get(
			"name",
			grimoire_id
		)
	)

	if player_index < player_boards.size() \
	and player_boards[player_index] != null:
		player_boards[player_index].refresh()

	print(
		"Player ",
		player_index + 1,
		" chose ",
		get_school_display_name(school_id),
		" / ",
		player.starting_grimoire_name,
		" | Grimoire ",
		player.grimoire.size(),
		" | Memories ",
		player.memories.size()
	)

	return true


func begin_starting_school_setup() -> bool:
	if starting_setup_complete:
		return true

	if players.size() > mage_database.get_mage_ids().size():
		print(
			"Starting setup requires ",
			players.size(),
			" Mages; only ",
			mage_database.get_mage_ids().size(),
			" are implemented."
		)
		return false

	if players.size() > active_school_ids.size():
		print(
			"Starting setup requires ",
			players.size(),
			" implemented Schools; only ",
			active_school_ids.size(),
			" are active."
		)
		return false

	starting_setup_order = get_play_order()

	if starting_setup_order.is_empty():
		return false

	starting_setup_stage = "mage"
	starting_setup_cursor = 0
	current_phase = PHASE_SETUP

	return advance_starting_school_setup()


func advance_starting_school_setup() -> bool:
	if starting_setup_complete:
		return true

	if waiting_for_player_input:
		return true

	while true:
		if starting_setup_cursor >= starting_setup_order.size():
			match starting_setup_stage:
				"mage":
					starting_setup_stage = "school"
					starting_setup_cursor = 0
					continue

				"school":
					starting_setup_stage = "grimoire"
					starting_setup_cursor = 0
					continue

				"grimoire":
					starting_setup_complete = true
					current_phase = ""

					print("")
					print("==============================================")
					print("            STARTING SETUP COMPLETE")
					print("==============================================")
					print("")

					if game_flow_active:
						return resolve_black_rose_phase()

					return true

				_:
					return false

		var player_index: int = starting_setup_order[
			starting_setup_cursor
		]
		var player: PlayerState = players[
			player_index
		]

		match starting_setup_stage:
			"mage":
				if player.mage_id != "":
					starting_setup_cursor += 1
					continue

				var available_mages: Array = (
					_available_starting_mages(
						player_index
					)
				)

				if available_mages.is_empty():
					print(
						"No legal Mage remains for Player ",
						player_index + 1
					)
					return false

				return request_player_input({
					"type": "starting_mage_choice",
					"phase": PHASE_SETUP,
					"setup_stage": "mage",
					"player_index": player_index,
					"available_mages": available_mages
				})

			"school":
				if player.school_id != "":
					starting_setup_cursor += 1
					continue

				var available_schools: Array = (
					_available_starting_schools(
						player_index
					)
				)

				if available_schools.is_empty():
					print(
						"No legal School remains for Player ",
						player_index + 1
					)
					return false

				return request_player_input({
					"type": "starting_school_choice",
					"phase": PHASE_SETUP,
					"setup_stage": "school",
					"player_index": player_index,
					"mage_id": player.mage_id,
					"available_schools": available_schools
				})

			"grimoire":
				if player.starting_grimoire_id != "":
					starting_setup_cursor += 1
					continue

				var options: Array = (
					get_starting_grimoire_options(
						player.school_id
					)
				)

				if options.is_empty():
					print(
						"No Starting Grimoire data for ",
						player.school_id
					)
					return false

				return request_player_input({
					"type": "starting_grimoire_choice",
					"phase": PHASE_SETUP,
					"setup_stage": "grimoire",
					"player_index": player_index,
					"mage_id": player.mage_id,
					"school_id": player.school_id,
					"school_name": get_school_display_name(
						player.school_id
					),
					"options": options
				})

			_:
				return false

	# GDScript does not consider `while true` exhaustive for a typed return
	# function, even though every branch above returns or continues.
	return false


func submit_starting_mage_choice(
	player_index: int,
	mage_id: String
) -> bool:
	if not waiting_for_player_input \
	or str(
		pending_input.get(
			"type",
			""
		)
	) != "starting_mage_choice":
		return false

	if starting_setup_stage != "mage":
		return false

	if player_index != int(
		pending_input.get(
			"player_index",
			-1
		)
	):
		return false

	var legal_ids: Array[String] = []

	for mage_value in pending_input.get(
		"available_mages",
		[]
	):
		if not mage_value is Dictionary:
			continue

		legal_ids.append(
			str(
				mage_value.get(
					"id",
					""
				)
			)
		)

	if not legal_ids.has(mage_id):
		return false

	if not assign_mage_to_player(
		player_index,
		mage_id
	):
		return false

	clear_player_input()
	starting_setup_cursor += 1

	return advance_starting_school_setup()

func submit_starting_school_choice(
	player_index: int,
	school_id: String
) -> bool:
	if not waiting_for_player_input \
	or str(pending_input.get("type", "")) != "starting_school_choice":
		return false

	if player_index != int(
		pending_input.get("player_index", -1)
	):
		return false

	var legal_ids: Array[String] = []

	for school_value in pending_input.get(
		"available_schools",
		[]
	):
		if not school_value is Dictionary:
			continue

		legal_ids.append(
			str(school_value.get("id", ""))
		)

	if not legal_ids.has(school_id):
		return false

	players[player_index].school_id = school_id

	clear_player_input()
	starting_setup_cursor += 1

	return advance_starting_school_setup()


func submit_starting_grimoire_choice(
	player_index: int,
	grimoire_id: String
) -> bool:
	if not waiting_for_player_input \
	or str(pending_input.get("type", "")) != "starting_grimoire_choice":
		return false

	if player_index != int(
		pending_input.get("player_index", -1)
	):
		return false

	var player: PlayerState = players[player_index]
	var legal_ids: Array[String] = []

	for option_value in pending_input.get("options", []):
		if not option_value is Dictionary:
			continue

		legal_ids.append(
			str(option_value.get("id", ""))
		)

	if not legal_ids.has(grimoire_id):
		return false

	if not build_starting_grimoire(
		player_index,
		player.school_id,
		grimoire_id
	):
		return false

	clear_player_input()
	starting_setup_cursor += 1
	return advance_starting_school_setup()

# =============================================================================
# WHOLE TURN FLOW
# =============================================================================


func _ensure_interactive_beta_started() -> void:
	if network_client:
		return
	if waiting_for_player_input:
		if beta_hud != null \
		and not pending_input.is_empty():
			beta_hud.present_pending_request(
				pending_input
			)
		return

	if game_has_ended:
		return

	if game_flow_active:
		if current_phase == "" \
		and resolution_stack.is_empty():
			game_flow_active = false
		else:
			return

	var started: bool = start_game_flow()

	if not started \
	and not waiting_for_player_input:
		game_flow_active = false

		print(
			"ERROR: beta game flow could not start. ",
			"Starting Grimoire DB schools: ",
			school_specialization_database.keys(),
			" | active schools: ",
			active_school_ids
		)

func start_game_flow() -> bool:
	if game_has_ended:
		return false
	if waiting_for_player_input or not resolution_stack.is_empty():
		return false

	game_flow_active = true

	if not starting_setup_complete:
		var setup_started: bool = begin_starting_school_setup()

		if not setup_started \
		and not waiting_for_player_input:
			game_flow_active = false

		return setup_started

	var phase_started: bool = resolve_black_rose_phase()

	if not phase_started \
	and not waiting_for_player_input:
		game_flow_active = false

	return phase_started


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

	var previous_room_id: String = ""
	var previous_room_coord: Vector2i = Vector2i.ZERO
	var previous_in_cell: bool = true

	if player.mage != null:
		previous_room_id = player.mage.room_id
		previous_room_coord = player.mage.room_coord
		previous_in_cell = player.mage.in_cell

	player.mage_id = str(data["id"])

	player.mage = MageState.new(
		str(data["id"]),
		int(data.get("health", 10)),
		int(data.get("strength", 0)),
		int(data.get("speed", 0))
	)

	player.mage.room_id = previous_room_id
	player.mage.room_coord = previous_room_coord
	player.mage.in_cell = previous_in_cell

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
	player.school_id = ""
	player.starting_grimoire_id = ""
	player.starting_grimoire_name = ""

	if player_index < player_boards.size() 	and player_boards[player_index] != null:
		player_boards[player_index].refresh()

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

	var spell: SpellCardState = spell_database.spells[spell_id]
	return clone_spell_card(spell)

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
				quest_manager.draw_phase_quest(
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

		if quest.is_solved():
			continue
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

		if player.completed_quests[index].is_solved():
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
	

func clear_board_target_choices() -> void:
	for node in get_tree().get_nodes_in_group("board_target_choices"):
		node.hide()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.get_parent().remove_child(node)
		node.queue_free()


func show_board_target_choice(option: Dictionary, callback: Callable, selected: bool = false) -> bool:
	var token: String = str(option.get("token", ""))
	var target: Node = null
	var position_in_target := Vector2(-24, -24)
	var hit_size := Vector2(48, 48)
	if token.begins_with("damage:") or token.begins_with("instability:"):
		var parts := token.split(":")
		if parts.size() != 3:
			return false
		var owners: Array = []
		var nodes: Array = []
		if token.begins_with("instability:"):
			var room = get_room_by_id(str(option.get("cube_room_id", "")))
			if room == null:
				return false
			owners = room.instability_cubes
			nodes = room.instability_cube_nodes
		else:
			var player_index: int = int(option.get("cube_player_index", -1))
			if option.has("cube_evocation_owner"):
				var evocation = get_evocation_by_owner_index(int(option.cube_evocation_owner), int(option.cube_evocation_index))
				if evocation == null or not evocation_tokens.has(evocation.get_instance_id()):
					return false
				owners = evocation.damage_cubes
				var model_token: Node = evocation_tokens[evocation.get_instance_id()]
				# Damage cubes are projected next to the Evocation while choosing.
				for i in range(owners.size()):
					var name_value := "ChoiceDamage%d" % i
					var cube = model_token.get_node_or_null(name_value)
					if cube == null or cube.is_queued_for_deletion():
						cube = preload("res://cube.tscn").instantiate()
						cube.name = name_value
						cube.cube_color = Color.BLACK if int(owners[i]) < 0 else players[int(owners[i])].color
						cube.position = Vector2(i * 18 - owners.size() * 9, 30)
						cube.add_to_group("board_target_choices")
						model_token.add_child(cube)
					nodes.append(cube)
			elif player_index >= 0 and player_index < player_boards.size():
				owners = players[player_index].mage.damage_cubes
				for slot in player_boards[player_index].get_node("DamageTrack").get_children():
					var cube = slot.get_node_or_null("DamageCube")
					if cube != null:
						nodes.append(cube)
		var ordinal := 0
		for i in range(mini(owners.size(), nodes.size())):
			if int(owners[i]) == int(parts[1]):
				if ordinal == int(parts[2]):
					target = nodes[i]
					break
				ordinal += 1
		position_in_target = Vector2(-3, -3)
		hit_size = Vector2(20, 20)
	elif int(option.get("evocation_index", -1)) >= 0:
		var evocation = get_evocation_by_owner_index(int(option.get("owner_id", -1)), int(option.evocation_index))
		if evocation != null:
			target = evocation_tokens.get(evocation.get_instance_id())
	elif option.has("player_index"):
		var index: int = int(option.player_index)
		if index >= 0 and index < mage_tokens.size():
			target = mage_tokens[index]
	if target == null:
		return false
	var button := Button.new()
	button.position = position_in_target
	button.size = hit_size
	button.z_index = 100
	button.tooltip_text = str(option.get("name", token))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 0.8, 0.15, 0.3 if selected else 0.04)
	style.border_color = Color(1, 0.8, 0.15)
	style.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", style)
	button.add_to_group("board_target_choices")
	button.set_meta("choice_token", token)
	button.pressed.connect(callback, CONNECT_DEFERRED)
	target.add_child(button)
	return true


func clear_lodge_room_choices() -> void:
	for node in get_tree().get_nodes_in_group("lodge_room_choices"):
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.hide()
		node.queue_free()

func show_lodge_room_choices(callbacks: Dictionary, selected_rooms: Array[String] = []) -> void:
	clear_lodge_room_choices()
	for room_id in callbacks:
		var room = get_room_by_id(str(room_id))
		if room == null:
			continue
		var choice = preload("res://lodge_room_choice.gd").new()
		choice.selected = str(room_id) in selected_rooms
		choice.setup(room.radius)
		choice.add_to_group("lodge_room_choices")
		choice.chosen.connect(callbacks[room_id])
		room.add_child(choice)
