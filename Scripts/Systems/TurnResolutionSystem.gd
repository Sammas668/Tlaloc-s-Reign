# TurnResolutionSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/TurnResolutionSystem.gd
#
# Owns the live Veintena resolution order for the TRGameState/CampaignState
# migration path. This extracts turn orchestration from TRGameState while
# preserving the current order, report text, and signal behaviour.
#
# Patch 6: adds a structured turn summary skeleton while keeping last_report as
# the normal UI-facing text feed. The structured summary is stored as metadata on
# the runtime state under "last_turn_summary" so it does not require a new state
# variable during the CampaignState migration.
class_name TurnResolutionSystem
extends RefCounted

func advance_veintena(state: Node) -> void:
	if state == null:
		return

	if not bool(state.get("initialized")):
		if state.has_method("new_game"):
			state.call("new_game")

	var report_variant: Variant = state.get("last_report")
	var report: Array = []
	if report_variant is Array:
		report = report_variant as Array
	report.clear()
	state.set("last_report", report)

	var current_veintena: int = int(state.get("current_veintena"))
	var ritual_year: int = _safe_state_int(state, "ritual_year", 1)
	var summary: Dictionary = _new_turn_summary(current_veintena, ritual_year)

	report.append("Veintena " + str(current_veintena) + " resolves.")
	_add_summary_section(summary, "calendar_start", "Calendar", ["Veintena " + str(current_veintena) + " resolves."])

	var before_estate_stockpiles: Dictionary = _state_dictionary(state, "estate_stockpiles")
	var before_market_stockpiles: Dictionary = _state_dictionary(state, "market_stockpiles")
	var resources: Dictionary = _state_dictionary(state, "resources")

	var previous_demand_index: int = 0
	if state.has_method("_current_palace_ruler_demand_index"):
		previous_demand_index = int(state.call("_current_palace_ruler_demand_index"))

	var previous_demand_title: String = "Court Need"
	if state.has_method("_current_palace_ruler_demand_set"):
		var demand_set_variant: Variant = state.call("_current_palace_ruler_demand_set")
		if demand_set_variant is Dictionary:
			previous_demand_title = String((demand_set_variant as Dictionary).get("title", "Court Need"))

	var previous_demand_completion: Dictionary = {}
	if state.has_method("get_palace_ruler_demand_completion_summary"):
		var completion_variant: Variant = state.call("get_palace_ruler_demand_completion_summary")
		if completion_variant is Dictionary:
			previous_demand_completion = completion_variant as Dictionary

	_resolve_stage(state, report, summary, "population_upkeep", "Population Upkeep", "_pay_population_upkeep")
	_resolve_stage(state, report, summary, "housing_maintenance", "Housing Maintenance", "_pay_housing_maintenance")
	_resolve_stage(state, report, summary, "palace_maintenance", "Palace Maintenance", "_pay_palace_maintenance")
	_resolve_stage(state, report, summary, "building_operations", "Building Operations", "_operate_buildings")
	_resolve_stage(state, report, summary, "warband_recovery", "Warband Recovery", "_recover_injured_warriors")

	var after_estate_stockpiles: Dictionary = _state_dictionary(state, "estate_stockpiles")
	var after_market_stockpiles: Dictionary = _state_dictionary(state, "market_stockpiles")
	var estate_delta_lines: Array[String] = _stockpile_delta_lines(before_estate_stockpiles, after_estate_stockpiles, resources, "Estate stockpiles")
	var market_delta_lines: Array[String] = _stockpile_delta_lines(before_market_stockpiles, after_market_stockpiles, resources, "Market stockpiles")
	for line: String in estate_delta_lines:
		report.append(line)
	for line: String in market_delta_lines:
		report.append(line)
	_add_summary_section(summary, "stockpile_changes", "Stockpile Changes", estate_delta_lines + market_delta_lines)

	current_veintena += 1
	if current_veintena > 18:
		current_veintena = 1
		ritual_year += 1
		state.set("ritual_year", ritual_year)
		report.append("Nemontemi reckoning placeholder: the next Ritual Year begins.")
		_add_summary_section(summary, "nemontemi", "Nemontemi", ["Nemontemi reckoning placeholder: the next Ritual Year begins."])
	state.set("current_veintena", current_veintena)

	var demand_transition_start: int = report.size()
	if state.has_method("_report_palace_ruler_demand_cycle_transition"):
		state.call("_report_palace_ruler_demand_cycle_transition", previous_demand_index, previous_demand_title, previous_demand_completion)
	_add_stage_lines_from_report(summary, "court_needs", "Court Needs", report, demand_transition_start, "No court-need transition this Veintena.")

	var entering_line: String = "Now entering Veintena " + str(current_veintena) + "."
	report.append(entering_line)
	_add_summary_section(summary, "calendar_end", "Next Veintena", [entering_line])

	summary["to_veintena"] = current_veintena
	summary["to_ritual_year"] = ritual_year
	summary["report_line_count"] = report.size()
	state.set("last_report", report)
	state.set_meta("last_turn_summary", summary)

	if state.has_signal("turn_advanced"):
		state.emit_signal("turn_advanced", report)
	if state.has_signal("state_changed"):
		state.emit_signal("state_changed")

