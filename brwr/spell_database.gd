class_name SpellDatabase
extends RefCounted


var spells: Dictionary = {}


func load_database(path: String = "res://data/spells.json") -> bool:
	spells.clear()

	var file = FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		print("ERRORE: impossibile aprire ", path)
		return false

	var parsed = JSON.parse_string(
		file.get_as_text()
	)

	if parsed == null:
		print("ERRORE: JSON Spell non valido")
		return false

	for spell_data in parsed:
		var spell = SpellCardState.new(
			spell_data["id"],
			spell_data["name"],
			spell_data["school"],
			spell_data["light"],
			spell_data["dark"],
			int(spell_data.get("copies", 3)),
			bool(spell_data.get("instability", false))
		)

		spells[spell.id] = spell

	print(
		"Spells loaded: ",
		spells.size()
	)

	return true


func get_spell(spell_id: String) -> SpellCardState:
	return spells.get(spell_id, null)


func get_school_spells(school_id: String) -> Array[SpellCardState]:
	var result: Array[SpellCardState] = []

	for spell in spells.values():
		if spell.school_id == school_id:
			result.append(spell)

	return result
