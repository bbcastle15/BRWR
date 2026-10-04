class_name DeathEffectResolver
extends RefCounted

# Stateless extensions to the existing Effect / resolution-stack engine.
# Destiny ownership lives on MageState; trophies remain on PlayerState.
const TYPES := ["assign_destiny", "destiny_threshold", "defeat_with_destiny",
	"gain_trophy", "spend_trophy", "choose_effect", "for_each_mage",
	"remove_targets_evocation", "heal_per_assigned_destiny", "damage_per_destiny",
	"ignore_spell", "end_evocation_activation"]

static func ignores(context: Dictionary, player: int) -> bool:
	return player in context.get("ignored_spell_players", [])

static func mage_context(context: Dictionary, target: int) -> Dictionary:
	var result := context.duplicate(false)
	result.erase("target_evocation")
	result.erase("target_is_dummy")
	result["spell_target_type"] = "mage"
	result["target_model_type"] = "mage"
	result["target_player_index"] = target
	return result

static func queue_effects(game, effects: Array, context: Dictionary) -> bool:
	if effects.is_empty():
		return true
	return game.queue_resolution({"type": "effect_sequence", "resolver_kind": "spell",
		"effects": effects, "index": 0, "context": context})

static func queue_sentence(game, effects: Array, context: Dictionary) -> bool:
	var sentence_context := context.duplicate(false)
	sentence_context["sentence_damage_frames"] = []
	return game.queue_resolution({"type": "spell_sentence", "effects": effects,
		"context": sentence_context, "started": false})

static func defer_damage_post_event(frame: Dictionary) -> bool:
	var context: Dictionary = frame.get("result_context", {})
	if not context.has("sentence_damage_frames") or bool(frame.get("sentence_replayed", false)):
		return false
	var pending := frame.duplicate(false)
	pending["sentence_replayed"] = true
	var result_context := context.duplicate(false)
	result_context.erase("sentence_damage_frames")
	pending["result_context"] = result_context
	context.sentence_damage_frames.append(pending)
	return true

static func finish_sentence(game, context: Dictionary) -> bool:
	var pending: Array = context.get("sentence_damage_frames", [])
	if pending.is_empty():
		return true
	# Damage has already been applied. Reactions and defeats now follow play
	# order, after the whole sentence, including any conversion, has resolved.
	var order: Array = game.get_play_order()
	pending.sort_custom(func(a, b): return order.find(int(a.target_player_index)) < order.find(int(b.target_player_index)))
	game.queue_resolution(pending.pop_front())
	return false

static func process_sentence(game, frame: Dictionary) -> bool:
	if not bool(frame.started):
		frame["started"] = true
		queue_effects(game, frame.effects, frame.context)
		return false
	return finish_sentence(game, frame.context)

