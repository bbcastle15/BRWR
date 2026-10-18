class_name SchoolEffects
extends RefCounted

# Shared, data-driven sentences for the remaining Codex schools. All choices
# suspend the existing Effect sequence; no second spell/attachment state exists.
const TYPES := ["filtered_model_effect", "each_owned_evocation", "scaled_school_effect",
	"remove_evocation_then", "pay_room_instability", "if_effect_result", "summon_equipment",
	"damage_selected_evocation", "trigger_target_effect", "chain_damage", "if_jinxed",
	"discard_jinx", "for_school_mages", "place_target_colored_room", "pay_power_effect",
	"arm_prepared_reactions", "marked_entry_attack", "opponent_protection_choice", "steal_trophy",
	"activate_mage_evocation", "evocation_strength_damage_mage", "place_instability_at_target",
	"convert_damage_store_black_rose", "record_black_conversion", "school_condition",
	"other_owner_instability", "remove_upgrade", "target_gain_power", "target_take_crown",
	"activate_last_nightmare", "activate_all_nightmares", "draw_school_event", "school_damage_self",
	"target_discard_hand", "convert_instability_reward_owners", "reward_converted_owners",
	"remove_payment_evocation", "move_mage_in_target_room", "nightmare_room_effect",
	"defeat_nightmare_target", "repeat_for_events", "power_per_triggered_trap", "remember_trigger_count", "damage_from_context",
	"removed_room_effect", "quest_moon_payment", "search_grimoire_cards", "remove_many_evocations",
	"place_owned_evocation_in_target_room", "resummon_trigger_evocation",
	"channel_altar_damage", "discard_board_event", "remember_removed_count", "if_removed_count", "last_damaged_room_effect",
	"choose_quest_moon", "replace_resolving_spell", "controlled_memory_replacement", "choose_evocation_to_summon", "ranged_mage_attack"]

static func model_options(game, effect: Dictionary, context: Dictionary) -> Array:
	var caster: int = int(context.caster_id)
	var center: String = FamineRules.target_room(game, context) if bool(effect.get("from_target", false)) else ""
	var options := ForgottenRules.models(game, context, str(effect.get("target", "evocation")), effect.get("range", "*"), center)
	return options.filter(func(o):
		var ev: EvocationState = o.value.get("evocation")
		if bool(effect.get("movable", false)) and ev != null and ev.archetype == "equipment": return false
		if bool(effect.get("physical_attack_target", false)):
			if ev != null and (ev == context.get("source_evocation") or game.get_evocation_controller_id(ev) == caster or not ForgottenEvocations.ability(game, ev, "cannot_be_physically_attacked").is_empty()): return false
			if ev == null and ForgottenPassives.value(game.players[int(o.value.player_index)], "cannot_be_evocation_attack_target") > 0: return false
		if bool(effect.get("jinxed", false)) and (ev != null or game.players[int(o.value.player_index)].mage.jinxes.is_empty()): return false
		if effect.has("owner") and (ev == null or (ev.owner_id == caster) != (effect.owner == "self")): return false
		if effect.has("archetype") and (ev == null or ev.archetype != effect.archetype): return false
		if effect.has("evocation_id") and (ev == null or ev.evocation_id != effect.evocation_id): return false
		if effect.has("max_health") and (ev == null or ev.health > int(effect.max_health)): return false
		if int(effect.get("min_nightmares", 0)) > 0 and (ev != null or nightmare_count(game, int(o.value.player_index)) < int(effect.min_nightmares)): return false
		if bool(effect.get("different_room", false)) and o.room_id == center: return false
		if effect.has("distinct_key") and context.get(str(effect.distinct_key), []).has(ev if ev != null else int(o.value.player_index)): return false
		return true)

