extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	for i in range(10):
		await process_frame
	var player = game.players[0]
	for id in ["bibliotheca", "observatory", "sanctuary"]:
		var room = game.get_room_by_id(id)
		room.flipped = false
		var before: int = player.active_quests.size() + player.completed_quests.size()
		game.activate_room(0, id)
		check(player.active_quests.size() + player.completed_quests.size() == before + 1, id + " must actually draw a Quest")
	var pleasures = game.get_room_by_id("pleasures_room")
	pleasures.flipped = true
	var quest_count: int = player.active_quests.size()
	game.activate_room(0, "pleasures_room")
	check(player.active_quests.size() == quest_count + 3, "Draw must finish before discard choice")
	check(game.pending_input.get("choice_kind") == "room_discard", "Discard Quests must request a choice")
	check(not game.submit_effect_choice(0, ["invalid"]), "Invalid discard must preserve pending choice")
	var discarded: int = game.quest_discard.size()
	game.submit_effect_choice(0, [game.pending_input.options[0].token, game.pending_input.options[1].token])
	check(player.active_quests.size() == quest_count + 1, "Pleasures Room must net one Quest")
	check(game.quest_discard.size() == discarded + 2, "Discarded Quests must enter Quest discard")
	var black_rose = game.get_room_by_id("black_rose")
	black_rose.flipped = true
	player.hand.clear()
	for i in range(4):
		player.hand.append(game.spell_database.spells["shared_torture"])
	var deck_before: int = game.forgotten_deck.size()
	game.activate_room(0, "black_rose")
	check(game.pending_input.get("choice_kind") == "room_discard", "Black Rose must ask for its three-card payment")
	game.submit_effect_choice(0, [game.pending_input.options[0].token, game.pending_input.options[1].token, game.pending_input.options[2].token])
	check(game.pending_input.get("choice_kind") == "room_forgotten_keep", "Rebuilt Black Rose must offer its two Forgotten cards")
	var selected = game.pending_effect_choice_values[game.pending_input.options[0].token]
	var removed: int = game.forgotten_removed_from_game.size()
	game.submit_effect_choice(0, [game.pending_input.options[0].token])
	check(player.hand.has(selected) and player.hand.size() == 2, "Only selected Forgotten card enters Hand")
	check(game.forgotten_deck.size() == deck_before - 2, "Draw-two consumes exactly two cards")
	check(game.forgotten_removed_from_game.size() == removed + 1, "Unchosen Forgotten leaves the game")
	var context := {"game": game, "player_index": 0, "caster_id": 0}
	var before: int = player.hand.size()
	game.room_effect_resolver.resolve_effect({"type": "draw_forgotten", "amount": 1}, context)
	check(player.hand.size() == before + 1, "Destroyed Black Rose primitive draws one Forgotten")
	game.forgotten_deck.clear()
	check(game.room_effect_resolver.resolve_effect({"type": "draw_forgotten_choose", "draw": 2, "keep": 1}, context), "Empty deck must not block")
	check(game.resolution_stack.is_empty() and not game.waiting_for_player_input, "Room resolutions must finish")
	print("ROOM DECKS PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
