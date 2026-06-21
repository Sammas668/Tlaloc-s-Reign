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
const CAMPAIGN_BRIDGE_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/CampaignBridgeSystem.gd")
const PRESTIGE_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/PrestigeSystem.gd")
const MARKET_TRADE_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/MarketTradeSystem.gd")
const STOREHOUSE_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/StorehouseSystem.gd")
const MARKET_ECONOMY_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/MarketEconomySystem.gd")
const POPULATION_UPKEEP_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/PopulationUpkeepSystem.gd")
const HOUSING_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/HousingSystem.gd")
const LABOUR_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/LabourSystem.gd")
const ESTATE_BUILDING_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/EstateBuildingSystem.gd")
const PRODUCTION_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/ProductionSystem.gd")
const TURN_RESOLUTION_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/TurnResolutionSystem.gd")
const TURN_RUNTIME_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/TurnRuntimeSystem.gd")
const PALACE_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/PalaceSystem.gd")
const PALACE_ROUTE_OVERVIEW_SYSTEM_SCRIPT: GDScript = preload("res://Scripts/Systems/PalaceRouteOverviewSystem.gd")
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

# CampaignState is the live/save-state authority. The matching TRGameState
# variables remain temporary compatibility mirrors for older UI paths.
var campaign_state: CampaignState = null
var _campaign_bridge_system_instance: RefCounted = null

var _prestige_system_instance: PrestigeSystem = null
var _market_trade_system_instance: MarketTradeSystem = null
var _storehouse_system_instance: RefCounted = null
var _market_economy_system_instance: MarketEconomySystem = null
var _population_upkeep_system_instance: PopulationUpkeepSystem = null
var _housing_system_instance: HousingSystem = null
var _labour_system_instance: RefCounted = null
var _estate_building_system_instance: RefCounted = null
var _production_system_instance: ProductionSystem = null
var _turn_resolution_system_instance: TurnResolutionSystem = null
var _turn_runtime_system_instance: RefCounted = null
var _palace_system_instance: PalaceSystem = null
var _palace_route_overview_system_instance: RefCounted = null
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

func _get_campaign_bridge_system() -> RefCounted:
	if _campaign_bridge_system_instance == null:
		_campaign_bridge_system_instance = CAMPAIGN_BRIDGE_SYSTEM_SCRIPT.new()
	return _campaign_bridge_system_instance

func get_campaign_state_snapshot() -> CampaignState:
	_sync_campaign_state_from_current_runtime()
	return _get_campaign_state()

func _sync_campaign_state_from_current_runtime() -> void:
	_get_campaign_bridge_system().call("sync_from_current_runtime", self)

func _apply_campaign_state_to_current_runtime() -> void:
	_get_campaign_bridge_system().call("apply_campaign_state_to_current_runtime", self)

func _ensure_campaign_state_palace_bridge() -> CampaignState:
	return _get_campaign_bridge_system().call("ensure_campaign_state_palace_bridge", self) as CampaignState

func _capture_legacy_palace_state_to_campaign_state() -> void:
	_get_campaign_bridge_system().call("capture_legacy_palace_state_to_campaign_state", self)

func _mirror_palace_state_from_campaign_state_to_legacy() -> void:
	_get_campaign_bridge_system().call("mirror_palace_state_from_campaign_state_to_legacy", self)

func _ensure_campaign_state_estate_structure_bridge() -> CampaignState:
	return _get_campaign_bridge_system().call("ensure_campaign_state_estate_structure_bridge", self) as CampaignState

func _mirror_estate_structure_compatibility_from_campaign_state() -> void:
	_get_campaign_bridge_system().call("mirror_estate_structure_compatibility_from_campaign_state", self)

func _ensure_campaign_state_warband_flower_war_bridge() -> CampaignState:
	return _get_campaign_bridge_system().call("ensure_campaign_state_warband_flower_war_bridge", self) as CampaignState

func _mirror_warband_flower_war_compatibility_from_campaign_state() -> void:
	_get_campaign_bridge_system().call("mirror_warband_flower_war_compatibility_from_campaign_state", self)

func _ensure_campaign_state_stockpile_bridge() -> CampaignState:
	return _get_campaign_bridge_system().call("ensure_campaign_state_stockpile_bridge", self) as CampaignState

func _mirror_stockpile_compatibility_from_campaign_state() -> void:
	_get_campaign_bridge_system().call("mirror_stockpile_compatibility_from_campaign_state", self)

func _mirror_calendar_report_compatibility_from_campaign_state() -> void:
	_get_campaign_bridge_system().call("mirror_calendar_report_compatibility_from_campaign_state", self)

func _ensure_campaign_state_calendar_report_bridge() -> CampaignState:
	return _get_campaign_bridge_system().call("ensure_campaign_state_calendar_report_bridge", self) as CampaignState

func _capture_legacy_calendar_report_to_campaign_state() -> void:
	_get_campaign_bridge_system().call("capture_legacy_calendar_report_to_campaign_state", self)

func _set_current_veintena_value(value: int) -> int:
	return int(_get_campaign_bridge_system().call("set_current_veintena_value", self, value))

func _clear_report_lines() -> void:
	_get_campaign_bridge_system().call("clear_report_lines", self)

func _set_report_lines(lines: Array) -> void:
	_get_campaign_bridge_system().call("set_report_lines", self, lines)

func _append_report_line(line: String) -> void:
	_get_campaign_bridge_system().call("append_report_line", self, line)

func _ensure_campaign_state_prestige_bridge() -> CampaignState:
	return _get_campaign_bridge_system().call("ensure_campaign_state_prestige_bridge", self) as CampaignState

func _mirror_prestige_compatibility_from_campaign_state() -> void:
	_get_campaign_bridge_system().call("mirror_prestige_compatibility_from_campaign_state", self)

