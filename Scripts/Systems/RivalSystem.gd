# RivalSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/RivalSystem.gd
#
# v0.43.20 extraction slice.
# Owns rival identity, pressure-note and placeholder rival-prestige state rules that were previously embedded in TRGameState.
# This is still information-only: it does not add rival AI, procurement, sabotage or turn actions yet.
class_name RivalSystem
extends RefCounted

const SYSTEM_VERSION: String = "v0.43.20"

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
	# Prototype leaderboard placeholders. Rival prestige is displayed so the player
	# understands that Prestige is relative, but rival gain/loss logic is not
	# implemented yet. Future Rival AI patches should replace these with real values.
	return {
		"war_rival": 30.0,
		"cunning_rival": 24.0,
		"diplomatic_rival": 36.0
	}

func ensure_rival_prestige(game_state: Node) -> void:
	if game_state == null:
		return
	var current: Dictionary = game_state.get("rival_prestige") as Dictionary
	if current.is_empty():
		game_state.set("rival_prestige", default_rival_prestige_values())
		return
	var defaults: Dictionary = default_rival_prestige_values()
	var changed: bool = false
	for key_variant: Variant in defaults.keys():
		var rival_id: String = String(key_variant)
		if not current.has(rival_id):
			current[rival_id] = float(defaults[key_variant])
			changed = true
	if changed:
		game_state.set("rival_prestige", current)

func get_rival_prestige(game_state: Node) -> Dictionary:
	if game_state == null:
		return default_rival_prestige_values()
	ensure_rival_prestige(game_state)
	var values: Dictionary = game_state.get("rival_prestige") as Dictionary
	return values.duplicate(true)

func set_rival_prestige(game_state: Node, house_id: String, value: float) -> Dictionary:
	# Debug/prototype helper for later rival tests. It does not spend or transfer Prestige.
	if game_state == null:
		return {"ok": false, "reason": "Rival state is not connected."}
	ensure_rival_prestige(game_state)
	var values: Dictionary = game_state.get("rival_prestige") as Dictionary
	values[house_id] = value
	game_state.set("rival_prestige", values)
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
