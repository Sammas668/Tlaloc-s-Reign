# FlowerWarSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/FlowerWarSystem.gd
#
# Extracted Flower War rules slice.
# TRGameState remains the live state owner during the architecture split.
class_name FlowerWarSystem
extends RefCounted

const FLOWER_WAR_DOCTRINES: Dictionary = {
	"unspecialised": {"name": "Unspecialised", "offence": 1.0, "defence": 1.0, "role": "Balanced household warriors."},
	"eagle": {"name": "Eagle", "offence": 1.0, "defence": 1.2, "role": "Captive specialists and sustained war fighters."},
	"jaguar": {"name": "Jaguar", "offence": 1.3, "defence": 1.0, "role": "Elite offensive warriors. No hidden Prestige bonus; Prestige comes from victories, casualties, captives and loot."},
	"otomi": {"name": "Otomi", "offence": 1.0, "defence": 1.5, "role": "Defensive veterans who preserve warriors without sacrificing baseline offence."},
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
	"balanced": {"name": "Balanced Defence", "offence_multiplier": 1.0, "defence_multiplier": 1.0, "casualty_multiplier": 1.0, "description": "Hold the line without taking unusual risks."},
	"depth": {"name": "Defence in Depth", "offence_multiplier": 0.85, "defence_multiplier": 1.25, "casualty_multiplier": 0.75, "description": "Preserve warriors by yielding ground and absorbing the raid."},
	"good_offence": {"name": "Aggressive Counterattack", "offence_multiplier": 1.25, "defence_multiplier": 0.85, "casualty_multiplier": 1.25, "description": "Punish attackers at higher risk to defending warbands."}
}

