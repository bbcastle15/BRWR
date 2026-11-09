# First baseline only. NOT a trained agent. A seeded, inspectable opponent
# that can exercise the AI interface before self-play / RL is introduced.
extends RefCounted

var rng := RandomNumberGenerator.new()
var style := "balanced"

func _init(seed_value: int = 42, play_style: String = "balanced") -> void:
	rng.seed = seed_value
	style = play_style


func choose(observation: Dictionary, decision: Dictionary) -> int:
	var options: Array = decision.get("candidates", [])
	if options.is_empty():
		return -1
	var best_index := 0
	var best_score := -1.0e20
	for item in options:
		var score: float = _score(observation, decision, item)
		score += rng.randf_range(-0.15, 0.15) # Break ties reproducibly.
		if score > best_score:
			best_score = score
			best_index = int(item.get("id", 0))
	return best_index


func _score(obs: Dictionary, decision: Dictionary, item: Dictionary) -> float:
	var kind := str(decision.get("type", ""))
	var payload: Dictionary = item.get("payload", {})
	var detail: Dictionary = item.get("detail", {})
	match kind:
		"action_activation_step":
			var action: Dictionary = detail.get("action", {})
			var action_kind := str(action.get("type", ""))
			if str(detail.get("kind", "")) == "quest":
				return 9.0
			if action_kind in ["spell", "quick"]:
				return 4.0
			if action_kind == "fight":
				return 3.0 if style == "aggressive" else 2.0
			if action_kind in ["explore", "momentum"]:
				return 2.5
			if str(detail.get("kind", "")) == "finish":
				return -2.0
		"study_choose_schools":
			var player_index := int(decision.get("player_index", -1))
			var players: Array = obs.get("players", [])
			if player_index >= 0 and player_index < players.size():
				var own_school := str(players[player_index].get("school_id", ""))
				var count := 0.0
				for school in payload.get("school_ids", []):
					if school == own_school:
						count += 1.0
				return count
		"study_keep_cards":
			# Further card evaluation will be added after spell feature extraction.
			return 1.0
		"preparation":
			match str(decision.get("substep", "")):
				"count":
					return float(payload.get("ai_count", 0))
				"quick_card":
					return 1.0 if int(payload.get("ai_hand_index", -1)) >= 0 else 0.0
				"ready_side", "quick_side":
					return 0.0 # Explore both playable sides instead of hardcoding Light.
			return 0.0
		"trigger_decision":
			return 1.0 if int(payload.get("queue_index", -1)) >= 0 else 0.0
		"evocation_phase_activations":
			var plan: Dictionary = detail.get("plan", {})
			return 2.0 if str(plan.get("attack_timing", "none")) != "none" else 0.0
		"black_rose_optional_quest_discard", "study_optional_discard":
			return 1.0 if (int(payload.get("quest_index", -1)) < 0 and kind.begins_with("black_rose")) or (int(payload.get("hand_index", -1)) < 0 and kind.begins_with("study")) else 0.0
	return 0.0
