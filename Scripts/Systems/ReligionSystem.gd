# ReligionSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/ReligionSystem.gd
#
# Owns religion and sacrifice rule logic extracted from TRGameState.gd.
# Reads/writes CampaignState through TRGameState runtime accessors instead of
# treating TRGameState mirror fields as the source of truth.

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
			available = int(floor(_stock(state, String(option.get("resource_id", "")))))
		elif source_type == "population":
			available = _active_population_for_group(state, String(option.get("population_group", "")))
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
		available = int(floor(_stock(state, String(option.get("resource_id", "")))))
	elif source_type == "population":
		available = _active_population_for_group(state, String(option.get("population_group", "")))
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
		_add_stock(state, String(option.get("resource_id", "")), -float(count))
	elif source_type == "population":
		var group_id: String = String(option.get("population_group", ""))
		_add_population(state, group_id, -count)
		_ensure_population_dependent_runtime(state)

	var prestige_gain: float = snappedf(float(count) * float(option.get("prestige_each", 0.0)), 0.01)
	var favour_gain: float = snappedf(float(count) * float(option.get("favour_each", option.get("prestige_each", 0.0))), 0.01)
	var god_text: String = ""
	if god_id != "":
		god_text = " to " + _palace_route_name(state, god_id)
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
		"veintena": _current_veintena(state),
		"detail": detail
	}

	if state != null and state.has_method("add_player_prestige"):
		state.call("add_player_prestige", prestige_gain, "religion_sacrifice", detail, record)

	_append_sacrifice_prestige_record(state, record)
	var report_line: String = detail + " Prestige +" + _format_amount(state, prestige_gain) + "; favour +" + _format_amount(state, favour_gain) + "."
	_append_report_line(state, report_line)

	if state != null and state.has_signal("state_changed"):
		state.emit_signal("state_changed")

	return {
		"ok": true,
		"reason": "Sacrifice recorded.",
		"record": record,
		"prestige_gain": prestige_gain,
		"favour_gain": favour_gain,
		"message": report_line
	}


func get_sacrifice_prestige_records(state: Node) -> Array[Dictionary]:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_sacrifice_prestige_records_copy"):
		return runtime_state.call("get_sacrifice_prestige_records_copy") as Array[Dictionary]

	var output: Array[Dictionary] = []
	return output


# -----------------------------------------------------------------------------
# CampaignState-first helper access
# -----------------------------------------------------------------------------

func _campaign_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null


func _stock(state: Node, resource_id: String) -> float:
	if state != null and state.has_method("_stock"):
		return float(state.call("_stock", resource_id))
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_estate_stock"):
		return float(runtime_state.call("get_estate_stock", resource_id))
	return 0.0


func _add_stock(state: Node, resource_id: String, amount: float) -> void:
	if state != null and state.has_method("_add_stock"):
		state.call("_add_stock", resource_id, amount)
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("add_estate_stock"):
		runtime_state.call("add_estate_stock", resource_id, amount)


func _active_population_for_group(state: Node, group_id: String) -> int:
	if state != null and state.has_method("_active_population_for_group"):
		return int(state.call("_active_population_for_group", group_id))
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_population_count"):
		return int(runtime_state.call("get_population_count", group_id))
	return 0


func _add_population(state: Node, group_id: String, amount: int) -> void:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("add_population_count"):
		runtime_state.call("add_population_count", group_id, amount)
		if state != null and state.has_method("_mirror_estate_structure_compatibility_from_campaign_state"):
			state.call("_mirror_estate_structure_compatibility_from_campaign_state")
		return


func _ensure_population_dependent_runtime(state: Node) -> void:
	if state == null:
		return
	if state.has_method("_ensure_active_housing_counts"):
		state.call("_ensure_active_housing_counts")
	if state.has_method("_ensure_labour_assignments"):
		state.call("_ensure_labour_assignments")


func _current_veintena(state: Node) -> int:
	if state != null and state.has_method("get_current_veintena"):
		return int(state.call("get_current_veintena"))
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_current_veintena_value"):
		return int(runtime_state.call("get_current_veintena_value"))
	return 1


func _palace_route_name(state: Node, god_id: String) -> String:
	if state != null and state.has_method("get_palace_route_name"):
		return String(state.call("get_palace_route_name", god_id))
	return god_id.capitalize()


func _append_sacrifice_prestige_record(state: Node, record: Dictionary) -> void:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("append_sacrifice_prestige_record"):
		runtime_state.call("append_sacrifice_prestige_record", record)
		if state != null and state.has_method("_mirror_prestige_compatibility_from_campaign_state"):
			state.call("_mirror_prestige_compatibility_from_campaign_state")


func _append_report_line(state: Node, line: String) -> void:
	if state != null and state.has_method("_append_report_line"):
		state.call("_append_report_line", line)
		return

	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("append_report_line"):
		runtime_state.call("append_report_line", line)
		if state != null and state.has_method("_mirror_calendar_report_compatibility_from_campaign_state"):
			state.call("_mirror_calendar_report_compatibility_from_campaign_state")


func _format_amount(state: Node, value: float) -> String:
	if state != null and state.has_method("_format_amount"):
		return String(state.call("_format_amount", value))
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))
