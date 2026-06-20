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
const MARKET_ECONOMY_DATA_PATH: String = "res://Data/Prototype0/market_economy.json"
const CAMPAIGN_STATE_SCRIPT: GDScript = preload("res://Scripts/state/CampaignState.gd")
const PRESTIGE_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/PrestigeSystem.gd")
const MARKET_TRADE_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/MarketTradeSystem.gd")
const POPULATION_UPKEEP_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/PopulationUpkeepSystem.gd")
const HOUSING_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/HousingSystem.gd")
const PRODUCTION_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/ProductionSystem.gd")
const TURN_RESOLUTION_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/TurnResolutionSystem.gd")
const PALACE_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/PalaceSystem.gd")
const RELIGION_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/ReligionSystem.gd")
const WARBAND_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/WarbandSystem.gd")
const FLOWER_WAR_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/FlowerWarSystem.gd")
const RIVAL_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/RivalSystem.gd")


const GOD_TLALOC: String = "tlaloc"
const GOD_HUITZILOPOCHTLI: String = "huitzilopochtli"
const GOD_TEZCATLIPOCA: String = "tezcatlipoca"
const GOD_QUETZALCOATL: String = "quetzalcoatl"
const PALACE_GOD_IDS: Array[String] = [GOD_TLALOC, GOD_HUITZILOPOCHTLI, GOD_TEZCATLIPOCA, GOD_QUETZALCOATL]

var resources: Dictionary = {}
var resource_order: Array[String] = []
var buildings: Dictionary = {}
var building_order: Array[String] = []

var estate_stockpiles: Dictionary = {}
var market_stockpiles: Dictionary = {}
var market_demand: Dictionary = {}
var estate_buildings: Dictionary = {}
var active_housing_counts: Dictionary = {}
var population: Dictionary = {}
var base_housing_capacity: Dictionary = {}
var labour_assignments: Dictionary = {}
var market_economy: Dictionary = {}

var current_veintena: int = 1
var last_report: Array[String] = []
var initialized: bool = false
var player_palace_dedicated_god: String = ""
var palace_built_structures: Dictionary = {}
var palace_structure_runtime_statuses: Dictionary = {}
var palace_delivered_ruler_demands: Dictionary = {} # Legacy compatibility only; v0.36 uses donation records.
var palace_ruler_demand_donations: Array[Dictionary] = []
var player_prestige: float = 0.0
var rival_prestige: Dictionary = {}
var prestige_history: Array[Dictionary] = []
var sacrifice_prestige_records: Array[Dictionary] = []
var last_palace_maintenance_report: Array[String] = []
# Palace gate is now reconnected: player-started attacking Flower Wars require
# a Palace dedicated to Huitzilopochtli. Defensive Flower Wars can still happen
# regardless of dedication because the player is responding to an attack.
var flower_war_palace_gate_enabled: bool = true

# v0.44.2 bridge: CampaignState is the future live save-state owner.
# During this phase TRGameState still owns the active variables, but keeps a
# CampaignState snapshot so the migration can proceed without changing UI calls.
var campaign_state: CampaignState = null

var _prestige_system_instance: PrestigeSystem = null
var _market_trade_system_instance: MarketTradeSystem = null
var _population_upkeep_system_instance: PopulationUpkeepSystem = null
var _housing_system_instance: HousingSystem = null
var _production_system_instance: ProductionSystem = null
var _turn_resolution_system_instance: TurnResolutionSystem = null
var _palace_system_instance: PalaceSystem = null
var _religion_system_instance: ReligionSystem = null
var _warband_system_instance: WarbandSystem = null
var _flower_war_system_instance: FlowerWarSystem = null
var _rival_system_instance: RivalSystem = null

var population_upkeep_rates: Dictionary = {
	"macehualtin": {"maize": 1.0, "cotton": 0.05, "cloth": 0.2, "tools": 0.1},
	"tlacotin": {"maize": 0.5, "cotton": 0.025, "cloth": 0.1, "tools": 0.05},
	"tolteca": {"maize": 1.0, "cotton": 0.1, "cloth": 0.3, "tools": 0.25},
	"yaotequihuaqueh": {"maize": 1.25, "cloth": 0.3, "tools": 0.1, "weapons": 0.2, "cacao": 0.05},
	"tlamacazqueh": {"maize": 1.0, "cloth": 0.2, "ritual_goods": 0.2, "cacao": 0.1},
	"pipiltin": {"maize": 1.0, "cloth": 0.4, "ritual_goods": 0.1, "cacao": 0.3, "fine_textiles": 0.2},
	"malli": {"maize": 0.5}
}


func _get_campaign_state() -> CampaignState:
	if campaign_state == null:
		campaign_state = CAMPAIGN_STATE_SCRIPT.new() as CampaignState
	return campaign_state

func get_campaign_state_snapshot() -> CampaignState:
	# Public bridge for migration/debugging. Returns a fresh snapshot of the
	# current TRGameState-owned runtime without changing gameplay ownership yet.
	_sync_campaign_state_from_current_runtime()
	return _get_campaign_state()

func _sync_campaign_state_from_current_runtime() -> void:
	var snapshot: CampaignState = _get_campaign_state()
	snapshot.copy_from_game_state(self)

func _apply_campaign_state_to_current_runtime() -> void:
	# Migration bridge only. Do not use casually until CampaignState becomes the
	# authoritative live-state owner in a later patch.
	if campaign_state == null:
		return
	campaign_state.apply_to_game_state(self)

func _emit_state_changed_and_sync() -> void:
	# v0.44.4 bridge: keep the CampaignState mirror current whenever TRGameState
	# completes a local runtime mutation. TRGameState is still the public API and
	# active runtime owner; CampaignState is not authoritative yet.
	_sync_campaign_state_from_current_runtime()
	emit_signal("state_changed")

func get_campaign_state_sync_report(sync_first: bool = false) -> Dictionary:
	# v0.44.5 bridge audit: compare the current TRGameState-owned runtime
	# against the CampaignState mirror. This is a migration/debug helper only;
	# it does not make CampaignState authoritative.
	if sync_first:
		_sync_campaign_state_from_current_runtime()
	var snapshot: CampaignState = _get_campaign_state()
	var fields: Array[String] = [
		"resources",
		"resource_order",
		"buildings",
		"building_order",
		"estate_stockpiles",
		"market_stockpiles",
		"market_demand",
		"market_economy",
		"estate_buildings",
		"active_housing_counts",
		"population",
		"base_housing_capacity",
		"labour_assignments",
		"current_veintena",
		"last_report",
		"initialized",
		"player_palace_dedicated_god",
		"palace_built_structures",
		"palace_structure_runtime_statuses",
		"palace_delivered_ruler_demands",
		"palace_ruler_demand_donations",
		"last_palace_maintenance_report",
		"player_prestige",
		"rival_prestige",
		"prestige_history",
		"sacrifice_prestige_records",
		"flower_war_palace_gate_enabled",
		"last_flower_war_report",
		"flower_war_report_archive",
		"warbands"
	]
	var rows: Array[Dictionary] = []
	var mismatch_count: int = 0
	for field_name: String in fields:
		var live_value: Variant = get(field_name)
		var mirror_value: Variant = snapshot.get(field_name)
		var live_text: String = _campaign_state_compare_text(live_value)
		var mirror_text: String = _campaign_state_compare_text(mirror_value)
		var matches: bool = live_text == mirror_text
		if not matches:
			mismatch_count += 1
		rows.append({
			"field": field_name,
			"matches": matches,
			"live_type": type_string(typeof(live_value)),
			"mirror_type": type_string(typeof(mirror_value)),
			"live_preview": _campaign_state_preview(live_value),
			"mirror_preview": _campaign_state_preview(mirror_value)
		})
	return {
		"schema_version": "campaign_state_sync_report_v0_44_5",
		"sync_first": sync_first,
		"field_count": fields.size(),
		"mismatch_count": mismatch_count,
		"in_sync": mismatch_count == 0,
		"rows": rows
	}

func is_campaign_state_mirror_in_sync() -> bool:
	var report: Dictionary = get_campaign_state_sync_report(false)
	return bool(report.get("in_sync", false))

func _campaign_state_compare_text(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		var keys: Array[String] = []
		for key_variant: Variant in dictionary.keys():
			keys.append(str(key_variant))
		keys.sort()
		var parts: Array[String] = []
		for key: String in keys:
			parts.append(key + ":" + _campaign_state_compare_text(dictionary.get(key)))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var array_value: Array = value as Array
		var parts: Array[String] = []
		for item: Variant in array_value:
			parts.append(_campaign_state_compare_text(item))
		return "[" + ",".join(parts) + "]"
	return str(value)

func _campaign_state_preview(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		return "Dictionary(" + str(dictionary.size()) + ")"
	if value is Array:
		var array_value: Array = value as Array
		return "Array(" + str(array_value.size()) + ")"
	var text: String = str(value)
	if text.length() > 80:
		return text.substr(0, 77) + "..."
	return text

func _get_prestige_system() -> PrestigeSystem:
	if _prestige_system_instance == null:
		_prestige_system_instance = PRESTIGE_SYSTEM_SCRIPT.new() as PrestigeSystem
	return _prestige_system_instance

func _get_market_trade_system() -> MarketTradeSystem:
	if _market_trade_system_instance == null:
		_market_trade_system_instance = MARKET_TRADE_SYSTEM_SCRIPT.new() as MarketTradeSystem
	return _market_trade_system_instance

func _get_population_upkeep_system() -> PopulationUpkeepSystem:
	if _population_upkeep_system_instance == null:
		_population_upkeep_system_instance = POPULATION_UPKEEP_SYSTEM_SCRIPT.new() as PopulationUpkeepSystem
	return _population_upkeep_system_instance

func _get_housing_system() -> HousingSystem:
	if _housing_system_instance == null:
		_housing_system_instance = HOUSING_SYSTEM_SCRIPT.new() as HousingSystem
	return _housing_system_instance

func _get_production_system() -> ProductionSystem:
	if _production_system_instance == null:
		_production_system_instance = PRODUCTION_SYSTEM_SCRIPT.new() as ProductionSystem
	return _production_system_instance

func _get_turn_resolution_system() -> TurnResolutionSystem:
	if _turn_resolution_system_instance == null:
		_turn_resolution_system_instance = TURN_RESOLUTION_SYSTEM_SCRIPT.new() as TurnResolutionSystem
	return _turn_resolution_system_instance

func _get_palace_system() -> PalaceSystem:
	if _palace_system_instance == null:
		_palace_system_instance = PALACE_SYSTEM_SCRIPT.new() as PalaceSystem
	return _palace_system_instance

func _get_religion_system() -> ReligionSystem:
	if _religion_system_instance == null:
		_religion_system_instance = RELIGION_SYSTEM_SCRIPT.new() as ReligionSystem
	return _religion_system_instance

func _get_warband_system() -> WarbandSystem:
	if _warband_system_instance == null:
		_warband_system_instance = WARBAND_SYSTEM_SCRIPT.new() as WarbandSystem
	return _warband_system_instance

func _get_flower_war_system() -> FlowerWarSystem:
	if _flower_war_system_instance == null:
		_flower_war_system_instance = FLOWER_WAR_SYSTEM_SCRIPT.new() as FlowerWarSystem
	return _flower_war_system_instance

func _get_rival_system() -> RivalSystem:
	if _rival_system_instance == null:
		_rival_system_instance = RIVAL_SYSTEM_SCRIPT.new() as RivalSystem
	return _rival_system_instance

func _ready() -> void:
	if not initialized:
		new_game()

func new_game() -> void:
	_load_project_data_into_campaign_state()
	palace_built_structures.clear()
	palace_delivered_ruler_demands.clear()
	palace_ruler_demand_donations.clear()
	player_prestige = 0.0
	rival_prestige = _default_rival_prestige_values()
	prestige_history.clear()
	sacrifice_prestige_records.clear()
	_ensure_warband_state()
	last_flower_war_report.clear()
	flower_war_report_archive.clear()
	initialized = true
	last_report.clear()
	last_report.append("New estate simulation started.")
	_emit_state_changed_and_sync()

func _load_project_data_into_campaign_state() -> void:
	# v0.44.6: CampaignState now owns JSON/start-state shaping for the bridge.
	# TRGameState remains the public API and active runtime owner, but no longer
	# carries duplicate project-data loading helpers.
	var runtime_state: CampaignState = _get_campaign_state()
	var result: Dictionary = runtime_state.load_project_data_from_paths(
		RESOURCE_DATA_PATH,
		BUILDING_DATA_PATH,
		START_STATE_PATH,
		MARKET_ECONOMY_DATA_PATH
	)
	for warning_variant: Variant in result.get("warnings", []):
		push_warning(String(warning_variant))
	runtime_state.apply_to_game_state(self)
	_ensure_base_housing_capacity()
	_ensure_active_housing_counts()
	# New-game start states should not begin with productive buildings idle just
	# because a previous patch or save file left empty labour assignment entries.
	# Default setup staffs production automatically in priority order, with maize
	# protected first, then other production buildings until population runs out.
	_auto_staff_all_productive_buildings()

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
	var housing_maintenance: Dictionary = estimate_housing_maintenance()
	var upkeep: Dictionary = estimate_population_upkeep()
	var output: Array[Dictionary] = []
	for resource_id: String in resource_order:
		var resource_data: Dictionary = resources[resource_id] as Dictionary
		var stored: float = _stock(resource_id)
		var in_value: float = float(incoming.get(resource_id, 0.0))
		var upkeep_value: float = float(upkeep.get(resource_id, 0.0))
		var input_value: float = float(building_inputs.get(resource_id, 0.0))
		var housing_value: float = float(housing_maintenance.get(resource_id, 0.0))
		var outgoing: float = upkeep_value + input_value + housing_value
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
			"reserved_breakdown": _reserve_breakdown(resource_id, upkeep_value, input_value, housing_value)
		}
		output.append(good)
	return output

func get_market_goods() -> Array[Dictionary]:
	var raw_goods: Array = estimate_market_resolution().get("goods", []) as Array
	var output: Array[Dictionary] = []
	for item_variant: Variant in raw_goods:
		var item: Dictionary = item_variant as Dictionary
		output.append(item.duplicate(true))
	return output

func get_market_trade_preview(trade_plan: Dictionary) -> Dictionary:
	# v0.43.2 public API. UI can use this to preview barter values without
	# owning market pricing rules. Existing TradeBasketView still works while
	# the UI migration is staged.
	return _get_market_trade_system().get_trade_preview(self, trade_plan)

func validate_market_trade_plan(trade_plan: Dictionary) -> Dictionary:
	return _get_market_trade_system().validate_trade_plan(self, trade_plan)

func apply_market_trade_plan(trade_plan: Dictionary) -> Dictionary:
	return _get_market_trade_system().apply_trade_plan(self, trade_plan)

func get_market_trade_prestige_lines(trade_plan: Dictionary) -> Array[Dictionary]:
	var preview: Dictionary = get_market_trade_preview(trade_plan)
	var lines: Array[Dictionary] = []
	for line_variant: Variant in (preview.get("trade_lines", []) as Array):
		if line_variant is Dictionary:
			lines.append((line_variant as Dictionary).duplicate(true))
	return lines

func get_market_trade_pricing(resource_id: String, amount: float) -> Dictionary:
	var market_goods: Dictionary = _get_market_trade_system().market_goods_by_id(self)
	return _get_market_trade_system().trade_pricing(market_goods, resource_id, amount)

func estimate_market_resolution() -> Dictionary:
	var base_goods: Array[Dictionary] = _base_market_goods()
	var resolved_goods: Array[Dictionary] = _apply_market_economy_to_goods(base_goods)
	var total_output: float = 0.0
	var total_demand: float = 0.0
	var net_value: float = 0.0
	var crisis_goods: Array[String] = []
	var shortage_goods: Array[String] = []
	var surplus_goods: Array[String] = []
	for good: Dictionary in resolved_goods:
		total_output += float(good.get("village_total_production", 0.0))
		total_demand += float(good.get("village_total_demand", 0.0))
		net_value += float(good.get("village_net_change", 0.0))
		var label: String = String(good.get("label", ""))
		var name: String = String(good.get("name", good.get("id", "Good")))
		if label == "Crisis":
			crisis_goods.append(name)
		elif label == "Shortage":
			shortage_goods.append(name)
		elif label == "Abundant":
			surplus_goods.append(name)
	return {
		"goods": resolved_goods,
		"source_of_truth": String(market_economy.get("source_of_truth", "start_state market stock/demand")),
		"total_output": total_output,
		"total_demand": total_demand,
		"net_change": net_value,
		"crisis_goods": crisis_goods,
		"shortage_goods": shortage_goods,
		"surplus_goods": surplus_goods,
		"village_population": (market_economy.get("village_population", {}) as Dictionary).duplicate(true),
		"schema_version": String(market_economy.get("schema_version", ""))
	}

func get_market_economy_summary() -> Dictionary:
	return estimate_market_resolution()

func get_village_economy_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var goods: Array = estimate_market_resolution().get("goods", []) as Array
	for good_variant: Variant in goods:
		var good: Dictionary = good_variant as Dictionary
		rows.append({
			"id": String(good.get("id", "")),
			"name": String(good.get("name", "Good")),
			"natural_production": float(good.get("village_natural_production", 0.0)),
			"building_output": float(good.get("village_building_output", 0.0)),
			"estate_output": float(good.get("market_estate_output_supply", 0.0)),
			"total_production": float(good.get("village_total_production", 0.0)),
			"population_consumption": float(good.get("village_population_consumption", 0.0)),
			"building_input_demand": float(good.get("village_building_input_demand", 0.0)),
			"construction_demand": float(good.get("market_construction_demand", 0.0)),
			"estate_input_demand": float(good.get("market_estate_input_demand", 0.0)),
			"total_demand": float(good.get("village_total_demand", 0.0)),
			"net_change": float(good.get("village_net_change", 0.0)),
			"projected_market_stock": float(good.get("projected_market_stock", 0.0)),
			"label": String(good.get("label", "Unknown")),
			"trend": String(good.get("trend", "Stable")),
			"note": String(good.get("village_note", ""))
		})
	return rows

func _base_market_goods() -> Array[Dictionary]:
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


func get_housing_summary() -> Dictionary:
	return _get_housing_system().get_housing_summary(self)

func get_housing_rows(focus_id: String = "overview") -> Array[Dictionary]:
	return _get_housing_system().get_housing_rows(self, focus_id)

func housing_capacity_by_group(overrides: Dictionary = {}, active_only: bool = true) -> Dictionary:
	return _get_housing_system().housing_capacity_by_group(self, overrides, active_only)

func active_population_by_group() -> Dictionary:
	return _get_housing_system().active_population_by_group(self)

func inactive_population_by_group() -> Dictionary:
	return _get_housing_system().inactive_population_by_group(self)

func _active_population_for_group(group_id: String) -> int:
	return _get_housing_system().active_population_for_group(self, group_id)

func estimate_housing_maintenance() -> Dictionary:
	return _get_housing_system().estimate_housing_maintenance(self)

func _housing_building_view_data(building_id: String) -> Dictionary:
	return _get_housing_system().housing_building_view_data(self, building_id)

func _housing_category_summary(category_id: String, built_capacity_by_group: Dictionary, active_capacity_by_group: Dictionary) -> Dictionary:
	return _get_housing_system().housing_category_summary(self, category_id, built_capacity_by_group, active_capacity_by_group)

func _housing_category_order() -> Array[String]:
	return _get_housing_system().housing_category_order()

func _housing_category_name(category_id: String) -> String:
	return _get_housing_system().housing_category_name(category_id)

func _housing_group_ids_for_category(category_id: String) -> Array[String]:
	return _get_housing_system().housing_group_ids_for_category(category_id)

func _housing_maintenance_for_category(category_id: String) -> Dictionary:
	return _get_housing_system().housing_maintenance_for_category(self, category_id)

func _housing_status_text(population_count: int, capacity_count: int) -> String:
	return _get_housing_system().housing_status_text(population_count, capacity_count)

func _housing_building_status_text(building_id: String) -> String:
	return _get_housing_system().housing_building_status_text(self, building_id)

func _housing_efficiency_text(capacity: Dictionary, maintenance: Dictionary) -> String:
	return _get_housing_system().housing_efficiency_text(capacity, maintenance)

func _would_destroy_overcrowd(building_id: String) -> Dictionary:
	return _get_housing_system().would_destroy_overcrowd(self, building_id)

func _is_housing_building_id(building_id: String) -> bool:
	return _get_housing_system().is_housing_building_id(self, building_id)

func _ensure_base_housing_capacity() -> void:
	_get_housing_system().ensure_base_housing_capacity(self)

func _ensure_active_housing_counts() -> void:
	_get_housing_system().ensure_active_housing_counts(self)

func set_active_housing_count(building_id: String, active_count: int) -> bool:
	var result: bool = _get_housing_system().set_active_housing_count(self, building_id, active_count)
	if result:
		_ensure_labour_assignments()
		_emit_state_changed_and_sync()
	return result

func get_housing_mothball_rows() -> Array[Dictionary]:
	return _get_housing_system().get_housing_mothball_rows(self)

func get_housing_mothball_data() -> Dictionary:
	return _get_housing_system().get_housing_mothball_data(self)

func get_productive_labour_rows() -> Array[Dictionary]:
	_ensure_labour_assignments()
	var required: Dictionary = _productive_labour_required()
	var assigned_by_group: Dictionary = _assigned_labour_by_group()
	var rows: Array[Dictionary] = []
	for group_id: String in _productive_labour_group_ids():
		var total: int = _active_population_for_group(group_id)
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
	var total: int = _active_population_for_group(group_id)
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
		var member_total: int = _active_population_for_group(member_id)
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
		var total_pop: int = _active_population_for_group(member_id)
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
		var total_pop: int = _active_population_for_group(member_id)
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
	# Goods spoken for before construction spending: population upkeep, housing
	# maintenance, and current production input demand. This matches the Storehouse
	# Reserved / Free to spend logic.
	var reserved: Dictionary = {}
	var upkeep: Dictionary = estimate_population_upkeep()
	var maintenance: Dictionary = estimate_housing_maintenance()
	var inputs: Dictionary = estimate_building_inputs()
	for resource_variant: Variant in upkeep.keys():
		var resource_id: String = String(resource_variant)
		reserved[resource_id] = float(reserved.get(resource_id, 0.0)) + float(upkeep[resource_id])
	for resource_variant: Variant in maintenance.keys():
		var resource_id: String = String(resource_variant)
		reserved[resource_id] = float(reserved.get(resource_id, 0.0)) + float(maintenance[resource_id])
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
		_emit_state_changed_and_sync()
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	var cost: Dictionary = definition.get("build_cost", {}) as Dictionary
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, -float(cost[resource_id]))
	var previous_count: int = int(estate_buildings.get(building_id, 0))
	var previous_staffed: int = _staffed_count_for_building(building_id)
	estate_buildings[building_id] = previous_count + 1
	if _is_housing_building_id(building_id):
		_ensure_active_housing_counts()
		active_housing_counts[building_id] = int(active_housing_counts.get(building_id, previous_count)) + 1
		active_housing_counts[building_id] = clampi(int(active_housing_counts[building_id]), 0, int(estate_buildings.get(building_id, 0)))
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
	_emit_state_changed_and_sync()
	return true

