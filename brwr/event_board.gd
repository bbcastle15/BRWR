extends Control


# =========================================================
# RESOURCES
# =========================================================

var cube_scene = preload("res://cube.tscn")


# =========================================================
# EVENT BOARD GEOMETRY
# =========================================================

const SMALL_CARD_SIZE = Vector2(80, 52)

const R = 70.0
const CENTER_Y = 325.0

const RECT_X = 145.0
const RECT_WIDTH = 161.0

const RECT_TOP = 60.0
const RECT_BOTTOM = 590.0

const SLOT_GAP = 6.0


# =========================================================
# BLACK ROSE CUBES
# =========================================================

const BLACK_ROSE_MAX_CUBES: int = 30

var black_rose_cube_count: int = (
	BLACK_ROSE_MAX_CUBES
)


# =========================================================
# QUESTS
#
# Per ora EventBoard mantiene solamente il discard
# delle Quest.
#
# Gli Event NON vengono conservati qui:
#
# Game.event_decks
# Game.active_events
# Game.event_discard
# Game.current_moon
#
# sono l'unica fonte dello stato Event.
# =========================================================

var quest_discard: Array = []


# =========================================================
# READY
# =========================================================

func _ready():

	create_board_shape()

	await get_tree().process_frame

	setup_event_slots()
	setup_lower_slots()

	create_cube_pool_ui()
	update_black_rose_cube_pool()


# =========================================================
# EVENT UI
# =========================================================

func refresh_event_slots():

	var game = get_parent()


	if game == null:
		return


	# -----------------------------------------------------
	# ACTIVE EVENTS
	# -----------------------------------------------------

	show_event_in_slot(
		$ActiveEvent1,
		game.active_events[0]
	)


	show_event_in_slot(
		$ActiveEvent2,
		game.active_events[1]
	)


	show_event_in_slot(
		$ActiveEvent3,
		game.active_events[2]
	)


	# -----------------------------------------------------
	# DECK / DISCARD
	# -----------------------------------------------------

	update_event_deck_label()
	update_event_discard_label()
	show_event_in_slot($EventDiscardSlot, game.event_discard.back() if not game.event_discard.is_empty() else null)


# =========================================================
# SHOW EVENT
#
# EventCardState non è CardState.
#
# Card art and enlarged inspection project the existing EventCardState.
# =========================================================

func show_event_in_slot(
	slot: Control,
	event: EventCardState
):

	var old_view = slot.get_node_or_null(
		"EventView"
	)


	if old_view != null:
		old_view.free()


	if event == null:
		return


	var game = get_parent()
	var view = game.ReferenceCardPreview.make_card("events", event.id, event.event_name,
		SMALL_CARD_SIZE, game.open_event_card.bind(event), true)
	view.name = "EventView"
	slot.add_child(view)


# =========================================================
# EVENT DECK LABEL
# =========================================================

func update_event_deck_label():

	var game = get_parent()


	if game == null:
		return


	var label = (
		$EventDeckSlot
		.get_node_or_null(
			"Label"
		)
	)


	if label == null:
		return


	var moon: int = (
		game.current_moon
	)


	var deck_size: int = 0


	if game.event_decks.has(
		moon
	):

		deck_size = (
			game.event_decks[
				moon
			].size()
		)


	label.text = (
		"EVENT DECK\n"
		+ "Moon "
		+ str(moon)
		+ "\n"
		+ str(deck_size)
	)


# =========================================================
# EVENT DISCARD LABEL
# =========================================================

func update_event_discard_label():

	var game = get_parent()


	if game == null:
		return


	var label = (
		$EventDiscardSlot
		.get_node_or_null(
			"Label"
		)
	)


	if label == null:
		return


	label.text = (
		"DISCARD\n"
		+ str(
			game.event_discard.size()
		)
	)


# =========================================================
# MOON UI UPDATE
#
# La Moon vera è Game.current_moon.
# EventBoard non conserva una seconda copia dello stato.
# =========================================================

func set_moon(
	moon: int
):

	print(
		"Event Board changed to Moon ",
		moon
	)


	update_event_deck_label()


