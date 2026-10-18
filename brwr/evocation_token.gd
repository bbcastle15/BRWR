extends Node2D

signal inspect_requested

const PORTRAIT_SHADER = preload("res://assets/tokens/evocation_portrait.gdshader")
const ReferenceArt = preload("res://reference_card_preview.gd")
static var portrait_cache: Dictionary = {}
static var portrait_regions: Dictionary = {}

# Circle-shaped hit area, shared by inspection and the existing target chooser.
# Transparent corners must not intercept another model's click.
class PortraitButton extends Button:
	func _has_point(point: Vector2) -> bool:
		return point.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5

var evocation_id: String = ""
var evocation_name: String = ""
var owner_id: int = -1
var owner_color: Color = Color.WHITE
var board_number: int = 0
var _state: EvocationState
var _portrait: Texture2D
var _inspect_button: Button
var _copy_badge: Label
var _name_tag: Label
var _names_visible := false
var _compact := false
var _hovered := false
var _refresh_elapsed := 0.0


func setup(
	id_value: String,
	name_value: String,
	owner_index: int,
	color: Color,
	number: int = 0,
	state: EvocationState = null
) -> void:
	evocation_id = id_value
	evocation_name = name_value
	owner_id = owner_index
	owner_color = color
	board_number = number
	_state = state
	z_index = 79
	_portrait = portrait_texture(evocation_id)

	_build_visual()
	_refresh_details()
	queue_redraw()


static func portrait_texture(id: String) -> Texture2D:
	if portrait_cache.has(id):
		return portrait_cache[id]
	var portrait_path := "res://assets/tokens/evocations/%s.png" % id
	if ResourceLoader.exists(portrait_path):
		portrait_cache[id] = load(portrait_path)
		return portrait_cache[id]
	if portrait_regions.is_empty():
		portrait_regions = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tokens/evocations/portraits.json"))
	var region: Dictionary = portrait_regions.get(id, {})
	var source: Texture2D = load(str(region.path)) if region.has("path") else ReferenceArt.card_texture("evocations", id)
	if source == null:
		return null
	# Reuse the exact creature painted on its card, with a per-creature crop.
	# Normalized coordinates survive Web's smaller imported textures.
	var center: Array = region.get("center", [0.20, 0.24])
	var side := source.get_width() * float(region.get("width", 0.28))
	var crop := AtlasTexture.new()
	crop.atlas = source
	crop.region = Rect2(Vector2(center[0], center[1]) * source.get_size() - Vector2.ONE * side * 0.5, Vector2.ONE * side)
	crop.filter_clip = true
	portrait_cache[id] = crop
	return crop


func _build_visual() -> void:
	for child in get_children():
		child.queue_free()

	if has_portrait():
		_build_medallion()
	else:
		_build_legacy_token()
	_name_tag = Label.new()
	_name_tag.name = "EvocationName"
	_name_tag.position = Vector2(-22, 25)
	_name_tag.size = Vector2(44, 18)
	_name_tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tag.add_theme_font_size_override("font_size", 10)
	_name_tag.add_theme_color_override("font_color", Color.WHITE)
	_name_tag.add_theme_color_override("font_outline_color", Color("111417"))
	_name_tag.add_theme_constant_override("outline_size", 3)
	_name_tag.visible = _names_visible
	add_child(_name_tag)

	_inspect_button = PortraitButton.new() if has_portrait() else Button.new()
	_inspect_button.name = "InspectButton"
	_inspect_button.position = Vector2(-24, -24) if has_portrait() else Vector2(-21, -20)
	_inspect_button.size = Vector2(48, 48) if has_portrait() else Vector2(42, 45)
	_inspect_button.flat = true
	_inspect_button.focus_mode = Control.FOCUS_NONE
	for style_name in ["normal", "hover", "pressed", "focus"]:
		_inspect_button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	_inspect_button.mouse_entered.connect(func(): _hovered = true; queue_redraw(); _refresh_details())
	_inspect_button.mouse_exited.connect(func(): _hovered = false; queue_redraw())
	_inspect_button.pressed.connect(func(): inspect_requested.emit())
	add_child(_inspect_button)


func _build_medallion() -> void:
	var portrait := Sprite2D.new()
	portrait.name = "Portrait"
	portrait.texture = _portrait
	portrait.scale = Vector2(34.0, 34.0) / _portrait.get_size()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mask := ShaderMaterial.new()
	mask.shader = PORTRAIT_SHADER
	if _portrait is AtlasTexture:
		var region: Rect2 = _portrait.region
		var atlas_size: Vector2 = _portrait.atlas.get_size()
		mask.set_shader_parameter("portrait_region", Vector4(region.position.x / atlas_size.x, region.position.y / atlas_size.y, region.size.x / atlas_size.x, region.size.y / atlas_size.y))
	portrait.material = mask
	add_child(portrait)
	_copy_badge = Label.new()
	_copy_badge.name = "CopyNumber"
	_copy_badge.position = Vector2(7, 7)
	_copy_badge.size = Vector2(17, 17)
	_copy_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_copy_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_copy_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_copy_badge.add_theme_font_size_override("font_size", 11)
	_copy_badge.add_theme_constant_override("outline_size", 0)
	_copy_badge.add_theme_color_override("font_color", Color.WHITE)
	add_child(_copy_badge)
	_update_badge_style()


