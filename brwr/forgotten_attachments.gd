class_name ForgottenAttachments
extends RefCounted

static var definitions: Dictionary = {}

static func database() -> Dictionary:
	if definitions.is_empty():
		definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/attachments.json"))
	return definitions

static func definition(kind: String, id: String) -> Dictionary:
	for data in database().get(kind, []):
		if data.id == id:
			return data
	return {}

static func available(game, kind: String) -> Array:
	var result: Array = []
	for data in database().get(kind, []):
		var count: int = int(data.copies)
		for player in game.players:
			if kind == "jinxes":
				for assigned in player.mage.jinxes:
					if assigned.id == data.id:
						count -= 1
			else:
				for ev in player.evocations:
					count -= ev.upgrades.count(str(data.id))
		for i in maxi(0, count):
			result.append(str(data.id))
	return result

static func abilities(ev: EvocationState) -> Array:
	var result: Array = []
	for id in ev.upgrades:
		result.append_array(definition("upgrades", id).get("abilities", []))
	return result

static func can_receive_upgrade(game, ev: EvocationState) -> bool:
	return ev != null and game.is_evocation_in_play(ev) and not ev.archetype in ["equipment", "pestis", "nightmare"] and not bool(ev.definition.get("fixed_stats", false))

static func assign_upgrade(game, caster: int, ev: EvocationState, context: Dictionary, effect: Dictionary = {}) -> bool:
	context["upgrade_assigned"] = false
	if not can_receive_upgrade(game, ev):
		return true
	if not context.has("drawn_upgrade"):
		var deck := available(game, "upgrades")
		deck = deck.filter(func(id): return not ev.upgrades.has(id))
		if effect.has("id"): deck = deck.filter(func(id): return id == effect.id)
		if deck.is_empty():
			return true
		if bool(effect.get("choice", false)):
			var options: Array = []
			for candidate in deck:
				if not options.any(func(o): return o.value == candidate):
					options.append({"token": "upgrade:" + candidate, "value": candidate, "id": candidate, "card_kind": "upgrades", "name": definition("upgrades", candidate).name})
			if not DruidicRules.choose(game, caster, context, "drawn_upgrade", options, "Choose an Upgrade."): return false
		else:
			game.shuffle_with_rng(deck)
			context["drawn_upgrade"] = str(deck.back())
	var id: String = str(context.drawn_upgrade)
	var capacity: int = int(ForgottenEvocations.ability(game, ev, "upgrade_capacity").get("amount", 1))
	if ev.upgrades.size() >= capacity:
		var options: Array = [{"token": "discard_new", "value": id, "name": "Discard " + str(definition("upgrades", id).name)}]
		for old in ev.upgrades:
			options.append({"token": "upgrade:" + old, "value": old, "name": "Discard " + str(definition("upgrades", old).name)})
		if not DruidicRules.choose(game, ev.owner_id if ev.owner_id >= 0 else caster, context, "discard_upgrade", options, "Choose the Upgrade to discard."):
			return false
		var discard: String = str(context.get("discard_upgrade", id))
		context.erase("discard_upgrade")
		if discard == id:
			context.erase("drawn_upgrade")
			return true
		ev.upgrades.erase(discard)
	ev.upgrades.append(id)
	context["upgrade_assigned"] = true
	context.erase("drawn_upgrade")
	recompute_stats(game, ev)
	context["stored_target_strength"] = game.get_evocation_effective_strength(ev)
	game.refresh_all_player_boards()
	return true

static func recompute_stats(game, ev: EvocationState) -> void:
	var base: Dictionary = game.evocation_database.get_evocation(ev.evocation_id)
	ev.health = int(base.health)
	ev.strength = int(base.strength)
	ev.speed = int(base.speed)
	for item in game.get_evocation_abilities(ev):
		if item.type == "stats":
			ev.health += int(item.get("health", 0))
			ev.strength += int(item.get("strength", 0))
			ev.speed += int(item.get("speed", 0))
		elif item.type == "health_bonus_if_upgraded" and not ev.upgrades.is_empty():
			ev.health += int(item.amount)
	ev.speed = maxi(0, ev.speed)

static func assign_jinx(game, caster: int, target: int, context: Dictionary, effect: Dictionary = {}) -> bool:
	if target < 0 or target >= game.players.size() or DeathEffectResolver.ignores(context, target):
		return true
	var mage = game.players[target].mage
	# An attack resolves defeat before its subsequent ability (FAQ p.5).
	if mage == null or (mage.in_cell and target != caster):
		return true
	if not context.has("assigned_jinx"):
		var deck := available(game, "jinxes")
		if effect.has("id"): deck = deck.filter(func(id): return id == effect.id)
		if deck.is_empty():
			return true
		var id: String = ""
		if bool(effect.get("choice", false)):
			var options: Array = []
			for candidate in deck:
				if not mage.jinxes.any(func(j): return j.id == candidate) and not options.any(func(o): return o.value == candidate):
					options.append({"token": "jinx:" + candidate, "value": candidate, "id": candidate, "card_kind": "jinxs", "name": definition("jinxes", candidate).name})
			if options.is_empty(): return true
			if not DruidicRules.choose(game, caster, context, "school_jinx", options, "Choose a Jinx to assign."): return false
			id = str(context.school_jinx)
			context.erase("school_jinx")
		else:
			game.shuffle_with_rng(deck)
			id = str(deck.back())
		# A duplicate name cannot be assigned (Codex p.109); it goes back.
		for assigned in mage.jinxes:
			if assigned.id == id:
				return true
		context["jinx_was_vulnerable"] = mage.jinxes.any(func(j): return j.id == "vulnerability")
		mage.jinxes.append({"id": id, "progress": 0})
		context["assigned_jinx"] = id
		var item := definition("jinxes", id)
		print("Player ", target + 1, " assigned Jinx: ", item.name)
		game.queue_resolution({"type": "jinx_assignment", "id": id, "player_index": target})
		if item.trigger in ["assigned_or_solve_quest", "assigned_or_cell"]:
			game.deal_damage(-1, target, int(item.damage), "jinx")
	var vulnerable: bool = bool(context.get("jinx_was_vulnerable", false))
	if vulnerable:
		if not DruidicRules.choose(game, caster, context, "jinx_damage", [{"token": "inflict", "value": true, "name": "Inflict 1 Damage"}], "Vulnerability: inflict 1 Damage?", true):
			return false
		if context.get("jinx_damage") == true:
			game.deal_damage(caster, target, 1, "jinx")
	context.erase("assigned_jinx")
	context.erase("jinx_damage")
	context.erase("jinx_was_vulnerable")
	game.refresh_all_player_boards()
	return true

