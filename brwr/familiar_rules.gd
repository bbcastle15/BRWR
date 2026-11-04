class_name FamiliarRules
extends RefCounted

# Magister pp. 8–10, with the FAQ's Eracleto setup correction. A Familiar
# occupies one ordinary Evocation slot; Guard is a position, not a second Mage.
static func is_familiar(ev: EvocationState) -> bool:
	return ev != null and bool(ev.definition.get("familiar",false))

static func guarded(ev: EvocationState) -> bool:
	return is_familiar(ev) and ev.familiar_guard

static func attack_bonus(game, ev: EvocationState, target_damage: int) -> int:
	if guarded(ev) or target_damage > 0: return 0
	return int(ForgottenEvocations.ability(game,ev,"attack_bonus_against_undamaged").get("amount",0))

static func guard(game, owner: int) -> EvocationState:
	for ev in game.players[owner].evocations:
		if guarded(ev) and not ev.is_defeated(): return ev
	return null

static func sync(game) -> void:
	for player in game.players:
		for ev in player.evocations:
			if guarded(ev): ev.room_id = player.mage.room_id

static func summon(game, caster: int, id: String, context: Dictionary) -> bool:
	var player: PlayerState = game.players[caster]
	if player.mage.in_cell or player.evocations.any(func(ev):return is_familiar(ev)): return true
	if not context.has("familiar_summon_started"):
		context["familiar_summon_started"] = true
		return ForgottenRules.queue(game,[{"type":"summon_evocation","evocation_id":id},{"type":"familiar_guard_summoned"}],ForgottenRules.target_context(context,player.mage.room_id))
	return true

static func set_guard(game, ev: EvocationState, guarding: bool) -> void:
	ev.familiar_guard = guarding
	if guarding: ev.room_id = game.players[ev.owner_id].mage.room_id
	game.refresh_model_tokens()
	game.refresh_player_board(ev.owner_id)

static func actions(game, owner: int) -> Array:
	var result: Array = []
	var player: PlayerState = game.players[owner]
	if player.mage.in_cell: return result
	for ev in player.evocations:
		if not is_familiar(ev) or not ev.familiar_action_available or ev.is_defeated(): continue
		var choices: Array = ["assault","concentration"] if ev.familiar_guard else (["flanking"] if ev.room_id == player.mage.room_id else [])
		for choice in choices:
			result.append({"kind":"familiar","label":ev.evocation_name+" · "+str(choice).capitalize(),"action":{"type":"familiar","action_id":choice,"evocation_id":ev.evocation_id},"consumes_action":true})
	return result

static func perform(game, owner: int, id: String, action: String) -> bool:
	var legal := actions(game,owner)
	if not legal.any(func(a):return a.action.action_id == action and a.action.evocation_id == id): return false
	var ev: EvocationState
	for candidate in game.players[owner].evocations:
		if candidate.evocation_id == id: ev = candidate
	if ev == null: return false
	ev.familiar_action_available = false
	game.append_public_log("%s · %s" % [ev.evocation_name,action.capitalize()])
	var context := {"game":game,"caster_id":owner,"source_evocation":ev,"resolver_kind":"evocation","caster_room_id":ev.room_id}
	match action:
		"assault":
			set_guard(game,ev,false)
			game.activate_evocation(ev,owner,{})
			return true
		"flanking": set_guard(game,ev,true)
		"concentration":
			return ForgottenRules.queue(game,[{"type":"choose_one","prompt":"Eracleto · Concentration","options":[
				{"id":"instability","label":"Remove 1 Instability here, then place 1 within 2","effects":[{"type":"self_room_effect","effects":[{"type":"remove_instability","amount":1}]},{"type":"room_effect","range":2,"effects":[{"type":"place_instability","amount":1}]}]},
				{"id":"hunt","label":"Switch to Hunt and activate Eracleto","effects":[{"type":"familiar_assault"}]}]}],context)
	return true

static func before_mage_cell(game, owner: int, defeated: bool = false) -> void:
	var ev := guard(game,owner)
	if ev != null and (defeated or game.players[owner].mage.is_defeated()): ev.familiar_guard = false

static func refresh_token(player: PlayerState) -> void:
	for ev in player.evocations:
		if is_familiar(ev): ev.familiar_action_available = true

static func cleanup(game, frame: Dictionary) -> bool:
	if not frame.has("remaining"):
		frame["remaining"] = ForgottenEvocations.all_models(game).filter(func(ev):return is_familiar(ev) and not ev.familiar_guard)
	while not frame.remaining.is_empty():
		var ev: EvocationState = frame.remaining[0]
		var player: PlayerState = game.players[ev.owner_id]
		if not game.is_evocation_in_play(ev) or player.mage.in_cell or not game.is_room_within_effect_range(ev.room_id,player.mage.room_id,1):
			frame.remaining.pop_front()
			continue
		if not DruidicRules.choose(game,ev.owner_id,frame,"guard",[{"token":"guard","value":true,"name":"Return to Guard"}],"Return %s to Guard without spending its Action token?" % ev.evocation_name,true): return false
		if frame.get("guard") == true: set_guard(game,ev,true)
		frame.erase("guard")
		frame.remaining.pop_front()
	return true

static func distribute_damage(game, frame: Dictionary) -> bool:
	if bool(frame.get("familiar_checked",false)): return true
	var owner: int = int(frame.target_player_index)
	var ev := guard(game,owner)
	if ev == null:
		frame["familiar_checked"] = true
		return true
	var options: Array = []
	for n in range(mini(int(frame.amount),ev.get_remaining_health())+1): options.append({"token":"guard:%d" % n,"value":n,"name":"Assign %d Damage to %s" % [n,ev.evocation_name]})
	if not DruidicRules.choose(game,owner,frame,"familiar_damage",options,"Distribute incoming Damage between your Mage and the Familiar."): return false
	var amount: int = int(frame.get("familiar_damage",0))
	frame["familiar_checked"] = true
	if amount > 0:
		frame.amount = int(frame.amount)-amount
		var event: GameEvent = frame.get("event")
		if event != null: event.amount = int(frame.amount)
		game.queue_resolution({"type":"evocation_damage","evocation":ev,"amount":amount,"attacker_id":frame.attacker_id,"action_type":frame.action_type,"source_model_type":frame.get("source_model_type","mage"),"source_evocation":frame.get("source_evocation"),"damage_ability_parent":frame,"suppressed_trigger_types":frame.get("suppressed_trigger_types",[])})
		return false
	return true

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.game
	var caster: int = int(context.caster_id)
	match str(effect.type):
		"summon_familiar": return summon(game,caster,str(effect.id),context)
		"familiar_guard_summoned":
			var ev: EvocationState = context.get("last_summoned_evocation")
			if is_familiar(ev):
				ev.familiar_action_available = true
				set_guard(game,ev,true)
		"familiar_assault":
			var ev: EvocationState = context.get("source_evocation")
			if is_familiar(ev) and game.is_evocation_in_play(ev):
				set_guard(game,ev,false)
				game.activate_evocation(ev,caster,{})
	return true
