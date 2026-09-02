class_name RevealedSpellState
extends RefCounted


var spell: SpellCardState
var use_dark_side: bool = false
var slot_id: String = ""


func _init(
	spell_state: SpellCardState,
	dark_side: bool,
	slot: String = ""
):
	spell = spell_state
	use_dark_side = dark_side
	slot_id = slot


func get_active_side() -> Dictionary:
	return spell.get_side(use_dark_side)


func get_element() -> String:
	return str(
		get_active_side().get("element", "")
	)
