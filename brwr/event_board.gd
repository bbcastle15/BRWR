extends Control

const ART_SIZE = Vector2(232, 312)
const ART_ORIGIN = Vector2(0, 176)
const SOURCE_SIZE = Vector2(1081, 1455)
const LODGE_NOTCH = Vector2(190, 325)
const SMALL_CARD_SIZE = Vector2(78, 48)
const BLACK_ROSE_MAX_CUBES: int = 30

var cube_scene = preload("res://cube.tscn")
# Preserve the existing pool API used by Game; visual nodes never own cubes.
var black_rose_cube_count: int = BLACK_ROSE_MAX_CUBES
var _slots_ready := false
var _trophy_snapshot: Array = []
var _quest_top: QuestCardState

func _ready() -> void:
	create_board_shape()
	setup_event_slots()
	setup_lower_slots()
	create_cube_pool_ui()
	_slots_ready = true
	update_black_rose_cube_pool()
	await get_tree().process_frame
	refresh_event_slots()

func _art_point(point: Vector2) -> Vector2:
	return ART_ORIGIN + point / SOURCE_SIZE * ART_SIZE

func create_board_shape() -> void:
	# Keep a physical outline for Game's camera and PlayerBoard layout bounds.
	var outline := PackedVector2Array([Vector2(24, 6), Vector2(552, 6),
		Vector2(629, 140), Vector2(920, 140), Vector2(1080, 380),
		Vector2(884, 636), Vector2(884, 714), Vector2(1080, 1010),
		Vector2(911, 1263), Vector2(625, 1263), Vector2(519, 1440), Vector2(24, 1440)])
	var points := PackedVector2Array()
	for point in outline:
		points.append(_art_point(point))
	$BoardShape.polygon = points
	$BoardShape.hide()
	$Title.hide()
	var art := TextureRect.new()
	art.name = "EventBoardArt"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture = preload("res://assets/boards/event_board_reference.png")
	art.position = ART_ORIGIN
	art.size = ART_SIZE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	move_child(art, 0)

func setup_card_slot(slot: Control, slot_position: Vector2, label_text: String, slot_size: Vector2 = SMALL_CARD_SIZE) -> void:
	slot.position = slot_position
	slot.custom_minimum_size = slot_size
	slot.size = slot_size
	slot.tooltip_text = label_text
	slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	slot.mouse_filter = Control.MOUSE_FILTER_PASS

func setup_event_slots() -> void:
	setup_card_slot($EventDiscardSlot, _art_point(Vector2(85, 60)), "Event discard")
	setup_card_slot($ActiveEvent3, _art_point(Vector2(141, 306)), "Event III")
	setup_card_slot($ActiveEvent2, _art_point(Vector2(141, 563)), "Event II")
	setup_card_slot($ActiveEvent1, _art_point(Vector2(141, 825)), "Event I")
	setup_card_slot($EventDeckSlot, _art_point(Vector2(89, 1087)), "Event deck")
	_make_badge($EventDeckSlot, "Label", Vector2(0, SMALL_CARD_SIZE.y + 3))
	_make_badge($EventDiscardSlot, "Label", Vector2(0, -13))

func setup_lower_slots() -> void:
	setup_card_slot($BlackRoseTrophySlot, _art_point(Vector2(565, 265)), "Black Rose trophies", Vector2(78, 54))
	setup_card_slot($BlackRoseCubePool, _art_point(Vector2(565, 856)), "Black Rose cube reserve", Vector2(78, 60))
	setup_card_slot($QuestDiscardSlot, _art_point(Vector2(558, 571)), "Quest discard", Vector2(66, 48))
	_make_badge($QuestDiscardSlot, "CountLabel", Vector2(0, 49))

func _make_badge(parent: Control, badge_name: String, at: Vector2) -> Label:
	var label := Label.new()
	label.name = badge_name
	label.position = at
	label.size = Vector2(parent.size.x, 12)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.95, 0.87, 0.67))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _remove_view(slot: Control, view_name: String) -> void:
	var old_view = slot.get_node_or_null(view_name)
	if old_view != null:
		slot.remove_child(old_view)
		old_view.queue_free()

