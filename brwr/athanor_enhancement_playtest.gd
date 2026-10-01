extends SceneTree

var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(8):
		await process_frame
	var player = game.players[0]
	var viatorium = game.clone_spell_card(game.spell_database.get_spell("viatorium_spagyricum"))
	var target_room = game.get_room_by_id("forge")
	for p in game.players:
		p.mage.in_cell = false
		p.mage.room_id = "forge"
		p.mage.room_coord = game.room_id_to_coord("forge")
	for dark in [true, false]:
		player.revealed_spells.assign([RevealedSpellState.new(viatorium, dark)])
		var athanor = game.clone_spell_card(game.spell_database.get_spell("athanor_eruption"))
		check(game.can_apply_enhancement(0, ["air"], athanor) == dark, "Only Viatorium Dark supplies Air to Athanor")
		check(game.can_apply_enhancement(0, ["water"], athanor) != dark, "Only Viatorium Light supplies Water")
		var cubes_before: int = target_room.get_instability_count()
		var damage_before: int = game.players[1].mage.get_damage()
		player.quick_spell = ReadySpellState.new(athanor, true)
		check(game.cast_quick_spell(0, {"target_model_type": "mage", "target_player_index": 1}), "Athanor Dark cast must commit")
		check(target_room.get_instability_count() == cubes_before + (1 if dark else 0), "Air Enhancement must place one instability in target Room")
		check(game.players[1].mage.get_damage() == damage_before + 2, "Athanor base damage remains two")
		check(game.resolution_stack.is_empty(), "Athanor must fully resolve")
	var evocation = game.summon_evocation(1, "succubus", "forge")
	player.revealed_spells.assign([RevealedSpellState.new(viatorium, true)])
	var before: int = target_room.get_instability_count()
	player.quick_spell = ReadySpellState.new(game.clone_spell_card(game.spell_database.get_spell("athanor_eruption")), true)
	check(game.cast_quick_spell(0, {"target_model_type": "evocation", "target_evocation": evocation}), "Athanor may target an Evocation")
	check(target_room.get_instability_count() == before + 1 and evocation.get_damage() == 2, "Enhancement must also place instability at an Evocation target")
	print("ATHANOR ENHANCEMENT: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
