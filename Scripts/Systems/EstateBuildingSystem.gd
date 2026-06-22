# EstateBuildingSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/EstateBuildingSystem.gd
#
# Owns estate building view rows, construction checks, construction spending and
# building destruction. Reads/writes CampaignState first through TRGameState
# bridge/accessors, with TRGameState field fallback kept only for compatibility.

class_name EstateBuildingSystem
extends RefCounted


func building_matches_focus(definition: Dictionary, focus_id: String) -> bool:
	if focus_id == "" or focus_id == "overview" or focus_id == "build":
		return true

	var category: String = String(definition.get("category", ""))
	if focus_id == category:
		return true
	if focus_id == "maize" and String(definition.get("id", "")) == "maize_chinampa":
		return true
	if focus_id == "cacao" and String(definition.get("id", "")) == "cacao_garden":
		return true
	if focus_id == "cotton" and String(definition.get("id", "")) == "cotton_chinampa":
		return true

	return false


func building_view_data(state: Node, building_id: String) -> Dictionary:
	if state == null:
		return {}

	var buildings: Dictionary = _buildings(state)
	if not buildings.has(building_id):
		return {}

	var estate_buildings: Dictionary = _estate_buildings(state)
	var definition: Dictionary = buildings[building_id] as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	var status: Dictionary = state.call("_estimate_building_status", building_id) as Dictionary
	var staff: Dictionary = definition.get("staff", {}) as Dictionary
	if bool(state.call("_is_productive_building_id", building_id)):
		staff = state.call("_production_staff_for_building", building_id) as Dictionary

	var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
	var outputs: Dictionary = definition.get("outputs", {}) as Dictionary
	var build_time: int = int(definition.get("build_time_veintenas", definition.get("build_time", 0)))

	return {
		"id": building_id,
		"name": String(definition.get("name", building_id.capitalize())),
		"screen": String(definition.get("screen", "")),
		"category": String(definition.get("category", "")),
		"description": String(definition.get("description", "")),
		"count": count,
		"staff": staff,
		"inputs": inputs,
		"outputs": outputs,
		"staff_total": _multiply_dictionary(state, staff, count),
		"staff_assigned": state.call("_assigned_staff_for_building", building_id),
		"inputs_total": _multiply_dictionary(state, inputs, int(status.get("operating", 0))),
		"outputs_total": _multiply_dictionary(state, outputs, int(status.get("operating", 0))),
		"staff_after_build": _multiply_dictionary(state, staff, count + 1),
		"inputs_after_build": _multiply_dictionary(state, inputs, count + 1),
		"outputs_after_build": _multiply_dictionary(state, outputs, count + 1),
		"staff_after_destroy": _multiply_dictionary(state, staff, max(0, count - 1)),
		"inputs_after_destroy": _multiply_dictionary(state, inputs, max(0, count - 1)),
		"outputs_after_destroy": _multiply_dictionary(state, outputs, max(0, count - 1)),
		"build_cost": definition.get("build_cost", {}) as Dictionary,
		"build_time_veintenas": build_time,
		"can_build": can_build(state, building_id),
		"build_status": build_status_text(state, building_id),
		"can_destroy": can_destroy(state, building_id),
		"destroy_status": destroy_status_text(state, building_id),
		"operating": int(status.get("operating", 0)),
		"blocked": int(status.get("blocked", 0)),
		"status_text": String(status.get("status_text", ""))
	}


func reserved_resources_for_current_turn(state: Node) -> Dictionary:
	if state == null:
		return {}

	var reserved: Dictionary = {}
	_add_dictionary_amounts(reserved, state.call("estimate_population_upkeep") as Dictionary)
	_add_dictionary_amounts(reserved, state.call("estimate_housing_maintenance") as Dictionary)
	_add_dictionary_amounts(reserved, state.call("estimate_building_inputs") as Dictionary)
	return reserved


func free_stock_after_reserves(state: Node, resource_id: String) -> float:
	var reserved: Dictionary = reserved_resources_for_current_turn(state)
	return maxf(0.0, _stock(state, resource_id) - float(reserved.get(resource_id, 0.0)))


func can_build(state: Node, building_id: String) -> bool:
	if state == null:
		return false

	var buildings: Dictionary = _buildings(state)
	if not buildings.has(building_id):
		return false

	var definition: Dictionary = buildings[building_id] as Dictionary
	var cost: Dictionary = definition.get("build_cost", {}) as Dictionary
	var reserved: Dictionary = reserved_resources_for_current_turn(state)

	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var free_after_reserves: float = maxf(0.0, _stock(state, resource_id) - float(reserved.get(resource_id, 0.0)))
		if free_after_reserves < float(cost[resource_variant]):
			return false

	return true


