class_name DruidicRules
extends RefCounted

# School-specific rules use the existing resolution stack and physical cards.
# A transformed Mage remains a Mage; no Evocation slot or second model is made.
const EFFECT_TYPES := ["transform", "if_transformed", "self_effect", "room_effect",
	"mage_move", "mage_attack", "select_evocation_and_activate", "heal_owned_evocations",
	"damage_per_target_room_instability", "peek_grimoire_keep", "peek_quests_keep",
	"choose_memory_to_hand", "solve_active_quest", "mage_in_room_power"]

static func scoped_context(context: Dictionary) -> Dictionary:
	var result: Dictionary = context.duplicate(true)
	for key in ["target_player_index", "target_evocation", "target_model_type", "target_room_id",
		"selected_damage_owner_ids", "selected_instability_owner_ids", "spell_primary_target",
		"effect_target_room_id", "selected_evocation_to_activate", "target_is_dummy"]:
		result.erase(key)
	return result

static func sequence(game, effects: Array, context: Dictionary, kind: String = "spell") -> bool:
	return game.queue_resolution({"type": "effect_sequence", "resolver_kind": kind,
		"effects": effects, "index": 0, "context": context})

static func choose(game, player: int, context: Dictionary, key: String, options: Array,
		prompt: String, optional: bool = false, kind: String = "druidic_choice") -> bool:
	if context.has(key) or options.is_empty():
		return true
	context["game"] = game
	if not context.has("caster_id"):
		context["caster_id"] = player
	game.request_effect_choice(player, kind, context, key, options, 0 if optional else 1, 1, prompt)
	return false

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.get("game")
	var caster: int = int(context.get("caster_id", -1))
	if game == null or caster < 0 or caster >= game.players.size():
		return false
	var player = game.players[caster]
	match str(effect.type):
		"transform":
			return transform(game, caster, str(effect.form), context)
		"if_transformed":
			if player.get_transformation_id() == str(effect.form):
				sequence(game, effect.effects, context)
			return true
		"self_effect":
			var own := scoped_context(context)
			own.merge({"target_player_index": caster, "target_model_type": "mage",
				"spell_target_type": "self", "caster_room_id": player.mage.room_id}, true)
			return sequence(game, effect.effects, own)
		"room_effect":
			var options: Array = game._quest_room_choice_options(caster, effect, player.mage.room_id)
			if not choose(game, caster, context, "druidic_room", options, "Choose a Room.", false, "secondary_room"):
				return false
			if not context.has("druidic_room"):
				return true
			var nested := scoped_context(context)
			nested["target_room_id"] = str(context.druidic_room)
			nested["spell_target_type"] = "room"
			nested["caster_room_id"] = player.mage.room_id
			context.erase("druidic_room")
			nested.erase("druidic_room")
			return sequence(game, effect.effects, nested)
		"mage_move":
			if player.mage.in_cell:
				return true
			var nested: Dictionary = context.get("druidic_move", {})
			if nested.is_empty():
				nested = scoped_context(context)
				nested.merge({"target_player_index": caster, "target_model_type": "mage"}, true)
				context["druidic_move"] = nested
			var result: bool = game.effect_resolver.resolve_effect({"type": "move_target_up_to", "distance": int(effect.get("distance", 1))}, nested)
			if result:
				context.erase("druidic_move")
			return result
		"mage_attack":
			return mage_attack(game, caster, effect, context)
		"select_evocation_and_activate":
			var options: Array = game._quest_evocation_choice_options(caster, effect)
			if not choose(game, caster, context, "druidic_evocation", options, "Choose an Evocation to activate.", false, "evocation_target"):
				return false
			var evocation = context.get("druidic_evocation")
			context.erase("druidic_evocation")
			if evocation == null or not game.is_evocation_in_play(evocation):
				return true
			return game.activate_evocation(evocation, caster, {})
		"heal_owned_evocations":
			var options: Array = game._quest_evocation_choice_options(caster, {"target_owner": "self", "range": effect.get("range", 1)})
			# Push in reverse so the existing stack visits physical slots in order.
			for i in range(options.size() - 1, -1, -1):
				var nested := scoped_context(context)
				nested.merge({"target_model_type": "evocation", "target_evocation": options[i].value, "spell_target_type": "evocation"}, true)
				sequence(game, [{"type": "heal", "amount": int(effect.amount)}], nested)
			return true
		"damage_per_target_room_instability":
			var room_id: String = game.effect_resolver._target_model_room(context)
			var room = game.get_room_by_id(room_id)
			var amount: int = 0 if room == null else mini(int(effect.get("max_amount", 3)), room.instability_cubes.size() * int(effect.get("amount_per_cube", 1)))
			return game.effect_resolver.resolve_effect({"type": "damage", "amount": amount}, context)
		"peek_grimoire_keep", "peek_quests_keep":
			return peek_cards(game, caster, effect, context)
		"choose_memory_to_hand":
			var options: Array = []
			for i in player.memories.size():
				var card: SpellCardState = player.memories[i]
				options.append({"token": "memory:%d" % i, "value": card, "id": card.id, "name": card.card_name, "card_kind": "spells"})
			if not choose(game, caster, context, "druidic_memory", options, "Choose a Spell from Memories."):
				return false
			var selected = context.get("druidic_memory")
			context.erase("druidic_memory")
			if selected != null and player.memories.has(selected):
				player.memories.erase(selected)
				player.add_spell_to_hand(selected)
			return true
		"solve_active_quest":
			var options: Array = []
			for i in player.active_quests.size():
				var quest = player.active_quests[i]
				options.append({"token": "quest:%d" % i, "value": quest, "name": quest.get_name()})
			if not choose(game, caster, context, "druidic_quest", options, "Choose an Active Quest to solve."):
				return false
			var quest = context.get("druidic_quest")
			context.erase("druidic_quest")
			if quest != null and player.active_quests.has(quest):
				# Solving by an Effect bypasses the task, without a fake completion trigger.
				player.active_quests.erase(quest)
				quest.complete()
				player.completed_quests.append(quest)
				return game.quest_manager.solve_quest(game, caster, quest, {})
			return true
		"mage_in_room_power":
			var options: Array = game._quest_mage_choice_options(caster, {"range": 0, "exclude_self": true})
			if not choose(game, caster, context, "druidic_power_target", options, "Choose a Mage in your Room.", false, "mage_target"):
				return false
			var target: int = int(context.get("druidic_power_target", -1))
			context.erase("druidic_power_target")
			if target >= 0 and target != caster:
				var nested := scoped_context(context)
				nested.merge({"target_player_index": target, "target_model_type": "mage"}, true)
				return game.effect_resolver.resolve_effect({"type": "steal_power", "amount": int(effect.amount)}, nested)
	return false

