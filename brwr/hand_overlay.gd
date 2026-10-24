class_name HandOverlay
extends Control


signal preparation_confirmed(payload: Dictionary)
signal study_confirmed(indices: Array)
signal quest_selection_confirmed(tokens: Array)
signal overlay_closed
signal confirmation_changed(button: Button)


const MODE_BROWSE := "browse"
const MODE_PREPARATION := "preparation"
const MODE_STUDY := "study"
const MODE_MEMORIES := "memories"
const MODE_QUEST_SELECTION := "quest_selection"
var study_selection: Array[int] = []
var study_confirm_button: Button
var quest_selection: Array[String] = []
var quest_selection_min: int = 0
var quest_selection_max: int = 0

const CARD_ASPECT := 2.0 / 3.0
const CARD_MAX_WIDTH := 630.0
const CARD_GAP := 18
const VISIBLE_CARD_LIMIT := 6
const CARD_FRAME_HEIGHT := 44.0

# First try the common deterministic paths. If none exists, the script performs
# one cached recursive search for <spell_id>.png under res://.
const CARD_ART_ROOTS: Array[String] = [
	"res://assets/cards/spells",
	"res://assets/cards",
	"res://assets/spell_cards",
	"res://assets/spells",
	"res://cards/spells",
	"res://cards",
	"res://spell_cards",
	"res://art/cards",
	"res://art/spells",
	"res://images/cards",
	"res://images/spells"
]


var game = null

var mode: String = MODE_BROWSE
var owner_player_index: int = -1
var current_request: Dictionary = {}
var cards: Array = []

var selected_hand_index: int = -1
var selected_dark: bool = false

var ready_hand_indices: Array[int] = []
var ready_dark_sides: Array[bool] = []
var quick_hand_index: int = -1
var quick_dark_side: bool = false

var texture_cache: Dictionary = {}


var dim_background: ColorRect
var main_panel: PanelContainer

var title_label: Label
var instruction_label: Label
var count_label: Label
var close_button: Button

var card_scroll: ScrollContainer
var card_row: GridContainer

var prep_controls: VBoxContainer
var selection_label: Label
var slots_label: Label
var side_label: Label

var light_button: Button
var dark_button: Button
var ready_button: Button
var quick_button: Button
var unassign_button: Button
var clear_button: Button
var confirm_button: Button

var feedback_label: Label
var tabs: TabBar
var quest_scroll: ScrollContainer
var quest_columns: HBoxContainer
var jinx_scroll: ScrollContainer
var jinx_row: HBoxContainer
var jinx_signature := ""
var quest_signature := ""
var cards_heading := ""
var cards_instructions := ""


func setup(game_node) -> void:
	game = game_node

	name = "HandOverlay"
	set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1000
	visible = false

	_build_ui()
	visibility_changed.connect(_update_controls)