static func nightmare_count(game, mage: int = -1, room: String = "") -> int:
	var count := 0
	for ev in ForgottenEvocations.all_models(game):
		if ev.archetype == "nightmare" and (mage < 0 or ev.assigned_mage == mage) and (room.is_empty() or room == ev.room_id): count += 1
	return count

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.game
	var caster: int = int(context.caster_id)
	var player: PlayerState = game.players[caster]
	var ev: EvocationState = context.get("target_evocation")
	var target: int = int(context.get("target_player_index", -1))
	match str(effect.type):
		"last_damaged_room_effect":
			# Defeat has already moved the Mage to a Cell; use the damage receipt.
			var room_id: String = str(context.get("last_damage_target_room_id", ""))
			return ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, room_id)) if game.is_lodge_room_id(room_id) else true
		"choose_quest_moon":
			var options: Array = []
			for moon in [game.current_moon, mini(3, game.current_moon + 1)]:
				if not options.any(func(o): return o.value == moon) and not game.quest_decks.get(moon, []).is_empty():
					options.append({"token": "moon:%d" % moon, "value": moon, "name": "Moon %d" % moon})
			if not DruidicRules.choose(game, caster, context, "school_quest_moon", options, "Choose the Quest deck."): return false
			if not context.has("school_quest_moon"): return true
			var nested: Dictionary = context.duplicate(true)
			nested["quest_draw_moon"] = int(context.school_quest_moon)
			context.erase("school_quest_moon")
			return ForgottenRules.queue(game, [{"type": "peek_quests_keep", "amount": int(effect.amount)}], nested)
		"replace_resolving_spell":
			return replace_current_spell(game, caster, context, bool(effect.get("cast", false)))
		"controlled_memory_replacement":
			if not context.has("school_drawn_memories"):
				var drawn: Array = []
				for i in mini(2, player.memories.size()):
					var index: int = game.rng.randi_range(0, player.memories.size() - 1)
					var card: SpellCardState = player.memories[index]
					player.memories.remove_at(index)
					player.hand.append(card)
					drawn.append(card)
				context["school_drawn_memories"] = drawn
			if not bool(context.get("school_memory_discarded", false)):
				var options: Array = []
				for card in context.school_drawn_memories: options.append({"token": "discard:%d" % card.get_instance_id(), "value": card, "id": card.id, "name": card.card_name, "card_kind": "spells"})
				if not DruidicRules.choose(game, caster, context, "school_memory_discard", options, "Discard one of the drawn Spells."): return false
				var discarded: SpellCardState = context.get("school_memory_discard")
				if discarded != null:
					player.hand.erase(discarded)
					game.move_spell_to_memories_or_remove(caster, discarded)
					context.school_drawn_memories.erase(discarded)
				context["school_memory_discarded"] = true
			if context.school_drawn_memories.is_empty(): return true
			return replace_current_spell(game, caster, context, false, context.school_drawn_memories, true)
		"choose_evocation_to_summon":
			var options: Array = []
			for data in game.evocation_database.evocations.values():
				if data.archetype in ["equipment", "nightmare"] or bool(data.get("forgotten", false)) or int(data.health) > int(effect.get("max_health", 999)) or game.get_available_evocation_copies(data.id) <= 0: continue
				options.append({"token": "summon:" + data.id, "value": data.id, "id": data.id, "name": data.name, "card_kind": "evocations"})
			if not DruidicRules.choose(game, caster, context, "school_summon", options, "Choose an Evocation to summon."): return false
			if not context.has("school_summon"): return true
			var id: String = str(context.school_summon)
			context.erase("school_summon")
			return ForgottenRules.queue(game, [{"type": "summon_evocation", "evocation_id": id}], context)
		"ranged_mage_attack":
			return DruidicRules.mage_attack(game, caster, effect, context)
		"removed_room_effect":
			return ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, str(context.get("removed_evocation_room_id", ""))))
		"remember_removed_count":
			context["school_removed_count"] = 0
			return true
		"if_removed_count":
			return ForgottenRules.queue(game, effect.effects, context) if int(context.get("school_removed_count", 0)) >= int(effect.amount) else true
		"quest_moon_payment":
			var options: Array = []
			for quest in player.active_quests:
				options.append({"token": "quest:%d" % quest.get_instance_id(), "value": quest, "name": quest.get_name(), "id": quest.get_id(), "card_kind": "quests", "board_player_index": caster, "quest_section": "active", "quest_index": player.active_quests.find(quest)})
			if not DruidicRules.choose(game, caster, context, "school_quest", options, "Choose an Active Quest.", false, "quest_target"): return false
			var quest = context.get("school_quest")
			if quest == null: return true
			var cost: int = quest.get_moon()
			if effect.get("payment") == "power":
				if player.power < cost:
					context.erase("school_quest")
					return true
				game.add_player_power(caster, -cost)
			else:
				var room = game.get_room_by_id(FamineRules.target_room(game, context))
				if room == null or room.instability_cubes.count(caster) < cost:
					context.erase("school_quest")
					return true
				if not game.effect_resolver.resolve_effect({"type": "remove_instability", "amount": cost, "owner": "self"}, context): return false
			context.erase("school_quest")
			game.quest_manager.complete_active_quest(game, caster, quest)
			if bool(effect.get("solve", false)): return game.quest_manager.solve_quest(game, caster, quest, {})
			game.refresh_player_board(caster)
			return true
		"search_grimoire_cards":
			if bool(effect.get("shuffle_memories", false)) and not context.has("school_search_started"):
				player.grimoire.append_array(player.memories)
				player.memories.clear()
				context["school_search_started"] = true
			var options: Array = []
			for i in player.grimoire.size():
				var card: SpellCardState = player.grimoire[i]
				if bool(effect.get("summon", false)) and not contains_effect(card.get_effects(false), "summon") and not contains_effect(card.get_effects(true), "summon"): continue
				options.append({"token": "grimoire:%d" % i, "value": card, "id": card.id, "name": card.card_name, "card_kind": "spells"})
			var count: int = mini(int(effect.amount), options.size())
			if not context.has("school_search_cards") and count > 0:
				game.request_effect_choice(caster, "spell_search", context, "school_search_cards", options, 0 if bool(effect.get("optional", false)) else count, count, "Choose Spells from your Grimoire.")
				return false
			var value = context.get("school_search_cards", [])
			var cards: Array = value if value is Array else [value]
			for card in cards:
				if player.grimoire.has(card):
					player.grimoire.erase(card)
					player.hand.append(card)
			game.shuffle_with_rng(player.grimoire)
			context.erase("school_search_started")
			context.erase("school_search_cards")
			return true
		"remove_many_evocations":
			var options := model_options(game, effect, context)
			var count: int = mini(int(effect.amount), options.size())
			if not context.has("school_remove_models") and count > 0:
				game.request_effect_choice(caster, "evocation_target", context, "school_remove_models", options, 0, count, "Choose Evocations to remove.")
				return false
			var value = context.get("school_remove_models", [])
			var selected: Array = value if value is Array else [value]
			var removed := 0
			for option in selected:
				if option is Dictionary and game.effect_resolver._remove_evocation(game, option.evocation, context): removed += 1
			context["school_removed_count"] = removed
			context.erase("school_remove_models")
			return ForgottenRules.queue(game, effect.get("effects", []), context)
		"place_owned_evocation_in_target_room":
			var options := model_options(game, {"owner": "self", "movable": true, "distinct_key": "school_placed_evocations"}, context)
			if not DruidicRules.choose(game, caster, context, "school_place_evocation", options, "Choose one of your Evocations to place and activate.", false, "evocation_target"): return false
			var chosen = context.get("school_place_evocation")
			context.erase("school_place_evocation")
			if chosen is Dictionary:
				var used: Array = context.get("school_placed_evocations", [])
				used.append(chosen.evocation)
				context["school_placed_evocations"] = used
				game.effect_resolver._place_target_model_direct(game, ForgottenRules.target_context(context, chosen), FamineRules.target_room(game, context))
				game.activate_evocation(chosen.evocation, caster, {})
			return true
		"resummon_trigger_evocation":
			var event: GameEvent = context.get("trigger_event")
			if event == null or event.target_evocation == null: return true
			return ForgottenRules.queue(game, [{"type": "summon_evocation", "evocation_id": event.target_evocation.evocation_id}, {"type": "assign_upgrade", "id": str(effect.upgrade)}], ForgottenRules.target_context(context, event.target_room_id))
		"channel_altar_damage":
			return resolve({"type": "filtered_model_effect", "owner": "self", "archetype": "altar", "optional": true,
				"effects": [{"type": "damage_selected_evocation", "amount": 1, "black_rose": true}, {"type": "if_effect_result", "key": "last_damage_dealt", "effects": effect.effects}]}, context)
		"discard_board_event":
			var options: Array = []
			for i in game.active_events.size():
				if game.active_events[i] != null: options.append({"token": "event:%d" % i, "value": i, "id": game.active_events[i].id, "name": game.active_events[i].event_name, "card_kind": "events"})
			if not DruidicRules.choose(game, caster, context, "school_discard_event", options, "Choose an Event to discard."): return false
			var slot = context.get("school_discard_event")
			context.erase("school_discard_event")
			if slot != null:
				var event: EventCardState = game.active_events[int(slot)]
				game.active_events[int(slot)] = null
				game.discard_event(event, not bool(effect.get("remove", false)))
				return ForgottenRules.queue(game, effect.get("effects", []), context)
			return true
		"damage_from_context":
			return ForgottenRules.queue(game, [{"type": "damage", "amount": int(context.get(str(effect.amount_key), 0))}], context)
		"school_condition":
			var valid := false
			match str(effect.condition):
				"target_has_upgrade": valid = ev != null and not ev.upgrades.is_empty()
				"target_survived": valid = game.is_evocation_in_play(ev) if ev != null else target >= 0 and not game.players[target].mage.in_cell
				"caster_survived": valid = not player.mage.in_cell and not player.mage.is_defeated()
				"damaged_models": valid = context.get("models_damaged_by_effect", []).size() >= int(effect.get("minimum", 2))
				"target_nightmares": valid = target >= 0 and nightmare_count(game, target) >= int(effect.get("minimum", 3))
				"room_no_own_instability":
					var room = game.get_room_by_id(FamineRules.target_room(game, context))
					valid = room != null and not room.instability_cubes.has(caster)
				"target_has_crown": valid = game.crown_owner_id == target
				"owns_equipment": valid = player.evocations.any(func(e): return e.archetype == "equipment")
				"removed_demon": valid = context.get("removed_archetype") == "demon"
			return ForgottenRules.queue(game, effect.effects if valid else effect.get("otherwise", []), context)
		"other_owner_instability":
			var owner: int = int(effect.get("owner", -1))
			if str(effect.get("owner", "")) == "choose":
				var options: Array = []
				for id in game.get_play_order():
					if id != caster: options.append({"token": "owner:%d" % id, "value": id, "name": game.players[id].player_name})
				if not DruidicRules.choose(game, caster, context, "instability_owner", options, "Choose the Mage who places Instability."): return false
				owner = int(context.get("instability_owner", -1))
				context.erase("instability_owner")
			var room_id: String = FamineRules.target_room(game, context)
			var room = game.get_room_by_id(room_id)
			if room == null: return true
			var before: int = room.instability_cubes.size()
			if owner == -1: game.place_black_rose_instability(room_id, int(effect.amount))
			else: game.place_player_instability(owner, room_id, int(effect.amount))
			context["school_instability_placed"] = room.instability_cubes.size() - before
			if int(context.school_instability_placed) > 0: return ForgottenRules.queue(game, effect.get("effects", []), context)
			return true
		"target_gain_power":
			if target >= 0: game.add_player_power(target, int(effect.amount))
			return true
		"target_take_crown":
			if target >= 0: game.take_crown(target)
			return true
		"remove_upgrade":
			if ev == null or ev.upgrades.is_empty(): return true
			var options: Array = []
			for id in ev.upgrades: options.append({"token": "upgrade:" + str(id), "value": id, "id": id, "name": ForgottenAttachments.definition("upgrades", id).name, "card_kind": "upgrades"})
			if not DruidicRules.choose(game, caster, context, "school_upgrade_remove", options, "Choose an Upgrade to discard."): return false
			var id = context.get("school_upgrade_remove")
			context.erase("school_upgrade_remove")
			if id != null:
				ev.upgrades.erase(id)
				ForgottenAttachments.recompute_stats(game, ev)
				return ForgottenRules.queue(game, effect.get("effects", []), context)
			return true
		"remove_payment_evocation":
			var options := model_options(game, effect, context)
			if not DruidicRules.choose(game, caster, context, "school_payment_evocation", options, "Choose an Evocation to remove.", false, "evocation_target"): return false
			var chosen = context.get("school_payment_evocation")
			context.erase("school_payment_evocation")
			if chosen is Dictionary and game.effect_resolver._remove_evocation(game, chosen.evocation, context, true): return ForgottenRules.queue(game, effect.effects, context)
			return true
		"school_damage_self":
			game.deal_damage(target if bool(effect.get("by_target", false)) else -1, caster, int(effect.amount), "spell")
			return true
		"draw_school_event":
			game.draw_event(caster, {})
			return true
		"activate_last_nightmare":
			var assigned: EvocationState = context.get("last_assigned_nightmare")
			if assigned != null and game.is_evocation_in_play(assigned): game.activate_evocation(assigned, caster, {}, int(effect.get("strength_bonus", 0)))
			return true
		"activate_all_nightmares":
			for model in ForgottenEvocations.all_models(game):
				if model.archetype == "nightmare": game.activate_evocation(model, caster, {}, int(effect.get("strength_bonus", 0)))
			return true
		"defeat_nightmare_target":
			if target >= 0 and nightmare_count(game, target) >= 3 and not game.players[target].mage.in_cell:
				game.queue_resolution({"type": "damage", "step": "after_post_event", "forced_defeat": true, "attacker_id": caster, "target_player_index": target, "action_type": "spell", "source_model_type": "mage", "actual_damage": 0})
			return true
		"nightmare_room_effect":
			var options := ForgottenRules.rooms(game, context)
			options = options.filter(func(o): return nightmare_count(game, -1, o.room_id) > 0)
			if not DruidicRules.choose(game, caster, context, "nightmare_room", options, "Choose a Room containing a Nightmare.", false, "secondary_room"): return false
			var chosen = context.get("nightmare_room")
			context.erase("nightmare_room")
			return ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, chosen)) if chosen is String else true
		"move_mage_in_target_room":
			return resolve({"type": "filtered_model_effect", "target": "mage", "range": 0, "from_target": true, "effects": [{"type": "move_target_up_to", "distance": 1}]}, context)
		"repeat_for_events":
			for event in game.active_events:
				if event != null: ForgottenRules.queue(game, effect.effects, context.duplicate(true))
			return true
		"remember_trigger_count":
			context["school_traps_before"] = game.traps_resolved_count
			return true
		"power_per_triggered_trap":
			game.add_player_power(caster, maxi(0, game.traps_resolved_count - int(context.get("school_traps_before", game.traps_resolved_count))))
			return true
		"target_discard_hand":
			if target < 0: return true
			var amount: int = mini(int(effect.amount), game.players[target].hand.size())
			if not context.has("school_hand_discard") and amount > 0:
				var options: Array = []
				for i in game.players[target].hand.size():
					var card: SpellCardState = game.players[target].hand[i]
					options.append({"token": "hand:%d" % i, "value": card, "id": card.id, "name": card.card_name})
				game.request_effect_choice(target, "spell_discard", context, "school_hand_discard", options, amount, amount, "Choose Spells to discard.")
				return false
			var selected = context.get("school_hand_discard", [])
			var cards: Array = selected if selected is Array else [selected]
			context.erase("school_hand_discard")
			var removed := 0
			for card in cards:
				if game.players[target].hand.has(card):
					game.players[target].hand.erase(card)
					game.move_spell_to_memories_or_remove(target, card)
					removed += 1
			if bool(effect.get("steal_shortfall", false)): return ForgottenRules.queue(game, [{"type": "steal_power", "amount": int(effect.amount) - removed}], context)
			return true
		"convert_instability_reward_owners":
			var room = game.get_room_by_id(FamineRules.target_room(game, context))
			if room == null: return true
			context["school_instability_before"] = room.instability_cubes.duplicate()
			return ForgottenRules.queue(game, [{"type": "convert_instability", "amount": int(effect.amount)}, {"type": "reward_converted_owners"}], context)
		"reward_converted_owners":
			var room = game.get_room_by_id(FamineRules.target_room(game, context))
			if room == null: return true
			var owners: Array = []
			var before: Array = context.get("school_instability_before", [])
			for i in mini(before.size(), room.instability_cubes.size()):
				if before[i] != caster and room.instability_cubes[i] == caster and not owners.has(before[i]): owners.append(before[i])
			for owner in owners:
				if owner == -1: game.add_black_rose_power(1)
				else: game.add_player_power(owner, 1)
			return true
		"evocation_strength_damage_mage":
			if ev == null: return true
			var amount: int = game.get_evocation_effective_strength(ev)
			return ForgottenRules.queue(game, [{"type": "damage", "amount": amount}], ForgottenRules.target_context(context, {"target_type": "mage", "player_index": int(effect.mage)}))
		"place_instability_at_target":
			return FamineRules.relative_room_effect(game, caster, {"range": 0, "effects": [{"type": "place_instability", "amount": int(effect.amount)}]}, context)
		"convert_damage_store_black_rose":
			if target < 0: return true
			context["school_black_before"] = game.players[target].mage.damage_cubes.count(-1)
			return ForgottenRules.queue(game, [{"type": "convert_damage", "amount": int(effect.amount)}, {"type": "record_black_conversion"}], context)
		"record_black_conversion":
			context["school_converted_black_rose"] = maxi(0, int(context.get("school_black_before", 0)) - game.players[target].mage.damage_cubes.count(-1)) if target >= 0 else 0
			return true
		"if_jinxed":
			return ForgottenRules.queue(game, effect.effects, context) if target >= 0 and not game.players[target].mage.jinxes.is_empty() else true
		"for_school_mages":
			for id in game.get_play_order():
				if id == caster or game.players[id].mage.in_cell or DeathEffectResolver.ignores(context, id): continue
				if bool(effect.get("jinxed", false)) and game.players[id].mage.jinxes.is_empty(): continue
				if effect.has("range") and not game.is_room_within_effect_range(FamineRules.target_room(game, context), game.players[id].mage.room_id, effect.range): continue
				ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, {"target_type": "mage", "player_index": id}))
			return true
		"discard_jinx":
			context["jinx_discarded"] = false
			if target < 0: return true
			var options: Array = []
			for jinx in game.players[target].mage.jinxes:
				options.append({"token": "jinx:" + str(jinx.id), "value": jinx.id, "id": jinx.id, "card_kind": "jinxs", "name": ForgottenAttachments.definition("jinxes", jinx.id).name})
			if not DruidicRules.choose(game, caster if bool(effect.get("caster_chooses", false)) else target, context, "school_jinx_discard", options, "Choose a Jinx to discard.", bool(effect.get("optional", false))): return false
			var selected = context.get("school_jinx_discard")
			context.erase("school_jinx_discard")
			for jinx in game.players[target].mage.jinxes.duplicate():
				if selected is String and jinx.id == selected:
					game.players[target].mage.jinxes.erase(jinx)
					game.return_owner_cubes(target, int(jinx.progress))
					context["jinx_discarded"] = true
					var event := GameEvent.new("jinx_discarded")
					event.source_player_index = target
					game.queue_resolution({"type": "game_event", "event": event})
					if effect.has("effects"): ForgottenRules.queue(game, effect.effects, context)
					break
			game.refresh_all_player_boards()
			return true
		"place_target_colored_room":
			var options := ForgottenRules.rooms(game, context)
			options = options.filter(func(o): return str(game.get_room(o.room_id).get("color", "")) in effect.colors)
			if not DruidicRules.choose(game, caster, context, "colored_room", options, "Choose a Room of the indicated colour.", false, "secondary_room"): return false
			var selected = context.get("colored_room")
			context.erase("colored_room")
			if selected is String: game.effect_resolver._place_target_model_direct(game, context, selected)
			return true
		"pay_power_effect":
			if player.power < int(effect.amount): return true
			if not bool(effect.get("optional", true)):
				game.add_player_power(caster, -int(effect.amount))
				return ForgottenRules.queue(game, effect.effects, context)
			if not DruidicRules.choose(game, caster, context, "school_power_cost", [{"token": "pay", "value": true, "name": "Lose %d Power" % int(effect.amount)}], "Pay Power for this Effect?", true): return false
			var pay: bool = context.get("school_power_cost") == true
			context.erase("school_power_cost")
			if pay:
				game.add_player_power(caster, -int(effect.amount))
				return ForgottenRules.queue(game, effect.effects, context)
			return true
		"arm_prepared_reactions":
			var options: Array = []
			var cards: Array = player.ready_spells.duplicate()
			if player.quick_spell != null: cards.append(player.quick_spell)
			for ready in cards:
				if ready.spell.get_side(ready.use_dark_side).get("type") in ["trap", "protection"]:
					options.append({"token": "arm:%d" % ready.get_instance_id(), "value": ready, "id": ready.spell.id, "card_kind": "spells", "name": ready.spell.card_name})
			if options.is_empty(): return true
			if not context.has("school_arm"):
				game.request_effect_choice(caster, "prepared_reactions", context, "school_arm", options, 0, mini(int(effect.amount), options.size()), "Choose prepared Trap/Protection Spells to activate.")
				return false
			var selected = context.school_arm
			context.erase("school_arm")
			if not selected is Array: selected = [selected]
			for ready in selected:
				if not ready is ReadySpellState: continue
				player.ready_spells.erase(ready)
				if player.quick_spell == ready: player.quick_spell = null
				game.cast_ready_spell_state(caster, ready, {})
			return true
		"marked_entry_attack":
			if target < 0: return true
			return resolve({"type": "filtered_model_effect", "target": "evocation", "range": 0, "from_target": true,
				"effects": [{"type": "evocation_strength_damage_mage", "mage": target}]}, context)
		"opponent_protection_choice":
			if target < 0: return true
			var options: Array = [{"token": "ignore", "value": true, "name": "The caster ignores my Spell"}, {"token": "lose", "value": false, "name": "Lose 1 Power"}]
			if not DruidicRules.choose(game, target, context, "school_protection_choice", options, "Choose the outcome of the Protection."): return false
			var ignore: bool = context.get("school_protection_choice") == true
			context.erase("school_protection_choice")
			if ignore: return game.effect_resolver.resolve_effect({"type": "ignore_trigger_spell_effect", "include_forgotten": true}, context)
			game.add_player_power(target, -1)
			return true
		"steal_trophy":
			if target < 0 or game.players[target].trophies.is_empty(): return true
			var options: Array = []
			for i in game.players[target].trophies.size(): options.append({"token": "trophy:%d" % i, "value": i, "name": "Trophy of Player %d" % (game.players[target].trophies[i] + 1)})
			if not DruidicRules.choose(game, caster, context, "school_trophy", options, "Choose a Trophy to steal."): return false
			var i: int = int(context.get("school_trophy", -1))
			context.erase("school_trophy")
			if i >= 0 and i < game.players[target].trophies.size(): game.gain_player_trophy(caster, game.players[target].trophies.pop_at(i))
			return true
		"activate_mage_evocation":
			if target < 0: return true
			var options := ForgottenRules.models(game, context, "evocation")
			options = options.filter(func(o): return o.value.evocation.owner_id == target)
			if not DruidicRules.choose(game, caster, context, "school_activate_evocation", options, "Choose one of the target Mage's Evocations.", false, "evocation_target"): return false
			var selected = context.get("school_activate_evocation")
			context.erase("school_activate_evocation")
			if selected is Dictionary:
				var bonus: int = int(effect.get("bonus_if_jinx_discarded", 0)) if bool(context.get("jinx_discarded", false)) else 0
				game.activate_evocation(selected.evocation, caster, {"evocation_activation_speed_bonus": bonus}, bonus)
			return true
		"filtered_model_effect":
			var options := model_options(game, effect, context)
			if not DruidicRules.choose(game, caster, context, "school_model", options, str(effect.get("prompt", "Choose a Model.")), bool(effect.get("optional", false)), "model_target"):
				return false
			var selected = context.get("school_model")
			context.erase("school_model")
			if selected is Dictionary and effect.has("distinct_key"):
				var used: Array = context.get(str(effect.distinct_key), [])
				used.append(selected.get("evocation", selected.get("player_index", -1)))
				context[str(effect.distinct_key)] = used
			return ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, selected)) if selected is Dictionary else true
		"each_owned_evocation":
			var seen: Array = []
			for model in player.evocations:
				if model.assigned_mage >= 0 or (effect.has("archetype") and model.archetype != effect.archetype): continue
				if bool(effect.get("distinct_rooms", false)) and seen.has(model.room_id): continue
				seen.append(model.room_id)
				ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, {"target_type": "evocation", "evocation": model}))
			return true
		"scaled_school_effect":
			var amount: int = int(effect.get("base", 0))
			match str(effect.get("value", "")):
				"owned_evocations":
					for model in player.evocations:
						if model.assigned_mage < 0 and (not effect.has("archetype") or model.archetype == effect.archetype): amount += 1
				"target_strength": amount += game.get_evocation_effective_strength(ev) if ev != null else 0
				"stored_target_strength": amount += int(context.get("stored_target_strength", 0))
				"target_upgrades": amount += ev.upgrades.size() if ev != null else int(context.get("removed_upgrade_count", 0))
				"mage_strength": amount += player.get_mage_strength()
				"target_jinxes": amount += game.players[target].mage.jinxes.size() if target >= 0 else 0
				"instability_shortfall": amount += maxi(0, int(effect.total) - int(context.get("last_instability_placed", 0)))
				"conversion_shortfall": amount += maxi(0, int(effect.total) - int(context.get("last_damage_converted", 0)))
				"target_nightmares": amount += nightmare_count(game, target) if target >= 0 else 0
				"all_nightmares": amount += nightmare_count(game)
				"evocation_copies":
					for model in ForgottenEvocations.all_models(game):
						if model.evocation_id == str(effect.evocation_id): amount += 1
				"room_nightmares": amount += nightmare_count(game, -1, FamineRules.target_room(game, context))
				"board_events":
					for event in game.active_events:
						if event != null: amount += 1
				"all_altars":
					for model in ForgottenEvocations.all_models(game):
						if model.archetype == "altar": amount += 1
				"last_healed": amount += int(context.get("last_damage_healed", 0))
			amount = mini(int(effect.get("max", 999)), amount * int(effect.get("multiplier", 1)))
			var nested: Dictionary = effect.effect.duplicate(true)
			nested["amount"] = amount
			return ForgottenRules.queue(game, [nested], context)
		"remove_evocation_then":
			if ev == null or not game.is_evocation_in_play(ev) or (effect.has("max_health") and ev.health > int(effect.max_health)): return true
			if bool(effect.get("owned", false)) and ev.owner_id != caster: return true
			var nested := ForgottenRules.target_context(context, ev.room_id)
			nested["stored_target_strength"] = game.get_evocation_effective_strength(ev)
			nested["removed_archetype"] = ev.archetype
			if bool(effect.get("owner_effect", false)): nested["caster_id"] = ev.owner_id
			nested["removed_upgrade_count"] = ev.upgrades.size()
			if game.effect_resolver._remove_evocation(game, ev, context, true):
				return ForgottenRules.queue(game, effect.effects, nested)
			return true
		"pay_room_instability":
			var room = game.get_room_by_id(FamineRules.target_room(game, context))
			var amount: int = int(effect.amount)
			if room == null: return true
			var eligible: int = room.instability_cubes.count(caster) if bool(effect.get("own", false)) else room.instability_cubes.size()
			if eligible < amount: return true
			if not context.has("school_payment_started"):
				context["school_payment_started"] = true
				context.erase("effect_instability_removed")
			var cost := {"type": "remove_instability", "amount": amount}
			if bool(effect.get("own", false)): cost["owner"] = "self"
			if not game.effect_resolver.resolve_effect(cost, context): return false
			context.erase("school_payment_started")
			return ForgottenRules.queue(game, effect.effects, context)
		"if_effect_result":
			var value = context.get(str(effect.key))
			var valid: bool = value != null
			if value is bool: valid = value
			elif value is int or value is float: valid = value > 0
			return ForgottenRules.queue(game, effect.effects, context) if valid else true
		"summon_equipment":
			if not context.has("school_equipment"):
				var options: Array = []
				for data in game.evocation_database.evocations.values():
					if data.archetype != "equipment" or (effect.has("id") and data.id != effect.id): continue
					if game.get_available_evocation_copies(data.id) <= 0 or player.evocations.any(func(e): return e.evocation_id == data.id): continue
					options.append({"token": "equipment:" + data.id, "value": data.id, "id": data.id, "card_kind": "evocations", "name": data.name})
				if options.is_empty():
					context.erase("last_summoned_evocation")
					return true
				if options.size() == 1: context["school_equipment"] = options[0].value
				elif not DruidicRules.choose(game, caster, context, "school_equipment", options, "Choose an Equipment to summon."): return false
			var summoned = game.summon_evocation_for_effect(caster, str(context.school_equipment), player.mage.room_id, context)
			if summoned == null and not bool(context.get("summon_declined", false)): return false
			context.erase("school_equipment")
			context["last_summoned_evocation"] = summoned
			return true
		"damage_selected_evocation":
			if ev != null and game.is_evocation_in_play(ev):
				context["school_damage_dealt"] = 0
				context["last_damage_dealt"] = 0
				game.deal_damage_to_evocation(-1 if bool(effect.get("black_rose", false)) else caster, ev, int(effect.amount), [], "spell", "black_rose" if bool(effect.get("black_rose", false)) else "mage")
			return true
		"trigger_target_effect":
			var event: GameEvent = context.get("trigger_event")
			if event == null: return true
			var value: Dictionary = {"target_type": "mage", "player_index": event.target_player_index}
			if event.target_evocation != null: value = {"target_type": "evocation", "evocation": event.target_evocation}
			return ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, value))
		"chain_damage":
			var used: Array = context.get("school_chain_targets", [])
			if used.is_empty():
				used.append(context.get("target_evocation", context.get("target_player_index", -1)))
			var options := ForgottenRules.models(game, context, "model", effect.range)
			options = options.filter(func(o): return not used.has(o.value.get("evocation", o.value.get("player_index", -1))))
			if not DruidicRules.choose(game, caster, context, "chain_target", options, "Choose a different Model.", false, "model_target"): return false
			var selected = context.get("chain_target")
			context.erase("chain_target")
			if selected is Dictionary:
				used.append(selected.get("evocation", selected.get("player_index", -1)))
				context["school_chain_targets"] = used
				return ForgottenRules.queue(game, [{"type": "damage", "amount": effect.amount}], ForgottenRules.target_context(context, selected))
			return true
	return false

