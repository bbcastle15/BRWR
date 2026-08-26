class_name SpellCardState
extends RefCounted

enum SpellType {
	COMBAT,
	CONTINGENCY,
	PROTECTION,
	TRAP
}


enum TargetType {
	SELF,
	MODEL,
	MAGE,
	EVOCATION,
	AREA,
	SPECIAL
}


var id: String
var card_name: String
var school_id: String

var light_side: Dictionary = {}
var dark_side: Dictionary = {}

var copies: int = 3
var personal: bool = false
var forgotten: bool = false
var instability: bool = false


func _init(
	card_id: String,
	name: String,
	school: String,
	light: Dictionary,
	dark: Dictionary,
	card_copies: int = 3,
	card_instability: bool = false
):
	id = card_id
	card_name = name
	school_id = school

	light_side = light
	dark_side = dark

	copies = card_copies
	instability = card_instability


func get_side(use_dark_side: bool) -> Dictionary:
	if use_dark_side:
		return dark_side

	return light_side


func get_effects(use_dark_side: bool) -> Array:
	var side = get_side(use_dark_side)

	return side.get("effects", [])

func has_instability() -> bool:
	return instability
