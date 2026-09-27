class_name CardView
extends Button


const DEFAULT_CARD_SIZE := Vector2(95, 132)

var card_state = null
var card_id: String = ""
var card_name: String = "Spell"
var hand_index: int = -1
var use_dark_side: bool = false
var selected: bool = false


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	refresh()


func setup(card) -> void:
	card_state = card

	if card_state == null:
		card_id = ""
		card_name = "Spell"
	else:
		card_id = str(card_state.id)
		card_name = str(card_state.card_name)

	refresh()


func setup_from_data(data: Dictionary) -> void:
	card_state = null
	card_id = str(data.get("id", ""))
	card_name = str(data.get("name", card_id))
	hand_index = int(data.get("hand_index", -1))
	refresh()


func set_display_size(new_size: Vector2) -> void:
	custom_minimum_size = new_size
	size = new_size

	if has_node("Artwork"):
		$Artwork.position = Vector2.ZERO
		$Artwork.size = new_size

	if has_node("Fallback"):
		$Fallback.position = Vector2.ZERO
		$Fallback.size = new_size

	if has_node("Fallback/NameLabel"):
		$Fallback/NameLabel.position = Vector2(6, 6)
		$Fallback/NameLabel.size = new_size - Vector2(12, 12)

	if has_node("SideLabel"):
		$SideLabel.position = Vector2(4, 4)
		$SideLabel.size = Vector2(max(54.0, new_size.x - 8.0), 18)


func set_side(dark_side: bool) -> void:
	use_dark_side = dark_side
	_refresh_side_label()


func set_selected(value: bool) -> void:
	selected = value

	if selected:
		self_modulate = Color(0.78, 0.92, 1.0, 1.0)
	else:
		self_modulate = Color.WHITE


func refresh() -> void:
	if not is_node_ready():
		return

	var texture := VisualAssets.load_spell_texture(card_id)
	$Artwork.texture = texture
	$Artwork.visible = texture != null
	$Fallback.visible = texture == null
	$Fallback/NameLabel.text = card_name

	tooltip_text = card_name
	_refresh_side_label()


func _refresh_side_label() -> void:
	if not is_node_ready():
		return

	if card_state == null and hand_index >= 0:
		$SideLabel.text = ""
		$SideLabel.visible = false
		return

	$SideLabel.visible = true
	$SideLabel.text = "DARK" if use_dark_side else "LIGHT"
