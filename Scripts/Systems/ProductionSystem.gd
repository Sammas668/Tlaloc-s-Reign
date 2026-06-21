# ProductionSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/ProductionSystem.gd
#
# Owns production resolution and production operation rules.
# CampaignState is the live/save-state owner. TRGameState remains the public
# facade and compatibility API while systems migrate toward CampaignState-first
# reads and writes.
class_name ProductionSystem
extends RefCounted

func estimate_production_resolution(state: Node) -> Dictionary:
	if state == null:
		return _empty_resolution()
	_call_if_present(state, "_ensure_labour_assignments")
	var temp_stockpile: Dictionary = _copy_float_dictionary(_estate_stockpiles_copy(state))
	var upkeep_needed: Dictionary = _call_dictionary(state, "estimate_population_upkeep")
	var maintenance_needed: Dictionary = _call_dictionary(state, "estimate_housing_maintenance")
	var upkeep_paid: Dictionary = {}
	var upkeep_shortfalls: Dictionary = {}
	var maintenance_paid: Dictionary = {}
	var maintenance_shortfalls: Dictionary = {}

	_apply_cost_dictionary_to_stockpile(upkeep_needed, temp_stockpile, upkeep_paid, upkeep_shortfalls)
	_apply_cost_dictionary_to_stockpile(maintenance_needed, temp_stockpile, maintenance_paid, maintenance_shortfalls)

	var total_inputs: Dictionary = {}
	var total_outputs: Dictionary = {}
	var building_statuses: Dictionary = {}
	var report_lines: Array[String] = []
	var building_order: Array[String] = _building_order_copy(state)
	var buildings: Dictionary = _buildings_copy(state)
	var estate_buildings: Dictionary = _estate_buildings_copy(state)

	for building_id: String in building_order:
		if not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			building_statuses[building_id] = _not_built_status()
			continue

		var staffed_count: int = count
		if _is_productive_building_id(state, building_id):
			staffed_count = _staffed_count_for_building(state, building_id)
		staffed_count = clampi(staffed_count, 0, count)

		var operated: int = 0
		var input_blocked: int = 0
		var input_shortages: Array[String] = []

		for index: int in range(staffed_count):
			var reason: String = _can_operate_instance_with_stockpile(state, definition, temp_stockpile)
			if reason == "":
				var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
				var outputs: Dictionary = definition.get("outputs", {}) as Dictionary
				_consume_inputs_from_stockpile(inputs, temp_stockpile)
				_add_outputs_to_stockpile(outputs, temp_stockpile)
				_add_dictionary_amounts(total_inputs, inputs)
				_add_dictionary_amounts(total_outputs, outputs)
				operated += 1
			else:
				input_blocked += 1
				if not input_shortages.has(reason):
					input_shortages.append(reason)

		var unstaffed: int = max(0, count - staffed_count)
		var blocked: int = input_blocked + unstaffed
		var status_text: String = "Staffed " + str(staffed_count) + " / " + str(count) + "; operating " + str(operated) + " / " + str(staffed_count) + " staffed"
		if unstaffed > 0:
			status_text += "; unstaffed " + str(unstaffed)
		if input_blocked > 0:
			status_text += "; input blocked " + str(input_blocked)
		if not input_shortages.is_empty():
			status_text += "; " + "; ".join(input_shortages)

		building_statuses[building_id] = {
			"operating": operated,
			"blocked": blocked,
			"staffed_count": staffed_count,
			"unstaffed": unstaffed,
			"input_blocked": input_blocked,
			"status_text": status_text,
			"input_shortages": input_shortages.duplicate()
		}

		var display_name: String = String(definition.get("name", building_id))
		if operated > 0:
			report_lines.append(display_name + " would operate x" + str(operated) + ".")
		if input_blocked > 0:
			report_lines.append(display_name + " would be input-blocked x" + str(input_blocked) + ".")
		if _is_productive_building_id(state, building_id) and unstaffed > 0:
			report_lines.append(display_name + " would be unstaffed x" + str(unstaffed) + ".")

	return {
		"inputs": total_inputs,
		"outputs": total_outputs,
		"building_statuses": building_statuses,
		"stockpile_after_upkeep_and_production": temp_stockpile,
		"upkeep_needed": upkeep_needed,
		"upkeep_paid": upkeep_paid,
		"upkeep_shortfalls": upkeep_shortfalls,
		"housing_maintenance_needed": maintenance_needed,
		"housing_maintenance_paid": maintenance_paid,
		"housing_maintenance_shortfalls": maintenance_shortfalls,
		"reports": report_lines
	}