func can_destroy(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	if int(estate_buildings.get(building_id, 0)) <= 0:
		return false
	if _is_housing_building_id(building_id):
		var overcrowd: Dictionary = _would_destroy_overcrowd(building_id)
		return not bool(overcrowd.get("blocked", false))
	return true

func destroy_status_text(building_id: String) -> String:
	if not buildings.has(building_id):
		return "Unknown building."
	if int(estate_buildings.get(building_id, 0)) <= 0:
		return "None built."
	if _is_housing_building_id(building_id):
		var overcrowd: Dictionary = _would_destroy_overcrowd(building_id)
		if bool(overcrowd.get("blocked", false)):
			var lines: Array = overcrowd.get("lines", []) as Array
			return "Cannot destroy: would overcrowd " + ", ".join(lines) + "."
		return "Can destroy one. No refund in this prototype."
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
		_emit_state_changed_and_sync()
		return false
	var before_destroy_count: int = int(estate_buildings.get(building_id, 0))
	estate_buildings[building_id] = max(0, before_destroy_count - 1)
	if _is_housing_building_id(building_id):
		_ensure_active_housing_counts()
		active_housing_counts[building_id] = mini(int(active_housing_counts.get(building_id, 0)), int(estate_buildings.get(building_id, 0)))
	_ensure_labour_assignments()
	last_report.append("Destroyed one " + get_building_name(building_id) + ". No refund given.")
	emit_signal("destroy_completed", building_id)
	_emit_state_changed_and_sync()
	return true

func advance_veintena() -> void:
	_get_turn_resolution_system().advance_veintena(self)
	_sync_campaign_state_from_current_runtime()

func estimate_population_upkeep() -> Dictionary:
	return _get_population_upkeep_system().calculate_population_upkeep(active_population_by_group(), population_upkeep_rates)

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
	# Authoritative production preview. Rule logic now lives in ProductionSystem;
	# TRGameState remains the live-state owner and public API for the UI.
	return _get_production_system().estimate_production_resolution(self)

func _copy_stockpile_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = float(source[key_variant])
	return output

func _add_dictionary_amounts(target: Dictionary, amounts: Dictionary) -> void:
	for resource_variant: Variant in amounts.keys():
		var resource_id: String = String(resource_variant)
		target[resource_id] = float(target.get(resource_id, 0.0)) + float(amounts[resource_variant])

func _pay_population_upkeep() -> void:
	var resolution: Dictionary = _get_population_upkeep_system().resolve_population_upkeep(estate_stockpiles, active_population_by_group(), population_upkeep_rates)
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
			last_report.append("Paid population upkeep: " + _format_amount(needed) + " " + get_resource_name(resource_id) + ".")
		else:
			last_report.append("Shortage: paid only " + _format_amount(paid) + " / " + _format_amount(needed) + " " + get_resource_name(resource_id) + " for population upkeep.")

func _pay_housing_maintenance() -> void:
	var payments: Array = _get_housing_system().pay_housing_maintenance(self)
	for payment_variant: Variant in payments:
		if not (payment_variant is Dictionary):
			continue
		var payment: Dictionary = payment_variant as Dictionary
		var resource_id: String = String(payment.get("resource_id", ""))
		var needed: float = float(payment.get("needed", 0.0))
		var paid: float = float(payment.get("paid", 0.0))
		var shortfall: float = float(payment.get("shortfall", 0.0))
		if shortfall <= 0.001:
			last_report.append("Paid housing building upkeep: " + _format_amount(needed) + " " + get_resource_name(resource_id) + ".")
		else:
			last_report.append("Housing building upkeep shortage: paid only " + _format_amount(paid) + " / " + _format_amount(needed) + " " + get_resource_name(resource_id) + ".")

func _operate_buildings() -> void:
	var reports: Array = _get_production_system().operate_buildings(self)
	for report_variant: Variant in reports:
		last_report.append(String(report_variant))

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
			var total: int = _active_population_for_group(group_id)
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
		var total: int = _active_population_for_group(group_id)
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
	var total_pop: int = _active_population_for_group(group_id)
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
		var total: int = _active_population_for_group(group_id)
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
	_emit_state_changed_and_sync()

func _dictionary_to_named_string(values: Dictionary, suffix: String = "") -> String:
	var parts: Array[String] = []
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		var label: String = key
		if resources.has(key):
			label = get_resource_name(key)
		elif population.has(key) or base_housing_capacity.has(key):
			label = _labour_group_name(key)
		var amount_text: String = ""
		var value: Variant = values[key_variant]
		if value is int:
			amount_text = str(int(value))
		else:
			amount_text = _format_amount(float(value))
		if suffix != "":
			parts.append(label + " " + amount_text + " " + suffix)
		else:
			parts.append(label + " " + amount_text)
	if parts.is_empty():
		return "None"
	return "; ".join(parts)

func _stock(resource_id: String) -> float:
	return float(estate_stockpiles.get(resource_id, 0.0))

func _add_stock(resource_id: String, amount: float) -> void:
	estate_stockpiles[resource_id] = maxf(0.0, _stock(resource_id) + amount)

func _reserve_breakdown(resource_id: String, upkeep_value: float, input_value: float, housing_value: float = 0.0) -> Array[String]:
	var lines: Array[String] = []
	if upkeep_value > 0.0:
		lines.append("Population upkeep: " + _format_amount(upkeep_value))
	if housing_value > 0.0:
		lines.append("Housing building upkeep: " + _format_amount(housing_value))
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
	return _get_rival_system().market_note_for_resource(resource_id)


func _apply_market_economy_to_goods(goods: Array[Dictionary]) -> Array[Dictionary]:
	if market_economy.is_empty():
		return goods
	var natural: Dictionary = market_economy.get("village_natural_production", {}) as Dictionary
	var building_outputs: Dictionary = market_economy.get("village_building_outputs", {}) as Dictionary
	var population_use: Dictionary = market_economy.get("village_population_consumption", {}) as Dictionary
	var building_inputs: Dictionary = market_economy.get("village_building_inputs", {}) as Dictionary
	var construction_demand: Dictionary = market_economy.get("year1_construction_demand_per_turn", {}) as Dictionary
	var estate_inputs: Dictionary = market_economy.get("starter_estate_input_demand", {}) as Dictionary
	var estate_outputs: Dictionary = market_economy.get("starter_estate_output_supply", {}) as Dictionary
	var event_modifiers: Dictionary = market_economy.get("event_modifiers", {}) as Dictionary
	for index: int in range(goods.size()):
		var good: Dictionary = goods[index]
		var resource_id: String = String(good.get("id", ""))
		var market_stock: float = float(good.get("market_stock", 0.0))
		var base_value: float = float(good.get("base_value", 1.0))
		var natural_output: float = _market_resource_value(natural, resource_id)
		var building_output: float = _market_resource_value(building_outputs, resource_id)
		var estate_output: float = _market_resource_value(estate_outputs, resource_id)
		var population_demand: float = _market_resource_value(population_use, resource_id)
		var building_demand: float = _market_resource_value(building_inputs, resource_id)
		var construction_need: float = _market_resource_value(construction_demand, resource_id)
		var estate_demand: float = _market_resource_value(estate_inputs, resource_id)
		var event_delta: float = _market_resource_value(event_modifiers, resource_id)
		# Spreadsheet reconciliation: the background market uses the v0.12 balance
		# workbook as its source of truth. Natural output + village building output
		# + the modelled starter-estate supply are compared against population
		# upkeep + village production inputs + year-one construction pressure +
		# starter-estate input pressure. This reproduces the Market Balance sheet
		# net / turn values while still showing the village pieces separately.
		var total_output: float = maxf(0.0, natural_output + building_output + estate_output + event_delta)
		var total_demand: float = maxf(0.0, population_demand + building_demand + construction_need + estate_demand)
		if total_demand <= 0.001:
			total_demand = maxf(0.0, float(good.get("demand", 0.0)))
		var net_change: float = total_output - total_demand
		var projected_stock: float = maxf(0.0, market_stock + net_change)
		var projected_coverage: float = 0.0
		if total_demand > 0.001:
			projected_coverage = projected_stock / total_demand
		var multiplier: float = _market_scarcity_multiplier(projected_coverage, total_demand)
		var projected_value: float = base_value * multiplier
		good["starting_market_stock"] = market_stock
		good["village_natural_production"] = natural_output
		good["village_building_output"] = building_output
		good["market_estate_output_supply"] = estate_output
		good["village_event_delta"] = event_delta
		good["village_total_production"] = total_output
		good["village_population_consumption"] = population_demand
		good["village_building_input_demand"] = building_demand
		good["market_construction_demand"] = construction_need
		good["market_estate_input_demand"] = estate_demand
		good["village_total_demand"] = total_demand
		good["village_net_change"] = net_change
		good["projected_market_stock"] = projected_stock
		good["projected_coverage"] = projected_coverage
		good["projected_value"] = projected_value
		good["demand"] = total_demand
		good["coverage"] = projected_coverage
		good["current_value"] = projected_value
		good["label"] = _market_pressure_label(projected_coverage, total_demand)
		good["trend"] = _market_net_trend(net_change, total_demand)
		good["village_note"] = _market_good_note(resource_id)
		goods[index] = good
	return goods

func _market_resource_value(source: Dictionary, resource_id: String) -> float:
	return float(source.get(resource_id, 0.0))

func _market_scarcity_multiplier(coverage: float, demand: float) -> float:
	if demand <= 0.001:
		return 1.0
	if coverage <= 0.001:
		return 3.0
	return clampf(3.0 / coverage, 0.50, 3.0)

func _market_pressure_label(coverage: float, demand: float) -> String:
	if demand <= 0.001:
		return "No demand"
	if coverage < 1.0:
		return "Crisis"
	if coverage < 2.0:
		return "Shortage"
	if coverage < 3.0:
		return "Tight"
	if coverage > 6.0:
		return "Abundant"
	return "Comfortable"

func _market_net_trend(net_change: float, demand: float) -> String:
	if demand <= 0.001:
		return "Stable"
	if net_change <= -demand * 0.35:
		return "Falling fast"
	if net_change < -0.01:
		return "Falling"
	if net_change >= demand * 0.35:
		return "Rising fast"
	if net_change > 0.01:
		return "Rising"
	return "Stable"

func _market_good_note(resource_id: String) -> String:
	var notes: Dictionary = market_economy.get("resource_notes", {}) as Dictionary
	return String(notes.get(resource_id, "No village economy note recorded yet."))

func _format_amount(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))

# -----------------------------------------------------------------------------
# Barracks / Flower Wars v0.15 — injured recovery + reinforcement clarity
# -----------------------------------------------------------------------------

var last_flower_war_report: Dictionary = {}
var flower_war_report_archive: Array[Dictionary] = []
var warbands: Dictionary = {}

const FLOWER_WAR_DOCTRINES: Dictionary = {
	"unspecialised": {"name": "Unspecialised", "offence": 1.0, "defence": 1.0, "role": "Balanced household warriors."},
	"eagle": {"name": "Eagle", "offence": 1.0, "defence": 1.2, "role": "Captive specialists and sustained war fighters."},
	"jaguar": {"name": "Jaguar", "offence": 1.3, "defence": 1.0, "role": "Elite offensive warriors. No hidden Prestige bonus; Prestige comes from victories, casualties, captives and loot."},
	"otomi": {"name": "Otomi", "offence": 0.8, "defence": 1.5, "role": "Defensive veterans who preserve warriors."},
	"coyote": {"name": "Coyote", "offence": 1.4, "defence": 0.5, "role": "Glass-cannon raiders who favour loot."}
}

const FLOWER_WAR_PROVISIONING: Dictionary = {
	"standard": {"name": "Standard", "supply_multiplier": 1.0, "combat_multiplier": 1.0},
	"well": {"name": "Well Provisioned", "supply_multiplier": 2.0, "combat_multiplier": 1.1},
	"royal": {"name": "Royal Provision", "supply_multiplier": 4.0, "combat_multiplier": 1.2}
}

const FLOWER_WAR_OPTIONS: Dictionary = {
	"minor": {"name": "Minor Flower War", "warriors": 5, "enemy_warriors": 5, "enemy_xp": 1.0, "enemy_offence": 1.0, "enemy_defence": 1.0, "base_loot_value": 1.2},
	"standard": {"name": "Standard Flower War", "warriors": 10, "enemy_warriors": 10, "enemy_xp": 1.0, "enemy_offence": 1.0, "enemy_defence": 1.0, "base_loot_value": 2.4},
	"major": {"name": "Major Flower War", "warriors": 20, "enemy_warriors": 20, "enemy_xp": 1.0, "enemy_offence": 1.0, "enemy_defence": 1.0, "base_loot_value": 4.8}
}

const FLOWER_WAR_DEFENCE_STRATEGIES: Dictionary = {
	"balanced": {"name": "Balanced Defence", "offence_multiplier": 1.0, "defence_multiplier": 1.0, "description": "A steady response with no bonus or penalty."},
	"depth": {"name": "Defence in Depth", "offence_multiplier": 0.85, "defence_multiplier": 1.25, "description": "Protect the warbands and absorb the attack. More defence, less offence."},
	"good_offence": {"name": "The Best Defence is a Good Offence", "offence_multiplier": 1.25, "defence_multiplier": 0.85, "description": "Counterattack hard. More offence, less defence."}
}

func get_warrior_count() -> int:
	return int(population.get("yaotequihuaqueh", 0))

func get_warrior_capacity() -> int:
	var capacity: Dictionary = housing_capacity_by_group({}, true)
	return int(capacity.get("yaotequihuaqueh", 0))

func get_barracks_summary() -> Dictionary:
	var warriors: int = get_warrior_count()
	var capacity: int = get_warrior_capacity()
	return {
		"warriors": warriors,
		"capacity": capacity,
		"free_capacity": max(0, capacity - warriors),
		"unassigned_warriors": _unassigned_warrior_pool(),
		"status": "Ready" if warriors > 0 else "No warriors available",
		"weapons": free_stock_after_reserves("weapons"),
		"captives": int(estate_stockpiles.get("captives", 0.0)),
		"palace_dedicated_god": get_player_palace_dedicated_god(),
		"has_war_god_palace": has_war_god_palace(),
		"flower_war_palace_gate_enabled": is_flower_war_palace_gate_enabled(),
		"flower_war_palace_gate_passed": flower_war_palace_gate_passed(),
		"doctrines": FLOWER_WAR_DOCTRINES.duplicate(true),
		"provisioning": FLOWER_WAR_PROVISIONING.duplicate(true),
		"defence_strategies": FLOWER_WAR_DEFENCE_STRATEGIES.duplicate(true),
		"army_muster": get_army_muster_summary()
	}

func get_warband_combat_stats(warband_id: String) -> Dictionary:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {}
	var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	return _warband_combat_stats_from_warband(warband)

func get_army_muster_summary() -> Dictionary:
	_ensure_warband_state()
	var rows: Array[Dictionary] = []
	var total_ready: int = 0
	var total_injured: int = 0
	var total_dead: int = 0
	var total_offence: float = 0.0
	var total_defence: float = 0.0
	var active_warbands: int = 0
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = warband
		var stats: Dictionary = _warband_combat_stats_from_warband(warband)
		rows.append(stats)
		total_ready += int(stats.get("ready", 0))
		total_injured += int(stats.get("injured", 0))
		total_dead += int(stats.get("dead_total", 0))
		total_offence += float(stats.get("effective_offence", 0.0))
		total_defence += float(stats.get("effective_defence", 0.0))
		if int(stats.get("ready", 0)) > 0:
			active_warbands += 1
	return {
		"warbands": rows,
		"warband_count": rows.size(),
		"active_warband_count": active_warbands,
		"ready_warriors": total_ready,
		"injured_not_fighting": total_injured,
		"dead_suffered": total_dead,
		"effective_offence": snappedf(total_offence, 0.01),
		"effective_defence": snappedf(total_defence, 0.01),
		"skill_web_effects_connected": false,
		"stats_note": "Combat stats use ready warriors and the doctrine chosen through the Skill Web specialism. Other node effects are not connected to Flower War resolution yet.",
		"injury_note": "Injured warriors do not fight, cannot be unassigned, and recover on the next Veintena advance."
	}

func _warband_doctrine_data(doctrine_id: String) -> Dictionary:
	var cleaned: String = doctrine_id
	if not FLOWER_WAR_DOCTRINES.has(cleaned):
		cleaned = "unspecialised"
	var data: Dictionary = (FLOWER_WAR_DOCTRINES[cleaned] as Dictionary).duplicate(true)
	data["id"] = cleaned
	return data

func _warband_combat_stats_from_warband(warband: Dictionary) -> Dictionary:
	var doctrine_id: String = String(warband.get("doctrine", "unspecialised"))
	var doctrine: Dictionary = _warband_doctrine_data(doctrine_id)
	var ready: int = max(0, int(warband.get("ready_warriors", warband.get("ready", 0))))
	var injured: int = max(0, int(warband.get("injured_warriors", warband.get("injured", 0))))
	var dead_total: int = max(0, int(warband.get("dead_total", 0)))
	var total_known: int = ready + injured
	var offence_mod: float = float(doctrine.get("offence", 1.0))
	var defence_mod: float = float(doctrine.get("defence", 1.0))
	return {
		"id": String(warband.get("id", "")),
		"name": String(warband.get("name", "Warband")),
		"doctrine_id": String(doctrine.get("id", "unspecialised")),
		"doctrine_name": String(doctrine.get("name", "Unspecialised")),
		"doctrine_role": String(doctrine.get("role", "")),
		"ready": ready,
		"injured": injured,
		"dead_total": dead_total,
		"total_present": total_known,
		"offence_modifier": offence_mod,
		"defence_modifier": defence_mod,
		"effective_offence": snappedf(float(ready) * offence_mod, 0.01),
		"effective_defence": snappedf(float(ready) * defence_mod, 0.01),
		"skill_web_effects_connected": false,
		"stats_note": "Doctrine preview. The Skill Web specialism sets combat doctrine; other node effects are recorded as prototype data but are not connected to Flower War resolution yet."
	}


func get_player_palace_dedicated_god() -> String:
	return _get_palace_system().get_player_palace_dedicated_god(self)

func set_player_palace_dedicated_god(god_id: String) -> Dictionary:
	return _get_palace_system().set_player_palace_dedicated_god(self, god_id)

func has_war_god_palace() -> bool:
	return _get_palace_system().has_war_god_palace(self)

func is_flower_war_palace_gate_enabled() -> bool:
	return _get_palace_system().is_flower_war_palace_gate_enabled(self)

func set_flower_war_palace_gate_enabled(enabled: bool) -> Dictionary:
	return _get_palace_system().set_flower_war_palace_gate_enabled(self, enabled)

func flower_war_palace_gate_passed() -> bool:
	return _get_palace_system().flower_war_palace_gate_passed(self)

func flower_war_palace_gate_status_text() -> String:
	return _get_palace_system().flower_war_palace_gate_status_text(self)

func _god_display_name(god_id: String) -> String:
	return _get_palace_system().god_display_name(god_id)

func get_palace_dedicated_god() -> String:
	return _get_palace_system().get_palace_dedicated_god(self)

func get_palace_route_name(god_id: String) -> String:
	return _get_palace_system().get_palace_route_name(god_id)

func get_palace_route_power_summary(god_id: String) -> String:
	return _get_palace_system().get_palace_route_power_summary(god_id)

func can_dedicate_palace_to_god(god_id: String) -> Dictionary:
	return _get_palace_system().can_dedicate_palace_to_god(self, god_id)

func dedicate_palace_to_god(god_id: String) -> Dictionary:
	return _get_palace_system().dedicate_palace_to_god(self, god_id)

