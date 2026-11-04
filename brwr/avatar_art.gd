class_name AvatarArt
extends RefCounted

static var atlas: Dictionary = {}
static var textures: Dictionary = {}

static func command_back_id(moon: int, public_state: Dictionary) -> String:
	var id := "command_back_%d" % clampi(moon, 1, 3)
	var symbol := str(public_state.get("reaction", ""))
	if symbol in ["damage", "suffered_damage", "combat_spell"]:
		var kind := str(public_state.get("reaction_type", "protection"))
		var suffix := "combat" if symbol == "combat_spell" else "damage"
		var candidate := id + "_" + kind + "_" + suffix
		if ResourceLoader.exists("res://assets/avatars/possessed/approved/" + candidate + ".png"):
			return candidate
	return id

static func reaction_description(public_state: Dictionary) -> String:
	var symbol := str(public_state.get("reaction", ""))
	if symbol.is_empty(): return "No active Trap or Protection."
	var trigger := "is targeted by a Combat Spell" if symbol == "combat_spell" else "takes at least 1 Damage"
	var text := "%s · triggers when the Avatar %s." % [str(public_state.get("reaction_type", "protection")).capitalize(), trigger]
	if not public_state.get("reaction_available", false): text += " Unavailable: Command limit reached."
	return text

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
