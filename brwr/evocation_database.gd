class_name EvocationDatabase
extends RefCounted


var evocations: Dictionary = {}


func load_database(
	path: String = "res://data/evocations.json"
) -> bool:

	evocations.clear()

	var file = FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		print(
			"ERRORE: impossibile aprire ",
			path
		)
		return false

	var parsed = JSON.parse_string(
		file.get_as_text()
	)

	if parsed == null:
		print(
			"ERRORE: JSON Evocations non valido"
		)
		return false

	for evocation_data in parsed:
		evocations[
			evocation_data["id"]
		] = evocation_data

	print(
		"Evocations loaded: ",
		evocations.size()
	)

	return true


func get_evocation(
	evocation_id: String
) -> Dictionary:

	return evocations.get(
		evocation_id,
		{}
	)
	
func get_all_evocations() -> Array:

	var result: Array = []

	for evocation_data in evocations.values():
		result.append(evocation_data)

	return result


func get_evocations_with_max_health(
	max_health: int
) -> Array:

	var result: Array = []

	for evocation_data in evocations.values():

		if int(
			evocation_data.get(
				"health",
				999
			)
		) > max_health:
			continue

		if int(
			evocation_data.get(
				"copies",
				0
			)
		) <= 0:
			continue

		result.append(
			evocation_data
		)

	return result