static func progress(game, player: int, assigned: Dictionary) -> void:
	var item := definition("jinxes", str(assigned.id))
	var taken: int = game.take_owner_cubes(player, 1)
	assigned.progress = int(assigned.progress) + taken
	if int(assigned.progress) >= int(item.slots):
		game.players[player].mage.jinxes.erase(assigned)
		game.return_owner_cubes(player, int(assigned.progress))
		var event := GameEvent.new("jinx_discarded")
		event.source_player_index = player
		game.queue_resolution({"type": "game_event", "event": event})

static func reduce_power(game, player: int, amount: int) -> int:
	if amount < 2:
		return amount
	var reduction: int = 0
	for ev in ForgottenEvocations.all_models(game):
		if ev.owner_id != player and not ForgottenEvocations.ability(game, ev, "opponents_gain_less_power").is_empty():
			reduction += 1
	for assigned in game.players[player].mage.jinxes.duplicate():
		if definition("jinxes", str(assigned.id)).trigger == "reduce_power":
			reduction += 1
			progress(game, player, assigned)
	return maxi(0, amount - reduction)

static func reduce_instability(game, player: int, room: String, amount: int) -> int:
	if amount <= 0:
		return amount
	var reduction: int = 0
	for ev in ForgottenEvocations.all_models(game):
		if ev.room_id == room and ev.owner_id != player:
			reduction += int(ForgottenEvocations.ability(game, ev, "reduce_opponent_instability").get("amount", 0))
	if player >= 0:
		for assigned in game.players[player].mage.jinxes.duplicate():
			if definition("jinxes", str(assigned.id)).trigger == "reduce_instability":
				reduction += 1
				progress(game, player, assigned)
	return maxi(0, amount - reduction)

static func on_event(game, event: GameEvent) -> void:
	for i in game.players.size():
		for assigned in game.players[i].mage.jinxes.duplicate():
			var item := definition("jinxes", str(assigned.id))
			var own: bool = event.source_player_index == i
			var damage: bool = false
			match str(item.trigger):
				"other_trap_protection": damage = event.event_type == "spell_effect_resolved" and not own and event.data.get("spell_type") in ["trap", "protection"]
				"enter_room": damage = event.event_type == "mage_enters_room" and own
				"assigned_or_solve_quest": damage = event.event_type == "quest_solved" and own
				"any_summon": damage = event.event_type == "forgotten_summon_effect"
				"gain_power": damage = event.event_type == "power_gained" and own
				"assigned_or_cell": damage = event.event_type == "mage_placed_in_cell" and own
			if damage:
				game.deal_damage(-1, i, int(item.get("damage", 1)), "jinx")
			var advance: bool = false
			match str(item.task):
				"room_colors": advance = own and event.event_type == "room_effect_resolved" and str(event.data.get("room_color", "")) in item.get("colors", [])
				"placed_cell": advance = own and event.event_type == "mage_placed_in_cell"
				"own_summon": advance = own and event.event_type == "forgotten_summon_effect"
				"explore_momentum": advance = own and event.event_type in ["explore_performed", "momentum_performed"]
				"discard_jinx_or_quest": advance = own and event.event_type in ["jinx_discarded", "quest_solved"]
			if advance:
				progress(game, i, assigned)

static func physical_action_finished(game, player: int) -> void:
	for assigned in game.players[player].mage.jinxes.duplicate():
		if definition("jinxes", str(assigned.id)).task == "explore_momentum":
			progress(game, player, assigned)

static func process_end_phase(game, frame: Dictionary) -> bool:
	if not frame.has("remaining"):
		var remaining: Array = []
		for owner in game.get_play_order():
			for ev in game.players[owner].evocations:
				if not ForgottenEvocations.ability(game, ev, "move_after_black_rose").is_empty():
					remaining.append(ev)
		frame["remaining"] = remaining
	if frame.remaining.is_empty():
		return true
	var ev: EvocationState = frame.remaining[0]
	var moved: int = int(frame.get("moved", 0))
	if not game.is_evocation_in_play(ev) or ev.is_defeated() or moved >= ev.speed:
		frame.remaining.pop_front()
		frame.erase("moved")
		return false
	var owner: int = game.get_evocation_controller_id(ev)
	var context := {"game": game, "caster_id": owner, "source_evocation": ev}
	if not DruidicRules.choose(game, owner, frame, "destination", ForgottenRules.rooms(game, context, 1),
		"Tendon Implant: move, or select the current Room to stop.", false, "movement_destination"):
		return false
	var destination: String = str(frame.get("destination", ev.room_id))
	frame.erase("destination")
	if destination == ev.room_id:
		frame.remaining.pop_front()
		frame.erase("moved")
	else:
		frame["moved"] = moved + 1
		game.move_evocation_to_room_id(ev, destination, 1)
	return false
