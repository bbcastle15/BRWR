extends CanvasLayer

var root: Control
var title_label: Label
var art: TextureRect
var description: RichTextLabel
var panel: PanelContainer
var pile_controls: HBoxContainer
var pile_cards: Array = []
var pile_index := 0
var pile_title := ""
var pile_kind := "spells"
var pile_description := Callable()

# Readable fallback while a card illustration has not yet been supplied.
static func describe_rules(value: Variant) -> String:
	if value is Dictionary:
		var lines: PackedStringArray = []
		for key in value:
			lines.append(str(key).replace("_", " ").capitalize() + ": " + describe_rules(value[key]))
		return "\n".join(lines)
	if value is Array:
		var lines: PackedStringArray = []
		for item in value:
			lines.append(describe_rules(item))
		return "\n\n".join(lines)
	return str(value).replace("_", " ")

static func card_texture(kind: String, id: String) -> Texture2D:
	var avatar_texture := AvatarArt.texture(id)
	if avatar_texture != null: return avatar_texture
	if kind == "spells":
		return SpellArtResolver.get_texture(id)
	# Keep the supplied filename; resource paths are case-sensitive in Web exports.
	if kind == "mages" and id == "landolfo_ii":
		id = "landolfo_II"
	var aliases: Dictionary = {
		"evocations": {"eros_bow": "firos_bow", "talos_corset": "taloss_corset"},
		"upgrades": {"cerebral_implant": "cerebreal_implant", "grafted_crossbow": "crafted_crossbow"},
		"jinxs": {"locusts": "locust"}
	}.get(kind, {})
	if aliases.has(id) and not ResourceLoader.exists("res://assets/" + kind + "/" + id + ".png"):
		id = aliases[id]
	for base in ["res://assets/", "res://assets/cards/"]:
		for extension in ["png", "webp", "jpg"]:
			var path: String = base + kind + "/" + id + "." + extension
			if ResourceLoader.exists(path):
				return load(path) as Texture2D
	return null

static func make_card(kind: String, id: String, title: String, card_size: Vector2, callback: Callable, rotate_art: bool = false) -> Button:
	var button := Button.new()
	button.custom_minimum_size = card_size
	button.size = card_size
	button.tooltip_text = title + " — Inspect"
	button.pressed.connect(callback)
	var texture := card_texture(kind, id)
	if texture == null:
		button.text = title
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if rotate_art:
			# Portrait source fills the landscape slot after a clockwise quarter-turn.
			image.size = Vector2(card_size.y, card_size.x)
			image.position = Vector2(card_size.x, 0)
			image.rotation = PI / 2.0
		else:
			image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(image)
	return button

static func make_back(title: String, card_size: Vector2, callback: Callable = Callable()) -> Button:
	var button := Button.new()
	button.custom_minimum_size = card_size
	button.size = card_size
	button.tooltip_text = title
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	if callback.is_valid():
		button.pressed.connect(callback, CONNECT_DEFERRED)
	var image := TextureRect.new()
	image.name = "CardBack"
	image.texture = preload("res://assets/tabletop/card_back.png")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return button

func _ready() -> void:
	layer = 151
	root = Control.new()
	root.theme = preload("res://tabletop_style.gd").make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 650)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_outline_color", Color("0b1012"))
	title_label.add_theme_constant_override("outline_size", 6)
	column.add_child(title_label)
	art = TextureRect.new()
	art.custom_minimum_size = Vector2(480, 460)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(art)
	description = RichTextLabel.new()
	description.custom_minimum_size = Vector2(480, 150)
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(description)
	pile_controls = HBoxContainer.new()
	pile_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(pile_controls)
	for direction in [-1, 1]:
		var arrow := Button.new()
		arrow.text = "‹ Previous" if direction == -1 else "Next ›"
		arrow.pressed.connect(_browse_pile.bind(direction))
		pile_controls.add_child(arrow)
	pile_controls.hide()
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide_preview)
	column.add_child(close)
	hide_preview()

