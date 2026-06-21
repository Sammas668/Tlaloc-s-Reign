# CampaignBridgeSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/CampaignBridgeSystem.gd
#
# Patch 8K2 — CampaignState bridge cleanup.
#
# Owns TRGameState <-> CampaignState bridging while CampaignState becomes the
# authoritative live/save-state owner. TRGameState remains the public runtime
# facade for UI and systems; its legacy variables are compatibility mirrors.
# Calendar/report state and religion state are CampaignState-authoritative.
class_name CampaignBridgeSystem
extends RefCounted

const AUTHORITATIVE_CALENDAR_FIELDS: Array[String] = [
	"current_veintena",
	"calendar_period",
	"ritual_year",
	"last_report",
	"last_turn_summary",
	"initialized"
]

func _get_campaign_state(state: Node) -> RefCounted:
	if state == null or not state.has_method("_get_campaign_state"):
		return null
	var runtime_state: Variant = state.call("_get_campaign_state")
	if runtime_state is RefCounted:
		return runtime_state as RefCounted
	return null

# -----------------------------------------------------------------------------
# Full bridge sync
# -----------------------------------------------------------------------------

func sync_from_current_runtime(state: Node) -> void:
	var snapshot: RefCounted = _get_campaign_state(state)
	if snapshot == null:
		return

	# Preserve CampaignState-authoritative domains before copying remaining legacy
	# fields from TRGameState. This prevents old compatibility mirrors from
	# overwriting the true live calendar/report state.
	var authoritative_estate_stockpiles: Dictionary = snapshot.call("get_estate_stockpiles_copy") as Dictionary
	var authoritative_market_stockpiles: Dictionary = snapshot.call("get_market_stockpiles_copy") as Dictionary
	var authoritative_current_veintena: int = int(snapshot.call("get_current_veintena_value"))
	var authoritative_calendar_period: String = String(snapshot.call("get_calendar_period_value"))
	var authoritative_ritual_year: int = int(snapshot.call("get_ritual_year_value"))
	var authoritative_last_report: Array = snapshot.call("get_last_report_copy") as Array
	var authoritative_last_turn_summary: Dictionary = snapshot.call("get_last_turn_summary_copy") as Dictionary
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
	var authoritative_religion_state: Dictionary = {}
	if snapshot.has_method("get_religion_state_copy"):
		authoritative_religion_state = snapshot.call("get_religion_state_copy") as Dictionary

	snapshot.call("copy_from_game_state", state)

	if not authoritative_estate_stockpiles.is_empty():
		snapshot.call("set_estate_stockpiles_values", authoritative_estate_stockpiles)
	if not authoritative_market_stockpiles.is_empty():
		snapshot.call("set_market_stockpiles_values", authoritative_market_stockpiles)

	snapshot.call("set_current_veintena", authoritative_current_veintena)
	snapshot.call("set_calendar_period_value", authoritative_calendar_period)
	snapshot.call("set_ritual_year_value", authoritative_ritual_year)
	snapshot.call("set_last_report", authoritative_last_report)
	snapshot.call("set_last_turn_summary", authoritative_last_turn_summary)
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
	if snapshot.has_method("set_religion_state"):
		snapshot.call("set_religion_state", authoritative_religion_state)

	mirror_stockpile_compatibility_from_campaign_state(state)
	mirror_calendar_report_compatibility_from_campaign_state(state)
	mirror_prestige_compatibility_from_campaign_state(state)
	mirror_palace_state_from_campaign_state_to_legacy(state)
	mirror_estate_structure_compatibility_from_campaign_state(state)
	mirror_warband_flower_war_compatibility_from_campaign_state(state)
	mirror_rival_state_from_campaign_state_to_legacy(state)
	mirror_religion_state_from_campaign_state_to_legacy(state)

