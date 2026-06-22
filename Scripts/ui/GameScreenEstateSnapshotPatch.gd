# GameScreenEstateSnapshotPatch.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenEstateSnapshotPatch.gd
#
# Patch 8P1C: Estate screen per-refresh snapshot cache.
#
# The base Estate screen builds report subtitles/details by repeatedly asking
# Storehouse, Production, Housing and Labour helpers for the same information.
# This wrapper keeps the 8P1B coalesced refresh behaviour, then prepares one
# Estate overview snapshot before the deferred full refresh is flushed. During
# that refresh, Estate helper calls read from the snapshot instead of repeatedly
# recalculating the same summaries.
extends "res://Scripts/ui/GameScreenCoalescedRefreshPatch.gd"

var _estate_overview_snapshot: Dictionary = {}
var _estate_snapshot_active: bool = false


func _flush_refresh_all() -> void:
	if not _refresh_pending:
		return

	_prepare_estate_overview_snapshot_for_refresh()
	super._flush_refresh_all()


func _prepare_estate_overview_snapshot_for_refresh() -> void:
	_estate_overview_snapshot.clear()
	_estate_snapshot_active = false
	if current_location_id != "estate":
		return
	_estate_overview_snapshot = _build_estate_overview_snapshot()
	_estate_snapshot_active = true


func get_estate_overview_snapshot() -> Dictionary:
	if _estate_snapshot_active:
		return _estate_overview_snapshot.duplicate(true)
	return _build_estate_overview_snapshot()


func _build_estate_overview_snapshot() -> Dictionary:
	var state: Node = _state()
	var snapshot: Dictionary = {
		"previous_turn_lines": _read_last_turn_report_lines_uncached(state),
		"production_resolution": {},
		"production_output_totals": {},
		"production_input_totals": {},
		"storehouse_goods": [],
		"goods_warning_lines": [],
		"housing_summary": {},
		"production_building_summary": {},
		"production_buildable_count": 0,
		"action_priority_lines": []
	}

	if state == null:
		return snapshot

	var production_resolution: Dictionary = _read_production_resolution_uncached(state)
	snapshot["production_resolution"] = production_resolution
	snapshot["production_output_totals"] = _dictionary_copy(production_resolution.get("outputs", {}) as Dictionary)
	snapshot["production_input_totals"] = _dictionary_copy(production_resolution.get("inputs", {}) as Dictionary)
	snapshot["housing_summary"] = super._housing_summary()
	snapshot["production_building_summary"] = _build_production_summary_from_resolution(state, production_resolution)
	snapshot["production_buildable_count"] = _read_production_buildable_count_uncached(state)
	snapshot["storehouse_goods"] = _build_storehouse_goods_from_snapshot(state, snapshot)
	snapshot["goods_warning_lines"] = _build_goods_warning_lines_from_goods(snapshot["storehouse_goods"] as Array, 99)
	snapshot["action_priority_lines"] = _build_action_priority_lines_from_snapshot(snapshot, 99)

	return snapshot


# -----------------------------------------------------------------------------
# Estate helper overrides
# -----------------------------------------------------------------------------

func _last_turn_report_lines() -> Array[String]:
	if _estate_snapshot_active and _estate_overview_snapshot.has("previous_turn_lines"):
		return _string_array_copy(_estate_overview_snapshot.get("previous_turn_lines", []))
	return super._last_turn_report_lines()


func _storehouse_goods() -> Array[Dictionary]:
	if _estate_snapshot_active and _estate_overview_snapshot.has("storehouse_goods"):
		return _dictionary_array_copy(_estate_overview_snapshot.get("storehouse_goods", []))
	return super._storehouse_goods()


func _production_output_totals() -> Dictionary:
	if _estate_snapshot_active and _estate_overview_snapshot.has("production_output_totals"):
		return _dictionary_copy(_estate_overview_snapshot.get("production_output_totals", {}) as Dictionary)
	return super._production_output_totals()


func _production_input_totals() -> Dictionary:
	if _estate_snapshot_active and _estate_overview_snapshot.has("production_input_totals"):
		return _dictionary_copy(_estate_overview_snapshot.get("production_input_totals", {}) as Dictionary)
	return super._production_input_totals()


