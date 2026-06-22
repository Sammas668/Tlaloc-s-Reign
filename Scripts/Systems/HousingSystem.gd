# HousingSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/HousingSystem.gd
#
# Owns housing-capacity, active/mothballed housing and housing-maintenance rules.
# Reads and writes CampaignState through explicit access methods. If
# CampaignState is unavailable, this system returns safe defaults instead of
# reading or writing retired TRGameState duplicate state.

class_name HousingSystem
extends RefCounted

var _active_population_cache_token: String = ""
var _active_population_cache: Dictionary = {}


func get_housing_summary(state: Node) -> Dictionary:
	var tiers: Array[Dictionary] = []
	var total_population: int = 0
	var total_active_population: int = 0
	var total_inactive_population: int = 0
	var total_capacity: int = 0
	var total_active_capacity: int = 0
	var total_over: int = 0
	var total_free: int = 0
	var built_capacity_by_group: Dictionary = housing_capacity_by_group(state, {}, false)
	var active_capacity_by_group: Dictionary = housing_capacity_by_group(state, {}, true)
	var maintenance: Dictionary = estimate_housing_maintenance(state)

	for category_id: String in housing_category_order():
		var tier: Dictionary = housing_category_summary(state, category_id, built_capacity_by_group, active_capacity_by_group)
		tiers.append(tier)
		total_population += int(tier.get("population", 0))
		total_active_population += int(tier.get("active_population", 0))
		total_inactive_population += int(tier.get("inactive_population", 0))
		total_capacity += int(tier.get("capacity", 0))
		total_active_capacity += int(tier.get("active_capacity", 0))
		total_over += int(tier.get("over_capacity", 0))
		total_free += int(tier.get("free_capacity", 0))

	return {
		"tiers": tiers,
		"capacity_by_group": active_capacity_by_group,
		"built_capacity_by_group": built_capacity_by_group,
		"maintenance": maintenance,
		"total_population": total_population,
		"total_active_population": total_active_population,
		"total_inactive_population": total_inactive_population,
		"total_capacity": total_capacity,
		"total_active_capacity": total_active_capacity,
		"total_over_capacity": total_over,
		"total_free_capacity": total_free,
		"status_text": housing_status_text(total_active_population, total_active_capacity)
	}


func get_housing_rows(state: Node, focus_id: String = "overview") -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var built_capacity_by_group: Dictionary = housing_capacity_by_group(state, {}, false)
	var active_capacity_by_group: Dictionary = housing_capacity_by_group(state, {}, true)

	if focus_id == "" or focus_id == "overview":
		for category_id: String in housing_category_order():
			var tier: Dictionary = housing_category_summary(state, category_id, built_capacity_by_group, active_capacity_by_group)
			tier["is_summary"] = true
			output.append(tier)
		return output

	if focus_id == "mothball":
		return get_housing_mothball_rows(state)

	var buildings: Dictionary = _buildings(state)
	for building_id: String in _building_order(state):
		if not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		if String(definition.get("screen", "")) != "housing":
			continue
		if String(definition.get("category", "")) != focus_id:
			continue
		output.append(housing_building_view_data(state, building_id, built_capacity_by_group, active_capacity_by_group))

	return output


func housing_capacity_by_group(state: Node, overrides: Dictionary = {}, active_only: bool = true) -> Dictionary:
	ensure_active_housing_counts(state)

	var result: Dictionary = {}
	var base_housing_capacity: Dictionary = _base_housing_capacity(state)
	var population: Dictionary = _population(state)
	var estate_buildings: Dictionary = _estate_buildings(state)
	var active_housing_counts: Dictionary = _active_housing_counts(state)
	var buildings: Dictionary = _buildings(state)
	var building_order: Array[String] = _building_order(state)

	for group_variant: Variant in base_housing_capacity.keys():
		var group_id: String = String(group_variant)
		result[group_id] = int(base_housing_capacity[group_variant])

	for group_variant: Variant in population.keys():
		var group_id: String = String(group_variant)
		if not result.has(group_id):
			result[group_id] = 0

	for building_id: String in building_order:
		if not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		if String(definition.get("screen", "")) != "housing":
			continue
		if not definition.has("housing_capacity") and not definition.has("housing_maintenance"):
			continue

		var built_count: int = int(estate_buildings.get(building_id, 0))
		var count: int = built_count
		if active_only:
			count = int(active_housing_counts.get(building_id, built_count))
		if overrides.has(building_id):
			count = int(overrides[building_id])

		count = clampi(count, 0, built_count)
		if count <= 0:
			continue

		var capacity: Dictionary = definition.get("housing_capacity", {}) as Dictionary
		for group_variant: Variant in capacity.keys():
			var group_id: String = String(group_variant)
			result[group_id] = int(result.get(group_id, 0)) + int(capacity[group_variant]) * count

	return result


