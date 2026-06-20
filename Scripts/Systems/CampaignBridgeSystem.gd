# CampaignBridgeSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/CampaignBridgeSystem.gd
#
# v0.45.14 extraction target.
# Owns TRGameState <-> CampaignState bridge, mirroring and migration audit logic.
# TRGameState remains the public UI API while CampaignState continues becoming
# the authoritative live save-state owner.
class_name CampaignBridgeSystem
extends RefCounted

func _get_campaign_state(state: Node) -> RefCounted:
	if state == null or not state.has_method("_get_campaign_state"):
		return null
	var runtime_state: Variant = state.call("_get_campaign_state")
	if runtime_state is RefCounted:
		return runtime_state as RefCounted
	return null

func sync_from_current_runtime(state: Node) -> void:
	var snapshot: RefCounted = _get_campaign_state(state)
	if snapshot == null:
		return
	# Stockpile, calendar/report, Prestige and Palace state are CampaignState-authoritative.
	# Preserve those values while syncing remaining legacy fields from TRGameState.
	var authoritative_estate_stockpiles: Dictionary = snapshot.call("get_estate_stockpiles_copy") as Dictionary
	var authoritative_market_stockpiles: Dictionary = snapshot.call("get_market_stockpiles_copy") as Dictionary
	var authoritative_current_veintena: int = int(snapshot.call("get_current_veintena_value"))
	var authoritative_last_report: Array = snapshot.call("get_last_report_copy") as Array
	var authoritative_initialized: bool = bool(snapshot.get("initialized"))
	var authoritative_player_prestige: float = float(snapshot.call("get_player_prestige_value"))
	var authoritative_rival_prestige: Dictionary = snapshot.call("get_rival_prestige_copy") as Dictionary
	var authoritative_prestige_history: Array = snapshot.call("get_prestige_history_copy") as Array
	var authoritative_sacrifice_records: Array = snapshot.call("get_sacrifice_prestige_records_copy") as Array
	var authoritative_palace_dedicated_god: String = String(snapshot.call("get_palace_dedicated_god_value"))
	var authoritative_palace_built_structures: Dictionary = snapshot.call("get_palace_built_structures_copy") as Dictionary
	var authoritative_palace_runtime_statuses: Dictionary = snapshot.call("get_palace_structure_runtime_statuses_copy") as Dictionary
	var authoritative_palace_delivered_demands: Dictionary = snapshot.call("get_palace_delivered_ruler_demands_copy") as Dictionary
	var authoritative_palace_donations: Array = snapshot.call("get_palace_ruler_demand_donations_copy") as Array
	var authoritative_palace_maintenance_report: Array = snapshot.call("get_last_palace_maintenance_report_copy") as Array
	var authoritative_flower_war_gate: bool = bool(snapshot.call("get_flower_war_palace_gate_enabled_value"))
	snapshot.call("copy_from_game_state", state)
	if not authoritative_estate_stockpiles.is_empty():
		snapshot.call("set_estate_stockpiles_values", authoritative_estate_stockpiles)
	if not authoritative_market_stockpiles.is_empty():
		snapshot.call("set_market_stockpiles_values", authoritative_market_stockpiles)
	snapshot.call("set_current_veintena", authoritative_current_veintena)
	snapshot.call("set_last_report", authoritative_last_report)
	snapshot.call("set_initialized", authoritative_initialized)
	snapshot.call("set_player_prestige_value", authoritative_player_prestige)
	if not authoritative_rival_prestige.is_empty():
		snapshot.call("set_rival_prestige_values", authoritative_rival_prestige)
	snapshot.call("set_prestige_history_records", authoritative_prestige_history)
	snapshot.call("set_sacrifice_prestige_records", authoritative_sacrifice_records)
	snapshot.call("set_palace_dedicated_god_value", authoritative_palace_dedicated_god)
	snapshot.call("set_palace_built_structures", authoritative_palace_built_structures)
	snapshot.call("set_palace_structure_runtime_statuses", authoritative_palace_runtime_statuses)
	snapshot.call("set_palace_delivered_ruler_demands", authoritative_palace_delivered_demands)
	snapshot.call("set_palace_ruler_demand_donations", authoritative_palace_donations)
	snapshot.call("set_last_palace_maintenance_report", authoritative_palace_maintenance_report)
	snapshot.call("set_flower_war_palace_gate_enabled_value", authoritative_flower_war_gate)
	mirror_stockpile_compatibility_from_campaign_state(state)
	mirror_calendar_report_compatibility_from_campaign_state(state)
	mirror_prestige_compatibility_from_campaign_state(state)
	mirror_palace_state_from_campaign_state_to_legacy(state)
	mirror_estate_structure_compatibility_from_campaign_state(state)
	mirror_warband_flower_war_compatibility_from_campaign_state(state)

