extends RefCounted

# Presentation only: no choices, timers or resolution calls originate here.
static func icon(code: String) -> String:
	return "[img=26x26]res://assets/avatars/possessed/production/symbols/%s_white.png[/img]" % code

static func describe(effect: Dictionary) -> String:
	var amount := str(effect.get("amount", 1))
	match str(effect.get("type", "")):
		"room_effect", "if_transformed":
			var parts := PackedStringArray()
			for child in effect.get("effects", []): parts.append(describe(child))
			return " ".join(parts)
		"move_model_near_target_room":
			return "Move up to %s a %s." % [str(effect.get("distance", 1)), icon("e934")]
		"damage": return "Inflict %s %s." % [amount, icon("e902")]
		"heal": return "Heal %s %s." % [amount, icon("e902")]
		"place_instability": return "Place %s %s." % [amount, icon("e904")]
		"convert_instability": return "Convert %s %s." % [amount, icon("e904")]
		"convert_damage": return "Convert %s %s." % [amount, icon("e902")]
		"gain_power": return "Gain %s %s." % [amount, icon("e901")]
		"set_target_room_from_triggering_mage": return "Target the Room that the triggering Mage entered."
		"move_one_mage_in_target_room": return "Move a Mage in the target Room up to %s." % str(effect.get("distance", 1))
		"geoform": return "Geoform · " + ", ".join(PackedStringArray(effect.get("room_colors", [])))
		"room_target": return "Choose a Room within %s." % str(effect.get("range", 0))
		"summon_evocation": return "Summon " + str(effect.get("evocation_id", "an Evocation")).replace("_", " ").capitalize() + "."
		_:
			return str(effect.get("type", "Effect")).replace("_", " ").capitalize() + (" · " + amount if effect.has("amount") else "")