static func transformation_available(game, caster: int, form: String) -> bool:
	# North Winds p.7: the three Ursa/Bjorn and Crocodilus/Loki models
	# are shared by summons and transformations.
	var evocation_id: String = "ursa" if form == "bjorn" else "crocodilus"
	var available: int = game.get_available_evocation_copies(evocation_id)
	if game.players[caster].get_transformation_id() == form:
		available += 1
	return available > 0

static func end_transformation(game, player_index: int) -> void:
	var player = game.players[player_index]
	if player.transformation == null:
		return
	var card: SpellCardState = player.transformation.spell
	player.transformation = null
	game.move_spell_to_memories_or_remove(player_index, card)
	game.refresh_model_tokens()
	game.refresh_player_board(player_index)
	if card.school_id == "druidic" and player.memories.has(card):
		game.queue_resolution({"type": "druidic_recover", "player_index": player_index, "card": card, "context": {}})

static func transform(game, caster: int, form: String, context: Dictionary) -> bool:
	if bool(context.get("became_transformation", false)):
		return true
	var player = game.players[caster]
	var card: SpellCardState = context.get("resolving_spell")
	if card == null or str(card.dark_side.get("transformation", {}).get("id", "")) != form:
		return false
	if not bool(context.get("transformation_previous_discarded", false)):
		context["transformation_previous_discarded"] = true
		if player.transformation != null:
			end_transformation(game, caster)
			# The recovery is a nested frame, not a retry of the Spell effect.
	if player.mage.in_cell or not transformation_available(game, caster, form):
		return true
	player.transformation = RevealedSpellState.new(card, false)
	context["became_transformation"] = true
	game._clear_player_board_spell_by_spell(caster, card)
	for evocation in player.evocations.duplicate():
		if evocation.archetype == "equipment":
			game.emit_evocation_defeated_or_removed(evocation, "removed")
			game.finalize_evocation_removal(evocation)
	game.refresh_model_tokens()
	game.refresh_player_board(caster)
	print("Player ", caster + 1, " transformed into ", form.capitalize())
	return true

