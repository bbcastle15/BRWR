extends Control

var card_view_scene = preload("res://card_view.tscn")

var event_decks: Dictionary = {
	1: [],
	2: [],
	3: []
}

var current_moon: int = 1

var active_event_cards: Array = [
	null,
	null,
	null
]

var discarded_event_cards: Array[CardState] = []
var cube_scene = preload("res://cube.tscn")

const SMALL_CARD_SIZE = Vector2(80, 52)

# Stessa geometria della Power Board
const R = 70.0
const CENTER_Y = 325.0

const RECT_X = 145.0
const RECT_WIDTH = 161.0

const RECT_TOP = 60.0
const RECT_BOTTOM = 590.0

const SLOT_GAP = 6.0

const BLACK_ROSE_MAX_CUBES: int = 30

var black_rose_cube_count: int = BLACK_ROSE_MAX_CUBES

var active_events: Array = [
	null,
	null,
	null
]

var event_discard: Array = []
var quest_discard: Array = []

func initialize_events(rng: RandomNumberGenerator):
	load_event_database()
	shuffle_event_decks(rng)

	current_moon = 1

	refresh_event_slots()
	
func shuffle_event_decks(rng: RandomNumberGenerator):
	for moon in [1, 2, 3]:
		var deck: Array = event_decks[moon]

		for i in range(deck.size() - 1, 0, -1):
			var j = rng.randi_range(0, i)

			var temp = deck[i]
			deck[i] = deck[j]
			deck[j] = temp
func refresh_event_slots():
	show_card_in_slot(
		$ActiveEvent1,
		active_event_cards[0]
	)

	show_card_in_slot(
		$ActiveEvent2,
		active_event_cards[1]
	)

	show_card_in_slot(
		$ActiveEvent3,
		active_event_cards[2]
	)
	update_event_deck_label()
	update_event_discard_label()

func update_event_deck_label():
	var label = $EventDeckSlot.get_node_or_null("Label")

	if label != null:
		label.text = (
			"EVENT DECK\n"
			+ "Moon " + str(current_moon)
			+ "\n"
			+ str(event_decks[current_moon].size())
		)
func update_event_discard_label():
	var label = $EventDiscardSlot.get_node_or_null("Label")

	if label != null:
		label.text = (
			"DISCARD\n"
			+ str(discarded_event_cards.size())
		)
func show_card_in_slot(slot: Control, card: CardState):
	var old_view = slot.get_node_or_null("CardView")

	if old_view != null:
		old_view.queue_free()

	if card == null:
		return

	var view = card_view_scene.instantiate()
	view.name = "CardView"

	slot.add_child(view)

	view.position = Vector2.ZERO
	view.setup(card)

func _ready():
	create_board_shape()

	await get_tree().process_frame

	setup_event_slots()
	setup_lower_slots()

	create_cube_pool_ui()
	update_black_rose_cube_pool()
	
func create_cube_pool_ui():
	var pool = $BlackRoseCubePool

	if pool.get_node_or_null("CubePreview") == null:
		var cube = cube_scene.instantiate()
		cube.name = "CubePreview"
		cube.owner_type = cube.OwnerType.BLACK_ROSE
		cube.cube_color = Color.BLACK
		cube.position = Vector2(8, 14)

		pool.add_child(cube)

	if pool.get_node_or_null("CountLabel") == null:
		var label = Label.new()
		label.name = "CountLabel"
		label.position = Vector2(32, 10)
		label.text = "× 30"

		pool.add_child(label)
	
func update_black_rose_cube_pool():
	var label = $BlackRoseCubePool.get_node_or_null("CountLabel")

	if label != null:
		label.text = "× " + str(black_rose_cube_count)
		
		
func set_black_rose_cube_count(value: int):
	black_rose_cube_count = clamp(
		value,
		0,
		BLACK_ROSE_MAX_CUBES
	)
	update_black_rose_cube_pool()


func take_black_rose_cubes(amount: int) -> int:
	var taken = min(
		max(amount, 0),
		black_rose_cube_count
	)

	black_rose_cube_count -= taken

	update_black_rose_cube_pool()

	return taken



