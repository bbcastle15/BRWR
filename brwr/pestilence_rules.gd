class_name PestilenceRules
extends RefCounted

const TYPES := ["assign_infectio", "infectio_condition", "pestis_damage_near_target", "instability_per_room_infectio", "remove_source_evocation", "infect_other_mages_in_target_room"]

static func assign(game, caster: int, target: int, amount: int) -> void:
	if target < 0 or target == caster or target >= game.players.size(): return
	var mage: MageState = game.players[target].mage
	var taken: int = game.take_owner_cubes(caster, mini(amount, maxi(0, 3 - mage.infectio_tokens.size())))
	for i in taken: mage.infectio_tokens.append(caster)
	game.refresh_player_board(target)

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.game
	var caster: int = int(context.caster_id)
	var target: int = int(context.get("target_player_index", -1))
	match str(effect.type):
		"infect_other_mages_in_target_room":
			for option in ForgottenRules.models(game, context, "mage", 0, FamineRules.target_room(game, context)):
				if int(option.value.player_index) != target: assign(game, caster, int(option.value.player_index), int(effect.amount))
			return true
		"assign_infectio":
			if context.get("spell_target_type") in ["room", "area"]:
				for option in ForgottenRules.models(game, context, "mage", 0, FamineRules.target_room(game, context)):
					if not DeathEffectResolver.ignores(context, int(option.value.player_index)): assign(game, caster, int(option.value.player_index), int(effect.amount))
			elif context.get("target_evocation") == null and not DeathEffectResolver.ignores(context, target): assign(game, caster, target, int(effect.amount))
			return true
		"infectio_condition":
			return ForgottenRules.queue(game, effect.effects, context) if target >= 0 and game.players[target].mage.infectio_tokens.size() >= int(effect.get("minimum", 3)) else true
		"pestis_damage_near_target":
			var count := 0
			for ev in ForgottenEvocations.all_models(game):
				if ev.evocation_id == "pestis" and game.is_room_within_effect_range(FamineRules.target_room(game, context), ev.room_id, 1): count += 1
			return ForgottenRules.queue(game, [{"type": "damage", "amount": mini(3, count)}], context)
		"instability_per_room_infectio":
			var count := 0
			for option in ForgottenRules.models(game, context, "mage", 0, FamineRules.target_room(game, context)):
				count += game.players[int(option.value.player_index)].mage.infectio_tokens.size()
			return ForgottenRules.queue(game, [{"type": "convert_instability", "amount": count}], context)
		"remove_source_evocation":
			var ev: EvocationState = context.get("source_evocation")
			if ev != null and game.is_evocation_in_play(ev): game.effect_resolver._remove_evocation(game, ev, context)
			return true
	return false

static func queue_tokens(game, target: int) -> void:
	if not game.players[target].mage.infectio_tokens.is_empty():
		game.queue_resolution({"type": "infectio_resolution", "target": target})

static func process_tokens(game, frame: Dictionary) -> bool:
	var target: int = int(frame.target)
	var mage: MageState = game.players[target].mage
	if frame.has("resolved_owner"):
		game.return_owner_cubes(int(frame.resolved_owner), 1)
		frame.erase("resolved_owner")
	if mage.infectio_tokens.is_empty(): return true
	var owner: int = mage.infectio_tokens.pop_front()
	# The token's cube returns after its damage and reactions have resolved.
	# Remove it from the assigned list now so a nested defeat cannot resolve it twice.
	frame["resolved_owner"] = owner
	game.deal_damage(owner, target, 1, "infectio")
	game.refresh_player_board(target)
	return false

static func on_event(game, event: GameEvent) -> void:
	if event.event_type != "evocation_defeated_or_removed" or event.target_evocation == null: return
	var ev: EvocationState = event.target_evocation
	if ev.evocation_id != "pestis": return
	var context := {"game": game, "caster_id": ev.owner_id, "source_evocation": ev, "caster_room_id": ev.room_id, "target_room_id": ev.room_id, "spell_target_type": "room", "resolver_kind": "evocation"}
	ForgottenRules.queue(game, [{"type": "choose_one", "options": [
		{"id": "infect", "label": "Assign 1 Infectio to a Mage in this Room", "effects": [{"type": "filtered_model_effect", "target": "mage", "range": 0, "from_target": true, "effects": [{"type": "assign_infectio", "amount": 1}]}]},
		{"id": "instability", "label": "Place 1 Instability in this Room", "effects": [{"type": "place_instability", "amount": 1}]}]}], context)
