class_name SpellArtResolver
extends RefCounted

static var _texture_cache: Dictionary = {}

const CARD_ART_ROOTS: Array[String] = [
	"res://assets/cards/spells",
	"res://assets/cards",
	"res://assets/spell_cards",
	"res://assets/spells",
	"res://cards/spells",
	"res://cards",
	"res://spell_cards",
	"res://art/cards",
	"res://art/spells",
	"res://images/cards",
	"res://images/spells"
]

static func get_texture(spell_id: String, school_id: String = "") -> Texture2D:
	if spell_id == "":
		return null

	if _texture_cache.has(spell_id):
		return _texture_cache[spell_id]

	var candidates: Array[String] = []

	for root in CARD_ART_ROOTS:
		if school_id != "":
			candidates.append(root.path_join(school_id).path_join(spell_id + ".png"))
		candidates.append(root.path_join(spell_id + ".png"))

	for path in candidates:
		if not ResourceLoader.exists(path):
			continue
		var texture = load(path)
		if texture is Texture2D:
			_texture_cache[spell_id] = texture
			return texture

	var recursive_path: String = _find_resource_file_recursive(
		"res://",
		spell_id + ".png",
		0
	)

	if recursive_path != "" and ResourceLoader.exists(recursive_path):
		var texture = load(recursive_path)
		if texture is Texture2D:
			_texture_cache[spell_id] = texture
			return texture

	_texture_cache[spell_id] = null
	return null


static func _find_resource_file_recursive(
	directory_path: String,
	target_file_name: String,
	depth: int
) -> String:
	if depth > 7:
		return ""

	var dir := DirAccess.open(directory_path)
	if dir == null:
		return ""

	dir.list_dir_begin()
	var entry: String = dir.get_next()

	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue

		var full_path: String = directory_path.path_join(entry)

		if dir.current_is_dir():
			if entry != ".godot" and entry != ".git":
				var found := _find_resource_file_recursive(
					full_path,
					target_file_name,
					depth + 1
				)
				if found != "":
					dir.list_dir_end()
					return found
		elif entry.to_lower() == target_file_name.to_lower():
			dir.list_dir_end()
			return full_path

		entry = dir.get_next()

	dir.list_dir_end()
	return ""
