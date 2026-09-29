extends RefCounted

# Texture coordinates follow the existing hexagon; Lodge geometry stays unchanged.
static func apply(background: Polygon2D, asset_id: String, radius: float) -> bool:
	var path := "res://assets/rooms/%s.png" % asset_id
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