func _emit_state_changed_and_sync() -> void:
	_get_campaign_bridge_system().call("emit_state_changed_and_sync", self)

func get_campaign_state_sync_report(sync_first: bool = false) -> Dictionary:
	return _get_campaign_bridge_system().call("get_campaign_state_sync_report", self, sync_first) as Dictionary

func is_campaign_state_mirror_in_sync() -> bool:
	return bool(_get_campaign_bridge_system().call("is_campaign_state_mirror_in_sync", self))

func _campaign_state_compare_text(value: Variant) -> String:
	return String(_get_campaign_bridge_system().call("campaign_state_compare_text", value))

func _campaign_state_preview(value: Variant) -> String:
	return String(_get_campaign_bridge_system().call("campaign_state_preview", value))

func _get_prestige_system() -> PrestigeSystem:
	if _prestige_system_instance == null:
		_prestige_system_instance = PRESTIGE_SYSTEM_SCRIPT.new() as PrestigeSystem
	return _prestige_system_instance

func _get_market_trade_system() -> MarketTradeSystem:
	if _market_trade_system_instance == null:
		_market_trade_system_instance = MARKET_TRADE_SYSTEM_SCRIPT.new() as MarketTradeSystem
	return _market_trade_system_instance

func _get_storehouse_system() -> RefCounted:
	if _storehouse_system_instance == null:
		_storehouse_system_instance = STOREHOUSE_SYSTEM_SCRIPT.new()
	return _storehouse_system_instance

func _get_market_economy_system() -> MarketEconomySystem:
	if _market_economy_system_instance == null:
		_market_economy_system_instance = MARKET_ECONOMY_SYSTEM_SCRIPT.new() as MarketEconomySystem
	return _market_economy_system_instance

func _get_population_upkeep_system() -> PopulationUpkeepSystem:
	if _population_upkeep_system_instance == null:
		_population_upkeep_system_instance = POPULATION_UPKEEP_SYSTEM_SCRIPT.new() as PopulationUpkeepSystem
	return _population_upkeep_system_instance

func _get_housing_system() -> HousingSystem:
	if _housing_system_instance == null:
		_housing_system_instance = HOUSING_SYSTEM_SCRIPT.new() as HousingSystem
	return _housing_system_instance

func _get_labour_system() -> RefCounted:
	if _labour_system_instance == null:
		_labour_system_instance = LABOUR_SYSTEM_SCRIPT.new()
	return _labour_system_instance

func _get_estate_building_system() -> RefCounted:
	if _estate_building_system_instance == null:
		_estate_building_system_instance = ESTATE_BUILDING_SYSTEM_SCRIPT.new()
	return _estate_building_system_instance

func _get_production_system() -> ProductionSystem:
	if _production_system_instance == null:
		_production_system_instance = PRODUCTION_SYSTEM_SCRIPT.new() as ProductionSystem
	return _production_system_instance

func _get_turn_resolution_system() -> TurnResolutionSystem:
	if _turn_resolution_system_instance == null:
		_turn_resolution_system_instance = TURN_RESOLUTION_SYSTEM_SCRIPT.new() as TurnResolutionSystem
	return _turn_resolution_system_instance

func _get_turn_runtime_system() -> RefCounted:
	if _turn_runtime_system_instance == null:
		_turn_runtime_system_instance = TURN_RUNTIME_SYSTEM_SCRIPT.new()
	return _turn_runtime_system_instance

func _get_palace_system() -> PalaceSystem:
	if _palace_system_instance == null:
		_palace_system_instance = PALACE_SYSTEM_SCRIPT.new() as PalaceSystem
	return _palace_system_instance

func _get_palace_route_overview_system() -> RefCounted:
	if _palace_route_overview_system_instance == null:
		_palace_route_overview_system_instance = PALACE_ROUTE_OVERVIEW_SYSTEM_SCRIPT.new() as RefCounted
	return _palace_route_overview_system_instance

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
	var runtime_state: CampaignState = _get_campaign_state()
	runtime_state.clear_palace_state()
	runtime_state.set_flower_war_palace_gate_enabled_value(true)
	_mirror_palace_state_from_campaign_state_to_legacy()
	runtime_state.set_player_prestige_value(0.0)
	runtime_state.set_rival_prestige_values(_default_rival_prestige_values())
	runtime_state.clear_prestige_history()
	runtime_state.clear_sacrifice_prestige_records()
	_mirror_prestige_compatibility_from_campaign_state()
	_ensure_warband_state()
	last_flower_war_report.clear()
	flower_war_report_archive.clear()
	runtime_state.set_initialized(true)
	runtime_state.clear_last_report()
	runtime_state.append_report_line("New estate simulation started.")
	_mirror_calendar_report_compatibility_from_campaign_state()
	_emit_state_changed_and_sync()

func _load_project_data_into_campaign_state() -> void:
	# CampaignState owns JSON/start-state shaping. TRGameState remains the public
	# facade for UI and system calls.
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
	# Read-only UI access should not force a bridge sync.
	return _get_campaign_state().get_current_veintena_value()

func get_last_report() -> Array[String]:
	# Read-only UI access should not force a bridge sync.
	return _get_campaign_state().get_last_report_copy()

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
	return _get_storehouse_system().call("get_storehouse_goods", self) as Array[Dictionary]

func get_market_goods() -> Array[Dictionary]:
	return _get_market_economy_system().get_market_goods(self)

func get_market_trade_preview(trade_plan: Dictionary) -> Dictionary:
	# v0.43.2 public API. UI can use this to preview barter values without
	# owning market pricing rules. Existing TradeBasketView still works while
	# the UI migration is staged.
	return _get_market_trade_system().get_trade_preview(self, trade_plan)

func validate_market_trade_plan(trade_plan: Dictionary) -> Dictionary:
	return _get_market_trade_system().validate_trade_plan(self, trade_plan)

