# PrestigeSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/PrestigeSystem.gd
#
# Owns Prestige calculation and summary rules.
# Reads/writes CampaignState through TRGameState runtime accessors instead of
# treating TRGameState mirror fields as the source of truth.

class_name PrestigeSystem
extends RefCounted

const SCHEMA_SAVVY_TRADE: String = "savvy_trade_prestige_v0_43_1"
const SCHEMA_ECONOMIC_SUMMARY: String = "economic_prestige_savvy_trade_v0_43_1"
const SCHEMA_PRESTIGE_CORE: String = "prestige_core_v0_43_1"


func resource_base_value(state: Node, resource_id: String) -> float:
	var resources: Dictionary = _campaign_resources(state)
	if resources.has(resource_id):
		var data: Dictionary = resources[resource_id] as Dictionary
		return float(data.get("base_value", 1.0))
	return 1.0


func get_savvy_trade_prestige_scale() -> float:
	# Economic Prestige should be small, deliberate and tied to good market judgement.
	# Selling high and buying low produce Prestige from the value advantage over the
	# good's base value. This is not passive surplus Prestige.
	return 0.25


func get_savvy_trade_prestige_for_line(state: Node, resource_id: String, amount: float, average_unit_value: float) -> Dictionary:
	var traded_amount: float = absf(amount)
	var base_value: float = resource_base_value(state, resource_id)
	var direction: String = "none"
	var advantage_per_unit: float = 0.0

	if amount < -0.001:
		direction = "sell_high"
		advantage_per_unit = maxf(0.0, average_unit_value - base_value)
	elif amount > 0.001:
		direction = "buy_low"
		advantage_per_unit = maxf(0.0, base_value - average_unit_value)

	var prestige_gain: float = snappedf(traded_amount * advantage_per_unit * get_savvy_trade_prestige_scale(), 0.01)
	var label: String = "No savvy trade Prestige"
	var resource_name: String = _resource_name(state, resource_id)

	if prestige_gain > 0.001:
		if direction == "sell_high":
			label = "Sold high: " + resource_name + " +" + _format_amount(prestige_gain) + " Prestige"
		elif direction == "buy_low":
			label = "Bought low: " + resource_name + " +" + _format_amount(prestige_gain) + " Prestige"

	return {
		"resource_id": resource_id,
		"resource_name": resource_name,
		"amount": amount,
		"traded_amount": traded_amount,
		"direction": direction,
		"base_value": base_value,
		"average_unit_value": average_unit_value,
		"advantage_per_unit": advantage_per_unit,
		"scale": get_savvy_trade_prestige_scale(),
		"prestige_gain": prestige_gain,
		"label": label
	}


func get_savvy_trade_prestige_preview(state: Node, trade_lines: Array) -> Dictionary:
	var lines: Array[Dictionary] = []
	var total: float = 0.0

	for line_variant: Variant in trade_lines:
		if not (line_variant is Dictionary):
			continue
		var line: Dictionary = line_variant as Dictionary
		var resource_id: String = String(line.get("resource_id", ""))
		if resource_id == "":
			continue
		var amount: float = float(line.get("amount", 0.0))
		var average_unit_value: float = float(line.get("average_unit_value", line.get("average_value", line.get("unit_value", resource_base_value(state, resource_id)))))
		var result: Dictionary = get_savvy_trade_prestige_for_line(state, resource_id, amount, average_unit_value)
		lines.append(result)
		total += float(result.get("prestige_gain", 0.0))

	total = snappedf(total, 0.01)
	var positive_lines: Array[String] = []
	for result: Dictionary in lines:
		if float(result.get("prestige_gain", 0.0)) > 0.001:
			positive_lines.append(String(result.get("label", "Savvy trade")))

	var headline: String = "No savvy trade Prestige."
	if total > 0.001:
		headline = "Savvy trade Prestige: +" + _format_amount(total)

	return {
		"schema_version": SCHEMA_SAVVY_TRADE,
		"total_prestige": total,
		"lines": lines,
		"positive_lines": positive_lines,
		"headline": headline,
		"scale": get_savvy_trade_prestige_scale(),
		"mechanics_note": "Economic Prestige comes from market skill only: sell above base value or buy below base value. No passive surplus, maize stockpile or production-output Prestige is granted."
	}


