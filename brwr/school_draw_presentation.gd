extends CanvasLayer

# A one-off public reveal of the already selected Library. Never uses Game.rng
# or changes the selection, and stays alive (hidden) to prevent snapshot replays.
signal finished

const Style = preload("res://tabletop_style.gd")
const CardPreview = preload("res://reference_card_preview.gd")
const BACK = preload("res://assets/tabletop/card_back.png")
const TITLE_FONT = preload("res://assets/fonts/library_title.ttf")
const DESIGN_SIZE := Vector2(1600, 900)
const CARD_SIZE := Vector2(210, 315)
const DEAL_START := 1.7
const DEAL_INTERVAL := 0.85

var school_ids: Array[String] = []
var root: Control
var stage: Control
var deck: Control
var packets: Array[Control] = []
var cards: Array[Control] = []
var names: Array[Label] = []
var status: Label
var skip_button: Button
var timeline: Tween
var playing := false
var revealed_count := 0


func present(game) -> void:
	if root != null: return
	school_ids.assign(game.active_school_ids)
	if school_ids.is_empty(): return
	layer = 180
	playing = true
	_build(game)
	_layout()
	root.resized.connect(_layout)
	_animate()


func _build(game) -> void:
	root = Control.new()
	root.name = "SchoolDraw"
	root.theme = Style.make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.gui_input.connect(func(_event): root.accept_event())
	var background := TextureRect.new()
	background.texture = preload("res://assets/tabletop/playmat.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate = Color(0.42, 0.45, 0.46)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage = Control.new()
	stage.name = "Stage"
	stage.size = DESIGN_SIZE
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stage)
	_label("BLACK ROSE WARS · REBIRTH", Vector2(100, 61), Vector2(1400, 30), 17, Style.GOLD)
	var title := _label("The Library", Vector2(100, 98), Vector2(1400, 72), 56, Style.PAPER)
	title.add_theme_font_override("font", TITLE_FONT)
	status = _label("Shuffling the Schools…", Vector2(100, 183), Vector2(1400, 34), 22, Style.MUTED)
	for x in [200, 865]:
		var rule := ColorRect.new()
		rule.position = Vector2(x, 235)
		rule.size = Vector2(535, 1)
		rule.color = Color(0.71, 0.60, 0.39, 0.45)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(rule)
	_label("✦", Vector2(760, 216), Vector2(80, 38), 30, Style.GOLD)

	var gap := 22.0
	var total := school_ids.size() * CARD_SIZE.x + (school_ids.size() - 1) * gap
	for i in school_ids.size():
		var position := Vector2((DESIGN_SIZE.x - total) / 2.0 + i * (CARD_SIZE.x + gap), 300)
		var slot := Panel.new()
		slot.position = position
		slot.size = CARD_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", Style.panel(Color("484136"), Color(0.03, 0.04, 0.05, 0.48)))
		stage.add_child(slot)
		_label("%02d" % (i + 1), position - Vector2(0, 26), Vector2(CARD_SIZE.x, 22), 14, Style.GOLD)
		var name_label := _label(game.get_school_display_name(school_ids[i]), position + Vector2(-9, CARD_SIZE.y + 16), Vector2(CARD_SIZE.x + 18, 42), 24, Style.PAPER)
		name_label.modulate.a = 0.0
		names.append(name_label)

	deck = Control.new()
	deck.name = "Deck"
	deck.position = Vector2(800, 460)
	deck.scale = Vector2.ONE * 0.88
	deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(deck)
	for i in 6:
		var packet := _card()
		packet.position = -CARD_SIZE * 0.5 + Vector2(i * 2, -i * 2)
		deck.add_child(packet)
		packets.append(packet)

	for i in school_ids.size():
		var card := _card()
		card.name = "School_" + school_ids[i]
		card.set_meta("school_id", school_ids[i])
		card.set_meta("front", CardPreview.card_texture("schools", school_ids[i]))
		card.set_meta("destination", Vector2((DESIGN_SIZE.x - total) / 2.0 + i * (CARD_SIZE.x + gap), 300))
		card.position = Vector2(800, 747) - CARD_SIZE * 0.5
		card.scale = Vector2.ONE * 0.48
		card.visible = false
		stage.add_child(card)
		cards.append(card)

	skip_button = Button.new()
	skip_button.name = "Skip"
	skip_button.text = "Skip animation"
	skip_button.tooltip_text = "Reveal all Schools, then Continue"
	skip_button.position = Vector2(1320, 810)
	skip_button.size = Vector2(220, 52)
	skip_button.add_theme_font_size_override("font_size", 19)
	skip_button.pressed.connect(_continue_or_reveal)
	stage.add_child(skip_button)
	var hint := _label("These Schools will be available throughout this game.", Vector2(250, 757), Vector2(1100, 34), 20, Style.MUTED)
	hint.name = "Hint"
	hint.modulate.a = 0


