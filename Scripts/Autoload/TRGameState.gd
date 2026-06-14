# TRGameState.gd
# Godot 4.x
# Suggested autoload name: TRGameState
# Project path: res://Scripts/autoload/TRGameState.gd
extends Node

signal state_changed
signal turn_advanced(report: Array)
signal build_completed(building_id: String)
signal build_failed(building_id: String, reason: String)
signal destroy_completed(building_id: String)
signal destroy_failed(building_id: String, reason: String)

const RESOURCE_DATA_PATH: String = "res://Data/Prototype0/resources.json"
const BUILDING_DATA_PATH: String = "res://Data/Prototype0/buildings.json"
const START_STATE_PATH: String = "res://Data/Prototype0/start_state.json"

var resources: Dictionary = {}
var resource_order: Array[String] = []
var buildings: Dictionary = {}
var building_order: Array[String] = []

var estate_stockpiles: Dictionary = {}
var market_stockpiles: Dictionary = {}
var market_demand: Dictionary = {}
var estate_buildings: Dictionary = {}
var population: Dictionary = {}
var labour_assignments: Dictionary = {}

var current_veintena: int = 1
var last_report: Array[String] = []
var initialized: bool = false

var population_upkeep_rates: Dictionary = {
	"macehualtin": {"maize": 1.0, "cotton": 0.05, "cloth": 0.2, "tools": 0.1},
	"tlacotin": {"maize": 0.5, "cotton": 0.025, "cloth": 0.1, "tools": 0.05},
	"tolteca": {"maize": 1.0, "cotton": 0.1, "cloth": 0.3, "tools": 0.25},
	"yaotequihuaqueh": {"maize": 1.25, "cloth": 0.3, "tools": 0.1, "weapons": 0.2, "cacao": 0.05},
	"tlamacazqueh": {"maize": 1.0, "cloth": 0.2, "ritual_goods": 0.2, "cacao": 0.1},
	"pipiltin": {"maize": 1.0, "cloth": 0.4, "ritual_goods": 0.1, "cacao": 0.3, "fine_textiles": 0.2},
	"malli": {"maize": 0.5}
}

func _ready() -> void:
	if not initialized:
		new_game()

func new_game() -> void:
	_load_resource_definitions()
	_load_building_definitions()
	_load_start_state()
	initialized = true
	last_report.clear()
	last_report.append("New estate simulation started.")
	emit_signal("state_changed")

func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Missing data file: " + path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open data file: " + path)
		return {}
	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		return parsed as Dictionary
	push_warning("Data file did not parse as Dictionary: " + path)
	return {}

func _load_resource_definitions() -> void:
	resources.clear()
	resource_order.clear()
	var data: Dictionary = _load_json_dictionary(RESOURCE_DATA_PATH)
	var rows: Array = data.get("resources", []) as Array
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant as Dictionary
		var resource_id: String = String(row.get("id", ""))
		if resource_id == "":
			continue
		resources[resource_id] = row
		resource_order.append(resource_id)

func _load_building_definitions() -> void:
	buildings.clear()
	building_order.clear()
	var data: Dictionary = _load_json_dictionary(BUILDING_DATA_PATH)
	var rows: Array = data.get("buildings", []) as Array
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant as Dictionary
		var building_id: String = String(row.get("id", ""))
		if building_id == "":
			continue
		buildings[building_id] = row
		building_order.append(building_id)
	building_order.sort_custom(func(a: String, b: String) -> bool:
		var a_data: Dictionary = buildings[a] as Dictionary
		var b_data: Dictionary = buildings[b] as Dictionary
		return int(a_data.get("priority", 999)) < int(b_data.get("priority", 999))
	)

func _load_start_state() -> void:
	var data: Dictionary = _load_json_dictionary(START_STATE_PATH)
	current_veintena = int(data.get("current_veintena", 1))
	estate_stockpiles = _float_dictionary(data.get("estate_stockpiles", {}) as Dictionary)
	market_stockpiles = _float_dictionary(data.get("market_stockpiles", {}) as Dictionary)
	market_demand = _float_dictionary(data.get("market_demand", {}) as Dictionary)
	estate_buildings = _int_dictionary(data.get("estate_buildings", {}) as Dictionary)
	population = _int_dictionary(data.get("population", {}) as Dictionary)
	labour_assignments = _nested_int_dictionary(data.get("labour_assignments", {}) as Dictionary)
	_ensure_all_resource_keys()
	_ensure_all_building_keys()
	# New-game start states should not begin with productive buildings idle just
	# because a previous patch or save file left empty labour assignment entries.
	# Default setup staffs production automatically in priority order, with maize
	# protected first, then other production buildings until population runs out.
	_auto_staff_all_productive_buildings()

func _float_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = float(source[key])
	return output

func _int_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = int(source[key])
	return output

func _nested_int_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		var value: Variant = source[key_variant]
		if value is Dictionary:
			output[key] = _int_dictionary(value as Dictionary)
	return output

func _ensure_all_resource_keys() -> void:
	for resource_id: String in resource_order:
		if not estate_stockpiles.has(resource_id):
			estate_stockpiles[resource_id] = 0.0
		if not market_stockpiles.has(resource_id):
			market_stockpiles[resource_id] = 0.0
		if not market_demand.has(resource_id):
			market_demand[resource_id] = 0.0

func _ensure_all_building_keys() -> void:
	for building_id: String in building_order:
		if not estate_buildings.has(building_id):
			estate_buildings[building_id] = 0

func get_current_veintena() -> int:
	return current_veintena

func get_last_report() -> Array[String]:
	var output: Array[String] = []
	for line_variant: Variant in last_report:
		output.append(String(line_variant))
	return output

func get_resource_name(resource_id: String) -> String:
	if resources.has(resource_id):
		var data: Dictionary = resources[resource_id] as Dictionary
		return String(data.get("name", resource_id.capitalize()))
	return resource_id.capitalize()

func get_building_name(building_id: String) -> String:
	if buildings.has(building_id):
		var data: Dictionary = buildings[building_id] as Dictionary
		return String(data.get("name", building_id.capitalize()))
	return building_id.capitalize()

func get_storehouse_goods() -> Array[Dictionary]:
	var incoming: Dictionary = estimate_building_outputs()
	var building_inputs: Dictionary = estimate_building_inputs()
	var upkeep: Dictionary = estimate_population_upkeep()
	var output: Array[Dictionary] = []
	for resource_id: String in resource_order:
		var resource_data: Dictionary = resources[resource_id] as Dictionary
		var stored: float = _stock(resource_id)
		var in_value: float = float(incoming.get(resource_id, 0.0))
		var upkeep_value: float = float(upkeep.get(resource_id, 0.0))
		var input_value: float = float(building_inputs.get(resource_id, 0.0))
		var outgoing: float = upkeep_value + input_value
		var reserved: float = outgoing
		var free_value: float = maxf(0.0, stored - reserved)
		var good: Dictionary = {
			"id": resource_id,
			"name": String(resource_data.get("name", resource_id.capitalize())),
			"category": String(resource_data.get("category", "raw")),
			"stored": stored,
			"incoming": in_value,
			"outgoing": outgoing,
			"reserved": reserved,
			"free": free_value,
			"net": in_value - outgoing,
			"pressure": _pressure_label(stored, outgoing),
			"uses": resource_data.get("uses", []) as Array,
			"reserved_breakdown": _reserve_breakdown(resource_id, upkeep_value, input_value)
		}
		output.append(good)
	return output

