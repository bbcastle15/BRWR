class_name AvatarArt
extends RefCounted

static var atlas: Dictionary = {}
static var textures: Dictionary = {}

static func texture(id: String) -> Texture2D:
	if atlas.is_empty():
		atlas = JSON.parse_string(FileAccess.get_file_as_string("res://assets/avatars/possessed/atlas.json"))
	if not atlas.has(id): return null
	if not textures.has(id):
		var entry: Dictionary = atlas[id]
		var image := AtlasTexture.new()
		image.atlas = load("res://assets/avatars/possessed/" + str(entry.file))
		var rect: Array = entry.rect
		image.region = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
		image.filter_clip = true
		textures[id] = image
	return textures[id]