func get_flower_war_options(state: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for option_id: String in ["minor", "standard", "major"]:
		var data: Dictionary = FLOWER_WAR_OPTIONS[option_id] as Dictionary
		var row: Dictionary = data.duplicate(true)
		row["id"] = option_id
		var warrior_count: int = 0
		if state != null and state.has_method("get_warrior_count"):
			warrior_count = int(state.call("get_warrior_count"))
		row["can_launch_standard"] = warrior_count >= int(row.get("warriors", 0))
		rows.append(row)
	return rows

func get_flower_war_defence_strategies() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for strategy_id: String in ["balanced", "depth", "good_offence"]:
		var data: Dictionary = FLOWER_WAR_DEFENCE_STRATEGIES[strategy_id] as Dictionary
		var row: Dictionary = data.duplicate(true)
		row["id"] = strategy_id
		rows.append(row)
	return rows

func flower_war_defence_strategy_data(strategy_id: String) -> Dictionary:
	var cleaned: String = strategy_id
	if not FLOWER_WAR_DEFENCE_STRATEGIES.has(cleaned):
		cleaned = "balanced"
	var data: Dictionary = (FLOWER_WAR_DEFENCE_STRATEGIES[cleaned] as Dictionary).duplicate(true)
	data["id"] = cleaned
	return data

func flower_war_result_label(net_damage: int, attacker_size: int, defender_size: int) -> String:
	var scale: float = maxf(1.0, float(max(attacker_size, defender_size)))
	var ratio: float = float(net_damage) / scale
	if ratio >= 0.65:
		return "Crushing Victory"
	if ratio >= 0.25:
		return "Victory"
	if ratio > 0.05:
		return "Marginal Victory"
	if ratio >= -0.05:
		return "Stalemate"
	if ratio > -0.35:
		return "Defeat"
	return "Crushing Defeat"

func flower_war_captives(result: String, defender_casualties: int, warriors_committed: int, doctrine_id: String) -> int:
	if defender_casualties <= 0:
		return 0
	var rate: float = 0.0
	match result:
		"Crushing Victory":
			rate = 0.45
		"Victory":
			rate = 0.30
		"Marginal Victory":
			rate = 0.15
		_:
			rate = 0.0
	if doctrine_id == "eagle":
		rate += float(warriors_committed) * 0.02
	var raw: float = float(defender_casualties) * rate
	if raw > 0.0:
		return mini(defender_casualties, max(1, int(ceil(raw))))
	return 0

func flower_war_captives_for_all_warbands(result: String, defender_casualties: int, warriors_committed: int, eagle_warriors: int) -> int:
	if defender_casualties <= 0:
		return 0
	var rate: float = 0.0
	match result:
		"Crushing Victory":
			rate = 0.45
		"Victory":
			rate = 0.30
		"Marginal Victory":
			rate = 0.15
		_:
			rate = 0.0
	if eagle_warriors > 0:
		rate += float(eagle_warriors) * 0.02
	var raw: float = float(defender_casualties) * rate
	if raw > 0.0:
		return mini(defender_casualties, max(1, int(ceil(raw))))
	return 0

func flower_war_loot(result: String, defender_casualties: int, doctrine_id: String, base_loot_value: float) -> Dictionary:
	var multiplier: float = _loot_multiplier_for_result(result)
	if doctrine_id == "coyote":
		multiplier *= 1.5
	return _loot_bundle_from_units(float(defender_casualties) * base_loot_value * multiplier)

func flower_war_loot_for_all_warbands(result: String, defender_casualties: int, coyote_warriors: int, warriors_committed: int, base_loot_value: float) -> Dictionary:
	var multiplier: float = _loot_multiplier_for_result(result)
	if coyote_warriors > 0 and warriors_committed > 0:
		multiplier *= 1.0 + 0.5 * (float(coyote_warriors) / float(warriors_committed))
	return _loot_bundle_from_units(float(defender_casualties) * base_loot_value * multiplier)

func flower_war_loot_display_value(state: Node, loot: Dictionary) -> float:
	var total: float = 0.0
	var resources: Dictionary = {}
	if state != null:
		var resources_variant: Variant = state.get("resources")
		if resources_variant is Dictionary:
			resources = resources_variant as Dictionary
	for resource_variant: Variant in loot.keys():
		var resource_id: String = String(resource_variant)
		var base_value: float = 1.0
		if resources.has(resource_id):
			var resource_data: Dictionary = resources[resource_id] as Dictionary
			base_value = float(resource_data.get("base_value", 1.0))
		total += float(loot[resource_variant]) * base_value
	return snappedf(total, 0.01)

func flower_war_xp_gain(result: String, warriors_committed: int, defender_casualties: int, captives: int) -> int:
	var result_bonus: int = 0
	match result:
		"Crushing Victory":
			result_bonus = 8
		"Victory":
			result_bonus = 5
		"Marginal Victory":
			result_bonus = 3
		"Stalemate":
			result_bonus = 2
		"Defeat":
			result_bonus = 1
		_:
			result_bonus = 1
	return max(1, warriors_committed + defender_casualties * 2 + captives * 4 + result_bonus)

func flower_war_provisioning_cost(warriors_committed: int, supply_multiplier: float) -> Dictionary:
	return {"maize": float(warriors_committed) * 1.0 * supply_multiplier, "weapons": float(warriors_committed) * 0.2 * supply_multiplier}

func _loot_multiplier_for_result(result: String) -> float:
	match result:
		"Crushing Victory":
			return 2.0
		"Victory":
			return 1.2
		"Marginal Victory":
			return 0.6
		"Stalemate":
			return 0.3
		"Defeat":
			return 0.1
		_:
			return 0.0

func _loot_bundle_from_units(raw_units: float) -> Dictionary:
	var units: float = maxf(0.0, raw_units)
	if units <= 0.0:
		return {}
	return {
		"maize": snappedf(units * 0.50, 0.01),
		"wood": snappedf(units * 0.25, 0.01),
		"cloth": snappedf(units * 0.15, 0.01),
		"obsidian": snappedf(units * 0.10, 0.01)
	}


# -----------------------------------------------------------------------------
# Attack preview construction v0.43.15
# -----------------------------------------------------------------------------

func get_single_doctrine_attack_preview(state: Node, option_id: String = "minor", doctrine_id: String = "unspecialised", provisioning_id: String = "standard") -> Dictionary:
	if not FLOWER_WAR_OPTIONS.has(option_id):
		return {"ok": false, "reason": "Unknown Flower War option."}
	if not FLOWER_WAR_DOCTRINES.has(doctrine_id):
		doctrine_id = "unspecialised"
	if not FLOWER_WAR_PROVISIONING.has(provisioning_id):
		provisioning_id = "standard"
	var option: Dictionary = FLOWER_WAR_OPTIONS[option_id] as Dictionary
	var doctrine: Dictionary = FLOWER_WAR_DOCTRINES[doctrine_id] as Dictionary
	var provisioning: Dictionary = FLOWER_WAR_PROVISIONING[provisioning_id] as Dictionary
	var warriors_committed: int = int(option.get("warriors", 0))
	var enemy_warriors: int = int(option.get("enemy_warriors", warriors_committed))
	var combat_multiplier: float = float(provisioning.get("combat_multiplier", 1.0))
	var attacker_attack: float = float(warriors_committed) * float(doctrine.get("offence", 1.0)) * combat_multiplier
	var defender_defence: float = float(enemy_warriors) * float(option.get("enemy_defence", 1.0))
	var defender_casualties: int = clampi(int(round(maxf(0.0, attacker_attack - defender_defence * 0.55))), 0, enemy_warriors)
	var surviving_defenders: int = max(0, enemy_warriors - defender_casualties)
	var defender_attack: float = float(surviving_defenders) * float(option.get("enemy_offence", 1.0))
	var attacker_defence: float = float(warriors_committed) * float(doctrine.get("defence", 1.0))
	var attacker_casualties: int = clampi(int(round(maxf(0.0, defender_attack - attacker_defence * 0.55))), 0, warriors_committed)
	var net_damage: int = defender_casualties - attacker_casualties
	var result: String = flower_war_result_label(net_damage, warriors_committed, enemy_warriors)
	var captives: int = flower_war_captives(result, defender_casualties, warriors_committed, doctrine_id)
	var loot: Dictionary = flower_war_loot(result, defender_casualties, doctrine_id, float(option.get("base_loot_value", 1.2)))
	var loot_value: float = flower_war_loot_display_value(state, loot)
	var provisioning_cost: Dictionary = flower_war_provisioning_cost(warriors_committed, float(provisioning.get("supply_multiplier", 1.0)))
	var injured_not_fighting: int = 0
	if state != null and state.has_method("get_army_muster_summary"):
		injured_not_fighting = int((state.call("get_army_muster_summary") as Dictionary).get("injured_not_fighting", 0))
	var preview: Dictionary = {
		"ok": true,
		"option_id": option_id,
		"option_name": String(option.get("name", option_id.capitalize())),
		"doctrine_id": doctrine_id,
		"doctrine_name": String(doctrine.get("name", doctrine_id.capitalize())),
		"provisioning_id": provisioning_id,
		"provisioning_name": String(provisioning.get("name", provisioning_id.capitalize())),
		"warriors_committed": warriors_committed,
		"committed_warriors": warriors_committed,
		"injured_not_fighting": injured_not_fighting,
		"enemy_warriors": enemy_warriors,
		"attacker_attack": attacker_attack,
		"attacker_defence": attacker_defence,
		"defender_casualties": defender_casualties,
		"attacker_casualties": attacker_casualties,
		"attacker_losses": attacker_casualties,
		"attacker_injured": int(ceil(float(attacker_casualties) * 0.6)),
		"attacker_dead": int(floor(float(attacker_casualties) * 0.4)),
		"result": result,
		"captives": captives,
		"loot": loot,
		"loot_value": loot_value,
		"provisioning_cost": provisioning_cost,
		"prestige_pending": false
	}
	_attach_attack_prestige_fields(state, preview, result, defender_casualties, captives, loot_value)
	return preview

func get_combined_attack_preview(state: Node, option_id: String, provisioning_id: String, participants: Array, injured_not_fighting: int = 0, selected_ids: Array[String] = [], all_warbands: bool = false) -> Dictionary:
	if not FLOWER_WAR_OPTIONS.has(option_id):
		return {"ok": false, "reason": "Unknown Flower War option."}
	if not FLOWER_WAR_PROVISIONING.has(provisioning_id):
		provisioning_id = "standard"
	var option: Dictionary = FLOWER_WAR_OPTIONS[option_id] as Dictionary
	var provisioning: Dictionary = FLOWER_WAR_PROVISIONING[provisioning_id] as Dictionary
	var clean_participants: Array[Dictionary] = []
	var warriors_committed: int = 0
	var weighted_offence: float = 0.0
	var weighted_defence: float = 0.0
	var eagle_warriors: int = 0
	var coyote_warriors: int = 0
	for participant_variant: Variant in participants:
		if not (participant_variant is Dictionary):
			continue
		var participant: Dictionary = (participant_variant as Dictionary).duplicate(true)
		var ready: int = max(0, int(participant.get("ready", participant.get("committed", 0))))
		if ready <= 0:
			continue
		participant["committed"] = ready
		participant["ready"] = ready
		clean_participants.append(participant)
		warriors_committed += ready
		weighted_offence += float(participant.get("effective_offence", 0.0))
		weighted_defence += float(participant.get("effective_defence", 0.0))
		var doctrine_id: String = String(participant.get("doctrine_id", participant.get("doctrine", "unspecialised")))
		if doctrine_id == "eagle":
			eagle_warriors += ready
		elif doctrine_id == "coyote":
			coyote_warriors += ready
	if warriors_committed <= 0:
		return {"ok": false, "reason": "No ready warriors are assigned to warbands." if all_warbands else "No selected warbands have ready warriors."}
	var enemy_warriors: int = int(option.get("enemy_warriors", option.get("warriors", warriors_committed)))
	var minimum_warriors: int = int(option.get("warriors", enemy_warriors))
	var combat_multiplier: float = float(provisioning.get("combat_multiplier", 1.0))
	var attacker_attack: float = weighted_offence * combat_multiplier
	var defender_defence: float = float(enemy_warriors) * float(option.get("enemy_defence", 1.0))
	var defender_casualties: int = clampi(int(round(maxf(0.0, attacker_attack - defender_defence * 0.55))), 0, enemy_warriors)
	var surviving_defenders: int = max(0, enemy_warriors - defender_casualties)
	var defender_attack: float = float(surviving_defenders) * float(option.get("enemy_offence", 1.0))
	var attacker_defence: float = weighted_defence
	var attacker_casualties: int = clampi(int(round(maxf(0.0, defender_attack - attacker_defence * 0.55))), 0, warriors_committed)
	var net_damage: int = defender_casualties - attacker_casualties
	var result: String = flower_war_result_label(net_damage, warriors_committed, enemy_warriors)
	var captives: int = flower_war_captives_for_all_warbands(result, defender_casualties, warriors_committed, eagle_warriors)
	var loot: Dictionary = flower_war_loot_for_all_warbands(result, defender_casualties, coyote_warriors, warriors_committed, float(option.get("base_loot_value", 1.2)))
	var loot_value: float = flower_war_loot_display_value(state, loot)
	var provisioning_cost: Dictionary = flower_war_provisioning_cost(warriors_committed, float(provisioning.get("supply_multiplier", 1.0)))
	var xp_gained: int = flower_war_xp_gain(result, warriors_committed, defender_casualties, captives)
	var preview: Dictionary = {
		"ok": true,
		"event_type": "flower_war_attack",
		"selected_warbands": not all_warbands,
		"selected_warband_ids": selected_ids.duplicate(),
		"all_warbands": all_warbands,
		"warband_id": "all_warbands" if all_warbands else "selected_warbands",
		"warband_name": "All Warbands" if all_warbands else "Selected Warbands",
		"option_id": option_id,
		"option_name": String(option.get("name", option_id.capitalize())),
		"option_minimum_warriors": minimum_warriors,
		"doctrine_id": "combined",
		"doctrine_name": "Combined Warbands",
		"provisioning_id": provisioning_id,
		"provisioning_name": String(provisioning.get("name", provisioning_id.capitalize())),
		"participants": clean_participants,
		"participating_warband_count": clean_participants.size(),
		"warriors_committed": warriors_committed,
		"committed_warriors": warriors_committed,
		"injured_not_fighting": injured_not_fighting,
		"enemy_warriors": enemy_warriors,
		"attacker_attack": attacker_attack,
		"attacker_defence": attacker_defence,
		"defender_casualties": defender_casualties,
		"attacker_casualties": attacker_casualties,
		"attacker_losses": attacker_casualties,
		"attacker_injured": int(ceil(float(attacker_casualties) * 0.6)),
		"attacker_dead": int(floor(float(attacker_casualties) * 0.4)),
		"result": result,
		"captives": captives,
		"loot": loot,
		"loot_value": loot_value,
		"provisioning_cost": provisioning_cost,
		"xp_gained": xp_gained,
		"eagle_warriors": eagle_warriors,
		"coyote_warriors": coyote_warriors,
		"prestige_pending": false
	}
	_attach_attack_prestige_fields(state, preview, result, defender_casualties, captives, loot_value)
	return preview


# -----------------------------------------------------------------------------
# Attack resolution / mutation v0.43.17
# -----------------------------------------------------------------------------

func can_launch_combined_attack(state: Node, warband_ids: Array, option_id: String = "minor", provisioning_id: String = "standard", all_warbands: bool = false) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Campaign state is not connected."}
	if state.has_method("_ensure_warband_state"):
		state.call("_ensure_warband_state")
	if state.has_method("flower_war_palace_gate_passed") and not bool(state.call("flower_war_palace_gate_passed")):
		var gate_reason: String = "Flower Wars require palace authority."
		if state.has_method("flower_war_palace_gate_status_text"):
			gate_reason = String(state.call("flower_war_palace_gate_status_text"))
		return {"ok": false, "reason": gate_reason}

	var preview: Dictionary = {}
	if all_warbands:
		if state.has_method("get_flower_war_preview_with_all_warbands"):
			preview = state.call("get_flower_war_preview_with_all_warbands", option_id, provisioning_id) as Dictionary
	else:
		if state.has_method("get_flower_war_preview_with_selected_warbands"):
			preview = state.call("get_flower_war_preview_with_selected_warbands", warband_ids, option_id, provisioning_id) as Dictionary
	if not bool(preview.get("ok", false)):
		return preview

	var committed: int = int(preview.get("warriors_committed", 0))
	var minimum_warriors: int = int(preview.get("option_minimum_warriors", 0))
	if committed < minimum_warriors:
		if all_warbands:
			return {"ok": false, "reason": "This scale needs at least " + str(minimum_warriors) + " ready warriors across all warbands; only " + str(committed) + " ready."}
		return {"ok": false, "reason": "This scale needs at least " + str(minimum_warriors) + " ready warriors; selected warbands provide " + str(committed) + "."}

	if state.has_method("_can_pay_free_stock"):
		var cost_status: Dictionary = state.call("_can_pay_free_stock", preview.get("provisioning_cost", {}) as Dictionary) as Dictionary
		if not bool(cost_status.get("ok", false)):
			return cost_status

	var ready_reason: String = "Ready. All ready warbands will be committed." if all_warbands else "Ready. Selected warbands will be committed."
	return {"ok": true, "reason": ready_reason, "preview": preview}

func launch_combined_attack(state: Node, warband_ids: Array, option_id: String = "minor", provisioning_id: String = "standard", all_warbands: bool = false) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Campaign state is not connected."}
	var status: Dictionary = can_launch_combined_attack(state, warband_ids, option_id, provisioning_id, all_warbands)
	if not bool(status.get("ok", false)):
		var failed_report: Dictionary = {
			"ok": false,
			"reason": String(status.get("reason", "Flower War cannot launch.")),
			"warband_id": "all_warbands" if all_warbands else "selected_warbands"
		}
		failed_report["all_warbands"] = all_warbands
		failed_report["selected_warbands"] = not all_warbands
		state.set("last_flower_war_report", failed_report)
		_append_state_report(state, "Flower War not launched: " + String(failed_report.get("reason", "blocked")) + ".")
		if state.has_signal("state_changed"):
			state.emit_signal("state_changed")
		return failed_report.duplicate(true)

	var preview: Dictionary = status.get("preview", {}) as Dictionary
	if preview.is_empty():
		if all_warbands and state.has_method("get_flower_war_preview_with_all_warbands"):
			preview = state.call("get_flower_war_preview_with_all_warbands", option_id, provisioning_id) as Dictionary
		elif state.has_method("get_flower_war_preview_with_selected_warbands"):
			preview = state.call("get_flower_war_preview_with_selected_warbands", warband_ids, option_id, provisioning_id) as Dictionary
	if state.has_method("_pay_free_stock"):
		state.call("_pay_free_stock", preview.get("provisioning_cost", {}) as Dictionary)

	var participants: Array = preview.get("participants", []) as Array
	var committed: int = int(preview.get("warriors_committed", 0))
	var casualties: int = int(preview.get("attacker_casualties", 0))
	var captives: int = int(preview.get("captives", 0))
	var xp_total: int = int(preview.get("xp_gained", 0))
	var casualty_alloc: Dictionary = _distribute_by_weights_from_state(state, casualties, participants, "committed", true)
	var xp_alloc: Dictionary = _distribute_by_weights_from_state(state, xp_total, participants, "committed", false)
	var total_injured: int = 0
	var total_dead: int = 0
	var participant_reports: Array[Dictionary] = []
	var level_reports: Array[String] = []
	var warbands: Dictionary = _state_dictionary(state, "warbands")
	var current_veintena: int = int(state.get("current_veintena"))

	for participant_variant: Variant in participants:
		if not (participant_variant is Dictionary):
			continue
		var participant: Dictionary = participant_variant as Dictionary
		var warband_id: String = String(participant.get("id", ""))
		if not warbands.has(warband_id) or not (warbands[warband_id] is Dictionary):
			continue
		var warband: Dictionary = warbands[warband_id] as Dictionary
		var synced_before: Dictionary = warband.duplicate(true)
		if state.has_method("_sync_warband_progress"):
			synced_before = state.call("_sync_warband_progress", synced_before) as Dictionary
		var level_before: int = int(synced_before.get("level", 1))
		var committed_i: int = int(participant.get("committed", 0))
		var casualties_i: int = clampi(int(casualty_alloc.get(warband_id, 0)), 0, committed_i)
		var dead_i: int = int(floor(float(casualties_i) * 0.4))
		var injured_i: int = max(0, casualties_i - dead_i)
		var xp_i: int = max(0, int(xp_alloc.get(warband_id, 0)))
		total_injured += injured_i
		total_dead += dead_i
		warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0)) - casualties_i)
		warband["injured_warriors"] = max(0, int(warband.get("injured_warriors", 0)) + injured_i)
		warband["dead_total"] = max(0, int(warband.get("dead_total", 0)) + dead_i)
		warband["xp"] = max(0, int(warband.get("xp", 0)) + xp_i)
		var history: Array = warband.get("battle_history", []) as Array
		var history_record: Dictionary = {
			"veintena": current_veintena,
			"option_id": option_id,
			"result": String(preview.get("result", "Unknown")),
			"committed": committed_i,
			"casualties": casualties_i,
			"injured": injured_i,
			"dead": dead_i,
			"captives": captives,
			"xp_gained": xp_i
		}
		if all_warbands:
			history_record["all_warbands"] = true
		else:
			history_record["provisioning_id"] = provisioning_id
			history_record["selected_warbands"] = true
		history.append(history_record)
		warband["battle_history"] = history
		if state.has_method("_sync_warband_progress"):
			warbands[warband_id] = state.call("_sync_warband_progress", warband) as Dictionary
		else:
			warbands[warband_id] = warband
		var stored_warband: Dictionary = warbands[warband_id] as Dictionary
		var level_after: int = int(stored_warband.get("level", level_before))
		if level_after > level_before:
			level_reports.append(String(warband.get("name", "Warband")) + " reached Level " + str(level_after) + " and gained " + str(max(0, level_after - level_before)) + " skill point(s)")
		var participant_report: Dictionary = {
			"id": warband_id,
			"name": String(warband.get("name", "Warband")),
			"committed": committed_i,
			"casualties": casualties_i,
			"injured": injured_i,
			"dead": dead_i,
			"xp_gained": xp_i,
			"level_before": level_before,
			"level_after": level_after
		}
		if not all_warbands:
			participant_report["sent"] = committed_i
			participant_report["returned_ready"] = max(0, committed_i - casualties_i)
		participant_reports.append(participant_report)

	state.set("warbands", warbands)
	if total_dead > 0:
		var population: Dictionary = _state_dictionary(state, "population")
		var warrior_count: int = 0
		if state.has_method("get_warrior_count"):
			warrior_count = int(state.call("get_warrior_count"))
		else:
			warrior_count = int(population.get("yaotequihuaqueh", 0))
		population["yaotequihuaqueh"] = max(0, warrior_count - total_dead)
		state.set("population", population)
	if captives > 0:
		var estate_stockpiles: Dictionary = _state_dictionary(state, "estate_stockpiles")
		estate_stockpiles["captives"] = float(estate_stockpiles.get("captives", 0.0)) + float(captives)
		state.set("estate_stockpiles", estate_stockpiles)
	if state.has_method("add_looted_goods_bundle"):
		state.call("add_looted_goods_bundle", preview.get("loot", {}) as Dictionary)

	var report: Dictionary = preview.duplicate(true)
	report["ok"] = true
	if all_warbands:
		report["all_warbands"] = true
		report["warband_id"] = "all_warbands"
		report["warband_name"] = "All Warbands"
	else:
		report["event_type"] = "flower_war_return"
		report["selected_warbands"] = true
		report["all_warbands"] = false
		report["warband_id"] = "selected_warbands"
		report["warband_name"] = "Selected Warbands"
	report["warriors_returned"] = max(0, committed - casualties)
	report["attacker_injured"] = total_injured
	report["attacker_dead"] = total_dead
	report["participant_reports"] = participant_reports
	report["level_reports"] = level_reports
	if state.has_method("_apply_flower_war_prestige_to_report"):
		report = state.call("_apply_flower_war_prestige_to_report", report) as Dictionary
	if state.has_method("_archive_flower_war_report"):
		state.call("_archive_flower_war_report", report)
	state.set("last_flower_war_report", report)

	var line_prefix: String = "All warbands fought " if all_warbands else "Selected warbands fought "
	var line: String = line_prefix + String(preview.get("option_name", "Flower War")) + ": " + String(preview.get("result", "Unknown")) + ". Warriors committed " + str(committed) + " across " + str(participant_reports.size()) + " warbands; casualties " + str(casualties) + " (injured " + str(total_injured) + ", dead " + str(total_dead) + "). Captives gained " + str(captives) + ". XP +" + str(xp_total) + " shared by participating warbands. " + String(report.get("prestige_text", "Prestige +0")) + "."
	if not level_reports.is_empty():
		line += " " + "; ".join(level_reports) + "."
	_append_state_report(state, line)
	if state.has_signal("state_changed"):
		state.emit_signal("state_changed")
	return report.duplicate(true)

