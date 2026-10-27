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

func run():
	check(not baseline_path.is_empty(), "Provide baseline path")
	if failed: quit(1); return
	var game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	game.network_client = true
	root.add_child(game)
	while game.beta_hud == null: await process_frame
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
		"reference_card_preview.gd", "table_reserves.gd", "room.gd", "network_projection.gd", "online_session.gd", "choice_confirmation.gd", "avatar_effects.gd", "effect_resolver.gd", "data/spells.json"]:
		script_hashes[file] = FileAccess.get_sha256("res://" + file)
	if writing:
		var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://docs/mage-art-2026-10-23/manifest.json"))
		for card in manifest.cards:
			if not mage_ids.has(card.id): mage_ids.append(card.id)
		var out = FileAccess.open(baseline_path, FileAccess.WRITE)
		out.store_string(JSON.stringify({"spells":available,"missing_spells":missing,"mages":mage_ids,"scripts":script_hashes}, "\t"))
		out.close()
		print("SOURCE ART BASELINE: ", available.size(), " Spell textures; ", mage_ids.size(), " Mage textures")
		print("EXISTING MISSING SPELL ART: ", missing)
	else:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
		check(available == expected.spells, "Exported Spell art differs from source")
		check(missing == expected.missing_spells, "Export introduced missing art")
		check(script_hashes == expected.scripts, "Exported scripts differ from current working tree")
		for id in expected.mages:
			check(game.ReferenceCardPreview.card_texture("mages", id) != null, "Missing exported Mage card: " + id)
		for slot in ["QuestSlot", "JinxSlot", "UpgradeSlot"]:
			check(game.get_node("PowerBoard").get_node_or_null(slot + "/AvailableDeck/CardBack") != null, "Missing catalog deck: " + slot)
		game._reference_card_preview().show_school_library("alchemy")
		check(game._reference_card_preview().pile_cards.size() == 13, "Exported School catalog incomplete")
		check(game.table_shell != null and game.players.size() == 2, "Exported UI did not initialize")
		print("EXPORT PARITY: ", expected.spells.size(), " Spell textures, ", expected.mages.size(), " Mage cards, ", script_hashes.size(), " matching scripts; ", "FAIL" if failed else "PASS")
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
