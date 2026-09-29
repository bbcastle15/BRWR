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
	
	# Deve stare davanti alla grafica della Room
	z_index = 10


func _draw() -> void:
	# Black Rose cubes must remain visible over the black printed slots.
	if owner_type == OwnerType.BLACK_ROSE:
		draw_rect(Rect2(Vector2.ZERO, CUBE_SIZE), Color(0.85, 0.85, 0.85), false, 1.5)