# -----------------------------------------------------------------------------
# Event hooks / participant helpers / legacy single-warband launch path
# -----------------------------------------------------------------------------

func start_attack_event(state: Node, option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> Dictionary:
	# Event-hook infrastructure only. This does not resolve a Flower War. It returns
	# a standard payload that UI, rivals, calendar, palace or religion systems can
	# use to open the attacking Flower War muster later.
	_ensure_warband_state(state)
	if state != null and state.has_method("flower_war_palace_gate_passed") and not bool(state.call("flower_war_palace_gate_passed")):
		var gate_text: String = String(state.call("flower_war_palace_gate_status_text")) if state.has_method("flower_war_palace_gate_status_text") else "Flower War palace gate blocks this attack."
		return {
			"ok": false,
			"event_type": "flower_war_attack_muster",
			"war_direction": "attack",
			"source_id": source_id,
			"context": context.duplicate(true),
			"option_id": option_id,
			"reason": gate_text,
			"message": gate_text
		}
	if not FLOWER_WAR_OPTIONS.has(option_id):
		option_id = "standard"
	var selected_ids: Array[String] = selected_warband_ids_or_all_ready(state, [])
	var preview: Dictionary = {}
	if state != null and state.has_method("get_flower_war_preview_with_selected_warbands"):
		var preview_variant: Variant = state.call("get_flower_war_preview_with_selected_warbands", selected_ids, option_id, "standard")
		if preview_variant is Dictionary:
			preview = preview_variant as Dictionary
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

func start_defence_event(state: Node, option_id: String = "standard", source_id: String = "rival", context: Dictionary = {}) -> Dictionary:
	# Event-hook infrastructure only. This does not resolve a Flower War. It returns
	# a standard payload that UI, rivals, calendar, palace or religion systems can
	# use to open the defensive Flower War strategy event later.
	_ensure_warband_state(state)
	if not FLOWER_WAR_OPTIONS.has(option_id):
		option_id = "standard"
	var preview: Dictionary = {}
	if state != null and state.has_method("get_flower_war_defence_preview"):
		var preview_variant: Variant = state.call("get_flower_war_defence_preview", option_id, "balanced")
		if preview_variant is Dictionary:
			preview = preview_variant as Dictionary
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

func get_event_hook_summary() -> Dictionary:
	return {
		"ok": true,
		"attack_hook": "start_flower_war_attack_event(option_id, source_id, context)",
		"defence_hook": "start_flower_war_defence_event(option_id, source_id, context)",
		"possible_sources": ["player", "rival", "calendar", "palace", "religion"],
		"note": "Hooks prepare event payloads only; they do not add rival AI or new combat rules."
	}

func flower_war_participant_rows_for_ids(state: Node, selected_ids: Array[String]) -> Array[Dictionary]:
	_ensure_warband_state(state)
	var participants: Array[Dictionary] = []
	var warbands: Dictionary = _state_dictionary(state, "warbands")
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
		var synced: Dictionary = _sync_warband_progress(state, warband.duplicate(true))
		warbands[warband_id] = synced
		var stats: Dictionary = _warband_combat_stats_from_warband(state, synced)
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
	_set_state_dictionary(state, "warbands", warbands)
	_mirror_warband_state(state)
	return participants

func selected_warband_ids_or_all_ready(state: Node, warband_ids: Array) -> Array[String]:
	_ensure_warband_state(state)
	var output: Array[String] = []
	var warbands: Dictionary = _state_dictionary(state, "warbands")
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

func distribute_integer_by_weights(total: int, participants: Array, weight_key: String = "committed", cap_by_weight: bool = false) -> Dictionary:
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

func get_single_warband_attack_preview(state: Node, warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state(state)
	var warbands: Dictionary = _state_dictionary(state, "warbands")
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var resolved_doctrine: String = doctrine_id
	if resolved_doctrine == "" or resolved_doctrine == "warband":
		resolved_doctrine = String(warband.get("doctrine", "unspecialised"))
	var preview: Dictionary = get_single_doctrine_attack_preview(state, option_id, resolved_doctrine, provisioning_id)
	if not bool(preview.get("ok", false)):
		return preview
	preview["warband_id"] = warband_id
	preview["warband_name"] = String(warband.get("name", "Warband"))
	preview["warband_ready"] = int(warband.get("ready_warriors", 0))
	preview["warband_injured"] = int(warband.get("injured_warriors", 0))
	preview["warband_level"] = int(_sync_warband_progress(state, warband.duplicate(true)).get("level", 1))
	preview["xp_gained"] = flower_war_xp_gain(String(preview.get("result", "Stalemate")), int(preview.get("warriors_committed", 0)), int(preview.get("defender_casualties", 0)), int(preview.get("captives", 0)))
	return preview

func can_launch_single_warband_attack(state: Node, warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state(state)
	if state != null and state.has_method("flower_war_palace_gate_passed") and not bool(state.call("flower_war_palace_gate_passed")):
		var gate_text: String = String(state.call("flower_war_palace_gate_status_text")) if state.has_method("flower_war_palace_gate_status_text") else "Flower War palace gate blocks this attack."
		return {"ok": false, "reason": gate_text}
	var warbands: Dictionary = _state_dictionary(state, "warbands")
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	var preview: Dictionary = get_single_warband_attack_preview(state, warband_id, option_id, doctrine_id, provisioning_id)
	if not bool(preview.get("ok", false)):
		return preview
	var needed_warriors: int = int(preview.get("warriors_committed", 0))
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var ready: int = int(warband.get("ready_warriors", 0))
	if ready < needed_warriors:
		return {"ok": false, "reason": String(warband.get("name", "Warband")) + " needs " + str(needed_warriors) + " ready warriors; only " + str(ready) + " ready."}
	var cost_status: Dictionary = {"ok": true, "reason": "Ready."}
	if state != null and state.has_method("_can_pay_free_stock"):
		var cost_variant: Variant = state.call("_can_pay_free_stock", preview.get("provisioning_cost", {}) as Dictionary)
		if cost_variant is Dictionary:
			cost_status = cost_variant as Dictionary
	if not bool(cost_status.get("ok", false)):
		return cost_status
	return {"ok": true, "reason": "Ready.", "preview": preview}

func launch_single_warband_attack(state: Node, warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	var status: Dictionary = can_launch_single_warband_attack(state, warband_id, option_id, doctrine_id, provisioning_id)
	if not bool(status.get("ok", false)):
		var blocked_report: Dictionary = {"ok": false, "reason": String(status.get("reason", "Flower War cannot launch.")), "warband_id": warband_id}
		_set_state_dictionary(state, "last_flower_war_report", blocked_report)
		_append_state_report(state, "Flower War not launched: " + String(blocked_report.get("reason", "blocked")) + ".")
		_emit_state_changed(state)
		return blocked_report.duplicate(true)
	var preview: Dictionary = status.get("preview", {}) as Dictionary
	if preview.is_empty():
		preview = get_single_warband_attack_preview(state, warband_id, option_id, doctrine_id, provisioning_id)
	if state != null and state.has_method("_pay_free_stock"):
		state.call("_pay_free_stock", preview.get("provisioning_cost", {}) as Dictionary)
	var warbands: Dictionary = _state_dictionary(state, "warbands")
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var level_before: int = int(_sync_warband_progress(state, warband.duplicate(true)).get("level", 1))
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
		"veintena": _current_veintena(state),
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
	warbands[warband_id] = _sync_warband_progress(state, warband)
	var level_after: int = int((warbands[warband_id] as Dictionary).get("level", level_before))
	_set_state_dictionary(state, "warbands", warbands)
	_mirror_warband_state(state)

	if dead > 0:
		var population: Dictionary = _state_dictionary(state, "population")
		var warrior_count: int = int(state.call("get_warrior_count")) if state != null and state.has_method("get_warrior_count") else int(population.get("yaotequihuaqueh", 0))
		population["yaotequihuaqueh"] = max(0, warrior_count - dead)
		_set_state_dictionary(state, "population", population)
	if captives > 0 and state != null and state.has_method("_add_stock"):
		state.call("_add_stock", "captives", float(captives))
	if state != null and state.has_method("add_looted_goods_bundle"):
		state.call("add_looted_goods_bundle", preview.get("loot", {}) as Dictionary)

	var final_report: Dictionary = preview.duplicate(true)
	final_report["ok"] = true
	final_report["warband_id"] = warband_id
	final_report["warband_name"] = String(warband.get("name", "Warband"))
	final_report["warriors_returned"] = max(0, committed - casualties)
	final_report["xp_gained"] = xp_gain
	final_report["level_before"] = level_before
	final_report["level_after"] = level_after
	if state != null and state.has_method("_apply_flower_war_prestige_to_report"):
		var prestige_variant: Variant = state.call("_apply_flower_war_prestige_to_report", final_report)
		if prestige_variant is Dictionary:
			final_report = prestige_variant as Dictionary
	_set_state_dictionary(state, "last_flower_war_report", final_report)
	_mirror_warband_state(state)

	var line: String = String(warband.get("name", "Warband")) + " fought " + String(preview.get("option_name", "Flower War")) + ": " + String(preview.get("result", "Unknown")) + ". Warriors committed " + str(committed) + "; casualties " + str(casualties) + " (injured " + str(injured) + ", dead " + str(dead) + "). Captives gained " + str(captives) + ". XP +" + str(xp_gain) + ". " + String(final_report.get("prestige_text", "Prestige +0")) + "."
	if level_after > level_before:
		line += " " + String(warband.get("name", "Warband")) + " reached Level " + str(level_after) + " and gained " + str(max(0, level_after - level_before)) + " skill point(s)."
	_append_state_report(state, line)
	_emit_state_changed(state)
	return final_report.duplicate(true)

func _ensure_warband_state(state: Node) -> void:
	if state != null and state.has_method("_ensure_warband_state"):
		state.call("_ensure_warband_state")

func _sync_warband_progress(state: Node, warband: Dictionary) -> Dictionary:
	if state != null and state.has_method("_sync_warband_progress"):
		var result: Variant = state.call("_sync_warband_progress", warband)
		if result is Dictionary:
			return result as Dictionary
	return warband.duplicate(true)

func _warband_combat_stats_from_warband(state: Node, warband: Dictionary) -> Dictionary:
	if state != null and state.has_method("_warband_combat_stats_from_warband"):
		var result: Variant = state.call("_warband_combat_stats_from_warband", warband)
		if result is Dictionary:
			return result as Dictionary
	return _fallback_warband_combat_stats(warband)

func _set_state_dictionary(state: Node, property_name: String, value: Dictionary) -> void:
	if state != null:
		state.set(property_name, value.duplicate(true))

func _mirror_warband_state(state: Node) -> void:
	if state != null and state.has_method("_mirror_warband_flower_war_compatibility_from_campaign_state"):
		# Capture first when available so CampaignState sees any mutation made through the legacy dictionary.
		if state.has_method("_ensure_campaign_state_warband_flower_war_bridge"):
			state.call("_ensure_campaign_state_warband_flower_war_bridge")
		state.call("_mirror_warband_flower_war_compatibility_from_campaign_state")

func _current_veintena(state: Node) -> int:
	if state != null and state.has_method("get_current_veintena"):
		return int(state.call("get_current_veintena"))
	if state != null:
		return int(state.get("current_veintena"))
	return 1

func _state_dictionary(state: Node, property_name: String) -> Dictionary:
	if state == null:
		return {}
	var value: Variant = state.get(property_name)
	if value is Dictionary:
		return value as Dictionary
	return {}

func _append_state_report(state: Node, line: String) -> void:
	if state == null:
		return
	var report_variant: Variant = state.get("last_report")
	if report_variant is Array:
		var report: Array = report_variant as Array
		report.append(line)
		state.set("last_report", report)

func _distribute_by_weights_from_state(state: Node, total: int, rows: Array, weight_key: String, cap_to_weight: bool) -> Dictionary:
	if state != null and state.has_method("_distribute_integer_by_weights"):
		return state.call("_distribute_integer_by_weights", total, rows, weight_key, cap_to_weight) as Dictionary
	var output: Dictionary = {}
	if total <= 0 or rows.is_empty():
		return output
	var total_weight: float = 0.0
	for row_variant: Variant in rows:
		if row_variant is Dictionary:
			total_weight += maxf(0.0, float((row_variant as Dictionary).get(weight_key, 0.0)))
	if total_weight <= 0.0:
		return output
	var remaining: int = total
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		var id_value: String = String(row.get("id", ""))
		var weight: float = maxf(0.0, float(row.get(weight_key, 0.0)))
		var amount: int = int(round(float(total) * weight / total_weight))
		if cap_to_weight:
			amount = mini(amount, int(weight))
		amount = mini(amount, remaining)
		output[id_value] = max(0, amount)
		remaining -= max(0, amount)
	return output


# -----------------------------------------------------------------------------
# Defence resolution / mutation v0.43.18
# -----------------------------------------------------------------------------

func can_resolve_defence(state: Node, option_id: String = "standard", strategy_id: String = "balanced") -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Campaign state is not connected."}
	if state.has_method("_ensure_warband_state"):
		state.call("_ensure_warband_state")
	var preview: Dictionary = get_defence_preview(state, option_id, strategy_id)
	if not bool(preview.get("ok", false)):
		return preview
	var committed: int = int(preview.get("warriors_committed", 0))
	var minimum_warriors: int = int(preview.get("option_minimum_warriors", 0))
	if committed < minimum_warriors:
		return {"ok": false, "reason": "This defence needs at least " + str(minimum_warriors) + " ready warriors; defending warbands provide " + str(committed) + "."}
	return {"ok": true, "reason": "Ready. Warbands will defend the estate.", "preview": preview}

func resolve_defence(state: Node, option_id: String = "standard", strategy_id: String = "balanced") -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Campaign state is not connected.", "war_direction": "defence"}
	var status: Dictionary = can_resolve_defence(state, option_id, strategy_id)
	if not bool(status.get("ok", false)):
		var failed_report: Dictionary = {
			"ok": false,
			"reason": String(status.get("reason", "Flower War defence cannot resolve.")),
			"war_direction": "defence"
		}
		state.set("last_flower_war_report", failed_report)
		_append_state_report(state, "Flower War defence not resolved: " + String(failed_report.get("reason", "blocked")) + ".")
		if state.has_signal("state_changed"):
			state.emit_signal("state_changed")
		return failed_report.duplicate(true)

	var preview: Dictionary = status.get("preview", {}) as Dictionary
	if preview.is_empty():
		preview = get_defence_preview(state, option_id, strategy_id)
	var participants: Array = preview.get("participants", []) as Array
	var committed: int = int(preview.get("warriors_committed", 0))
	var casualties: int = int(preview.get("defender_casualties", preview.get("attacker_casualties", 0)))
	var xp_total: int = int(preview.get("xp_gained", 0))
	var casualty_alloc: Dictionary = _distribute_by_weights_from_state(state, casualties, participants, "committed", true)
	var xp_alloc: Dictionary = _distribute_by_weights_from_state(state, xp_total, participants, "committed", false)
	var total_injured: int = 0
	var total_dead: int = 0
	var participant_reports: Array[Dictionary] = []
	var level_reports: Array[String] = []
	var warbands: Dictionary = _state_dictionary(state, "warbands")
	var current_veintena: int = int(state.get("current_veintena"))

	for participant_variant: Variant in participants:
		if not (participant_variant is Dictionary):
			continue
		var participant: Dictionary = participant_variant as Dictionary
		var warband_id: String = String(participant.get("id", ""))
		if not warbands.has(warband_id) or not (warbands[warband_id] is Dictionary):
			continue
		var warband: Dictionary = warbands[warband_id] as Dictionary
		var synced_before: Dictionary = warband.duplicate(true)
		if state.has_method("_sync_warband_progress"):
			synced_before = state.call("_sync_warband_progress", synced_before) as Dictionary
		var level_before: int = int(synced_before.get("level", 1))
		var committed_i: int = int(participant.get("committed", 0))
		var casualties_i: int = clampi(int(casualty_alloc.get(warband_id, 0)), 0, committed_i)
		var dead_i: int = int(floor(float(casualties_i) * 0.4))
		var injured_i: int = max(0, casualties_i - dead_i)
		var xp_i: int = max(0, int(xp_alloc.get(warband_id, 0)))
		total_injured += injured_i
		total_dead += dead_i
		warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0)) - casualties_i)
		warband["injured_warriors"] = max(0, int(warband.get("injured_warriors", 0)) + injured_i)
		warband["dead_total"] = max(0, int(warband.get("dead_total", 0)) + dead_i)
		warband["xp"] = max(0, int(warband.get("xp", 0)) + xp_i)
		var history: Array = warband.get("battle_history", []) as Array
		history.append({
			"veintena": current_veintena,
			"option_id": option_id,
			"strategy_id": strategy_id,
			"result": String(preview.get("result", "Unknown")),
			"committed": committed_i,
			"casualties": casualties_i,
			"injured": injured_i,
			"dead": dead_i,
			"captives": 0,
			"xp_gained": xp_i,
			"defensive": true
		})
		warband["battle_history"] = history
		if state.has_method("_sync_warband_progress"):
			warbands[warband_id] = state.call("_sync_warband_progress", warband) as Dictionary
		else:
			warbands[warband_id] = warband
		var stored_warband: Dictionary = warbands[warband_id] as Dictionary
		var level_after: int = int(stored_warband.get("level", level_before))
		if level_after > level_before:
			level_reports.append(String(warband.get("name", "Warband")) + " reached Level " + str(level_after) + " and gained " + str(max(0, level_after - level_before)) + " skill point(s)")
		participant_reports.append({
			"id": warband_id,
			"name": String(warband.get("name", "Warband")),
			"committed": committed_i,
			"sent": committed_i,
			"returned_ready": max(0, committed_i - casualties_i),
			"casualties": casualties_i,
			"injured": injured_i,
			"dead": dead_i,
			"xp_gained": xp_i,
			"level_before": level_before,
			"level_after": level_after
		})

	state.set("warbands", warbands)
	if total_dead > 0:
		var population: Dictionary = _state_dictionary(state, "population")
		var warrior_count: int = 0
		if state.has_method("get_warrior_count"):
			warrior_count = int(state.call("get_warrior_count"))
		else:
			warrior_count = int(population.get("yaotequihuaqueh", 0))
		population["yaotequihuaqueh"] = max(0, warrior_count - total_dead)
		state.set("population", population)

	var report: Dictionary = preview.duplicate(true)
	report["ok"] = true
	report["event_type"] = "flower_war_return"
	report["war_direction"] = "defence"
	report["warband_id"] = "defending_warbands"
	report["warband_name"] = "Defending Warbands"
	report["warriors_returned"] = max(0, committed - casualties)
	report["attacker_injured"] = total_injured
	report["attacker_dead"] = total_dead
	report["participant_reports"] = participant_reports
	report["level_reports"] = level_reports
	if state.has_method("_apply_flower_war_prestige_to_report"):
		report = state.call("_apply_flower_war_prestige_to_report", report) as Dictionary
	if state.has_method("_archive_flower_war_report"):
		state.call("_archive_flower_war_report", report)
	state.set("last_flower_war_report", report)

	var line: String = "Defending warbands resolved " + String(preview.get("option_name", "Flower War")) + " using " + String(preview.get("defence_strategy_name", "Balanced Defence")) + ": " + String(preview.get("result", "Unknown")) + ". Warriors defending " + str(committed) + " across " + str(participant_reports.size()) + " warbands; casualties " + str(casualties) + " (injured " + str(total_injured) + ", dead " + str(total_dead) + "). Enemy casualties " + str(int(preview.get("enemy_casualties", 0))) + ". XP +" + str(xp_total) + " shared by defending warbands. " + String(report.get("prestige_text", "Prestige +0")) + "."
	if not level_reports.is_empty():
		line += " " + "; ".join(level_reports) + "."
	_append_state_report(state, line)
	if state.has_signal("state_changed"):
		state.emit_signal("state_changed")
	return report.duplicate(true)


# -----------------------------------------------------------------------------
# Defence preview construction v0.43.16
# -----------------------------------------------------------------------------

func get_defence_preview(state: Node, option_id: String = "standard", strategy_id: String = "balanced") -> Dictionary:
	if not FLOWER_WAR_OPTIONS.has(option_id):
		return {"ok": false, "reason": "Unknown Flower War option."}
	var option: Dictionary = FLOWER_WAR_OPTIONS[option_id] as Dictionary
	var strategy: Dictionary = flower_war_defence_strategy_data(strategy_id)
	var warbands: Dictionary = {}
	if state != null:
		var warbands_variant: Variant = state.get("warbands")
		if warbands_variant is Dictionary:
			warbands = warbands_variant as Dictionary
	var participants: Array[Dictionary] = []
	var warriors_committed: int = 0
	var weighted_offence: float = 0.0
	var weighted_defence: float = 0.0
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		if not (warbands[warband_id] is Dictionary):
			continue
		var warband: Dictionary = (warbands[warband_id] as Dictionary).duplicate(true)
		if state != null and state.has_method("_sync_warband_progress"):
			warband = state.call("_sync_warband_progress", warband) as Dictionary
		warbands[warband_id] = warband
		var stats: Dictionary = {}
		if state != null and state.has_method("_warband_combat_stats_from_warband"):
			stats = state.call("_warband_combat_stats_from_warband", warband) as Dictionary
		else:
			stats = _fallback_warband_combat_stats(warband)
		var ready: int = int(stats.get("ready", 0))
		if ready <= 0:
			continue
		participants.append({
			"id": warband_id,
			"name": String(warband.get("name", "Warband")),
			"committed": ready,
			"ready": ready,
			"doctrine": String(warband.get("doctrine", "unspecialised")),
			"doctrine_name": String(stats.get("doctrine_name", "Unspecialised")),
			"effective_offence": float(stats.get("effective_offence", 0.0)),
			"effective_defence": float(stats.get("effective_defence", 0.0))
		})
		warriors_committed += ready
		weighted_offence += float(stats.get("effective_offence", 0.0))
		weighted_defence += float(stats.get("effective_defence", 0.0))
	if state != null:
		state.set("warbands", warbands)
	if warriors_committed <= 0:
		return {"ok": false, "reason": "No ready warbands can defend."}
	var enemy_warriors: int = int(option.get("enemy_warriors", option.get("warriors", 0)))
	var player_attack: float = weighted_offence * float(strategy.get("offence_multiplier", 1.0))
	var player_defence: float = weighted_defence * float(strategy.get("defence_multiplier", 1.0))
	var enemy_attack: float = float(enemy_warriors) * float(option.get("enemy_offence", 1.0))
	var enemy_defence: float = float(enemy_warriors) * float(option.get("enemy_defence", 1.0))
	var enemy_casualties: int = clampi(int(round(maxf(0.0, player_attack - enemy_defence * 0.55))), 0, enemy_warriors)
	var surviving_enemy: int = max(0, enemy_warriors - enemy_casualties)
	var returning_enemy_attack: float = float(surviving_enemy) * float(option.get("enemy_offence", 1.0))
	var defender_casualties: int = clampi(int(round(maxf(0.0, returning_enemy_attack - player_defence * 0.55))), 0, warriors_committed)
	var net_damage: int = enemy_casualties - defender_casualties
	var result: String = flower_war_result_label(net_damage, warriors_committed, enemy_warriors)
	var xp_gained: int = flower_war_xp_gain(result, warriors_committed, enemy_casualties, 0)
	var prestige_breakdown: Dictionary = _defence_prestige_breakdown(state, result, enemy_casualties)
	return {
		"ok": true,
		"event_type": "flower_war_defence_preview",
		"war_direction": "defence",
		"option_id": option_id,
		"option_name": String(option.get("name", option_id.capitalize())),
		"option_minimum_warriors": int(option.get("warriors", 0)),
		"defence_strategy_id": String(strategy.get("id", "balanced")),
		"defence_strategy_name": String(strategy.get("name", "Balanced Defence")),
		"defence_strategy_description": String(strategy.get("description", "")),
		"offence_multiplier": float(strategy.get("offence_multiplier", 1.0)),
		"defence_multiplier": float(strategy.get("defence_multiplier", 1.0)),
		"participants": participants,
		"participating_warband_count": participants.size(),
		"warriors_committed": warriors_committed,
		"committed_warriors": warriors_committed,
		"enemy_warriors": enemy_warriors,
		"attacker_attack": enemy_attack,
		"attacker_defence": enemy_defence,
		"defender_attack": player_attack,
		"defender_defence": player_defence,
		"enemy_casualties": enemy_casualties,
		"defender_casualties": defender_casualties,
		"attacker_casualties": defender_casualties,
		"attacker_losses": defender_casualties,
		"attacker_injured": int(ceil(float(defender_casualties) * 0.6)),
		"attacker_dead": int(floor(float(defender_casualties) * 0.4)),
		"result": result,
		"captives": 0,
		"loot": {},
		"loot_value": 0.0,
		"provisioning_cost": {},
		"xp_gained": xp_gained,
		"prestige_pending": false,
		"prestige_breakdown": prestige_breakdown,
		"prestige_gain": float(prestige_breakdown.get("total", 0.0)),
		"prestige_text": _prestige_text_from_breakdown(prestige_breakdown)
	}

func _defence_prestige_breakdown(state: Node, result: String, enemy_casualties: int) -> Dictionary:
	if state != null and state.has_method("get_flower_war_prestige_preview"):
		return state.call("get_flower_war_prestige_preview", {
			"war_direction": "defence",
			"result": result,
			"enemy_casualties": enemy_casualties
		}) as Dictionary
	return {}

func _fallback_warband_combat_stats(warband: Dictionary) -> Dictionary:
	var ready: int = max(0, int(warband.get("ready_warriors", 0)))
	var doctrine_id: String = String(warband.get("doctrine", "unspecialised"))
	if not FLOWER_WAR_DOCTRINES.has(doctrine_id):
		doctrine_id = "unspecialised"
	var doctrine: Dictionary = FLOWER_WAR_DOCTRINES[doctrine_id] as Dictionary
	return {
		"ready": ready,
		"doctrine_name": String(doctrine.get("name", doctrine_id.capitalize())),
		"effective_offence": float(ready) * float(doctrine.get("offence", 1.0)),
		"effective_defence": float(ready) * float(doctrine.get("defence", 1.0))
	}

func _attach_attack_prestige_fields(state: Node, preview: Dictionary, result: String, defender_casualties: int, captives: int, loot_value: float) -> void:
	var breakdown: Dictionary = {}
	if state != null and state.has_method("get_flower_war_prestige_preview"):
		breakdown = state.call("get_flower_war_prestige_preview", {
			"war_direction": "attack",
			"result": result,
			"defender_casualties": defender_casualties,
			"captives": captives,
			"loot_value": loot_value
		}) as Dictionary
	preview["prestige_breakdown"] = breakdown
	preview["prestige_gain"] = float(breakdown.get("total", 0.0))
	preview["prestige_text"] = _prestige_text_from_breakdown(breakdown)

func _prestige_text_from_breakdown(breakdown: Dictionary) -> String:
	var amount: float = float(breakdown.get("total", 0.0))
	var prefix: String = "+" if amount >= 0.0 else ""
	return "Prestige " + prefix + _fmt(amount)

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))


func _emit_state_changed(state: Node) -> void:
	if state != null and state.has_signal("state_changed"):
		state.emit_signal("state_changed")