func active_population_by_group(state: Node) -> Dictionary:
	var token: String = _active_population_cache_key(state)
	if token != "" and token == _active_population_cache_token and not _active_population_cache.is_empty():
		return _active_population_cache

	var result: Dictionary = {}
	var active_capacity: Dictionary = housing_capacity_by_group(state, {}, true)
	var population: Dictionary = _population(state)

	for group_variant: Variant in population.keys():
		var group_id: String = String(group_variant)
		var total: int = int(population.get(group_id, 0))
		var active_cap: int = int(active_capacity.get(group_id, total))
		result[group_id] = mini(total, max(0, active_cap))

	_active_population_cache_token = token
	_active_population_cache = result
	return result


func inactive_population_by_group(state: Node) -> Dictionary:
	var result: Dictionary = {}
	var active: Dictionary = active_population_by_group(state)
	var population: Dictionary = _population(state)

	for group_variant: Variant in population.keys():
		var group_id: String = String(group_variant)
		result[group_id] = max(0, int(population.get(group_id, 0)) - int(active.get(group_id, 0)))

	return result


func active_population_for_group(state: Node, group_id: String) -> int:
	return int(active_population_by_group(state).get(group_id, 0))


func estimate_housing_maintenance(state: Node) -> Dictionary:
	var result: Dictionary = {}
	var estate_buildings: Dictionary = _estate_buildings(state)
	var buildings: Dictionary = _buildings(state)

	for building_id: String in _building_order(state):
		if not is_housing_building_id(state, building_id):
			continue
		if not buildings.has(building_id):
			continue

		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue

		var definition: Dictionary = buildings[building_id] as Dictionary
		var maintenance: Dictionary = definition.get("housing_maintenance", {}) as Dictionary
		for resource_variant: Variant in maintenance.keys():
			var resource_id: String = String(resource_variant)
			result[resource_id] = float(result.get(resource_id, 0.0)) + float(maintenance[resource_variant]) * float(count)

	return result


func housing_building_view_data(state: Node, building_id: String, built_capacity_by_group: Dictionary = {}, active_capacity_by_group: Dictionary = {}) -> Dictionary:
	ensure_active_housing_counts(state)

	var buildings: Dictionary = _buildings(state)
	if not buildings.has(building_id):
		return {}

	var estate_buildings: Dictionary = _estate_buildings(state)
	var active_housing_counts: Dictionary = _active_housing_counts(state)
	var definition: Dictionary = buildings[building_id] as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	var active_count: int = int(active_housing_counts.get(building_id, count))
	var mothballed_count: int = max(0, count - active_count)
	var capacity: Dictionary = definition.get("housing_capacity", {}) as Dictionary
	var maintenance: Dictionary = definition.get("housing_maintenance", {}) as Dictionary
	var category_id: String = String(definition.get("category", ""))
	var built_capacity_cache: Dictionary = built_capacity_by_group
	var active_capacity_cache: Dictionary = active_capacity_by_group
	if built_capacity_cache.is_empty():
		built_capacity_cache = housing_capacity_by_group(state, {}, false)
	if active_capacity_cache.is_empty():
		active_capacity_cache = housing_capacity_by_group(state, {}, true)
	var category_summary: Dictionary = housing_category_summary(state, category_id, built_capacity_cache, active_capacity_cache)

	var can_build_value: bool = false
	var build_status_value: String = "Build status unavailable."
	var can_destroy_value: bool = false
	var destroy_status_value: String = "Destroy status unavailable."
	if state != null and state.has_method("can_build"):
		can_build_value = bool(state.call("can_build", building_id))
	if state != null and state.has_method("build_status_text"):
		build_status_value = String(state.call("build_status_text", building_id))
	if state != null and state.has_method("can_destroy"):
		can_destroy_value = bool(state.call("can_destroy", building_id))
	if state != null and state.has_method("destroy_status_text"):
		destroy_status_value = String(state.call("destroy_status_text", building_id))

	return {
		"id": building_id,
		"name": String(definition.get("name", building_id.capitalize())),
		"screen": "housing",
		"category": category_id,
		"tier": String(definition.get("tier", "")),
		"description": String(definition.get("description", "")),
		"count": count,
		"active_count": active_count,
		"mothballed_count": mothballed_count,
		"operating": active_count,
		"blocked": mothballed_count,
		"build_cost": definition.get("build_cost", {}) as Dictionary,
		"housing_capacity": capacity,
		"housing_maintenance": maintenance,
		"inputs": maintenance,
		"outputs": capacity,
		"capacity_total": _multiply_dictionary(capacity, count),
		"active_capacity_total": _multiply_dictionary(capacity, active_count),
		"maintenance_total": _multiply_dictionary(maintenance, count),
		"capacity_after_build": _multiply_dictionary(capacity, count + 1),
		"maintenance_after_build": _multiply_dictionary(maintenance, count + 1),
		"capacity_after_destroy": _multiply_dictionary(capacity, max(0, count - 1)),
		"maintenance_after_destroy": _multiply_dictionary(maintenance, max(0, count - 1)),
		"category_summary": category_summary,
		"efficiency_text": housing_efficiency_text(capacity, maintenance),
		"can_build": can_build_value,
		"build_status": build_status_value,
		"can_destroy": can_destroy_value,
		"destroy_status": destroy_status_value,
		"status_text": housing_building_status_text(state, building_id)
	}