func _rotate_card_view(view: Button, card_size: Vector2) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		view.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	# Reuse card inspection, rotating only its art counterclockwise with the board.
	for child in view.get_children():
		if child is TextureRect:
			child.rotation = -PI / 2.0
			child.position = Vector2(0, card_size.y)

func show_event_in_slot(slot: Control, event: EventCardState) -> void:
	_remove_view(slot, "EventView")
	if event == null:
		return
	var game = get_parent()
	var view = game.ReferenceCardPreview.make_card("events", event.id, event.event_name,
		slot.size, game.open_event_card.bind(event), true)
	view.name = "EventView"
	_rotate_card_view(view, slot.size)
	slot.add_child(view)

func refresh_event_slots() -> void:
	if not _slots_ready:
		return
	var game = get_parent()
	for i in range(3):
		show_event_in_slot(get_node("ActiveEvent" + str(i + 1)), game.active_events[i])
	show_event_in_slot($EventDiscardSlot, game.event_discard.back() if not game.event_discard.is_empty() else null)
	update_event_deck_label()
	update_event_discard_label()
	refresh_support_slots()

func update_event_deck_label() -> void:
	if not _slots_ready:
		return
	var game = get_parent()
	var count: int = game.event_decks.get(game.current_moon, []).size()
	$EventDeckSlot/Label.text = "☾ %d · %d" % [game.current_moon, count]
	$EventDeckSlot.tooltip_text = "Moon %d · %d Events" % [game.current_moon, count]

func update_event_discard_label() -> void:
	if _slots_ready:
		$EventDiscardSlot/Label.text = str(get_parent().event_discard.size())

func set_moon(_moon: int) -> void:
	update_event_deck_label()

func create_cube_pool_ui() -> void:
	for i in range(BLACK_ROSE_MAX_CUBES):
		var cube = cube_scene.instantiate()
		cube.name = "CubePreview" if i == 0 else "Cube" + str(i)
		cube.cube_color = Color.BLACK
		cube.owner_type = cube.OwnerType.BLACK_ROSE
		cube.position = Vector2(12 + (i % 6) * 9, (i / 6) * 9)
		$BlackRoseCubePool.add_child(cube)
		cube.scale = Vector2.ONE * 0.55
	_make_badge($BlackRoseCubePool, "CountLabel", Vector2(0, 46))

func update_black_rose_cube_pool() -> void:
	if not _slots_ready:
		return
	for i in range(BLACK_ROSE_MAX_CUBES):
		$BlackRoseCubePool.get_child(i).visible = i < black_rose_cube_count
	$BlackRoseCubePool/CountLabel.text = "× %d" % black_rose_cube_count

func refresh_support_slots() -> void:
	if not _slots_ready:
		return
	var game = get_parent()
	var top: QuestCardState = game.quest_discard.back() if not game.quest_discard.is_empty() else null
	$QuestDiscardSlot/CountLabel.text = str(game.quest_discard.size())
	if top != _quest_top:
		_quest_top = top
		_remove_view($QuestDiscardSlot, "QuestView")
		if top != null:
			var view = game.ReferenceCardPreview.make_card("quests", top.id, top.card_name,
				$QuestDiscardSlot.size, game.open_discarded_quest_card.bind(top), true)
			view.name = "QuestView"
			_rotate_card_view(view, $QuestDiscardSlot.size)
			$QuestDiscardSlot.add_child(view)
	if _trophy_snapshot != game.black_rose_trophies:
		_trophy_snapshot = game.black_rose_trophies.duplicate()
		for child in $BlackRoseTrophySlot.get_children():
			$BlackRoseTrophySlot.remove_child(child)
			child.queue_free()
		for i in range(_trophy_snapshot.size()):
			var owner: int = int(_trophy_snapshot[i])
			var token = preload("res://power_marker.tscn").instantiate()
			token.marker_name = str(owner + 1)
			token.marker_color = [Color.RED, Color.BLUE, Color.GREEN, Color.PURPLE, Color.YELLOW, Color.WHITE][owner]
			$BlackRoseTrophySlot.add_child(token)
			token.scale = Vector2.ONE * 0.6
			token.position = Vector2(12 + (i % 5) * 13, 12 + (i / 5) * 13)
			token.tooltip_text = "Trophy · Player %d" % [owner + 1]

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
