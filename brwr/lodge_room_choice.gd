extends Control

signal chosen

var polygon := PackedVector2Array()
var selected := false

func setup(radius: float) -> void:
	position = Vector2(-radius, -radius)
	size = Vector2.ONE * radius * 2.0
	for i in range(6):
		polygon.append(Vector2.ONE * radius + Vector2.from_angle(deg_to_rad(60.0 * i)) * radius * 0.96)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	z_index = 100
	tooltip_text = "Select Room"

func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)

func _draw() -> void:
	draw_colored_polygon(polygon, Color(0.2, 1.0, 0.45, 0.4) if selected else Color(1.0, 0.8, 0.2, 0.24))
	var outline := polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline, Color(1.0, 0.85, 0.25), 5.0, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		chosen.emit()
