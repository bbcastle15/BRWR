from pathlib import Path
import shutil
import sys

ROOT = Path(".")
GAME = ROOT / "game.gd"
BOARD = ROOT / "player_board.gd"

def fail(msg):
    print("ERROR:", msg)
    sys.exit(1)

def backup(path):
    bak = path.with_suffix(path.suffix + ".board_spells.bak")
    if not bak.exists():
        shutil.copy2(path, bak)
        print("Backup:", bak)

def replace_once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        fail(f"{label}: expected 1 match, found {n}")
    return text.replace(old, new, 1)

if not GAME.exists() or not BOARD.exists():
    fail("Run this script from the Godot project root.")

if not (ROOT / "spell_art_resolver.gd").exists():
    fail("spell_art_resolver.gd is missing from the project root.")
if not (ROOT / "spell_card_preview.gd").exists():
    fail("spell_card_preview.gd is missing from the project root.")

# =========================================================
# GAME.GD
# =========================================================
game = GAME.read_text(encoding="utf-8")

if "func get_player_board_spell_slot_data(" not in game:
    backup(GAME)

    game = replace_once(
        game,
        "var player_boards: Array = []\n",
        "var player_boards: Array = []\n"
        "var player_board_spell_slots: Dictionary = {}\n"
        "var spell_preview_script = preload(\"res://spell_card_preview.gd\")\n",
        "player-board Spell state"
    )

    game = replace_once(
        game,
        "\t\tboard.setup(players[i])\n",
        "\t\tboard.setup(players[i], self, i)\n",
        "PlayerBoard setup"
    )

    game = replace_once(
        game,
        "\twaiting_for_player_input = true\n\n\n"
        "\tprint(\n",
        "\twaiting_for_player_input = true\n"
        "\trefresh_all_player_boards()\n\n\n"
        "\tprint(\n",
        "request_player_input board refresh"
    )

    game = replace_once(
        game,
        "\tpending_input.clear()\n"
        "\twaiting_for_player_input = false\n\n\n"
        "\tplayer_input_resolved.emit(\n",
        "\tpending_input.clear()\n"
        "\twaiting_for_player_input = false\n"
        "\trefresh_all_player_boards()\n\n\n"
        "\tplayer_input_resolved.emit(\n",
        "clear_player_input board refresh"
    )

    helper_block = r'''
func refresh_player_board(
	player_index: int
) -> void:
	if player_index < 0 	or player_index >= player_boards.size():
		return

	if player_boards[player_index] == null:
		return

	player_boards[player_index].refresh()


func refresh_all_player_boards() -> void:
	for board in player_boards:
		if board != null:
			board.refresh()


func get_ui_viewer_player_index() -> int:
	if waiting_for_player_input:
		return int(
			pending_input.get(
				"player_index",
				-1
			)
		)

	return -1


func can_view_private_player_board_spells(
	owner_player_index: int
) -> bool:
	return (
		get_ui_viewer_player_index()
		== owner_player_index
	)


func _ensure_player_board_spell_slots(
	player_index: int
) -> Dictionary:
	if not player_board_spell_slots.has(player_index):
		player_board_spell_slots[player_index] = {
			"Q": {},
			"I": {},
			"II": {},
			"III": {}
		}

	return player_board_spell_slots[player_index]


func _set_player_board_spell_slot(
	player_index: int,
	slot_id: String,
	spell: SpellCardState,
	use_dark_side: bool,
	state: String
) -> void:
	if spell == null:
		return

	var slots: Dictionary = _ensure_player_board_spell_slots(
		player_index
	)

	slots[slot_id] = {
		"spell": spell,
		"use_dark_side": use_dark_side,
		"state": state
	}


func _clear_player_board_spell_slots(
	player_index: int
) -> void:
	player_board_spell_slots[player_index] = {
		"Q": {},
		"I": {},
		"II": {},
		"III": {}
	}

	refresh_player_board(player_index)


func _sync_player_board_prepared_spells(
	player_index: int
) -> void:
	if player_index < 0 	or player_index >= players.size():
		return

	var player = players[player_index]
	var slots: Dictionary = {
		"Q": {},
		"I": {},
		"II": {},
		"III": {}
	}

	var numbered_ids: Array[String] = [
		"I",
		"II",
		"III"
	]

	for i in range(
		min(
			3,
			player.ready_spells.size()
		)
	):
		var ready = player.ready_spells[i]

		if ready == null 		or ready.spell == null:
			continue

		slots[numbered_ids[i]] = {
			"spell": ready.spell,
			"use_dark_side": ready.use_dark_side,
			"state": "prepared"
		}

	if player.quick_spell != null 	and player.quick_spell.spell != null:
		slots["Q"] = {
			"spell": player.quick_spell.spell,
			"use_dark_side": player.quick_spell.use_dark_side,
			"state": "prepared"
		}

	player_board_spell_slots[player_index] = slots
	refresh_player_board(player_index)


func _find_player_board_slot_for_spell(
	player_index: int,
	spell: SpellCardState
) -> String:
	if spell == null:
		return ""

	var slots: Dictionary = _ensure_player_board_spell_slots(
		player_index
	)

	for slot_id_value in [
		"Q",
		"I",
		"II",
		"III"
	]:
		var slot_id: String = str(slot_id_value)
		var entry: Dictionary = slots.get(
			slot_id,
			{}
		)

		if entry.get(
			"spell",
			null
		) == spell:
			return slot_id

	return ""


func _set_player_board_spell_state(
	player_index: int,
	spell: SpellCardState,
	state: String
) -> void:
	var slot_id: String = _find_player_board_slot_for_spell(
		player_index,
		spell
	)

	if slot_id == "":
		return

	var slots: Dictionary = _ensure_player_board_spell_slots(
		player_index
	)
	var entry: Dictionary = slots.get(
		slot_id,
		{}
	)

	if entry.is_empty():
		return

	entry["state"] = state
	slots[slot_id] = entry
	refresh_player_board(player_index)


func _clear_player_board_spell_by_spell(
	player_index: int,
	spell: SpellCardState
) -> void:
	var slot_id: String = _find_player_board_slot_for_spell(
		player_index,
		spell
	)

	if slot_id == "":
		return

	var slots: Dictionary = _ensure_player_board_spell_slots(
		player_index
	)
	slots[slot_id] = {}
	refresh_player_board(player_index)


func get_player_board_spell_slot_data(
	player_index: int,
	slot_id: String
) -> Dictionary:
	if player_index < 0 	or player_index >= players.size():
		return {}

	var slots: Dictionary = _ensure_player_board_spell_slots(
		player_index
	)
	var entry: Dictionary = slots.get(
		slot_id,
		{}
	)

	if entry.is_empty():
		return {}

	var spell: SpellCardState = entry.get(
		"spell",
		null
	)

	if spell == null:
		return {}

	var state: String = str(
		entry.get(
			"state",
			"prepared"
		)
	)

	return {
		"occupied": true,
		"state": state,
		"public": state == "revealed",
		"id": spell.id,
		"name": spell.card_name,
		"school_id": spell.school_id,
		"use_dark_side": bool(
			entry.get(
				"use_dark_side",
				false
			)
		),
		"slot_id": slot_id
	}


func open_player_board_spell(
	player_index: int,
	slot_id: String
) -> void:
	var data: Dictionary = get_player_board_spell_slot_data(
		player_index,
		slot_id
	)

	if data.is_empty():
		return

	var public_card: bool = bool(
		data.get(
			"public",
			false
		)
	)

	if not public_card 	and not can_view_private_player_board_spells(
		player_index
	):
		return

	var preview = get_node_or_null(
		"SpellCardPreview"
	)

	if preview == null:
		preview = spell_preview_script.new()
		preview.name = "SpellCardPreview"
		add_child(preview)

	preview.show_spell(
		str(data.get("id", "")),
		str(data.get("name", "Spell")),
		str(data.get("school_id", "")),
		bool(data.get("use_dark_side", false)),
		public_card
	)


'''
    game = replace_once(
        game,
        "func create_player_boards():\n",
        helper_block + "func create_player_boards():\n",
        "PlayerBoard Spell helper API"
    )

    game = replace_once(
        game,
        "\tif player.quick_spell != null:\n"
        "\t\tprint(\n"
        "\t\t\t\"  Quick: \",\n"
        "\t\t\tplayer.quick_spell.spell.card_name,\n"
        "\t\t\t\" | \",\n"
        "\t\t\t\"Dark\" if player.quick_spell.use_dark_side else \"Light\"\n"
        "\t\t)\n\n"
        "\treturn true\n\n"
        "func resolve_preparation_phase",
        "\tif player.quick_spell != null:\n"
        "\t\tprint(\n"
        "\t\t\t\"  Quick: \",\n"
        "\t\t\tplayer.quick_spell.spell.card_name,\n"
        "\t\t\t\" | \",\n"
        "\t\t\t\"Dark\" if player.quick_spell.use_dark_side else \"Light\"\n"
        "\t\t)\n\n"
        "\t_sync_player_board_prepared_spells(player_index)\n"
        "\treturn true\n\n"
        "func resolve_preparation_phase",
        "Preparation -> PlayerBoard"
    )

    game = replace_once(
        game,
        "\t\t\t\tplayer.add_active_spell(active_spell)\n"
        "\t\t\t\tprint(\n",
        "\t\t\t\tplayer.add_active_spell(active_spell)\n"
        "\t\t\t\t_set_player_board_spell_state(\n"
        "\t\t\t\t\tplayer_index,\n"
        "\t\t\t\t\tspell,\n"
        "\t\t\t\t\t\"active_hidden\"\n"
        "\t\t\t\t)\n"
        "\t\t\t\tprint(\n",
        "Trap/Protection hidden board state"
    )

    game = replace_once(
        game,
        "\t\t\tplayers[\n"
        "\t\t\t\tcaster_id\n"
        "\t\t\t].add_revealed_spell(\n"
        "\t\t\t\trevealed\n"
        "\t\t\t)\n\n"
        "\t\t\t_register_ongoing_revealed_spell(",
        "\t\t\tplayers[\n"
        "\t\t\t\tcaster_id\n"
        "\t\t\t].add_revealed_spell(\n"
        "\t\t\t\trevealed\n"
        "\t\t\t)\n\n"
        "\t\t\t_set_player_board_spell_state(\n"
        "\t\t\t\tcaster_id,\n"
        "\t\t\t\tspell,\n"
        "\t\t\t\t\"revealed\"\n"
        "\t\t\t)\n\n"
        "\t\t\t_register_ongoing_revealed_spell(",
        "normal Spell public reveal"
    )

    game = replace_once(
        game,
        "\t\t\t\tplayers[owner_id].add_revealed_spell(revealed)\n\n"
        "\t\t\tif spell_type == \"trap\" or spell_type == \"protection\":\n",
        "\t\t\t\tplayers[owner_id].add_revealed_spell(revealed)\n"
        "\t\t\t\t_set_player_board_spell_state(\n"
        "\t\t\t\t\towner_id,\n"
        "\t\t\t\t\tactive_spell.spell,\n"
        "\t\t\t\t\t\"revealed\"\n"
        "\t\t\t\t)\n\n"
        "\t\t\tif spell_type == \"trap\" or spell_type == \"protection\":\n",
        "triggered Spell public reveal"
    )

    game = replace_once(
        game,
        "\t\t\tmove_spell_to_memories_or_remove(\n"
        "\t\t\t\tplayer_index,\n"
        "\t\t\t\tspell\n"
        "\t\t\t)\n\n"
        "\t\t\tresolution[\"discarded_spell_id\"] = spell.id\n",
        "\t\t\tmove_spell_to_memories_or_remove(\n"
        "\t\t\t\tplayer_index,\n"
        "\t\t\t\tspell\n"
        "\t\t\t)\n\n"
        "\t\t\t_clear_player_board_spell_by_spell(\n"
        "\t\t\t\tplayer_index,\n"
        "\t\t\t\tspell\n"
        "\t\t\t)\n"
        "\t\t\tresolution[\"discarded_spell_id\"] = spell.id\n",
        "Momentum PlayerBoard removal"
    )

    game = replace_once(
        game,
        "\tplayer.revealed_spells.clear()\n\n"
        "\tplayer.refresh_physical_actions()\n",
        "\tplayer.revealed_spells.clear()\n"
        "\t_clear_player_board_spell_slots(player_index)\n\n"
        "\tplayer.refresh_physical_actions()\n",
        "Clean-up PlayerBoard slots"
    )

    GAME.write_text(game, encoding="utf-8", newline="\n")
    print("Updated game.gd")
