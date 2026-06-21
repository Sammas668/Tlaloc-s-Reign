# CampaignState.gd
# Godot 4.x
# Project path: res://Scripts/state/CampaignState.gd
#
# CampaignState is the live campaign/save-data owner.
# It intentionally contains state containers, data-shaping helpers, start-state
# loading and save/load helpers, but not gameplay rules.
#
# TRGameState remains the public runtime facade. Systems should read/write live
# campaign data through this object or through explicit CampaignState bridges,
# while UI continues to call TRGameState public methods.

class_name CampaignState
extends RefCounted

const SCHEMA_VERSION: String = "campaign_state_v0_47_5_patch_8e"

# -----------------------------------------------------------------------------
# Calendar / report / summary state
# -----------------------------------------------------------------------------

var current_veintena: int = 1
var calendar_period: String = "veintena" # "veintena" or "nemontemi"
var ritual_year: int = 1
var last_report: Array[String] = []
var last_turn_summary: Dictionary = {}
var initialized: bool = false

# -----------------------------------------------------------------------------
# Static-data-derived live dictionaries
# -----------------------------------------------------------------------------

var resources: Dictionary = {}
var resource_order: Array[String] = []
var buildings: Dictionary = {}
var building_order: Array[String] = []

# -----------------------------------------------------------------------------
# Economy / estate live state
# -----------------------------------------------------------------------------

var estate_stockpiles: Dictionary = {}
var market_stockpiles: Dictionary = {}
var market_demand: Dictionary = {}
var market_economy: Dictionary = {}

var estate_buildings: Dictionary = {}
var active_housing_counts: Dictionary = {}
var population: Dictionary = {}
var base_housing_capacity: Dictionary = {}
var labour_assignments: Dictionary = {}

# -----------------------------------------------------------------------------
# Palace / prestige / religion live state
# -----------------------------------------------------------------------------

var player_palace_dedicated_god: String = ""
var palace_built_structures: Dictionary = {}
var palace_structure_runtime_statuses: Dictionary = {}
var palace_delivered_ruler_demands: Dictionary = {} # Legacy compatibility only.
var palace_ruler_demand_donations: Array[Dictionary] = []
var last_palace_maintenance_report: Array[String] = []

var player_prestige: float = 0.0
var rival_prestige: Dictionary = {}
var prestige_history: Array[Dictionary] = []
var sacrifice_prestige_records: Array[Dictionary] = []

# Serialisable religion-state container.
# ReligionStateSystem instances bind to this dictionary and write back after
# mutation. This is now the save/load-facing home for shrine levels, divine
# favour, ritual capacity and recent offering reports.
var religion_state: Dictionary = {}

# -----------------------------------------------------------------------------
# War / Flower War / Rival live state
# -----------------------------------------------------------------------------

var flower_war_palace_gate_enabled: bool = true
var last_flower_war_report: Dictionary = {}
var flower_war_report_archive: Array[Dictionary] = []
var warbands: Dictionary = {}

# Rival Prototype 1 scaffold containers.
var rival_houses: Dictionary = {}
var rival_stockpiles: Dictionary = {}
var rival_build_progress: Dictionary = {}
var rival_action_history: Array[Dictionary] = []

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

func reset_runtime_state() -> void:
	current_veintena = 1
	calendar_period = "veintena"
	ritual_year = 1
	last_report.clear()
	last_turn_summary.clear()
	initialized = false

	resources.clear()
	resource_order.clear()
	buildings.clear()
	building_order.clear()

	estate_stockpiles.clear()
	market_stockpiles.clear()
	market_demand.clear()
	market_economy.clear()

	estate_buildings.clear()
	active_housing_counts.clear()
	population.clear()
	base_housing_capacity.clear()
	labour_assignments.clear()

	player_palace_dedicated_god = ""
	palace_built_structures.clear()
	palace_structure_runtime_statuses.clear()
	palace_delivered_ruler_demands.clear()
	palace_ruler_demand_donations.clear()
	last_palace_maintenance_report.clear()

	player_prestige = 0.0
	rival_prestige.clear()
	prestige_history.clear()
	sacrifice_prestige_records.clear()
	religion_state.clear()

	flower_war_palace_gate_enabled = true
	last_flower_war_report.clear()
	flower_war_report_archive.clear()
	warbands.clear()

	rival_houses.clear()
	rival_stockpiles.clear()
	rival_build_progress.clear()
	rival_action_history.clear()

func load_static_definitions(new_resources: Dictionary, new_resource_order: Array[String], new_buildings: Dictionary, new_building_order: Array[String], new_market_economy: Dictionary) -> void:
	resources = _duplicate_dictionary(new_resources)
	resource_order = new_resource_order.duplicate()
	buildings = _duplicate_dictionary(new_buildings)
	building_order = new_building_order.duplicate()
	market_economy = _duplicate_dictionary(new_market_economy)