func apply_market_trade_plan(trade_plan: Dictionary) -> Dictionary:
	# v0.45.0: MarketTradeSystem applies stockpile changes through CampaignState.
	# TRGameState mirrors after acceptance only for old UI/system readers.
	var result: Dictionary = _get_market_trade_system().apply_trade_plan(self, trade_plan)
	_mirror_stockpile_compatibility_from_campaign_state()
	_sync_campaign_state_from_current_runtime()
	return result

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
	return _get_market_economy_system().estimate_market_resolution(self)

func get_market_economy_summary() -> Dictionary:
	return estimate_market_resolution()

func get_village_economy_rows() -> Array[Dictionary]:
	return _get_market_economy_system().get_village_economy_rows(self)

func _base_market_goods() -> Array[Dictionary]:
	return _get_market_economy_system().base_market_goods(self)

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
	return _get_labour_system().call("get_productive_labour_rows", self) as Array[Dictionary]

func get_labour_assignment_data() -> Dictionary:
	return _get_labour_system().call("get_labour_assignment_data", self) as Dictionary

func _single_labour_assignment_group_data(group_id: String, assigned_by_group: Dictionary, required_by_group: Dictionary) -> Dictionary:
	return _get_labour_system().call("single_labour_assignment_group_data", self, group_id, assigned_by_group, required_by_group) as Dictionary

func _combined_labour_assignment_group_data(group_id: String, display_name: String, description: String, member_ids: Array[String], assigned_by_group: Dictionary, required_by_group: Dictionary) -> Dictionary:
	return _get_labour_system().call("combined_labour_assignment_group_data", self, group_id, display_name, description, member_ids, assigned_by_group, required_by_group) as Dictionary

func assign_labour_to_building(building_id: String, group_id: String, amount: int) -> bool:
	return bool(_get_labour_system().call("assign_labour_to_building", self, building_id, group_id, amount))

func set_staffed_building_count(building_id: String, requested_count: int) -> bool:
	return bool(_get_labour_system().call("set_staffed_building_count", self, building_id, requested_count))

func set_staffed_building_count_for_group(building_id: String, group_id: String, requested_count: int) -> bool:
	return bool(_get_labour_system().call("set_staffed_building_count_for_group", self, building_id, group_id, requested_count))

func set_staffed_building_count_for_field_labour(building_id: String, requested_count: int) -> bool:
	return bool(_get_labour_system().call("set_staffed_building_count_for_field_labour", self, building_id, requested_count))

func _productive_labour_required() -> Dictionary:
	return _get_labour_system().call("productive_labour_required", self) as Dictionary

func _productive_labour_group_ids() -> Array[String]:
	var raw: Array = _get_labour_system().call("productive_labour_group_ids") as Array
	var output: Array[String] = []
	for item: Variant in raw:
		output.append(String(item))
	return output

func _max_staffable_count_for_field_labour_with_used(building_id: String, used_by_group: Dictionary) -> int:
	return int(_get_labour_system().call("max_staffable_count_for_field_labour_with_used", self, building_id, used_by_group))

func _field_labour_population_split_for_building(building_id: String, staffed_copies: int, used_by_group: Dictionary = {}) -> Dictionary:
	return _get_labour_system().call("field_labour_population_split_for_building", self, building_id, staffed_copies, used_by_group) as Dictionary

func _field_labour_distribution_for_building(target_building_id: String, target_copies: int) -> Dictionary:
	return _get_labour_system().call("field_labour_distribution_for_building", self, target_building_id, target_copies) as Dictionary

func _field_labour_fallback_staff_required(building_id: String) -> int:
	return int(_get_labour_system().call("field_labour_fallback_staff_required", self, building_id))

func _field_labour_group_ids() -> Array[String]:
	var raw: Array = _get_labour_system().call("field_labour_group_ids") as Array
	var output: Array[String] = []
	for item: Variant in raw:
		output.append(String(item))
	return output

func _production_staff_for_building(building_id: String) -> Dictionary:
	return _get_labour_system().call("production_staff_for_building", self, building_id) as Dictionary

func _labour_group_name(group_id: String) -> String:
	return String(_get_labour_system().call("labour_group_name", group_id))

func _labour_group_description(group_id: String) -> String:
	return String(_get_labour_system().call("labour_group_description", group_id))

func _building_matches_focus(definition: Dictionary, focus_id: String) -> bool:
	return bool(_get_estate_building_system().call("building_matches_focus", definition, focus_id))

func _building_view_data(building_id: String) -> Dictionary:
	return _get_estate_building_system().call("building_view_data", self, building_id) as Dictionary

func reserved_resources_for_current_turn() -> Dictionary:
	return _get_estate_building_system().call("reserved_resources_for_current_turn", self) as Dictionary

func free_stock_after_reserves(resource_id: String) -> float:
	return float(_get_estate_building_system().call("free_stock_after_reserves", self, resource_id))

func can_build(building_id: String) -> bool:
	return bool(_get_estate_building_system().call("can_build", self, building_id))

func build_status_text(building_id: String) -> String:
	return String(_get_estate_building_system().call("build_status_text", self, building_id))

func build_building(building_id: String) -> bool:
	return bool(_get_estate_building_system().call("build_building", self, building_id))

func can_destroy(building_id: String) -> bool:
	return bool(_get_estate_building_system().call("can_destroy", self, building_id))

func destroy_status_text(building_id: String) -> String:
	return String(_get_estate_building_system().call("destroy_status_text", self, building_id))

func destroy_building(building_id: String) -> bool:
	return bool(_get_estate_building_system().call("destroy_building", self, building_id))

func advance_veintena() -> void:
	_get_turn_resolution_system().advance_veintena(self)
	# TurnResolutionSystem still writes calendar/report values directly to the
	# TRGameState compatibility wrapper. Capture that output into CampaignState
	# before the normal CampaignState-first sync preserves authoritative values.
	_capture_legacy_calendar_report_to_campaign_state()
	_sync_campaign_state_from_current_runtime()
	_mirror_calendar_report_compatibility_from_campaign_state()

