class_name AlternativeRoomRules
extends RefCounted

# Alternative Rooms use the same Lodge slots, cards and resolution stack.
# These are reusable printed clauses, not a second Room/state database.
const EFFECT_TYPES := ["room_target", "room_payment", "room_choice", "room_search_deck",
	"room_library_draw", "room_activate_evocation", "room_black_rose_damage",
	"room_damage_evocations", "room_remove_evocations", "room_move"]

static func child_context(context: Dictionary) -> Dictionary:
	var nested := DruidicRules.scoped_context(context)
	for key in context.get("_interactive_choice_keys", []):
		nested.erase(key)
	for key in ["_interactive_choice_keys", "quest_target_model", "target_model", "room_choice",
		"room_payment_cards", "room_search_card", "room_search_school", "room_effect_no_target", "_skip_room_effect"]:
		nested.erase(key)
	return nested

static func queue(game, effects: Array, context: Dictionary) -> bool:
	context["alternative_room"] = true
	return DruidicRules.sequence(game, effects, context, "room")

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.get("game")
	var caster: int = int(context.get("caster_id", -1))
	if game == null or caster < 0 or caster >= game.players.size():
		return false
	var player = game.players[caster]
	match str(effect.type):
		"room_move":
			return game.queue_resolution({"type": "room_move", "remaining": int(effect.get("distance", 1)), "context": context.duplicate(true)})
		"room_target":
			var kind: String = str(effect.target)
			var nested := child_context(context)
			if kind == "self":
				nested.merge({"spell_target_type": "self", "target_model_type": "mage", "target_player_index": caster}, true)
			else:
				var include_owned: bool = str(effect.get("target_owner", "")) != "opponent"
				var options: Array = ForgottenRules.rooms(game, context, effect.get("range", "*")) if kind == "room" else ForgottenRules.models(game, context, kind, effect.get("range", "*"), "", include_owned)
				if effect.has("max_health"):
					options = options.filter(func(o): return o.value is Dictionary and o.value.get("evocation") != null and o.value.evocation.health <= int(effect.max_health))
				if not DruidicRules.choose(game, caster, context, "room_choice", options, "Choose a " + kind + ".", false, "secondary_room" if kind == "room" else "model_target"):
					return false
				var selected = context.get("room_choice")
				context.erase("room_choice")
				if selected == null:
					return true
				nested = ForgottenRules.target_context(nested, selected)
			return queue(game, effect.effects, nested)
		"room_payment":
			return pay(game, caster, effect, context)
		"room_choice":
			var options: Array = []
			for i in effect.choices.size():
				options.append({"token": "room_mode:%d" % i, "value": i, "name": str(effect.choices[i].label)})
			if not DruidicRules.choose(game, caster, context, "room_choice", options, "Choose the Room Effect."):
				return false
			var selected: int = int(context.get("room_choice", -1))
			context.erase("room_choice")
			return queue(game, effect.choices[selected].effects, context.duplicate(false)) if selected >= 0 else true
		"room_search_deck", "room_library_draw":
			return search_deck(game, caster, effect, context)
		"room_activate_evocation":
			var ev: EvocationState = context.get("last_summoned_evocation") if bool(effect.get("last_summoned", false)) else context.get("target_evocation")
			if ev == null or not game.is_evocation_in_play(ev) or ev.is_defeated():
				return true
			# Each activation has its own movement/attack choices, including when a
			# Room activates the same freshly summoned model twice (Whales Cemetery).
			return game.activate_evocation(ev, caster, {"evocation_activation_speed_bonus": int(effect.get("speed_bonus", 0))}, int(effect.get("strength_bonus", 0)))
		"room_black_rose_damage":
			game.deal_damage(-1, caster, int(effect.amount), "room")
			return true
		"room_damage_evocations":
			var models: Array = ForgottenEvocations.all_models(game).filter(func(ev): return not ev.is_defeated() and game.is_lodge_room_id(ev.room_id) and game.get_evocation_controller_id(ev) != caster)
			for i in range(models.size() - 1, -1, -1):
				var nested := ForgottenRules.target_context(child_context(context), {"target_type": "evocation", "evocation": models[i]})
				queue(game, [{"type": "damage", "amount": int(effect.amount), "shared": true}], nested)
			return true
		"room_remove_evocations":
			var options: Array = []
			for ev in ForgottenEvocations.all_models(game):
				if game.is_lodge_room_id(ev.room_id) and ForgottenEvocations.can_remove(game, ev, context):
					options.append({"token": "remove:%d" % ev.get_instance_id(), "value": ev, "name": ev.get_display_name(), "room_id": ev.room_id, "id": ev.evocation_id})
			if not DruidicRules.choose(game, caster, context, "room_choice", options, "Choose the next Evocation to remove.", false, "evocation_target"):
				return false
			var ev: EvocationState = context.get("room_choice")
			context.erase("room_choice")
			if ev != null and game.is_evocation_in_play(ev):
				# Reactions to the removal resolve before the next model is chosen.
				queue(game, [effect], context.duplicate(false))
				game.effect_resolver._remove_evocation(game, ev, context)
			return true
	return false

static func ready_cards(player, quick_only: bool = false) -> Array:
	var result: Array = [] if quick_only else player.ready_spells.duplicate()
	if player.quick_spell != null:
		result.append(player.quick_spell)
	return result

