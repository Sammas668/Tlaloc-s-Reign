# TurnRuntimeSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/TurnRuntimeSystem.gd
#
# Owns small turn-runtime helper bodies that were still sitting in TRGameState.
# Reads/writes CampaignState through runtime helpers instead of treating
# TRGameState duplicate state fields as the source of truth.

class_name TurnRuntimeSystem
extends RefCounted


func estimate_building_inputs(state: Node) -> Dictionary:
	if state == null or not state.has_method("estimate_production_resolution"):
		return {}
	var resolution: Dictionary = state.call("estimate_production_resolution") as Dictionary
	return (resolution.get("inputs", {}) as Dictionary).duplicate(true)


func estimate_building_outputs(state: Node) -> Dictionary:
	if state == null or not state.has_method("estimate_production_resolution"):
		return {}
	var resolution: Dictionary = state.call("estimate_production_resolution") as Dictionary
	return (resolution.get("outputs", {}) as Dictionary).duplicate(true)


func pay_population_upkeep(state: Node) -> void:
	if state == null:
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state == null or not runtime_state.has_method("get_estate_stockpiles_copy"):
		return

	var working_stockpiles: Dictionary = runtime_state.call("get_estate_stockpiles_copy") as Dictionary
	var upkeep_system: Object = state.call("_get_population_upkeep_system") as Object
	var active_population: Dictionary = state.call("active_population_by_group") as Dictionary
	var rates: Dictionary = _population_upkeep_rates(state)
	var resolution: Dictionary = upkeep_system.call("resolve_population_upkeep", working_stockpiles, active_population, rates) as Dictionary
	if runtime_state.has_method("set_estate_stockpiles_values"):
		runtime_state.call("set_estate_stockpiles_values", working_stockpiles)

	var payments: Array = resolution.get("payments", []) as Array
	for payment_variant: Variant in payments:
		if not (payment_variant is Dictionary):
			continue
		var payment: Dictionary = payment_variant as Dictionary
		var resource_id: String = String(payment.get("resource_id", ""))
		var needed: float = float(payment.get("needed", 0.0))
		var paid: float = float(payment.get("paid", 0.0))
		var shortfall: float = float(payment.get("shortfall", 0.0))
		if shortfall <= 0.001:
			_append_report_line(state, "Paid population upkeep: " + _format_amount(state, needed) + " " + _resource_name(state, resource_id) + ".")
		else:
			_append_report_line(state, "Shortage: paid only " + _format_amount(state, paid) + " / " + _format_amount(state, needed) + " " + _resource_name(state, resource_id) + " for population upkeep.")


func pay_housing_maintenance(state: Node) -> void:
	if state == null:
		return
	var housing_system: Object = state.call("_get_housing_system") as Object
	var payments: Array = housing_system.call("pay_housing_maintenance", state) as Array
	for payment_variant: Variant in payments:
		if not (payment_variant is Dictionary):
			continue
		var payment: Dictionary = payment_variant as Dictionary
		var resource_id: String = String(payment.get("resource_id", ""))
		var needed: float = float(payment.get("needed", 0.0))
		var paid: float = float(payment.get("paid", 0.0))
		var shortfall: float = float(payment.get("shortfall", 0.0))
		if shortfall <= 0.001:
			_append_report_line(state, "Paid housing building upkeep: " + _format_amount(state, needed) + " " + _resource_name(state, resource_id) + ".")
		else:
			_append_report_line(state, "Housing building upkeep shortage: paid only " + _format_amount(state, paid) + " / " + _format_amount(state, needed) + " " + _resource_name(state, resource_id) + ".")


func operate_buildings(state: Node) -> void:
	if state == null:
		return
	var production_system: Object = state.call("_get_production_system") as Object
	var reports: Array = production_system.call("operate_buildings", state) as Array
	for report_variant: Variant in reports:
		_append_report_line(state, String(report_variant))


func reserve_staff(staff: Dictionary, available_staff: Dictionary) -> void:
	for group_variant: Variant in staff.keys():
		var group_id: String = String(group_variant)
		available_staff[group_id] = int(available_staff.get(group_id, 0)) - int(staff[group_variant])


func consume_inputs(state: Node, inputs: Dictionary) -> void:
	if state == null:
		return
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		if state.has_method("_add_stock"):
			state.call("_add_stock", resource_id, -float(inputs[resource_id]))


func add_outputs(state: Node, outputs: Dictionary) -> void:
	if state == null:
		return
	for resource_variant: Variant in outputs.keys():
		var resource_id: String = String(resource_variant)
		if state.has_method("_add_stock"):
			state.call("_add_stock", resource_id, float(outputs[resource_id]))


func estimate_building_status(state: Node, building_id: String) -> Dictionary:
	if state == null:
		return _default_building_status("Unknown building.")

	var buildings: Dictionary = _campaign_buildings(state)
	if not buildings.has(building_id):
		return _default_building_status("Unknown building.")

	var resolution: Dictionary = state.call("estimate_production_resolution") as Dictionary
	var statuses: Dictionary = resolution.get("building_statuses", {}) as Dictionary
	if statuses.has(building_id):
		return (statuses[building_id] as Dictionary).duplicate(true)
	return _default_building_status("Not built.")


func estimated_operating_count_for_building(state: Node, building_id: String) -> int:
	if state == null:
		return 0

	var buildings: Dictionary = _campaign_buildings(state)
	if not buildings.has(building_id):
		return 0

	return int(estimate_building_status(state, building_id).get("operating", 0))


func _default_building_status(status_text: String) -> Dictionary:
	return {
		"operating": 0,
		"blocked": 0,
		"staffed_count": 0,
		"unstaffed": 0,
		"input_blocked": 0,
		"status_text": status_text,
		"input_shortages": []
	}


func _campaign_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null


func _campaign_buildings(state: Node) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_buildings_copy"):
		return runtime_state.call("get_buildings_copy") as Dictionary
	return {}


func _population_upkeep_rates(state: Node) -> Dictionary:
	# Population upkeep rates are rule/static data exposed through the runtime
	# facade, not CampaignState live/save data.
	if state != null and state.has_method("get_population_upkeep_rates_copy"):
		return state.call("get_population_upkeep_rates_copy") as Dictionary
	return {}


func _append_report_line(state: Node, line: String) -> void:
	if state != null and state.has_method("_append_report_line"):
		state.call("_append_report_line", line)
		return
	if state == null:
		return

	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("append_report_line"):
		runtime_state.call("append_report_line", line)


func _format_amount(state: Node, value: float) -> String:
	if state != null and state.has_method("_format_amount"):
		return String(state.call("_format_amount", value))
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))


func _resource_name(state: Node, resource_id: String) -> String:
	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))
	return resource_id.capitalize()
