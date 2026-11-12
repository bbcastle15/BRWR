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
var _event_views: Dictionary = {}
var _track_initialized := false
const EVENT_SLIDE_SECONDS := 0.52
var _trophy_snapshot: Array = []
var _quest_top: QuestCardState
var _starved_snapshot: Array = []

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
	var browse := Button.new()
	browse.flat = true
	browse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browse.tooltip_text = "Browse Event discards"
	browse.pressed.connect(open_event_pile.bind(-1))
	$EventDiscardSlot.add_child(browse)
	_make_badge($EventDiscardSlot, "Label", Vector2(0, -13)).z_index = 2

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

func open_event_pile(slot_index: int = -1) -> void:
	var game = get_parent()
	var cards: Array = game.event_discard if slot_index < 0 else EventTrack.cards_in(game.active_events, slot_index)
	var entries := []
	for i in range(cards.size() - 1, -1, -1):
		var event: EventCardState = cards[i]
		entries.append({"id": event.id, "name": event.event_name,
			"text": "Moon %d · %s\n\n%s" % [event.moon, event.phase.capitalize(), event.text]})
	game.inspected_quest = null
	var title: String = "Event discards" if slot_index < 0 else "Event slot " + ["I", "II", "III"][slot_index]
	game._reference_card_preview().show_reference_pile("events", entries, title, func(entry): return entry.text)

func _inspect_event(id: String) -> void:
	var game = get_parent()
	for i in game.active_events.size():
		for card in EventTrack.cards_in(game.active_events, i):
			if card.id == id:
				open_event_pile(i)
				return
	open_event_pile(-1)