static func contains_effect(value, kind: String) -> bool:
	if value is Dictionary:
		if value.get("type") == kind: return true
		if kind == "summon" and (str(value.get("type", "")).begins_with("summon_") or value.get("type") == "choose_evocation_to_summon" or "summon" in value.get("keywords", [])): return true
		for nested in value.values():
			if contains_effect(nested, kind): return true
	elif value is Array:
		for nested in value:
			if contains_effect(nested, kind): return true
	return false

static func replace_current_spell(game, caster: int, context: Dictionary, cast: bool, candidates: Array = [], optional: bool = false) -> bool:
	var player: PlayerState = game.players[caster]
	var current: SpellCardState = context.get("resolving_spell")
	if current == null: return true
	var cards: Array = player.hand if candidates.is_empty() else candidates
	var options: Array = []
	for card in cards:
		if player.hand.has(card): options.append({"token": "replacement:%d" % card.get_instance_id(), "value": card, "id": card.id, "name": card.card_name, "card_kind": "spells"})
	if not DruidicRules.choose(game, caster, context, "school_replacement", options, "Choose the Spell to prepare in this slot.", optional): return false
	var replacement: SpellCardState = context.get("school_replacement")
	if replacement == null: return true
	if replacement.has_single_effect():
		context["school_replacement_dark"] = false
	elif not DruidicRules.choose(game, caster, context, "school_replacement_dark", [{"token": "light", "value": false, "name": "Light"}, {"token": "dark", "value": true, "name": "Dark"}], "Choose the active side."): return false
	var dark: bool = bool(context.school_replacement_dark)
	var slot: String = game._find_player_board_slot_for_spell(caster, current)
	if slot.is_empty(): return true
	# The current card is still resolving; register it through the existing
	# replacement API, which owns preparation, slot order and discard state.
	var revealed := RevealedSpellState.new(current, bool(context.get("spell_use_dark_side", false)), slot)
	player.revealed_spells.append(revealed)
	if game.replace_revealed_spell_from_hand(caster, revealed, replacement, dark):
		context["returned_to_hand"] = true
		for frame in game.resolution_stack:
			if frame.get("type") == "spell_resolution" and frame.get("spell") == current:
				frame.context["returned_to_hand"] = true
		if cast:
			var ready: ReadySpellState = player.quick_spell if slot == "Q" else player.get_next_ready_spell()
			game.queue_resolution({"type": "spell_cast", "step": "start", "player_index": caster, "ready_spell": ready, "source": "quick" if slot == "Q" else "ready", "context": {}})
	else:
		player.revealed_spells.erase(revealed)
	context.erase("school_replacement")
	context.erase("school_replacement_dark")
	return true
