extends Node2D


var player_index: int = -1
var token_color: Color = Color.WHITE


func setup(index: int, color: Color):
	player_index = index
	token_color = color

	create_shape()

	$Label.text = str(index + 1)


func create_shape():
	var points = PackedVector2Array([
		Vector2(-10, -10),
		Vector2(10, -10),
		Vector2(10, 10),
		Vector2(-10, 10)
	])

	$Body.polygon = points
	$Body.color = token_color
