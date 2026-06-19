# WarbandSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/WarbandSystem.gd
#
# Extracted warband roster / skill-web public API slice.
# TRGameState remains the live state owner during the architecture split.
class_name WarbandSystem
extends RefCounted

const VALID_DOCTRINE_IDS: Array[String] = ["unspecialised", "eagle", "jaguar", "otomi", "coyote"]

func recover_injured_warriors_now(state: Node) -> Dictionary:
	# Test/dev helper. Normal recovery happens automatically when the Veintena advances.
	_ensure_warbands(state)
	var report: Dictionary = recover_injured_warriors(state)
	_emit_state_changed(state)
	return report

func recover_injured_warriors(state: Node) -> Dictionary:
	_ensure_warbands(state)
	var warbands: Dictionary = _warbands(state)
	var recovered_total: int = 0
	var lines: Array[String] = []
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var warband: Dictionary = warbands[warband_id] as Dictionary
		var injured: int = max(0, int(warband.get("injured_warriors", 0)))
		if injured <= 0:
			continue
		warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0))) + injured
		warband["injured_warriors"] = 0
		warbands[warband_id] = _sync_progress(state, warband)
		recovered_total += injured
		var name: String = String(warband.get("name", "Warband"))
		lines.append(str(injured) + " injured warrior" + ("s" if injured != 1 else "") + " returned to " + name + ".")
	if recovered_total > 0:
		_append_report(state, "Warband recovery: " + " ".join(lines))
	_set_warbands(state, warbands)
	return {"recovered": recovered_total, "lines": lines}

