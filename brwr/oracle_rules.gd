class_name OracleRules
extends RefCounted

const TYPES := ["prophecy", "revelation", "revelation_or", "oracle_keyword_resolved", "discard_events_for_effect", "peek_library_keep"]

static func prepare_revelation(game, caster: int, side: Dictionary, context: Dictionary) -> bool:
	if not bool(side.get("revelation", false)) or context.has("revelation_count"): return true
	var options := EventTrack.choices(game.active_events)
	if not context.has("revelation_slots") and not options.is_empty():
		game.request_effect_choice(caster, "events", context, "revelation_slots", options, 0, options.size(), "Revelation: choose Events to discard before resolving this Spell.")
		return false
	var selected = context.get("revelation_slots", [])
	context["revelation_count"] = 0
	for card in (selected if selected is Array else [selected]):
		if card is EventCardState and EventTrack.discard_from_slot(game, card, false):
			context.revelation_count += 1
	return true

static func keyword_event(game, caster: int, keyword: String) -> void:
	var event := GameEvent.new("oracle_keyword_resolved")
	event.source_player_index = caster
	event.source_model_type = "mage"
	event.data["keyword"] = keyword
	game.queue_resolution({"type": "game_event", "event": event})

static func draw_prophecy(game) -> EventCardState:
	var moon: int = game.current_moon
	var deck: Array = game.event_decks[moon]
	var instants: Array[EventCardState] = []
	while true:
		if deck.is_empty():
			EventTrack.refill_deck(game, moon)
		if deck.is_empty():
			# Holding the revealed Instants aside keeps the search finite.
			game.event_discard.append_array(instants)
			game.get_node("EventBoard").refresh_event_slots()
			game.append_public_log("Prophecy found no non-Instant Event for this Moon.")
			return null
		var card: EventCardState = deck.pop_back()
		if card.is_instant():
			instants.append(card)
			continue
		# The Oracle erratum returns revealed Instants to the deck on success.
		if not instants.is_empty():
			deck.append_array(instants)
			game.shuffle_with_rng(deck)
		game.get_node("EventBoard").refresh_event_slots()
		return card
	return null

static func place_prophecy(game, frame: Dictionary) -> bool:
	if frame.get("placed", false): return true
	var options := []
	for i in game.active_events.size():
		options.append({"token": "slot:%d" % i, "value": i, "name": "Event slot %d" % (i + 1)})
	var card: EventCardState = frame.event
	if not DruidicRules.choose(game, frame.caster_id, frame, "prophecy_slot", options,
			"Prophecy · Choose a slot for %s." % card.event_name, false, "prophecy_slot"):
		return false
	var slot: int = frame.prophecy_slot
	frame["placed"] = true
	var stack := EventTrack.cards_in(game.active_events, slot)
	stack.append(card)
	game.active_events[slot] = stack
	game.get_node("EventBoard").refresh_event_slots()
	game.append_public_log("Prophecy placed %s in Event slot %d." % [card.event_name, slot + 1])
	keyword_event(game, frame.caster_id, "prophecy")
	if card.phase == "always":
		game.queue_resolution({"type": "event_sequence", "event": card, "_card_presented": true,
			"context": {"game": game, "event": card, "drawing_player_index": frame.caster_id, "play_order": game.get_play_order()}})
	return true

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.game
	var caster: int = int(context.caster_id)
	match str(effect.type):
		"prophecy":
			var card := draw_prophecy(game)
			if card != null:
				return game.queue_resolution({"type": "oracle_prophecy", "event": card, "caster_id": caster})
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
			var options := EventTrack.choices(game.active_events)
			var amount := int(effect.amount)
			if options.size() < amount: return true
			if not DruidicRules.choose(game, caster, context, "oracle_pay_events", [{"token": "discard", "value": true, "name": "Discard %d Events" % amount}], "Discard Events for this Effect?", true): return false
			if context.get("oracle_pay_events") != true:
				context.erase("oracle_pay_events")
				return true
			if options.size() > amount and not context.has("oracle_payment_cards"):
				game.request_effect_choice(caster, "events", context, "oracle_payment_cards", options, amount, amount, "Choose %d Events to discard." % amount)
				return false
			var payment: Array = context.get("oracle_payment_cards", options.map(func(o): return o.value))
			context.erase("oracle_pay_events")
			context.erase("oracle_payment_cards")
			for event in payment:
				EventTrack.discard_from_slot(game, event, true)
			return ForgottenRules.queue(game, effect.effects, context)
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
