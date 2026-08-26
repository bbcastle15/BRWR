class_name EvocationState
extends RefCounted


var evocation_id: String = ""
var evocation_name: String = ""
var archetype: String = ""

var owner_id: int = -1
var controller_id: int = -1

var health: int = 0
var strength: int = 0
var speed: int = 0

var room_id: String = ""

var damage_cubes: Array[int] = []


func _init(
	id: String,
	name: String,
	evocation_archetype: String,
	evocation_health: int,
	evocation_strength: int,
	evocation_speed: int,
	owner: int
):
	evocation_id = id
	evocation_name = name
	archetype = evocation_archetype

	health = evocation_health
	strength = evocation_strength
	speed = evocation_speed

	owner_id = owner
	controller_id = owner


func get_damage() -> int:
	return damage_cubes.size()


func get_remaining_health() -> int:
	return health - get_damage()


func is_defeated() -> bool:
	return get_damage() >= health


func add_damage(owner: int, amount: int) -> int:
	var amount_to_place = min(
		max(amount, 0),
		get_remaining_health()
	)

	for i in range(amount_to_place):
		damage_cubes.append(owner)

	return amount_to_place


func get_damage_from(owner: int) -> int:
	return damage_cubes.count(owner)
