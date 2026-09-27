class_name VisualAssets
extends RefCounted


const SPELL_DIR := "res://assets/spells/"


static func spell_texture_path(spell_id: String) -> String:
	if spell_id.is_empty():
		return ""

	return SPELL_DIR + spell_id + ".png"


static func load_spell_texture(spell_id: String) -> Texture2D:
	var path := spell_texture_path(spell_id)

	if path.is_empty() or not ResourceLoader.exists(path):
		return null

	return load(path) as Texture2D
