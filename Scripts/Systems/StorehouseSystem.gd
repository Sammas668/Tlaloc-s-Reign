# StorehouseSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/StorehouseSystem.gd
#
# Owns Storehouse goods row construction and reserve/pressure presentation logic.
# Reads CampaignState first through TRGameState accessors, with TRGameState
# field fallback kept only for compatibility.

class_name StorehouseSystem
extends RefCounted


func get_storehouse_goods(state: Node) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if state == null:
		return output

	var incoming: Dictionary = {}
	if state.has_method("estimate_building_outputs"):
		incoming = state.call("estimate_building_outputs") as Dictionary

	var building_inputs: Dictionary = {}
	if state.has_method("estimate_building_inputs"):
		building_inputs = state.call("estimate_building_inputs") as Dictionary

	var housing_maintenance: Dictionary = {}
	if state.has_method("estimate_housing_maintenance"):
		housing_maintenance = state.call("estimate_housing_maintenance") as Dictionary

	var upkeep: Dictionary = {}
	if state.has_method("estimate_population_upkeep"):
		upkeep = state.call("estimate_population_upkeep") as Dictionary

	var resource_order: Array[String] = _campaign_string_array(state, "resource_order")
	var resources: Dictionary = _campaign_dictionary(state, "resources")
	if resource_order.is_empty() or resources.is_empty():
		return output

	for resource_variant: Variant in resource_order:
		var resource_id: String = String(resource_variant)
		if not resources.has(resource_id):
			continue

		var resource_data: Dictionary = resources[resource_id] as Dictionary
		var stored: float = _stock_value(state, resource_id)
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
			"pressure": pressure_label(stored, outgoing),
			"uses": resource_data.get("uses", []) as Array,
			"reserved_breakdown": reserve_breakdown(state, resource_id, upkeep_value, input_value, housing_value)
		})

	return output


func reserve_breakdown(state: Node, resource_id: String, upkeep_value: float, input_value: float, housing_value: float = 0.0) -> Array[String]:
	var lines: Array[String] = []
	if upkeep_value > 0.0:
		lines.append("Population upkeep: " + _format_amount(state, upkeep_value))
	if input_value > 0.0:
		lines.append("Production inputs: " + _format_amount(state, input_value))
	if housing_value > 0.0:
		lines.append("Housing maintenance: " + _format_amount(state, housing_value))
	if lines.is_empty():
		lines.append("No current reserve.")
	return lines


func pressure_label(stored: float, outgoing: float) -> String:
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


func _campaign_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null

func _campaign_dictionary(state: Node, key: String) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		match key:
			"estate_stockpiles":
				if runtime_state.has_method("get_estate_stockpiles_copy"):
					return runtime_state.call("get_estate_stockpiles_copy") as Dictionary
			_:
				var runtime_value: Variant = runtime_state.get(key)
				if runtime_value is Dictionary:
					return (runtime_value as Dictionary).duplicate(true)

	if state != null:
		var fallback: Variant = state.get(key)
		if fallback is Dictionary:
			return (fallback as Dictionary).duplicate(true)

	return {}


func _campaign_string_array(state: Node, key: String) -> Array[String]:
	var output: Array[String] = []
	var runtime_state: RefCounted = _campaign_state(state)
	var raw_value: Variant = null

	if runtime_state != null:
		raw_value = runtime_state.get(key)
	if raw_value == null and state != null:
		raw_value = state.get(key)

	if raw_value is Array:
		for item: Variant in raw_value as Array:
			output.append(String(item))

	return output


func _stock_value(state: Node, resource_id: String) -> float:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_estate_stock"):
		return float(runtime_state.call("get_estate_stock", resource_id))

	if state != null and state.has_method("_stock"):
		return float(state.call("_stock", resource_id))

	var stockpiles: Dictionary = _campaign_dictionary(state, "estate_stockpiles")
	return float(stockpiles.get(resource_id, 0.0))


func _format_amount(state: Node, value: float) -> String:
	if state != null and state.has_method("_format_amount"):
		return String(state.call("_format_amount", value))
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))