func operate_buildings(state: Node) -> Array[String]:
	var reports: Array[String] = []
	if state == null:
		return reports
	_call_if_present(state, "_ensure_labour_assignments")
	var building_order: Array[String] = _building_order_copy(state)
	var buildings: Dictionary = _buildings_copy(state)
	var estate_buildings: Dictionary = _estate_buildings_copy(state)

	for building_id: String in building_order:
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0 or not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var target_count: int = count
		if _is_productive_building_id(state, building_id):
			target_count = _staffed_count_for_building(state, building_id)
		var operated: int = 0
		var blocked: int = 0
		for index: int in range(target_count):
			var reason: String = _can_operate_instance(state, definition)
			if reason == "":
				_consume_inputs(state, definition.get("inputs", {}) as Dictionary)
				_add_outputs(state, definition.get("outputs", {}) as Dictionary)
				operated += 1
			else:
				blocked += 1
				reports.append(String(definition.get("name", building_id)) + " blocked: " + reason)
		if operated > 0:
			reports.append(String(definition.get("name", building_id)) + " operated x" + str(operated) + ".")
		if _is_productive_building_id(state, building_id) and target_count < count:
			reports.append(String(definition.get("name", building_id)) + " unstaffed x" + str(count - target_count) + ".")
	_mirror_stockpiles_to_legacy(state)
	return reports

func _empty_resolution() -> Dictionary:
	return {
		"inputs": {},
		"outputs": {},
		"building_statuses": {},
		"stockpile_after_upkeep_and_production": {},
		"upkeep_needed": {},
		"upkeep_paid": {},
		"upkeep_shortfalls": {},
		"housing_maintenance_needed": {},
		"housing_maintenance_paid": {},
		"housing_maintenance_shortfalls": {},
		"reports": []
	}

func _not_built_status() -> Dictionary:
	return {
		"operating": 0,
		"blocked": 0,
		"staffed_count": 0,
		"unstaffed": 0,
		"input_blocked": 0,
		"status_text": "Not built.",
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

func _campaign_dictionary(state: Node, key: String) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		match key:
			"estate_stockpiles":
				if runtime_state.has_method("get_estate_stockpiles_copy"):
					return runtime_state.call("get_estate_stockpiles_copy") as Dictionary
			"buildings":
				var buildings_value: Variant = runtime_state.get("buildings")
				if buildings_value is Dictionary:
					return (buildings_value as Dictionary).duplicate(true)
			"estate_buildings":
				if runtime_state.has_method("get_estate_buildings_copy"):
					return runtime_state.call("get_estate_buildings_copy") as Dictionary
				var estate_value: Variant = runtime_state.get("estate_buildings")
				if estate_value is Dictionary:
					return (estate_value as Dictionary).duplicate(true)
			_:
				var generic_value: Variant = runtime_state.get(key)
				if generic_value is Dictionary:
					return (generic_value as Dictionary).duplicate(true)
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
	if raw_value == null:
		raw_value = state.get(key)
	if raw_value is Array:
		for item: Variant in raw_value as Array:
			output.append(String(item))
	return output

func _estate_stockpiles_copy(state: Node) -> Dictionary:
	return _campaign_dictionary(state, "estate_stockpiles")

func _buildings_copy(state: Node) -> Dictionary:
	return _campaign_dictionary(state, "buildings")

func _estate_buildings_copy(state: Node) -> Dictionary:
	return _campaign_dictionary(state, "estate_buildings")

func _building_order_copy(state: Node) -> Array[String]:
	return _campaign_string_array(state, "building_order")

func _call_if_present(state: Node, method_name: String) -> void:
	if state != null and state.has_method(method_name):
		state.call(method_name)

func _call_dictionary(state: Node, method_name: String) -> Dictionary:
	if state != null and state.has_method(method_name):
		var result: Variant = state.call(method_name)
		if result is Dictionary:
			return (result as Dictionary).duplicate(true)
	return {}

func _is_productive_building_id(state: Node, building_id: String) -> bool:
	if state != null and state.has_method("_is_productive_building_id"):
		return bool(state.call("_is_productive_building_id", building_id))
	var buildings: Dictionary = _buildings_copy(state)
	if not buildings.has(building_id):
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	var screen_id: String = String(definition.get("screen", ""))
	return screen_id == "chinampas" or screen_id == "workshops"

func _staffed_count_for_building(state: Node, building_id: String) -> int:
	if state != null and state.has_method("_staffed_count_for_building"):
		return int(state.call("_staffed_count_for_building", building_id))
	var estate_buildings: Dictionary = _estate_buildings_copy(state)
	return int(estate_buildings.get(building_id, 0))

func _resource_name(state: Node, resource_id: String) -> String:
	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))
	return resource_id.replace("_", " ").capitalize()

