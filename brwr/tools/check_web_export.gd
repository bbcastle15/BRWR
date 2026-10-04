extends SceneTree

var elapsed := 0.0

func _initialize() -> void:
	call_deferred("run")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 30:
		push_error("Exported game did not finish loading")
		quit(1)
	return false

func run() -> void:
	for path in ["res://spell_card_preview.gd", "res://reference_card_preview.gd", "res://data/spells.json", "res://web_build.json"]:
		assert(FileAccess.file_exists(path), "Missing exported resource: " + path)
	var scene = load("res://game.tscn")
	assert(scene != null)
	var game = scene.instantiate()
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	game.network_client = true
	root.add_child(game)
	while game.beta_hud == null: await process_frame
	assert(game.players.size() == 2)
	assert(game.spell_database.spells.size() > 0)
	for spell in game.spell_database.spells.values():
		assert(SpellArtResolver.get_texture(spell.id, spell.school_id) != null, "Missing exported spell art: " + spell.id)
	for school_id in game.active_school_ids:
		assert(game.ReferenceCardPreview.card_texture("schools", school_id) != null, "Missing exported School art: " + school_id)
	assert(load("res://assets/boards/event_board_reference.png") != null)
	assert(game.table_shell != null and game.table_shell.banners.size() == game.players.size())
	for path in ["res://assets/tabletop/playmat.png", "res://assets/tabletop/card_back.png", "res://assets/tokens/trap.png", "res://assets/tokens/protection.png", "res://assets/tokens/permanent.png"]:
		assert(load(path) is Texture2D, "Missing exported tabletop art: " + path)
	game.queue_free()
	await process_frame
	print("EXPORTED PACK CHECK PASS")
	quit()
