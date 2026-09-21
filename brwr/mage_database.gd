class_name MageDatabase
extends RefCounted


var mages: Dictionary = {}


func load_database(
	path: String = "res://data/mages.json"
) -> bool:

	if not FileAccess.file_exists(path):
		print(
			"MageDatabase: file not found: ",
			path
		)
		return false

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		print(
			"MageDatabase: could not open: ",
			path
		)
		return false

	var parsed = JSON.parse_string(
		file.get_as_text()
	)

	if parsed == null:
		print(
			"MageDatabase: invalid JSON: ",
			path
		)
		return false

	if not parsed is Dictionary:
		print(
			"MageDatabase: root must be a Dictionary"
		)
		return false

	mages = parsed

	print(
		"Mages DB: ",
		mages.size()
	)

	return true


func has_mage(mage_id: String) -> bool:
	return mages.has(mage_id)


func get_mage_data(
	mage_id: String
) -> Dictionary:

	if not mages.has(mage_id):
		print(
			"MageDatabase: unknown Mage: ",
			mage_id
		)
		return {}

	return mages[mage_id].duplicate(true)


func get_mage_ids() -> Array[String]:
	var result: Array[String] = []

	for mage_id in mages.keys():
		result.append(str(mage_id))

	return result