func housing_category_summary(state: Node, category_id: String, built_capacity_by_group: Dictionary, active_capacity_by_group: Dictionary) -> Dictionary:
	var group_ids: Array[String] = housing_group_ids_for_category(category_id)
	var population_total: int = 0
	var active_population_total: int = 0
	var inactive_population_total: int = 0
	var built_capacity_total: int = 0
	var active_capacity_total: int = 0
	var member_rows: Array[Dictionary] = []
	var population: Dictionary = _population(state)

	for group_id: String in group_ids:
		var pop_count: int = int(population.get(group_id, 0))
		var built_capacity_count: int = int(built_capacity_by_group.get(group_id, 0))
		var active_capacity_count: int = int(active_capacity_by_group.get(group_id, 0))
		var active_pop: int = mini(pop_count, max(0, active_capacity_count))
		var inactive_pop: int = max(0, pop_count - active_pop)
		population_total += pop_count
		active_population_total += active_pop
		inactive_population_total += inactive_pop
		built_capacity_total += built_capacity_count
		active_capacity_total += active_capacity_count
		member_rows.append({
			"id": group_id,
			"name": labour_group_name(group_id),
			"population": pop_count,
			"active_population": active_pop,
			"inactive_population": inactive_pop,
			"capacity": built_capacity_count,
			"active_capacity": active_capacity_count,
			"free_capacity": max(0, active_capacity_count - active_pop),
			"over_capacity": max(0, active_pop - active_capacity_count),
			"status": housing_status_text(active_pop, active_capacity_count)
		})

	var building_options: Array[Dictionary] = []
	var buildings: Dictionary = _buildings(state)
	var estate_buildings: Dictionary = _estate_buildings(state)
	var active_housing_counts: Dictionary = _active_housing_counts(state)

	for building_id: String in _building_order(state):
		if not is_housing_building_id(state, building_id):
			continue
		if not buildings.has(building_id):
			continue

		var definition: Dictionary = buildings[building_id] as Dictionary
		if String(definition.get("category", "")) != category_id:
			continue

		building_options.append({
			"id": building_id,
			"name": String(definition.get("name", building_id.capitalize())),
			"tier": String(definition.get("tier", "")),
			"count": int(estate_buildings.get(building_id, 0)),
			"active_count": int(active_housing_counts.get(building_id, int(estate_buildings.get(building_id, 0)))),
			"build_cost": definition.get("build_cost", {}) as Dictionary,
			"housing_capacity": definition.get("housing_capacity", {}) as Dictionary,
			"housing_maintenance": definition.get("housing_maintenance", {}) as Dictionary,
			"efficiency_text": housing_efficiency_text(definition.get("housing_capacity", {}) as Dictionary, definition.get("housing_maintenance", {}) as Dictionary)
		})

	return {
		"id": category_id,
		"name": housing_category_name(category_id),
		"population": population_total,
		"active_population": active_population_total,
		"inactive_population": inactive_population_total,
		"capacity": built_capacity_total,
		"active_capacity": active_capacity_total,
		"free_capacity": max(0, active_capacity_total - active_population_total),
		"over_capacity": max(0, active_population_total - active_capacity_total),
		"status": housing_status_text(active_population_total, active_capacity_total),
		"members": member_rows,
		"buildings": building_options,
		"maintenance": housing_maintenance_for_category(state, category_id)
	}


