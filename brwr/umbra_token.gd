extends "res://evocation_token.gd"

# A projection of the assigned Evocation, clipped around its Mage's base.
# Each piece remains an independent inspection/target surface, including online.
const INNER := 23.5
const OUTER := 35.0
var sector := 0

class SectorButton extends Button:
	var sector := 0
	var highlighted := false
	var selected := false
	func _has_point(point: Vector2) -> bool:
		var delta := point - size * 0.5
		var angle := wrapf(delta.angle() + PI * 0.5 - sector * TAU / 3.0, 0, TAU)
		return delta.length() >= 23.5 and delta.length() <= 36.0 and angle <= TAU / 3.0
	func _draw() -> void:
		if not highlighted and not is_hovered(): return
		var start := -PI * 0.5 + sector * TAU / 3.0
		var color := Color("baffc4") if selected else Color("ffdd88")
		for radius in [24.0, 35.5]:
			draw_arc(size * 0.5, radius, start + 0.02, start + TAU / 3.0 - 0.02, 36, color, 1.6, true)
		for angle in [start + 0.02, start + TAU / 3.0 - 0.02]:
			draw_line(size * 0.5 + Vector2.from_angle(angle) * 24, size * 0.5 + Vector2.from_angle(angle) * 35.5, color, 1.6, true)

func _build_visual() -> void:
	_inspect_button = create_target_button()
	_inspect_button.name = "InspectButton"
	_inspect_button.position = Vector2(-36, -36)
	_inspect_button.size = Vector2(72, 72)
	_inspect_button.mouse_entered.connect(func(): _hovered = true; queue_redraw(); _inspect_button.queue_redraw())
	_inspect_button.mouse_exited.connect(func(): _hovered = false; queue_redraw(); _inspect_button.queue_redraw())
	_inspect_button.pressed.connect(func(): inspect_requested.emit())
	add_child(_inspect_button)
	_name_tag = Label.new()
	_name_tag.name = "AssignedSlot"
	_name_tag.size = Vector2(14, 12)
	_name_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tag.add_theme_font_size_override("font_size", 8)
	_name_tag.add_theme_color_override("font_color", Color("f3e3ff"))
	_name_tag.add_theme_color_override("font_outline_color", Color("171120"))
	_name_tag.add_theme_constant_override("outline_size", 3)
	add_child(_name_tag)
	set_sector(0)

func set_sector(index: int) -> void:
	sector = posmod(index, 3)
	if _inspect_button != null: _inspect_button.sector = sector
	if _name_tag != null:
		_name_tag.position = Vector2.from_angle(-PI * 0.5 + (sector + 0.5) * TAU / 3.0) * 29.0 - _name_tag.size * 0.5
	for child in get_children():
		if child is SectorButton: child.sector = sector; child.queue_redraw()
	queue_redraw()

func _draw() -> void:
	var start := -PI * 0.5 + sector * TAU / 3.0 + 0.025
	var finish := start + TAU / 3.0 - 0.05
	# Nested arcs create an inset dark-violet piece with a silver bevel.
	draw_arc(Vector2(0, 1), 30, start, finish, 48, Color(0, 0, 0, 0.7), 13, true)
	draw_arc(Vector2.ZERO, 29.25, start, finish, 48, Color("aaa1bd"), 11.5, true)
	draw_arc(Vector2.ZERO, 29.25, start, finish, 48, Color("1c142a"), 9.5, true)
	draw_arc(Vector2.ZERO, 30, start + 0.02, finish - 0.02, 48, Color("48315f"), 6.5, true)
	draw_arc(Vector2.ZERO, 31, start + 0.04, finish - 0.04, 48, Color("72518a"), 2.0, true)
	for i in [1, 2, 4, 5]:
		var angle := lerpf(start, finish, i / 6.0)
		var thorn := PackedVector2Array([Vector2.from_angle(angle - 0.065) * 33, Vector2.from_angle(angle) * 26, Vector2.from_angle(angle + 0.06) * 32])
		draw_colored_polygon(thorn, Color("b09bbf"))
	if _hovered:
		draw_arc(Vector2.ZERO, 35.5, start, finish, 48, Color("ffdd88"), 1.6, true)

func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.15:
		_refresh_elapsed = 0.0
		_refresh_details()

func _refresh_details() -> void:
	if _inspect_button == null or _state == null: return
	_inspect_button.tooltip_text = "Umbra · Player %d · Evocation slot %d\nHP %d/%d\nClick to inspect" % [_state.assigned_mage + 1, _state.assigned_slot, _state.get_remaining_health(), _state.health]
	_name_tag.text = str(_state.assigned_slot)

func sync_state(state: EvocationState, owner_index: int, color: Color) -> void:
	_state = state
	owner_id = owner_index
	owner_color = color
	board_number = state.board_number
	_refresh_details()

func set_names_visible(_value: bool) -> void:
	pass # The slot number and hover tooltip identify each small ring piece.

func create_visual_copy() -> Node2D:
	var copy = super.create_visual_copy()
	copy.set_sector(sector)
	copy._name_tag.text = _name_tag.text
	return copy

func has_portrait() -> bool:
	return true # Reuse the existing model-choice route with a sector hitbox.

func create_target_button() -> Button:
	var button := SectorButton.new()
	button.sector = sector
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	for style_name in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	return button

func style_target_button(button: Button, selected: bool) -> void:
	button.position = Vector2(-36, -36)
	button.size = Vector2(72, 72)
	button.text = ""
	button.highlighted = true
	button.selected = selected
	button.sector = sector
	for style_name in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	button.queue_redraw()
