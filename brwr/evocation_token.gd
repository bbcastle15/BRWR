extends Node2D

signal inspect_requested

var evocation_id: String = ""
var evocation_name: String = ""
var owner_id: int = -1
var owner_color: Color = Color.WHITE
var board_number: int = 0


func setup(
	id_value: String,
	name_value: String,
	owner_index: int,
	color: Color,
	number: int = 0
) -> void:
	evocation_id = id_value
	evocation_name = name_value
	owner_id = owner_index
	owner_color = color
	board_number = number
	z_index = 79

	_build_visual()


func _build_visual() -> void:
	for child in get_children():
		child.queue_free()

	var owner_ring := Polygon2D.new()
	owner_ring.name = "OwnerRing"
	owner_ring.polygon = _diamond_points(19.0)
	owner_ring.color = owner_color
	owner_ring.z_index = -2
	add_child(owner_ring)

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _diamond_points(15.5)
	body.color = Color(0.075, 0.075, 0.085, 1.0)
	body.z_index = -1
	add_child(body)

	var type_label := Label.new()
	type_label.name = "TypeLabel"
	type_label.text = _abbreviation(evocation_name) + (str(board_number) if board_number > 0 else "")
	type_label.position = Vector2(-21, -14)
	type_label.size = Vector2(42, 23)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_label.add_theme_font_size_override("font_size", 13)
	type_label.add_theme_color_override("font_color", Color.WHITE)
	type_label.add_theme_color_override("font_outline_color", Color.BLACK)
	type_label.add_theme_constant_override("outline_size", 4)
	add_child(type_label)

	var owner_label := Label.new()
	owner_label.name = "OwnerLabel"
	owner_label.text = "P" + str(owner_id + 1)
	owner_label.position = Vector2(-18, 8)
	owner_label.size = Vector2(36, 17)
	owner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	owner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner_label.add_theme_font_size_override("font_size", 10)
	owner_label.add_theme_color_override("font_color", owner_color)
	owner_label.add_theme_color_override("font_outline_color", Color.BLACK)
	owner_label.add_theme_constant_override("outline_size", 4)
	add_child(owner_label)

	var inspect_button := Button.new()
	inspect_button.name = "InspectButton"
	inspect_button.position = Vector2(-21, -20)
	inspect_button.size = Vector2(42, 45)
	inspect_button.flat = true
	inspect_button.tooltip_text = evocation_name + " #" + str(board_number) + " · P" + str(owner_id + 1) + " — Inspect"
	inspect_button.pressed.connect(func(): inspect_requested.emit())
	add_child(inspect_button)


func _abbreviation(value: String) -> String:
	var clean: String = value.strip_edges()

	if clean == "":
		return "EV"

	var words: PackedStringArray = clean.split(" ", false)

	if words.size() >= 2:
		return (
			words[0].substr(0, 1)
			+ words[1].substr(0, 1)
		).to_upper()

	if clean.length() == 1:
		return clean.to_upper()

	return clean.substr(0, 2).to_upper()


func _diamond_points(
	radius: float
) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -radius),
		Vector2(radius, 0),
		Vector2(0, radius),
		Vector2(-radius, 0)
	])
