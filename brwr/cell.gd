extends Node2D

@export var cell_id: String = ""
@export var cell_name: String = "Cell"
@export var cell_color: Color = Color.DIM_GRAY
@export var radius: float = 70.0

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
	background.color = cell_color

	$CellName.text = cell_name
