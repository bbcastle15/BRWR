extends RefCounted

# Only primitive, permission-filtered data crosses the wire. Clients reuse the
# existing state classes as a read-only view; all rules execute on the host.
static func build(game, viewer: int) -> Dictionary:
	var state: Dictionary = game.get_beta_game_state(viewer)
	state["revision"] = game.input_revision
	state["turn_presentation"] = game.get_turn_presentation()
	state["card_presentation"] = game.card_presentation.duplicate(true)
	state["public_action_log"] = game.public_action_log.duplicate()
	state["damage_acknowledgements"] = game.damage_acknowledgements.duplicate(true)
	state["feedback_serial"] = game.table_feedback_serial
	state["feedback_events"] = game.table_feedback_events.duplicate(true)
	state["avatar"] = game.avatar.public_data() if game.avatar != null else {}
	state["active_schools"] = game.active_school_ids.duplicate()
	state["school_discards"] = {}
	for school_id in game.school_discards:
		# Discards are public; library order and hidden Spell identities stay private.
		state.school_discards[school_id] = game.get_school_discard(school_id).map(func(card): return card.id)
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
		state.players[i]["trophies"] = player.trophies.duplicate()
		state.players[i].mage["infectio_tokens"] = player.mage.infectio_tokens.duplicate()
		state.players[i].mage["jinxes"] = player.mage.jinxes.duplicate(true)
		for field in ["active_quests", "completed_quests"]:
			for j in player.get(field).size():
				state.players[i][field][j]["instance"] = player.get(field)[j].get_instance_id()
		for j in player.evocations.size():
			state.players[i].evocations[j]["name"] = player.evocations[j].evocation_name
			state.players[i].evocations[j]["board_number"] = player.evocations[j].board_number
			state.players[i].evocations[j]["damage_cubes"] = player.evocations[j].damage_cubes.duplicate()
			state.players[i].evocations[j]["stored_owner_cubes"] = game.get_evocation_stored_owner_cube_count(player.evocations[j])
		for active in player.active_spells:
			if active.active and game._is_ongoing_revealed_spell(active.get_side()):
				state.permanents.append({"owner": i, "slot": game._find_player_board_slot_for_spell(i, active.spell), "id": active.spell.id, "dark": active.use_dark_side, "room": str(active.context.get("target_room_id", "")), "target_player": active.target_player_index})
	for child in game.get_children():
		if not child.has_meta("hex_coord"):
			continue
		if child.get("room_id") != null:
			state.rooms.append({"id": child.room_id, "variant_id": child.get_art_id(), "coord": child.get_meta("hex_coord"), "flipped": child.flipped, "activated": child.activated_this_turn, "cubes": child.instability_cubes.duplicate(), "vastum": game.room_has_vastum(child.room_id)})
		elif child.has_meta("owner_index"):
			state.cells.append({"owner": child.get_meta("owner_index"), "coord": child.get_meta("hex_coord")})
	state["events"] = game.active_events.map(func(card): return "" if card == null else card.id)
	state["event_discard"] = game.event_discard.map(func(card): return card.id)
	state["event_counts"] = {}
	for moon in game.event_decks:
		state.event_counts[moon] = game.event_decks[moon].size()
	state["black_rose_cubes"] = game.get_node("EventBoard").black_rose_cube_count
	state["black_rose_trophies"] = game.black_rose_trophies.duplicate()
	state["quest_discard"] = game.quest_discard.map(func(card): return card.id)
	return state