else:
    print("game.gd already contains PlayerBoard Spell integration.")

# =========================================================
# PLAYER_BOARD.GD
# =========================================================
board = BOARD.read_text(encoding="utf-8")

if "func refresh_spell_slots()" not in board:
    backup(BOARD)

    board = replace_once(
        board,
        "var player_state: PlayerState\n",
        "var player_state: PlayerState\n"
        "var game = null\n"
        "var player_index: int = -1\n",
        "PlayerBoard fields"
    )

    board = replace_once(
        board,
        "func setup(player: PlayerState):\n"
        "\tplayer_state = player\n\n"
        "\tcreate_damage_track()\n"
        "\trefresh()\n",
        "func setup(\n"
        "\tplayer: PlayerState,\n"
        "\tgame_node = null,\n"
        "\tindex: int = -1\n"
        "):\n"
        "\tplayer_state = player\n"
        "\tgame = game_node\n"
        "\tplayer_index = index if index >= 0 else player.player_index\n\n"
        "\tcreate_damage_track()\n"
        "\trefresh()\n",
        "PlayerBoard setup"
    )

    board = replace_once(
        board,
        "\trefresh_damage_track()\n",
        "\trefresh_spell_slots()\n"
        "\trefresh_damage_track()\n",
        "PlayerBoard refresh"
    )

    board = replace_once(
        board,
        "\tsetup_slot(\n"
        "\t\t$SpellSlots/SpellSlotIII,\n"
        "\t\tVector2(\n"
        "\t\t\tcards_x\n"
        "\t\t\t+ (\n"
        "\t\t\t\tSPELL_SIZE.x\n"
        "\t\t\t\t+ CARD_GAP\n"
        "\t\t\t) * 2.0,\n"
        "\t\t\tbottom_y\n"
        "\t\t),\n"
        "\t\tSPELL_SIZE\n"
        "\t)\n\n\n"
        "func setup_slot(",
        "\tsetup_slot(\n"
        "\t\t$SpellSlots/SpellSlotIII,\n"
        "\t\tVector2(\n"
        "\t\t\tcards_x\n"
        "\t\t\t+ (\n"
        "\t\t\t\tSPELL_SIZE.x\n"
        "\t\t\t\t+ CARD_GAP\n"
        "\t\t\t) * 2.0,\n"
        "\t\t\tbottom_y\n"
        "\t\t),\n"
        "\t\tSPELL_SIZE\n"
        "\t)\n\n"
        "\t_configure_spell_slot($SpellSlots/QuickSpellSlot, \"Q\")\n"
        "\t_configure_spell_slot($SpellSlots/SpellSlotI, \"I\")\n"
        "\t_configure_spell_slot($SpellSlots/SpellSlotII, \"II\")\n"
        "\t_configure_spell_slot($SpellSlots/SpellSlotIII, \"III\")\n\n\n"
        "func setup_slot(",
        "Spell slot widgets"
    )

    board_helpers = r'''
func _configure_spell_slot(
	slot: Control,
	slot_id: String
) -> void:
	if slot.get_node_or_null("CardBack") == null:
		var back := ColorRect.new()
		back.name = "CardBack"
		back.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)
		back.color = Color(0.055, 0.055, 0.07, 1.0)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.visible = false
		slot.add_child(back)
		slot.move_child(back, 0)

	if slot.get_node_or_null("CardArt") == null:
		var art := TextureRect.new()
		art.name = "CardArt"
		art.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.visible = false
		slot.add_child(art)

	if slot.get_node_or_null("CardClickButton") == null:
		var button := Button.new()
		button.name = "CardClickButton"
		button.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)
		button.flat = true
		button.text = ""
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(
			Callable(
				self,
				"_on_spell_slot_pressed"
			).bind(
				slot_id
			)
		)
		slot.add_child(button)


func refresh_spell_slots() -> void:
	if player_state == null:
		return

	_render_spell_slot(
		$SpellSlots/QuickSpellSlot,
		"Q",
		"QUICK"
	)
	_render_spell_slot(
		$SpellSlots/SpellSlotI,
		"I",
		"I"
	)
	_render_spell_slot(
		$SpellSlots/SpellSlotII,
		"II",
		"II"
	)
	_render_spell_slot(
		$SpellSlots/SpellSlotIII,
		"III",
		"III"
	)


func _render_spell_slot(
	slot: Control,
	slot_id: String,
	empty_label: String
) -> void:
	_configure_spell_slot(
		slot,
		slot_id
	)

	var label: Label = slot.get_node_or_null("Label")
	var back: ColorRect = slot.get_node_or_null("CardBack")
	var art: TextureRect = slot.get_node_or_null("CardArt")
	var button: Button = slot.get_node_or_null("CardClickButton")

	if label == null 	or back == null 	or art == null 	or button == null:
		return

	var data: Dictionary = {}

	if game != null:
		data = game.get_player_board_spell_slot_data(
			player_index,
			slot_id
		)

	if data.is_empty():
		back.visible = false
		art.visible = false
		art.texture = null
		label.visible = true
		label.text = empty_label
		button.disabled = true
		button.tooltip_text = ""
		return

	var public_card: bool = bool(
		data.get(
			"public",
			false
		)
	)

	if public_card:
		var texture: Texture2D = SpellArtResolver.get_texture(
			str(data.get("id", "")),
			str(data.get("school_id", ""))
		)

		back.visible = false

		if texture != null:
			art.texture = texture
			art.visible = true
			label.visible = false
		else:
			art.texture = null
			art.visible = false
			label.visible = true
			label.text = str(
				data.get(
					"name",
					"Spell"
				)
			)

		button.disabled = false
		button.tooltip_text = (
			str(data.get("name", "Spell"))
			+ " — click to inspect"
		)
		return

	back.visible = true
	art.texture = null
	art.visible = false
	label.visible = true
	label.text = empty_label + "
SET"

	var owner_can_view: bool = (
		game != null
		and game.can_view_private_player_board_spells(
			player_index
		)
	)

	button.disabled = not owner_can_view
	button.tooltip_text = (
		"Click to inspect your prepared Spell"
		if owner_can_view
		else "Prepared Spell — hidden"
	)


func _on_spell_slot_pressed(
	slot_id: String
) -> void:
	if game == null:
		return

	game.open_player_board_spell(
		player_index,
		slot_id
	)


'''
    board = replace_once(
        board,
        "# =========================================================\n"
        "# DAMAGE TRACK\n"
        "# =========================================================\n",
        board_helpers
        + "# =========================================================\n"
        "# DAMAGE TRACK\n"
        "# =========================================================\n",
        "PlayerBoard Spell renderer"
    )

    BOARD.write_text(board, encoding="utf-8", newline="\n")
    print("Updated player_board.gd")
else:
    print("player_board.gd already contains PlayerBoard Spell rendering.")

print()
print("PLAYER BOARD SPELLS READY")
print("- Prepared cards occupy Q/I/II/III as hidden SET cards.")
print("- Only the owning current player can inspect them.")
print("- Revealed cards become face-up and public.")
print("- Armed Trap/Protection remains hidden until triggered.")
