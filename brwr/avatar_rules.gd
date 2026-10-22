class_name AvatarRules
extends RefCounted

const DEFINITIONS := "res://data/avatars.json"
const COMMANDS := "res://data/avatar_commands.json"
const EVENTS := "res://data/avatar_events.json"

static func definitions() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(DEFINITIONS))

static func available() -> Array:
	return definitions().filter(func(item): return bool(item.get("implemented", false)))

static func is_avatar(game, index: int) -> bool:
	return game.avatar != null and game.avatar.player_index == index

static func human_order(game) -> Array[int]:
	var result: Array[int] = []
	for index in game.get_play_order():
		if not is_avatar(game, index):
			result.append(index)
	return result

static func cube_owner(game, index: int) -> int:
	return -1 if is_avatar(game, index) else index

static func setup(game) -> void:
	if game.avatar_selection.is_empty():
		return
	var id: String = str(game.avatar_selection.get("id", ""))
	var catalog: Array = definitions()
	if id == "random":
		var choices := available()
		if choices.is_empty(): return
		id = str(choices[game.rng.randi_range(0, choices.size() - 1)].id)
	var found := catalog.filter(func(item): return item.id == id)
	if found.is_empty(): return
	game.avatar = AvatarState.new()
	var state: AvatarState = game.avatar
	state.game = game
	state.player_index = game.players.size() - 1
	state.definition = found[0].duplicate(true)
	state.difficulty = str(game.avatar_selection.get("difficulty", "apprentice"))
	var player: PlayerState = game.players[state.player_index]
	player.avatar = state
	player.player_name = str(state.definition.name)
	player.mage_id = id
	player.color = Color(0.13, 0.13, 0.15)
	player.mage = MageState.new(id, int(state.definition.health), int(state.definition.strength), int(state.definition.speed))
	player.available_physical_actions = 0
	player.personal_spell_id = ""
	for moon in [1, 2, 3]:
		var deck: Array[SpellCardState] = []
		state.decks[moon] = deck
	for entry in JSON.parse_string(FileAccess.get_file_as_string(COMMANDS)):
		if not str(entry.id).begins_with(str(state.definition.command_prefix)): continue
		var side: Dictionary = {}
		for section in entry.sections:
			if section.kind == "spell":
				side = section.duplicate(true)
				break
		var card := SpellCardState.new(entry.id, entry.name, "", side, side, 1)
		card.avatar_command = entry.duplicate(true)
		game.spell_database.spells[card.id] = card
		state.decks[int(entry.moon)].append(card)
	for deck in state.decks.values(): game.shuffle_with_rng(deck)
	# Replace the Event DB/decks, rather than mixing Avatar and ordinary Events.
	game.event_database.load_database(EVENTS)
	game.create_event_decks()

static func place_at_setup(game) -> void:
	if game.avatar == null: return
	var mage: MageState = game.players[game.avatar.player_index].mage
	mage.room_id = str(game.avatar.definition.setup_room)
	mage.room_coord = game.room_id_to_coord(mage.room_id)
	mage.in_cell = false

static func immune_to_damage(game, attacker: int, target: int, action: String) -> bool:
	return is_avatar(game, target) and (cube_owner(game, attacker) == -1 or action == "event")

static func choose(game, frame: Dictionary, key: String, options: Array, prompt: String, kind: String = "model_target") -> bool:
	if frame.has(key): return true
	if options.is_empty():
		frame[key] = null
		return true
	game.request_effect_choice(game.crown_owner_id, kind, frame, key, options, 1, 1, "Choice of the Crown · " + prompt)
	return false

static func distance(game, origin: String, target: String) -> int:
	return game.get_hex_distance(game.room_id_to_coord(origin), game.room_id_to_coord(target))

static func model_options(game, range_value: int = -1, origin: String = "", mages_only: bool = true) -> Array:
	var result: Array = []
	if origin.is_empty(): origin = game.players[game.avatar.player_index].mage.room_id
	for p in game.players:
		if p.avatar == null and not p.mage.in_cell and not p.mage.is_defeated() and (range_value < 0 or distance(game, origin, p.mage.room_id) <= range_value):
			result.append({"token": "mage:%d" % p.player_index, "value": {"player_index": p.player_index},
				"player_index": p.player_index, "name": p.player_name, "room_id": p.mage.room_id})
		if not mages_only:
			for ev in p.evocations:
				if ev.archetype == "equipment" or ev.assigned_mage >= 0 or ev.is_defeated() or game.get_evocation_controller_id(ev) == game.avatar.player_index: continue
				if range_value >= 0 and distance(game, origin, ev.room_id) > range_value: continue
				result.append({"token": "evocation:%d" % ev.get_instance_id(), "value": {"evocation": ev},
					"owner_id": p.player_index, "evocation_index": p.evocations.find(ev), "name": ev.get_display_name(), "room_id": ev.room_id})
	return result