func return_black_rose_cubes(amount: int):
	black_rose_cube_count = min(
		black_rose_cube_count + max(amount, 0),
		BLACK_ROSE_MAX_CUBES
	)

	update_black_rose_cube_pool()

func create_board_shape():
	var shape = $BoardShape

	var half_r = R / 2.0
	var hex_h = sqrt(3.0) * R

	var upper_center_y = CENTER_Y - hex_h / 2.0
	var lower_center_y = CENTER_Y + hex_h / 2.0

	var board_width = RECT_X + RECT_WIDTH

	var points = PackedVector2Array([
		# Rettangolo: alto sinistra → alto destra
		Vector2(0, RECT_TOP),
		Vector2(RECT_WIDTH, RECT_TOP),

		# Collegamento superiore verso la zona sagomata
		Vector2(
			board_width - RECT_X,
			upper_center_y - hex_h / 2.0
		),

		Vector2(
			board_width - half_r,
			upper_center_y - hex_h / 2.0
		),

		# Punta superiore verso la Lodge
		Vector2(
			board_width,
			upper_center_y
		),

		# Vertice condiviso centrale
		Vector2(
			board_width - half_r,
			CENTER_Y
		),

		# Punta inferiore verso la Lodge
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

		Vector2(RECT_WIDTH, RECT_BOTTOM),

		# Rettangolo inferiore
		Vector2(0, RECT_BOTTOM)
	])

	shape.polygon = points
	shape.color = Color(0.10, 0.10, 0.10)

func setup_event_slots():
	var rect_center_x = RECT_WIDTH / 2.0

	var slot_x = (
		rect_center_x
		- SMALL_CARD_SIZE.x / 2.0
	)

	var total_height = (
		SMALL_CARD_SIZE.y * 5.0
		+ SLOT_GAP * 4.0
	)

	var available_height = RECT_BOTTOM - RECT_TOP

	var start_y = (
		RECT_TOP
		+ available_height / 2.0
		- total_height / 2.0
	)

	setup_card_slot(
		$EventDiscardSlot,
		Vector2(slot_x, start_y),
		"EVENT\nDISCARD"
	)

	setup_card_slot(
		$ActiveEvent3,
		Vector2(
			slot_x,
			start_y + (SMALL_CARD_SIZE.y + SLOT_GAP)
		),
		"EVENT 3"
	)

	setup_card_slot(
		$ActiveEvent2,
		Vector2(
			slot_x,
			start_y + (SMALL_CARD_SIZE.y + SLOT_GAP) * 2.0
		),
		"EVENT 2"
	)

	setup_card_slot(
		$ActiveEvent1,
		Vector2(
			slot_x,
			start_y + (SMALL_CARD_SIZE.y + SLOT_GAP) * 3.0
		),
		"EVENT 1"
	)

	setup_card_slot(
		$EventDeckSlot,
		Vector2(
			slot_x,
			start_y + (SMALL_CARD_SIZE.y + SLOT_GAP) * 4.0
		),
		"EVENT\nDECK"
	)
	
func setup_card_slot(
	slot: Control,
	slot_position: Vector2,
	label_text: String
):
	slot.position = slot_position
	slot.size = SMALL_CARD_SIZE
	slot.custom_minimum_size = SMALL_CARD_SIZE

	var label = slot.get_node_or_null("Label")

	if label == null:
		label = Label.new()
		label.name = "Label"
		slot.add_child(label)

	label.position = Vector2.ZERO
	label.size = SMALL_CARD_SIZE

	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
