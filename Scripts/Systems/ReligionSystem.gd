# ReligionSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/ReligionSystem.gd
#
# Owns religion and sacrifice rule logic extracted from TRGameState.gd.
# TRGameState remains the live state owner and public UI API while the
# architecture split is in progress.
class_name ReligionSystem
extends RefCounted

func sacrifice_prestige_option_definitions() -> Array[Dictionary]:
	# Prototype values follow the agreed hierarchy: Captive > Priest > Slave/Tlacotin.
	# Sacrifice Prestige is public religious fame. It is score only and is never spent.
	return [
		{
			"id": "captive",
			"name": "Captive",
			"source_type": "resource",
			"resource_id": "captives",
			"population_group": "",
			"prestige_each": 8.0,
			"favour_each": 8.0,
			"description": "Highest-prestige sacrifice. Captives are the central ritual prize of Flower Wars."
		},
		{
			"id": "priest",
			"name": "Priest",
			"source_type": "population",
			"resource_id": "",
			"population_group": "tlamacazqueh",
			"prestige_each": 4.0,
			"favour_each": 4.0,
			"description": "Moderate-prestige sacrifice. This is costly because it removes a trained priest from the estate."
		},
		{
			"id": "tlacotin",
			"name": "Tlacotin Labourer",
			"source_type": "population",
			"resource_id": "",
			"population_group": "tlacotin",
			"prestige_each": 1.0,
			"favour_each": 1.0,
			"description": "Small-prestige sacrifice. This uses bonded labour and should remain much less prestigious than captive sacrifice."
		}
	]

func get_sacrifice_prestige_options(state: Node) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for option: Dictionary in sacrifice_prestige_option_definitions():
		var source_type: String = String(option.get("source_type", ""))
		var available: int = 0
		if source_type == "resource":
			available = int(floor(float(state.call("_stock", String(option.get("resource_id", ""))))))
		elif source_type == "population":
			available = int(state.call("_active_population_for_group", String(option.get("population_group", ""))))
		var row: Dictionary = option.duplicate(true)
		row["available"] = available
		row["can_sacrifice_one"] = available >= 1
		row["prestige_preview_one"] = float(row.get("prestige_each", 0.0))
		row["favour_preview_one"] = float(row.get("favour_each", row.get("prestige_each", 0.0)))
		output.append(row)
	return output

func sacrifice_prestige_option_by_id(sacrifice_id: String) -> Dictionary:
	for option: Dictionary in sacrifice_prestige_option_definitions():
		if String(option.get("id", "")) == sacrifice_id:
			return option.duplicate(true)
	return {}

func can_sacrifice_for_prestige(state: Node, sacrifice_id: String, amount: int = 1) -> Dictionary:
	var option: Dictionary = sacrifice_prestige_option_by_id(sacrifice_id)
	if option.is_empty():
		return {"ok": false, "reason": "Unknown sacrifice type."}
	var count: int = max(0, amount)
	if count <= 0:
		return {"ok": false, "reason": "Choose at least 1 sacrifice."}
	var source_type: String = String(option.get("source_type", ""))
	var available: int = 0
	if source_type == "resource":
		available = int(floor(float(state.call("_stock", String(option.get("resource_id", ""))))))
	elif source_type == "population":
		available = int(state.call("_active_population_for_group", String(option.get("population_group", ""))))
	else:
		return {"ok": false, "reason": "Sacrifice source is not configured."}
	if available < count:
		return {"ok": false, "reason": "Only " + str(available) + " available."}
	return {"ok": true, "reason": "Ready.", "available": available}

func sacrifice_for_prestige(state: Node, sacrifice_id: String, amount: int = 1, god_id: String = "") -> Dictionary:
	var status: Dictionary = can_sacrifice_for_prestige(state, sacrifice_id, amount)
	if not bool(status.get("ok", false)):
		return status
	var option: Dictionary = sacrifice_prestige_option_by_id(sacrifice_id)
	var count: int = max(1, amount)
	var source_type: String = String(option.get("source_type", ""))
	if source_type == "resource":
		state.call("_add_stock", String(option.get("resource_id", "")), -float(count))
	elif source_type == "population":
		var group_id: String = String(option.get("population_group", ""))
		var population: Dictionary = state.get("population") as Dictionary
		population[group_id] = max(0, int(population.get(group_id, 0)) - count)
		state.set("population", population)
		state.call("_ensure_active_housing_counts")
		state.call("_ensure_labour_assignments")
	var prestige_gain: float = snappedf(float(count) * float(option.get("prestige_each", 0.0)), 0.01)
	var favour_gain: float = snappedf(float(count) * float(option.get("favour_each", option.get("prestige_each", 0.0))), 0.01)
	var god_text: String = ""
	if god_id != "":
		god_text = " to " + String(state.call("get_palace_route_name", god_id))
	var detail: String = "Sacrificed " + str(count) + " " + String(option.get("name", "sacrifice")) + god_text + "."
	var record: Dictionary = {
		"source_id": "religion_sacrifice",
		"sacrifice_id": sacrifice_id,
		"name": String(option.get("name", "Sacrifice")),
		"amount": count,
		"god_id": god_id,
		"prestige_each": float(option.get("prestige_each", 0.0)),
		"favour_each": float(option.get("favour_each", option.get("prestige_each", 0.0))),
		"prestige_gain": prestige_gain,
		"favour_gain": favour_gain,
		"veintena": int(state.get("current_veintena")),
		"detail": detail
	}
	state.call("add_player_prestige", prestige_gain, "religion_sacrifice", detail, record)
	var sacrifice_records: Array = state.get("sacrifice_prestige_records") as Array
	sacrifice_records.append(record.duplicate(true))
	state.set("sacrifice_prestige_records", sacrifice_records)
	var report: Array = state.get("last_report") as Array
	report.append(detail + " Prestige +" + String(state.call("_format_amount", prestige_gain)) + "; favour +" + String(state.call("_format_amount", favour_gain)) + ".")
	state.set("last_report", report)
	if state.has_signal("state_changed"):
		state.emit_signal("state_changed")
	return {
		"ok": true,
		"reason": "Sacrifice recorded.",
		"record": record,
		"prestige_gain": prestige_gain,
		"favour_gain": favour_gain,
		"message": detail + " Prestige +" + String(state.call("_format_amount", prestige_gain)) + "; favour +" + String(state.call("_format_amount", favour_gain)) + "."
	}

func get_sacrifice_prestige_records(state: Node) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var records: Array = state.get("sacrifice_prestige_records") as Array
	for record_variant: Variant in records:
		if record_variant is Dictionary:
			output.append((record_variant as Dictionary).duplicate(true))
	return output
