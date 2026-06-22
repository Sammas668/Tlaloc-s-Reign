# TurnResolutionSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/TurnResolutionSystem.gd
#
# CampaignState-authoritative turn/calendar runtime.
# Divine favour decay runs from turn runtime, not UI.
# Owns the live Veintena / Nemontemi resolution order while CampaignState owns
# current_veintena, calendar_period, ritual_year, last_report and
# last_turn_summary. TRGameState remains the public facade and compatibility API.

class_name TurnResolutionSystem
extends RefCounted

const RELIGION_STATE_SYSTEM_SCRIPT: Script = preload("res://Scripts/Systems/ReligionStateSystem.gd")
const SHRINE_RITUAL_RULES_SCRIPT: Script = preload("res://Scripts/Systems/ShrineRitualRules.gd")

const GOD_IDS: Array[String] = ["tlaloc", "huitzilopochtli", "tezcatlipoca", "quetzalcoatl"]
const RELIGION_NORMAL_DECAY: float = 2.0
const RELIGION_NEMONTEMI_DECAY: float = 4.0


func advance_turn(state: Node) -> void:
	advance_veintena(state)


func advance_veintena(state: Node) -> void:
	if state == null:
		return

	if not _campaign_initialized(state):
		if state.has_method("new_game"):
			state.call("new_game")

	if _calendar_period(state) == "nemontemi":
		_resolve_nemontemi(state)
		return

	_resolve_ordinary_veintena(state)


func _resolve_ordinary_veintena(state: Node) -> void:
	var current_veintena: int = _current_veintena(state)
	var ritual_year: int = _ritual_year(state)
	var summary: Dictionary = _new_turn_summary(current_veintena, ritual_year, "veintena")

	_set_report_lines(state, [])
	_append_report_line(state, "Veintena " + str(current_veintena) + " resolves.")
	_add_summary_section(summary, "calendar_start", "Calendar", ["Veintena " + str(current_veintena) + " resolves."])

	var before_estate_stockpiles: Dictionary = _campaign_dictionary(state, "estate_stockpiles")
	var before_market_stockpiles: Dictionary = _campaign_dictionary(state, "market_stockpiles")
	var resources: Dictionary = _campaign_dictionary(state, "resources")

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

	_resolve_stage(state, summary, "population_upkeep", "Population Upkeep", "_pay_population_upkeep")
	_resolve_stage(state, summary, "housing_maintenance", "Housing Maintenance", "_pay_housing_maintenance")
	_resolve_stage(state, summary, "palace_maintenance", "Palace Maintenance", "_pay_palace_maintenance")
	_resolve_stage(state, summary, "building_operations", "Building Operations", "_operate_buildings")
	_resolve_stage(state, summary, "warband_recovery", "Warband Recovery", "_recover_injured_warriors")
	_resolve_religion_decay_stage(state, summary, "religion_decay", "Religion", RELIGION_NORMAL_DECAY)

	var after_estate_stockpiles: Dictionary = _campaign_dictionary(state, "estate_stockpiles")
	var after_market_stockpiles: Dictionary = _campaign_dictionary(state, "market_stockpiles")
	var estate_delta_lines: Array[String] = _stockpile_delta_lines(before_estate_stockpiles, after_estate_stockpiles, resources, "Estate stockpiles")
	var market_delta_lines: Array[String] = _stockpile_delta_lines(before_market_stockpiles, after_market_stockpiles, resources, "Market stockpiles")

	for line: String in estate_delta_lines:
		_append_report_line(state, line)
	for line: String in market_delta_lines:
		_append_report_line(state, line)

	_add_summary_section(summary, "stockpile_changes", "Stockpile Changes", estate_delta_lines + market_delta_lines)

	var next_veintena: int = current_veintena + 1
	var next_period: String = "veintena"

	if current_veintena >= 18:
		next_veintena = 18
		next_period = "nemontemi"
		var nemontemi_line: String = "Final ordinary Veintena complete. Now entering Nemontemi for Ritual Year " + str(ritual_year) + "."
		_append_report_line(state, nemontemi_line)
		_add_summary_section(summary, "nemontemi", "Nemontemi", [nemontemi_line])
	else:
		var entering_line: String = "Now entering Veintena " + str(next_veintena) + "."
		_append_report_line(state, entering_line)
		_add_summary_section(summary, "calendar_end", "Next Veintena", [entering_line])

	_set_calendar_runtime_state(state, next_veintena, ritual_year, next_period)

	var demand_transition_start: int = _get_report_lines(state).size()
	if state.has_method("_report_palace_ruler_demand_cycle_transition"):
		state.call("_report_palace_ruler_demand_cycle_transition", previous_demand_index, previous_demand_title, previous_demand_completion)
	_add_stage_lines_from_report(summary, "court_needs", "Court Needs", _get_report_lines(state), demand_transition_start, "No court-need transition this Veintena.")

	summary["to_veintena"] = next_veintena
	summary["to_ritual_year"] = ritual_year
	summary["to_period"] = next_period
	summary["report_line_count"] = _get_report_lines(state).size()

	_set_last_turn_summary(state, summary)
	_emit_turn_signals(state)