func get_market_goods() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for resource_id: String in resource_order:
		var resource_data: Dictionary = resources[resource_id] as Dictionary
		var stock_value: float = float(market_stockpiles.get(resource_id, 0.0))
		var demand_value: float = maxf(0.0, float(market_demand.get(resource_id, 0.0)))
		var coverage: float = 0.0
		if demand_value > 0.0:
			coverage = stock_value / demand_value
		var multiplier: float = _scarcity_multiplier(coverage, demand_value)
		var base_value: float = float(resource_data.get("base_value", 1.0))
		var current_value: float = base_value * multiplier
		var good: Dictionary = {
			"id": resource_id,
			"name": String(resource_data.get("name", resource_id.capitalize())),
			"category": String(resource_data.get("category", "raw")),
			"market_stock": stock_value,
			"demand": demand_value,
			"base_value": base_value,
			"current_value": current_value,
			"coverage": coverage,
			"label": _market_label(coverage, demand_value),
			"trend": _market_trend(coverage, demand_value),
			"buy_note": "Buy when estate free stock is low or a build needs this good.",
			"sell_note": "Sell only true surplus after upkeep, input and build reserves are protected.",
			"rival_note": _rival_market_note(resource_id)
		}
		output.append(good)
	return output

func get_buildings_for_screen(screen_id: String, focus_id: String = "overview") -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for building_id: String in building_order:
		var definition: Dictionary = buildings[building_id] as Dictionary
		if String(definition.get("screen", "")) != screen_id:
			continue
		if not _building_matches_focus(definition, focus_id):
			continue
		output.append(_building_view_data(building_id))
	return output

func get_productive_labour_rows() -> Array[Dictionary]:
	_ensure_labour_assignments()
	var required: Dictionary = _productive_labour_required()
	var assigned_by_group: Dictionary = _assigned_labour_by_group()
	var rows: Array[Dictionary] = []
	for group_id: String in _productive_labour_group_ids():
		var total: int = int(population.get(group_id, 0))
		var assigned_value: int = int(assigned_by_group.get(group_id, 0))
		var required_value: int = int(required.get(group_id, assigned_value))
		var free: int = max(0, total - assigned_value)
		var short: int = max(0, assigned_value - total)
		var pressure: String = "Available"
		if total <= 0:
			pressure = "Absent"
		elif assigned_value > total:
			pressure = "Overstretched"
		elif free == 0 and total > 0:
			pressure = "Fully assigned"
		elif assigned_value >= int(total * 0.75):
			pressure = "Tight"
		rows.append({
			"id": "labour_" + group_id,
			"name": _labour_group_name(group_id),
			"screen": "production",
			"category": "labour",
			"is_labour": true,
			"description": _labour_group_description(group_id),
			"count": total,
			"staff": {
				"total_population": total,
				"required_by_staffed_production": required_value,
				"assigned_to_production": assigned_value,
				"free_or_background_labour": free,
				"shortfall": short
			},
			"inputs": {},
			"outputs": {},
			"build_cost": {},
			"can_build": false,
			"build_status": "Use the Labour tab to choose which built productive buildings are staffed.",
			"operating": assigned_value,
			"blocked": short,
			"status_text": pressure + ": assigned " + str(assigned_value) + " / total " + str(total) + "; unassigned " + str(free) + "."
		})
	return rows

func get_labour_assignment_data() -> Dictionary:
	_ensure_labour_assignments()
	var assigned_by_group: Dictionary = _assigned_labour_by_group()
	var required_by_group: Dictionary = _productive_labour_required()
	var groups: Array[Dictionary] = []

	# Player-facing labour buttons are deliberately simpler than the underlying
	# population groups. Macehualtin and Tlacotin both staff the same productive
	# field/chinampa buildings, so the UI presents them as one Field Labour pool
	# while still showing the two population groups underneath. Tolteca remain
	# separate because they operate workshops.
	groups.append(_combined_labour_assignment_group_data(
		"field_labour",
		"Field Labour",
		"Macehualtin and Tlacotin can both staff chinampas and raw production buildings. The slider assigns staffed building copies from their combined pool.",
		_field_labour_group_ids(),
		assigned_by_group,
		required_by_group
	))
	groups.append(_single_labour_assignment_group_data("tolteca", assigned_by_group, required_by_group))

	var building_rows: Array[Dictionary] = []
	for building_id: String in building_order:
		if not _is_productive_building_id(building_id):
			continue
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var staff_by_group: Dictionary = _production_staff_for_building(building_id)
		if staff_by_group.is_empty():
			continue
		var assignments: Dictionary = _staff_assignments_for_building(building_id)
		var max_by_group: Dictionary = {}
		for group_variant: Variant in staff_by_group.keys():
			var group_id: String = String(group_variant)
			max_by_group[group_id] = _max_staffable_count_for_building_group(building_id, group_id)
		if _building_can_use_field_labour(building_id):
			max_by_group["field_labour"] = _max_staffable_count_for_field_labour(building_id)
		var staffed_count: int = _staffed_count_for_building(building_id)
		var status: Dictionary = _estimate_building_status(building_id)
		var operating: int = int(status.get("operating", 0))
		building_rows.append({
			"id": building_id,
			"name": String(definition.get("name", building_id.capitalize())),
			"count": count,
			"staffed_count": staffed_count,
			"staff_assignments": assignments,
			"allowed_worker_groups": _allowed_worker_groups_for_building(building_id),
			"staff_per_instance_by_group": staff_by_group,
			"max_staffable_by_group": max_by_group,
			"max_staffable": _max_staffable_count_for_building(building_id),
			"staff_population_by_group": _staff_population_by_building(building_id),
			"operating": operating,
			"blocked": int(status.get("blocked", 0)),
			"unstaffed": int(status.get("unstaffed", 0)),
			"status_text": String(status.get("status_text", "")),
			"staff_per_instance": staff_by_group,
			"staff_at_staffed": _assigned_staff_for_building(building_id),
			"inputs_per_instance": definition.get("inputs", {}) as Dictionary,
			"outputs_per_instance": definition.get("outputs", {}) as Dictionary,
			"inputs_at_staffed": _multiply_dictionary(definition.get("inputs", {}) as Dictionary, staffed_count),
			"outputs_at_staffed": _multiply_dictionary(definition.get("outputs", {}) as Dictionary, staffed_count),
			"inputs_at_operating": _multiply_dictionary(definition.get("inputs", {}) as Dictionary, operating),
			"outputs_at_operating": _multiply_dictionary(definition.get("outputs", {}) as Dictionary, operating)
		})

	return {"groups": groups, "buildings": building_rows}

func _single_labour_assignment_group_data(group_id: String, assigned_by_group: Dictionary, required_by_group: Dictionary) -> Dictionary:
	var total: int = int(population.get(group_id, 0))
	var assigned: int = int(assigned_by_group.get(group_id, 0))
	var required: int = int(required_by_group.get(group_id, assigned))
	return {
		"id": group_id,
		"name": _labour_group_name(group_id),
		"description": _labour_group_description(group_id),
		"total": total,
		"assigned": assigned,
		"required": required,
		"unassigned": max(0, total - assigned),
		"shortfall": max(0, assigned - total),
		"members": [{
			"id": group_id,
			"name": _labour_group_name(group_id),
			"total": total,
			"assigned": assigned,
			"required": required,
			"unassigned": max(0, total - assigned),
			"shortfall": max(0, assigned - total)
		}]
	}

