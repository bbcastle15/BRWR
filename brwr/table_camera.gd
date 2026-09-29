extends Camera2D

var dragging := false

func minimum_zoom() -> float:
	if get_parent().has_method("get_tabletop_bounds"):
		var bounds: Rect2 = get_parent().get_tabletop_bounds()
		var view := get_viewport_rect().size
		return minf(view.x / maxf(bounds.size.x, 1.0), view.y / maxf(bounds.size.y, 1.0))
	return 1.0

func _process(_delta: float) -> void:
	zoom = Vector2.ONE * maxf(zoom.x, minimum_zoom())

func _ready() -> void:
	position = get_viewport_rect().size * 0.5
	zoom = Vector2.ONE * 1.2
	call_deferred("reset_view")

func reset_view() -> void:
	position = get_viewport_rect().size * 0.5
	zoom = Vector2.ONE
	if get_parent().has_method("get_tabletop_bounds"):
		var bounds: Rect2 = get_parent().get_tabletop_bounds()
		var viewport_size := get_viewport_rect().size
		position = bounds.get_center()
		zoom = Vector2.ONE * minf(viewport_size.x / bounds.size.x, viewport_size.y / bounds.size.y)

func zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := get_canvas_transform().affine_inverse() * screen_point
	zoom = Vector2.ONE * clampf(zoom.x * factor, minimum_zoom(), maxf(4.0, minimum_zoom()))
	force_update_scroll()
	var after := get_canvas_transform().affine_inverse() * screen_point
	position += before - after
	force_update_scroll()

func _input(event: InputEvent) -> void:
	# Right-drag works across board controls too; left clicks remain game input.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		dragging = event.pressed
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and dragging:
		position -= event.relative / zoom
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position, 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_HOME:
		reset_view()
