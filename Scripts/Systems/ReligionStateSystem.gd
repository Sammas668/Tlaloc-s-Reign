# ReligionStateSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/ReligionStateSystem.gd
#
# CampaignState-backed religion state.
#
# Owns mutable Prototype 0 religion state while persisting that state through
# CampaignState.religion_state. Shrine UI reads and mutates this system through
# UIScreenContext / TRGameState runtime access; the UI controller does not own
# live religion state.
class_name ReligionStateSystem
extends RefCounted

const SCHEMA_VERSION: String = "religion_state_v0_47_5_patch_8h"
const RELIGION_STARTING_FAVOUR: float = 40.0

var _initialized: bool = false
var _divine_favour: Dictionary = {}
var _shrine_levels: Dictionary = {}
var _shrine_upgrades: Dictionary = {}
var _ritual_capacity_used_this_veintena: float = 0.0
var _last_offering_report: Array[String] = []

var _campaign_state: RefCounted = null
var _syncing_from_campaign_state: bool = false

# -----------------------------------------------------------------------------
# CampaignState binding / save-load helpers
# -----------------------------------------------------------------------------

func bind_campaign_state(campaign_state: RefCounted, god_ids: Array = []) -> ReligionStateSystem:
	_campaign_state = campaign_state
	pull_from_campaign_state()
	if not god_ids.is_empty():
		ensure(god_ids)
	return self

func unbind_campaign_state() -> void:
	_campaign_state = null

func pull_from_campaign_state() -> void:
	if _campaign_state == null or not _campaign_state.has_method("get_religion_state_copy"):
		return
	var raw: Variant = _campaign_state.call("get_religion_state_copy")
	if raw is Dictionary:
		apply_state_dictionary(raw as Dictionary)

func push_to_campaign_state() -> void:
	if _syncing_from_campaign_state:
		return
	if _campaign_state == null or not _campaign_state.has_method("set_religion_state"):
		return
	_campaign_state.call("set_religion_state", to_state_dictionary())

func to_state_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"initialized": _initialized,
		"divine_favour": _duplicate_dictionary(_divine_favour),
		"shrine_levels": _duplicate_dictionary(_shrine_levels),
		"shrine_upgrades": _duplicate_dictionary(_shrine_upgrades),
		"ritual_capacity_used_this_veintena": _ritual_capacity_used_this_veintena,
		"last_offering_report": _last_offering_report.duplicate()
	}

func apply_state_dictionary(data: Dictionary) -> void:
	if data.is_empty():
		return
	_syncing_from_campaign_state = true
	_initialized = bool(data.get("initialized", _initialized))
	_divine_favour = _float_dictionary(_dictionary_from_variant(data.get("divine_favour", _divine_favour)))
	_shrine_levels = _int_dictionary(_dictionary_from_variant(data.get("shrine_levels", _shrine_levels)))
	_shrine_upgrades = _upgrade_dictionary(_dictionary_from_variant(data.get("shrine_upgrades", _shrine_upgrades)))
	_ritual_capacity_used_this_veintena = maxf(0.0, float(data.get("ritual_capacity_used_this_veintena", _ritual_capacity_used_this_veintena)))
	_last_offering_report = _string_array_from_variant(data.get("last_offering_report", _last_offering_report))
	_syncing_from_campaign_state = false

func _mark_changed() -> void:
	push_to_campaign_state()

# -----------------------------------------------------------------------------
# Runtime state API
# -----------------------------------------------------------------------------

func ensure(god_ids: Array) -> void:
	var changed: bool = false
	for god_id: String in god_ids:
		if not _divine_favour.has(god_id):
			_divine_favour[god_id] = RELIGION_STARTING_FAVOUR
			changed = true
		if not _shrine_levels.has(god_id):
			_shrine_levels[god_id] = 1
			changed = true
		if not _shrine_upgrades.has(god_id):
			_shrine_upgrades[god_id] = []
			changed = true
	if not _initialized:
		_initialized = true
		changed = true
	if changed:
		_mark_changed()

func is_initialized() -> bool:
	return _initialized

func favour(god_id: String, default_value: float = RELIGION_STARTING_FAVOUR) -> float:
	return float(_divine_favour.get(god_id, default_value))

func set_favour(god_id: String, value: float) -> void:
	_divine_favour[god_id] = clampf(value, 0.0, 100.0)
	_mark_changed()

func shrine_level(god_id: String) -> int:
	return clampi(int(_shrine_levels.get(god_id, 1)), 1, 4)

func set_shrine_level(god_id: String, level: int) -> void:
	_shrine_levels[god_id] = clampi(level, 1, 4)
	_mark_changed()

func purchased_upgrade_ids(god_id: String) -> Array[String]:
	var output: Array[String] = []
	var raw: Array = _array_from_variant(_shrine_upgrades.get(god_id, []))
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
		_mark_changed()

func ritual_capacity_used() -> float:
	return _ritual_capacity_used_this_veintena

func add_ritual_capacity(amount: float) -> void:
	_ritual_capacity_used_this_veintena = maxf(0.0, _ritual_capacity_used_this_veintena + amount)
	_mark_changed()

func reset_ritual_capacity() -> void:
	_ritual_capacity_used_this_veintena = 0.0
	_mark_changed()

func last_offering_report() -> Array[String]:
	var output: Array[String] = []
	for line: String in _last_offering_report:
		output.append(line)
	return output

func has_offering_report() -> bool:
	return not _last_offering_report.is_empty()

func clear_offering_report() -> void:
	_last_offering_report.clear()
	_mark_changed()

func append_offering_report(line: String) -> void:
	_last_offering_report.append(line)
	_mark_changed()

func set_offering_report(lines: Array) -> void:
	_last_offering_report.clear()
	for line: String in lines:
		_last_offering_report.append(line)
	_mark_changed()

# -----------------------------------------------------------------------------
# Utility helpers
# -----------------------------------------------------------------------------

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

func _upgrade_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		var values: Array[String] = []
		for item: Variant in _array_from_variant(source[key_variant]):
			values.append(String(item))
		output[key] = values
	return output

func _duplicate_dictionary(source: Dictionary) -> Dictionary:
	return source.duplicate(true)
