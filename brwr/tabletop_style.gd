extends RefCounted

const INK := Color("101519")
const PAPER := Color("efe4cd")
const GOLD := Color("b69a63")
const MUTED := Color("a5aaa7")

static func panel(accent: Color = GOLD, fill: Color = INK, border: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = accent
	box.set_border_width_all(border)
	box.set_corner_radius_all(8)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 9
	box.shadow_offset = Vector2(0, 4)
	return box

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Label", PAPER)
	result.set_stylebox("panel", "PanelContainer", panel())
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := Color("1b2328")
		var edge := Color("5b5343")
		if state in ["hover", "focus", "pressed"]:
			edge = GOLD
			fill = Color("30322b")
		if state == "disabled":
			fill = Color("151a1e")
			edge = Color("363a3c")
		result.set_stylebox(state, "Button", panel(edge, fill))
	result.set_color("font_color", "Button", PAPER)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", Color("666e72"))
	for state in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var selected: bool = state == "tab_selected"
		var tab := panel(GOLD if selected else Color("3e4849"), Color("25302e") if selected else Color("141c20"))
		tab.border_width_top = 3 if selected else 1
		tab.content_margin_left = 28
		tab.content_margin_right = 28
		tab.corner_radius_bottom_left = 0
		tab.corner_radius_bottom_right = 0
		result.set_stylebox(state, "TabBar", tab)
	result.set_color("font_selected_color", "TabBar", PAPER)
	result.set_color("font_unselected_color", "TabBar", MUTED)
	return result

static func marker(kind: String, player_color: Color, extent: Vector2 = Vector2(48, 48), slot_id: String = "") -> TextureRect:
	var art := TextureRect.new()
	art.texture = load("res://assets/tokens/" + kind.to_lower() + ".png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = extent
	art.size = extent
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/tokens/player_token.gdshader")
	material.set_shader_parameter("player_color", player_color)
	art.material = material
	if kind.to_lower() == "permanent" and not slot_id.is_empty():
		# Persistence tokens identify the originating physical Spell Slot (p.20).
		# The neutral starburst texture is shared; the slot comes from Game.
		if slot_id == "Q":
			var bolt := Polygon2D.new()
			bolt.name = "QuickSlot"
			var points := PackedVector2Array()
			for point in [Vector2(0.50, 0.34), Vector2(0.36, 0.52), Vector2(0.47, 0.52), Vector2(0.43, 0.66), Vector2(0.64, 0.44), Vector2(0.52, 0.44), Vector2(0.56, 0.34)]:
				points.append(point * extent)
			bolt.polygon = points
			bolt.color = PAPER
			art.add_child(bolt)
		else:
			var number := Label.new()
			number.name = "SpellSlot"
			number.text = slot_id
			number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			number.add_theme_font_size_override("font_size", roundi(extent.y * 0.20))
			number.add_theme_color_override("font_color", PAPER)
			number.add_theme_color_override("font_outline_color", Color("121212"))
			number.add_theme_constant_override("outline_size", maxi(1, roundi(extent.y * 0.02)))
			number.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.add_child(number)
	return art