func _resolve_stage(state: Node, report: Array, summary: Dictionary, stage_id: String, title: String, method_name: String) -> void:
	var start_index: int = report.size()
	var ran: bool = _call_if_present(state, method_name)
	if ran:
		_add_stage_lines_from_report(summary, stage_id, title, report, start_index, "Resolved without a detailed report line.")
	else:
		_add_summary_section(summary, stage_id, title, ["Skipped: " + method_name + " is not present on the runtime state."])

func _call_if_present(state: Node, method_name: String) -> bool:
	if state != null and state.has_method(method_name):
		state.call(method_name)
		return true
	return false

func _new_turn_summary(from_veintena: int, from_ritual_year: int) -> Dictionary:
	return {
		"schema": "turn_summary_v0_1",
		"from_veintena": from_veintena,
		"from_ritual_year": from_ritual_year,
		"to_veintena": from_veintena,
		"to_ritual_year": from_ritual_year,
		"sections": [],
		"report_line_count": 0
	}

func _add_stage_lines_from_report(summary: Dictionary, section_id: String, title: String, report: Array, start_index: int, fallback_line: String) -> void:
	var lines: Array[String] = []
	for index: int in range(start_index, report.size()):
		lines.append(String(report[index]))
	if lines.is_empty():
		lines.append(fallback_line)
	_add_summary_section(summary, section_id, title, lines)

func _add_summary_section(summary: Dictionary, section_id: String, title: String, lines: Array[String]) -> void:
	var sections: Array = summary.get("sections", []) as Array
	sections.append({
		"id": section_id,
		"title": title,
		"lines": lines.duplicate()
	})
	summary["sections"] = sections

func _state_dictionary(state: Node, property_name: String) -> Dictionary:
	if state == null:
		return {}
	var value: Variant = state.get(property_name)
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func _safe_state_int(state: Node, property_name: String, fallback: int) -> int:
	if state == null:
		return fallback
	var value: Variant = state.get(property_name)
	if value == null:
		return fallback
	return int(value)

func _stockpile_delta_lines(before: Dictionary, after: Dictionary, resources: Dictionary, label: String) -> Array[String]:
	var changes: Array[Dictionary] = []
	var seen: Dictionary = {}
	for key_variant: Variant in before.keys():
		seen[String(key_variant)] = true
	for key_variant: Variant in after.keys():
		seen[String(key_variant)] = true
	for key_variant: Variant in seen.keys():
		var resource_id: String = String(key_variant)
		var delta: float = float(after.get(resource_id, 0.0)) - float(before.get(resource_id, 0.0))
		if absf(delta) <= 0.001:
			continue
		changes.append({"id": resource_id, "delta": delta})
	changes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a.get("delta", 0.0))) > absf(float(b.get("delta", 0.0)))
	)
	if changes.is_empty():
		return [label + ": no visible net change."]
	var parts: Array[String] = []
	var count: int = 0
	for change: Dictionary in changes:
		if count >= 8:
			break
		var resource_id: String = String(change.get("id", ""))
		var delta_value: float = float(change.get("delta", 0.0))
		parts.append(_resource_display_name(resource_id, resources) + " " + _signed_amount(delta_value))
		count += 1
	var line: String = label + ": " + "; ".join(parts)
	if changes.size() > count:
		line += "; +" + str(changes.size() - count) + " more changed goods"
	line += "."
	return [line]

func _resource_display_name(resource_id: String, resources: Dictionary) -> String:
	if resources.has(resource_id) and resources[resource_id] is Dictionary:
		var data: Dictionary = resources[resource_id] as Dictionary
		return String(data.get("name", resource_id.replace("_", " ").capitalize()))
	return resource_id.replace("_", " ").capitalize()

func _signed_amount(value: float) -> String:
	var prefix: String = "+" if value >= 0.0 else ""
	return prefix + _fmt(value)

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))
