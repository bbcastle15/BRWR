extends SceneTree

func _initialize():
	var ids: Array = ["possessed", "command_back"]
	for path in [AvatarRules.COMMANDS, AvatarRules.EVENTS]:
		for entry in JSON.parse_string(FileAccess.get_file_as_string(path)): ids.append(entry.id)
	for id in ids:
		var texture: Texture2D = AvatarArt.texture(id)
		if texture == null:
			push_error("Missing Avatar card: " + str(id))
			quit(1)
			return
		if id != "command_back" and (texture is AtlasTexture or not texture.resource_path.contains("/approved/") or texture.get_width() < 900):
			push_error("HD face missing from runtime: " + str(id))
			quit(1)
			return
	print("AVATAR HD ART: ", ids.size(), " cards loaded from restored PNGs; no low-resolution atlas faces.")
	quit()