func estimate_population_upkeep() -> Dictionary:
	return _get_population_upkeep_system().calculate_population_upkeep(active_population_by_group(), population_upkeep_rates)

func estimate_building_inputs() -> Dictionary:
	return _get_turn_runtime_system().call("estimate_building_inputs", self) as Dictionary
func estimate_building_outputs() -> Dictionary:
	return _get_turn_runtime_system().call("estimate_building_outputs", self) as Dictionary
func estimate_production_resolution() -> Dictionary:
	# Authoritative production preview. Rule logic now lives in ProductionSystem;
	# TRGameState remains the live-state owner and public API for the UI.
	return _get_production_system().estimate_production_resolution(self)

func _pay_population_upkeep() -> void:
	_get_turn_runtime_system().call("pay_population_upkeep", self)
func _pay_housing_maintenance() -> void:
	_get_turn_runtime_system().call("pay_housing_maintenance", self)
func _operate_buildings() -> void:
	_get_turn_runtime_system().call("operate_buildings", self)
func _reserve_staff(staff: Dictionary, available_staff: Dictionary) -> void:
	_get_turn_runtime_system().call("reserve_staff", staff, available_staff)
func _consume_inputs(inputs: Dictionary) -> void:
	_get_turn_runtime_system().call("consume_inputs", self, inputs)
func _add_outputs(outputs: Dictionary) -> void:
	_get_turn_runtime_system().call("add_outputs", self, outputs)
func _estimate_building_status(building_id: String) -> Dictionary:
	return _get_turn_runtime_system().call("estimate_building_status", self, building_id) as Dictionary
func _estimated_operating_count_for_building(building_id: String) -> int:
	return int(_get_turn_runtime_system().call("estimated_operating_count_for_building", self, building_id))
func _is_productive_building_id(building_id: String) -> bool:
	return bool(_get_labour_system().call("is_productive_building_id", self, building_id))

func _auto_staff_all_productive_buildings() -> void:
	_get_labour_system().call("auto_staff_all_productive_buildings", self)
	_sync_campaign_state_from_current_runtime()

func _auto_staff_single_building_to_max(building_id: String) -> void:
	_get_labour_system().call("auto_staff_single_building_to_max", self, building_id)
	_sync_campaign_state_from_current_runtime()

func _production_auto_staff_order() -> Array[String]:
	return _get_labour_system().call("production_auto_staff_order", self) as Array[String]

func _is_maize_production_building(building_id: String) -> bool:
	return bool(_get_labour_system().call("is_maize_production_building", self, building_id))

func _ensure_labour_assignments() -> void:
	_get_labour_system().call("ensure_labour_assignments", self)
	_sync_campaign_state_from_current_runtime()

func _default_assignment_for_building(building_id: String, count: int, running_by_group: Dictionary) -> Dictionary:
	return _get_labour_system().call("default_assignment_for_building", self, building_id, count, running_by_group) as Dictionary

func _allowed_worker_groups_for_building(building_id: String) -> Array[String]:
	return _get_labour_system().call("allowed_worker_groups_for_building", self, building_id) as Array[String]

func _staff_required_per_copy_for_group(building_id: String, group_id: String) -> int:
	return int(_get_labour_system().call("staff_required_per_copy_for_group", self, building_id, group_id))

func _coerce_staff_assignments_for_building(building_id: String, value: Variant) -> Dictionary:
	return _get_labour_system().call("coerce_staff_assignments_for_building", self, building_id, value) as Dictionary

func _staff_assignments_for_building(building_id: String) -> Dictionary:
	return _get_labour_system().call("staff_assignments_for_building", self, building_id) as Dictionary

func _assigned_staff_for_building(building_id: String) -> Dictionary:
	return _get_labour_system().call("assigned_staff_for_building", self, building_id) as Dictionary

func _staff_population_by_building(building_id: String) -> Dictionary:
	return _get_labour_system().call("staff_population_by_building", self, building_id) as Dictionary

func _staffed_count_for_building(building_id: String) -> int:
	return int(_get_labour_system().call("staffed_count_for_building", self, building_id))

func _staffed_count_for_group(building_id: String, group_id: String) -> int:
	return int(_get_labour_system().call("staffed_count_for_group", self, building_id, group_id))

func _coerce_staffed_count_from_assignment(building_id: String, value: Variant) -> int:
	return int(_get_labour_system().call("coerce_staffed_count_from_assignment", self, building_id, value))

func _clamp_staffed_count_for_building(building_id: String, requested_count: int) -> int:
	return int(_get_labour_system().call("clamp_staffed_count_for_building", self, building_id, requested_count))

func _clamp_staffed_count_for_building_group(building_id: String, group_id: String, requested_count: int) -> int:
	return int(_get_labour_system().call("clamp_staffed_count_for_building_group", self, building_id, group_id, requested_count))

func _building_can_use_field_labour(building_id: String) -> bool:
	return bool(_get_labour_system().call("building_can_use_field_labour", self, building_id))

func _field_labour_staffed_count_for_building(building_id: String) -> int:
	return int(_get_labour_system().call("field_labour_staffed_count_for_building", self, building_id))

func _max_staffable_count_for_field_labour(building_id: String) -> int:
	return int(_get_labour_system().call("max_staffable_count_for_field_labour", self, building_id))

func _max_staffable_count_for_building_group(building_id: String, group_id: String, override_for_building: Dictionary = {}, precomputed_elsewhere: Dictionary = {}) -> int:
	return int(_get_labour_system().call("max_staffable_count_for_building_group", self, building_id, group_id, override_for_building, precomputed_elsewhere))

