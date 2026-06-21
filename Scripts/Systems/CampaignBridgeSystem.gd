# CampaignBridgeSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/CampaignBridgeSystem.gd
#
# CampaignState bridge.
#
# Owns compatibility entry points while CampaignState is the authoritative
# live/save-state owner. TRGameState remains the public runtime facade for UI
# and systems, but 8O3 has removed the old live-state mirror fields from the
# facade through static resource/building and market-domain mirrors.
class_name CampaignBridgeSystem
extends RefCounted

func _get_campaign_state(state: Node) -> RefCounted:
	if state == null or not state.has_method("_get_campaign_state"):
		return null
	var runtime_state: Variant = state.call("_get_campaign_state")
	if runtime_state is RefCounted:
		return runtime_state as RefCounted
	return null

# -----------------------------------------------------------------------------
# Full bridge sync
# -----------------------------------------------------------------------------

func sync_from_current_runtime(state: Node) -> void:
	var snapshot: RefCounted = _get_campaign_state(state)
	if snapshot == null:
		return

	# 8O3G: all active TRGameState live-state compatibility mirrors through the
	# static resource/building and market domains have been deleted. Do not copy
	# from TRGameState here; missing mirror properties would overwrite the true
	# CampaignState data with empty fallback values.
	mirror_rival_state_from_campaign_state_to_legacy(state)
	mirror_religion_state_from_campaign_state_to_legacy(state)

func apply_campaign_state_to_current_runtime(state: Node) -> void:
	# 8O4A: broad CampaignState -> TRGameState application is retired.
	# TRGameState is now a facade only; live state stays in CampaignState.
	# Retain this method as a no-op compatibility hook until all old callers are gone.
	return

# -----------------------------------------------------------------------------
# Calendar/report authority
# -----------------------------------------------------------------------------

func ensure_campaign_state_calendar_report_bridge(state: Node) -> RefCounted:
	return _get_campaign_state(state)

func set_current_veintena_value(state: Node, value: int) -> int:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state == null:
		return value
	return int(runtime_state.call("set_current_veintena", value))

func set_calendar_period_value(state: Node, value: String) -> String:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state == null:
		return value
	return String(runtime_state.call("set_calendar_period_value", value))

func set_ritual_year_value(state: Node, value: int) -> int:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state == null:
		return value
	return int(runtime_state.call("set_ritual_year_value", value))

func set_calendar_runtime_state(state: Node, veintena: int, ritual_year: int, period: String) -> void:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state == null:
		return
	runtime_state.call("set_current_veintena", veintena)
	runtime_state.call("set_ritual_year_value", ritual_year)
	runtime_state.call("set_calendar_period_value", period)

func clear_report_lines(state: Node) -> void:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state != null:
		runtime_state.call("clear_last_report")

func set_report_lines(state: Node, lines: Array) -> void:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state != null:
		runtime_state.call("set_last_report", lines)

func append_report_line(state: Node, line: String) -> void:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state != null:
		runtime_state.call("append_report_line", line)

func set_last_turn_summary(state: Node, summary: Dictionary) -> void:
	var runtime_state: RefCounted = ensure_campaign_state_calendar_report_bridge(state)
	if runtime_state != null:
		runtime_state.call("set_last_turn_summary", summary)

# -----------------------------------------------------------------------------
# Stockpile bridge
# -----------------------------------------------------------------------------

func ensure_campaign_state_stockpile_bridge(state: Node) -> RefCounted:
	# 8O3D: stockpile state is CampaignState-direct. This bridge is retained only
	# as a safe compatibility hook for callers that still ask for it.
	return _get_campaign_state(state)

func mirror_stockpile_compatibility_from_campaign_state(state: Node) -> void:
	# 8O3D: compatibility hook retained, but no estate/market stockpile mirrors
	# are written back onto TRGameState.
	pass

# -----------------------------------------------------------------------------
# Palace bridge
# -----------------------------------------------------------------------------

func ensure_campaign_state_palace_bridge(state: Node) -> RefCounted:
	# 8O3C: palace state is CampaignState-direct. This bridge is retained only
	# as a safe compatibility hook for callers that still ask for it.
	return _get_campaign_state(state)

func capture_legacy_palace_state_to_campaign_state(state: Node) -> void:
	# 8O3C: TRGameState palace mirrors have been deleted, so there is no legacy
	# palace state to capture back into CampaignState.
	pass

func mirror_palace_state_from_campaign_state_to_legacy(state: Node) -> void:
	# 8O3C: compatibility hook retained, but no palace mirrors are written back
	# onto TRGameState.
	pass

# -----------------------------------------------------------------------------
# Estate / population / warband bridge
# -----------------------------------------------------------------------------

func ensure_campaign_state_estate_structure_bridge(state: Node) -> RefCounted:
	# 8O3E: estate buildings, active housing, population, base housing capacity
	# and labour assignments are CampaignState-direct. This bridge is retained only
	# as a safe compatibility hook for callers that still ask for it.
	return _get_campaign_state(state)

func mirror_estate_structure_compatibility_from_campaign_state(state: Node) -> void:
	# 8O3E: compatibility hook retained, but no estate/population/labour mirrors
	# are written back onto TRGameState.
	pass

