# PalaceSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/PalaceSystem.gd
#
# Owns palace dedication, palace route labels, palace structure rules,
# palace static structure-tree data, route authority presentation and court needs.
# Reads/writes CampaignState first through TRGameState accessors, with
# TRGameState field fallback kept only for compatibility.
class_name PalaceSystem
extends RefCounted

const GOD_TLALOC: String = "tlaloc"
const GOD_HUITZILOPOCHTLI: String = "huitzilopochtli"
const GOD_TEZCATLIPOCA: String = "tezcatlipoca"
const GOD_QUETZALCOATL: String = "quetzalcoatl"
const PALACE_GOD_IDS: Array[String] = [GOD_TLALOC, GOD_HUITZILOPOCHTLI, GOD_TEZCATLIPOCA, GOD_QUETZALCOATL]

func get_player_palace_dedicated_god(state: Node) -> String:
	if state == null:
		return ""
	return _palace_string(state, "player_palace_dedicated_god", "")

func set_player_palace_dedicated_god(state: Node, god_id: String) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Palace state is not connected."}
	var cleaned: String = god_id.strip_edges().to_lower()
	if cleaned == "":
		_set_palace_value(state, "player_palace_dedicated_god", "")
		if is_flower_war_palace_gate_enabled(state):
			_append_report(state, "Palace dedication cleared. Flower Wars are locked until the palace is dedicated to Huitzilopochtli.")
		else:
			_append_report(state, "Palace dedication cleared. Flower Wars remain open because the palace gate is not active yet.")
		_emit_state_changed(state)
		return {"ok": true, "reason": "Palace dedication cleared."}
	if not PALACE_GOD_IDS.has(cleaned):
		return {"ok": false, "reason": "Unknown palace god: " + god_id + "."}
	_set_palace_value(state, "player_palace_dedicated_god", cleaned)
	_append_report(state, "Palace dedicated to " + god_display_name(cleaned) + ".")
	_emit_state_changed(state)
	return {"ok": true, "reason": "Palace dedicated to " + god_display_name(cleaned) + "."}

func has_war_god_palace(state: Node) -> bool:
	# Actual dedication state only. Use flower_war_palace_gate_passed() for launch permission.
	return get_player_palace_dedicated_god(state) == GOD_HUITZILOPOCHTLI

func is_flower_war_palace_gate_enabled(state: Node) -> bool:
	if state == null:
		return false
	return _palace_bool(state, "flower_war_palace_gate_enabled", false)

func set_flower_war_palace_gate_enabled(state: Node, enabled: bool) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Palace state is not connected."}
	_set_palace_value(state, "flower_war_palace_gate_enabled", enabled)
	if enabled:
		_append_report(state, "Flower War palace gate enabled. Flower Wars now require a Huitzilopochtli-dedicated palace.")
	else:
		_append_report(state, "Flower War palace gate disabled. Flower Wars are open until the Palace system is implemented.")
	_emit_state_changed(state)
	return {"ok": true, "enabled": enabled}

func flower_war_palace_gate_passed(state: Node) -> bool:
	# Attacking Flower Wars require the Palace to be dedicated to Huitzilopochtli
	# when the gate is enabled. Defensive Flower Wars do not call this gate.
	if not is_flower_war_palace_gate_enabled(state):
		return true
	return has_war_god_palace(state)

func flower_war_palace_gate_status_text(state: Node) -> String:
	if not is_flower_war_palace_gate_enabled(state):
		return "Palace gate inactive: attacking Flower Wars are open for testing."
	if has_war_god_palace(state):
		return "Huitzilopochtli Palace authority active: attacking Flower Wars are authorised."
	var dedicated_god: String = get_player_palace_dedicated_god(state)
	if dedicated_god == "":
		return "Attacking Flower Wars locked: dedicate the Palace to Huitzilopochtli to authorise the war route. Defensive Flower Wars can still occur."
	return "Attacking Flower Wars locked: current palace dedication is " + god_display_name(dedicated_god) + "; Huitzilopochtli is required. Defensive Flower Wars can still occur."

func god_display_name(god_id: String) -> String:
	match god_id:
		GOD_TLALOC:
			return "Tlaloc"
		GOD_HUITZILOPOCHTLI:
			return "Huitzilopochtli"
		GOD_TEZCATLIPOCA:
			return "Tezcatlipoca"
		GOD_QUETZALCOATL:
			return "Quetzalcoatl"
	return god_id.capitalize()

func get_palace_dedicated_god(state: Node) -> String:
	return get_player_palace_dedicated_god(state)

func get_palace_route_name(god_id: String) -> String:
	match god_id:
		GOD_TLALOC:
			return "Natural Calendar Foresight"
		GOD_HUITZILOPOCHTLI:
			return "Flower Wars Authority"
		GOD_TEZCATLIPOCA:
			return "Scarcity and Intrigue"
		GOD_QUETZALCOATL:
			return "Legitimacy and Recognition"
	return "No Palace Route"

func get_palace_route_power_summary(god_id: String) -> String:
	match god_id:
		GOD_TLALOC:
			return "Deep calendar and natural-event foresight: higher palace levels will reveal droughts, floods, harvest pressure and other natural events earlier and in more detail."
		GOD_HUITZILOPOCHTLI:
			return "Flower Wars authority: dedicating the Palace to Huitzilopochtli formally authorises attacking Flower Wars and the war route."
		GOD_TEZCATLIPOCA:
			return "Scarcity, intrigue and market pressure: future structures will support rival pressure, disruption, manipulation, sabotage hooks and market leverage."
		GOD_QUETZALCOATL:
			return "Legitimacy, recognition and palace trust: future structures will strengthen ruler-facing credibility, order, tribute reliability and prestige-style authority."
	return "No palace dedication has been chosen. Dedication will define the house's palace route."

func can_dedicate_palace_to_god(state: Node, god_id: String) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Palace state is not connected."}
	var cleaned: String = god_id.strip_edges().to_lower()
	if cleaned == "":
		return {"ok": false, "reason": "Choose a palace god."}
	if not PALACE_GOD_IDS.has(cleaned):
		return {"ok": false, "reason": "Unknown palace god: " + god_id + "."}
	var current_god: String = get_palace_dedicated_god(state)
	if current_god != "":
		return {"ok": false, "reason": "The palace is already dedicated to " + god_display_name(current_god) + ". Prototype 0 dedication is permanent."}
	return {"ok": true, "reason": "Ready to dedicate the palace to " + god_display_name(cleaned) + "."}

func dedicate_palace_to_god(state: Node, god_id: String) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Palace state is not connected."}
	var status: Dictionary = can_dedicate_palace_to_god(state, god_id)
	if not bool(status.get("ok", false)):
		_append_report(state, "Palace dedication failed: " + String(status.get("reason", "")))
		_emit_state_changed(state)
		return status
	var cleaned: String = god_id.strip_edges().to_lower()
	_set_palace_value(state, "player_palace_dedicated_god", cleaned)
	_append_report(state, "Palace dedicated to " + god_display_name(cleaned) + ". The Divine Seat now displays the " + get_palace_route_name(cleaned) + " structure node data.")
	_emit_state_changed(state)
	return {"ok": true, "reason": "Palace dedicated to " + god_display_name(cleaned) + ".", "god_id": cleaned}

func get_palace_level(state: Node) -> int:
	if state == null:
		return 1
	var dedicated_god: String = get_palace_dedicated_god(state)
	if dedicated_god == "":
		return 1
	var highest: int = 1
	if not state.has_method("get_built_palace_structure_ids") or not state.has_method("_palace_structure_by_id"):
		return highest
	var built_ids_variant: Variant = state.call("get_built_palace_structure_ids")
	if not (built_ids_variant is Array):
		return highest
	var built_ids: Array = built_ids_variant as Array
	for structure_variant: Variant in built_ids:
		var structure_id: String = String(structure_variant)
		var structure_variant_data: Variant = state.call("_palace_structure_by_id", structure_id, dedicated_god)
		if not (structure_variant_data is Dictionary):
			continue
		var structure: Dictionary = structure_variant_data as Dictionary
		if structure.is_empty():
			continue
		highest = maxi(highest, int(structure.get("tier", 1)))
	return highest