func build_status_text(state: Node, building_id: String) -> String:
	if state == null:
		return "Building state is not connected."

	var buildings: Dictionary = _buildings(state)
	if not buildings.has(building_id):
		return "Unknown building."

	var definition: Dictionary = buildings[building_id] as Dictionary
	var cost: Dictionary = definition.get("build_cost", {}) as Dictionary
	var reserved: Dictionary = reserved_resources_for_current_turn(state)
	var missing: Array[String] = []

	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(cost[resource_variant])
		var stored: float = _stock(state, resource_id)
		var reserved_amount: float = float(reserved.get(resource_id, 0.0))
		var free_after_reserves: float = maxf(0.0, stored - reserved_amount)
		if free_after_reserves < needed:
			var shortfall: float = needed - free_after_reserves
			var part: String = _resource_name(state, resource_id) + " " + _format_amount(state, shortfall)
			if reserved_amount > 0.0:
				part += " after reserves"
			missing.append(part)

	if missing.is_empty():
		return "Buildable now using free stock after reserves."
	return "Missing: " + ", ".join(missing)


func build_building(state: Node, building_id: String) -> bool:
	if state == null:
		return false

	var buildings: Dictionary = _buildings(state)
	if not buildings.has(building_id):
		_emit_signal_if_present(state, "build_failed", [building_id, "Unknown building."])
		return false

	if not can_build(state, building_id):
		var reason: String = build_status_text(state, building_id)
		_append_report_line(state, _building_name(state, building_id) + " not built. " + reason)
		_emit_signal_if_present(state, "build_failed", [building_id, reason])
		_emit_state_changed_and_sync(state)
		return false

	var definition: Dictionary = buildings[building_id] as Dictionary
	var cost: Dictionary = definition.get("build_cost", {}) as Dictionary
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(state, resource_id, -float(cost[resource_variant]))

	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state == null:
		return false

	var previous_count: int = int(_estate_buildings(state).get(building_id, 0))
	if runtime_state.has_method("get_estate_building_count"):
		previous_count = int(runtime_state.call("get_estate_building_count", building_id))

	var previous_staffed: int = int(state.call("_staffed_count_for_building", building_id))
	if runtime_state.has_method("set_estate_building_count"):
		runtime_state.call("set_estate_building_count", building_id, previous_count + 1)

	if bool(state.call("_is_housing_building_id", building_id)):
		state.call("_ensure_active_housing_counts")
		var active_housing_counts: Dictionary = _active_housing_counts(state)
		if runtime_state.has_method("set_active_housing_count_value"):
			runtime_state.call("set_active_housing_count_value", building_id, int(active_housing_counts.get(building_id, previous_count)) + 1)

	if bool(state.call("_is_productive_building_id", building_id)) and previous_staffed >= previous_count:
		state.call("_auto_staff_single_building_to_max", building_id)
	else:
		state.call("_ensure_labour_assignments")

	_append_report_line(state, "Built " + _building_name(state, building_id) + ".")
	_emit_signal_if_present(state, "build_completed", [building_id])
	_emit_state_changed_and_sync(state)
	return true


func can_destroy(state: Node, building_id: String) -> bool:
	if state == null:
		return false

	var buildings: Dictionary = _buildings(state)
	var estate_buildings: Dictionary = _estate_buildings(state)
	if not buildings.has(building_id):
		return false
	if int(estate_buildings.get(building_id, 0)) <= 0:
		return false

	if bool(state.call("_is_housing_building_id", building_id)):
		var overcrowd: Dictionary = state.call("_would_destroy_overcrowd", building_id) as Dictionary
		return not bool(overcrowd.get("blocked", false))

	return true


func destroy_status_text(state: Node, building_id: String) -> String:
	if state == null:
		return "Building state is not connected."

	var buildings: Dictionary = _buildings(state)
	var estate_buildings: Dictionary = _estate_buildings(state)
	if not buildings.has(building_id):
		return "Unknown building."
	if int(estate_buildings.get(building_id, 0)) <= 0:
		return "None built."

	if bool(state.call("_is_housing_building_id", building_id)):
		var overcrowd: Dictionary = state.call("_would_destroy_overcrowd", building_id) as Dictionary
		if bool(overcrowd.get("blocked", false)):
			var lines: Array = overcrowd.get("lines", []) as Array
			return "Cannot destroy: would overcrowd " + ", ".join(lines) + "."
		return "Can destroy one. No refund in this prototype."

	if can_destroy(state, building_id):
		return "Can destroy one. No refund in this prototype."
	return "None built."


