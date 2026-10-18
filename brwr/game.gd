extends Node2D

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
var table_shell = null
var playmat: TextureRect
var table_reserves = null
var network_turn_presentation: Dictionary = {}
# Public presentation metadata only; effects stay in the existing resolution frames.
var card_presentation: Dictionary = {}
var card_presentation_serial := 0
var avatar_selection: Dictionary = {}
var avatar: AvatarState = null
var avatar_board: Node2D = null
const CARD_PRESENTATION_SECONDS := 2.3
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
# A movement changes the model state immediately, but nested Trap/Protection/
# Room resolutions used to run in the same render frame.  Requesting one frame
# of visual yield makes the committed movement visible before follow-up effects.
var resolution_visual_yield_requested: bool = false
var resolution_visual_yield_active: bool = false
var next_resolution_id: int = 1
var active_effect_context: Dictionary = {}

# CINIS_ENGINE_V1
# Cubes physically stored on Evocation cards by card abilities.
# Key = Evocation Object instance id, value = number of owner's cubes.
var stored_evocation_owner_cubes: Dictionary = {}

# Interactive choices requested while resolving an Effect.  The public
# request only exposes serializable option data; runtime values such as
# RevealedSpellState / EvocationState stay here until the player answers.
var pending_effect_choice_context: Dictionary = {}
var pending_effect_choice_values: Dictionary = {}

# Board-first Effect choices. Room choices are projected directly on the Lodge
# instead of forcing the player through a text menu. Vastum-only choices use
# the actual Vastum tokens as the click targets.
var pending_lodge_effect_room_tokens: Dictionary = {}
var pending_lodge_effect_selected_tokens: Array[String] = []
var pending_lodge_effect_player_index: int = -1
var pending_lodge_effect_min_select: int = 0
var pending_lodge_effect_max_select: int = 0
var pending_lodge_effect_vastum_only: bool = false

# Chaos reveal is modal: the revealed Grimoire card stays on screen until the
# resolving player explicitly clicks it away.
var pending_chaos_reveal_context: Dictionary = {}
var pending_chaos_reveal_context_key: String = ""
var pending_chaos_reveal_player_index: int = -1
var chaos_reveal_click_layer: CanvasLayer = null
# Dedicated fallback UI for the Chaos wildcard.  This is intentionally owned
# by Game so it cannot disappear because a generic effect-choice renderer
# ignores this specific choice kind.
var chaos_wildcard_choice_layer: CanvasLayer = null

# Clean-up decisions are intentionally one card at a time so every Active
# Trap/Protection can independently return to Hand, even on UIs that only
# support one card selection per prompt.
var cleanup_return_indices_by_player: Dictionary = {}
var cleanup_decided_indices_by_player: Dictionary = {}

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

# Online PvP: Library selection/draw remains authoritative and ordered, then
# every player resolves the private post-draw Study choices concurrently.
# These dictionaries live only on the authoritative host; each client receives
# only its own request through get_beta_pending_input().
var study_parallel_active: bool = false
var study_parallel_drawn_cards: Dictionary = {}
var study_parallel_requests: Dictionary = {}

# Online PvP Preparation is simultaneous: each player gets only their own
# private Hand request, while the host remains authoritative.
var preparation_parallel_active: bool = false
var preparation_parallel_requests: Dictionary = {}

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
var room_variants: Dictionary = {} # core Room ID -> selected definition, or "random"
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

# Vastum state is authoritative here, while the Room-owned Vastum marker is
# the only visible token.  Game creates only an invisible click target and a
# temporary outline for interaction; it never draws a second Vastum image.
var vastum_room_state: Dictionary = {}
var vastum_token_nodes: Dictionary = {}
var vastum_visual_nodes: Dictionary = {}
var vastum_outline_nodes: Dictionary = {}
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
var traps_resolved_count: int = 0

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
		},
		"chaos": {
			"name": "Chaos",
			"starting_grimoires": [
				{
					"id": "affliction",
					"name": "Affliction",
					"spell_ids": [
						"shapeshifting_energy",
						"erratic_vortex",
						"necrotic_plague",
						"void_wandering",
						"mutagenic_madness",
						"arrogance"
					]
				},
				{
					"id": "auromancer",
					"name": "Auromancer",
					"spell_ids": [
						"reclamation",
						"disorder",
						"fumbling_in_the_dark",
						"ephemeral_bond",
						"dark_path",
						"corruption_veil"
					]
				}
			]
		}
	}


func load_school_specializations() -> Dictionary:
	var candidate_paths: Array[String] = [
		"res://data/school_specializations_v19.json",
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
		+ "using built-in Starting Grimoires"
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
	evocation_database.load_database()
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

	create_players()
	AvatarRules.setup(self)
	assign_initial_crown()
	create_lodge()
	AvatarRules.place_at_setup(self)
	if avatar != null:
		avatar_board = AvatarBoard.new()
		add_child(avatar_board)
		avatar_board.setup(self)
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

		table_shell = preload("res://tabletop_shell.gd").new()
		add_child(table_shell)
		table_shell.setup(self)

		beta_hud = BetaHUDScript.new()
		add_child(beta_hud)
		beta_hud.setup(
			self,
			beta_sidebar_width
		)
		table_reserves = preload("res://table_reserves.gd").new()
		add_child(table_reserves)
		table_reserves.setup(self)

		var viewport := get_viewport()
		if not viewport.size_changed.is_connected(
			_on_beta_viewport_resized
		):
			viewport.size_changed.connect(
				_on_beta_viewport_resized
			)

		_apply_beta_table_layout()

	if not run_tests_on_ready \
	and enable_beta_hud:
		if not network_client and network_session == null:
			call_deferred(
				"_ensure_interactive_beta_started"
			)
	elif auto_start_game_flow:
		start_game_flow()

func get_turn_presentation() -> Dictionary:
	if network_client:
		return network_turn_presentation
	if avatar != null and resolution_stack.any(func(f): return str(f.get("type", "")) in ["avatar_activation", "avatar_command", "avatar_section"]):
		return {"player_index": avatar.player_index, "actions_used": avatar.commands_used, "action_limit": avatar.command_limit()}
	# A reaction may ask another player for input without changing the turn.
	if current_phase == PHASE_ACTION and action_activation_active:
		return {"player_index": action_activation_player_index, "actions_used": action_activation_actions_used}
	return {"player_index": int(pending_input.get("player_index", -1)) if waiting_for_player_input else -1,
		"actions_used": 0}

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
	var black_rose = selected_room_definition(get_room("black_rose"))
	var throne = selected_room_definition(get_room("throne"))

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
			room_pool.append(selected_room_definition(room_data))

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
	refresh_vastum_tokens()

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

	room_id_by_coord[hex_position] = room.get_room_id()


func selected_room_definition(base: Dictionary) -> Dictionary:
	var base_id: String = str(base.get("id", ""))
	var selection: String = str(room_variants.get(base_id, base_id))
	if selection == base_id:
		return base
	var candidates: Array = [base]
	for definition in room_database:
		if str(definition.get("replaces", "")) != base_id or not bool(definition.get("playable", true)):
			continue
		if selection == str(definition.get("id", "")):
			return definition
		candidates.append(definition)
	if selection == "random":
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	# A mismatched ID can never replace a Room from another family.
	return base


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
			if evocation == null or evocation.archetype == "equipment":
				continue

			var instance_id: int = int(
				evocation.get_instance_id()
			)
			live_ids[instance_id] = true

			if evocation_tokens.has(instance_id):
				evocation_tokens[instance_id].sync_state(evocation, owner_index,
					Color.DIM_GRAY if evocation.assigned_mage >= 0 else owner.color)
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
				Color.DIM_GRAY if evocation.assigned_mage >= 0 else players[owner_index].color,
				evocation.board_number,
				evocation
			)
			token.set_names_visible(table_shell != null and table_shell.evocation_names_visible)
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


func open_jinx_card(player_index: int, id: String) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	for jinx in players[player_index].mage.jinxes:
		if str(jinx.id) == id:
			var data := ForgottenAttachments.definition("jinxes", id)
			_reference_card_preview().show_card("jinxs", id, str(data.get("name", id)),
				"Player %d · Task: %d / %d" % [player_index + 1, int(jinx.progress), int(data.get("slots", 0))])
			return


func open_evocation_inspection(evocation: EvocationState, from_player_board: bool = false) -> void:
	# PlayerBoard is a modal tabletop view. A Lodge token that happens to sit
	# under the clicked card must never receive the same pointer interaction.
	if not from_player_board and table_shell != null \
	and table_shell.board_overlay != null \
	and table_shell.board_overlay.visible:
		return
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
			evocation.speed, get_evocation_effective_strength(evocation), evocation.room_id, get_evocation_controller_id(evocation) + 1]
	)
	if not evocation.upgrades.is_empty():
		var names: Array = []
		for id in evocation.upgrades:
			names.append(ForgottenAttachments.definition("upgrades", id).get("name", id))
		evocation_inspection.dialog_text += "\nUpgrades: " + ", ".join(names)
	if evocation.assigned_mage >= 0:
		evocation_inspection.dialog_text += "\nAssigned to %s · slot %d" % [players[evocation.assigned_mage].player_name, evocation.assigned_slot]
	if not evocation.stored_trophies.is_empty():
		evocation_inspection.dialog_text += "\nTrophies: %d" % evocation.stored_trophies.size()
	evocation_inspection.get_label().hide()
	evocation_inspection.get_node("Content/Stats").text = evocation_inspection.dialog_text


func refresh_model_tokens() -> void:
	EquipmentRules.sync(self)
	ForgottenEvocations.sync_assigned(self)
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

		token.set_transformation(players[player_index].get_transformation_id())
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

		var with_portraits: bool = entries.any(func(entry): return entry.node.has_method("has_portrait") and entry.node.has_portrait())
		var offsets: Array[Vector2] = (
			_model_token_offsets(
				entries.size(),
				with_portraits
			)
		)
		var center: Vector2 = group_centers[
			location_key
		]

		for i in range(entries.size()):
			var node = entries[i]["node"]

			if not is_instance_valid(node):
				continue

			# In a crowded Room use its central band, clear of the scroll and cubes.
			var rows := ceili(entries.size() / 3.0)
			node.scale = Vector2.ONE * (minf(0.72, 48.0 / maxf(1.0, rows - 1) / 48.0) if with_portraits and entries.size() > 3 else 1.0)
			_position_model_token(node, center + offsets[i], location_key)


func _position_model_token(node: Node2D, destination: Vector2, location_key: String) -> void:
	var previous_location: String = str(node.get_meta("visual_location", ""))
	var previous_destination: Vector2 = node.get_meta("visual_destination", node.position)
	node.set_meta("visual_location", location_key)
	node.set_meta("visual_destination", destination)
	if previous_destination.is_equal_approx(destination) and not previous_location.is_empty():
		return
	var previous_tween: Tween = node.get_meta("movement_tween") if node.has_meta("movement_tween") else null
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	# Initial placement and viewport/layout changes are immediate. Only a real
	# change of authoritative location slides a model between Rooms or its Cell.
	if previous_location.is_empty() or previous_location == location_key or table_shell == null:
		node.position = destination
		return
	var tween := node.create_tween()
	node.set_meta("movement_tween", tween)
	tween.tween_property(node, "position", destination, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _model_token_offsets(
	count: int,
	with_portraits: bool = false
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
			Vector2(-44 if with_portraits else -34, 0),
			Vector2(0, 0),
			Vector2(44 if with_portraits else 34, 0)
		]

	var columns: int = 2 if with_portraits and count == 4 else mini(3, count)
	var spacing_x: float = 44.0 if with_portraits else 35.0
	var spacing_y: float = minf(35.0 if with_portraits else 30.0, 48.0 / maxf(1.0, ceilf(float(count) / columns) - 1.0))
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
	owner_id = AvatarRules.cube_owner(self, owner_id)
	if owner_id == -1:
		return $EventBoard.take_black_rose_cubes(amount)

	if owner_id < 0 or owner_id >= players.size():
		print("ERRORE: owner_id non valido: ", owner_id)
		return 0

	return players[owner_id].take_cubes(amount)
	
func return_owner_cubes(owner_id: int, amount: int):
	owner_id = AvatarRules.cube_owner(self, owner_id)
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
	suppressed_trigger_types: Array = [],
	source_evocation: EvocationState = null
) -> int:
	if AvatarRules.immune_to_damage(self, attacker_id, target_player_index, action_type): return 0
	if DeathEffectResolver.ignores(active_effect_context, target_player_index):
		return 0
	if target_player_index < 0 \
	or target_player_index >= players.size():
		print("deal_damage: invalid target player")
		return 0

	if amount <= 0:
		return 0

	amount = _event_spell_damage_amount(attacker_id, amount, action_type)
	if attacker_id >= 0 and attacker_id != target_player_index \
	and is_mage_in_cell(target_player_index) and action_type not in ["event", "infectio"]:
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
		"source_model_type": "black_rose" if attacker_id == -1 else ("evocation" if source_evocation != null else "mage"),
		"source_evocation": source_evocation,
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
	$EventBoard.refresh_support_slots()
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
		if (category == "physical" and type in ["explore", "fight", "command", "transformation", "equipment", "spell_physical"]) \
		or (category == "momentum" and type == "momentum") \
		or (category == "quests" and option.get("kind") == "quest") \
		or (category == "finish" and option.get("kind") == "finish"):
			result.append(option)
	return result


func open_player_board_action(player_index: int, category: String) -> void:
	var options := get_player_board_action_options(player_index, category)
	if options.is_empty():
		return
	if table_shell != null:
		table_shell.close_board()
	if category == "finish":
		submit_beta_input(player_index, {"token": str(options[0].token)})
	elif beta_hud != null:
		beta_hud.open_board_actions(category)


func activate_player_board_spell(player_index: int, slot_id: String, inspect_only: bool = false) -> void:
	var token := get_player_board_cast_token(player_index, slot_id)
	if not inspect_only and token != "":
		if table_shell != null:
			table_shell.close_board()
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
		var matches: bool = (section == "private" and not quest.revealed and not quest.completed) or (section == "revealed" and quest.revealed and not quest.completed) or (section == "active" and not quest.completed and not quest.solved) or (section == "completed" and quest.completed and not quest.solved) or (section == "solved" and quest.solved)
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


func open_discarded_quest_card(card: QuestCardState) -> void:
	if card == null or not quest_discard.has(card):
		return
	inspected_quest = null
	_reference_card_preview().show_card("quests", card.id, card.card_name,
		"Task:\n%s\n\nEffects:\n%s" % [ReferenceCardPreview.describe_rules(card.task), ReferenceCardPreview.describe_rules(card.effects)])


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
				button.custom_minimum_size = Vector2(44, 44)
				button.flat = true
				var slot_id := _find_player_board_slot_for_spell(active.owner_id, active.spell)
				button.add_child(preload("res://tabletop_style.gd").marker("permanent", players[active.owner_id].color, Vector2(44, 44), slot_id))
				button.tooltip_text = active.spell.card_name
				button.pressed.connect(open_player_board_spell.bind(active.owner_id, slot_id))
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
	if avatar_board != null: bounds = bounds.merge(avatar_board.get_bounds())
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
	if table_reserves != null:
		bounds = bounds.merge(table_reserves.get_bounds())
	bounds = bounds.grow(96.0)
	# Match the usable viewport ratio by adding fabric, never shrinking Rooms.
	# At minimum zoom all pieces fit and no empty world appears past the mat.
	var area := get_table_view_rect()
	var extent := bounds.size
	var aspect := area.size.aspect()
	if extent.aspect() < aspect:
		extent.x = extent.y * aspect
	else:
		extent.y = extent.x / aspect
	return Rect2(bounds.get_center() - extent * 0.5, extent)


func get_table_view_rect() -> Rect2:
	var view := get_viewport_rect().size
	if table_shell != null:
		return Rect2(216, 0, maxf(160, view.x - 216), view.y)
	return Rect2(Vector2.ZERO, view)


func update_player_board_positions():
	if table_reserves != null:
		table_reserves.layout()
	if table_shell != null:
		table_shell._layout()
	else:
		for board in player_boards:
			board.hide()
	if playmat != null:
		var bounds := get_tabletop_bounds()
		playmat.position = bounds.position
		playmat.size = bounds.size


func _ensure_beta_background() -> void:
	if beta_background_layer != null:
		return

	beta_background_layer = CanvasLayer.new()
	beta_background_layer.layer = -100
	beta_background_layer.name = "BetaBackgroundLayer"
	add_child(beta_background_layer)

	var background := ColorRect.new()
	background.name = "BetaBackground"
	background.color = Color("090d0f")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	beta_background_layer.add_child(background)
	playmat = TextureRect.new()
	playmat.name = "Playmat"
	playmat.texture = load("res://assets/tabletop/playmat.png")
	playmat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	playmat.stretch_mode = TextureRect.STRETCH_SCALE
	playmat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	playmat.z_index = -100
	add_child(playmat)


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
	# Preserve the 2/4-player Room joints. With 3 players only the left
	# board moves; with 5/6, both notches join the outermost Cell's tip.
	var event_anchor := Vector2i(-2, 1)
	var power_anchor := Vector2i(2, -1)
	if player_count == 3 or player_count >= 5:
		for coord: Vector2i in player_cell_coords.values():
			if coord.x < event_anchor.x:
				event_anchor = coord
			if player_count >= 5 and coord.x > power_anchor.x:
				power_anchor = coord
	$EventBoard.position = hex_to_pixel(event_anchor) - Vector2(HEX_RADIUS, 0) - $EventBoard.LODGE_NOTCH
	$PowerBoard.position = hex_to_pixel(power_anchor) + Vector2(HEX_RADIUS, 0) - $PowerBoard.LODGE_NOTCH
	if avatar_board != null: avatar_board.reposition()

	update_player_board_positions()
	refresh_model_tokens()


func set_player_power(player_index: int, value: int):
	if AvatarRules.is_avatar(self, player_index):
		set_black_rose_power(value)
		return
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

	if amount > 0:
		amount = ForgottenAttachments.reduce_power(self, player_index, amount)
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
		event.data["source_kind"] = ForgottenPassives.source_kind(self)

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
	
func summon_evocation_for_effect(owner_id: int, evocation_id: String, room_id: String, context: Dictionary) -> EvocationState:
	context.erase("summon_declined")
	context.erase("last_summoned_evocation")
	if owner_id < 0 or owner_id >= players.size() or evocation_database.get_evocation(evocation_id).is_empty() or not is_lodge_room_id(room_id):
		return null
	if str(evocation_database.get_evocation(evocation_id).get("archetype", "")) == "nightmare":
		return null
	for existing in players[owner_id].evocations:
		if not ForgottenEvocations.ability(self, existing, "replace_summon_with_heal").is_empty():
			effect_resolver._heal_evocation(self, existing, 1)
			context["summon_declined"] = true
			return null
	# Rulebook p.20: with no model in reserve, the summon places nothing.
	# Check before offering a replacement, so no existing Evocation is lost.
	if get_available_evocation_copies(evocation_id) <= 0:
		context.erase("summon_replacement")
		context["summon_declined"] = true
		return null
	var player = players[owner_id]
	if str(evocation_database.get_evocation(evocation_id).get("archetype", "")) == "equipment" and player.evocations.any(func(e): return e.evocation_id == evocation_id):
		context["summon_declined"] = true
		return null
	if bool(evocation_database.get_evocation(evocation_id).get("requires_owner_cube", false)) and player.available_cubes <= 0:
		context["summon_declined"] = true
		return null
	if not bool(evocation_database.get_evocation(evocation_id).get("no_slot", false)) and not player.has_free_evocation_slot():
		if not context.has("summon_replacement"):
			request_effect_choice(owner_id, "summon_replacement", context, "summon_replacement",
				_spell_secondary_evocation_options(owner_id, owner_id).filter(func(o): return o.value.assigned_mage < 0 and not bool(o.value.definition.get("no_slot", false))), 0, 1,
				"Choose one of your Evocations to replace, or skip this summon.")
			return null
		var replacement = context.get("summon_replacement")
		context.erase("summon_replacement")
		if not replacement is EvocationState or not replacement in player.evocations or replacement.assigned_mage >= 0:
			context["summon_declined"] = true
			return null
		# Replacement returns the card/cubes without defeat or removal triggers.
		finalize_evocation_removal(replacement)
	return summon_evocation(owner_id, evocation_id, room_id)


