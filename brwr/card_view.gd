extends Control


const CARD_SIZE = Vector2(80, 52)

var card_state: CardState


func _ready():
	size = CARD_SIZE
	custom_minimum_size = CARD_SIZE

	$Background.position = Vector2.ZERO
	$Background.size = CARD_SIZE

	$NameLabel.position = Vector2.ZERO
	$NameLabel.size = CARD_SIZE
	$NameLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$NameLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func setup(card: CardState):
	card_state = card
	refresh()


func refresh():
	if card_state == null:
		return

	$NameLabel.text = card_state.card_name