func _resolve_nemontemi(state: Node) -> void:
	var ritual_year: int = _ritual_year(state)
	var summary: Dictionary = _new_turn_summary(18, ritual_year, "nemontemi")

	_set_report_lines(state, [])
	_append_report_line(state, "Nemontemi reckoning resolves for Ritual Year " + str(ritual_year) + ".")
	_append_report_line(state, "Nemontemi restrictions hook: no Flower Wars; construction, market activity and productivity restrictions can be connected later.")

	_resolve_religion_decay_stage(state, summary, "nemontemi_religion_decay", "Nemontemi Religion", RELIGION_NEMONTEMI_DECAY)

	_append_report_line(state, "Annual review hooks: prestige, palace recognition, rival comparison, Flower War results and offering history will be connected later.")

	var next_year: int = ritual_year + 1
	_set_calendar_runtime_state(state, 1, next_year, "veintena")
	_append_report_line(state, "Ritual Year " + str(next_year) + " begins at Veintena 1.")
	_add_summary_section(summary, "nemontemi", "Nemontemi", _get_report_lines(state))

	summary["to_veintena"] = 1
	summary["to_ritual_year"] = next_year
	summary["to_period"] = "veintena"
	summary["report_line_count"] = _get_report_lines(state).size()

	_set_last_turn_summary(state, summary)
	_emit_turn_signals(state)


# -----------------------------------------------------------------------------
# CampaignState-authoritative helpers
# -----------------------------------------------------------------------------

func _campaign_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null


func _campaign_initialized(state: Node) -> bool:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_initialized_value"):
		return bool(runtime_state.call("get_initialized_value"))
	return false


func _current_veintena(state: Node) -> int:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_current_veintena_value"):
		return clampi(int(runtime_state.call("get_current_veintena_value")), 1, 18)
	return 1


func _calendar_period(state: Node) -> String:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_calendar_period_value"):
		return String(runtime_state.call("get_calendar_period_value"))
	return "veintena"


func _ritual_year(state: Node) -> int:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_ritual_year_value"):
		return max(1, int(runtime_state.call("get_ritual_year_value")))
	return 1


func _get_report_lines(state: Node) -> Array:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_last_report_copy"):
		return runtime_state.call("get_last_report_copy") as Array
	return []


func _set_calendar_runtime_state(state: Node, veintena: int, ritual_year: int, period: String) -> void:
	if state != null and state.has_method("_get_campaign_bridge_system"):
		var bridge: Variant = state.call("_get_campaign_bridge_system")
		if bridge is RefCounted and (bridge as RefCounted).has_method("set_calendar_runtime_state"):
			(bridge as RefCounted).call("set_calendar_runtime_state", state, veintena, ritual_year, period)
			return

	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		if runtime_state.has_method("set_current_veintena"):
			runtime_state.call("set_current_veintena", veintena)
		if runtime_state.has_method("set_ritual_year_value"):
			runtime_state.call("set_ritual_year_value", ritual_year)
		if runtime_state.has_method("set_calendar_period_value"):
			runtime_state.call("set_calendar_period_value", period)