func get_warband_rows(state: Node) -> Array[Dictionary]:
	_ensure_warbands(state)
	var warbands: Dictionary = _warbands(state)
	var rows: Array[Dictionary] = []
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var row: Dictionary = _sync_progress(state, (warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = row
		var spec: Dictionary = row.get("specialisation", {}) as Dictionary
		var combat_stats: Dictionary = _combat_stats_from_warband(state, row)
		row["specialisation_name"] = String(spec.get("name", "None"))
		row["doctrine_name"] = String(combat_stats.get("doctrine_name", _doctrine_name(state, String(row.get("doctrine", "unspecialised")))))
		row["combat_stats"] = combat_stats
		row["offence_modifier"] = float(combat_stats.get("offence_modifier", 1.0))
		row["defence_modifier"] = float(combat_stats.get("defence_modifier", 1.0))
		row["effective_offence"] = float(combat_stats.get("effective_offence", 0.0))
		row["effective_defence"] = float(combat_stats.get("effective_defence", 0.0))
		row["ready"] = int(row.get("ready_warriors", 0))
		row["injured"] = int(row.get("injured_warriors", 0))
		row["total"] = int(row.get("ready_warriors", 0)) + int(row.get("injured_warriors", 0))
		row["warriors"] = int(row.get("ready_warriors", 0))
		row["total_warriors"] = int(row.get("total", 0))
		row["can_launch"] = int(row.get("ready_warriors", 0)) > 0
		row["injured_recovery_text"] = "Injured warriors recover on the next Veintena advance." if int(row.get("injured_warriors", 0)) > 0 else "No injured warriors awaiting recovery."
		rows.append(row)
	_set_warbands(state, warbands)
	return rows

func get_warband_by_id(state: Node, warband_id: String) -> Dictionary:
	_ensure_warbands(state)
	var warbands: Dictionary = _warbands(state)
	if warbands.has(warband_id):
		var row: Dictionary = _sync_progress(state, (warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = row
		var spec: Dictionary = row.get("specialisation", {}) as Dictionary
		var combat_stats: Dictionary = _combat_stats_from_warband(state, row)
		row["specialisation_name"] = String(spec.get("name", "None"))
		row["doctrine_name"] = String(combat_stats.get("doctrine_name", _doctrine_name(state, String(row.get("doctrine", "unspecialised")))))
		row["combat_stats"] = combat_stats
		row["offence_modifier"] = float(combat_stats.get("offence_modifier", 1.0))
		row["defence_modifier"] = float(combat_stats.get("defence_modifier", 1.0))
		row["effective_offence"] = float(combat_stats.get("effective_offence", 0.0))
		row["effective_defence"] = float(combat_stats.get("effective_defence", 0.0))
		_set_warbands(state, warbands)
		return row
	return {}

func can_rename_warband(state: Node, warband_id: String, new_name: String) -> Dictionary:
	_ensure_warbands(state)
	var warbands: Dictionary = _warbands(state)
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	var cleaned: String = new_name.strip_edges()
	if cleaned == "":
		return {"ok": false, "reason": "Warband name cannot be empty."}
	if cleaned.length() > 32:
		return {"ok": false, "reason": "Warband name must be 32 characters or fewer."}
	for other_id_variant: Variant in warbands.keys():
		var other_id: String = String(other_id_variant)
		if other_id == warband_id:
			continue
		var other: Dictionary = warbands[other_id] as Dictionary
		if String(other.get("name", "")).strip_edges().to_lower() == cleaned.to_lower():
			return {"ok": false, "reason": "Another warband already uses that name."}
	return {"ok": true, "reason": "Ready.", "clean_name": cleaned}

func rename_warband(state: Node, warband_id: String, new_name: String) -> Dictionary:
	var status: Dictionary = can_rename_warband(state, warband_id, new_name)
	if not bool(status.get("ok", false)):
		_append_report(state, "Warband rename failed: " + String(status.get("reason", "Unknown reason.")))
		_emit_state_changed(state)
		return status
	var warbands: Dictionary = _warbands(state)
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var old_name: String = String(warband.get("name", "Warband"))
	var clean_name: String = String(status.get("clean_name", new_name.strip_edges()))
	warband["name"] = clean_name
	warbands[warband_id] = _sync_progress(state, warband)
	_set_warbands(state, warbands)
	_append_report(state, old_name + " renamed to " + clean_name + ".")
	_emit_state_changed(state)
	return {"ok": true, "reason": "Warband renamed.", "warband_id": warband_id, "name": clean_name}

func can_set_warband_name(state: Node, warband_id: String, new_name: String) -> Dictionary:
	return can_rename_warband(state, warband_id, new_name)

func set_warband_name(state: Node, warband_id: String, new_name: String) -> Dictionary:
	return rename_warband(state, warband_id, new_name)

func get_primary_warband(state: Node) -> Dictionary:
	return get_warband_by_id(state, "first_warband")

func get_unassigned_warrior_pool(state: Node) -> int:
	return _unassigned_pool(state)

func can_create_warband(state: Node, name: String = "New Warband", warriors: int = 0, doctrine_id: String = "unspecialised", commander: String = "Household Captain") -> Dictionary:
	_ensure_warbands(state)
	if warriors < 0:
		return {"ok": false, "reason": "Warrior count cannot be negative."}
	if not VALID_DOCTRINE_IDS.has(doctrine_id):
		return {"ok": false, "reason": "Unknown doctrine."}
	var available: int = _unassigned_pool(state)
	if warriors > available:
		return {"ok": false, "reason": "Need " + str(warriors) + " unassigned warriors; only " + str(available) + " available."}
	return {"ok": true, "reason": "Ready."}

func create_warband(state: Node, name: String = "New Warband", warriors: int = 0, doctrine_id: String = "unspecialised", commander: String = "Household Captain") -> Dictionary:
	var status: Dictionary = can_create_warband(state, name, warriors, doctrine_id, commander)
	if not bool(status.get("ok", false)):
		return status
	var warbands: Dictionary = _warbands(state)
	var base_id: String = name.strip_edges().to_lower().replace(" ", "_")
	if base_id == "":
		base_id = "warband"
	var warband_id: String = base_id
	var suffix: int = 2
	while warbands.has(warband_id):
		warband_id = base_id + "_" + str(suffix)
		suffix += 1
	var created_warband: Dictionary = state.call("_make_starting_warband", warband_id, name, commander, warriors) as Dictionary
	created_warband["doctrine"] = doctrine_id
	warbands[warband_id] = created_warband
	_set_warbands(state, warbands)
	_emit_state_changed(state)
	return {"ok": true, "reason": "Created warband.", "warband_id": warband_id}

func can_reinforce_warband(state: Node, warband_id: String, amount: int) -> Dictionary:
	return can_assign_warriors_to_warband(state, warband_id, amount)

func reinforce_warband(state: Node, warband_id: String, amount: int) -> Dictionary:
	return assign_warriors_to_warband(state, warband_id, amount)

func can_assign_warriors_to_warband(state: Node, warband_id: String, amount: int) -> Dictionary:
	_ensure_warbands(state)
	var warbands: Dictionary = _warbands(state)
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	if amount <= 0:
		return {"ok": false, "reason": "Choose at least 1 warrior."}
	var available: int = _unassigned_pool(state)
	if amount > available:
		return {"ok": false, "reason": "Need " + str(amount) + " unassigned warriors; only " + str(available) + " available."}
	return {"ok": true, "reason": "Ready."}

func assign_warriors_to_warband(state: Node, warband_id: String, amount: int) -> Dictionary:
	var status: Dictionary = can_assign_warriors_to_warband(state, warband_id, amount)
	if not bool(status.get("ok", false)):
		return status
	var warbands: Dictionary = _warbands(state)
	var warband: Dictionary = warbands[warband_id] as Dictionary
	warband["ready_warriors"] = int(warband.get("ready_warriors", 0)) + amount
	warbands[warband_id] = _sync_progress(state, warband)
	_set_warbands(state, warbands)
	_emit_state_changed(state)
	return {"ok": true, "reason": "Assigned " + str(amount) + " warriors to " + String(warband.get("name", "warband")) + "."}

func can_unassign_warriors_from_warband(state: Node, warband_id: String, amount: int) -> Dictionary:
	_ensure_warbands(state)
	var warbands: Dictionary = _warbands(state)
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	if amount <= 0:
		return {"ok": false, "reason": "Choose at least 1 warrior."}
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var ready: int = int(warband.get("ready_warriors", 0))
	if amount > ready:
		return {"ok": false, "reason": "Only " + str(ready) + " ready warriors can be unassigned."}
	return {"ok": true, "reason": "Ready."}

func unassign_warriors_from_warband(state: Node, warband_id: String, amount: int) -> Dictionary:
	var status: Dictionary = can_unassign_warriors_from_warband(state, warband_id, amount)
	if not bool(status.get("ok", false)):
		return status
	var warbands: Dictionary = _warbands(state)
	var warband: Dictionary = warbands[warband_id] as Dictionary
	warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0)) - amount)
	warbands[warband_id] = _sync_progress(state, warband)
	_set_warbands(state, warbands)
	_emit_state_changed(state)
	return {"ok": true, "reason": "Unassigned " + str(amount) + " warriors from " + String(warband.get("name", "warband")) + "."}

func can_specialise_warband(state: Node, warband_id: String, doctrine_id: String) -> Dictionary:
	# Deprecated compatibility hook. Doctrine is no longer chosen through a
	# separate oath/action; it is derived from the Skill Web specialism gateway.
	_ensure_warbands(state)
	if not _warbands(state).has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	return {"ok": false, "reason": "Choose doctrine by purchasing a Skill Web specialism gateway."}

func specialise_warband(state: Node, warband_id: String, doctrine_id: String) -> Dictionary:
	return can_specialise_warband(state, warband_id, doctrine_id)

func get_warband_skill_web(state: Node, warband_id: String = "") -> Dictionary:
	_ensure_warbands(state)
	var target_id: String = warband_id
	if target_id == "":
		target_id = "first_warband"
	var warband: Dictionary = get_warband_by_id(state, target_id)
	var purchased: Array[String] = _purchased_trait_ids(state, warband)
	var nodes: Array[Dictionary] = []
	for node: Dictionary in _skill_node_definitions(state):
		var row: Dictionary = node.duplicate(true)
		var trait_id: String = String(row.get("id", ""))
		var bought: bool = purchased.has(trait_id)
		var locked_by_specialisation: bool = bool(state.call("_warband_trait_locked_by_specialisation", purchased, row))
		var requirements_met: bool = bool(state.call("_warband_trait_requirements_met", purchased, row))
		row["purchased"] = bought
		row["available"] = (not bought) and (not locked_by_specialisation) and requirements_met and int(warband.get("trait_points", 0)) >= int(row.get("cost", 1))
		row["locked"] = (not bought) and (locked_by_specialisation or not requirements_met)
		row["lock_reason"] = ""
		if locked_by_specialisation:
			row["lock_reason"] = String(state.call("_warband_specialisation_lock_text", purchased))
		elif not requirements_met:
			row["lock_reason"] = "Requires " + String(state.call("_warband_requirements_text", row)) + "."
		nodes.append(row)
	return {
		"warband_id": target_id,
		"warband": warband,
		"nodes": nodes,
		"connections": _skill_connections(state),
		"trait_points": int(warband.get("trait_points", 0)),
		"purchased_traits": purchased,
		"specialisation": warband.get("specialisation", {}) as Dictionary,
		"skill_effects": warband.get("skill_effects", {}) as Dictionary,
		"specialisation_note": "Each warband may choose one major specialism branch. Buying one specialism gateway locks the other specialism gateways for that warband."
	}

func get_warband_trait_tree(state: Node, warband_id: String) -> Dictionary:
	return get_warband_skill_web(state, warband_id)

func get_warband_trait_points(state: Node, warband_id: String) -> int:
	return int(get_warband_by_id(state, warband_id).get("trait_points", 0))

func get_warband_purchased_traits(state: Node, warband_id: String) -> Array[String]:
	var warband: Dictionary = get_warband_by_id(state, warband_id)
	return _purchased_trait_ids(state, warband)

func get_warband_available_traits(state: Node, warband_id: String) -> Array[Dictionary]:
	var web: Dictionary = get_warband_skill_web(state, warband_id)
	var output: Array[Dictionary] = []
	for node_variant: Variant in web.get("nodes", []) as Array:
		var node: Dictionary = node_variant as Dictionary
		if bool(node.get("available", false)):
			output.append(node)
	return output

func get_warband_locked_traits(state: Node, warband_id: String) -> Array[Dictionary]:
	var web: Dictionary = get_warband_skill_web(state, warband_id)
	var output: Array[Dictionary] = []
	for node_variant: Variant in web.get("nodes", []) as Array:
		var node: Dictionary = node_variant as Dictionary
		if bool(node.get("locked", false)):
			output.append(node)
	return output

func can_purchase_warband_trait(state: Node, warband_id: String, trait_id: String) -> Dictionary:
	_ensure_warbands(state)
	var warbands: Dictionary = _warbands(state)
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	var warband: Dictionary = _sync_progress(state, (warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	_set_warbands(state, warbands)
	var node: Dictionary = _skill_node_by_id(state, trait_id)
	if node.is_empty():
		return {"ok": false, "reason": "Unknown trait."}
	var purchased: Array[String] = _purchased_trait_ids(state, warband)
	if purchased.has(trait_id):
		return {"ok": false, "reason": "Already purchased."}
	if bool(state.call("_warband_trait_locked_by_specialisation", purchased, node)):
		return {"ok": false, "reason": String(state.call("_warband_specialisation_lock_text", purchased))}
	if not bool(state.call("_warband_trait_requirements_met", purchased, node)):
		return {"ok": false, "reason": "Requires " + String(state.call("_warband_requirements_text", node)) + "."}
	var cost: int = max(0, int(node.get("cost", 1)))
	if int(warband.get("trait_points", 0)) < cost:
		return {"ok": false, "reason": "Need " + str(cost) + " trait point" + ("s" if cost != 1 else "") + "."}
	return {"ok": true, "reason": "Ready.", "cost": cost}

func purchase_warband_trait(state: Node, warband_id: String, trait_id: String) -> Dictionary:
	var status: Dictionary = can_purchase_warband_trait(state, warband_id, trait_id)
	if not bool(status.get("ok", false)):
		return status
	var warbands: Dictionary = _warbands(state)
	var warband: Dictionary = warbands[warband_id] as Dictionary
	warband = state.call("_ensure_warband_skill_defaults", warband) as Dictionary
	var purchased: Array[String] = _purchased_trait_ids(state, warband)
	purchased.append(trait_id)
	warband["purchased_traits"] = purchased
	warband["traits"] = purchased.duplicate()
	warbands[warband_id] = _sync_progress(state, warband)
	_set_warbands(state, warbands)
	var node: Dictionary = _skill_node_by_id(state, trait_id)
	_append_report(state, String(warband.get("name", "Warband")) + " purchased trait: " + String(node.get("name", trait_id)) + ".")
	_emit_state_changed(state)
	return {"ok": true, "reason": "Trait purchased.", "warband_id": warband_id, "trait_id": trait_id}

func get_warband_trait_effect_totals(state: Node, warband_id: String) -> Dictionary:
	var warband: Dictionary = get_warband_by_id(state, warband_id)
	if warband.is_empty():
		return {}
	return (warband.get("skill_effects", {}) as Dictionary).duplicate(true)

func get_warband_specialisation_summary(state: Node, warband_id: String) -> Dictionary:
	var warband: Dictionary = get_warband_by_id(state, warband_id)
	if warband.is_empty():
		return {}
	return (warband.get("specialisation", {}) as Dictionary).duplicate(true)

func get_warband_flower_war_stability_audit(state: Node) -> Dictionary:
	# Non-mechanical audit helper for testing the current canonical warband rules.
	_ensure_warbands(state)
	var warbands: Dictionary = _warbands(state)
	var issues: Array[String] = []
	var rows: Array[Dictionary] = []
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var row: Dictionary = _sync_progress(state, (warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = row
		var spec: Dictionary = row.get("specialisation", {}) as Dictionary
		var doctrine_id: String = String(row.get("doctrine", "unspecialised"))
		var expected_doctrine: String = String(spec.get("doctrine_id", "unspecialised"))
		if doctrine_id != expected_doctrine:
			issues.append(String(row.get("name", warband_id)) + " doctrine mismatch: " + doctrine_id + " vs " + expected_doctrine)
		rows.append({
			"id": warband_id,
			"name": String(row.get("name", "Warband")),
			"doctrine": doctrine_id,
			"specialism": String(spec.get("name", "None")),
			"ready": int(row.get("ready_warriors", 0)),
			"injured": int(row.get("injured_warriors", 0)),
			"dead_total_report_only": int(row.get("dead_total", 0))
		})
	_set_warbands(state, warbands)
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"warbands": rows,
		"specialism_sets_doctrine": true,
		"other_specialisms_lock": true,
		"dead_normal_cards": false,
		"skill_node_effects_connected": false,
		"event_hooks_ready": true
	}

# -----------------------------------------------------------------------------
# State/proxy helpers
# -----------------------------------------------------------------------------

func _warbands(state: Node) -> Dictionary:
	var value: Variant = state.get("warbands")
	if value is Dictionary:
		return value as Dictionary
	return {}

func _set_warbands(state: Node, warbands: Dictionary) -> void:
	state.set("warbands", warbands)

func _ensure_warbands(state: Node) -> void:
	if state != null and state.has_method("_ensure_warband_state"):
		state.call("_ensure_warband_state")

func _sync_progress(state: Node, warband: Dictionary) -> Dictionary:
	if state != null and state.has_method("_sync_warband_progress"):
		return state.call("_sync_warband_progress", warband) as Dictionary
	return warband

func _combat_stats_from_warband(state: Node, warband: Dictionary) -> Dictionary:
	if state != null and state.has_method("_warband_combat_stats_from_warband"):
		return state.call("_warband_combat_stats_from_warband", warband) as Dictionary
	return {}

func _doctrine_name(state: Node, doctrine_id: String) -> String:
	if state != null and state.has_method("_warband_doctrine_name"):
		return String(state.call("_warband_doctrine_name", doctrine_id))
	return doctrine_id.capitalize()

func _unassigned_pool(state: Node) -> int:
	if state != null and state.has_method("_unassigned_warrior_pool"):
		return int(state.call("_unassigned_warrior_pool"))
	return 0

func _purchased_trait_ids(state: Node, warband: Dictionary) -> Array[String]:
	if state != null and state.has_method("_warband_purchased_trait_ids"):
		return state.call("_warband_purchased_trait_ids", warband) as Array[String]
	return []

func _skill_node_definitions(state: Node) -> Array[Dictionary]:
	if state != null and state.has_method("_warband_skill_node_definitions"):
		return state.call("_warband_skill_node_definitions") as Array[Dictionary]
	return []

func _skill_connections(state: Node) -> Array[Dictionary]:
	if state != null and state.has_method("_warband_skill_connections"):
		return state.call("_warband_skill_connections") as Array[Dictionary]
	return []

func _skill_node_by_id(state: Node, trait_id: String) -> Dictionary:
	if state != null and state.has_method("_warband_skill_node_by_id"):
		return state.call("_warband_skill_node_by_id", trait_id) as Dictionary
	return {}

func _append_report(state: Node, line: String) -> void:
	var report_variant: Variant = state.get("last_report")
	if report_variant is Array:
		var report: Array = report_variant as Array
		report.append(line)
		state.set("last_report", report)

func _emit_state_changed(state: Node) -> void:
	if state != null and state.has_signal("state_changed"):
		state.emit_signal("state_changed")
