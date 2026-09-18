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
	
func get_element(
	use_dark_side: bool
) -> String:

	var side = get_side(
		use_dark_side
	)

	return str(
		side.get("element", "")
	)
	
func get_enhancement(
	use_dark_side: bool
) -> Dictionary:

	var side = get_side(
		use_dark_side
	)

	return side.get(
		"enhancement",
		{}
	)
func has_summon_effect() -> bool:

	if _dictionary_has_summon_effect(
		light_side
	):
		return true

	if _dictionary_has_summon_effect(
		dark_side
	):
		return true

	return false


func _dictionary_has_summon_effect(
	data: Dictionary
) -> bool:

	if data.has("type"):

		var effect_type: String = str(
			data["type"]
		)

		if effect_type.begins_with(
			"summon_"
		):
			return true


	for value in data.values():

		if value is Dictionary:

			if _dictionary_has_summon_effect(
				value
			):
				return true


		elif value is Array:

			for element in value:

				if element is Dictionary:

					if _dictionary_has_summon_effect(
						element
					):
						return true


	return false