static func mage_attack(game, caster: int, effect: Dictionary, context: Dictionary) -> bool:
	var player = game.players[caster]
	if player.mage.in_cell:
		return true
	var options: Array = game._spell_model_target_options(caster, {"range": effect.get("range", 0)})
	var valid: Array = []
	for option in options:
		if str(option.get("target_type", "")) == "dummy":
			continue
		var value: Dictionary = option.get("value", {})
		if value.get("target_type") == "evocation" and not game._valid_mage_physical_attack_evocation(caster, value.evocation, int(effect.get("range", 0))):
			continue
		valid.append(option)
	if not choose(game, caster, context, "druidic_attack", valid, "Choose a target for the Physical Attack.", bool(effect.get("optional", false)), "model_target"):
		return false
	var target = context.get("druidic_attack")
	context.erase("druidic_attack")
	if not target is Dictionary or target.is_empty():
		return true
	if int(effect.get("followup_damage", 0)) > 0:
		sequence(game, [{"type": "damage", "amount": int(effect.followup_damage)}], ForgottenRules.target_context(context, target), "physical")
	if target.get("target_type") == "mage":
		var victim: int = int(target.get("player_index", -1))
		if victim < 0 or game.players[victim].mage.in_cell or not game.is_room_within_effect_range(player.mage.room_id, game.players[victim].mage.room_id, int(effect.get("range", 0))):
			return true
		# Apply the additional sentence after the attack and its reactions.
		if int(effect.get("target_mage_lose_power", 0)) > 0:
			game.queue_resolution({"type": "druidic_attack_power", "target": victim, "amount": int(effect.target_mage_lose_power)})
		ForgottenPassives.physical_attack(game, caster)
		game.deal_damage(caster, victim, player.get_mage_strength() + int(effect.get("strength_bonus", 0)), "physical_attack")
	elif target.get("target_type") == "evocation":
		var evocation = target.get("evocation")
		if game._valid_mage_physical_attack_evocation(caster, evocation, int(effect.get("range", 0))):
			ForgottenPassives.physical_attack(game, caster)
			game.deal_damage_to_evocation(caster, evocation, player.get_mage_strength() + int(effect.get("strength_bonus", 0)), [], "physical_attack", "mage", null)
	return true

static func action_options(game, player_index: int) -> Array:
	var player = game.players[player_index]
	var result: Array = []
	if player.mage.in_cell or not player.has_physical_action():
		return result
	for action in player.get_transformation_data().get("actions", []):
		result.append({"kind": "transformation", "label": "%s · %s" % [player.get_transformation_id().capitalize(), action.name],
			"action": {"type": "transformation", "action_id": str(action.id)}, "consumes_action": true})
	return result

static func perform_action(game, player_index: int, action_id: String, free: bool = false) -> bool:
	var player = game.players[player_index]
	if player.mage.in_cell or player.transformation == null or (not free and not player.has_physical_action()):
		return false
	for action in player.get_transformation_data().get("actions", []):
		if str(action.id) != action_id:
			continue
		if not free:
			player.exhaust_physical_action()
		game.refresh_player_board(player_index)
		return game.queue_resolution({"type": "druidic_action", "player_index": player_index, "index": 0,
			"effects": action.effects, "context": {"game": game, "caster_id": player_index,
			"caster_room_id": player.mage.room_id, "action_type": "physical_attack"}})
	return false