# =========================================================
# BLACK ROSE CUBE POOL UI
# =========================================================

func create_cube_pool_ui():

	var pool = $BlackRoseCubePool


	if pool.get_node_or_null(
		"CubePreview"
	) == null:

		var cube = cube_scene.instantiate()

		cube.name = "CubePreview"

		cube.owner_type = (
			cube.OwnerType.BLACK_ROSE
		)

		cube.cube_color = Color.BLACK

		cube.position = Vector2(
			8,
			14
		)


		pool.add_child(
			cube
		)


	if pool.get_node_or_null(
		"CountLabel"
	) == null:

		var label = Label.new()

		label.name = "CountLabel"

		label.position = Vector2(
			32,
			10
		)

		label.text = (
			"× "
			+ str(
				BLACK_ROSE_MAX_CUBES
			)
		)


		pool.add_child(
			label
		)


func update_black_rose_cube_pool():

	var label = (
		$BlackRoseCubePool
		.get_node_or_null(
			"CountLabel"
		)
	)


	if label != null:

		label.text = (
			"× "
			+ str(
				black_rose_cube_count
			)
		)


func set_black_rose_cube_count(
	value: int
):

	black_rose_cube_count = clamp(
		value,
		0,
		BLACK_ROSE_MAX_CUBES
	)


	update_black_rose_cube_pool()


func take_black_rose_cubes(
	amount: int
) -> int:

	var taken: int = min(
		max(
			amount,
			0
		),
		black_rose_cube_count
	)


	black_rose_cube_count -= (
		taken
	)


	update_black_rose_cube_pool()


	return taken


func return_black_rose_cubes(
	amount: int
):

	black_rose_cube_count = min(
		black_rose_cube_count
		+ max(
			amount,
			0
		),
		BLACK_ROSE_MAX_CUBES
	)


	update_black_rose_cube_pool()


# =========================================================
# BOARD SHAPE
# =========================================================

func create_board_shape():

	var shape = $BoardShape


	var half_r = (
		R / 2.0
	)

	var hex_h = (
		sqrt(3.0) * R
	)


	var upper_center_y = (
		CENTER_Y
		- hex_h / 2.0
	)

	var lower_center_y = (
		CENTER_Y
		+ hex_h / 2.0
	)


	var board_width = (
		RECT_X
		+ RECT_WIDTH
	)


	var points = PackedVector2Array([

		# Rettangolo superiore

		Vector2(
			0,
			RECT_TOP
		),

		Vector2(
			RECT_WIDTH,
			RECT_TOP
		),


		# Collegamento superiore

		Vector2(
			board_width - RECT_X,
			upper_center_y - hex_h / 2.0
		),

		Vector2(
			board_width - half_r,
			upper_center_y - hex_h / 2.0
		),


		# Punta superiore verso Lodge

		Vector2(
			board_width,
			upper_center_y
		),


		# Vertice centrale

		Vector2(
			board_width - half_r,
			CENTER_Y
		),


		# Punta inferiore verso Lodge

		Vector2(
			board_width,
			lower_center_y
		),

		Vector2(
			board_width - half_r,
			lower_center_y + hex_h / 2.0
		),


		# Collegamento inferiore

		Vector2(
			board_width - RECT_X,
			lower_center_y + hex_h / 2.0
		),

		Vector2(
			RECT_WIDTH,
			RECT_BOTTOM
		),


		# Rettangolo inferiore

		Vector2(
			0,
			RECT_BOTTOM
		)
	])


	shape.polygon = points

	shape.color = Color(
		0.10,
		0.10,
		0.10
	)


# =========================================================
# EVENT SLOT LAYOUT
# =========================================================

