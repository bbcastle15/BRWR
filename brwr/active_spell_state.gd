class_name ActiveSpellState
extends RefCounted


var spell: SpellCardState

var owner_id: int = -1
var use_dark_side: bool = false
var target_player_index: int = -1
var active: bool = true
var context: Dictionary = {}

func _init(
	spell_state: SpellCardState,
	player_id: int,
	dark_side: bool,
	target_index: int = -1
):
	spell = spell_state
	owner_id = player_id
	use_dark_side = dark_side
	target_player_index = target_index

func get_side() -> Dictionary:
	return spell.get_side(use_dark_side)


func get_spell_type() -> String:
	return str(
		get_side().get("type", "")
	)


func get_trigger() -> Dictionary:
	return get_side().get(
		"trigger",
		{}
	)


func get_effects() -> Array:
	return spell.get_effects(
		use_dark_side
	)