static func room_options(game, range_value: int = -1, origin: String = "") -> Array:
	if origin.is_empty(): origin = game.players[game.avatar.player_index].mage.room_id
	var result: Array = []
	for room_id in game.room_id_by_coord.values():
		if range_value >= 0 and distance(game, origin, room_id) > range_value: continue
		var room = game.get_room_by_id(room_id)
		result.append({"token": "room:" + room_id, "value": str(room_id), "room_id": str(room_id), "name": room.room_name})
	return result

static func _metric(game, option: Dictionary, criterion: String, origin: String) -> int:
	var value = option.value
	if value is String:
		var room = game.get_room_by_id(value)
		if criterion == "most_instability": return room.get_instability_count()
		if criterion == "nearest": return -distance(game, origin, value)
		# FAQ p.2: exclude the Avatar itself AND its Evocations from these counts.
		return model_options(game, 0, value, criterion == "most_mages").size()
	var ev: EvocationState = value.get("evocation")
	var index: int = ev.owner_id if ev != null else int(value.get("player_index", -1))
	var mage: MageState = game.players[index].mage
	match criterion:
		"nearest": return -distance(game, origin, ev.room_id if ev != null else mage.room_id)
		"most_damage": return ev.get_damage() if ev != null else mage.get_damage()
		"most_black_rose_damage": return ev.damage_cubes.count(-1) if ev != null else mage.get_damage_from(-1)
		"most_power": return game.players[index].power
		"most_trophies": return game.players[index].trophies.size()
	return 0

static func rank(game, options: Array, criteria: Array, origin: String = "") -> Array:
	if origin.is_empty(): origin = game.players[game.avatar.player_index].mage.room_id
	var result := options.duplicate()
	for criterion in criteria:
		if result.size() <= 1: break
		var best := -2147483648
		for option in result: best = maxi(best, _metric(game, option, criterion, origin))
		result = result.filter(func(option): return _metric(game, option, criterion, origin) == best)
	return result

static func priority(game, options: Array, number: int, origin: String = "") -> Array:
	return rank(game, options, game.avatar.definition.priorities.get(str(number), []), origin)

static func begin_activation(game, additional: bool = false, resume_phase: bool = true) -> bool:
	if game.avatar == null: return false
	var state: AvatarState = game.avatar
	if not additional and not state.can_activate(): return false
	return game.queue_resolution({"type": "avatar_activation", "additional": additional,
		"on_complete": "advance_action_phase" if resume_phase else ""})

static func process_activation(game, frame: Dictionary) -> bool:
	if bool(frame.get("started", false)): return true
	frame["started"] = true
	var state: AvatarState = game.avatar
	var player: PlayerState = game.players[state.player_index]
	if not bool(frame.get("additional", false)) and player.mage.in_cell and state.definition.skill == "dominion":
		# Dominion is only checked at the START of an activation, not a reaction.
		game.place_mage_in_room_direct(state.player_index, str(state.definition.setup_room))
		return true
	var card := state.draw_command(bool(frame.get("additional", false)))
	if card == null: return true
	game.queue_resolution({"type": "avatar_command", "card": card, "sections": card.avatar_command.sections,
		"index": 0, "context": {}})
	return false

static func process_command(game, frame: Dictionary) -> bool:
	if not bool(frame.get("revealed", false)):
		frame["revealed"] = true
		var card: SpellCardState = frame.card
		if card.avatar_command.sections.any(func(s): return s.kind == "spell"):
			game.players[game.avatar.player_index].revealed_spells.append(RevealedSpellState.new(card, false))
			var event := GameEvent.new("spell_revealed")
			event.source_model_type = "mage"
			event.source_player_index = game.avatar.player_index
			event.source_room_id = game.players[game.avatar.player_index].mage.room_id
			event.data["spell_type"] = card.light_side.get("type", "")
			game.queue_resolution({"type": "game_event", "event": event})
		return false
	var index: int = int(frame.get("index", 0))
	var sections: Array = frame.sections
	if index >= sections.size(): return true
	frame["index"] = index + 1
	var section: Dictionary = sections[index]
	if game.players[game.avatar.player_index].mage.in_cell and section.kind == "spell": return false
	if game.players[game.avatar.player_index].mage.in_cell and section.kind == "physical" and not section.effects.any(func(e): return e.type == "move_toward"): return false
	game.queue_resolution({"type": "avatar_section", "card": frame.card, "section": section,
		"reaction": frame.get("reaction", false), "event": frame.get("event"), "context": {}, "stage": "target"})
	return false