static func pay(game, caster: int, effect: Dictionary, context: Dictionary) -> bool:
	var player = game.players[caster]
	var power: int = int(effect.get("power", 0))
	var ready_count: int = int(effect.get("ready", 0))
	var hand_count: int = int(effect.get("hand", 0))
	var ready: Array = ready_cards(player, bool(effect.get("quick_only", false)))
	# Validate the entire cost before consuming any cards/cubes/Power.
	if player.power < power or ready.size() < ready_count or player.hand.size() < hand_count:
		return true
	for part in ["ready", "hand"]:
		var count: int = ready_count if part == "ready" else hand_count
		var key: String = "room_payment_" + part
		if count == 0 or context.has(key):
			continue
		var source: Array = ready if part == "ready" else player.hand
		var options: Array = []
		for i in source.size():
			var card: SpellCardState = source[i].spell if part == "ready" else source[i]
			options.append({"token": part + ":" + str(i), "value": source[i], "id": card.id, "name": card.card_name, "card_kind": "spells"})
		game.request_effect_choice(caster, "room_payment", context, key, options, count, count, "Discard %d %s Spell(s)." % [count, part])
		return false
	var chosen_ready: Array = selections(context.get("room_payment_ready"))
	var chosen_hand: Array = selections(context.get("room_payment_hand"))
	if chosen_ready.size() != ready_count or chosen_hand.size() != hand_count:
		return true
	if chosen_ready.any(func(card): return not card in ready) or chosen_hand.any(func(card): return not card in player.hand):
		return true
	for prepared in chosen_ready:
		if player.quick_spell == prepared:
			player.quick_spell = null
		else:
			player.ready_spells.erase(prepared)
		game._clear_player_board_spell_by_spell(caster, prepared.spell)
		game.move_spell_to_memories_or_remove(caster, prepared.spell)
	for card in chosen_hand:
		player.hand.erase(card)
		game.move_spell_to_memories_or_remove(caster, card)
	if power > 0:
		game.add_player_power(caster, -power)
	context.erase("room_payment_ready")
	context.erase("room_payment_hand")
	game.refresh_all_player_boards()
	return queue(game, effect.effects, child_context(context))

static func selections(value) -> Array:
	if value == null:
		return []
	return value if value is Array else [value]

static func process_movement(game, frame: Dictionary) -> bool:
	if int(frame.remaining) <= 0:
		return true
	var context: Dictionary = frame.context
	var ev: EvocationState = context.get("target_evocation")
	var target: int = int(context.get("target_player_index", -1))
	if ev != null:
		if not game.is_evocation_in_play(ev) or ev.is_defeated():
			return true
	elif target < 0 or game.players[target].mage.in_cell:
		return true
	var origin: String = ev.room_id if ev != null else game.players[target].mage.room_id
	if not game.effect_resolver.resolve_effect({"type": "move_target_up_to", "distance": 1}, context):
		return not game.waiting_for_player_input
	frame["remaining"] = int(frame.remaining) - 1
	var destination: String = ev.room_id if ev != null else game.players[target].mage.room_id
	return origin == destination or int(frame.remaining) <= 0

static func search_deck(game, caster: int, effect: Dictionary, context: Dictionary) -> bool:
	var source: String = str(effect.get("source", "library"))
	var deck: Array = []
	if source == "library":
		var schools: Array = []
		for id in game.school_libraries:
			# Drawing uses the normal discard refill; searching only offers cards
			# actually in the deck, so an empty School cannot consume the choice.
			var can_refill: bool = effect.type == "room_library_draw" and not game.get_school_discard(id).is_empty()
			if not game.get_school_library(id).is_empty() or can_refill:
				schools.append({"token": "school:" + str(id), "value": id, "school_id": id, "id": id, "name": str(id).capitalize(), "card_kind": "schools"})
		if not DruidicRules.choose(game, caster, context, "room_search_school", schools, "Choose a School.", false, "school"):
			return false
		if not context.has("room_search_school"):
			return true
		var school: String = str(context.room_search_school)
		if effect.type == "room_library_draw":
			var drawn = game.draw_from_school_library(school)
			context.erase("room_search_school")
			if drawn != null:
				game.players[caster].add_spell_to_hand(drawn)
			return true
		deck = game.get_school_library(school)
	elif source == "forgotten":
		deck = game.forgotten_deck
	else:
		deck = game.players[caster].grimoire
	var options: Array = []
	for i in deck.size():
		var card: SpellCardState = deck[i]
		options.append({"token": "search:%d" % i, "value": card, "id": card.id, "name": card.card_name, "card_kind": "spells"})
	if not DruidicRules.choose(game, caster, context, "room_search_card", options, "Choose a Spell."):
		return false
	var chosen: SpellCardState = context.get("room_search_card")
	context.erase("room_search_card")
	context.erase("room_search_school")
	if chosen != null and chosen in deck:
		deck.erase(chosen)
		if source == "forgotten" and str(chosen.light_side.get("type", "")) == "on_draw":
			game.resolve_drawn_forgotten(caster, chosen)
		else:
			game.players[caster].add_spell_to_hand(chosen)
	if bool(effect.get("shuffle", true)):
		deck.shuffle()
	return true