func _combined_labour_assignment_group_data(group_id: String, display_name: String, description: String, member_ids: Array[String], assigned_by_group: Dictionary, required_by_group: Dictionary) -> Dictionary:
	var total: int = 0
	var assigned: int = 0
	var required: int = 0
	var shortfall: int = 0
	var members: Array[Dictionary] = []
	for member_id: String in member_ids:
		var member_total: int = int(population.get(member_id, 0))
		var member_assigned: int = int(assigned_by_group.get(member_id, 0))
		var member_required: int = int(required_by_group.get(member_id, member_assigned))
		var member_shortfall: int = max(0, member_assigned - member_total)
		total += member_total
		assigned += member_assigned
		required += member_required
		shortfall += member_shortfall
		members.append({
			"id": member_id,
			"name": _labour_group_name(member_id),
			"total": member_total,
			"assigned": member_assigned,
			"required": member_required,
			"unassigned": max(0, member_total - member_assigned),
			"shortfall": member_shortfall
		})
	return {
		"id": group_id,
		"name": display_name,
		"description": description,
		"total": total,
		"assigned": assigned,
		"required": required,
		"unassigned": max(0, total - assigned),
		"shortfall": shortfall,
		"members": members
	}

func assign_labour_to_building(building_id: String, group_id: String, amount: int) -> bool:
	# Labour is assigned by staffing built building copies. If a group is supplied,
	# only that worker type changes; otherwise this falls back to the old total-count behaviour.
	if group_id != "":
		return set_staffed_building_count_for_group(building_id, group_id, amount)
	return set_staffed_building_count(building_id, amount)

func set_staffed_building_count(building_id: String, requested_count: int) -> bool:
	# Backwards-compatible total-staffing setter. It fills the building using the
	# first available productive worker types in order.
	_ensure_labour_assignments()
	if not buildings.has(building_id):
		return false
	if not _is_productive_building_id(building_id):
		return false
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return false
	var wanted: int = clampi(requested_count, 0, count)
	var requested: Dictionary = {}
	var remaining: int = wanted
	for group_id: String in _allowed_worker_groups_for_building(building_id):
		if remaining <= 0:
			break
		var max_for_group: int = _max_staffable_count_for_building_group(building_id, group_id, requested)
		var amount: int = mini(remaining, max_for_group)
		requested[group_id] = amount
		remaining -= amount
	labour_assignments[building_id] = requested
	_ensure_labour_assignments()
	return _staffed_count_for_building(building_id) == wanted

func set_staffed_building_count_for_group(building_id: String, group_id: String, requested_count: int) -> bool:
	if group_id == "field_labour":
		return set_staffed_building_count_for_field_labour(building_id, requested_count)
	_ensure_labour_assignments()
	if not buildings.has(building_id):
		return false
	if not _is_productive_building_id(building_id):
		return false
	var allowed: Array[String] = _allowed_worker_groups_for_building(building_id)
	if not allowed.has(group_id):
		return false
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return false
	var current: Dictionary = _staff_assignments_for_building(building_id)
	var final_count: int = _clamp_staffed_count_for_building_group(building_id, group_id, requested_count)
	current[group_id] = final_count

	# If the selected worker type now claims too many building slots, displace
	# other worker types on this same building. This lets the player select
	# Tlacotin, drag the bar up, and have those copies replace Macehualtin rather
	# than first having to reduce the Macehualtin bar manually.
	var used_slots: int = 0
	for key_variant: Variant in current.keys():
		used_slots += int(current[key_variant])
	if used_slots > count:
		var excess: int = used_slots - count
		for other_group: String in allowed:
			if other_group == group_id:
				continue
			if excess <= 0:
				break
			var other_value: int = int(current.get(other_group, 0))
			var reduction: int = mini(other_value, excess)
			current[other_group] = other_value - reduction
			excess -= reduction

	for key_variant: Variant in current.keys().duplicate():
		if int(current[key_variant]) <= 0:
			current.erase(key_variant)

	labour_assignments[building_id] = current
	_ensure_labour_assignments()
	return int((_staff_assignments_for_building(building_id)).get(group_id, 0)) == requested_count

func set_staffed_building_count_for_field_labour(building_id: String, requested_count: int) -> bool:
	_ensure_labour_assignments()
	if not buildings.has(building_id):
		return false
	if not _is_productive_building_id(building_id):
		return false
	if not _building_can_use_field_labour(building_id):
		return false
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return false
	var max_allowed: int = _max_staffable_count_for_field_labour(building_id)
	var wanted: int = clampi(requested_count, 0, mini(count, max_allowed))
	var current: Dictionary = _staff_assignments_for_building(building_id)

	# Replace any old per-member field assignments with one combined pool value.
	for member_id: String in _field_labour_group_ids():
		current.erase(member_id)
	current.erase("field_labour")
	if wanted > 0:
		current["field_labour"] = wanted

	# Do not overfill building slots if future data allows mixed specialist and
	# field-labour staffing on the same building.
	var used_slots: int = 0
	for key_variant: Variant in current.keys():
		used_slots += int(current[key_variant])
	if used_slots > count:
		current["field_labour"] = max(0, int(current.get("field_labour", 0)) - (used_slots - count))

	for key_variant: Variant in current.keys().duplicate():
		if int(current[key_variant]) <= 0:
			current.erase(key_variant)

	labour_assignments[building_id] = current
	_ensure_labour_assignments()
	return _field_labour_staffed_count_for_building(building_id) == wanted

func _productive_labour_required() -> Dictionary:
	# In the current prototype, "required" means the population committed to the
	# currently staffed production buildings. Storehouse input/output estimates use
	# the same staffed building counts.
	return _assigned_labour_by_group()

func _productive_labour_group_ids() -> Array[String]:
	# Warriors are deliberately excluded here. They belong to Barracks and Flower
	# Wars. Production labour is commoner/bonded labour and skilled artisans.
	return ["macehualtin", "tlacotin", "tolteca"]


func _max_staffable_count_for_field_labour_with_used(building_id: String, used_by_group: Dictionary) -> int:
	if not buildings.has(building_id):
		return 0
	if not _building_can_use_field_labour(building_id):
		return 0
	var count: int = int(estate_buildings.get(building_id, 0))
	var needed_per: int = _field_labour_fallback_staff_required(building_id)
	if needed_per <= 0:
		return 0
	var available_total: int = 0
	for member_id: String in _field_labour_group_ids():
		var total_pop: int = int(population.get(member_id, 0))
		var already: int = int(used_by_group.get(member_id, 0))
		available_total += max(0, total_pop - already)
	return mini(count, int(floor(float(available_total) / float(needed_per))))

