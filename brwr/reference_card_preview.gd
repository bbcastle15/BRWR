extends CanvasLayer

var root: Control
var title_label: Label
var art: TextureRect
var description: RichTextLabel

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

func _ready() -> void:
	layer = 151
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 650)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 24)
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
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide_preview)
	column.add_child(close)
	hide_preview()

func show_card(kind: String, id: String, title: String, text: String) -> void:
	title_label.text = title
	art.texture = card_texture(kind, id)
	art.visible = art.texture != null
	description.text = text
	root.show()

func hide_preview() -> void:
	root.hide()
