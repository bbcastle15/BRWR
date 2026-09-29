extends SceneTree

# Central icons checked against the card images in assets/spells.
const ICON_CARDS = [
	"albify", "grim_torment", "ineluctable_pain", "liquid_fire", "pain_mark",
	"purifying_aludel", "silver_of_the_sages", "viatorium_spagyricum",
	"visceral_fire", "cross_and_delight"
]
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func reset_room(game, room) -> void:
	for owner in room.instability_cubes:
		game.return_owner_cubes(owner, 1)
	room.clear_instability()

func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(10):
		await process_frame
	var player = game.players[0]
	player.mage.in_cell = false
	player.mage.room_id = game.player_entrance_room_ids[0]
	var room = game.get_room_by_id(player.mage.room_id)
	var initial_pool: int = player.available_cubes
	for spell in game.spell_database.spells.values():
		if spell.school_id not in ["agony", "alchemy"]:
			continue
		var expected: bool = ICON_CARDS.has(spell.id)
		check(spell.has_instability() == expected, "Central icon data mismatch: " + spell.id)
		for dark in [false, true]:
			game.resolve_spell_reveal_instability(0, spell, dark)
			check(room.get_instability_count() == int(expected), "Wrong Instability count: " + spell.id)
			check(room.instability_cube_nodes.size() == int(expected), "Missing visual cube: " + spell.id)
			check(player.available_cubes == initial_pool - int(expected), "Wrong pool consumption: " + spell.id)
			reset_room(game, room)
	# Exercise the actual Quick and Ready cast paths, including full resolution.
	for source in ["quick", "ready"]:
		var spell = game.spell_database.spells["ineluctable_pain"]
		var ready := ReadySpellState.new(spell, true)
		if source == "quick":
			player.quick_spell = ready
		else:
			player.ready_spells.append(ready)
		game.queue_resolution({"type": "spell_cast", "player_index": 0, "ready_spell": ready, "source": source})
		check(room.get_instability_by_owner(0) == 1, source + " cast must place exactly one owned cube")
		check(game.resolution_stack.is_empty(), "Cast must finish without repeating Instability")
		player.active_spells.clear()
		reset_room(game, room)
	# Stop before effects to distinguish the caster's room from the target room.
	var target_room_id: String = game._beta_adjacent_room_ids(room.room_id)[0]
	var target_room = game.get_room_by_id(target_room_id)
	game.players[1].mage.in_cell = false
	game.players[1].mage.room_id = target_room_id
	player.quick_spell = ReadySpellState.new(game.spell_database.spells["grim_torment"], false)
	game.processing_resolution_stack = true
	game.process_spell_cast_resolution({"player_index": 0, "ready_spell": player.quick_spell,
		"source": "quick", "context": {"target_player_index": 1, "target_model_type": "mage"}})
	check(room.get_instability_count() == 1 and target_room.get_instability_count() == 0,
		"Central icon must place in the caster's room before damage resolves")
	game.resolution_stack.clear()
	reset_room(game, room)
	# Hidden protections place their icon only when revealed by the trigger.
	player.quick_spell = ReadySpellState.new(game.spell_database.spells["silver_of_the_sages"], false)
	game.process_spell_cast_resolution({"player_index": 0, "ready_spell": player.quick_spell, "source": "quick"})
	check(room.get_instability_count() == 0, "Arming a hidden protection must not place its icon")
	game.process_trigger_spell_resolution({"active_spell": player.active_spells[0], "event": GameEvent.new("damage_about_to_be_inflicted")})
	check(room.get_instability_count() == 1, "Revealing a protection must place its icon")
	game.resolution_stack.clear()
	game.processing_resolution_stack = false
	reset_room(game, room)
	# Existing room/pool limits must still apply.
	var spell = game.spell_database.spells["ineluctable_pain"]
	player.mage.in_cell = true
	game.resolve_spell_reveal_instability(0, spell)
	check(room.get_instability_count() == 0, "Cell must not receive Instability")
	player.mage.in_cell = false
	room.flipped = true
	game.resolve_spell_reveal_instability(0, spell)
	check(room.get_instability_count() == 0, "Rebuilt room must not receive Instability")
	room.flipped = false
	game.place_instability(0, room.room_id, room.get_instability_resistance())
	var pool_after_fill: int = player.available_cubes
	game.resolve_spell_reveal_instability(0, spell)
	check(room.get_instability_count() == room.get_instability_resistance(), "Full room must not overflow")
	check(player.available_cubes == pool_after_fill, "Full room must not consume another cube")
	reset_room(game, room)
	player.available_cubes = 0
	game.resolve_spell_reveal_instability(0, spell)
	check(room.get_instability_count() == 0, "Empty pool must not create cubes")
	print("SPELL INSTABILITY PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