func _field_labour_population_split_for_building(building_id: String, staffed_copies: int, used_by_group: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	var needed_per: int = _field_labour_fallback_staff_required(building_id)
	if needed_per <= 0 or staffed_copies <= 0:
		return result
	var remaining_people: int = staffed_copies * needed_per
	for member_id: String in _field_labour_group_ids():
		if remaining_people <= 0:
			break
		var total_pop: int = int(population.get(member_id, 0))
		var already: int = int(used_by_group.get(member_id, 0))
		var available_pop: int = max(0, total_pop - already)
		var use_pop: int = mini(remaining_people, available_pop)
		if use_pop > 0:
			result[member_id] = use_pop
			remaining_people -= use_pop
	return result

func _field_labour_distribution_for_building(target_building_id: String, target_copies: int) -> Dictionary:
	# Work through buildings in a stable order so the displayed Macehualtin/Tlacotin
	# split is deterministic and does not double-count the same population.
	var used_by_group: Dictionary = {}
	for building_id: String in building_order:
		if not _is_productive_building_id(building_id):
			continue
		var assignments: Dictionary = _staff_assignments_for_building(building_id)
		var copies: int = int(assignments.get("field_labour", 0))
		if building_id == target_building_id:
			copies = target_copies
		if copies <= 0:
			if building_id == target_building_id:
				return {}
			continue
		var split: Dictionary = _field_labour_population_split_for_building(building_id, copies, used_by_group)
		if building_id == target_building_id:
			return split
		for member_variant: Variant in split.keys():
			var member_id: String = String(member_variant)
			used_by_group[member_id] = int(used_by_group.get(member_id, 0)) + int(split[member_id])
	return {}

func _field_labour_fallback_staff_required(building_id: String) -> int:
	# If old building data only lists one field-labour member, use that same
	# per-building requirement for the combined pool. The shipped buildings.json in
	# this patch lists both Macehualtin and Tlacotin for chinampas, but this keeps
	# older local data from breaking the combined pool.
	for member_id: String in _field_labour_group_ids():
		var amount: int = _staff_required_per_copy_for_group(building_id, member_id)
		if amount > 0:
			return amount
	return 0

func _field_labour_group_ids() -> Array[String]:
	return ["macehualtin", "tlacotin"]

func _production_staff_for_building(building_id: String) -> Dictionary:
	if not buildings.has(building_id):
		return {}
	var output: Dictionary = {}
	for group_id: String in _allowed_worker_groups_for_building(building_id):
		var required: int = _staff_required_per_copy_for_group(building_id, group_id)
		if required > 0:
			output[group_id] = required
	return output

func _labour_group_name(group_id: String) -> String:
	match group_id:
		"macehualtin":
			return "Macehualtin Labourers"
		"tlacotin":
			return "Tlacotin Labourers"
		"tolteca":
			return "Tolteca Artisans"
		"yaotequihuaqueh":
			return "Yaotequihuaqueh Warriors"
	return group_id.capitalize()

func _labour_group_description(group_id: String) -> String:
	match group_id:
		"macehualtin":
			return "Commoner labourers are the main productive base for chinampas and estate work."
		"tlacotin":
			return "Bonded or enslaved labour can support productive work where the estate has capacity and control."
		"tolteca":
			return "Skilled artisans operate workshops and convert raw goods into processed or luxury goods."
		"yaotequihuaqueh":
			return "Warriors mostly belong to Barracks and Flower Wars, but some production chains such as weapon yards can require martial staff."
	return "Productive labour group."

func _building_matches_focus(definition: Dictionary, focus_id: String) -> bool:
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

func _building_view_data(building_id: String) -> Dictionary:
	var definition: Dictionary = buildings[building_id] as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	var status: Dictionary = _estimate_building_status(building_id)
	var staff: Dictionary = definition.get("staff", {}) as Dictionary
	if _is_productive_building_id(building_id):
		staff = _production_staff_for_building(building_id)
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
		"staff_total": _multiply_dictionary(staff, count),
		"staff_assigned": _assigned_staff_for_building(building_id),
		"inputs_total": _multiply_dictionary(inputs, int(status.get("operating", 0))),
		"outputs_total": _multiply_dictionary(outputs, int(status.get("operating", 0))),
		"staff_after_build": _multiply_dictionary(staff, count + 1),
		"inputs_after_build": _multiply_dictionary(inputs, count + 1),
		"outputs_after_build": _multiply_dictionary(outputs, count + 1),
		"staff_after_destroy": _multiply_dictionary(staff, max(0, count - 1)),
		"inputs_after_destroy": _multiply_dictionary(inputs, max(0, count - 1)),
		"outputs_after_destroy": _multiply_dictionary(outputs, max(0, count - 1)),
		"build_cost": definition.get("build_cost", {}) as Dictionary,
		"build_time_veintenas": build_time,
		"can_build": can_build(building_id),
		"build_status": build_status_text(building_id),
		"can_destroy": can_destroy(building_id),
		"destroy_status": destroy_status_text(building_id),
		"operating": int(status.get("operating", 0)),
		"blocked": int(status.get("blocked", 0)),
		"status_text": String(status.get("status_text", ""))
	}

func reserved_resources_for_current_turn() -> Dictionary:
	# These are goods already effectively spoken for before construction spending:
	# population upkeep plus current building input demand. This matches the
	# Storehouse “Reserved” / “Free to spend” logic, so construction cannot consume
	# goods needed to keep the estate running this Veintena.
	var reserved: Dictionary = {}
	var upkeep: Dictionary = estimate_population_upkeep()
	var inputs: Dictionary = estimate_building_inputs()
	for resource_variant: Variant in upkeep.keys():
		var resource_id: String = String(resource_variant)
		reserved[resource_id] = float(reserved.get(resource_id, 0.0)) + float(upkeep[resource_id])
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		reserved[resource_id] = float(reserved.get(resource_id, 0.0)) + float(inputs[resource_id])
	return reserved

func free_stock_after_reserves(resource_id: String) -> float:
	var reserved: Dictionary = reserved_resources_for_current_turn()
	return maxf(0.0, _stock(resource_id) - float(reserved.get(resource_id, 0.0)))

func can_build(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	var cost: Dictionary = definition.get("build_cost", {}) as Dictionary
	var reserved: Dictionary = reserved_resources_for_current_turn()
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var free_after_reserves: float = maxf(0.0, _stock(resource_id) - float(reserved.get(resource_id, 0.0)))
		if free_after_reserves < float(cost[resource_id]):
			return false
	return true

func build_status_text(building_id: String) -> String:
	if not buildings.has(building_id):
		return "Unknown building."
	var definition: Dictionary = buildings[building_id] as Dictionary
	var cost: Dictionary = definition.get("build_cost", {}) as Dictionary
	var reserved: Dictionary = reserved_resources_for_current_turn()
	var missing: Array[String] = []
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(cost[resource_id])
		var stored: float = _stock(resource_id)
		var reserved_amount: float = float(reserved.get(resource_id, 0.0))
		var free_after_reserves: float = maxf(0.0, stored - reserved_amount)
		if free_after_reserves < needed:
			var shortfall: float = needed - free_after_reserves
			var part: String = get_resource_name(resource_id) + " " + _format_amount(shortfall)
			if reserved_amount > 0.0:
				part += " after reserves"
			missing.append(part)
	if missing.is_empty():
		return "Buildable now using free stock after reserves."
	return "Missing: " + ", ".join(missing)

func build_building(building_id: String) -> bool:
	if not buildings.has(building_id):
		emit_signal("build_failed", building_id, "Unknown building.")
		return false
	if not can_build(building_id):
		var reason: String = build_status_text(building_id)
		last_report.append(get_building_name(building_id) + " not built. " + reason)
		emit_signal("build_failed", building_id, reason)
		emit_signal("state_changed")
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	var cost: Dictionary = definition.get("build_cost", {}) as Dictionary
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, -float(cost[resource_id]))
	var previous_count: int = int(estate_buildings.get(building_id, 0))
	var previous_staffed: int = _staffed_count_for_building(building_id)
	estate_buildings[building_id] = previous_count + 1
	# If this building type was previously fully staffed, try to staff the new
	# copy automatically. If the player had deliberately left copies unstaffed,
	# keep that manual choice instead of silently overriding it.
	if _is_productive_building_id(building_id) and previous_staffed >= previous_count:
		_auto_staff_single_building_to_max(building_id)
	else:
		_ensure_labour_assignments()
	var message: String = "Built " + get_building_name(building_id) + "."
	last_report.append(message)
	emit_signal("build_completed", building_id)
	emit_signal("state_changed")
	return true