func record_savvy_trade_prestige(state: Node, trade_lines: Array, detail: String = "Savvy market trade") -> Dictionary:
	var preview: Dictionary = get_savvy_trade_prestige_preview(state, trade_lines)
	var amount: float = float(preview.get("total_prestige", 0.0))
	var current_prestige: float = _player_prestige(state)

	if amount <= 0.001:
		return {"ok": true, "amount": 0.0, "prestige": current_prestige, "preview": preview}

	var result: Dictionary = {}
	if state != null and state.has_method("add_player_prestige"):
		result = state.call("add_player_prestige", amount, "economic_savvy_trade", detail, preview) as Dictionary

	_append_report_line(state, detail + ": +" + _format_amount(amount) + " Prestige from savvy trade.")

	if state != null and state.has_signal("state_changed"):
		state.emit_signal("state_changed")

	return {"ok": true, "amount": amount, "prestige": _player_prestige(state), "preview": preview, "record": result.get("record", {})}


func get_economic_prestige_summary(state: Node) -> Dictionary:
	var recent: Array[Dictionary] = []
	var history: Array[Dictionary] = _prestige_history(state)
	history.reverse()

	for item: Dictionary in history:
		if String(item.get("source_id", "")) != "economic_savvy_trade":
			continue
		if recent.size() >= 8:
			break
		recent.append(item.duplicate(true))

	return {
		"schema_version": SCHEMA_ECONOMIC_SUMMARY,
		"active": true,
		"scale": get_savvy_trade_prestige_scale(),
		"recent_savvy_trades": recent,
		"headline": "Economic Prestige comes from savvy market trades.",
		"mechanics_note": "Sell goods above base value or buy goods below base value. Passive surplus, stored maize and production output do not grant economic Prestige."
	}


func format_signed_prestige(amount: float) -> String:
	var prefix: String = "+" if amount >= 0.0 else ""
	return prefix + _format_amount(amount)


func flower_war_result_prestige_value(result: String) -> float:
	match result:
		"Crushing Victory":
			return 20.0
		"Victory":
			return 12.0
		"Marginal Victory", "Narrow Victory":
			return 6.0
		"Stalemate":
			return 0.0
		"Defeat":
			return -5.0
		"Crushing Defeat":
			return -15.0
	return 0.0


func flower_war_prestige_breakdown(report: Dictionary) -> Dictionary:
	var direction: String = String(report.get("war_direction", "attack"))
	var result: String = String(report.get("result", "Stalemate"))
	var outcome_prestige: float = flower_war_result_prestige_value(result)
	var enemy_casualties: int = 0

	if direction == "defence":
		enemy_casualties = int(report.get("enemy_casualties", 0))
	else:
		enemy_casualties = int(report.get("defender_casualties", 0))

	var enemy_casualty_prestige: float = snappedf(float(enemy_casualties) * 0.20, 0.01)
	var captives: int = 0
	var captive_prestige: float = 0.0
	var loot_value: float = 0.0
	var loot_prestige: float = 0.0

	if direction != "defence":
		captives = int(report.get("captives", 0))
		captive_prestige = snappedf(float(captives) * 2.0, 0.01)
		loot_value = float(report.get("loot_value", 0.0))
		loot_prestige = snappedf(maxf(0.0, loot_value) * 0.05, 0.01)

	var total: float = snappedf(outcome_prestige + enemy_casualty_prestige + captive_prestige + loot_prestige, 0.01)
	var lines: Array[String] = []
	lines.append("Outcome " + result + ": " + format_signed_prestige(outcome_prestige))

	if enemy_casualties > 0:
		lines.append("Enemy casualties " + str(enemy_casualties) + ": +" + _format_amount(enemy_casualty_prestige))
	if captives > 0:
		lines.append("Captives " + str(captives) + ": +" + _format_amount(captive_prestige))
	if loot_prestige > 0.0:
		lines.append("Loot value " + _format_amount(loot_value) + ": +" + _format_amount(loot_prestige))
	if lines.is_empty():
		lines.append("No Prestige change.")

	return {
		"direction": direction,
		"result": result,
		"outcome_prestige": outcome_prestige,
		"enemy_casualties": enemy_casualties,
		"enemy_casualty_prestige": enemy_casualty_prestige,
		"captives": captives,
		"captive_prestige": captive_prestige,
		"loot_value": loot_value,
		"loot_prestige": loot_prestige,
		"total": total,
		"lines": lines
	}


