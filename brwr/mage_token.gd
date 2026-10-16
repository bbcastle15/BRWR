extends Node2D


var player_index: int = -1
var token_color: Color = Color.WHITE
var transformation_id: String = ""


func setup(index: int, color: Color):
	player_index = index
	token_color = color
	z_index = 80

	create_shape()

	var label: Label = $Label
	label.text = "P" + str(index + 1)
	label.position = Vector2(-22, 15)
	label.size = Vector2(44, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)


func create_shape():
	$Body.hide()
	var art = get_node_or_null("MageArt")
	if art == null:
		art = Sprite2D.new()
		art.name = "MageArt"
		add_child(art)
		move_child(art, 0)
	art.texture = preload("res://assets/tokens/mage_power.png")
	art.scale = Vector2.ONE * 46.0 / art.texture.get_width()
	var tint := ShaderMaterial.new()
	tint.shader = preload("res://assets/tokens/player_token.gdshader")
	tint.set_shader_parameter("player_color", token_color)
	art.material = tint


func set_transformation(form: String) -> void:
	if form == transformation_id:
		return
	transformation_id = form
	$Label.text = "P%d" % (player_index + 1) + (" · " + form.capitalize() if not form.is_empty() else "")
	$Label.position.x = -45 if not form.is_empty() else -22
	$Label.size.x = 90 if not form.is_empty() else 44
	var badge := get_node_or_null("Transformation") as Label
	if badge == null:
		badge = Label.new()
		badge.name = "Transformation"
		badge.position = Vector2(-20, -19)
		badge.size = Vector2(40, 34)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size", 19)
		badge.add_theme_color_override("font_color", token_color.lightened(0.3))
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 7)
		add_child(badge)
	badge.text = form.left(1).to_upper()
	badge.visible = not form.is_empty()
	$MageArt.modulate.a = 0.65 if not form.is_empty() else 1.0


func _circle_points(
	radius: float,
	point_count: int
) -> PackedVector2Array:
	var points := PackedVector2Array()

	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		points.append(
			Vector2(
				cos(angle),
				sin(angle)
			) * radius
		)

	return points