func _draw() -> void:
	if not has_portrait():
		return
	draw_circle(Vector2(0, 2), 22, Color(0, 0, 0, 0.65), true, -1, true)
	draw_circle(Vector2.ZERO, 21, Color("16191e"), true, -1, true)
	draw_circle(Vector2.ZERO, 19.5, owner_color, true, -1, true)
	draw_circle(Vector2.ZERO, 17.8, Color("080b0f"), true, -1, true)
	if not _compact:
		draw_arc(Vector2.ZERO, 20, -PI * 0.9, -PI * 0.15, 32, owner_color.lightened(0.5), 0.7, true)
		draw_arc(Vector2.ZERO, 20, PI * 0.1, PI * 0.8, 32, owner_color.darkened(0.55), 0.8, true)
	if _hovered:
		draw_arc(Vector2.ZERO, 22.5, 0, TAU, 64, Color("f1d79c"), 1.3, true)


func has_portrait() -> bool:
	return _portrait != null


func sync_state(state: EvocationState, owner_index: int, color: Color) -> void:
	# Keep a reference to the authoritative instance; never copy its health/location.
	_state = state
	if owner_id != owner_index or owner_color != color:
		owner_id = owner_index
		owner_color = color
		if has_portrait():
			_update_badge_style()
			queue_redraw()
		else:
			get_node("OwnerRing").color = color
			get_node("OwnerLabel").text = "P%d" % (owner_id + 1)
			get_node("OwnerLabel").add_theme_color_override("font_color", color)
	board_number = state.board_number
	_refresh_details()


func set_names_visible(value: bool) -> void:
	_names_visible = value
	if _name_tag != null:
		_name_tag.visible = value


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed < 0.15:
		return
	_refresh_elapsed = 0.0
	_refresh_details()
	if has_portrait():
		var compact := get_global_transform_with_canvas().x.length() * 42.0 < 30.0
		if compact != _compact:
			_compact = compact
			_copy_badge.visible = not compact and board_number > 0
			queue_redraw()


func _refresh_details() -> void:
	if _inspect_button == null:
		return
	var title := evocation_name + (" #%d" % board_number if board_number > 0 else "")
	var details := title + " · P%d" % (owner_id + 1)
	if _state != null:
		details += "\nHP %d/%d" % [_state.get_remaining_health(), _state.health]
		if _state.controller_id >= 0 and _state.controller_id != owner_id:
			details += " · Controlled by P%d" % (_state.controller_id + 1)
	_inspect_button.tooltip_text = details + "\nClick to inspect"
	_name_tag.text = evocation_name
	if _copy_badge != null:
		_copy_badge.text = str(board_number)
		_copy_badge.visible = not _compact and board_number > 0
	elif has_node("TypeLabel"):
		get_node("TypeLabel").text = _abbreviation(evocation_name) + (str(board_number) if board_number > 0 else "")


func _update_badge_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101319")
	style.border_color = owner_color.lightened(0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	_copy_badge.add_theme_stylebox_override("normal", style)


func create_target_button() -> Button:
	return PortraitButton.new()


func style_target_button(button: Button, selected: bool) -> void:
	# Selection belongs to the existing chooser. Only its presentation changes.
	# Leave the portrait unobscured and use the outside of the medallion as a ring.
	button.text = ""
	for style_name in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.draw_center = false
		style.border_color = Color("97ffa7") if selected else Color("ffcc4d")
		style.set_border_width_all(3 if selected or style_name != "normal" else 2)
		style.set_corner_radius_all(24)
		style.corner_detail = 12
		button.add_theme_stylebox_override(style_name, style)
	if selected:
		var check := Label.new()
		check.text = "✓"
		check.position = Vector2(0, -6)
		check.add_theme_color_override("font_color", Color("baffc4"))
		check.add_theme_font_size_override("font_size", 16)
		check.add_theme_constant_override("outline_size", 4)
		check.add_theme_color_override("font_outline_color", Color("0d1712"))
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(check)


func _build_legacy_token() -> void:
	var owner_ring := Polygon2D.new()
	owner_ring.name = "OwnerRing"
	owner_ring.polygon = _diamond_points(19.0)
	owner_ring.color = owner_color
	owner_ring.z_index = -2
	add_child(owner_ring)

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _diamond_points(15.5)
	body.color = Color(0.075, 0.075, 0.085, 1.0)
	body.z_index = -1
	add_child(body)

	var type_label := Label.new()
	type_label.name = "TypeLabel"
	type_label.text = _abbreviation(evocation_name) + (str(board_number) if board_number > 0 else "")
	type_label.position = Vector2(-21, -14)
	type_label.size = Vector2(42, 23)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_label.add_theme_font_size_override("font_size", 13)
	type_label.add_theme_color_override("font_color", Color.WHITE)
	type_label.add_theme_color_override("font_outline_color", Color.BLACK)
	type_label.add_theme_constant_override("outline_size", 4)
	add_child(type_label)

	var owner_label := Label.new()
	owner_label.name = "OwnerLabel"
	owner_label.text = "P" + str(owner_id + 1)
	owner_label.position = Vector2(-18, 8)
	owner_label.size = Vector2(36, 17)
	owner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	owner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner_label.add_theme_font_size_override("font_size", 10)
	owner_label.add_theme_color_override("font_color", owner_color)
	owner_label.add_theme_color_override("font_outline_color", Color.BLACK)
	owner_label.add_theme_constant_override("outline_size", 4)
	add_child(owner_label)

func _abbreviation(value: String) -> String:
	var clean: String = value.strip_edges()

	if clean == "":
		return "EV"

	var words: PackedStringArray = clean.split(" ", false)

	if words.size() >= 2:
		return (
			words[0].substr(0, 1)
			+ words[1].substr(0, 1)
		).to_upper()

	if clean.length() == 1:
		return clean.to_upper()

	return clean.substr(0, 2).to_upper()


func _diamond_points(
	radius: float
) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -radius),
		Vector2(radius, 0),
		Vector2(0, radius),
		Vector2(-radius, 0)
	])
