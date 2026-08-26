class_name CardState
extends RefCounted


enum CardType {
	EVENT,
	QUEST,
	SPELL,
	EVOCATION,
	JINX,
	UPGRADE
}


var id: String
var card_name: String
var card_type: CardType

var moon: int = 0
var data: Dictionary = {}


func _init(
	card_id: String,
	name: String,
	type: CardType,
	card_data: Dictionary = {}
):
	id = card_id
	card_name = name
	card_type = type
	data = card_data

	if card_data.has("moon"):
		moon = int(card_data["moon"])
