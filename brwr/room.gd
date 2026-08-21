extends Node2D

@export var room_name: String = "Room"
@export var room_color: Color = Color.DIM_GRAY
@export var radius: float = 150.0

func _ready():
	var background = $Background
	
	var points = PackedVector2Array()
	
	for i in range(6):
		var angle = deg_to_rad(60 * i)
		var point = Vector2(
			cos(angle) * radius,
			sin(angle) * radius
		)
		points.append(point)
	
	background.polygon = points
	background.color = room_color
	
	$RoomName.text = room_name