func _position_event(event: EventCardState, slot: Control, offset: Vector2, animate: bool) -> Button:
	var view: Button = _event_views.get(event.id)
	var start: Vector2 = $EventDeckSlot.position
	if view == null:
		view = get_parent().ReferenceCardPreview.make_card("events", event.id, event.event_name,
			slot.size, _inspect_event.bind(event.id), true)
		view.name = "Event_" + event.id
		_rotate_card_view(view, slot.size)
		_event_views[event.id] = view
	else:
		var old_slot: Control = view.get_parent()
		if old_slot == slot and view.get_meta("destination", Vector2.INF) == offset and animate:
			return view
		start = old_slot.position + view.position
		var tween: Tween = view.get_meta("slide") if view.has_meta("slide") else null
		if tween != null: tween.kill()
		old_slot.remove_child(view)
	slot.add_child(view)
	view.set_meta("destination", offset)
	view.position = start - slot.position if animate else offset
	if view.position != offset:
		var tween := view.create_tween()
		view.set_meta("slide", tween)
		tween.tween_property(view, "position", offset, EVENT_SLIDE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return view

func _remove_event_view(id: String) -> void:
	var view: Button = _event_views[id]
	_event_views.erase(id)
	view.get_parent().remove_child(view)
	view.queue_free()

func refresh_event_slots(animate: bool = true) -> void:
	if not _slots_ready:
		return
	var game = get_parent()
	animate = animate and _track_initialized
	_track_initialized = true
	var visible_ids := {}
	for i in game.active_events.size():
		var slot: Control = get_node("ActiveEvent" + str(i + 1))
		var cards := EventTrack.cards_in(game.active_events, i)
		for depth in cards.size():
			var card: EventCardState = cards[depth]
			var offset := Vector2(2.6, 2.2) * depth * minf(1.0, 3.0 / maxi(1, cards.size() - 1))
			var view := _position_event(card, slot, offset, animate)
			slot.move_child(view, -1)
			visible_ids[card.id] = true
	var top: EventCardState = null if game.event_discard.is_empty() else game.event_discard.back()
	if top != null:
		var view := _position_event(top, $EventDiscardSlot, Vector2.ZERO, animate)
		$EventDiscardSlot.move_child(view, -1)
		visible_ids[top.id] = true
	for id in _event_views.keys():
		if visible_ids.has(id): continue
		var view: Button = _event_views[id]
		var discarded: EventCardState = game.event_database.get_event(id)
		# Multiple cards can leave III at once. Let the buried ones arrive too.
		if animate and discarded != null and game.event_discard.has(discarded):
			if view.get_parent() != $EventDiscardSlot:
				_position_event(discarded, $EventDiscardSlot, Vector2.ZERO, true)
				$EventDiscardSlot.move_child(view, 0)
			var slide: Tween = view.get_meta("slide") if view.has_meta("slide") else null
			if slide != null and slide.is_running():
				var finish := _finish_discard_slide.bind(id)
				if not slide.finished.is_connected(finish): slide.finished.connect(finish, CONNECT_ONE_SHOT)
				continue
		_remove_event_view(id)
	update_event_deck_label()
	update_event_discard_label()
	refresh_support_slots()

func _finish_discard_slide(id: String) -> void:
	var view: Button = _event_views.get(id)
	var discard: Array = get_parent().event_discard
	if view != null and view.get_parent() == $EventDiscardSlot and (discard.is_empty() or discard.back().id != id):
		_remove_event_view(id)

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
	var game = get_parent()
	var starved: Array = game.players.map(func(player): return player.starved_cubes)
	var has_starved: bool = starved.any(func(amount): return amount > 0)
	for i in range(BLACK_ROSE_MAX_CUBES):
		var cube = $BlackRoseCubePool.get_child(i)
		cube.visible = i < black_rose_cube_count
		cube.position = Vector2(10 + (i % 10) * 6, 2 + (i / 10) * 6) if has_starved else Vector2(12 + (i % 6) * 9, (i / 6) * 9)
		cube.scale = Vector2.ONE * (0.35 if has_starved else 0.55)
	$BlackRoseCubePool/CountLabel.text = "× %d" % black_rose_cube_count
	$BlackRoseCubePool/CountLabel.position.y = 54 if has_starved else 46
	var details: PackedStringArray = ["Black Rose reserve: %d Cubes" % black_rose_cube_count]
	for owner in game.players.size():
		if game.players[owner].starved_cubes > 0:
			details.append("%s: %d Starved Cubes (unavailable)" % [game.players[owner].player_name, game.players[owner].starved_cubes])
	$BlackRoseCubePool.tooltip_text = "\n".join(details)
	if starved == _starved_snapshot:
		return
	_starved_snapshot = starved
	_remove_view($BlackRoseCubePool, "StarvedCubes")
	var layer := Control.new()
	layer.name = "StarvedCubes"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$BlackRoseCubePool.add_child(layer)
	for owner in game.players.size():
		var amount: int = game.players[owner].starved_cubes
		if amount <= 0:
			continue
		for i in amount:
			var cube = cube_scene.instantiate()
			cube.cube_color = game.players[owner].color
			cube.position = Vector2(10 + i * 6, 23 + owner * 5)
			cube.scale = Vector2.ONE * 0.3
			layer.add_child(cube)

func refresh_support_slots() -> void:
	if not _slots_ready:
		return
	var game = get_parent()
	update_black_rose_cube_pool()
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
	if _trophy_snapshot != game.black_rose_trophies or $BlackRoseTrophySlot.get_node_or_null("TrophyCount") == null:
		_trophy_snapshot = game.black_rose_trophies.duplicate()
		for child in $BlackRoseTrophySlot.get_children():
			$BlackRoseTrophySlot.remove_child(child)
			child.queue_free()
		for i in range(_trophy_snapshot.size()):
			var owner: int = int(_trophy_snapshot[i])
			var token = preload("res://tabletop_style.gd").marker("trophy_token", game.players[owner].color, Vector2(28, 28))
			$BlackRoseTrophySlot.add_child(token)
			token.position = Vector2(4 + (i % 4) * 13, 8 + (i / 4) * 8)
			token.tooltip_text = "Trophy · Player %d" % [owner + 1]
		var inspect := Button.new()
		inspect.name = "TrophyCount"
		inspect.flat = true
		inspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inspect.tooltip_text = "Black Rose · %d trophies" % _trophy_snapshot.size()
		inspect.pressed.connect(func(): game._reference_card_preview().show_card("tokens", "trophy_token", "Black Rose trophies", "%d trophies" % game.black_rose_trophies.size()))
		$BlackRoseTrophySlot.add_child(inspect)

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