func _set_report_lines(state: Node, lines: Array) -> void:
	if state != null and state.has_method("_set_report_lines"):
		state.call("_set_report_lines", lines)
		return

	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("set_last_report"):
		runtime_state.call("set_last_report", lines)


func _append_report_line(state: Node, line: String) -> void:
	if state != null and state.has_method("_append_report_line"):
		state.call("_append_report_line", line)
		return

	var lines: Array = _get_report_lines(state)
	lines.append(line)
	_set_report_lines(state, lines)


func _set_last_turn_summary(state: Node, summary: Dictionary) -> void:
	if state != null and state.has_method("_get_campaign_bridge_system"):
		var bridge: Variant = state.call("_get_campaign_bridge_system")
		if bridge is RefCounted and (bridge as RefCounted).has_method("set_last_turn_summary"):
			(bridge as RefCounted).call("set_last_turn_summary", state, summary)
			return

	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("set_last_turn_summary"):
		runtime_state.call("set_last_turn_summary", summary)


func _campaign_dictionary(state: Node, property_name: String) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state == null:
		return {}

	match property_name:
		"estate_stockpiles":
			if runtime_state.has_method("get_estate_stockpiles_copy"):
				return runtime_state.call("get_estate_stockpiles_copy") as Dictionary
		"market_stockpiles":
			if runtime_state.has_method("get_market_stockpiles_copy"):
				return runtime_state.call("get_market_stockpiles_copy") as Dictionary
		"resources":
			if runtime_state.has_method("get_resources_copy"):
				return runtime_state.call("get_resources_copy") as Dictionary
	return {}


# -----------------------------------------------------------------------------
# Religion turn helpers
# -----------------------------------------------------------------------------

func _resolve_religion_decay_stage(state: Node, summary: Dictionary, section_id: String, title: String, decay_amount: float) -> void:
	var start_index: int = _get_report_lines(state).size()
	var ran: bool = _apply_divine_favour_decay(state, decay_amount)
	if ran:
		_reset_religion_ritual_capacity(state)
		_add_stage_lines_from_report(summary, section_id, title, _get_report_lines(state), start_index, "Divine favour decay resolved.")
	else:
		_add_summary_section(summary, section_id, title, ["Skipped: CampaignState-backed religion state is not available."])


func _apply_divine_favour_decay(state: Node, decay_amount: float) -> bool:
	var religion_state: RefCounted = _religion_state_system(state)
	if religion_state == null:
		return false

	if religion_state.has_method("ensure"):
		religion_state.call("ensure", GOD_IDS)

	var parts: Array[String] = []
	for god_id: String in GOD_IDS:
		var before: float = 40.0
		if religion_state.has_method("favour"):
			before = float(religion_state.call("favour", god_id, 40.0))

		var actual_decay: float = _religion_decay_for_god(religion_state, god_id, decay_amount)
		var after: float = clampf(before - actual_decay, 0.0, 100.0)

		if religion_state.has_method("set_favour"):
			religion_state.call("set_favour", god_id, after)

		parts.append(_god_name(god_id) + " " + _fmt(before) + "→" + _fmt(after))

	_append_report_line(state, "Divine favour decays: " + "; ".join(parts) + ".")
	return true


func _reset_religion_ritual_capacity(state: Node) -> void:
	var religion_state: RefCounted = _religion_state_system(state)
	if religion_state != null and religion_state.has_method("reset_ritual_capacity"):
		religion_state.call("reset_ritual_capacity")


