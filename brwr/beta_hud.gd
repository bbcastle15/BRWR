class_name BetaHUD
extends CanvasLayer

const HandOverlayScript = preload("res://hand_overlay.gd")


const CardViewScene = preload("res://card_view.tscn")


var game = null
var current_request: Dictionary = {}
var current_player_index: int = -1

var overlay: Control
var panel: PanelContainer
var phase_label: Label
var player_label: Label
var state_label: Label
var prompt_label: Label
var content: VBoxContainer
var feedback_label: Label
var reserved_width: float = 340.0
var hand_button: Button
var hand_overlay = null

var generic_selection: Array = []
var school_draft: Array[String] = []

var prep_ready_hand_indices: Array[int] = []
var prep_ready_dark: Array[bool] = []
var prep_quick_hand_index: int = -1
var prep_quick_dark: bool = false
var prep_selected_hand_index: int = -1

var evocation_draft: Array = []

# The engine exposes atomic legal actions. The HUD groups them so the player
# chooses the Action first, then movement/target/timing in a second step.
var action_menu_mode: String = "root"
var action_menu_filter: Dictionary = {}


func setup(
	game_node,
	sidebar_width: float = 340.0
) -> void:
	game = game_node
	reserved_width = max(
		320.0,
		sidebar_width
	)

	_build_ui()

	if not game.player_input_requested.is_connected(
		_on_player_input_requested
	):
		game.player_input_requested.connect(
			_on_player_input_requested
		)

	if not game.player_input_resolved.is_connected(
		_on_player_input_resolved
	):
		game.player_input_resolved.connect(
			_on_player_input_resolved
		)

	if not game.phase_completed.is_connected(
		_on_phase_completed
	):
		game.phase_completed.connect(
			_on_phase_completed
		)

	if not game.game_over.is_connected(
		_on_game_over
	):
		game.game_over.connect(
			_on_game_over
		)

	_refresh_header()

	if game.waiting_for_player_input \
	and not game.pending_input.is_empty():
		call_deferred(
			"present_pending_request",
			game.pending_input.duplicate(true)
		)


func present_pending_request(
	request: Dictionary
) -> void:
	_on_player_input_requested(
		request
	)


func get_reserved_width() -> float:
	return reserved_width

func get_supported_input_types() -> Array[String]:
	return [
		"starting_mage_choice",
		"starting_school_choice",
		"starting_grimoire_choice",
		"effect_choice",
		"action_activation",
		"action_activation_step",
		"preparation",
		"study_choose_schools",
		"study_keep_cards",
		"study_optional_discard",
		"study_hand_limit",
		"trigger_decision",
		"evocation_phase_activations",
		"cleanup_active_spells",
		"black_rose_optional_quest_discard",
		"black_rose_active_quest_limit",
		"black_rose_completed_quest_limit"
	]


func supports_input_type(input_type: String) -> bool:
	return get_supported_input_types().has(input_type)