func _label(text: String, position: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	stage.add_child(label)
	return label


func _card() -> Control:
	var frame := Panel.new()
	frame.size = CARD_SIZE
	frame.pivot_offset = CARD_SIZE * 0.5
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := Style.panel(Style.GOLD, Color("151b20"), 2)
	edge.shadow_color = Color(0, 0, 0, 0.65)
	edge.shadow_size = 15
	edge.shadow_offset = Vector2(0, 9)
	frame.add_theme_stylebox_override("panel", edge)
	var art := TextureRect.new()
	art.name = "Art"
	art.texture = BACK
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(3, 3)
	art.size = CARD_SIZE - Vector2(6, 6)
	frame.add_child(art)
	return frame


func _layout() -> void:
	var fit := minf(root.size.x / DESIGN_SIZE.x, root.size.y / DESIGN_SIZE.y)
	stage.scale = Vector2.ONE * fit
	stage.position = (root.size - DESIGN_SIZE * fit) * 0.5


func _shuffle(progress: float) -> void:
	# Alternating packets cross over one another; no gameplay RNG is consumed.
	for i in packets.size():
		var wave := sin(progress * TAU * 2.5 + (PI if i % 2 else 0.0)) * sin(progress * PI)
		packets[i].position = -CARD_SIZE * 0.5 + Vector2(i * 2 + wave * (65 + i * 5), -i * 2 - absf(wave) * 12)
		packets[i].rotation = wave * 0.12
		packets[i].z_index = i if wave >= 0 else 6 - i


func _animate() -> void:
	root.modulate.a = 0
	timeline = create_tween().set_parallel(true)
	timeline.tween_property(root, "modulate:a", 1.0, 0.22)
	timeline.tween_method(_shuffle, 0.0, 1.0, 1.35).set_delay(0.10)
	timeline.tween_property(deck, "position", Vector2(800, 747), 0.35).set_delay(1.45).set_trans(Tween.TRANS_SINE)
	timeline.tween_property(deck, "scale", Vector2.ONE * 0.48, 0.35).set_delay(1.45).set_trans(Tween.TRANS_SINE)
	for i in cards.size():
		var start := DEAL_START + i * DEAL_INTERVAL
		var card := cards[i]
		timeline.tween_callback(_begin_deal.bind(i)).set_delay(start)
		timeline.tween_property(card, "position", card.get_meta("destination"), 0.42).set_delay(start).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		timeline.tween_property(card, "scale", Vector2.ONE, 0.42).set_delay(start).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		timeline.tween_property(card, "scale:x", 0.015, 0.12).set_delay(start + 0.42).from(1.0).set_trans(Tween.TRANS_SINE)
		timeline.tween_callback(_reveal.bind(i)).set_delay(start + 0.54)
		timeline.tween_property(card, "scale:x", 1.0, 0.18).set_delay(start + 0.54).from(0.015).set_trans(Tween.TRANS_SINE)
		timeline.tween_property(names[i], "modulate:a", 1.0, 0.22).set_delay(start + 0.59)
	var complete := DEAL_START + (cards.size() - 1) * DEAL_INTERVAL + 0.81
	timeline.tween_property(deck, "modulate:a", 0.0, 0.3).set_delay(complete - 0.4)
	timeline.tween_callback(func():
		status.text = "The Schools are chosen."
		skip_button.text = "Continue").set_delay(complete)
	timeline.tween_property(stage.get_node("Hint"), "modulate:a", 1.0, 0.25).set_delay(complete)
	# The selected Schools stay readable until this viewer explicitly continues.

func _continue_or_reveal() -> void:
	if revealed_count == cards.size():
		finish()
		return
	if timeline != null: timeline.kill()
	root.modulate.a = 1.0
	deck.hide()
	for i in cards.size():
		cards[i].show()
		cards[i].position = cards[i].get_meta("destination")
		cards[i].scale = Vector2.ONE
		cards[i].get_node("Art").texture = cards[i].get_meta("front")
		names[i].modulate.a = 1.0
	revealed_count = cards.size()
	status.text = "The Schools are chosen."
	skip_button.text = "Continue"
	stage.get_node("Hint").modulate.a = 1.0


func _begin_deal(index: int) -> void:
	cards[index].show()
	status.text = "Drawing School %d of %d" % [index + 1, cards.size()]


func _reveal(index: int) -> void:
	cards[index].get_node("Art").texture = cards[index].get_meta("front")
	revealed_count += 1


func finish() -> void:
	if not playing: return
	playing = false
	if timeline != null: timeline.kill()
	root.hide()
	set_process_input(false)
	finished.emit()


func _input(event: InputEvent) -> void:
	if not playing: return
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
			_continue_or_reveal()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