func can_destroy(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	return int(estate_buildings.get(building_id, 0)) > 0

func destroy_status_text(building_id: String) -> String:
	if not buildings.has(building_id):
		return "Unknown building."
	if can_destroy(building_id):
		return "Can destroy one. No refund in this prototype."
	return "None built."

func destroy_building(building_id: String) -> bool:
	if not buildings.has(building_id):
		emit_signal("destroy_failed", building_id, "Unknown building.")
		return false
	if not can_destroy(building_id):
		var reason: String = destroy_status_text(building_id)
		last_report.append(get_building_name(building_id) + " not destroyed. " + reason)
		emit_signal("destroy_failed", building_id, reason)
		emit_signal("state_changed")
		return false
	estate_buildings[building_id] = max(0, int(estate_buildings.get(building_id, 0)) - 1)
	_ensure_labour_assignments()
	last_report.append("Destroyed one " + get_building_name(building_id) + ". No refund given.")
	emit_signal("destroy_completed", building_id)
	emit_signal("state_changed")
	return true

func advance_veintena() -> void:
	if not initialized:
		new_game()
	last_report.clear()
	last_report.append("Veintena " + str(current_veintena) + " resolves.")
	_pay_population_upkeep()
	_operate_buildings()
	current_veintena += 1
	if current_veintena > 18:
		current_veintena = 1
		last_report.append("Nemontemi reckoning placeholder: the next Ritual Year begins.")
	last_report.append("Now entering Veintena " + str(current_veintena) + ".")
	emit_signal("turn_advanced", last_report)
	emit_signal("state_changed")

func estimate_population_upkeep() -> Dictionary:
	var result: Dictionary = {}
	for group_variant: Variant in population.keys():
		var group_id: String = String(group_variant)
		var count: int = int(population.get(group_id, 0))
		var rates: Dictionary = population_upkeep_rates.get(group_id, {}) as Dictionary
		for resource_variant: Variant in rates.keys():
			var resource_id: String = String(resource_variant)
			var amount: float = float(rates[resource_id]) * float(count) / 5.0
			result[resource_id] = float(result.get(resource_id, 0.0)) + amount
	return result

func estimate_building_inputs() -> Dictionary:
	# Single source of truth for Storehouse / Production / Labour previews.
	# This now uses the same dry-run resolver as the rest of the UI, so input
	# demand reflects staffed buildings, population upkeep paid first, and shared
	# input goods being consumed by earlier buildings in building_order.
	var resolution: Dictionary = estimate_production_resolution()
	return (resolution.get("inputs", {}) as Dictionary).duplicate(true)

func estimate_building_outputs() -> Dictionary:
	# Single source of truth for Storehouse / Production / Labour previews.
	# This now uses the same dry-run resolver as the rest of the UI, so output
	# only comes from buildings that are both staffed and supplied in the shared
	# temporary stockpile.
	var resolution: Dictionary = estimate_production_resolution()
	return (resolution.get("outputs", {}) as Dictionary).duplicate(true)

func estimate_production_resolution() -> Dictionary:
	# Authoritative production preview. This mirrors Advance Veintena order:
	# 1. copy current stockpiles
	# 2. pay population upkeep from the copied stockpile
	# 3. process staffed production buildings in building_order
	# 4. consume inputs from the copied stockpile
	# 5. add outputs to the copied stockpile
	# 6. record exactly what would operate, block, or sit unstaffed
	_ensure_labour_assignments()
	var temp_stockpile: Dictionary = _copy_stockpile_dictionary(estate_stockpiles)
	var upkeep_needed: Dictionary = estimate_population_upkeep()
	var upkeep_paid: Dictionary = {}
	var upkeep_shortfalls: Dictionary = {}

	for resource_variant: Variant in upkeep_needed.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(upkeep_needed[resource_variant])
		var available: float = float(temp_stockpile.get(resource_id, 0.0))
		var paid: float = minf(available, needed)
		temp_stockpile[resource_id] = available - paid
		upkeep_paid[resource_id] = paid
		if paid < needed:
			upkeep_shortfalls[resource_id] = needed - paid

	var total_inputs: Dictionary = {}
	var total_outputs: Dictionary = {}
	var building_statuses: Dictionary = {}
	var report_lines: Array[String] = []

	for building_id: String in building_order:
		if not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			building_statuses[building_id] = {
				"operating": 0,
				"blocked": 0,
				"staffed_count": 0,
				"unstaffed": 0,
				"input_blocked": 0,
				"status_text": "Not built.",
				"input_shortages": []
			}
			continue

		var staffed_count: int = count
		if _is_productive_building_id(building_id):
			staffed_count = _staffed_count_for_building(building_id)
		staffed_count = clampi(staffed_count, 0, count)

		var operated: int = 0
		var input_blocked: int = 0
		var input_shortages: Array[String] = []

		for index: int in range(staffed_count):
			var reason: String = _can_operate_instance_with_stockpile(definition, temp_stockpile)
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

		if operated > 0:
			report_lines.append(String(definition.get("name", building_id)) + " would operate x" + str(operated) + ".")
		if input_blocked > 0:
			report_lines.append(String(definition.get("name", building_id)) + " would be input-blocked x" + str(input_blocked) + ".")
		if _is_productive_building_id(building_id) and unstaffed > 0:
			report_lines.append(String(definition.get("name", building_id)) + " would be unstaffed x" + str(unstaffed) + ".")

	return {
		"inputs": total_inputs,
		"outputs": total_outputs,
		"building_statuses": building_statuses,
		"stockpile_after_upkeep_and_production": temp_stockpile,
		"upkeep_needed": upkeep_needed,
		"upkeep_paid": upkeep_paid,
		"upkeep_shortfalls": upkeep_shortfalls,
		"reports": report_lines
	}

func _copy_stockpile_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = float(source[key_variant])
	return output

func _can_operate_instance_with_stockpile(definition: Dictionary, temp_stockpile: Dictionary) -> String:
	var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(inputs[resource_variant])
		if float(temp_stockpile.get(resource_id, 0.0)) < needed:
			return "not enough " + get_resource_name(resource_id) + " input"
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

func _pay_population_upkeep() -> void:
	var upkeep: Dictionary = estimate_population_upkeep()
	for resource_variant: Variant in upkeep.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(upkeep[resource_id])
		var available: float = _stock(resource_id)
		var paid: float = minf(available, needed)
		_add_stock(resource_id, -paid)
		if paid >= needed:
			last_report.append("Paid population upkeep: " + _format_amount(needed) + " " + get_resource_name(resource_id) + ".")
		else:
			last_report.append("Shortage: paid only " + _format_amount(paid) + " / " + _format_amount(needed) + " " + get_resource_name(resource_id) + " for population upkeep.")

func _operate_buildings() -> void:
	_ensure_labour_assignments()
	for building_id: String in building_order:
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var target_count: int = count
		if _is_productive_building_id(building_id):
			target_count = _staffed_count_for_building(building_id)
		var operated: int = 0
		var blocked: int = 0
		for index: int in range(target_count):
			var reason: String = _can_operate_instance(definition)
			if reason == "":
				_consume_inputs(definition.get("inputs", {}) as Dictionary)
				_add_outputs(definition.get("outputs", {}) as Dictionary)
				operated += 1
			else:
				blocked += 1
				last_report.append(String(definition.get("name", building_id)) + " blocked: " + reason)
		if operated > 0:
			last_report.append(String(definition.get("name", building_id)) + " operated x" + str(operated) + ".")
		if _is_productive_building_id(building_id) and target_count < count:
			last_report.append(String(definition.get("name", building_id)) + " unstaffed x" + str(count - target_count) + ".")

func _can_operate_instance(definition: Dictionary) -> String:
	var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		if _stock(resource_id) < float(inputs[resource_id]):
			return "not enough " + get_resource_name(resource_id) + " input"
	return ""

func _reserve_staff(staff: Dictionary, available_staff: Dictionary) -> void:
	# Legacy helper retained for older patches. Production staffing is now handled
	# by staffed building counts rather than per-population sliders.
	for group_variant: Variant in staff.keys():
		var group_id: String = String(group_variant)
		available_staff[group_id] = int(available_staff.get(group_id, 0)) - int(staff[group_id])

func _consume_inputs(inputs: Dictionary) -> void:
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, -float(inputs[resource_id]))

