extends SceneTree
var game
var checks := 0
var failures: Array[String] = []
func _initialize():
	call_deferred("run")
	create_timer(90).timeout.connect(func(): push_error("Avatar test timeout"); quit(2))
func expect(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func settle():
	for i in 4: await process_frame
func drain():
	for i in 500:
		if not game.card_presentation.is_empty(): game.dismiss_card_presentation()
		if game.waiting_for_player_input:
			var pending: Dictionary = game.pending_input
			if pending.type != "effect_choice":
				push_error("Unexpected input " + str(pending)); return
			var choices: Array = pending.board_options if pending.get("board_only", false) else pending.options
			var choice = choices[0]
			if not game.submit_effect_choice(pending.player_index, [choice.token]):
				push_error("Rejected " + str(pending)); return
		game.process_resolution_stack()
		await process_frame
		if game.resolution_stack.is_empty() and not game.waiting_for_player_input: return
	push_error("Unfinished stack " + str(game.resolution_stack))
func run():
	game = load("res://game.tscn").instantiate()
	game.beta_force_fullscreen = false
	game.auto_start_game_flow = false
	game.network_client = true
	game.player_count = 3
	game.avatar_selection = {"id":"possessed", "difficulty":"apprentice"}
	root.add_child(game)
	while game.beta_hud == null: await process_frame
	await settle()
	game.network_client = false
	game.game_flow_active = false
	game.current_phase = game.PHASE_ACTION
	game.local_viewer_index = 0
	expect(game.avatar != null, "Avatar configured")
	expect(game.players[2].mage.room_id == "black_rose", "Avatar starts in Black Rose Room")
	expect(game.players[2].mage.health == 12, "Possessed has 12 Health")
	for moon in [1,2,3]: expect(game.avatar.decks[moon].size() == 10, "10 commands Moon " + str(moon))
	expect(game.event_decks[1].size() == 5, "Five events per Moon")
	expect(game.crown_owner_id != 2, "Avatar never starts with Crown")
	game.add_player_power(2, 3)
	expect(game.players[2].power == 3 and game.black_rose_power == 3, "Shared Black Rose Power")
	var cubes: int = game.players[2].available_cubes
	game.take_owner_cubes(2, 1)
	expect(game.players[2].available_cubes == cubes - 1, "Shared Black Rose cubes")
	game.return_owner_cubes(2,1)
	for p in game.players:
		p.mage.in_cell = false
		p.mage.room_id = "black_rose"
		p.mage.room_coord = game.room_id_to_coord("black_rose")
	game.deal_damage(-1, 2, 2, "spell")
	await drain()
	expect(game.players[2].mage.get_damage() == 0, "Avatar immune to Black Rose damage")
	for card_data in JSON.parse_string(FileAccess.get_file_as_string(AvatarRules.COMMANDS)):
		game.avatar.commands_used = 0
		game.current_moon = int(card_data.moon)
		var card: SpellCardState = game.spell_database.spells[card_data.id]
		print("COMMAND: ", card.id)
		game.queue_resolution({"type":"avatar_command", "card":card, "sections":card_data.sections, "index":0})
		await drain()
		expect(game.resolution_stack.is_empty(), "Resolved " + card.id)
	print("AVATAR CHECKS: ", checks, " FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)