func load_start_state(start_data: Dictionary) -> void:
	current_veintena = int(start_data.get("current_veintena", 1))
	calendar_period = String(start_data.get("calendar_period", "veintena"))
	ritual_year = int(start_data.get("ritual_year", 1))
	estate_stockpiles = _float_dictionary(_dictionary_from_variant(start_data.get("estate_stockpiles", {})))
	market_stockpiles = _float_dictionary(_dictionary_from_variant(start_data.get("market_stockpiles", {})))
	market_demand = _float_dictionary(_dictionary_from_variant(start_data.get("market_demand", {})))
	estate_buildings = _int_dictionary(_dictionary_from_variant(start_data.get("estate_buildings", {})))
	active_housing_counts = _int_dictionary(_dictionary_from_variant(start_data.get("active_housing_counts", {})))
	population = _int_dictionary(_dictionary_from_variant(start_data.get("population", {})))
	base_housing_capacity = _int_dictionary(_dictionary_from_variant(start_data.get("base_housing_capacity", {})))
	labour_assignments = _nested_int_dictionary(_dictionary_from_variant(start_data.get("labour_assignments", {})))
	religion_state = _duplicate_dictionary(_dictionary_from_variant(start_data.get("religion_state", {})))
	rival_houses = _duplicate_dictionary(_dictionary_from_variant(start_data.get("rival_houses", {})))
	rival_stockpiles = _duplicate_dictionary(_dictionary_from_variant(start_data.get("rival_stockpiles", {})))
	rival_build_progress = _duplicate_dictionary(_dictionary_from_variant(start_data.get("rival_build_progress", {})))
	ensure_all_resource_keys()
	ensure_all_building_keys()

func ensure_all_resource_keys() -> void:
	for resource_id: String in resource_order:
		if not estate_stockpiles.has(resource_id):
			estate_stockpiles[resource_id] = 0.0
		if not market_stockpiles.has(resource_id):
			market_stockpiles[resource_id] = 0.0
		if not market_demand.has(resource_id):
			market_demand[resource_id] = 0.0

func ensure_all_building_keys() -> void:
	for building_id: String in building_order:
		if not estate_buildings.has(building_id):
			estate_buildings[building_id] = 0

# -----------------------------------------------------------------------------
# Project-data loading helpers
# -----------------------------------------------------------------------------

func load_project_data_from_paths(resource_path: String, building_path: String, start_state_path: String, market_economy_path: String) -> Dictionary:
	reset_runtime_state()
	var warnings: Array[String] = []
	var resource_data: Dictionary = _load_json_dictionary(resource_path, warnings)
	var building_data: Dictionary = _load_json_dictionary(building_path, warnings)
	var market_data: Dictionary = _load_json_dictionary(market_economy_path, warnings)
	var start_data: Dictionary = _load_json_dictionary(start_state_path, warnings)
	_load_resource_definitions_from_data(resource_data)
	_load_building_definitions_from_data(building_data)
	market_economy = _duplicate_dictionary(market_data)
	load_start_state(start_data)
	return {
		"schema_version": "campaign_state_project_data_load_v0_47_5_patch_8e",
		"ok": warnings.is_empty(),
		"warnings": warnings,
		"resource_count": resources.size(),
		"building_count": buildings.size(),
		"market_economy_loaded": not market_economy.is_empty(),
		"start_state_loaded": not start_data.is_empty()
	}

