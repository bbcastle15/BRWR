extends SceneTree

# Run on the source with -- --write-baseline=<absolute JSON path>, then against
# --main-pack output/web/index.pck with -- --baseline=<same JSON path>.
# Existing missing art is reported explicitly; an export may not lose any art
# which actually exists in the source, nor ship different gameplay/UI scripts.
var baseline_path := ""
var writing := false
var failed := false

func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--write-baseline="):
			writing = true
			baseline_path = arg.trim_prefix("--write-baseline=")
		elif arg.begins_with("--baseline="):
			baseline_path = arg.trim_prefix("--baseline=")
	call_deferred("run")
	create_timer(90).timeout.connect(func(): push_error("Export parity timeout"); quit(2))

func check(ok: bool, label: String):
	if not ok:
		failed = true
		push_error(label)

func pixel_hash(texture: Texture2D) -> String:
	var pixels := texture.get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(pixels.get_data())
	return context.finish().hex_encode()

func atlas_hash(texture: AtlasTexture) -> String:
	# Export may compile a .tres into a remapped binary. Compare the actual
	# crop, its sampling settings and pixels through the runtime resource.
	return str([texture.atlas.resource_path, texture.region, texture.margin,
		texture.filter_clip, pixel_hash(texture)]).sha256_text()

func run():
	check(not baseline_path.is_empty(), "Provide baseline path")
	if failed: quit(1); return
	var game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	game.network_client = true
	root.add_child(game)
	while game.beta_hud == null: await process_frame
	var session = load("res://online_session.gd").new()
	root.add_child(session)
	var network_version: String = session.version
	session.queue_free()
	var available: Array[String] = []
	var missing: Array[String] = []
	for spell in game.spell_database.spells.values():
		if SpellArtResolver.get_texture(spell.id, spell.school_id) != null:
			available.append(spell.id)
		else: missing.append(spell.id)
	available.sort()
	missing.sort()
	var mage_ids: Array = []
	for mage in game.mage_database.mages.values(): mage_ids.append(str(mage.id))
	var script_hashes := {}
	for file in ["game.gd", "beta_hud.gd", "hand_overlay.gd", "player_board.gd",
		"tabletop_shell.gd", "tabletop_style.gd", "power_board.gd", "avatar_board.gd",
		"reference_card_preview.gd", "table_reserves.gd", "room.gd", "network_projection.gd", "online_session.gd", "choice_confirmation.gd", "avatar_effects.gd", "effect_resolver.gd", "effect_description.gd", "table_camera.gd", "action_history.gd", "data/room_art_sockets.json", "data/spells.json", "avatar_art.gd", "avatar_state.gd", "avatar_rules.gd",
		"spell_card_preview.gd", "spell_art_resolver.gd", "evocation_inspection.gd", "equipment_rules.gd", "druidic_rules.gd", "assets/tokens/evocation_portrait.gdshader", "assets/tokens/player_token.gdshader", "data/school_specializations_v19.json",
		"umbra_token.gd", "evocation_token.gd", "mage_token.gd", "mage_effects.gd", "familiar_rules.gd", "mage_database.gd", "evocation_state.gd", "forgotten_evocations.gd", "forgotten_passives.gd", "school_effects.gd", "triggered_spell_manager.gd", "data/mages.json", "data/evocations.json", "assets/tokens/evocations/portraits.json", "school_draw_presentation.gd", "main_menu.gd", "death_effect_resolver.gd", "data/quests.json"]:
		script_hashes[file] = FileAccess.get_sha256("res://" + file)
	var quest_ids: Array = game.quest_database.quests.keys()
	quest_ids.sort()
	var quest_art: Dictionary = {}
	for id in quest_ids:
		var face = game.ReferenceCardPreview.card_texture("quests", str(id))
		var expected_path := "res://assets/quests/symbols/" + str(id) + ".png"
		if game.quest_database.quests[id].moon == 1:
			expected_path = "res://assets/quests/reconstructed/conspirator_mage.png" if id == "conspirator_mage" else "res://assets/quests/originals/" + str(id) + ".tres"
		var restored_path := "res://assets/quests/restored/" + str(id) + ".png"
		if ResourceLoader.exists(restored_path): expected_path = restored_path
		check(face != null and face.resource_path == expected_path, "Quest must use its current approved source: " + str(id))
		if face == null: continue
		quest_art[id] = face.resource_path
		if face.resource_path == restored_path:
			script_hashes[restored_path] = pixel_hash(face)
		if face is AtlasTexture:
			script_hashes[face.resource_path] = atlas_hash(face)
			check(Rect2(Vector2.ZERO, face.atlas.get_size()).encloses(face.region), "Quest crop must remain inside the original scan: " + str(id))
			var centers: PackedVector2Array = game.ReferenceCardPreview.quest_progress_centers(str(id), Vector2(260, 390))
			check(centers.size() == game.quest_database.quests[id].cube_slots, "Printed progress slots must match Quest: " + str(id))
	var quest_back = game.ReferenceCardPreview.quest_back_texture(1)
	check(quest_back is AtlasTexture, "Moon I Quest back must use the original scan")
	var original_hash := ""
	if quest_back is AtlasTexture:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(quest_back.atlas.get_image().get_data())
		original_hash = context.finish().hex_encode()
		script_hashes[quest_back.resource_path] = atlas_hash(quest_back)
	var board = game.get_node("PowerBoard")
	var deck_back = board.get_node("QuestSlot/AvailableDeck/CardBack")
	for moon in [1, 2, 3, 1]:
		game.current_moon = moon
		board._refresh_quest_deck_back()
		var expected_back = game.ReferenceCardPreview.quest_back_texture(moon)
		check(expected_back != null and deck_back.texture == expected_back, "Quest deck back follows Moon %d" % moon)
		if moon > 1 and expected_back != null:
			script_hashes[expected_back.resource_path] = pixel_hash(expected_back)
		check(is_equal_approx(deck_back.rotation, PI / 2.0), "Printed Quest deck backs use portrait art")
	for kind in ["jinxs", "upgrades"]:
		var back = game.ReferenceCardPreview.card_texture(kind, "back")
		check(back != null and back.get_width() >= 512, "High quality deck back must be exported: " + kind)
	check(game.is_school_complete("hex"), "Hex must be playable in source and Web export")
	for spell in game.spell_database.spells.values():
		if spell.school_id == "hex":
			var hex_face := SpellArtResolver.get_texture(spell.id, "hex")
			check(hex_face != null and hex_face.resource_path.begins_with("res://assets/spells/hex_reviewed/"), "Reviewed Hex face: " + str(spell.id))
			if hex_face != null: script_hashes[hex_face.resource_path] = pixel_hash(hex_face)
	check(game.is_school_complete("nightmare"), "Nightmare must be playable in source and Web export")
	check(load("res://assets/fonts/library_title.ttf") is FontFile, "School reveal title font must be exported")
	check(not game.mage_database.get_mage_ids().has("hyperion"), "Incomplete three-Model Mage stays outside setup")
	for id in ["agorix","albedo","alhazred","alice","alisha","architect","arianna","baron_doria","bella","cacus","boogeyman","cosma","fenrir","gramigna","griphon","helblindi","ignis","irene","jack","jukas","maelice","minotaurus","odin","razvan","rubedo","saba","shroudtech","slenderman","talia","ulrich"]:
		check(game.mage_database.get_mage_ids().has(id), "Mage is selectable: " + id)
		check(SpellArtResolver.get_texture(game.mage_database.get_mage_data(id).personal_spell_id) != null, "Personal Spell image exists: " + id)
	for id in ["command_back_1_protection_damage", "command_back_2_protection_damage", "command_back_2_protection_combat", "command_back_3_protection_damage", "command_back_3_protection_combat"]:
		check(AvatarArt.texture(id) != null, "Missing Avatar reaction back: " + id)
	for symbol in ["damage", "combat"]:
		check(game.ReferenceCardPreview.card_texture("tokens", "avatar_protection_" + symbol) != null, "Missing Avatar reaction token: " + symbol)
	if writing:
		var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://docs/mage-art-2026-10-23/manifest.json"))
		for card in manifest.cards:
			if not mage_ids.has(card.id): mage_ids.append(card.id)
		var out = FileAccess.open(baseline_path, FileAccess.WRITE)
		out.store_string(JSON.stringify({"spells":available,"missing_spells":missing,"mages":mage_ids,"quests":quest_ids,"quest_art":quest_art,"quest_original_pixels_sha256":original_hash,"scripts":script_hashes,"network_version":network_version}, "\t"))
		out.close()
		print("SOURCE ART BASELINE: ", available.size(), " Spell textures; ", mage_ids.size(), " Mage textures")
		print("EXISTING MISSING SPELL ART: ", missing)
	else:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
		check(available == expected.spells, "Exported Spell art differs from source")
		check(missing == expected.missing_spells, "Export introduced missing art")
		check(script_hashes == expected.scripts, "Exported scripts differ from current working tree")
		check(network_version == expected.network_version, "Native host and exported client have different multiplayer compatibility versions")
		check(quest_ids == expected.quests, "Exported Quest faces differ from source")
		check(quest_art == expected.quest_art, "Exported Quest textures use different sources")
		check(original_hash == expected.quest_original_pixels_sha256, "Web export altered pixels of the original Quest scans")
		for id in expected.mages:
			check(game.ReferenceCardPreview.card_texture("mages", id) != null, "Missing exported Mage card: " + id)
		for slot in ["QuestSlot", "JinxSlot", "UpgradeSlot"]:
			check(game.get_node("PowerBoard").get_node_or_null(slot + "/AvailableDeck/CardBack") != null, "Missing catalog deck: " + slot)
		game._reference_card_preview().show_school_library("alchemy")
		check(game._reference_card_preview().pile_cards.size() == 13, "Exported School catalog incomplete")
		check(game.table_shell != null and game.players.size() == 2, "Exported UI did not initialize")
		print("EXPORT PARITY: ", expected.spells.size(), " Spell textures, ", expected.mages.size(), " Mage cards, ", quest_ids.size(), " Quest faces, ", script_hashes.size(), " matching scripts; ", "FAIL" if failed else "PASS")
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