func _clamp_staffed_count_with_running(building_id: String, requested_count: int, running_by_group: Dictionary) -> int:
	return int(_get_labour_system().call("clamp_staffed_count_with_running", self, building_id, requested_count, running_by_group))

func _max_staffable_count_for_building(building_id: String) -> int:
	return int(_get_labour_system().call("max_staffable_count_for_building", self, building_id))

func _assigned_labour_by_group_excluding(excluded_building_id: String) -> Dictionary:
	return _get_labour_system().call("assigned_labour_by_group_excluding", self, excluded_building_id) as Dictionary

func _assigned_labour_by_group() -> Dictionary:
	return _get_labour_system().call("assigned_labour_by_group", self) as Dictionary

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
		_append_report_line("Loot assigned into goods: " + ", ".join(gained_parts) + ".")
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
	# v0.45.0: estate stockpile reads pass through CampaignState.
	# The legacy estate_stockpiles dictionary is only a compatibility mirror.
	var runtime_state: CampaignState = _ensure_campaign_state_stockpile_bridge()
	return runtime_state.get_estate_stock(resource_id)

func _add_stock(resource_id: String, amount: float) -> void:
	# v0.45.0: estate stockpile writes update CampaignState first, then mirror
	# back to TRGameState's compatibility dictionary for old UI/system paths.
	var runtime_state: CampaignState = _ensure_campaign_state_stockpile_bridge()
	runtime_state.add_estate_stock(resource_id, amount)
	_mirror_stockpile_compatibility_from_campaign_state()

func _reserve_breakdown(resource_id: String, upkeep_value: float, input_value: float, housing_value: float = 0.0) -> Array[String]:
	return _get_storehouse_system().call("reserve_breakdown", self, resource_id, upkeep_value, input_value, housing_value) as Array[String]

func _pressure_label(stored: float, outgoing: float) -> String:
	return String(_get_storehouse_system().call("pressure_label", stored, outgoing))

func _scarcity_multiplier(coverage: float, demand_value: float) -> float:
	return _get_market_economy_system().scarcity_multiplier(coverage, demand_value)

func _market_label(coverage: float, demand_value: float) -> String:
	return _get_market_economy_system().market_label(coverage, demand_value)

func _market_trend(coverage: float, demand_value: float) -> String:
	return _get_market_economy_system().market_trend(coverage, demand_value)

func _rival_market_note(resource_id: String) -> String:
	return _get_rival_system().market_note_for_resource(resource_id)

func _apply_market_economy_to_goods(goods: Array[Dictionary]) -> Array[Dictionary]:
	return _get_market_economy_system().apply_market_economy_to_goods(self, goods)

func _market_resource_value(source: Dictionary, resource_id: String) -> float:
	return _get_market_economy_system().market_resource_value(source, resource_id)

func _market_scarcity_multiplier(coverage: float, demand: float) -> float:
	return _get_market_economy_system().market_scarcity_multiplier(coverage, demand)

func _market_pressure_label(coverage: float, demand: float) -> String:
	return _get_market_economy_system().market_pressure_label(coverage, demand)

func _market_net_trend(net_change: float, demand: float) -> String:
	return _get_market_economy_system().market_net_trend(net_change, demand)

func _market_good_note(resource_id: String) -> String:
	return _get_market_economy_system().market_good_note(self, resource_id)

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

func get_warrior_count() -> int:
	return int(population.get("yaotequihuaqueh", 0))

func get_warrior_capacity() -> int:
	var capacity: Dictionary = housing_capacity_by_group({}, true)
	return int(capacity.get("yaotequihuaqueh", 0))

func get_barracks_summary() -> Dictionary:
	return _get_warband_system().get_barracks_summary(self)

func get_warband_combat_stats(warband_id: String) -> Dictionary:
	return _get_warband_system().get_warband_combat_stats(self, warband_id)

func get_army_muster_summary() -> Dictionary:
	return _get_warband_system().get_army_muster_summary(self)

func _warband_doctrine_data(doctrine_id: String) -> Dictionary:
	return _get_warband_system().warband_doctrine_data(doctrine_id)

func _warband_combat_stats_from_warband(warband: Dictionary) -> Dictionary:
	return _get_warband_system().warband_combat_stats_from_warband(warband)

func get_player_palace_dedicated_god() -> String:
	return _get_campaign_state().get_palace_dedicated_god_value()

func set_player_palace_dedicated_god(god_id: String) -> Dictionary:
	# v0.45.12c hotfix: palace dedication state is now CampaignState-first.
	# Do not route this through PalaceSystem because that older system writes to the
	# TRGameState compatibility mirror and emits before CampaignState is updated.
	var cleaned: String = god_id.strip_edges().to_lower()
	if cleaned == "":
		_get_campaign_state().set_palace_dedicated_god_value("")
		_mirror_palace_state_from_campaign_state_to_legacy()
		_append_report_line("Palace dedication cleared. Flower Wars are locked until the palace is dedicated to Huitzilopochtli.")
		_emit_state_changed_and_sync()
		return {"ok": true, "reason": "Palace dedication cleared."}
	if not PALACE_GOD_IDS.has(cleaned):
		return {"ok": false, "reason": "Unknown palace god: " + god_id + "."}
	_get_campaign_state().set_palace_dedicated_god_value(cleaned)
	_mirror_palace_state_from_campaign_state_to_legacy()
	_append_report_line("Palace dedicated to " + _god_display_name(cleaned) + ".")
	_emit_state_changed_and_sync()
	return {"ok": true, "reason": "Palace dedicated to " + _god_display_name(cleaned) + ".", "god_id": cleaned}

func has_war_god_palace() -> bool:
	return _get_palace_system().has_war_god_palace(self)

func is_flower_war_palace_gate_enabled() -> bool:
	return _get_campaign_state().get_flower_war_palace_gate_enabled_value()