func _load_json_dictionary(path: String, warnings: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		warnings.append("Missing data file: " + path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		warnings.append("Could not open data file: " + path)
		return {}
	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		return parsed as Dictionary
	warnings.append("Data file did not parse as Dictionary: " + path)
	return {}

func _load_resource_definitions_from_data(data: Dictionary) -> void:
	resources.clear()
	resource_order.clear()
	var rows: Array = data.get("resources", []) as Array
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		var resource_id: String = String(row.get("id", ""))
		if resource_id == "":
			continue
		resources[resource_id] = row
		resource_order.append(resource_id)

func _load_building_definitions_from_data(data: Dictionary) -> void:
	buildings.clear()
	building_order.clear()
	var rows: Array = data.get("buildings", []) as Array
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
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

# -----------------------------------------------------------------------------
# TRGameState bridge helpers
# -----------------------------------------------------------------------------

func copy_from_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	resources = _get_dictionary(game_state, "resources")
	resource_order = _get_string_array(game_state, "resource_order")
	buildings = _get_dictionary(game_state, "buildings")
	building_order = _get_string_array(game_state, "building_order")

	estate_stockpiles = _get_dictionary(game_state, "estate_stockpiles")
	market_stockpiles = _get_dictionary(game_state, "market_stockpiles")
	market_demand = _get_dictionary(game_state, "market_demand")
	market_economy = _get_dictionary(game_state, "market_economy")

	estate_buildings = _get_dictionary(game_state, "estate_buildings")
	active_housing_counts = _get_dictionary(game_state, "active_housing_counts")
	population = _get_dictionary(game_state, "population")
	base_housing_capacity = _get_dictionary(game_state, "base_housing_capacity")
	labour_assignments = _get_dictionary(game_state, "labour_assignments")

	current_veintena = int(_node_get_default(game_state, "current_veintena", 1))
	calendar_period = String(_node_get_default(game_state, "calendar_period", calendar_period))
	ritual_year = int(_node_get_default(game_state, "ritual_year", ritual_year))
	last_report = _get_string_array(game_state, "last_report")
	last_turn_summary = _get_dictionary(game_state, "last_turn_summary")
	initialized = bool(_node_get_default(game_state, "initialized", false))

	player_palace_dedicated_god = String(_node_get_default(game_state, "player_palace_dedicated_god", ""))
	palace_built_structures = _get_dictionary(game_state, "palace_built_structures")
	palace_structure_runtime_statuses = _get_dictionary(game_state, "palace_structure_runtime_statuses")
	palace_delivered_ruler_demands = _get_dictionary(game_state, "palace_delivered_ruler_demands")
	palace_ruler_demand_donations = _get_dictionary_array(game_state, "palace_ruler_demand_donations")
	last_palace_maintenance_report = _get_string_array(game_state, "last_palace_maintenance_report")

	player_prestige = float(_node_get_default(game_state, "player_prestige", 0.0))
	rival_prestige = _get_dictionary(game_state, "rival_prestige")
	prestige_history = _get_dictionary_array(game_state, "prestige_history")
	sacrifice_prestige_records = _get_dictionary_array(game_state, "sacrifice_prestige_records")
	religion_state = _get_dictionary(game_state, "religion_state")

	flower_war_palace_gate_enabled = bool(_node_get_default(game_state, "flower_war_palace_gate_enabled", true))
	last_flower_war_report = _get_dictionary(game_state, "last_flower_war_report")
	flower_war_report_archive = _get_dictionary_array(game_state, "flower_war_report_archive")
	warbands = _get_dictionary(game_state, "warbands")

	rival_houses = _get_dictionary(game_state, "rival_houses")
	rival_stockpiles = _get_dictionary(game_state, "rival_stockpiles")
	rival_build_progress = _get_dictionary(game_state, "rival_build_progress")
	rival_action_history = _get_dictionary_array(game_state, "rival_action_history")

func apply_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("resources", _duplicate_dictionary(resources))
	game_state.set("resource_order", resource_order.duplicate())
	game_state.set("buildings", _duplicate_dictionary(buildings))
	game_state.set("building_order", building_order.duplicate())

	game_state.set("estate_stockpiles", _duplicate_dictionary(estate_stockpiles))
	game_state.set("market_stockpiles", _duplicate_dictionary(market_stockpiles))
	game_state.set("market_demand", _duplicate_dictionary(market_demand))
	game_state.set("market_economy", _duplicate_dictionary(market_economy))

	game_state.set("estate_buildings", _duplicate_dictionary(estate_buildings))
	game_state.set("active_housing_counts", _duplicate_dictionary(active_housing_counts))
	game_state.set("population", _duplicate_dictionary(population))
	game_state.set("base_housing_capacity", _duplicate_dictionary(base_housing_capacity))
	game_state.set("labour_assignments", _duplicate_dictionary(labour_assignments))

	game_state.set("current_veintena", current_veintena)
	game_state.set("last_report", last_report.duplicate())
	game_state.set("initialized", initialized)

	# These properties may not exist as legacy fields yet; they are safe future
	# compatibility writes for the CampaignState migration.
	game_state.set("calendar_period", calendar_period)
	game_state.set("ritual_year", ritual_year)
	game_state.set("last_turn_summary", _duplicate_dictionary(last_turn_summary))
	mirror_religion_state_to_game_state(game_state)
	game_state.set("rival_houses", _duplicate_dictionary(rival_houses))
	game_state.set("rival_stockpiles", _duplicate_dictionary(rival_stockpiles))
	game_state.set("rival_build_progress", _duplicate_dictionary(rival_build_progress))
	game_state.set("rival_action_history", _duplicate_dictionary_array(rival_action_history))

	game_state.set("player_palace_dedicated_god", player_palace_dedicated_god)
	game_state.set("palace_built_structures", _duplicate_dictionary(palace_built_structures))
	game_state.set("palace_structure_runtime_statuses", _duplicate_dictionary(palace_structure_runtime_statuses))
	game_state.set("palace_delivered_ruler_demands", _duplicate_dictionary(palace_delivered_ruler_demands))
	game_state.set("palace_ruler_demand_donations", _duplicate_dictionary_array(palace_ruler_demand_donations))
	game_state.set("last_palace_maintenance_report", last_palace_maintenance_report.duplicate())

	game_state.set("player_prestige", player_prestige)
	game_state.set("rival_prestige", _duplicate_dictionary(rival_prestige))
	game_state.set("prestige_history", _duplicate_dictionary_array(prestige_history))
	game_state.set("sacrifice_prestige_records", _duplicate_dictionary_array(sacrifice_prestige_records))

	game_state.set("flower_war_palace_gate_enabled", flower_war_palace_gate_enabled)
	game_state.set("last_flower_war_report", _duplicate_dictionary(last_flower_war_report))
	game_state.set("flower_war_report_archive", _duplicate_dictionary_array(flower_war_report_archive))
	game_state.set("warbands", _duplicate_dictionary(warbands))

# -----------------------------------------------------------------------------
# Stockpile access helpers
# -----------------------------------------------------------------------------

func get_estate_stockpiles_copy() -> Dictionary:
	return _duplicate_dictionary(estate_stockpiles)

func set_estate_stockpiles_values(values: Dictionary) -> void:
	estate_stockpiles = _float_dictionary(values)
	ensure_all_resource_keys()

func get_market_stockpiles_copy() -> Dictionary:
	return _duplicate_dictionary(market_stockpiles)

func set_market_stockpiles_values(values: Dictionary) -> void:
	market_stockpiles = _float_dictionary(values)
	ensure_all_resource_keys()

func seed_stockpiles_from_game_state_if_empty(game_state: Node) -> void:
	if game_state == null:
		return
	if estate_stockpiles.is_empty():
		estate_stockpiles = _float_dictionary(_get_dictionary(game_state, "estate_stockpiles"))
	if market_stockpiles.is_empty():
		market_stockpiles = _float_dictionary(_get_dictionary(game_state, "market_stockpiles"))
	ensure_all_resource_keys()

func get_estate_stock(resource_id: String) -> float:
	return float(estate_stockpiles.get(resource_id, 0.0))

func set_estate_stock(resource_id: String, amount: float) -> float:
	var value: float = maxf(0.0, amount)
	estate_stockpiles[resource_id] = value
	return value

func add_estate_stock(resource_id: String, amount: float) -> float:
	return set_estate_stock(resource_id, get_estate_stock(resource_id) + amount)

func get_market_stock(resource_id: String) -> float:
	return float(market_stockpiles.get(resource_id, 0.0))

func set_market_stock(resource_id: String, amount: float) -> float:
	var value: float = maxf(0.0, amount)
	market_stockpiles[resource_id] = value
	return value

func add_market_stock(resource_id: String, amount: float) -> float:
	return set_market_stock(resource_id, get_market_stock(resource_id) + amount)

func mirror_stockpiles_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("estate_stockpiles", _duplicate_dictionary(estate_stockpiles))
	game_state.set("market_stockpiles", _duplicate_dictionary(market_stockpiles))

# -----------------------------------------------------------------------------
# Calendar / report / summary access helpers
# -----------------------------------------------------------------------------

func get_current_veintena_value() -> int:
	return current_veintena

func set_current_veintena(value: int) -> int:
	current_veintena = maxi(1, value)
	return current_veintena

func get_calendar_period_value() -> String:
	return calendar_period

func set_calendar_period_value(value: String) -> String:
	var cleaned: String = value.strip_edges().to_lower()
	if cleaned != "nemontemi":
		cleaned = "veintena"
	calendar_period = cleaned
	return calendar_period

func get_ritual_year_value() -> int:
	return ritual_year

func set_ritual_year_value(value: int) -> int:
	ritual_year = maxi(1, value)
	return ritual_year

func set_initialized(value: bool) -> void:
	initialized = value

func get_last_report_copy() -> Array[String]:
	var output: Array[String] = []
	for line_variant: Variant in last_report:
		output.append(String(line_variant))
	return output

func set_last_report(lines: Array) -> void:
	last_report = _string_array_from_variant(lines)

func clear_last_report() -> void:
	last_report.clear()

func append_report_line(line: String) -> void:
	if line.strip_edges() == "":
		return
	last_report.append(line)

func get_last_turn_summary_copy() -> Dictionary:
	return _duplicate_dictionary(last_turn_summary)

func set_last_turn_summary(summary: Dictionary) -> void:
	last_turn_summary = _duplicate_dictionary(summary)

func clear_last_turn_summary() -> void:
	last_turn_summary.clear()

func ensure_turn_summary_sections(section_ids: Array[String]) -> void:
	for section_id: String in section_ids:
		if not last_turn_summary.has(section_id) or not (last_turn_summary[section_id] is Array):
			last_turn_summary[section_id] = []

func append_turn_summary_entry(section_id: String, entry: Dictionary) -> void:
	if not last_turn_summary.has(section_id) or not (last_turn_summary[section_id] is Array):
		last_turn_summary[section_id] = []
	var rows: Array = last_turn_summary[section_id] as Array
	rows.append(entry.duplicate(true))
	last_turn_summary[section_id] = rows

func mirror_calendar_report_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("current_veintena", current_veintena)
	game_state.set("last_report", last_report.duplicate())
	game_state.set("initialized", initialized)
	game_state.set("calendar_period", calendar_period)
	game_state.set("ritual_year", ritual_year)
	game_state.set("last_turn_summary", _duplicate_dictionary(last_turn_summary))

# -----------------------------------------------------------------------------
# Prestige access helpers
# -----------------------------------------------------------------------------

func get_player_prestige_value() -> float:
	return player_prestige

func set_player_prestige_value(value: float) -> float:
	player_prestige = maxf(0.0, value)
	return player_prestige

func add_player_prestige_record(amount: float, source_id: String, detail: String, context: Dictionary = {}, veintena: int = 1) -> Dictionary:
	if absf(amount) <= 0.0001:
		return {"ok": true, "amount": 0.0, "prestige": player_prestige}
	var before: float = player_prestige
	player_prestige = maxf(0.0, player_prestige + amount)
	var record: Dictionary = {
		"veintena": veintena,
		"source_id": source_id,
		"detail": detail,
		"amount": amount,
		"prestige_before": before,
		"prestige_after": player_prestige,
		"context": context.duplicate(true)
	}
	prestige_history.append(record)
	return {"ok": true, "amount": amount, "prestige": player_prestige, "record": record}

func get_prestige_history_copy() -> Array[Dictionary]:
	return _duplicate_dictionary_array(prestige_history)

func set_prestige_history_records(records: Array) -> void:
	prestige_history = _duplicate_dictionary_array(records)

func clear_prestige_history() -> void:
	prestige_history.clear()

func set_rival_prestige_values(values: Dictionary) -> Dictionary:
	rival_prestige = _duplicate_dictionary(values)
	return rival_prestige.duplicate(true)

func get_rival_prestige_copy() -> Dictionary:
	return _duplicate_dictionary(rival_prestige)

func set_rival_prestige_value(house_id: String, value: float) -> Dictionary:
	rival_prestige[house_id] = maxf(0.0, value)
	return {"ok": true, "house_id": house_id, "prestige": float(rival_prestige.get(house_id, 0.0))}

func get_sacrifice_prestige_records_copy() -> Array[Dictionary]:
	return _duplicate_dictionary_array(sacrifice_prestige_records)

func set_sacrifice_prestige_records(records: Array) -> void:
	sacrifice_prestige_records = _duplicate_dictionary_array(records)

func append_sacrifice_prestige_record(record: Dictionary) -> void:
	sacrifice_prestige_records.append(record.duplicate(true))

func clear_sacrifice_prestige_records() -> void:
	sacrifice_prestige_records.clear()

func mirror_prestige_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("player_prestige", player_prestige)
	game_state.set("rival_prestige", _duplicate_dictionary(rival_prestige))
	game_state.set("prestige_history", _duplicate_dictionary_array(prestige_history))
	game_state.set("sacrifice_prestige_records", _duplicate_dictionary_array(sacrifice_prestige_records))

# -----------------------------------------------------------------------------
# Palace state access helpers
# -----------------------------------------------------------------------------

func get_palace_dedicated_god_value() -> String:
	return player_palace_dedicated_god

func set_palace_dedicated_god_value(god_id: String) -> String:
	player_palace_dedicated_god = god_id.strip_edges().to_lower()
	return player_palace_dedicated_god

func clear_palace_state() -> void:
	player_palace_dedicated_god = ""
	palace_built_structures.clear()
	palace_structure_runtime_statuses.clear()
	palace_delivered_ruler_demands.clear()
	palace_ruler_demand_donations.clear()
	last_palace_maintenance_report.clear()

func get_palace_built_structures_copy() -> Dictionary:
	return _duplicate_dictionary(palace_built_structures)

func set_palace_built_structures(value: Dictionary) -> void:
	palace_built_structures = _duplicate_dictionary(value)

func clear_palace_built_structures() -> void:
	palace_built_structures.clear()

func is_palace_structure_built(structure_id: String) -> bool:
	return bool(palace_built_structures.get(structure_id, false))

func mark_palace_structure_built(structure_id: String) -> void:
	if structure_id.strip_edges() == "":
		return
	palace_built_structures[structure_id] = true

func get_palace_structure_runtime_statuses_copy() -> Dictionary:
	return _duplicate_dictionary(palace_structure_runtime_statuses)

func set_palace_structure_runtime_statuses(value: Dictionary) -> void:
	palace_structure_runtime_statuses = _duplicate_dictionary(value)

func clear_palace_structure_runtime_statuses() -> void:
	palace_structure_runtime_statuses.clear()

func get_palace_delivered_ruler_demands_copy() -> Dictionary:
	return _duplicate_dictionary(palace_delivered_ruler_demands)

func set_palace_delivered_ruler_demands(value: Dictionary) -> void:
	palace_delivered_ruler_demands = _duplicate_dictionary(value)

func clear_palace_delivered_ruler_demands() -> void:
	palace_delivered_ruler_demands.clear()

func get_palace_ruler_demand_donations_copy() -> Array[Dictionary]:
	return _duplicate_dictionary_array(palace_ruler_demand_donations)

func set_palace_ruler_demand_donations(value: Array) -> void:
	palace_ruler_demand_donations = _duplicate_dictionary_array(value)

func append_palace_ruler_demand_donation(record: Dictionary) -> void:
	palace_ruler_demand_donations.append(record.duplicate(true))

func get_last_palace_maintenance_report_copy() -> Array[String]:
	return _string_array_from_variant(last_palace_maintenance_report)

func set_last_palace_maintenance_report(lines: Array) -> void:
	last_palace_maintenance_report = _string_array_from_variant(lines)

func get_flower_war_palace_gate_enabled_value() -> bool:
	return flower_war_palace_gate_enabled

func set_flower_war_palace_gate_enabled_value(enabled: bool) -> void:
	flower_war_palace_gate_enabled = enabled

func capture_palace_state_from_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	player_palace_dedicated_god = String(_node_get_default(game_state, "player_palace_dedicated_god", ""))
	palace_built_structures = _get_dictionary(game_state, "palace_built_structures")
	palace_structure_runtime_statuses = _get_dictionary(game_state, "palace_structure_runtime_statuses")
	palace_delivered_ruler_demands = _get_dictionary(game_state, "palace_delivered_ruler_demands")
	palace_ruler_demand_donations = _get_dictionary_array(game_state, "palace_ruler_demand_donations")
	last_palace_maintenance_report = _get_string_array(game_state, "last_palace_maintenance_report")
	flower_war_palace_gate_enabled = bool(_node_get_default(game_state, "flower_war_palace_gate_enabled", true))

func mirror_palace_state_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("player_palace_dedicated_god", player_palace_dedicated_god)
	game_state.set("palace_built_structures", _duplicate_dictionary(palace_built_structures))
	game_state.set("palace_structure_runtime_statuses", _duplicate_dictionary(palace_structure_runtime_statuses))
	game_state.set("palace_delivered_ruler_demands", _duplicate_dictionary(palace_delivered_ruler_demands))
	game_state.set("palace_ruler_demand_donations", _duplicate_dictionary_array(palace_ruler_demand_donations))
	game_state.set("last_palace_maintenance_report", last_palace_maintenance_report.duplicate())
	game_state.set("flower_war_palace_gate_enabled", flower_war_palace_gate_enabled)

# -----------------------------------------------------------------------------
# Religion state scaffold helpers
# -----------------------------------------------------------------------------

func get_religion_state_copy() -> Dictionary:
	return _duplicate_dictionary(religion_state)

func set_religion_state(value: Dictionary) -> void:
	religion_state = _duplicate_dictionary(value)

func merge_religion_state(value: Dictionary) -> void:
	for key_variant: Variant in value.keys():
		religion_state[String(key_variant)] = value[key_variant]

func clear_religion_state() -> void:
	religion_state.clear()

func set_religion_value(key: String, value: Variant) -> void:
	religion_state[key] = value

func get_religion_value(key: String, default_value: Variant = null) -> Variant:
	return religion_state.get(key, default_value)

func mirror_religion_state_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	var copy: Dictionary = _duplicate_dictionary(religion_state)
	game_state.set_meta("religion_state", copy)
	if game_state.get("religion_state") != null:
		game_state.set("religion_state", copy)

# -----------------------------------------------------------------------------
# Population / buildings / housing state access helpers
# -----------------------------------------------------------------------------

func get_population_copy() -> Dictionary:
	return _duplicate_dictionary(population)

func get_population_count(group_id: String) -> int:
	return int(population.get(group_id, 0))

func set_population_count(group_id: String, amount: int) -> int:
	var value: int = max(0, amount)
	population[group_id] = value
	return value

func add_population_count(group_id: String, amount: int) -> int:
	return set_population_count(group_id, get_population_count(group_id) + amount)

func get_estate_buildings_copy() -> Dictionary:
	return _duplicate_dictionary(estate_buildings)

func get_estate_building_count(building_id: String) -> int:
	return int(estate_buildings.get(building_id, 0))

func set_estate_building_count(building_id: String, amount: int) -> int:
	var value: int = max(0, amount)
	estate_buildings[building_id] = value
	return value

func add_estate_building_count(building_id: String, amount: int) -> int:
	return set_estate_building_count(building_id, get_estate_building_count(building_id) + amount)

func get_active_housing_counts_copy() -> Dictionary:
	return _duplicate_dictionary(active_housing_counts)

func get_active_housing_count(building_id: String) -> int:
	return int(active_housing_counts.get(building_id, 0))

func set_active_housing_count_value(building_id: String, amount: int) -> int:
	var built_count: int = get_estate_building_count(building_id)
	var value: int = clampi(amount, 0, built_count)
	active_housing_counts[building_id] = value
	return value

func get_base_housing_capacity_copy() -> Dictionary:
	return _duplicate_dictionary(base_housing_capacity)

func set_base_housing_capacity_values(values: Dictionary) -> void:
	base_housing_capacity = _int_dictionary(values)

func set_base_housing_capacity_value(group_id: String, amount: int) -> int:
	var value: int = max(0, amount)
	base_housing_capacity[group_id] = value
	return value

func get_labour_assignments_copy() -> Dictionary:
	return _duplicate_dictionary(labour_assignments)

func get_labour_assignment_for_building(building_id: String) -> Dictionary:
	var value: Variant = labour_assignments.get(building_id, {})
	if value is Dictionary:
		return _duplicate_dictionary(value as Dictionary)
	return {}

func set_labour_assignments_values(values: Dictionary) -> void:
	labour_assignments = _duplicate_dictionary(values)

func set_labour_assignment_for_building(building_id: String, assignments: Dictionary) -> void:
	labour_assignments[building_id] = _duplicate_dictionary(assignments)

func clear_labour_assignment_for_building(building_id: String) -> void:
	labour_assignments.erase(building_id)

func mirror_population_building_housing_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("population", _duplicate_dictionary(population))
	game_state.set("estate_buildings", _duplicate_dictionary(estate_buildings))
	game_state.set("active_housing_counts", _duplicate_dictionary(active_housing_counts))
	game_state.set("base_housing_capacity", _duplicate_dictionary(base_housing_capacity))
	game_state.set("labour_assignments", _duplicate_dictionary(labour_assignments))

# -----------------------------------------------------------------------------
# Warband / Flower War report state access helpers
# -----------------------------------------------------------------------------

func get_warbands_copy() -> Dictionary:
	return _duplicate_dictionary(warbands)

func set_warbands_values(values: Dictionary) -> void:
	warbands = _duplicate_dictionary(values)

func has_warband(warband_id: String) -> bool:
	return warbands.has(warband_id)

func get_warband_copy(warband_id: String) -> Dictionary:
	var value: Variant = warbands.get(warband_id, {})
	if value is Dictionary:
		return _duplicate_dictionary(value as Dictionary)
	return {}

func set_warband_value(warband_id: String, warband: Dictionary) -> void:
	if warband_id == "":
		return
	warbands[warband_id] = _duplicate_dictionary(warband)

func erase_warband(warband_id: String) -> void:
	warbands.erase(warband_id)

func clear_warbands() -> void:
	warbands.clear()

func get_last_flower_war_report_copy() -> Dictionary:
	return _duplicate_dictionary(last_flower_war_report)

func set_last_flower_war_report(report: Dictionary) -> void:
	last_flower_war_report = _duplicate_dictionary(report)

func clear_last_flower_war_report() -> void:
	last_flower_war_report.clear()

func get_flower_war_report_archive_copy() -> Array[Dictionary]:
	return _duplicate_dictionary_array(flower_war_report_archive)

func get_flower_war_report_archive_count() -> int:
	return flower_war_report_archive.size()

func set_flower_war_report_archive(values: Array) -> void:
	flower_war_report_archive = _duplicate_dictionary_array(values)

func append_flower_war_report_archive(report: Dictionary, max_entries: int = 20) -> void:
	if report.is_empty():
		return
	flower_war_report_archive.append(_duplicate_dictionary(report))
	var cap: int = max(0, max_entries)
	if cap <= 0:
		return
	while flower_war_report_archive.size() > cap:
		flower_war_report_archive.pop_front()

func clear_flower_war_report_archive() -> void:
	flower_war_report_archive.clear()

func mirror_warband_flower_war_state_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("warbands", _duplicate_dictionary(warbands))
	game_state.set("last_flower_war_report", _duplicate_dictionary(last_flower_war_report))
	game_state.set("flower_war_report_archive", _duplicate_dictionary_array(flower_war_report_archive))

# -----------------------------------------------------------------------------
# Rival scaffold helpers
# -----------------------------------------------------------------------------

func get_rival_houses_copy() -> Dictionary:
	return _duplicate_dictionary(rival_houses)

func set_rival_houses_values(values: Dictionary) -> void:
	rival_houses = _duplicate_dictionary(values)

func get_rival_stockpiles_copy() -> Dictionary:
	return _duplicate_dictionary(rival_stockpiles)

func set_rival_stockpiles_values(values: Dictionary) -> void:
	rival_stockpiles = _duplicate_dictionary(values)

func get_rival_build_progress_copy() -> Dictionary:
	return _duplicate_dictionary(rival_build_progress)

func set_rival_build_progress_values(values: Dictionary) -> void:
	rival_build_progress = _duplicate_dictionary(values)

func get_rival_action_history_copy() -> Array[Dictionary]:
	return _duplicate_dictionary_array(rival_action_history)

func set_rival_action_history_values(values: Array) -> void:
	rival_action_history = _duplicate_dictionary_array(values)

func append_rival_action(record: Dictionary, max_entries: int = 40) -> void:
	if record.is_empty():
		return
	rival_action_history.append(record.duplicate(true))
	while max_entries > 0 and rival_action_history.size() > max_entries:
		rival_action_history.pop_front()

func mirror_rival_state_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("rival_houses", _duplicate_dictionary(rival_houses))
	game_state.set("rival_stockpiles", _duplicate_dictionary(rival_stockpiles))
	game_state.set("rival_build_progress", _duplicate_dictionary(rival_build_progress))
	game_state.set("rival_action_history", _duplicate_dictionary_array(rival_action_history))

# -----------------------------------------------------------------------------
# Save/load-facing helpers
# -----------------------------------------------------------------------------

func to_save_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"current_veintena": current_veintena,
		"calendar_period": calendar_period,
		"ritual_year": ritual_year,
		"last_report": last_report.duplicate(),
		"last_turn_summary": _duplicate_dictionary(last_turn_summary),
		"initialized": initialized,

		"estate_stockpiles": _duplicate_dictionary(estate_stockpiles),
		"market_stockpiles": _duplicate_dictionary(market_stockpiles),
		"market_demand": _duplicate_dictionary(market_demand),
		"estate_buildings": _duplicate_dictionary(estate_buildings),
		"active_housing_counts": _duplicate_dictionary(active_housing_counts),
		"population": _duplicate_dictionary(population),
		"base_housing_capacity": _duplicate_dictionary(base_housing_capacity),
		"labour_assignments": _duplicate_dictionary(labour_assignments),

		"player_palace_dedicated_god": player_palace_dedicated_god,
		"palace_built_structures": _duplicate_dictionary(palace_built_structures),
		"palace_structure_runtime_statuses": _duplicate_dictionary(palace_structure_runtime_statuses),
		"palace_delivered_ruler_demands": _duplicate_dictionary(palace_delivered_ruler_demands),
		"palace_ruler_demand_donations": _duplicate_dictionary_array(palace_ruler_demand_donations),
		"last_palace_maintenance_report": last_palace_maintenance_report.duplicate(),

		"player_prestige": player_prestige,
		"rival_prestige": _duplicate_dictionary(rival_prestige),
		"prestige_history": _duplicate_dictionary_array(prestige_history),
		"sacrifice_prestige_records": _duplicate_dictionary_array(sacrifice_prestige_records),

		"religion_state": _duplicate_dictionary(religion_state),

		"flower_war_palace_gate_enabled": flower_war_palace_gate_enabled,
		"last_flower_war_report": _duplicate_dictionary(last_flower_war_report),
		"flower_war_report_archive": _duplicate_dictionary_array(flower_war_report_archive),
		"warbands": _duplicate_dictionary(warbands),

		"rival_houses": _duplicate_dictionary(rival_houses),
		"rival_stockpiles": _duplicate_dictionary(rival_stockpiles),
		"rival_build_progress": _duplicate_dictionary(rival_build_progress),
		"rival_action_history": _duplicate_dictionary_array(rival_action_history)
	}

func apply_save_dictionary(data: Dictionary) -> void:
	current_veintena = int(data.get("current_veintena", current_veintena))
	calendar_period = String(data.get("calendar_period", calendar_period))
	ritual_year = int(data.get("ritual_year", ritual_year))
	last_report = _string_array_from_variant(data.get("last_report", last_report))
	last_turn_summary = _duplicate_dictionary(_dictionary_from_variant(data.get("last_turn_summary", last_turn_summary)))
	initialized = bool(data.get("initialized", initialized))

	estate_stockpiles = _float_dictionary(_dictionary_from_variant(data.get("estate_stockpiles", estate_stockpiles)))
	market_stockpiles = _float_dictionary(_dictionary_from_variant(data.get("market_stockpiles", market_stockpiles)))
	market_demand = _float_dictionary(_dictionary_from_variant(data.get("market_demand", market_demand)))
	estate_buildings = _int_dictionary(_dictionary_from_variant(data.get("estate_buildings", estate_buildings)))
	active_housing_counts = _int_dictionary(_dictionary_from_variant(data.get("active_housing_counts", active_housing_counts)))
	population = _int_dictionary(_dictionary_from_variant(data.get("population", population)))
	base_housing_capacity = _int_dictionary(_dictionary_from_variant(data.get("base_housing_capacity", base_housing_capacity)))
	labour_assignments = _nested_int_dictionary(_dictionary_from_variant(data.get("labour_assignments", labour_assignments)))

	player_palace_dedicated_god = String(data.get("player_palace_dedicated_god", player_palace_dedicated_god))
	palace_built_structures = _duplicate_dictionary(_dictionary_from_variant(data.get("palace_built_structures", palace_built_structures)))
	palace_structure_runtime_statuses = _duplicate_dictionary(_dictionary_from_variant(data.get("palace_structure_runtime_statuses", palace_structure_runtime_statuses)))
	palace_delivered_ruler_demands = _duplicate_dictionary(_dictionary_from_variant(data.get("palace_delivered_ruler_demands", palace_delivered_ruler_demands)))
	palace_ruler_demand_donations = _duplicate_dictionary_array(_array_from_variant(data.get("palace_ruler_demand_donations", palace_ruler_demand_donations)))
	last_palace_maintenance_report = _string_array_from_variant(data.get("last_palace_maintenance_report", last_palace_maintenance_report))

	player_prestige = float(data.get("player_prestige", player_prestige))
	rival_prestige = _duplicate_dictionary(_dictionary_from_variant(data.get("rival_prestige", rival_prestige)))
	prestige_history = _duplicate_dictionary_array(_array_from_variant(data.get("prestige_history", prestige_history)))
	sacrifice_prestige_records = _duplicate_dictionary_array(_array_from_variant(data.get("sacrifice_prestige_records", sacrifice_prestige_records)))

	religion_state = _duplicate_dictionary(_dictionary_from_variant(data.get("religion_state", religion_state)))

	flower_war_palace_gate_enabled = bool(data.get("flower_war_palace_gate_enabled", flower_war_palace_gate_enabled))
	last_flower_war_report = _duplicate_dictionary(_dictionary_from_variant(data.get("last_flower_war_report", last_flower_war_report)))
	flower_war_report_archive = _duplicate_dictionary_array(_array_from_variant(data.get("flower_war_report_archive", flower_war_report_archive)))
	warbands = _duplicate_dictionary(_dictionary_from_variant(data.get("warbands", warbands)))

	rival_houses = _duplicate_dictionary(_dictionary_from_variant(data.get("rival_houses", rival_houses)))
	rival_stockpiles = _duplicate_dictionary(_dictionary_from_variant(data.get("rival_stockpiles", rival_stockpiles)))
	rival_build_progress = _duplicate_dictionary(_dictionary_from_variant(data.get("rival_build_progress", rival_build_progress)))
	rival_action_history = _duplicate_dictionary_array(_array_from_variant(data.get("rival_action_history", rival_action_history)))

	ensure_all_resource_keys()
	ensure_all_building_keys()

# -----------------------------------------------------------------------------
# Utility helpers
# -----------------------------------------------------------------------------

func _node_get_default(node: Node, property_name: String, default_value: Variant) -> Variant:
	if node == null:
		return default_value
	if node.has_meta(property_name):
		return node.get_meta(property_name)
	var value: Variant = node.get(property_name)
	if value == null:
		return default_value
	return value

func _get_dictionary(node: Node, property_name: String) -> Dictionary:
	return _dictionary_from_variant(_node_get_default(node, property_name, {}))

func _get_string_array(node: Node, property_name: String) -> Array[String]:
	return _string_array_from_variant(_node_get_default(node, property_name, []))

func _get_dictionary_array(node: Node, property_name: String) -> Array[Dictionary]:
	return _duplicate_dictionary_array(_array_from_variant(_node_get_default(node, property_name, [])))

func _dictionary_from_variant(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func _array_from_variant(value: Variant) -> Array:
	if value is Array:
		return value as Array
	return []

func _string_array_from_variant(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if value is Array:
		for item: Variant in value:
			output.append(String(item))
	return output

func _float_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = float(source[key_variant])
	return output

func _int_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = int(source[key_variant])
	return output

func _nested_int_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		var value: Variant = source[key_variant]
		if value is Dictionary:
			output[key] = _int_dictionary(value as Dictionary)
	return output

func _duplicate_dictionary(source: Dictionary) -> Dictionary:
	return source.duplicate(true)

func _duplicate_dictionary_array(source: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for item: Variant in source:
		if item is Dictionary:
			output.append((item as Dictionary).duplicate(true))
	return output
