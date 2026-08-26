class_name TriggeredSpellManager
extends RefCounted


func get_triggered_spells(
	event: GameEvent,
	players: Array
) -> Array[Dictionary]:

	var triggered: Array[Dictionary] = []

	for player_index in range(players.size()):
		var player = players[player_index]

		for active_spell in player.active_spells:
			if not active_spell.active:
				continue

			var trigger = active_spell.get_trigger()

			if trigger.is_empty():
				continue

			if trigger_matches(
				trigger,
				event,
				active_spell
			):
				triggered.append({
					"active_spell": active_spell,
					"event": event
				})

	return triggered
	
func trigger_matches(
	trigger: Dictionary,
	event: GameEvent,
	active_spell: ActiveSpellState
) -> bool:

	var trigger_type = str(
		trigger.get("type", "")
	)

	match trigger_type:

		"another_model_inflicts_damage":
			return (
				event.event_type == "damage_inflicted"
				and is_another_model(
					event,
					active_spell.owner_id
				)
			)

		"another_model_inflicts_damage_to_caster":
			return (
				event.event_type == "damage_inflicted"
				and event.target_model_type == "mage"
				and event.target_player_index
					== active_spell.owner_id
				and is_another_model(
					event,
					active_spell.owner_id
				)
			)

		_:
			print(
				"UNKNOWN TRIGGER TYPE: ",
				trigger_type
			)

			return false

func is_another_model(
	event: GameEvent,
	owner_id: int
) -> bool:

	if event.source_model_type == "mage":
		return (
			event.source_player_index
			!= owner_id
		)

	if event.source_model_type == "evocation":
		if event.source_evocation == null:
			return false

		return (
			event.source_evocation.controller_id
			!= owner_id
		)

	return false