static func append_reaction(game, event: GameEvent, triggered: Array) -> void:
	if game.avatar == null or not game.avatar.can_activate(): return
	var state: AvatarState = game.avatar
	var card: SpellCardState = state.active_deck().back()
	var reaction: Dictionary = card.avatar_command.get("reaction", {})
	if reaction.is_empty() or "protection" in event.suppressed_trigger_types: return
	var matches := false
	var target: bool = event.target_model_type == "mage" and event.target_player_index == state.player_index
	match str(reaction.trigger):
		"damage": matches = event.event_type == "damage_about_to_be_inflicted" and target and event.amount > 0
		"suffered_damage": matches = event.event_type == "damage_inflicted" and target and event.amount > 0
		"combat_spell":
			matches = event.event_type == "spell_effect_about_to_resolve" and str(event.get_meta("source_spell_type", "")) == "combat" and state.player_index in event.get_meta("affected_player_indices", [])
	if not matches or cube_owner(game, event.source_player_index) == -1: return
	# The ordinary trigger window supplies play order and handles nesting. The
	# face is not added to active_spells: only the current top card is armed.
	var proxy := SpellCardState.new(card.id, card.card_name, "", {"type": "protection"}, {})
	var active := ActiveSpellState.new(proxy, state.player_index, false)
	active.context["avatar_command"] = card
	triggered.append({"active_spell": active, "event": event})

static func trigger_reaction(game, active: ActiveSpellState, event: GameEvent) -> bool:
	var card: SpellCardState = active.context.get("avatar_command")
	if card == null or not game.avatar.can_activate() or game.avatar.active_deck().back() != card: return true
	game.avatar.draw_command()
	var reaction: Dictionary = card.avatar_command.reaction.duplicate(true)
	reaction["kind"] = "reaction"
	return game.queue_resolution({"type": "avatar_command", "card": card, "sections": [reaction],
		"reaction": true, "event": event, "index": 0})

static func process_cleanup(game, frame: Dictionary) -> bool:
	var player: PlayerState = game.players[game.avatar.player_index]
	if not bool(frame.get("jinxes", false)):
		frame["jinxes"] = true
		for jinx in player.mage.jinxes.duplicate(): ForgottenAttachments.progress(game, player.player_index, jinx)
		return false
	if not bool(frame.get("assigned_done", false)):
		var options: Array = []
		for ev in player.evocations:
			if ev.assigned_mage == player.player_index:
				options.append({"token": "assigned:%d" % ev.get_instance_id(), "value": ev, "name": ev.get_display_name()})
		if not choose(game, frame, "assigned", options, "Remove one assigned Evocation."): return false
		frame["assigned_done"] = true
		if frame.assigned != null: AvatarEffects.remove_evocation(game, frame.assigned)
		return false
	game.avatar.recycle_memories()
	return true

static func prepare_evocation(game, frame: Dictionary) -> bool:
	var ev: EvocationState = frame.get("evocation")
	if ev == null or not ForgottenEvocations.can_activate(game, ev):
		frame["avatar_planned"] = true
		return true
	if ForgottenEvocations.extended(game, ev):
		# Extended card abilities retain their existing pipeline; unresolved
		# choices go to the Crown through request_effect_choice.
		frame["avatar_planned"] = true
		return true
	var plans: Array = game._beta_evocation_activation_plans(ev, game.avatar.player_index)
	var attacks: Array = plans.filter(func(plan): return not plan.get("target", {}).is_empty())
	var mages: Array = attacks.filter(func(plan): return plan.target.target_model_type == "mage")
	if not mages.is_empty(): attacks = mages
	if not attacks.is_empty():
		var options: Array = []
		for plan in attacks:
			var target: Dictionary = plan.target
			var value: Dictionary = {"player_index": int(target.target_player_index)}
			if target.target_model_type == "evocation":
				value = {"evocation": game.get_evocation_by_owner_index(int(target.target_evocation_owner_id), int(target.target_evocation_index))}
			var token: String = "mage:%d" % value.player_index if value.has("player_index") else "evocation:%d" % value.evocation.get_instance_id()
			if not options.any(func(o): return o.token == token): options.append({"token": token, "value": value, "name": target.name})
		options = rank(game, options, ["nearest", "most_damage", "most_power"], ev.room_id)
		if not choose(game, frame, "ai_target", options, "Choose the target for " + ev.get_display_name()): return false
		plans = attacks.filter(func(plan):
			if frame.ai_target.has("player_index"): return int(plan.target.target_player_index) == int(frame.ai_target.player_index)
			return game.get_evocation_by_owner_index(int(plan.target.target_evocation_owner_id), int(plan.target.target_evocation_index)) == frame.ai_target.evocation)
		# Do not move away again after attacking. Equivalent paths remain a
		# genuine Choice of the Crown, rather than an arbitrary array-order tie.
		var shortest := 999
		for plan in plans: shortest = mini(shortest, plan.path.size())
		plans = plans.filter(func(plan): return plan.path.size() == shortest)
	var choices: Array = []
	for plan in plans:
		choices.append({"token": "activation_plan:%d" % choices.size(), "value": plan.context,
			"path": plan.path.duplicate(),
			"name": str(plan.label) + (" · " + " → ".join(plan.path) if not plan.path.is_empty() else "")})
	if not choose(game, frame, "ai_plan", choices, "Choose the path for " + ev.get_display_name(), "evocation_activation_plan"): return false
	if not frame.has("context"): frame["context"] = {}
	if frame.ai_plan is Dictionary: frame.context.merge(frame.ai_plan, true)
	frame["avatar_planned"] = true
	return true