func summon_evocation(
	owner_id: int,
	evocation_id: String,
	room_id: String
) -> EvocationState:

	if owner_id < 0 or owner_id >= players.size():
		print("ERRORE: owner_id non valido")
		return null

	var player = players[owner_id]

	var definition: Dictionary = evocation_database.get_evocation(evocation_id)
	if definition.get("archetype") == "equipment" and player.evocations.any(func(e): return e.evocation_id == evocation_id): return null
	if bool(definition.get("requires_owner_cube", false)) and player.available_cubes <= 0: return null

	if str(evocation_database.get_evocation(evocation_id).get("archetype", "")) == "nightmare":
		return null # Nightmares are assigned through their own Effect, never summoned.
	if not evocation_database.get_evocation(evocation_id).is_empty():
		for existing in player.evocations:
			if not ForgottenEvocations.ability(self, existing, "replace_summon_with_heal").is_empty():
				effect_resolver._heal_evocation(self, existing, 1)
				return null

	if not bool(evocation_database.get_evocation(evocation_id).get("no_slot", false)) and not player.has_free_evocation_slot():
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

	if get_available_evocation_copies(evocation_id) <= 0:
		print("No available copies of Evocation: ", evocation_id)
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

	evocation.definition = data
	evocation.room_id = room_id

	if not player.add_evocation(evocation):
		return null

	_store_owner_cubes_on_evocation_summon(evocation)
	ForgottenEvocations.on_summon(self, evocation)

	print(
		"Player ",
		owner_id + 1,
		" summoned ",
		evocation.evocation_name,
		" in room ",
		room_id
	)

	refresh_model_tokens()
	_request_resolution_visual_yield()
	queue_model_room_entry(
		"evocation",
		room_id,
		-1,
		evocation
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

			if evocation.is_defeated():
				_try_prevent_evocation_defeat_with_stored_cube(evocation)

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


# GEOMANCY_GEOFORM_V1

# CAPUT_DRACONIS_V1
func _caput_append_player_once(result: Array, player_index: int):
	if player_index < 0 or player_index >= players.size():
		return
	if not result.has(player_index):
		result.append(player_index)


func _caput_effect_can_affect_mage(effect: Dictionary) -> bool:
	var effect_type: String = str(effect.get("type", ""))

	if effect_type == "":
		return false

	# Generic families that can directly change a Mage.
	if "damage" in effect_type \
	or "mage" in effect_type \
	or effect_type.begins_with("move") \
	or effect_type.begins_with("place_target") \
	or effect_type.begins_with("swap") \
	or effect_type in [
		"lose_power",
		"steal_power",
		"convert_damage",
		"starve",
		"conditional_payment"
	]:
		return true

	# Nested effects are inspected recursively so conditional / choose-one /
	# Geoform wrappers do not hide an effect that the Mage is about to suffer.
	for key in ["effects", "else_effects"]:
		for nested in effect.get(key, []):
			if nested is Dictionary and _caput_effect_can_affect_mage(nested):
				return true

	for option in effect.get("options", []):
		if not option is Dictionary:
			continue
		for nested in option.get("effects", []):
			if nested is Dictionary and _caput_effect_can_affect_mage(nested):
				return true

	return false


func _caput_effect_affected_players(
	effect: Dictionary,
	context: Dictionary
) -> Array:
	var result: Array = []
	var caster_id: int = int(context.get("caster_id", -1))
	var effect_type: String = str(effect.get("type", ""))
	var target_type: String = str(
		effect.get(
			"target",
			context.get("spell_target_type", "")
		)
	)

	# Being the printed target is itself a valid Caput Draconis condition.
	if target_type == "mage":
		_caput_append_player_once(
			result,
			int(context.get("target_player_index", -1))
		)
	elif target_type == "model":
		var model_type: String = str(context.get("target_model_type", ""))
		if model_type == "mage" or (
			model_type == "" and context.has("target_player_index")
		):
			_caput_append_player_once(
				result,
				int(context.get("target_player_index", -1))
			)
	elif target_type == "self":
		_caput_append_player_once(result, caster_id)

	# Effects hitting the entire Lodge can make any Mage suffer the Effect.
	if effect_type == "damage_all_models_lodge":
		for player_index in range(players.size()):
			if not is_mage_in_cell(player_index):
				_caput_append_player_once(result, player_index)

	# Whips of Thorns-style area damage is centered on the target Room.
	if effect_type == "damage_rooms_in_range_from_target":
		var origin_room_id: String = str(context.get("target_room_id", ""))
		var max_distance: int = maxi(0, int(effect.get("range_from_target", 0)))
		if origin_room_id != "":
			for player_index in range(players.size()):
				if is_mage_in_cell(player_index):
					continue
				var room_id: String = str(players[player_index].mage.room_id)
				if room_id != "" and is_room_within_effect_range(
					origin_room_id,
					room_id,
					max_distance
				):
					_caput_append_player_once(result, player_index)

	# A Room is not a Mage, so merely placing Instability does not qualify.
	# If the current sentence can affect a Mage, every Mage in that Room is
	# "about to suffer its Effect" and may use Caput Draconis.
	if effect_type == "starve":
		for player_index in FamineRules.target_mages(self, effect, context):
			_caput_append_player_once(result, player_index)
	elif target_type == "room" and _caput_effect_can_affect_mage(effect):
		var room_id: String = str(context.get("target_room_id", ""))
		if room_id != "":
			for player_index in range(players.size()):
				if is_mage_in_cell(player_index):
					continue
				if str(players[player_index].mage.room_id) == room_id:
					_caput_append_player_once(result, player_index)

	return result


func _append_caput_draconis_triggers(
	event: GameEvent,
	triggered: Array
):
	if event == null or not event.has_meta("caput_spell_effect"):
		return
	if not bool(event.get_meta("caput_spell_effect")):
		return

	var spell_type: String = str(event.get_meta("source_spell_type", ""))
	var affected_value = event.get_meta("affected_player_indices", [])
	var affected: Array = affected_value if affected_value is Array else []

	for affected_value_item in affected:
		var owner_id: int = int(affected_value_item)
		if owner_id < 0 or owner_id >= players.size():
			continue

		for active_spell in players[owner_id].active_spells:
			if active_spell == null or not active_spell.active:
				continue
			if active_spell.get_spell_type() != "protection":
				continue

			var side: Dictionary = active_spell.get_side()
			var trigger_value = side.get("trigger", {})
			if not trigger_value is Dictionary:
				continue
			var trigger: Dictionary = trigger_value
			if str(trigger.get("type", "")) != \
			"caster_targeted_or_about_to_suffer_spell_effect":
				continue

			var allowed_types: Array[String] = []
			for value in trigger.get("spell_types", []):
				allowed_types.append(str(value))
			if not allowed_types.is_empty() and not allowed_types.has(spell_type):
				continue

			var duplicate: bool = false
			for trigger_data_value in triggered:
				if trigger_data_value is Dictionary \
				and trigger_data_value.get("active_spell", null) == active_spell:
					duplicate = true
					break
			if duplicate:
				continue

			triggered.append({
				"active_spell": active_spell,
				"event": event
			})


func _announce_caput_draconis_effect(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var affected: Array = _caput_effect_affected_players(effect, context)
	if affected.is_empty():
		return false

	var event := GameEvent.new("spell_effect_about_to_resolve")
	event.source_model_type = "mage"
	event.source_player_index = int(context.get("caster_id", -1))
	event.source_room_id = str(context.get("caster_room_id", ""))
	if affected.size() == 1:
		event.target_model_type = "mage"
		event.target_player_index = int(affected[0])

	event.set_meta("caput_spell_effect", true)
	event.set_meta("source_spell_context", context)
	event.set_meta("source_spell_effect", effect)
	event.set_meta("source_spell_id", str(context.get("spell_id", "")))
	event.set_meta("source_spell_type", str(context.get("spell_type", "")))
	event.set_meta("source_spell_forgotten", bool(context.get("spell_forgotten", false)))
	event.set_meta("affected_player_indices", affected)

	# Reuse the normal optional Protection trigger window and ordering.
	return not process_game_event(event)


func _append_geomancy_room_entry_triggers(
	event: GameEvent,
	triggered: Array
):
	if event == null:
		return

	if not event.has_meta("room_entry_event_type"):
		return

	if str(event.get_meta("room_entry_event_type")) != "mage_enters_room":
		return

	if str(event.source_model_type) != "mage":
		return

	var entering_player_index: int = int(event.source_player_index)
	if entering_player_index < 0 or entering_player_index >= players.size():
		return

	if EquipmentRules.has_ability(self, entering_player_index, "ignore_room_entry_traps"):
		return
	var room_id: String = str(event.source_room_id)
	if room_id == "":
		room_id = str(event.target_room_id)
	if room_id == "":
		return

	var room_data = get_room(room_id)
	if room_data == null or not room_data is Dictionary:
		return

	var room_color: String = str(room_data.get("color", ""))

	var active_player_count: int = min(
		player_count,
		players.size()
	)

	for owner_id in range(active_player_count):
		# "Another Mage" excludes the Trap owner.
		if owner_id == entering_player_index:
			continue

		for active_spell in players[owner_id].active_spells:
			if active_spell == null or not active_spell.active:
				continue

			var side: Dictionary = active_spell.get_side()
			var trigger_value = side.get("trigger", {})
			if not trigger_value is Dictionary:
				continue

			var trigger: Dictionary = trigger_value
			if str(trigger.get("type", "")) != "another_mage_enters_room":
				continue

			var allowed_colors: Array[String] = []
			for color_value in trigger.get("room_colors", []):
				allowed_colors.append(str(color_value))

			if not allowed_colors.is_empty() \
			and not allowed_colors.has(room_color):
				continue

			var already_present: bool = false
			for trigger_data_value in triggered:
				if not trigger_data_value is Dictionary:
					continue
				var trigger_data: Dictionary = trigger_data_value
				if trigger_data.get("active_spell", null) == active_spell:
					already_present = true
					break

			if already_present:
				continue

			triggered.append({
				"active_spell": active_spell,
				"event": event
			})


func gain_player_trophy(owner: int, victim: int) -> void:
	if owner < 0 or owner >= players.size(): return
	players[owner].trophies.append(victim)
	var event := GameEvent.new("trophy_gained")
	event.source_player_index = owner
	event.source_model_type = "mage"
	event.target_player_index = victim
	queue_resolution({"type": "game_event", "event": event})


func process_game_event(
	event: GameEvent
) -> bool:
	if event == null:
		return true
	EquipmentRules.on_event(self, event)
	PestilenceRules.on_event(self, event)
	ForgottenPassives.on_event(self, event)
	ForgottenAttachments.on_event(self, event)
	ForgottenEvocations.on_event(self, event)
	DruidicRules.on_evocation_loss(self, event)

	if quest_manager != null:
		quest_manager.process_game_event(
			self,
			event
		)


	var triggered = triggered_spell_manager.get_triggered_spells(
		event,
		players
	)
	triggered = triggered.filter(func(item):
		var active: ActiveSpellState = item.active_spell
		var trigger: Dictionary = active.get_trigger()
		if trigger.get("type") == "model_enters_caster_room":
			return not players[active.owner_id].mage.in_cell and event.target_room_id == players[active.owner_id].mage.room_id
		if trigger.has("range"):
			var room_id: String = event.target_room_id if not event.target_room_id.is_empty() else event.source_room_id
			return is_room_within_effect_range(players[active.owner_id].mage.room_id, room_id, trigger.range)
		return true)

	_append_geomancy_room_entry_triggers(
		event,
		triggered
	)

	_append_caput_draconis_triggers(
		event,
		triggered
	)
	AvatarRules.append_reaction(self, event, triggered)
	AvatarEvents.on_event(self, event)

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

	if active_spell.context.has("avatar_command"):
		return AvatarRules.trigger_reaction(self, active_spell, event)

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
	amount: int,
	controller_id: int = -1
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
		"attacker_id": controller_id if controller_id >= 0 else get_evocation_controller_id(evocation),
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


# =============================================================================
# GEOMANCY ATTACHED EFFECTS — CARCER
# =============================================================================

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

	return ForgottenPassives.spell_room_in_range(self, caster_id, target_room_id, range_value)


func _request_resolution_visual_yield() -> void:
	if processing_resolution_stack:
		resolution_visual_yield_requested = true
	if network_session != null and not network_client:
		network_session.call_deferred("publish")


func _resume_resolution_after_visual_yield() -> void:
	# Keep nested effects behind the movement animation (one frame without UI).
	resolution_visual_yield_active = false
	process_resolution_stack()


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
		_request_resolution_visual_yield()
		queue_model_room_entry(
			"mage",
			destination_room_id,
			player_index,
			null
		)
		return true

	if get_hex_distance(mage.room_coord, destination_coord) > max_distance:
		return false

	var previous_room_id: String = str(mage.room_id)
	mage.room_id = destination_room_id
	mage.room_coord = destination_coord
	mage.in_cell = false
	print("Player ", player_index + 1, " moved to ", destination_room_id)
	refresh_model_tokens()
	_request_resolution_visual_yield()
	if previous_room_id != destination_room_id:
		queue_model_room_entry(
			"mage",
			destination_room_id,
			player_index,
			null
		)
	return true

func move_evocation_to_room_id(
	evocation: EvocationState,
	destination_room_id: String,
	max_distance: int
) -> bool:

	if evocation == null or evocation.archetype == "equipment":
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

	var previous_room_id: String = str(evocation.room_id)
	evocation.room_id = destination_room_id

	print(
		evocation.evocation_name,
		" moved to ",
		destination_room_id
	)

	refresh_model_tokens()
	_request_resolution_visual_yield()
	if previous_room_id != destination_room_id:
		queue_model_room_entry(
			"evocation",
			destination_room_id,
			-1,
			evocation
		)
	return true

# =============================================================================
# MODEL ENTERS ROOM
# =============================================================================

func place_mage_in_room_direct(
	player_index: int,
	room_id: String
) -> bool:
	if player_index < 0 or player_index >= players.size():
		return false

	var coord: Vector2i = room_id_to_coord(room_id)
	if coord == Vector2i(9999, 9999):
		return false

	var mage = players[player_index].mage
	if mage == null:
		return false

	mage.room_id = room_id
	mage.room_coord = coord
	mage.in_cell = false

	refresh_model_tokens()
	_request_resolution_visual_yield()

	queue_model_room_entry(
		"mage",
		room_id,
		player_index,
		null
	)

	return true


func place_evocation_in_room_direct(
	evocation: EvocationState,
	room_id: String
) -> bool:
	if evocation == null \
	or evocation.archetype == "equipment" \
	or evocation.is_defeated() \
	or not is_evocation_in_play(evocation):
		return false

	if not is_lodge_room_id(room_id):
		return false

	evocation.room_id = room_id

	refresh_model_tokens()
	_request_resolution_visual_yield()

	queue_model_room_entry(
		"evocation",
		room_id,
		-1,
		evocation
	)

	return true


func queue_model_room_entry(
	model_type: String,
	room_id: String,
	player_index: int = -1,
	evocation: EvocationState = null
) -> bool:
	if model_type != "mage" and model_type != "evocation":
		return false

	if not is_lodge_room_id(room_id):
		return false

	if model_type == "mage":
		if player_index < 0 or player_index >= players.size():
			return false
	else:
		if evocation == null:
			return false

	return queue_resolution({
		"type": "model_room_entry",
		"step": "start",
		"model_type": model_type,
		"room_id": room_id,
		"player_index": player_index,
		"evocation": evocation,
		"event_index": 0,
		"ability_index": 0
	})


func process_model_room_entry_resolution(
	resolution: Dictionary
) -> bool:
	var model_type: String = str(
		resolution.get("model_type", "")
	)
	var room_id: String = str(
		resolution.get("room_id", "")
	)
	var player_index: int = int(
		resolution.get("player_index", -1)
	)
	var entering_evocation: EvocationState = resolution.get(
		"evocation",
		null
	)

	match str(resolution.get("step", "start")):
		"start":
			var event_types: Array[String] = [
				"model_enters_room"
			]

			if model_type == "mage":
				event_types.append("mage_enters_room")

			resolution["event_types"] = event_types
			resolution["event_index"] = 0

			var pending_abilities: Array = []

			for player in players:
				for source in player.evocations:
					if source == null \
					or source.is_defeated() \
					or not is_evocation_in_play(source):
						continue

					if source == entering_evocation:
						continue

					if str(source.room_id) != room_id:
						continue

					for ability_value in get_evocation_abilities(source):
						if not ability_value is Dictionary:
							continue

						var ability: Dictionary = ability_value
						var ability_type: String = str(
							ability.get("type", "")
						)
						var trigger: String = str(
							ability.get("trigger", "")
						)
						var applies: bool = false

						if ability_type == "damage_models_entering_room" \
						and trigger == "model_enters_room":
							applies = true

						if model_type == "mage" \
						and ability_type == "damage_mage_entering_room" \
						and trigger == "mage_enters_room":
							applies = true

						if not applies:
							continue

						pending_abilities.append({
							"source": source,
							"controller_id": get_evocation_controller_id(source),
							"ability": ability
						})

			resolution["pending_abilities"] = pending_abilities
			resolution["ability_index"] = 0
			resolution["step"] = "events"
			return false

		"events":
			var event_types: Array = resolution.get(
				"event_types",
				[]
			)
			var event_index: int = int(
				resolution.get("event_index", 0)
			)

			if event_index >= event_types.size():
				resolution["step"] = "abilities"
				return false

			var event := GameEvent.new(
				str(event_types[event_index])
			)

			event.set_meta(
				"room_entry_event_type",
				str(event_types[event_index])
			)

			event.source_model_type = model_type
			event.source_room_id = room_id
			event.target_room_id = room_id
			event.action_type = "enter_room"

			if model_type == "mage":
				event.source_player_index = player_index
			else:
				event.source_evocation = entering_evocation
				if entering_evocation != null:
					event.source_player_index = entering_evocation.owner_id

			resolution["event_index"] = event_index + 1
			queue_resolution({
				"type": "game_event",
				"event": event
			})
			return false

		"abilities":
			var pending_abilities: Array = resolution.get(
				"pending_abilities",
				[]
			)
			var ability_index: int = int(
				resolution.get("ability_index", 0)
			)

			if ability_index >= pending_abilities.size():
				return true

			resolution["ability_index"] = ability_index + 1

			var item: Dictionary = pending_abilities[
				ability_index
			]
			var source: EvocationState = item.get(
				"source",
				null
			)
			var controller_id: int = int(
				item.get("controller_id", -1)
			)
			var ability: Dictionary = item.get(
				"ability",
				{}
			)
			var amount: int = int(
				ability.get("amount", 0)
			)

			if source == null \
			or source.is_defeated() \
			or not is_evocation_in_play(source) \
			or str(source.room_id) != room_id \
			or amount <= 0:
				return false

			if model_type == "mage":
				if player_index < 0 \
				or player_index >= players.size():
					return false

				var mage = players[player_index].mage
				if mage == null \
				or mage.in_cell \
				or str(mage.room_id) != room_id:
					return false

				deal_damage_from_evocation(
					source,
					player_index,
					amount,
					controller_id
				)
				return false

			if entering_evocation == null \
			or entering_evocation.is_defeated() \
			or not is_evocation_in_play(entering_evocation) \
			or str(entering_evocation.room_id) != room_id:
				return false

			deal_damage_to_evocation(
				controller_id,
				entering_evocation,
				amount,
				[],
				"evocation_ability",
				"evocation",
				source
			)
			return false

		_:
			return true


func process_summon_distinct_evocations_resolution(
	resolution: Dictionary
) -> bool:
	var owner_id: int = int(
		resolution.get("owner_id", -1)
	)
	var evocation_id: String = str(
		resolution.get("evocation_id", "")
	)
	var room_ids: Array = resolution.get(
		"room_ids",
		[]
	)
	var cursor: int = int(
		resolution.get("cursor", 0)
	)
	var context: Dictionary = resolution.get(
		"context",
		{}
	)
	var result_key: String = str(
		resolution.get(
			"result_key",
			"last_distinct_summoned_evocations"
		)
	)

	if cursor >= room_ids.size():
		return true

	var room_id: String = str(room_ids[cursor])

	var summoned: EvocationState = summon_evocation_for_effect(
		owner_id,
		evocation_id,
		room_id,
		context
	)

	if waiting_for_player_input:
		return false

	resolution["cursor"] = cursor + 1

	if summoned != null:
		var summoned_list: Array = context.get(
			result_key,
			[]
		)

		summoned_list.append(summoned)
		context[result_key] = summoned_list
		context["last_summoned_evocation"] = summoned
		context["effect_summoned_evocation"] = true

	return false


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

	for player in players:
		if player.evocations.has(evocation):
			return true
	return false


func get_evocation_controller_id(
	evocation: EvocationState
) -> int:
	if evocation == null:
		return -999

	var controller_id: int = int(evocation.controller_id)

	if controller_id < 0:
		controller_id = int(evocation.owner_id)

	return controller_id



# A_BURNING_WORLD_V1
# =============================================================================
# EVOCATION CARD ABILITIES
# ANCIENTS_SYMBOL_ON_ACTIVATE_V1
# =============================================================================

func get_evocation_abilities(
	evocation: EvocationState
) -> Array:
	if evocation == null:
		return []

	var data: Dictionary = evocation_database.get_evocation(
		evocation.evocation_id
	)

	if data.is_empty():
		return []

	return data.get("abilities", []).duplicate(true) + ForgottenAttachments.abilities(evocation)


func get_evocation_attack_range(
	evocation: EvocationState
) -> int:
	# Normal Evocation Physical Attacks are Range 0 (same Room).
	var result: int = 0

	for ability_value in get_evocation_abilities(evocation):
		if not ability_value is Dictionary:
			continue

		var ability: Dictionary = ability_value
		if not str(ability.get("type", "")) in ["attack_range", "attack_room"]:
			continue

		result = max(
			result,
			int(ability.get("range", 0))
		)

	return result


func get_evocation_effective_strength(
	evocation: EvocationState,
	strength_bonus: int = 0
) -> int:
	if evocation == null:
		return 0

	if bool(evocation.definition.get("fixed_stats", false)): return int(evocation.definition.strength)
	var result: int = int(evocation.strength) + strength_bonus

	for ability_value in get_evocation_abilities(evocation):
		if not ability_value is Dictionary:
			continue

		var ability: Dictionary = ability_value
		if str(ability.get("type", "")) \
		!= "strength_per_other_same_evocation_in_room":
			continue

		var same_room_count: int = 0

		for player in players:
			for other in player.evocations:
				if other == null \
				or other == evocation \
				or other.is_defeated():
					continue

				if str(other.evocation_id) != str(evocation.evocation_id):
					continue

				if str(other.room_id) != str(evocation.room_id):
					continue

				same_room_count += 1

		result += (
			same_room_count
			* int(
				ability.get(
					"amount_per_other",
					ability.get("amount", 1)
				)
			)
		)

	return result + ForgottenEvocations.bonus_strength(self, evocation)



# =============================================================================
# CINIS / STORED EVOCATION CUBES
# =============================================================================

func _evocation_storage_key(
	evocation: EvocationState
) -> int:
	if evocation == null:
		return 0

	return int(evocation.get_instance_id())


func _find_evocation_ability_by_types(
	evocation: EvocationState,
	ability_types: Array[String]
) -> Dictionary:
	if evocation == null:
		return {}

	for ability_value in get_evocation_abilities(evocation):
		if not ability_value is Dictionary:
			continue

		var ability: Dictionary = ability_value
		if str(ability.get("type", "")) in ability_types:
			return ability

	return {}


func get_evocation_stored_owner_cube_count(
	evocation: EvocationState
) -> int:
	var key: int = _evocation_storage_key(evocation)
	if key == 0:
		return 0

	return max(
		0,
		int(stored_evocation_owner_cubes.get(key, 0))
	)


func _store_owner_cubes_on_evocation_summon(
	evocation: EvocationState
) -> int:
	if evocation == null:
		return 0

	var ability: Dictionary = _find_evocation_ability_by_types(
		evocation,
		[
			"store_owner_cube_on_summon",
			"summon_with_resurrection_cube"
		]
	)

	if ability.is_empty():
		return 0

	var requested: int = max(
		0,
		int(ability.get("amount", 1))
	)

	if requested <= 0:
		return 0

	var owner_id: int = int(evocation.owner_id)
	if owner_id < 0 or owner_id >= players.size():
		return 0

	var taken: int = take_owner_cubes(
		owner_id,
		requested
	)

	if taken <= 0:
		print(
			evocation.get_display_name(),
			": no owner cube available to place on its card"
		)
		return 0

	var key: int = _evocation_storage_key(evocation)
	stored_evocation_owner_cubes[key] = (
		get_evocation_stored_owner_cube_count(evocation)
		+ taken
	)

	print(
		evocation.get_display_name(),
		": stored ",
		taken,
		" owner cube on its card"
	)

	refresh_all_player_boards()
	return taken


func _return_stored_owner_cubes_from_evocation(
	evocation: EvocationState
) -> int:
	if evocation == null:
		return 0

	var stored: int = get_evocation_stored_owner_cube_count(
		evocation
	)

	if stored <= 0:
		return 0

	var owner_id: int = int(evocation.owner_id)
	var key: int = _evocation_storage_key(evocation)

	stored_evocation_owner_cubes.erase(key)

	if owner_id >= 0 and owner_id < players.size():
		return_owner_cubes(
			owner_id,
			stored
		)

	refresh_all_player_boards()
	return stored


func _try_prevent_evocation_defeat_with_stored_cube(
	evocation: EvocationState
) -> bool:
	if evocation == null or not evocation.is_defeated():
		return false

	var ability: Dictionary = _find_evocation_ability_by_types(
		evocation,
		[
			"prevent_defeat_with_stored_cube",
			"prevent_defeat_with_resurrection_cube"
		]
	)

	if ability.is_empty():
		return false

	var stored: int = get_evocation_stored_owner_cube_count(
		evocation
	)

	if stored <= 0:
		return false

	var owner_id: int = int(evocation.owner_id)
	var key: int = _evocation_storage_key(evocation)

	stored -= 1

	if stored <= 0:
		stored_evocation_owner_cubes.erase(key)
	else:
		stored_evocation_owner_cubes[key] = stored

	if owner_id >= 0 and owner_id < players.size():
		return_owner_cubes(
			owner_id,
			1
		)

	var heal_all: bool = bool(
		ability.get(
			"heal_all_damage",
			str(ability.get("heal", "")) == "full"
		)
	)

	if heal_all:
		var damage_snapshot: Array[int] = (
			evocation.damage_cubes.duplicate()
		)

		for cube_owner_id in damage_snapshot:
			return_owner_cubes(
				int(cube_owner_id),
				1
			)

		evocation.damage_cubes.clear()

	refresh_all_player_boards()
	refresh_model_tokens()

	var prevented: bool = not evocation.is_defeated()

	if prevented:
		print(
			evocation.get_display_name(),
			": defeat prevented; stored cube discarded",
			" and all Damage healed"
			if heal_all
			else ""
		)

	return prevented


func finalize_evocation_removal(
	evocation: EvocationState
) -> bool:
	if evocation == null:
		return false

	var owner_id: int = evocation.assigned_mage if evocation.assigned_mage >= 0 else int(evocation.owner_id)
	if owner_id < 0 or owner_id >= players.size():
		return false

	var owner = players[owner_id]
	var index: int = owner.evocations.find(evocation)

	if index == -1:
		return false

	# Cubes stored on the Evocation card also return to their owner when
	# the Evocation leaves play for any reason other than prevented defeat.
	_return_stored_owner_cubes_from_evocation(evocation)

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
	evocation: EvocationState,
	attack_range: int = 0
) -> bool:
	if evocation != null and not ForgottenEvocations.ability(self, evocation, "cannot_be_physically_attacked").is_empty():
		return false
	if attacker_id < 0 or attacker_id >= players.size():
		return false

	if evocation == null \
	or evocation.is_defeated() \
	or not is_evocation_in_play(evocation):
		return false

	var attacker_mage = players[attacker_id].mage

	if attacker_mage == null or attacker_mage.in_cell:
		return false

	if not is_room_within_effect_range(attacker_mage.room_id, evocation.room_id, attack_range):
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

	var force_activation: bool = bool(context.get("force_room_activation", false))
	if not force_activation and not room.can_activate(allow_reactivate_flipped):
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
		"force_activation": force_activation,
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
	for player in players:
		if str(player.get_transformation_data().get("evocation_id", "")) == evocation_id:
			copies_in_play += 1


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



# =========================================================
# CHAOS SCHOOL - VASTUM
# =========================================================

func _sync_room_vastum_visual(room_id: String) -> void:
	var room = get_room_by_id(room_id)
	if room == null:
		return

	# Room art only projects authoritative state. Reading the old visual flag
	# here would recreate a Vastum immediately after remove_vastum erased it.
	if room.has_method("set_vastum_present"):
		room.set_vastum_present(room_has_vastum(room_id))


func room_has_vastum(room_id: String) -> bool:
	return bool(vastum_room_state.get(room_id, false))


func _find_room_vastum_visual(node: Node):
	if node == null:
		return null

	# Prefer an explicit accessor if Room exposes one.
	if node.has_method("get_vastum_token_node"):
		var explicit = node.get_vastum_token_node()
		if is_instance_valid(explicit):
			return explicit

	for child in node.get_children():
		if not is_instance_valid(child):
			continue

		# Never mistake our own interaction helpers for the actual token art.
		if child.is_in_group("vastum_click_targets") \
		or child.is_in_group("vastum_choice_outlines"):
			continue

		if "vastum" in str(child.name).to_lower():
			return child

		var nested = _find_room_vastum_visual(child)
		if is_instance_valid(nested):
			return nested

	return null


func _create_vastum_outline(room_id: String, visual):
	var old_outline = vastum_outline_nodes.get(room_id, null)
	if is_instance_valid(old_outline):
		old_outline.queue_free()
		vastum_outline_nodes.erase(room_id)

	if not is_instance_valid(visual) or not visual is Control:
		return null

	var host = visual.get_parent()
	if host == null:
		return null

	var margin := 5.0
	var outline := Panel.new()
	outline.position = visual.position - Vector2(margin, margin)
	outline.size = visual.size + Vector2(margin * 2.0, margin * 2.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color.WHITE
	style.set_border_width_all(3)
	style.set_corner_radius_all(32)
	style.shadow_color = Color(1, 1, 1, 0.65)
	style.shadow_size = 5
	outline.add_theme_stylebox_override("panel", style)

	outline.name = "VastumChoiceOutline"
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.z_index = visual.z_index - 1
	outline.visible = false
	outline.add_to_group("vastum_choice_outlines")
	host.add_child(outline)
	host.move_child(outline, max(0, visual.get_index()))

	vastum_outline_nodes[room_id] = outline
	return outline


func _create_vastum_token(room_id: String):
	var room = get_room_by_id(room_id)
	if room == null:
		return null

	_sync_room_vastum_visual(room_id)

	var visual = _find_room_vastum_visual(room)
	if is_instance_valid(visual):
		vastum_visual_nodes[room_id] = visual

	# The click target is intentionally invisible.  The visible token remains
	# the small Room-owned token below the Room name.
	var hitbox := Button.new()
	hitbox.name = "VastumClickTarget"
	hitbox.flat = true
	hitbox.text = ""
	hitbox.focus_mode = Control.FOCUS_NONE
	hitbox.mouse_filter = Control.MOUSE_FILTER_STOP
	hitbox.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hitbox.tooltip_text = "Vastum · " + str(room.room_name)
	hitbox.add_to_group("vastum_click_targets")

	var host: Node = room
	if is_instance_valid(visual) and visual is Control:
		host = visual.get_parent()
		var margin := 6.0
		hitbox.position = visual.position - Vector2(margin, margin)
		hitbox.size = visual.size + Vector2(margin * 2.0, margin * 2.0)
		hitbox.z_index = visual.z_index + 10
	else:
		# Fallback only for old Room scenes where the marker cannot be found.
		# No second texture is drawn.
		hitbox.position = Vector2(18.0, 14.0)
		hitbox.size = Vector2(58.0, 58.0)
		hitbox.z_index = 650

	var empty_style := StyleBoxEmpty.new()
	hitbox.add_theme_stylebox_override("normal", empty_style)
	hitbox.add_theme_stylebox_override("hover", empty_style)
	hitbox.add_theme_stylebox_override("pressed", empty_style)

	hitbox.pressed.connect(
		_on_vastum_token_pressed.bind(room_id),
		CONNECT_DEFERRED
	)
	host.add_child(hitbox)

	vastum_token_nodes[room_id] = hitbox
	if is_instance_valid(visual):
		_create_vastum_outline(room_id, visual)

	return hitbox


func _refresh_vastum_token(room_id: String) -> void:
	_sync_room_vastum_visual(room_id)

	var existing = vastum_token_nodes.get(room_id, null)
	var visual = vastum_visual_nodes.get(room_id, null)
	var outline = vastum_outline_nodes.get(room_id, null)

	if not room_has_vastum(room_id):
		if is_instance_valid(existing):
			existing.queue_free()
		if is_instance_valid(outline):
			outline.queue_free()
		vastum_token_nodes.erase(room_id)
		vastum_visual_nodes.erase(room_id)
		vastum_outline_nodes.erase(room_id)
		return

	# Room rebuilds can replace the visual token. Recreate the transparent
	# click target/outline whenever either side becomes stale.
	if not is_instance_valid(existing) or not is_instance_valid(visual):
		if is_instance_valid(existing):
			existing.queue_free()
		if is_instance_valid(outline):
			outline.queue_free()
		vastum_token_nodes.erase(room_id)
		vastum_visual_nodes.erase(room_id)
		vastum_outline_nodes.erase(room_id)
		existing = _create_vastum_token(room_id)
		visual = vastum_visual_nodes.get(room_id, null)
		outline = vastum_outline_nodes.get(room_id, null)

	var selectable: bool = pending_lodge_effect_vastum_only \
		and pending_lodge_effect_room_tokens.has(room_id)
	var token_value: String = str(
		pending_lodge_effect_room_tokens.get(room_id, "")
	)
	var selected: bool = token_value in pending_lodge_effect_selected_tokens

	if is_instance_valid(existing):
		existing.mouse_filter = (
			Control.MOUSE_FILTER_STOP
			if selectable
			else Control.MOUSE_FILTER_IGNORE
		)

	if is_instance_valid(outline):
		outline.visible = selectable
		outline.modulate = (
			Color(0.35, 1.0, 0.35, 1.0)
			if selected
			else Color(1.0, 0.82, 0.25)
		)


func refresh_vastum_tokens() -> void:
	# Drop stale helper references first (Rooms can be rebuilt/recreated).
	for room_id_value in vastum_token_nodes.keys():
		var node = vastum_token_nodes.get(room_id_value, null)
		if not is_instance_valid(node):
			vastum_token_nodes.erase(room_id_value)

	for room_id_value in vastum_outline_nodes.keys():
		var node = vastum_outline_nodes.get(room_id_value, null)
		if not is_instance_valid(node):
			vastum_outline_nodes.erase(room_id_value)

	for room_id_value in vastum_visual_nodes.keys():
		var node = vastum_visual_nodes.get(room_id_value, null)
		if not is_instance_valid(node):
			vastum_visual_nodes.erase(room_id_value)

	for room_value in room_id_by_coord.values():
		_refresh_vastum_token(str(room_value))


func _on_vastum_token_pressed(room_id: String) -> void:
	# Vastum tokens are always real click targets. During a Vastum-specific
	# Effect choice the click resolves/toggles that choice directly.
	if pending_lodge_effect_vastum_only \
	and pending_lodge_effect_room_tokens.has(room_id):
		_on_direct_lodge_room_chosen(room_id)
		return

	var room = get_room_by_id(room_id)
	if room != null:
		print("Vastum in ", room.room_name, " (", room_id, ")")


func place_vastum(room_id: String) -> bool:
	var room = get_room_by_id(room_id)
	if room == null:
		return false

	# Chaos: one Vastum maximum per Room. A duplicate placement is ignored,
	# while the rest of the Effect still resolves.
	if room_has_vastum(room_id):
		_refresh_vastum_token(room_id)
		return true

	vastum_room_state[room_id] = true
	_refresh_vastum_token(room_id)
	print("Vastum placed in ", room_id)
	return true


func remove_vastum(room_id: String) -> bool:
	if get_room_by_id(room_id) == null:
		return false
	if not room_has_vastum(room_id):
		return false

	vastum_room_state.erase(room_id)
	_refresh_vastum_token(room_id)
	print("Vastum removed from ", room_id)
	return true


func get_vastum_room_ids() -> Array[String]:
	var result: Array[String] = []
	for room_value in room_id_by_coord.values():
		var room_id: String = str(room_value)
		if room_has_vastum(room_id):
			result.append(room_id)
	return result


func count_vastum() -> int:
	return get_vastum_room_ids().size()


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
	copy.avatar_command = spell.avatar_command.duplicate(true)

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

func get_playable_school_ids() -> Array[String]:
	var result: Array[String] = []
	for school_id in school_specialization_database:
		if is_school_complete(school_id):
			result.append(school_id)
	return result


func is_school_complete(school_id: String) -> bool:
	var data: Dictionary = school_specialization_database.get(school_id, {})
	if not bool(data.get("rules_implemented", false)):
		return false
	if ReferenceCardPreview.card_texture("schools", school_id) == null:
		return false
	var cards: Array[SpellCardState] = spell_database.get_school_spells(school_id)
	cards = cards.filter(func(card): return not card.personal and not card.forgotten)
	if cards.size() != 12:
		return false
	for card in cards:
		if SpellArtResolver.get_texture(card.id, school_id) == null:
			return false
		for dark in [false, true]:
			var side: Dictionary = card.get_side(dark)
			# Transformations can have an empty immediate Effect sequence; their
			# actions live in the authoritative transformation definition.
			if not side.has("effects") or not side.has("type") or not _school_material_available(side):
				return false
	var grimoires: Array = data.get("starting_grimoires", [])
	if grimoires.size() != 2:
		return false
	var starting_ids: Array[String] = []
	for grimoire in grimoires:
		var ids: Array = grimoire.get("spell_ids", [])
		if ids.size() != 6:
			return false
		for id in ids:
			if starting_ids.has(id) or not cards.has(spell_database.get_spell(id)):
				return false
			starting_ids.append(id)
	return true


func _school_material_available(value: Variant) -> bool:
	if value is Dictionary:
		if value.has("evocation_id"):
			var id: String = str(value.evocation_id)
			if evocation_database.get_evocation(id).is_empty() or ReferenceCardPreview.card_texture("evocations", id) == null:
				return false
		if value.get("type", "") in ["assign_upgrade", "assign_jinx"]:
			var kind: String = "upgrades" if value.type == "assign_upgrade" else "jinxes"
			var definitions: Array = ForgottenAttachments.database().get(kind, [])
			if value.has("id"):
				definitions = definitions.filter(func(item): return item.id == value.id)
			if definitions.is_empty():
				return false
			for item in definitions:
				if ReferenceCardPreview.card_texture("upgrades" if kind == "upgrades" else "jinxs", item.id) == null:
					return false
		for child in value.values():
			if not _school_material_available(child):
				return false
	elif value is Array:
		for child in value:
			if not _school_material_available(child):
				return false
	return true


func select_active_schools():
	active_school_ids.clear()
	# Incomplete schools stay in the database for development, outside the
	# match's authoritative Libraries and all setup/Study choices.
	var available_school_ids: Array[String] = get_playable_school_ids()


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
	# Neither Personal nor Forgotten cards can enter a School's discard pile.
	# Rulebook p.14; FAQ p.3; Codex p.60.
	if spell.forgotten:
		return remove_forgotten_from_game(spell)
	if spell.personal:
		print("Personal Spell removed from game: ", spell.card_name)
		return true


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

	apply_mage_forgotten_exclusions()
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

	if str(spell.light_side.get("type", "")) == "on_draw":
		resolve_drawn_forgotten(player_index, spell)
		return spell

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


func resolve_drawn_forgotten(player_index: int, spell: SpellCardState, companions: Array = []) -> void:
	for other in companions:
		if other != spell:
			players[player_index].hand.erase(other)
			remove_forgotten_from_game(other)
	remove_forgotten_from_game(spell)
	queue_resolution({"type": "spell_resolution", "spell": spell, "use_dark_side": false,
		"context": {"game": self, "caster_id": player_index, "drawn_forgotten": true,
			"caster_room_id": players[player_index].mage.room_id}})

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


func apply_mage_forgotten_exclusions() -> void:
	var excluded: Array = []
	for player in players:
		if mage_database.has_mage(player.mage_id):
			excluded.append_array(mage_database.get_mage_data(player.mage_id).get("excluded_forgotten_spell_ids", []))
	for spell in forgotten_deck.duplicate():
		if spell.id in excluded:
			forgotten_deck.erase(spell)
			remove_forgotten_from_game(spell)


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
	revealed: RevealedSpellState,
	replacement: SpellCardState,
	use_dark_side: bool = false
) -> bool:
	if player_index < 0 or player_index >= players.size() or revealed == null or replacement == null:
		return false
	var player = players[player_index]
	if not player.revealed_spells.has(revealed) or not player.hand.has(replacement):
		return false
	var slot_id := _find_player_board_slot_for_spell(player_index, revealed.spell)
	if slot_id == "":
		slot_id = revealed.slot_id
	if not slot_id in ["Q", "I", "II", "III"]:
		return false
	# Armory replaces the physical card in the same slot, ready and private.
	# Reuse ordinary preparation and discard state, including Forgotten removal.
	var prepared: bool = player.set_quick_spell(replacement, use_dark_side) if slot_id == "Q" else player.add_ready_spell(replacement, use_dark_side)
	if not prepared:
		return false
	player.revealed_spells.erase(revealed)
	for active in player.active_spells.duplicate():
		if active.spell == revealed.spell:
			active.active = false
			player.remove_active_spell(active)
	move_spell_to_memories_or_remove(player_index, revealed.spell)
	_set_player_board_spell_slot(player_index, slot_id, replacement, use_dark_side, "prepared")
	if slot_id != "Q":
		var ordered_slots := ["I", "II", "III"]
		player.ready_spells.sort_custom(func(a, b):
			return ordered_slots.find(_find_player_board_slot_for_spell(player_index, a.spell)) < ordered_slots.find(_find_player_board_slot_for_spell(player_index, b.spell)))
	_refresh_permanent_room_markers()
	refresh_player_board(player_index)
	print("Player ", player_index + 1, " discarded ", revealed.spell.card_name,
		" and readied ", replacement.card_name, " in ", slot_id)
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
	if AvatarRules.is_avatar(self, player_index): return false

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

	# The Crown is presentation state for the left player rail. PowerBoard
	# markers must not be touched when ownership changes. The shell refreshes
	# its banners from crown_owner_id.
	refresh_all_player_boards()
	return true

func activate_evocation(
	evocation: EvocationState,
	controller_id: int = -1,
	context: Dictionary = {},
	strength_bonus: int = 0
) -> bool:
	if evocation == null:
		return false

	if controller_id == -1 and evocation.assigned_mage < 0:
		controller_id = evocation.owner_id

	if controller_id < -1 or controller_id >= players.size() or not ForgottenEvocations.can_activate(self, evocation):
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
	var was_in_cell: bool = mage.in_cell

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

	if not was_in_cell:
		var event := GameEvent.new("mage_placed_in_cell")
		event.source_model_type = "mage"
		event.source_player_index = player_index
		event.target_player_index = player_index
		queue_resolution({"type": "game_event", "event": event})
	return true

func place_instability(
	owner_id: int,
	room_id: String,
	amount: int = 1
) -> int:

	amount = ForgottenAttachments.reduce_instability(self, owner_id, room_id, amount)
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
			AvatarRules.cube_owner(self, owner_id)
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
		active_effect_context["effect_target_room_id"] = room_id
		active_effect_context["effect_instability_placed"] = (
			int(active_effect_context.get("effect_instability_placed", 0))
			+ placed
		)


	if placed > 0:
		var placement := GameEvent.new("instability_placed")
		placement.source_player_index = owner_id
		placement.source_room_id = room_id
		placement.amount = placed
		placement.data["no_instability_echo"] = bool(active_effect_context.get("no_instability_echo", false))
		queue_resolution({"type": "game_event", "event": placement})

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


	if placed > 0 and owner_id >= 0 and placed == available_slots:
		var event := GameEvent.new("last_instability_placed")
		event.source_model_type = "mage"
		event.source_player_index = owner_id
		event.source_room_id = players[owner_id].mage.room_id
		event.target_room_id = room_id
		event.amount = placed
		queue_resolution({"type": "game_event", "event": event})
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

	current_phase_play_order = AvatarRules.human_order(self)

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
		players.size() - (2 if avatar != null else 1)
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
		AvatarRules.human_order(self)
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


	# The phase entry is resumable: Events, then Feral Magic / normal draws,
	# then the existing interactive (or online parallel) Library study.
	study_phase_cursor = 0
	study_drawn_cards.clear()
	study_parallel_active = false
	study_parallel_drawn_cards.clear()
	study_parallel_requests.clear()
	return queue_resolution({"type": "druidic_study", "order": current_phase_play_order.duplicate(),
		"index": 0, "context": {}, "phase_context": phase_context, "on_complete": "advance_study_phase"})


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


	for i in ready_spells_to_prepare.size():
		if not ready_spells_to_prepare[i].is_playable_side(bool(ready_dark_sides[i])):
			return false
	if quick_spell_to_prepare != null and not quick_spell_to_prepare.is_playable_side(quick_dark_side):
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
		AvatarRules.human_order(self)
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

	if _use_parallel_online_preparation():
		return _begin_parallel_preparation()

	return advance_preparation_phase()

func player_has_available_action(
	player_index: int
) -> bool:
	if AvatarRules.is_avatar(self, player_index): return avatar.can_activate()
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
				and player.get_mage_speed() > 0
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
		"equipment":
			return EquipmentRules.perform(self, player_index, str(action.get("evocation_id", "")), str(action.get("action_id", "")))
		"spell_physical":
			return EquipmentRules.perform_spell_action(self, player_index, str(action.get("spell_id", "")), str(action.get("action_id", "")))
		"transformation":
			return DruidicRules.perform_action(self, player_index, str(action.get("action_id", "")))
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


	if avatar != null: avatar.commands_used = 0
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

	evocation_phase_cursor = 0
	evocation_phase_activated.clear()
	return queue_resolution({"type": "druidic_phase_start", "order": current_phase_play_order.duplicate(),
		"index": 0, "context": {}, "phase_context": phase_context, "on_complete": "advance_evocation_phase"})


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
	_clear_direct_lodge_effect_choice()
	_hide_chaos_wildcard_overlay()

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
	if str(context.get("resolver_kind", "")) == "quest" and value is Dictionary and bool(value.get("quest_dummy_target", false)):
		context[context_key] = null
		context["target_is_dummy"] = true

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


func _effect_choice_uses_direct_lodge(
	choice_kind: String,
	public_options: Array
) -> bool:
	if not choice_kind in [
		"vastum_room",
		"remove_vastum",
		"chaos_room",
		"vastum_destination",
		"movement_destination",
		"construct_room",
		"secondary_room",
		"distinct_summon_rooms",
		"evocation_ability_room"
	]:
		return false
	if public_options.is_empty():
		return false
	for option_value in public_options:
		if not option_value is Dictionary:
			return false
		var room_id: String = str(option_value.get("room_id", ""))
		if room_id == "" or not is_lodge_room_id(room_id):
			return false
	return true


func _effect_choice_uses_vastum_tokens(choice_kind: String) -> bool:
	return choice_kind in [
		"remove_vastum",
		"chaos_room"
	]


func _clear_direct_lodge_effect_choice() -> void:
	pending_lodge_effect_room_tokens.clear()
	pending_lodge_effect_selected_tokens.clear()
	pending_lodge_effect_player_index = -1
	pending_lodge_effect_min_select = 0
	pending_lodge_effect_max_select = 0
	pending_lodge_effect_vastum_only = false
	refresh_vastum_tokens()


func _show_direct_lodge_effect_choice(
	player_index: int,
	choice_kind: String,
	public_options: Array,
	min_select: int,
	max_select: int
) -> void:
	pending_lodge_effect_room_tokens.clear()
	pending_lodge_effect_selected_tokens.clear()
	pending_lodge_effect_player_index = player_index
	pending_lodge_effect_min_select = min_select
	pending_lodge_effect_max_select = max_select
	pending_lodge_effect_vastum_only = _effect_choice_uses_vastum_tokens(choice_kind)

	var callbacks: Dictionary = {}
	for option_value in public_options:
		var option: Dictionary = option_value
		var room_id: String = str(option.get("room_id", ""))
		var token: String = str(option.get("token", ""))
		if room_id == "" or token == "":
			continue
		pending_lodge_effect_room_tokens[room_id] = token
		if not pending_lodge_effect_vastum_only:
			callbacks[room_id] = _on_direct_lodge_room_chosen.bind(room_id)

	if pending_lodge_effect_vastum_only:
		clear_lodge_room_choices()
		refresh_vastum_tokens()
	else:
		show_lodge_room_choices(callbacks, [])


func _on_direct_lodge_room_chosen(room_id: String) -> void:
	if not waiting_for_player_input \
	or str(pending_input.get("type", "")) != "effect_choice":
		return
	if pending_lodge_effect_player_index < 0 \
	or not pending_lodge_effect_room_tokens.has(room_id):
		return

	var token: String = str(pending_lodge_effect_room_tokens[room_id])
	if pending_lodge_effect_max_select <= 1:
		submit_beta_input(
			pending_lodge_effect_player_index,
			{"selection": token}
		)
		return

	if token in pending_lodge_effect_selected_tokens:
		pending_lodge_effect_selected_tokens.erase(token)
	else:
		if pending_lodge_effect_selected_tokens.size() >= pending_lodge_effect_max_select:
			return
		pending_lodge_effect_selected_tokens.append(token)

	refresh_vastum_tokens()
	if not pending_lodge_effect_vastum_only:
		var selected_rooms: Array[String] = []
		for selected_token in pending_lodge_effect_selected_tokens:
			for candidate_room in pending_lodge_effect_room_tokens:
				if str(pending_lodge_effect_room_tokens[candidate_room]) == selected_token:
					selected_rooms.append(str(candidate_room))
		var callbacks: Dictionary = {}
		for candidate_room in pending_lodge_effect_room_tokens:
			callbacks[str(candidate_room)] = _on_direct_lodge_room_chosen.bind(str(candidate_room))
		show_lodge_room_choices(callbacks, selected_rooms)

	# Chaos removals use an exact number of tokens, so reaching that number is
	# an unambiguous confirmation and keeps the interaction entirely on-board.
	if pending_lodge_effect_min_select == pending_lodge_effect_max_select \
	and pending_lodge_effect_selected_tokens.size() == pending_lodge_effect_max_select:
		submit_beta_input(
			pending_lodge_effect_player_index,
			{"selection": pending_lodge_effect_selected_tokens.duplicate()}
		)


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
	if AvatarRules.is_avatar(self, player_index):
		player_index = crown_owner_id
		prompt = "Choice of the Crown · " + prompt
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
		if token.begins_with("evocation_type:") or token.begins_with("evocation_deck:"):
			public_option["card_kind"] = "evocations"
		elif token.begins_with("school:") or option.has("school_id"):
			public_option["card_kind"] = "schools"
			public_option["id"] = str(option.get("school_id", value))
		if value is EventCardState:
			public_option["card_kind"] = "events"
			public_option["id"] = value.id
		var choice_spell = value.spell if value is RevealedSpellState or value is ReadySpellState else value
		if choice_spell is SpellCardState:
			public_option["card_kind"] = "spells"
			public_option["id"] = choice_spell.id
			public_option["board_player_index"] = player_index
			public_option["slot_id"] = _find_player_board_slot_for_spell(player_index, choice_spell)
		var choice_quest = value.get("quest") if value is Dictionary else value
		if choice_quest is QuestState:
			public_option["card_kind"] = "quests"
			public_option["id"] = choice_quest.get_id()
			public_option["board_player_index"] = player_index
			public_option["quest_section"] = "solved" if choice_quest.solved else ("completed" if choice_quest.completed else "active")
			public_option["quest_index"] = (players[player_index].completed_quests if choice_quest.completed else players[player_index].active_quests).find(choice_quest)
		var evocation = value if value is EvocationState else (value.get("evocation") if value is Dictionary else null)
		if evocation is EvocationState:
			var address_owner: int = evocation.assigned_mage if evocation.assigned_mage >= 0 else evocation.owner_id
			public_option["owner_id"] = address_owner
			public_option["evocation_index"] = players[address_owner].evocations.find(evocation)
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
			if token.begins_with("instability:"):
				public_option["cube_room_id"] = str(context.get("target_room_id", ""))
			public_option["cube_player_index"] = int(option.get("cube_player_index", context.get("target_player_index", player_index)))
			var target_evocation = context.get("target_evocation")
			if target_evocation is EvocationState:
				var address_owner: int = target_evocation.assigned_mage if target_evocation.assigned_mage >= 0 else target_evocation.owner_id
				public_option["cube_evocation_owner"] = address_owner
				public_option["cube_evocation_index"] = players[address_owner].evocations.find(target_evocation)
		public_options.append(public_option)

	if public_options.is_empty():
		return false

	pending_effect_choice_context = context
	pending_effect_choice_values = runtime_values
	var movement_origin: String = str(context.get("movement_origin_room_id", ""))
	if choice_kind == "evocation_activation_plan" and context.get("evocation") is EvocationState:
		movement_origin = str(context.evocation.room_id)

	var direct_lodge: bool = _effect_choice_uses_direct_lodge(
		choice_kind,
		public_options
	)
	var request_options: Array = [] if direct_lodge else public_options
	var request: Dictionary = {
		"type": "effect_choice",
		"phase": current_phase,
		"player_index": player_index,
		"choice_kind": choice_kind,
		"context_key": context_key,
		"movement_origin_room_id": movement_origin,
		"prompt": prompt,
		"min_select": min_select,
		"max_select": max_select,
		"board_only": direct_lodge,
		# board_options remain serializable for online/state projection, while
		# options stays empty so the standard text-choice menu does not open.
		"board_options": public_options if direct_lodge else [],
		"options": request_options
	}

	var requested: bool = request_player_input(request)
	if requested and direct_lodge:
		_show_direct_lodge_effect_choice(
			player_index, choice_kind, public_options, min_select, max_select
		)
	elif requested and choice_kind == "chaos_all_element":
		_show_chaos_wildcard_overlay(
			player_index,
			public_options
		)
	return requested


func _hide_chaos_wildcard_overlay() -> void:
	if is_instance_valid(chaos_wildcard_choice_layer):
		chaos_wildcard_choice_layer.queue_free()
	chaos_wildcard_choice_layer = null


func _on_chaos_wildcard_choice_pressed(
	player_index: int,
	token: String
) -> void:
	if token == "":
		return
	submit_beta_input(
		player_index,
		{"selection": token}
	)


func _show_chaos_wildcard_overlay(
	player_index: int,
	public_options: Array
) -> void:
	_hide_chaos_wildcard_overlay()

	if public_options.is_empty():
		return

	chaos_wildcard_choice_layer = CanvasLayer.new()
	chaos_wildcard_choice_layer.name = "ChaosWildcardChoiceLayer"
	chaos_wildcard_choice_layer.layer = 1250
	add_child(chaos_wildcard_choice_layer)

	var blocker := ColorRect.new()
	blocker.color = Color(0.0, 0.0, 0.0, 0.72)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	chaos_wildcard_choice_layer.add_child(blocker)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 310.0)
	panel.position = (
		get_viewport_rect().size * 0.5
		- panel.custom_minimum_size * 0.5
	)
	blocker.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var title := Label.new()
	title.text = "CHAOS — WILDCARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var prompt := Label.new()
	prompt.text = "Choose which Chaos effect to resolve in the selected Vastum Room."
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(prompt)

	for option_value in public_options:
		if not option_value is Dictionary:
			continue

		var option: Dictionary = option_value
		var token: String = str(option.get("token", ""))
		if token == "":
			continue

		var button := Button.new()
		button.text = str(
			option.get(
				"name",
				option.get("label", token)
			)
		)
		button.custom_minimum_size = Vector2(0.0, 52.0)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(
			_on_chaos_wildcard_choice_pressed.bind(
				player_index,
				token
			),
			CONNECT_DEFERRED
		)
		box.add_child(button)


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
		if bool(effect.get("_spell_range", false)): in_range = ForgottenPassives.spell_room_in_range(self, caster_id, room_id, range_value)
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
		if player_index == caster_id and not bool(effect.get("include_self", false)):
			continue

		var mage = players[player_index].mage
		if mage == null or mage.in_cell:
			continue
		if int(effect.get("min_target_nightmares", 0)) > SchoolEffects.nightmare_count(self, player_index):
			continue

		var in_range: bool = ForgottenPassives.spell_room_in_range(self, caster_id, mage.room_id, range_value) if bool(effect.get("_spell_range", false)) else _quest_effect_room_in_range(caster_id, mage.room_id, range_value)
		if not in_range:
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

	var max_health: int = int(effect.get("target_max_health", effect.get("max_health", -1)))

	for owner_index in range(players.size()):
		if owner_filter != -999999 and owner_index != owner_filter:
			continue

		var evocations: Array[EvocationState] = players[owner_index].evocations

		for evocation_index in range(evocations.size()):
			var evocation: EvocationState = evocations[evocation_index]

			if evocation == null or evocation.is_defeated():
				continue
			if not EquipmentRules.can_target_as(evocation, caster_id, str(effect.get("target", "evocation"))):
				continue

			if archetype_filter != "" \
			and evocation.archetype != archetype_filter:
				continue

			if max_health >= 0 and evocation.health > max_health:
				continue
			if effect.has("target_evocation_id") and evocation.evocation_id != str(effect.target_evocation_id):
				continue

			var in_range: bool = ForgottenPassives.spell_room_in_range(self, caster_id, evocation.room_id, range_value) if bool(effect.get("_spell_range", false)) else _quest_effect_room_in_range(caster_id, evocation.room_id, range_value)
			if not in_range:
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
		if not EquipmentRules.can_target_as(evocation, caster_id, "model"):
			continue

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
	# The offered cards and the resolver must apply the same Element filter.
	return effect_resolver._side_has_any_element(side, required_elements)


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

	var only_value = options[0].get("value")
	var selects_quest: bool = only_value is QuestState or (only_value is Dictionary and only_value.get("quest") is QuestState)
	var selects_evocation: bool = only_value is EvocationState
	if options.size() == 1 and not confirm_single and not selects_quest and not selects_evocation:
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
		var options: Array = _quest_evocation_choice_options(caster_id, effect)
		# Rulebook pp.26–27: a model-target Effect may use the Dummy Target.
		# It has no owner/archetype and cannot pay a removal cost.
		if str(effect.get("target_owner", "")) == "" and str(effect.get("target_archetype", effect.get("evocation_archetype", ""))) == "" and str(effect.get("type", "")) != "activate_owned_evocation":
			options.append({"token": "quest_dummy", "value": {"quest_dummy_target": true}, "name": "Dummy target — no Evocation removed", "target_type": "dummy"})

		return _quest_request_single_choice(
			caster_id,
			"target_evocation",
			context,
			context_key,
			options,
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
		if bool(data.get("forgotten", false)):
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

			for cube_index in range(room.instability_cubes.size()):
				var owner_id: int = int(room.instability_cubes[cube_index])
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
					"value": {"owner_id": owner_id, "cube_index": cube_index},
					"owner_id": owner_id,
					"owner_name": owner_name,
					# Keep instability selection on the Lodge. Without this address
					# the generic board-target projection cannot find the physical
					# cube and may fall back to unrelated PlayerBoard UI.
					"cube_room_id": room_id
				})

			if options.size() <= max_convert:
				var selected_owners: Array = []
				for option_value in options:
					var option: Dictionary = option_value
					selected_owners.append(
						option.get("value")
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

				if str(spell.light_side.get("type", "")) == "on_draw":
					context["selected_forgotten_spell"] = spell
					return true
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
	if bool(context.get("target_is_dummy", false)):
		return true
	# Low-level EffectResolver uses spell_target_type as the generic target-kind
	# field. Quest Effects have their target printed on each sentence, so project
	# it into the shared runtime context before asking for the concrete target.
	# Without this, Room-target Quest Effects select a Room correctly but reach
	# the Effect resolver with an empty target type.
	var target_type: String = str(effect.get("target", ""))
	if target_type != "":
		context["spell_target_type"] = target_type
	else:
		context.erase("spell_target_type")

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
	return (trigger is Dictionary and not trigger.is_empty()) or not side.get("passives", {}).is_empty()


func _queue_spell_effect_resolved_event(
	player_index: int,
	spell: SpellCardState,
	spell_type: String,
	room_id: String
) -> void:
	if player_index < 0 or player_index >= players.size() or spell == null:
		return

	var event := GameEvent.new(
		"spell_effect_resolved",
		{
			"spell_id": spell.id,
			"spell_type": spell_type
		}
	)
	event.action_type = "spell"
	event.source_model_type = "mage"
	event.source_player_index = player_index
	event.source_room_id = room_id
	queue_resolution({"type": "game_event", "event": event})


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
		if evocation.archetype == "equipment" and evocation.owner_id != caster_id:
			continue
		if side.get("effects", []).any(func(effect): return effect.get("type") == "assign_upgrade") and not ForgottenAttachments.can_receive_upgrade(self, evocation):
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
	side = side.duplicate()
	side["target"] = "model"
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
	side = side.duplicate(true)
	side["_spell_range"] = true
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

	if bool(side.get("defer_primary_target", false)):
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
	ForgottenPassives.prepare_context(self, context)
	var new_owner: int = int(effect.get("converter_owner_id", -1)) if mode == "convert_damage_on_caster" else caster

	# A Room-target Convert is one Effect with one global amount, not `amount`
	# per Model in the Room.  Present every eligible Damage cube together so the
	# player can choose, including Black Rose/opponent Damage on their own Mage or
	# Evocations.  The rules explicitly allow converting Damage on your own models.
	if mode == "convert_damage" and target_type == "room":
		var room_id: String = str(context.get("target_room_id", ""))
		if room_id == "":
			return true
		var room_key: String = "convert_room:" + room_id
		if context.has(room_key):
			return true
		var room_options: Array = []
		for player_index in range(players.size()):
			var mage = players[player_index].mage
			if mage != null and not mage.in_cell and mage.room_id == room_id and not DeathEffectResolver.ignores(context, player_index):
				var occurrences: Dictionary = {}
				for cube_index in range(mage.damage_cubes.size()):
					var owner: int = int(mage.damage_cubes[cube_index])
					var ordinal: int = int(occurrences.get(owner, 0))
					occurrences[owner] = ordinal + 1
					if owner == new_owner:
						continue
					room_options.append({
						"token": "damage:mage:%d:%d:%d" % [player_index, owner, ordinal],
						"value": {"model_type": "mage", "player_index": player_index, "owner_id": owner, "cube_index": cube_index},
						"cube_player_index": player_index,
						"owner_id": owner,
						"name": "Damage on Player %d" % (player_index + 1)
					})
			for evocation_index in range(players[player_index].evocations.size()):
				var evocation: EvocationState = players[player_index].evocations[evocation_index]
				if evocation == null or evocation.is_defeated() or evocation.room_id != room_id or (str(context.get("resolver_kind", "spell")) == "spell" and not ForgottenEvocations.ability(self, evocation, "ignore_spell_effects").is_empty()):
					continue
				var ev_occurrences: Dictionary = {}
				for cube_index in range(evocation.damage_cubes.size()):
					var owner: int = int(evocation.damage_cubes[cube_index])
					var ordinal: int = int(ev_occurrences.get(owner, 0))
					ev_occurrences[owner] = ordinal + 1
					if owner == new_owner:
						continue
					room_options.append({
						"token": "damage:evocation:%d:%d:%d:%d" % [player_index, evocation_index, owner, ordinal],
						"value": {"model_type": "evocation", "owner_index": player_index, "evocation_index": evocation_index, "owner_id": owner, "cube_index": cube_index},
						"cube_evocation_owner": player_index,
						"cube_evocation_index": evocation_index,
						"owner_id": owner,
						"name": "Damage on " + evocation.get_display_name()
					})
		var room_amount: int = mini(int(effect.get("amount", 0)), room_options.size())
		room_amount = mini(room_amount, players[caster].available_cubes)
		if room_amount <= 0:
			return true
		request_effect_choice(
			caster, "convert_damage_cubes", context, room_key, room_options,
			room_amount, room_amount,
			"Choose %d Damage cube%s in the target Room to convert." % [room_amount, "" if room_amount == 1 else "s"]
		)
		return false

	var models: Array = []
	for i in range(players.size()):
		var mage = players[i].mage
		var include := false
		if DeathEffectResolver.ignores(context, i):
			continue
		if mode == "convert_damage_on_caster":
			include = i == caster
		elif i != caster:
			if mode == "convert_damage_each_other_mage":
				include = i != int(context.get("target_player_index", -1)) and not mage.in_cell
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
			if target_type == "evocation" and context.get("target_evocation") == evocation:
				models.append({"key": "evocation:%d" % evocation.get_instance_id(), "cubes": evocation.damage_cubes, "cube_evocation_owner": i, "cube_evocation_index": j})
	for model in models:
		var key: String = "convert_" + str(model.key)
		if context.has(key):
			continue
		var options: Array = []
		var occurrences: Dictionary = {}
		for cube_index in range(model.cubes.size()):
			var owner: int = int(model.cubes[cube_index])
			var ordinal: int = int(occurrences.get(owner, 0))
			occurrences[owner] = ordinal + 1
			if int(owner) == new_owner:
				continue
			var option: Dictionary = model.duplicate()
			option.erase("cubes")
			option.erase("key")
			option.merge({"token": "damage:%d:%d" % [owner, ordinal], "value": {"owner_id": owner, "cube_index": cube_index}})
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
	if str(effect.get("type", "")) in DeathEffectResolver.TYPES:
		return DeathEffectResolver.prepare(self, effect, context)
	var caster_id: int = int(
		context.get("caster_id", -1)
	)

	if caster_id < 0 or caster_id >= players.size():
		return true

	var effect_type: String = str(
		effect.get("type", "")
	)

	match effect_type:
		"place_instability":
			if str(context.get("resolver_kind", "")) != "evocation" \
			or str(effect.get("target", "")) != "room":
				return true

			if str(context.get("target_room_id", "")) != "":
				return true

			var source_evocation = context.get("source_evocation", null)
			var origin_room_id: String = ""

			if source_evocation is EvocationState:
				origin_room_id = str(source_evocation.room_id)

			var options: Array = _quest_room_choice_options(
				caster_id,
				effect,
				origin_room_id
			)

			return _quest_request_single_choice(
				caster_id,
				"evocation_ability_room",
				context,
				"target_room_id",
				options,
				"Choose the Room for "
				+ (source_evocation.get_display_name() if source_evocation is EvocationState else "the Evocation")
				+ "'s ability.",
				true
			)

		"heal", "convert_instability", "complete_owned_quest_choice":
			return _prepare_quest_special_choice(effect, context)
		"activate_room_from_owned_evocation":
			var selected_room: String = str(context.get("target_room_id", ""))
			if selected_room != "" and _spell_room_target_allowed(caster_id, {"effects": [effect]}, selected_room):
				return true
			context.erase("target_room_id")
			var options := _spell_room_target_options(caster_id, {"range": "*", "effects": [effect]})
			for option in options:
				option["value"] = option.room_id
			# Even a single eligible Room is confirmed on the Lodge, so activation
			# and the subsequent Room-effect target are visibly separate choices.
			return _quest_request_single_choice(caster_id, "construct_room", context,
				"target_room_id", options, "Choose the Room to activate from a Construct.", true)
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
		"complete_owned_quest_choice":
			keys_to_clear = ["selected_active_quest"]
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
	return queue_resolution({"type": "forgotten_activation_start", "player_index": player_index,
		"on_complete": "continue_action_activation"})


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

	for option in options:
		var action: Dictionary = option.get("action", {})
		if str(action.get("type", "")) == "momentum":
			var ready = players[player_index].quick_spell if bool(action.get("use_quick", false)) else null
			var index: int = int(action.get("ready_index", -1))
			if ready == null and index >= 0 and index < players[player_index].ready_spells.size():
				ready = players[player_index].ready_spells[index]
			if ready != null:
				option["board_player_index"] = player_index
				option["slot_id"] = _find_player_board_slot_for_spell(player_index, ready.spell)
				option["spell_id"] = ready.spell.id
		elif str(option.get("kind", "")) == "quest":
			option["board_player_index"] = player_index
			option["quest_section"] = "completed"
			option["quest_index"] = int(action.get("quest_index", -1))

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
		if AvatarRules.is_avatar(self, player_index):
			if avatar.can_activate(): return AvatarRules.begin_activation(self)
			continue


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

func _use_parallel_online_preparation() -> bool:
	return network_session != null and not network_client and players.size() > 1


func _make_parallel_preparation_request(player_index: int) -> Dictionary:
	var hand_data: Array = []
	for hand_index in range(players[player_index].hand.size()):
		var spell: SpellCardState = players[player_index].hand[hand_index]
		if spell == null:
			continue
		hand_data.append({
			"hand_index": hand_index,
			"id": spell.id,
			"name": spell.card_name,
			"school_id": spell.school_id
		})
	return {
		"type": "preparation",
		"phase": PHASE_PREPARATION,
		"player_index": player_index,
		"min_spells": 2,
		"max_spells": 4,
		"max_numbered_spells": 3,
		"quick_allowed": true,
		"hand": hand_data
	}


func _begin_parallel_preparation() -> bool:
	preparation_parallel_requests.clear()
	for player_index in current_phase_play_order:
		preparation_parallel_requests[player_index] = _make_parallel_preparation_request(player_index)
	preparation_parallel_active = true
	pending_input = {
		"type": "preparation_parallel",
		"phase": PHASE_PREPARATION,
		"player_index": -1,
		"private": true
	}
	waiting_for_player_input = true
	input_revision += 1
	refresh_all_player_boards()
	var viewer: int = get_ui_viewer_player_index()
	if preparation_parallel_requests.has(viewer):
		player_input_requested.emit(preparation_parallel_requests[viewer].duplicate(true))
	if network_session != null:
		network_session.call_deferred("publish")
	return true


func _submit_parallel_preparation(player_index: int, payload: Dictionary) -> bool:
	if not preparation_parallel_requests.has(player_index):
		return false
	if str(payload.get("_request_type", "")) != "preparation":
		return false
	var request: Dictionary = preparation_parallel_requests[player_index]
	if not prepare_player_spells(
		player_index,
		payload.get("ready_hand_indices", []),
		payload.get("ready_dark_sides", []),
		int(payload.get("quick_hand_index", -1)),
		bool(payload.get("quick_dark_side", false))
	):
		return false
	preparation_parallel_requests.erase(player_index)
	if player_index == get_ui_viewer_player_index():
		player_input_resolved.emit(request.duplicate(true))
	refresh_all_player_boards()
	if network_session != null:
		network_session.call_deferred("publish")
	if not preparation_parallel_requests.is_empty():
		return true
	preparation_parallel_active = false
	pending_input.clear()
	waiting_for_player_input = false
	return finish_preparation_phase()


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

	if study_parallel_active:
		return true


	# =====================================================
	# ALL PLAYERS HAVE DRAWN / COMPLETED STUDY
	# =====================================================

	if study_phase_cursor \
	>= current_phase_play_order.size():

		if _use_parallel_online_study() \
		and study_parallel_drawn_cards.size() == current_phase_play_order.size():
			return _begin_parallel_study_post_draw()

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

	if _use_parallel_online_study():
		# Keep each player's four physical draws private on the host until all
		# players have drawn. Only then do the post-draw choices open together.
		study_parallel_drawn_cards[player_index] = study_drawn_cards.duplicate()
		study_drawn_cards.clear()
		clear_player_input()
		study_phase_cursor += 1
		return advance_study_phase()

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
		) and not spell.forgotten and not spell.personal:

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

		"min_select":
			discard_count,

		"max_select":
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
func _use_parallel_online_study() -> bool:
	return network_session != null and not network_client and players.size() > 1