func apply_campaign_state_to_current_runtime(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return
	runtime_state.call("apply_to_game_state", state)
	mirror_calendar_report_compatibility_from_campaign_state(state)

# -----------------------------------------------------------------------------
# Calendar/report authority
# -----------------------------------------------------------------------------

func ensure_campaign_state_calendar_report_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	# CampaignState is the authority. Only seed from legacy when the CampaignState
	# object has not been initialised yet but old TRGameState already has data.
	if not bool(runtime_state.get("initialized")) and bool(_legacy_value(state, "initialized", false)):
		runtime_state.call("set_current_veintena", int(_legacy_value(state, "current_veintena", 1)))
		runtime_state.call("set_calendar_period_value", String(_legacy_meta_or_property(state, "calendar_period", "veintena")))
		runtime_state.call("set_ritual_year_value", int(_legacy_meta_or_property(state, "ritual_year", 1)))
		runtime_state.call("set_last_report", _legacy_value(state, "last_report", []))
		runtime_state.call("set_last_turn_summary", _legacy_meta_or_property(state, "last_turn_summary", {}))
		runtime_state.call("set_initialized", true)
	mirror_calendar_report_compatibility_from_campaign_state(state)
	return runtime_state

func capture_legacy_calendar_report_to_campaign_state(state: Node) -> void:
	# Compatibility-only escape hatch for older systems. New turn/calendar code should
	# write through CampaignState helpers directly instead of relying on this method.
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return
	runtime_state.call("set_current_veintena", int(_legacy_value(state, "current_veintena", 1)))
	runtime_state.call("set_calendar_period_value", String(_legacy_meta_or_property(state, "calendar_period", "veintena")))
	runtime_state.call("set_ritual_year_value", int(_legacy_meta_or_property(state, "ritual_year", 1)))
	runtime_state.call("set_last_report", _legacy_value(state, "last_report", []))
	runtime_state.call("set_last_turn_summary", _legacy_meta_or_property(state, "last_turn_summary", {}))
	runtime_state.call("set_initialized", bool(_legacy_value(state, "initialized", false)))
	mirror_calendar_report_compatibility_from_campaign_state(state)

func mirror_calendar_report_compatibility_from_campaign_state(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null or state == null:
		return
	var veintena_value: int = int(runtime_state.call("get_current_veintena_value"))
	var period_value: String = String(runtime_state.call("get_calendar_period_value"))
	var ritual_year_value: int = int(runtime_state.call("get_ritual_year_value"))
	var summary_copy: Dictionary = runtime_state.call("get_last_turn_summary_copy") as Dictionary
	state.set("current_veintena", veintena_value)
	state.set("last_report", runtime_state.call("get_last_report_copy"))
	state.set("initialized", bool(runtime_state.get("initialized")))
	# calendar_period / ritual_year / last_turn_summary may not exist as declared
	# TRGameState properties in older local files, so metadata is the safe legacy
	# mirror as a compatibility mirror for older UI paths.
	state.set_meta("calendar_period", period_value)
	state.set_meta("ritual_year", ritual_year_value)
	state.set_meta("last_turn_summary", summary_copy)

func set_current_veintena_value(state: Node, value: int) -> int:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state == null:
		return value
	var result: int = int(runtime_state.call("set_current_veintena", value))
	mirror_calendar_report_compatibility_from_campaign_state(state)
	return result

func set_calendar_period_value(state: Node, value: String) -> String:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state == null:
		return value
	var result: String = String(runtime_state.call("set_calendar_period_value", value))
	mirror_calendar_report_compatibility_from_campaign_state(state)
	return result

func set_ritual_year_value(state: Node, value: int) -> int:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state == null:
		return value
	var result: int = int(runtime_state.call("set_ritual_year_value", value))
	mirror_calendar_report_compatibility_from_campaign_state(state)
	return result

func set_calendar_runtime_state(state: Node, veintena: int, ritual_year: int, period: String) -> void:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state == null:
		return
	runtime_state.call("set_current_veintena", veintena)
	runtime_state.call("set_ritual_year_value", ritual_year)
	runtime_state.call("set_calendar_period_value", period)
	mirror_calendar_report_compatibility_from_campaign_state(state)

func clear_report_lines(state: Node) -> void:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state != null:
		runtime_state.call("clear_last_report")
	mirror_calendar_report_compatibility_from_campaign_state(state)

func set_report_lines(state: Node, lines: Array) -> void:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state != null:
		runtime_state.call("set_last_report", lines)
	mirror_calendar_report_compatibility_from_campaign_state(state)

func append_report_line(state: Node, line: String) -> void:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state != null:
		runtime_state.call("append_report_line", line)
	mirror_calendar_report_compatibility_from_campaign_state(state)

func set_last_turn_summary(state: Node, summary: Dictionary) -> void:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state != null:
		runtime_state.call("set_last_turn_summary", summary)
	mirror_calendar_report_compatibility_from_campaign_state(state)

# -----------------------------------------------------------------------------
# Stockpile bridge
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Palace bridge
# -----------------------------------------------------------------------------

func ensure_campaign_state_palace_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	if String(runtime_state.call("get_palace_dedicated_god_value")) == "" and String(_legacy_value(state, "player_palace_dedicated_god", "")) != "":
		runtime_state.call("set_palace_dedicated_god_value", String(_legacy_value(state, "player_palace_dedicated_god", "")))
	if (runtime_state.call("get_palace_built_structures_copy") as Dictionary).is_empty() and not (_legacy_value(state, "palace_built_structures", {}) as Dictionary).is_empty():
		runtime_state.call("set_palace_built_structures", _legacy_value(state, "palace_built_structures", {}))
	if (runtime_state.call("get_palace_structure_runtime_statuses_copy") as Dictionary).is_empty() and not (_legacy_value(state, "palace_structure_runtime_statuses", {}) as Dictionary).is_empty():
		runtime_state.call("set_palace_structure_runtime_statuses", _legacy_value(state, "palace_structure_runtime_statuses", {}))
	if (runtime_state.call("get_palace_delivered_ruler_demands_copy") as Dictionary).is_empty() and not (_legacy_value(state, "palace_delivered_ruler_demands", {}) as Dictionary).is_empty():
		runtime_state.call("set_palace_delivered_ruler_demands", _legacy_value(state, "palace_delivered_ruler_demands", {}))
	if (runtime_state.call("get_palace_ruler_demand_donations_copy") as Array).is_empty() and not (_legacy_value(state, "palace_ruler_demand_donations", []) as Array).is_empty():
		runtime_state.call("set_palace_ruler_demand_donations", _legacy_value(state, "palace_ruler_demand_donations", []))
	if (runtime_state.call("get_last_palace_maintenance_report_copy") as Array).is_empty() and not (_legacy_value(state, "last_palace_maintenance_report", []) as Array).is_empty():
		runtime_state.call("set_last_palace_maintenance_report", _legacy_value(state, "last_palace_maintenance_report", []))
	runtime_state.call("set_flower_war_palace_gate_enabled_value", bool(_legacy_value(state, "flower_war_palace_gate_enabled", true)))
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

# -----------------------------------------------------------------------------
# Estate / population / warband bridge
# -----------------------------------------------------------------------------

func ensure_campaign_state_estate_structure_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	if (runtime_state.get("population") as Dictionary).is_empty() and not (_legacy_value(state, "population", {}) as Dictionary).is_empty():
		runtime_state.set("population", (_legacy_value(state, "population", {}) as Dictionary).duplicate(true))
	if (runtime_state.get("estate_buildings") as Dictionary).is_empty() and not (_legacy_value(state, "estate_buildings", {}) as Dictionary).is_empty():
		runtime_state.set("estate_buildings", (_legacy_value(state, "estate_buildings", {}) as Dictionary).duplicate(true))
	if (runtime_state.get("active_housing_counts") as Dictionary).is_empty() and not (_legacy_value(state, "active_housing_counts", {}) as Dictionary).is_empty():
		runtime_state.set("active_housing_counts", (_legacy_value(state, "active_housing_counts", {}) as Dictionary).duplicate(true))
	if (runtime_state.get("base_housing_capacity") as Dictionary).is_empty() and not (_legacy_value(state, "base_housing_capacity", {}) as Dictionary).is_empty():
		runtime_state.set("base_housing_capacity", (_legacy_value(state, "base_housing_capacity", {}) as Dictionary).duplicate(true))
	if (runtime_state.get("labour_assignments") as Dictionary).is_empty() and not (_legacy_value(state, "labour_assignments", {}) as Dictionary).is_empty():
		runtime_state.set("labour_assignments", (_legacy_value(state, "labour_assignments", {}) as Dictionary).duplicate(true))
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
	if (runtime_state.get("warbands") as Dictionary).is_empty() and not (_legacy_value(state, "warbands", {}) as Dictionary).is_empty():
		runtime_state.set("warbands", (_legacy_value(state, "warbands", {}) as Dictionary).duplicate(true))
	if (runtime_state.get("last_flower_war_report") as Dictionary).is_empty() and not (_legacy_value(state, "last_flower_war_report", {}) as Dictionary).is_empty():
		runtime_state.set("last_flower_war_report", (_legacy_value(state, "last_flower_war_report", {}) as Dictionary).duplicate(true))
	if (runtime_state.get("flower_war_report_archive") as Array).is_empty() and not (_legacy_value(state, "flower_war_report_archive", []) as Array).is_empty():
		runtime_state.set("flower_war_report_archive", (_legacy_value(state, "flower_war_report_archive", []) as Array).duplicate(true))
	mirror_warband_flower_war_compatibility_from_campaign_state(state)
	return runtime_state

func mirror_warband_flower_war_compatibility_from_campaign_state(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state != null:
		runtime_state.call("mirror_warband_flower_war_state_to_game_state", state)

# -----------------------------------------------------------------------------
# Prestige bridge
# -----------------------------------------------------------------------------

func ensure_campaign_state_prestige_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	if (runtime_state.get("prestige_history") as Array).is_empty() and not (_legacy_value(state, "prestige_history", []) as Array).is_empty():
		runtime_state.set("prestige_history", (_legacy_value(state, "prestige_history", []) as Array).duplicate(true))
	if absf(float(runtime_state.get("player_prestige"))) <= 0.0001 and absf(float(_legacy_value(state, "player_prestige", 0.0))) > 0.0001:
		runtime_state.set("player_prestige", float(_legacy_value(state, "player_prestige", 0.0)))
	if (runtime_state.get("rival_prestige") as Dictionary).is_empty():
		if not (_legacy_value(state, "rival_prestige", {}) as Dictionary).is_empty():
			runtime_state.set("rival_prestige", (_legacy_value(state, "rival_prestige", {}) as Dictionary).duplicate(true))
		elif state != null and state.has_method("_default_rival_prestige_values"):
			runtime_state.set("rival_prestige", state.call("_default_rival_prestige_values"))
	if (runtime_state.get("sacrifice_prestige_records") as Array).is_empty() and not (_legacy_value(state, "sacrifice_prestige_records", []) as Array).is_empty():
		runtime_state.set("sacrifice_prestige_records", (_legacy_value(state, "sacrifice_prestige_records", []) as Array).duplicate(true))
	mirror_prestige_compatibility_from_campaign_state(state)
	return runtime_state

func mirror_prestige_compatibility_from_campaign_state(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null or state == null:
		return
	state.set("player_prestige", float(runtime_state.call("get_player_prestige_value")))
	state.set("rival_prestige", runtime_state.call("get_rival_prestige_copy"))
	state.set("prestige_history", runtime_state.call("get_prestige_history_copy"))
	state.set("sacrifice_prestige_records", runtime_state.call("get_sacrifice_prestige_records_copy"))

# -----------------------------------------------------------------------------
# Religion and rival placeholder bridge for 8H/10 readiness
# -----------------------------------------------------------------------------

func ensure_campaign_state_religion_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	var current: Dictionary = {}
	if runtime_state.has_method("get_religion_state_copy"):
		current = runtime_state.call("get_religion_state_copy") as Dictionary
	if current.is_empty():
		var legacy: Variant = _legacy_meta_or_property(state, "religion_state", {})
		if legacy is Dictionary and not (legacy as Dictionary).is_empty() and runtime_state.has_method("set_religion_state"):
			runtime_state.call("set_religion_state", legacy as Dictionary)
	mirror_religion_state_from_campaign_state_to_legacy(state)
	return runtime_state

func mirror_religion_state_from_campaign_state_to_legacy(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null or state == null:
		return
	if runtime_state.has_method("mirror_religion_state_to_game_state"):
		runtime_state.call("mirror_religion_state_to_game_state", state)

func mirror_rival_state_from_campaign_state_to_legacy(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null or state == null:
		return
	if runtime_state.has_method("mirror_rival_state_to_game_state"):
		runtime_state.call("mirror_rival_state_to_game_state", state)

# -----------------------------------------------------------------------------
# Signals and audit
# -----------------------------------------------------------------------------

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
		"current_veintena", "calendar_period", "ritual_year", "last_report", "last_turn_summary", "initialized",
		"player_palace_dedicated_god", "palace_built_structures", "palace_structure_runtime_statuses",
		"palace_delivered_ruler_demands", "palace_ruler_demand_donations", "last_palace_maintenance_report",
		"player_prestige", "rival_prestige", "prestige_history", "sacrifice_prestige_records",
		"religion_state",
		"flower_war_palace_gate_enabled", "last_flower_war_report", "flower_war_report_archive", "warbands",
		"rival_houses", "rival_stockpiles", "rival_build_progress", "rival_action_history"
	]
	var rows: Array[Dictionary] = []
	var mismatch_count: int = 0
	for field_name: String in fields:
		var live_value: Variant = _legacy_meta_or_property(state, field_name, null)
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
			"mirror_preview": campaign_state_preview(mirror_value),
			"authoritative": field_name in AUTHORITATIVE_CALENDAR_FIELDS
		})
	return {
		"schema_version": "campaign_state_sync_report_v0_47_5_patch_8g",
		"sync_first": sync_first,
		"field_count": fields.size(),
		"mismatch_count": mismatch_count,
		"in_sync": mismatch_count == 0,
		"rows": rows,
		"calendar_report_authority": "CampaignState"
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

# -----------------------------------------------------------------------------
# Small compatibility helpers
# -----------------------------------------------------------------------------

func _legacy_value(state: Node, property_name: String, fallback: Variant) -> Variant:
	if state == null:
		return fallback
	var value: Variant = state.get(property_name)
	if value == null:
		return fallback
	return value

func _legacy_meta_or_property(state: Node, key: String, fallback: Variant) -> Variant:
	if state == null:
		return fallback
	if state.has_meta(key):
		return state.get_meta(key)
	var value: Variant = state.get(key)
	if value == null:
		return fallback
	return value
