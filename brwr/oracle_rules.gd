class_name OracleRules
extends RefCounted

const TYPES := ["prophecy", "revelation", "revelation_or", "oracle_keyword_resolved", "discard_events_for_effect", "peek_library_keep"]

static func prepare_revelation(game, caster: int, side: Dictionary, context: Dictionary) -> bool:
	if not bool(side.get("revelation", false)) or context.has("revelation_count"): return true
	var options: Array = []
	for i in game.active_events.size():
		var event: EventCardState = game.active_events[i]
		if event != null: options.append({"token": "event:%d" % i, "value": i, "id": event.id, "name": event.event_name, "card_kind": "events"})
	if not context.has("revelation_slots") and not options.is_empty():
		game.request_effect_choice(caster, "events", context, "revelation_slots", options, 0, options.size(), "Revelation: choose Events to discard before resolving this Spell.")
		return false
	var selected = context.get("revelation_slots", [])
	var slots: Array = selected if selected is Array else [selected]
	context["revelation_count"] = 0
	for slot in slots:
		if slot is int or slot is float:
			var event: EventCardState = game.active_events[int(slot)]
			if event != null:
				game.active_events[int(slot)] = null
				game.discard_event(event, false)
				context.revelation_count += 1
	return true

static func keyword_event(game, caster: int, keyword: String) -> void:
	var event := GameEvent.new("oracle_keyword_resolved")
	event.source_player_index = caster
	event.source_model_type = "mage"
	event.data["keyword"] = keyword
	game.queue_resolution({"type": "game_event", "event": event})

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.game
	var caster: int = int(context.caster_id)
	match str(effect.type):
		"prophecy":
			if not context.has("prophecy_event"):
				var deck: Array = game.event_decks.get(game.current_moon, [])
				var instants: Array = []
				var found: EventCardState
				while not deck.is_empty():
					var event: EventCardState = deck.pop_back()
					if event.is_instant(): instants.append(event)
					else:
						found = event
						break
				deck.append_array(instants)
				game.shuffle_with_rng(deck)
				if found == null: return true
				context["prophecy_event"] = found
			var options: Array = []
			for i in 3: options.append({"token": "slot:%d" % i, "value": i, "name": "Event slot %d" % (i + 1)})
			if not DruidicRules.choose(game, caster, context, "prophecy_slot", options, "Prophecy: choose the slot for " + context.prophecy_event.event_name + "."): return false
			var slot: int = int(context.prophecy_slot)
			var displaced: EventCardState = game.active_events[slot]
			game.active_events[slot] = context.prophecy_event
			if displaced != null: game.discard_event(displaced, false)
			context.erase("prophecy_event")
			context.erase("prophecy_slot")
			game.get_node("EventBoard").refresh_event_slots()
			keyword_event(game, caster, "prophecy")
			return true
		"revelation", "revelation_or":
			var count: int = int(context.get("revelation_count", 0))
			var effects: Array = []
			if count == 0 and effect.type == "revelation_or": effects.append_array(effect.get("normal", []))
			for i in count: effects.append_array(effect.effects.duplicate(true))
			if count > 0: effects.append({"type": "oracle_keyword_resolved", "keyword": "revelation"})
			return ForgottenRules.queue(game, effects, context)
		"oracle_keyword_resolved":
			keyword_event(game, caster, str(effect.keyword))
			return true
		"discard_events_for_effect":
			var slots: Array = []
			for i in game.active_events.size():
				if game.active_events[i] != null: slots.append(i)
			if slots.size() < int(effect.amount): return true
			if not DruidicRules.choose(game, caster, context, "oracle_pay_events", [{"token": "discard", "value": true, "name": "Discard %d Events" % int(effect.amount)}], "Discard Events for this Effect?", true): return false
			var accepted: bool = context.get("oracle_pay_events") == true
			context.erase("oracle_pay_events")
			if accepted:
				for i in slots:
					var event: EventCardState = game.active_events[i]
					game.active_events[i] = null
					game.discard_event(event, true)
				return ForgottenRules.queue(game, effect.effects, context)
			return true
		"peek_library_keep":
			if not context.has("oracle_peek"): context["oracle_peek"] = []
			while context.oracle_peek.size() < int(effect.get("amount", 2)) and not bool(context.get("oracle_peek_done", false)):
				var options: Array = []
				for id in game.school_libraries:
					if not game.school_libraries[id].is_empty(): options.append({"token": "school:" + id, "value": id, "school_id": id, "name": id.capitalize()})
				if not DruidicRules.choose(game, caster, context, "oracle_school", options, "Choose a School for Spell %d of %d." % [context.oracle_peek.size() + 1, int(effect.get("amount", 2))], false, "library_school"): return false
				if not context.has("oracle_school"):
					context["oracle_peek_done"] = true
					break
				var count: int = 1 if bool(effect.get("multiple_schools", false)) else int(effect.get("amount", 2))
				for i in count:
					var card: SpellCardState = game.draw_from_school_library(str(context.oracle_school))
					if card != null: context.oracle_peek.append(card)
				context.erase("oracle_school")
				if not bool(effect.get("multiple_schools", false)): context["oracle_peek_done"] = true
			var options: Array = []
			for i in context.oracle_peek.size():
				var card: SpellCardState = context.oracle_peek[i]
				options.append({"token": "card:%d" % i, "value": i, "id": card.id, "name": card.card_name, "card_kind": "spells"})
			if not DruidicRules.choose(game, caster, context, "oracle_keep", options, "Choose the Spell to add to your Hand."): return false
			for i in context.oracle_peek.size():
				var card: SpellCardState = context.oracle_peek[i]
				if i == int(context.get("oracle_keep", -1)): game.players[caster].add_spell_to_hand(card)
				else: game.school_discards[card.school_id].append(card)
			for key in ["oracle_peek", "oracle_school", "oracle_keep", "oracle_peek_done"]: context.erase(key)
			game.refresh_player_board(caster)
			return true
	return false