func _make_parallel_study_keep_request(player_index: int) -> Dictionary:
	var drawn: Array = study_parallel_drawn_cards.get(player_index, [])
	var card_data: Array = []
	for i in range(drawn.size()):
		var spell: SpellCardState = drawn[i]
		card_data.append({
			"draw_index": i,
			"id": spell.id,
			"name": spell.card_name,
			"school_id": spell.school_id
		})
	return {
		"type": "study_keep_cards",
		"phase": PHASE_STUDY,
		"player_index": player_index,
		"keep_count": 2,
		"cards": card_data
	}


func _make_parallel_study_optional_request(player_index: int) -> Dictionary:
	var hand_data: Array = []
	for i in range(players[player_index].hand.size()):
		var spell: SpellCardState = players[player_index].hand[i]
		hand_data.append({
			"hand_index": i,
			"id": spell.id,
			"name": spell.card_name,
			"school_id": spell.school_id
		})
	return {
		"type": "study_optional_discard",
		"phase": PHASE_STUDY,
		"player_index": player_index,
		"optional": true,
		"max_discard": 1,
		"hand": hand_data
	}


func _make_parallel_study_hand_limit_request(player_index: int, discard_count: int) -> Dictionary:
	var hand_data: Array = []
	for i in range(players[player_index].hand.size()):
		var spell: SpellCardState = players[player_index].hand[i]
		hand_data.append({
			"hand_index": i,
			"id": spell.id,
			"name": spell.card_name,
			"school_id": spell.school_id
		})
	return {
		"type": "study_hand_limit",
		"phase": PHASE_STUDY,
		"player_index": player_index,
		"discard_count": discard_count,
		"min_select": discard_count,
		"max_select": discard_count,
		"hand": hand_data
	}


