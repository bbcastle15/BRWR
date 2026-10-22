extends RefCounted

# Standard play uses named replacements only. Same-colour substitution is
# not a rule of this setup; scenario Rooms require their own implemented mode.

static func allows(base: Dictionary, variant: Dictionary) -> bool:
	if not bool(variant.get("playable", true)):
		return false
	return bool(base.get("core", false)) and str(variant.get("replaces", "")) == str(base.id)

static func for_slot(base: Dictionary, variant: Dictionary) -> Dictionary:
	var result := variant.duplicate(true)
	result["replaces"] = str(base.id)
	return result
