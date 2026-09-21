class_name QuestCardState
extends RefCounted


var id: String = ""
var card_name: String = ""

var moon: int = 1

# Descrizione machine-readable della condizione.
var task: Dictionary = {}

# Effetti utilizzabili dopo il completamento.
var effects: Array = []

var cube_slots: int = 0
var power_reward: int = 0


func _init(
	quest_id: String = "",
	quest_name: String = "",
	quest_moon: int = 1,
	quest_task: Dictionary = {},
	quest_effects: Array = [],
	quest_cube_slots: int = 0,
	quest_power_reward: int = 0
):
	id = quest_id
	card_name = quest_name
	moon = quest_moon

	task = quest_task.duplicate(true)
	effects = quest_effects.duplicate(true)

	cube_slots = quest_cube_slots
	power_reward = quest_power_reward


func create_instance(
	owner_id: int = -1
):
	return QuestState.new(
		self,
		owner_id
	)
