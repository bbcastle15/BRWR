class_name AvatarEvents
extends RefCounted

const PASSIVES := ["avatar_room_activation", "avatar_convert_new_instability"]

static func on_event(game, event: GameEvent) -> void:
	if game.avatar == null: return
	for card in game.active_events:
		if card == null or card.phase != game.current_phase: continue
		for effect in card.effects:
			if effect.type == "avatar_room_activation" and event.event_type == "room_effect_resolved" and event.source_player_index >= 0 and not AvatarRules.is_avatar(game, event.source_player_index):
				if event.source_room_id != "throne" and str(event.data.get("room_color", "")) in effect.colors:
					game.queue_resolution({"type": "avatar_event", "effect": effect,
						"target": event.source_player_index, "context": {}})
			if effect.type == "avatar_convert_new_instability" and event.event_type == "instability_placed" and event.amount >= int(effect.minimum) and event.source_player_index >= 0 and not AvatarRules.is_avatar(game, event.source_player_index):
				game.queue_resolution({"type": "avatar_event", "effect": effect, "target": event.source_player_index,
					"room_id": event.source_room_id, "context": {}})

static func process(game, frame: Dictionary) -> bool:
	if game.avatar == null: return true
	var effect: Dictionary = frame.effect
	var kind: String = str(effect.type)
	var actor: int = game.avatar.player_index
	var mage: MageState = game.players[actor].mage
	var amount: int = int(effect.get("amount", 1))
	if not frame.has("targets"):
		frame["targets"] = AvatarRules.human_order(game)
		if frame.has("target"): frame["targets"] = [int(frame.target)]
		if kind == "avatar_crown_power_damage": frame["targets"] = [game.crown_owner_id]
		if kind in ["avatar_instability_if_color", "avatar_near_black_rose_instability"]:
			frame["targets"] = [actor]
	var cursor: int = int(frame.get("cursor", 0))
	if cursor >= frame.targets.size(): return true
	var target: int = int(frame.targets[cursor])
	var player: PlayerState = game.players[target]
	match kind:
		"avatar_instability_if_color":
			_advance(frame)
			if not mage.in_cell and mage.room_id != "throne" and str(game.get_room_by_id(mage.room_id).room_data.get("color", "")) in effect.colors:
				game.place_instability(actor, mage.room_id, amount)
		"avatar_near_black_rose_instability":
			_advance(frame)
			var br: String = str(game.avatar.definition.setup_room)
			if not mage.in_cell and AvatarRules.distance(game, mage.room_id, br) <= int(effect.range): game.place_instability(actor, br, amount)
		"avatar_convert_new_instability":
			_advance(frame)
			var room = game.get_room_by_id(str(frame.get("room_id", "")))
			if room != null:
				for index in range(room.instability_cubes.size() - 1, -1, -1):
					if int(room.instability_cubes[index]) != target: continue
					if game.take_owner_cubes(-1, 1) > 0:
						game.return_owner_cubes(target, 1)
						room.convert_instability_cube(target, -1, index)
					break
		"avatar_crown_power_damage", "avatar_room_activation":
			if not bool(frame.get("power_done", false)):
				frame["power_done"] = true
				game.add_player_power(target, int(effect.power))
				return false
			_advance(frame)
			game.deal_damage(-1, target, int(effect.damage), "event")
		"avatar_convert_damaged_mages":
			_advance(frame)
			if player.mage.get_damage_from(-1) > 0: AvatarEffects.rightmost_conversion(game, player.mage.damage_cubes, amount)
		"avatar_compare_power":
			_advance(frame)
			if player.power < game.black_rose_power: game.add_player_power(target, 1)
			elif player.power > game.black_rose_power: game.add_player_power(target, -1)
		"avatar_power_or_evocation":
			var options: Array = [{"token": "lose_power", "value": null, "name": "Lose 1 Power"}]
			for ev in player.evocations:
				if ev.assigned_mage < 0: options.append({"token": "evocation:%d" % ev.get_instance_id(), "value": ev, "name": "Remove " + ev.get_display_name()})
			if not AvatarEffects._human_choice(game, target, frame, "choice", options, "Revolt of the Servants · lose 1 Power or remove an Evocation."): return false
			var chosen: EvocationState = frame.choice
			_advance(frame)
			if chosen == null: game.add_player_power(target, -1)
			else: AvatarEffects.remove_evocation(game, chosen)
		"avatar_trophy_power_loss":
			_advance(frame)
			if actor in player.trophies: game.add_player_power(target, -amount)
		"avatar_discard_solved_quest":
			var options: Array = []
			for quest in player.completed_quests:
				if quest.is_solved(): options.append({"token": "quest:%d" % quest.get_instance_id(), "value": quest, "name": quest.get_name()})
			if not options.is_empty():
				if not AvatarEffects._human_choice(game, target, frame, "choice", options, "Manipulating the Past · discard one solved Quest."): return false
				game.quest_manager.discard_completed_quest(game, target, frame.choice)
			_advance(frame)
		"avatar_damaged_power_loss":
			_advance(frame)
			if player.mage.get_damage_from(-1) > 0: game.add_player_power(target, -amount)
		"avatar_damage_nearby":
			_advance(frame)
			if not mage.in_cell and not player.mage.in_cell and AvatarRules.distance(game, mage.room_id, player.mage.room_id) <= int(effect.range): game.deal_damage(-1, target, amount, "event")
		_:
			push_error("Unsupported Avatar Event: " + kind)
			return true
	return false

static func _advance(frame: Dictionary) -> void:
	frame["cursor"] = int(frame.get("cursor", 0)) + 1
	frame.erase("choice")
	frame.erase("power_done")