func get_palace_structure_tree_shell(god_id: String = "") -> Dictionary:
	var route_id: String = god_id.strip_edges().to_lower()
	if route_id == "":
		route_id = get_palace_dedicated_god()
	if not PALACE_GOD_IDS.has(route_id):
		return {"god_id": "", "god_name": "None", "route_name": "No Palace Route", "tiers": [], "note": "Dedicate the palace to reveal a route-specific palace structure tree."}
	var tiers: Array[Dictionary] = _palace_structure_tree_tiers(route_id)
	_apply_palace_structure_statuses(tiers, route_id)
	return {
		"god_id": route_id,
		"god_name": _god_display_name(route_id),
		"route_name": get_palace_route_name(route_id),
		"power_summary": get_palace_route_power_summary(route_id),
		"tiers": tiers,
		"built_structure_count": get_built_palace_structure_ids().size(),
		"total_maintenance": get_palace_total_maintenance(),
		"required_staff": get_palace_required_staff(),
		"note": "Palace structures can be built and now preview active/inactive status from maintenance and staff availability. Authority effects are still future patches."
	}

func _palace_structure_node(
	id: String,
	god_id: String,
	tier: int,
	name: String,
	description: String,
	build_cost: Dictionary,
	maintenance_cost: Dictionary,
	staff_requirement: Dictionary,
	prerequisites: Array[String],
	effect_summary: String
) -> Dictionary:
	var prerequisite_text: String = "None"
	if not prerequisites.is_empty():
		prerequisite_text = ", ".join(prerequisites)
	var built: bool = _is_palace_structure_built(id)
	var status_text: String = "Not built"
	if built:
		status_text = "Built — operation check pending"
	return {
		"id": id,
		"name": name,
		"god_id": god_id,
		"route": get_palace_route_name(god_id),
		"tier": tier,
		"level": tier,
		"description": description,
		"summary": effect_summary,
		"build_cost": build_cost,
		"maintenance_cost": maintenance_cost,
		"staff_requirement": staff_requirement,
		"prerequisites": prerequisites,
		"prerequisite_text": prerequisite_text,
		"effect_summary": effect_summary,
		"status": status_text,
		"built": built,
		"active": false,
		"inactive_reason": "Not built.",
		"prototype_note": "Construction, maintenance payment and staff checks are implemented. Authority effects are not active yet."
	}