func _begin_parallel_study_post_draw() -> bool:
	if not _use_parallel_online_study() or study_parallel_active:
		return false

	study_parallel_requests.clear()
	for player_index in current_phase_play_order:
		var drawn: Array = study_parallel_drawn_cards.get(player_index, [])
		if drawn.size() != 4:
			print("Study parallel: expected 4 drawn cards for Player ", player_index + 1)
			return false
		study_parallel_requests[player_index] = _make_parallel_study_keep_request(player_index)

	study_parallel_active = true
	pending_input = {
		"type": "study_parallel",
		"phase": PHASE_STUDY,
		"player_index": -1,
		"private": true
	}
	waiting_for_player_input = true
	input_revision += 1
	refresh_all_player_boards()

	var viewer: int = get_ui_viewer_player_index()
	if study_parallel_requests.has(viewer):
		var viewer_request: Dictionary = study_parallel_requests[viewer]
		player_input_requested.emit(viewer_request.duplicate(true))
	if network_session != null:
		network_session.call_deferred("publish")
	return true


func _set_parallel_study_request(player_index: int, request: Dictionary) -> void:
	var previous: Dictionary = {}
	if study_parallel_requests.has(player_index):
		var stored_previous: Dictionary = study_parallel_requests[player_index]
		previous = stored_previous.duplicate(true)
	study_parallel_requests[player_index] = request.duplicate(true)
	refresh_all_player_boards()

	if player_index == get_ui_viewer_player_index():
		if not previous.is_empty():
			player_input_resolved.emit(previous)
		player_input_requested.emit(request.duplicate(true))
	if network_session != null:
		network_session.call_deferred("publish")


