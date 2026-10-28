extends Camera2D

var dragging := false
var fitted_zoom := 0.0
var fitted_center := Vector2.ZERO
var power_focus: Tween
var movement_focus: Tween
var power_return_position := Vector2.ZERO
var power_return_zoom := Vector2.ONE

func minimum_zoom() -> float:
	if get_parent().has_method("get_tabletop_bounds"):
		var bounds: Rect2 = get_parent().get_tabletop_bounds()
		var view: Vector2 = get_parent().get_table_view_rect().size
		return maxf(view.x / maxf(bounds.size.x, 1.0), view.y / maxf(bounds.size.y, 1.0))
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
	_cancel_power_focus(true)
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
	clamp_to_playmat()
	force_update_scroll()

func reset_view() -> void:
	_cancel_power_focus()
	position = get_viewport_rect().size * 0.5
	zoom = Vector2.ONE
	if get_parent().has_method("get_tabletop_bounds"):
		var bounds: Rect2 = get_parent().get_tabletop_bounds()
		zoom = Vector2.ONE * minimum_zoom()
		position = _view_center(bounds, zoom.x)
		fitted_zoom = zoom.x
		fitted_center = position
	clamp_to_playmat()
	force_update_scroll()

func focus_lodge() -> void:
	# Personal boards are screen overlays; all table space belongs to the Lodge.
	reset_view()

func ensure_movement_visible(origin: Vector2, destination: Vector2) -> void:
	var area: Rect2 = get_parent().get_table_view_rect()
	var bounds := Rect2(origin, Vector2.ZERO).expand(destination).grow(get_parent().HEX_RADIUS * 1.2)
	var view_center := position + (area.get_center() - get_viewport_rect().size * 0.5) / zoom.x
	var visible := Rect2(view_center - area.size / zoom.x * 0.5, area.size / zoom.x)
	if visible.encloses(bounds): return
	_cancel_power_focus()
	if movement_focus != null and movement_focus.is_valid(): movement_focus.kill()
	var target_zoom := maxf(minimum_zoom(), minf(zoom.x, minf(area.size.x / bounds.size.x, area.size.y / bounds.size.y)))
	var target_position := _view_center(bounds, target_zoom)
	var start_position := position
	var start_zoom := zoom
	movement_focus = create_tween()
	movement_focus.tween_method(func(weight: float):
		_set_focus_view(start_position.lerp(target_position, weight), start_zoom.lerp(Vector2.ONE * target_zoom, weight)), 0.0, 1.0, 0.18).set_trans(Tween.TRANS_SINE)

func _view_center(bounds: Rect2, scale_value: float) -> Vector2:
	var area: Rect2 = get_parent().get_table_view_rect()
	return bounds.get_center() - (area.get_center() - get_viewport_rect().size * 0.5) / scale_value

func clamp_to_playmat() -> void:
	if not get_parent().has_method("get_tabletop_bounds"):
		return
	var bounds: Rect2 = get_parent().get_tabletop_bounds()
	var area: Rect2 = get_parent().get_table_view_rect()
	var half := area.size / (2.0 * zoom.x)
	var offset := (area.get_center() - get_viewport_rect().size * 0.5) / zoom.x
	var center := position + offset
	center.x = clampf(center.x, bounds.position.x + half.x, bounds.end.x - half.x)
	center.y = clampf(center.y, bounds.position.y + half.y, bounds.end.y - half.y)
	position = center - offset

func _table_covered() -> bool:
	var game = get_parent()
	var preview = game.get_node_or_null("ReferenceCardPreview")
	if preview != null and preview.root.visible:
		return true
	return (game.table_shell != null and (game.table_shell.board_overlay.visible or game.table_shell.card_overlay.visible)) or (game.beta_hud != null and (game.beta_hud.hand_overlay.visible or game.beta_hud.panel.visible))

func zoom_at(screen_point: Vector2, factor: float) -> void:
	_cancel_power_focus()
	var before := get_canvas_transform().affine_inverse() * screen_point
	zoom = Vector2.ONE * clampf(zoom.x * factor, minimum_zoom(), maxf(4.0, minimum_zoom()))
	force_update_scroll()
	var after := get_canvas_transform().affine_inverse() * screen_point
	position += before - after
	clamp_to_playmat()
	force_update_scroll()

func _input(event: InputEvent) -> void:
	if _table_covered():
		dragging = false
		return
	# Right-drag works across board controls too; left clicks remain game input.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_cancel_power_focus()
		dragging = event.pressed
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and dragging:
		position -= event.relative / zoom
		clamp_to_playmat()
		force_update_scroll()
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


func focus_power_board() -> void:
	if _table_covered():
		return
	var board = get_parent().get_node_or_null("PowerBoard")
	if board == null:
		return
	if power_focus == null:
		power_return_position = position
		power_return_zoom = zoom
	else:
		power_focus.kill()
	var bounds: Rect2 = board.get_global_transform() * Rect2(board.ART_ORIGIN, board.ART_SIZE)
	var target_zoom := maxf(minimum_zoom(), minf(power_return_zoom.x * 1.3, 0.8 * get_parent().get_table_view_rect().size.y / bounds.size.y))
	var target_position := _view_center(bounds, target_zoom)
	var start_position := position
	var start_zoom := zoom
	power_focus = create_tween()
	power_focus.tween_method(func(weight: float):
		_set_focus_view(start_position.lerp(target_position, weight), start_zoom.lerp(Vector2.ONE * target_zoom, weight)), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	power_focus.tween_interval(1.8)
	power_focus.tween_method(func(weight: float):
		_set_focus_view(target_position.lerp(power_return_position, weight), (Vector2.ONE * target_zoom).lerp(power_return_zoom, weight)), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	power_focus.tween_callback(func(): power_focus = null)


func _set_focus_view(center: Vector2, scale_value: Vector2) -> void:
	position = center
	zoom = scale_value
	clamp_to_playmat()
	force_update_scroll()


func _cancel_power_focus(restore: bool = false) -> void:
	if power_focus != null:
		power_focus.kill()
		power_focus = null
		if restore:
			_set_focus_view(power_return_position, power_return_zoom)
