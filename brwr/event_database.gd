class_name EventDatabase
extends RefCounted


var events: Dictionary = {}


func load_database(
	path: String = "res://data/events.json"
) -> bool:

	events.clear()


	if not FileAccess.file_exists(path):

		print(
			"EventDatabase: file not found: ",
			path
		)

		return false


	var file := FileAccess.open(
		path,
		FileAccess.READ
	)


	if file == null:
		return false


	var json_text: String = (
		file.get_as_text()
	)


	var data = JSON.parse_string(
		json_text
	)


	if data == null:

		print(
			"EventDatabase: invalid JSON"
		)

		return false


	if not data is Array:

		print(
			"EventDatabase: root must be Array"
		)

		return false


	for entry in data:

		var card := EventCardState.new(
			str(entry.get("id", "")),
			str(entry.get("name", "")),
			int(entry.get("moon", 1)),
			bool(entry.get("crown", false)),
			str(entry.get("phase", "")),
			int(entry.get("slot", 0)),
			int(entry.get("reveal_power", 0)),
			int(entry.get("discard_power", 0)),
			entry.get("effects", []),
			str(entry.get("text", ""))
		)


		events[card.id] = card


	print(
		"Events DB: ",
		events.size()
	)


	return true


func get_event(
	event_id: String
) -> EventCardState:

	return events.get(
		event_id
	)


func get_events_for_moon(
	moon: int
) -> Array[EventCardState]:

	var result: Array[EventCardState] = []


	for card in events.values():

		if card.moon == moon:
			result.append(card)


	return result