func show_card(kind: String, id: String, title: String, text: String) -> void:
	# Until the user supplies artwork, expose the printed rules from the same
	# database used by the engine, including previews during Mage selection.
	if text.is_empty() and card_texture(kind, id) == null:
		var game = get_parent()
		if kind == "spells" and game.get("spell_database") != null:
			var spell: SpellCardState = game.spell_database.get_spell(id)
			if spell != null:
				for face in ["light", "dark"]:
					var side: Dictionary = spell.get_side(face == "dark")
					if side.has("text"):
						text += "%s · %s · %s · %s %s\n%s\n\n" % [face.capitalize(), str(side.type).capitalize(), str(side.element).capitalize(), str(side.target).capitalize(), str(side.get("range", "")).trim_suffix(".0"), str(side.text)]
		elif kind == "schools" and game.get("school_specialization_database") != null:
			text = str(game.school_specialization_database.get(id, {}).get("description", ""))
	pile_controls.hide()
	title_label.text = title
	art.texture = card_texture(kind, id)
	art.visible = art.texture != null
	description.text = text
	description.visible = not text.is_empty()
	if art.texture != null and (kind == "avatars" or (kind == "spells" and id.begins_with("possessed_"))):
		var view := get_viewport().get_visible_rect().size
		var ratio: float = art.texture.get_size().aspect()
		var height := minf(view.y - (320 if description.visible else 230), (view.x - 120) / ratio)
		art.custom_minimum_size = Vector2(height * ratio, height)
		description.custom_minimum_size = Vector2(height * ratio, 80)
		panel.custom_minimum_size = Vector2.ZERO
	elif kind in ["evocations", "upgrades"]:
		var view := get_viewport().get_visible_rect().size
		var width := minf(view.x - 96.0, 1100.0)
		var height := maxf(180.0, view.y - 330.0)
		if art.texture != null:
			height = minf(height, width / art.texture.get_size().aspect())
			width = height * art.texture.get_size().aspect()
		art.custom_minimum_size = Vector2(width, height)
		description.custom_minimum_size = Vector2(width, 64 if art.texture != null else 280)
		panel.custom_minimum_size = Vector2.ZERO
	elif kind == "schools" and art.texture != null:
		# The rules are printed on the School card: give the image the available
		# height instead of reserving an empty description box below it.
		var height := clampf(get_viewport().get_visible_rect().size.y - 140.0, 240.0, 1000.0)
		art.custom_minimum_size = Vector2(height * art.texture.get_size().aspect(), height)
		description.custom_minimum_size = Vector2(480, 150)
		panel.custom_minimum_size = Vector2.ZERO
	else:
		art.custom_minimum_size = Vector2(480, 460)
		description.custom_minimum_size = Vector2(480, 150)
		panel.custom_minimum_size = Vector2(520, 650)
	panel.size = panel.get_combined_minimum_size()
	root.show()

func show_spell_pile(cards: Array, title: String) -> void:
	pile_kind = "spells"
	pile_description = Callable()
	pile_cards = cards.duplicate()
	pile_title = title
	pile_index = maxi(0, pile_cards.size() - 1)
	_browse_pile(0)

func show_reference_pile(kind: String, cards: Array, title: String, describe: Callable = Callable()) -> void:
	pile_kind = kind
	pile_cards = cards.duplicate()
	pile_title = title
	pile_description = describe
	pile_index = 0
	_browse_pile(0)

func _browse_pile(direction: int) -> void:
	if pile_cards.is_empty():
		show_card(pile_kind, "", pile_title, "No discarded Spells." if pile_kind == "spells" else "No cards.")
		return
	pile_index = clampi(pile_index + direction, 0, pile_cards.size() - 1)
	var card = pile_cards[pile_index]
	var title := "%s · %d / %d" % [pile_title, pile_index + 1, pile_cards.size()]
	if pile_kind == "spells":
		show_card("spells", card.id, title, "")
		art.texture = SpellArtResolver.get_texture(card.id, card.school_id)
	else:
		var text: String = str(pile_description.call(card)) if pile_description.is_valid() else ""
		show_card(pile_kind, str(card.id), str(card.get("name", card.id)) + " · " + title, text)
	pile_controls.show()
	pile_controls.get_child(0).disabled = pile_index == 0
	pile_controls.get_child(1).disabled = pile_index == pile_cards.size() - 1

func hide_preview() -> void:
	root.hide()

func _unhandled_input(event: InputEvent) -> void:
	if root.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_preview()
		get_viewport().set_input_as_handled()