func _religion_state_system(state: Node) -> RefCounted:
	if state != null:
		if state.has_method("get_religion_state_system"):
			var public_raw: Variant = state.call("get_religion_state_system")
			if public_raw is RefCounted:
				return public_raw as RefCounted
		if state.has_method("_get_religion_state_system"):
			var private_raw: Variant = state.call("_get_religion_state_system")
			if private_raw is RefCounted:
				return private_raw as RefCounted

	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		var campaign_backed: RefCounted = RELIGION_STATE_SYSTEM_SCRIPT.new() as RefCounted
		if campaign_backed != null and campaign_backed.has_method("bind_campaign_state"):
			campaign_backed.call("bind_campaign_state", runtime_state, GOD_IDS)
		return campaign_backed

	return null


func _religion_decay_for_god(religion_state: RefCounted, god_id: String, base_decay: float) -> float:
	var reduction: float = 0.0
	var purchased: Array[String] = []

	if religion_state != null and religion_state.has_method("purchased_upgrade_ids"):
		var raw_purchased: Variant = religion_state.call("purchased_upgrade_ids", god_id)
		if raw_purchased is Array:
			for upgrade_variant: Variant in raw_purchased as Array:
				purchased.append(String(upgrade_variant))

	var shrine_level: int = 1
	if religion_state != null and religion_state.has_method("shrine_level"):
		shrine_level = int(religion_state.call("shrine_level", god_id))

	for upgrade_id: String in purchased:
		var upgrade: Dictionary = _shrine_upgrade_by_id(god_id, upgrade_id)
		if upgrade.is_empty():
			continue
		if int(upgrade.get("level", 1)) > shrine_level:
			continue
		reduction += float(upgrade.get("decay_reduction", 0.0))

	return maxf(0.0, base_decay - reduction)


func _shrine_upgrade_by_id(god_id: String, upgrade_id: String) -> Dictionary:
	var upgrades: Array = SHRINE_RITUAL_RULES_SCRIPT.god_upgrade_definitions(god_id)
	for upgrade_variant: Variant in upgrades:
		if upgrade_variant is Dictionary:
			var upgrade: Dictionary = upgrade_variant as Dictionary
			if String(upgrade.get("id", "")) == upgrade_id:
				return upgrade.duplicate(true)
	return {}


func _god_name(god_id: String) -> String:
	return String(SHRINE_RITUAL_RULES_SCRIPT.god_name(god_id))


# -----------------------------------------------------------------------------
# Stage and summary helpers
# -----------------------------------------------------------------------------

func _resolve_stage(state: Node, summary: Dictionary, stage_id: String, title: String, method_name: String) -> void:
	var start_index: int = _get_report_lines(state).size()
	var ran: bool = _call_if_present(state, method_name)
	var report_after: Array = _get_report_lines(state)
	if ran:
		_add_stage_lines_from_report(summary, stage_id, title, report_after, start_index, "Resolved without a detailed report line.")
	else:
		_add_summary_section(summary, stage_id, title, ["Skipped: " + method_name + " is not present on the runtime state."])


func _call_if_present(state: Node, method_name: String) -> bool:
	if state != null and state.has_method(method_name):
		state.call(method_name)
		return true
	return false


func _new_turn_summary(from_veintena: int, from_ritual_year: int, from_period: String = "veintena") -> Dictionary:
	return {
		"schema": "turn_summary_v0_47_5_patch_8g",
		"from_veintena": from_veintena,
		"from_ritual_year": from_ritual_year,
		"from_period": from_period,
		"to_veintena": from_veintena,
		"to_ritual_year": from_ritual_year,
		"to_period": from_period,
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


func _emit_turn_signals(state: Node) -> void:
	var report: Array = _get_report_lines(state)
	if state != null and state.has_signal("turn_advanced"):
		state.emit_signal("turn_advanced", report)
	if state != null and state.has_signal("state_changed"):
		state.emit_signal("state_changed")


# -----------------------------------------------------------------------------
# Formatting helpers
# -----------------------------------------------------------------------------

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