func set_flower_war_palace_gate_enabled(enabled: bool) -> Dictionary:
	var result: Dictionary = _get_palace_system().set_flower_war_palace_gate_enabled(self, enabled)
	_capture_legacy_palace_state_to_campaign_state()
	_capture_legacy_calendar_report_to_campaign_state()
	_emit_state_changed_and_sync()
	return result

func flower_war_palace_gate_passed() -> bool:
	return _get_palace_system().flower_war_palace_gate_passed(self)

func flower_war_palace_gate_status_text() -> String:
	return _get_palace_system().flower_war_palace_gate_status_text(self)

func _god_display_name(god_id: String) -> String:
	return _get_palace_system().god_display_name(god_id)

func get_palace_dedicated_god() -> String:
	return _get_campaign_state().get_palace_dedicated_god_value()

func get_palace_route_name(god_id: String) -> String:
	return _get_palace_system().get_palace_route_name(god_id)

func get_palace_route_power_summary(god_id: String) -> String:
	return _get_palace_system().get_palace_route_power_summary(god_id)

func can_dedicate_palace_to_god(god_id: String) -> Dictionary:
	# v0.45.12c hotfix: read CampaignState, not the legacy mirror.
	var cleaned: String = god_id.strip_edges().to_lower()
	if cleaned == "":
		return {"ok": false, "reason": "Choose a palace god."}
	if not PALACE_GOD_IDS.has(cleaned):
		return {"ok": false, "reason": "Unknown palace god: " + god_id + "."}
	var current_god: String = _get_campaign_state().get_palace_dedicated_god_value()
	if current_god != "":
		return {"ok": false, "reason": "The palace is already dedicated to " + _god_display_name(current_god) + ". Prototype 0 dedication is permanent."}
	return {"ok": true, "reason": "Ready to dedicate the palace to " + _god_display_name(cleaned) + "."}

func dedicate_palace_to_god(god_id: String) -> Dictionary:
	# v0.45.12c hotfix: perform dedication directly against CampaignState.
	# This avoids the old PalaceSystem path that writes to TRGameState first and
	# can be overwritten by CampaignState-authoritative sync.
	var status: Dictionary = can_dedicate_palace_to_god(god_id)
	if not bool(status.get("ok", false)):
		_append_report_line("Palace dedication failed: " + String(status.get("reason", "")))
		_emit_state_changed_and_sync()
		return status
	var cleaned: String = god_id.strip_edges().to_lower()
	_get_campaign_state().set_palace_dedicated_god_value(cleaned)
	_mirror_palace_state_from_campaign_state_to_legacy()
	_append_report_line("Palace dedicated to " + _god_display_name(cleaned) + ". The Divine Seat now displays the " + get_palace_route_name(cleaned) + " structure node data.")
	_emit_state_changed_and_sync()
	return {"ok": true, "reason": "Palace dedicated to " + _god_display_name(cleaned) + ".", "god_id": cleaned}

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
	return _get_palace_system().palace_structure_node(self, id, god_id, tier, name, description, build_cost, maintenance_cost, staff_requirement, prerequisites, effect_summary)

func _palace_structure_tree_tiers(god_id: String) -> Array[Dictionary]:
	return _get_palace_system().palace_structure_tree_tiers(self, god_id)

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
	var result: Dictionary = _get_palace_system().build_palace_structure(self, structure_id)
	_capture_legacy_palace_state_to_campaign_state()
	_capture_legacy_calendar_report_to_campaign_state()
	_emit_state_changed_and_sync()
	return result

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
	var statuses: Dictionary = _get_palace_system().get_palace_structure_runtime_statuses(self)
	_capture_legacy_palace_state_to_campaign_state()
	_sync_campaign_state_from_current_runtime()
	return statuses

func get_active_palace_structure_ids() -> Array[String]:
	return _get_palace_system().get_active_palace_structure_ids(self)

func get_inactive_palace_structure_ids() -> Array[String]:
	return _get_palace_system().get_inactive_palace_structure_ids(self)

func _resolve_palace_structure_operation(pay_costs: bool) -> Dictionary:
	var result: Dictionary = _get_palace_system().resolve_palace_structure_operation(self, pay_costs)
	_capture_legacy_palace_state_to_campaign_state()
	_sync_campaign_state_from_current_runtime()
	return result

func _pay_palace_maintenance() -> void:
	_get_palace_system().pay_palace_maintenance(self)
	_capture_legacy_palace_state_to_campaign_state()
	_sync_campaign_state_from_current_runtime()

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
	return _get_palace_route_overview_system().tlaloc_controlled_natural_pressure_events()

func _veintena_distance_to(target_veintena: int) -> int:
	return _get_palace_route_overview_system().veintena_distance_to(self, target_veintena)

func _tlaloc_active_structure_tier() -> int:
	return _get_palace_route_overview_system().tlaloc_active_structure_tier(self)

func _tlaloc_active_structure_names() -> Array[String]:
	return _get_palace_route_overview_system().tlaloc_active_structure_names(self)

func _tlaloc_forecast_range_for_tier(tier: int) -> int:
	return _get_palace_route_overview_system().tlaloc_forecast_range_for_tier(tier)

func _tlaloc_forecast_detail_label(tier: int) -> String:
	return _get_palace_route_overview_system().tlaloc_forecast_detail_label(tier)

func _format_veintena_distance(distance: int) -> String:
	return _get_palace_route_overview_system().format_veintena_distance(distance)

func _format_resource_id_list(resource_ids: Array) -> String:
	return _get_palace_route_overview_system().format_resource_id_list(self, resource_ids)

func _tlaloc_forecast_row(event: Dictionary, detail_tier: int, distance: int) -> Dictionary:
	return _get_palace_route_overview_system().tlaloc_forecast_row(self, event, detail_tier, distance)

func get_tlaloc_natural_calendar_forecast() -> Dictionary:
	return _get_palace_route_overview_system().get_tlaloc_natural_calendar_forecast(self)