func _build_ui() -> void:
	dim_background = ColorRect.new()
	dim_background.color = Color(0.0, 0.0, 0.0, 0.78)
	dim_background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	dim_background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim_background)

	var outer_margin := MarginContainer.new()
	outer_margin.mouse_filter = Control.MOUSE_FILTER_STOP
	outer_margin.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	outer_margin.add_theme_constant_override("margin_left", 12)
	outer_margin.add_theme_constant_override("margin_right", 12)
	outer_margin.add_theme_constant_override("margin_top", 12)
	outer_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(outer_margin)

	main_panel = PanelContainer.new()
	main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	main_panel.add_theme_stylebox_override("panel", preload("res://tabletop_style.gd").fabric_panel())

	outer_margin.add_child(main_panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 20)
	panel_margin.add_theme_constant_override("margin_right", 20)
	panel_margin.add_theme_constant_override("margin_top", 16)
	panel_margin.add_theme_constant_override("margin_bottom", 16)
	main_panel.add_child(panel_margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	panel_margin.add_child(root)

	# -----------------------------------------------------
	# HEADER
	# -----------------------------------------------------

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var header_text := VBoxContainer.new()
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_text)

	title_label = Label.new()
	title_label.text = "HAND"
	title_label.add_theme_font_size_override("font_size", 24)
	header_text.add_child(title_label)

	instruction_label = Label.new()
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction_label.modulate = Color(0.86, 0.86, 0.86)
	header_text.add_child(instruction_label)

	count_label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 16)
	header.add_child(count_label)

	close_button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(90, 42)
	close_button.pressed.connect(
		_on_close_pressed
	)
	header.add_child(close_button)

	root.add_child(HSeparator.new())

	# -----------------------------------------------------
	# LARGE CARD STRIP
	# -----------------------------------------------------
	tabs = TabBar.new()
	tabs.add_tab("Cards")
	tabs.add_tab("Quests")
	tabs.add_tab("Jinx")
	tabs.tab_changed.connect(_change_tab)
	root.add_child(tabs)

	var hand_body := HBoxContainer.new()
	hand_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_body.add_theme_constant_override("separation", 18)
	root.add_child(hand_body)
	card_scroll = ScrollContainer.new()
	card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.resized.connect(func(): call_deferred("_layout_cards"))
	hand_body.add_child(card_scroll)

	var card_margin := MarginContainer.new()
	card_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_margin.add_theme_constant_override("margin_left", 8)
	card_margin.add_theme_constant_override("margin_right", 8)
	card_margin.add_theme_constant_override("margin_top", 6)
	card_margin.add_theme_constant_override("margin_bottom", 6)
	card_scroll.add_child(card_margin)

	var card_center := CenterContainer.new()
	card_margin.add_child(card_center)
	card_row = GridContainer.new()
	card_row.columns = 1
	card_row.add_theme_constant_override("h_separation", CARD_GAP)
	card_row.add_theme_constant_override("v_separation", 12)
	card_center.add_child(card_row)
	quest_scroll = ScrollContainer.new()
	quest_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quest_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_body.add_child(quest_scroll)
	quest_columns = HBoxContainer.new()
	quest_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_columns.add_theme_constant_override("separation", 18)
	quest_scroll.add_child(quest_columns)
	quest_scroll.hide()
	jinx_scroll = ScrollContainer.new()
	jinx_scroll.name = "JinxCards"
	jinx_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jinx_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	jinx_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_body.add_child(jinx_scroll)
	jinx_row = HBoxContainer.new()
	jinx_row.add_theme_constant_override("separation", 20)
	jinx_scroll.add_child(jinx_row)
	jinx_scroll.hide()

	root.add_child(HSeparator.new())

	# -----------------------------------------------------
	# PREPARATION CONTROLS
	# -----------------------------------------------------

	prep_controls = VBoxContainer.new()
	prep_controls.add_theme_constant_override("separation", 8)
	root.add_child(prep_controls)
	var preparation_summary := HBoxContainer.new()
	preparation_summary.add_theme_constant_override("separation", 20)
	prep_controls.add_child(preparation_summary)

	selection_label = Label.new()
	selection_label.add_theme_font_size_override("font_size", 17)
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preparation_summary.add_child(selection_label)

	slots_label = Label.new()
	slots_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slots_label.add_theme_font_size_override("font_size", 15)
	slots_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	preparation_summary.add_child(slots_label)

	var choice_row := HBoxContainer.new()
	choice_row.add_theme_constant_override("separation", 8)
	prep_controls.add_child(choice_row)

	side_label = Label.new()
	side_label.text = "Side:"
	side_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	choice_row.add_child(side_label)

	light_button = Button.new()
	light_button.text = "Light"
	light_button.toggle_mode = true
	light_button.custom_minimum_size = Vector2(90, 40)
	light_button.pressed.connect(
		Callable(self, "_set_selected_side").bind(false)
	)
	choice_row.add_child(light_button)

	dark_button = Button.new()
	dark_button.text = "Dark"
	dark_button.toggle_mode = true
	dark_button.custom_minimum_size = Vector2(90, 40)
	dark_button.pressed.connect(
		Callable(self, "_set_selected_side").bind(true)
	)
	choice_row.add_child(dark_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_row.add_child(spacer)

	ready_button = Button.new()
	ready_button.text = "Ready"
	ready_button.custom_minimum_size = Vector2(130, 40)
	ready_button.pressed.connect(
		_assign_selected_numbered
	)
	choice_row.add_child(ready_button)

	quick_button = Button.new()
	quick_button.text = "Quick"
	quick_button.custom_minimum_size = Vector2(120, 40)
	quick_button.pressed.connect(
		_assign_selected_quick
	)
	choice_row.add_child(quick_button)

	unassign_button = Button.new()
	unassign_button.text = "Unassign"
	unassign_button.custom_minimum_size = Vector2(110, 40)
	unassign_button.pressed.connect(
		_unassign_selected
	)
	choice_row.add_child(unassign_button)

	feedback_label = Label.new()
	feedback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.modulate = Color(0.90, 0.82, 0.55)
	prep_controls.add_child(feedback_label)

	clear_button = Button.new()
	clear_button.text = "Clear"
	clear_button.custom_minimum_size = Vector2(100, 42)
	clear_button.pressed.connect(
		_clear_preparation
	)
	choice_row.add_child(clear_button)

	confirm_button = Button.new()
	confirm_button.text = "Confirm"
	confirm_button.custom_minimum_size = Vector2(130, 42)
	confirm_button.pressed.connect(
		_confirm_preparation
	)
	header.add_child(confirm_button)
	header.move_child(confirm_button, header.get_child_count() - 2)
	study_confirm_button = Button.new()
	study_confirm_button.text = "Keep selected cards"
	study_confirm_button.pressed.connect(_on_header_selection_confirmed)
	study_confirm_button.hide()
	header.add_child(study_confirm_button)
	header.move_child(study_confirm_button, header.get_child_count() - 2)


func open_study(request: Dictionary) -> void:
	mode = MODE_STUDY
	current_request = request.duplicate(true)
	owner_player_index = int(request.get("player_index", -1))
	cards = request.get("cards", []).duplicate(true)
	for card in cards:
		card["hand_index"] = card.get("draw_index", -1)
	study_selection.clear()
	ready_hand_indices.clear()
	quick_hand_index = -1
	selected_hand_index = -1
	title_label.text = "PLAYER %d — STUDY" % (owner_player_index + 1)
	instruction_label.text = "Choose two cards to keep. Click a selected card to deselect it."
	close_button.disabled = false
	close_button.text = "Hide"
	prep_controls.hide()
	study_confirm_button.show()
	visible = true
	move_to_front()
	_render_cards()
	_update_controls()
	_select_cards_tab(true)


func _on_header_selection_confirmed() -> void:
	if mode == MODE_STUDY:
		if study_selection.size() == 2:
			study_confirmed.emit(study_selection.duplicate())
		return
	if mode == MODE_QUEST_SELECTION:
		if quest_selection.size() >= quest_selection_min and quest_selection.size() <= quest_selection_max:
			quest_selection_confirmed.emit(quest_selection.duplicate())


func open_quest_selection(request: Dictionary) -> void:
	if game == null:
		return
	mode = MODE_QUEST_SELECTION
	current_request = request.duplicate(true)
	owner_player_index = int(request.get("player_index", -1))
	if owner_player_index < 0 or owner_player_index >= game.players.size():
		return
	quest_selection.clear()
	quest_selection_min = int(request.get("min_select", 0))
	quest_selection_max = int(request.get("max_select", 1))
	cards.clear()
	selected_hand_index = -1
	title_label.text = "PLAYER %d — QUESTS" % (owner_player_index + 1)
	instruction_label.text = str(request.get("prompt", "Choose Quest cards."))
	close_button.visible = true
	close_button.disabled = false
	close_button.text = "Hide"
	prep_controls.hide()
	study_confirm_button.show()
	study_confirm_button.text = "Confirm Quest selection"
	visible = true
	move_to_front()
	tabs.set_current_tab(1)
	_change_tab(1)
	_update_controls()


func open_preparation(
	request: Dictionary
) -> void:
	mode = MODE_PREPARATION
	study_confirm_button.hide()
	current_request = request.duplicate(true)
	owner_player_index = int(
		current_request.get(
			"player_index",
			-1
		)
	)

	cards = current_request.get(
		"hand",
		[]
	).duplicate(true)

	selected_hand_index = -1
	selected_dark = false

	ready_hand_indices.clear()
	ready_dark_sides.clear()
	quick_hand_index = -1
	quick_dark_side = false

	title_label.text = (
		"PLAYER "
		+ str(owner_player_index + 1)
		+ " — PREPARATION"
	)

	instruction_label.text = (
		"Choose Light or Dark, then prepare 2–4 Spells in I–III or Quick. Scroll to see more cards."
	)

	close_button.visible = true
	close_button.disabled = false
	close_button.text = "Hide"

	prep_controls.visible = true
	feedback_label.text = ""

	visible = true
	move_to_front()

	_render_cards()
	_update_controls()
	_select_cards_tab(true)


func open_memories(player_index: int) -> void:
	if game == null or player_index < 0 or player_index >= game.players.size():
		return
	mode = MODE_MEMORIES
	study_confirm_button.hide()
	current_request.clear()
	owner_player_index = player_index
	cards.clear()
	for i in range(game.players[player_index].memories.size()):
		var spell = game.players[player_index].memories[i]
		if spell == null:
			continue
		cards.append({
			"hand_index": i,
			"id": spell.id,
			"name": spell.card_name,
			"school_id": spell.school_id
		})
	selected_hand_index = -1
	title_label.text = "PLAYER %d — MEMORIES" % (player_index + 1)
	instruction_label.text = "Public Spell discard pile."
	close_button.visible = true
	close_button.disabled = false
	close_button.text = "Close"
	prep_controls.hide()
	visible = true
	move_to_front()
	_render_cards()
	_update_controls()
	_select_cards_tab(true)


func open_browse(
	player_index: int
) -> void:
	if game == null:
		return

	if player_index < 0 \
	or player_index >= game.players.size():
		return
	if player_index != game.get_ui_viewer_player_index():
		return

	mode = MODE_BROWSE
	study_confirm_button.hide()
	current_request.clear()
	owner_player_index = player_index

	var state: Dictionary = game.get_beta_game_state(
		player_index
	)

	var player_states: Array = state.get(
		"players",
		[]
	)

	if player_index >= player_states.size():
		return

	var player_data: Dictionary = player_states[
		player_index
	]

	cards.clear()

	var source_hand: Array = player_data.get(
		"hand",
		[]
	)

	for i in range(source_hand.size()):
		var card_value = source_hand[i]

		if not card_value is Dictionary:
			continue

		var card: Dictionary = card_value.duplicate(
			true
		)

		card["hand_index"] = i
		cards.append(card)

	selected_hand_index = -1
	selected_dark = false

	title_label.text = (
		"PLAYER "
		+ str(player_index + 1)
		+ " — HAND"
	)

	instruction_label.text = (
		"Browse your Hand. Press H, Esc, or Close to return to the Lodge."
	)

	close_button.visible = true
	close_button.disabled = false
	close_button.text = "Close"

	prep_controls.visible = false

	visible = true
	move_to_front()

	_render_cards()
	_update_controls()
	_select_cards_tab(true)


func _select_cards_tab(refresh_heading: bool = false) -> void:
	if refresh_heading:
		cards_heading = title_label.text
		cards_instructions = instruction_label.text
	tabs.set_current_tab(0)
	_change_tab(0)


func _change_tab(index: int) -> void:
	if mode == MODE_MEMORIES and index != 0:
		tabs.set_current_tab(0)
		index = 0
	card_scroll.visible = index == 0
	quest_scroll.visible = index == 1
	jinx_scroll.visible = index == 2
	prep_controls.visible = index == 0 and mode == MODE_PREPARATION
	if index == 1:
		title_label.text = "PLAYER %d — QUESTS" % (owner_player_index + 1)
		if mode == MODE_QUEST_SELECTION:
			instruction_label.text = str(current_request.get("prompt", "Choose Quest cards."))
		else:
			instruction_label.text = "Complete the Task of an Active Quest, then resolve its Effects during your Activation. Solved Quests award Power."
		count_label.text = ""
		_render_quests()
	elif index == 2:
		title_label.text = "PLAYER %d — JINX" % (owner_player_index + 1)
		instruction_label.text = "Assigned Jinxes. Complete each card's Task to discard it. Click a card to inspect."
		_render_jinxes()
	else:
		title_label.text = cards_heading
		instruction_label.text = cards_instructions
		count_label.text = "%d cards" % cards.size()
		call_deferred("_layout_cards")
	# A preparation/study draft belongs to the Cards tab, and is preserved.
	_update_controls()


func _process(_delta: float) -> void:
	if not visible or game == null:
		return
	if mode != MODE_MEMORIES and owner_player_index != game.get_ui_viewer_player_index():
		close_overlay(true)
		return
	if tabs.current_tab == 1:
		var signature := str(game.get_player_board_action_options(owner_player_index, "quests"))
		for data in game.get_player_quest_cards(owner_player_index, "active") + game.get_player_quest_cards(owner_player_index, "completed") + game.get_player_quest_cards(owner_player_index, "solved"):
			var quest: QuestState = data.quest
			signature += str([quest.get_instance_id(), quest.revealed, quest.progress, quest.completed, quest.solved])
		if signature != quest_signature:
			quest_signature = signature
			_render_quests()
	elif tabs.current_tab == 2:
		var signature := str(game.players[owner_player_index].mage.jinxes)
		if signature != jinx_signature:
			_render_jinxes()


func _render_jinxes() -> void:
	for child in jinx_row.get_children():
		jinx_row.remove_child(child)
		child.queue_free()
	var assigned: Array = game.players[owner_player_index].mage.jinxes
	jinx_signature = str(assigned)
	count_label.text = "%d Jinx" % assigned.size()
	if assigned.is_empty():
		var empty := Label.new()
		empty.text = "No Jinx assigned."
		jinx_row.add_child(empty)
	for jinx in assigned:
		var data := ForgottenAttachments.definition("jinxes", str(jinx.id))
		var column := VBoxContainer.new()
		column.name = "Jinx_" + str(jinx.id)
		jinx_row.add_child(column)
		var height: float = clampf(get_viewport_rect().size.y - 340, 320, 590)
		var card: Button = game.ReferenceCardPreview.make_card("jinxs", str(jinx.id), str(data.get("name", jinx.id)),
			Vector2(height * 0.65, height), game.open_jinx_card.bind(owner_player_index, str(jinx.id)))
		column.add_child(card)
		var progress := HBoxContainer.new()
		progress.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_child(progress)
		for i in int(data.get("slots", 0)):
			var cube = preload("res://cube.tscn").instantiate()
			cube.cube_color = game.players[owner_player_index].color if i < int(jinx.progress) else Color("35373c")
			progress.add_child(cube)
		var count := Label.new()
		count.text = "  %d / %d" % [int(jinx.progress), int(data.get("slots", 0))]
		progress.add_child(count)


func _quest_selection_option(quest: QuestState, section: String) -> Dictionary:
	if mode != MODE_QUEST_SELECTION or quest == null:
		return {}
	var normalized_section: String = section
	for option_value in current_request.get("options", []):
		if not option_value is Dictionary:
			continue
		var option: Dictionary = option_value
		var option_section: String = str(option.get("quest_section", ""))
		if option_section == "revealed":
			option_section = "active"
		if option_section != "" and option_section != normalized_section:
			continue
		if str(option.get("id", "")) == quest.get_id():
			return option
	return {}


func _toggle_quest_selection(token: String) -> void:
	if mode != MODE_QUEST_SELECTION or token == "":
		return
	if quest_selection.has(token):
		quest_selection.erase(token)
	elif quest_selection.size() < quest_selection_max:
		quest_selection.append(token)
	_render_quests()
	_update_controls()


func _render_quest_progress_cubes(card: Control, quest: QuestState, card_size: Vector2) -> void:
	# Printed Quest art already contains the empty slots. Overlay only cubes that
	# are actually on the card, aligned left-to-right over the printed row.
	var placed: int = mini(quest.progress, quest.get_cube_slots())
	if placed <= 0:
		return
	var overlay := Control.new()
	overlay.name = "QuestProgress"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(overlay)
	var cube_scale: float = card_size.x / 112.0 * 0.82
	var cube_visual: float = 14.0 * cube_scale
	var gap: float = 3.0 * cube_scale
	var total_width: float = placed * cube_visual + maxi(0, placed - 1) * gap
	var start_x: float = (card_size.x - total_width) * 0.5
	var slot_y: float = card_size.y * 0.555 - cube_visual * 0.5
	for i in range(placed):
		var cube = preload("res://cube.tscn").instantiate()
		cube.cube_color = game.players[owner_player_index].color
		cube.scale = Vector2.ONE * cube_scale
		cube.position = Vector2(start_x + i * (cube_visual + gap), slot_y)
		overlay.add_child(cube)


func _render_quests() -> void:
	for child in quest_columns.get_children():
		quest_columns.remove_child(child)
		child.queue_free()
	for section in ["active", "completed", "solved"]:
		var column := VBoxContainer.new()
		column.name = section.capitalize()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = 1.0
		column.add_theme_constant_override("separation", 12)
		quest_columns.add_child(column)
		var entries: Array = game.get_player_quest_cards(owner_player_index, section)
		var heading := Label.new()
		heading.text = "%s · %d" % [section.capitalize(), entries.size()]
		heading.add_theme_font_size_override("font_size", 21)
		heading.add_theme_color_override("font_color", Color("cbb178"))
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(heading)
		if entries.is_empty():
			var empty := Label.new()
			empty.text = "—"
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(empty)
		for data in entries:
			var quest: QuestState = data.quest
			var center := CenterContainer.new()
			column.add_child(center)
			var width := clampf((main_panel.size.x - 160) / 3.0, 140, 260)
			var card_size := Vector2(width, width * 1.42)
			var selection_option: Dictionary = _quest_selection_option(quest, section)
			var selection_token: String = str(selection_option.get("token", ""))
			var callback: Callable = game.open_quest_card.bind(quest)
			if mode == MODE_QUEST_SELECTION and selection_token != "":
				callback = _toggle_quest_selection.bind(selection_token)
			var card: Button = game.ReferenceCardPreview.make_back("Solved Quest · Inspect", card_size, callback) if section == "solved" else game.ReferenceCardPreview.make_card("quests", quest.get_id(), quest.get_name(), card_size, callback)
			card.set_meta("choice_quest", quest)
			center.add_child(card)
			if mode == MODE_QUEST_SELECTION:
				card.disabled = selection_token == ""
				card.modulate = Color.WHITE if selection_token != "" else Color(0.55, 0.55, 0.55, 0.72)
				if selection_token != "" and quest_selection.has(selection_token):
					var selected_frame := Panel.new()
					selected_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
					selected_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
					var style := StyleBoxFlat.new()
					style.bg_color = Color(0.15, 0.65, 0.25, 0.08)
					style.border_color = Color(0.3, 1.0, 0.45, 0.95)
					style.set_border_width_all(5)
					style.set_corner_radius_all(8)
					selected_frame.add_theme_stylebox_override("panel", style)
					selected_frame.z_index = 40
					card.add_child(selected_frame)
			if section != "solved":
				_render_quest_progress_cubes(card, quest, card_size)
			var status := Label.new()
			status.text = "Revealed" if quest.revealed else "Private"
			if section != "active": status.text = section.capitalize()
			if mode == MODE_QUEST_SELECTION and selection_token != "":
				status.text = "SELECTED" if quest_selection.has(selection_token) else "Click to select"
			status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(status)
			if section == "completed" and mode != MODE_QUEST_SELECTION:
				var solve := Button.new()
				solve.text = "Resolve Quest"
				solve.disabled = true
				for option in game.get_player_board_action_options(owner_player_index, "quests"):
					var index: int = int(option.get("descriptor", {}).get("quest_index", -1))
					if index >= 0 and index < game.players[owner_player_index].completed_quests.size() and game.players[owner_player_index].completed_quests[index] == quest:
						solve.disabled = false
						solve.pressed.connect(_resolve_quest.bind(str(option.token)), CONNECT_DEFERRED)
				column.add_child(solve)


func _resolve_quest(token: String) -> void:
	if owner_player_index != game.get_ui_viewer_player_index():
		return
	game.submit_beta_input(owner_player_index, {"token": token})


func close_overlay(
	force: bool = false
) -> void:
	if not visible:
		return

	visible = false
	overlay_closed.emit()


func is_mandatory_open() -> bool:
	return (
		visible
		and mode == MODE_PREPARATION
	)


func _on_close_pressed() -> void:
	close_overlay(false)


func _unhandled_key_input(
	event: InputEvent
) -> void:
	if not visible:
		return

	if not event is InputEventKey:
		return

	if not event.pressed \
	or event.echo:
		return

	if event.keycode == KEY_ESCAPE:
		close_overlay(false)


func _render_cards() -> void:
	for child in card_row.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()

	count_label.text = (
		str(cards.size())
		+ (
			" cards"
			if cards.size() != 1
			else " card"
		)
	)

	if cards.is_empty():
		var empty := Label.new()
		empty.text = "No cards." if mode == MODE_MEMORIES else "Your Hand is empty."
		empty.add_theme_font_size_override("font_size", 20)
		card_row.add_child(empty)
		return

	var display_size := _card_display_size(
		cards.size()
	)

	for card_value in cards:
		if not card_value is Dictionary:
			continue

		var card: Dictionary = card_value
		var hand_index: int = int(
			card.get(
				"hand_index",
				-1
			)
		)

		card_row.add_child(
			_create_card_widget(
				card,
				hand_index,
				display_size
			)
		)
	call_deferred("_layout_cards")


func _card_display_size(
	_card_count: int
) -> Vector2:
	# Readability comes from the available height. Width may require scrolling,
	# including with fewer than six cards on a laptop; never shrink to fit all.
	var available_width: float = maxf(1.0, card_scroll.size.x - 36.0)
	var available_height: float = maxf(1.0, card_scroll.size.y - 32.0)
	var height_limit: float = available_height - CARD_FRAME_HEIGHT
	# One card still fits on narrow viewports; image height must fit vertically.
	var width: float = maxf(1.0, minf(CARD_MAX_WIDTH, minf(available_width - 20.0, height_limit * CARD_ASPECT)))
	return Vector2(width, width / CARD_ASPECT)


func _layout_cards() -> void:
	if cards.is_empty():
		return
	card_row.columns = maxi(cards.size(), 1)
	var display_size := _card_display_size(cards.size())
	var frame_width: float = display_size.x + 20.0
	if cards.size() > VISIBLE_CARD_LIMIT:
		frame_width = maxf(frame_width, (card_scroll.size.x - 36.0 - (VISIBLE_CARD_LIMIT - 1) * CARD_GAP) / VISIBLE_CARD_LIMIT)
	for frame in card_row.get_children():
		frame.custom_minimum_size = Vector2(frame_width, display_size.y + CARD_FRAME_HEIGHT)
		var button: TextureButton = frame.get_meta("card_button")
		button.custom_minimum_size = display_size


func _create_card_widget(
	card: Dictionary,
	hand_index: int,
	display_size: Vector2
) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(
		display_size.x + 12.0,
		display_size.y + 66.0
	)

	var selected: bool = (
		study_selection.has(hand_index) if mode == MODE_STUDY else hand_index == selected_hand_index
	)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		0.10,
		0.10,
		0.10,
		0.95
	)
	style.border_color = (
		Color(0.93, 0.72, 0.24, 1.0)
		if selected
		else Color(0.28, 0.28, 0.28, 1.0)
	)
	style.set_border_width_all(
		4 if selected else 2
	)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	frame.add_theme_stylebox_override(
		"panel",
		style
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var header := HBoxContainer.new()
	# The illustration already contains the card name; keep only its tooltip.
	header.hide()
	column.add_child(header)

	var name_label := Label.new()
	name_label.text = str(
		card.get(
			"name",
			card.get(
				"id",
				"Spell"
			)
		)
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override(
		"font_size",
		16
	)
	header.add_child(name_label)

	var assignment_label := Label.new()
	assignment_label.text = _assignment_badge(
		hand_index
	)
	assignment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	assignment_label.add_theme_font_size_override(
		"font_size",
		15
	)
	assignment_label.modulate = Color(
		0.96,
		0.80,
		0.35
	)
	header.add_child(assignment_label)

	var card_button := TextureButton.new()
	frame.set_meta("card_button", card_button)
	card_button.custom_minimum_size = display_size
	card_button.ignore_texture_size = true
	card_button.stretch_mode = (
		TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	)
	card_button.tooltip_text = name_label.text

	var texture := _resolve_card_texture(
		card
	)

	if texture != null:
		card_button.texture_normal = texture
	else:
		var fallback := GradientTexture2D.new()
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([
			Color(0.18, 0.18, 0.18),
			Color(0.08, 0.08, 0.08)
		])
		fallback.gradient = gradient
		fallback.width = int(display_size.x)
		fallback.height = int(display_size.y)
		card_button.texture_normal = fallback

	game.connect_card_choice(card_button, {"card_kind": "spells", "id": str(card.get("id", "")), "name": name_label.text}, _select_card.bind(hand_index))

	column.add_child(card_button)
	if mode == MODE_PREPARATION and not _single_effect_card(hand_index) and (selected or _is_assigned(hand_index)):
		var side := preload("res://tabletop_style.gd").spell_side_frame()
		card_button.add_child(side)
		var dark := selected_dark if selected else _assigned_dark_side(hand_index)
		var fit := func(): preload("res://tabletop_style.gd").fit_spell_side(side, card_button.size, texture, dark)
		card_button.resized.connect(fit)
		fit.call_deferred()

	var hint := Label.new()
	var assignment := _assignment_badge(hand_index)
	hint.text = assignment if not assignment.is_empty() else ("SELECTED" if selected else "")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = (
		Color(0.93, 0.72, 0.24)
		if selected
		else Color(0.68, 0.68, 0.68)
	)
	column.add_child(hint)

	return frame


func _assignment_badge(
	hand_index: int
) -> String:
	if mode != MODE_PREPARATION:
		return ""
	var numbered_index: int = ready_hand_indices.find(
		hand_index
	)

	if numbered_index != -1:
		if _single_effect_card(hand_index):
			return _roman_slot(numbered_index)
		return (
			_roman_slot(
				numbered_index
			)
			+ " • "
			+ (
				"D"
				if ready_dark_sides[numbered_index]
				else "L"
			)
		)

	if quick_hand_index == hand_index:
		if _single_effect_card(hand_index):
			return "Q"
		return (
			"Q • "
			+ (
				"D"
				if quick_dark_side
				else "L"
			)
		)

	return ""


func _select_card(
	hand_index: int
) -> void:
	if mode == MODE_STUDY:
		if study_selection.has(hand_index):
			study_selection.erase(hand_index)
		elif study_selection.size() < 2:
			study_selection.append(hand_index)
		_render_cards()
		_update_controls()
		return
	selected_hand_index = hand_index
	selected_dark = _assigned_dark_side(
		hand_index
	)

	feedback_label.text = ""

	_render_cards()
	_update_controls()


func _assigned_dark_side(
	hand_index: int
) -> bool:
	var numbered_index: int = ready_hand_indices.find(
		hand_index
	)

	if numbered_index != -1:
		return ready_dark_sides[
			numbered_index
		]

	if quick_hand_index == hand_index:
		return quick_dark_side

	return false


func _selected_dark_playable() -> bool:
	for card in cards:
		if card is Dictionary and int(card.get("hand_index", -1)) == selected_hand_index:
			if card.has("dark_playable"):
				return bool(card.dark_playable)
			if game != null:
				var spell: SpellCardState = game.spell_database.get_spell(str(card.get("id", "")))
				return spell == null or spell.is_playable_side(true)
			return true
	return true


func _single_effect_card(hand_index: int) -> bool:
	for card in cards:
		if int(card.get("hand_index", -1)) == hand_index:
			var spell: SpellCardState = game.spell_database.get_spell(str(card.get("id", "")))
			return spell != null and spell.has_single_effect()
	return false


func _set_selected_side(
	use_dark: bool
) -> void:
	if selected_hand_index == -1:
		return
	if use_dark and not _selected_dark_playable():
		return

	selected_dark = use_dark

	var numbered_index: int = ready_hand_indices.find(
		selected_hand_index
	)

	if numbered_index != -1:
		ready_dark_sides[
			numbered_index
		] = selected_dark

	if quick_hand_index == selected_hand_index:
		quick_dark_side = selected_dark

	_render_cards()
	_update_controls()


func _assign_selected_numbered() -> void:
	if selected_hand_index == -1:
		return

	var existing_index: int = ready_hand_indices.find(
		selected_hand_index
	)

	if existing_index != -1:
		ready_dark_sides[
			existing_index
		] = selected_dark
		feedback_label.text = (
			"Updated "
			+ _roman_slot(existing_index)
			+ " to "
			+ _side_name(selected_dark)
			+ "."
		)
		_render_cards()
		_update_controls()
		return

	if quick_hand_index == selected_hand_index:
		quick_hand_index = -1
		quick_dark_side = false

	var max_numbered: int = int(
		current_request.get(
			"max_numbered_spells",
			3
		)
	)

	if ready_hand_indices.size() >= max_numbered:
		feedback_label.text = (
			"All numbered Spell Slots are already filled."
		)
		_update_controls()
		return

	ready_hand_indices.append(
		selected_hand_index
	)
	ready_dark_sides.append(
		selected_dark
	)

	feedback_label.text = (
		"Assigned to "
		+ _roman_slot(
			ready_hand_indices.size() - 1
		)
		+ " — "
		+ _side_name(selected_dark)
		+ "."
	)

	_render_cards()
	_update_controls()


func _assign_selected_quick() -> void:
	if selected_hand_index == -1:
		return

	var numbered_index: int = ready_hand_indices.find(
		selected_hand_index
	)

	if numbered_index != -1:
		ready_hand_indices.remove_at(
			numbered_index
		)
		ready_dark_sides.remove_at(
			numbered_index
		)

	quick_hand_index = selected_hand_index
	quick_dark_side = selected_dark

	feedback_label.text = (
		"Assigned to Quick — "
		+ _side_name(selected_dark)
		+ "."
	)

	_render_cards()
	_update_controls()


func _unassign_selected() -> void:
	if selected_hand_index == -1:
		return

	var changed: bool = false

	var numbered_index: int = ready_hand_indices.find(
		selected_hand_index
	)

	if numbered_index != -1:
		ready_hand_indices.remove_at(
			numbered_index
		)
		ready_dark_sides.remove_at(
			numbered_index
		)
		changed = true

	if quick_hand_index == selected_hand_index:
		quick_hand_index = -1
		quick_dark_side = false
		changed = true

	if changed:
		feedback_label.text = "Spell unassigned."

	_render_cards()
	_update_controls()


func _clear_preparation() -> void:
	ready_hand_indices.clear()
	ready_dark_sides.clear()
	quick_hand_index = -1
	quick_dark_side = false
	selected_hand_index = -1
	selected_dark = false
	feedback_label.text = "Preparation cleared."

	_render_cards()
	_update_controls()


func _confirm_preparation() -> void:
	var total_prepared: int = (
		ready_hand_indices.size()
		+ (
			1
			if quick_hand_index != -1
			else 0
		)
	)

	var min_spells: int = int(
		current_request.get(
			"min_spells",
			2
		)
	)

	var max_spells: int = int(
		current_request.get(
			"max_spells",
			4
		)
	)

	if total_prepared < min_spells \
	or total_prepared > max_spells:
		feedback_label.text = (
			"Prepare between "
			+ str(min_spells)
			+ " and "
			+ str(max_spells)
			+ " Spells."
		)
		_update_controls()
		return

	var payload: Dictionary = {
		"ready_hand_indices":
			ready_hand_indices.duplicate(),
		"ready_dark_sides":
			ready_dark_sides.duplicate(),
		"quick_hand_index":
			quick_hand_index,
		"quick_dark_side":
			quick_dark_side
	}

	preparation_confirmed.emit(
		payload
	)


func _update_controls() -> void:
	confirm_button.visible = mode == MODE_PREPARATION and tabs.current_tab == 0
	if mode == MODE_STUDY:
		study_confirm_button.visible = tabs.current_tab == 0
		study_confirm_button.disabled = study_selection.size() != 2
		study_confirm_button.text = "Keep selected cards (%d/2)" % study_selection.size()
		confirmation_changed.emit(study_confirm_button)
		return
	if mode == MODE_QUEST_SELECTION:
		study_confirm_button.visible = tabs.current_tab == 1
		var valid_count: bool = quest_selection.size() >= quest_selection_min and quest_selection.size() <= quest_selection_max
		study_confirm_button.disabled = not valid_count
		study_confirm_button.text = "Confirm Quest selection (%d/%d)" % [quest_selection.size(), quest_selection_max]
		return
	study_confirm_button.hide()
	if mode != MODE_PREPARATION:
		return
	feedback_label.visible = not feedback_label.text.is_empty()

	var has_selection: bool = (
		selected_hand_index != -1
	)
	var single_effect: bool = has_selection and _single_effect_card(selected_hand_index)

	var selected_name: String = (
		_card_name_by_hand_index(
			selected_hand_index
		)
		if has_selection
		else "-"
	)

	selection_label.text = (
		"Selected: "
		+ selected_name
		+ (
			" — "
			+ ("Single effect" if single_effect else _side_name(selected_dark))
			if has_selection
			else ""
		)
	)

	light_button.disabled = not has_selection
	side_label.visible = not single_effect
	light_button.visible = not single_effect
	dark_button.visible = not single_effect
	dark_button.disabled = not has_selection or not _selected_dark_playable()
	dark_button.tooltip_text = "This face is a Transformation, obtained by casting the Light side." if has_selection and not _selected_dark_playable() else ""

	light_button.set_pressed_no_signal(
		has_selection
		and not selected_dark
	)
	dark_button.set_pressed_no_signal(
		has_selection
		and selected_dark
	)

	var max_numbered: int = int(
		current_request.get(
			"max_numbered_spells",
			3
		)
	)

	var existing_numbered: int = ready_hand_indices.find(
		selected_hand_index
	)

	if existing_numbered != -1:
		ready_button.text = (
			"Update "
			+ _roman_slot(
				existing_numbered
			)
		)
	else:
		var next_slot_index: int = ready_hand_indices.size()

		if next_slot_index < max_numbered:
			ready_button.text = (
				"Ready → "
				+ _roman_slot(
					next_slot_index
				)
			)
		else:
			ready_button.text = "Numbered full"

	ready_button.disabled = (
		not has_selection
		or (
			ready_hand_indices.size() >= max_numbered
			and existing_numbered == -1
		)
	)

	quick_button.disabled = (
		not has_selection
		or not bool(
			current_request.get(
				"quick_allowed",
				true
			)
		)
	)

	if quick_hand_index == selected_hand_index \
	and has_selection:
		quick_button.text = "Quick ✓"
	else:
		quick_button.text = "Set as Quick"

	unassign_button.disabled = (
		not has_selection
		or not _is_assigned(
			selected_hand_index
		)
	)

	slots_label.text = _slots_summary()

	var total_prepared: int = (
		ready_hand_indices.size()
		+ (
			1
			if quick_hand_index != -1
			else 0
		)
	)

	var min_spells: int = int(
		current_request.get(
			"min_spells",
			2
		)
	)
	var max_spells: int = int(
		current_request.get(
			"max_spells",
			4
		)
	)

	confirm_button.text = (
		"Confirm "
		+ str(total_prepared)
		+ "/"
		+ str(max_spells)
	)

	confirm_button.disabled = (
		total_prepared < min_spells
		or total_prepared > max_spells
	)
	confirmation_changed.emit(confirm_button)


func _slots_summary() -> String:
	var parts: Array[String] = []

	for i in range(3):
		var text_value: String = (
			_roman_slot(i)
			+ ": "
		)

		if i < ready_hand_indices.size():
			text_value += _card_name_by_hand_index(ready_hand_indices[i])
			if not _single_effect_card(ready_hand_indices[i]):
				text_value += " (D)" if ready_dark_sides[i] else " (L)"
		else:
			text_value += "—"

		parts.append(text_value)

	var quick_text := "Quick: "

	if quick_hand_index != -1:
		quick_text += _card_name_by_hand_index(quick_hand_index)
		if not _single_effect_card(quick_hand_index):
			quick_text += " (D)" if quick_dark_side else " (L)"
	else:
		quick_text += "—"

	parts.append(quick_text)

	return "   |   ".join(parts)


func _is_assigned(
	hand_index: int
) -> bool:
	return (
		ready_hand_indices.has(
			hand_index
		)
		or quick_hand_index == hand_index
	)


func _card_name_by_hand_index(
	hand_index: int
) -> String:
	for card_value in cards:
		if not card_value is Dictionary:
			continue

		var card: Dictionary = card_value

		if int(
			card.get(
				"hand_index",
				-1
			)
		) != hand_index:
			continue

		return str(
			card.get(
				"name",
				card.get(
					"id",
					"Spell"
				)
			)
		)

	return "Spell"


func _side_name(
	use_dark: bool
) -> String:
	if _single_effect_card(selected_hand_index):
		return "Single effect"
	return (
		"Dark"
		if use_dark
		else "Light"
	)


func _roman_slot(
	slot_index: int
) -> String:
	match slot_index:
		0:
			return "I"
		1:
			return "II"
		2:
			return "III"
		_:
			return str(slot_index + 1)


func _resolve_card_texture(
	card: Dictionary
) -> Texture2D:
	var spell_id: String = str(
		card.get(
			"id",
			""
		)
	)

	if spell_id == "":
		return null

	if texture_cache.has(spell_id):
		return texture_cache[
			spell_id
		]

	var school_id: String = str(
		card.get(
			"school_id",
			""
		)
	)

	var candidates: Array[String] = []
	candidates.append(VisualAssets.spell_texture_path(spell_id))

	for root in CARD_ART_ROOTS:
		if school_id != "":
			candidates.append(
				root.path_join(
					school_id
				).path_join(
					spell_id + ".png"
				)
			)

		candidates.append(
			root.path_join(
				spell_id + ".png"
			)
		)

	for path in candidates:
		if not ResourceLoader.exists(path):
			continue

		var texture = load(path)

		if texture is Texture2D:
			texture_cache[
				spell_id
			] = texture
			return texture

	var recursive_path: String = (
		_find_resource_file_recursive(
			"res://",
			spell_id + ".png",
			0
		)
	)

	if recursive_path != "" \
	and ResourceLoader.exists(recursive_path):
		var texture = load(
			recursive_path
		)

		if texture is Texture2D:
			texture_cache[
				spell_id
			] = texture
			return texture

	texture_cache[
		spell_id
	] = null

	return null


func _find_resource_file_recursive(
	directory_path: String,
	target_file_name: String,
	depth: int
) -> String:
	if depth > 7:
		return ""

	var dir := DirAccess.open(
		directory_path
	)

	if dir == null:
		return ""

	dir.list_dir_begin()

	var entry: String = dir.get_next()

	while entry != "":
		if entry == "." \
		or entry == "..":
			entry = dir.get_next()
			continue

		var full_path: String = (
			directory_path.path_join(
				entry
			)
		)

		if dir.current_is_dir():
			if entry != ".godot" \
			and entry != ".git":
				var found: String = (
					_find_resource_file_recursive(
						full_path,
						target_file_name,
						depth + 1
					)
				)

				if found != "":
					dir.list_dir_end()
					return found
		else:
			if entry.to_lower() \
			== target_file_name.to_lower():
				dir.list_dir_end()
				return full_path

		entry = dir.get_next()

	dir.list_dir_end()
	return ""