static func affected_mages(game, effect: Dictionary, context: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var center: String = str(context.get("target_room_id", ""))
	for id in game.get_play_order():
		var mage: MageState = game.players[id].mage
		if id == int(context.get("caster_id", -1)) or mage.in_cell or ignores(context, id):
			continue
		if mage.destiny_tokens.size() < int(effect.get("min_destiny", 0)):
			continue
		if effect.has("distance"):
			if center.is_empty() or game.get_hex_distance(game.room_id_to_coord(center), game.room_id_to_coord(mage.room_id)) > int(effect.distance):
				continue
		result.append(id)
	return result

static func prepare(game, effect: Dictionary, context: Dictionary) -> bool:
	var caster: int = int(context.get("caster_id", -1))
	match str(effect.get("type", "")):
		"choose_effect":
			if context.has("death_branch"):
				return true
			var options: Array = []
			var branches: Array = effect.get("choices", [])
			for i in range(branches.size()):
				options.append({"token": "branch:%d" % i, "value": i, "label": branches[i].label})
			return game._apply_or_request_secondary_choice(caster, "spell_branch", context,
				"death_branch", options, "Choose one Effect.")
		"spend_trophy":
			if context.has("spent_trophy_index"):
				return true
			var options: Array = []
			for i in range(game.players[caster].trophies.size()):
				options.append({"token": "trophy:%d" % i, "value": i,
					"label": "Discard Trophy of Player %d" % (game.players[caster].trophies[i] + 1)})
			if options.is_empty():
				context["spent_trophy_index"] = -1
				return true
			if bool(effect.get("optional", false)):
				options.append({"token": "trophy:decline", "value": -1, "label": "Keep my Trophies"})
			return game._apply_or_request_secondary_choice(caster, "trophy_cost", context,
				"spent_trophy_index", options, "Choose a Trophy to discard.")
		"remove_targets_evocation":
			var target: int = int(context.get("target_player_index", -1))
			if target < 0 or ignores(context, target) or context.has("target_owned_evocation"):
				return true
			var options: Array = []
			for evocation in game.players[target].evocations:
				if evocation.health <= int(effect.get("max_health", 3)):
					options.append({"token": "remove:%d" % evocation.board_number,
						"value": evocation, "label": evocation.get_display_name()})
			return game._apply_or_request_secondary_choice(target, "target_evocation", context,
				"target_owned_evocation", options, "Choose one of your Evocations to remove (maximum Health 3).")
	return true

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.get("game")
	var caster: int = int(context.get("caster_id", -1))
	if game == null or caster < 0 or caster >= game.players.size():
		return false
	var target: int = int(context.get("target_player_index", -1))
	if effect.get("target_from_trigger") == "source" and context.get("trigger_event") != null:
		target = context.trigger_event.source_player_index
	var valid_target: bool = target >= 0 and target < game.players.size() and target != caster and not ignores(context, target) and not bool(context.get("target_is_dummy", false))
	match str(effect.type):
		"assign_destiny":
			if not valid_target or game.players[target].mage.in_cell:
				return true
			var mage: MageState = game.players[target].mage
			var assigned: int = game.take_owner_cubes(caster, mini(int(effect.get("amount", 1)), 3 - mage.destiny_tokens.size()))
			for i in range(assigned):
				mage.destiny_tokens.append(caster)
			var counter: Dictionary = context.get("destiny_assignment_total", {})
			counter["count"] = int(counter.get("count", 0)) + assigned
			context["destiny_assignment_total"] = counter
			game.refresh_all_player_boards()
			return true
		"destiny_threshold":
			if valid_target and game.players[target].mage.destiny_tokens.size() >= int(effect.get("amount", 2)):
				if bool(effect.get("same_sentence", false)):
					return queue_sentence(game, effect.get("effects", []), context)
				return queue_effects(game, effect.get("effects", []), context)
			return true
		"defeat_with_destiny":
			if valid_target and not game.players[target].mage.in_cell and game.players[target].mage.destiny_tokens.size() >= 3:
				return game.queue_resolution({"type": "damage", "step": "after_post_event", "forced_defeat": true,
					"destiny_defeat": true, "attacker_id": caster, "target_player_index": target,
					"action_type": "spell", "source_model_type": "mage", "actual_damage": 0})
			return true
		"gain_trophy":
			if valid_target:
				game.players[caster].trophies.append(target)
				game.refresh_all_player_boards()
			return true
		"spend_trophy":
			var index: int = int(context.get("spent_trophy_index", -1))
			context.erase("spent_trophy_index")
			if index >= 0 and index < game.players[caster].trophies.size():
				game.players[caster].trophies.remove_at(index)
				game.refresh_all_player_boards()
				return queue_effects(game, effect.get("effects", []), context)
			return true
		"choose_effect":
			var index: int = int(context.get("death_branch", -1))
			context.erase("death_branch")
			var choices: Array = effect.get("choices", [])
			return queue_effects(game, choices[index].get("effects", []), context) if index >= 0 and index < choices.size() else false
		"for_each_mage":
			var targets := affected_mages(game, effect, context)
			# Share only the accumulation counter; target/choice state is per Mage.
			context["destiny_assignment_total"] = {"count": 0}
			var group_context := context.duplicate(false)
			group_context["sentence_damage_frames"] = []
			return game.queue_resolution({"type": "mage_effects", "targets": targets,
				"effects": effect.get("effects", []), "context": group_context, "index": 0})
		"remove_targets_evocation":
			var evocation: EvocationState = context.get("target_owned_evocation")
			context.erase("target_owned_evocation")
			if valid_target and evocation != null and evocation in game.players[target].evocations and evocation.health <= int(effect.get("max_health", 3)):
				return game.effect_resolver._remove_evocation(game, evocation, context, false)
			return true
		"heal_per_assigned_destiny":
			var amount: int = int(context.get("destiny_assignment_total", {}).get("count", 0))
			return queue_effects(game, [{"type": "heal", "amount": amount}], mage_context(context, caster))
		"damage_per_destiny":
			if valid_target:
				return queue_effects(game, [{"type": "damage", "amount": game.players[target].mage.destiny_tokens.size()}], context)
			return true
		"ignore_spell":
			var event: GameEvent = context.get("trigger_event")
			if event != null and event.data.get("spell_context") is Dictionary:
				var original: Dictionary = event.data.spell_context
				var ignored: Array = original.get("ignored_spell_players", [])
				if not caster in ignored:
					ignored.append(caster)
				original["ignored_spell_players"] = ignored
			return true
		"end_evocation_activation":
			var evocation: EvocationState = context.get("target_evocation")
			for frame in game.resolution_stack:
				if frame.get("type") == "evocation_activation" and frame.get("evocation") == evocation:
					frame["activation_ended"] = true
			return true
	return false

static func process_mages(game, frame: Dictionary) -> bool:
	var index: int = int(frame.get("index", 0))
	var targets: Array = frame.get("targets", [])
	if index >= targets.size():
		return finish_sentence(game, frame.context)
	frame["index"] = index + 1
	queue_effects(game, frame.effects, mage_context(frame.context, int(targets[index])))
	return false

static func process_destiny(game, frame: Dictionary) -> bool:
	var victim: int = int(frame.victim)
	var mage: MageState = game.players[victim].mage
	var order: Array = frame.get("order", [])
	var index: int = int(frame.get("index", 0))
	if index >= order.size():
		return true
	var owner: int = int(order[index])
	var count: int = mage.destiny_tokens.count(owner)
	if count == 0:
		frame["index"] = index + 1
		return false
	if not frame.has("destiny_count"):
		var options: Array = []
		for n in range(count + 1):
			options.append({"token": "destiny:%d" % n, "value": n,
				"label": "Resolve %d Destiny" % n if n > 0 else "Keep Destiny assigned"})
		game.request_effect_choice(owner, "destiny_resolution", frame, "destiny_count", options, 1, 1,
			"Player %d is defeated: choose how many Destiny tokens to resolve." % (victim + 1))
		return false
	var chosen: int = mini(int(frame.destiny_count), count)
	if chosen > 0:
		if not frame.has("conversion_context"):
			frame["conversion_context"] = {"game": game, "caster_id": owner,
				"target_player_index": victim, "spell_target_type": "mage"}
		var conversion: Dictionary = frame.conversion_context
		if not game._prepare_damage_conversion_choices({"type": "convert_damage", "amount": chosen}, conversion):
			return false
		game.effect_resolver.resolve_effect({"type": "convert_damage", "amount": chosen}, conversion)
		for n in range(chosen):
			mage.destiny_tokens.erase(owner)
			game.return_owner_cubes(owner, 1)
	frame.erase("destiny_count")
	frame.erase("conversion_context")
	frame["index"] = index + 1
	game.refresh_all_player_boards()
	return false

static func apply_trigger_target(side: Dictionary, context: Dictionary, event: GameEvent) -> void:
	var kind: String = str(side.get("trigger_target", ""))
	if kind.is_empty():
		return
	context.erase("target_evocation")
	context.erase("target_player_index")
	context["spell_target_type"] = str(side.get("target", ""))
	match kind:
		"source_mage", "damaged_mage":
			context["target_player_index"] = event.source_player_index if kind == "source_mage" else event.target_player_index
			context["target_model_type"] = "mage"
		"source_evocation":
			context["target_evocation"] = event.source_evocation
			context["target_model_type"] = "evocation"
		"event_room":
			context["target_room_id"] = event.target_room_id
		"caster_room":
			context["target_room_id"] = str(context.get("caster_room_id", ""))
		"self":
			context["target_player_index"] = int(context.caster_id)
			context["target_model_type"] = "mage"

static func announce_spell(game, context: Dictionary, effects: Array) -> bool:
	if str(context.get("spell_id", "")).is_empty():
		return false
	if not context.has("_spell_guard_announced"):
		context["_spell_guard_announced"] = []
		context["ignored_spell_players"] = []
	var card: SpellCardState = game.spell_database.get_spell(str(context.spell_id))
	if card == null or card.forgotten:
		return false
	var targets: Array[int] = []
	var target: int = int(context.get("target_player_index", -1))
	var caster: int = int(context.caster_id)
	if target >= 0 and target != caster:
		targets.append(target)
	for effect in effects:
		var affected: Array[int] = []
		var kind: String = str(effect.get("type", ""))
		if kind in ["damage", "convert_damage", "heal"] and str(context.get("spell_target_type", "")) in ["room", "area"]:
			affected = affected_mages(game, {"distance": 0}, context)
		elif kind == "damage_within_distance":
			affected = affected_mages(game, {"distance": int(effect.get("distance", 1))}, context)
		elif kind == "damage_all_models_of_type" and effect.get("model_type") == "mage":
			affected = affected_mages(game, {} if effect.get("scope") == "lodge" else {"distance": 0}, context)
		for id in affected:
			if not id in targets:
				targets.append(id)
	targets = targets.filter(func(id): return not id in context._spell_guard_announced)
	if targets.is_empty():
		return false
	context._spell_guard_announced.append_array(targets)
	var event := GameEvent.new("spell_effect_about_to_resolve")
	event.source_model_type = "mage"
	event.source_player_index = caster
	event.source_room_id = str(context.get("caster_room_id", ""))
	event.data = {"targets": targets, "spell_context": context}
	game.process_game_event(event)
	return true
