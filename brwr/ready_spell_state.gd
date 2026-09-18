class_name ReadySpellState
extends RefCounted


var spell: SpellCardState
var use_dark_side: bool = false


func _init(
	spell_card: SpellCardState,
	dark_side: bool = false
):
	spell = spell_card
	use_dark_side = dark_side