func destroy_building(state: Node, building_id: String) -> bool:
	if state == null:
		return false

	var buildings: Dictionary = _buildings(state)
	if not buildings.has(building_id):
		_emit_signal_if_present(state, "destroy_failed", [building_id, "Unknown building."])
		return false

	if not can_destroy(state, building_id):
		var reason: String = destroy_status_text(state, building_id)
		_append_report_line(state, _building_name(state, building_id) + " not destroyed. " + reason)
		_emit_signal_if_present(state, "destroy_failed", [building_id, reason])
		_emit_state_changed_and_sync(state)
		return false

	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state == null:
		return false

	var before_destroy_count: int = int(_estate_buildings(state).get(building_id, 0))
	if runtime_state.has_method("get_estate_building_count"):
		before_destroy_count = int(runtime_state.call("get_estate_building_count", building_id))
	if runtime_state.has_method("set_estate_building_count"):
		runtime_state.call("set_estate_building_count", building_id, max(0, before_destroy_count - 1))

	if bool(state.call("_is_housing_building_id", building_id)):
		state.call("_ensure_active_housing_counts")
		var active_housing_counts: Dictionary = _active_housing_counts(state)
		var estate_buildings: Dictionary = _estate_buildings(state)
		if runtime_state.has_method("set_active_housing_count_value"):
			runtime_state.call("set_active_housing_count_value", building_id, mini(int(active_housing_counts.get(building_id, 0)), int(estate_buildings.get(building_id, 0))))

	state.call("_ensure_labour_assignments")
	_append_report_line(state, "Destroyed one " + _building_name(state, building_id) + ". No refund given.")
	_emit_signal_if_present(state, "destroy_completed", [building_id])
	_emit_state_changed_and_sync(state)
	return true


# -----------------------------------------------------------------------------
# CampaignState-first accessors
# -----------------------------------------------------------------------------

func _campaign_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null

func _campaign_stockpile_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null

func _dictionary_from_campaign_state(state: Node, key: String) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state == null:
		return {}
	match key:
		"buildings":
			if runtime_state.has_method("get_buildings_copy"):
				return runtime_state.call("get_buildings_copy") as Dictionary
		"estate_buildings":
			if runtime_state.has_method("get_estate_buildings_copy"):
				return runtime_state.call("get_estate_buildings_copy") as Dictionary
		"active_housing_counts":
			if runtime_state.has_method("get_active_housing_counts_copy"):
				return runtime_state.call("get_active_housing_counts_copy") as Dictionary
	return {}

func _buildings(state: Node) -> Dictionary:
	return _dictionary_from_campaign_state(state, "buildings")


func _estate_buildings(state: Node) -> Dictionary:
	return _dictionary_from_campaign_state(state, "estate_buildings")


func _active_housing_counts(state: Node) -> Dictionary:
	return _dictionary_from_campaign_state(state, "active_housing_counts")


func _stock(state: Node, resource_id: String) -> float:
	var runtime_state: RefCounted = _campaign_stockpile_state(state)
	if runtime_state != null and runtime_state.has_method("get_estate_stock"):
		return float(runtime_state.call("get_estate_stock", resource_id))
	return 0.0


func _add_stock(state: Node, resource_id: String, delta: float) -> void:
	var runtime_state: RefCounted = _campaign_stockpile_state(state)
	if runtime_state != null and runtime_state.has_method("add_estate_stock"):
		runtime_state.call("add_estate_stock", resource_id, delta)
		return



func _multiply_dictionary(state: Node, values: Dictionary, multiplier: int) -> Dictionary:
	if state != null and state.has_method("_multiply_dictionary"):
		return state.call("_multiply_dictionary", values, multiplier) as Dictionary

	var output: Dictionary = {}
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		output[key] = float(values[key_variant]) * float(multiplier)
	return output


func _resource_name(state: Node, resource_id: String) -> String:
	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))
	return resource_id.capitalize()


func _building_name(state: Node, building_id: String) -> String:
	if state != null and state.has_method("get_building_name"):
		return String(state.call("get_building_name", building_id))
	return building_id.capitalize()


func _format_amount(state: Node, value: float) -> String:
	if state != null and state.has_method("_format_amount"):
		return String(state.call("_format_amount", value))
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))


func _append_report_line(state: Node, line: String) -> void:
	if state != null and state.has_method("_append_report_line"):
		state.call("_append_report_line", line)


func _emit_state_changed_and_sync(state: Node) -> void:
	if state != null and state.has_method("_emit_state_changed_and_sync"):
		state.call("_emit_state_changed_and_sync")


func _add_dictionary_amounts(target: Dictionary, source: Dictionary) -> void:
	for resource_variant: Variant in source.keys():
		var resource_id: String = String(resource_variant)
		target[resource_id] = float(target.get(resource_id, 0.0)) + float(source[resource_variant])


func _emit_signal_if_present(state: Node, signal_name: String, args: Array = []) -> void:
	if state == null or not state.has_signal(signal_name):
		return

	match args.size():
		0:
			state.emit_signal(signal_name)
		1:
			state.emit_signal(signal_name, args[0])
		2:
			state.emit_signal(signal_name, args[0], args[1])
		3:
			state.emit_signal(signal_name, args[0], args[1], args[2])
		_:
			state.emit_signal(signal_name)