static func apply(game, state: Dictionary) -> void:
	var power_board = game.get_node("PowerBoard")
	# Joining a running table positions markers directly; subsequent score
	# changes use the same animations as local games.
	power_board.instant_updates = not game.has_meta("received_network_snapshot")
	var initial_snapshot: bool = power_board.instant_updates
	game.suppress_placement_feedback = initial_snapshot
	game.set_meta("received_network_snapshot", true)
	var previous_revision: int = game.input_revision
	var previous_pending: Dictionary = game.pending_input.duplicate(true)
	var previous_result: Dictionary = game.final_result.duplicate(true)
	game.final_result = state.get("final_result", {}).duplicate(true)
	for field in ["black_rose_power", "crown_owner_id", "game_flow_active", "game_has_ended", "waiting_for_player_input"]:
		game.set(field, state[field])
	game.current_round = state.round
	game.current_moon = state.moon
	if game.avatar != null:
		game.avatar.network_public = state.get("avatar", {}).duplicate(true)
		game.avatar.commands_used = int(game.avatar.network_public.get("commands_used", 0))
		for moon in game.avatar.decks:
			game.avatar.decks[moon].clear()
			game.avatar.decks[moon].resize(int(game.avatar.network_public.get("deck_counts", {}).get(moon, 0)))
	game.current_phase = state.phase
	game.input_revision = state.revision
	game.network_turn_presentation = state.get("turn_presentation", {})
	game.public_action_log.assign(state.get("public_action_log", []))
	game.damage_acknowledgements = state.get("damage_acknowledgements", {}).duplicate(true)
	game.card_presentation = state.get("card_presentation", {}).duplicate()
	game.active_school_ids.assign(state.get("active_schools", game.active_school_ids))
	game.school_discards.clear()
	for school_id in state.get("school_discards", {}):
		game.school_discards[school_id] = []
		for card_id in state.school_discards[school_id]:
			game.school_discards[school_id].append(game.spell_database.get_spell(card_id))
	game.pending_input = state.pending_input
	game.network_slot_views = state.slots
	game.network_cast_tokens = state.cast_tokens
	# A lethal hit can be healed/cleared before the next snapshot. Replay the
	# public placement record, not a damage-count difference, exactly once.
	if not initial_snapshot and game.table_shell != null:
		for event in state.get("feedback_events", []):
			if int(event.get("serial", 0)) > game.table_feedback_serial:
				game.table_shell.receive_feedback(event)
	game.table_feedback_serial = int(state.get("feedback_serial", game.table_feedback_serial))
	game.player_board_spell_slots.clear()
	game.black_rose_trophies.assign(state.get("black_rose_trophies", []))
	game.quest_discard.clear()
	game.stored_evocation_owner_cubes.clear()
	for id in state.get("quest_discard", []):
		game.quest_discard.append(game.quest_database.get_quest(id))
	for data in state.players:
		var player = game.players[int(data.player_index)]
		player.trophies.assign(data.get("trophies", []))
		var old_health: int = player.mage.health
		for field in ["power", "school_id", "starting_grimoire_id", "starting_grimoire_name", "mage_id", "available_cubes", "available_physical_actions"]:
			player.set(field, data[field])
		player.player_name = data.name
		player.starved_cubes = int(data.get("starved_cubes", 0))
		player.mage.mage_id = data.mage_id
		for field in ["health", "strength", "speed", "in_cell", "room_id"]:
			player.mage.set(field, data.mage[field])
		player.mage.room_coord = Vector2i(data.mage.room_coord.q, data.mage.room_coord.r)
		player.mage.damage_cubes.assign(data.mage.damage_cubes)
		player.mage.destiny_tokens.assign(data.mage.get("destiny_tokens", []))
		player.mage.jinxes.assign(data.mage.get("jinxes", []))
		player.mage.infectio_tokens.assign(data.mage.get("infectio_tokens", []))
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
		for card in data.get("memories", []):
			var memory_spell = game.spell_database.get_spell(str(card.get("id", "")))
			if memory_spell != null:
				player.memories.append(memory_spell)
		# Backward compatibility with old snapshots that exposed only a count.
		if not data.has("memories"):
			player.memories.resize(data.memories_count)
		player.ready_spells.clear()
		for card in data.get("ready_spells", []):
			player.ready_spells.append(ReadySpellState.new(game.spell_database.get_spell(card.id), card.use_dark_side))
		var quick: Dictionary = data.get("quick_spell", {})
		player.quick_spell = null if quick.is_empty() else ReadySpellState.new(game.spell_database.get_spell(quick.id), quick.use_dark_side)
		player.revealed_spells.clear()
		var transformed: Dictionary = data.get("transformation", {})
		player.transformation = null if transformed.is_empty() else RevealedSpellState.new(game.spell_database.get_spell(transformed.id), false)
		for card in data.revealed_spells:
			player.revealed_spells.append(RevealedSpellState.new(game.spell_database.get_spell(card.id), card.use_dark_side))
		player.active_spells.clear()
		var old_quests: Dictionary = {}
		for quest in player.active_quests + player.completed_quests:
			old_quests[quest.get_meta("network_instance", -1)] = quest
		player.active_quests.clear()
		player.completed_quests.clear()
		for field in ["active_quests", "completed_quests"]:
			for card in data[field]:
				var quest: QuestState = old_quests.get(card.get("instance", -1))
				if quest == null or (quest.card == null and card.has("id")):
					quest = QuestState.new(game.quest_database.get_quest(str(card.get("id", ""))), player.player_index)
				quest.set_meta("network_instance", card.get("instance", -1))
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
				evocation.definition = game.evocation_database.get_evocation(card.id)
			for field in ["controller_id", "board_number", "room_id", "health", "strength", "speed"]:
				evocation.set(field, card[field])
			evocation.strength = int(card.get("base_strength", card.strength))
			evocation.damage_cubes.assign(card.damage_cubes)
			evocation.owner_id = int(card.owner_id)
			evocation.assigned_mage = int(card.get("assigned_mage", -1))
			evocation.assigned_slot = int(card.get("assigned_slot", 0))
			evocation.upgrades.assign(card.get("upgrades", []))
			evocation.stored_trophies.assign(card.get("stored_trophies", []))
			game.stored_evocation_owner_cubes[game._evocation_storage_key(evocation)] = int(card.get("stored_owner_cubes", 0))
			player.evocations.append(evocation)
		game.get_node("PowerBoard").set_player_power(player.player_index, player.power)
	for data in state.permanents:
		var active := ActiveSpellState.new(game.spell_database.get_spell(data.id), data.owner, data.dark)
		active.context["target_room_id"] = data.room
		active.target_player_index = int(data.get("target_player", -1))
		game.players[data.owner].active_spells.append(active)
		if not str(data.slot).is_empty():
			game._ensure_player_board_spell_slots(data.owner)[data.slot] = {"spell": active.spell, "state": "revealed", "use_dark_side": data.dark}
	game.room_id_by_coord.clear()
	game.vastum_room_state.clear()
	for data in state.rooms:
		var room = game.get_room_by_id(data.id)
		if room == null:
			continue
		var variant_id: String = str(data.get("variant_id", data.id))
		if room.get_art_id() != variant_id:
			var definition = game.get_room(variant_id)
			if definition != null and (variant_id == str(data.id) or preload("res://room_variants.gd").allows(game.get_room(str(data.id)), definition)):
				room.setup_room(preload("res://room_variants.gd").for_slot(game.get_room(str(data.id)), definition))
				room.room_color = game.get_room_color(str(definition.color))
		room.set_meta("hex_coord", data.coord)
		room.position = game.hex_to_pixel(data.coord)
		game.room_id_by_coord[data.coord] = data.id
		room.flipped = data.flipped
		room.activated_this_turn = data.activated
		if bool(data.get("vastum", false)):
			game.vastum_room_state[str(data.id)] = true
		if room.instability_cubes != data.cubes:
			var previous_count: int = room.instability_cubes.size()
			var prefix_unchanged: bool = data.cubes.size() >= previous_count and data.cubes.slice(0, previous_count) == room.instability_cubes
			if prefix_unchanged:
				for i in range(previous_count, data.cubes.size()):
					room.add_instability_cube(int(data.cubes[i]), not initial_snapshot)
				continue
			room.clear_instability()
			for i in data.cubes.size():
				room.add_instability_cube(int(data.cubes[i]), not initial_snapshot and i >= previous_count)
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
	power_board.instant_updates = false
	game.update_table_layout()
	game.refresh_model_tokens()
	game.suppress_placement_feedback = false
	game.refresh_vastum_tokens()
	game.refresh_all_player_boards()
	game._refresh_permanent_room_markers()
	if game.table_shell != null:
		if initial_snapshot: game.table_shell._observe(false)
		game.table_shell.sync_card_presentation()
	var pending_changed: bool = previous_pending != game.pending_input
	if previous_revision != game.input_revision or pending_changed or not game.waiting_for_player_input:
		game.player_input_resolved.emit(previous_pending)
		if game.waiting_for_player_input:
			game.player_input_requested.emit(game.pending_input)
	if not game.final_result.is_empty() and int(game.final_result.get("winner", -999)) != -999 and (previous_result != game.final_result or not game.waiting_for_player_input):
		game.game_over.emit(game.final_result)
