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
	custom_minimum_size = CUBE_SIZE
	size = CUBE_SIZE
	
	$Body.position = Vector2.ZERO
	$Body.size = CUBE_SIZE
	$Body.color = cube_color
	
	# Deve stare davanti alla grafica della Room
	z_index = 10
