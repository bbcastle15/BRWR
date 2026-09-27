from pathlib import Path
import re, shutil, sys

ROOT = Path(".")
BETA = ROOT / "beta_hud.gd"
PLAYER = ROOT / "player_board.gd"

def fail(msg):
    print("ERROR:", msg)
    sys.exit(1)

def replace_once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        fail(f"{label}: expected 1 match, found {n}")
    return text.replace(old, new, 1)

def backup(path):
    bak = path.with_suffix(path.suffix + ".hand_overlay.bak")
    if not bak.exists():
        shutil.copy2(path, bak)
        print("Backup:", bak)

if not BETA.exists() or not PLAYER.exists():
    fail("Run this from the Godot project root containing beta_hud.gd and player_board.gd.")
if not (ROOT / "hand_overlay.gd").exists():
    fail("hand_overlay.gd must be in the project root.")

beta = BETA.read_text(encoding="utf-8")
player = PLAYER.read_text(encoding="utf-8")

if 'const HandOverlayScript = preload("res://hand_overlay.gd")' not in beta:
    backup(BETA)

    beta = replace_once(
        beta,
        "class_name BetaHUD\nextends CanvasLayer\n",
        'class_name BetaHUD\nextends CanvasLayer\n\nconst HandOverlayScript = preload("res://hand_overlay.gd")\n',
        "header"
    )

    beta = replace_once(
        beta,
        "var feedback_label: Label\nvar reserved_width: float = 340.0\n",
        "var feedback_label: Label\nvar reserved_width: float = 340.0\nvar hand_button: Button\nvar hand_overlay = null\n",
        "fields"
    )

    beta = replace_once(
        beta,
        "\tstate_label = Label.new()\n"
        "\tstate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART\n"
        "\troot_box.add_child(state_label)\n\n"
        "\troot_box.add_child(HSeparator.new())\n",
        "\tstate_label = Label.new()\n"
        "\tstate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART\n"
        "\troot_box.add_child(state_label)\n\n"
        "\thand_button = Button.new()\n"
        "\thand_button.text = \"HAND\"\n"
        "\thand_button.custom_minimum_size = Vector2(0, 42)\n"
        "\thand_button.pressed.connect(_open_hand_overlay)\n"
        "\troot_box.add_child(hand_button)\n\n"
        "\troot_box.add_child(HSeparator.new())\n",
        "HAND button"
    )

    beta = replace_once(
        beta,
        '\tfooter.text = "F10: show/hide beta panel"\n'
        '\tfooter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT\n'
        '\tfooter.modulate = Color(0.75, 0.75, 0.75)\n'
        '\troot_box.add_child(footer)\n',
        '\tfooter.text = "H: hand   •   F10: show/hide beta panel"\n'
        '\tfooter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT\n'
        '\tfooter.modulate = Color(0.75, 0.75, 0.75)\n'
        '\troot_box.add_child(footer)\n\n'
        '\thand_overlay = HandOverlayScript.new()\n'
        '\toverlay.add_child(hand_overlay)\n'
        '\thand_overlay.setup(game)\n'
        '\thand_overlay.preparation_confirmed.connect(_on_hand_overlay_preparation_confirmed)\n',
        "overlay creation"
    )

    p = re.compile(
        r'func _unhandled_key_input\(event: InputEvent\) -> void:\n.*?(?=func _toggle_panel\(\) -> void:)',
        re.S
    )
    repl = """func _unhandled_key_input(event: InputEvent) -> void:
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


"""
    beta, n = p.subn(repl, beta, count=1)
    if n != 1:
        fail("keyboard handler replacement failed")

    beta = replace_once(
        beta,
        "func _on_player_input_resolved(\n\t_request: Dictionary\n) -> void:\n\t_refresh_header()\n",
        "func _on_player_input_resolved(\n\t_request: Dictionary\n) -> void:\n\tif hand_overlay != null:\n\t\thand_overlay.close_overlay(true)\n\n\t_refresh_header()\n",
        "input resolved"
    )

    beta = replace_once(
        beta,
        "func _on_player_input_requested(\n\trequest: Dictionary\n) -> void:\n\tcurrent_request = request.duplicate(true)\n",
        "func _on_player_input_requested(\n\trequest: Dictionary\n) -> void:\n\tif hand_overlay != null:\n\t\thand_overlay.close_overlay(true)\n\n\tcurrent_request = request.duplicate(true)\n",
        "input requested"
    )

    beta = replace_once(
        beta,
        '\tstate_label.text = "  |  ".join(summary)\n',
        '\tstate_label.text = "  |  ".join(summary)\n\n'
        '\tif hand_button != null:\n'
        '\t\tvar hand_count: int = 0\n'
        '\t\tif viewer >= 0:\n'
        '\t\t\tvar ps: Array = state.get("players", [])\n'
        '\t\t\tif viewer < ps.size():\n'
        '\t\t\t\thand_count = int(ps[viewer].get("hand_count", 0))\n'
        '\t\thand_button.text = "HAND (" + str(hand_count) + ")"\n'
        '\t\thand_button.disabled = viewer < 0 or hand_count <= 0\n',
        "hand count"
    )

    p = re.compile(r'func _render_preparation\(\) -> void:\n.*?(?=func _prep_assign\()', re.S)
    repl = """func _render_preparation() -> void:
	_add_info(
		"Your Hand is open over the Lodge. "
		+ "Choose Light/Dark and assign 2–4 Spells. "
		+ "The overlay closes automatically after Confirm."
	)

	if hand_overlay != null:
		hand_overlay.open_preparation(current_request)


"""
    beta, n = p.subn(repl, beta, count=1)
    if n != 1:
        fail("Preparation renderer replacement failed")

    BETA.write_text(beta, encoding="utf-8", newline="\n")
    print("Updated beta_hud.gd")
else:
    print("beta_hud.gd already contains HandOverlay integration.")

if '$HandInfo.text = "Hand: 0"' in player:
    backup(PLAYER)
    player = player.replace(
        '\t# Temporaneo finché non implementiamo la mano.\n\t$HandInfo.text = "Hand: 0"\n',
        '\t$HandInfo.text = "Hand: " + str(player_state.hand.size())\n',
        1
    )
    PLAYER.write_text(player, encoding="utf-8", newline="\n")
    print("Updated player_board.gd")
else:
    print("player_board.gd HandInfo already changed or placeholder not found.")

print("\nDone. Start Godot and test Preparation.")