func _housing_summary() -> Dictionary:
	if _estate_snapshot_active and _estate_overview_snapshot.has("housing_summary"):
		return _dictionary_copy(_estate_overview_snapshot.get("housing_summary", {}) as Dictionary)
	return super._housing_summary()


func _production_building_summary() -> Dictionary:
	if _estate_snapshot_active and _estate_overview_snapshot.has("production_building_summary"):
		return _dictionary_copy(_estate_overview_snapshot.get("production_building_summary", {}) as Dictionary)
	return super._production_building_summary()


func _production_buildable_count() -> int:
	if _estate_snapshot_active and _estate_overview_snapshot.has("production_buildable_count"):
		return int(_estate_overview_snapshot.get("production_buildable_count", 0))
	return super._production_buildable_count()


func _estate_goods_warning_lines(max_items: int = 8) -> Array[String]:
	if _estate_snapshot_active and _estate_overview_snapshot.has("goods_warning_lines"):
		return _limited_string_array(_estate_overview_snapshot.get("goods_warning_lines", []), max_items)
	return super._estate_goods_warning_lines(max_items)


func _estate_action_priority_lines(max_items: int = 8) -> Array[String]:
	if _estate_snapshot_active and _estate_overview_snapshot.has("action_priority_lines"):
		return _limited_string_array(_estate_overview_snapshot.get("action_priority_lines", []), max_items)
	return super._estate_action_priority_lines(max_items)


# -----------------------------------------------------------------------------
# Snapshot construction helpers
# -----------------------------------------------------------------------------

func _read_last_turn_report_lines_uncached(state: Node) -> Array[String]:
	var output: Array[String] = []
	if state != null and state.has_method("get_last_report"):
		var raw: Array = state.call("get_last_report") as Array
		for line_variant: Variant in raw:
			var line: String = String(line_variant)
			if line.strip_edges() != "":
				output.append(line)
	return output


func _read_production_resolution_uncached(state: Node) -> Dictionary:
	if state != null and state.has_method("estimate_production_resolution"):
		var raw: Variant = state.call("estimate_production_resolution")
		if raw is Dictionary:
			return (raw as Dictionary).duplicate(true)
	return {}


func _read_production_buildable_count_uncached(state: Node) -> int:
	var count: int = 0
	var campaign_state: RefCounted = _campaign_state_for_snapshot(state)
	if campaign_state == null:
		return super._production_buildable_count()
	if not campaign_state.has_method("get_buildings_copy") or not campaign_state.has_method("get_building_order_copy"):
		return super._production_buildable_count()

	var buildings: Dictionary = campaign_state.call("get_buildings_copy") as Dictionary
	var order: Array = campaign_state.call("get_building_order_copy") as Array
	for building_variant: Variant in order:
		var building_id: String = String(building_variant)
		if not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var screen_id: String = String(definition.get("screen", ""))
		if screen_id != "chinampas" and screen_id != "workshops":
			continue
		if state.has_method("can_build") and bool(state.call("can_build", building_id)):
			count += 1
	return count