func setup_event_slots():

	var rect_center_x = (
		RECT_WIDTH / 2.0
	)


	var slot_x = (
		rect_center_x
		- SMALL_CARD_SIZE.x / 2.0
	)


	var total_height = (
		SMALL_CARD_SIZE.y * 5.0
		+ SLOT_GAP * 4.0
	)


	var available_height = (
		RECT_BOTTOM
		- RECT_TOP
	)


	var start_y = (
		RECT_TOP
		+ available_height / 2.0
		- total_height / 2.0
	)


	# -----------------------------------------------------
	# EVENT DISCARD
	# -----------------------------------------------------

	setup_card_slot(
		$EventDiscardSlot,
		Vector2(
			slot_x,
			start_y
		),
		"EVENT\nDISCARD"
	)


	# -----------------------------------------------------
	# ACTIVE EVENT 3
	# -----------------------------------------------------

	setup_card_slot(
		$ActiveEvent3,
		Vector2(
			slot_x,
			start_y
			+ (
				SMALL_CARD_SIZE.y
				+ SLOT_GAP
			)
		),
		"EVENT 3"
	)


	# -----------------------------------------------------
	# ACTIVE EVENT 2
	# -----------------------------------------------------

	setup_card_slot(
		$ActiveEvent2,
		Vector2(
			slot_x,
			start_y
			+ (
				SMALL_CARD_SIZE.y
				+ SLOT_GAP
			) * 2.0
		),
		"EVENT 2"
	)


	# -----------------------------------------------------
	# ACTIVE EVENT 1
	# -----------------------------------------------------

	setup_card_slot(
		$ActiveEvent1,
		Vector2(
			slot_x,
			start_y
			+ (
				SMALL_CARD_SIZE.y
				+ SLOT_GAP
			) * 3.0
		),
		"EVENT 1"
	)


	# -----------------------------------------------------
	# EVENT DECK
	# -----------------------------------------------------

	setup_card_slot(
		$EventDeckSlot,
		Vector2(
			slot_x,
			start_y
			+ (
				SMALL_CARD_SIZE.y
				+ SLOT_GAP
			) * 4.0
		),
		"EVENT\nDECK"
	)


# =========================================================
# GENERIC CARD SLOT
# =========================================================

func setup_card_slot(
	slot: Control,
	slot_position: Vector2,
	label_text: String
):

	slot.position = (
		slot_position
	)

	slot.size = (
		SMALL_CARD_SIZE
	)

	slot.custom_minimum_size = (
		SMALL_CARD_SIZE
	)


	var label = slot.get_node_or_null(
		"Label"
	)


	if label == null:

		label = Label.new()

		label.name = "Label"

		slot.add_child(
			label
		)


	label.position = Vector2.ZERO

	label.size = (
		SMALL_CARD_SIZE
	)


	label.text = (
		label_text
	)


	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)


# =========================================================
# LOWER BOARD SLOTS
# =========================================================

func setup_lower_slots():

	var hex_h = (
		sqrt(3.0) * R
	)


	var upper_center_y = (
		CENTER_Y
		- hex_h / 2.0
	)

	var lower_center_y = (
		CENTER_Y
		+ hex_h / 2.0
	)


	var board_width = (
		RECT_X
		+ RECT_WIDTH
	)


	var irregular_center_x = (
		board_width
		- 105.0
	)


	# =====================================================
	# TROPHIES
	# =====================================================

	setup_card_slot(
		$BlackRoseTrophySlot,
		Vector2(
			irregular_center_x
			- SMALL_CARD_SIZE.x / 2.0,

			upper_center_y
			- SMALL_CARD_SIZE.y / 2.0
		),
		"TROPHIES"
	)


	# =====================================================
	# BLACK ROSE CUBE POOL
	# =====================================================

	var cube_pool_size = Vector2(
		80,
		45
	)


	$BlackRoseCubePool.size = (
		cube_pool_size
	)

	$BlackRoseCubePool.custom_minimum_size = (
		cube_pool_size
	)


	$BlackRoseCubePool.position = Vector2(

		irregular_center_x
		- cube_pool_size.x / 2.0,

		lower_center_y
		- cube_pool_size.y / 2.0
	)


	# =====================================================
	# QUEST DISCARD
	# =====================================================

	setup_card_slot(
		$QuestDiscardSlot,
		Vector2(
			irregular_center_x
			- SMALL_CARD_SIZE.x / 2.0,

			CENTER_Y
			- SMALL_CARD_SIZE.y / 2.0
		),
		"QUEST\nDISCARD"
	)
