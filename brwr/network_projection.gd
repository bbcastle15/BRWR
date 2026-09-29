extends RefCounted

# Only primitive, permission-filtered data crosses the wire. Clients reuse the
# existing state classes as a read-only view; all rules execute on the host.
static func build(game, viewer: int) -> Dictionary:
	var state: Dictionary = game.get_beta_game_state(viewer)
	state["revision"] = game.input_revision
	state["slots"] = {}
	state["cast_tokens"] = {}
	state["rooms"] = []
	state["cells"] = []
	state["permanents"] = []
	for i in game.players.size():
		state.slots[i] = {}
		state.cast_tokens[i] = {}
		for slot in ["Q", "I", "II", "III"]:
			state.slots[i][slot] = game.get_player_board_spell_slot_data(i, slot, viewer)
			state.cast_tokens[i][slot] = game.get_player_board_cast_token(i, slot, viewer)
		var player = game.players[i]
		for j in player.evocations.size():
			state.players[i].evocations[j]["name"] = player.evocations[j].evocation_name
			state.players[i].evocations[j]["board_number"] = player.evocations[j].board_number
			state.players[i].evocations[j]["damage_cubes"] = player.evocations[j].damage_cubes.duplicate()
		for active in player.active_spells:
			if active.active and active.get_side().get("target", "") in ["room", "area"] and game._is_ongoing_revealed_spell(active.get_side()):
				state.permanents.append({"owner": i, "slot": game._find_player_board_slot_for_spell(i, active.spell), "id": active.spell.id, "dark": active.use_dark_side, "room": str(active.context.get("target_room_id", ""))})
	for child in game.get_children():
		if not child.has_meta("hex_coord"):
			continue
		if child.get("room_id") != null:
			state.rooms.append({"id": child.room_id, "coord": child.get_meta("hex_coord"), "flipped": child.flipped, "activated": child.activated_this_turn, "cubes": child.instability_cubes.duplicate()})
		elif child.has_meta("owner_index"):
			state.cells.append({"owner": child.get_meta("owner_index"), "coord": child.get_meta("hex_coord")})
	state["events"] = game.active_events.map(func(card): return "" if card == null else card.id)
	state["event_discard"] = game.event_discard.map(func(card): return card.id)
	state["event_counts"] = {}
	for moon in game.event_decks:
		state.event_counts[moon] = game.event_decks[moon].size()
	state["black_rose_cubes"] = game.get_node("EventBoard").black_rose_cube_count
	return state