func flower_war_preview_prestige_for_attack(result: String, defender_casualties: int, captives: int, loot_value: float) -> Dictionary:
	return flower_war_prestige_breakdown({
		"war_direction": "attack",
		"result": result,
		"defender_casualties": defender_casualties,
		"captives": captives,
		"loot_value": loot_value
	})


func flower_war_preview_prestige_for_defence(result: String, enemy_casualties: int) -> Dictionary:
	return flower_war_prestige_breakdown({
		"war_direction": "defence",
		"result": result,
		"enemy_casualties": enemy_casualties
	})


func prestige_text_from_breakdown(breakdown: Dictionary) -> String:
	return "Prestige " + format_signed_prestige(float(breakdown.get("total", 0.0)))


func apply_flower_war_prestige_to_report(state: Node, report: Dictionary) -> Dictionary:
	var breakdown: Dictionary = flower_war_prestige_breakdown(report)
	var amount: float = float(breakdown.get("total", 0.0))
	var direction: String = String(report.get("war_direction", "attack"))
	var result: String = String(report.get("result", "Stalemate"))
	var source_id: String = "flower_war_defence" if direction == "defence" else "flower_war_attack"
	var detail: String = "Flower War " + ("defence" if direction == "defence" else "muster") + ": " + result

	if absf(amount) > 0.0001 and state != null and state.has_method("add_player_prestige"):
		state.call("add_player_prestige", amount, source_id, detail, breakdown)

	report["prestige_pending"] = false
	report["prestige_gain"] = amount
	report["prestige_breakdown"] = breakdown
	report["prestige_text"] = prestige_text_from_breakdown(breakdown)
	return report


func default_rival_prestige_values() -> Dictionary:
	# Prototype leaderboard placeholders. Rival prestige is displayed so the player
	# understands that Prestige is relative, but rival gain/loss logic is not
	# implemented yet. Future Rival AI patches should replace these with real values.
	return {
		"war_rival": 30.0,
		"cunning_rival": 24.0,
		"diplomatic_rival": 36.0
	}


func prestige_house_name(house_id: String) -> String:
	match house_id:
		"player":
			return "Player House"
		"war_rival":
			return "War Rival"
		"cunning_rival":
			return "Cunning Rival"
		"diplomatic_rival":
			return "Diplomatic Rival"
	return house_id.capitalize()


func get_prestige_leaderboard(state: Node) -> Array[Dictionary]:
	var player_prestige: float = _player_prestige(state)
	var rival_prestige: Dictionary = _rival_prestige(state)

	if rival_prestige.is_empty():
		rival_prestige = default_rival_prestige_values()
		_set_rival_prestige(state, rival_prestige)

	var rows: Array[Dictionary] = []
	rows.append({"house_id": "player", "name": prestige_house_name("player"), "prestige": player_prestige, "is_player": true, "source": "live"})

	for rival_id_variant: Variant in rival_prestige.keys():
		var rival_id: String = String(rival_id_variant)
		rows.append({"house_id": rival_id, "name": prestige_house_name(rival_id), "prestige": float(rival_prestige[rival_id_variant]), "is_player": false, "source": "placeholder"})

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_value: float = float(a.get("prestige", 0.0))
		var b_value: float = float(b.get("prestige", 0.0))
		if is_equal_approx(a_value, b_value):
			return String(a.get("name", "")) < String(b.get("name", ""))
		return a_value > b_value
	)

	var rank: int = 1
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		if index > 0:
			var previous: Dictionary = rows[index - 1] as Dictionary
			if not is_equal_approx(float(row.get("prestige", 0.0)), float(previous.get("prestige", 0.0))):
				rank = index + 1
		row["rank"] = rank
		rows[index] = row

	return rows


