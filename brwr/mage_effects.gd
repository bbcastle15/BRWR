class_name MageEffects
extends RefCounted

# Additional Codex sentences. These are ordinary frames in the shared Effect
# sequence: choices, damage, reactions and defeat always finish before resuming.
const TYPES := ["heal_caster", "fixed_room_effect", "summon_removed_evocation", "removed_owner_power",
	"black_rose_power_if_room_activated", "repeat_counted_effect", "draw_random_memories_up_to",
	"discard_quest_or_jinx", "discard_hand_for_effect", "move_then_effect", "if_mage_moved",
	"move_per_board_event", "attack_selected_target", "summon_in_unoccupied_type_room",
	"peek_forgotten_keep_bottom", "gain_target_trophy", "repeat_paid_effect", "pay_power_or_effect",
	"discard_triggering_persistent", "each_mage_move_attack", "record_personal_attack", "move_room_persistent"]

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.game
	var caster: int = int(context.caster_id)
	var player: PlayerState = game.players[caster]
	match str(effect.type):
		"heal_caster":
			return ForgottenRules.queue(game, [{"type":"self_effect", "effects":[{"type":"heal", "amount":int(effect.amount)}]}], context)
		"fixed_room_effect":
			return ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, str(effect.room_id)))
		"move_room_persistent":
			return move_room_persistent(game, player, caster, effect, context)
		"summon_removed_evocation":
			if str(context.get("removed_evocation_id", "")).is_empty(): return true
			return ForgottenRules.queue(game, [{"type":"summon_evocation", "evocation_id":context.removed_evocation_id}], context)
		"removed_owner_power":
			var owner: int = int(context.get("removed_evocation_owner", -2))
			if owner == -1: game.add_black_rose_power(int(effect.amount))
			elif owner >= 0: game.add_player_power(owner, int(effect.amount))
			return true
		"black_rose_power_if_room_activated":
			if FamineRules.target_room(game, context) == "black_rose" and bool(context.get("mage_room_activation_succeeded", false)):
				game.add_black_rose_power(int(effect.amount))
			return true
		"repeat_counted_effect":
			var sentences: Array = []
			for i in int(context.get(str(effect.key), 0)): sentences.append_array(effect.effects)
			return ForgottenRules.queue(game, sentences, context)
		"draw_random_memories_up_to":
			var maximum: int = mini(int(effect.amount), player.memories.size())
			var options: Array = []
			for count in range(maximum + 1): options.append({"token":"count:%d" % count, "value":count, "name":"Draw %d Spell(s)" % count})
			if not DruidicRules.choose(game, caster, context, "mage_memory_count", options, "Choose how many random Spells to draw from Memories."): return false
			var count: int = int(context.get("mage_memory_count", 0))
			context.erase("mage_memory_count")
			for i in count: game.draw_random_memory(caster)
			if count > 0:
				if effect.get("cost") == "power": game.add_player_power(caster, -count)
				elif effect.get("cost") == "damage": game.deal_damage(-1, caster, count, "spell")
			return true
		"discard_hand_for_effect":
			var options: Array = []
			for card in player.hand: options.append({"token":"hand:%d" % card.get_instance_id(), "value":card, "id":card.id, "name":card.card_name, "card_kind":"spells"})
			if not context.has("mage_hand_discard") and not options.is_empty():
				game.request_effect_choice(caster, "spell_discard", context, "mage_hand_discard", options, 0, mini(int(effect.amount), options.size()), "Choose Spells to discard, or skip.")
				return false
			var selected = context.get("mage_hand_discard", [])
			var cards: Array = selected if selected is Array else [selected]
			context.erase("mage_hand_discard")
			context["mage_discard_count"] = 0
			for card in cards:
				if player.hand.has(card):
					player.hand.erase(card)
					game.move_spell_to_memories_or_remove(caster, card)
					context.mage_discard_count += 1
			return ForgottenRules.queue(game, effect.get("effects", []), context)
		"discard_quest_or_jinx":
			var options: Array = []
			for quest in player.active_quests:
				options.append({"token":"quest:%d" % quest.get_instance_id(), "value":quest, "id":quest.get_id(), "name":quest.get_name(), "card_kind":"quests", "board_player_index":caster, "quest_section":"active", "quest_index":player.active_quests.find(quest)})
			for jinx in player.mage.jinxes:
				options.append({"token":"jinx:"+str(jinx.id), "value":jinx, "id":jinx.id, "name":ForgottenAttachments.definition("jinxes",jinx.id).name, "card_kind":"jinxs"})
			if not DruidicRules.choose(game,caster,context,"mage_discard_affliction",options,"Discard an Active Quest or an assigned Jinx."): return false
			var selected = context.get("mage_discard_affliction")
			context.erase("mage_discard_affliction")
			if selected is QuestState and player.active_quests.has(selected):
				player.active_quests.erase(selected)
				game.return_owner_cubes(caster, selected.progress)
				game.quest_discard.append(selected.card)
			elif selected is Dictionary and player.mage.jinxes.has(selected):
				player.mage.jinxes.erase(selected)
				game.return_owner_cubes(caster, int(selected.get("progress",0)))
				var event := GameEvent.new("jinx_discarded")
				event.source_player_index = caster
				game.queue_resolution({"type":"game_event","event":event})
			else: return true
			game.refresh_player_board(caster)
			return ForgottenRules.queue(game,effect.effects,context)
		"move_then_effect":
			var nested: Dictionary = context.duplicate(true)
			nested["mage_move_origin"] = player.mage.room_id
			return ForgottenRules.queue(game,[{"type":"mage_move","distance":1},{"type":"if_mage_moved","effects":effect.effects}],nested)
		"if_mage_moved":
			if not player.mage.in_cell and player.mage.room_id != str(context.get("mage_move_origin",player.mage.room_id)):
				return ForgottenRules.queue(game,effect.effects,context)
			return true
		"move_per_board_event":
			var nested: Dictionary = context.duplicate(true)
			nested["suppressed_trigger_types"] = effect.get("suppressed_trigger_types",[])
			return ForgottenRules.queue(game,[{"type":"mage_move","distance":ForgottenRules.event_count(game)}],nested)
		"attack_selected_target":
			var target: Dictionary = {"target_type":"mage","player_index":int(context.get("target_player_index",-1))}
			if context.get("target_evocation") != null: target = {"target_type":"evocation","evocation":context.target_evocation}
			context["druidic_attack"] = target
			var nested: Dictionary = effect.duplicate(true)
			if ForgottenRules.event_count(game) >= int(effect.get("ignore_protection_if_events",99)): nested["suppressed_trigger_types"] = ["protection"]
			return DruidicRules.mage_attack(game,caster,nested,context)
		"summon_in_unoccupied_type_room":
			var options := ForgottenRules.rooms(game,context,effect.get("range",1))
			options = options.filter(func(o): return not ForgottenEvocations.all_models(game).any(func(ev): return ev.evocation_id == str(effect.evocation_id) and ev.room_id == o.room_id))
			if not DruidicRules.choose(game,caster,context,"mage_summon_room",options,"Choose a Room without a %s." % str(effect.evocation_id).capitalize(),false,"secondary_room"): return false
			var selected = context.get("mage_summon_room")
			context.erase("mage_summon_room")
			if selected is String: return ForgottenRules.queue(game,[{"type":"summon_evocation","evocation_id":effect.evocation_id}],ForgottenRules.target_context(context,selected))
			return true
		"peek_forgotten_keep_bottom":
			var candidates: Array = []
			for i in mini(int(effect.amount),game.forgotten_deck.size()): candidates.append(game.forgotten_deck[-1-i])
			var options: Array = []
			for card in candidates: options.append({"token":"forgotten:%d" % card.get_instance_id(),"value":card,"id":card.id,"name":card.card_name,"card_kind":"spells"})
			if not DruidicRules.choose(game,caster,context,"mage_forgotten_keep",options,"Keep one Forgotten Spell; return the other to the bottom."): return false
			var kept: SpellCardState = context.get("mage_forgotten_keep")
			context.erase("mage_forgotten_keep")
			if kept == null: return true
			for card in candidates:
				game.forgotten_deck.erase(card)
				if card == kept:
					if str(card.light_side.get("type","")) == "on_draw": game.resolve_drawn_forgotten(caster,card)
					else: player.hand.append(card)
				else: game.forgotten_deck.push_front(card)
			game.announce_forgotten_draw(caster)
			return true
		"gain_target_trophy":
			var target: int = int(context.get("target_player_index",-1))
			if target >= 0: game.gain_player_trophy(caster,target)
			return true
		"repeat_paid_effect":
			var repeated: int = int(effect.get("iteration",0))
			var sequence: Array = effect.effects.duplicate(true)
			if repeated < int(effect.repeats):
				var again: Dictionary = effect.duplicate(true)
				again["iteration"] = repeated + 1
				sequence.append({"type":"conditional_payment","optional":true,"cost":{"type":"discard_spell","amount":1,"from":"hand","destination":"memories"},"effects":[again]})
			return ForgottenRules.queue(game,sequence,context)
		"pay_power_or_effect":
			var options: Array = [{"token":"skip","value":false,"name":"Do not pay"}]
			if player.power >= int(effect.amount): options.append({"token":"pay","value":true,"name":"Lose %d Power" % int(effect.amount)})
			if not DruidicRules.choose(game,caster,context,"mage_power_payment",options,"Pay Power to convert Instability?"): return false
			var paid: bool = context.get("mage_power_payment") == true
			context.erase("mage_power_payment")
			if paid: game.add_player_power(caster,-int(effect.amount))
			return ForgottenRules.queue(game,effect.effects if paid else effect.get("otherwise",[]),context)
		"discard_triggering_persistent":
			var active: ActiveSpellState = context.get("active_spell")
			if active != null and active.active:
				active.active = false
				player.remove_active_spell(active)
				game.move_spell_to_memories_or_remove(caster,active.spell)
				game._clear_player_board_spell_by_spell(caster,active.spell)
			return true
		"each_mage_move_attack":
			var order: Array = game.get_play_order().duplicate()
			while not order.is_empty() and order[0] != caster: order.push_back(order.pop_front())
			var counter := {"attacks":0,"owner":caster,"max":int(effect.get("max",3)),"power":int(effect.get("power_per_attack",1))}
			for i in range(order.size()-1,-1,-1):
				var actor: int = int(order[i])
				if game.players[actor].mage.in_cell: continue
				var nested: Dictionary = {"game":game,"caster_id":actor,"caster_room_id":game.players[actor].mage.room_id,"mage_attack_counter":counter}
				ForgottenRules.queue(game,[{"type":"optional_effect","prompt":"Drums of War: move up to 1 and perform a Physical Attack?","effects":[{"type":"mage_move","distance":1},{"type":"mage_attack","effects":[{"type":"record_personal_attack"}]}]}],nested)
			return true
		"record_personal_attack":
			var counter: Dictionary = context.get("mage_attack_counter",{})
			if not counter.is_empty() and int(counter.attacks) < int(counter.max):
				counter.attacks += 1
				game.add_player_power(int(counter.owner),int(counter.power))
			return true
	return false

