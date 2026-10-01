extends RefCounted

# Texture coordinates follow the existing hexagon; Lodge geometry stays unchanged.
static func apply(background: Polygon2D, asset_id: String, radius: float, rebuilt: bool = false) -> bool:
	var path := "res://assets/rooms/%s.png" % asset_id
	var rebuilt_path := "res://assets/rooms/rebuilt/%s.png" % asset_id
	if rebuilt and ResourceLoader.exists(rebuilt_path):
		path = rebuilt_path
	if not ResourceLoader.exists(path):
		background.texture = null
		return false
	var texture := load(path) as Texture2D
	if texture == null:
		return false
	var bounds := Vector2(radius * 2.0, radius * sqrt(3.0))
	var texture_size := texture.get_size()
	var scale_factor := maxf(bounds.x / texture_size.x, bounds.y / texture_size.y)
	var uv := PackedVector2Array()
	for point in background.polygon:
		uv.append(point / scale_factor + texture_size * 0.5)
	background.texture = texture
	background.uv = uv
	background.color = Color.WHITE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return true


static func activation_token(asset_id: String, used: bool) -> Texture2D:
	var path := "res://assets/rooms/tokens/%s_%s.png" % [asset_id, "used" if used else "available"]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
