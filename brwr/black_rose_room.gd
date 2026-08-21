extends Polygon2D

func _ready():
	var radius = 150.0
	
	var points = PackedVector2Array()
	
	for i in range(6):
		var angle = deg_to_rad(60 * i)
		var point = Vector2(
			cos(angle) * radius,
			sin(angle) * radius
		)
		points.append(point)
	
	polygon = points
