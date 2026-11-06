extends "res://evocation_token.gd"

const INNER := 23.5
const RADIUS := 17.0
const DISTANCE := 26.0
const OUTER := DISTANCE + RADIUS
var sector := 0
var attached := true
var portrait_sprite: Sprite2D

class SectorButton extends Button:
	var sector := 0
	var attached := true
	var highlighted := false
	var selected := false
	func center_offset() -> Vector2:
		return Vector2.from_angle(-PI * 0.5 + (sector + 0.5) * TAU / 3.0) * DISTANCE if attached else Vector2.ZERO
	func _has_point(point: Vector2) -> bool:
		var delta := point - size * 0.5
		return delta.distance_to(center_offset()) <= RADIUS and (not attached or delta.length() >= INNER)
	func _draw() -> void:
		if not highlighted and not is_hovered(): return
		var center := size * 0.5
		var offset := center_offset()
		var points := PackedVector2Array()
		for i in 97:
			var point := offset + Vector2.from_angle(i * TAU / 96.0) * (RADIUS - 0.5)
			if not attached or point.length() >= INNER:
				points.append(point + center)
			elif points.size() > 1:
				draw_polyline(points, Color("baffc4") if selected else Color("ffdd88"), 1.6, true)
				points.clear()
		if points.size() > 1: draw_polyline(points, Color("baffc4") if selected else Color("ffdd88"), 1.6, true)

func _build_visual() -> void:
	portrait_sprite = Sprite2D.new()
	portrait_sprite.name = "Portrait"
	portrait_sprite.texture = _portrait
	if _portrait != null: portrait_sprite.scale = Vector2.ONE * RADIUS * 2.0 / _portrait.get_size()
	var mask := ShaderMaterial.new()
	mask.shader = preload("res://assets/tokens/attached_portrait.gdshader")
	mask.set_shader_parameter("cut_radius", INNER / (RADIUS * 2.0))
	if _portrait is AtlasTexture:
		var r: Rect2 = _portrait.region
		var extent: Vector2 = _portrait.atlas.get_size()
		mask.set_shader_parameter("portrait_region", Vector4(r.position.x / extent.x, r.position.y / extent.y, r.size.x / extent.x, r.size.y / extent.y))
	portrait_sprite.material = mask
	add_child(portrait_sprite)
	_inspect_button = create_target_button()
	_inspect_button.name = "InspectButton"
	_inspect_button.position = Vector2(-62, -62)
	_inspect_button.size = Vector2(124, 124)
	_inspect_button.pressed.connect(func(): inspect_requested.emit())
	add_child(_inspect_button)
	_name_tag = Label.new()
	_name_tag.name = "AssignedSlot"
	_name_tag.size = Vector2(18, 16)
	_name_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tag.add_theme_font_size_override("font_size", 11)
	_name_tag.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_tag.add_theme_constant_override("outline_size", 3)
	add_child(_name_tag)
	set_sector(0)

func set_attached(value: bool) -> void:
	attached = value
	set_sector(sector)

func set_sector(index: int) -> void:
	sector = posmod(index, 3)
	var offset := Vector2.from_angle(-PI * 0.5 + (sector + 0.5) * TAU / 3.0) * DISTANCE if attached else Vector2.ZERO
	if portrait_sprite != null:
		portrait_sprite.position = offset
		portrait_sprite.material.set_shader_parameter("mage_center", Vector2.ONE * 0.5 - offset / (RADIUS * 2.0))
		portrait_sprite.material.set_shader_parameter("rim_color", Color.BLACK if evocation_id == "umbra" else owner_color)
		portrait_sprite.material.set_shader_parameter("attached", attached)
	if _name_tag != null: _name_tag.position = offset + Vector2(-9, 1)
	for child in get_children():
		if child is SectorButton:
			child.sector = sector
			child.attached = attached
			child.queue_redraw()

func _draw() -> void:
	pass

func _refresh_details() -> void:
	if _inspect_button == null: return
	if _state != null:
		_inspect_button.tooltip_text = "%s · HP %d/%d\nClick to inspect" % [evocation_name, _state.get_remaining_health(), _state.health]
		_name_tag.text = str(_state.assigned_slot) if _state.assigned_mage >= 0 else str(board_number)

func sync_state(state: EvocationState, owner_index: int, color: Color) -> void:
	_state = state
	owner_id = owner_index
	owner_color = color
	board_number = state.board_number
	set_attached(state.assigned_mage >= 0 or FamiliarRules.guarded(state))
	_refresh_details()

func set_names_visible(_value: bool) -> void:
	pass

func create_visual_copy() -> Node2D:
	var copy = super.create_visual_copy()
	copy.set_attached(attached)
	copy.set_sector(sector)
	copy._name_tag.text = _name_tag.text
	return copy

func create_target_button() -> Button:
	var button := SectorButton.new()
	button.sector = sector
	button.attached = attached
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	for style_name in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	return button

func style_target_button(button: Button, selected: bool) -> void:
	button.position = Vector2(-62, -62)
	button.size = Vector2(124, 124)
	button.text = ""
	button.highlighted = true
	button.selected = selected
	button.sector = sector
	button.attached = attached
	button.queue_redraw()
