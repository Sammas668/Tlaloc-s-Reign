# LabourSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/LabourSystem.gd
#
# v0.45.9 extraction: owns labour-assignment UI rows, staffing setters,
# and field-labour helper calculations while TRGameState remains the public API.
class_name LabourSystem
extends RefCounted

func get_productive_labour_rows(state: Node) -> Array[Dictionary]:
	if state == null:
		return []
	state.call("_ensure_labour_assignments")
	var required: Dictionary = state.call("_productive_labour_required") as Dictionary
	var assigned_by_group: Dictionary = state.call("_assigned_labour_by_group") as Dictionary
	var rows: Array[Dictionary] = []
	for group_id: String in _string_array_from_variant(state.call("_productive_labour_group_ids")):
		var total: int = int(state.call("_active_population_for_group", group_id))
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
			"name": labour_group_name(group_id),
			"screen": "production",
			"category": "labour",
			"is_labour": true,
			"description": labour_group_description(group_id),
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

func get_labour_assignment_data(state: Node) -> Dictionary:
	if state == null:
		return {"groups": [], "buildings": []}
	state.call("_ensure_labour_assignments")
	var assigned_by_group: Dictionary = state.call("_assigned_labour_by_group") as Dictionary
	var required_by_group: Dictionary = state.call("_productive_labour_required") as Dictionary
	var groups: Array[Dictionary] = []
	groups.append(combined_labour_assignment_group_data(
		state,
		"field_labour",
		"Field Labour",
		"Macehualtin and Tlacotin can both staff chinampas and raw production buildings. The slider assigns staffed building copies from their combined pool.",
		field_labour_group_ids(),
		assigned_by_group,
		required_by_group
	))
	groups.append(single_labour_assignment_group_data(state, "tolteca", assigned_by_group, required_by_group))

	var building_rows: Array[Dictionary] = []
	var building_order: Array = state.get("building_order") as Array
	var buildings: Dictionary = state.get("buildings") as Dictionary
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	for building_id_variant: Variant in building_order:
		var building_id: String = String(building_id_variant)
		if not bool(state.call("_is_productive_building_id", building_id)):
			continue
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var staff_by_group: Dictionary = production_staff_for_building(state, building_id)
		if staff_by_group.is_empty():
			continue
		var assignments: Dictionary = state.call("_staff_assignments_for_building", building_id) as Dictionary
		var max_by_group: Dictionary = {}
		for group_variant: Variant in staff_by_group.keys():
			var group_id: String = String(group_variant)
			max_by_group[group_id] = int(state.call("_max_staffable_count_for_building_group", building_id, group_id))
		if bool(state.call("_building_can_use_field_labour", building_id)):
			max_by_group["field_labour"] = int(state.call("_max_staffable_count_for_field_labour", building_id))
		var staffed_count: int = int(state.call("_staffed_count_for_building", building_id))
		var status: Dictionary = state.call("_estimate_building_status", building_id) as Dictionary
		var operating: int = int(status.get("operating", 0))
		building_rows.append({
			"id": building_id,
			"name": String(definition.get("name", building_id.capitalize())),
			"count": count,
			"staffed_count": staffed_count,
			"staff_assignments": assignments,
			"allowed_worker_groups": state.call("_allowed_worker_groups_for_building", building_id),
			"staff_per_instance_by_group": staff_by_group,
			"max_staffable_by_group": max_by_group,
			"max_staffable": int(state.call("_max_staffable_count_for_building", building_id)),
			"staff_population_by_group": state.call("_staff_population_by_building", building_id),
			"operating": operating,
			"blocked": int(status.get("blocked", 0)),
			"unstaffed": int(status.get("unstaffed", 0)),
			"status_text": String(status.get("status_text", "")),
			"staff_per_instance": staff_by_group,
			"staff_at_staffed": state.call("_assigned_staff_for_building", building_id),
			"inputs_per_instance": definition.get("inputs", {}) as Dictionary,
			"outputs_per_instance": definition.get("outputs", {}) as Dictionary,
			"inputs_at_staffed": state.call("_multiply_dictionary", definition.get("inputs", {}) as Dictionary, staffed_count),
			"outputs_at_staffed": state.call("_multiply_dictionary", definition.get("outputs", {}) as Dictionary, staffed_count),
			"inputs_at_operating": state.call("_multiply_dictionary", definition.get("inputs", {}) as Dictionary, operating),
			"outputs_at_operating": state.call("_multiply_dictionary", definition.get("outputs", {}) as Dictionary, operating)
		})
	return {"groups": groups, "buildings": building_rows}