func _palace_structure_tree_tiers(god_id: String) -> Array[Dictionary]:
	match god_id:
		"tlaloc":
			return [
				{"tier": 1, "title": "Level 1 — Household Water Court", "structures": [
					_palace_structure_node("tlaloc_rain_reading_basin", god_id, 1, "Rain-Reading Basin", "A polished basin set in the palace court for reading rain, reflected sky, canal levels and field signs.", {"wood": 18.0, "cloth": 4.0, "ritual_goods": 1.0}, {"cacao": 0.5, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Reveals basic nearby natural pressure once the Tlaloc authority system is active."),
					_palace_structure_node("tlaloc_canal_listening_court", god_id, 1, "Canal Listening Court", "A quiet court where priests and estate nobles listen for canal, flood and lake warnings.", {"wood": 22.0, "cloth": 5.0, "ritual_goods": 1.0}, {"cacao": 0.5, "cloth": 0.5}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Future hook for canal, flood and water-management warnings."),
					_palace_structure_node("tlaloc_field_omen_chamber", god_id, 1, "Field Omen Chamber", "A chamber for crop samples, pest signs and soil offerings brought in from the estate lands.", {"wood": 16.0, "cloth": 4.0, "cacao": 1.0}, {"cacao": 0.5, "ritual_goods": 0.25}, {"tlamacazqueh": 1}, [], "Future hook for crop, pest and harvest-risk signs.")
				]},
				{"tier": 2, "title": "Level 2 — Storm Calendar Wing", "structures": [
					_palace_structure_node("tlaloc_storm_calendar_archive", god_id, 2, "Storm Calendar Archive", "Painted bark records and priestly tallies compare present weather signs against previous ritual years.", {"wood": 40.0, "cloth": 10.0, "ritual_goods": 3.0, "cacao": 2.0}, {"cacao": 1.0, "cloth": 0.5, "ritual_goods": 0.5}, {"tlamacazqueh": 2, "pipiltin": 1}, ["One Level 1 Tlaloc structure"], "Extends natural-event forecast range."),
					_palace_structure_node("tlaloc_drought_vessel_court", god_id, 2, "Drought Vessel Court", "Rows of sealed vessels hold water, dust and field offerings to read dry-season severity.", {"wood": 34.0, "cloth": 8.0, "ritual_goods": 3.0}, {"cacao": 1.0, "ritual_goods": 0.5}, {"tlamacazqueh": 2}, ["Rain-Reading Basin"], "Future hook for drought severity and preparation."),
					_palace_structure_node("tlaloc_flood_marker_terrace", god_id, 2, "Flood Marker Terrace", "A raised terrace marked with carved flood levels and canal measures.", {"wood": 44.0, "cloth": 8.0, "tools": 2.0}, {"cacao": 0.75, "tools": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, ["Canal Listening Court"], "Future hook for flood severity and likely affected goods.")
				]},
				{"tier": 3, "title": "Level 3 — Deep Omen Court", "structures": [
					_palace_structure_node("tlaloc_deep_calendar_observatory", god_id, 3, "Deep Calendar Observatory", "A high palace platform for aligning rain, mountain, canal and crop records into long-range forecast patterns.", {"wood": 80.0, "cloth": 18.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, {"cacao": 1.5, "ritual_goods": 1.0, "fine_textiles": 0.25}, {"tlamacazqueh": 3, "pipiltin": 2}, ["Storm Calendar Archive"], "Reveals event duration and affected goods once forecast mechanics are active."),
					_palace_structure_node("tlaloc_lake_mirror_priests", god_id, 3, "Lake-Mirror Priests", "A staffed priestly office that compares mirrored water signs against tribute and field records.", {"wood": 70.0, "cloth": 16.0, "ritual_goods": 6.0, "cacao": 4.0}, {"cacao": 2.0, "ritual_goods": 0.75}, {"tlamacazqueh": 4, "pipiltin": 1}, ["Drought Vessel Court or Flood Marker Terrace"], "Future hook for better forecast accuracy and fewer unknowns.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Tlaloc", "structures": [
					_palace_structure_node("tlaloc_great_court", god_id, 4, "Great Court of Tlaloc", "A full palace court dedicated to rain, waters, fields and the hidden calendar of natural pressure.", {"wood": 140.0, "cloth": 35.0, "ritual_goods": 10.0, "fine_textiles": 2.0}, {"cacao": 3.0, "ritual_goods": 1.5, "fine_textiles": 0.5}, {"tlamacazqueh": 6, "pipiltin": 3}, ["Deep Calendar Observatory", "Lake-Mirror Priests"], "Long-range natural calendar foresight and full Tlaloc palace authority.")
				]}
			]
		"huitzilopochtli":
			return [
				{"tier": 1, "title": "Level 1 — War Banner Court", "structures": [
					_palace_structure_node("huitz_war_banner_court", god_id, 1, "War Banner Court", "A court for public war standards, muster rites and the formal authority of the war route.", {"wood": 20.0, "cloth": 5.0, "weapons": 1.0}, {"cacao": 0.5, "cloth": 0.5}, {"pipiltin": 1}, [], "Supports formal Flower War authority under a Huitzilopochtli Palace."),
					_palace_structure_node("huitz_captive_procession_steps", god_id, 1, "Captive Procession Steps", "Ceremonial steps for bringing captives, witnesses and war spoils into palace view.", {"wood": 18.0, "cloth": 4.0, "ritual_goods": 1.0}, {"cacao": 0.5, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Future hook for captives, sacrifice and war-route visibility."),
					_palace_structure_node("huitz_weapon_oath_hall", god_id, 1, "Weapon Oath Hall", "A hall where warriors and nobles bind weapons, discipline and palace service to the war god.", {"wood": 24.0, "cloth": 4.0, "weapons": 2.0}, {"cacao": 0.5, "weapons": 0.25}, {"pipiltin": 1}, [], "Future hook for military organisation and warrior preparation.")
				]},
				{"tier": 2, "title": "Level 2 — Martial Review Wing", "structures": [
					_palace_structure_node("huitz_eagle_jaguar_review_court", god_id, 2, "Eagle-Jaguar Review Court", "A review court for warbands, captains and noble witnesses before a Flower War muster.", {"wood": 45.0, "cloth": 10.0, "weapons": 3.0, "cacao": 2.0}, {"cacao": 1.0, "cloth": 0.5}, {"pipiltin": 2}, ["War Banner Court"], "Future hook for warband management authority."),
					_palace_structure_node("huitz_sacrifice_ledger_chamber", god_id, 2, "Sacrifice Ledger Chamber", "A palace office recording captives, ritual use, witnesses and obligation fulfilment.", {"wood": 36.0, "cloth": 8.0, "ritual_goods": 3.0}, {"cacao": 1.0, "ritual_goods": 0.5}, {"tlamacazqueh": 2, "pipiltin": 1}, ["Captive Procession Steps"], "Future hook for captive-to-ritual administration."),
					_palace_structure_node("huitz_martial_tribute_office", god_id, 2, "Martial Tribute Office", "An office that separates war spoils, weapon obligations and ruler-facing martial goods.", {"wood": 38.0, "cloth": 8.0, "tools": 2.0, "weapons": 2.0}, {"cacao": 1.0, "tools": 0.25}, {"pipiltin": 2}, ["Weapon Oath Hall"], "Future hook for war spoils and obligations.")
				]},
				{"tier": 3, "title": "Level 3 — Sun-War Tribunal", "structures": [
					_palace_structure_node("huitz_sun_war_tribunal", god_id, 3, "Sun-War Tribunal", "A high tribunal where war success, captives and noble martial claims are judged.", {"wood": 85.0, "cloth": 18.0, "ritual_goods": 6.0, "weapons": 5.0, "fine_textiles": 1.0}, {"cacao": 1.5, "ritual_goods": 0.75, "weapons": 0.5}, {"tlamacazqueh": 2, "pipiltin": 3}, ["Eagle-Jaguar Review Court"], "Stronger war-route legitimacy and martial recognition hooks."),
					_palace_structure_node("huitz_captive_witness_court", god_id, 3, "Captive Witness Court", "A public court where captives, witnesses and palace representatives make war results visible.", {"wood": 74.0, "cloth": 16.0, "ritual_goods": 6.0, "cacao": 4.0}, {"cacao": 2.0, "ritual_goods": 0.75}, {"tlamacazqueh": 3, "pipiltin": 2}, ["Sacrifice Ledger Chamber or Martial Tribute Office"], "Future hook for public war legitimacy and captive display.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Huitzilopochtli", "structures": [
					_palace_structure_node("huitz_great_court", god_id, 4, "Great Court of Huitzilopochtli", "A full palace court for war, captives, martial claims and the authority to pursue the war route.", {"wood": 150.0, "cloth": 35.0, "weapons": 10.0, "ritual_goods": 10.0, "fine_textiles": 2.0}, {"cacao": 3.0, "ritual_goods": 1.5, "weapons": 0.75}, {"tlamacazqueh": 4, "pipiltin": 5}, ["Sun-War Tribunal", "Captive Witness Court"], "Full war palace authority and late war-route support.")
				]}
			]
		"tezcatlipoca":
			return [
				{"tier": 1, "title": "Level 1 — Mirror Court", "structures": [
					_palace_structure_node("tez_obsidian_mirror_chamber", god_id, 1, "Obsidian Mirror Chamber", "A dark palace room for reading rivals, scarcity and hidden pressure through polished obsidian.", {"wood": 18.0, "cloth": 4.0, "obsidian": 2.0}, {"cacao": 0.75, "obsidian": 0.25}, {"pipiltin": 1}, [], "Future hook for rival and market-pressure hints."),
					_palace_structure_node("tez_smoke_messenger_room", god_id, 1, "Smoke Messenger Room", "A chamber for controlled smoke rites, secret messages and dangerous promises.", {"wood": 20.0, "cloth": 5.0, "ritual_goods": 1.0}, {"cacao": 0.75, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Future hook for manipulation and hidden communication."),
					_palace_structure_node("tez_night_ledger_office", god_id, 1, "Night Ledger Office", "A concealed ledger office for recording shortages, debts, rival needs and pressure points.", {"wood": 18.0, "cloth": 5.0, "cacao": 1.0}, {"cacao": 1.0, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for shortage and pressure-point tracking.")
				]},
				{"tier": 2, "title": "Level 2 — Shadow Administration", "structures": [
					_palace_structure_node("tez_rival_shadow_court", god_id, 2, "Rival Shadow Court", "A hidden court for measuring rival weakness, pride, debts and dangerous opportunities.", {"wood": 42.0, "cloth": 10.0, "obsidian": 3.0, "cacao": 3.0}, {"cacao": 1.5, "fine_textiles": 0.25}, {"pipiltin": 2}, ["Obsidian Mirror Chamber"], "Future hook for rival disruption."),
					_palace_structure_node("tez_scarcity_granary_office", god_id, 2, "Scarcity Granary Office", "An office that tracks shortages, market bottlenecks and which goods can be pressured.", {"wood": 40.0, "cloth": 8.0, "tools": 2.0, "cacao": 2.0}, {"cacao": 1.25, "tools": 0.25}, {"pipiltin": 2}, ["Night Ledger Office"], "Future hook for market pressure leverage."),
					_palace_structure_node("tez_whispering_servant_network", god_id, 2, "Whispering Servant Network", "A staff network of servants, messengers and obligated listeners around rival households.", {"wood": 34.0, "cloth": 10.0, "cacao": 4.0}, {"cacao": 1.5, "cloth": 0.5}, {"pipiltin": 1, "tlacotin": 5}, ["Smoke Messenger Room"], "Future hook for intrigue and hidden pressure.")
				]},
				{"tier": 3, "title": "Level 3 — Black Mirror Council", "structures": [
					_palace_structure_node("tez_black_mirror_council", god_id, 3, "Black Mirror Council", "A dangerous council for coordinating hidden pressure, scarcity plays and rival manipulation.", {"wood": 82.0, "cloth": 20.0, "obsidian": 6.0, "fine_textiles": 1.0}, {"cacao": 2.5, "obsidian": 0.5, "fine_textiles": 0.25}, {"tlamacazqueh": 2, "pipiltin": 3}, ["Rival Shadow Court or Scarcity Granary Office"], "Stronger hidden pressure and manipulation hooks."),
					_palace_structure_node("tez_broken_oath_chamber", god_id, 3, "Broken Oath Chamber", "A private chamber for dangerous bargains, threats and promises that should never be spoken publicly.", {"wood": 70.0, "cloth": 16.0, "ritual_goods": 5.0, "obsidian": 4.0}, {"cacao": 2.0, "ritual_goods": 0.75}, {"tlamacazqueh": 2, "pipiltin": 2}, ["Whispering Servant Network"], "Future hook for dangerous rival-pressure tools.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Tezcatlipoca", "structures": [
					_palace_structure_node("tez_great_court", god_id, 4, "Great Court of Tezcatlipoca", "A hidden-palace court where scarcity, fear, ambition and rival weakness are treated as instruments of power.", {"wood": 145.0, "cloth": 35.0, "obsidian": 10.0, "ritual_goods": 8.0, "fine_textiles": 2.0}, {"cacao": 4.0, "obsidian": 1.0, "fine_textiles": 0.5}, {"tlamacazqueh": 3, "pipiltin": 6}, ["Black Mirror Council", "Broken Oath Chamber"], "High-level scarcity, intrigue and rival-pressure authority.")
				]}
			]
		"quetzalcoatl":
			return [
				{"tier": 1, "title": "Level 1 — Feathered Audience Hall", "structures": [
					_palace_structure_node("quetz_feathered_audience_hall", god_id, 1, "Feathered Audience Hall", "An elegant audience hall where the palace presents orderly, legitimate authority to guests and retainers.", {"wood": 20.0, "cloth": 6.0, "cacao": 1.0}, {"cacao": 0.75, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for ruler-facing legitimacy."),
					_palace_structure_node("quetz_tribute_record_office", god_id, 1, "Tribute Record Office", "A record office for tribute promises, deliveries, stored goods and ruler-facing reliability.", {"wood": 18.0, "cloth": 5.0, "tools": 1.0}, {"cacao": 0.5, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for court-need donation clarity."),
					_palace_structure_node("quetz_scribe_mat_court", god_id, 1, "Scribe Mat Court", "A court of mats, painted records and formal speech for orderly palace administration.", {"wood": 18.0, "cloth": 5.0, "cacao": 1.0}, {"cacao": 0.75, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for order and palace administration.")
				]},
				{"tier": 2, "title": "Level 2 — Diplomatic Reception Wing", "structures": [
					_palace_structure_node("quetz_diplomatic_reception_court", god_id, 2, "Diplomatic Reception Court", "A reception court for rival houses, messengers, ruler agents and formal negotiation.", {"wood": 42.0, "cloth": 12.0, "cacao": 3.0, "fine_textiles": 1.0}, {"cacao": 1.5, "fine_textiles": 0.25}, {"pipiltin": 2}, ["Feathered Audience Hall"], "Future negotiation and recognition hooks."),
					_palace_structure_node("quetz_law_speech_chamber", god_id, 2, "Law-Speech Chamber", "A chamber where obligations, promises and public judgements are spoken before witnesses.", {"wood": 38.0, "cloth": 10.0, "ritual_goods": 2.0}, {"cacao": 1.0, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 2}, ["Scribe Mat Court"], "Future hook for trust and formal legitimacy."),
					_palace_structure_node("quetz_market_wind_gallery", god_id, 2, "Market-Wind Gallery", "A palace gallery where trade information, tribute expectation and visible order are brought together.", {"wood": 40.0, "cloth": 10.0, "tools": 2.0, "cacao": 2.0}, {"cacao": 1.0, "cloth": 0.5}, {"pipiltin": 2}, ["Tribute Record Office"], "Future hook for palace performance and credibility.")
				]},
				{"tier": 3, "title": "Level 3 — Feathered Legitimacy Court", "structures": [
					_palace_structure_node("quetz_feathered_legitimacy_court", god_id, 3, "Feathered Legitimacy Court", "A major court of record, ceremony and noble reception for proving the house deserves recognition.", {"wood": 82.0, "cloth": 22.0, "cacao": 5.0, "fine_textiles": 2.0}, {"cacao": 2.0, "fine_textiles": 0.5}, {"pipiltin": 4}, ["Diplomatic Reception Court or Law-Speech Chamber"], "Stronger recognition-route and tribute credibility hooks."),
					_palace_structure_node("quetz_ruler_witness_hall", god_id, 3, "Ruler Witness Hall", "A formal hall designed to make obligation, success and legitimacy visible to agents of higher authority.", {"wood": 74.0, "cloth": 18.0, "ritual_goods": 4.0, "fine_textiles": 1.0}, {"cacao": 2.0, "ritual_goods": 0.5, "fine_textiles": 0.25}, {"tlamacazqueh": 1, "pipiltin": 3}, ["Market-Wind Gallery"], "Future hook for high-trust ruler-facing display.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Quetzalcoatl", "structures": [
					_palace_structure_node("quetz_great_court", god_id, 4, "Great Court of Quetzalcoatl", "A full legitimacy court for tribute reliability, palace order, recognition and ruler-facing trust.", {"wood": 150.0, "cloth": 40.0, "cacao": 8.0, "ritual_goods": 8.0, "fine_textiles": 3.0}, {"cacao": 3.5, "fine_textiles": 0.75}, {"tlamacazqueh": 2, "pipiltin": 6}, ["Feathered Legitimacy Court", "Ruler Witness Hall"], "Full legitimacy palace authority and late recognition-route support.")
				]}
			]
	return []


func get_built_palace_structure_ids() -> Array[String]:
	return _get_palace_system().get_built_palace_structure_ids(self)

func _is_palace_structure_built(structure_id: String) -> bool:
	return _get_palace_system().is_palace_structure_built(self, structure_id)

func _apply_palace_structure_statuses(tiers: Array[Dictionary], route_id: String) -> void:
	_get_palace_system().apply_palace_structure_statuses(self, tiers, route_id)

func _palace_structure_by_id(structure_id: String, route_id: String = "") -> Dictionary:
	return _get_palace_system().palace_structure_by_id(self, structure_id, route_id)

func _palace_structure_id_by_name(god_id: String, structure_name: String) -> String:
	return _get_palace_system().palace_structure_id_by_name(self, god_id, structure_name)

func _palace_any_built_in_tier(god_id: String, tier_number: int) -> bool:
	return _get_palace_system().palace_any_built_in_tier(self, god_id, tier_number)

func _palace_prerequisite_check(god_id: String, prerequisite_text: String) -> Dictionary:
	return _get_palace_system().palace_prerequisite_check(self, god_id, prerequisite_text)

func _palace_prerequisites_met(structure: Dictionary) -> Dictionary:
	return _get_palace_system().palace_prerequisites_met(self, structure)

func _can_pay_palace_build_cost(cost: Dictionary) -> Dictionary:
	return _get_palace_system().can_pay_palace_build_cost(self, cost)

func can_build_palace_structure(structure_id: String) -> Dictionary:
	return _get_palace_system().can_build_palace_structure(self, structure_id)

func build_palace_structure(structure_id: String) -> Dictionary:
	return _get_palace_system().build_palace_structure(self, structure_id)

func _palace_built_structure_ids_in_tree_order(god_id: String) -> Array[String]:
	return _get_palace_system().palace_built_structure_ids_in_tree_order(self, god_id)

func _palace_staff_group_order() -> Array[String]:
	return _get_palace_system().palace_staff_group_order()

func get_palace_staff_capacity() -> Dictionary:
	return _get_palace_system().get_palace_staff_capacity(self)

func get_palace_staff_summary() -> Dictionary:
	return _get_palace_system().get_palace_staff_summary(self)

func get_palace_structure_operation_preview() -> Dictionary:
	return _get_palace_system().get_palace_structure_operation_preview(self)

func get_palace_structure_runtime_statuses() -> Dictionary:
	return _get_palace_system().get_palace_structure_runtime_statuses(self)

func get_active_palace_structure_ids() -> Array[String]:
	return _get_palace_system().get_active_palace_structure_ids(self)

func get_inactive_palace_structure_ids() -> Array[String]:
	return _get_palace_system().get_inactive_palace_structure_ids(self)

func _resolve_palace_structure_operation(pay_costs: bool) -> Dictionary:
	return _get_palace_system().resolve_palace_structure_operation(self, pay_costs)

func _pay_palace_maintenance() -> void:
	_get_palace_system().pay_palace_maintenance(self)

func get_palace_total_maintenance() -> Dictionary:
	return _get_palace_system().get_palace_total_maintenance(self)

func get_palace_required_staff() -> Dictionary:
	return _get_palace_system().get_palace_required_staff(self)

func get_palace_level() -> int:
	return _get_palace_system().get_palace_level(self)

func get_palace_dedication_routes() -> Array[Dictionary]:
	return _get_palace_system().get_palace_dedication_routes(self)

func _palace_authority_route_headline(god_id: String, active_count: int) -> String:
	return _get_palace_system().palace_authority_route_headline(god_id, active_count)

func _palace_authority_route_body(god_id: String, active_count: int) -> String:
	return _get_palace_system().palace_authority_route_body(god_id, active_count)

func _palace_authority_structure_row(structure_id: String, status: Dictionary, god_id: String) -> Dictionary:
	return _get_palace_system().palace_authority_structure_row(self, structure_id, status, god_id)

func _palace_next_locked_authority_rows(god_id: String, limit: int = 4) -> Array[Dictionary]:
	return _get_palace_system().palace_next_locked_authority_rows(self, god_id, limit)

func get_palace_authority_summary() -> Dictionary:
	return _get_palace_system().get_palace_authority_summary(self)

func _tlaloc_controlled_natural_pressure_events() -> Array[Dictionary]:
	# v0.28 uses a deterministic test calendar instead of a random natural-event
	# system. These events do not apply gameplay effects yet; they exist so the
	# Tlaloc Palace route can prove its information/forecasting identity safely.
	return [
		{
			"id": "dry_wind_signs",
			"target_veintena": 4,
			"name": "Dry Wind Signs",
			"category": "Drought pressure",
			"summary": "Fields and canals show early dry-season stress.",
			"severity": "Moderate",
			"affected_goods": ["maize", "cacao"],
			"duration": "2 Veintenas",
			"preparation": "Protect maize stores, avoid over-selling food, and prepare rain rites or irrigation responses."
		},
		{
			"id": "heavy_rain_risk",
			"target_veintena": 7,
			"name": "Heavy Rain Risk",
			"category": "Flood / water pressure",
			"summary": "Lake and canal signs suggest a heavy rain period.",
			"severity": "Light to moderate",
			"affected_goods": ["wood", "maize"],
			"duration": "1 Veintena",
			"preparation": "Protect wood stocks, watch canal-linked production, and prepare for temporary field disruption."
		},
		{
			"id": "field_pest_pressure",
			"target_veintena": 10,
			"name": "Field Pest Pressure",
			"category": "Crop / pest pressure",
			"summary": "Field samples and omen records suggest pest pressure in the growing cycle.",
			"severity": "Moderate",
			"affected_goods": ["maize", "cotton"],
			"duration": "2–3 Veintenas",
			"preparation": "Build food buffer, avoid relying on one crop chain, and keep tools available for field response."
		},
		{
			"id": "clear_sky_window",
			"target_veintena": 13,
			"name": "Clear Sky Window",
			"category": "Favourable weather window",
			"summary": "The sky-reading basin suggests a calmer period for hauling, drying and outdoor work.",
			"severity": "Favourable",
			"affected_goods": ["wood", "cotton", "cloth"],
			"duration": "1–2 Veintenas",
			"preparation": "Plan construction and transport-heavy production while weather pressure is low."
		},
		{
			"id": "late_water_warning",
			"target_veintena": 16,
			"name": "Late Water Warning",
			"category": "Rain / canal uncertainty",
			"summary": "Late-year water signs are unstable and could disrupt estate timing.",
			"severity": "Uncertain",
			"affected_goods": ["maize", "tools"],
			"duration": "Unknown",
			"preparation": "Keep reserves flexible and avoid spending all tools before late-year obligations are known."
		}
	]

func _veintena_distance_to(target_veintena: int) -> int:
	var target: int = clampi(target_veintena, 1, 18)
	var distance: int = target - current_veintena
	if distance < 0:
		distance += 18
	return distance

func _tlaloc_active_structure_tier() -> int:
	if get_palace_dedicated_god() != GOD_TLALOC:
		return 0
	var highest: int = 0
	var statuses: Dictionary = get_palace_structure_runtime_statuses()
	for structure_id: String in _palace_built_structure_ids_in_tree_order(GOD_TLALOC):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(structure_id, GOD_TLALOC)
		if structure.is_empty():
			continue
		highest = maxi(highest, int(structure.get("tier", 1)))
	return highest

func _tlaloc_active_structure_names() -> Array[String]:
	var names: Array[String] = []
	if get_palace_dedicated_god() != GOD_TLALOC:
		return names
	var statuses: Dictionary = get_palace_structure_runtime_statuses()
	for structure_id: String in _palace_built_structure_ids_in_tree_order(GOD_TLALOC):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(structure_id, GOD_TLALOC)
		if not structure.is_empty():
			names.append(String(structure.get("name", structure_id)))
	return names

func _tlaloc_forecast_range_for_tier(tier: int) -> int:
	match tier:
		1:
			return 3
		2:
			return 6
		3:
			return 10
		4:
			return 18
	return 0

func _tlaloc_forecast_detail_label(tier: int) -> String:
	match tier:
		1:
			return "Basic near warning"
		2:
			return "Extended warning"
		3:
			return "Detailed forecast"
		4:
			return "Deep natural calendar"
	return "Dormant"

func _format_veintena_distance(distance: int) -> String:
	if distance <= 0:
		return "Current Veintena"
	if distance == 1:
		return "Next Veintena"
	return "In " + str(distance) + " Veintenas"

func _format_resource_id_list(resource_ids: Array) -> String:
	var parts: Array[String] = []
	for resource_variant: Variant in resource_ids:
		parts.append(get_resource_name(String(resource_variant)))
	if parts.is_empty():
		return "Unknown"
	return ", ".join(parts)

func _tlaloc_forecast_row(event: Dictionary, detail_tier: int, distance: int) -> Dictionary:
	var name: String = "Unclear natural pressure"
	var category: String = "Natural pressure"
	var severity: String = "Hidden"
	var affected_goods: String = "Hidden"
	var duration: String = "Hidden"
	var preparation: String = "Build active Tlaloc structures to reveal preparation advice."
	var summary_text: String = "The palace senses pressure in the natural calendar, but details are still unclear."
	if detail_tier >= 1:
		category = String(event.get("category", category))
		summary_text = String(event.get("summary", summary_text))
	if detail_tier >= 2:
		name = String(event.get("name", name))
	if detail_tier >= 3:
		severity = String(event.get("severity", severity))
		affected_goods = _format_resource_id_list(event.get("affected_goods", []) as Array)
		duration = String(event.get("duration", duration))
	if detail_tier >= 4:
		preparation = String(event.get("preparation", preparation))
	return {
		"id": String(event.get("id", "natural_pressure")),
		"name": name,
		"category": category,
		"timing": _format_veintena_distance(distance),
		"turns_until": distance,
		"target_veintena": int(event.get("target_veintena", 1)),
		"summary": summary_text,
		"severity": severity,
		"affected_goods": affected_goods,
		"duration": duration,
		"preparation": preparation,
		"detail_tier": detail_tier
	}

func get_tlaloc_natural_calendar_forecast() -> Dictionary:
	var dedicated: bool = get_palace_dedicated_god() == GOD_TLALOC
	var detail_tier: int = _tlaloc_active_structure_tier()
	var forecast_range: int = _tlaloc_forecast_range_for_tier(detail_tier)
	var rows: Array[Dictionary] = []
	var hidden_count: int = 0
	for event: Dictionary in _tlaloc_controlled_natural_pressure_events():
		var distance: int = _veintena_distance_to(int(event.get("target_veintena", 1)))
		if dedicated and detail_tier > 0 and distance <= forecast_range:
			rows.append(_tlaloc_forecast_row(event, detail_tier, distance))
		else:
			hidden_count += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("turns_until", 0)) < int(b.get("turns_until", 0))
	)
	var headline: String = "Tlaloc foresight unavailable"
	var summary_text: String = "Dedicate the Palace to Tlaloc, then build and maintain active Tlaloc structures to reveal natural pressure before rivals can react."
	if dedicated and detail_tier <= 0:
		headline = "Tlaloc foresight dormant"
		summary_text = "The palace is dedicated to Tlaloc, but no active Tlaloc palace structures are maintained and staffed this Veintena."
	elif dedicated and detail_tier > 0:
		headline = "Tlaloc Natural Calendar Foresight — " + _tlaloc_forecast_detail_label(detail_tier)
		summary_text = "Active Tlaloc structures reveal natural pressures up to " + str(forecast_range) + " Veintenas ahead. This is a controlled prototype forecast; it does not apply event effects yet."
	return {
		"available": dedicated,
		"active": dedicated and detail_tier > 0,
		"detail_tier": detail_tier,
		"detail_label": _tlaloc_forecast_detail_label(detail_tier),
		"forecast_range_veintenas": forecast_range,
		"current_veintena": current_veintena,
		"headline": headline,
		"summary": summary_text,
		"active_structures": _tlaloc_active_structure_names(),
		"events": rows,
		"visible_event_count": rows.size(),
		"hidden_event_count": hidden_count,
		"mechanics_note": "Forecast rows are information only in v0.28. They do not yet alter production, markets, yields, disasters or rival behaviour."
	}


func _tezcatlipoca_active_structure_tier() -> int:
	if get_palace_dedicated_god() != GOD_TEZCATLIPOCA:
		return 0
	var highest: int = 0
	var statuses: Dictionary = get_palace_structure_runtime_statuses()
	for structure_id: String in _palace_built_structure_ids_in_tree_order(GOD_TEZCATLIPOCA):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(structure_id, GOD_TEZCATLIPOCA)
		if structure.is_empty():
			continue
		highest = maxi(highest, int(structure.get("tier", 1)))
	return highest

func _tezcatlipoca_active_structure_names() -> Array[String]:
	var names: Array[String] = []
	if get_palace_dedicated_god() != GOD_TEZCATLIPOCA:
		return names
	var statuses: Dictionary = get_palace_structure_runtime_statuses()
	for structure_id: String in _palace_built_structure_ids_in_tree_order(GOD_TEZCATLIPOCA):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(structure_id, GOD_TEZCATLIPOCA)
		if not structure.is_empty():
			names.append(String(structure.get("name", structure_id)))
	return names

func _tezcatlipoca_pressure_detail_label(tier: int) -> String:
	match tier:
		1:
			return "First pressure signs"
		2:
			return "Named shortages and rivals"
		3:
			return "Leverage reading"
		4:
			return "Deep mirror council"
	return "Dormant"

func _tezcatlipoca_market_pressure_limit(tier: int) -> int:
	match tier:
		1:
			return 2
		2:
			return 4
		3:
			return 6
		4:
			return 8
	return 0

func _tezcatlipoca_pressure_score(good: Dictionary) -> float:
	var score: float = 0.0
	var label: String = String(good.get("label", ""))
	var coverage: float = float(good.get("coverage", 0.0))
	var current_value: float = float(good.get("current_value", good.get("projected_value", 0.0)))
	var base_value: float = maxf(0.01, float(good.get("base_value", 1.0)))
	match label:
		"Crisis":
			score += 100.0
		"Shortage":
			score += 70.0
		"Tight":
			score += 40.0
		"Abundant":
			score -= 20.0
	if coverage > 0.0:
		score += maxf(0.0, 3.0 - coverage) * 12.0
	score += maxf(0.0, (current_value / base_value) - 1.0) * 25.0
	return score

func _tezcatlipoca_market_pressure_row(good: Dictionary, detail_tier: int) -> Dictionary:
	var good_id: String = String(good.get("id", ""))
	var good_name: String = String(good.get("name", get_resource_name(good_id)))
	var label: String = String(good.get("label", "Unknown"))
	var trend: String = String(good.get("trend", "Stable"))
	var coverage_text: String = "Hidden"
	var value_text: String = "Hidden"
	var leverage_text: String = "Pressure exists, but the mirror has not revealed a usable hook."
	var exposure_text: String = "Hidden"
	if detail_tier >= 2:
		coverage_text = _format_amount(float(good.get("coverage", 0.0)))
		exposure_text = label + " / " + trend
	if detail_tier >= 3:
		value_text = _format_amount(float(good.get("current_value", good.get("projected_value", 0.0))))
		leverage_text = "Future hook: watch this good for market pressure, rival procurement pressure or scarcity manipulation."
	if detail_tier >= 4:
		leverage_text = "Deep mirror hook: future Tezcatlipoca actions may pressure this good, exploit shortage, or turn rival demand against them."
	return {
		"id": good_id,
		"name": good_name,
		"pressure": label,
		"trend": trend,
		"coverage": coverage_text,
		"current_value": value_text,
		"exposure": exposure_text,
		"leverage": leverage_text,
		"score": _tezcatlipoca_pressure_score(good),
		"detail_tier": detail_tier
	}

func _tezcatlipoca_rival_pressure_hooks(detail_tier: int) -> Array[Dictionary]:
	return _get_rival_system().tezcatlipoca_rival_pressure_hooks(detail_tier)

func get_tezcatlipoca_pressure_overview() -> Dictionary:
	var dedicated: bool = get_palace_dedicated_god() == GOD_TEZCATLIPOCA
	var detail_tier: int = _tezcatlipoca_active_structure_tier()
	var market_rows: Array[Dictionary] = []
	if dedicated and detail_tier > 0:
		var goods: Array = estimate_market_resolution().get("goods", []) as Array
		var pressure_goods: Array[Dictionary] = []
		for good_variant: Variant in goods:
			if not (good_variant is Dictionary):
				continue
			var good: Dictionary = good_variant as Dictionary
			var label: String = String(good.get("label", ""))
			var score: float = _tezcatlipoca_pressure_score(good)
			if score > 0.0 or label == "Crisis" or label == "Shortage" or label == "Tight":
				pressure_goods.append(good)
		pressure_goods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _tezcatlipoca_pressure_score(a) > _tezcatlipoca_pressure_score(b)
		)
		var limit: int = _tezcatlipoca_market_pressure_limit(detail_tier)
		for index: int in range(mini(limit, pressure_goods.size())):
			market_rows.append(_tezcatlipoca_market_pressure_row(pressure_goods[index], detail_tier))
	var headline: String = "Tezcatlipoca pressure unavailable"
	var summary_text: String = "Dedicate the Palace to Tezcatlipoca, then build and maintain active Tezcatlipoca structures to read scarcity, rival pressure and hidden market leverage."
	if dedicated and detail_tier <= 0:
		headline = "Tezcatlipoca pressure dormant"
		summary_text = "The palace is dedicated to Tezcatlipoca, but no active Tezcatlipoca palace structures are maintained and staffed this Veintena."
	elif dedicated and detail_tier > 0:
		headline = "Tezcatlipoca Scarcity Mirror — " + _tezcatlipoca_pressure_detail_label(detail_tier)
		summary_text = "Active Tezcatlipoca structures reveal market pressure and rival vulnerability hooks. This is an information-only prototype; it does not manipulate goods, sabotage rivals or alter prices yet."
	return {
		"available": dedicated,
		"active": dedicated and detail_tier > 0,
		"detail_tier": detail_tier,
		"detail_label": _tezcatlipoca_pressure_detail_label(detail_tier),
		"headline": headline,
		"summary": summary_text,
		"active_structures": _tezcatlipoca_active_structure_names(),
		"market_pressure_rows": market_rows,
		"rival_pressure_rows": _tezcatlipoca_rival_pressure_hooks(detail_tier),
		"visible_market_pressure_count": market_rows.size(),
		"visible_rival_pressure_count": _tezcatlipoca_rival_pressure_hooks(detail_tier).size(),
		"mechanics_note": "Tezcatlipoca pressure rows are information-only in v0.29. They do not yet change market stock, prices, rival behaviour, sabotage, prestige or diplomacy."
	}


func _quetzalcoatl_active_structure_tier() -> int:
	if get_palace_dedicated_god() != GOD_QUETZALCOATL:
		return 0
	var max_tier: int = 0
	var statuses: Dictionary = get_palace_structure_runtime_statuses()
	for structure_id: String in _palace_built_structure_ids_in_tree_order(GOD_QUETZALCOATL):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(structure_id, GOD_QUETZALCOATL)
		max_tier = maxi(max_tier, int(structure.get("tier", structure.get("level", 0))))
	return max_tier

func _quetzalcoatl_active_structure_names() -> Array[String]:
	var names: Array[String] = []
	if get_palace_dedicated_god() != GOD_QUETZALCOATL:
		return names
	var statuses: Dictionary = get_palace_structure_runtime_statuses()
	for structure_id: String in _palace_built_structure_ids_in_tree_order(GOD_QUETZALCOATL):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(structure_id, GOD_QUETZALCOATL)
		if not structure.is_empty():
			names.append(String(structure.get("name", structure_id)))
	return names

func _quetzalcoatl_detail_label(tier: int) -> String:
	match tier:
		1:
			return "Household legitimacy signs"
		2:
			return "Tribute credibility reading"
		3:
			return "Ruler-facing trust hooks"
		4:
			return "Great legitimacy court"
	return "Dormant"

func _quetzalcoatl_legitimacy_rows(detail_tier: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if detail_tier <= 0:
		return rows
	var raw_rows: Array[Dictionary] = [
		{"id": "palace_order", "name": "Palace Order", "domain": "Court order and visible authority", "summary": "The palace can present itself as orderly, deliberate and ruler-facing.", "future_hook": "Future hook: improves palace-performance confidence and reduces ambiguity around obligations."},
		{"id": "tribute_credibility", "name": "Tribute Credibility", "domain": "Demand delivery and tribute reliability", "summary": "The house can make promised goods and delivered goods appear more credible to higher authority.", "future_hook": "Future hook: clearer demand delivery quality and better ruler-facing trust."},
		{"id": "recognition_route", "name": "Recognition Route", "domain": "Regional legitimacy and public reputation", "summary": "The palace can frame estate success as lawful, civilised and worthy of recognition.", "future_hook": "Future hook: supports future formal recognition once that system is designed."},
		{"id": "court_witness", "name": "Ruler Witness", "domain": "Agents, witnesses and formal reporting", "summary": "The palace is prepared to impress agents of higher authority and make obligations visible.", "future_hook": "Future hook: stronger effect on court presentation and formal recognition."}
	]
	var max_rows: int = 1
	if detail_tier >= 2:
		max_rows = 2
	if detail_tier >= 3:
		max_rows = 3
	if detail_tier >= 4:
		max_rows = 4
	for index: int in range(mini(max_rows, raw_rows.size())):
		var source: Dictionary = raw_rows[index]
		var row: Dictionary = {
			"id": String(source.get("id", "legitimacy")),
			"name": String(source.get("name", "Legitimacy")),
			"domain": "Hidden",
			"summary": "The palace shows signs of legitimacy, but the route has not revealed clear political hooks yet.",
			"future_hook": "Build higher active Quetzalcoatl structures to reveal future legitimacy and recognition hooks.",
			"detail_tier": detail_tier
		}
		if detail_tier >= 1:
			row["domain"] = String(source.get("domain", "Legitimacy"))
			row["summary"] = String(source.get("summary", row["summary"]))
		if detail_tier >= 3:
			row["future_hook"] = String(source.get("future_hook", row["future_hook"]))
		rows.append(row)
	return rows

func _quetzalcoatl_obligation_rows(detail_tier: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if detail_tier <= 0:
		return rows
	var raw_rows: Array[Dictionary] = [
		{"id": "raw_demand", "name": "Raw Demand Credibility", "domain": "Maize, wood, cotton, cacao, obsidian", "summary": "Future court needs can be read as material obligations rather than vague court pressure.", "future_hook": "Future hook: improves clarity around the Raw court-need slot."},
		{"id": "processed_demand", "name": "Processed Demand Credibility", "domain": "Tools, weapons, cloth", "summary": "The palace can prepare records that make processed-good delivery more legible.", "future_hook": "Future hook: improves clarity around the Processed court-need slot."},
		{"id": "luxury_special_demand", "name": "Luxury / Special Demand Credibility", "domain": "Fine textiles, captives and high-status goods", "summary": "The palace can frame elite deliveries as legitimate service rather than mere surplus spending.", "future_hook": "Future hook: improves clarity around the Luxury/Special court-need slot."}
	]
	var max_rows: int = 1
	if detail_tier >= 2:
		max_rows = 2
	if detail_tier >= 3:
		max_rows = 3
	for index: int in range(mini(max_rows, raw_rows.size())):
		var source: Dictionary = raw_rows[index]
		var row: Dictionary = {
			"id": String(source.get("id", "obligation")),
			"name": String(source.get("name", "Obligation")),
			"domain": "Hidden",
			"summary": "The palace senses future obligation pressure, but details are not implemented yet.",
			"future_hook": "Future hook: court need donation and presentation hooks can use this route later.",
			"detail_tier": detail_tier
		}
		if detail_tier >= 2:
			row["domain"] = String(source.get("domain", "Demand goods"))
			row["summary"] = String(source.get("summary", row["summary"]))
		if detail_tier >= 4:
			row["future_hook"] = String(source.get("future_hook", row["future_hook"]))
		rows.append(row)
	return rows

func get_quetzalcoatl_legitimacy_overview() -> Dictionary:
	var dedicated: bool = get_palace_dedicated_god() == GOD_QUETZALCOATL
	var detail_tier: int = _quetzalcoatl_active_structure_tier()
	var headline: String = "Quetzalcoatl legitimacy unavailable"
	var summary_text: String = "Dedicate the Palace to Quetzalcoatl, then build and maintain active Quetzalcoatl structures to reveal legitimacy, recognition, tribute credibility and palace-trust hooks."
	if dedicated and detail_tier <= 0:
		headline = "Quetzalcoatl legitimacy dormant"
		summary_text = "The palace is dedicated to Quetzalcoatl, but no active Quetzalcoatl palace structures are maintained and staffed this Veintena."
	elif dedicated and detail_tier > 0:
		headline = "Quetzalcoatl Legitimacy Court — " + _quetzalcoatl_detail_label(detail_tier)
		summary_text = "Active Quetzalcoatl structures reveal legitimacy, tribute credibility and recognition-route hooks. This route is information-only; court-need donations create prestige separately by base value."
	var legitimacy_rows: Array[Dictionary] = []
	var obligation_rows: Array[Dictionary] = []
	if dedicated and detail_tier > 0:
		legitimacy_rows = _quetzalcoatl_legitimacy_rows(detail_tier)
		obligation_rows = _quetzalcoatl_obligation_rows(detail_tier)
	return {
		"available": dedicated,
		"active": dedicated and detail_tier > 0,
		"detail_tier": detail_tier,
		"detail_label": _quetzalcoatl_detail_label(detail_tier),
		"headline": headline,
		"summary": summary_text,
		"active_structures": _quetzalcoatl_active_structure_names(),
		"legitimacy_rows": legitimacy_rows,
		"obligation_rows": obligation_rows,
		"visible_legitimacy_count": legitimacy_rows.size(),
		"visible_obligation_count": obligation_rows.size(),
		"mechanics_note": "Quetzalcoatl rows are information-only. They do not add recognition, royal favour, local stability or diplomacy effects; court-need donations create prestige separately by base value."
	}



# -----------------------------------------------------------------------------
# Palace Court Needs / Donation Prestige v0.36
# -----------------------------------------------------------------------------
# Court needs are not binary fulfilment quests. They are visible ruler/court needs.
# Donating a needed good consumes real stock and grants Prestige according to the
# base value of the donated good. Prestige is a score, never a currency.

func _palace_ruler_demand_sets() -> Array[Dictionary]:
	return _get_palace_system().palace_ruler_demand_sets()

func _current_palace_ruler_demand_index() -> int:
	return _get_palace_system().current_palace_ruler_demand_index(self)

func _palace_ruler_demand_cycle_window(index: int) -> Dictionary:
	return _get_palace_system().palace_ruler_demand_cycle_window(index)

func _palace_ruler_demand_deadline_summary(index: int = -1) -> Dictionary:
	return _get_palace_system().palace_ruler_demand_deadline_summary(self, index)

func _report_palace_ruler_demand_cycle_transition(previous_index: int, previous_title: String, previous_completion: Dictionary) -> void:
	_get_palace_system().report_palace_ruler_demand_cycle_transition(self, previous_index, previous_title, previous_completion)

func _current_palace_ruler_demand_set() -> Dictionary:
	return _get_palace_system().current_palace_ruler_demand_set(self)

func _palace_ruler_demand_cycle_id() -> String:
	return _get_palace_system().palace_ruler_demand_cycle_id(self)

func _palace_ruler_demand_raw_row_by_slot(slot_id: String) -> Dictionary:
	return _get_palace_system().palace_ruler_demand_raw_row_by_slot(self, slot_id)

func _resource_base_value(resource_id: String) -> float:
	return _get_prestige_system().resource_base_value(self, resource_id)

func get_player_prestige() -> float:
	return player_prestige

func add_player_prestige(amount: float, source_id: String, detail: String, context: Dictionary = {}) -> Dictionary:
	if absf(amount) <= 0.0001:
		return {"ok": true, "amount": 0.0, "prestige": player_prestige}
	var before: float = player_prestige
	player_prestige += amount
	var record: Dictionary = {
		"veintena": current_veintena,
		"source_id": source_id,
		"detail": detail,
		"amount": amount,
		"prestige_before": before,
		"prestige_after": player_prestige,
		"context": context.duplicate(true)
	}
	prestige_history.append(record)
	return {"ok": true, "amount": amount, "prestige": player_prestige, "record": record}

func get_savvy_trade_prestige_scale() -> float:
	return _get_prestige_system().get_savvy_trade_prestige_scale()

func get_savvy_trade_prestige_for_line(resource_id: String, amount: float, average_unit_value: float) -> Dictionary:
	return _get_prestige_system().get_savvy_trade_prestige_for_line(self, resource_id, amount, average_unit_value)

func get_savvy_trade_prestige_preview(trade_lines: Array) -> Dictionary:
	return _get_prestige_system().get_savvy_trade_prestige_preview(self, trade_lines)

func record_savvy_trade_prestige(trade_lines: Array, detail: String = "Savvy market trade") -> Dictionary:
	return _get_prestige_system().record_savvy_trade_prestige(self, trade_lines, detail)

func get_economic_prestige_summary() -> Dictionary:
	return _get_prestige_system().get_economic_prestige_summary(self)

func _format_signed_prestige(amount: float) -> String:
	return _get_prestige_system().format_signed_prestige(amount)

func _flower_war_result_prestige_value(result: String) -> float:
	return _get_prestige_system().flower_war_result_prestige_value(result)

func _flower_war_prestige_breakdown(report: Dictionary) -> Dictionary:
	return _get_prestige_system().flower_war_prestige_breakdown(report)

func _flower_war_preview_prestige_for_attack(result: String, defender_casualties: int, captives: int, loot_value: float) -> Dictionary:
	return _get_prestige_system().flower_war_preview_prestige_for_attack(result, defender_casualties, captives, loot_value)

func _flower_war_preview_prestige_for_defence(result: String, enemy_casualties: int) -> Dictionary:
	return _get_prestige_system().flower_war_preview_prestige_for_defence(result, enemy_casualties)

func get_flower_war_prestige_preview(report: Dictionary) -> Dictionary:
	return _get_prestige_system().flower_war_prestige_breakdown(report)

func _prestige_text_from_breakdown(breakdown: Dictionary) -> String:
	return _get_prestige_system().prestige_text_from_breakdown(breakdown)

func _apply_flower_war_prestige_to_report(report: Dictionary) -> Dictionary:
	return _get_prestige_system().apply_flower_war_prestige_to_report(self, report)

func get_prestige_history() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for item: Dictionary in prestige_history:
		output.append(item.duplicate(true))
	return output

func get_rival_house_definitions() -> Array[Dictionary]:
	return _get_rival_system().get_rival_house_definitions()

func get_rival_pressure_hooks(detail_tier: int = 3) -> Array[Dictionary]:
	return _get_rival_system().tezcatlipoca_rival_pressure_hooks(detail_tier)

func get_rival_market_note(resource_id: String) -> String:
	return _get_rival_system().market_note_for_resource(resource_id)

func _default_rival_prestige_values() -> Dictionary:
	return _get_rival_system().default_rival_prestige_values()

func _prestige_house_name(house_id: String) -> String:
	return _get_prestige_system().prestige_house_name(house_id)

func get_rival_prestige() -> Dictionary:
	return _get_rival_system().get_rival_prestige(self)

func set_rival_prestige(house_id: String, value: float) -> Dictionary:
	return _get_rival_system().set_rival_prestige(self, house_id, value)

func get_prestige_leaderboard() -> Array[Dictionary]:
	return _get_prestige_system().get_prestige_leaderboard(self)

func get_player_prestige_rank() -> Dictionary:
	return _get_prestige_system().get_player_prestige_rank(self)

func get_prestige_summary() -> Dictionary:
	return _get_prestige_system().get_prestige_summary(self)

func _sacrifice_prestige_option_definitions() -> Array[Dictionary]:
	return _get_religion_system().sacrifice_prestige_option_definitions()

func get_sacrifice_prestige_options() -> Array[Dictionary]:
	return _get_religion_system().get_sacrifice_prestige_options(self)

func _sacrifice_prestige_option_by_id(sacrifice_id: String) -> Dictionary:
	return _get_religion_system().sacrifice_prestige_option_by_id(sacrifice_id)

func can_sacrifice_for_prestige(sacrifice_id: String, amount: int = 1) -> Dictionary:
	return _get_religion_system().can_sacrifice_for_prestige(self, sacrifice_id, amount)

func sacrifice_for_prestige(sacrifice_id: String, amount: int = 1, god_id: String = "") -> Dictionary:
	return _get_religion_system().sacrifice_for_prestige(self, sacrifice_id, amount, god_id)

func get_sacrifice_prestige_records() -> Array[Dictionary]:
	return _get_religion_system().get_sacrifice_prestige_records(self)

func _palace_donation_records_for_cycle(cycle_id: String = "") -> Array[Dictionary]:
	return _get_palace_system().palace_donation_records_for_cycle(self, cycle_id)

func _palace_donation_records_for_cycle_slot(cycle_id: String, slot_id: String) -> Array[Dictionary]:
	return _get_palace_system().palace_donation_records_for_cycle_slot(self, cycle_id, slot_id)

func _palace_donation_total_for_cycle(cycle_id: String = "") -> Dictionary:
	return _get_palace_system().palace_donation_total_for_cycle(self, cycle_id)

func _palace_donation_total_for_slot(cycle_id: String, slot_id: String) -> Dictionary:
	return _get_palace_system().palace_donation_total_for_slot(self, cycle_id, slot_id)

func can_donate_palace_need(slot_id: String, amount: float) -> Dictionary:
	return _get_palace_system().can_donate_palace_need(self, slot_id, amount)

func donate_palace_need(slot_id: String, amount: float) -> Dictionary:
	return _get_palace_system().donate_palace_need(self, slot_id, amount)

func is_palace_ruler_demand_delivered(slot_id: String) -> bool:
	return _get_palace_system().is_palace_ruler_demand_delivered(self, slot_id)

func can_deliver_palace_ruler_demand(slot_id: String) -> Dictionary:
	return _get_palace_system().can_deliver_palace_ruler_demand(self, slot_id)

func deliver_palace_ruler_demand(slot_id: String) -> Dictionary:
	return _get_palace_system().deliver_palace_ruler_demand(self, slot_id)

func get_palace_ruler_demand_delivery_records() -> Array[Dictionary]:
	return _get_palace_system().get_palace_ruler_demand_delivery_records(self)

func _palace_ruler_demand_archive_row(raw_row: Dictionary, cycle_id: String) -> Dictionary:
	return _get_palace_system().palace_ruler_demand_archive_row(self, raw_row, cycle_id)

func _palace_ruler_demand_records_for_cycle(cycle_id: String) -> Array[Dictionary]:
	return _get_palace_system().palace_ruler_demand_records_for_cycle(self, cycle_id)

func get_palace_ruler_demand_cycle_archive() -> Array[Dictionary]:
	return _get_palace_system().get_palace_ruler_demand_cycle_archive(self)

func _palace_need_donation_summary_for_cycle(cycle_id: String, rows: Array[Dictionary] = []) -> Dictionary:
	return _get_palace_system().palace_need_donation_summary_for_cycle(self, cycle_id, rows)

func get_palace_ruler_demand_completion_summary() -> Dictionary:
	return _get_palace_system().get_palace_ruler_demand_completion_summary(self)

func _palace_ruler_demand_row(raw_row: Dictionary) -> Dictionary:
	return _get_palace_system().palace_ruler_demand_row(self, raw_row)

func get_palace_ruler_demands_summary() -> Dictionary:
	return _get_palace_system().get_palace_ruler_demands_summary(self)

func get_palace_summary() -> Dictionary:
	var dedicated_god: String = get_palace_dedicated_god()
	var dedicated: bool = dedicated_god != ""
	var route_name: String = "No dedication"
	var god_name: String = "None"
	if dedicated:
		route_name = get_palace_route_name(dedicated_god)
		god_name = _god_display_name(dedicated_god)
	return {
		"schema_version": "palace_court_needs_v0_36",
		"palace_level": get_palace_level(),
		"dedicated": dedicated,
		"dedicated_god": dedicated_god,
		"dedicated_god_name": god_name,
		"route_name": route_name,
		"power_summary": get_palace_route_power_summary(dedicated_god),
		"dedication_routes": get_palace_dedication_routes(),
		"structure_tree_shell": get_palace_structure_tree_shell(dedicated_god),
		"built_structures": get_built_palace_structure_ids(),
		"active_structures": get_active_palace_structure_ids(),
		"inactive_structures": get_inactive_palace_structure_ids(),
		"built_structure_count": get_built_palace_structure_ids().size(),
		"active_structure_count": get_active_palace_structure_ids().size(),
		"inactive_structure_count": get_inactive_palace_structure_ids().size(),
		"total_maintenance": get_palace_total_maintenance(),
		"required_staff": get_palace_required_staff(),
		"staff_capacity": get_palace_staff_capacity(),
		"staff_summary": get_palace_staff_summary(),
		"palace_operation_preview": get_palace_structure_operation_preview(),
		"last_palace_maintenance_report": last_palace_maintenance_report.duplicate(),
		"authority_summary": get_palace_authority_summary(),
		"tlaloc_forecast": get_tlaloc_natural_calendar_forecast(),
		"tezcatlipoca_pressure": get_tezcatlipoca_pressure_overview(),
		"quetzalcoatl_legitimacy": get_quetzalcoatl_legitimacy_overview(),
		"ruler_demands": get_palace_ruler_demands_summary(),
		"authority_status": String(get_palace_authority_summary().get("headline", "Palace authority not connected.")),
		"ruler_demand_status": String(get_palace_ruler_demands_summary().get("headline", "Court needs donation prototype active.")),
		"prestige_summary": get_prestige_summary(),
		"flower_war_gate_enabled": is_flower_war_palace_gate_enabled(),
		"flower_war_gate_passed": flower_war_palace_gate_passed(),
		"flower_war_gate_status": flower_war_palace_gate_status_text(),
		"implementation_note": "v0.36 reframes court needs as court needs. Donating needed goods grants Prestige based on donated amount × resource base value. Prestige is score only and is never spent."
	}

func get_flower_war_options() -> Array[Dictionary]:
	return _get_flower_war_system().get_flower_war_options(self)

func get_flower_war_defence_strategies() -> Array[Dictionary]:
	return _get_flower_war_system().get_flower_war_defence_strategies()

func start_flower_war_attack_event(option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> Dictionary:
	# Event-hook infrastructure only. This does not resolve a Flower War. It returns
	# a standard payload that UI, rivals, calendar, palace or religion systems can
	# use to open the attacking Flower War muster later.
	_ensure_warband_state()
	if not flower_war_palace_gate_passed():
		return {
			"ok": false,
			"event_type": "flower_war_attack_muster",
			"war_direction": "attack",
			"source_id": source_id,
			"context": context.duplicate(true),
			"option_id": option_id,
			"reason": flower_war_palace_gate_status_text(),
			"message": flower_war_palace_gate_status_text()
		}
	if not FLOWER_WAR_OPTIONS.has(option_id):
		option_id = "standard"
	var selected_ids: Array[String] = []
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var row: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = row
		if int(row.get("ready_warriors", 0)) > 0:
			selected_ids.append(warband_id)
	var preview: Dictionary = get_flower_war_preview_with_selected_warbands(selected_ids, option_id, "standard")
	return {
		"ok": true,
		"event_type": "flower_war_attack_muster",
		"war_direction": "attack",
		"source_id": source_id,
		"context": context.duplicate(true),
		"option_id": option_id,
		"default_provisioning_id": "standard",
		"default_selected_warbands": selected_ids,
		"preview": preview,
		"message": "Flower War attack event ready. Open the full-screen muster to choose warbands and provisions."
	}

func start_flower_war_defence_event(option_id: String = "standard", source_id: String = "rival", context: Dictionary = {}) -> Dictionary:
	# Event-hook infrastructure only. This does not resolve a Flower War. It returns
	# a standard payload that UI, rivals, calendar, palace or religion systems can
	# use to open the defensive Flower War strategy event later.
	_ensure_warband_state()
	if not FLOWER_WAR_OPTIONS.has(option_id):
		option_id = "standard"
	var preview: Dictionary = get_flower_war_defence_preview(option_id, "balanced")
	return {
		"ok": true,
		"event_type": "flower_war_defence",
		"war_direction": "defence",
		"source_id": source_id,
		"context": context.duplicate(true),
		"option_id": option_id,
		"default_strategy_id": "balanced",
		"preview": preview,
		"message": "Flower War defence event ready. Open the full-screen defence event to choose a strategy."
	}

func get_flower_war_event_hook_summary() -> Dictionary:
	return {
		"ok": true,
		"attack_hook": "start_flower_war_attack_event(option_id, source_id, context)",
		"defence_hook": "start_flower_war_defence_event(option_id, source_id, context)",
		"possible_sources": ["player", "rival", "calendar", "palace", "religion"],
		"note": "Hooks prepare event payloads only; they do not add rival AI or new combat rules."
	}

func _flower_war_defence_strategy_data(strategy_id: String) -> Dictionary:
	return _get_flower_war_system().flower_war_defence_strategy_data(strategy_id)

func get_flower_war_preview(option_id: String = "minor", doctrine_id: String = "unspecialised", provisioning_id: String = "standard") -> Dictionary:
	return _get_flower_war_system().get_single_doctrine_attack_preview(self, option_id, doctrine_id, provisioning_id)

func can_launch_flower_war(option_id: String = "minor", doctrine_id: String = "unspecialised", provisioning_id: String = "standard") -> Dictionary:
	# Backwards-compatible wrapper. The old generic launch path now sends all
	# ready warbands, so it cannot bypass warband casualties, XP or the
	# Temporary palace gate infrastructure is currently disabled. doctrine_id is ignored because each warband
	# carries its own doctrine once traits/specialisation are connected.
	return can_launch_flower_war_with_all_warbands(option_id, provisioning_id)

func launch_flower_war(option_id: String = "minor", doctrine_id: String = "unspecialised", provisioning_id: String = "standard") -> Dictionary:
	# Backwards-compatible wrapper. All current Flower War launches commit every
	# ready warband together. doctrine_id is ignored for the all-warband launch.
	return launch_flower_war_with_all_warbands(option_id, provisioning_id)

func get_last_flower_war_report() -> Dictionary:
	return last_flower_war_report.duplicate(true)

func get_flower_war_report_archive(limit_count: int = 12) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var copied: Array[Dictionary] = []
	for report_variant: Variant in flower_war_report_archive:
		if report_variant is Dictionary:
			copied.append((report_variant as Dictionary).duplicate(true))
	copied.reverse()
	var limit_value: int = max(0, limit_count)
	for report: Dictionary in copied:
		if limit_value > 0 and output.size() >= limit_value:
			break
		output.append(report)
	return output

func _archive_flower_war_report(report: Dictionary) -> void:
	if report.is_empty() or not bool(report.get("ok", false)):
		return
	var stored: Dictionary = report.duplicate(true)
	stored["archive_index"] = flower_war_report_archive.size() + 1
	stored["archive_veintena"] = current_veintena
	stored["archive_title"] = _flower_war_archive_title(stored)
	flower_war_report_archive.append(stored)
	while flower_war_report_archive.size() > 20:
		flower_war_report_archive.pop_front()

func _flower_war_archive_title(report: Dictionary) -> String:
	var direction: String = String(report.get("war_direction", "attack"))
	var option_name: String = String(report.get("option_name", "Flower War"))
	var result: String = String(report.get("result", "Unknown"))
	if direction == "defence":
		return "Defence — " + option_name + " — " + result
	return "Muster — " + option_name + " — " + result

func _flower_war_participant_rows_for_ids(selected_ids: Array[String]) -> Array[Dictionary]:
	_ensure_warband_state()
	var participants: Array[Dictionary] = []
	for warband_id: String in selected_ids:
		if not warbands.has(warband_id):
			continue
		var warband: Dictionary = warbands[warband_id] as Dictionary
		var ready: int = max(0, int(warband.get("ready_warriors", 0)))
		if ready <= 0:
			continue
		var doctrine_id: String = String(warband.get("doctrine", "unspecialised"))
		if not FLOWER_WAR_DOCTRINES.has(doctrine_id):
			doctrine_id = "unspecialised"
		var synced: Dictionary = _sync_warband_progress(warband.duplicate(true))
		warbands[warband_id] = synced
		var stats: Dictionary = _warband_combat_stats_from_warband(synced)
		participants.append({
			"id": warband_id,
			"name": String(stats.get("name", "Warband")),
			"committed": ready,
			"ready": ready,
			"injured": int(stats.get("injured", 0)),
			"level": int(synced.get("level", 1)),
			"doctrine_id": doctrine_id,
			"doctrine": doctrine_id,
			"doctrine_name": String(stats.get("doctrine_name", doctrine_id.capitalize())),
			"offence": float(stats.get("offence_modifier", 1.0)),
			"defence": float(stats.get("defence_modifier", 1.0)),
			"effective_offence": float(stats.get("effective_offence", 0.0)),
			"effective_defence": float(stats.get("effective_defence", 0.0)),
			"combat_stats": stats
		})
	return participants

func get_flower_war_preview_with_all_warbands(option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state()
	var selected_ids: Array[String] = _selected_warband_ids_or_all_ready([])
	var participants: Array[Dictionary] = _flower_war_participant_rows_for_ids(selected_ids)
	var injured_not_fighting: int = int(get_army_muster_summary().get("injured_not_fighting", 0))
	return _get_flower_war_system().get_combined_attack_preview(self, option_id, provisioning_id, participants, injured_not_fighting, selected_ids, true)

func can_launch_flower_war_with_all_warbands(option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	return _get_flower_war_system().can_launch_combined_attack(self, [], option_id, provisioning_id, true)

func launch_flower_war_with_all_warbands(option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	return _get_flower_war_system().launch_combined_attack(self, [], option_id, provisioning_id, true)

func _selected_warband_ids_or_all_ready(warband_ids: Array) -> Array[String]:
	_ensure_warband_state()
	var output: Array[String] = []
	if warband_ids.is_empty():
		for id_variant: Variant in warbands.keys():
			var id_value: String = String(id_variant)
			var warband: Dictionary = warbands[id_value] as Dictionary
			if int(warband.get("ready_warriors", 0)) > 0:
				output.append(id_value)
		return output
	for id_variant: Variant in warband_ids:
		var id_value: String = String(id_variant)
		if id_value == "" or output.has(id_value):
			continue
		if warbands.has(id_value):
			output.append(id_value)
	return output

func get_flower_war_preview_with_selected_warbands(warband_ids: Array, option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state()
	var selected_ids: Array[String] = _selected_warband_ids_or_all_ready(warband_ids)
	var participants: Array[Dictionary] = _flower_war_participant_rows_for_ids(selected_ids)
	var injured_not_fighting: int = int(get_army_muster_summary().get("injured_not_fighting", 0))
	return _get_flower_war_system().get_combined_attack_preview(self, option_id, provisioning_id, participants, injured_not_fighting, selected_ids, false)

func can_launch_flower_war_with_selected_warbands(warband_ids: Array, option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	return _get_flower_war_system().can_launch_combined_attack(self, warband_ids, option_id, provisioning_id, false)

func launch_flower_war_with_selected_warbands(warband_ids: Array, option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	return _get_flower_war_system().launch_combined_attack(self, warband_ids, option_id, provisioning_id, false)

func get_flower_war_defence_preview(option_id: String = "standard", strategy_id: String = "balanced") -> Dictionary:
	_ensure_warband_state()
	return _get_flower_war_system().get_defence_preview(self, option_id, strategy_id)

func can_resolve_flower_war_defence(option_id: String = "standard", strategy_id: String = "balanced") -> Dictionary:
	return _get_flower_war_system().can_resolve_defence(self, option_id, strategy_id)

func resolve_flower_war_defence(option_id: String = "standard", strategy_id: String = "balanced") -> Dictionary:
	return _get_flower_war_system().resolve_defence(self, option_id, strategy_id)

func _flower_war_captives_for_all_warbands(result: String, defender_casualties: int, warriors_committed: int, eagle_warriors: int) -> int:
	return _get_flower_war_system().flower_war_captives_for_all_warbands(result, defender_casualties, warriors_committed, eagle_warriors)

func _flower_war_loot_for_all_warbands(result: String, defender_casualties: int, coyote_warriors: int, warriors_committed: int, base_loot_value: float) -> Dictionary:
	return _get_flower_war_system().flower_war_loot_for_all_warbands(result, defender_casualties, coyote_warriors, warriors_committed, base_loot_value)

func _distribute_integer_by_weights(total: int, participants: Array, weight_key: String = "committed", cap_by_weight: bool = false) -> Dictionary:
	var result: Dictionary = {}
	if total <= 0:
		return result
	var total_weight: int = 0
	for participant_variant: Variant in participants:
		var participant: Dictionary = participant_variant as Dictionary
		total_weight += max(0, int(participant.get(weight_key, 0)))
	if total_weight <= 0:
		return result
	var remaining: int = total
	var remainders: Array[Dictionary] = []
	for participant_variant: Variant in participants:
		var participant: Dictionary = participant_variant as Dictionary
		var participant_id: String = String(participant.get("id", ""))
		var weight: int = max(0, int(participant.get(weight_key, 0)))
		if participant_id == "" or weight <= 0:
			continue
		var raw: float = float(total) * float(weight) / float(total_weight)
		var base: int = int(floor(raw))
		var cap_value: int = total
		if cap_by_weight:
			cap_value = weight
		base = mini(base, cap_value)
		result[participant_id] = base
		remaining -= base
		remainders.append({"id": participant_id, "fraction": raw - float(base), "cap": cap_value})
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("fraction", 0.0)) > float(b.get("fraction", 0.0))
	)
	var guard: int = 0
	while remaining > 0 and guard < 1000:
		var allocated: bool = false
		for item: Dictionary in remainders:
			if remaining <= 0:
				break
			var participant_id: String = String(item.get("id", ""))
			var cap_value: int = int(item.get("cap", total))
			if int(result.get(participant_id, 0)) < cap_value:
				result[participant_id] = int(result.get(participant_id, 0)) + 1
				remaining -= 1
				allocated = true
		if not allocated:
			break
		guard += 1
	return result

func get_flower_war_preview_with_warband(warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var resolved_doctrine: String = doctrine_id
	if resolved_doctrine == "" or resolved_doctrine == "warband":
		resolved_doctrine = String(warband.get("doctrine", "unspecialised"))
	var preview: Dictionary = get_flower_war_preview(option_id, resolved_doctrine, provisioning_id)
	if not bool(preview.get("ok", false)):
		return preview
	preview["warband_id"] = warband_id
	preview["warband_name"] = String(warband.get("name", "Warband"))
	preview["warband_ready"] = int(warband.get("ready_warriors", 0))
	preview["warband_injured"] = int(warband.get("injured_warriors", 0))
	preview["warband_level"] = int(_sync_warband_progress(warband.duplicate(true)).get("level", 1))
	preview["xp_gained"] = _flower_war_xp_gain(String(preview.get("result", "Stalemate")), int(preview.get("warriors_committed", 0)), int(preview.get("defender_casualties", 0)), int(preview.get("captives", 0)))
	return preview

func can_launch_flower_war_with_warband(warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state()
	if not flower_war_palace_gate_passed():
		return {"ok": false, "reason": flower_war_palace_gate_status_text()}
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	var preview: Dictionary = get_flower_war_preview_with_warband(warband_id, option_id, doctrine_id, provisioning_id)
	if not bool(preview.get("ok", false)):
		return preview
	var needed_warriors: int = int(preview.get("warriors_committed", 0))
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var ready: int = int(warband.get("ready_warriors", 0))
	if ready < needed_warriors:
		return {"ok": false, "reason": String(warband.get("name", "Warband")) + " needs " + str(needed_warriors) + " ready warriors; only " + str(ready) + " ready."}
	var cost_status: Dictionary = _can_pay_free_stock(preview.get("provisioning_cost", {}) as Dictionary)
	if not bool(cost_status.get("ok", false)):
		return cost_status
	return {"ok": true, "reason": "Ready.", "preview": preview}

func launch_flower_war_with_warband(warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	var status: Dictionary = can_launch_flower_war_with_warband(warband_id, option_id, doctrine_id, provisioning_id)
	if not bool(status.get("ok", false)):
		last_flower_war_report = {"ok": false, "reason": String(status.get("reason", "Flower War cannot launch.")), "warband_id": warband_id}
		last_report.append("Flower War not launched: " + String(last_flower_war_report.get("reason", "blocked")) + ".")
		_emit_state_changed_and_sync()
		return last_flower_war_report.duplicate(true)
	var preview: Dictionary = status.get("preview", {}) as Dictionary
	if preview.is_empty():
		preview = get_flower_war_preview_with_warband(warband_id, option_id, doctrine_id, provisioning_id)
	_pay_free_stock(preview.get("provisioning_cost", {}) as Dictionary)
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var level_before: int = int(_sync_warband_progress(warband.duplicate(true)).get("level", 1))
	var committed: int = int(preview.get("warriors_committed", 0))
	var casualties: int = int(preview.get("attacker_casualties", 0))
	var injured: int = int(preview.get("attacker_injured", 0))
	var dead: int = int(preview.get("attacker_dead", 0))
	var captives: int = int(preview.get("captives", 0))
	var xp_gain: int = int(preview.get("xp_gained", 0))

	warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0)) - casualties)
	warband["injured_warriors"] = max(0, int(warband.get("injured_warriors", 0)) + injured)
	warband["dead_total"] = max(0, int(warband.get("dead_total", 0)) + dead)
	warband["xp"] = max(0, int(warband.get("xp", 0)) + xp_gain)
	var history: Array = warband.get("battle_history", []) as Array
	history.append({
		"veintena": current_veintena,
		"option_id": option_id,
		"result": String(preview.get("result", "Unknown")),
		"committed": committed,
		"casualties": casualties,
		"injured": injured,
		"dead": dead,
		"captives": captives,
		"xp_gained": xp_gain
	})
	warband["battle_history"] = history
	warbands[warband_id] = _sync_warband_progress(warband)
	var level_after: int = int((warbands[warband_id] as Dictionary).get("level", level_before))

	if dead > 0:
		population["yaotequihuaqueh"] = max(0, get_warrior_count() - dead)
	if captives > 0:
		estate_stockpiles["captives"] = float(estate_stockpiles.get("captives", 0.0)) + float(captives)
	add_looted_goods_bundle(preview.get("loot", {}) as Dictionary)

	last_flower_war_report = preview.duplicate(true)
	last_flower_war_report["ok"] = true
	last_flower_war_report["warband_id"] = warband_id
	last_flower_war_report["warband_name"] = String(warband.get("name", "Warband"))
	last_flower_war_report["warriors_returned"] = max(0, committed - casualties)
	last_flower_war_report["xp_gained"] = xp_gain
	last_flower_war_report["level_before"] = level_before
	last_flower_war_report["level_after"] = level_after
	last_flower_war_report = _apply_flower_war_prestige_to_report(last_flower_war_report)

	var line: String = String(warband.get("name", "Warband")) + " fought " + String(preview.get("option_name", "Flower War")) + ": " + String(preview.get("result", "Unknown")) + ". Warriors committed " + str(committed) + "; casualties " + str(casualties) + " (injured " + str(injured) + ", dead " + str(dead) + "). Captives gained " + str(captives) + ". XP +" + str(xp_gain) + ". " + String(last_flower_war_report.get("prestige_text", "Prestige +0")) + "."
	if level_after > level_before:
		line += " " + String(warband.get("name", "Warband")) + " reached Level " + str(level_after) + " and gained " + str(max(0, level_after - level_before)) + " skill point(s)."
	last_report.append(line)
	_emit_state_changed_and_sync()
	return last_flower_war_report.duplicate(true)

func _flower_war_result_label(net_damage: int, attacker_size: int, defender_size: int) -> String:
	return _get_flower_war_system().flower_war_result_label(net_damage, attacker_size, defender_size)

func _flower_war_captives(result: String, defender_casualties: int, warriors_committed: int, doctrine_id: String) -> int:
	return _get_flower_war_system().flower_war_captives(result, defender_casualties, warriors_committed, doctrine_id)

func _flower_war_loot(result: String, defender_casualties: int, doctrine_id: String, base_loot_value: float) -> Dictionary:
	return _get_flower_war_system().flower_war_loot(result, defender_casualties, doctrine_id, base_loot_value)

func _flower_war_loot_display_value(loot: Dictionary) -> float:
	return _get_flower_war_system().flower_war_loot_display_value(self, loot)

func _flower_war_xp_gain(result: String, warriors_committed: int, defender_casualties: int, captives: int) -> int:
	return _get_flower_war_system().flower_war_xp_gain(result, warriors_committed, defender_casualties, captives)

func _flower_war_provisioning_cost(warriors_committed: int, supply_multiplier: float) -> Dictionary:
	return _get_flower_war_system().flower_war_provisioning_cost(warriors_committed, supply_multiplier)

func _can_pay_free_stock(cost: Dictionary) -> Dictionary:
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(cost[resource_variant])
		if free_stock_after_reserves(resource_id) + 0.001 < needed:
			return {"ok": false, "reason": "Need " + _format_amount(needed) + " free " + get_resource_name(resource_id) + " after reserves."}
	return {"ok": true, "reason": "Ready."}

func _pay_free_stock(cost: Dictionary) -> void:
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, -float(cost[resource_variant]))


# -----------------------------------------------------------------------------
# Warband Roster Backend v0.2 — canonical infrastructure, no launch mutation yet
# -----------------------------------------------------------------------------

func _ensure_warband_state() -> void:
	if not warbands.is_empty():
		return
	var total_warriors: int = get_warrior_count()
	var first: int = int(ceil(float(total_warriors) / 3.0))
	var second: int = int(floor(float(total_warriors) / 3.0))
	var third: int = max(0, total_warriors - first - second)
	warbands["first_warband"] = _make_starting_warband("first_warband", "First Warband", "Household Captain", first)
	warbands["second_warband"] = _make_starting_warband("second_warband", "Second Warband", "Senior Warrior", second)
	warbands["third_warband"] = _make_starting_warband("third_warband", "Third Warband", "Young Captain", third)

func _make_starting_warband(warband_id: String, name: String, commander: String, ready_warriors: int) -> Dictionary:
	return {
		"id": warband_id,
		"name": name,
		"commander": commander,
		"doctrine": "unspecialised",
		"ready_warriors": max(0, ready_warriors),
		"injured_warriors": 0,
		"dead_total": 0,
		"xp": 0,
		"level": 1,
		"total_trait_points": 0,
		"spent_trait_points": 0,
		"trait_points": 0,
		"purchased_traits": ["household_muster"],
		"traits": ["household_muster"],
		"skill_effects": {},
		"specialisation": {},
		"battle_history": []
	}

func _sync_warband_progress(warband: Dictionary) -> Dictionary:
	var xp: int = max(0, int(warband.get("xp", 0)))
	var level: int = _warband_level_for_xp(xp)
	warband["xp"] = xp
	warband["level"] = level
	warband["xp_to_next"] = _warband_xp_to_next(level)
	warband["xp_current_level_start"] = _warband_xp_required_for_level(level)
	warband["xp_next_level"] = _warband_xp_required_for_level(level + 1)
	warband["xp_in_level"] = xp - int(warband.get("xp_current_level_start", 0))
	warband["xp_needed_in_level"] = max(1, int(warband.get("xp_next_level", 0)) - int(warband.get("xp_current_level_start", 0)))
	warband["xp_progress"] = clampf(float(warband.get("xp_in_level", 0)) / float(warband.get("xp_needed_in_level", 1)), 0.0, 1.0)
	warband = _ensure_warband_skill_defaults(warband)
	warband["total_trait_points"] = max(0, level - 1)
	warband["spent_trait_points"] = _warband_spent_trait_points(warband)
	warband["trait_points"] = max(0, int(warband.get("total_trait_points", 0)) - int(warband.get("spent_trait_points", 0)))
	warband["skill_effects"] = _warband_trait_effect_totals_from_purchased(_warband_purchased_trait_ids(warband))
	warband["specialisation"] = _warband_specialisation_summary_for_warband(warband)
	# Canonical rule: the Skill Web specialism is the warband's doctrine identity.
	# Unspecialised warbands remain doctrine-neutral until a specialism gateway is bought.
	warband["doctrine"] = _warband_doctrine_from_specialisation(warband)
	return warband

func _warband_xp_required_for_level(level: int) -> int:
	var target: int = max(1, level)
	return (target - 1) * target * 5

func _warband_xp_to_next(level: int) -> int:
	return _warband_xp_required_for_level(max(1, level) + 1)

func _warband_level_for_xp(xp: int) -> int:
	var level: int = 1
	while xp >= _warband_xp_required_for_level(level + 1):
		level += 1
	return level

func _warband_spent_trait_points(warband: Dictionary) -> int:
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	var spent: int = 0
	for trait_id: String in purchased:
		var node: Dictionary = _warband_skill_node_by_id(trait_id)
		spent += max(0, int(node.get("cost", 0)))
	return spent

func _warband_doctrine_from_specialisation(warband: Dictionary) -> String:
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	var chosen_cluster: String = _warband_chosen_specialisation_cluster(purchased)
	if FLOWER_WAR_DOCTRINES.has(chosen_cluster):
		return chosen_cluster
	return "unspecialised"


func recover_injured_warriors_now() -> Dictionary:
	return _get_warband_system().recover_injured_warriors_now(self)

func _recover_injured_warriors() -> Dictionary:
	return _get_warband_system().recover_injured_warriors(self)

func get_warband_rows() -> Array[Dictionary]:
	return _get_warband_system().get_warband_rows(self)

func get_warband_by_id(warband_id: String) -> Dictionary:
	return _get_warband_system().get_warband_by_id(self, warband_id)

func can_rename_warband(warband_id: String, new_name: String) -> Dictionary:
	return _get_warband_system().can_rename_warband(self, warband_id, new_name)

func rename_warband(warband_id: String, new_name: String) -> Dictionary:
	return _get_warband_system().rename_warband(self, warband_id, new_name)

func can_set_warband_name(warband_id: String, new_name: String) -> Dictionary:
	return _get_warband_system().can_set_warband_name(self, warband_id, new_name)

func set_warband_name(warband_id: String, new_name: String) -> Dictionary:
	return _get_warband_system().set_warband_name(self, warband_id, new_name)

func get_primary_warband() -> Dictionary:
	return _get_warband_system().get_primary_warband(self)

func get_unassigned_warrior_pool() -> int:
	return _get_warband_system().get_unassigned_warrior_pool(self)

func can_create_warband(name: String = "New Warband", warriors: int = 0, doctrine_id: String = "unspecialised", commander: String = "Household Captain") -> Dictionary:
	return _get_warband_system().can_create_warband(self, name, warriors, doctrine_id, commander)

func create_warband(name: String = "New Warband", warriors: int = 0, doctrine_id: String = "unspecialised", commander: String = "Household Captain") -> Dictionary:
	return _get_warband_system().create_warband(self, name, warriors, doctrine_id, commander)

func can_reinforce_warband(warband_id: String, amount: int) -> Dictionary:
	return _get_warband_system().can_reinforce_warband(self, warband_id, amount)

func reinforce_warband(warband_id: String, amount: int) -> Dictionary:
	return _get_warband_system().reinforce_warband(self, warband_id, amount)

func can_assign_warriors_to_warband(warband_id: String, amount: int) -> Dictionary:
	return _get_warband_system().can_assign_warriors_to_warband(self, warband_id, amount)

func assign_warriors_to_warband(warband_id: String, amount: int) -> Dictionary:
	return _get_warband_system().assign_warriors_to_warband(self, warband_id, amount)

func can_unassign_warriors_from_warband(warband_id: String, amount: int) -> Dictionary:
	return _get_warband_system().can_unassign_warriors_from_warband(self, warband_id, amount)

func unassign_warriors_from_warband(warband_id: String, amount: int) -> Dictionary:
	return _get_warband_system().unassign_warriors_from_warband(self, warband_id, amount)

func can_specialise_warband(warband_id: String, doctrine_id: String) -> Dictionary:
	return _get_warband_system().can_specialise_warband(self, warband_id, doctrine_id)

func specialise_warband(warband_id: String, doctrine_id: String) -> Dictionary:
	return _get_warband_system().specialise_warband(self, warband_id, doctrine_id)

func get_warband_skill_web(warband_id: String = "") -> Dictionary:
	return _get_warband_system().get_warband_skill_web(self, warband_id)

func get_warband_trait_tree(warband_id: String) -> Dictionary:
	return _get_warband_system().get_warband_trait_tree(self, warband_id)

func get_warband_trait_points(warband_id: String) -> int:
	return _get_warband_system().get_warband_trait_points(self, warband_id)

func get_warband_purchased_traits(warband_id: String) -> Array[String]:
	return _get_warband_system().get_warband_purchased_traits(self, warband_id)

func get_warband_available_traits(warband_id: String) -> Array[Dictionary]:
	return _get_warband_system().get_warband_available_traits(self, warband_id)

func get_warband_locked_traits(warband_id: String) -> Array[Dictionary]:
	return _get_warband_system().get_warband_locked_traits(self, warband_id)

func can_purchase_warband_trait(warband_id: String, trait_id: String) -> Dictionary:
	return _get_warband_system().can_purchase_warband_trait(self, warband_id, trait_id)

func purchase_warband_trait(warband_id: String, trait_id: String) -> Dictionary:
	return _get_warband_system().purchase_warband_trait(self, warband_id, trait_id)

func get_warband_trait_effect_totals(warband_id: String) -> Dictionary:
	return _get_warband_system().get_warband_trait_effect_totals(self, warband_id)

func get_warband_specialisation_summary(warband_id: String) -> Dictionary:
	return _get_warband_system().get_warband_specialisation_summary(self, warband_id)

func _ensure_warband_skill_defaults(warband: Dictionary) -> Dictionary:
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	if not purchased.has("household_muster"):
		purchased.insert(0, "household_muster")
	warband["purchased_traits"] = purchased
	warband["traits"] = purchased.duplicate()
	return warband

func _warband_purchased_trait_ids(warband: Dictionary) -> Array[String]:
	var output: Array[String] = []
	var raw: Array = []
	if warband.has("purchased_traits"):
		raw = warband.get("purchased_traits", []) as Array
	elif warband.has("traits"):
		raw = warband.get("traits", []) as Array
	for item_variant: Variant in raw:
		var trait_id: String = String(item_variant)
		if trait_id == "":
			continue
		if output.has(trait_id):
			continue
		if _warband_skill_node_by_id(trait_id).is_empty():
			continue
		output.append(trait_id)
	if output.is_empty():
		output.append("household_muster")
	elif not output.has("household_muster"):
		output.insert(0, "household_muster")
	return output

func _warband_trait_effect_totals_from_purchased(purchased: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for trait_id: String in purchased:
		var node: Dictionary = _warband_skill_node_by_id(trait_id)
		var effects: Dictionary = node.get("effects", {}) as Dictionary
		for effect_variant: Variant in effects.keys():
			var effect_id: String = String(effect_variant)
			result[effect_id] = float(result.get(effect_id, 0.0)) + float(effects[effect_variant])
	return result

func _warband_specialisation_summary_for_warband(warband: Dictionary) -> Dictionary:
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	var point_clusters: Dictionary = {"eagle": 0, "jaguar": 0, "otomi": 0, "coyote": 0, "veteran": 0, "supply": 0, "core": 0}
	var keystones: Array[String] = _warband_purchased_specialisation_clusters(purchased)
	for trait_id: String in purchased:
		var node: Dictionary = _warband_skill_node_by_id(trait_id)
		var cluster: String = String(node.get("cluster", "core"))
		var cost: int = max(0, int(node.get("cost", 0)))
		point_clusters[cluster] = int(point_clusters.get(cluster, 0)) + cost
	var military_clusters: Array[String] = ["eagle", "jaguar", "otomi", "coyote"]
	var primary: String = ""
	var primary_points: int = 0
	for cluster_id: String in military_clusters:
		var points: int = int(point_clusters.get(cluster_id, 0))
		if points > primary_points:
			primary = cluster_id
			primary_points = points
	var name: String = "Unspecialised"
	var style: String = "none"
	var locked: bool = false
	if not keystones.is_empty():
		primary = keystones[0]
		locked = true
		style = "specialised"
		name = _warband_cluster_display_name(primary) + " Specialist"
		if keystones.size() > 1:
			# Legacy safeguard for older test saves made before specialisms locked.
			name += " (legacy mixed)"
			style = "legacy_mixed"
	elif primary != "" and primary_points > 0:
		name = _warband_cluster_display_name(primary) + "-leaning"
		style = "leaning"
	var doctrine_id: String = primary if locked and FLOWER_WAR_DOCTRINES.has(primary) else "unspecialised"
	return {
		"name": name,
		"style": style,
		"primary": primary,
		"primary_name": _warband_cluster_display_name(primary),
		"secondary": "",
		"secondary_name": "None",
		"keystones": keystones,
		"locked_specialism": locked,
		"specialism_locked": locked,
		"doctrine_id": doctrine_id,
		"doctrine_name": _warband_doctrine_name(doctrine_id),
		"sets_combat_doctrine": locked,
		"points_by_cluster": point_clusters,
		"effect_totals": _warband_trait_effect_totals_from_purchased(purchased)
	}

func _warband_cluster_display_name(cluster_id: String) -> String:
	match cluster_id:
		"eagle":
			return "Eagle"
		"jaguar":
			return "Jaguar"
		"otomi":
			return "Otomi"
		"coyote":
			return "Coyote"
		"veteran":
			return "Veteran"
		"supply":
			return "Supply"
		"core":
			return "Household"
	return cluster_id.capitalize()


func _warband_chosen_specialisation_cluster(purchased: Array[String]) -> String:
	for trait_id: String in purchased:
		var node: Dictionary = _warband_skill_node_by_id(trait_id)
		if bool(node.get("specialisation", false)):
			return String(node.get("cluster", ""))
	return ""

func _warband_purchased_specialisation_clusters(purchased: Array[String]) -> Array[String]:
	var output: Array[String] = []
	for trait_id: String in purchased:
		var node: Dictionary = _warband_skill_node_by_id(trait_id)
		if bool(node.get("specialisation", false)):
			var cluster_id: String = String(node.get("cluster", ""))
			if cluster_id != "" and not output.has(cluster_id):
				output.append(cluster_id)
	return output

func _warband_trait_locked_by_specialisation(purchased: Array[String], node: Dictionary) -> bool:
	# A warband may only take one major troop specialism. The approach and
	# preparation nodes remain open, but once a specialist gateway is bought,
	# the other specialist gateways are permanently locked.
	if not bool(node.get("specialisation", false)):
		return false
	var chosen_cluster: String = _warband_chosen_specialisation_cluster(purchased)
	if chosen_cluster == "":
		return false
	return String(node.get("cluster", "")) != chosen_cluster

func _warband_specialisation_lock_text(purchased: Array[String]) -> String:
	var chosen_cluster: String = _warband_chosen_specialisation_cluster(purchased)
	if chosen_cluster == "":
		return ""
	return "Locked by " + _warband_cluster_display_name(chosen_cluster) + " specialism. A warband can only choose one specialism."

func _warband_trait_requirements_met(purchased: Array[String], node: Dictionary) -> bool:
	var requirements: Array = node.get("requires", []) as Array
	for req_variant: Variant in requirements:
		var req_id: String = String(req_variant)
		if not purchased.has(req_id):
			return false
	var any_requirements: Array = node.get("requires_any", []) as Array
	if not any_requirements.is_empty():
		var any_met: bool = false
		for req_variant: Variant in any_requirements:
			var req_id: String = String(req_variant)
			if purchased.has(req_id):
				any_met = true
				break
		if not any_met:
			return false
	return true

func _warband_requirements_text(node: Dictionary) -> String:
	var requirements: Array = node.get("requires", []) as Array
	var any_requirements: Array = node.get("requires_any", []) as Array
	var names: Array[String] = []
	for req_variant: Variant in requirements:
		var req_id: String = String(req_variant)
		var req_node: Dictionary = _warband_skill_node_by_id(req_id)
		if req_node.is_empty():
			names.append(req_id)
		else:
			names.append(String(req_node.get("name", req_id)))
	var any_names: Array[String] = []
	for req_variant: Variant in any_requirements:
		var req_id: String = String(req_variant)
		var req_node: Dictionary = _warband_skill_node_by_id(req_id)
		if req_node.is_empty():
			any_names.append(req_id)
		else:
			any_names.append(String(req_node.get("name", req_id)))
	if names.is_empty() and any_names.is_empty():
		return "no prerequisite"
	if names.is_empty():
		return "one of " + ", ".join(any_names)
	if any_names.is_empty():
		return ", ".join(names)
	return ", ".join(names) + " and one of " + ", ".join(any_names)

func _warband_skill_connections() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for node: Dictionary in _warband_skill_node_definitions():
		var to_id: String = String(node.get("id", ""))
		var requirements: Array = node.get("requires", []) as Array
		for req_variant: Variant in requirements:
			output.append({"from": String(req_variant), "to": to_id, "type": "required"})
		var any_requirements: Array = node.get("requires_any", []) as Array
		for req_variant: Variant in any_requirements:
			output.append({"from": String(req_variant), "to": to_id, "type": "any"})
	return output

func _warband_skill_node_by_id(trait_id: String) -> Dictionary:
	for node: Dictionary in _warband_skill_node_definitions():
		if String(node.get("id", "")) == trait_id:
			return node.duplicate(true)
	return {}

func _warband_skill_node_definitions() -> Array[Dictionary]:
	# v0.12.11 symmetric branched rejoin web structure.
	# Each doctrine follows the same symmetric readable pattern:
	# approach -> preparation -> specialist gateway -> three short branches ->
	# elite rejoin node -> three advanced branches -> final chosen capstone.
	# Specialisation gateways are now mutually exclusive: one warband, one major troop specialism.
	return [
		{
			"id": "household_muster",
			"name": "Household Muster",
			"cluster": "core",
			"tier": 0,
			"x": 0,
			"y": 0,
			"cost": 0,
			"effects": {
				"readiness_add": 1.0
			},
			"description": "The founding muster node. Every warband starts here for free."
		},
		{
			"id": "formation_drill",
			"name": "Formation Drill",
			"cluster": "core",
			"tier": 1,
			"x": 0,
			"y": 1,
			"cost": 1,
			"requires": [
				"household_muster"
			],
			"effects": {
				"defence_add": 0.01
			},
			"description": "Basic formation practice makes the band steadier in battle."
		},
		{
			"id": "weapon_familiarity",
			"name": "Weapon Familiarity",
			"cluster": "core",
			"tier": 1,
			"x": 1,
			"y": 0,
			"cost": 1,
			"requires": [
				"household_muster"
			],
			"effects": {
				"offence_add": 0.01
			},
			"description": "Warriors become more comfortable with house weapons and drill patterns."
		},
		{
			"id": "veteran_captains",
			"name": "Veteran Captains",
			"cluster": "veteran",
			"tier": 1,
			"x": -1,
			"y": 0,
			"cost": 1,
			"requires": [
				"household_muster"
			],
			"effects": {
				"xp_gain_add": 0.02
			},
			"description": "Experienced captains help the warband learn from each expedition."
		},
		{
			"id": "battle_rhythm",
			"name": "Battle Rhythm",
			"cluster": "veteran",
			"tier": 2,
			"x": 0,
			"y": -1,
			"cost": 1,
			"requires": [
				"household_muster"
			],
			"effects": {
				"offence_add": 0.005,
				"defence_add": 0.005,
				"provisioning_discount_add": 0.01
			},
			"description": "The company learns how to move, close, withdraw, reform and keep supplies ordered as one body. This now folds in the old Supply Habits support bonus so the centre web stays clean and symmetrical."
		},
		{
			"id": "eagle_approach",
			"name": "Eagle Approach",
			"cluster": "eagle",
			"tier": 1,
			"x": 0,
			"y": 3,
			"cost": 1,
			"requires": [
				"formation_drill"
			],
			"effects": {
				"capture_chance_add": 0.01
			},
			"description": "The warband begins training toward controlled capture and disciplined advance."
		},
		{
			"id": "eagle_controlled_advance",
			"name": "Controlled Advance",
			"cluster": "eagle",
			"tier": 2,
			"x": 0,
			"y": 4,
			"cost": 1,
			"requires": [
				"eagle_approach"
			],
			"effects": {
				"capture_chance_add": 0.015,
				"defence_add": 0.01
			},
			"description": "The band learns to close while preserving valuable enemies alive."
		},
		{
			"id": "eagle_specialisation",
			"name": "Eagle Specialist",
			"cluster": "eagle",
			"tier": 3,
			"x": 0,
			"y": 5,
			"cost": 1,
			"requires": [
				"eagle_controlled_advance"
			],
			"effects": {
				"capture_chance_add": 0.025
			},
			"description": "A locking specialism gateway into Eagle traditions. Once chosen, other troop specialism gateways are closed to this warband.",
			"specialisation": true
		},
		{
			"id": "eagle_net_drill",
			"name": "Net Drill",
			"cluster": "eagle",
			"tier": 4,
			"x": -2,
			"y": 6,
			"cost": 1,
			"requires": [
				"eagle_specialisation"
			],
			"effects": {
				"capture_chance_add": 0.025
			},
			"description": "Capture",
			"path": "capture"
		},
		{
			"id": "eagle_prisoner_rings",
			"name": "Prisoner Rings",
			"cluster": "eagle",
			"tier": 5,
			"x": -2,
			"y": 7,
			"cost": 1,
			"requires": [
				"eagle_net_drill"
			],
			"effects": {
				"capture_chance_add": 0.03
			},
			"description": "Capture",
			"path": "capture"
		},
		{
			"id": "eagle_living_tribute",
			"name": "Living Tribute",
			"cluster": "eagle",
			"tier": 6,
			"x": -2,
			"y": 8,
			"cost": 1,
			"requires": [
				"eagle_prisoner_rings"
			],
			"effects": {
				"capture_chance_add": 0.04
			},
			"description": "Capture",
			"path": "capture"
		},
		{
			"id": "eagle_temple_guard",
			"name": "Temple Guard",
			"cluster": "eagle",
			"tier": 4,
			"x": 0,
			"y": 6,
			"cost": 1,
			"requires": [
				"eagle_specialisation"
			],
			"effects": {
				"defence_add": 0.025
			},
			"description": "Temple",
			"path": "temple"
		},
		{
			"id": "eagle_sacred_discipline",
			"name": "Sacred Discipline",
			"cluster": "eagle",
			"tier": 5,
			"x": 0,
			"y": 7,
			"cost": 1,
			"requires": [
				"eagle_temple_guard"
			],
			"effects": {
				"defence_add": 0.03
			},
			"description": "Temple",
			"path": "temple"
		},
		{
			"id": "eagle_shielded_capture",
			"name": "Shielded Capture",
			"cluster": "eagle",
			"tier": 6,
			"x": 0,
			"y": 8,
			"cost": 1,
			"requires": [
				"eagle_sacred_discipline"
			],
			"effects": {
				"defence_add": 0.025,
				"capture_chance_add": 0.015
			},
			"description": "Temple",
			"path": "temple"
		},
		{
			"id": "eagle_war_banners",
			"name": "War Banners",
			"cluster": "eagle",
			"tier": 4,
			"x": 2,
			"y": 6,
			"cost": 1,
			"requires": [
				"eagle_specialisation"
			],
			"effects": {
				"prestige_pending_add": 0.025
			},
			"description": "Banner",
			"path": "banner"
		},
		{
			"id": "eagle_noble_witnesses",
			"name": "Noble Witnesses",
			"cluster": "eagle",
			"tier": 5,
			"x": 2,
			"y": 7,
			"cost": 1,
			"requires": [
				"eagle_war_banners"
			],
			"effects": {
				"prestige_pending_add": 0.035
			},
			"description": "Banner",
			"path": "banner"
		},
		{
			"id": "eagle_victory_procession",
			"name": "Victory Procession",
			"cluster": "eagle",
			"tier": 6,
			"x": 2,
			"y": 8,
			"cost": 1,
			"requires": [
				"eagle_noble_witnesses"
			],
			"effects": {
				"prestige_pending_add": 0.045
			},
			"description": "Banner",
			"path": "banner"
		},
		{
			"id": "elite_eagle_warriors",
			"name": "Elite Eagle Warriors",
			"cluster": "eagle",
			"tier": 7,
			"x": 0,
			"y": 9,
			"cost": 1,
			"requires": [
				"eagle_specialisation"
			],
			"requires_any": [
				"eagle_living_tribute",
				"eagle_shielded_capture",
				"eagle_victory_procession"
			],
			"effects": {
				"capture_chance_add": 0.04,
				"defence_add": 0.02
			},
			"description": "The branches rejoin into an elite Eagle company identity. Any completed first Eagle branch can reach this node.",
			"rejoin": true
		},
		{
			"id": "eagle_captive_masters",
			"name": "Captive Masters",
			"cluster": "eagle",
			"tier": 8,
			"x": -2,
			"y": 10,
			"cost": 1,
			"requires": [
				"elite_eagle_warriors"
			],
			"effects": {
				"capture_chance_add": 0.045
			},
			"description": "High Captors",
			"path": "high_capture"
		},
		{
			"id": "eagle_prince_takers",
			"name": "Prince Takers",
			"cluster": "eagle",
			"tier": 9,
			"x": -2,
			"y": 11,
			"cost": 1,
			"requires": [
				"eagle_captive_masters"
			],
			"effects": {
				"capture_chance_add": 0.055
			},
			"description": "High Captors",
			"path": "high_capture"
		},
		{
			"id": "eagle_temple_oath",
			"name": "Temple Oath",
			"cluster": "eagle",
			"tier": 8,
			"x": 0,
			"y": 10,
			"cost": 1,
			"requires": [
				"elite_eagle_warriors"
			],
			"effects": {
				"defence_add": 0.04
			},
			"description": "Honour Guard",
			"path": "honour"
		},
		{
			"id": "eagle_guarded_return",
			"name": "Guarded Return",
			"cluster": "eagle",
			"tier": 9,
			"x": 0,
			"y": 11,
			"cost": 1,
			"requires": [
				"eagle_temple_oath"
			],
			"effects": {
				"defence_add": 0.04,
				"death_chance_add": -0.01
			},
			"description": "Honour Guard",
			"path": "honour"
		},
		{
			"id": "eagle_procession_songs",
			"name": "Procession Songs",
			"cluster": "eagle",
			"tier": 8,
			"x": 2,
			"y": 10,
			"cost": 1,
			"requires": [
				"elite_eagle_warriors"
			],
			"effects": {
				"prestige_pending_add": 0.045
			},
			"description": "Public Glory",
			"path": "public"
		},
		{
			"id": "eagle_radiant_standards",
			"name": "Radiant Standards",
			"cluster": "eagle",
			"tier": 9,
			"x": 2,
			"y": 11,
			"cost": 1,
			"requires": [
				"eagle_procession_songs"
			],
			"effects": {
				"prestige_pending_add": 0.06
			},
			"description": "Public Glory",
			"path": "public"
		},
		{
			"id": "chosen_eagles",
			"name": "Chosen Eagles",
			"cluster": "eagle",
			"tier": 10,
			"x": 0,
			"y": 12,
			"cost": 1,
			"requires": [
				"elite_eagle_warriors"
			],
			"requires_any": [
				"eagle_prince_takers",
				"eagle_guarded_return",
				"eagle_radiant_standards"
			],
			"effects": {
				"capture_chance_add": 0.075,
				"prestige_pending_add": 0.035
			},
			"description": "The advanced branches rejoin into the Chosen Eagles: an elite warband known for living captives, sacred discipline and public honour.",
			"capstone": true,
			"rejoin": true,
			"chosen_capstone": true
		},
		{
			"id": "jaguar_approach",
			"name": "Jaguar Approach",
			"cluster": "jaguar",
			"tier": 1,
			"x": 3,
			"y": 0,
			"cost": 1,
			"requires": [
				"weapon_familiarity"
			],
			"effects": {
				"offence_add": 0.02
			},
			"description": "The warband begins training toward shock, killing power and visible martial fame."
		},
		{
			"id": "jaguar_close_drill",
			"name": "Close Drill",
			"cluster": "jaguar",
			"tier": 2,
			"x": 4,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_approach"
			],
			"effects": {
				"offence_add": 0.025
			},
			"description": "Close-order fighting makes the band more dangerous once battle is joined."
		},
		{
			"id": "jaguar_specialisation",
			"name": "Jaguar Specialist",
			"cluster": "jaguar",
			"tier": 3,
			"x": 5,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_close_drill"
			],
			"effects": {
				"offence_add": 0.03
			},
			"description": "A locking specialism gateway into Jaguar traditions. Once chosen, other troop specialism gateways are closed to this warband.",
			"specialisation": true
		},
		{
			"id": "jaguar_blooded_charge",
			"name": "Blooded Charge",
			"cluster": "jaguar",
			"tier": 4,
			"x": 6,
			"y": 2,
			"cost": 1,
			"requires": [
				"jaguar_specialisation"
			],
			"effects": {
				"offence_add": 0.025
			},
			"description": "The Blooded line favours direct assault and decisive melee pressure.",
			"path": "blooded"
		},
		{
			"id": "jaguar_close_killers",
			"name": "Close Killers",
			"cluster": "jaguar",
			"tier": 5,
			"x": 7,
			"y": 2,
			"cost": 1,
			"requires": [
				"jaguar_blooded_charge"
			],
			"effects": {
				"offence_add": 0.03
			},
			"description": "The Blooded line favours direct assault and decisive melee pressure.",
			"path": "blooded"
		},
		{
			"id": "jaguar_red_hands",
			"name": "Red Hands",
			"cluster": "jaguar",
			"tier": 6,
			"x": 8,
			"y": 2,
			"cost": 1,
			"requires": [
				"jaguar_close_killers"
			],
			"effects": {
				"offence_add": 0.035
			},
			"description": "The Blooded line favours direct assault and decisive melee pressure.",
			"path": "blooded"
		},
		{
			"id": "jaguar_trophy_display",
			"name": "Trophy Display",
			"cluster": "jaguar",
			"tier": 4,
			"x": 6,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_specialisation"
			],
			"effects": {
				"prestige_pending_add": 0.03
			},
			"description": "The Trophy line turns victories into renown and fear.",
			"path": "trophy"
		},
		{
			"id": "jaguar_war_fame",
			"name": "War Fame",
			"cluster": "jaguar",
			"tier": 5,
			"x": 7,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_trophy_display"
			],
			"effects": {
				"prestige_pending_add": 0.035
			},
			"description": "The Trophy line turns victories into renown and fear.",
			"path": "trophy"
		},
		{
			"id": "jaguar_public_terror",
			"name": "Public Terror",
			"cluster": "jaguar",
			"tier": 6,
			"x": 8,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_war_fame"
			],
			"effects": {
				"prestige_pending_add": 0.04
			},
			"description": "The Trophy line turns victories into renown and fear.",
			"path": "trophy"
		},
		{
			"id": "jaguar_death_oath",
			"name": "Death-Seeker Oath",
			"cluster": "jaguar",
			"tier": 4,
			"x": 6,
			"y": -2,
			"cost": 1,
			"requires": [
				"jaguar_specialisation"
			],
			"effects": {
				"offence_add": 0.02,
				"death_chance_add": 0.005
			},
			"description": "The Death-Seeker line trades safety for terrifying commitment.",
			"path": "death"
		},
		{
			"id": "jaguar_ritual_ferocity",
			"name": "Ritual Ferocity",
			"cluster": "jaguar",
			"tier": 5,
			"x": 7,
			"y": -2,
			"cost": 1,
			"requires": [
				"jaguar_death_oath"
			],
			"effects": {
				"offence_add": 0.025,
				"capture_chance_add": 0.005
			},
			"description": "The Death-Seeker line trades safety for terrifying commitment.",
			"path": "death"
		},
		{
			"id": "jaguar_no_retreat",
			"name": "No Retreat",
			"cluster": "jaguar",
			"tier": 6,
			"x": 8,
			"y": -2,
			"cost": 1,
			"requires": [
				"jaguar_ritual_ferocity"
			],
			"effects": {
				"offence_add": 0.035,
				"defence_add": -0.005
			},
			"description": "The Death-Seeker line trades safety for terrifying commitment.",
			"path": "death"
		},
		{
			"id": "elite_jaguar_warriors",
			"name": "Elite Jaguar Warriors",
			"cluster": "jaguar",
			"tier": 7,
			"x": 9,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_specialisation"
			],
			"requires_any": [
				"jaguar_red_hands",
				"jaguar_public_terror",
				"jaguar_no_retreat"
			],
			"effects": {
				"offence_add": 0.05,
				"defence_add": 0.015
			},
			"description": "The branches rejoin into an elite Jaguar company identity. Any completed first Jaguar branch can reach this node.",
			"rejoin": true
		},
		{
			"id": "jaguar_breaking_strike",
			"name": "Breaking Strike",
			"cluster": "jaguar",
			"tier": 8,
			"x": 10,
			"y": 2,
			"cost": 1,
			"requires": [
				"elite_jaguar_warriors"
			],
			"effects": {
				"offence_add": 0.04,
				"enemy_defence_add": -0.005
			},
			"description": "Elite Butchers",
			"path": "butchers"
		},
		{
			"id": "jaguar_blooded_veterans",
			"name": "Blooded Veterans",
			"cluster": "jaguar",
			"tier": 9,
			"x": 11,
			"y": 2,
			"cost": 1,
			"requires": [
				"jaguar_breaking_strike"
			],
			"effects": {
				"offence_add": 0.05
			},
			"description": "Elite Butchers",
			"path": "butchers"
		},
		{
			"id": "jaguar_named_victories",
			"name": "Named Victories",
			"cluster": "jaguar",
			"tier": 8,
			"x": 10,
			"y": 0,
			"cost": 1,
			"requires": [
				"elite_jaguar_warriors"
			],
			"effects": {
				"prestige_pending_add": 0.045
			},
			"description": "Fame Bearers",
			"path": "fame"
		},
		{
			"id": "jaguar_trophy_procession",
			"name": "Trophy Procession",
			"cluster": "jaguar",
			"tier": 9,
			"x": 11,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_named_victories"
			],
			"effects": {
				"prestige_pending_add": 0.06
			},
			"description": "Fame Bearers",
			"path": "fame"
		},
		{
			"id": "jaguar_blood_debt",
			"name": "Blood Debt",
			"cluster": "jaguar",
			"tier": 8,
			"x": 10,
			"y": -2,
			"cost": 1,
			"requires": [
				"elite_jaguar_warriors"
			],
			"effects": {
				"capture_chance_add": 0.015,
				"offence_add": 0.025
			},
			"description": "Ritual Killers",
			"path": "ritual"
		},
		{
			"id": "jaguar_ritual_panic",
			"name": "Ritual Panic",
			"cluster": "jaguar",
			"tier": 9,
			"x": 11,
			"y": -2,
			"cost": 1,
			"requires": [
				"jaguar_blood_debt"
			],
			"effects": {
				"offence_add": 0.04,
				"capture_chance_add": 0.02
			},
			"description": "Ritual Killers",
			"path": "ritual"
		},
		{
			"id": "chosen_jaguars",
			"name": "Chosen Jaguars",
			"cluster": "jaguar",
			"tier": 10,
			"x": 12,
			"y": 0,
			"cost": 1,
			"requires": [
				"elite_jaguar_warriors"
			],
			"requires_any": [
				"jaguar_blooded_veterans",
				"jaguar_trophy_procession",
				"jaguar_ritual_panic"
			],
			"effects": {
				"offence_add": 0.08,
				"prestige_pending_add": 0.04
			},
			"description": "The advanced branches rejoin into the Chosen Jaguars: a famous elite warband whose identity is built on fear, trophies and decisive violence.",
			"capstone": true,
			"rejoin": true,
			"chosen_capstone": true
		},
		{
			"id": "otomi_approach",
			"name": "Otomi Approach",
			"cluster": "otomi",
			"tier": 1,
			"x": -3,
			"y": 0,
			"cost": 1,
			"requires": [
				"veteran_captains"
			],
			"effects": {
				"defence_add": 0.02
			},
			"description": "The warband begins training toward endurance, formation and survival."
		},
		{
			"id": "otomi_brace_drill",
			"name": "Brace Drill",
			"cluster": "otomi",
			"tier": 2,
			"x": -4,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_approach"
			],
			"effects": {
				"defence_add": 0.025
			},
			"description": "The band learns to absorb pressure without breaking."
		},
		{
			"id": "otomi_specialisation",
			"name": "Otomi Specialist",
			"cluster": "otomi",
			"tier": 3,
			"x": -5,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_brace_drill"
			],
			"effects": {
				"defence_add": 0.035,
				"death_chance_add": -0.005
			},
			"description": "A locking specialism gateway into Otomi traditions. Once chosen, other troop specialism gateways are closed to this warband.",
			"specialisation": true
		},
		{
			"id": "otomi_shield_wall",
			"name": "Shield Wall",
			"cluster": "otomi",
			"tier": 4,
			"x": -6,
			"y": 2,
			"cost": 1,
			"requires": [
				"otomi_specialisation"
			],
			"effects": {
				"defence_add": 0.03
			},
			"description": "Shield",
			"path": "shield"
		},
		{
			"id": "otomi_hold_ground",
			"name": "Hold Ground",
			"cluster": "otomi",
			"tier": 5,
			"x": -7,
			"y": 2,
			"cost": 1,
			"requires": [
				"otomi_shield_wall"
			],
			"effects": {
				"defence_add": 0.035
			},
			"description": "Shield",
			"path": "shield"
		},
		{
			"id": "otomi_unbroken_line",
			"name": "Unbroken Line",
			"cluster": "otomi",
			"tier": 6,
			"x": -8,
			"y": 2,
			"cost": 1,
			"requires": [
				"otomi_hold_ground"
			],
			"effects": {
				"defence_add": 0.045
			},
			"description": "Shield",
			"path": "shield"
		},
		{
			"id": "otomi_iron_resolve",
			"name": "Iron Resolve",
			"cluster": "otomi",
			"tier": 4,
			"x": -6,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_specialisation"
			],
			"effects": {
				"death_chance_add": -0.015
			},
			"description": "Survival",
			"path": "survival"
		},
		{
			"id": "otomi_carry_wounded",
			"name": "Carry the Wounded",
			"cluster": "otomi",
			"tier": 5,
			"x": -7,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_iron_resolve"
			],
			"effects": {
				"death_chance_add": -0.015,
				"injury_recovery_add": 0.02
			},
			"description": "Survival",
			"path": "survival"
		},
		{
			"id": "otomi_death_avoidance",
			"name": "Death Avoidance",
			"cluster": "otomi",
			"tier": 6,
			"x": -8,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_carry_wounded"
			],
			"effects": {
				"death_chance_add": -0.025
			},
			"description": "Survival",
			"path": "survival"
		},
		{
			"id": "otomi_hard_march",
			"name": "Hard March",
			"cluster": "otomi",
			"tier": 4,
			"x": -6,
			"y": -2,
			"cost": 1,
			"requires": [
				"otomi_specialisation"
			],
			"effects": {
				"provisioning_discount_add": 0.02
			},
			"description": "Frontier",
			"path": "frontier"
		},
		{
			"id": "otomi_lean_camp",
			"name": "Lean Camp",
			"cluster": "otomi",
			"tier": 5,
			"x": -7,
			"y": -2,
			"cost": 1,
			"requires": [
				"otomi_hard_march"
			],
			"effects": {
				"provisioning_discount_add": 0.025
			},
			"description": "Frontier",
			"path": "frontier"
		},
		{
			"id": "otomi_rough_ground",
			"name": "Rough Ground",
			"cluster": "otomi",
			"tier": 6,
			"x": -8,
			"y": -2,
			"cost": 1,
			"requires": [
				"otomi_lean_camp"
			],
			"effects": {
				"provisioning_discount_add": 0.03,
				"casualty_chance_add": -0.005
			},
			"description": "Frontier",
			"path": "frontier"
		},
		{
			"id": "elite_otomi_warriors",
			"name": "Elite Otomi Warriors",
			"cluster": "otomi",
			"tier": 7,
			"x": -9,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_specialisation"
			],
			"requires_any": [
				"otomi_unbroken_line",
				"otomi_death_avoidance",
				"otomi_rough_ground"
			],
			"effects": {
				"defence_add": 0.055,
				"death_chance_add": -0.01
			},
			"description": "The branches rejoin into an elite Otomi company identity. Any completed first Otomi branch can reach this node.",
			"rejoin": true
		},
		{
			"id": "otomi_braced_veterans",
			"name": "Braced Veterans",
			"cluster": "otomi",
			"tier": 8,
			"x": -10,
			"y": 2,
			"cost": 1,
			"requires": [
				"elite_otomi_warriors"
			],
			"effects": {
				"defence_add": 0.045
			},
			"description": "Wall Veterans",
			"path": "wall"
		},
		{
			"id": "otomi_stone_line",
			"name": "Stone Line",
			"cluster": "otomi",
			"tier": 9,
			"x": -11,
			"y": 2,
			"cost": 1,
			"requires": [
				"otomi_braced_veterans"
			],
			"effects": {
				"defence_add": 0.06
			},
			"description": "Wall Veterans",
			"path": "wall"
		},
		{
			"id": "otomi_wounded_return",
			"name": "Wounded Return",
			"cluster": "otomi",
			"tier": 8,
			"x": -10,
			"y": 0,
			"cost": 1,
			"requires": [
				"elite_otomi_warriors"
			],
			"effects": {
				"injury_recovery_add": 0.035,
				"death_chance_add": -0.015
			},
			"description": "Recovery Veterans",
			"path": "recovery"
		},
		{
			"id": "otomi_veteran_recovery",
			"name": "Veteran Recovery",
			"cluster": "otomi",
			"tier": 9,
			"x": -11,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_wounded_return"
			],
			"effects": {
				"injury_recovery_add": 0.045,
				"death_chance_add": -0.02
			},
			"description": "Recovery Veterans",
			"path": "recovery"
		},
		{
			"id": "otomi_route_hardening",
			"name": "Route Hardening",
			"cluster": "otomi",
			"tier": 8,
			"x": -10,
			"y": -2,
			"cost": 1,
			"requires": [
				"elite_otomi_warriors"
			],
			"effects": {
				"provisioning_discount_add": 0.045
			},
			"description": "Frontier Veterans",
			"path": "frontier_elite"
		},
		{
			"id": "otomi_low_upkeep_veterans",
			"name": "Low-Upkeep Veterans",
			"cluster": "otomi",
			"tier": 9,
			"x": -11,
			"y": -2,
			"cost": 1,
			"requires": [
				"otomi_route_hardening"
			],
			"effects": {
				"provisioning_discount_add": 0.06,
				"casualty_chance_add": -0.01
			},
			"description": "Frontier Veterans",
			"path": "frontier_elite"
		},
		{
			"id": "unbroken_otomi",
			"name": "Unbroken Otomi",
			"cluster": "otomi",
			"tier": 10,
			"x": -12,
			"y": 0,
			"cost": 1,
			"requires": [
				"elite_otomi_warriors"
			],
			"requires_any": [
				"otomi_stone_line",
				"otomi_veteran_recovery",
				"otomi_low_upkeep_veterans"
			],
			"effects": {
				"defence_add": 0.08,
				"death_chance_add": -0.025
			},
			"description": "The advanced branches rejoin into the Unbroken Otomi: an elite warband famous for survival, discipline and holding the line.",
			"capstone": true,
			"rejoin": true,
			"chosen_capstone": true
		},
		{
			"id": "coyote_approach",
			"name": "Coyote Approach",
			"cluster": "coyote",
			"tier": 1,
			"x": 0,
			"y": -3,
			"cost": 1,
			"requires": [
				"battle_rhythm"
			],
			"effects": {
				"loot_value_add": 0.02
			},
			"description": "The warband begins training toward speed, raiding and opportunistic returns."
		},
		{
			"id": "coyote_route_drill",
			"name": "Route Drill",
			"cluster": "coyote",
			"tier": 2,
			"x": 0,
			"y": -4,
			"cost": 1,
			"requires": [
				"coyote_approach"
			],
			"effects": {
				"loot_value_add": 0.02,
				"provisioning_discount_add": 0.005
			},
			"description": "Known routes help the band find goods and escape cleanly."
		},
		{
			"id": "coyote_specialisation",
			"name": "Coyote Specialist",
			"cluster": "coyote",
			"tier": 3,
			"x": 0,
			"y": -5,
			"cost": 1,
			"requires": [
				"coyote_route_drill"
			],
			"effects": {
				"loot_value_add": 0.035
			},
			"description": "A locking specialism gateway into Coyote traditions. Once chosen, other troop specialism gateways are closed to this warband.",
			"specialisation": true
		},
		{
			"id": "coyote_spoil_takers",
			"name": "Spoil Takers",
			"cluster": "coyote",
			"tier": 4,
			"x": -2,
			"y": -6,
			"cost": 1,
			"requires": [
				"coyote_specialisation"
			],
			"effects": {
				"loot_value_add": 0.03
			},
			"description": "Raider",
			"path": "raider"
		},
		{
			"id": "coyote_fast_looting",
			"name": "Fast Looting",
			"cluster": "coyote",
			"tier": 5,
			"x": -2,
			"y": -7,
			"cost": 1,
			"requires": [
				"coyote_spoil_takers"
			],
			"effects": {
				"loot_value_add": 0.035
			},
			"description": "Raider",
			"path": "raider"
		},
		{
			"id": "coyote_prize_scouts",
			"name": "Prize Scouts",
			"cluster": "coyote",
			"tier": 6,
			"x": -2,
			"y": -8,
			"cost": 1,
			"requires": [
				"coyote_fast_looting"
			],
			"effects": {
				"loot_value_add": 0.045
			},
			"description": "Raider",
			"path": "raider"
		},
		{
			"id": "coyote_light_provisioning",
			"name": "Light Provisioning",
			"cluster": "coyote",
			"tier": 4,
			"x": 0,
			"y": -6,
			"cost": 1,
			"requires": [
				"coyote_specialisation"
			],
			"effects": {
				"provisioning_discount_add": 0.025
			},
			"description": "Scout",
			"path": "scout"
		},
		{
			"id": "coyote_route_knowledge",
			"name": "Route Knowledge",
			"cluster": "coyote",
			"tier": 5,
			"x": 0,
			"y": -7,
			"cost": 1,
			"requires": [
				"coyote_light_provisioning"
			],
			"effects": {
				"provisioning_discount_add": 0.03,
				"casualty_chance_add": -0.005
			},
			"description": "Scout",
			"path": "scout"
		},
		{
			"id": "coyote_cheap_campaigns",
			"name": "Cheap Campaigns",
			"cluster": "coyote",
			"tier": 6,
			"x": 0,
			"y": -8,
			"cost": 1,
			"requires": [
				"coyote_route_knowledge"
			],
			"effects": {
				"provisioning_discount_add": 0.04
			},
			"description": "Scout",
			"path": "scout"
		},
		{
			"id": "coyote_sudden_strike",
			"name": "Sudden Strike",
			"cluster": "coyote",
			"tier": 4,
			"x": 2,
			"y": -6,
			"cost": 1,
			"requires": [
				"coyote_specialisation"
			],
			"effects": {
				"offence_add": 0.025,
				"defence_add": -0.005
			},
			"description": "Ghost",
			"path": "ghost"
		},
		{
			"id": "coyote_vanishing_line",
			"name": "Vanishing Line",
			"cluster": "coyote",
			"tier": 5,
			"x": 2,
			"y": -7,
			"cost": 1,
			"requires": [
				"coyote_sudden_strike"
			],
			"effects": {
				"offence_add": 0.025,
				"casualty_chance_add": -0.005
			},
			"description": "Ghost",
			"path": "ghost"
		},
		{
			"id": "coyote_fragile_violence",
			"name": "Fragile Violence",
			"cluster": "coyote",
			"tier": 6,
			"x": 2,
			"y": -8,
			"cost": 1,
			"requires": [
				"coyote_vanishing_line"
			],
			"effects": {
				"offence_add": 0.04,
				"defence_add": -0.01
			},
			"description": "Ghost",
			"path": "ghost"
		},
		{
			"id": "elite_coyote_warriors",
			"name": "Elite Coyote Warriors",
			"cluster": "coyote",
			"tier": 7,
			"x": 0,
			"y": -9,
			"cost": 1,
			"requires": [
				"coyote_specialisation"
			],
			"requires_any": [
				"coyote_prize_scouts",
				"coyote_cheap_campaigns",
				"coyote_fragile_violence"
			],
			"effects": {
				"loot_value_add": 0.055,
				"provisioning_discount_add": 0.015
			},
			"description": "The branches rejoin into an elite Coyote company identity. Any completed first Coyote branch can reach this node.",
			"rejoin": true
		},
		{
			"id": "coyote_night_plunder",
			"name": "Night Plunder",
			"cluster": "coyote",
			"tier": 8,
			"x": -2,
			"y": -10,
			"cost": 1,
			"requires": [
				"elite_coyote_warriors"
			],
			"effects": {
				"loot_value_add": 0.05
			},
			"description": "Plunder Veterans",
			"path": "plunder"
		},
		{
			"id": "coyote_choice_spoils",
			"name": "Choice Spoils",
			"cluster": "coyote",
			"tier": 9,
			"x": -2,
			"y": -11,
			"cost": 1,
			"requires": [
				"coyote_night_plunder"
			],
			"effects": {
				"loot_value_add": 0.07
			},
			"description": "Plunder Veterans",
			"path": "plunder"
		},
		{
			"id": "coyote_hidden_paths",
			"name": "Hidden Paths",
			"cluster": "coyote",
			"tier": 8,
			"x": 0,
			"y": -10,
			"cost": 1,
			"requires": [
				"elite_coyote_warriors"
			],
			"effects": {
				"provisioning_discount_add": 0.045,
				"casualty_chance_add": -0.005
			},
			"description": "Route Veterans",
			"path": "routes"
		},
		{
			"id": "coyote_supply_vanish",
			"name": "Supply Vanish",
			"cluster": "coyote",
			"tier": 9,
			"x": 0,
			"y": -11,
			"cost": 1,
			"requires": [
				"coyote_hidden_paths"
			],
			"effects": {
				"provisioning_discount_add": 0.06,
				"casualty_chance_add": -0.01
			},
			"description": "Route Veterans",
			"path": "routes"
		},
		{
			"id": "coyote_ghost_assault",
			"name": "Ghost Assault",
			"cluster": "coyote",
			"tier": 8,
			"x": 2,
			"y": -10,
			"cost": 1,
			"requires": [
				"elite_coyote_warriors"
			],
			"effects": {
				"offence_add": 0.045,
				"loot_value_add": 0.02
			},
			"description": "Shadow Veterans",
			"path": "shadow"
		},
		{
			"id": "coyote_no_tracks",
			"name": "No Tracks",
			"cluster": "coyote",
			"tier": 9,
			"x": 2,
			"y": -11,
			"cost": 1,
			"requires": [
				"coyote_ghost_assault"
			],
			"effects": {
				"offence_add": 0.06,
				"defence_add": -0.01,
				"loot_value_add": 0.025
			},
			"description": "Shadow Veterans",
			"path": "shadow"
		},
		{
			"id": "shadow_coyotes",
			"name": "Shadow Coyotes",
			"cluster": "coyote",
			"tier": 10,
			"x": 0,
			"y": -12,
			"cost": 1,
			"requires": [
				"elite_coyote_warriors"
			],
			"requires_any": [
				"coyote_choice_spoils",
				"coyote_supply_vanish",
				"coyote_no_tracks"
			],
			"effects": {
				"loot_value_add": 0.08,
				"provisioning_discount_add": 0.035,
				"offence_add": 0.025
			},
			"description": "The advanced branches rejoin into the Shadow Coyotes: an elite warband known for plunder, routes and sudden disappearance.",
			"capstone": true,
			"rejoin": true,
			"chosen_capstone": true
		}
	]

func _unassigned_warrior_pool() -> int:
	_ensure_warband_state()
	var assigned: int = 0
	for warband_variant: Variant in warbands.values():
		var warband: Dictionary = warband_variant as Dictionary
		assigned += int(warband.get("ready_warriors", 0))
		assigned += int(warband.get("injured_warriors", 0))
	return max(0, get_warrior_count() - assigned)

func get_warband_flower_war_stability_audit() -> Dictionary:
	return _get_warband_system().get_warband_flower_war_stability_audit(self)

func _warband_doctrine_name(doctrine_id: String) -> String:
	if FLOWER_WAR_DOCTRINES.has(doctrine_id):
		var data: Dictionary = FLOWER_WAR_DOCTRINES[doctrine_id] as Dictionary
		return String(data.get("name", doctrine_id.capitalize()))
	return doctrine_id.capitalize()