func housing_category_order() -> Array[String]:
	return ["field_labour", "artisans", "tlacotin", "warriors", "priests", "nobles", "captives"]


func housing_category_name(category_id: String) -> String:
	match category_id:
		"field_labour":
			return "Field Labour"
		"artisans":
			return "Artisans"
		"tlacotin":
			return "Tlacotin"
		"warriors":
			return "Warriors"
		"priests":
			return "Priests"
		"nobles":
			return "Nobles"
		"captives":
			return "Captives"
	return category_id.capitalize()


func housing_group_ids_for_category(category_id: String) -> Array[String]:
	match category_id:
		"field_labour":
			return ["macehualtin"]
		"artisans":
			return ["tolteca"]
		"tlacotin":
			return ["tlacotin"]
		"warriors":
			return ["yaotequihuaqueh"]
		"priests":
			return ["tlamacazqueh"]
		"nobles":
			return ["pipiltin"]
		"captives":
			return ["malli"]
	return []


func housing_maintenance_for_category(state: Node, category_id: String) -> Dictionary:
	var result: Dictionary = {}
	var estate_buildings: Dictionary = _estate_buildings(state)
	var buildings: Dictionary = _buildings(state)

	for building_id: String in _building_order(state):
		if not is_housing_building_id(state, building_id):
			continue
		if not buildings.has(building_id):
			continue

		var definition: Dictionary = buildings[building_id] as Dictionary
		if String(definition.get("category", "")) != category_id:
			continue

		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue

		var maintenance: Dictionary = definition.get("housing_maintenance", {}) as Dictionary
		for resource_variant: Variant in maintenance.keys():
			var resource_id: String = String(resource_variant)
			result[resource_id] = float(result.get(resource_id, 0.0)) + float(maintenance[resource_variant]) * float(count)

	return result


func housing_status_text(population_count: int, capacity_count: int) -> String:
	if capacity_count <= 0:
		if population_count <= 0:
			return "No population"
		return "No active capacity"
	if population_count > capacity_count:
		return "Inactive overflow"
	if population_count == capacity_count:
		return "Full"

	var use_ratio: float = float(population_count) / float(capacity_count)
	if use_ratio >= 0.9:
		return "Strained"
	if use_ratio >= 0.7:
		return "Tight"
	return "Comfortable"


func housing_building_status_text(state: Node, building_id: String) -> String:
	var buildings: Dictionary = _buildings(state)
	if not buildings.has(building_id):
		return "Unknown building."

	var definition: Dictionary = buildings[building_id] as Dictionary
	var count: int = int(_estate_buildings(state).get(building_id, 0))
	var active_count: int = int(_active_housing_counts(state).get(building_id, count))
	var capacity: Dictionary = definition.get("housing_capacity", {}) as Dictionary
	var maintenance: Dictionary = definition.get("housing_maintenance", {}) as Dictionary
	var text: String = "Built " + str(count) + "; active " + str(active_count) + "; mothballed " + str(max(0, count - active_count)) + ". Adds " + _dictionary_to_named_string(state, capacity, "capacity") + " each."
	if not maintenance.is_empty():
		text += " Building upkeep each: " + _dictionary_to_named_string(state, maintenance, "") + "."
	return text


func housing_efficiency_text(capacity: Dictionary, maintenance: Dictionary) -> String:
	if maintenance.is_empty():
		return "No building upkeep"
	return "Larger housing tiers have lower upkeep per capacity."


