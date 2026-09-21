class_name QuestDatabase
extends RefCounted


var quests: Dictionary = {}


func load_from_file(
	path: String
) -> bool:

	quests.clear()

	if not FileAccess.file_exists(path):
		print(
			"QuestDatabase: file not found: ",
			path
		)
		return false

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		return false

	var parsed = JSON.parse_string(
		file.get_as_text()
	)

	if parsed == null:
		print(
			"QuestDatabase: invalid JSON"
		)
		return false

	if not parsed is Dictionary:
		print(
			"QuestDatabase: root must be Dictionary"
		)
		return false

	for quest_id in parsed.keys():

		var data: Dictionary = parsed[quest_id]

		var card := QuestCardState.new(
			str(quest_id),
			str(
				data.get(
					"name",
					quest_id
				)
			),
			int(
				data.get(
					"moon",
					1
				)
			),
			data.get(
				"task",
				{}
			),
			data.get(
				"effects",
				[]
			),
			int(
				data.get(
					"cube_slots",
					0
				)
			),
			int(
				data.get(
					"power_reward",
					0
				)
			)
		)

		quests[quest_id] = card

	print(
		"Quests DB: ",
		quests.size()
	)

	return true


func get_quest(
	quest_id: String
) -> QuestCardState:

	return quests.get(
		quest_id
	)


func create_deck_for_moon(
	moon: int
) -> Array[QuestCardState]:

	var deck: Array[QuestCardState] = []

	for card in quests.values():

		if card.moon != moon:
			continue

		deck.append(card)

	return deck	