static func move_room_persistent(game, player: PlayerState, caster: int, effect: Dictionary, context: Dictionary) -> bool:
	if not context.has("moving_persistent"):
		var tokens: Array = []
		for active in player.active_spells:
			var room_id: String = game.room_for_persistent(active)
			if room_id.is_empty(): continue
			var room = game.get_room_by_id(room_id)
			if room != null:
				tokens.append({
					"token": "persistent:%d" % active.get_instance_id(), "value": active,
					"id": active.spell.id, "card_kind": "spells",
					"name": "%s · %s" % [active.spell.card_name, room.room_name]
				})
		if tokens.is_empty(): return true
		if not DruidicRules.choose(game, caster, context, "moving_persistent", tokens,
				"Choose one of your Persistent tokens assigned to a Room.", false, "room_persistent"):
			return false
	var token: ActiveSpellState = context.moving_persistent
	var origin: String = game.room_for_persistent(token)
	if origin.is_empty() or token not in player.active_spells: return true
	var rooms: Array = ForgottenRules.rooms(game, context).filter(func(option): return option.room_id != origin)
	if rooms.is_empty(): return true
	if not DruidicRules.choose(game, caster, context, "persistent_destination", rooms,
			"Choose another Room for the Persistent token. That Room will activate.", false, "secondary_room"):
		return false
	var destination: String = context.persistent_destination
	context.erase("moving_persistent")
	context.erase("persistent_destination")
	token.context["target_room_id"] = destination
	return ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, destination))
