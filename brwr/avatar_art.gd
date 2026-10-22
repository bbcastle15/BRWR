class_name AvatarArt
extends RefCounted

static var atlas: Dictionary = {}
static var textures: Dictionary = {}

static func texture(id: String) -> Texture2D:
	if id == "command_back": id = "command_back_1"
	# The restored PNGs use the Energy of the Rose treatment approved by the user.
	# All presentation paths (board, previews and resolution) share this loader.
	var restored_path := "res://assets/avatars/possessed/approved/" + id + ".png"
	if ResourceLoader.exists(restored_path):
		if not textures.has(id): textures[id] = load(restored_path)
		return textures[id]
	if id in ["command_back_1", "command_back_2", "command_back_3"]:
		var back_path := "res://assets/avatars/possessed/restored/" + id + ".png"
		if not textures.has(id): textures[id] = load(back_path)
		return textures[id]
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
