# ReligionStateSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/ReligionStateSystem.gd
#
# Owns the live Prototype 0 religion state that previously lived directly in
# GameScreenMarketOverviewPatch.gd and then temporarily inside the Shrine screen
# controller. Patch 8D makes this a runtime-owned state holder accessed through
# UIScreenContext / TRGameState metadata bridge, ready for later CampaignState
# migration. Mutable divine favour, shrine levels, shrine upgrades, ritual
# capacity and recent ritual reports should not be stored as UI fields.
extends RefCounted

const RELIGION_STARTING_FAVOUR: float = 40.0

var _initialized: bool = false
var _divine_favour: Dictionary = {}
var _shrine_levels: Dictionary = {}
var _shrine_upgrades: Dictionary = {}
var _ritual_capacity_used_this_veintena: float = 0.0
var _last_offering_report: Array[String] = []

func ensure(god_ids: Array[String]) -> void:
	if _initialized:
		return
	for god_id: String in god_ids:
		_divine_favour[god_id] = RELIGION_STARTING_FAVOUR
		_shrine_levels[god_id] = 1
		_shrine_upgrades[god_id] = []
	_initialized = true

func is_initialized() -> bool:
	return _initialized

func favour(god_id: String, default_value: float = RELIGION_STARTING_FAVOUR) -> float:
	return float(_divine_favour.get(god_id, default_value))

func set_favour(god_id: String, value: float) -> void:
	_divine_favour[god_id] = clampf(value, 0.0, 100.0)

func shrine_level(god_id: String) -> int:
	return clampi(int(_shrine_levels.get(god_id, 1)), 1, 4)

func set_shrine_level(god_id: String, level: int) -> void:
	_shrine_levels[god_id] = clampi(level, 1, 4)

func purchased_upgrade_ids(god_id: String) -> Array[String]:
	var output: Array[String] = []
	var raw: Array = _shrine_upgrades.get(god_id, []) as Array
	for item: Variant in raw:
		output.append(String(item))
	return output

func has_upgrade(god_id: String, upgrade_id: String) -> bool:
	return purchased_upgrade_ids(god_id).has(upgrade_id)

func add_upgrade(god_id: String, upgrade_id: String) -> void:
	var upgrades: Array[String] = purchased_upgrade_ids(god_id)
	if not upgrades.has(upgrade_id):
		upgrades.append(upgrade_id)
	_shrine_upgrades[god_id] = upgrades

func ritual_capacity_used() -> float:
	return _ritual_capacity_used_this_veintena

func add_ritual_capacity(amount: float) -> void:
	_ritual_capacity_used_this_veintena = maxf(0.0, _ritual_capacity_used_this_veintena + amount)

func reset_ritual_capacity() -> void:
	_ritual_capacity_used_this_veintena = 0.0

func last_offering_report() -> Array[String]:
	var output: Array[String] = []
	for line: String in _last_offering_report:
		output.append(line)
	return output

func has_offering_report() -> bool:
	return not _last_offering_report.is_empty()

func clear_offering_report() -> void:
	_last_offering_report.clear()

func append_offering_report(line: String) -> void:
	_last_offering_report.append(line)

func set_offering_report(lines: Array[String]) -> void:
	_last_offering_report.clear()
	for line: String in lines:
		_last_offering_report.append(line)