func would_destroy_overcrowd(state: Node, building_id: String) -> Dictionary:
	var result: Dictionary = {"blocked": false, "lines": []}
	if not is_housing_building_id(state, building_id):
		return result

	var current_count: int = int(_estate_buildings(state).get(building_id, 0))
	if current_count <= 0:
		return result

	var active_count: int = int(_active_housing_counts(state).get(building_id, current_count))
	var active_after: int = mini(active_count, max(0, current_count - 1))
	var overrides: Dictionary = {building_id: active_after}
	var after_capacity: Dictionary = housing_capacity_by_group(state, overrides, true)
	var active_by_group: Dictionary = active_population_by_group(state)
	var lines: Array[String] = []

	for group_variant: Variant in _population(state).keys():
		var group_id: String = String(group_variant)
		var active_pop: int = int(active_by_group.get(group_id, 0))
		var capacity_count: int = int(after_capacity.get(group_id, 0))
		if active_pop > capacity_count:
			lines.append(labour_group_name(group_id) + " by " + str(active_pop - capacity_count))

	if not lines.is_empty():
		result["blocked"] = true
		result["lines"] = lines

	return result


func is_housing_building_id(state: Node, building_id: String) -> bool:
	var buildings: Dictionary = _buildings(state)
	if not buildings.has(building_id):
		return false

	var definition: Dictionary = buildings[building_id] as Dictionary
	return String(definition.get("screen", "")) == "housing" and (definition.has("housing_capacity") or definition.has("housing_maintenance"))


func ensure_base_housing_capacity(state: Node) -> void:
	var base_housing_capacity: Dictionary = _base_housing_capacity(state)
	for group_variant: Variant in _population(state).keys():
		var group_id: String = String(group_variant)
		if not base_housing_capacity.has(group_id):
			base_housing_capacity[group_id] = 0
	_set_base_housing_capacity(state, base_housing_capacity)


func ensure_active_housing_counts(state: Node) -> void:
	var active_housing_counts: Dictionary = _active_housing_counts(state)
	var estate_buildings: Dictionary = _estate_buildings(state)
	var buildings: Dictionary = _buildings(state)
	var changed: bool = false

	for building_id: String in _building_order(state):
		var is_housing: bool = false
		if buildings.has(building_id):
			var definition: Dictionary = buildings[building_id] as Dictionary
			is_housing = String(definition.get("screen", "")) == "housing" and (definition.has("housing_capacity") or definition.has("housing_maintenance"))
		if not is_housing:
			if active_housing_counts.has(building_id):
				active_housing_counts.erase(building_id)
				changed = true
			continue

		var built_count: int = int(estate_buildings.get(building_id, 0))
		if built_count <= 0:
			if int(active_housing_counts.get(building_id, -1)) != 0:
				active_housing_counts[building_id] = 0
				changed = true
			continue

		if not active_housing_counts.has(building_id):
			active_housing_counts[building_id] = built_count
			changed = true
		else:
			var clamped: int = clampi(int(active_housing_counts[building_id]), 0, built_count)
			if int(active_housing_counts[building_id]) != clamped:
				active_housing_counts[building_id] = clamped
				changed = true

	if changed:
		_set_active_housing_counts(state, active_housing_counts)

func set_active_housing_count(state: Node, building_id: String, active_count: int) -> bool:
	if not is_housing_building_id(state, building_id):
		return false

	ensure_active_housing_counts(state)
	var active_housing_counts: Dictionary = _active_housing_counts(state)
	var built_count: int = int(_estate_buildings(state).get(building_id, 0))
	active_housing_counts[building_id] = clampi(active_count, 0, built_count)
	_set_active_housing_counts(state, active_housing_counts)
	return true


func get_housing_mothball_rows(state: Node) -> Array[Dictionary]:
	ensure_active_housing_counts(state)

	var rows: Array[Dictionary] = []
	for building_id: String in _building_order(state):
		if not is_housing_building_id(state, building_id):
			continue
		var count: int = int(_estate_buildings(state).get(building_id, 0))
		if count <= 0:
			continue
		rows.append(housing_building_view_data(state, building_id))

	return rows


func get_housing_mothball_data(state: Node) -> Dictionary:
	return {"summary": get_housing_summary(state), "rows": get_housing_mothball_rows(state)}


func pay_housing_maintenance(state: Node) -> Array[Dictionary]:
	var payments: Array[Dictionary] = []
	var maintenance: Dictionary = estimate_housing_maintenance(state)
	var estate_stockpiles: Dictionary = _estate_stockpiles(state)

	for resource_variant: Variant in maintenance.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(maintenance[resource_variant])
		var available: float = float(estate_stockpiles.get(resource_id, 0.0))
		var paid: float = minf(available, needed)
		estate_stockpiles[resource_id] = maxf(0.0, available - paid)
		payments.append({
			"resource_id": resource_id,
			"needed": needed,
			"paid": paid,
			"shortfall": maxf(0.0, needed - paid)
		})

	_set_estate_stockpiles(state, estate_stockpiles)
	return payments