func _tezcatlipoca_active_structure_tier() -> int:
	return _get_palace_route_overview_system().tezcatlipoca_active_structure_tier(self)

func _tezcatlipoca_active_structure_names() -> Array[String]:
	return _get_palace_route_overview_system().tezcatlipoca_active_structure_names(self)

func _tezcatlipoca_pressure_detail_label(tier: int) -> String:
	return _get_palace_route_overview_system().tezcatlipoca_pressure_detail_label(tier)

func _tezcatlipoca_market_pressure_limit(tier: int) -> int:
	return _get_palace_route_overview_system().tezcatlipoca_market_pressure_limit(tier)

func _tezcatlipoca_pressure_score(good: Dictionary) -> float:
	return _get_palace_route_overview_system().tezcatlipoca_pressure_score(good)

func _tezcatlipoca_market_pressure_row(good: Dictionary, detail_tier: int) -> Dictionary:
	return _get_palace_route_overview_system().tezcatlipoca_market_pressure_row(self, good, detail_tier)

func _tezcatlipoca_rival_pressure_hooks(detail_tier: int) -> Array[Dictionary]:
	return _get_palace_route_overview_system().tezcatlipoca_rival_pressure_hooks(self, detail_tier)

func get_tezcatlipoca_pressure_overview() -> Dictionary:
	return _get_palace_route_overview_system().get_tezcatlipoca_pressure_overview(self)

func _quetzalcoatl_active_structure_tier() -> int:
	return _get_palace_route_overview_system().quetzalcoatl_active_structure_tier(self)

func _quetzalcoatl_active_structure_names() -> Array[String]:
	return _get_palace_route_overview_system().quetzalcoatl_active_structure_names(self)

func _quetzalcoatl_detail_label(tier: int) -> String:
	return _get_palace_route_overview_system().quetzalcoatl_detail_label(tier)

func _quetzalcoatl_legitimacy_rows(detail_tier: int) -> Array[Dictionary]:
	return _get_palace_route_overview_system().quetzalcoatl_legitimacy_rows(detail_tier)

func _quetzalcoatl_obligation_rows(detail_tier: int) -> Array[Dictionary]:
	return _get_palace_route_overview_system().quetzalcoatl_obligation_rows(detail_tier)

func get_quetzalcoatl_legitimacy_overview() -> Dictionary:
	return _get_palace_route_overview_system().get_quetzalcoatl_legitimacy_overview(self)


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
	return _ensure_campaign_state_prestige_bridge().get_player_prestige_value()

func add_player_prestige(amount: float, source_id: String, detail: String, context: Dictionary = {}) -> Dictionary:
	var runtime_state: CampaignState = _ensure_campaign_state_prestige_bridge()
	var result: Dictionary = runtime_state.add_player_prestige_record(amount, source_id, detail, context, get_current_veintena())
	_mirror_prestige_compatibility_from_campaign_state()
	return result

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
	return _ensure_campaign_state_prestige_bridge().get_prestige_history_copy()

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
	var runtime_state: CampaignState = _ensure_campaign_state_prestige_bridge()
	if runtime_state.rival_prestige.is_empty():
		runtime_state.set_rival_prestige_values(_default_rival_prestige_values())
		_mirror_prestige_compatibility_from_campaign_state()
	return runtime_state.get_rival_prestige_copy()

func set_rival_prestige(house_id: String, value: float) -> Dictionary:
	var runtime_state: CampaignState = _ensure_campaign_state_prestige_bridge()
	var result: Dictionary = runtime_state.set_rival_prestige_value(house_id, value)
	_mirror_prestige_compatibility_from_campaign_state()
	_emit_state_changed_and_sync()
	return result

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
	var result: Dictionary = _get_religion_system().sacrifice_for_prestige(self, sacrifice_id, amount, god_id)
	# ReligionSystem still appends sacrifice records through the TRGameState
	# compatibility field. Mirror those records into CampaignState after the call.
	var runtime_state: CampaignState = _get_campaign_state()
	runtime_state.set_sacrifice_prestige_records(sacrifice_prestige_records)
	_mirror_prestige_compatibility_from_campaign_state()
	return result

func get_sacrifice_prestige_records() -> Array[Dictionary]:
	return _ensure_campaign_state_prestige_bridge().get_sacrifice_prestige_records_copy()

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
	var result: Dictionary = _get_palace_system().donate_palace_need(self, slot_id, amount)
	_capture_legacy_palace_state_to_campaign_state()
	_capture_legacy_calendar_report_to_campaign_state()
	_emit_state_changed_and_sync()
	return result

func is_palace_ruler_demand_delivered(slot_id: String) -> bool:
	return _get_palace_system().is_palace_ruler_demand_delivered(self, slot_id)

func can_deliver_palace_ruler_demand(slot_id: String) -> Dictionary:
	return _get_palace_system().can_deliver_palace_ruler_demand(self, slot_id)

func deliver_palace_ruler_demand(slot_id: String) -> Dictionary:
	var result: Dictionary = _get_palace_system().deliver_palace_ruler_demand(self, slot_id)
	_capture_legacy_palace_state_to_campaign_state()
	_capture_legacy_calendar_report_to_campaign_state()
	_emit_state_changed_and_sync()
	return result

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
	return _get_palace_system().get_palace_summary(self)

func get_flower_war_options() -> Array[Dictionary]:
	return _get_flower_war_system().get_flower_war_options(self)

func get_flower_war_defence_strategies() -> Array[Dictionary]:
	return _get_flower_war_system().get_flower_war_defence_strategies()

