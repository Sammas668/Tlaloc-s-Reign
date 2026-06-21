# RivalSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/RivalSystem.gd
#
# Owns rival identity, pressure-note and placeholder rival-prestige state rules.
# Reads/writes CampaignState first through TRGameState accessors, with
# TRGameState field fallback kept only for compatibility.
#
# This is still information-only: it does not add rival AI, procurement,
# sabotage or turn actions yet.

class_name RivalSystem
extends RefCounted

const SYSTEM_VERSION: String = "v0.48_8n2c"


func system_name() -> String:
	return "RivalSystem"


func get_rival_house_definitions() -> Array[Dictionary]:
	return [
		{
			"id": "war_rival",
			"name": "War Rival",
			"god_id": "huitzilopochtli",
			"focus": "Flower Wars, obsidian, weapons, captives and martial prestige.",
			"target_goods": ["obsidian", "weapons", "captives", "cloth", "tools"],
			"prototype_role": "Visible future rival for the Huitzilopochtli / war route."
		},
		{
			"id": "cunning_rival",
			"name": "Cunning Rival",
			"god_id": "tezcatlipoca",
			"focus": "Tools, cloth, wood, storage, bottlenecks and market leverage.",
			"target_goods": ["tools", "cloth", "wood", "cacao", "cotton"],
			"prototype_role": "Visible future rival for the Tezcatlipoca / scarcity-pressure route."
		},
		{
			"id": "diplomatic_rival",
			"name": "Diplomatic Rival",
			"god_id": "quetzalcoatl",
			"focus": "Cacao, fine textiles, noble display, court needs and legitimacy.",
			"target_goods": ["cacao", "fine_textiles", "cloth", "cotton", "tools"],
			"prototype_role": "Visible future rival for the Quetzalcoatl / palace-recognition route."
		}
	]


func default_rival_prestige_values() -> Dictionary:
	return {
		"war_rival": 30.0,
		"cunning_rival": 24.0,
		"diplomatic_rival": 36.0
	}


func ensure_rival_prestige(game_state: Node) -> void:
	if game_state == null:
		return

	var current: Dictionary = _rival_prestige(game_state)
	if current.is_empty():
		_set_rival_prestige(game_state, default_rival_prestige_values())
		return

	var defaults: Dictionary = default_rival_prestige_values()
	var changed: bool = false
	for key_variant: Variant in defaults.keys():
		var rival_id: String = String(key_variant)
		if not current.has(rival_id):
			current[rival_id] = float(defaults[key_variant])
			changed = true

	if changed:
		_set_rival_prestige(game_state, current)


func get_rival_prestige(game_state: Node) -> Dictionary:
	if game_state == null:
		return default_rival_prestige_values()
	ensure_rival_prestige(game_state)
	return _rival_prestige(game_state).duplicate(true)


func set_rival_prestige(game_state: Node, house_id: String, value: float) -> Dictionary:
	# Debug/prototype helper for later rival tests. It does not spend or transfer Prestige.
	if game_state == null:
		return {"ok": false, "reason": "Rival state is not connected."}

	ensure_rival_prestige(game_state)
	var values: Dictionary = _rival_prestige(game_state)
	values[house_id] = value
	_set_rival_prestige(game_state, values)

	if game_state.has_signal("state_changed"):
		game_state.emit_signal("state_changed")

	return {"ok": true, "house_id": house_id, "prestige": value}


func market_note_for_resource(resource_id: String) -> String:
	match resource_id:
		"weapons", "obsidian":
			return "War Rival pressure: weapons, obsidian and martial goods."
		"tools", "cloth":
			return "Cunning Rival pressure: practical bottlenecks and market leverage."
		"cacao", "fine_textiles":
			return "Diplomatic Rival pressure: palace-facing status goods."
	return "Rival behaviour can alter this market once procurement is connected."


func tezcatlipoca_rival_pressure_hooks(detail_tier: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if detail_tier <= 0:
		return rows

	var raw_hooks: Array[Dictionary] = [
		{"id": "war_rival_martial_goods", "rival": "War Rival", "domain": "Obsidian, weapons, captives", "summary": "The War Rival is vulnerable to equipment bottlenecks and captive pressure.", "future_hook": "Future hook: expose or exploit martial-goods shortages before a Flower War."},
		{"id": "cunning_rival_practical_bottlenecks", "rival": "Cunning Rival", "domain": "Tools, cloth, wood", "summary": "The Cunning Rival depends on practical bottlenecks and flexible building goods.", "future_hook": "Future hook: counter-pressure, misinformation or market leverage against practical goods."},
		{"id": "diplomatic_rival_status_goods", "rival": "Diplomatic Rival", "domain": "Cacao, fine textiles, tribute goods", "summary": "The Diplomatic Rival is exposed through status goods and ruler-facing obligations.", "future_hook": "Future hook: palace embarrassment, tribute pressure or credibility disruption."}
	]

	var max_rows: int = 1
	if detail_tier >= 2:
		max_rows = 2
	if detail_tier >= 3:
		max_rows = 3

	for index: int in range(mini(max_rows, raw_hooks.size())):
		var hook: Dictionary = raw_hooks[index]
		var row: Dictionary = {
			"id": String(hook.get("id", "hook")),
			"rival": String(hook.get("rival", "Rival")),
			"domain": "Hidden",
			"summary": "The mirror suggests a rival pressure point, but the details are not yet clear.",
			"future_hook": "Build higher active Tezcatlipoca structures to reveal future manipulation hooks.",
			"detail_tier": detail_tier
		}
		if detail_tier >= 2:
			row["domain"] = String(hook.get("domain", "Pressure goods"))
			row["summary"] = String(hook.get("summary", row["summary"]))
		if detail_tier >= 3:
			row["future_hook"] = String(hook.get("future_hook", row["future_hook"]))
		rows.append(row)

	return rows


func _campaign_state(game_state: Node) -> RefCounted:
	if game_state == null:
		return null
	if game_state.has_method("_get_campaign_state"):
		var raw: Variant = game_state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null

func _rival_prestige(game_state: Node) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(game_state)
	if runtime_state != null and runtime_state.has_method("get_rival_prestige_copy"):
		return runtime_state.call("get_rival_prestige_copy") as Dictionary

	if game_state != null:
		var value: Variant = game_state.get("rival_prestige")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)

	return {}


func _set_rival_prestige(game_state: Node, values: Dictionary) -> void:
	var runtime_state: RefCounted = _campaign_state(game_state)
	if runtime_state != null and runtime_state.has_method("set_rival_prestige_values"):
		runtime_state.call("set_rival_prestige_values", values)
		if game_state != null and game_state.has_method("_mirror_prestige_compatibility_from_campaign_state"):
			game_state.call("_mirror_prestige_compatibility_from_campaign_state")
		return

	if game_state != null:
		game_state.set("rival_prestige", values)
