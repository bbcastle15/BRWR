class_name FamineRules
extends RefCounted

# Codex Arcanum pp.19–21, 73. Starved cubes remain part of the owner's
# physical pool. Choices and all nested Effects use Game's resolution stack.
const EFFECT_TYPES := ["starve", "feed_choice", "relative_room_effect", "steal_solved_quest"]
const MAX_STARVED_CUBES := 10

static func target_room(game, context: Dictionary) -> String:
	# Movement/placement can change a Model's Room during the Spell. A cached
	# primary/trigger Room must not keep subsequent Effects at its old location.
	if str(context.get("spell_target_type", "")) not in ["room", "area"]:
		var evocation: EvocationState = context.get("target_evocation")
		if evocation != null:
			return evocation.room_id
		var target: int = int(context.get("target_player_index", -1))
		if target >= 0 and target < game.players.size():
			return game.players[target].mage.room_id
	return str(context.get("target_room_id", ""))

static func target_mages(game, effect: Dictionary, context: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if bool(context.get("target_is_dummy", false)):
		return result
	var caster: int = int(context.get("caster_id", -1))
	var area: bool = str(context.get("spell_target_type", "")) in ["room", "area"] or effect.has("range_from_target")
	var center: String = target_room(game, context)
	for id in game.get_play_order():
		if id == caster or game.players[id].mage.in_cell or DeathEffectResolver.ignores(context, id):
			continue
		if area:
			if not game.is_room_within_effect_range(center, game.players[id].mage.room_id, effect.get("range_from_target", 0)):
				continue
		elif str(context.get("target_model_type", "mage")) != "mage" or id != int(context.get("target_player_index", -1)):
			continue
		result.append(id)
	return result

static func refresh_cubes(game) -> void:
	game.refresh_all_player_boards()
	game.get_node("EventBoard").update_black_rose_cube_pool()

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.get("game")
	var caster: int = int(context.get("caster_id", -1))
	if game == null or caster < 0 or caster >= game.players.size():
		return false
	match str(effect.type):
		"starve":
			for id in target_mages(game, effect, context):
				var player: PlayerState = game.players[id]
				var taken: int = player.take_cubes(mini(maxi(0, int(effect.amount)), MAX_STARVED_CUBES - player.starved_cubes))
				player.starved_cubes += taken
				if taken > 0:
					print("Starve: Player ", id + 1, " placed ", taken, " Cubes on the Event Board | ", player.starved_cubes, "/10")
					if effect.has("lose_power_if_starved"):
						game.add_player_power(id, -int(effect.lose_power_if_starved))
			refresh_cubes(game)
			return true
		"feed_choice":
			return feed_choice(game, caster, effect, context)
		"relative_room_effect":
			return relative_room_effect(game, caster, effect, context)
		"steal_solved_quest":
			return steal_solved_quest(game, caster, context)
	return false

static func feed_choice(game, caster: int, effect: Dictionary, context: Dictionary) -> bool:
	var targets := target_mages(game, {}, context)
	var amount: int = maxi(1, int(effect.amount))
	var target: int = targets[0] if targets.size() == 1 else -1
	var available: bool = target >= 0 and game.players[target].starved_cubes >= amount
	var key := "famine_feed_branch"
	if not context.has(key):
		if not available:
			return ForgottenRules.queue(game, effect.effects, context)
		var options: Array = [
			{"token": "feed:normal", "value": false, "name": str(effect.normal_label)},
			{"token": "feed:alternative", "value": true, "name": "Feed %d — %s" % [amount, str(effect.feed_label)]}
		]
		game.request_effect_choice(caster, "spell_branch", context, key, options, 1, 1,
			"Choose the normal Effect or return %d of the target's Cubes to use Feed." % amount)
		return false
	var use_feed: bool = context.get(key) == true
	context.erase(key)
	if use_feed:
		# Revalidate and pay exactly once, before any sentence of the alternative.
		if not available:
			return true
		var player: PlayerState = game.players[target]
		player.starved_cubes -= amount
		player.return_cubes(amount)
		refresh_cubes(game)
		print("Feed ", amount, ": Player ", target + 1, " recovers Cubes from the Event Board")
	return ForgottenRules.queue(game, effect.feed_effects if use_feed else effect.effects, context)

static func relative_room_effect(game, caster: int, effect: Dictionary, context: Dictionary) -> bool:
	if bool(context.get("target_is_dummy", false)):
		return true
	var target: int = int(context.get("target_player_index", -1))
	if target >= 0 and (game.players[target].mage.in_cell or DeathEffectResolver.ignores(context, target)):
		return true
	var center: String = target_room(game, context)
	if not game.is_lodge_room_id(center):
		return true
	var options: Array = game._quest_room_choice_options(caster, {"range": effect.get("range", 0)}, center)
	if bool(effect.get("different_from_origin", false)):
		options = options.filter(func(option): return str(option.room_id) != center)
	if options.is_empty():
		return true
	if bool(effect.get("each", false)):
		for i in range(options.size() - 1, -1, -1):
			ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, str(options[i].room_id)))
		return true
	var key := "famine_relative_room"
	if not DruidicRules.choose(game, caster, context, key, options, "Choose a Room within %s of the target." % str(effect.get("range", 0)), false, "secondary_room"):
		return false
	var room_id: String = str(context.get(key, ""))
	context.erase(key)
	return ForgottenRules.queue(game, effect.effects, ForgottenRules.target_context(context, room_id))

static func steal_solved_quest(game, caster: int, context: Dictionary) -> bool:
	var targets := target_mages(game, {}, context)
	if targets.size() != 1:
		return true
	var target: int = targets[0]
	var options: Array = []
	var pile: Array = game.players[target].completed_quests
	for i in pile.size():
		if pile[i].is_solved():
			# Solved Quests are face down. Do not publish identities to the thief
			# (or serialize the underlying Quest object into an online choice).
			options.append({"token": "steal_quest:%d" % i, "value": i, "name": "Solved Quest %d" % (options.size() + 1), "card_kind": "quests", "hidden": true})
	if not DruidicRules.choose(game, caster, context, "famine_stolen_quest", options, "Choose a face-down Solved Quest to steal."):
		return false
	var index: int = int(context.get("famine_stolen_quest", -1))
	context.erase("famine_stolen_quest")
	if index >= 0 and index < pile.size() and pile[index].is_solved():
		var quest: QuestState = pile[index]
		pile.remove_at(index)
		quest.owner_id = caster
		game.players[caster].completed_quests.append(quest)
		# Its reward was already paid. Transfer the card for final scoring only.
		game.refresh_player_board(caster)
		game.refresh_player_board(target)
	return true
