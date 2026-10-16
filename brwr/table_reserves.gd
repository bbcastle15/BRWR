extends Node2D

# Public tabletop display. Counts and cards are read from Game's existing pools.
const Preview = preload("res://reference_card_preview.gd")
const Style = preload("res://tabletop_style.gd")
const EVOCATION_SIZE := Vector2(178, 112)
const SCHOOL_SIZE := Vector2(114, 171)
const PILE_SIZE := Vector2(78, 117)
var game
var evocations: GridContainer
var schools: GridContainer
var discard_buttons: Dictionary = {}
var displayed_schools: Array[String] = []
var signature := ""

func setup(game_node) -> void:
	game = game_node
	name = "TableReserves"
	evocations = GridContainer.new()
	evocations.name = "EvocationReserve"
	evocations.columns = 4
	evocations.add_theme_constant_override("h_separation", 12)
	evocations.add_theme_constant_override("v_separation", 12)
	add_child(evocations)
	schools = GridContainer.new()
	schools.name = "SchoolLibraries"
	schools.columns = 2
	schools.add_theme_constant_override("h_separation", 18)
	schools.add_theme_constant_override("v_separation", 16)
	add_child(schools)
	for definition in game.evocation_database.get_all_evocations():
		if bool(definition.get("forgotten", false)):
			continue
		var id: String = str(definition.id)
		var card := Preview.make_card("evocations", id, str(definition.name), EVOCATION_SIZE, _inspect_evocation.bind(id))
		card.name = id
		evocations.add_child(card)
	refresh()

func _rebuild_schools() -> void:
	for row in schools.get_children():
		schools.remove_child(row)
		row.queue_free()
	discard_buttons.clear()
	displayed_schools.assign(game.active_school_ids)
	for id in displayed_schools:
		var row := HBoxContainer.new()
		row.name = id
		row.add_theme_constant_override("separation", 8)
		schools.add_child(row)
		row.add_child(Preview.make_card("schools", id, id.capitalize(), SCHOOL_SIZE, _inspect_school.bind(id)))
		var pile := VBoxContainer.new()
		pile.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(pile)
		var card := Preview.make_back("Discard · " + id.capitalize(), PILE_SIZE, _inspect_discard.bind(id))
		card.name = "Discard"
		pile.add_child(card)
		var count := Label.new()
		count.name = "Count"
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.add_theme_font_size_override("font_size", 12)
		count.add_theme_color_override("font_color", Style.PAPER)
		pile.add_child(count)
		discard_buttons[id] = card
	# Containers retain their previous size when children are removed.
	schools.size = schools.get_combined_minimum_size()

func layout() -> void:
	var event = game.get_node("EventBoard")
	var power = game.get_node("PowerBoard")
	var lodge: Rect2 = game.get_lodge_table_bounds()
	var left_edge: float = minf(lodge.position.x, event.position.x + event.ART_ORIGIN.x)
	var right_edge: float = maxf(lodge.end.x, power.position.x + power.ART_ORIGIN.x + power.ART_SIZE.x)
	var reserve_size := evocations.get_combined_minimum_size()
	evocations.position = Vector2(left_edge - reserve_size.x - 32, lodge.get_center().y - reserve_size.y / 2)
	schools.position = Vector2(right_edge + 32, lodge.get_center().y - schools.get_combined_minimum_size().y / 2)

func get_bounds() -> Rect2:
	return Rect2(evocations.position, evocations.get_combined_minimum_size()).merge(Rect2(schools.position, schools.get_combined_minimum_size()))

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	if displayed_schools != game.active_school_ids:
		_rebuild_schools()
		game.call_deferred("update_player_board_positions")
	var next := str(game.active_school_ids)
	for id in discard_buttons:
		next += str(game.get_school_discard(id).map(func(card): return card.id))
	if next == signature:
		return
	signature = next
	for id in discard_buttons:
		var discard: Array = game.get_school_discard(id)
		var card: Button = discard_buttons[id]
		var art: TextureRect = card.get_node("CardBack")
		art.texture = preload("res://assets/tabletop/card_back.png") if discard.is_empty() else SpellArtResolver.get_texture(discard.back().id)
		card.get_parent().get_node("Count").text = "%d discards" % discard.size()
		card.tooltip_text = "%s · %d discarded Spells" % [id.capitalize(), discard.size()]

func _inspect_evocation(id: String) -> void:
	var data: Dictionary = game.evocation_database.get_evocation(id)
	game._reference_card_preview().show_card("evocations", id, str(data.name), "Available copies: %d / %d" % [game.get_available_evocation_copies(id), int(data.get("copies", 0))])

func _inspect_school(id: String) -> void:
	game._reference_card_preview().show_card("schools", id, id.capitalize(), "")

func _inspect_discard(id: String) -> void:
	game._reference_card_preview().show_spell_pile(game.get_school_discard(id), id.capitalize() + " — Discards")
