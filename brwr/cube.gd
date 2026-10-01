extends Control

enum OwnerType {
	BLACK_ROSE,
	PLAYER
}

@export var owner_type: OwnerType = OwnerType.BLACK_ROSE
@export var player_index: int = -1
@export var cube_color: Color = Color.BLACK

const CUBE_SIZE = Vector2(14, 14)


func _ready():
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = CUBE_SIZE
	size = CUBE_SIZE
	
	$Body.set_anchors_preset(Control.PRESET_TOP_LEFT)
	$Body.position = Vector2.ZERO
	$Body.size = CUBE_SIZE
	$Body.color = cube_color
	$Body.hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Deve stare davanti alla grafica della Room
	z_index = 10


func _draw() -> void:
	# Three shaded faces fit the existing footprint, including damage tracks.
	var base := cube_color
	if cube_color == Color.BLACK:
		base = Color(0.13, 0.14, 0.16)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 3), Vector2(11, 3), Vector2(11, 14), Vector2(0, 14)]), base)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 3), Vector2(3, 0), Vector2(14, 0), Vector2(11, 3)]), base.lightened(0.38))
	draw_colored_polygon(PackedVector2Array([Vector2(11, 3), Vector2(14, 0), Vector2(14, 11), Vector2(11, 14)]), base.darkened(0.4))
	var outline := base.lightened(0.55) if cube_color == Color.BLACK else base.darkened(0.65)
	draw_polyline(PackedVector2Array([Vector2(0, 3), Vector2(3, 0), Vector2(14, 0), Vector2(14, 11), Vector2(11, 14), Vector2(0, 14), Vector2(0, 3)]), outline, 0.7, true)
