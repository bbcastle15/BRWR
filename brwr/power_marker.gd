extends Control

@export var marker_name: String = ""
@export var marker_color: Color = Color.WHITE

func _ready():
	$Body.color = marker_color
	$Label.text = marker_name
