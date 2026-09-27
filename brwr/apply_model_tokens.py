from pathlib import Path
import shutil
import sys

ROOT = Path(".")
GAME = ROOT / "game.gd"
MAGE_TOKEN = ROOT / "mage_token.gd"
EVOC_GD = ROOT / "evocation_token.gd"
EVOC_TSCN = ROOT / "evocation_token.tscn"

MAGE_TOKEN_CODE = 'extends Node2D\n\n\nvar player_index: int = -1\nvar token_color: Color = Color.WHITE\n\n\nfunc setup(index: int, color: Color):\n\tplayer_index = index\n\ttoken_color = color\n\tz_index = 80\n\n\tcreate_shape()\n\n\tvar label: Label = $Label\n\tlabel.text = "P" + str(index + 1)\n\tlabel.position = Vector2(-22, -11)\n\tlabel.size = Vector2(44, 22)\n\tlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER\n\tlabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER\n\tlabel.mouse_filter = Control.MOUSE_FILTER_IGNORE\n\tlabel.add_theme_font_size_override("font_size", 14)\n\tlabel.add_theme_color_override("font_color", Color.WHITE)\n\tlabel.add_theme_color_override("font_outline_color", Color.BLACK)\n\tlabel.add_theme_constant_override("outline_size", 5)\n\n\nfunc create_shape():\n\tvar ring = get_node_or_null("Ring")\n\n\tif ring == null:\n\t\tring = Polygon2D.new()\n\t\tring.name = "Ring"\n\t\tring.z_index = -1\n\t\tadd_child(ring)\n\n\tring.polygon = _circle_points(20.0, 28)\n\tring.color = Color(0.04, 0.04, 0.04, 1.0)\n\n\t$Body.polygon = _circle_points(17.0, 28)\n\t$Body.color = token_color\n\n\nfunc _circle_points(\n\tradius: float,\n\tpoint_count: int\n) -> PackedVector2Array:\n\tvar points := PackedVector2Array()\n\n\tfor i in range(point_count):\n\t\tvar angle: float = TAU * float(i) / float(point_count)\n\t\tpoints.append(\n\t\t\tVector2(\n\t\t\t\tcos(angle),\n\t\t\t\tsin(angle)\n\t\t\t) * radius\n\t\t)\n\n\treturn points\n'
EVOCATION_TOKEN_CODE = 'extends Node2D\n\n\nvar evocation_id: String = ""\nvar evocation_name: String = ""\nvar owner_id: int = -1\nvar owner_color: Color = Color.WHITE\n\n\nfunc setup(\n\tid_value: String,\n\tname_value: String,\n\towner_index: int,\n\tcolor: Color\n) -> void:\n\tevocation_id = id_value\n\tevocation_name = name_value\n\towner_id = owner_index\n\towner_color = color\n\tz_index = 79\n\n\t_build_visual()\n\n\nfunc _build_visual() -> void:\n\tfor child in get_children():\n\t\tchild.queue_free()\n\n\tvar owner_ring := Polygon2D.new()\n\towner_ring.name = "OwnerRing"\n\towner_ring.polygon = _diamond_points(19.0)\n\towner_ring.color = owner_color\n\towner_ring.z_index = -2\n\tadd_child(owner_ring)\n\n\tvar body := Polygon2D.new()\n\tbody.name = "Body"\n\tbody.polygon = _diamond_points(15.5)\n\tbody.color = Color(0.075, 0.075, 0.085, 1.0)\n\tbody.z_index = -1\n\tadd_child(body)\n\n\tvar type_label := Label.new()\n\ttype_label.name = "TypeLabel"\n\ttype_label.text = _abbreviation(evocation_name)\n\ttype_label.position = Vector2(-21, -14)\n\ttype_label.size = Vector2(42, 23)\n\ttype_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER\n\ttype_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER\n\ttype_label.mouse_filter = Control.MOUSE_FILTER_IGNORE\n\ttype_label.add_theme_font_size_override("font_size", 13)\n\ttype_label.add_theme_color_override("font_color", Color.WHITE)\n\ttype_label.add_theme_color_override("font_outline_color", Color.BLACK)\n\ttype_label.add_theme_constant_override("outline_size", 4)\n\tadd_child(type_label)\n\n\tvar owner_label := Label.new()\n\towner_label.name = "OwnerLabel"\n\towner_label.text = "P" + str(owner_id + 1)\n\towner_label.position = Vector2(-18, 8)\n\towner_label.size = Vector2(36, 17)\n\towner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER\n\towner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER\n\towner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE\n\towner_label.add_theme_font_size_override("font_size", 10)\n\towner_label.add_theme_color_override("font_color", owner_color)\n\towner_label.add_theme_color_override("font_outline_color", Color.BLACK)\n\towner_label.add_theme_constant_override("outline_size", 4)\n\tadd_child(owner_label)\n\n\nfunc _abbreviation(value: String) -> String:\n\tvar clean: String = value.strip_edges()\n\n\tif clean == "":\n\t\treturn "EV"\n\n\tvar words: PackedStringArray = clean.split(" ", false)\n\n\tif words.size() >= 2:\n\t\treturn (\n\t\t\twords[0].substr(0, 1)\n\t\t\t+ words[1].substr(0, 1)\n\t\t).to_upper()\n\n\tif clean.length() == 1:\n\t\treturn clean.to_upper()\n\n\treturn clean.substr(0, 2).to_upper()\n\n\nfunc _diamond_points(\n\tradius: float\n) -> PackedVector2Array:\n\treturn PackedVector2Array([\n\t\tVector2(0, -radius),\n\t\tVector2(radius, 0),\n\t\tVector2(0, radius),\n\t\tVector2(-radius, 0)\n\t])\n'
EVOCATION_TOKEN_TSCN = '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://evocation_token.gd" id="1_evocation"]\n\n[node name="EvocationToken" type="Node2D"]\nscript = ExtResource("1_evocation")\n'
TOKEN_BLOCK = '\nfunc create_model_tokens() -> void:\n\tfor token in mage_tokens:\n\t\tif is_instance_valid(token):\n\t\t\ttoken.queue_free()\n\n\tmage_tokens.clear()\n\n\tfor token_value in evocation_tokens.values():\n\t\tif is_instance_valid(token_value):\n\t\t\ttoken_value.queue_free()\n\n\tevocation_tokens.clear()\n\n\tfor player_index in range(players.size()):\n\t\tvar token = mage_token_scene.instantiate()\n\t\ttoken.name = "MageToken_P" + str(player_index + 1)\n\t\ttoken.setup(\n\t\t\tplayer_index,\n\t\t\tplayers[player_index].color\n\t\t)\n\t\tadd_child(token)\n\t\tmage_tokens.append(token)\n\n\trefresh_model_tokens()\n\n\nfunc _sync_evocation_tokens() -> void:\n\tvar live_ids: Dictionary = {}\n\n\tfor owner_index in range(players.size()):\n\t\tvar owner = players[owner_index]\n\n\t\tfor evocation in owner.evocations:\n\t\t\tif evocation == null:\n\t\t\t\tcontinue\n\n\t\t\tvar instance_id: int = int(\n\t\t\t\tevocation.get_instance_id()\n\t\t\t)\n\t\t\tlive_ids[instance_id] = true\n\n\t\t\tif evocation_tokens.has(instance_id):\n\t\t\t\tcontinue\n\n\t\t\tvar token = evocation_token_scene.instantiate()\n\t\t\ttoken.name = (\n\t\t\t\t"EvocationToken_"\n\t\t\t\t+ evocation.evocation_id\n\t\t\t\t+ "_P"\n\t\t\t\t+ str(owner_index + 1)\n\t\t\t)\n\t\t\ttoken.setup(\n\t\t\t\tevocation.evocation_id,\n\t\t\t\tevocation.evocation_name,\n\t\t\t\towner_index,\n\t\t\t\tplayers[owner_index].color\n\t\t\t)\n\t\t\tadd_child(token)\n\t\t\tevocation_tokens[instance_id] = token\n\n\tvar stale_ids: Array = []\n\n\tfor instance_id_value in evocation_tokens.keys():\n\t\tvar instance_id: int = int(instance_id_value)\n\n\t\tif live_ids.has(instance_id):\n\t\t\tcontinue\n\n\t\tvar old_token = evocation_tokens[\n\t\t\tinstance_id\n\t\t]\n\n\t\tif is_instance_valid(old_token):\n\t\t\told_token.queue_free()\n\n\t\tstale_ids.append(instance_id)\n\n\tfor instance_id in stale_ids:\n\t\tevocation_tokens.erase(instance_id)\n\n\nfunc refresh_model_tokens() -> void:\n\tif players.is_empty():\n\t\treturn\n\n\t_sync_evocation_tokens()\n\n\tvar groups: Dictionary = {}\n\tvar group_centers: Dictionary = {}\n\n\tfor player_index in range(players.size()):\n\t\tif player_index >= mage_tokens.size():\n\t\t\tcontinue\n\n\t\tvar mage = players[player_index].mage\n\t\tvar token = mage_tokens[player_index]\n\n\t\tif mage == null or not is_instance_valid(token):\n\t\t\tcontinue\n\n\t\tvar location_key: String = ""\n\t\tvar center: Vector2 = Vector2.ZERO\n\n\t\tif mage.in_cell:\n\t\t\tvar cell_coord: Vector2i = mage.room_coord\n\n\t\t\tif player_cell_coords.has(player_index):\n\t\t\t\tcell_coord = player_cell_coords[\n\t\t\t\t\tplayer_index\n\t\t\t\t]\n\n\t\t\tlocation_key = "cell:" + str(player_index)\n\t\t\tcenter = hex_to_pixel(cell_coord)\n\t\telse:\n\t\t\tif mage.room_id == "":\n\t\t\t\ttoken.visible = false\n\t\t\t\tcontinue\n\n\t\t\tvar room_coord: Vector2i = room_id_to_coord(\n\t\t\t\tmage.room_id\n\t\t\t)\n\n\t\t\tif room_coord == Vector2i(9999, 9999):\n\t\t\t\ttoken.visible = false\n\t\t\t\tcontinue\n\n\t\t\tlocation_key = "room:" + mage.room_id\n\t\t\tcenter = hex_to_pixel(room_coord)\n\n\t\ttoken.visible = true\n\n\t\tif not groups.has(location_key):\n\t\t\tgroups[location_key] = []\n\t\t\tgroup_centers[location_key] = center\n\n\t\tgroups[location_key].append({\n\t\t\t"node": token,\n\t\t\t"sort": player_index * 100\n\t\t})\n\n\tfor owner_index in range(players.size()):\n\t\tfor evocation_index in range(\n\t\t\tplayers[owner_index].evocations.size()\n\t\t):\n\t\t\tvar evocation = players[\n\t\t\t\towner_index\n\t\t\t].evocations[\n\t\t\t\tevocation_index\n\t\t\t]\n\n\t\t\tif evocation == null:\n\t\t\t\tcontinue\n\n\t\t\tif evocation.room_id == "":\n\t\t\t\tcontinue\n\n\t\t\tvar instance_id: int = int(\n\t\t\t\tevocation.get_instance_id()\n\t\t\t)\n\n\t\t\tif not evocation_tokens.has(instance_id):\n\t\t\t\tcontinue\n\n\t\t\tvar token = evocation_tokens[\n\t\t\t\tinstance_id\n\t\t\t]\n\n\t\t\tif not is_instance_valid(token):\n\t\t\t\tcontinue\n\n\t\t\tvar room_coord: Vector2i = room_id_to_coord(\n\t\t\t\tevocation.room_id\n\t\t\t)\n\n\t\t\tif room_coord == Vector2i(9999, 9999):\n\t\t\t\ttoken.visible = false\n\t\t\t\tcontinue\n\n\t\t\ttoken.visible = true\n\n\t\t\tvar location_key: String = (\n\t\t\t\t"room:"\n\t\t\t\t+ evocation.room_id\n\t\t\t)\n\n\t\t\tif not groups.has(location_key):\n\t\t\t\tgroups[location_key] = []\n\t\t\t\tgroup_centers[location_key] = hex_to_pixel(\n\t\t\t\t\troom_coord\n\t\t\t\t)\n\n\t\t\tgroups[location_key].append({\n\t\t\t\t"node": token,\n\t\t\t\t"sort":\n\t\t\t\t\t10000\n\t\t\t\t\t+ owner_index * 100\n\t\t\t\t\t+ evocation_index\n\t\t\t})\n\n\tfor location_key_value in groups.keys():\n\t\tvar location_key: String = str(\n\t\t\tlocation_key_value\n\t\t)\n\t\tvar entries: Array = groups[\n\t\t\tlocation_key\n\t\t]\n\n\t\tentries.sort_custom(\n\t\t\tfunc(a, b):\n\t\t\t\treturn int(a["sort"]) < int(b["sort"])\n\t\t)\n\n\t\tvar offsets: Array[Vector2] = (\n\t\t\t_model_token_offsets(\n\t\t\t\tentries.size()\n\t\t\t)\n\t\t)\n\t\tvar center: Vector2 = group_centers[\n\t\t\tlocation_key\n\t\t]\n\n\t\tfor i in range(entries.size()):\n\t\t\tvar node = entries[i]["node"]\n\n\t\t\tif not is_instance_valid(node):\n\t\t\t\tcontinue\n\n\t\t\tnode.position = center + offsets[i]\n\n\nfunc _model_token_offsets(\n\tcount: int\n) -> Array[Vector2]:\n\tvar result: Array[Vector2] = []\n\n\tif count <= 0:\n\t\treturn result\n\n\tif count == 1:\n\t\treturn [Vector2(0, -38)]\n\n\tif count == 2:\n\t\treturn [\n\t\t\tVector2(-22, -38),\n\t\t\tVector2(22, -38)\n\t\t]\n\n\tif count == 3:\n\t\treturn [\n\t\t\tVector2(-34, -38),\n\t\t\tVector2(0, -38),\n\t\t\tVector2(34, -38)\n\t\t]\n\n\tvar columns: int = mini(3, count)\n\tvar spacing_x: float = 35.0\n\tvar spacing_y: float = 34.0\n\tvar rows: int = int(\n\t\tceil(\n\t\t\tfloat(count)\n\t\t\t/ float(columns)\n\t\t)\n\t)\n\tvar start_y: float = (\n\t\t-42.0\n\t\t- float(rows - 1) * spacing_y * 0.5\n\t)\n\n\tfor i in range(count):\n\t\tvar row: int = int(i / columns)\n\t\tvar column: int = i % columns\n\n\t\tvar items_in_row: int = mini(\n\t\t\tcolumns,\n\t\t\tcount - row * columns\n\t\t)\n\n\t\tvar start_x: float = (\n\t\t\t-float(items_in_row - 1)\n\t\t\t* spacing_x\n\t\t\t* 0.5\n\t\t)\n\n\t\tresult.append(\n\t\t\tVector2(\n\t\t\t\tstart_x\n\t\t\t\t+ float(column)\n\t\t\t\t* spacing_x,\n\t\t\t\tstart_y\n\t\t\t\t+ float(row)\n\t\t\t\t* spacing_y\n\t\t\t)\n\t\t)\n\n\treturn result\n\n\n'

