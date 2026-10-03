extends Control

@export var marker_name: String = ""
@export var marker_color: Color = Color.WHITE

func _ready():
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(22, 22)
	$Body.hide()
	var art := TextureRect.new()
	art.name = "TokenArt"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture = preload("res://assets/tokens/black_rose_power.png") if marker_name == "BR" else preload("res://assets/tokens/mage_power.png")
	art.position = Vector2(-11, -11)
	art.size = Vector2(22, 22)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if marker_name != "BR":
		var tint := ShaderMaterial.new()
		tint.shader = preload("res://assets/tokens/player_token.gdshader")
		tint.set_shader_parameter("player_color", marker_color)
		art.material = tint
	add_child(art)
	$Label.z_index = 1
	$Label.text = ""
	$Label.position = Vector2(-13, -7)
	$Label.size = Vector2(26, 14)
	$Label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$Label.add_theme_font_size_override("font_size", 8)
	$Label.add_theme_color_override("font_outline_color", Color.BLACK)
	$Label.add_theme_constant_override("outline_size", 2)
	$Label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_PASS
	z_index = 12
	queue_redraw()

func _has_point(point: Vector2) -> bool:
	return point.length() <= 11.0