func apply_campaign_state_to_current_runtime(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return
	runtime_state.call("apply_to_game_state", state)

func ensure_campaign_state_palace_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	if String(runtime_state.call("get_palace_dedicated_god_value")) == "" and String(state.get("player_palace_dedicated_god")) != "":
		runtime_state.call("set_palace_dedicated_god_value", String(state.get("player_palace_dedicated_god")))
	if (runtime_state.call("get_palace_built_structures_copy") as Dictionary).is_empty() and not (state.get("palace_built_structures") as Dictionary).is_empty():
		runtime_state.call("set_palace_built_structures", state.get("palace_built_structures"))
	if (runtime_state.call("get_palace_structure_runtime_statuses_copy") as Dictionary).is_empty() and not (state.get("palace_structure_runtime_statuses") as Dictionary).is_empty():
		runtime_state.call("set_palace_structure_runtime_statuses", state.get("palace_structure_runtime_statuses"))
	if (runtime_state.call("get_palace_delivered_ruler_demands_copy") as Dictionary).is_empty() and not (state.get("palace_delivered_ruler_demands") as Dictionary).is_empty():
		runtime_state.call("set_palace_delivered_ruler_demands", state.get("palace_delivered_ruler_demands"))
	if (runtime_state.call("get_palace_ruler_demand_donations_copy") as Array).is_empty() and not (state.get("palace_ruler_demand_donations") as Array).is_empty():
		runtime_state.call("set_palace_ruler_demand_donations", state.get("palace_ruler_demand_donations"))
	if (runtime_state.call("get_last_palace_maintenance_report_copy") as Array).is_empty() and not (state.get("last_palace_maintenance_report") as Array).is_empty():
		runtime_state.call("set_last_palace_maintenance_report", state.get("last_palace_maintenance_report"))
	runtime_state.call("set_flower_war_palace_gate_enabled_value", bool(state.get("flower_war_palace_gate_enabled")))
	mirror_palace_state_from_campaign_state_to_legacy(state)
	return runtime_state

func capture_legacy_palace_state_to_campaign_state(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return
	runtime_state.call("capture_palace_state_from_game_state", state)
	mirror_palace_state_from_campaign_state_to_legacy(state)

func mirror_palace_state_from_campaign_state_to_legacy(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state != null:
		runtime_state.call("mirror_palace_state_to_game_state", state)

func ensure_campaign_state_estate_structure_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	if (runtime_state.get("population") as Dictionary).is_empty() and not (state.get("population") as Dictionary).is_empty():
		runtime_state.set("population", (state.get("population") as Dictionary).duplicate(true))
	if (runtime_state.get("estate_buildings") as Dictionary).is_empty() and not (state.get("estate_buildings") as Dictionary).is_empty():
		runtime_state.set("estate_buildings", (state.get("estate_buildings") as Dictionary).duplicate(true))
	if (runtime_state.get("active_housing_counts") as Dictionary).is_empty() and not (state.get("active_housing_counts") as Dictionary).is_empty():
		runtime_state.set("active_housing_counts", (state.get("active_housing_counts") as Dictionary).duplicate(true))
	if (runtime_state.get("base_housing_capacity") as Dictionary).is_empty() and not (state.get("base_housing_capacity") as Dictionary).is_empty():
		runtime_state.set("base_housing_capacity", (state.get("base_housing_capacity") as Dictionary).duplicate(true))
	if (runtime_state.get("labour_assignments") as Dictionary).is_empty() and not (state.get("labour_assignments") as Dictionary).is_empty():
		runtime_state.set("labour_assignments", (state.get("labour_assignments") as Dictionary).duplicate(true))
	mirror_estate_structure_compatibility_from_campaign_state(state)
	return runtime_state

func mirror_estate_structure_compatibility_from_campaign_state(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state != null:
		runtime_state.call("mirror_population_building_housing_to_game_state", state)

func ensure_campaign_state_warband_flower_war_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	if (runtime_state.get("warbands") as Dictionary).is_empty() and not (state.get("warbands") as Dictionary).is_empty():
		runtime_state.set("warbands", (state.get("warbands") as Dictionary).duplicate(true))
	if (runtime_state.get("last_flower_war_report") as Dictionary).is_empty() and not (state.get("last_flower_war_report") as Dictionary).is_empty():
		runtime_state.set("last_flower_war_report", (state.get("last_flower_war_report") as Dictionary).duplicate(true))
	if (runtime_state.get("flower_war_report_archive") as Array).is_empty() and not (state.get("flower_war_report_archive") as Array).is_empty():
		runtime_state.set("flower_war_report_archive", (state.get("flower_war_report_archive") as Array).duplicate(true))
	mirror_warband_flower_war_compatibility_from_campaign_state(state)
	return runtime_state

func mirror_warband_flower_war_compatibility_from_campaign_state(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state != null:
		runtime_state.call("mirror_warband_flower_war_state_to_game_state", state)

func ensure_campaign_state_stockpile_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	runtime_state.call("seed_stockpiles_from_game_state_if_empty", state)
	mirror_stockpile_compatibility_from_campaign_state(state)
	return runtime_state

func mirror_stockpile_compatibility_from_campaign_state(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state != null:
		runtime_state.call("mirror_stockpiles_to_game_state", state)

func mirror_calendar_report_compatibility_from_campaign_state(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return
	state.set("current_veintena", int(runtime_state.call("get_current_veintena_value")))
	var report_copy: Array = runtime_state.call("get_last_report_copy") as Array
	var legacy_report_variant: Variant = state.get("last_report")
	var legacy_report: Array = []
	if legacy_report_variant is Array:
		legacy_report = legacy_report_variant as Array
	legacy_report.clear()
	for line: Variant in report_copy:
		legacy_report.append(String(line))
	state.set("last_report", legacy_report)
	state.set("initialized", bool(runtime_state.get("initialized")))

func ensure_campaign_state_calendar_report_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	var legacy_report: Array = state.get("last_report") as Array
	if (runtime_state.call("get_last_report_copy") as Array).is_empty() and not legacy_report.is_empty():
		runtime_state.call("set_last_report", legacy_report)
	if int(runtime_state.call("get_current_veintena_value")) <= 1 and int(state.get("current_veintena")) > 1:
		runtime_state.call("set_current_veintena", int(state.get("current_veintena")))
	if bool(state.get("initialized")) and not bool(runtime_state.get("initialized")):
		runtime_state.call("set_initialized", true)
	mirror_calendar_report_compatibility_from_campaign_state(state)
	return runtime_state

func capture_legacy_calendar_report_to_campaign_state(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return
	runtime_state.call("set_current_veintena", int(state.get("current_veintena")))
	runtime_state.call("set_last_report", state.get("last_report"))
	runtime_state.call("set_initialized", bool(state.get("initialized")))
	mirror_calendar_report_compatibility_from_campaign_state(state)

func set_current_veintena_value(state: Node, value: int) -> int:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return value
	var result: int = int(runtime_state.call("set_current_veintena", value))
	mirror_calendar_report_compatibility_from_campaign_state(state)
	return result

func clear_report_lines(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state != null:
		runtime_state.call("clear_last_report")
	mirror_calendar_report_compatibility_from_campaign_state(state)

func set_report_lines(state: Node, lines: Array) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state != null:
		runtime_state.call("set_last_report", lines)
	mirror_calendar_report_compatibility_from_campaign_state(state)

func append_report_line(state: Node, line: String) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state != null:
		runtime_state.call("append_report_line", line)
	mirror_calendar_report_compatibility_from_campaign_state(state)

func ensure_campaign_state_prestige_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	if (runtime_state.get("prestige_history") as Array).is_empty() and not (state.get("prestige_history") as Array).is_empty():
		runtime_state.set("prestige_history", (state.get("prestige_history") as Array).duplicate(true))
	if absf(float(runtime_state.get("player_prestige"))) <= 0.0001 and absf(float(state.get("player_prestige"))) > 0.0001:
		runtime_state.set("player_prestige", float(state.get("player_prestige")))
	if (runtime_state.get("rival_prestige") as Dictionary).is_empty():
		if not (state.get("rival_prestige") as Dictionary).is_empty():
			runtime_state.set("rival_prestige", (state.get("rival_prestige") as Dictionary).duplicate(true))
		elif state.has_method("_default_rival_prestige_values"):
			runtime_state.set("rival_prestige", state.call("_default_rival_prestige_values"))
	if (runtime_state.get("sacrifice_prestige_records") as Array).is_empty() and not (state.get("sacrifice_prestige_records") as Array).is_empty():
		runtime_state.set("sacrifice_prestige_records", (state.get("sacrifice_prestige_records") as Array).duplicate(true))
	mirror_prestige_compatibility_from_campaign_state(state)
	return runtime_state

func mirror_prestige_compatibility_from_campaign_state(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return
	state.set("player_prestige", float(runtime_state.call("get_player_prestige_value")))
	state.set("rival_prestige", runtime_state.call("get_rival_prestige_copy"))
	state.set("prestige_history", runtime_state.call("get_prestige_history_copy"))
	state.set("sacrifice_prestige_records", runtime_state.call("get_sacrifice_prestige_records_copy"))

func emit_state_changed_and_sync(state: Node) -> void:
	sync_from_current_runtime(state)
	if state != null and state.has_signal("state_changed"):
		state.emit_signal("state_changed")

func get_campaign_state_sync_report(state: Node, sync_first: bool = false) -> Dictionary:
	if sync_first:
		sync_from_current_runtime(state)
	var snapshot: RefCounted = _get_campaign_state(state)
	var fields: Array[String] = [
		"resources", "resource_order", "buildings", "building_order",
		"estate_stockpiles", "market_stockpiles", "market_demand", "market_economy",
		"estate_buildings", "active_housing_counts", "population", "base_housing_capacity", "labour_assignments",
		"current_veintena", "last_report", "initialized",
		"player_palace_dedicated_god", "palace_built_structures", "palace_structure_runtime_statuses",
		"palace_delivered_ruler_demands", "palace_ruler_demand_donations", "last_palace_maintenance_report",
		"player_prestige", "rival_prestige", "prestige_history", "sacrifice_prestige_records",
		"flower_war_palace_gate_enabled", "last_flower_war_report", "flower_war_report_archive", "warbands"
	]
	var rows: Array[Dictionary] = []
	var mismatch_count: int = 0
	for field_name: String in fields:
		var live_value: Variant = state.get(field_name)
		var mirror_value: Variant = snapshot.get(field_name) if snapshot != null else null
		var live_text: String = campaign_state_compare_text(live_value)
		var mirror_text: String = campaign_state_compare_text(mirror_value)
		var matches: bool = live_text == mirror_text
		if not matches:
			mismatch_count += 1
		rows.append({
			"field": field_name,
			"matches": matches,
			"live_type": type_string(typeof(live_value)),
			"mirror_type": type_string(typeof(mirror_value)),
			"live_preview": campaign_state_preview(live_value),
			"mirror_preview": campaign_state_preview(mirror_value)
		})
	return {
		"schema_version": "campaign_state_sync_report_v0_45_14",
		"sync_first": sync_first,
		"field_count": fields.size(),
		"mismatch_count": mismatch_count,
		"in_sync": mismatch_count == 0,
		"rows": rows
	}

func is_campaign_state_mirror_in_sync(state: Node) -> bool:
	var report: Dictionary = get_campaign_state_sync_report(state, false)
	return bool(report.get("in_sync", false))

func campaign_state_compare_text(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		var keys: Array[String] = []
		for key_variant: Variant in dictionary.keys():
			keys.append(str(key_variant))
		keys.sort()
		var parts: Array[String] = []
		for key: String in keys:
			parts.append(key + ":" + campaign_state_compare_text(dictionary.get(key)))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var array_value: Array = value as Array
		var parts: Array[String] = []
		for item: Variant in array_value:
			parts.append(campaign_state_compare_text(item))
		return "[" + ",".join(parts) + "]"
	return str(value)

func campaign_state_preview(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		return "Dictionary(" + str(dictionary.size()) + ")"
	if value is Array:
		var array_value: Array = value as Array
		return "Array(" + str(array_value.size()) + ")"
	var text: String = str(value)
	if text.length() > 80:
		return text.substr(0, 77) + "..."
	return text