func _add_outputs(outputs: Dictionary) -> void:
	for resource_variant: Variant in outputs.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, float(outputs[resource_id]))

func _estimate_building_status(building_id: String) -> Dictionary:
	if not buildings.has(building_id):
		return {"operating": 0, "blocked": 0, "staffed_count": 0, "unstaffed": 0, "input_blocked": 0, "status_text": "Unknown building.", "input_shortages": []}
	var resolution: Dictionary = estimate_production_resolution()
	var statuses: Dictionary = resolution.get("building_statuses", {}) as Dictionary
	if statuses.has(building_id):
		return (statuses[building_id] as Dictionary).duplicate(true)
	return {"operating": 0, "blocked": 0, "staffed_count": 0, "unstaffed": 0, "input_blocked": 0, "status_text": "Not built.", "input_shortages": []}

func _estimated_operating_count_for_building(building_id: String) -> int:
	if not buildings.has(building_id):
		return 0
	return int(_estimate_building_status(building_id).get("operating", 0))

func _is_productive_building_id(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	var screen_id: String = String(definition.get("screen", ""))
	return screen_id == "chinampas" or screen_id == "workshops"

func _auto_staff_all_productive_buildings() -> void:
	# Force a clean automatic staffing pass. Used for new-game setup so built
	# production starts staffed when the estate has the people for it.
	labour_assignments.clear()
	var running_by_group: Dictionary = {}
	for building_id: String in _production_auto_staff_order():
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		var assignment: Dictionary = _default_assignment_for_building(building_id, count, running_by_group)
		labour_assignments[building_id] = assignment
	_ensure_labour_assignments()

func _auto_staff_single_building_to_max(building_id: String) -> void:
	# Try to staff as many copies of one building as possible without rewriting
	# all other manual assignments. This is mainly used after constructing one
	# extra productive building.
	if not _is_productive_building_id(building_id):
		return
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return
	var running_by_group: Dictionary = _assigned_labour_by_group_excluding(building_id)
	var assignment: Dictionary = _default_assignment_for_building(building_id, count, running_by_group)
	labour_assignments[building_id] = assignment
	_ensure_labour_assignments()

func _production_auto_staff_order() -> Array[String]:
	# Maize is the protected food base and should be staffed before every other
	# productive building. After maize, use normal building priority/order so the
	# fewest possible lower-priority buildings are left idle when labour is short.
	var maize_ids: Array[String] = []
	var other_ids: Array[String] = []
	for building_id: String in building_order:
		if not _is_productive_building_id(building_id):
			continue
		if _is_maize_production_building(building_id):
			maize_ids.append(building_id)
		else:
			other_ids.append(building_id)
	maize_ids.append_array(other_ids)
	return maize_ids

func _is_maize_production_building(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	if building_id.find("maize") >= 0:
		return true
	var definition: Dictionary = buildings[building_id] as Dictionary
	var outputs: Dictionary = definition.get("outputs", {}) as Dictionary
	return outputs.has("maize")

func _ensure_labour_assignments() -> void:
	# Labour assignment is stored as: building_id -> {worker_group_id: staffed_building_count}.
	# For the combined Field Labour UI, raw/chinampa buildings store
	# {"field_labour": count}. That count means "this many building copies are
	# staffed from the combined Macehualtin + Tlacotin pool". The population split
	# is calculated separately so the two populations can combine to staff one
	# building copy.
	var running_by_group: Dictionary = {}

	for building_key_variant: Variant in labour_assignments.keys().duplicate():
		var existing_id: String = String(building_key_variant)
		if not _is_productive_building_id(existing_id) or int(estate_buildings.get(existing_id, 0)) <= 0:
			labour_assignments.erase(existing_id)

	for building_id: String in building_order:
		if not _is_productive_building_id(building_id):
			continue
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			labour_assignments.erase(building_id)
			continue
		var allowed: Array[String] = _allowed_worker_groups_for_building(building_id)
		if allowed.is_empty() and not _building_can_use_field_labour(building_id):
			labour_assignments.erase(building_id)
			continue

		var requested: Dictionary = {}
		if labour_assignments.has(building_id):
			requested = _coerce_staff_assignments_for_building(building_id, labour_assignments[building_id])
		else:
			requested = _default_assignment_for_building(building_id, count, running_by_group)

		var final_assignments: Dictionary = {}
		var remaining_slots: int = count

		# Combined Field Labour is handled before the individual worker loop because
		# one staffed building can be supplied by a mixture of Macehualtin and Tlacotin.
		if _building_can_use_field_labour(building_id):
			var field_wanted: int = clampi(int(requested.get("field_labour", 0)), 0, remaining_slots)
			if field_wanted > 0:
				var field_possible: int = _max_staffable_count_for_field_labour_with_used(building_id, running_by_group)
				var field_count: int = mini(field_wanted, field_possible)
				if field_count > 0:
					final_assignments["field_labour"] = field_count
					var split: Dictionary = _field_labour_population_split_for_building(building_id, field_count, running_by_group)
					for member_variant: Variant in split.keys():
						var member_id: String = String(member_variant)
						running_by_group[member_id] = int(running_by_group.get(member_id, 0)) + int(split[member_id])
					remaining_slots -= field_count

		# Specialist / non-field groups are still handled individually.
		for group_id: String in allowed:
			if group_id == "macehualtin" or group_id == "tlacotin":
				# These are represented by the combined field_labour entry for chinampas.
				if _building_can_use_field_labour(building_id):
					continue
			if remaining_slots <= 0:
				break
			var wanted: int = clampi(int(requested.get(group_id, 0)), 0, remaining_slots)
			var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
			var total: int = int(population.get(group_id, 0))
			var already: int = int(running_by_group.get(group_id, 0))
			var available_pop: int = max(0, total - already)
			var max_by_pop: int = 0
			if needed_per > 0:
				max_by_pop = int(floor(float(available_pop) / float(needed_per)))
			var final_count: int = mini(wanted, max_by_pop)
			if final_count > 0:
				final_assignments[group_id] = final_count
				running_by_group[group_id] = already + final_count * needed_per
				remaining_slots -= final_count

		labour_assignments[building_id] = final_assignments

func _default_assignment_for_building(building_id: String, count: int, running_by_group: Dictionary) -> Dictionary:
	var requested: Dictionary = {}
	var remaining: int = count
	if _building_can_use_field_labour(building_id):
		var possible_field: int = _max_staffable_count_for_field_labour_with_used(building_id, running_by_group)
		var use_field: int = mini(remaining, possible_field)
		if use_field > 0:
			requested["field_labour"] = use_field
			var split: Dictionary = _field_labour_population_split_for_building(building_id, use_field, running_by_group)
			for member_variant: Variant in split.keys():
				var member_id: String = String(member_variant)
				running_by_group[member_id] = int(running_by_group.get(member_id, 0)) + int(split[member_id])
			remaining -= use_field
		if remaining <= 0:
			return requested

	for group_id: String in _allowed_worker_groups_for_building(building_id):
		if group_id == "macehualtin" or group_id == "tlacotin":
			if _building_can_use_field_labour(building_id):
				continue
		if remaining <= 0:
			break
		var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
		var total: int = int(population.get(group_id, 0))
		var already: int = int(running_by_group.get(group_id, 0))
		var available_pop: int = max(0, total - already)
		var possible: int = 0
		if needed_per > 0:
			possible = int(floor(float(available_pop) / float(needed_per)))
		var use_count: int = mini(remaining, possible)
		if use_count > 0:
			requested[group_id] = use_count
			running_by_group[group_id] = already + use_count * needed_per
			remaining -= use_count
	return requested

func _allowed_worker_groups_for_building(building_id: String) -> Array[String]:
	var output: Array[String] = []
	if not buildings.has(building_id):
		return output
	var definition: Dictionary = buildings[building_id] as Dictionary
	var staff: Dictionary = definition.get("staff", {}) as Dictionary
	var screen_id: String = String(definition.get("screen", ""))
	# Chinampa/raw field labour can be staffed by free Macehualtin or Tlacotin.
	# Workshops remain Tolteca/artisan-led unless the building data explicitly says otherwise.
	if screen_id == "chinampas" and staff.has("macehualtin"):
		output.append("macehualtin")
		output.append("tlacotin")
	else:
		for group_variant: Variant in staff.keys():
			var group_id: String = String(group_variant)
			if _productive_labour_group_ids().has(group_id):
				output.append(group_id)
	return output

func _staff_required_per_copy_for_group(building_id: String, group_id: String) -> int:
	if not buildings.has(building_id):
		return 0
	if group_id == "field_labour":
		return _field_labour_fallback_staff_required(building_id)
	var definition: Dictionary = buildings[building_id] as Dictionary
	var staff: Dictionary = definition.get("staff", {}) as Dictionary
	if staff.has(group_id):
		return int(staff[group_id])
	# Tlacotin can substitute for Macehualtin on chinampa/raw production buildings.
	if group_id == "tlacotin" and String(definition.get("screen", "")) == "chinampas" and staff.has("macehualtin"):
		return int(staff["macehualtin"])
	return 0

func _coerce_staff_assignments_for_building(building_id: String, value: Variant) -> Dictionary:
	var output: Dictionary = {}
	var allowed: Array[String] = _allowed_worker_groups_for_building(building_id)
	if allowed.is_empty() and not _building_can_use_field_labour(building_id):
		return output
	var count: int = int(estate_buildings.get(building_id, 0))
	if value is int or value is float:
		var amount: int = clampi(int(value), 0, count)
		if amount <= 0:
			return output
		if _building_can_use_field_labour(building_id):
			output["field_labour"] = amount
		elif not allowed.is_empty():
			output[allowed[0]] = amount
		return output
	if not (value is Dictionary):
		return output
	var assignment: Dictionary = value as Dictionary

	if _building_can_use_field_labour(building_id):
		var field_amount: int = int(assignment.get("field_labour", 0))
		# Older patches stored Macehualtin/Tlacotin copy counts separately. Merge
		# them into the combined Field Labour pool so the two populations can staff
		# one building together.
		for member_id: String in _field_labour_group_ids():
			field_amount += int(assignment.get(member_id, 0))
		if field_amount > 0:
			output["field_labour"] = clampi(field_amount, 0, count)

	for group_id: String in allowed:
		if _field_labour_group_ids().has(group_id) and _building_can_use_field_labour(building_id):
			continue
		var raw_amount: int = int(assignment.get(group_id, 0))
		if raw_amount <= 0:
			continue
		var needed_per: int = max(1, _staff_required_per_copy_for_group(building_id, group_id))
		if raw_amount > count:
			output[group_id] = int(floor(float(raw_amount) / float(needed_per)))
		else:
			output[group_id] = raw_amount
	return output

func _staff_assignments_for_building(building_id: String) -> Dictionary:
	if not labour_assignments.has(building_id):
		return {}
	return _coerce_staff_assignments_for_building(building_id, labour_assignments[building_id])

func _assigned_staff_for_building(building_id: String) -> Dictionary:
	_ensure_labour_assignments()
	return _staff_population_by_building(building_id)

func _staff_population_by_building(building_id: String) -> Dictionary:
	var result: Dictionary = {}
	var assignments: Dictionary = _staff_assignments_for_building(building_id)
	if assignments.has("field_labour"):
		var copies: int = int(assignments.get("field_labour", 0))
		var split: Dictionary = _field_labour_distribution_for_building(building_id, copies)
		for member_variant: Variant in split.keys():
			var member_id: String = String(member_variant)
			result[member_id] = int(result.get(member_id, 0)) + int(split[member_id])
	for group_variant: Variant in assignments.keys():
		var group_id: String = String(group_variant)
		if group_id == "field_labour":
			continue
		var copies: int = int(assignments[group_id])
		var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
		if copies > 0 and needed_per > 0:
			result[group_id] = int(result.get(group_id, 0)) + copies * needed_per
	return result

func _staffed_count_for_building(building_id: String) -> int:
	var total: int = 0
	var assignments: Dictionary = _staff_assignments_for_building(building_id)
	for group_variant: Variant in assignments.keys():
		total += int(assignments[group_variant])
	return clampi(total, 0, int(estate_buildings.get(building_id, 0)))

func _staffed_count_for_group(building_id: String, group_id: String) -> int:
	if group_id == "field_labour":
		return _field_labour_staffed_count_for_building(building_id)
	return int(_staff_assignments_for_building(building_id).get(group_id, 0))

func _coerce_staffed_count_from_assignment(building_id: String, value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	var assignments: Dictionary = _coerce_staff_assignments_for_building(building_id, value)
	var total: int = 0
	for group_variant: Variant in assignments.keys():
		total += int(assignments[group_variant])
	return total

func _clamp_staffed_count_for_building(building_id: String, requested_count: int) -> int:
	var count: int = int(estate_buildings.get(building_id, 0))
	var wanted: int = clampi(requested_count, 0, count)
	if _building_can_use_field_labour(building_id):
		return mini(wanted, _max_staffable_count_for_field_labour(building_id))
	var assigned_elsewhere: Dictionary = _assigned_labour_by_group_excluding(building_id)
	var requested: Dictionary = {}
	var remaining: int = wanted
	for group_id: String in _allowed_worker_groups_for_building(building_id):
		if remaining <= 0:
			break
		var max_for_group: int = _max_staffable_count_for_building_group(building_id, group_id, requested, assigned_elsewhere)
		var use_count: int = mini(remaining, max_for_group)
		requested[group_id] = use_count
		remaining -= use_count
	var total: int = 0
	for group_variant: Variant in requested.keys():
		total += int(requested[group_variant])
	return total

func _clamp_staffed_count_for_building_group(building_id: String, group_id: String, requested_count: int) -> int:
	var count: int = int(estate_buildings.get(building_id, 0))
	var wanted: int = clampi(requested_count, 0, count)
	var max_allowed: int = _max_staffable_count_for_building_group(building_id, group_id)
	return mini(wanted, max_allowed)

func _building_can_use_field_labour(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	if String(definition.get("screen", "")) == "chinampas":
		return true
	var allowed: Array[String] = _allowed_worker_groups_for_building(building_id)
	for member_id: String in _field_labour_group_ids():
		if allowed.has(member_id):
			return true
	return false

func _field_labour_staffed_count_for_building(building_id: String) -> int:
	var assignments: Dictionary = _staff_assignments_for_building(building_id)
	var total: int = int(assignments.get("field_labour", 0))
	# Keep older per-member assignments readable if they still exist.
	for member_id: String in _field_labour_group_ids():
		total += int(assignments.get(member_id, 0))
	return clampi(total, 0, int(estate_buildings.get(building_id, 0)))

func _max_staffable_count_for_field_labour(building_id: String) -> int:
	return _max_staffable_count_for_field_labour_with_used(building_id, _assigned_labour_by_group_excluding(building_id))

func _max_staffable_count_for_building_group(building_id: String, group_id: String, override_for_building: Dictionary = {}, precomputed_elsewhere: Dictionary = {}) -> int:
	if group_id == "field_labour":
		var elsewhere: Dictionary = precomputed_elsewhere
		if elsewhere.is_empty():
			elsewhere = _assigned_labour_by_group_excluding(building_id)
		return _max_staffable_count_for_field_labour_with_used(building_id, elsewhere)
	if not buildings.has(building_id):
		return 0
	if not _allowed_worker_groups_for_building(building_id).has(group_id):
		return 0
	var count: int = int(estate_buildings.get(building_id, 0))
	var assigned_elsewhere: Dictionary = precomputed_elsewhere
	if assigned_elsewhere.is_empty():
		assigned_elsewhere = _assigned_labour_by_group_excluding(building_id)
	var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
	if needed_per <= 0:
		return 0
	var total_pop: int = int(population.get(group_id, 0))
	var already_elsewhere: int = int(assigned_elsewhere.get(group_id, 0))
	var available_pop: int = max(0, total_pop - already_elsewhere)
	var max_by_pop: int = int(floor(float(available_pop) / float(needed_per)))
	return mini(count, max_by_pop)

func _clamp_staffed_count_with_running(building_id: String, requested_count: int, running_by_group: Dictionary) -> int:
	var count: int = int(estate_buildings.get(building_id, 0))
	var remaining: int = clampi(requested_count, 0, count)
	var staffed: int = 0
	if _building_can_use_field_labour(building_id):
		var possible_field: int = _max_staffable_count_for_field_labour_with_used(building_id, running_by_group)
		var use_field: int = mini(remaining, possible_field)
		if use_field > 0:
			var split: Dictionary = _field_labour_population_split_for_building(building_id, use_field, running_by_group)
			for member_variant: Variant in split.keys():
				var member_id: String = String(member_variant)
				running_by_group[member_id] = int(running_by_group.get(member_id, 0)) + int(split[member_id])
			staffed += use_field
			remaining -= use_field
	if remaining <= 0:
		return staffed
	for group_id: String in _allowed_worker_groups_for_building(building_id):
		if _field_labour_group_ids().has(group_id) and _building_can_use_field_labour(building_id):
			continue
		if remaining <= 0:
			break
		var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
		var total: int = int(population.get(group_id, 0))
		var already: int = int(running_by_group.get(group_id, 0))
		var available: int = max(0, total - already)
		var possible: int = 0
		if needed_per > 0:
			possible = int(floor(float(available) / float(needed_per)))
		var use_count: int = mini(remaining, possible)
		staffed += use_count
		running_by_group[group_id] = already + use_count * needed_per
		remaining -= use_count
	return staffed

func _max_staffable_count_for_building(building_id: String) -> int:
	if not buildings.has(building_id):
		return 0
	return _clamp_staffed_count_for_building(building_id, int(estate_buildings.get(building_id, 0)))

func _assigned_labour_by_group_excluding(excluded_building_id: String) -> Dictionary:
	var result: Dictionary = {}
	for building_variant: Variant in labour_assignments.keys():
		var building_id: String = String(building_variant)
		if building_id == excluded_building_id:
			continue
		var assigned: Dictionary = _staff_population_by_building(building_id)
		for group_variant: Variant in assigned.keys():
			var group_id: String = String(group_variant)
			result[group_id] = int(result.get(group_id, 0)) + int(assigned[group_id])
	return result

func _assigned_labour_by_group() -> Dictionary:
	var result: Dictionary = {}
	for building_variant: Variant in labour_assignments.keys():
		var building_id: String = String(building_variant)
		var assigned: Dictionary = _staff_population_by_building(building_id)
		for group_variant: Variant in assigned.keys():
			var group_id: String = String(group_variant)
			result[group_id] = int(result.get(group_id, 0)) + int(assigned[group_id])
	return result


func _multiply_dictionary(values: Dictionary, multiplier: int) -> Dictionary:
	var result: Dictionary = {}
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		result[key] = float(values[key_variant]) * float(multiplier)
	return result

func add_looted_goods_bundle(loot: Dictionary) -> void:
	# Flower Wars should not create a separate "Looted Goods" stockpile.
	# Loot is immediately assigned into actual goods such as maize, wood, cacao,
	# obsidian, cloth, tools, weapons, ritual goods, or fine textiles.
	var gained_parts: Array[String] = []
	for resource_variant: Variant in loot.keys():
		var resource_id: String = String(resource_variant)
		if not resource_order.has(resource_id):
			push_warning("Ignoring looted item that is not a real good: " + resource_id)
			continue
		var amount: float = maxf(0.0, float(loot[resource_id]))
		if amount <= 0.0:
			continue
		_add_stock(resource_id, amount)
		gained_parts.append(_format_amount(amount) + " " + get_resource_name(resource_id))
	if not gained_parts.is_empty():
		last_report.append("Loot assigned into goods: " + ", ".join(gained_parts) + ".")
	emit_signal("state_changed")

func _stock(resource_id: String) -> float:
	return float(estate_stockpiles.get(resource_id, 0.0))

func _add_stock(resource_id: String, amount: float) -> void:
	estate_stockpiles[resource_id] = maxf(0.0, _stock(resource_id) + amount)

func _reserve_breakdown(resource_id: String, upkeep_value: float, input_value: float) -> Array[String]:
	var lines: Array[String] = []
	if upkeep_value > 0.0:
		lines.append("Population upkeep: " + _format_amount(upkeep_value))
	if input_value > 0.0:
		lines.append("Building inputs: " + _format_amount(input_value))
	if lines.is_empty():
		lines.append("No current reserve pressure")
	return lines

func _pressure_label(stored: float, outgoing: float) -> String:
	if outgoing <= 0.0:
		if stored <= 0.0:
			return "Absent"
		return "Stored"
	var coverage: float = stored / outgoing
	if coverage >= 5.0:
		return "Abundant"
	if coverage >= 3.0:
		return "Comfortable"
	if coverage >= 1.5:
		return "Tight"
	if coverage >= 0.75:
		return "Shortage"
	return "Crisis"

func _scarcity_multiplier(coverage: float, demand_value: float) -> float:
	if demand_value <= 0.0:
		return 0.75
	if coverage <= 0.0:
		return 3.0
	return maxf(0.75, minf(3.0, 3.0 / coverage))

func _market_label(coverage: float, demand_value: float) -> String:
	if demand_value <= 0.0:
		return "No demand"
	if coverage >= 5.0:
		return "Abundant"
	if coverage >= 3.0:
		return "Comfortable"
	if coverage >= 1.5:
		return "Tight"
	if coverage >= 0.75:
		return "Shortage"
	return "Crisis"

func _market_trend(coverage: float, demand_value: float) -> String:
	if demand_value <= 0.0:
		return "Idle"
	if coverage >= 5.0:
		return "Soft"
	if coverage >= 3.0:
		return "Stable"
	if coverage >= 1.5:
		return "Rising"
	return "Critical"

func _rival_market_note(resource_id: String) -> String:
	match resource_id:
		"weapons", "obsidian":
			return "War Rival pressure: weapons, obsidian and martial goods."
		"tools", "cloth":
			return "Cunning Rival pressure: practical bottlenecks and market leverage."
		"cacao", "fine_textiles":
			return "Diplomatic Rival pressure: palace-facing status goods."
	return "Rival behaviour can alter this market once procurement is connected."

func _format_amount(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))