func _submit_parallel_study_input(player_index: int, payload: Dictionary) -> bool:
	if not study_parallel_requests.has(player_index):
		return false
	var request: Dictionary = study_parallel_requests[player_index]
	var request_type: String = str(request.get("type", ""))
	# Global input_revision stays stable while different players advance at their
	# own pace. Tag each wire submission with the private stage it answered so a
	# delayed Keep packet cannot accidentally become an Optional Discard skip.
	if str(payload.get("_request_type", "")) != request_type:
		return false
	match request_type:
		"study_keep_cards":
			return _submit_parallel_study_keep(player_index, payload.get("keep_indices", []))
		"study_optional_discard":
			return _submit_parallel_study_optional_discard(player_index, int(payload.get("hand_index", -1)))
		"study_hand_limit":
			return _submit_parallel_study_hand_limit(player_index, payload.get("hand_indices", []))
	return false


func _submit_parallel_study_keep(player_index: int, keep_indices: Array) -> bool:
	var drawn: Array = study_parallel_drawn_cards.get(player_index, [])
	if drawn.size() != 4 or keep_indices.size() != 2:
		return false
	var first_index: int = int(keep_indices[0])
	var second_index: int = int(keep_indices[1])
	if first_index < 0 or first_index >= 4 or second_index < 0 or second_index >= 4 or first_index == second_index:
		return false

	var player = players[player_index]
	for i in range(drawn.size()):
		var spell: SpellCardState = drawn[i]
		if i == first_index or i == second_index:
			player.add_spell_to_hand(spell)
		else:
			if not discard_to_school(spell.school_id, spell):
				return false
	study_parallel_drawn_cards[player_index] = []
	_set_parallel_study_request(player_index, _make_parallel_study_optional_request(player_index))
	return true


func _submit_parallel_study_optional_discard(player_index: int, hand_index: int = -1) -> bool:
	var player = players[player_index]
	if hand_index != -1:
		if hand_index < 0 or hand_index >= player.hand.size():
			return false
		var spell: SpellCardState = player.hand[hand_index]
		if not is_school_active(spell.school_id) and not spell.forgotten and not spell.personal:
			return false
		player.hand.remove_at(hand_index)
		if not discard_to_school(spell.school_id, spell):
			player.hand.insert(hand_index, spell)
			return false

	var excess: int = player.get_hand_size() - player.get_hand_limit()
	if excess > 0:
		_set_parallel_study_request(player_index, _make_parallel_study_hand_limit_request(player_index, excess))
		return true
	return _complete_parallel_player_study(player_index)


func _submit_parallel_study_hand_limit(player_index: int, hand_indices: Array) -> bool:
	var request: Dictionary = study_parallel_requests.get(player_index, {})
	var required_count: int = int(request.get("discard_count", 0))
	if hand_indices.size() != required_count:
		return false

	var player = players[player_index]
	var validated_indices: Array[int] = []
	for value in hand_indices:
		var hand_index: int = int(value)
		if hand_index < 0 or hand_index >= player.hand.size() or validated_indices.has(hand_index):
			return false
		validated_indices.append(hand_index)
	validated_indices.sort()
	validated_indices.reverse()
	for hand_index in validated_indices:
		var spell: SpellCardState = player.hand[hand_index]
		player.hand.remove_at(hand_index)
		move_spell_to_memories_or_remove(player_index, spell)
	return _complete_parallel_player_study(player_index)


func _complete_parallel_player_study(player_index: int) -> bool:
	if players[player_index].get_hand_size() > players[player_index].get_hand_limit():
		return false
	var resolved_request: Dictionary = {}
	if study_parallel_requests.has(player_index):
		var stored_request: Dictionary = study_parallel_requests[player_index]
		resolved_request = stored_request.duplicate(true)
	study_parallel_requests.erase(player_index)

	print("Player ", player_index + 1, " completed simultaneous Study | Hand: ", players[player_index].get_hand_size())

	if player_index == get_ui_viewer_player_index() and not resolved_request.is_empty():
		player_input_resolved.emit(resolved_request)
	if network_session != null:
		network_session.call_deferred("publish")

	if not study_parallel_requests.is_empty():
		return true

	study_parallel_active = false
	study_parallel_drawn_cards.clear()
	pending_input.clear()
	waiting_for_player_input = false
	refresh_all_player_boards()
	return finish_study_phase()


