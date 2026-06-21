# WarDoctrineRules.gd
# Godot 4.x
# Project path: res://Scripts/Systems/WarDoctrineRules.gd
#
# Single source of truth for Prototype 0 Flower War / Warband doctrine values.
# FlowerWarSystem.gd, WarbandSystem.gd and any UI fallback combat display should
# read from this file so doctrine stats cannot drift again.
class_name WarDoctrineRules
extends RefCounted

const VALID_DOCTRINE_IDS: Array[String] = ["unspecialised", "eagle", "jaguar", "otomi", "coyote"]

const DOCTRINES: Dictionary = {
	"unspecialised": {
		"name": "Unspecialised",
		"offence": 1.0,
		"defence": 1.0,
		"role": "Balanced household warriors."
	},
	"eagle": {
		"name": "Eagle",
		"offence": 1.0,
		"defence": 1.2,
		"role": "Captive specialists and sustained war fighters."
	},
	"jaguar": {
		"name": "Jaguar",
		"offence": 1.3,
		"defence": 1.0,
		"role": "Elite offensive warriors. No hidden Prestige bonus; Prestige comes from victories, casualties, captives and loot."
	},
	"otomi": {
		"name": "Otomi",
		"offence": 0.8,
		"defence": 1.5,
		"role": "Defensive veterans who trade offence for survival."
	},
	"coyote": {
		"name": "Coyote",
		"offence": 1.4,
		"defence": 0.5,
		"role": "Glass-cannon raiders who favour loot."
	}
}

static func doctrine_ids() -> Array[String]:
	return VALID_DOCTRINE_IDS.duplicate()

static func has_doctrine(doctrine_id: String) -> bool:
	return DOCTRINES.has(doctrine_id)

static func normalise_doctrine_id(doctrine_id: String) -> String:
	if DOCTRINES.has(doctrine_id):
		return doctrine_id
	return "unspecialised"

static func normalize_doctrine_id(doctrine_id: String) -> String:
	# US spelling alias for callers that use normalize.
	return normalise_doctrine_id(doctrine_id)

static func doctrine_data(doctrine_id: String) -> Dictionary:
	var cleaned: String = normalise_doctrine_id(doctrine_id)
	var data: Dictionary = (DOCTRINES[cleaned] as Dictionary).duplicate(true)
	data["id"] = cleaned
	return data

static func all_doctrines() -> Dictionary:
	return DOCTRINES.duplicate(true)

static func doctrine_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for doctrine_id: String in VALID_DOCTRINE_IDS:
		rows.append(doctrine_data(doctrine_id))
	return rows

static func doctrine_name(doctrine_id: String) -> String:
	return String(doctrine_data(doctrine_id).get("name", normalise_doctrine_id(doctrine_id).capitalize()))

static func doctrine_role(doctrine_id: String) -> String:
	return String(doctrine_data(doctrine_id).get("role", ""))

static func doctrine_offence(doctrine_id: String) -> float:
	return float(doctrine_data(doctrine_id).get("offence", 1.0))

static func doctrine_defence(doctrine_id: String) -> float:
	return float(doctrine_data(doctrine_id).get("defence", 1.0))