func start_flower_war_attack_event(option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> Dictionary:
	return _get_flower_war_system().start_attack_event(self, option_id, source_id, context)

func start_flower_war_defence_event(option_id: String = "standard", source_id: String = "rival", context: Dictionary = {}) -> Dictionary:
	return _get_flower_war_system().start_defence_event(self, option_id, source_id, context)

func get_flower_war_event_hook_summary() -> Dictionary:
	return _get_flower_war_system().get_event_hook_summary()

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
	var runtime_state: CampaignState = _ensure_campaign_state_warband_flower_war_bridge()
	return runtime_state.get_last_flower_war_report_copy()

func get_flower_war_report_archive(limit_count: int = 12) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var runtime_state: CampaignState = _ensure_campaign_state_warband_flower_war_bridge()
	var copied: Array[Dictionary] = runtime_state.get_flower_war_report_archive_copy()
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
	var runtime_state: CampaignState = _ensure_campaign_state_warband_flower_war_bridge()
	var stored: Dictionary = report.duplicate(true)
	stored["archive_index"] = runtime_state.get_flower_war_report_archive_count() + 1
	stored["archive_veintena"] = get_current_veintena()
	stored["archive_title"] = _flower_war_archive_title(stored)
	runtime_state.append_flower_war_report_archive(stored, 20)
	_mirror_warband_flower_war_compatibility_from_campaign_state()

func _flower_war_archive_title(report: Dictionary) -> String:
	var direction: String = String(report.get("war_direction", "attack"))
	var option_name: String = String(report.get("option_name", "Flower War"))
	var result: String = String(report.get("result", "Unknown"))
	if direction == "defence":
		return "Defence — " + option_name + " — " + result
	return "Muster — " + option_name + " — " + result

func _flower_war_participant_rows_for_ids(selected_ids: Array[String]) -> Array[Dictionary]:
	return _get_flower_war_system().flower_war_participant_rows_for_ids(self, selected_ids)

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
	return _get_flower_war_system().selected_warband_ids_or_all_ready(self, warband_ids)

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
	return _get_flower_war_system().distribute_integer_by_weights(total, participants, weight_key, cap_by_weight)

func get_flower_war_preview_with_warband(warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	return _get_flower_war_system().get_single_warband_attack_preview(self, warband_id, option_id, doctrine_id, provisioning_id)

func can_launch_flower_war_with_warband(warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	return _get_flower_war_system().can_launch_single_warband_attack(self, warband_id, option_id, doctrine_id, provisioning_id)

func launch_flower_war_with_warband(warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	return _get_flower_war_system().launch_single_warband_attack(self, warband_id, option_id, doctrine_id, provisioning_id)

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
	_get_warband_system().ensure_warband_state(self)

func _make_starting_warband(warband_id: String, name: String, commander: String, ready_warriors: int) -> Dictionary:
	return _get_warband_system().make_starting_warband(warband_id, name, commander, ready_warriors)

func _sync_warband_progress(warband: Dictionary) -> Dictionary:
	return _get_warband_system().sync_warband_progress(warband)

func _warband_xp_required_for_level(level: int) -> int:
	return _get_warband_system().warband_xp_required_for_level(level)

func _warband_xp_to_next(level: int) -> int:
	return _get_warband_system().warband_xp_to_next(level)

func _warband_level_for_xp(xp: int) -> int:
	return _get_warband_system().warband_level_for_xp(xp)

func _warband_spent_trait_points(warband: Dictionary) -> int:
	return _get_warband_system().warband_spent_trait_points(warband)

func _warband_doctrine_from_specialisation(warband: Dictionary) -> String:
	return _get_warband_system().warband_doctrine_from_specialisation(warband)

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
	return _get_warband_system().ensure_warband_skill_defaults(warband)

func _warband_purchased_trait_ids(warband: Dictionary) -> Array[String]:
	return _get_warband_system().warband_purchased_trait_ids(warband)

func _warband_trait_effect_totals_from_purchased(purchased: Array[String]) -> Dictionary:
	return _get_warband_system().warband_trait_effect_totals_from_purchased(purchased)

func _warband_specialisation_summary_for_warband(warband: Dictionary) -> Dictionary:
	return _get_warband_system().warband_specialisation_summary_for_warband(warband)

func _warband_cluster_display_name(cluster_id: String) -> String:
	return _get_warband_system().warband_cluster_display_name(cluster_id)

func _warband_chosen_specialisation_cluster(purchased: Array[String]) -> String:
	return _get_warband_system().warband_chosen_specialisation_cluster(purchased)

func _warband_purchased_specialisation_clusters(purchased: Array[String]) -> Array[String]:
	return _get_warband_system().warband_purchased_specialisation_clusters(purchased)

func _warband_trait_locked_by_specialisation(purchased: Array[String], node: Dictionary) -> bool:
	return _get_warband_system().warband_trait_locked_by_specialisation(purchased, node)

func _warband_specialisation_lock_text(purchased: Array[String]) -> String:
	return _get_warband_system().warband_specialisation_lock_text(purchased)

func _warband_trait_requirements_met(purchased: Array[String], node: Dictionary) -> bool:
	return _get_warband_system().warband_trait_requirements_met(purchased, node)

func _warband_requirements_text(node: Dictionary) -> String:
	return _get_warband_system().warband_requirements_text(node)

func _warband_skill_connections() -> Array[Dictionary]:
	return _get_warband_system().warband_skill_connections()

func _warband_skill_node_by_id(trait_id: String) -> Dictionary:
	return _get_warband_system().warband_skill_node_by_id(trait_id)

func _warband_skill_node_definitions() -> Array[Dictionary]:
	return _get_warband_system().warband_skill_node_definitions()

func _unassigned_warrior_pool() -> int:
	return _get_warband_system().unassigned_warrior_pool(self)

func get_warband_flower_war_stability_audit() -> Dictionary:
	return _get_warband_system().get_warband_flower_war_stability_audit(self)

func _warband_doctrine_name(doctrine_id: String) -> String:
	return _get_warband_system().warband_doctrine_name(doctrine_id)