func get_player_prestige_rank(state: Node) -> Dictionary:
	for row: Dictionary in get_prestige_leaderboard(state):
		if bool(row.get("is_player", false)):
			return row.duplicate(true)
	return {"rank": 0, "name": "Player House", "prestige": _player_prestige(state), "is_player": true}


func get_prestige_summary(state: Node) -> Dictionary:
	var leaderboard: Array[Dictionary] = get_prestige_leaderboard(state)
	var player_rank: Dictionary = get_player_prestige_rank(state)
	var history_rows: Array[Dictionary] = _prestige_history(state)
	history_rows.reverse()

	var latest_history: Array[Dictionary] = []
	for item: Dictionary in history_rows:
		if latest_history.size() >= 8:
			break
		latest_history.append(item.duplicate(true))

	return {
		"schema_version": SCHEMA_PRESTIGE_CORE,
		"player_prestige": _player_prestige(state),
		"rival_prestige": get_rival_prestige(state),
		"leaderboard": leaderboard,
		"player_rank": player_rank,
		"player_rank_number": int(player_rank.get("rank", 0)),
		"prestige_history": _prestige_history(state),
		"recent_history": latest_history,
		"mechanics_note": "Prestige is the main score. It is earned, lost, displayed and compared against rivals. It is never spent. Court-need donations, Flower War outcomes, rituals, shrine levels, sacrifices and savvy market trades currently add Prestige."
	}


func get_rival_prestige(state: Node) -> Dictionary:
	var rival_values: Dictionary = _rival_prestige(state)
	if rival_values.is_empty():
		rival_values = default_rival_prestige_values()
		_set_rival_prestige(state, rival_values)
	return rival_values.duplicate(true)


# -----------------------------------------------------------------------------
# CampaignState-first helper access
# -----------------------------------------------------------------------------

func _campaign_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null


func _campaign_resources(state: Node) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		var runtime_value: Variant = runtime_state.get("resources")
		if runtime_value is Dictionary:
			return runtime_value as Dictionary
	return {}


func _player_prestige(state: Node) -> float:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_player_prestige_value"):
		return float(runtime_state.call("get_player_prestige_value"))
	if state != null and state.has_method("get_player_prestige"):
		return float(state.call("get_player_prestige"))
	return 0.0


func _rival_prestige(state: Node) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_rival_prestige_copy"):
		return runtime_state.call("get_rival_prestige_copy") as Dictionary
	return {}


func _set_rival_prestige(state: Node, values: Dictionary) -> void:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("set_rival_prestige_values"):
		runtime_state.call("set_rival_prestige_values", values)
		if state != null and state.has_method("_mirror_prestige_compatibility_from_campaign_state"):
			state.call("_mirror_prestige_compatibility_from_campaign_state")


func _prestige_history(state: Node) -> Array[Dictionary]:
	if state != null and state.has_method("get_prestige_history"):
		return state.call("get_prestige_history") as Array[Dictionary]

	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_prestige_history_copy"):
		return runtime_state.call("get_prestige_history_copy") as Array[Dictionary]

	return []


func _append_report_line(state: Node, line: String) -> void:
	if state != null and state.has_method("_append_report_line"):
		state.call("_append_report_line", line)
		return

	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("append_report_line"):
		runtime_state.call("append_report_line", line)
		if state != null and state.has_method("_mirror_calendar_report_compatibility_from_campaign_state"):
			state.call("_mirror_calendar_report_compatibility_from_campaign_state")


func _resource_name(state: Node, resource_id: String) -> String:
	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))
	return resource_id.capitalize()


func _format_amount(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))