func _build_production_summary_from_resolution(state: Node, production_resolution: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"built": 0,
		"operating": 0,
		"blocked": 0,
		"blocked_lines": [],
		"unbuilt_lines": []
	}

	var campaign_state: RefCounted = _campaign_state_for_snapshot(state)
	if campaign_state == null:
		return super._production_building_summary()
	if not campaign_state.has_method("get_buildings_copy") or not campaign_state.has_method("get_building_order_copy") or not campaign_state.has_method("get_estate_buildings_copy"):
		return super._production_building_summary()

	var buildings: Dictionary = campaign_state.call("get_buildings_copy") as Dictionary
	var order: Array = campaign_state.call("get_building_order_copy") as Array
	var estate_buildings: Dictionary = campaign_state.call("get_estate_buildings_copy") as Dictionary
	var statuses: Dictionary = production_resolution.get("building_statuses", {}) as Dictionary
	var blocked_lines: Array[String] = []
	var unbuilt_lines: Array[String] = []
	var built_count: int = 0
	var operating_count: int = 0
	var blocked_count: int = 0

	for building_variant: Variant in order:
		var building_id: String = String(building_variant)
		if not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var screen_id: String = String(definition.get("screen", ""))
		if screen_id != "chinampas" and screen_id != "workshops":
			continue

		var name: String = String(definition.get("name", building_id.capitalize()))
		var count: int = int(estate_buildings.get(building_id, 0))
		var status: Dictionary = statuses.get(building_id, {}) as Dictionary
		var operating: int = int(status.get("operating", 0))
		var blocked: int = int(status.get("blocked", 0))

		built_count += count
		operating_count += operating
		blocked_count += blocked

		if count <= 0:
			unbuilt_lines.append(name + " not built")
		elif blocked > 0:
			blocked_lines.append(name + " " + String(status.get("status_text", "blocked")))

	result["built"] = built_count
	result["operating"] = operating_count
	result["blocked"] = blocked_count
	result["blocked_lines"] = blocked_lines
	result["unbuilt_lines"] = unbuilt_lines
	return result