func get_palace_dedication_routes(state: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var current_god: String = get_palace_dedicated_god(state)
	for god_id: String in PALACE_GOD_IDS:
		var dedication_status: Dictionary = can_dedicate_palace_to_god(state, god_id)
		rows.append({
			"id": god_id,
			"god_id": god_id,
			"god_name": god_display_name(god_id),
			"route_name": get_palace_route_name(god_id),
			"power_summary": get_palace_route_power_summary(god_id),
			"is_chosen": god_id == current_god,
			"is_available_for_future_dedication": current_god == "",
			"can_dedicate": bool(dedication_status.get("ok", false)),
			"dedication_status": String(dedication_status.get("reason", "")),
			"prototype_status": "Dedication UI active. Palace structures can be built and must be maintained/staffed to stay active. Huitzilopochtli authorises attacking Flower Wars; Tlaloc, Tezcatlipoca and Quetzalcoatl authority panels are information-only prototypes."
		})
	return rows



# -----------------------------------------------------------------------------
# Palace structure tree static data
# -----------------------------------------------------------------------------

func palace_structure_node(
	state: Node,
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
	var prerequisite_text: String = "None"
	if not prerequisites.is_empty():
		prerequisite_text = ", ".join(prerequisites)
	var built: bool = is_palace_structure_built(state, id)
	var status_text: String = "Not built"
	if built:
		status_text = "Built — operation check pending"
	return {
		"id": id,
		"name": name,
		"god_id": god_id,
		"route": get_palace_route_name(god_id),
		"tier": tier,
		"level": tier,
		"description": description,
		"summary": effect_summary,
		"build_cost": build_cost,
		"maintenance_cost": maintenance_cost,
		"staff_requirement": staff_requirement,
		"prerequisites": prerequisites,
		"prerequisite_text": prerequisite_text,
		"effect_summary": effect_summary,
		"status": status_text,
		"built": built,
		"active": false,
		"inactive_reason": "Not built.",
		"prototype_note": "Construction, maintenance payment and staff checks are implemented. Authority effects are not active yet."
	}


func palace_structure_tree_tiers(state: Node, god_id: String) -> Array[Dictionary]:
	match god_id:
		"tlaloc":
			return [
				{"tier": 1, "title": "Level 1 — Household Water Court", "structures": [
					palace_structure_node(state, "tlaloc_rain_reading_basin", god_id, 1, "Rain-Reading Basin", "A polished basin set in the palace court for reading rain, reflected sky, canal levels and field signs.", {"wood": 18.0, "cloth": 4.0, "ritual_goods": 1.0}, {"cacao": 0.5, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Reveals basic nearby natural pressure once the Tlaloc authority system is active."),
					palace_structure_node(state, "tlaloc_canal_listening_court", god_id, 1, "Canal Listening Court", "A quiet court where priests and estate nobles listen for canal, flood and lake warnings.", {"wood": 22.0, "cloth": 5.0, "ritual_goods": 1.0}, {"cacao": 0.5, "cloth": 0.5}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Future hook for canal, flood and water-management warnings."),
					palace_structure_node(state, "tlaloc_field_omen_chamber", god_id, 1, "Field Omen Chamber", "A chamber for crop samples, pest signs and soil offerings brought in from the estate lands.", {"wood": 16.0, "cloth": 4.0, "cacao": 1.0}, {"cacao": 0.5, "ritual_goods": 0.25}, {"tlamacazqueh": 1}, [], "Future hook for crop, pest and harvest-risk signs.")
				]},
				{"tier": 2, "title": "Level 2 — Storm Calendar Wing", "structures": [
					palace_structure_node(state, "tlaloc_storm_calendar_archive", god_id, 2, "Storm Calendar Archive", "Painted bark records and priestly tallies compare present weather signs against previous ritual years.", {"wood": 40.0, "cloth": 10.0, "ritual_goods": 3.0, "cacao": 2.0}, {"cacao": 1.0, "cloth": 0.5, "ritual_goods": 0.5}, {"tlamacazqueh": 2, "pipiltin": 1}, ["One Level 1 Tlaloc structure"], "Extends natural-event forecast range."),
					palace_structure_node(state, "tlaloc_drought_vessel_court", god_id, 2, "Drought Vessel Court", "Rows of sealed vessels hold water, dust and field offerings to read dry-season severity.", {"wood": 34.0, "cloth": 8.0, "ritual_goods": 3.0}, {"cacao": 1.0, "ritual_goods": 0.5}, {"tlamacazqueh": 2}, ["Rain-Reading Basin"], "Future hook for drought severity and preparation."),
					palace_structure_node(state, "tlaloc_flood_marker_terrace", god_id, 2, "Flood Marker Terrace", "A raised terrace marked with carved flood levels and canal measures.", {"wood": 44.0, "cloth": 8.0, "tools": 2.0}, {"cacao": 0.75, "tools": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, ["Canal Listening Court"], "Future hook for flood severity and likely affected goods.")
				]},
				{"tier": 3, "title": "Level 3 — Deep Omen Court", "structures": [
					palace_structure_node(state, "tlaloc_deep_calendar_observatory", god_id, 3, "Deep Calendar Observatory", "A high palace platform for aligning rain, mountain, canal and crop records into long-range forecast patterns.", {"wood": 80.0, "cloth": 18.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, {"cacao": 1.5, "ritual_goods": 1.0, "fine_textiles": 0.25}, {"tlamacazqueh": 3, "pipiltin": 2}, ["Storm Calendar Archive"], "Reveals event duration and affected goods once forecast mechanics are active."),
					palace_structure_node(state, "tlaloc_lake_mirror_priests", god_id, 3, "Lake-Mirror Priests", "A staffed priestly office that compares mirrored water signs against tribute and field records.", {"wood": 70.0, "cloth": 16.0, "ritual_goods": 6.0, "cacao": 4.0}, {"cacao": 2.0, "ritual_goods": 0.75}, {"tlamacazqueh": 4, "pipiltin": 1}, ["Drought Vessel Court or Flood Marker Terrace"], "Future hook for better forecast accuracy and fewer unknowns.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Tlaloc", "structures": [
					palace_structure_node(state, "tlaloc_great_court", god_id, 4, "Great Court of Tlaloc", "A full palace court dedicated to rain, waters, fields and the hidden calendar of natural pressure.", {"wood": 140.0, "cloth": 35.0, "ritual_goods": 10.0, "fine_textiles": 2.0}, {"cacao": 3.0, "ritual_goods": 1.5, "fine_textiles": 0.5}, {"tlamacazqueh": 6, "pipiltin": 3}, ["Deep Calendar Observatory", "Lake-Mirror Priests"], "Long-range natural calendar foresight and full Tlaloc palace authority.")
				]}
			]
		"huitzilopochtli":
			return [
				{"tier": 1, "title": "Level 1 — War Banner Court", "structures": [
					palace_structure_node(state, "huitz_war_banner_court", god_id, 1, "War Banner Court", "A court for public war standards, muster rites and the formal authority of the war route.", {"wood": 20.0, "cloth": 5.0, "weapons": 1.0}, {"cacao": 0.5, "cloth": 0.5}, {"pipiltin": 1}, [], "Supports formal Flower War authority under a Huitzilopochtli Palace."),
					palace_structure_node(state, "huitz_captive_procession_steps", god_id, 1, "Captive Procession Steps", "Ceremonial steps for bringing captives, witnesses and war spoils into palace view.", {"wood": 18.0, "cloth": 4.0, "ritual_goods": 1.0}, {"cacao": 0.5, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Future hook for captives, sacrifice and war-route visibility."),
					palace_structure_node(state, "huitz_weapon_oath_hall", god_id, 1, "Weapon Oath Hall", "A hall where warriors and nobles bind weapons, discipline and palace service to the war god.", {"wood": 24.0, "cloth": 4.0, "weapons": 2.0}, {"cacao": 0.5, "weapons": 0.25}, {"pipiltin": 1}, [], "Future hook for military organisation and warrior preparation.")
				]},
				{"tier": 2, "title": "Level 2 — Martial Review Wing", "structures": [
					palace_structure_node(state, "huitz_eagle_jaguar_review_court", god_id, 2, "Eagle-Jaguar Review Court", "A review court for warbands, captains and noble witnesses before a Flower War muster.", {"wood": 45.0, "cloth": 10.0, "weapons": 3.0, "cacao": 2.0}, {"cacao": 1.0, "cloth": 0.5}, {"pipiltin": 2}, ["War Banner Court"], "Future hook for warband management authority."),
					palace_structure_node(state, "huitz_sacrifice_ledger_chamber", god_id, 2, "Sacrifice Ledger Chamber", "A palace office recording captives, ritual use, witnesses and obligation fulfilment.", {"wood": 36.0, "cloth": 8.0, "ritual_goods": 3.0}, {"cacao": 1.0, "ritual_goods": 0.5}, {"tlamacazqueh": 2, "pipiltin": 1}, ["Captive Procession Steps"], "Future hook for captive-to-ritual administration."),
					palace_structure_node(state, "huitz_martial_tribute_office", god_id, 2, "Martial Tribute Office", "An office that separates war spoils, weapon obligations and ruler-facing martial goods.", {"wood": 38.0, "cloth": 8.0, "tools": 2.0, "weapons": 2.0}, {"cacao": 1.0, "tools": 0.25}, {"pipiltin": 2}, ["Weapon Oath Hall"], "Future hook for war spoils and obligations.")
				]},
				{"tier": 3, "title": "Level 3 — Sun-War Tribunal", "structures": [
					palace_structure_node(state, "huitz_sun_war_tribunal", god_id, 3, "Sun-War Tribunal", "A high tribunal where war success, captives and noble martial claims are judged.", {"wood": 85.0, "cloth": 18.0, "ritual_goods": 6.0, "weapons": 5.0, "fine_textiles": 1.0}, {"cacao": 1.5, "ritual_goods": 0.75, "weapons": 0.5}, {"tlamacazqueh": 2, "pipiltin": 3}, ["Eagle-Jaguar Review Court"], "Stronger war-route legitimacy and martial recognition hooks."),
					palace_structure_node(state, "huitz_captive_witness_court", god_id, 3, "Captive Witness Court", "A public court where captives, witnesses and palace representatives make war results visible.", {"wood": 74.0, "cloth": 16.0, "ritual_goods": 6.0, "cacao": 4.0}, {"cacao": 2.0, "ritual_goods": 0.75}, {"tlamacazqueh": 3, "pipiltin": 2}, ["Sacrifice Ledger Chamber or Martial Tribute Office"], "Future hook for public war legitimacy and captive display.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Huitzilopochtli", "structures": [
					palace_structure_node(state, "huitz_great_court", god_id, 4, "Great Court of Huitzilopochtli", "A full palace court for war, captives, martial claims and the authority to pursue the war route.", {"wood": 150.0, "cloth": 35.0, "weapons": 10.0, "ritual_goods": 10.0, "fine_textiles": 2.0}, {"cacao": 3.0, "ritual_goods": 1.5, "weapons": 0.75}, {"tlamacazqueh": 4, "pipiltin": 5}, ["Sun-War Tribunal", "Captive Witness Court"], "Full war palace authority and late war-route support.")
				]}
			]
		"tezcatlipoca":
			return [
				{"tier": 1, "title": "Level 1 — Mirror Court", "structures": [
					palace_structure_node(state, "tez_obsidian_mirror_chamber", god_id, 1, "Obsidian Mirror Chamber", "A dark palace room for reading rivals, scarcity and hidden pressure through polished obsidian.", {"wood": 18.0, "cloth": 4.0, "obsidian": 2.0}, {"cacao": 0.75, "obsidian": 0.25}, {"pipiltin": 1}, [], "Future hook for rival and market-pressure hints."),
					palace_structure_node(state, "tez_smoke_messenger_room", god_id, 1, "Smoke Messenger Room", "A chamber for controlled smoke rites, secret messages and dangerous promises.", {"wood": 20.0, "cloth": 5.0, "ritual_goods": 1.0}, {"cacao": 0.75, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Future hook for manipulation and hidden communication."),
					palace_structure_node(state, "tez_night_ledger_office", god_id, 1, "Night Ledger Office", "A concealed ledger office for recording shortages, debts, rival needs and pressure points.", {"wood": 18.0, "cloth": 5.0, "cacao": 1.0}, {"cacao": 1.0, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for shortage and pressure-point tracking.")
				]},
				{"tier": 2, "title": "Level 2 — Shadow Administration", "structures": [
					palace_structure_node(state, "tez_rival_shadow_court", god_id, 2, "Rival Shadow Court", "A hidden court for measuring rival weakness, pride, debts and dangerous opportunities.", {"wood": 42.0, "cloth": 10.0, "obsidian": 3.0, "cacao": 3.0}, {"cacao": 1.5, "fine_textiles": 0.25}, {"pipiltin": 2}, ["Obsidian Mirror Chamber"], "Future hook for rival disruption."),
					palace_structure_node(state, "tez_scarcity_granary_office", god_id, 2, "Scarcity Granary Office", "An office that tracks shortages, market bottlenecks and which goods can be pressured.", {"wood": 40.0, "cloth": 8.0, "tools": 2.0, "cacao": 2.0}, {"cacao": 1.25, "tools": 0.25}, {"pipiltin": 2}, ["Night Ledger Office"], "Future hook for market pressure leverage."),
					palace_structure_node(state, "tez_whispering_servant_network", god_id, 2, "Whispering Servant Network", "A staff network of servants, messengers and obligated listeners around rival households.", {"wood": 34.0, "cloth": 10.0, "cacao": 4.0}, {"cacao": 1.5, "cloth": 0.5}, {"pipiltin": 1, "tlacotin": 5}, ["Smoke Messenger Room"], "Future hook for intrigue and hidden pressure.")
				]},
				{"tier": 3, "title": "Level 3 — Black Mirror Council", "structures": [
					palace_structure_node(state, "tez_black_mirror_council", god_id, 3, "Black Mirror Council", "A dangerous council for coordinating hidden pressure, scarcity plays and rival manipulation.", {"wood": 82.0, "cloth": 20.0, "obsidian": 6.0, "fine_textiles": 1.0}, {"cacao": 2.5, "obsidian": 0.5, "fine_textiles": 0.25}, {"tlamacazqueh": 2, "pipiltin": 3}, ["Rival Shadow Court or Scarcity Granary Office"], "Stronger hidden pressure and manipulation hooks."),
					palace_structure_node(state, "tez_broken_oath_chamber", god_id, 3, "Broken Oath Chamber", "A private chamber for dangerous bargains, threats and promises that should never be spoken publicly.", {"wood": 70.0, "cloth": 16.0, "ritual_goods": 5.0, "obsidian": 4.0}, {"cacao": 2.0, "ritual_goods": 0.75}, {"tlamacazqueh": 2, "pipiltin": 2}, ["Whispering Servant Network"], "Future hook for dangerous rival-pressure tools.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Tezcatlipoca", "structures": [
					palace_structure_node(state, "tez_great_court", god_id, 4, "Great Court of Tezcatlipoca", "A hidden-palace court where scarcity, fear, ambition and rival weakness are treated as instruments of power.", {"wood": 145.0, "cloth": 35.0, "obsidian": 10.0, "ritual_goods": 8.0, "fine_textiles": 2.0}, {"cacao": 4.0, "obsidian": 1.0, "fine_textiles": 0.5}, {"tlamacazqueh": 3, "pipiltin": 6}, ["Black Mirror Council", "Broken Oath Chamber"], "High-level scarcity, intrigue and rival-pressure authority.")
				]}
			]
		"quetzalcoatl":
			return [
				{"tier": 1, "title": "Level 1 — Feathered Audience Hall", "structures": [
					palace_structure_node(state, "quetz_feathered_audience_hall", god_id, 1, "Feathered Audience Hall", "An elegant audience hall where the palace presents orderly, legitimate authority to guests and retainers.", {"wood": 20.0, "cloth": 6.0, "cacao": 1.0}, {"cacao": 0.75, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for ruler-facing legitimacy."),
					palace_structure_node(state, "quetz_tribute_record_office", god_id, 1, "Tribute Record Office", "A record office for tribute promises, deliveries, stored goods and ruler-facing reliability.", {"wood": 18.0, "cloth": 5.0, "tools": 1.0}, {"cacao": 0.5, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for court-need donation clarity."),
					palace_structure_node(state, "quetz_scribe_mat_court", god_id, 1, "Scribe Mat Court", "A court of mats, painted records and formal speech for orderly palace administration.", {"wood": 18.0, "cloth": 5.0, "cacao": 1.0}, {"cacao": 0.75, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for order and palace administration.")
				]},
				{"tier": 2, "title": "Level 2 — Diplomatic Reception Wing", "structures": [
					palace_structure_node(state, "quetz_diplomatic_reception_court", god_id, 2, "Diplomatic Reception Court", "A reception court for rival houses, messengers, ruler agents and formal negotiation.", {"wood": 42.0, "cloth": 12.0, "cacao": 3.0, "fine_textiles": 1.0}, {"cacao": 1.5, "fine_textiles": 0.25}, {"pipiltin": 2}, ["Feathered Audience Hall"], "Future negotiation and recognition hooks."),
					palace_structure_node(state, "quetz_law_speech_chamber", god_id, 2, "Law-Speech Chamber", "A chamber where obligations, promises and public judgements are spoken before witnesses.", {"wood": 38.0, "cloth": 10.0, "ritual_goods": 2.0}, {"cacao": 1.0, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 2}, ["Scribe Mat Court"], "Future hook for trust and formal legitimacy."),
					palace_structure_node(state, "quetz_market_wind_gallery", god_id, 2, "Market-Wind Gallery", "A palace gallery where trade information, tribute expectation and visible order are brought together.", {"wood": 40.0, "cloth": 10.0, "tools": 2.0, "cacao": 2.0}, {"cacao": 1.0, "cloth": 0.5}, {"pipiltin": 2}, ["Tribute Record Office"], "Future hook for palace performance and credibility.")
				]},
				{"tier": 3, "title": "Level 3 — Feathered Legitimacy Court", "structures": [
					palace_structure_node(state, "quetz_feathered_legitimacy_court", god_id, 3, "Feathered Legitimacy Court", "A major court of record, ceremony and noble reception for proving the house deserves recognition.", {"wood": 82.0, "cloth": 22.0, "cacao": 5.0, "fine_textiles": 2.0}, {"cacao": 2.0, "fine_textiles": 0.5}, {"pipiltin": 4}, ["Diplomatic Reception Court or Law-Speech Chamber"], "Stronger recognition-route and tribute credibility hooks."),
					palace_structure_node(state, "quetz_ruler_witness_hall", god_id, 3, "Ruler Witness Hall", "A formal hall designed to make obligation, success and legitimacy visible to agents of higher authority.", {"wood": 74.0, "cloth": 18.0, "ritual_goods": 4.0, "fine_textiles": 1.0}, {"cacao": 2.0, "ritual_goods": 0.5, "fine_textiles": 0.25}, {"tlamacazqueh": 1, "pipiltin": 3}, ["Market-Wind Gallery"], "Future hook for high-trust ruler-facing display.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Quetzalcoatl", "structures": [
					palace_structure_node(state, "quetz_great_court", god_id, 4, "Great Court of Quetzalcoatl", "A full legitimacy court for tribute reliability, palace order, recognition and ruler-facing trust.", {"wood": 150.0, "cloth": 40.0, "cacao": 8.0, "ritual_goods": 8.0, "fine_textiles": 3.0}, {"cacao": 3.5, "fine_textiles": 0.75}, {"tlamacazqueh": 2, "pipiltin": 6}, ["Feathered Legitimacy Court", "Ruler Witness Hall"], "Full legitimacy palace authority and late recognition-route support.")
				]}
			]
	return []



func get_built_palace_structure_ids(state: Node) -> Array[String]:
	var output: Array[String] = []
	if state == null:
		return output
	var built_variant: Variant = _palace_dictionary(state, "palace_built_structures")
	if not (built_variant is Dictionary):
		return output
	var built: Dictionary = built_variant as Dictionary
	for key_variant: Variant in built.keys():
		var structure_id: String = String(key_variant)
		if bool(built.get(structure_id, false)):
			output.append(structure_id)
	output.sort()
	return output

func is_palace_structure_built(state: Node, structure_id: String) -> bool:
	if state == null:
		return false
	var built_variant: Variant = _palace_dictionary(state, "palace_built_structures")
	if not (built_variant is Dictionary):
		return false
	return bool((built_variant as Dictionary).get(structure_id, false))

func apply_palace_structure_statuses(state: Node, tiers: Array[Dictionary], route_id: String) -> void:
	var operation_preview: Dictionary = get_palace_structure_operation_preview(state)
	var operation_statuses: Dictionary = operation_preview.get("statuses", {}) as Dictionary
	for tier_index: int in range(tiers.size()):
		var tier: Dictionary = tiers[tier_index]
		var structures: Array = tier.get("structures", []) as Array
		for structure_index: int in range(structures.size()):
			if not (structures[structure_index] is Dictionary):
				continue
			var structure: Dictionary = structures[structure_index] as Dictionary
			var structure_id: String = String(structure.get("id", ""))
			var built: bool = is_palace_structure_built(state, structure_id)
			var build_status: Dictionary = can_build_palace_structure(state, structure_id)
			structure["built"] = built
			structure["can_build"] = bool(build_status.get("ok", false))
			structure["build_status"] = String(build_status.get("reason", ""))
			if built:
				var op_status: Dictionary = operation_statuses.get(structure_id, {}) as Dictionary
				var active: bool = bool(op_status.get("active", false))
				structure["active"] = active
				structure["inactive_reason"] = String(op_status.get("inactive_reason", "Operation status not calculated."))
				structure["maintenance_paid_preview"] = op_status.get("maintenance_paid", {}) as Dictionary
				structure["staff_assigned_preview"] = op_status.get("staff_assigned", {}) as Dictionary
				structure["status"] = "Active" if active else "Built, inactive"
			elif bool(build_status.get("ok", false)):
				structure["active"] = false
				structure["inactive_reason"] = "Not built."
				structure["status"] = "Ready to build"
			else:
				structure["active"] = false
				structure["inactive_reason"] = "Not built."
				structure["status"] = "Locked"
			structures[structure_index] = structure
		tier["structures"] = structures
		tiers[tier_index] = tier

func palace_structure_by_id(state: Node, structure_id: String, route_id: String = "") -> Dictionary:
	if state == null:
		return {}
	var search_routes: Array[String] = []
	if route_id.strip_edges() != "":
		search_routes.append(route_id.strip_edges().to_lower())
	else:
		var dedicated: String = get_palace_dedicated_god(state)
		if dedicated != "":
			search_routes.append(dedicated)
		else:
			for palace_god_id: String in PALACE_GOD_IDS:
				search_routes.append(palace_god_id)
	for god_id: String in search_routes:
		var tiers_variant: Variant = palace_structure_tree_tiers(state, god_id)
		if not (tiers_variant is Array):
			continue
		var tiers: Array = tiers_variant as Array
		for tier_variant: Variant in tiers:
			if not (tier_variant is Dictionary):
				continue
			var tier: Dictionary = tier_variant as Dictionary
			var structures: Array = tier.get("structures", []) as Array
			for structure_variant: Variant in structures:
				if not (structure_variant is Dictionary):
					continue
				var structure: Dictionary = structure_variant as Dictionary
				if String(structure.get("id", "")) == structure_id:
					return structure.duplicate(true)
	return {}

func palace_structure_id_by_name(state: Node, god_id: String, structure_name: String) -> String:
	if state == null:
		return ""
	var needle: String = structure_name.strip_edges().to_lower()
	if needle == "":
		return ""
	var tiers_variant: Variant = palace_structure_tree_tiers(state, god_id)
	if not (tiers_variant is Array):
		return ""
	var tiers: Array = tiers_variant as Array
	for tier_variant: Variant in tiers:
		if not (tier_variant is Dictionary):
			continue
		var tier: Dictionary = tier_variant as Dictionary
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if not (structure_variant is Dictionary):
				continue
			var structure: Dictionary = structure_variant as Dictionary
			if String(structure.get("name", "")).strip_edges().to_lower() == needle:
				return String(structure.get("id", ""))
	return ""

func palace_any_built_in_tier(state: Node, god_id: String, tier_number: int) -> bool:
	if state == null:
		return false
	var tiers_variant: Variant = palace_structure_tree_tiers(state, god_id)
	if not (tiers_variant is Array):
		return false
	var tiers: Array = tiers_variant as Array
	for tier_variant: Variant in tiers:
		if not (tier_variant is Dictionary):
			continue
		var tier: Dictionary = tier_variant as Dictionary
		if int(tier.get("tier", 0)) != tier_number:
			continue
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if not (structure_variant is Dictionary):
				continue
			var structure: Dictionary = structure_variant as Dictionary
			if is_palace_structure_built(state, String(structure.get("id", ""))):
				return true
	return false

func palace_prerequisite_check(state: Node, god_id: String, prerequisite_text: String) -> Dictionary:
	var text: String = prerequisite_text.strip_edges()
	if text == "":
		return {"ok": true, "reason": "No prerequisite."}
	if text.begins_with("One Level 1"):
		if palace_any_built_in_tier(state, god_id, 1):
			return {"ok": true, "reason": text + " met."}
		return {"ok": false, "reason": "Requires any Level 1 " + god_display_name(god_id) + " palace structure."}
	if text.find(" or ") >= 0:
		var options: PackedStringArray = text.split(" or ")
		for option: String in options:
			var option_id: String = palace_structure_id_by_name(state, god_id, option)
			if option_id != "" and is_palace_structure_built(state, option_id):
				return {"ok": true, "reason": text + " met."}
		return {"ok": false, "reason": "Requires one of: " + text + "."}
	var required_id: String = palace_structure_id_by_name(state, god_id, text)
	if required_id == "":
		return {"ok": false, "reason": "Unknown prerequisite: " + text + "."}
	if is_palace_structure_built(state, required_id):
		return {"ok": true, "reason": text + " met."}
	return {"ok": false, "reason": "Requires " + text + "."}

func palace_prerequisites_met(state: Node, structure: Dictionary) -> Dictionary:
	var god_id: String = String(structure.get("god_id", get_palace_dedicated_god(state)))
	var prerequisites: Array = structure.get("prerequisites", []) as Array
	var blocked: Array[String] = []
	for prereq_variant: Variant in prerequisites:
		var check: Dictionary = palace_prerequisite_check(state, god_id, String(prereq_variant))
		if not bool(check.get("ok", false)):
			blocked.append(String(check.get("reason", "Prerequisite not met.")))
	if blocked.is_empty():
		return {"ok": true, "reason": "Prerequisites met."}
	return {"ok": false, "reason": " ".join(blocked)}

func can_pay_palace_build_cost(state: Node, cost: Dictionary) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Palace state is not connected."}
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(cost[resource_variant])
		var free_value: float = float(state.call("free_stock_after_reserves", resource_id))
		if free_value + 0.001 < needed:
			return {"ok": false, "reason": "Need " + _format_amount(state, needed - free_value) + " more free " + _resource_name(state, resource_id) + " after reserves."}
	return {"ok": true, "reason": "Build cost available."}

func can_build_palace_structure(state: Node, structure_id: String) -> Dictionary:
	var dedicated_god: String = get_palace_dedicated_god(state)
	if dedicated_god == "":
		return {"ok": false, "reason": "Dedicate the palace before building palace structures."}
	var structure: Dictionary = palace_structure_by_id(state, structure_id, dedicated_god)
	if structure.is_empty():
		return {"ok": false, "reason": "Unknown palace structure for the chosen route."}
	if is_palace_structure_built(state, structure_id):
		return {"ok": false, "reason": "Already built."}
	var prereq_status: Dictionary = palace_prerequisites_met(state, structure)
	if not bool(prereq_status.get("ok", false)):
		return {"ok": false, "reason": String(prereq_status.get("reason", "Prerequisites not met."))}
	var cost_status: Dictionary = can_pay_palace_build_cost(state, structure.get("build_cost", {}) as Dictionary)
	if not bool(cost_status.get("ok", false)):
		return cost_status
	return {"ok": true, "reason": "Ready to build " + String(structure.get("name", "palace structure")) + "."}

func build_palace_structure(state: Node, structure_id: String) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Palace state is not connected."}
	var status: Dictionary = can_build_palace_structure(state, structure_id)
	if not bool(status.get("ok", false)):
		_append_report(state, "Palace structure not built: " + String(status.get("reason", "Blocked.")))
		_emit_state_changed(state)
		return status
	var structure: Dictionary = palace_structure_by_id(state, structure_id, get_palace_dedicated_god(state))
	var cost: Dictionary = structure.get("build_cost", {}) as Dictionary
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(state, resource_id, -float(cost[resource_variant]))
	var built: Dictionary = _palace_dictionary(state, "palace_built_structures")
	built[structure_id] = true
	_set_palace_dictionary(state, "palace_built_structures", built)
	_set_palace_dictionary(state, "palace_structure_runtime_statuses", {})
	_append_report(state, "Built palace structure: " + String(structure.get("name", structure_id)) + ". It must now be maintained and staffed each Veintena to remain active.")
	_emit_state_changed(state)
	return {"ok": true, "reason": "Built " + String(structure.get("name", structure_id)) + ".", "structure_id": structure_id}

func palace_built_structure_ids_in_tree_order(state: Node, god_id: String) -> Array[String]:
	var output: Array[String] = []
	if state == null or god_id == "":
		return output
	var tiers_variant: Variant = palace_structure_tree_tiers(state, god_id)
	if not (tiers_variant is Array):
		return output
	var tiers: Array = tiers_variant as Array
	for tier_variant: Variant in tiers:
		if not (tier_variant is Dictionary):
			continue
		var tier: Dictionary = tier_variant as Dictionary
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if not (structure_variant is Dictionary):
				continue
			var structure: Dictionary = structure_variant as Dictionary
			var structure_id: String = String(structure.get("id", ""))
			if structure_id != "" and is_palace_structure_built(state, structure_id):
				output.append(structure_id)
	return output

func palace_staff_group_order() -> Array[String]:
	return ["pipiltin", "tlamacazqueh", "tolteca", "tlacotin", "macehualtin", "yaotequihuaqueh", "malli"]

func get_palace_staff_capacity(state: Node) -> Dictionary:
	var result: Dictionary = {}
	if state == null:
		return result
	for group_id: String in palace_staff_group_order():
		result[group_id] = int(state.call("_active_population_for_group", group_id))
	return result

func get_palace_staff_summary(state: Node) -> Dictionary:
	var capacity: Dictionary = get_palace_staff_capacity(state)
	var required: Dictionary = get_palace_required_staff(state)
	var operation: Dictionary = get_palace_structure_operation_preview(state)
	var used: Dictionary = operation.get("staff_used", {}) as Dictionary
	var shortfalls: Dictionary = operation.get("staff_shortfalls", {}) as Dictionary
	var rows: Array[Dictionary] = []
	var group_ids: Array[String] = palace_staff_group_order()
	for key_variant: Variant in required.keys():
		var key_id: String = String(key_variant)
		if not group_ids.has(key_id):
			group_ids.append(key_id)
	for key_variant: Variant in used.keys():
		var key_id: String = String(key_variant)
		if not group_ids.has(key_id):
			group_ids.append(key_id)
	for key_variant: Variant in shortfalls.keys():
		var key_id: String = String(key_variant)
		if not group_ids.has(key_id):
			group_ids.append(key_id)
	var total_required: int = 0
	var total_used: int = 0
	var total_shortfall: int = 0
	for group_id: String in group_ids:
		var available_count: int = int(capacity.get(group_id, 0))
		var required_count: int = int(required.get(group_id, 0))
		var used_count: int = int(used.get(group_id, 0))
		var shortfall_count: int = int(shortfalls.get(group_id, 0))
		if available_count <= 0 and required_count <= 0 and used_count <= 0 and shortfall_count <= 0:
			continue
		total_required += required_count
		total_used += used_count
		total_shortfall += shortfall_count
		var status: String = "Idle"
		if required_count <= 0:
			status = "Not required"
		elif shortfall_count > 0:
			status = "Shortfall"
		elif used_count >= required_count:
			status = "Covered"
		elif used_count > 0:
			status = "Partly assigned"
		else:
			status = "Available"
		rows.append({
			"id": group_id,
			"name": _labour_group_name(state, group_id),
			"available": available_count,
			"required_by_built_structures": required_count,
			"assigned_to_active_structures": used_count,
			"remaining_after_active_structures": max(0, available_count - used_count),
			"shortfall": shortfall_count,
			"status": status
		})
	var headline: String = "No palace staff required yet."
	if total_required > 0:
		headline = "Palace staff: " + str(total_used) + " assigned to active structures / " + str(total_required) + " required by built structures."
		if total_shortfall > 0:
			headline += " Shortfall: " + str(total_shortfall) + "."
	return {
		"rows": rows,
		"capacity": capacity,
		"required": required,
		"used": used,
		"shortfalls": shortfalls,
		"total_required": total_required,
		"total_used": total_used,
		"total_shortfall": total_shortfall,
		"headline": headline,
		"note": "Palace structures use existing active population groups such as Pipiltin nobles, Tlamacazqueh priests, Tolteca specialists and labour groups where specified."
	}

func get_palace_structure_operation_preview(state: Node) -> Dictionary:
	return resolve_palace_structure_operation(state, false)

func get_palace_structure_runtime_statuses(state: Node) -> Dictionary:
	if state == null:
		return {}
	var statuses_variant: Variant = _palace_dictionary(state, "palace_structure_runtime_statuses")
	if statuses_variant is Dictionary and not (statuses_variant as Dictionary).is_empty():
		return (statuses_variant as Dictionary).duplicate(true)
	return (get_palace_structure_operation_preview(state).get("statuses", {}) as Dictionary).duplicate(true)

func get_active_palace_structure_ids(state: Node) -> Array[String]:
	var output: Array[String] = []
	var statuses: Dictionary = get_palace_structure_runtime_statuses(state)
	for key_variant: Variant in statuses.keys():
		var structure_id: String = String(key_variant)
		var status: Dictionary = statuses[structure_id] as Dictionary
		if bool(status.get("active", false)):
			output.append(structure_id)
	output.sort()
	return output

func get_inactive_palace_structure_ids(state: Node) -> Array[String]:
	var output: Array[String] = []
	var statuses: Dictionary = get_palace_structure_runtime_statuses(state)
	for key_variant: Variant in statuses.keys():
		var structure_id: String = String(key_variant)
		var status: Dictionary = statuses[structure_id] as Dictionary
		if bool(status.get("built", false)) and not bool(status.get("active", false)):
			output.append(structure_id)
	output.sort()
	return output

func resolve_palace_structure_operation(state: Node, pay_costs: bool) -> Dictionary:
	var dedicated_god: String = get_palace_dedicated_god(state)
	var result: Dictionary = {
		"dedicated_god": dedicated_god,
		"statuses": {},
		"active_structure_ids": [],
		"inactive_structure_ids": [],
		"maintenance_needed": {},
		"maintenance_paid": {},
		"maintenance_shortfalls": {},
		"staff_capacity": get_palace_staff_capacity(state),
		"staff_used": {},
		"staff_shortfalls": {},
		"reports": []
	}
	if state == null or dedicated_god == "":
		return result
	var temp_stockpile: Dictionary = _copy_stockpile_dictionary(_estate_stockpiles_copy(state))
	var available_staff: Dictionary = get_palace_staff_capacity(state)
	var structure_ids: Array[String] = palace_built_structure_ids_in_tree_order(state, dedicated_god)
	for structure_id: String in structure_ids:
		var structure: Dictionary = palace_structure_by_id(state, structure_id, dedicated_god)
		if structure.is_empty():
			continue
		var maintenance: Dictionary = structure.get("maintenance_cost", {}) as Dictionary
		var staff: Dictionary = structure.get("staff_requirement", {}) as Dictionary
		_add_dictionary_amounts(result["maintenance_needed"] as Dictionary, maintenance)
		var missing_parts: Array[String] = []
		for resource_variant: Variant in maintenance.keys():
			var resource_id: String = String(resource_variant)
			var needed: float = float(maintenance[resource_variant])
			var available: float = float(temp_stockpile.get(resource_id, 0.0))
			if available + 0.001 < needed:
				var shortfall: float = needed - available
				(result["maintenance_shortfalls"] as Dictionary)[resource_id] = float((result["maintenance_shortfalls"] as Dictionary).get(resource_id, 0.0)) + shortfall
				missing_parts.append(_format_amount(state, shortfall) + " " + _resource_name(state, resource_id))
		for staff_variant: Variant in staff.keys():
			var staff_id: String = String(staff_variant)
			var needed_staff: int = int(staff[staff_variant])
			var available_staff_count: int = int(available_staff.get(staff_id, 0))
			if available_staff_count < needed_staff:
				var staff_shortfall: int = needed_staff - available_staff_count
				(result["staff_shortfalls"] as Dictionary)[staff_id] = int((result["staff_shortfalls"] as Dictionary).get(staff_id, 0)) + staff_shortfall
				missing_parts.append(_labour_group_name(state, staff_id) + " " + str(staff_shortfall))
		var structure_status: Dictionary = {
			"id": structure_id,
			"name": String(structure.get("name", structure_id)),
			"built": true,
			"active": false,
			"inactive_reason": "",
			"maintenance_paid": {},
			"staff_assigned": {}
		}
		if missing_parts.is_empty():
			structure_status["active"] = true
			structure_status["inactive_reason"] = "Active."
			for resource_variant: Variant in maintenance.keys():
				var resource_id: String = String(resource_variant)
				var amount: float = float(maintenance[resource_variant])
				temp_stockpile[resource_id] = float(temp_stockpile.get(resource_id, 0.0)) - amount
				(structure_status["maintenance_paid"] as Dictionary)[resource_id] = amount
				(result["maintenance_paid"] as Dictionary)[resource_id] = float((result["maintenance_paid"] as Dictionary).get(resource_id, 0.0)) + amount
			for staff_variant: Variant in staff.keys():
				var staff_id: String = String(staff_variant)
				var amount: int = int(staff[staff_variant])
				available_staff[staff_id] = int(available_staff.get(staff_id, 0)) - amount
				(structure_status["staff_assigned"] as Dictionary)[staff_id] = amount
				(result["staff_used"] as Dictionary)[staff_id] = int((result["staff_used"] as Dictionary).get(staff_id, 0)) + amount
			(result["active_structure_ids"] as Array).append(structure_id)
			(result["reports"] as Array).append("Palace structure active: " + String(structure.get("name", structure_id)) + ".")
		else:
			structure_status["inactive_reason"] = "Missing: " + ", ".join(missing_parts) + "."
			(result["inactive_structure_ids"] as Array).append(structure_id)
			(result["reports"] as Array).append("Palace structure inactive: " + String(structure.get("name", structure_id)) + " — " + String(structure_status["inactive_reason"]))
		(result["statuses"] as Dictionary)[structure_id] = structure_status
	if pay_costs:
		for resource_variant: Variant in (result["maintenance_paid"] as Dictionary).keys():
			var resource_id: String = String(resource_variant)
			_add_stock(state, resource_id, -float((result["maintenance_paid"] as Dictionary)[resource_variant]))
	return result

func pay_palace_maintenance(state: Node) -> void:
	if state == null:
		return
	_set_palace_string_array(state, "last_palace_maintenance_report", [])
	if get_palace_dedicated_god(state) == "" or get_built_palace_structure_ids(state).is_empty():
		_set_palace_dictionary(state, "palace_structure_runtime_statuses", {})
		return
	var resolution: Dictionary = resolve_palace_structure_operation(state, true)
	_set_palace_dictionary(state, "palace_structure_runtime_statuses", (resolution.get("statuses", {}) as Dictionary).duplicate(true))
	var reports: Array = resolution.get("reports", []) as Array
	if reports.is_empty():
		return
	_append_report(state, "Palace maintenance resolves.")
	var last_maintenance: Array[String] = []
	for report_variant: Variant in reports:
		var line: String = String(report_variant)
		last_maintenance.append(line)
		_append_report(state, line)
	_set_palace_string_array(state, "last_palace_maintenance_report", last_maintenance)

func get_palace_total_maintenance(state: Node) -> Dictionary:
	var result: Dictionary = {}
	var dedicated_god: String = get_palace_dedicated_god(state)
	if dedicated_god == "":
		return result
	for structure_id: String in get_built_palace_structure_ids(state):
		var structure: Dictionary = palace_structure_by_id(state, structure_id, dedicated_god)
		if structure.is_empty():
			continue
		var maintenance: Dictionary = structure.get("maintenance_cost", {}) as Dictionary
		for resource_variant: Variant in maintenance.keys():
			var resource_id: String = String(resource_variant)
			result[resource_id] = float(result.get(resource_id, 0.0)) + float(maintenance[resource_variant])
	return result

func get_palace_required_staff(state: Node) -> Dictionary:
	var result: Dictionary = {}
	var dedicated_god: String = get_palace_dedicated_god(state)
	if dedicated_god == "":
		return result
	for structure_id: String in get_built_palace_structure_ids(state):
		var structure: Dictionary = palace_structure_by_id(state, structure_id, dedicated_god)
		if structure.is_empty():
			continue
		var staff: Dictionary = structure.get("staff_requirement", {}) as Dictionary
		for staff_variant: Variant in staff.keys():
			var staff_id: String = String(staff_variant)
			result[staff_id] = int(result.get(staff_id, 0)) + int(staff[staff_variant])
	return result


func palace_authority_route_headline(god_id: String, active_count: int) -> String:
	if god_id == "":
		return "No Palace Authority"
	if active_count <= 0:
		return god_display_name(god_id) + " authority is dormant"
	match god_id:
		GOD_TLALOC:
			return "Tlaloc Authority — Natural Calendar Foresight"
		GOD_HUITZILOPOCHTLI:
			return "Huitzilopochtli Authority — Flower Wars"
		GOD_TEZCATLIPOCA:
			return "Tezcatlipoca Authority — Scarcity and Intrigue"
		GOD_QUETZALCOATL:
			return "Quetzalcoatl Authority — Legitimacy and Recognition"
	return "Palace Authority"

func palace_authority_route_body(god_id: String, active_count: int) -> String:
	if god_id == "":
		return "Dedicate the palace on the Divine Seat tab to unlock a route-specific authority screen."
	if active_count <= 0:
		return "Build, maintain and staff palace structures before this route can express authority."
	match god_id:
		GOD_TLALOC:
			return "Active Tlaloc structures now reveal a controlled natural-calendar forecast prototype: rain, drought, flood, crop and field pressures appear earlier and in more detail as the palace grows."
		GOD_HUITZILOPOCHTLI:
			return "Huitzilopochtli dedication authorises attacking Flower Wars. Active Huitzilopochtli structures support future war-route authority and escalation."
		GOD_TEZCATLIPOCA:
			return "Active Tezcatlipoca structures reveal an information-only scarcity mirror: market pressure, shortage leverage and rival vulnerability hooks. Sabotage and manipulation actions are not implemented yet."
		GOD_QUETZALCOATL:
			return "Active Quetzalcoatl structures reveal an information-only legitimacy court: ruler-facing credibility, tribute reliability, palace trust and recognition-route hooks. Court need donations create prestige by base value; broader recognition systems are not implemented yet."
	return "Active palace structures are ready, but their route authority has not been defined."

func palace_authority_structure_row(state: Node, structure_id: String, status: Dictionary, god_id: String) -> Dictionary:
	var structure: Dictionary = palace_structure_by_id(state, structure_id, god_id)
	if structure.is_empty():
		return {}
	return {
		"id": structure_id,
		"name": String(structure.get("name", structure_id)),
		"tier": int(structure.get("tier", 1)),
		"effect_summary": String(structure.get("effect_summary", structure.get("summary", "Future palace authority hook."))),
		"active": bool(status.get("active", false)),
		"inactive_reason": String(status.get("inactive_reason", "")),
		"maintenance_paid": (status.get("maintenance_paid", {}) as Dictionary).duplicate(true),
		"staff_assigned": (status.get("staff_assigned", {}) as Dictionary).duplicate(true)
	}

func palace_next_locked_authority_rows(state: Node, god_id: String, limit: int = 4) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if state == null or god_id == "":
		return rows
	var tiers_variant: Variant = palace_structure_tree_tiers(state, god_id)
	if not (tiers_variant is Array):
		return rows
	var tiers: Array = tiers_variant as Array
	for tier_variant: Variant in tiers:
		if not (tier_variant is Dictionary):
			continue
		var tier: Dictionary = tier_variant as Dictionary
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if not (structure_variant is Dictionary):
				continue
			var structure: Dictionary = structure_variant as Dictionary
			var structure_id: String = String(structure.get("id", ""))
			if structure_id == "" or is_palace_structure_built(state, structure_id):
				continue
			var build_status: Dictionary = can_build_palace_structure(state, structure_id)
			rows.append({
				"id": structure_id,
				"name": String(structure.get("name", structure_id)),
				"tier": int(structure.get("tier", 1)),
				"effect_summary": String(structure.get("effect_summary", structure.get("summary", "Future palace authority hook."))),
				"can_build": bool(build_status.get("ok", false)),
				"build_status": String(build_status.get("reason", ""))
			})
			if rows.size() >= limit:
				return rows
	return rows

func get_palace_authority_summary(state: Node) -> Dictionary:
	var god_id: String = get_palace_dedicated_god(state)
	var statuses: Dictionary = get_palace_structure_runtime_statuses(state)
	var active_rows: Array[Dictionary] = []
	var inactive_rows: Array[Dictionary] = []
	var highest_active_tier: int = 0
	if god_id != "":
		var ordered_built: Array[String] = palace_built_structure_ids_in_tree_order(state, god_id)
		for structure_id: String in ordered_built:
			var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
			var row: Dictionary = palace_authority_structure_row(state, structure_id, status, god_id)
			if row.is_empty():
				continue
			if bool(row.get("active", false)):
				highest_active_tier = maxi(highest_active_tier, int(row.get("tier", 1)))
				active_rows.append(row)
			else:
				inactive_rows.append(row)
	var headline: String = palace_authority_route_headline(god_id, active_rows.size())
	var body: String = palace_authority_route_body(god_id, active_rows.size())
	return {
		"dedicated": god_id != "",
		"god_id": god_id,
		"god_name": god_display_name(god_id) if god_id != "" else "None",
		"route_name": get_palace_route_name(god_id),
		"headline": headline,
		"body": body,
		"active_structure_count": active_rows.size(),
		"inactive_structure_count": inactive_rows.size(),
		"highest_active_tier": highest_active_tier,
		"active_structures": active_rows,
		"inactive_structures": inactive_rows,
		"next_locked_structures": palace_next_locked_authority_rows(state, god_id, 4),
		"mechanics_note": "This tab now reads active palace structures. It does not yet apply route authority effects to gameplay.",
		"flower_war_gate_status": flower_war_palace_gate_status_text(state),
		"ruler_demand_status": "Court needs are connected as donation opportunities; donations create prestige by base value."
	}


# -----------------------------------------------------------------------------
# Palace Court Needs / Donation Prestige v0.43.11
# -----------------------------------------------------------------------------
# Court needs are visible ruler/court needs. Donating a needed good consumes real
# stock and grants Prestige according to the base value of the donated good.
# Prestige is score only and is never spent.

func palace_ruler_demand_sets() -> Array[Dictionary]:
	return [
		{
			"id": "food_and_court_cloth",
			"title": "Food and Court Cloth Need",
			"veintena_band": "Early cycle",
			"flavour": "The court is visibly short of basic food, cloth and elite hospitality goods. Donating these goods raises the house's public standing.",
			"demands": [
				{"slot": "raw", "slot_name": "Raw / food need", "resource_id": "maize", "amount": 25.0, "note": "Basic food support and public reliability."},
				{"slot": "processed", "slot_name": "Processed need", "resource_id": "cloth", "amount": 6.0, "note": "Visible household order and practical tribute preparation."},
				{"slot": "luxury_special", "slot_name": "Luxury / special need", "resource_id": "cacao", "amount": 3.0, "note": "Elite court hospitality and status display."}
			]
		},
		{
			"id": "construction_and_ritual_readiness",
			"title": "Construction and Ritual Need",
			"veintena_band": "Middle cycle",
			"flavour": "The court values houses that can support construction, ritual display and practical administration at the same time.",
			"demands": [
				{"slot": "raw", "slot_name": "Raw need", "resource_id": "wood", "amount": 20.0, "note": "Construction capacity and estate readiness."},
				{"slot": "processed", "slot_name": "Processed need", "resource_id": "tools", "amount": 4.0, "note": "Administrative and construction competence."},
				{"slot": "luxury_special", "slot_name": "Luxury / special need", "resource_id": "ritual_goods", "amount": 2.0, "note": "Ritual credibility and visible obligation."}
			]
		},
		{
			"id": "war_and_luxury_pressure",
			"title": "War and Luxury Need",
			"veintena_band": "Late cycle",
			"flavour": "The court is attentive to martial usefulness, textile strength and high-status presentation.",
			"demands": [
				{"slot": "raw", "slot_name": "Raw need", "resource_id": "cotton", "amount": 18.0, "note": "Textile base and household production capacity."},
				{"slot": "processed", "slot_name": "Processed need", "resource_id": "weapons", "amount": 2.0, "note": "War-route visibility and martial usefulness."},
				{"slot": "luxury_special", "slot_name": "Luxury / special need", "resource_id": "fine_textiles", "amount": 1.0, "note": "High-status palace presentation."}
			]
		}
	]

func current_palace_ruler_demand_index(state: Node) -> int:
	if state == null:
		return 0
	var current_veintena: int = _current_veintena_value(state)
	var index: int = int(floor(float(current_veintena - 1) / 6.0))
	return clampi(index, 0, palace_ruler_demand_sets().size() - 1)

func palace_ruler_demand_cycle_window(index: int) -> Dictionary:
	var demand_sets: Array[Dictionary] = palace_ruler_demand_sets()
	var safe_index: int = clampi(index, 0, maxi(0, demand_sets.size() - 1))
	var start_veintena: int = safe_index * 6 + 1
	var end_veintena: int = mini(start_veintena + 5, 18)
	return {
		"start_veintena": start_veintena,
		"end_veintena": end_veintena,
		"label": "Veintenas " + str(start_veintena) + "–" + str(end_veintena)
	}

func palace_ruler_demand_deadline_summary(state: Node, index: int = -1) -> Dictionary:
	if state == null:
		return {"cycle_index": 0, "start_veintena": 1, "end_veintena": 6, "veintenas_remaining": 0, "urgency": "Unknown", "headline": "Court need cycle unavailable."}
	var selected_index: int = current_palace_ruler_demand_index(state) if index < 0 else index
	var window: Dictionary = palace_ruler_demand_cycle_window(selected_index)
	var start_veintena: int = int(window.get("start_veintena", 1))
	var end_veintena: int = int(window.get("end_veintena", 6))
	var current_veintena: int = _current_veintena_value(state)
	var remaining: int = maxi(0, end_veintena - current_veintena + 1)
	var urgency: String = "Time remains"
	if current_veintena < start_veintena:
		remaining = end_veintena - start_veintena + 1
		urgency = "Future cycle"
	elif remaining <= 1:
		urgency = "Final Veintena"
	elif remaining <= 2:
		urgency = "Deadline close"
	var suffix: String = "s" if remaining != 1 else ""
	var headline: String = String(window.get("label", "Court need cycle")) + "; " + str(remaining) + " Veintena" + suffix + " including the current turn."
	return {
		"cycle_index": selected_index,
		"start_veintena": start_veintena,
		"end_veintena": end_veintena,
		"veintenas_remaining": remaining,
		"urgency": urgency,
		"headline": headline
	}

func report_palace_ruler_demand_cycle_transition(state: Node, previous_index: int, previous_title: String, previous_completion: Dictionary) -> void:
	var new_index: int = current_palace_ruler_demand_index(state)
	if new_index == previous_index:
		return
	_append_report(state, "Court need cycle closed: " + previous_title + ". Donated value: +" + _format_amount(state, float(previous_completion.get("total_prestige", 0.0))) + " Prestige across " + str(int(previous_completion.get("donation_count", 0))) + " donations.")
	var new_cycle: Dictionary = current_palace_ruler_demand_set(state)
	if not new_cycle.is_empty():
		var deadline: Dictionary = palace_ruler_demand_deadline_summary(state, new_index)
		_append_report(state, "New court need cycle opened: " + String(new_cycle.get("title", "Court Need")) + ". " + String(deadline.get("headline", "")))

func current_palace_ruler_demand_set(state: Node) -> Dictionary:
	var demand_sets: Array[Dictionary] = palace_ruler_demand_sets()
	if demand_sets.is_empty():
		return {}
	var selected_index: int = current_palace_ruler_demand_index(state)
	return demand_sets[selected_index] if selected_index >= 0 and selected_index < demand_sets.size() else {}

func palace_ruler_demand_cycle_id(state: Node) -> String:
	var selected: Dictionary = current_palace_ruler_demand_set(state)
	return String(selected.get("id", "no_court_need_cycle"))

func palace_ruler_demand_raw_row_by_slot(state: Node, slot_id: String) -> Dictionary:
	var selected: Dictionary = current_palace_ruler_demand_set(state)
	var rows: Array = selected.get("demands", []) as Array
	for row_variant: Variant in rows:
		if row_variant is Dictionary:
			var row: Dictionary = row_variant as Dictionary
			if String(row.get("slot", "")) == slot_id:
				return row
	return {}

func palace_donation_records_for_cycle(state: Node, cycle_id: String = "") -> Array[Dictionary]:
	var target_cycle: String = palace_ruler_demand_cycle_id(state) if cycle_id == "" else cycle_id
	var output: Array[Dictionary] = []
	if state == null:
		return output
	var records_variant: Variant = _palace_dictionary_array(state, "palace_ruler_demand_donations")
	if not (records_variant is Array):
		return output
	var all_records: Array = records_variant as Array
	for record_variant: Variant in all_records:
		if record_variant is Dictionary:
			var record: Dictionary = record_variant as Dictionary
			if String(record.get("cycle_id", "")) == target_cycle:
				output.append(record.duplicate(true))
	return output

func palace_donation_records_for_cycle_slot(state: Node, cycle_id: String, slot_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for record: Dictionary in palace_donation_records_for_cycle(state, cycle_id):
		if String(record.get("slot", "")) == slot_id:
			output.append(record.duplicate(true))
	return output

func palace_donation_total_for_cycle(state: Node, cycle_id: String = "") -> Dictionary:
	var records: Array[Dictionary] = palace_donation_records_for_cycle(state, cycle_id)
	var total_amount: float = 0.0
	var total_prestige: float = 0.0
	var by_resource: Dictionary = {}
	var by_slot: Dictionary = {}
	for record: Dictionary in records:
		var amount: float = float(record.get("amount", 0.0))
		var prestige_gain: float = float(record.get("prestige_gain", 0.0))
		var resource_id: String = String(record.get("resource_id", ""))
		var slot_id: String = String(record.get("slot", ""))
		total_amount += amount
		total_prestige += prestige_gain
		by_resource[resource_id] = float(by_resource.get(resource_id, 0.0)) + amount
		by_slot[slot_id] = float(by_slot.get(slot_id, 0.0)) + amount
	return {
		"donation_count": records.size(),
		"total_amount": total_amount,
		"total_prestige": total_prestige,
		"by_resource": by_resource,
		"by_slot": by_slot,
		"records": records
	}

func palace_donation_total_for_slot(state: Node, cycle_id: String, slot_id: String) -> Dictionary:
	var records: Array[Dictionary] = palace_donation_records_for_cycle_slot(state, cycle_id, slot_id)
	var total_amount: float = 0.0
	var total_prestige: float = 0.0
	for record: Dictionary in records:
		total_amount += float(record.get("amount", 0.0))
		total_prestige += float(record.get("prestige_gain", 0.0))
	return {"donation_count": records.size(), "amount": total_amount, "prestige": total_prestige, "records": records}

func can_donate_palace_need(state: Node, slot_id: String, amount: float) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "Palace state is not connected."}
	var raw_row: Dictionary = palace_ruler_demand_raw_row_by_slot(state, slot_id)
	if raw_row.is_empty():
		return {"ok": false, "reason": "Unknown court-need slot: " + slot_id + "."}
	var resource_id: String = String(raw_row.get("resource_id", ""))
	if resource_id == "":
		return {"ok": false, "reason": "Court need row is missing a valid resource."}
	if amount <= 0.001:
		return {"ok": false, "reason": "Choose a positive donation amount."}
	var free_value: float = float(state.call("free_stock_after_reserves", resource_id))
	if free_value + 0.001 < amount:
		return {"ok": false, "reason": "Need " + _format_amount(state, amount - free_value) + " more free " + _resource_name(state, resource_id) + " after reserves."}
	var base_value: float = _resource_base_value(state, resource_id)
	return {"ok": true, "reason": "Ready to donate " + _format_amount(state, amount) + " " + _resource_name(state, resource_id) + " for +" + _format_amount(state, amount * base_value) + " Prestige.", "prestige_gain": amount * base_value}

func donate_palace_need(state: Node, slot_id: String, amount: float) -> Dictionary:
	var status: Dictionary = can_donate_palace_need(state, slot_id, amount)
	if not bool(status.get("ok", false)):
		_append_report(state, "Court need donation failed: " + String(status.get("reason", "Unknown reason.")))
		_emit_state_changed(state)
		return status
	var raw_row: Dictionary = palace_ruler_demand_raw_row_by_slot(state, slot_id)
	var resource_id: String = String(raw_row.get("resource_id", ""))
	var free_before: float = float(state.call("free_stock_after_reserves", resource_id))
	var stored_before: float = _stock(state, resource_id)
	var base_value: float = _resource_base_value(state, resource_id)
	var prestige_gain: float = snappedf(amount * base_value, 0.01)
	_add_stock(state, resource_id, -amount)
	var record: Dictionary = {
		"source_id": "court_need_donation",
		"cycle_id": palace_ruler_demand_cycle_id(state),
		"slot": slot_id,
		"slot_name": String(raw_row.get("slot_name", "Court need")),
		"resource_id": resource_id,
		"resource_name": _resource_name(state, resource_id),
		"amount": amount,
		"base_value": base_value,
		"prestige_gain": prestige_gain,
		"donated_veintena": _current_veintena_value(state),
		"free_before_donation": free_before,
		"stored_before_donation": stored_before
	}
	var donations_variant: Variant = _palace_dictionary_array(state, "palace_ruler_demand_donations")
	var donations: Array = []
	if donations_variant is Array:
		donations = donations_variant as Array
	donations.append(record.duplicate(true))
	_set_palace_dictionary_array(state, "palace_ruler_demand_donations", donations)
	state.call("add_player_prestige", prestige_gain, "court_need_donation", "Donated " + _format_amount(state, amount) + " " + _resource_name(state, resource_id) + " to a court need.", record)
	_append_report(state, "Court need donation: " + _format_amount(state, amount) + " " + _resource_name(state, resource_id) + " for +" + _format_amount(state, prestige_gain) + " Prestige.")
	_emit_state_changed(state)
	return {"ok": true, "reason": "Donation recorded.", "record": record, "prestige_gain": prestige_gain}

func is_palace_ruler_demand_delivered(state: Node, slot_id: String) -> bool:
	return float(palace_donation_total_for_slot(state, palace_ruler_demand_cycle_id(state), slot_id).get("amount", 0.0)) > 0.001

func can_deliver_palace_ruler_demand(state: Node, slot_id: String) -> Dictionary:
	var raw_row: Dictionary = palace_ruler_demand_raw_row_by_slot(state, slot_id)
	if raw_row.is_empty():
		return {"ok": false, "reason": "Unknown court-need slot."}
	return can_donate_palace_need(state, slot_id, float(raw_row.get("amount", 0.0)))

func deliver_palace_ruler_demand(state: Node, slot_id: String) -> Dictionary:
	var raw_row: Dictionary = palace_ruler_demand_raw_row_by_slot(state, slot_id)
	if raw_row.is_empty():
		return {"ok": false, "reason": "Unknown court-need slot."}
	return donate_palace_need(state, slot_id, float(raw_row.get("amount", 0.0)))

func get_palace_ruler_demand_delivery_records(state: Node) -> Array[Dictionary]:
	return palace_donation_records_for_cycle(state)

func palace_ruler_demand_archive_row(state: Node, raw_row: Dictionary, cycle_id: String) -> Dictionary:
	var slot_id: String = String(raw_row.get("slot", ""))
	var donation: Dictionary = palace_donation_total_for_slot(state, cycle_id, slot_id)
	var donated_amount: float = float(donation.get("amount", 0.0))
	var resource_id: String = String(raw_row.get("resource_id", ""))
	return {
		"slot": slot_id,
		"slot_name": String(raw_row.get("slot_name", "Court need")),
		"resource_id": resource_id,
		"resource_name": _resource_name(state, resource_id),
		"needed_marker": float(raw_row.get("amount", 0.0)),
		"donated": donated_amount > 0.001,
		"donated_amount": donated_amount,
		"donated_prestige": float(donation.get("prestige", 0.0)),
		"donation_count": int(donation.get("donation_count", 0)),
		"status": "Donated" if donated_amount > 0.001 else "No donation"
	}

func palace_ruler_demand_records_for_cycle(state: Node, cycle_id: String) -> Array[Dictionary]:
	return palace_donation_records_for_cycle(state, cycle_id)

func get_palace_ruler_demand_cycle_archive(state: Node) -> Array[Dictionary]:
	var archive: Array[Dictionary] = []
	var demand_sets: Array[Dictionary] = palace_ruler_demand_sets()
	var current_cycle_id: String = palace_ruler_demand_cycle_id(state)
	for index: int in range(demand_sets.size()):
		var cycle: Dictionary = demand_sets[index] as Dictionary
		var cycle_id: String = String(cycle.get("id", ""))
		var window: Dictionary = palace_ruler_demand_cycle_window(index)
		var rows: Array[Dictionary] = []
		for row_variant: Variant in (cycle.get("demands", []) as Array):
			if row_variant is Dictionary:
				rows.append(palace_ruler_demand_archive_row(state, row_variant as Dictionary, cycle_id))
		var donation_summary: Dictionary = palace_need_donation_summary_for_cycle(state, cycle_id, rows)
		archive.append({
			"cycle_id": cycle_id,
			"title": String(cycle.get("title", "Court Need Cycle")),
			"veintena_band": String(cycle.get("veintena_band", "Prototype cycle")),
			"cycle_window": String(window.get("label", "Court need cycle")),
			"start_veintena": int(window.get("start_veintena", 1)),
			"end_veintena": int(window.get("end_veintena", 6)),
			"flavour": String(cycle.get("flavour", "")),
			"is_current": cycle_id == current_cycle_id,
			"rows": rows,
			"records": palace_ruler_demand_records_for_cycle(state, cycle_id),
			"donation_count": int(donation_summary.get("donation_count", 0)),
			"donated_prestige": float(donation_summary.get("total_prestige", 0.0)),
			"donated_slots": int(donation_summary.get("donated_slots", 0)),
			"total_slots": int(donation_summary.get("total_slots", rows.size()))
		})
	return archive

func palace_need_donation_summary_for_cycle(state: Node, cycle_id: String, rows: Array[Dictionary] = []) -> Dictionary:
	var total: Dictionary = palace_donation_total_for_cycle(state, cycle_id)
	var donated_slots: int = 0
	var total_slots: int = rows.size()
	for row: Dictionary in rows:
		if bool(row.get("donated", false)):
			donated_slots += 1
	return {
		"label": "Prestige +" + _format_amount(state, float(total.get("total_prestige", 0.0))),
		"detail": str(int(total.get("donation_count", 0))) + " donations made across " + str(donated_slots) + " / " + str(total_slots) + " visible court needs.",
		"donation_count": int(total.get("donation_count", 0)),
		"total_amount": float(total.get("total_amount", 0.0)),
		"total_prestige": float(total.get("total_prestige", 0.0)),
		"donated_slots": donated_slots,
		"total_slots": total_slots,
		"records": total.get("records", []) as Array
	}

func get_palace_ruler_demand_completion_summary(state: Node) -> Dictionary:
	var rows: Array[Dictionary] = []
	for row_variant: Variant in (current_palace_ruler_demand_set(state).get("demands", []) as Array):
		if row_variant is Dictionary:
			rows.append(palace_ruler_demand_row(state, row_variant as Dictionary))
	return palace_need_donation_summary_for_cycle(state, palace_ruler_demand_cycle_id(state), rows)

func palace_ruler_demand_row(state: Node, raw_row: Dictionary) -> Dictionary:
	var slot_id: String = String(raw_row.get("slot", ""))
	var resource_id: String = String(raw_row.get("resource_id", ""))
	var need_marker: float = float(raw_row.get("amount", 0.0))
	var stored: float = _stock(state, resource_id)
	var free_value: float = float(state.call("free_stock_after_reserves", resource_id))
	var base_value: float = _resource_base_value(state, resource_id)
	var donation: Dictionary = palace_donation_total_for_slot(state, palace_ruler_demand_cycle_id(state), slot_id)
	var donated_amount: float = float(donation.get("amount", 0.0))
	var donated_prestige: float = float(donation.get("prestige", 0.0))
	var can_donate_status: Dictionary = can_donate_palace_need(state, slot_id, minf(maxf(1.0, need_marker), free_value)) if free_value > 0.001 else {"ok": false, "reason": "No free stock available after reserves."}
	return {
		"slot": slot_id,
		"slot_name": String(raw_row.get("slot_name", "Court need")),
		"resource_id": resource_id,
		"resource_name": _resource_name(state, resource_id),
		"requested": need_marker,
		"needed_marker": need_marker,
		"stored": stored,
		"free_after_reserves": free_value,
		"shortfall": 0.0,
		"ready": free_value > 0.001,
		"delivered": donated_amount > 0.001,
		"can_deliver": free_value > 0.001,
		"can_donate": free_value > 0.001,
		"delivery_status": String(can_donate_status.get("reason", "")),
		"donation_status": String(can_donate_status.get("reason", "")),
		"delivered_amount": donated_amount,
		"donated_amount": donated_amount,
		"delivered_veintena": 0,
		"delivery_quality": "",
		"donated_prestige": donated_prestige,
		"base_value": base_value,
		"prestige_for_need_marker": need_marker * base_value,
		"max_donation": free_value,
		"status": "Donated " + _format_amount(state, donated_amount) if donated_amount > 0.001 else ("Open need" if free_value > 0.001 else "No free stock"),
		"quality_hint": "Prestige = donated amount × base value (" + _format_amount(state, base_value) + ").",
		"note": String(raw_row.get("note", "Court-facing need."))
	}

func get_palace_ruler_demands_summary(state: Node) -> Dictionary:
	var demand_sets: Array[Dictionary] = palace_ruler_demand_sets()
	var selected_index: int = current_palace_ruler_demand_index(state)
	var selected: Dictionary = demand_sets[selected_index] if demand_sets.size() > 0 else {}
	var rows: Array[Dictionary] = []
	var open_count: int = 0
	var donated_slot_count: int = 0
	var total_count: int = 0
	var total_need_marker_value: float = 0.0
	var total_free_matching_value: float = 0.0
	var raw_rows: Array = selected.get("demands", []) as Array
	for row_variant: Variant in raw_rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = palace_ruler_demand_row(state, row_variant as Dictionary)
		rows.append(row)
		total_count += 1
		if bool(row.get("delivered", false)):
			donated_slot_count += 1
		if bool(row.get("can_donate", false)):
			open_count += 1
		total_need_marker_value += float(row.get("prestige_for_need_marker", 0.0))
		total_free_matching_value += float(row.get("free_after_reserves", 0.0)) * float(row.get("base_value", 1.0))
	var donation_summary: Dictionary = palace_need_donation_summary_for_cycle(state, String(selected.get("id", "")), rows)
	var deadline: Dictionary = palace_ruler_demand_deadline_summary(state, selected_index)
	var donated_prestige: float = float(donation_summary.get("total_prestige", 0.0))
	var headline: String = "Court needs: " + str(open_count) + " goods available to donate; this cycle has generated +" + _format_amount(state, donated_prestige) + " Prestige. Deadline: " + String(deadline.get("urgency", "Time remains")) + "."
	if total_count <= 0:
		headline = "Court needs have no active rows."
	return {
		"schema_version": "palace_court_needs_v0_43_11",
		"active": true,
		"donation_enabled": true,
		"delivery_enabled": false,
		"current_veintena": _current_veintena_value(state),
		"cycle_index": selected_index,
		"cycle_id": String(selected.get("id", "")),
		"title": String(selected.get("title", "Current Court Needs")),
		"veintena_band": String(selected.get("veintena_band", "Prototype cycle")),
		"cycle_window": String(deadline.get("headline", "Court need cycle")),
		"cycle_start_veintena": int(deadline.get("start_veintena", 1)),
		"cycle_end_veintena": int(deadline.get("end_veintena", 6)),
		"veintenas_remaining": int(deadline.get("veintenas_remaining", 0)),
		"urgency_label": String(deadline.get("urgency", "Time remains")),
		"deadline_summary": deadline,
		"flavour": String(selected.get("flavour", "The court needs goods; donating needed goods creates public prestige.")),
		"rows": rows,
		"ready_count": open_count,
		"delivered_count": donated_slot_count,
		"donated_slot_count": donated_slot_count,
		"total_count": total_count,
		"headline": headline,
		"completion_label": str(donated_slot_count) + " / " + str(total_count) + " needs donated to",
		"donation_label": str(donated_slot_count) + " / " + str(total_count) + " needs donated to",
		"completion_quality": "Prestige +" + _format_amount(state, donated_prestige),
		"donation_prestige_label": "Prestige +" + _format_amount(state, donated_prestige),
		"completion_detail": String(donation_summary.get("detail", "No donations yet.")),
		"completion_summary": donation_summary,
		"readiness_label": str(open_count) + " needs have free stock available",
		"delivery_records": get_palace_ruler_demand_delivery_records(state),
		"donation_records": get_palace_ruler_demand_delivery_records(state),
		"cycle_archive": get_palace_ruler_demand_cycle_archive(state),
		"total_requested_value": total_need_marker_value,
		"total_free_matching_value": total_free_matching_value,
		"total_donated_prestige": donated_prestige,
		"player_prestige": _player_prestige_value(state),
		"mechanics_note": "Court needs are donation opportunities. Donating a needed good grants Prestige equal to donated amount × that good's base value. Prestige is score only and is never spent. No royal favour, local stability or palace-route credit is created."
	}


func get_palace_summary(state: Node) -> Dictionary:
	if state == null:
		return {
			"schema_version": "palace_court_needs_v0_36",
			"dedicated": false,
			"dedicated_god": "",
			"dedicated_god_name": "None",
			"route_name": "No dedication"
		}
	var dedicated_god: String = String(state.call("get_palace_dedicated_god")) if state.has_method("get_palace_dedicated_god") else get_palace_dedicated_god(state)
	var dedicated: bool = dedicated_god != ""
	var route_name: String = "No dedication"
	var god_name: String = "None"
	if dedicated:
		route_name = String(state.call("get_palace_route_name", dedicated_god)) if state.has_method("get_palace_route_name") else get_palace_route_name(dedicated_god)
		god_name = String(state.call("_god_display_name", dedicated_god)) if state.has_method("_god_display_name") else god_display_name(dedicated_god)
	var campaign_state: Variant = state.call("_get_campaign_state") if state.has_method("_get_campaign_state") else null
	var last_maintenance_report: Array[String] = []
	if campaign_state != null and campaign_state.has_method("get_last_palace_maintenance_report_copy"):
		last_maintenance_report = campaign_state.call("get_last_palace_maintenance_report_copy") as Array[String]
	return {
		"schema_version": "palace_court_needs_v0_36",
		"palace_level": int(state.call("get_palace_level")) if state.has_method("get_palace_level") else get_palace_level(state),
		"dedicated": dedicated,
		"dedicated_god": dedicated_god,
		"dedicated_god_name": god_name,
		"route_name": route_name,
		"power_summary": String(state.call("get_palace_route_power_summary", dedicated_god)) if state.has_method("get_palace_route_power_summary") else get_palace_route_power_summary(dedicated_god),
		"dedication_routes": state.call("get_palace_dedication_routes") if state.has_method("get_palace_dedication_routes") else get_palace_dedication_routes(state),
		"structure_tree_shell": state.call("get_palace_structure_tree_shell", dedicated_god) if state.has_method("get_palace_structure_tree_shell") else {},
		"built_structures": state.call("get_built_palace_structure_ids") if state.has_method("get_built_palace_structure_ids") else get_built_palace_structure_ids(state),
		"active_structures": state.call("get_active_palace_structure_ids") if state.has_method("get_active_palace_structure_ids") else [],
		"inactive_structures": state.call("get_inactive_palace_structure_ids") if state.has_method("get_inactive_palace_structure_ids") else [],
		"built_structure_count": int((state.call("get_built_palace_structure_ids") as Array).size()) if state.has_method("get_built_palace_structure_ids") else get_built_palace_structure_ids(state).size(),
		"active_structure_count": int((state.call("get_active_palace_structure_ids") as Array).size()) if state.has_method("get_active_palace_structure_ids") else 0,
		"inactive_structure_count": int((state.call("get_inactive_palace_structure_ids") as Array).size()) if state.has_method("get_inactive_palace_structure_ids") else 0,
		"total_maintenance": state.call("get_palace_total_maintenance") if state.has_method("get_palace_total_maintenance") else get_palace_total_maintenance(state),
		"required_staff": state.call("get_palace_required_staff") if state.has_method("get_palace_required_staff") else get_palace_required_staff(state),
		"staff_capacity": state.call("get_palace_staff_capacity") if state.has_method("get_palace_staff_capacity") else get_palace_staff_capacity(state),
		"staff_summary": state.call("get_palace_staff_summary") if state.has_method("get_palace_staff_summary") else get_palace_staff_summary(state),
		"palace_operation_preview": state.call("get_palace_structure_operation_preview") if state.has_method("get_palace_structure_operation_preview") else get_palace_structure_operation_preview(state),
		"last_palace_maintenance_report": last_maintenance_report,
		"authority_summary": state.call("get_palace_authority_summary") if state.has_method("get_palace_authority_summary") else get_palace_authority_summary(state),
		"tlaloc_forecast": state.call("get_tlaloc_natural_calendar_forecast") if state.has_method("get_tlaloc_natural_calendar_forecast") else {},
		"tezcatlipoca_pressure": state.call("get_tezcatlipoca_pressure_overview") if state.has_method("get_tezcatlipoca_pressure_overview") else {},
		"quetzalcoatl_legitimacy": state.call("get_quetzalcoatl_legitimacy_overview") if state.has_method("get_quetzalcoatl_legitimacy_overview") else {},
		"ruler_demands": state.call("get_palace_ruler_demands_summary") if state.has_method("get_palace_ruler_demands_summary") else {},
		"authority_status": String((state.call("get_palace_authority_summary") as Dictionary).get("headline", "Palace authority not connected.")) if state.has_method("get_palace_authority_summary") else "Palace authority not connected.",
		"ruler_demand_status": String((state.call("get_palace_ruler_demands_summary") as Dictionary).get("headline", "Court needs donation prototype active.")) if state.has_method("get_palace_ruler_demands_summary") else "Court needs donation prototype active.",
		"prestige_summary": state.call("get_prestige_summary") if state.has_method("get_prestige_summary") else {},
		"flower_war_gate_enabled": bool(state.call("is_flower_war_palace_gate_enabled")) if state.has_method("is_flower_war_palace_gate_enabled") else is_flower_war_palace_gate_enabled(state),
		"flower_war_gate_passed": bool(state.call("flower_war_palace_gate_passed")) if state.has_method("flower_war_palace_gate_passed") else flower_war_palace_gate_passed(state),
		"flower_war_gate_status": String(state.call("flower_war_palace_gate_status_text")) if state.has_method("flower_war_palace_gate_status_text") else flower_war_palace_gate_status_text(state),
		"implementation_note": "v0.36 reframes court needs as court needs. Donating needed goods grants Prestige based on donated amount × resource base value. Prestige is score only and is never spent."
	}


# -----------------------------------------------------------------------------
# CampaignState-first palace access helpers
# -----------------------------------------------------------------------------

func _campaign_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null

func _palace_string(state: Node, property_name: String, default_value: String = "") -> String:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		match property_name:
			"player_palace_dedicated_god":
				if runtime_state.has_method("get_palace_dedicated_god_value"):
					return String(runtime_state.call("get_palace_dedicated_god_value"))
			_:
				var runtime_value: Variant = runtime_state.get(property_name)
				if runtime_value != null:
					return String(runtime_value)
	if state != null:
		var fallback: Variant = state.get(property_name)
		if fallback != null:
			return String(fallback)
	return default_value

func _palace_bool(state: Node, property_name: String, default_value: bool = false) -> bool:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		match property_name:
			"flower_war_palace_gate_enabled":
				if runtime_state.has_method("get_flower_war_palace_gate_enabled_value"):
					return bool(runtime_state.call("get_flower_war_palace_gate_enabled_value"))
			_:
				var runtime_value: Variant = runtime_state.get(property_name)
				if runtime_value != null:
					return bool(runtime_value)
	if state != null:
		var fallback: Variant = state.get(property_name)
		if fallback != null:
			return bool(fallback)
	return default_value

func _palace_dictionary(state: Node, property_name: String) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		match property_name:
			"palace_built_structures":
				if runtime_state.has_method("get_palace_built_structures_copy"):
					return runtime_state.call("get_palace_built_structures_copy") as Dictionary
			"palace_structure_runtime_statuses":
				if runtime_state.has_method("get_palace_structure_runtime_statuses_copy"):
					return runtime_state.call("get_palace_structure_runtime_statuses_copy") as Dictionary
			"palace_delivered_ruler_demands":
				if runtime_state.has_method("get_palace_delivered_ruler_demands_copy"):
					return runtime_state.call("get_palace_delivered_ruler_demands_copy") as Dictionary
			"estate_stockpiles":
				if runtime_state.has_method("get_estate_stockpiles_copy"):
					return runtime_state.call("get_estate_stockpiles_copy") as Dictionary
			_:
				var runtime_value: Variant = runtime_state.get(property_name)
				if runtime_value is Dictionary:
					return (runtime_value as Dictionary).duplicate(true)
	if state != null:
		var fallback: Variant = state.get(property_name)
		if fallback is Dictionary:
			return (fallback as Dictionary).duplicate(true)
	return {}

func _palace_dictionary_array(state: Node, property_name: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var runtime_state: RefCounted = _campaign_state(state)
	var raw_value: Variant = null
	if runtime_state != null:
		match property_name:
			"palace_ruler_demand_donations":
				if runtime_state.has_method("get_palace_ruler_demand_donations_copy"):
					raw_value = runtime_state.call("get_palace_ruler_demand_donations_copy")
			_:
				raw_value = runtime_state.get(property_name)
	if raw_value == null and state != null:
		raw_value = state.get(property_name)
	if raw_value is Array:
		for item: Variant in raw_value as Array:
			if item is Dictionary:
				output.append((item as Dictionary).duplicate(true))
	return output

func _palace_string_array(state: Node, property_name: String) -> Array[String]:
	var output: Array[String] = []
	var runtime_state: RefCounted = _campaign_state(state)
	var raw_value: Variant = null
	if runtime_state != null:
		match property_name:
			"last_palace_maintenance_report":
				if runtime_state.has_method("get_last_palace_maintenance_report_copy"):
					raw_value = runtime_state.call("get_last_palace_maintenance_report_copy")
			_:
				raw_value = runtime_state.get(property_name)
	if raw_value == null and state != null:
		raw_value = state.get(property_name)
	if raw_value is Array:
		for item: Variant in raw_value as Array:
			output.append(String(item))
	return output

func _set_palace_value(state: Node, property_name: String, value: Variant) -> void:
	if state == null:
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		match property_name:
			"player_palace_dedicated_god":
				if runtime_state.has_method("set_palace_dedicated_god_value"):
					runtime_state.call("set_palace_dedicated_god_value", String(value))
					_mirror_palace_state(state)
					return
			"flower_war_palace_gate_enabled":
				if runtime_state.has_method("set_flower_war_palace_gate_enabled_value"):
					runtime_state.call("set_flower_war_palace_gate_enabled_value", bool(value))
					_mirror_palace_state(state)
					return
	state.set(property_name, value)

func _set_palace_dictionary(state: Node, property_name: String, value: Dictionary) -> void:
	if state == null:
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		match property_name:
			"palace_built_structures":
				if runtime_state.has_method("set_palace_built_structures"):
					runtime_state.call("set_palace_built_structures", value)
					_mirror_palace_state(state)
					return
			"palace_structure_runtime_statuses":
				if runtime_state.has_method("set_palace_structure_runtime_statuses"):
					runtime_state.call("set_palace_structure_runtime_statuses", value)
					_mirror_palace_state(state)
					return
			"palace_delivered_ruler_demands":
				if runtime_state.has_method("set_palace_delivered_ruler_demands"):
					runtime_state.call("set_palace_delivered_ruler_demands", value)
					_mirror_palace_state(state)
					return
			"estate_stockpiles":
				if runtime_state.has_method("set_estate_stockpiles_values"):
					runtime_state.call("set_estate_stockpiles_values", value)
					_mirror_stockpiles(state)
					return
	state.set(property_name, value.duplicate(true))

func _set_palace_dictionary_array(state: Node, property_name: String, value: Array) -> void:
	if state == null:
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		match property_name:
			"palace_ruler_demand_donations":
				if runtime_state.has_method("set_palace_ruler_demand_donations"):
					runtime_state.call("set_palace_ruler_demand_donations", value)
					_mirror_palace_state(state)
					return
	state.set(property_name, value.duplicate(true))

func _set_palace_string_array(state: Node, property_name: String, value: Array) -> void:
	if state == null:
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		match property_name:
			"last_palace_maintenance_report":
				if runtime_state.has_method("set_last_palace_maintenance_report"):
					runtime_state.call("set_last_palace_maintenance_report", value)
					_mirror_palace_state(state)
					return
	state.set(property_name, value.duplicate())

func _estate_stockpiles_copy(state: Node) -> Dictionary:
	return _palace_dictionary(state, "estate_stockpiles")

func _stock(state: Node, resource_id: String) -> float:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_estate_stock"):
		return float(runtime_state.call("get_estate_stock", resource_id))
	if state != null and state.has_method("_stock"):
		return float(state.call("_stock", resource_id))
	return float(_estate_stockpiles_copy(state).get(resource_id, 0.0))

func _add_stock(state: Node, resource_id: String, amount: float) -> void:
	if state == null:
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("add_estate_stock"):
		runtime_state.call("add_estate_stock", resource_id, amount)
		_mirror_stockpiles(state)
		return
	if state.has_method("_add_stock"):
		state.call("_add_stock", resource_id, amount)

func _current_veintena_value(state: Node) -> int:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_current_veintena_value"):
		return int(runtime_state.call("get_current_veintena_value"))
	if state != null and state.has_method("get_current_veintena"):
		return int(state.call("get_current_veintena"))
	if state != null:
		return int(state.get("current_veintena"))
	return 1

func _player_prestige_value(state: Node) -> float:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_player_prestige_value"):
		return float(runtime_state.call("get_player_prestige_value"))
	if state != null:
		return float(state.get("player_prestige"))
	return 0.0

func _mirror_palace_state(state: Node) -> void:
	if state != null and state.has_method("_mirror_palace_state_from_campaign_state_to_legacy"):
		state.call("_mirror_palace_state_from_campaign_state_to_legacy")
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("mirror_palace_state_to_game_state"):
		runtime_state.call("mirror_palace_state_to_game_state", state)

func _mirror_stockpiles(state: Node) -> void:
	if state != null and state.has_method("_mirror_stockpile_compatibility_from_campaign_state"):
		state.call("_mirror_stockpile_compatibility_from_campaign_state")
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("mirror_stockpiles_to_game_state"):
		runtime_state.call("mirror_stockpiles_to_game_state", state)

func _copy_stockpile_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = float(source[key_variant])
	return output

func _add_dictionary_amounts(target: Dictionary, amounts: Dictionary) -> void:
	for key_variant: Variant in amounts.keys():
		var key: String = String(key_variant)
		target[key] = float(target.get(key, 0.0)) + float(amounts[key_variant])

func _resource_base_value(state: Node, resource_id: String) -> float:
	if state != null and state.has_method("_resource_base_value"):
		return float(state.call("_resource_base_value", resource_id))
	return 1.0

func _format_amount(state: Node, value: float) -> String:
	if state != null and state.has_method("_format_amount"):
		return String(state.call("_format_amount", value))
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))

func _resource_name(state: Node, resource_id: String) -> String:
	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))
	return resource_id.replace("_", " ").capitalize()

func _labour_group_name(state: Node, group_id: String) -> String:
	if state != null and state.has_method("_labour_group_name"):
		return String(state.call("_labour_group_name", group_id))
	return group_id.replace("_", " ").capitalize()

func _append_report(state: Node, text: String) -> void:
	if state == null or text.strip_edges() == "":
		return
	if state.has_method("_append_report_line"):
		state.call("_append_report_line", text)
		return
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("append_report_line"):
		runtime_state.call("append_report_line", text)
		if state.has_method("_mirror_calendar_report_compatibility_from_campaign_state"):
			state.call("_mirror_calendar_report_compatibility_from_campaign_state")
		return
	var report_variant: Variant = state.get("last_report")
	if report_variant is Array:
		var report: Array = report_variant as Array
		report.append(text)
		state.set("last_report", report)

func _emit_state_changed(state: Node) -> void:
	if state != null and state.has_signal("state_changed"):
		state.emit_signal("state_changed")
