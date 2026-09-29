extends Node2D

@export var cell_id: String = ""
@export var cell_name: String = "Cell"
@export var cell_color: Color = Color.DIM_GRAY
@export var radius: float = 70.0

func _ready():
	var background = $Background

	var points = PackedVector2Array()

	for i in range(6):
		var angle = deg_to_rad(60 * i)

		var point = Vector2(
			cos(angle) * radius,
			sin(angle) * radius
		)

		points.append(point)

	background.polygon = points
	background.color = cell_color
	var border := Line2D.new()
	border.name = "OwnerBorder"
	border.points = points
	border.closed = true
	border.width = 3.0
	border.default_color = cell_color
	border.z_index = 1
	add_child(border)

	$CellName.hide()
	if preload("res://room_art.gd").apply(background, "cell", radius):
		var owner_material := ShaderMaterial.new()
		owner_material.shader = preload("res://cell_owner_color.gdshader")
		owner_material.set_shader_parameter("owner_color", cell_color)
		background.material = owner_material
	$CellName.mouse_filter = Control.MOUSE_FILTER_IGNORE
