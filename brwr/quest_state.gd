class_name QuestState
extends RefCounted


var card: QuestCardState = null

var owner_id: int = -1

var revealed: bool = false
var progress: int = 0

var completed: bool = false
var solved: bool = false


func _init(
	quest_card: QuestCardState = null,
	quest_owner_id: int = -1
):
	card = quest_card
	owner_id = quest_owner_id


func get_id() -> String:
	if card == null:
		return ""

	return card.id


func get_name() -> String:
	if card == null:
		return ""

	return card.card_name


func get_moon() -> int:
	if card == null:
		return 1

	return card.moon


func get_cube_slots() -> int:
	if card == null:
		return 0

	return card.cube_slots


func get_power_reward() -> int:
	if card == null:
		return 0

	return card.power_reward


func get_task() -> Dictionary:
	if card == null:
		return {}

	return card.task


func get_effects() -> Array:
	if card == null:
		return []

	return card.effects


func reveal() -> void:
	revealed = true


func add_progress(
	amount: int = 1
) -> bool:

	if completed or solved:
		return false

	if card == null:
		return false

	if card.cube_slots <= 0:
		return false

	revealed = true

	progress = min(
		progress + amount,
		card.cube_slots
	)

	if progress >= card.cube_slots:
		complete()
		return true

	return false


func complete() -> void:
	if solved:
		return

	revealed = true
	completed = true


func solve() -> void:
	revealed = true
	completed = true
	solved = true


func is_active() -> bool:
	return not completed and not solved


func is_completed() -> bool:
	return completed and not solved


func is_solved() -> bool:
	return solved
