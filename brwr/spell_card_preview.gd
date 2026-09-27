class_name SpellCardPreview
extends CanvasLayer

var root: Control
var title_label: Label
var side_label: Label
var image: TextureRect
var fallback_label: Label

func _ready() -> void:
	layer = 150
	_build_ui()
	hide_preview()


func _build_ui() -> void:
	root = Control.new()
	root.name = "SpellCardPreviewRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 760)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.075, 0.985)
	style.border_color = Color(0.35, 0.35, 0.38, 1.0)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)

	var header_text := VBoxContainer.new()
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_text)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	header_text.add_child(title_label)

	side_label = Label.new()
	side_label.add_theme_font_size_override("font_size", 15)
	side_label.modulate = Color(0.86, 0.79, 0.58)
	header_text.add_child(side_label)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(90, 42)
	close_button.pressed.connect(hide_preview)
	header.add_child(close_button)

	column.add_child(HSeparator.new())

	image = TextureRect.new()
	image.custom_minimum_size = Vector2(440, 615)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(image)

	fallback_label = Label.new()
	fallback_label.custom_minimum_size = Vector2(440, 615)
	fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fallback_label.add_theme_font_size_override("font_size", 20)
	column.add_child(fallback_label)


func show_spell(
	spell_id: String,
	spell_name: String,
	school_id: String,
	use_dark_side: bool,
	public_card: bool
) -> void:
	var texture: Texture2D = SpellArtResolver.get_texture(spell_id, school_id)

	title_label.text = spell_name
	side_label.text = (
		("Played • " if public_card else "Prepared • ")
		+ ("Dark" if use_dark_side else "Light")
	)

	if texture != null:
		image.texture = texture
		image.visible = true
		fallback_label.visible = false
	else:
		image.texture = null
		image.visible = false
		fallback_label.visible = true
		fallback_label.text = (
			spell_name
			+ "\n\nCard image not found for:\n"
			+ spell_id
			+ ".png"
		)

	root.visible = true


func hide_preview() -> void:
	if root != null:
		root.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if root == null or not root.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		hide_preview()
