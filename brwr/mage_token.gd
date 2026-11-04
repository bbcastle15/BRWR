extends Node2D
signal action_requested

class TokenButton extends Button:
	func _has_point(point: Vector2) -> bool:
		return point.distance_to(size * 0.5) <= 23.0


var player_index: int = -1
var token_color: Color = Color.WHITE
var transformation_id: String = ""

func _process(_delta: float) -> void:
	var button := get_node_or_null("ActionButton") as Button
	var game = get_parent()
	if button == null or game == null or not game.has_method("get_player_board_action_options"): return
	var available: bool = game.beta_hud != null and game.beta_hud.action_menu_mode == "root" and not game.get_player_board_action_options(player_index, "physical").is_empty()
	button.mouse_filter = Control.MOUSE_FILTER_STOP if available else Control.MOUSE_FILTER_IGNORE
	button.tooltip_text = game.player_display_name(player_index) + " · Physical Actions"


func setup(index: int, color: Color):
	player_index = index
	token_color = color
	z_index = 80

	create_shape()
	var button := TokenButton.new()
	button.name = "ActionButton"
	button.position = Vector2(-23, -23)
	button.size = Vector2(46, 46)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Physical Actions"
	for style in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	button.pressed.connect(func(): action_requested.emit())
	add_child(button)

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


func set_nightmare_attached(attached: bool) -> void:
	# Keep the player identity outside the three-piece Nightmare ring.
	$Label.position.y = 34 if attached else 15


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