static func apply(game, state: Dictionary) -> void:
	var previous_revision: int = game.input_revision
	var previous_result: Dictionary = game.final_result.duplicate(true)
	game.final_result = state.get("final_result", {}).duplicate(true)
	for field in ["black_rose_power", "crown_owner_id", "game_flow_active", "game_has_ended", "waiting_for_player_input"]:
		game.set(field, state[field])
	game.current_round = state.round
	game.current_moon = state.moon
	game.current_phase = state.phase
	game.input_revision = state.revision
	game.pending_input = state.pending_input
	game.network_slot_views = state.slots
	game.network_cast_tokens = state.cast_tokens
	game.player_board_spell_slots.clear()
	for data in state.players:
		var player = game.players[int(data.player_index)]
		var old_health: int = player.mage.health
		for field in ["power", "school_id", "starting_grimoire_id", "starting_grimoire_name", "mage_id", "available_cubes", "available_physical_actions"]:
			player.set(field, data[field])
		player.player_name = data.name
		player.mage.mage_id = data.mage_id
		for field in ["health", "strength", "speed", "in_cell", "room_id"]:
			player.mage.set(field, data.mage[field])
		player.mage.room_coord = Vector2i(data.mage.room_coord.q, data.mage.room_coord.r)
		player.mage.damage_cubes.assign(data.mage.damage_cubes)
		if old_health != player.mage.health:
			game.player_boards[player.player_index].create_damage_track()
		player.hand.clear()
		if data.has("hand"):
			for card in data.hand:
				player.hand.append(game.spell_database.get_spell(card.id))
		else:
			player.hand.resize(data.hand_count) # Count only; no opposing identity.
		player.grimoire.clear()
		player.grimoire.resize(data.grimoire_count)
		player.memories.clear()
		player.memories.resize(data.memories_count)
		player.ready_spells.clear()
		for card in data.get("ready_spells", []):
			player.ready_spells.append(ReadySpellState.new(game.spell_database.get_spell(card.id), card.use_dark_side))
		var quick: Dictionary = data.get("quick_spell", {})
		player.quick_spell = null if quick.is_empty() else ReadySpellState.new(game.spell_database.get_spell(quick.id), quick.use_dark_side)
		player.revealed_spells.clear()
		for card in data.revealed_spells:
			player.revealed_spells.append(RevealedSpellState.new(game.spell_database.get_spell(card.id), card.use_dark_side))
		player.active_spells.clear()
		player.active_quests.clear()
		player.completed_quests.clear()
		for field in ["active_quests", "completed_quests"]:
			for card in data[field]:
				var quest := QuestState.new(game.quest_database.get_quest(str(card.get("id", ""))), player.player_index)
				for key in ["revealed", "completed", "solved", "progress"]:
					quest.set(key, card.get(key, 0 if key == "progress" else false))
				player.get(field).append(quest)
		var old_evocations: Dictionary = {}
		for evocation in player.evocations:
			old_evocations[evocation.board_number] = evocation
		player.evocations.clear()
		for card in data.evocations:
			var evocation = old_evocations.get(card.board_number)
			if evocation == null or evocation.evocation_id != card.id:
				evocation = EvocationState.new(card.id, card.name, card.archetype, card.health, card.strength, card.speed, card.owner_id)
			for field in ["controller_id", "board_number", "room_id", "health", "strength", "speed"]:
				evocation.set(field, card[field])
			evocation.damage_cubes.assign(card.damage_cubes)
			player.evocations.append(evocation)
		game.get_node("PowerBoard").set_player_power(player.player_index, player.power)
	for data in state.permanents:
		var active := ActiveSpellState.new(game.spell_database.get_spell(data.id), data.owner, data.dark)
		active.context["target_room_id"] = data.room
		game.players[data.owner].active_spells.append(active)
		game._ensure_player_board_spell_slots(data.owner)[data.slot] = {"spell": active.spell, "state": "revealed", "use_dark_side": data.dark}
	game.room_id_by_coord.clear()
	for data in state.rooms:
		var room = game.get_room_by_id(data.id)
		room.set_meta("hex_coord", data.coord)
		room.position = game.hex_to_pixel(data.coord)
		game.room_id_by_coord[data.coord] = data.id
		room.flipped = data.flipped
		room.activated_this_turn = data.activated
		if room.instability_cubes != data.cubes:
			room.clear_instability()
			for owner in data.cubes:
				room.add_instability_cube(owner)
	for data in state.cells:
		game.player_cell_coords[data.owner] = data.coord
		for child in game.get_children():
			if child.get_meta("owner_index", -1) == data.owner:
				child.set_meta("hex_coord", data.coord)
				child.position = game.hex_to_pixel(data.coord)
	game.active_events.clear()
	for id in state.events:
		game.active_events.append(game.event_database.get_event(id) if id != "" else null)
	game.event_discard.clear()
	for id in state.event_discard:
		game.event_discard.append(game.event_database.get_event(id))
	for moon in state.event_counts:
		game.event_decks[moon].clear()
		game.event_decks[moon].resize(state.event_counts[moon])
	game.get_node("EventBoard").set_black_rose_cube_count(state.black_rose_cubes)
	game.get_node("EventBoard").refresh_event_slots()
	game.get_node("PowerBoard").set_black_rose_power(game.black_rose_power)
	game.update_table_layout()
	game.refresh_model_tokens()
	game.refresh_all_player_boards()
	game._refresh_permanent_room_markers()
	if previous_revision != game.input_revision or not game.waiting_for_player_input:
		game.player_input_resolved.emit({})
		if game.waiting_for_player_input:
			game.player_input_requested.emit(game.pending_input)
	if not game.final_result.is_empty() and int(game.final_result.get("winner", -999)) != -999 and (previous_result != game.final_result or not game.waiting_for_player_input):
		game.game_over.emit(game.final_result)
