# WarbandSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/WarbandSystem.gd
#
# Owns warband roster, recovery, warrior assignment and skill-web rules.
# Reads/writes CampaignState first through TRGameState accessors, with
# TRGameState field fallback kept only for compatibility.
class_name WarbandSystem
extends RefCounted

const WAR_DOCTRINE_RULES_SCRIPT: Script = preload("res://Scripts/Systems/WarDoctrineRules.gd")

const FLOWER_WAR_PROVISIONING: Dictionary = {
	"standard": {"name": "Standard", "supply_multiplier": 1.0, "combat_multiplier": 1.0},
	"well": {"name": "Well Provisioned", "supply_multiplier": 2.0, "combat_multiplier": 1.1},
	"royal": {"name": "Royal Provision", "supply_multiplier": 4.0, "combat_multiplier": 1.2}
}

const FLOWER_WAR_DEFENCE_STRATEGIES: Dictionary = {
	"balanced": {"name": "Balanced Defence", "offence_multiplier": 1.0, "defence_multiplier": 1.0, "description": "A steady response with no bonus or penalty."},
	"depth": {"name": "Defence in Depth", "offence_multiplier": 0.85, "defence_multiplier": 1.25, "description": "Protect the warbands and absorb the attack. More defence, less offence."},
	"good_offence": {"name": "The Best Defence is a Good Offence", "offence_multiplier": 1.25, "defence_multiplier": 0.85, "description": "Counterattack hard. More offence, less defence."}
}

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
	if not WAR_DOCTRINE_RULES_SCRIPT.has_doctrine(doctrine_id):
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
	var created_warband: Dictionary = make_starting_warband(warband_id, name, commander, warriors)
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
	var nodes: Array[Dictionary] = _skill_node_definitions(state)
	var connections: Array[Dictionary] = _skill_connections(state)
	var target_id: String = _readable_warband_id(state, warband_id)
	var warband: Dictionary = get_warband_by_id(state, target_id)
	if warband.is_empty():
		# Preserve the old TRGameState contract: the UI gets an explicit ok=false
		# result with readable node/connection data instead of an empty dictionary.
		return {
			"ok": false,
			"reason": "Unknown warband.",
			"warband_id": target_id,
			"nodes": nodes,
			"traits": nodes,
			"connections": connections,
			"statuses": {},
			"description": "Warband Skill Web backend data. UI drawing comes later."
		}

	var purchased: Array[String] = _purchased_trait_ids(state, warband)
	var trait_points: int = int(warband.get("trait_points", 0))
	var node_rows: Array[Dictionary] = []
	var statuses: Dictionary = {}
	var available_traits: Array[Dictionary] = []
	var locked_traits: Array[Dictionary] = []

	for node: Dictionary in nodes:
		var row: Dictionary = node.duplicate(true)
		var trait_id: String = String(row.get("id", ""))
		var bought: bool = purchased.has(trait_id)
		var locked_by_specialisation: bool = bool(state.call("_warband_trait_locked_by_specialisation", purchased, row))
		var requirements_met: bool = bool(state.call("_warband_trait_requirements_met", purchased, row))
		var enough_points: bool = trait_points >= int(row.get("cost", 1))
		var lock_reason: String = ""
		if locked_by_specialisation:
			lock_reason = String(state.call("_warband_specialisation_lock_text", purchased))
		elif not requirements_met:
			lock_reason = "Requires " + String(state.call("_warband_requirements_text", row)) + "."
		elif not enough_points and not bought:
			lock_reason = "Need " + str(int(row.get("cost", 1))) + " trait point(s)."

		var can_purchase: bool = (not bought) and (not locked_by_specialisation) and requirements_met and enough_points
		var locked: bool = (not bought) and (locked_by_specialisation or not requirements_met or not enough_points)
		row["purchased"] = bought
		row["available"] = can_purchase
		row["locked"] = locked
		row["lock_reason"] = lock_reason
		node_rows.append(row)

		statuses[trait_id] = {
			"purchased": bought,
			"requirements_met": requirements_met,
			"can_purchase": can_purchase,
			"reason": "Ready." if can_purchase else lock_reason,
			"cost": int(row.get("cost", 1)),
			"cluster": String(row.get("cluster", "general"))
		}
		if can_purchase:
			available_traits.append(row.duplicate(true))
		elif locked:
			locked_traits.append(row.duplicate(true))

	return {
		"ok": true,
		"reason": "Ready.",
		"warband_id": target_id,
		"warband": warband,
		"combat_stats": _combat_stats_from_warband(state, warband),
		"nodes": node_rows,
		"traits": node_rows,
		"connections": connections,
		"statuses": statuses,
		"trait_points": trait_points,
		"points_available": trait_points,
		"points_total": int(warband.get("total_trait_points", 0)),
		"points_spent": int(warband.get("spent_trait_points", 0)),
		"purchased_traits": purchased,
		"available_traits": available_traits,
		"locked_traits": locked_traits,
		"effect_totals": get_warband_trait_effect_totals(state, target_id),
		"specialisation": get_warband_specialisation_summary(state, target_id),
		"skill_effects": warband.get("skill_effects", {}) as Dictionary,
		"description": "Warband Skill Web backend data. UI drawing comes later.",
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
# Warband skill-web static data
# -----------------------------------------------------------------------------

func warband_skill_connections() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for node: Dictionary in warband_skill_node_definitions():
		var to_id: String = String(node.get("id", ""))
		var requirements: Array = node.get("requires", []) as Array
		for req_variant: Variant in requirements:
			output.append({"from": String(req_variant), "to": to_id, "type": "required"})
		var any_requirements: Array = node.get("requires_any", []) as Array
		for req_variant: Variant in any_requirements:
			output.append({"from": String(req_variant), "to": to_id, "type": "any"})
	return output

func warband_skill_node_by_id(trait_id: String) -> Dictionary:
	for node: Dictionary in warband_skill_node_definitions():
		if String(node.get("id", "")) == trait_id:
			return node.duplicate(true)
	return {}

func warband_skill_node_definitions() -> Array[Dictionary]:
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


# -----------------------------------------------------------------------------
# Warband backend helpers extracted from TRGameState v0.45.8
# -----------------------------------------------------------------------------

func ensure_warband_state(state: Node) -> void:
	if state == null:
		return
	var current: Dictionary = _warbands(state)
	if not current.is_empty():
		return
	var total_warriors: int = 0
	if state.has_method("get_warrior_count"):
		total_warriors = int(state.call("get_warrior_count"))
	var first: int = int(ceil(float(total_warriors) / 3.0))
	var second: int = int(floor(float(total_warriors) / 3.0))
	var third: int = max(0, total_warriors - first - second)
	current["first_warband"] = make_starting_warband("first_warband", "First Warband", "Household Captain", first)
	current["second_warband"] = make_starting_warband("second_warband", "Second Warband", "Senior Warrior", second)
	current["third_warband"] = make_starting_warband("third_warband", "Third Warband", "Young Captain", third)
	_set_warbands(state, current)

func get_barracks_summary(state: Node) -> Dictionary:
	ensure_warband_state(state)
	var warriors: int = 0
	var capacity: int = 0
	if state != null and state.has_method("get_warrior_count"):
		warriors = int(state.call("get_warrior_count"))
	if state != null and state.has_method("get_warrior_capacity"):
		capacity = int(state.call("get_warrior_capacity"))
	var weapons: float = 0.0
	var captives: int = 0
	if state != null and state.has_method("free_stock_after_reserves"):
		weapons = float(state.call("free_stock_after_reserves", "weapons"))
	if state != null and state.has_method("_stock"):
		captives = int(state.call("_stock", "captives"))
	return {
		"warriors": warriors,
		"capacity": capacity,
		"free_capacity": max(0, capacity - warriors),
		"unassigned_warriors": unassigned_warrior_pool(state),
		"status": "Ready" if warriors > 0 else "No warriors available",
		"weapons": weapons,
		"captives": captives,
		"palace_dedicated_god": String(state.call("get_player_palace_dedicated_god")) if state != null and state.has_method("get_player_palace_dedicated_god") else "",
		"has_war_god_palace": bool(state.call("has_war_god_palace")) if state != null and state.has_method("has_war_god_palace") else false,
		"flower_war_palace_gate_enabled": bool(state.call("is_flower_war_palace_gate_enabled")) if state != null and state.has_method("is_flower_war_palace_gate_enabled") else false,
		"flower_war_palace_gate_passed": bool(state.call("flower_war_palace_gate_passed")) if state != null and state.has_method("flower_war_palace_gate_passed") else false,
		"doctrines": WAR_DOCTRINE_RULES_SCRIPT.all_doctrines(),
		"provisioning": FLOWER_WAR_PROVISIONING.duplicate(true),
		"defence_strategies": FLOWER_WAR_DEFENCE_STRATEGIES.duplicate(true),
		"army_muster": get_army_muster_summary(state)
	}

func get_warband_combat_stats(state: Node, warband_id: String) -> Dictionary:
	ensure_warband_state(state)
	var warbands: Dictionary = _warbands(state)
	if not warbands.has(warband_id):
		return {}
	var warband: Dictionary = sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	_set_warbands(state, warbands)
	return warband_combat_stats_from_warband(warband)

func get_army_muster_summary(state: Node) -> Dictionary:
	ensure_warband_state(state)
	var warbands: Dictionary = _warbands(state)
	var rows: Array[Dictionary] = []
	var total_ready: int = 0
	var total_injured: int = 0
	var total_dead: int = 0
	var total_offence: float = 0.0
	var total_defence: float = 0.0
	var active_warbands: int = 0
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var warband: Dictionary = sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = warband
		var stats: Dictionary = warband_combat_stats_from_warband(warband)
		rows.append(stats)
		total_ready += int(stats.get("ready", 0))
		total_injured += int(stats.get("injured", 0))
		total_dead += int(stats.get("dead_total", 0))
		total_offence += float(stats.get("effective_offence", 0.0))
		total_defence += float(stats.get("effective_defence", 0.0))
		if int(stats.get("ready", 0)) > 0:
			active_warbands += 1
	_set_warbands(state, warbands)
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

func make_starting_warband(warband_id: String, name: String, commander: String, ready_warriors: int) -> Dictionary:
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

func sync_warband_progress(warband: Dictionary) -> Dictionary:
	var xp: int = max(0, int(warband.get("xp", 0)))
	var level: int = warband_level_for_xp(xp)
	warband["xp"] = xp
	warband["level"] = level
	warband["xp_to_next"] = warband_xp_to_next(level)
	warband["xp_current_level_start"] = warband_xp_required_for_level(level)
	warband["xp_next_level"] = warband_xp_required_for_level(level + 1)
	warband["xp_in_level"] = xp - int(warband.get("xp_current_level_start", 0))
	warband["xp_needed_in_level"] = max(1, int(warband.get("xp_next_level", 0)) - int(warband.get("xp_current_level_start", 0)))
	warband["xp_progress"] = clampf(float(warband.get("xp_in_level", 0)) / float(warband.get("xp_needed_in_level", 1)), 0.0, 1.0)
	warband = ensure_warband_skill_defaults(warband)
	warband["total_trait_points"] = max(0, level - 1)
	warband["spent_trait_points"] = warband_spent_trait_points(warband)
	warband["trait_points"] = max(0, int(warband.get("total_trait_points", 0)) - int(warband.get("spent_trait_points", 0)))
	warband["skill_effects"] = warband_trait_effect_totals_from_purchased(warband_purchased_trait_ids(warband))
	warband["specialisation"] = warband_specialisation_summary_for_warband(warband)
	warband["doctrine"] = warband_doctrine_from_specialisation(warband)
	return warband

func warband_xp_required_for_level(level: int) -> int:
	var target: int = max(1, level)
	return (target - 1) * target * 5

func warband_xp_to_next(level: int) -> int:
	return warband_xp_required_for_level(max(1, level) + 1)

func warband_level_for_xp(xp: int) -> int:
	var level: int = 1
	while xp >= warband_xp_required_for_level(level + 1):
		level += 1
	return level

func warband_spent_trait_points(warband: Dictionary) -> int:
	var purchased: Array[String] = warband_purchased_trait_ids(warband)
	var spent: int = 0
	for trait_id: String in purchased:
		var node: Dictionary = warband_skill_node_by_id(trait_id)
		spent += max(0, int(node.get("cost", 0)))
	return spent

func warband_doctrine_from_specialisation(warband: Dictionary) -> String:
	var purchased: Array[String] = warband_purchased_trait_ids(warband)
	var chosen_cluster: String = warband_chosen_specialisation_cluster(purchased)
	if WAR_DOCTRINE_RULES_SCRIPT.has_doctrine(chosen_cluster):
		return chosen_cluster
	return "unspecialised"

func warband_doctrine_data(doctrine_id: String) -> Dictionary:
	var cleaned: String = doctrine_id
	if not WAR_DOCTRINE_RULES_SCRIPT.has_doctrine(cleaned):
		cleaned = "unspecialised"
	return WAR_DOCTRINE_RULES_SCRIPT.doctrine_data(cleaned) as Dictionary

func warband_combat_stats_from_warband(warband: Dictionary) -> Dictionary:
	var doctrine_id: String = String(warband.get("doctrine", "unspecialised"))
	var doctrine: Dictionary = warband_doctrine_data(doctrine_id)
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

func ensure_warband_skill_defaults(warband: Dictionary) -> Dictionary:
	var purchased: Array[String] = warband_purchased_trait_ids(warband)
	if not purchased.has("household_muster"):
		purchased.insert(0, "household_muster")
	warband["purchased_traits"] = purchased
	warband["traits"] = purchased.duplicate()
	return warband

func warband_purchased_trait_ids(warband: Dictionary) -> Array[String]:
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
		if warband_skill_node_by_id(trait_id).is_empty():
			continue
		output.append(trait_id)
	if output.is_empty():
		output.append("household_muster")
	elif not output.has("household_muster"):
		output.insert(0, "household_muster")
	return output

func warband_trait_effect_totals_from_purchased(purchased: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for trait_id: String in purchased:
		var node: Dictionary = warband_skill_node_by_id(trait_id)
		var effects: Dictionary = node.get("effects", {}) as Dictionary
		for effect_variant: Variant in effects.keys():
			var effect_id: String = String(effect_variant)
			result[effect_id] = float(result.get(effect_id, 0.0)) + float(effects[effect_variant])
	return result

func warband_specialisation_summary_for_warband(warband: Dictionary) -> Dictionary:
	var purchased: Array[String] = warband_purchased_trait_ids(warband)
	var point_clusters: Dictionary = {"eagle": 0, "jaguar": 0, "otomi": 0, "coyote": 0, "veteran": 0, "supply": 0, "core": 0}
	var keystones: Array[String] = warband_purchased_specialisation_clusters(purchased)
	for trait_id: String in purchased:
		var node: Dictionary = warband_skill_node_by_id(trait_id)
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
		name = warband_cluster_display_name(primary) + " Specialist"
		if keystones.size() > 1:
			name += " (legacy mixed)"
			style = "legacy_mixed"
	elif primary != "" and primary_points > 0:
		name = warband_cluster_display_name(primary) + "-leaning"
		style = "leaning"
	var doctrine_id: String = primary if locked and WAR_DOCTRINE_RULES_SCRIPT.has_doctrine(primary) else "unspecialised"
	return {
		"name": name,
		"style": style,
		"primary": primary,
		"primary_name": warband_cluster_display_name(primary),
		"secondary": "",
		"secondary_name": "None",
		"keystones": keystones,
		"locked_specialism": locked,
		"specialism_locked": locked,
		"doctrine_id": doctrine_id,
		"doctrine_name": warband_doctrine_name(doctrine_id),
		"sets_combat_doctrine": locked,
		"points_by_cluster": point_clusters,
		"effect_totals": warband_trait_effect_totals_from_purchased(purchased)
	}

func warband_cluster_display_name(cluster_id: String) -> String:
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

func warband_chosen_specialisation_cluster(purchased: Array[String]) -> String:
	for trait_id: String in purchased:
		var node: Dictionary = warband_skill_node_by_id(trait_id)
		if bool(node.get("specialisation", false)):
			return String(node.get("cluster", ""))
	return ""

func warband_purchased_specialisation_clusters(purchased: Array[String]) -> Array[String]:
	var output: Array[String] = []
	for trait_id: String in purchased:
		var node: Dictionary = warband_skill_node_by_id(trait_id)
		if bool(node.get("specialisation", false)):
			var cluster_id: String = String(node.get("cluster", ""))
			if cluster_id != "" and not output.has(cluster_id):
				output.append(cluster_id)
	return output

func warband_trait_locked_by_specialisation(purchased: Array[String], node: Dictionary) -> bool:
	if not bool(node.get("specialisation", false)):
		return false
	var chosen_cluster: String = warband_chosen_specialisation_cluster(purchased)
	if chosen_cluster == "":
		return false
	return String(node.get("cluster", "")) != chosen_cluster

func warband_specialisation_lock_text(purchased: Array[String]) -> String:
	var chosen_cluster: String = warband_chosen_specialisation_cluster(purchased)
	if chosen_cluster == "":
		return ""
	return "Locked by " + warband_cluster_display_name(chosen_cluster) + " specialism. A warband can only choose one specialism."

func warband_trait_requirements_met(purchased: Array[String], node: Dictionary) -> bool:
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

func warband_requirements_text(node: Dictionary) -> String:
	var requirements: Array = node.get("requires", []) as Array
	var any_requirements: Array = node.get("requires_any", []) as Array
	var names: Array[String] = []
	for req_variant: Variant in requirements:
		var req_id: String = String(req_variant)
		var req_node: Dictionary = warband_skill_node_by_id(req_id)
		if req_node.is_empty():
			names.append(req_id)
		else:
			names.append(String(req_node.get("name", req_id)))
	var any_names: Array[String] = []
	for req_variant: Variant in any_requirements:
		var req_id: String = String(req_variant)
		var req_node: Dictionary = warband_skill_node_by_id(req_id)
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

func unassigned_warrior_pool(state: Node) -> int:
	ensure_warband_state(state)
	var assigned: int = 0
	for warband_variant: Variant in _warbands(state).values():
		var warband: Dictionary = warband_variant as Dictionary
		assigned += int(warband.get("ready_warriors", 0))
		assigned += int(warband.get("injured_warriors", 0))
	var total: int = 0
	if state != null and state.has_method("get_warrior_count"):
		total = int(state.call("get_warrior_count"))
	return max(0, total - assigned)

func warband_doctrine_name(doctrine_id: String) -> String:
	var data: Dictionary = warband_doctrine_data(doctrine_id)
	return String(data.get("name", doctrine_id.capitalize()))

# -----------------------------------------------------------------------------
# State/proxy helpers
# -----------------------------------------------------------------------------

func _campaign_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null

func _warbands(state: Node) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_warbands_copy"):
		return runtime_state.call("get_warbands_copy") as Dictionary
	if state != null:
		var value: Variant = state.get("warbands")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}

func _set_warbands(state: Node, warbands: Dictionary) -> void:
	if state == null:
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("set_warbands_values"):
		runtime_state.call("set_warbands_values", warbands)
		if state.has_method("_mirror_warband_flower_war_compatibility_from_campaign_state"):
			state.call("_mirror_warband_flower_war_compatibility_from_campaign_state")
		return
	state.set("warbands", warbands)

func _ensure_warbands(state: Node) -> void:
	ensure_warband_state(state)
	_campaign_state(state)

func _matching_warband_id(state: Node, requested_id: String) -> String:
	var requested: String = requested_id.strip_edges()
	var warbands: Dictionary = _warbands(state)
	if requested != "" and warbands.has(requested):
		return requested
	var requested_lower: String = requested.to_lower()
	for key_variant: Variant in warbands.keys():
		var key: String = String(key_variant)
		var warband: Dictionary = warbands[key] as Dictionary
		if requested != "" and String(warband.get("id", "")) == requested:
			return key
		if requested_lower != "" and String(warband.get("name", "")).strip_edges().to_lower() == requested_lower:
			return key
	return ""

func _readable_warband_id(state: Node, requested_id: String = "") -> String:
	var matched: String = _matching_warband_id(state, requested_id)
	if matched != "":
		return matched
	var warbands: Dictionary = _warbands(state)
	if warbands.has("first_warband"):
		return "first_warband"
	for key_variant: Variant in warbands.keys():
		return String(key_variant)
	return requested_id

func _sync_progress(state: Node, warband: Dictionary) -> Dictionary:
	return sync_warband_progress(warband)

func _combat_stats_from_warband(state: Node, warband: Dictionary) -> Dictionary:
	return warband_combat_stats_from_warband(warband)

func _doctrine_name(state: Node, doctrine_id: String) -> String:
	return warband_doctrine_name(doctrine_id)

func _unassigned_pool(state: Node) -> int:
	return unassigned_warrior_pool(state)

func _purchased_trait_ids(state: Node, warband: Dictionary) -> Array[String]:
	return warband_purchased_trait_ids(warband)

func _skill_node_definitions(state: Node) -> Array[Dictionary]:
	return warband_skill_node_definitions()

func _skill_connections(state: Node) -> Array[Dictionary]:
	return warband_skill_connections()

func _skill_node_by_id(state: Node, trait_id: String) -> Dictionary:
	return warband_skill_node_by_id(trait_id)

func _append_report(state: Node, line: String) -> void:
	if line.strip_edges() == "":
		return
	if state != null and state.has_method("_append_report_line"):
		state.call("_append_report_line", line)
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("append_report_line"):
		runtime_state.call("append_report_line", line)
		if state != null and state.has_method("_mirror_calendar_report_compatibility_from_campaign_state"):
			state.call("_mirror_calendar_report_compatibility_from_campaign_state")
		return
	var report_variant: Variant = state.get("last_report") if state != null else []
	if report_variant is Array:
		var report: Array = report_variant as Array
		report.append(line)
		state.set("last_report", report)

func _emit_state_changed(state: Node) -> void:
	if state != null and state.has_signal("state_changed"):
		state.emit_signal("state_changed")