static func process_frame(game, frame: Dictionary) -> bool:
	match str(frame.type):
		"druidic_action":
			if bool(frame.get("cancelled_by_defeat", false)) or game.players[int(frame.player_index)].mage.in_cell:
				return true
			var index: int = int(frame.index)
			if index >= frame.effects.size():
				return true
			frame.index = index + 1
			sequence(game, [frame.effects[index]], frame.context, "physical")
			return false
		"druidic_recover":
			var player = game.players[int(frame.player_index)]
			if not player.memories.has(frame.card):
				return true
			var options: Array = [{"token": "communion:recover", "value": true, "name": "Return " + frame.card.card_name + " to Hand", "id": frame.card.id, "card_kind": "spells"}]
			if not choose(game, int(frame.player_index), frame.context, "recover", options, "Communion with Nature: return the transformation card to Hand?", true):
				return false
			if frame.context.get("recover") == true:
				player.memories.erase(frame.card)
				player.hand.append(frame.card)
			game.refresh_player_board(int(frame.player_index))
			return true
		"druidic_attack_power":
			game.add_player_power(int(frame.target), -int(frame.amount))
			return true
		"druidic_phase_start":
			return process_phase_start(game, frame)
		"druidic_study":
			return process_study(game, frame)
		"druidic_ursa_loss":
			return process_ursa_loss(game, frame)
	return true

static func process_phase_start(game, frame: Dictionary) -> bool:
	if not bool(frame.get("events_started", false)):
		frame["events_started"] = true
		game.resolve_events_for_phase(game.PHASE_EVOCATION, frame.get("phase_context", {}))
		return false
	if not bool(frame.get("nightmares_started", false)):
		frame["nightmares_started"] = true
		game.queue_resolution({"type": "forgotten_nightmare_phase", "context": {}})
		return false
	var order: Array = frame.order
	var index: int = int(frame.get("index", 0))
	if index >= order.size():
		return true
	var caster: int = int(order[index])
	var player = game.players[caster]
	var options: Array = []
	if not player.mage.in_cell:
		for action in player.get_transformation_data().get("actions", []):
			options.append({"token": "form:" + str(action.id), "value": str(action.id), "name": str(action.name)})
	var context: Dictionary = frame.get("context", {})
	frame["context"] = context
	if not choose(game, caster, context, "action", options, "Transformation: perform one free Physical Action, or skip.", true):
		return false
	frame.index = index + 1
	frame.context = {}
	if context.get("action") is String:
		perform_action(game, caster, str(context.action), true)
	return false

static func process_study(game, frame: Dictionary) -> bool:
	if not bool(frame.get("events_started", false)):
		frame["events_started"] = true
		game.resolve_events_for_phase(game.PHASE_STUDY, frame.get("phase_context", {}))
		return false
	var order: Array = frame.order
	var index: int = int(frame.get("index", 0))
	if index >= order.size():
		return true
	var caster: int = int(order[index])
	var player = game.players[caster]
	var context: Dictionary = frame.get("context", {})
	frame["context"] = context
	var options: Array = []
	if game.current_round == 1:
		for zone in ["grimoire", "memories"]:
			var cards: Array = player.get(zone)
			for i in cards.size():
				var card: SpellCardState = cards[i]
				if card.school_id == "druidic" and card.dark_side.has("transformation"):
					options.append({"token": "feral:%s:%d" % [zone, i], "value": {"card": card, "zone": zone}, "name": card.card_name, "id": card.id, "card_kind": "spells"})
	if not choose(game, caster, context, "feral", options, "Feral Magic: choose a transformation, or draw two normally.", true):
		return false
	frame.index = index + 1
	frame.context = {}
	var draws: int = 2
	var selection = context.get("feral")
	if selection is Dictionary and selection.has("card"):
		var cards: Array = player.get(str(selection.zone))
		if cards.has(selection.card):
			cards.erase(selection.card)
			player.hand.append(selection.card)
			game.shuffle_with_rng(player.grimoire)
			draws = 1
	for i in draws:
		game.draw_player_spell(caster)
	return false