func _build_ui() -> void:
	overlay = Control.new()
	overlay.name = "BetaHUDRoot"
	overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	add_child(overlay)

	panel = PanelContainer.new()
	panel.name = "BetaPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -reserved_width
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)

	var top_row := HBoxContainer.new()
	root_box.add_child(top_row)

	var title := Label.new()
	title.text = "BRWR — BETA UI"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)

	var hide_button := Button.new()
	hide_button.text = "Hide"
	hide_button.pressed.connect(_toggle_panel)
	top_row.add_child(hide_button)

	phase_label = Label.new()
	phase_label.text = "Phase: -"
	phase_label.add_theme_font_size_override("font_size", 16)
	root_box.add_child(phase_label)

	player_label = Label.new()
	player_label.text = "Player: -"
	root_box.add_child(player_label)

	state_label = Label.new()
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(state_label)

	hand_button = Button.new()
	hand_button.text = "HAND"
	hand_button.custom_minimum_size = Vector2(0, 42)
	hand_button.pressed.connect(_open_hand_overlay)
	root_box.add_child(hand_button)

	root_box.add_child(HSeparator.new())

	prompt_label = Label.new()
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.add_theme_font_size_override("font_size", 15)
	root_box.add_child(prompt_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	root_box.add_child(scroll)

	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	root_box.add_child(HSeparator.new())

	feedback_label = Label.new()
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.text = "Waiting for game..."
	root_box.add_child(feedback_label)

	var footer := Label.new()
	footer.text = "H: hand   •   F10: show/hide beta panel"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.modulate = Color(0.75, 0.75, 0.75)
	root_box.add_child(footer)

	hand_overlay = HandOverlayScript.new()
	overlay.add_child(hand_overlay)
	hand_overlay.setup(game)
	hand_overlay.preparation_confirmed.connect(_on_hand_overlay_preparation_confirmed)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_F10:
		_toggle_panel()
	elif event.keycode == KEY_H:
		if hand_overlay != null and hand_overlay.visible:
			hand_overlay.close_overlay(false)
		else:
			_open_hand_overlay()


func _open_hand_overlay() -> void:
	if hand_overlay == null or game == null:
		return

	if str(current_request.get("type", "")) == "preparation":
		hand_overlay.open_preparation(current_request)
		return

	if current_player_index < 0 or current_player_index >= game.players.size():
		feedback_label.text = "No player Hand is currently available."
		return

	hand_overlay.open_browse(current_player_index)


func _on_hand_overlay_preparation_confirmed(payload: Dictionary) -> void:
	if str(current_request.get("type", "")) != "preparation":
		return
	_submit(payload)


func _toggle_panel() -> void:
	if panel != null:
		panel.visible = not panel.visible


func _on_phase_completed(_phase: String) -> void:
	_refresh_header()


func _on_game_over(winner_data: Dictionary) -> void:
	_refresh_header()
	feedback_label.text = (
		"GAME OVER\n"
		+ JSON.stringify(winner_data)
	)


func _on_player_input_resolved(
	_request: Dictionary
) -> void:
	if hand_overlay != null:
		hand_overlay.close_overlay(true)

	_refresh_header()


func _on_player_input_requested(
	request: Dictionary
) -> void:
	if hand_overlay != null:
		hand_overlay.close_overlay(true)

	current_request = request.duplicate(true)
	current_player_index = int(
		current_request.get(
			"player_index",
			-1
		)
	)

	generic_selection.clear()
	school_draft.clear()
	prep_ready_hand_indices.clear()
	prep_ready_dark.clear()
	prep_quick_hand_index = -1
	prep_quick_dark = false
	prep_selected_hand_index = -1
	evocation_draft.clear()

	action_menu_mode = "root"
	action_menu_filter.clear()

	feedback_label.text = ""
	_render_current_request()


func _refresh_header() -> void:
	if game == null:
		return

	phase_label.text = (
		"Round "
		+ str(game.current_round)
		+ "  •  Moon "
		+ str(game.current_moon)
		+ "  •  "
		+ str(game.current_phase).capitalize()
	)

	if current_player_index >= 0 \
	and current_player_index < game.players.size():
		player_label.text = (
			"Decision: Player "
			+ str(current_player_index + 1)
			+ " — "
			+ game.players[current_player_index].player_name
		)
	else:
		player_label.text = "Decision: -"

	var viewer: int = (
		current_player_index
		if current_player_index >= 0
		else -1
	)

	var state: Dictionary = game.get_beta_game_state(
		viewer
	)

	var summary: Array[String] = []

	summary.append(
		"Black Rose Power: "
		+ str(state.get("black_rose_power", 0))
	)

	var crown_owner: int = int(
		state.get(
			"crown_owner_id",
			-1
		)
	)

	if crown_owner >= 0:
		summary.append(
			"Crown: P"
			+ str(crown_owner + 1)
		)

	if viewer >= 0:
		var player_states: Array = state.get(
			"players",
			[]
		)

		if viewer < player_states.size():
			var player_data: Dictionary = (
				player_states[viewer]
			)

			var mage_data: Dictionary = player_data.get(
				"mage",
				{}
			)

			summary.append(
				"HP "
				+ str(
					mage_data.get(
						"remaining_health",
						0
					)
				)
				+ "/"
				+ str(
					mage_data.get(
						"health",
						0
					)
				)
			)

			summary.append(
				"Power "
				+ str(
					player_data.get(
						"power",
						0
					)
				)
			)

			summary.append(
				"Cubes "
				+ str(
					player_data.get(
						"available_cubes",
						0
					)
				)
			)

			summary.append(
				"Hand "
				+ str(
					player_data.get(
						"hand_count",
						0
					)
				)
			)

	state_label.text = "  |  ".join(summary)

	if hand_button != null:
		var hand_count: int = 0
		if viewer >= 0:
			var ps: Array = state.get("players", [])
			if viewer < ps.size():
				hand_count = int(ps[viewer].get("hand_count", 0))
		hand_button.text = "HAND (" + str(hand_count) + ")"
		hand_button.disabled = viewer < 0 or hand_count <= 0


func _clear_content() -> void:
	for child in content.get_children():
		child.queue_free()


func _add_section(title_text: String) -> void:
	var label := Label.new()
	label.text = title_text
	label.add_theme_font_size_override(
		"font_size",
		16
	)
	content.add_child(label)


func _add_info(text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)


func _add_button(
	text_value: String,
	callback: Callable,
	disabled: bool = false
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.disabled = disabled
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	content.add_child(button)
	return button


func _add_small_button(
	parent: Control,
	text_value: String,
	callback: Callable,
	disabled: bool = false
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.disabled = disabled
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _render_current_request() -> void:
	_clear_content()
	_refresh_header()

	var input_type: String = str(
		current_request.get(
			"type",
			""
		)
	)

	prompt_label.text = _request_title(input_type)

	match input_type:
		"starting_mage_choice":
			_render_starting_mage_choice()

		"starting_school_choice":
			_render_starting_school_choice()

		"starting_grimoire_choice":
			_render_starting_grimoire_choice()

		"action_activation_step":
			_render_action_step()

		"effect_choice":
			_render_effect_choice()

		"study_choose_schools":
			_render_study_schools()

		"study_keep_cards":
			_render_index_multiselect(
				"Choose exactly 2 cards",
				current_request.get("cards", []),
				"draw_index",
				2,
				Callable(
					self,
					"_submit_study_keep"
				)
			)

		"study_optional_discard":
			_render_optional_hand_discard()

		"study_hand_limit":
			_render_index_multiselect(
				"Discard exactly "
				+ str(
					current_request.get(
						"discard_count",
						0
					)
				)
				+ " cards",
				current_request.get("hand", []),
				"hand_index",
				int(
					current_request.get(
						"discard_count",
						0
					)
				),
				Callable(
					self,
					"_submit_study_hand_limit"
				)
			)

		"preparation":
			_render_preparation()

		"trigger_decision":
			_render_trigger_decision()

		"evocation_phase_activations":
			_render_evocation_phase()

		"cleanup_active_spells":
			_render_cleanup_active_spells()

		"black_rose_optional_quest_discard":
			_render_optional_quest_discard()

		"black_rose_active_quest_limit":
			_render_index_multiselect(
				"Discard Active Quests",
				current_request.get("quests", []),
				"quest_index",
				int(
					current_request.get(
						"discard_count",
						0
					)
				),
				Callable(
					self,
					"_submit_active_quest_limit"
				)
			)

		"black_rose_completed_quest_limit":
			_render_index_multiselect(
				"Discard Completed Quests",
				current_request.get("quests", []),
				"quest_index",
				int(
					current_request.get(
						"discard_count",
						0
					)
				),
				Callable(
					self,
					"_submit_completed_quest_limit"
				)
			)

		"action_activation":
			_add_info(
				"Legacy batch Action request. "
				+ "The normal game loop uses action_activation_step."
			)

		_:
			_add_info(
				"Unsupported beta request:\n"
				+ JSON.stringify(
					current_request,
					"  "
				)
			)


func _request_title(input_type: String) -> String:
	match input_type:
		"starting_mage_choice":
			return "Setup — choose your Mage"
		"starting_school_choice":
			return "Setup — choose your School of Magic"
		"starting_grimoire_choice":
			return "Setup — choose your Starting Grimoire"
		"action_activation_step":
			return "Choose your next Action"
		"effect_choice":
			return str(
				current_request.get(
					"prompt",
					"Choose an Effect option"
				)
			)
		"study_choose_schools":
			return "Study — choose 4 Library draws"
		"study_keep_cards":
			return "Study — keep 2 cards"
		"study_optional_discard":
			return "Study — optional discard"
		"study_hand_limit":
			return "Study — Hand limit"
		"preparation":
			return "Preparation — ready your Spells"
		"trigger_decision":
			return "Triggered Trap / Protection"
		"evocation_phase_activations":
			return "Evocation Phase"
		"cleanup_active_spells":
			return "Clean-up — Active Spells"
		"black_rose_optional_quest_discard":
			return "Black Rose — optional Quest discard"
		"black_rose_active_quest_limit":
			return "Black Rose — Active Quest limit"
		"black_rose_completed_quest_limit":
			return "Black Rose — Completed Quest limit"
		_:
			return input_type


func _submit(payload: Dictionary) -> void:
	if game == null:
		return

	var accepted: bool = game.submit_beta_input(
		current_player_index,
		payload
	)

	if not accepted:
		feedback_label.text = (
			"Choice rejected by rules engine. "
			+ "The current request is still active."
		)
	else:
		feedback_label.text = "Choice accepted."


# =============================================================================
# STARTING SETUP
# =============================================================================


func _render_starting_mage_choice() -> void:
	_add_info(
		"All Mages are chosen first, in play order. "
		+ "A Mage already chosen by another player is unavailable."
	)

	for mage_value in current_request.get(
		"available_mages",
		[]
	):
		if not mage_value is Dictionary:
			continue

		var mage: Dictionary = mage_value
		var mage_id: String = str(
			mage.get(
				"id",
				""
			)
		)

		var button_text: String = (
			str(
				mage.get(
					"name",
					mage_id.capitalize()
				)
			)
			+ "\nHP "
			+ str(mage.get("health", 0))
			+ "  •  Hand "
			+ str(mage.get("hand_limit", 0))
			+ "  •  STR "
			+ str(mage.get("strength", 0))
			+ "  •  SPD "
			+ str(mage.get("speed", 0))
			+ "\nPersonal Spell: "
			+ str(
				mage.get(
					"personal_spell_name",
					mage.get(
						"personal_spell_id",
						""
					)
				)
			)
		)

		var button := _add_button(
			button_text,
			Callable(
				self,
				"_submit_starting_mage"
			).bind(mage_id)
		)

		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _submit_starting_mage(
	mage_id: String
) -> void:
	_submit({
		"mage_id": mage_id
	})

func _render_starting_school_choice() -> void:
	_add_info(
		"Choose one School. A School already chosen by another Mage "
		+ "is no longer available."
	)

	for school_value in current_request.get(
		"available_schools",
		[]
	):
		if not school_value is Dictionary:
			continue

		var school: Dictionary = school_value
		var school_id: String = str(
			school.get("id", "")
		)

		_add_button(
			str(
				school.get(
					"name",
					school_id.capitalize()
				)
			),
			Callable(
				self,
				"_submit_starting_school"
			).bind(school_id)
		)


func _submit_starting_school(
	school_id: String
) -> void:
	_submit({
		"school_id": school_id
	})


func _render_starting_grimoire_choice() -> void:
	_add_info(
		"School: "
		+ str(
			current_request.get(
				"school_name",
				current_request.get(
					"school_id",
					""
				)
			)
		)
		+ "\nChoose one specialization. Its six School Spells become "
		+ "your starting Grimoire together with one Personal Spell."
	)

	for option_value in current_request.get(
		"options",
		[]
	):
		if not option_value is Dictionary:
			continue

		var option: Dictionary = option_value
		var spell_names: Array[String] = []

		for spell_value in option.get(
			"spells",
			[]
		):
			if not spell_value is Dictionary:
				continue

			spell_names.append(
				str(
					spell_value.get(
						"name",
						spell_value.get(
							"id",
							"Spell"
						)
					)
				)
			)

		var option_name: String = str(
			option.get(
				"name",
				option.get(
					"id",
					"Starting Grimoire"
				)
			)
		)

		_add_section(option_name)
		_add_info(
			"• " + "\n• ".join(spell_names)
		)

		_add_button(
			"Choose " + option_name,
			Callable(
				self,
				"_submit_starting_grimoire"
			).bind(
				str(
					option.get(
						"id",
						""
					)
				)
			)
		)



func _submit_starting_grimoire(
	grimoire_id: String
) -> void:
	_submit({
		"grimoire_id": grimoire_id
	})

# =============================================================================
# ACTION PHASE
# =============================================================================

func _room_display_name(room_id: String) -> String:
	if room_id == "":
		return "Stay"

	if game == null:
		return room_id

	var room = game.get_room_by_id(room_id)

	if room == null:
		return room_id

	return str(room.room_name)


func _action_path_key(path: Array) -> String:
	var parts: Array[String] = []

	for room_value in path:
		parts.append(str(room_value))

	return "|".join(parts)


func _action_path_label(path: Array) -> String:
	if path.is_empty():
		if current_player_index >= 0 \
		and current_player_index < game.players.size():
			return (
				"Stay in "
				+ _room_display_name(
					game.players[
						current_player_index
					].mage.room_id
				)
			)

		return "Stay"

	var names: Array[String] = []

	for room_value in path:
		names.append(
			_room_display_name(
				str(room_value)
			)
		)

	return " → ".join(names)


func _action_options() -> Array:
	return current_request.get(
		"options",
		[]
	)


func _action_options_of_type(
	action_type: String
) -> Array:
	var result: Array = []

	for option_value in _action_options():
		if not option_value is Dictionary:
			continue

		var option: Dictionary = option_value
		var action: Dictionary = option.get(
			"action",
			{}
		)

		if str(action.get("type", "")) == action_type:
			result.append(option)

	return result


func get_action_root_entries_for_request(
	request: Dictionary
) -> Array:
	var result: Array = []
	var seen: Dictionary = {}

	for option_value in request.get("options", []):
		if not option_value is Dictionary:
			continue

		var option: Dictionary = option_value
		var kind: String = str(
			option.get(
				"kind",
				""
			)
		)

		if kind == "quest" or kind == "finish":
			result.append({
				"key": str(option.get("token", "")),
				"mode": "direct",
				"option": option.duplicate(true),
				"label": str(option.get("label", ""))
			})
			continue

		var action: Dictionary = option.get(
			"action",
			{}
		)
		var action_type: String = str(
			action.get(
				"type",
				""
			)
		)

		var key: String = action_type
		var label: String = str(
			option.get(
				"label",
				action_type.capitalize()
			)
		)
		var mode: String = action_type

		match action_type:
			"explore":
				key = "explore"
				label = "Explore"
				mode = "explore_paths"

			"fight":
				key = "fight"
				label = "Fight"
				mode = "fight_variants"

			"momentum":
				key = (
					"momentum:"
					+ str(
						action.get(
							"ready_index",
							-1
						)
					)
					+ ":"
					+ str(
						action.get(
							"use_quick",
							false
						)
					)
				)

				var spell_name: String = str(
					option.get(
						"descriptor",
						{}
					).get(
						"spell",
						{}
					).get(
						"name",
						""
					)
				)

				if spell_name == "":
					spell_name = str(
						option.get(
							"label",
							"Momentum"
						)
					).trim_prefix(
						"Momentum: discard "
					)

				label = "Momentum — discard " + spell_name
				mode = "momentum_destinations"

			"command":
				key = (
					"command:"
					+ str(
						action.get(
							"evocation_index",
							-1
						)
					)
				)

				var evocation_name: String = str(
					option.get(
						"descriptor",
						{}
					).get(
						"evocation",
						{}
					).get(
						"name",
						"Evocation"
					)
				)

				label = "Command " + evocation_name
				mode = "command_plans"

			"spell", "quick":
				key = str(option.get("token", ""))
				mode = "direct"

			_:
				key = str(option.get("token", ""))
				mode = "direct"

		if seen.has(key):
			continue

		seen[key] = true

		result.append({
			"key": key,
			"mode": mode,
			"option": option.duplicate(true),
			"label": label
		})

	return result


func _set_action_menu(
	mode: String,
	filter_data: Dictionary = {}
) -> void:
	action_menu_mode = mode
	action_menu_filter = filter_data.duplicate(true)
	_render_current_request()


func _back_to_action_root() -> void:
	action_menu_mode = "root"
	action_menu_filter.clear()
	_render_current_request()


func _render_action_step() -> void:
	_add_info(
		"Actions used: "
		+ str(
			current_request.get(
				"actions_used",
				0
			)
		)
		+ "/2"
	)

	match action_menu_mode:
		"root":
			_render_action_root()
		"explore_paths":
			_render_explore_paths()
		"explore_variants":
			_render_explore_variants()
		"momentum_destinations":
			_render_momentum_destinations()
		"fight_variants":
			_render_action_variant_list("fight")
		"command_plans":
			_render_command_paths()
		"command_variants":
			_render_command_variants()
		_:
			action_menu_mode = "root"
			action_menu_filter.clear()
			_render_action_root()


func _render_action_root() -> void:
	for entry_value in get_action_root_entries_for_request(
		current_request
	):
		var entry: Dictionary = entry_value
		var mode: String = str(
			entry.get(
				"mode",
				"direct"
			)
		)
		var option: Dictionary = entry.get(
			"option",
			{}
		)

		if mode == "direct":
			var prefix: String = ""

			match str(option.get("kind", "")):
				"quest":
					prefix = "[Quest] "
				"finish":
					prefix = "[End] "

			_add_button(
				prefix
				+ str(
					entry.get(
						"label",
						"Action"
					)
				),
				Callable(
					self,
					"_submit_action_token"
				).bind(
					str(
						option.get(
							"token",
							""
						)
					)
				)
			)

			continue

		var filter_data: Dictionary = {}

		if mode == "momentum_destinations":
			var action: Dictionary = option.get(
				"action",
				{}
			)

			filter_data = {
				"ready_index": int(
					action.get(
						"ready_index",
						-1
					)
				),
				"use_quick": bool(
					action.get(
						"use_quick",
						false
					)
				)
			}

		elif mode == "command_plans":
			filter_data = {
				"evocation_index": int(
					option.get(
						"action",
						{}
					).get(
						"evocation_index",
						-1
					)
				)
			}

		_add_button(
			str(
				entry.get(
					"label",
					"Action"
				)
			),
			Callable(
				self,
				"_set_action_menu"
			).bind(
				mode,
				filter_data
			)
		)


func _render_explore_paths() -> void:
	_add_section("Explore — choose movement")

	var seen_paths: Dictionary = {}

	for option_value in _action_options_of_type(
		"explore"
	):
		var option: Dictionary = option_value
		var action: Dictionary = option.get(
			"action",
			{}
		)
		var path: Array = action.get(
			"destination_room_ids",
			[]
		)
		var path_key: String = _action_path_key(path)

		if seen_paths.has(path_key):
			continue

		seen_paths[path_key] = true

		_add_button(
			_action_path_label(path),
			Callable(
				self,
				"_set_action_menu"
			).bind(
				"explore_variants",
				{
					"path_key": path_key
				}
			)
		)

	_add_button(
		"← Back",
		Callable(
			self,
			"_back_to_action_root"
		)
	)


func _render_explore_variants() -> void:
	var wanted_path: String = str(
		action_menu_filter.get(
			"path_key",
			""
		)
	)

	var matching: Array = []

	for option_value in _action_options_of_type(
		"explore"
	):
		var option: Dictionary = option_value
		var action: Dictionary = option.get(
			"action",
			{}
		)
		var path: Array = action.get(
			"destination_room_ids",
			[]
		)

		if _action_path_key(path) == wanted_path:
			matching.append(option)

	if matching.is_empty():
		_back_to_action_root()
		return

	var first_action: Dictionary = matching[0].get(
		"action",
		{}
	)

	_add_section(
		"Explore: "
		+ _action_path_label(
			first_action.get(
				"destination_room_ids",
				[]
			)
		)
	)

	for option_value in matching:
		var option: Dictionary = option_value
		var action: Dictionary = option.get(
			"action",
			{}
		)

		var timing_label: String = "Move only"

		if bool(
			action.get(
				"activate_room_before_movement",
				false
			)
		):
			timing_label = "Activate Room, then move"

		elif bool(
			action.get(
				"activate_room_after_movement",
				false
			)
		):
			timing_label = "Move, then activate Room"

		_add_button(
			timing_label,
			Callable(
				self,
				"_submit_action_token"
			).bind(
				str(
					option.get(
						"token",
						""
					)
				)
			)
		)

	_add_button(
		"← Change movement",
		Callable(
			self,
			"_set_action_menu"
		).bind(
			"explore_paths",
			{}
		)
	)


func _render_momentum_destinations() -> void:
	_add_section("Momentum — choose Move 1")

	var ready_index: int = int(
		action_menu_filter.get(
			"ready_index",
			-1
		)
	)
	var use_quick: bool = bool(
		action_menu_filter.get(
			"use_quick",
			false
		)
	)

	for option_value in _action_options_of_type(
		"momentum"
	):
		var option: Dictionary = option_value
		var action: Dictionary = option.get(
			"action",
			{}
		)

		if int(
			action.get(
				"ready_index",
				-1
			)
		) != ready_index \
		or bool(
			action.get(
				"use_quick",
				false
			)
		) != use_quick:
			continue

		var destination: String = str(
			action.get(
				"destination_room_id",
				""
			)
		)

		var label_text: String = (
			"Do not move"
			if destination == ""
			else "Move 1 → " + _room_display_name(destination)
		)

		_add_button(
			label_text,
			Callable(
				self,
				"_submit_action_token"
			).bind(
				str(
					option.get(
						"token",
						""
					)
				)
			)
		)

	_add_button(
		"← Back",
		Callable(
			self,
			"_back_to_action_root"
		)
	)


func _render_action_variant_list(
	action_type: String
) -> void:
	_add_section(action_type.capitalize())

	for option_value in _action_options_of_type(
		action_type
	):
		var option: Dictionary = option_value

		_add_button(
			str(
				option.get(
					"label",
					action_type.capitalize()
				)
			),
			Callable(
				self,
				"_submit_action_token"
			).bind(
				str(
					option.get(
						"token",
						""
					)
				)
			)
		)

	_add_button(
		"← Back",
		Callable(
			self,
			"_back_to_action_root"
		)
	)


func _command_option_path(
	option: Dictionary
) -> Array:
	var action: Dictionary = option.get(
		"action",
		{}
	)
	var context: Dictionary = action.get(
		"context",
		{}
	)

	return context.get(
		"evocation_move_room_ids",
		[]
	)


func _render_command_paths() -> void:
	_add_section("Command — choose movement")

	var evocation_index: int = int(
		action_menu_filter.get(
			"evocation_index",
			-1
		)
	)

	var seen_paths: Dictionary = {}

	for option_value in _action_options_of_type(
		"command"
	):
		var option: Dictionary = option_value
		var action: Dictionary = option.get(
			"action",
			{}
		)

		if int(
			action.get(
				"evocation_index",
				-1
			)
		) != evocation_index:
			continue

		var path: Array = _command_option_path(
			option
		)
		var path_key: String = _action_path_key(
			path
		)

		if seen_paths.has(path_key):
			continue

		seen_paths[path_key] = true

		var label_text: String = (
			"No movement"
			if path.is_empty()
			else _action_path_label(path)
		)

		_add_button(
			label_text,
			Callable(
				self,
				"_set_action_menu"
			).bind(
				"command_variants",
				{
					"evocation_index": evocation_index,
					"path_key": path_key
				}
			)
		)

	_add_button(
		"← Back",
		Callable(
			self,
			"_back_to_action_root"
		)
	)


func _command_variant_label(
	option: Dictionary
) -> String:
	var action: Dictionary = option.get(
		"action",
		{}
	)
	var context: Dictionary = action.get(
		"context",
		{}
	)

	var timing: String = str(
		context.get(
			"evocation_attack_timing",
			"none"
		)
	)

	if timing == "none":
		return "No attack"

	var descriptor: Dictionary = option.get(
		"descriptor",
		{}
	)
	var plan: Dictionary = descriptor.get(
		"activation_plan",
		{}
	)
	var target: Dictionary = plan.get(
		"target",
		{}
	)

	var target_name: String = str(
		target.get(
			"name",
			"Model"
		)
	)

	if timing == "before":
		return "Attack " + target_name + " before movement"

	return "Attack " + target_name + " after movement"


func _render_command_variants() -> void:
	_add_section("Command — choose attack")

	var evocation_index: int = int(
		action_menu_filter.get(
			"evocation_index",
			-1
		)
	)
	var wanted_path: String = str(
		action_menu_filter.get(
			"path_key",
			""
		)
	)

	var seen_variants: Dictionary = {}

	for option_value in _action_options_of_type(
		"command"
	):
		var option: Dictionary = option_value
		var action: Dictionary = option.get(
			"action",
			{}
		)

		if int(
			action.get(
				"evocation_index",
				-1
			)
		) != evocation_index:
			continue

		var path: Array = _command_option_path(
			option
		)

		if _action_path_key(path) != wanted_path:
			continue

		var label_text: String = _command_variant_label(
			option
		)

		if seen_variants.has(label_text):
			continue

		seen_variants[label_text] = true

		_add_button(
			label_text,
			Callable(
				self,
				"_submit_action_token"
			).bind(
				str(
					option.get(
						"token",
						""
					)
				)
			)
		)

	_add_button(
		"← Change movement",
		Callable(
			self,
			"_set_action_menu"
		).bind(
			"command_plans",
			{
				"evocation_index": evocation_index
			}
		)
	)



func _submit_action_token(token: String) -> void:
	_submit({
		"token": token
	})


# =============================================================================
# GENERIC EFFECT CHOICE
# =============================================================================

func _render_effect_choice() -> void:
	var min_select: int = int(
		current_request.get(
			"min_select",
			1
		)
	)

	var max_select: int = int(
		current_request.get(
			"max_select",
			1
		)
	)

	_add_info(
		"Choose "
		+ str(min_select)
		+ (
			""
			if min_select == max_select
			else "–" + str(max_select)
		)
	)

	var options: Array = current_request.get(
		"options",
		[]
	)

	if max_select <= 1:
		if min_select == 0:
			_add_button(
				"Skip",
				Callable(
					self,
					"_submit_effect_single"
				).bind("")
			)

		for option_value in options:
			var option: Dictionary = option_value
			var token: String = str(
				option.get(
					"token",
					""
				)
			)

			_add_button(
				_option_label(option),
				Callable(
					self,
					"_submit_effect_single"
				).bind(token)
			)

		return

	for option_value in options:
		var option: Dictionary = option_value
		var token: String = str(
			option.get(
				"token",
				""
			)
		)

		var selected: bool = generic_selection.has(
			token
		)

		_add_button(
			("✓ " if selected else "")
			+ _option_label(option),
			Callable(
				self,
				"_toggle_generic_value"
			).bind(token)
		)

	_add_button(
		"Confirm selection",
		Callable(
			self,
			"_submit_effect_multi"
		),
		generic_selection.size() < min_select \
		or generic_selection.size() > max_select
	)


func _submit_effect_single(token: String) -> void:
	if token == "":
		_submit({
			"selection": []
		})
	else:
		_submit({
			"selection": token
		})


func _submit_effect_multi() -> void:
	_submit({
		"selection": generic_selection.duplicate()
	})


func _option_label(option: Dictionary) -> String:
	for key in [
		"label",
		"name",
		"spell_name",
		"room_name",
		"id",
		"token"
	]:
		if option.has(key):
			return str(option[key])

	return JSON.stringify(option)


func _toggle_generic_value(value) -> void:
	if generic_selection.has(value):
		generic_selection.erase(value)
	else:
		generic_selection.append(value)

	_render_current_request()


# =============================================================================
# STUDY
# =============================================================================

func _render_study_schools() -> void:
	_add_info(
		"Library draws: "
		+ str(school_draft.size())
		+ "/4\n"
		+ (
			" → ".join(school_draft)
			if not school_draft.is_empty()
			else "Choose the School for each of the four draws."
		)
	)

	for school_value in current_request.get(
		"active_school_ids",
		[]
	):
		var school_id: String = str(
			school_value
		)

		_add_button(
			"Draw from "
			+ school_id.capitalize(),
			Callable(
				self,
				"_add_study_school"
			).bind(school_id),
			school_draft.size() >= 4
		)

	var controls := HBoxContainer.new()
	content.add_child(controls)

	_add_small_button(
		controls,
		"Undo",
		Callable(
			self,
			"_undo_study_school"
		),
		school_draft.is_empty()
	)

	_add_small_button(
		controls,
		"Clear",
		Callable(
			self,
			"_clear_study_schools"
		),
		school_draft.is_empty()
	)

	_add_small_button(
		controls,
		"Confirm",
		Callable(
			self,
			"_submit_study_schools"
		),
		school_draft.size() != 4
	)



func _add_study_school(school_id: String) -> void:
	if school_draft.size() >= 4:
		return

	school_draft.append(school_id)
	_render_current_request()


func _undo_study_school() -> void:
	if not school_draft.is_empty():
		school_draft.pop_back()

	_render_current_request()


func _clear_study_schools() -> void:
	school_draft.clear()
	_render_current_request()


func _submit_study_schools() -> void:
	_submit({
		"school_ids": school_draft.duplicate()
	})


func _submit_study_keep() -> void:
	_submit({
		"keep_indices": generic_selection.duplicate()
	})


func _render_optional_hand_discard() -> void:
	_add_button(
		"Keep current Hand",
		Callable(
			self,
			"_submit_optional_hand_discard"
		).bind(-1)
	)

	for card_value in current_request.get(
		"hand",
		[]
	):
		var card: Dictionary = card_value

		_add_button(
			"Discard "
			+ str(
				card.get(
					"name",
					card.get("id", "Card")
				)
			),
			Callable(
				self,
				"_submit_optional_hand_discard"
			).bind(
				int(
					card.get(
						"hand_index",
						-1
					)
				)
			)
		)


func _submit_optional_hand_discard(
	hand_index: int
) -> void:
	_submit({
		"hand_index": hand_index
	})


func _submit_study_hand_limit() -> void:
	_submit({
		"hand_indices": generic_selection.duplicate()
	})


# =============================================================================
# GENERIC INDEX MULTISELECT
# =============================================================================

func _render_index_multiselect(
	title_text: String,
	items: Array,
	index_key: String,
	required_count: int,
	submit_callback: Callable
) -> void:
	_add_section(title_text)

	_add_info(
		"Selected "
		+ str(generic_selection.size())
		+ "/"
		+ str(required_count)
	)

	for item_value in items:
		var item: Dictionary = item_value
		var index_value = item.get(
			index_key,
			-1
		)

		var selected: bool = generic_selection.has(
			index_value
		)

		var label_text: String = str(
			item.get(
				"name",
				item.get(
					"id",
					str(index_value)
				)
			)
		)

		_add_button(
			("✓ " if selected else "")
			+ label_text,
			Callable(
				self,
				"_toggle_generic_value"
			).bind(index_value)
		)

	_add_button(
		"Confirm",
		submit_callback,
		generic_selection.size() != required_count
	)


# =============================================================================
# PREPARATION
# =============================================================================

func _prep_hand_card_label(hand_index: int) -> String:
	for card_value in current_request.get("hand", []):
		var card: Dictionary = card_value
		if int(card.get("hand_index", -1)) != hand_index:
			continue

		return str(card.get("name", card.get("id", "Spell")))

	return "Hand #" + str(hand_index + 1)


func _render_preparation() -> void:
	_add_info(
		"Your Hand is open over the Lodge. "
		+ "Choose Light/Dark and assign 2–4 Spells. "
		+ "The overlay closes automatically after Confirm."
	)

	if hand_overlay != null:
		hand_overlay.open_preparation(current_request)


func _prep_assign(
	hand_index: int,
	dark: bool,
	as_quick: bool
) -> void:
	_prep_remove_internal(hand_index)

	if as_quick:
		prep_quick_hand_index = hand_index
		prep_quick_dark = dark
	else:
		if prep_ready_hand_indices.size() >= 3:
			feedback_label.text = (
				"All three numbered Spell Slots are already filled."
			)
			_render_current_request()
			return

		prep_ready_hand_indices.append(hand_index)
		prep_ready_dark.append(dark)

	_render_current_request()


func _prep_remove_internal(hand_index: int) -> void:
	var ready_index: int = prep_ready_hand_indices.find(hand_index)

	if ready_index != -1:
		prep_ready_hand_indices.remove_at(ready_index)
		prep_ready_dark.remove_at(ready_index)

	if prep_quick_hand_index == hand_index:
		prep_quick_hand_index = -1
		prep_quick_dark = false


func _prep_remove(hand_index: int) -> void:
	_prep_remove_internal(hand_index)
	_render_current_request()


func _prep_clear() -> void:
	prep_ready_hand_indices.clear()
	prep_ready_dark.clear()
	prep_quick_hand_index = -1
	prep_quick_dark = false
	prep_selected_hand_index = -1
	_render_current_request()


func _submit_preparation() -> void:
	_submit({
		"ready_hand_indices": prep_ready_hand_indices.duplicate(),
		"ready_dark_sides": prep_ready_dark.duplicate(),
		"quick_hand_index": prep_quick_hand_index,
		"quick_dark_side": prep_quick_dark
	})


# =============================================================================
# TRIGGERS
# =============================================================================

func _render_trigger_decision() -> void:
	_add_button(
		"Pass",
		Callable(
			self,
			"_submit_trigger"
		).bind(-1)
	)

	for option_value in current_request.get(
		"options",
		[]
	):
		var option: Dictionary = option_value

		_add_button(
			"Reveal "
			+ str(
				option.get(
					"spell_name",
					"Spell"
				)
			)
			+ " ["
			+ str(
				option.get(
					"spell_type",
					""
				)
			)
			+ "]",
			Callable(
				self,
				"_submit_trigger"
			).bind(
				int(
					option.get(
						"queue_index",
						-1
					)
				)
			)
		)


func _submit_trigger(queue_index: int) -> void:
	_submit({
		"queue_index": queue_index
	})


# =============================================================================
# EVOCATION PHASE
# =============================================================================

func _evocation_phase_plan_label(
	plan: Dictionary
) -> String:
	var path: Array = plan.get(
		"path",
		[]
	)
	var attack_timing: String = str(
		plan.get(
			"attack_timing",
			"none"
		)
	)
	var target: Dictionary = plan.get(
		"target",
		{}
	)

	var movement_label: String = (
		"No movement"
		if path.is_empty()
		else _action_path_label(path)
	)

	if attack_timing == "none":
		return movement_label + " — no attack"

	var target_name: String = str(
		target.get(
			"name",
			"Model"
		)
	)

	if attack_timing == "before":
		return (
			"Attack "
			+ target_name
			+ " → "
			+ movement_label
		)

	return (
		movement_label
		+ " → Attack "
		+ target_name
	)


func _render_evocation_phase() -> void:
	var required_count: int = int(
		current_request.get(
			"required_count",
			0
		)
	)

	_add_info(
		"Chosen activations: "
		+ str(evocation_draft.size())
		+ "/"
		+ str(required_count)
		+ "\nOrder of selection = activation order."
	)

	if not evocation_draft.is_empty():
		for i in range(evocation_draft.size()):
			var choice: Dictionary = evocation_draft[i]
			_add_info(
				str(i + 1)
				+ ". Evocation index "
				+ str(
					choice.get(
						"evocation_index",
						-1
					)
				)
			)

	for evocation_value in current_request.get(
		"evocations",
		[]
	):
		var evocation: Dictionary = evocation_value
		var evocation_index: int = int(
			evocation.get(
				"evocation_index",
				-1
			)
		)

		if _evocation_draft_has_index(
			evocation_index
		):
			continue

		_add_section(
			str(
				evocation.get(
					"name",
					"Evocation"
				)
			)
			+ " — choose plan"
		)

		var seen_plan_labels: Dictionary = {}

		for plan_value in evocation.get(
			"activation_plans",
			[]
		):
			var plan: Dictionary = plan_value
			var plan_label: String = _evocation_phase_plan_label(
				plan
			)

			if seen_plan_labels.has(plan_label):
				continue

			seen_plan_labels[plan_label] = true

			_add_button(
				plan_label,
				Callable(
					self,
					"_choose_evocation_plan"
				).bind(
					evocation_index,
					plan.get(
						"context",
						{}
					).duplicate(true)
				)
			)

	if not evocation_draft.is_empty():
		_add_button(
			"Undo last activation",
			Callable(
				self,
				"_undo_evocation_choice"
			)
		)

	_add_button(
		"Confirm Evocation Phase",
		Callable(
			self,
			"_submit_evocation_phase"
		),
		evocation_draft.size() != required_count
	)


func _evocation_draft_has_index(
	evocation_index: int
) -> bool:
	for choice_value in evocation_draft:
		var choice: Dictionary = choice_value

		if int(
			choice.get(
				"evocation_index",
				-1
			)
		) == evocation_index:
			return true

	return false


func _choose_evocation_plan(
	evocation_index: int,
	context_value: Dictionary
) -> void:
	if _evocation_draft_has_index(
		evocation_index
	):
		return

	evocation_draft.append({
		"evocation_index": evocation_index,
		"context": context_value.duplicate(true)
	})

	_render_current_request()


func _undo_evocation_choice() -> void:
	if not evocation_draft.is_empty():
		evocation_draft.pop_back()

	_render_current_request()


func _submit_evocation_phase() -> void:
	_submit({
		"choices": evocation_draft.duplicate(true)
	})


# =============================================================================
# CLEAN-UP
# =============================================================================

func _render_cleanup_active_spells() -> void:
	_add_info(
		"Select Trap/Protection Spells to return to Hand. "
		+ "Unselected cards go to Memories."
	)

	for option_value in current_request.get(
		"active_spells",
		[]
	):
		var option: Dictionary = option_value
		var index_value: int = int(
			option.get(
				"active_index",
				-1
			)
		)

		var selected: bool = generic_selection.has(
			index_value
		)

		_add_button(
			("✓ " if selected else "")
			+ str(
				option.get(
					"spell_name",
					"Spell"
				)
			),
			Callable(
				self,
				"_toggle_generic_value"
			).bind(index_value)
		)

	_add_button(
		"Confirm Clean-up",
		Callable(
			self,
			"_submit_cleanup"
		)
	)


func _submit_cleanup() -> void:
	_submit({
		"return_to_hand_indices":
			generic_selection.duplicate()
	})


# =============================================================================
# BLACK ROSE QUEST CHOICES
# =============================================================================

func _render_optional_quest_discard() -> void:
	_add_button(
		"Do not discard a Quest",
		Callable(
			self,
			"_submit_optional_quest"
		).bind(-1)
	)

	for quest_value in current_request.get(
		"quests",
		[]
	):
		var quest: Dictionary = quest_value

		_add_button(
			"Discard "
			+ str(
				quest.get(
					"name",
					"Quest"
				)
			),
			Callable(
				self,
				"_submit_optional_quest"
			).bind(
				int(
					quest.get(
						"quest_index",
						-1
					)
				)
			)
		)


func _submit_optional_quest(
	quest_index: int
) -> void:
	_submit({
		"quest_index": quest_index
	})


func _submit_active_quest_limit() -> void:
	_submit({
		"quest_indices": generic_selection.duplicate()
	})


func _submit_completed_quest_limit() -> void:
	_submit({
		"quest_indices": generic_selection.duplicate()
	})
