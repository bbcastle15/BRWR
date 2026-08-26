class_name MageState
extends RefCounted


var mage_id: String = ""
var health: int = 10
var room_id: String = ""
var room_coord: Vector2i = Vector2i.ZERO
# Ogni elemento rappresenta un Damage Cube presente sulla Mage Sheet.
#
# Convenzione owner_id:
# -1 = Black Rose
#  0 = Player 1
#  1 = Player 2
#  2 = Player 3
#  ...
var damage_cubes: Array[int] = []


func _init(id: String = "", mage_health: int = 10):
	mage_id = id
	health = mage_health


func get_damage() -> int:
	return damage_cubes.size()


func get_remaining_health() -> int:
	return health - get_damage()


func is_defeated() -> bool:
	return get_damage() >= health


func get_damage_from(owner_id: int) -> int:
	return damage_cubes.count(owner_id)


func add_damage(owner_id: int, amount: int) -> int:
	var amount_to_place = min(
		max(amount, 0),
		get_remaining_health()
	)

	for i in range(amount_to_place):
		damage_cubes.append(owner_id)

	return amount_to_place


func remove_damage(owner_id: int, amount: int) -> int:
	var removed = 0

	for i in range(amount):
		var index = damage_cubes.find(owner_id)

		if index == -1:
			break

		damage_cubes.remove_at(index)
		removed += 1

	return removed