static func peek_cards(game, caster: int, effect: Dictionary, context: Dictionary) -> bool:
	var player = game.players[caster]
	var quests: bool = str(effect.type) == "peek_quests_keep"
	if not context.has("druidic_peek_cards"):
		var cards: Array = []
		for i in int(effect.get("amount", 1)):
			if quests:
				var deck: Array = game.quest_decks.get(int(context.get("quest_draw_moon", game.current_moon)), [])
				if deck.is_empty():
					break
				cards.append(deck.pop_back())
			else:
				var drawn: SpellCardState = game.draw_player_spell(caster)
				if drawn == null:
					break
				player.hand.erase(drawn)
				cards.append(drawn)
		context["druidic_peek_cards"] = cards
	var cards: Array = context.druidic_peek_cards
	var options: Array = []
	for i in cards.size():
		options.append({"token": "peek:%d" % i, "value": i, "id": cards[i].id,
			"name": cards[i].card_name, "card_kind": "quests" if quests else "spells"})
	if not choose(game, caster, context, "druidic_keep", options, "Choose one card to keep; discard the others."):
		return false
	var selected: int = int(context.get("druidic_keep", -1))
	for i in cards.size():
		if quests:
			if i == selected:
				var quest := QuestState.new(cards[i], caster)
				if bool(cards[i].task.get("reveal_immediately", false)):
					quest.reveal()
				player.active_quests.append(quest)
			else:
				game.quest_discard.append(cards[i])
		elif i == selected:
			player.hand.append(cards[i])
		else:
			game.move_spell_to_memories_or_remove(caster, cards[i])
	context.erase("druidic_peek_cards")
	context.erase("druidic_keep")
	game.refresh_player_board(caster)
	return true

static func on_evocation_attack(game, evocation: EvocationState, controller: int) -> void:
	for ability in game.get_evocation_abilities(evocation):
		if ability.get("type") != "power_on_attack_if_not_leading":
			continue
		var power: int = game.players[controller].power
		if game.players.any(func(player): return player.power > power):
			game.add_player_power(controller, int(ability.get("amount", 1)))

static func on_evocation_loss(game, event: GameEvent) -> void:
	if event.event_type != "evocation_defeated_or_removed" or event.target_evocation == null:
		return
	for ability in game.get_evocation_abilities(event.target_evocation):
		if ability.get("type") == "damage_room_on_defeat_or_removal":
			game.queue_resolution({"type": "druidic_ursa_loss", "evocation": event.target_evocation,
				"room": event.target_room_id, "controller": game.get_evocation_controller_id(event.target_evocation),
				"amount": int(ability.get("amount", 1)), "index": 0})

static func process_ursa_loss(game, frame: Dictionary) -> bool:
	if not frame.has("targets"):
		var targets: Array = []
		for player in game.players:
			if player.player_index != int(frame.controller) and not player.mage.in_cell and player.mage.room_id == frame.room:
				targets.append(player.player_index)
			for evocation in player.evocations:
				if evocation != frame.evocation and evocation.room_id == frame.room and not evocation.is_defeated() and game.get_evocation_controller_id(evocation) != int(frame.controller):
					targets.append(evocation)
		frame.targets = targets
	if int(frame.index) >= frame.targets.size():
		return true
	var target = frame.targets[int(frame.index)]
	frame.index = int(frame.index) + 1
	if target is EvocationState:
		if game.is_evocation_in_play(target):
			game.deal_damage_to_evocation(int(frame.controller), target, int(frame.amount), [], "evocation_ability", "evocation", frame.evocation)
	elif not game.players[int(target)].mage.in_cell:
		game.queue_resolution({"type": "damage", "step": "pre_event", "attacker_id": int(frame.controller),
			"target_player_index": int(target), "amount": int(frame.amount), "action_type": "evocation_ability",
			"source_model_type": "evocation", "source_evocation": frame.evocation,
			"source_room_id": frame.room, "suppressed_trigger_types": []})
	return false