func finish_study_phase() -> bool:
	if current_phase != PHASE_STUDY or waiting_for_player_input:
		return false

	study_phase_cursor = 0
	study_drawn_cards.clear()
	study_parallel_active = false
	study_parallel_drawn_cards.clear()
	study_parallel_requests.clear()
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
		var room = get_room_by_id(mage.room_id)
		var room_color: String = "" if room == null else str(room.get_room_data().get("color", ""))
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
				"caster_room_id": mage.room_id,
				"effect_target_room_id": mage.room_id,
				"effect_room_color": room_color,
				"room_color": room_color,
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

	if play_order.is_empty() or avatar != null:
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
		# Finish the chosen Effect (and its nested reactions) before offering
		# another trigger from the same event. Otherwise push_front reverses
		# the chosen order and decisions see state from before the first Trap.
		if resolution_stack.any(func(frame):
			return str(frame.get("type", "")) in ["trigger_spell", "avatar_command"] and frame.get("event") == trigger_window_event):
			return true
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
		if current_spell.context.has("avatar_command"):
			trigger_window_queue.remove_at(trigger_window_cursor)
			handle_triggered_spell(current_data)
			return true

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
				"board_player_index": player_index,
				"slot_id": _find_player_board_slot_for_spell(player_index, active_spell.spell),
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

func _present_resolution_card(frame: Dictionary) -> bool:
	if table_shell == null or network_client or bool(frame.get("_card_presented", false)):
		return false
	var data: Dictionary = {}
	if frame.get("type") == "avatar_command":
		var command: SpellCardState = frame.card
		data = {"kind": "spells", "id": command.id, "title": command.card_name,
			"player": avatar.player_index, "single": true, "avatar": true}
	elif frame.get("type") == "spell_resolution":
		var spell: SpellCardState = frame.get("spell")
		if spell != null:
			data = {"kind": "spells", "id": spell.id, "title": spell.card_name,
				"player": int(frame.get("context", {}).get("caster_id", -1)),
				"dark": bool(frame.get("use_dark_side", false)), "single": spell.has_single_effect()}
	elif frame.get("type") == "trigger_spell":
		var active: ActiveSpellState = frame.get("active_spell")
		# An armed card stays hidden until it actually triggers. Ongoing public
		# permanents do not announce a new cast every time their passive fires.
		if active != null and active.get_spell_type() in ["trap", "protection"]:
			data = {"kind": "spells", "id": active.spell.id, "title": active.spell.card_name,
				"player": active.owner_id, "dark": active.use_dark_side, "single": active.spell.has_single_effect()}
	elif frame.get("type") == "event_sequence":
		var event: EventCardState = frame.get("event")
		if event != null:
			data = {"kind": "events", "id": event.id, "title": event.event_name}
	elif frame.get("type") == "quest_resolution":
		var quest: QuestState = frame.get("quest")
		if quest != null and quest.is_completed() and not quest.is_solved():
			data = {"kind": "quests", "id": quest.get_id(), "title": quest.get_name(), "player": frame.get("player_index", -1)}
	elif frame.get("type") == "room_activation":
		var room = get_room_by_id(str(frame.get("room_id", "")))
		if room != null and (bool(frame.get("force_activation", false)) or room.can_activate(bool(frame.get("allow_reactivate_flipped", false)))):
			data = {"kind": "rooms", "id": room.get_art_id(), "title": room.room_name, "flipped": room.flipped}
	if data.is_empty():
		return false
	frame["_card_presented"] = true
	card_presentation_serial += 1
	data["serial"] = card_presentation_serial
	data["requires_click"] = str(data.get("kind", "")) in ["events", "spells"]
	data["acknowledge_player"] = int(data.get("player", get_turn_presentation().get("player_index", 0)))
	if AvatarRules.is_avatar(self, int(data.acknowledge_player)):
		data.acknowledge_player = crown_owner_id
	if int(data.acknowledge_player) < 0:
		data.acknowledge_player = 0
	card_presentation = data
	table_shell.sync_card_presentation()
	if network_session != null:
		network_session.call_deferred("publish")
	if not bool(data.get("requires_click", false)):
		get_tree().create_timer(CARD_PRESENTATION_SECONDS).timeout.connect(
			_finish_card_presentation.bind(card_presentation_serial)
		)
	return true


func can_acknowledge_card_presentation(player_index: int) -> bool:
	return not card_presentation.is_empty() and (
		network_session == null or player_index == int(card_presentation.get("acknowledge_player", 0)))


func dismiss_card_presentation(serial: int = -1) -> bool:
	if network_client or card_presentation.is_empty():
		return false
	var active_serial: int = int(card_presentation.get("serial", -1))
	if serial >= 0 and serial != active_serial:
		return false
	_finish_card_presentation(active_serial)
	return true


func _finish_card_presentation(serial: int) -> void:
	if int(card_presentation.get("serial", -1)) != serial or network_client:
		return
	card_presentation = {}
	if table_shell != null:
		table_shell.sync_card_presentation()
	process_resolution_stack()
	if network_session != null:
		network_session.call_deferred("publish")


func process_resolution_stack() -> bool:
	if processing_resolution_stack or resolution_visual_yield_active:
		return true

	processing_resolution_stack = true

	while true:
		if not card_presentation.is_empty():
			processing_resolution_stack = false
			return true
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
		if _present_resolution_card(frame):
			processing_resolution_stack = false
			return true

		match resolution_type:
			"avatar_activation":
				completed = AvatarRules.process_activation(self, frame)
			"avatar_command":
				completed = AvatarRules.process_command(self, frame)
			"avatar_section":
				completed = AvatarEffects.process_section(self, frame)
			"avatar_event":
				completed = AvatarEvents.process(self, frame)
			"avatar_cleanup":
				completed = AvatarRules.process_cleanup(self, frame)
			"room_move":
				completed = AlternativeRoomRules.process_movement(self, frame)
			"forgotten_activation_start":
				completed = true
				if not bool(frame.get("started", false)):
					frame["started"] = true
					ForgottenPassives.activation_start(self, int(frame.player_index))
			"forgotten_end_black_rose":
				completed = ForgottenAttachments.process_end_phase(self, frame)
			"forgotten_defeat", "forgotten_survivors", "forgotten_distribute":
				completed = ForgottenRules.process_frame(self, frame)
			"infectio_resolution":
				completed = PestilenceRules.process_tokens(self, frame)
			"forgotten_nightmare_phase", "forgotten_nightmare_defeat":
				completed = ForgottenEvocations.process_frame(self, frame)
			"druidic_action", "druidic_recover", "druidic_attack_power", "druidic_phase_start", "druidic_study", "druidic_ursa_loss":
				completed = DruidicRules.process_frame(self, frame)
			"game_event":
				completed = true
				if not bool(frame.get("emitted", false)):
					frame["emitted"] = true
					process_game_event(frame.event)
			"destiny_resolution":
				completed = DeathEffectResolver.process_destiny(self, frame)
			"mage_effects":
				completed = DeathEffectResolver.process_mages(self, frame)
			"spell_sentence":
				completed = DeathEffectResolver.process_sentence(self, frame)
			"action_events":
				completed = process_action_events_resolution(frame)
			"cleanup_finish":
				completed = process_cleanup_finish_resolution(frame)
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
			"model_room_entry":
				completed = process_model_room_entry_resolution(frame)
			"summon_distinct_evocations":
				completed = process_summon_distinct_evocations_resolution(frame)
			"chaos_resolution":
				completed = effect_resolver.process_chaos_resolution(frame)
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

		if resolution_visual_yield_requested:
			resolution_visual_yield_requested = false
			resolution_visual_yield_active = true
			processing_resolution_stack = false
			if table_shell != null:
				get_tree().create_timer(0.36).timeout.connect(_resume_resolution_after_visual_yield)
			else:
				get_tree().process_frame.connect(_resume_resolution_after_visual_yield, CONNECT_ONE_SHOT)
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


func _succubus_redirect_options(player_index: int) -> Array:
	var options: Array = []
	if player_index < 0 or player_index >= players.size():
		return options
	for evocation_index in range(players[player_index].evocations.size()):
		var evocation: EvocationState = players[player_index].evocations[evocation_index]
		if evocation == null or evocation.assigned_mage >= 0:
			continue
		if evocation.is_defeated() or not is_evocation_in_play(evocation):
			continue
		var abilities: Array = evocation_database.get_evocation(evocation.evocation_id).get("abilities", [])
		var can_redirect := false
		for ability_value in abilities:
			if ability_value is Dictionary and str(ability_value.get("type", "")) == "redirect_owner_damage":
				can_redirect = true
				break
		if not can_redirect:
			continue
		options.append({
			"token": "succubus:%d:%d" % [player_index, evocation_index],
			"value": evocation,
			"name": "%s #%d" % [evocation.get_display_name(), evocation.board_number],
			"owner_id": player_index,
			"evocation_index": evocation_index
		})
	return options


func process_damage_resolution(
	resolution: Dictionary
) -> bool:
	var step: String = str(resolution.get("step", "pre_event"))
	# A previous Trap/Protection can defeat or place the target in their Cell
	# while this damage is queued. Recheck before applying it, not after defeat.
	if step in ["pre_event", "after_pre_event", "apply_damage"]:
		var target_id: int = int(resolution.get("target_player_index", -1))
		var source_id: int = int(resolution.get("attacker_id", -1))
		if AvatarRules.immune_to_damage(self, source_id, target_id, str(resolution.get("action_type", ""))):
			_sync_damage_result_context(resolution, 0)
			return true
		if source_id >= 0 and source_id != target_id and is_mage_in_cell(target_id) \
		and str(resolution.get("action_type", "")) not in ["event", "infectio"]:
			_sync_damage_result_context(resolution, 0)
			return true

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

			# Succubus: when its owner is about to suffer Damage, they may assign
			# exactly one of those Damage cubes to one of their Succubi instead.
			# This is separate from full-damage redirects granted by Spells.
			if not bool(resolution.get("succubus_checked", false)):
				resolution["succubus_checked"] = true
				var succubus_options := _succubus_redirect_options(int(resolution["target_player_index"]))
				var mandatory = succubus_options.filter(func(o): return bool(ForgottenEvocations.ability(self, o.value, "redirect_owner_damage").get("mandatory", false)))
				if not mandatory.is_empty():
					resolution["succubus_redirect_choice"] = mandatory[0].value
					succubus_options.clear()
				if not succubus_options.is_empty():
					if request_effect_choice(
						int(resolution["target_player_index"]),
						"succubus_redirect",
						resolution,
						"succubus_redirect_choice",
						succubus_options,
						0, 1,
						"You may assign 1 of this Damage to an eligible Evocation instead."
					):
						return false

			var chosen_succubus = resolution.get("succubus_redirect_choice", null)
			if chosen_succubus is EvocationState \
			and not chosen_succubus.is_defeated() \
			and is_evocation_in_play(chosen_succubus) \
			and int(resolution.get("amount", 0)) > 0:
				resolution["amount"] = int(resolution["amount"]) - 1
				resolution["step"] = "after_succubus_redirect"
				queue_resolution({
					"type": "evocation_damage",
					"evocation": chosen_succubus,
					# Both recipients belong to the same Damage Effect. Its source
					# ability resolves once, after the entire split has resolved.
					"damage_ability_parent": resolution,
					"amount": 1,
					"attacker_id": int(resolution.get("attacker_id", -1)),
					"action_type": str(resolution.get("action_type", "")),
					"source_model_type": str(resolution.get("source_model_type", "")),
					"source_evocation": resolution.get("source_evocation", null),
					"suppressed_trigger_types": resolution.get("suppressed_trigger_types", []).duplicate()
				})
				return false

			resolution["step"] = "apply_damage"
			return false

		"after_succubus_redirect":
			if int(resolution.get("amount", 0)) <= 0:
				_sync_damage_result_context(resolution, 0)
				return true
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
			var dealt: int = redirected_evocation.add_damage(AvatarRules.cube_owner(self, attacker_id), cubes)
			resolution["actual_damage"] = dealt
			resolution["step"] = "redirect_applied"
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
			var damage_dealt: int = target_mage.add_damage(AvatarRules.cube_owner(self, attacker_id), cubes_available)
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
			if DeathEffectResolver.defer_damage_post_event(resolution):
				return true
			var post_event := GameEvent.new("damage_inflicted")
			_fill_damage_event_source(post_event, resolution)
			var target_player_index: int = int(resolution.get("target_player_index", -1))
			post_event.target_model_type = "mage"
			post_event.target_player_index = target_player_index
			post_event.target_room_id = players[target_player_index].mage.room_id
			post_event.amount = int(resolution.get("actual_damage", 0))
			post_event.data["lethal"] = players[target_player_index].mage.is_defeated()
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

			if bool(resolution.get("forced_defeat", false)) or (not was_defeated and target_mage.is_defeated()):
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
			if not bool(resolution.get("forced_defeat", false)) and not players[victim].mage.is_defeated():
				return true
			# Defeat interrupts only physical resolutions already in progress.
			# A player-level flag would incorrectly cancel the next Cell exit.
			for frame in resolution_stack:
				if str(frame.get("type", "")) in ["explore", "fight", "command", "druidic_action"] and int(frame.get("player_index", -1)) == victim:
					frame["cancelled_by_defeat"] = true
			resolution["step"] = "after_destiny"
			if not players[victim].mage.destiny_tokens.is_empty():
				queue_resolution({"type": "destiny_resolution", "victim": victim, "order": get_play_order(), "index": 0})
			return false

		"after_destiny":
			var victim: int = int(resolution.get("target_player_index", -1))
			if resolution.has("defeat_receipt"):
				resolution.defeat_receipt["completed"] = true
			resolution["step"] = "award_defeat"
			# Codex p.13: Destiny resolves at step 3, before Cell placement.
			# Only assigned Evocations are removed; owned summons remain.
			queue_resolution({"type": "forgotten_nightmare_defeat", "victim": victim, "source_evocation": resolution.get("source_evocation"), "context": {}})
			place_mage_in_cell(victim)
			DruidicRules.end_transformation(self, victim)
			return false

		"award_defeat":
			var victim: int = int(resolution.get("target_player_index", -1))
			var killer: int = int(resolution.get("attacker_id", -1))
			if is_event_active("dominion"):
				killer = -1
			if killer == -1:
				black_rose_trophies.append(victim)
			elif killer >= 0 and killer < players.size():
				gain_player_trophy(killer, victim)
			# Codex p.13 grants the automatic Destiny defeat's caster an extra Trophy.
			var caster: int = int(resolution.get("attacker_id", -1))
			if bool(resolution.get("destiny_defeat", false)) and caster >= 0:
				gain_player_trophy(caster, victim)
			var counts: Dictionary = {}
			for owner in players[victim].mage.damage_cubes:
				counts[owner] = int(counts.get(owner, 0)) + 1
			resolution["defeat_rewards"] = {} if bool(resolution.get("no_defeat_power", false)) else ranked_power_rewards(counts, true)
			resolution["reward_owners"] = resolution.defeat_rewards.keys()
			# Assigned Nightmares were handled before Cell placement;
			# summoned Evocations stay in the Lodge.
			resolution["step"] = "defeat_rewards"
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
			PestilenceRules.queue_tokens(self, victim)
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
	var damage_event: GameEvent = resolution.get("event")
	context["last_damage_target_room_id"] = damage_event.target_room_id if damage_event != null else ""
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
	var source_context: Dictionary = resolution.get("result_context", resolution.get("damage_ability_parent", {}).get("result_context", {}))
	if str(source_context.get("spell_target_type", "")) in ["room", "area"] and not ForgottenEvocations.ability(self, resolution.evocation, "immune_room_damage").is_empty():
		_sync_evocation_damage_result_context(resolution, 0)
		return true
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
				AvatarRules.cube_owner(self, attacker_id),
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
			if DeathEffectResolver.defer_damage_post_event(resolution):
				return true
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
				# Cinis: resolve the stored-cube replacement before the
				# normal evocation_defeated_or_removed event is emitted.
				if _try_prevent_evocation_defeat_with_stored_cube(evocation):
					resolution["defeat_prevented_by_stored_cube"] = true
					return true

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
	if bool(resolution.get("effect_queued", false)):
		return true
	var context: Dictionary = resolution.context
	var controller: int = int(context.caster_id)
	if controller < 0 or controller >= players.size():
		return true
	var ability: Dictionary = resolution.ability

	# Rebuilt (flipped) Rooms cannot receive or contain Instability. Nigredo's
	# optional on-damage ability must therefore finish silently instead of
	# asking the controller to choose an effect that cannot resolve.
	var source_room = get_room_by_id(str(context.get("caster_room_id", "")))
	if source_room != null and source_room.flipped:
		resolution["effect_queued"] = true
		return true

	if not context.has("ability_choice"):
		var options: Array = []
		for effect in ability.get("choices", []):
			options.append({"token": "ability:" + str(options.size()), "value": effect,
				"name": str(effect.get("type", "")).replace("_", " ").capitalize() + " " + str(effect.get("amount", 1))})
		if options.is_empty():
			return true
		request_effect_choice(controller, "evocation_damage_ability", context, "ability_choice", options,
			0 if bool(ability.get("optional", false)) else 1, 1,
			str(resolution.name) + ": choose an Instability effect in its Room."
			+ (" You may skip." if bool(ability.get("optional", false)) else ""))
		return false
	var selected = context.get("ability_choice")
	resolution["effect_queued"] = true
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
			var effects: Array = [] if AvatarRules.is_avatar(self, player_index) else quest.get_effects()

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



func _room_move_choice_options(player_index: int) -> Array:
	var options: Array = []
	if player_index < 0 or player_index >= players.size():
		return options
	var mage = players[player_index].mage
	if mage == null or mage.in_cell:
		return options
	var destinations: Array = [mage.room_id]
	destinations.append_array(_beta_adjacent_room_ids(mage.room_id))
	for room_id in destinations:
		var room = get_room_by_id(room_id)
		options.append({
			"token": "room:" + room_id,
			"value": room_id,
			"target_type": "room",
			"room_id": room_id,
			"path": [room_id],
			"name": str(room.room_name) if room != null else room_id
		})
	return options


func _room_attack_choice_options(player_index: int) -> Array:
	var options: Array = []
	if player_index < 0 or player_index >= players.size():
		return options
	var mage = players[player_index].mage
	if mage == null or mage.in_cell:
		return options
	for target_index in range(players.size()):
		if target_index == player_index:
			continue
		var target_mage = players[target_index].mage
		if target_mage == null or target_mage.in_cell or target_mage.room_id != mage.room_id:
			continue
		options.append({
			"token": "mage:" + str(target_index),
			"value": target_index,
			"player_index": target_index,
			"target_type": "mage",
			"name": players[target_index].player_name
		})
	for owner_id in range(players.size()):
		for evocation_index in range(players[owner_id].evocations.size()):
			var evocation: EvocationState = players[owner_id].evocations[evocation_index]
			if not _valid_mage_physical_attack_evocation(player_index, evocation):
				continue
			options.append({
				"token": "evocation:%d:%d" % [owner_id, evocation_index],
				"value": evocation,
				"owner_id": owner_id,
				"evocation_index": evocation_index,
				"target_type": "evocation",
				"name": evocation.get_display_name()
			})
	return options