func single_labour_assignment_group_data(state: Node, group_id: String, assigned_by_group: Dictionary, required_by_group: Dictionary) -> Dictionary:
	var total: int = int(state.call("_active_population_for_group", group_id))
	var assigned: int = int(assigned_by_group.get(group_id, 0))
	var required: int = int(required_by_group.get(group_id, assigned))
	return {
		"id": group_id,
		"name": labour_group_name(group_id),
		"description": labour_group_description(group_id),
		"total": total,
		"assigned": assigned,
		"required": required,
		"unassigned": max(0, total - assigned),
		"shortfall": max(0, assigned - total),
		"members": [{
			"id": group_id,
			"name": labour_group_name(group_id),
			"total": total,
			"assigned": assigned,
			"required": required,
			"unassigned": max(0, total - assigned),
			"shortfall": max(0, assigned - total)
		}]
	}

func combined_labour_assignment_group_data(state: Node, group_id: String, display_name: String, description: String, member_ids: Array[String], assigned_by_group: Dictionary, required_by_group: Dictionary) -> Dictionary:
	var total: int = 0
	var assigned: int = 0
	var required: int = 0
	var shortfall: int = 0
	var members: Array[Dictionary] = []
	for member_id: String in member_ids:
		var member_total: int = int(state.call("_active_population_for_group", member_id))
		var member_assigned: int = int(assigned_by_group.get(member_id, 0))
		var member_required: int = int(required_by_group.get(member_id, member_assigned))
		var member_shortfall: int = max(0, member_assigned - member_total)
		total += member_total
		assigned += member_assigned
		required += member_required
		shortfall += member_shortfall
		members.append({
			"id": member_id,
			"name": labour_group_name(member_id),
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

func assign_labour_to_building(state: Node, building_id: String, group_id: String, amount: int) -> bool:
	if group_id != "":
		return set_staffed_building_count_for_group(state, building_id, group_id, amount)
	return set_staffed_building_count(state, building_id, amount)

func set_staffed_building_count(state: Node, building_id: String, requested_count: int) -> bool:
	state.call("_ensure_labour_assignments")
	var buildings: Dictionary = state.get("buildings") as Dictionary
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	if not buildings.has(building_id):
		return false
	if not bool(state.call("_is_productive_building_id", building_id)):
		return false
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return false
	var wanted: int = clampi(requested_count, 0, count)
	var requested: Dictionary = {}
	var remaining: int = wanted
	for group_id: String in _string_array_from_variant(state.call("_allowed_worker_groups_for_building", building_id)):
		if remaining <= 0:
			break
		var max_for_group: int = int(state.call("_max_staffable_count_for_building_group", building_id, group_id, requested))
		var amount: int = mini(remaining, max_for_group)
		requested[group_id] = amount
		remaining -= amount
	var labour_assignments: Dictionary = state.get("labour_assignments") as Dictionary
	labour_assignments[building_id] = requested
	state.set("labour_assignments", labour_assignments)
	state.call("_ensure_labour_assignments")
	state.call("_sync_campaign_state_from_current_runtime")
	return int(state.call("_staffed_count_for_building", building_id)) == wanted

func set_staffed_building_count_for_group(state: Node, building_id: String, group_id: String, requested_count: int) -> bool:
	if group_id == "field_labour":
		return set_staffed_building_count_for_field_labour(state, building_id, requested_count)
	state.call("_ensure_labour_assignments")
	var buildings: Dictionary = state.get("buildings") as Dictionary
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	if not buildings.has(building_id):
		return false
	if not bool(state.call("_is_productive_building_id", building_id)):
		return false
	var allowed: Array[String] = _string_array_from_variant(state.call("_allowed_worker_groups_for_building", building_id))
	if not allowed.has(group_id):
		return false
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return false
	var current: Dictionary = state.call("_staff_assignments_for_building", building_id) as Dictionary
	var final_count: int = int(state.call("_clamp_staffed_count_for_building_group", building_id, group_id, requested_count))
	current[group_id] = final_count
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
	var labour_assignments: Dictionary = state.get("labour_assignments") as Dictionary
	labour_assignments[building_id] = current
	state.set("labour_assignments", labour_assignments)
	state.call("_ensure_labour_assignments")
	state.call("_sync_campaign_state_from_current_runtime")
	return int((state.call("_staff_assignments_for_building", building_id) as Dictionary).get(group_id, 0)) == requested_count

func set_staffed_building_count_for_field_labour(state: Node, building_id: String, requested_count: int) -> bool:
	state.call("_ensure_labour_assignments")
	var buildings: Dictionary = state.get("buildings") as Dictionary
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	if not buildings.has(building_id):
		return false
	if not bool(state.call("_is_productive_building_id", building_id)):
		return false
	if not bool(state.call("_building_can_use_field_labour", building_id)):
		return false
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return false
	var max_allowed: int = int(state.call("_max_staffable_count_for_field_labour", building_id))
	var wanted: int = clampi(requested_count, 0, mini(count, max_allowed))
	var current: Dictionary = state.call("_staff_assignments_for_building", building_id) as Dictionary
	for member_id: String in field_labour_group_ids():
		current.erase(member_id)
	current.erase("field_labour")
	if wanted > 0:
		current["field_labour"] = wanted
	var used_slots: int = 0
	for key_variant: Variant in current.keys():
		used_slots += int(current[key_variant])
	if used_slots > count:
		current["field_labour"] = max(0, int(current.get("field_labour", 0)) - (used_slots - count))
	for key_variant: Variant in current.keys().duplicate():
		if int(current[key_variant]) <= 0:
			current.erase(key_variant)
	var labour_assignments: Dictionary = state.get("labour_assignments") as Dictionary
	labour_assignments[building_id] = current
	state.set("labour_assignments", labour_assignments)
	state.call("_ensure_labour_assignments")
	state.call("_sync_campaign_state_from_current_runtime")
	return int(state.call("_field_labour_staffed_count_for_building", building_id)) == wanted

func productive_labour_required(state: Node) -> Dictionary:
	return state.call("_assigned_labour_by_group") as Dictionary

func productive_labour_group_ids() -> Array[String]:
	return ["macehualtin", "tlacotin", "tolteca"]

func max_staffable_count_for_field_labour_with_used(state: Node, building_id: String, used_by_group: Dictionary) -> int:
	var buildings: Dictionary = state.get("buildings") as Dictionary
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	if not buildings.has(building_id):
		return 0
	if not bool(state.call("_building_can_use_field_labour", building_id)):
		return 0
	var count: int = int(estate_buildings.get(building_id, 0))
	var needed_per: int = field_labour_fallback_staff_required(state, building_id)
	if needed_per <= 0:
		return 0
	var available_total: int = 0
	for member_id: String in field_labour_group_ids():
		var total_pop: int = int(state.call("_active_population_for_group", member_id))
		var already: int = int(used_by_group.get(member_id, 0))
		available_total += max(0, total_pop - already)
	return mini(count, int(floor(float(available_total) / float(needed_per))))

func field_labour_population_split_for_building(state: Node, building_id: String, staffed_copies: int, used_by_group: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	var needed_per: int = field_labour_fallback_staff_required(state, building_id)
	if needed_per <= 0 or staffed_copies <= 0:
		return result
	var remaining_people: int = staffed_copies * needed_per
	for member_id: String in field_labour_group_ids():
		if remaining_people <= 0:
			break
		var total_pop: int = int(state.call("_active_population_for_group", member_id))
		var already: int = int(used_by_group.get(member_id, 0))
		var available_pop: int = max(0, total_pop - already)
		var use_pop: int = mini(remaining_people, available_pop)
		if use_pop > 0:
			result[member_id] = use_pop
			remaining_people -= use_pop
	return result

func field_labour_distribution_for_building(state: Node, target_building_id: String, target_copies: int) -> Dictionary:
	var used_by_group: Dictionary = {}
	var building_order: Array = state.get("building_order") as Array
	for building_id_variant: Variant in building_order:
		var building_id: String = String(building_id_variant)
		if not bool(state.call("_is_productive_building_id", building_id)):
			continue
		var assignments: Dictionary = state.call("_staff_assignments_for_building", building_id) as Dictionary
		var copies: int = int(assignments.get("field_labour", 0))
		if building_id == target_building_id:
			copies = target_copies
		if copies <= 0:
			if building_id == target_building_id:
				return {}
			continue
		var split: Dictionary = field_labour_population_split_for_building(state, building_id, copies, used_by_group)
		if building_id == target_building_id:
			return split
		for member_variant: Variant in split.keys():
			var member_id: String = String(member_variant)
			used_by_group[member_id] = int(used_by_group.get(member_id, 0)) + int(split[member_id])
	return {}

func field_labour_fallback_staff_required(state: Node, building_id: String) -> int:
	for member_id: String in field_labour_group_ids():
		var amount: int = int(state.call("_staff_required_per_copy_for_group", building_id, member_id))
		if amount > 0:
			return amount
	return 0

func field_labour_group_ids() -> Array[String]:
	return ["macehualtin", "tlacotin"]

func production_staff_for_building(state: Node, building_id: String) -> Dictionary:
	var buildings: Dictionary = state.get("buildings") as Dictionary
	if not buildings.has(building_id):
		return {}
	var output: Dictionary = {}
	for group_id: String in _string_array_from_variant(state.call("_allowed_worker_groups_for_building", building_id)):
		var required: int = int(state.call("_staff_required_per_copy_for_group", building_id, group_id))
		if required > 0:
			output[group_id] = required
	return output

func labour_group_name(group_id: String) -> String:
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

func labour_group_description(group_id: String) -> String:
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

# -----------------------------------------------------------------------------
# Labour staffing core helpers moved from TRGameState in v0.45.11
# -----------------------------------------------------------------------------

func is_productive_building_id(state: Node, building_id: String) -> bool:
	if state == null:
		return false
	var buildings: Dictionary = state.get("buildings") as Dictionary
	if not buildings.has(building_id):
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	var screen_id: String = String(definition.get("screen", ""))
	return screen_id == "chinampas" or screen_id == "workshops"

func auto_staff_all_productive_buildings(state: Node) -> void:
	if state == null:
		return
	var labour_assignments: Dictionary = state.get("labour_assignments") as Dictionary
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	labour_assignments.clear()
	var running_by_group: Dictionary = {}
	for building_id: String in production_auto_staff_order(state):
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		var assignment: Dictionary = default_assignment_for_building(state, building_id, count, running_by_group)
		labour_assignments[building_id] = assignment
	state.set("labour_assignments", labour_assignments)
	ensure_labour_assignments(state)

func auto_staff_single_building_to_max(state: Node, building_id: String) -> void:
	if state == null:
		return
	if not is_productive_building_id(state, building_id):
		return
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	var labour_assignments: Dictionary = state.get("labour_assignments") as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return
	var running_by_group: Dictionary = assigned_labour_by_group_excluding(state, building_id)
	var assignment: Dictionary = default_assignment_for_building(state, building_id, count, running_by_group)
	labour_assignments[building_id] = assignment
	state.set("labour_assignments", labour_assignments)
	ensure_labour_assignments(state)

func production_auto_staff_order(state: Node) -> Array[String]:
	var maize_ids: Array[String] = []
	var other_ids: Array[String] = []
	if state == null:
		return maize_ids
	var building_order: Array = state.get("building_order") as Array
	for building_id_variant: Variant in building_order:
		var building_id: String = String(building_id_variant)
		if not is_productive_building_id(state, building_id):
			continue
		if is_maize_production_building(state, building_id):
			maize_ids.append(building_id)
		else:
			other_ids.append(building_id)
	maize_ids.append_array(other_ids)
	return maize_ids

func is_maize_production_building(state: Node, building_id: String) -> bool:
	if state == null:
		return false
	var buildings: Dictionary = state.get("buildings") as Dictionary
	if not buildings.has(building_id):
		return false
	if building_id.find("maize") >= 0:
		return true
	var definition: Dictionary = buildings[building_id] as Dictionary
	var outputs: Dictionary = definition.get("outputs", {}) as Dictionary
	return outputs.has("maize")

func ensure_labour_assignments(state: Node) -> void:
	if state == null:
		return
	var labour_assignments: Dictionary = state.get("labour_assignments") as Dictionary
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	var building_order: Array = state.get("building_order") as Array
	var running_by_group: Dictionary = {}

	for building_key_variant: Variant in labour_assignments.keys().duplicate():
		var existing_id: String = String(building_key_variant)
		if not is_productive_building_id(state, existing_id) or int(estate_buildings.get(existing_id, 0)) <= 0:
			labour_assignments.erase(existing_id)

	for building_id_variant: Variant in building_order:
		var building_id: String = String(building_id_variant)
		if not is_productive_building_id(state, building_id):
			continue
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			labour_assignments.erase(building_id)
			continue
		var allowed: Array[String] = allowed_worker_groups_for_building(state, building_id)
		if allowed.is_empty() and not building_can_use_field_labour(state, building_id):
			labour_assignments.erase(building_id)
			continue

		var requested: Dictionary = {}
		if labour_assignments.has(building_id):
			requested = coerce_staff_assignments_for_building(state, building_id, labour_assignments[building_id])
		else:
			requested = default_assignment_for_building(state, building_id, count, running_by_group)

		var final_assignments: Dictionary = {}
		var remaining_slots: int = count

		if building_can_use_field_labour(state, building_id):
			var field_wanted: int = clampi(int(requested.get("field_labour", 0)), 0, remaining_slots)
			if field_wanted > 0:
				var field_possible: int = max_staffable_count_for_field_labour_with_used(state, building_id, running_by_group)
				var field_count: int = mini(field_wanted, field_possible)
				if field_count > 0:
					final_assignments["field_labour"] = field_count
					var split: Dictionary = field_labour_population_split_for_building(state, building_id, field_count, running_by_group)
					for member_variant: Variant in split.keys():
						var member_id: String = String(member_variant)
						running_by_group[member_id] = int(running_by_group.get(member_id, 0)) + int(split[member_id])
					remaining_slots -= field_count

		for group_id: String in allowed:
			if group_id == "macehualtin" or group_id == "tlacotin":
				if building_can_use_field_labour(state, building_id):
					continue
			if remaining_slots <= 0:
				break
			var wanted: int = clampi(int(requested.get(group_id, 0)), 0, remaining_slots)
			var needed_per: int = staff_required_per_copy_for_group(state, building_id, group_id)
			var total: int = int(state.call("_active_population_for_group", group_id))
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
	state.set("labour_assignments", labour_assignments)

func default_assignment_for_building(state: Node, building_id: String, count: int, running_by_group: Dictionary) -> Dictionary:
	var requested: Dictionary = {}
	var remaining: int = count
	if building_can_use_field_labour(state, building_id):
		var possible_field: int = max_staffable_count_for_field_labour_with_used(state, building_id, running_by_group)
		var use_field: int = mini(remaining, possible_field)
		if use_field > 0:
			requested["field_labour"] = use_field
			var split: Dictionary = field_labour_population_split_for_building(state, building_id, use_field, running_by_group)
			for member_variant: Variant in split.keys():
				var member_id: String = String(member_variant)
				running_by_group[member_id] = int(running_by_group.get(member_id, 0)) + int(split[member_id])
			remaining -= use_field
		if remaining <= 0:
			return requested

	for group_id: String in allowed_worker_groups_for_building(state, building_id):
		if group_id == "macehualtin" or group_id == "tlacotin":
			if building_can_use_field_labour(state, building_id):
				continue
		if remaining <= 0:
			break
		var needed_per: int = staff_required_per_copy_for_group(state, building_id, group_id)
		var total: int = int(state.call("_active_population_for_group", group_id))
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

func allowed_worker_groups_for_building(state: Node, building_id: String) -> Array[String]:
	var output: Array[String] = []
	if state == null:
		return output
	var buildings: Dictionary = state.get("buildings") as Dictionary
	if not buildings.has(building_id):
		return output
	var definition: Dictionary = buildings[building_id] as Dictionary
	var staff: Dictionary = definition.get("staff", {}) as Dictionary
	var screen_id: String = String(definition.get("screen", ""))
	if screen_id == "chinampas" and staff.has("macehualtin"):
		output.append("macehualtin")
		output.append("tlacotin")
	else:
		for group_variant: Variant in staff.keys():
			var group_id: String = String(group_variant)
			if productive_labour_group_ids().has(group_id):
				output.append(group_id)
	return output

func staff_required_per_copy_for_group(state: Node, building_id: String, group_id: String) -> int:
	if state == null:
		return 0
	var buildings: Dictionary = state.get("buildings") as Dictionary
	if not buildings.has(building_id):
		return 0
	if group_id == "field_labour":
		return field_labour_fallback_staff_required(state, building_id)
	var definition: Dictionary = buildings[building_id] as Dictionary
	var staff: Dictionary = definition.get("staff", {}) as Dictionary
	if staff.has(group_id):
		return int(staff[group_id])
	if group_id == "tlacotin" and String(definition.get("screen", "")) == "chinampas" and staff.has("macehualtin"):
		return int(staff["macehualtin"])
	return 0

func coerce_staff_assignments_for_building(state: Node, building_id: String, value: Variant) -> Dictionary:
	var output: Dictionary = {}
	if state == null:
		return output
	var allowed: Array[String] = allowed_worker_groups_for_building(state, building_id)
	if allowed.is_empty() and not building_can_use_field_labour(state, building_id):
		return output
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	if value is int or value is float:
		var amount: int = clampi(int(value), 0, count)
		if amount <= 0:
			return output
		if building_can_use_field_labour(state, building_id):
			output["field_labour"] = amount
		elif not allowed.is_empty():
			output[allowed[0]] = amount
		return output
	if not (value is Dictionary):
		return output
	var assignment: Dictionary = value as Dictionary

	if building_can_use_field_labour(state, building_id):
		var field_amount: int = int(assignment.get("field_labour", 0))
		for member_id: String in field_labour_group_ids():
			field_amount += int(assignment.get(member_id, 0))
		if field_amount > 0:
			output["field_labour"] = clampi(field_amount, 0, count)

	for group_id: String in allowed:
		if field_labour_group_ids().has(group_id) and building_can_use_field_labour(state, building_id):
			continue
		var raw_amount: int = int(assignment.get(group_id, 0))
		if raw_amount <= 0:
			continue
		var needed_per: int = max(1, staff_required_per_copy_for_group(state, building_id, group_id))
		if raw_amount > count:
			output[group_id] = int(floor(float(raw_amount) / float(needed_per)))
		else:
			output[group_id] = raw_amount
	return output

func staff_assignments_for_building(state: Node, building_id: String) -> Dictionary:
	var labour_assignments: Dictionary = state.get("labour_assignments") as Dictionary
	if not labour_assignments.has(building_id):
		return {}
	return coerce_staff_assignments_for_building(state, building_id, labour_assignments[building_id])

func assigned_staff_for_building(state: Node, building_id: String) -> Dictionary:
	ensure_labour_assignments(state)
	return staff_population_by_building(state, building_id)

func staff_population_by_building(state: Node, building_id: String) -> Dictionary:
	var result: Dictionary = {}
	var assignments: Dictionary = staff_assignments_for_building(state, building_id)
	if assignments.has("field_labour"):
		var copies: int = int(assignments.get("field_labour", 0))
		var split: Dictionary = field_labour_distribution_for_building(state, building_id, copies)
		for member_variant: Variant in split.keys():
			var member_id: String = String(member_variant)
			result[member_id] = int(result.get(member_id, 0)) + int(split[member_id])
	for group_variant: Variant in assignments.keys():
		var group_id: String = String(group_variant)
		if group_id == "field_labour":
			continue
		var copies: int = int(assignments[group_id])
		var needed_per: int = staff_required_per_copy_for_group(state, building_id, group_id)
		if copies > 0 and needed_per > 0:
			result[group_id] = int(result.get(group_id, 0)) + copies * needed_per
	return result

func staffed_count_for_building(state: Node, building_id: String) -> int:
	var total: int = 0
	var assignments: Dictionary = staff_assignments_for_building(state, building_id)
	for group_variant: Variant in assignments.keys():
		total += int(assignments[group_variant])
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	return clampi(total, 0, int(estate_buildings.get(building_id, 0)))

func staffed_count_for_group(state: Node, building_id: String, group_id: String) -> int:
	if group_id == "field_labour":
		return field_labour_staffed_count_for_building(state, building_id)
	return int(staff_assignments_for_building(state, building_id).get(group_id, 0))

func coerce_staffed_count_from_assignment(state: Node, building_id: String, value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	var assignments: Dictionary = coerce_staff_assignments_for_building(state, building_id, value)
	var total: int = 0
	for group_variant: Variant in assignments.keys():
		total += int(assignments[group_variant])
	return total

func clamp_staffed_count_for_building(state: Node, building_id: String, requested_count: int) -> int:
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	var wanted: int = clampi(requested_count, 0, count)
	if building_can_use_field_labour(state, building_id):
		return mini(wanted, max_staffable_count_for_field_labour(state, building_id))
	var assigned_elsewhere: Dictionary = assigned_labour_by_group_excluding(state, building_id)
	var requested: Dictionary = {}
	var remaining: int = wanted
	for group_id: String in allowed_worker_groups_for_building(state, building_id):
		if remaining <= 0:
			break
		var max_for_group: int = max_staffable_count_for_building_group(state, building_id, group_id, requested, assigned_elsewhere)
		var use_count: int = mini(remaining, max_for_group)
		requested[group_id] = use_count
		remaining -= use_count
	var total: int = 0
	for group_variant: Variant in requested.keys():
		total += int(requested[group_variant])
	return total

func clamp_staffed_count_for_building_group(state: Node, building_id: String, group_id: String, requested_count: int) -> int:
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	var wanted: int = clampi(requested_count, 0, count)
	var max_allowed: int = max_staffable_count_for_building_group(state, building_id, group_id)
	return mini(wanted, max_allowed)

func building_can_use_field_labour(state: Node, building_id: String) -> bool:
	if state == null:
		return false
	var buildings: Dictionary = state.get("buildings") as Dictionary
	if not buildings.has(building_id):
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	if String(definition.get("screen", "")) == "chinampas":
		return true
	var allowed: Array[String] = allowed_worker_groups_for_building(state, building_id)
	for member_id: String in field_labour_group_ids():
		if allowed.has(member_id):
			return true
	return false

func field_labour_staffed_count_for_building(state: Node, building_id: String) -> int:
	var assignments: Dictionary = staff_assignments_for_building(state, building_id)
	var total: int = int(assignments.get("field_labour", 0))
	for member_id: String in field_labour_group_ids():
		total += int(assignments.get(member_id, 0))
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	return clampi(total, 0, int(estate_buildings.get(building_id, 0)))

func max_staffable_count_for_field_labour(state: Node, building_id: String) -> int:
	return max_staffable_count_for_field_labour_with_used(state, building_id, assigned_labour_by_group_excluding(state, building_id))

func max_staffable_count_for_building_group(state: Node, building_id: String, group_id: String, override_for_building: Dictionary = {}, precomputed_elsewhere: Dictionary = {}) -> int:
	if group_id == "field_labour":
		var elsewhere: Dictionary = precomputed_elsewhere
		if elsewhere.is_empty():
			elsewhere = assigned_labour_by_group_excluding(state, building_id)
		return max_staffable_count_for_field_labour_with_used(state, building_id, elsewhere)
	var buildings: Dictionary = state.get("buildings") as Dictionary
	if not buildings.has(building_id):
		return 0
	if not allowed_worker_groups_for_building(state, building_id).has(group_id):
		return 0
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	var assigned_elsewhere: Dictionary = precomputed_elsewhere
	if assigned_elsewhere.is_empty():
		assigned_elsewhere = assigned_labour_by_group_excluding(state, building_id)
	var needed_per: int = staff_required_per_copy_for_group(state, building_id, group_id)
	if needed_per <= 0:
		return 0
	var total_pop: int = int(state.call("_active_population_for_group", group_id))
	var already_elsewhere: int = int(assigned_elsewhere.get(group_id, 0))
	var available_pop: int = max(0, total_pop - already_elsewhere)
	var max_by_pop: int = int(floor(float(available_pop) / float(needed_per)))
	return mini(count, max_by_pop)

func clamp_staffed_count_with_running(state: Node, building_id: String, requested_count: int, running_by_group: Dictionary) -> int:
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	var remaining: int = clampi(requested_count, 0, count)
	var staffed: int = 0
	if building_can_use_field_labour(state, building_id):
		var possible_field: int = max_staffable_count_for_field_labour_with_used(state, building_id, running_by_group)
		var use_field: int = mini(remaining, possible_field)
		if use_field > 0:
			var split: Dictionary = field_labour_population_split_for_building(state, building_id, use_field, running_by_group)
			for member_variant: Variant in split.keys():
				var member_id: String = String(member_variant)
				running_by_group[member_id] = int(running_by_group.get(member_id, 0)) + int(split[member_id])
			staffed += use_field
			remaining -= use_field
	if remaining <= 0:
		return staffed
	for group_id: String in allowed_worker_groups_for_building(state, building_id):
		if field_labour_group_ids().has(group_id) and building_can_use_field_labour(state, building_id):
			continue
		if remaining <= 0:
			break
		var needed_per: int = staff_required_per_copy_for_group(state, building_id, group_id)
		var total: int = int(state.call("_active_population_for_group", group_id))
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

func max_staffable_count_for_building(state: Node, building_id: String) -> int:
	var buildings: Dictionary = state.get("buildings") as Dictionary
	if not buildings.has(building_id):
		return 0
	var estate_buildings: Dictionary = state.get("estate_buildings") as Dictionary
	return clamp_staffed_count_for_building(state, building_id, int(estate_buildings.get(building_id, 0)))

func assigned_labour_by_group_excluding(state: Node, excluded_building_id: String) -> Dictionary:
	var result: Dictionary = {}
	var labour_assignments: Dictionary = state.get("labour_assignments") as Dictionary
	for building_variant: Variant in labour_assignments.keys():
		var building_id: String = String(building_variant)
		if building_id == excluded_building_id:
			continue
		var assigned: Dictionary = staff_population_by_building(state, building_id)
		for group_variant: Variant in assigned.keys():
			var group_id: String = String(group_variant)
			result[group_id] = int(result.get(group_id, 0)) + int(assigned[group_id])
	return result

func assigned_labour_by_group(state: Node) -> Dictionary:
	var result: Dictionary = {}
	var labour_assignments: Dictionary = state.get("labour_assignments") as Dictionary
	for building_variant: Variant in labour_assignments.keys():
		var building_id: String = String(building_variant)
		var assigned: Dictionary = staff_population_by_building(state, building_id)
		for group_variant: Variant in assigned.keys():
			var group_id: String = String(group_variant)
			result[group_id] = int(result.get(group_id, 0)) + int(assigned[group_id])
	return result

func _string_array_from_variant(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if value is Array:
		for item: Variant in value:
			output.append(String(item))
	return output
