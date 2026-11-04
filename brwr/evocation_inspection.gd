extends CanvasLayer

const Style = preload("res://tabletop_style.gd")
const Art = preload("res://reference_card_preview.gd")
var game
var panel: PanelContainer
var title_label: Label
var location_label: Label
var stats: HBoxContainer
var cards: HBoxContainer
var signature := ""

func _ready() -> void:
	layer = 152
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = Style.make_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	panel = PanelContainer.new()
	var fabric := Style.fabric_panel()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		fabric.set_content_margin(side, 36)
	panel.add_theme_stylebox_override("panel", fabric)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", Style.panel(Style.GOLD.darkened(0.4)))
	column.add_child(header_panel)
	var header := HBoxContainer.new()
	header_panel.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Style.GOLD)
	heading.add_child(title_label)
	location_label = Label.new()
	heading.add_child(location_label)
	var close := Button.new()
	close.text = "Close ×"
	close.pressed.connect(hide)
	header.add_child(close)
	stats = HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	column.add_child(stats)
	column.add_child(HSeparator.new())
	cards = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 20)
	column.add_child(cards)
	get_viewport().size_changed.connect(func(): signature = "")
	hide()

func refresh(ev: EvocationState) -> void:
	var room = game.get_room_by_id(ev.room_id)
	var view := get_viewport().get_visible_rect().size
	var key := str([ev.get_instance_id(), ev.get_damage(), ev.health, ev.speed,
		game.get_evocation_effective_strength(ev), ev.room_id, ev.upgrades, ev.stored_trophies,
		game.get_evocation_controller_id(ev), ev.familiar_guard, ev.familiar_action_available, view])
	if key == signature: return
	signature = key
	title_label.text = ev.get_display_name()
	location_label.text = "%s · Controlled by %s" % [room.room_name if room != null else ev.room_id.capitalize(), game.player_display_name(game.get_evocation_controller_id(ev))]
	if ev.assigned_mage >= 0: location_label.text += " · Assigned to %s, slot %d" % [game.player_display_name(ev.assigned_mage), ev.assigned_slot]
	if FamiliarRules.is_familiar(ev): location_label.text += " · %s · Familiar Action %s" % ["Guard" if ev.familiar_guard else "Hunt","available" if ev.familiar_action_available else "exhausted"]
	for container in [stats, cards]:
		for node in container.get_children():
			container.remove_child(node)
			node.queue_free()
	var values := [["HEALTH", "%d / %d" % [ev.get_remaining_health(), ev.health]], ["DAMAGE", str(ev.get_damage())],
		["SPEED", str(ev.speed)], ["STRENGTH", str(game.get_evocation_effective_strength(ev))]]
	if not ev.stored_trophies.is_empty(): values.append(["TROPHIES", str(ev.stored_trophies.size())])
	for pair in values:
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_stylebox_override("panel", Style.panel(Style.GOLD.darkened(0.4)))
		stats.add_child(chip)
		var label := Label.new()
		label.text = "%s\n%s" % pair
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_child(label)
	var width := minf(1200, view.x - 140)
	var height := maxf(180, view.y - 340)
	var has_upgrades := not ev.upgrades.is_empty()
	var main_width := width * (0.59 if has_upgrades else 1.0)
	_add_art(cards, "evocations", ev.evocation_id, Vector2(main_width, minf(height, main_width / 1.5)))
	if has_upgrades:
		var upgrades := VBoxContainer.new()
		cards.add_child(upgrades)
		var label := Label.new()
		label.text = "ASSIGNED UPGRADES"
		label.add_theme_color_override("font_color", Style.GOLD)
		upgrades.add_child(label)
		for id in ev.upgrades:
			_add_art(upgrades, "upgrades", id, Vector2(width * 0.39, minf((height - 35) / ev.upgrades.size(), width * 0.39 / 1.5)))
	panel.size = panel.get_combined_minimum_size()

func _add_art(parent: Control, kind: String, id: String, extent: Vector2) -> void:
	var image := TextureRect.new()
	image.texture = Art.card_texture(kind, id)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = extent
	parent.add_child(image)
	if image.texture == null:
		var label := Label.new()
		label.text = id.capitalize()
		image.add_child(label)

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