func _build_storehouse_goods_from_snapshot(state: Node, snapshot: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var campaign_state: RefCounted = _campaign_state_for_snapshot(state)
	if campaign_state == null:
		return output
	if not campaign_state.has_method("get_resource_order_copy") or not campaign_state.has_method("get_resources_copy") or not campaign_state.has_method("get_estate_stock"):
		return output

	var resource_order: Array = campaign_state.call("get_resource_order_copy") as Array
	var resources: Dictionary = campaign_state.call("get_resources_copy") as Dictionary
	var incoming: Dictionary = snapshot.get("production_output_totals", {}) as Dictionary
	var building_inputs: Dictionary = snapshot.get("production_input_totals", {}) as Dictionary
	var production_resolution: Dictionary = snapshot.get("production_resolution", {}) as Dictionary
	var housing_maintenance: Dictionary = production_resolution.get("housing_maintenance_needed", {}) as Dictionary
	var upkeep: Dictionary = production_resolution.get("upkeep_needed", {}) as Dictionary

	if housing_maintenance.is_empty() and state.has_method("estimate_housing_maintenance"):
		housing_maintenance = state.call("estimate_housing_maintenance") as Dictionary
	if upkeep.is_empty() and state.has_method("estimate_population_upkeep"):
		upkeep = state.call("estimate_population_upkeep") as Dictionary

	for resource_variant: Variant in resource_order:
		var resource_id: String = String(resource_variant)
		if not resources.has(resource_id):
			continue

		var resource_data: Dictionary = resources[resource_id] as Dictionary
		var stored: float = float(campaign_state.call("get_estate_stock", resource_id))
		var in_value: float = float(incoming.get(resource_id, 0.0))
		var upkeep_value: float = float(upkeep.get(resource_id, 0.0))
		var input_value: float = float(building_inputs.get(resource_id, 0.0))
		var housing_value: float = float(housing_maintenance.get(resource_id, 0.0))
		var outgoing: float = upkeep_value + input_value + housing_value
		var reserved: float = outgoing
		var free_value: float = maxf(0.0, stored - reserved)

		output.append({
			"id": resource_id,
			"name": String(resource_data.get("name", resource_id.capitalize())),
			"category": String(resource_data.get("category", "raw")),
			"stored": stored,
			"incoming": in_value,
			"outgoing": outgoing,
			"reserved": reserved,
			"free": free_value,
			"net": in_value - outgoing,
			"pressure": _snapshot_pressure_label(stored, outgoing),
			"uses": resource_data.get("uses", []) as Array,
			"reserved_breakdown": _snapshot_reserve_breakdown(upkeep_value, input_value, housing_value)
		})

	return output


func _build_goods_warning_lines_from_goods(goods: Array, max_items: int) -> Array[String]:
	var output: Array[String] = []
	for good_variant: Variant in goods:
		if output.size() >= max_items:
			break
		if not (good_variant is Dictionary):
			continue
		var good: Dictionary = good_variant as Dictionary
		var name: String = String(good.get("name", "Good"))
		var stored: float = float(good.get("stored", 0.0))
		var incoming: float = float(good.get("incoming", 0.0))
		var outgoing: float = float(good.get("outgoing", 0.0))
		var free_value: float = float(good.get("free", maxf(0.0, stored - outgoing)))
		var projected: float = stored + incoming - outgoing
		if projected < -0.001:
			output.append(name + ": projected shortage of " + _format_float(absf(projected)) + " after next turn.")
		elif free_value <= 0.001 and outgoing > 0.001:
			output.append(name + ": fully reserved by upkeep, maintenance or inputs.")
		elif incoming - outgoing < -0.001:
			output.append(name + ": declining by " + _format_float(absf(incoming - outgoing)) + " this turn.")
	return output


func _build_action_priority_lines_from_snapshot(snapshot: Dictionary, max_items: int) -> Array[String]:
	var output: Array[String] = []
	var warnings: Array[String] = _limited_string_array(snapshot.get("goods_warning_lines", []), 4)
	for warning: String in warnings:
		output.append("Resolve goods pressure — " + warning)

	var housing: Dictionary = snapshot.get("housing_summary", {}) as Dictionary
	var inactive: int = int(housing.get("total_inactive_population", 0))
	if inactive > 0:
		output.append("Open Housing or Mothball — " + str(inactive) + " people are inactive.")

	var production_summary: Dictionary = snapshot.get("production_building_summary", {}) as Dictionary
	var blocked: int = int(production_summary.get("blocked", 0))
	if blocked > 0:
		output.append("Open Production — " + str(blocked) + " production instance(s) are blocked or unstaffed.")

	var buildable_count: int = int(snapshot.get("production_buildable_count", 0))
	if buildable_count > 0:
		output.append("Consider Production expansion — " + str(buildable_count) + " production building type(s) are buildable now.")

	if output.is_empty():
		var outputs: String = _resource_dictionary_inline(snapshot.get("production_output_totals", {}) as Dictionary, 3)
		if outputs != "":
			output.append("Production looks stable. Expected output: " + outputs + ".")
		else:
			output.append("No urgent warning, but production output is low. Consider building or staffing production.")

	while output.size() > max_items:
		output.pop_back()
	return output


# -----------------------------------------------------------------------------
# Small local utilities
# -----------------------------------------------------------------------------

func _campaign_state_for_snapshot(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null


func _snapshot_pressure_label(stored: float, outgoing: float) -> String:
	if outgoing <= 0.0:
		if stored > 0.0:
			return "Surplus"
		return "Idle"
	var coverage: float = stored / outgoing
	if coverage >= 3.0:
		return "Secure"
	if coverage >= 1.5:
		return "Watch"
	if coverage >= 1.0:
		return "Tight"
	return "Shortfall"


func _snapshot_reserve_breakdown(upkeep_value: float, input_value: float, housing_value: float) -> Array[String]:
	var lines: Array[String] = []
	if upkeep_value > 0.0:
		lines.append("Population upkeep: " + _format_float(upkeep_value))
	if input_value > 0.0:
		lines.append("Production inputs: " + _format_float(input_value))
	if housing_value > 0.0:
		lines.append("Housing maintenance: " + _format_float(housing_value))
	if lines.is_empty():
		lines.append("No current reserve.")
	return lines


func _dictionary_copy(values: Dictionary) -> Dictionary:
	return values.duplicate(true)


func _dictionary_array_copy(values: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if values is Array:
		for item_variant: Variant in values as Array:
			if item_variant is Dictionary:
				output.append((item_variant as Dictionary).duplicate(true))
	return output


func _string_array_copy(values: Variant) -> Array[String]:
	var output: Array[String] = []
	if values is Array:
		for item_variant: Variant in values as Array:
			output.append(String(item_variant))
	return output


func _limited_string_array(values: Variant, max_items: int) -> Array[String]:
	var output: Array[String] = []
	if not (values is Array):
		return output
	for item_variant: Variant in values as Array:
		if output.size() >= max_items:
			break
		output.append(String(item_variant))
	return output
