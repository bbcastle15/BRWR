extends Camera2D

var dragging := false
var fitted_zoom := 0.0
var fitted_center := Vector2.ZERO

func minimum_zoom() -> float:
	if get_parent().has_method("get_tabletop_bounds"):
		var bounds: Rect2 = get_parent().get_tabletop_bounds()
		var view: Vector2 = get_parent().get_table_view_rect().size
		return minf(view.x / maxf(bounds.size.x, 1.0), view.y / maxf(bounds.size.y, 1.0))
	return 1.0

func _ready() -> void:
	position = get_viewport_rect().size * 0.5
	zoom = Vector2.ONE * 1.2
	call_deferred("focus_lodge")
	get_viewport().size_changed.connect(_on_viewport_resized)

func _on_viewport_resized() -> void:
	# Wait until the game has repositioned the table for the new viewport.
	call_deferred("adapt_to_viewport")

func adapt_to_viewport() -> void:
	if not get_parent().has_method("get_tabletop_bounds"):
		return
	var bounds: Rect2 = get_parent().get_tabletop_bounds()
	var next_fit := minimum_zoom()
	if fitted_zoom <= 0.0:
		reset_view()
		return
	var relative_zoom := zoom.x / fitted_zoom
	zoom = Vector2.ONE * maxf(next_fit, next_fit * relative_zoom)
	var next_center := _view_center(bounds, zoom.x)
	position += next_center - fitted_center
	fitted_zoom = next_fit
	fitted_center = next_center
	force_update_scroll()

func reset_view() -> void:
	position = get_viewport_rect().size * 0.5
	zoom = Vector2.ONE
	if get_parent().has_method("get_tabletop_bounds"):
		var bounds: Rect2 = get_parent().get_tabletop_bounds()
		zoom = Vector2.ONE * minimum_zoom()
		position = _view_center(bounds, zoom.x)
		fitted_zoom = zoom.x
		fitted_center = position
	force_update_scroll()

func focus_lodge() -> void:
	# Personal boards are screen overlays; all table space belongs to the Lodge.
	reset_view()

func _view_center(bounds: Rect2, scale_value: float) -> Vector2:
	var area: Rect2 = get_parent().get_table_view_rect()
	return bounds.get_center() - (area.get_center() - get_viewport_rect().size * 0.5) / scale_value

func _table_covered() -> bool:
	var game = get_parent()
	return (game.table_shell != null and (game.table_shell.board_overlay.visible or game.table_shell.card_overlay.visible)) or (game.beta_hud != null and (game.beta_hud.hand_overlay.visible or game.beta_hud.panel.visible))

func zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := get_canvas_transform().affine_inverse() * screen_point
	zoom = Vector2.ONE * clampf(zoom.x * factor, minimum_zoom(), maxf(4.0, minimum_zoom()))
	force_update_scroll()
	var after := get_canvas_transform().affine_inverse() * screen_point
	position += before - after
	force_update_scroll()

func _input(event: InputEvent) -> void:
	if _table_covered():
		dragging = false
		return
	# Right-drag works across board controls too; left clicks remain game input.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		dragging = event.pressed
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and dragging:
		position -= event.relative / zoom
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _table_covered():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position, 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_HOME:
		reset_view()
