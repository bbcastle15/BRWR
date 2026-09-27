from pathlib import Path
import shutil
import sys

root = Path(".")
game_path = root / "game.gd"
board_path = root / "player_board.gd"

def die(msg):
    print("ERROR:", msg)
    sys.exit(1)

if not game_path.exists() or not board_path.exists():
    die("Run this from the Godot project root.")

game = game_path.read_text(encoding="utf-8")
if "func get_player_board_spell_slot_data(" not in game:
    die("game.gd does not contain the previous PlayerBoard Spell integration.")

board = board_path.read_text(encoding="utf-8")

if "func refresh_spell_slots()" in board:
    print("player_board.gd is already patched.")
    sys.exit(0)

bak = board_path.with_suffix(".gd.board_spells_fix.bak")
if not bak.exists():
    shutil.copy2(board_path, bak)
    print("Backup:", bak)

# 1) Game reference + owner index.
needle = "var player_state: PlayerState\n"
if needle not in board:
    die("Could not find player_state field.")
board = board.replace(
    needle,
    needle + "var game = null\nvar player_index: int = -1\n",
    1,
)

# 2) setup() receives Game and owner id.
old_setup = (
    "func setup(player: PlayerState):\n"
    "\tplayer_state = player\n\n"
    "\tcreate_damage_track()\n"
    "\trefresh()\n"
)
new_setup = (
    "func setup(\n"
    "\tplayer: PlayerState,\n"
    "\tgame_node = null,\n"
    "\tindex: int = -1\n"
    "):\n"
    "\tplayer_state = player\n"
    "\tgame = game_node\n"
    "\tplayer_index = index if index >= 0 else player.player_index\n\n"
    "\tcreate_damage_track()\n"
    "\trefresh()\n"
)
if old_setup not in board:
    die("Could not find PlayerBoard setup().")
board = board.replace(old_setup, new_setup, 1)

# 3) refresh() also redraws Spell slots.
refresh_start = board.find("func refresh():")
refresh_end = board.find("\nfunc ", refresh_start + 1)
if refresh_start == -1 or refresh_end == -1:
    die("Could not locate refresh().")

refresh_block = board[refresh_start:refresh_end]
if "\trefresh_damage_track()\n" not in refresh_block:
    die("Could not find refresh_damage_track() inside refresh().")

refresh_block = refresh_block.replace(
    "\trefresh_damage_track()\n",
    "\trefresh_spell_slots()\n\trefresh_damage_track()\n",
    1,
)
board = board[:refresh_start] + refresh_block + board[refresh_end:]

# 4) Configure Q/I/II/III after setup_main_cards().
setup_slot_pos = board.find("\nfunc setup_slot(")
if setup_slot_pos == -1:
    die("Could not find setup_slot().")

configure_calls = (
    "\n\t_configure_spell_slot($SpellSlots/QuickSpellSlot, \"Q\")\n"
    "\t_configure_spell_slot($SpellSlots/SpellSlotI, \"I\")\n"
    "\t_configure_spell_slot($SpellSlots/SpellSlotII, \"II\")\n"
    "\t_configure_spell_slot($SpellSlots/SpellSlotIII, \"III\")\n"
)
board = board[:setup_slot_pos] + configure_calls + board[setup_slot_pos:]

# 5) Unique insertion point: function name, not the duplicated comment heading.
marker = "func create_damage_track():\n"
marker_pos = board.find(marker)
if marker_pos == -1:
    die("Could not find create_damage_track().")

helpers = r'''func _configure_spell_slot(slot: Control, slot_id: String) -> void:
	if slot.get_node_or_null("CardBack") == null:
		var back := ColorRect.new()
		back.name = "CardBack"
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		back.color = Color(0.055, 0.055, 0.07, 1.0)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.visible = false
		slot.add_child(back)
		slot.move_child(back, 0)

	if slot.get_node_or_null("CardArt") == null:
		var art := TextureRect.new()
		art.name = "CardArt"
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.visible = false
		slot.add_child(art)

	if slot.get_node_or_null("CardClickButton") == null:
		var button := Button.new()
		button.name = "CardClickButton"
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.flat = true
		button.text = ""
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(
			Callable(self, "_on_spell_slot_pressed").bind(slot_id)
		)
		slot.add_child(button)


func refresh_spell_slots() -> void:
	if player_state == null:
		return

	_render_spell_slot($SpellSlots/QuickSpellSlot, "Q", "QUICK")
	_render_spell_slot($SpellSlots/SpellSlotI, "I", "I")
	_render_spell_slot($SpellSlots/SpellSlotII, "II", "II")
	_render_spell_slot($SpellSlots/SpellSlotIII, "III", "III")


func _render_spell_slot(
	slot: Control,
	slot_id: String,
	empty_label: String
) -> void:
	_configure_spell_slot(slot, slot_id)

	var label: Label = slot.get_node_or_null("Label")
	var back: ColorRect = slot.get_node_or_null("CardBack")
	var art: TextureRect = slot.get_node_or_null("CardArt")
	var button: Button = slot.get_node_or_null("CardClickButton")

	if label == null or back == null or art == null or button == null:
		return

	var data: Dictionary = {}
	if game != null:
		data = game.get_player_board_spell_slot_data(player_index, slot_id)

	if data.is_empty():
		back.visible = false
		art.visible = false
		art.texture = null
		label.visible = true
		label.text = empty_label
		button.disabled = true
		button.tooltip_text = ""
		return

	var public_card: bool = bool(data.get("public", false))

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
			label.text = str(data.get("name", "Spell"))

		button.disabled = false
		button.tooltip_text = (
			str(data.get("name", "Spell")) + " — click to inspect"
		)
		return

	back.visible = true
	art.texture = null
	art.visible = false
	label.visible = true
	label.text = empty_label + "\nSET"

	var owner_can_view: bool = (
		game != null
		and game.can_view_private_player_board_spells(player_index)
	)

	button.disabled = not owner_can_view
	button.tooltip_text = (
		"Click to inspect your prepared Spell"
		if owner_can_view
		else "Prepared Spell — hidden"
	)


func _on_spell_slot_pressed(slot_id: String) -> void:
	if game == null:
		return
	game.open_player_board_spell(player_index, slot_id)


'''

board = board[:marker_pos] + helpers + board[marker_pos:]

board_path.write_text(board, encoding="utf-8", newline="\n")

print("Updated player_board.gd")
print("FIX APPLIED SUCCESSFULLY")
print("Do not rerun the old apply_player_board_spells.py.")