func _prepare_room_effect_choice(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	if bool(effect.get("shared", false)):
		return _prepare_spell_secondary_effect_choice(effect, context)
	if str(effect.get("type", "")) in AlternativeRoomRules.EFFECT_TYPES:
		return true
	var caster_id: int = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 or caster_id >= players.size():
		return true

	var effect_type: String = str(effect.get("type", ""))

	# Rebuilt Forge resolves a sequence of Move / Attack sentences. These are
	# interactive Room effects, so ask for each destination/target as the
	# sentence is reached instead of letting the low-level resolver fail and
	# merely turn the activation token.
	if effect_type == "move" and str(effect.get("target", "")) == "self":
		if context.has("destination_room_id"):
			return true
		var move_options := _room_move_choice_options(caster_id)
		if move_options.is_empty():
			_set_interactive_effect_choice(context, "_skip_room_effect", true)
			return true
		_set_interactive_effect_choice(context, "movement_origin_room_id", players[caster_id].mage.room_id)
		return not request_effect_choice(
			caster_id, "movement_destination", context, "destination_room_id",
			move_options, 1, 1, "Choose where to Move 1, or select your current Room to stay."
		)

	if effect_type == "attack" and str(effect.get("target", "")) == "self":
		if context.has("room_attack_target"):
			return true
		var attack_options := _room_attack_choice_options(caster_id)
		if attack_options.is_empty():
			# No legal Model in the current Room: this Attack sentence has no
			# target, but the remaining Forge sequence must continue.
			_set_interactive_effect_choice(context, "_skip_room_effect", true)
			return true
		return not request_effect_choice(
			caster_id, "room_attack_target", context, "room_attack_target",
			attack_options, 1, 1, "Forge: choose a Model in your Room to Attack."
		)

	if effect_type == "summon_evocation" and str(effect.get("range", "0")) != "0":
		if context.has("target_room_id") and str(context.get("target_room_id", "")) != "":
			return true
		var origin_room_id: String = str(context.get("room_id", players[caster_id].mage.room_id))
		var summon_options := _quest_room_choice_options(caster_id, {
			"target": "room",
			"range": effect.get("range", 0)
		}, origin_room_id)
		if summon_options.is_empty():
			_set_interactive_effect_choice(context, "_skip_room_effect", true)
			return true
		return not request_effect_choice(
			caster_id, "room_effect_room_target", context, "target_room_id",
			summon_options, 1, 1, "Crypt: choose a Room for this Cadaver."
		)

	if effect_type == "draw_forgotten_choose":
		if context.has("selected_forgotten_spell"):
			return true
		var options: Array = []
		var candidates: Array = []
		for offset in range(mini(int(effect.get("draw", 2)), forgotten_deck.size())):
			var index: int = forgotten_deck.size() - 1 - offset
			var spell: SpellCardState = forgotten_deck[index]
			candidates.append(spell)
			options.append({"token": "forgotten:" + str(index), "value": spell, "id": spell.id, "name": spell.card_name})
		for candidate in candidates:
			if str(candidate.light_side.get("type", "")) == "on_draw":
				for drawn in candidates:
					forgotten_deck.erase(drawn)
				context["_skip_room_effect"] = true
				resolve_drawn_forgotten(caster_id, candidate, candidates)
				return true
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
		if (not quest_choice and amount == source.size()) or amount == 0:
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
	# Do not request choices for a sentence that only belongs to the other
	# timing window (e.g. Lifeblood's initial Heal vs. its persistent trigger).
	if bool(effect.get("only_on_initial_cast", false)) and context.get("trigger_event") != null:
		return int(resolution.index) >= effects.size()
	if bool(effect.get("only_on_trigger", false)) and context.get("trigger_event") == null:
		return int(resolution.index) >= effects.size()
	if resolver_kind == "spell":
		var announced: bool = DeathEffectResolver.announce_spell(self, context, [effect])
		if announced and (waiting_for_player_input or trigger_window_active):
			resolution["index"] = index
			return false

		if int(resolution.get("_caput_announced_index", -1)) != index:
			resolution["_caput_announced_index"] = index
			if _announce_caput_draconis_effect(effect, context):
				resolution["index"] = index
				return false


	# Quest Effects may require a player decision.  Do this before applying
	# the Effect so no game state is changed until all required choices for
	# this sentence are known.
	if resolver_kind == "quest":
		# Each printed Quest sentence chooses its own target.  Never reuse the
		# previous sentence's Room/Model or conversion selection (Generous Moon is
		# the canonical case: its two Effects may target different Rooms).
		# Keep choices only while the *same* sentence is waiting for input.
		if int(resolution.get("target_effect_index", -1)) != index:
			resolution["target_effect_index"] = index
			_clear_interactive_effect_choices(context)
			for key in [
				"target_room_id", "target_player_index", "target_evocation",
				"target_model_type", "quest_target_model",
				"selected_evocation_to_activate", "spell_target_type", "target_is_dummy"
			]:
				context.erase(key)
		if not _prepare_quest_effect_choice(
			effect,
			context
		):
			# The frame must retry the same Effect after submit_effect_choice()
			# stores the selected runtime value in the live context.
			resolution["index"] = index
			return false
		if bool(context.get("target_is_dummy", false)):
			return int(resolution.index) >= effects.size()

	if resolver_kind in ["spell", "evocation", "physical"]:
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
	context["effect_summoned_evocation"] = false
	context["effect_target_room_id"] = ""
	context["effect_target_model_type"] = ""

	active_effect_context = context

	var success: bool = false


	match resolver_kind:

		"spell", "quest", "evocation", "physical":
			success = effect_resolver.resolve_effect(
				effect,
				context
			)

		"room":
			if bool(context.get("_skip_room_effect", false)):
				success = true
			else:
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


	# Any input requested while resolving this Effect means the Effect is PAUSED,
	# not completed. Retry the exact same Effect after the answer is submitted.
	# This is essential for Chaos: chaos_reveal_ack is a different input type
	# from effect_choice, but it belongs to the same Chaos Effect.
	if waiting_for_player_input:
		print(
			"EFFECT PAUSED: type=",
			str(effect.get("type", "")),
			" | input=",
			str(pending_input.get("type", "")),
			" | retry_index=",
			index
		)
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
		if resolver_kind in ["quest", "spell", "evocation", "physical"] or (resolver_kind == "room" and bool(context.get("alternative_room", false))):
			print(
				resolver_kind.capitalize(),
				" Effect could not be applied; skipped | effect ",
				str(effect.get("type", ""))
			)

			if resolver_kind in ["quest", "room"]:
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


	# Stable sentence receipts survive the next sentence's transient counters.
	var receipts := {"place_instability": "instability_placed", "convert_instability": "instability_converted", "convert_damage": "damage_converted", "heal": "damage_healed"}
	if receipts.has(str(effect.get("type", ""))):
		var receipt: String = receipts[str(effect.type)]
		context["last_" + receipt] = int(context.get("effect_" + receipt, 0))

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
		if effect_type.begins_with("summon_") or bool(context.get("effect_summoned_evocation", false)):
			keywords.append("summon")

		if "summon" in keywords:
			var summon_event := GameEvent.new("forgotten_summon_effect")
			summon_event.source_player_index = caster_id
			queue_resolution({"type": "game_event", "event": summon_event})

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
			# Quest tasks use room_color for generic Room filters. For an
			# effect_resolved event this is the Room actually affected by the
			# Effect, not necessarily the Room where the caster stands.
			"room_color": effect_room_color,
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
			context["resolving_spell"] = spell
			context["spell_forgotten"] = bool(spell.forgotten)
			context["spell_use_dark_side"] = use_dark_side

			if not bool(resolution.get("school_revealed", false)):
				resolution["school_revealed"] = true
				var revealed_event := GameEvent.new("spell_revealed")
				revealed_event.source_player_index = caster_id
				revealed_event.source_model_type = "mage"
				revealed_event.source_room_id = players[caster_id].mage.room_id
				revealed_event.data["spell_type"] = str(side.type)
				queue_resolution({"type": "game_event", "event": revealed_event})
				return false
			if not OracleRules.prepare_revelation(self, caster_id, side, context): return false

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
			# Draw-triggered Forgotten cards are discarded immediately, never
			# prepared/cast. Requiem can also return to hand during its resolution.
			if bool(context.get("drawn_forgotten", false)):
				return true
			if not bool(context.get("became_transformation", false)) and not bool(context.get("returned_to_hand", false)):
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

			_queue_spell_effect_resolved_event(
				caster_id,
				spell,
				str(context.get("spell_type", "")),
				players[caster_id].mage.room_id
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
			and spell_type != "permanent" \
			and spell_type != "trap" \
			and spell_type != "protection":
				print("Unsupported Spell type: ", spell_type)
				return true

			# Combat and Contingency Spells choose their primary target when
			# cast. Trap/Protection targets are determined by their trigger
			# semantics and remain handled by the Active Spell system.
			if spell_type == "combat" \
			or spell_type == "contingency" \
			or spell_type == "permanent":
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

			# Cauda Draconis triggers when another Mage CASTS a Quick Spell, so
			# announce the cast before the card is consumed or its Effect resolves.
			# The guard lives on the spell_cast frame to avoid re-emitting when a
			# triggered Trap temporarily pauses this frame.
			if source == "quick" \
			and not bool(resolution.get("_geomancy_quick_cast_emitted", false)):
				resolution["_geomancy_quick_cast_emitted"] = true
				var quick_event := GameEvent.new("quick_spell_cast")
				quick_event.action_type = "spell"
				quick_event.source_model_type = "mage"
				quick_event.source_player_index = player_index
				quick_event.source_room_id = player.mage.room_id
				quick_event.data["spell_id"] = spell.id
				quick_event.data["spell_type"] = spell_type
				queue_resolution({
					"type": "game_event",
					"event": quick_event
				})
				return false

			# The card leaves its prepared slot only after the Cast Action itself
			# has been validated. This avoids consuming a prepared card on an
			# invalid/unsupported cast request.
			if not bool(resolution.get("_school_cast_emitted", false)):
				resolution["_school_cast_emitted"] = true
				var cast_event := GameEvent.new("spell_cast_started")
				cast_event.source_player_index = player_index
				cast_event.source_model_type = "mage"
				cast_event.source_room_id = player.mage.room_id
				cast_event.target_room_id = player.mage.room_id
				queue_resolution({"type": "game_event", "event": cast_event})
				return false
			if str(context.get("target_room_id", "")) != "" and not _spell_room_target_allowed(
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
				"spell_forgotten": bool(active_spell.spell.forgotten),
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
			context["caster_room_id"] = players[owner_id].mage.room_id
			# Stored targets/choices of a permanent must not mask this trigger.
			context.erase("_spell_guard_announced")
			context.erase("ignored_spell_players")
			DeathEffectResolver.apply_trigger_target(active_side, context, event)

			resolution["context"] = context

			if spell_type == "trap" or spell_type == "protection":
				resolve_spell_reveal_instability(owner_id, active_spell.spell, active_spell.use_dark_side)

			resolution["step"] = "prepare_effects"
			return false
		"prepare_effects":
			var context: Dictionary = resolution.context
			if not OracleRules.prepare_revelation(self, owner_id, active_spell.get_side(), context): return false
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
						"spell_side": context.get("spell_side", {}),
						"caster_room_id": str(context.get("caster_room_id", "")),
						"source_room_id": str(context.get("caster_room_id", ""))
					}
				)

			resolution["step"] = "done"
			_apply_event_after_spell(owner_id, active_spell.get_spell_type())
			if active_spell.get_spell_type() == "trap": traps_resolved_count += 1
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
			var force_activation: bool = bool(resolution.get("force_activation", false))
			if not force_activation and not room.can_activate(
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
				"effects": [] if bool(room_context.get("avatar_no_room_effect", false)) else room.get_effects(),
				"index": 0,
				"context": room_context
			})
			return false

		"after_effects":
			# A nested game_event temporarily keeps this frame on the stack.
			# Finalize once, then let the resumed frame finish without re-emitting.
			resolution["step"] = "done"
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

			# Carcer Dark listens to Room Effects through the same GameEvent
			# pipeline used by ongoing Spells.
			var room_effect_event := GameEvent.new(
				"room_effect_resolved"
			)
			room_effect_event.action_type = "room"
			room_effect_event.source_model_type = "mage"
			room_effect_event.source_player_index = player_index
			room_effect_event.source_room_id = room.get_room_id()
			room_effect_event.data["room_id"] = room.get_room_id()
			room_effect_event.data["room_color"] = str(
				room.get_room_data().get("color", "")
			)
			queue_resolution({
				"type": "game_event",
				"event": room_effect_event
			})

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
			if not bool(resolution.get("jinx_checked", false)):
				resolution["jinx_checked"] = true
				ForgottenAttachments.physical_action_finished(self, player_index)

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
			if path.size() > player.get_mage_speed():
				return true

			if bool(resolution.get("activate_before", false)) \
			and bool(resolution.get("activate_after", false)):
				return true

			if not player.exhaust_physical_action():
				return true

			resolution["expected_room_id"] = player.mage.room_id
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
				# A trap may displace this Mage between Explore steps. Resume
				# the remaining movement from the actual location, not the route
				# chosen before the trap, then still activate the final Room.
				if resolution.has("expected_room_id") and str(player.mage.room_id) != str(resolution.expected_room_id):
					resolution["replan_movement"] = true
				if bool(resolution.get("replan_movement", false)):
					if not context.has("explore_destination"):
						var options := _quest_room_choice_options(player_index, {"range": 1}, player.mage.room_id)
						request_effect_choice(player_index, "movement_destination", context, "explore_destination", options, 1, 1,
							"Continue Explore · %d movement remaining. Select your Room to stop." % (path.size() - move_index))
						return false
					var destination: String = str(context.explore_destination)
					context.erase("explore_destination")
					if destination == player.mage.room_id:
						resolution["move_index"] = path.size()
						return false
					path[move_index] = destination
				if not move_mage_to_room_id(player_index, str(path[move_index]), 1):
					return true
				resolution["expected_room_id"] = path[move_index]
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
			if not bool(resolution.get("jinx_checked", false)):
				resolution["jinx_checked"] = true
				ForgottenAttachments.physical_action_finished(self, player_index)
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

				ForgottenPassives.physical_attack(self, player_index)
				deal_damage(
					player_index,
					target_player_index,
					player.get_mage_strength(),
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

				ForgottenPassives.physical_attack(self, player_index)
				deal_damage_to_evocation(
					player_index,
					target_evocation,
					player.get_mage_strength(),
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
	if AvatarRules.is_avatar(self, int(resolution.get("controller_id", -1))) and not bool(resolution.get("avatar_planned", false)):
		if not AvatarRules.prepare_evocation(self, resolution): return false
	var extended_evocation: EvocationState = resolution.get("evocation")
	if extended_evocation != null and ForgottenEvocations.extended(self, extended_evocation):
		return ForgottenEvocations.process_activation(self, resolution)
	if not ForgottenEvocations.can_activate(self, extended_evocation):
		return true
	if bool(resolution.get("activation_ended", false)):
		return true
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

	var activation_strength: int = get_evocation_effective_strength(
		evocation,
		strength_bonus
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
			resolution["step"] = "card_abilities"

			if attack_timing == "after":
				if _perform_evocation_physical_attack(
					evocation,
					controller_id,
					activation_strength,
					context
				):
					return false

			return false

		"card_abilities":
			var on_activate_abilities: Array = []

			for ability_value in get_evocation_abilities(evocation):
				if not ability_value is Dictionary:
					continue

				var ability: Dictionary = ability_value
				if str(ability.get("type", "")) == "on_activate":
					on_activate_abilities.append(ability)

			var ability_index: int = int(
				resolution.get(
					"on_activate_ability_index",
					0
				)
			)

			if ability_index >= on_activate_abilities.size():
				resolution["step"] = "done"
				return false

			var ability: Dictionary = on_activate_abilities[ability_index]
			var decision_key: String = (
				"_on_activate_ability_choice_"
				+ str(ability_index)
			)

			if bool(ability.get("optional", false)):
				if not resolution.has(decision_key):
					request_effect_choice(
						controller_id,
						"evocation_optional_ability",
						resolution,
						decision_key,
						[
							{
								"token": "choice:yes",
								"value": true,
								"name": "Yes"
							},
							{
								"token": "choice:no",
								"value": false,
								"name": "No"
							}
						],
						1,
						1,
						"Use "
						+ evocation.get_display_name()
						+ "'s activation ability?"
					)
					return false

				var use_ability: bool = bool(
					resolution.get(decision_key, false)
				)

				_forget_interactive_effect_choice_key(
					resolution,
					decision_key
				)

				if not use_ability:
					resolution["on_activate_ability_index"] = (
						ability_index + 1
					)
					return false

			resolution["on_activate_ability_index"] = (
				ability_index + 1
			)

			var ability_effects: Array = ability.get(
				"effects",
				[]
			)

			if ability_effects.is_empty():
				return false

			var ability_context: Dictionary = {
				"game": self,
				"caster_id": controller_id,
				"caster_room_id": str(evocation.room_id),
				"source_evocation": evocation,
				"source_kind": "evocation",
				"effect_origin_room_id": str(evocation.room_id)
			}

			queue_resolution({
				"type": "effect_sequence",
				"resolver_kind": "evocation",
				"effects": ability_effects,
				"index": 0,
				"context": ability_context
			})

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
	if str(frame.get("type", "")) in ["damage", "evocation_damage"] and not bool(frame.get("post_event_deferred", false)):
		var damage: int = int(frame.get("actual_damage", 0)) + int(frame.get("redirected_ability_damage", 0))
		var parent_damage: Dictionary = frame.get("damage_ability_parent", {})
		if not parent_damage.is_empty():
			parent_damage["redirected_ability_damage"] = int(parent_damage.get("redirected_ability_damage", 0)) + damage
		else:
			# Resolve reactions/defeat before the source's on-damage ability.
			_queue_evocation_damage_abilities(frame, damage)
	match str(frame.get("on_complete", "")):
		"advance_study_phase":
			advance_study_phase()
		"advance_action_phase":
			advance_action_phase()
		"continue_action_activation":
			_request_stepwise_action_activation()
		"advance_evocation_phase":
			advance_evocation_phase()
		"advance_cleanup_phase":
			advance_cleanup_phase()
		"finish_cleanup":
			finish_cleanup_phase()
		"continue_black_rose_event":
			_continue_black_rose_after_event(frame.get("context", {}))
		"continue_black_rose_quests":
			black_rose_quest_step = 4
			black_rose_quest_cursor = 0
			advance_black_rose_quest_steps()
		"finish_black_rose":
			_finish_black_rose_phase_after_upgrades()
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
		if AvatarRules.is_avatar(self, player_index):
			var remaining: Array = player.evocations.filter(func(ev): return ev.assigned_mage < 0 and ForgottenEvocations.can_activate(self, ev) and not ev in evocation_phase_activated)
			remaining.sort_custom(func(a, b): return a.board_number < b.board_number)
			if remaining.is_empty():
				evocation_phase_cursor += 1
				continue
			evocation_phase_activated.append(remaining[0])
			return queue_resolution({"type": "evocation_activation", "step": "start", "evocation": remaining[0], "controller_id": player_index, "context": {}, "on_complete": "advance_evocation_phase"})
		var evocation_data: Array = []
		for i in range(player.evocations.size()):
			var evocation: EvocationState = player.evocations[i]
			if evocation == null or evocation.assigned_mage >= 0 or not ForgottenEvocations.can_activate(self, evocation) or evocation_phase_activated.has(evocation):
				continue
			var controller_id: int = get_evocation_controller_id(evocation)
			evocation_data.append({
				"evocation_index": i,
				"id": evocation.evocation_id,
				"name": evocation.get_display_name(),
				"room_id": evocation.room_id,
				"speed": evocation.speed,
				"strength": get_evocation_effective_strength(evocation),
				"base_strength": evocation.strength,
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
	cleanup_return_indices_by_player.clear()
	cleanup_decided_indices_by_player.clear()
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
		if AvatarRules.is_avatar(self, player_index):
			cleanup_phase_cursor += 1
			return queue_resolution({"type": "avatar_cleanup", "on_complete": "advance_cleanup_phase"})
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
				"board_player_index": player_index,
				"slot_id": _find_player_board_slot_for_spell(
					player_index,
					active_spell.spell
				),
				"spell_id": active_spell.spell.id,
				"spell_name": active_spell.spell.card_name,
				"spell_type": spell_type
			})

		var decided: Array = cleanup_decided_indices_by_player.get(
			player_index,
			[]
		)

		# One single screen for all unused Trap/Protection cards.
		if not active_options.is_empty() and decided.is_empty():
			return request_player_input({
				"type": "cleanup_active_spells",
				"phase": PHASE_CLEANUP,
				"player_index": player_index,
				"active_spells": active_options,
				"single_card_decision": false,
				"min_select": 0,
				"max_select": active_options.size(),
				"return_to_hand_indices": []
			})

		var returns: Array[int] = []
		for index_value in cleanup_return_indices_by_player.get(
			player_index,
			[]
		):
			returns.append(int(index_value))

		_cleanup_player_mage_sheet(player_index, returns)
		cleanup_return_indices_by_player.erase(player_index)
		cleanup_decided_indices_by_player.erase(player_index)
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

	var decided: Array = cleanup_decided_indices_by_player.get(player_index, [])
	for index in allowed_indices:
		if not decided.has(index):
			decided.append(index)
	cleanup_decided_indices_by_player[player_index] = decided

	var accumulated: Array = cleanup_return_indices_by_player.get(player_index, [])
	for index in validated:
		if not accumulated.has(index):
			accumulated.append(index)
	cleanup_return_indices_by_player[player_index] = accumulated

	clear_player_input()
	# Stay on the same player until every Active Trap/Protection has received
	# its independent Hand/Memories decision.
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
	return queue_resolution({"type": "cleanup_finish", "context": phase_context})


func process_cleanup_finish_resolution(frame: Dictionary) -> bool:
	# Every nested Event/choice must finish before rebuilding, and all Room
	# rewards must finish before the final end-game check (rulebook p.31).
	match str(frame.get("step", "infectio")):
		"infectio":
			frame["step"] = "events"
			var order: Array = get_play_order()
			order.reverse()
			for id in order: PestilenceRules.queue_tokens(self, id)
			return false
		"events":
			frame["step"] = "rooms"
			resolve_events_for_phase(PHASE_CLEANUP, frame.context)
			return false
		"rooms":
			for room in get_children():
				if room.has_meta("room_id") and not room.flipped and room.is_instability_complete():
					resolve_room_completion(room)
					return false
			frame["step"] = "end_check"
			reset_room_activations()
			return false
		"end_check":
			frame["step"] = "done"
			if not check_end_game():
				frame["on_complete"] = "finish_cleanup"
			return true
	return true


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
		quest_counts[AvatarRules.cube_owner(self, player.player_index)] = player.completed_quests.filter(func(quest): return quest.is_solved()).size()
		trophy_counts[AvatarRules.cube_owner(self, player.player_index)] = player.trophies.size()
	var quest_rewards: Dictionary = ranked_power_rewards(quest_counts)
	var trophy_rewards: Dictionary = ranked_power_rewards(trophy_counts)
	var scores: Array = []
	for owner in range(-1, players.size()):
		if AvatarRules.is_avatar(self, owner): continue
		var base: int = black_rose_power if owner == -1 else players[owner].power
		var quest_bonus: int = int(quest_rewards.get(owner, 0))
		var trophy_bonus: int = int(trophy_rewards.get(owner, 0))
		var crown_bonus: int = 1 if owner >= 0 and owner == crown_owner_id else 0
		var total: int = base + quest_bonus + trophy_bonus + crown_bonus
		scores.append({"player_index": owner, "name": (str(avatar.definition.name) if avatar != null else "Black Rose") if owner == -1 else "Player " + str(owner + 1), "base": base, "quests": quest_bonus, "trophies": trophy_bonus, "crown": crown_bonus, "total": total})
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
		"school_id": spell.school_id,
		"dark_playable": spell.is_playable_side(true)
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
		"assigned_mage": evocation.assigned_mage, "assigned_slot": evocation.assigned_slot,
		"upgrades": evocation.upgrades.duplicate(), "stored_trophies": evocation.stored_trophies.duplicate(),
		"health": evocation.health,
		"damage": evocation.get_damage(),
		"strength": get_evocation_effective_strength(evocation),
		"base_strength": evocation.strength,
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
	var is_owner_view: bool = viewer_player_index == player_index and player.avatar == null
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
		"starved_cubes": player.starved_cubes,
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
			"damage_cubes": mage.damage_cubes.duplicate(),
			"destiny_tokens": mage.destiny_tokens.duplicate(),
			"infectio_tokens": mage.infectio_tokens.duplicate()
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
	result["transformation"] = _beta_revealed_spell_data(player.transformation) if player.transformation != null else {}

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

	# Memories are the public Spell discard pile. Their identities are visible
	# to every player; only Hand / prepared-hidden information stays private.
	var memories_data: Array = []
	for spell in player.memories:
		if spell != null:
			memories_data.append(_beta_spell_public_data(spell))
	result["memories"] = memories_data

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

	if preparation_parallel_active and current_phase == PHASE_PREPARATION:
		if preparation_parallel_requests.has(viewer_player_index):
			var prep_request: Dictionary = preparation_parallel_requests[viewer_player_index]
			return prep_request.duplicate(true)
		return {
			"type": "preparation_waiting",
			"phase": PHASE_PREPARATION,
			"player_index": viewer_player_index,
			"private": true
		}

	if study_parallel_active and current_phase == PHASE_STUDY:
		if study_parallel_requests.has(viewer_player_index):
			var viewer_request: Dictionary = study_parallel_requests[viewer_player_index]
			return viewer_request.duplicate(true)
		# A player who already finished Study sees no other player's private
		# request while the remaining seats finish concurrently.
		return {
			"type": "study_waiting",
			"phase": PHASE_STUDY,
			"player_index": viewer_player_index,
			"private": true
		}

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
	if target_player_index >= 0 and ForgottenPassives.value(players[target_player_index], "cannot_be_evocation_attack_target") > 0:
		return false
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

	var attack_room_id: String = (
		expected_room_id
		if expected_room_id != ""
		else evocation.room_id
	)

	var attack_coord: Vector2i = room_id_to_coord(
		attack_room_id
	)
	var target_coord: Vector2i = room_id_to_coord(
		target_mage.room_id
	)

	if attack_coord == Vector2i(9999, 9999) \
	or target_coord == Vector2i(9999, 9999):
		return false

	return get_hex_distance(
		attack_coord,
		target_coord
	) <= get_evocation_attack_range(evocation)


func _valid_evocation_attack_evocation(
	evocation: EvocationState,
	controller_id: int,
	target_evocation: EvocationState,
	expected_room_id: String = ""
) -> bool:
	if target_evocation != null and not ForgottenEvocations.ability(self, target_evocation, "cannot_be_physically_attacked").is_empty():
		return false
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

	if get_evocation_controller_id(
		target_evocation
	) == controller_id:
		return false

	var attack_room_id: String = (
		expected_room_id
		if expected_room_id != ""
		else evocation.room_id
	)

	var attack_coord: Vector2i = room_id_to_coord(
		attack_room_id
	)
	var target_coord: Vector2i = room_id_to_coord(
		target_evocation.room_id
	)

	if attack_coord == Vector2i(9999, 9999) \
	or target_coord == Vector2i(9999, 9999):
		return false

	return get_hex_distance(
		attack_coord,
		target_coord
	) <= get_evocation_attack_range(evocation)


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
	if not ForgottenEvocations.can_activate(self, evocation):
		return result
	if ForgottenEvocations.extended(self, evocation):
		return [{"label": "Activate " + evocation.get_display_name(), "path": [], "context": {"extended_activation": true}}]

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

	if bool(context.get("extended_activation", false)) and ForgottenEvocations.extended(self, evocation):
		return ForgottenEvocations.can_activate(self, evocation)
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

		DruidicRules.on_evocation_attack(self, evocation, controller_id)
		deal_damage_from_evocation(
			evocation,
			target_player_index,
			activation_strength,
			controller_id
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

		DruidicRules.on_evocation_attack(self, evocation, controller_id)
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

		if evocation != null and evocation.assigned_mage >= 0:
			continue
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
	actions.append_array(DruidicRules.action_options(self, player_index))
	actions.append_array(EquipmentRules.actions(self, player_index))

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

func request_chaos_reveal_ack(
	player_index: int,
	spell: SpellCardState,
	context: Dictionary,
	context_key: String
) -> bool:
	if waiting_for_player_input or spell == null:
		return false
	if player_index < 0 or player_index >= players.size():
		return false

	pending_chaos_reveal_context = context
	pending_chaos_reveal_context_key = context_key
	pending_chaos_reveal_player_index = player_index

	var requested: bool = request_player_input({
		"type": "chaos_reveal_ack",
		"phase": current_phase,
		"player_index": player_index,
		"spell_id": spell.id,
		"spell_name": spell.card_name,
		"school_id": spell.school_id,
		"prompt": "Chaos: revealed " + spell.card_name + ". Click the card to continue."
	})
	if not requested:
		pending_chaos_reveal_context = {}
		pending_chaos_reveal_context_key = ""
		pending_chaos_reveal_player_index = -1
		return false

	_show_chaos_reveal_overlay(spell)
	return true


func _show_chaos_reveal_overlay(spell: SpellCardState, player_index: int = -1) -> void:
	_hide_chaos_reveal_overlay()
	if spell == null:
		return
	if player_index < 0:
		player_index = pending_chaos_reveal_player_index

	var preview = get_node_or_null("SpellCardPreview")
	if preview == null:
		preview = spell_preview_script.new()
		preview.name = "SpellCardPreview"
		add_child(preview)
	# A Grimoire reveal is upright, so always show the Light side.
	preview.show_spell(
		spell.id,
		spell.card_name,
		spell.school_id,
		false,
		true
	)

	chaos_reveal_click_layer = CanvasLayer.new()
	chaos_reveal_click_layer.layer = 1200
	chaos_reveal_click_layer.name = "ChaosRevealClickLayer"
	add_child(chaos_reveal_click_layer)

	var click_blocker := Button.new()
	click_blocker.position = Vector2.ZERO
	click_blocker.size = get_viewport_rect().size
	click_blocker.flat = true
	click_blocker.text = ""
	click_blocker.focus_mode = Control.FOCUS_NONE
	click_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty_style := StyleBoxEmpty.new()
	click_blocker.add_theme_stylebox_override("normal", empty_style)
	click_blocker.add_theme_stylebox_override("hover", empty_style)
	click_blocker.add_theme_stylebox_override("pressed", empty_style)
	click_blocker.pressed.connect(
		_on_chaos_reveal_clicked.bind(player_index),
		CONNECT_DEFERRED
	)
	chaos_reveal_click_layer.add_child(click_blocker)

	var hint := Label.new()
	hint.text = "CLICK TO CONTINUE"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0.0, get_viewport_rect().size.y - 58.0)
	hint.size = Vector2(get_viewport_rect().size.x, 40.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color.WHITE)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	chaos_reveal_click_layer.add_child(hint)


func _hide_chaos_reveal_overlay() -> void:
	if is_instance_valid(chaos_reveal_click_layer):
		chaos_reveal_click_layer.queue_free()
	chaos_reveal_click_layer = null
	var preview = get_node_or_null("SpellCardPreview")
	if preview != null:
		preview.hide_preview()


func _on_chaos_reveal_clicked(player_index: int) -> void:
	submit_beta_input(player_index, {"acknowledge": true})


func submit_chaos_reveal_ack(player_index: int) -> bool:
	if not waiting_for_player_input \
	or str(pending_input.get("type", "")) != "chaos_reveal_ack":
		return false
	if player_index != int(pending_input.get("player_index", -1)) \
	or player_index != pending_chaos_reveal_player_index:
		return false
	if pending_chaos_reveal_context.is_empty() \
	or pending_chaos_reveal_context_key == "":
		return false

	_set_interactive_effect_choice(
		pending_chaos_reveal_context,
		pending_chaos_reveal_context_key,
		true
	)
	pending_chaos_reveal_context = {}
	pending_chaos_reveal_context_key = ""
	pending_chaos_reveal_player_index = -1
	_hide_chaos_reveal_overlay()
	clear_player_input()
	return process_resolution_stack()


func get_beta_supported_input_types() -> Array[String]:
	return [
		"final_winner_choice",
		"starting_mage_choice",
		"starting_school_choice",
		"starting_grimoire_choice",
		"effect_choice",
		"chaos_reveal_ack",
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

	if preparation_parallel_active and current_phase == PHASE_PREPARATION:
		return _submit_parallel_preparation(player_index, payload)

	if study_parallel_active and current_phase == PHASE_STUDY:
		return _submit_parallel_study_input(player_index, payload)

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

		"chaos_reveal_ack":
			return submit_chaos_reveal_ack(player_index)

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

	# Validate the Personal Spell before mutating either the Library or
	# the player's zones. This keeps setup atomic if mage data is incomplete.
	var personal_spell: SpellCardState = (
		create_personal_spell_copy(
			player.personal_spell_id
		)
	)

	if personal_spell == null:
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

	starting_setup_order = AvatarRules.human_order(self)

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
	apply_mage_forgotten_exclusions()
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
		player.get_mage_speed()
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
	return queue_resolution({"type": "forgotten_end_black_rose", "on_complete": "finish_black_rose"})


func _finish_black_rose_phase_after_upgrades() -> bool:
	if current_phase != PHASE_BLACK_ROSE:
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


func connect_card_choice(button: Button, option: Dictionary, callback: Callable) -> void:
	if not bool(option.get("hidden", false)) and (str(option.get("card_kind", "")) == "spells" or option.has("spell_id") or str(option.get("slot_id", "")) != ""):
		button.tooltip_text += "\nClick to select · Shift-click to inspect"
		# Read Shift while the signal is emitted, before deferring either action.
		# Deferring only the action also keeps selection from freeing its emitter.
		button.pressed.connect(_on_card_choice_pressed.bind(option, callback))
	else:
		button.pressed.connect(callback, CONNECT_DEFERRED)


func _on_card_choice_pressed(option: Dictionary, callback: Callable) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		_inspect_card_choice.call_deferred(option)
	else:
		callback.call_deferred()


func _inspect_card_choice(option: Dictionary) -> void:
	var slot_id: String = str(option.get("slot_id", ""))
	if slot_id != "":
		open_player_board_spell(int(option.get("board_player_index", -1)), slot_id)
	else:
		_reference_card_preview().show_card("spells", str(option.get("id", option.get("spell_id", ""))), str(option.get("name", "Spell")), "")


func _evocation_board_card(owner_index: int, evocation: EvocationState) -> Control:
	if owner_index < 0 or owner_index >= player_boards.size():
		return null
	var cards = player_boards[owner_index].get_node_or_null("EvocationCards")
	if cards != null:
		for card in cards.get_children():
			if card.has_meta("evocation") and card.get_meta("evocation") == evocation:
				return card
	return null


func show_board_target_choice(option: Dictionary, callback: Callable, selected: bool = false) -> bool:
	var token: String = str(option.get("token", ""))
	var target: Node = null
	var position_in_target := Vector2(-24, -24)
	var hit_size := Vector2(48, 48)
	var board_index: int = int(option.get("board_player_index", -1))
	if board_index >= 0 and board_index < player_boards.size():
		var slot_id: String = str(option.get("slot_id", ""))
		if slot_id != "" and get_player_board_spell_slot_data(board_index, slot_id).get("can_inspect", false):
			var slot_name: String = "QuickSpellSlot" if slot_id == "Q" else "SpellSlot" + slot_id
			target = player_boards[board_index].get_node_or_null("SpellSlots/" + slot_name)
		elif option.has("quest_index"):
			var section: String = str(option.get("quest_section", "revealed"))
			var quests: Array = players[board_index].completed_quests if section == "completed" else players[board_index].active_quests
			var index: int = int(option.quest_index)
			var strip = player_boards[board_index].get_node_or_null("Quest_" + section)
			if index >= 0 and index < quests.size() and can_inspect_quest(quests[index]) and strip != null:
				for row in strip.get_children():
					for card in row.get_children():
						if card.get_meta("choice_quest", null) == quests[index]:
							target = card
		if target is Control:
			position_in_target = Vector2.ZERO
			hit_size = target.size
	elif token.begins_with("damage:") or token.begins_with("instability:"):
		var parts := token.split(":")
		# Area conversions include the recipient in the token so cubes on
		# different Models remain distinct. Owner/ordinal are always last.
		var valid_cube_token: bool = parts.size() == 3 \
			or (parts.size() == 5 and parts[0] == "damage" and parts[1] == "mage") \
			or (parts.size() == 6 and parts[0] == "damage" and parts[1] == "evocation")
		if not valid_cube_token:
			return false
		var cube_owner: int = int(parts[parts.size() - 2])
		var cube_ordinal: int = int(parts[parts.size() - 1])
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
				if evocation == null:
					return false
				owners = evocation.damage_cubes
				if evocation.archetype == "equipment":
					board_index = int(option.cube_evocation_owner)
					var card := _evocation_board_card(board_index, evocation)
					if card == null or card.get_node_or_null("EvocationDamage") == null:
						return false
					nodes = card.get_node("EvocationDamage").get_children()
				else:
					if not evocation_tokens.has(evocation.get_instance_id()):
						return false
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
			if int(owners[i]) == cube_owner:
				if ordinal == cube_ordinal:
					target = nodes[i]
					break
				ordinal += 1
		# Slightly larger hit/highlight area makes multi-cube conversion choices
		# readable; selected cubes also receive the explicit checkmark below.
		position_in_target = Vector2(-7, -7)
		hit_size = Vector2(28, 28)
	elif int(option.get("evocation_index", -1)) >= 0:
		var evocation = get_evocation_by_owner_index(int(option.get("owner_id", -1)), int(option.evocation_index))
		if evocation != null:
			target = evocation_tokens.get(evocation.get_instance_id())
			if evocation.archetype == "equipment":
				board_index = int(option.get("owner_id", -1))
				target = _evocation_board_card(board_index, evocation)
				if target != null:
					position_in_target = Vector2.ZERO
					hit_size = target.size
	elif option.has("player_index"):
		var index: int = int(option.player_index)
		if index >= 0 and index < mage_tokens.size():
			target = mage_tokens[index]
	if target == null:
		return false
	if table_shell != null:
		if board_index >= 0:
			table_shell.reveal_board_choice(board_index)
		elif token.begins_with("instability:") or str(option.get("cube_room_id", "")) != "":
			# Instability cubes live on the Lodge. Never open a PlayerBoard just
			# because the public choice also carries a player index.
			table_shell.close_board()
		elif option.has("cube_evocation_owner"):
			table_shell.close_board()
		elif option.has("cube_player_index"):
			table_shell.reveal_board_choice(int(option.cube_player_index))
		else:
			table_shell.close_board()
	var portrait_choice: bool = target.has_method("has_portrait") and target.has_portrait()
	var button: Button = target.create_target_button() if portrait_choice else Button.new()
	var overlay_parent: Node = target
	var overlay_position: Vector2 = position_in_target
	# Quest/Spell cards are themselves Buttons. Put the choice hitbox on the
	# PlayerBoard root, above the card, so the inspection callback underneath
	# cannot also fire (Pleasures Room discard, card-selection effects, etc.).
	if board_index >= 0 and board_index < player_boards.size() and target is Control:
		overlay_parent = player_boards[board_index]
		overlay_position = (
			player_boards[board_index].get_global_transform().affine_inverse()
			* target.get_global_transform().origin
		)
	button.position = overlay_position
	button.size = hit_size
	button.z_index = 1000
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = str(option.get("name", token))
	button.text = "✓" if selected else ""
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color.BLACK)
	button.add_theme_constant_override("outline_size", 4)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.75, 0.34, 0.62) if selected else Color(1, 0.8, 0.15, 0.08)
	style.border_color = Color(0.55, 1.0, 0.62) if selected else Color(1, 0.8, 0.15)
	style.set_border_width_all(4 if selected else 2)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.25, 0.85, 0.42, 0.72) if selected else Color(1, 0.8, 0.15, 0.22)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	if portrait_choice:
		target.style_target_button(button, selected)
	button.add_to_group("board_target_choices")
	button.set_meta("choice_token", token)
	connect_card_choice(button, option, callback)
	overlay_parent.add_child(button)
	return true


func clear_lodge_room_choices() -> void:
	for node in get_tree().get_nodes_in_group("lodge_room_choices"):
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.hide()
		node.queue_free()

func show_lodge_room_choices(callbacks: Dictionary, selected_rooms: Array[String] = []) -> void:
	if table_shell != null:
		table_shell.close_board()
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