func ensure_campaign_state_warband_flower_war_bridge(state: Node) -> RefCounted:
	# 8O3F: warband and Flower War report state are CampaignState-direct. This
	# bridge is retained only as a safe compatibility hook for callers that still
	# ask for it.
	return _get_campaign_state(state)

func mirror_warband_flower_war_compatibility_from_campaign_state(state: Node) -> void:
	# 8O3F: compatibility hook retained, but no warband / Flower War report mirrors
	# are written back onto TRGameState.
	pass

# -----------------------------------------------------------------------------
# Prestige bridge
# -----------------------------------------------------------------------------

func ensure_campaign_state_prestige_bridge(state: Node) -> RefCounted:
	# Prestige is CampaignState-direct after 8O3B. This helper remains only as a
	# harmless compatibility entry point for old diagnostics; it does not seed from
	# or mirror back to TRGameState fields.
	return _get_campaign_state(state)

# -----------------------------------------------------------------------------
# Religion and rival placeholder bridge for 8H/10 readiness
# -----------------------------------------------------------------------------

func ensure_campaign_state_religion_bridge(state: Node) -> RefCounted:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null:
		return null
	var current: Dictionary = {}
	if runtime_state.has_method("get_religion_state_copy"):
		current = runtime_state.call("get_religion_state_copy") as Dictionary
	if current.is_empty():
		var legacy: Variant = _legacy_meta_or_property(state, "religion_state", {})
		if legacy is Dictionary and not (legacy as Dictionary).is_empty() and runtime_state.has_method("set_religion_state"):
			runtime_state.call("set_religion_state", legacy as Dictionary)
	mirror_religion_state_from_campaign_state_to_legacy(state)
	return runtime_state

func mirror_religion_state_from_campaign_state_to_legacy(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null or state == null:
		return
	if runtime_state.has_method("mirror_religion_state_to_game_state"):
		runtime_state.call("mirror_religion_state_to_game_state", state)

func mirror_rival_state_from_campaign_state_to_legacy(state: Node) -> void:
	var runtime_state: RefCounted = _get_campaign_state(state)
	if runtime_state == null or state == null:
		return
	if runtime_state.has_method("mirror_rival_state_to_game_state"):
		runtime_state.call("mirror_rival_state_to_game_state", state)

# -----------------------------------------------------------------------------
# Signals and audit
# -----------------------------------------------------------------------------

func emit_state_changed_and_sync(state: Node) -> void:
	sync_from_current_runtime(state)
	if state != null and state.has_signal("state_changed"):
		state.emit_signal("state_changed")

func get_campaign_state_sync_report(state: Node, sync_first: bool = false) -> Dictionary:
	if sync_first:
		sync_from_current_runtime(state)
	return {
		"schema_version": "campaign_state_sync_report_v0_47_5_patch_8o3g",
		"sync_first": sync_first,
		"field_count": 0,
		"mismatch_count": 0,
		"in_sync": true,
		"rows": [],
		"calendar_report_authority": "CampaignState-direct; TRGameState calendar/report mirrors removed in 8O3A.",
		"prestige_authority": "CampaignState-direct; TRGameState prestige mirrors removed in 8O3B.",
		"palace_authority": "CampaignState-direct; TRGameState palace mirrors removed in 8O3C.",
		"stockpile_authority": "CampaignState-direct; TRGameState estate/market stockpile mirrors removed in 8O3D.",
		"estate_population_authority": "CampaignState-direct; TRGameState estate/population/labour mirrors removed in 8O3E.",
		"warband_flower_war_authority": "CampaignState-direct; TRGameState warband/Flower War report mirrors removed in 8O3F.",
		"static_market_authority": "CampaignState-direct; TRGameState resource/building and market-demand/economy mirrors removed in 8O3G.",
		"diagnostic_note": "No live-state mirror fields remain for this bridge to compare."
	}

func is_campaign_state_mirror_in_sync(state: Node) -> bool:
	var report: Dictionary = get_campaign_state_sync_report(state, false)
	return bool(report.get("in_sync", false))

func campaign_state_compare_text(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		var keys: Array[String] = []
		for key_variant: Variant in dictionary.keys():
			keys.append(str(key_variant))
		keys.sort()
		var parts: Array[String] = []
		for key: String in keys:
			parts.append(key + ":" + campaign_state_compare_text(dictionary.get(key)))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var array_value: Array = value as Array
		var parts: Array[String] = []
		for item: Variant in array_value:
			parts.append(campaign_state_compare_text(item))
		return "[" + ",".join(parts) + "]"
	return str(value)

func campaign_state_preview(value: Variant) -> String:
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

# -----------------------------------------------------------------------------
# Small compatibility helpers
# -----------------------------------------------------------------------------

func _legacy_value(state: Node, property_name: String, fallback: Variant) -> Variant:
	if state == null:
		return fallback
	var value: Variant = state.get(property_name)
	if value == null:
		return fallback
	return value

func _legacy_meta_or_property(state: Node, key: String, fallback: Variant) -> Variant:
	if state == null:
		return fallback
	if state.has_meta(key):
		return state.get_meta(key)
	var value: Variant = state.get(key)
	if value == null:
		return fallback
	return value