func labour_group_name(group_id: String) -> String:
	match group_id:
		"macehualtin":
			return "Macehualtin Field Labour"
		"tlacotin":
			return "Tlacotin Bonded Labour"
		"tolteca":
			return "Tolteca Artisans"
		"yaotequihuaqueh":
			return "Warriors"
		"tlamacazqueh":
			return "Priests"
		"pipiltin":
			return "Nobles"
		"malli":
			return "Captives"
	return group_id.capitalize()


func _clear_active_population_cache() -> void:
	_active_population_cache_token = ""
	_active_population_cache.clear()


func _active_population_cache_key(state: Node) -> String:
	if state == null:
		return ""
	var population: Dictionary = _population(state)
	var active_counts: Dictionary = _active_housing_counts(state)
	var estate_buildings: Dictionary = _estate_buildings(state)
	var base_capacity: Dictionary = _base_housing_capacity(state)
	return str(population.hash()) + "|" + str(active_counts.hash()) + "|" + str(estate_buildings.hash()) + "|" + str(base_capacity.hash())


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
		"population":
			if runtime_state.has_method("get_population_copy"):
				return runtime_state.call("get_population_copy") as Dictionary
		"base_housing_capacity":
			if runtime_state.has_method("get_base_housing_capacity_copy"):
				return runtime_state.call("get_base_housing_capacity_copy") as Dictionary
		"estate_stockpiles":
			if runtime_state.has_method("get_estate_stockpiles_copy"):
				return runtime_state.call("get_estate_stockpiles_copy") as Dictionary
	return {}

func _buildings(state: Node) -> Dictionary:
	return _dictionary_from_campaign_state(state, "buildings")


func _building_order(state: Node) -> Array[String]:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_building_order_copy"):
		return runtime_state.call("get_building_order_copy") as Array[String]
	return []


func _estate_buildings(state: Node) -> Dictionary:
	return _dictionary_from_campaign_state(state, "estate_buildings")


func _active_housing_counts(state: Node) -> Dictionary:
	return _dictionary_from_campaign_state(state, "active_housing_counts")


func _population(state: Node) -> Dictionary:
	return _dictionary_from_campaign_state(state, "population")


func _base_housing_capacity(state: Node) -> Dictionary:
	return _dictionary_from_campaign_state(state, "base_housing_capacity")


func _estate_stockpiles(state: Node) -> Dictionary:
	return _dictionary_from_campaign_state(state, "estate_stockpiles")


func _set_base_housing_capacity(state: Node, values: Dictionary) -> void:
	_clear_active_population_cache()
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("set_base_housing_capacity_values"):
		runtime_state.call("set_base_housing_capacity_values", values)
		return


func _set_active_housing_counts(state: Node, values: Dictionary) -> void:
	_clear_active_population_cache()
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		for building_variant: Variant in values.keys():
			var building_id: String = String(building_variant)
			if runtime_state.has_method("set_active_housing_count_value"):
				runtime_state.call("set_active_housing_count_value", building_id, int(values[building_variant]))
			else:
				return
		return


func _set_estate_stockpiles(state: Node, values: Dictionary) -> void:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("set_estate_stockpiles_values"):
		runtime_state.call("set_estate_stockpiles_values", values)
		return


func _multiply_dictionary(values: Dictionary, multiplier: int) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		output[key] = float(values[key_variant]) * float(multiplier)
	return output


func _dictionary_to_named_string(state: Node, values: Dictionary, suffix: String = "") -> String:
	if values.is_empty():
		return "none"

	var parts: Array[String] = []
	for key_variant: Variant in values.keys():
		var resource_id: String = String(key_variant)
		var amount: String = _format_amount(float(values[key_variant]))
		var name: String = resource_id.capitalize()
		if state != null and state.has_method("get_resource_name"):
			name = String(state.call("get_resource_name", resource_id))
		var piece: String = name + " " + amount
		if suffix != "":
			piece += " " + suffix
		parts.append(piece)

	return ", ".join(parts)


func _format_amount(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))