def fail(msg):
    print("ERROR:", msg)
    sys.exit(1)

def backup(path):
    if not path.exists():
        return
    bak = path.with_suffix(path.suffix + ".model_tokens.bak")
    if not bak.exists():
        shutil.copy2(path, bak)
        print("Backup:", bak)

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        fail(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)

if not GAME.exists():
    fail("game.gd not found. Run this script from the Godot project root.")
if not MAGE_TOKEN.exists():
    fail("mage_token.gd not found. Run this script from the Godot project root.")

game = GAME.read_text(encoding="utf-8")
marker = 'var evocation_token_scene = preload("res://evocation_token.tscn")'

if marker in game:
    print("game.gd already contains the model-token integration.")
else:
    backup(GAME)
    backup(MAGE_TOKEN)

    game = replace_once(
        game,
        'var mage_token_scene = preload("res://mage_token.tscn")\nvar mage_tokens: Array = []\n',
        'var mage_token_scene = preload("res://mage_token.tscn")\n'
        'var mage_tokens: Array = []\n'
        'var evocation_token_scene = preload("res://evocation_token.tscn")\n'
        'var evocation_tokens: Dictionary = {}\n'
        'var player_cell_coords: Dictionary = {}\n',
        "token variables"
    )

    game = replace_once(
        game,
        '\tcreate_players()\n\tassign_initial_crown()\n\tcreate_lodge()\n\tcreate_player_boards()\n',
        '\tcreate_players()\n\tassign_initial_crown()\n\tcreate_lodge()\n\tcreate_model_tokens()\n\tcreate_player_boards()\n',
        "_ready model-token creation"
    )

    game = replace_once(
        game,
        '\tplayer_entrance_room_ids.clear()\n'
        '\tplayer_entrance_room_coords.clear()\n'
        '\tplayer_cell_exit_room_ids.clear()\n'
        '\tplayer_cell_exit_room_coords.clear()\n',
        '\tplayer_entrance_room_ids.clear()\n'
        '\tplayer_entrance_room_coords.clear()\n'
        '\tplayer_cell_exit_room_ids.clear()\n'
        '\tplayer_cell_exit_room_coords.clear()\n'
        '\tplayer_cell_coords.clear()\n',
        "cell-coordinate reset"
    )

    game = replace_once(
        game,
        '\t\tif i < players.size():\n\t\t\tplayer_entrance_room_coords[i] = primary_coord\n',
        '\t\tif i < players.size():\n'
        '\t\t\tplayer_cell_coords[i] = hex_position\n'
        '\t\t\tplayer_entrance_room_coords[i] = primary_coord\n',
        "cell-coordinate assignment"
    )

    game = replace_once(
        game,
        '\tprint(\n\t\t"Players created: ",\n\t\tplayers.size()\n\t)\n\nfunc place_player_instability(\n',
        '\tprint(\n\t\t"Players created: ",\n\t\tplayers.size()\n\t)\n\n'
        + TOKEN_BLOCK
        + 'func place_player_instability(\n',
        "model-token functions"
    )

    game = replace_once(
        game,
        '\tupdate_player_board_positions()\n\n\nfunc set_player_power',
        '\tupdate_player_board_positions()\n\trefresh_model_tokens()\n\n\nfunc set_player_power',
        "layout refresh"
    )

    game = replace_once(
        game,
        '\tprint(\n'
        '\t\t"Player ",\n'
        '\t\towner_id + 1,\n'
        '\t\t" summoned ",\n'
        '\t\tevocation.evocation_name,\n'
        '\t\t" in room ",\n'
        '\t\troom_id\n'
        '\t)\n\n'
        '\treturn evocation\n\n'
        'func deal_damage_to_model',
        '\tprint(\n'
        '\t\t"Player ",\n'
        '\t\towner_id + 1,\n'
        '\t\t" summoned ",\n'
        '\t\tevocation.evocation_name,\n'
        '\t\t" in room ",\n'
        '\t\troom_id\n'
        '\t)\n\n'
        '\trefresh_model_tokens()\n'
        '\treturn evocation\n\n'
        'func deal_damage_to_model',
        "summon refresh"
    )

    game = replace_once(
        game,
        '\tmage.room_id = room_id\n\tmage.room_coord = room_coord\n\n'
        '\tprint(\n'
        '\t\t"Player ",\n'
        '\t\tplayer_index + 1,\n'
        '\t\t" starts in ",\n'
        '\t\troom_id,\n'
        '\t\t" at ",\n'
        '\t\troom_coord\n'
        '\t)\n'
        'func coord_to_room_id',
        '\tmage.room_id = room_id\n\tmage.room_coord = room_coord\n\n'
        '\trefresh_model_tokens()\n\n'
        '\tprint(\n'
        '\t\t"Player ",\n'
        '\t\tplayer_index + 1,\n'
        '\t\t" starts in ",\n'
        '\t\troom_id,\n'
        '\t\t" at ",\n'
        '\t\troom_coord\n'
        '\t)\n'
        'func coord_to_room_id',
        "starting-position refresh"
    )

    game = replace_once(
        game,
        '\t\tprint(\n'
        '\t\t\t"Player ", player_index + 1,\n'
        '\t\t\t" entered the Lodge through ", destination_room_id\n'
        '\t\t)\n'
        '\t\treturn true\n',
        '\t\tprint(\n'
        '\t\t\t"Player ", player_index + 1,\n'
        '\t\t\t" entered the Lodge through ", destination_room_id\n'
        '\t\t)\n'
        '\t\trefresh_model_tokens()\n'
        '\t\treturn true\n',
        "Cell-exit token refresh"
    )

    game = replace_once(
        game,
        '\tmage.room_id = destination_room_id\n'
        '\tmage.room_coord = destination_coord\n'
        '\tmage.in_cell = false\n'
        '\tprint("Player ", player_index + 1, " moved to ", destination_room_id)\n'
        '\treturn true\n\n'
        'func move_evocation_to_room_id',
        '\tmage.room_id = destination_room_id\n'
        '\tmage.room_coord = destination_coord\n'
        '\tmage.in_cell = false\n'
        '\tprint("Player ", player_index + 1, " moved to ", destination_room_id)\n'
        '\trefresh_model_tokens()\n'
        '\treturn true\n\n'
        'func move_evocation_to_room_id',
        "mage-move refresh"
    )

    game = replace_once(
        game,
        '\tprint(\n'
        '\t\tevocation.evocation_name,\n'
        '\t\t" moved to ",\n'
        '\t\tdestination_room_id\n'
        '\t)\n\n'
        '\treturn true\n\n'
        'func is_lodge_room_id',
        '\tprint(\n'
        '\t\tevocation.evocation_name,\n'
        '\t\t" moved to ",\n'
        '\t\tdestination_room_id\n'
        '\t)\n\n'
        '\trefresh_model_tokens()\n'
        '\treturn true\n\n'
        'func is_lodge_room_id',
        "evocation-move refresh"
    )

    game = replace_once(
        game,
        '\tevocation.damage_cubes.clear()\n'
        '\towner.evocations.remove_at(index)\n\n'
        '\treturn true\n\n\n'
        'func _valid_mage_physical_attack_evocation',
        '\tevocation.damage_cubes.clear()\n'
        '\towner.evocations.remove_at(index)\n\n'
        '\trefresh_model_tokens()\n'
        '\treturn true\n\n\n'
        'func _valid_mage_physical_attack_evocation',
        "evocation-removal refresh"
    )

    game = replace_once(
        game,
        '\tmage.in_cell = true\n\n'
        '\tprint(\n'
        '\t\t"Player ",\n'
        '\t\tplayer_index + 1,\n'
        '\t\t" Mage placed in Cell | entrance ",\n'
        '\t\tmage.room_id\n'
        '\t)\n',
        '\tmage.in_cell = true\n'
        '\trefresh_model_tokens()\n\n'
        '\tprint(\n'
        '\t\t"Player ",\n'
        '\t\tplayer_index + 1,\n'
        '\t\t" Mage placed in Cell | entrance ",\n'
        '\t\tmage.room_id\n'
        '\t)\n',
        "defeat-to-Cell refresh"
    )

    GAME.write_text(game, encoding="utf-8", newline="\n")
    MAGE_TOKEN.write_text(MAGE_TOKEN_CODE, encoding="utf-8", newline="\n")
    EVOC_GD.write_text(EVOCATION_TOKEN_CODE, encoding="utf-8", newline="\n")
    EVOC_TSCN.write_text(EVOCATION_TOKEN_TSCN, encoding="utf-8", newline="\n")

    print("Updated game.gd")
    print("Updated mage_token.gd")
    print("Created evocation_token.gd")
    print("Created evocation_token.tscn")

print()
print("MODEL TOKENS READY")
print("- Mage: colored circle, P1/P2/...")
print("- Evocation: owner-colored diamond, type abbreviation + P#")
print("- Movement/summon/removal/defeat are synchronized")
