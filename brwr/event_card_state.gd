class_name EventCardState
extends RefCounted


var id: String = ""
var event_name: String = ""

var moon: int = 1

var crown: bool = false

var phase: String = ""

# 0 = Instant
# 1, 2, 3 = Event Board slot
var slot: int = 0

var reveal_power: int = 0
var discard_power: int = 0

var effects: Array = []

var text: String = ""


func _init(
	card_id: String = "",
	card_name: String = "",
	card_moon: int = 1,
	has_crown: bool = false,
	card_phase: String = "",
	card_slot: int = 0,
	card_reveal_power: int = 0,
	card_discard_power: int = 0,
	card_effects: Array = [],
	card_text: String = ""
):
	id = card_id
	event_name = card_name
	moon = card_moon
	crown = has_crown
	phase = card_phase
	slot = card_slot
	reveal_power = card_reveal_power
	discard_power = card_discard_power
	effects = card_effects
	text = card_text


func is_instant() -> bool:
	return phase == "instant"
