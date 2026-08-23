class_name PlayerState
extends RefCounted


const MAX_CUBES: int = 25


var player_index: int
var player_name: String
var color: Color

var power: int = 0
var available_cubes: int = MAX_CUBES

var mage_id: String = ""
var school_id: String = ""

var mage: MageState


func _init(index: int, name: String, player_color: Color):
	player_index = index
	player_name = name
	color = player_color

	# Temporaneo: tutti i Mage hanno 10 Health.
	# Quando creeremo il database dei Mage, questo valore
	# verrà letto dai dati del Mage scelto.
	mage = MageState.new("", 10)


func take_cubes(amount: int) -> int:
	var taken = min(
		max(amount, 0),
		available_cubes
	)

	available_cubes -= taken

	return taken


func return_cubes(amount: int):
	available_cubes = min(
		available_cubes + max(amount, 0),
		MAX_CUBES
	)
