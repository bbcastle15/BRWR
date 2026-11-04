extends "res://docs/handoff-2026-10-18/checks/schools.gd"

func _initialize() -> void:
	call_deferred("run")
	create_timer(180).timeout.connect(func(): push_error("Codex Mage check timeout"); quit(2))

func run() -> void:
	game = await make_game(4)
	var ids: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/mages.json")).keys()
	var tested := 0
	for id in ids:
		var data: Dictionary = game.mage_database.get_mage_data(id)
		var card: SpellCardState = game.spell_database.get_spell(str(data.personal_spell_id))
		if card == null or card.school_id != "personal" or id == "hyperion": continue
		for dark in [false,true]:
			reset_case()
			game.players[0].mage.damage_cubes.assign([1,1,2,2])
			var ev = game.summon_evocation(1,"templarii","arena")
			game.summon_evocation(0,"cadaver","arena")
			game.players[0].memories.clear()
			for i in 3: game.players[0].memories.append(game.spell_database.get_spell("litany"))
			var side: Dictionary = card.get_side(dark)
			var ctx: Dictionary = {}
			match str(side.target):
				"room": ctx = {"target_room_id":"arena"}
				"model", "mage": ctx = {"target_model_type":"mage", "target_player_index":1}
				"evocation": ctx = {"target_model_type":"evocation", "target_evocation":ev}
			print("MAGE CASE ",id," ",dark)
			expect(game.cast_ready_spell_state(0,ReadySpellState.new(card,dark),ctx),"Cast "+id)
			await drive()
			expect(game.resolution_stack.is_empty(),"No stall "+id)
			tested += 1
	print("CODEX MAGE SMOKE: %d sides, %d checks, %d failures" % [tested,checks,failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