func _copy_float_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = float(source[key_variant])
	return output

func _apply_cost_dictionary_to_stockpile(costs: Dictionary, stockpile: Dictionary, paid_out: Dictionary, shortfalls_out: Dictionary) -> void:
	for resource_variant: Variant in costs.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(costs[resource_variant])
		var available: float = float(stockpile.get(resource_id, 0.0))
		var paid: float = minf(available, needed)
		stockpile[resource_id] = available - paid
		paid_out[resource_id] = paid
		if paid < needed:
			shortfalls_out[resource_id] = needed - paid

func _can_operate_instance_with_stockpile(state: Node, definition: Dictionary, temp_stockpile: Dictionary) -> String:
	var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(inputs[resource_variant])
		if float(temp_stockpile.get(resource_id, 0.0)) < needed:
			return "not enough " + _resource_name(state, resource_id) + " input"
	return ""

func _consume_inputs_from_stockpile(inputs: Dictionary, temp_stockpile: Dictionary) -> void:
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		temp_stockpile[resource_id] = float(temp_stockpile.get(resource_id, 0.0)) - float(inputs[resource_variant])

func _add_outputs_to_stockpile(outputs: Dictionary, temp_stockpile: Dictionary) -> void:
	for resource_variant: Variant in outputs.keys():
		var resource_id: String = String(resource_variant)
		temp_stockpile[resource_id] = float(temp_stockpile.get(resource_id, 0.0)) + float(outputs[resource_variant])

func _add_dictionary_amounts(target: Dictionary, amounts: Dictionary) -> void:
	for resource_variant: Variant in amounts.keys():
		var resource_id: String = String(resource_variant)
		target[resource_id] = float(target.get(resource_id, 0.0)) + float(amounts[resource_variant])

func _can_operate_instance(state: Node, definition: Dictionary) -> String:
	var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		if _stock(state, resource_id) < float(inputs[resource_variant]):
			return "not enough " + _resource_name(state, resource_id) + " input"
	return ""

func _stock(state: Node, resource_id: String) -> float:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_estate_stock"):
		return float(runtime_state.call("get_estate_stock", resource_id))
	if state != null and state.has_method("_stock"):
		return float(state.call("_stock", resource_id))
	var stockpiles: Dictionary = _estate_stockpiles_copy(state)
	return float(stockpiles.get(resource_id, 0.0))

func _add_stock(state: Node, resource_id: String, amount: float) -> void:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("add_estate_stock"):
		runtime_state.call("add_estate_stock", resource_id, amount)
		_mirror_stockpiles_to_legacy(state)
		return
	if state != null and state.has_method("_add_stock"):
		state.call("_add_stock", resource_id, amount)
		return
	var stockpiles: Dictionary = _estate_stockpiles_copy(state)
	stockpiles[resource_id] = maxf(0.0, float(stockpiles.get(resource_id, 0.0)) + amount)
	if state != null:
		state.set("estate_stockpiles", stockpiles)

func _mirror_stockpiles_to_legacy(state: Node) -> void:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("mirror_stockpiles_to_game_state"):
		runtime_state.call("mirror_stockpiles_to_game_state", state)
		return
	if state != null and state.has_method("_mirror_stockpile_compatibility_from_campaign_state"):
		state.call("_mirror_stockpile_compatibility_from_campaign_state")

func _consume_inputs(state: Node, inputs: Dictionary) -> void:
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(state, resource_id, -float(inputs[resource_variant]))

func _add_outputs(state: Node, outputs: Dictionary) -> void:
	for resource_variant: Variant in outputs.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(state, resource_id, float(outputs[resource_variant]))