func setup_lower_slots():
	var hex_h = sqrt(3.0) * R

	var upper_center_y = CENTER_Y - hex_h / 2.0
	var lower_center_y = CENTER_Y + hex_h / 2.0

	var board_width = RECT_X + RECT_WIDTH
	var irregular_center_x = board_width - 105.0

	# Trophy nella parte superiore
	setup_card_slot(
		$BlackRoseTrophySlot,
		Vector2(
			irregular_center_x - SMALL_CARD_SIZE.x / 2.0,
			upper_center_y - SMALL_CARD_SIZE.y / 2.0
		),
		"TROPHIES"
	)

	# Black Rose cubes nella parte inferiore
	var cube_pool_size = Vector2(80, 45)

	$BlackRoseCubePool.size = cube_pool_size
	$BlackRoseCubePool.custom_minimum_size = cube_pool_size

	$BlackRoseCubePool.position = Vector2(
		irregular_center_x - cube_pool_size.x / 2.0,
		lower_center_y - cube_pool_size.y / 2.0
	)

	# Quest discard al centro
	setup_card_slot(
		$QuestDiscardSlot,
		Vector2(
			irregular_center_x - SMALL_CARD_SIZE.x / 2.0,
			CENTER_Y - SMALL_CARD_SIZE.y / 2.0
		),
		"QUEST\nDISCARD"
	)
	
func load_event_database():
	event_decks[1].clear()
	event_decks[2].clear()
	event_decks[3].clear()

	var file = FileAccess.open(
		"res://data/events.json",
		FileAccess.READ
	)

	if file == null:
		print("ERRORE: impossibile aprire events.json")
		return

	var json_data = JSON.parse_string(file.get_as_text())

	if json_data == null:
		print("ERRORE: events.json non valido")
		return

	for event_data in json_data:
		var card = CardState.new(
			event_data["id"],
			event_data["name"],
			CardState.CardType.EVENT,
			event_data
		)

		var moon = int(event_data.get("moon", 1))

		if moon >= 1 and moon <= 3:
			event_decks[moon].append(card)

	print(
		"Events loaded | Moon 1: ",
		event_decks[1].size(),
		" | Moon 2: ",
		event_decks[2].size(),
		" | Moon 3: ",
		event_decks[3].size()
	)

func shift_events():
	if active_event_cards[2] != null:
		discarded_event_cards.append(
			active_event_cards[2]
		)

		print(
			"Event shifted to discard: ",
			active_event_cards[2].card_name
		)

	active_event_cards[2] = active_event_cards[1]
	active_event_cards[1] = active_event_cards[0]
	active_event_cards[0] = null

	refresh_event_slots()

func draw_and_place_event():
	var card = draw_event()

	if card == null:
		return

	var slot_number = int(card.data.get("slot", 1))

	place_event(card, slot_number)
	
func place_event(card: CardState, slot_number: int):
	# Gli slot validi sono 1, 2, 3
	slot_number = clamp(slot_number, 1, 3)

	# Convertiamo:
	# slot 1 -> indice 0
	# slot 2 -> indice 1
	# slot 3 -> indice 2
	var index = slot_number - 1

	var card_to_place = card

	while card_to_place != null:
		# Se siamo usciti dallo slot 3,
		# la carta finisce nel discard.
		if index >= active_event_cards.size():
			discarded_event_cards.append(card_to_place)

			print(
				"Event discarded: ",
				card_to_place.card_name
			)

			break

		# Salviamo l'eventuale carta già presente.
		var displaced_card = active_event_cards[index]

		# Inseriamo la nuova carta.
		active_event_cards[index] = card_to_place

		print(
			card_to_place.card_name,
			" placed in Event Slot ",
			index + 1
		)

		# La carta che c'era prima viene spinta
		# nello slot successivo.
		card_to_place = displaced_card
		index += 1

	refresh_event_slots()
	
func draw_event() -> CardState:
	var deck: Array = event_decks[current_moon]

	if deck.is_empty():
		print("Event deck empty for Moon ", current_moon)
		return null

	var card = deck.pop_back()

	print(
		"Event drawn: ",
		card.card_name,
		" | Moon ",
		current_moon
	)

	return card
	
func set_moon(moon: int):
	moon = clamp(moon, 1, 3)

	if moon == current_moon:
		return

	current_moon = moon

	print("Event Board changed to Moon ", current_moon)

	update_event_deck_label()
