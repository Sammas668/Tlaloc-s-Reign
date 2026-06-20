# PalaceRouteOverviewSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/PalaceRouteOverviewSystem.gd
#
# v0.45.7 extraction target.
# Owns information-only palace route overview logic for Tlaloc, Tezcatlipoca
# and Quetzalcoatl. TRGameState remains the public UI API.
class_name PalaceRouteOverviewSystem
extends RefCounted

const GOD_TLALOC: String = "tlaloc"
const GOD_HUITZILOPOCHTLI: String = "huitzilopochtli"
const GOD_TEZCATLIPOCA: String = "tezcatlipoca"
const GOD_QUETZALCOATL: String = "quetzalcoatl"

# -----------------------------------------------------------------------------
# Shared state access helpers
# -----------------------------------------------------------------------------

func _palace_dedicated_god(state: Node) -> String:
	if state == null:
		return ""
	if state.has_method("get_palace_dedicated_god"):
		return String(state.call("get_palace_dedicated_god"))
	return String(state.get("player_palace_dedicated_god"))

func _palace_structure_runtime_statuses(state: Node) -> Dictionary:
	if state == null:
		return {}
	if state.has_method("get_palace_structure_runtime_statuses"):
		var value: Variant = state.call("get_palace_structure_runtime_statuses")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	var raw: Variant = state.get("palace_structure_runtime_statuses")
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}

func _palace_built_structure_ids_in_tree_order(state: Node, god_id: String) -> Array[String]:
	var output: Array[String] = []
	if state == null:
		return output
	if state.has_method("_palace_built_structure_ids_in_tree_order"):
		var value: Variant = state.call("_palace_built_structure_ids_in_tree_order", god_id)
		if value is Array:
			for item: Variant in value:
				output.append(String(item))
	return output

func _palace_structure_by_id(state: Node, structure_id: String, god_id: String) -> Dictionary:
	if state == null:
		return {}
	if state.has_method("_palace_structure_by_id"):
		var value: Variant = state.call("_palace_structure_by_id", structure_id, god_id)
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}

func _current_veintena(state: Node) -> int:
	if state == null:
		return 1
	if state.has_method("get_current_veintena"):
		return int(state.call("get_current_veintena"))
	return int(state.get("current_veintena"))

func _resource_name(state: Node, resource_id: String) -> String:
	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))
	return resource_id.capitalize()

func _market_resolution(state: Node) -> Dictionary:
	if state != null and state.has_method("estimate_market_resolution"):
		var value: Variant = state.call("estimate_market_resolution")
		if value is Dictionary:
			return value as Dictionary
	return {}

func _rival_pressure_hooks(state: Node, detail_tier: int) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if state != null and state.has_method("get_rival_pressure_hooks"):
		var value: Variant = state.call("get_rival_pressure_hooks", detail_tier)
		if value is Array:
			for item: Variant in value:
				if item is Dictionary:
					output.append((item as Dictionary).duplicate(true))
	return output

func _format_amount(state: Node, value: float) -> String:
	if state != null and state.has_method("_format_amount"):
		return String(state.call("_format_amount", value))
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))

# -----------------------------------------------------------------------------
# Tlaloc natural calendar forecast
# -----------------------------------------------------------------------------

func tlaloc_controlled_natural_pressure_events() -> Array[Dictionary]:
	# v0.28 uses a deterministic test calendar instead of a random natural-event
	# system. These events do not apply gameplay effects yet; they exist so the
	# Tlaloc Palace route can prove its information/forecasting identity safely.
	return [
		{
			"id": "dry_wind_signs",
			"target_veintena": 4,
			"name": "Dry Wind Signs",
			"category": "Drought pressure",
			"summary": "Fields and canals show early dry-season stress.",
			"severity": "Moderate",
			"affected_goods": ["maize", "cacao"],
			"duration": "2 Veintenas",
			"preparation": "Protect maize stores, avoid over-selling food, and prepare rain rites or irrigation responses."
		},
		{
			"id": "heavy_rain_risk",
			"target_veintena": 7,
			"name": "Heavy Rain Risk",
			"category": "Flood / water pressure",
			"summary": "Lake and canal signs suggest a heavy rain period.",
			"severity": "Light to moderate",
			"affected_goods": ["wood", "maize"],
			"duration": "1 Veintena",
			"preparation": "Protect wood stocks, watch canal-linked production, and prepare for temporary field disruption."
		},
		{
			"id": "field_pest_pressure",
			"target_veintena": 10,
			"name": "Field Pest Pressure",
			"category": "Crop / pest pressure",
			"summary": "Field samples and omen records suggest pest pressure in the growing cycle.",
			"severity": "Moderate",
			"affected_goods": ["maize", "cotton"],
			"duration": "2–3 Veintenas",
			"preparation": "Build food buffer, avoid relying on one crop chain, and keep tools available for field response."
		},
		{
			"id": "clear_sky_window",
			"target_veintena": 13,
			"name": "Clear Sky Window",
			"category": "Favourable weather window",
			"summary": "The sky-reading basin suggests a calmer period for hauling, drying and outdoor work.",
			"severity": "Favourable",
			"affected_goods": ["wood", "cotton", "cloth"],
			"duration": "1–2 Veintenas",
			"preparation": "Plan construction and transport-heavy production while weather pressure is low."
		},
		{
			"id": "late_water_warning",
			"target_veintena": 16,
			"name": "Late Water Warning",
			"category": "Rain / canal uncertainty",
			"summary": "Late-year water signs are unstable and could disrupt estate timing.",
			"severity": "Uncertain",
			"affected_goods": ["maize", "tools"],
			"duration": "Unknown",
			"preparation": "Keep reserves flexible and avoid spending all tools before late-year obligations are known."
		}
	]

func veintena_distance_to(state: Node, target_veintena: int) -> int:
	var target: int = clampi(target_veintena, 1, 18)
	var distance: int = target - _current_veintena(state)
	if distance < 0:
		distance += 18
	return distance

func tlaloc_active_structure_tier(state: Node) -> int:
	if _palace_dedicated_god(state) != GOD_TLALOC:
		return 0
	var highest: int = 0
	var statuses: Dictionary = _palace_structure_runtime_statuses(state)
	for structure_id: String in _palace_built_structure_ids_in_tree_order(state, GOD_TLALOC):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(state, structure_id, GOD_TLALOC)
		if structure.is_empty():
			continue
		highest = maxi(highest, int(structure.get("tier", 1)))
	return highest

func tlaloc_active_structure_names(state: Node) -> Array[String]:
	var names: Array[String] = []
	if _palace_dedicated_god(state) != GOD_TLALOC:
		return names
	var statuses: Dictionary = _palace_structure_runtime_statuses(state)
	for structure_id: String in _palace_built_structure_ids_in_tree_order(state, GOD_TLALOC):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(state, structure_id, GOD_TLALOC)
		if not structure.is_empty():
			names.append(String(structure.get("name", structure_id)))
	return names

func tlaloc_forecast_range_for_tier(tier: int) -> int:
	match tier:
		1:
			return 3
		2:
			return 6
		3:
			return 10
		4:
			return 18
	return 0

func tlaloc_forecast_detail_label(tier: int) -> String:
	match tier:
		1:
			return "Basic near warning"
		2:
			return "Extended warning"
		3:
			return "Detailed forecast"
		4:
			return "Deep natural calendar"
	return "Dormant"

func format_veintena_distance(distance: int) -> String:
	if distance <= 0:
		return "Current Veintena"
	if distance == 1:
		return "Next Veintena"
	return "In " + str(distance) + " Veintenas"

func format_resource_id_list(state: Node, resource_ids: Array) -> String:
	var parts: Array[String] = []
	for resource_variant: Variant in resource_ids:
		parts.append(_resource_name(state, String(resource_variant)))
	if parts.is_empty():
		return "Unknown"
	return ", ".join(parts)

func tlaloc_forecast_row(state: Node, event: Dictionary, detail_tier: int, distance: int) -> Dictionary:
	var name: String = "Unclear natural pressure"
	var category: String = "Natural pressure"
	var severity: String = "Hidden"
	var affected_goods: String = "Hidden"
	var duration: String = "Hidden"
	var preparation: String = "Build active Tlaloc structures to reveal preparation advice."
	var summary_text: String = "The palace senses pressure in the natural calendar, but details are still unclear."
	if detail_tier >= 1:
		category = String(event.get("category", category))
		summary_text = String(event.get("summary", summary_text))
	if detail_tier >= 2:
		name = String(event.get("name", name))
	if detail_tier >= 3:
		severity = String(event.get("severity", severity))
		affected_goods = format_resource_id_list(state, event.get("affected_goods", []) as Array)
		duration = String(event.get("duration", duration))
	if detail_tier >= 4:
		preparation = String(event.get("preparation", preparation))
	return {
		"id": String(event.get("id", "natural_pressure")),
		"name": name,
		"category": category,
		"timing": format_veintena_distance(distance),
		"turns_until": distance,
		"target_veintena": int(event.get("target_veintena", 1)),
		"summary": summary_text,
		"severity": severity,
		"affected_goods": affected_goods,
		"duration": duration,
		"preparation": preparation,
		"detail_tier": detail_tier
	}

func get_tlaloc_natural_calendar_forecast(state: Node) -> Dictionary:
	var dedicated: bool = _palace_dedicated_god(state) == GOD_TLALOC
	var detail_tier: int = tlaloc_active_structure_tier(state)
	var forecast_range: int = tlaloc_forecast_range_for_tier(detail_tier)
	var rows: Array[Dictionary] = []
	var hidden_count: int = 0
	for event: Dictionary in tlaloc_controlled_natural_pressure_events():
		var distance: int = veintena_distance_to(state, int(event.get("target_veintena", 1)))
		if dedicated and detail_tier > 0 and distance <= forecast_range:
			rows.append(tlaloc_forecast_row(state, event, detail_tier, distance))
		else:
			hidden_count += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("turns_until", 0)) < int(b.get("turns_until", 0))
	)
	var headline: String = "Tlaloc foresight unavailable"
	var summary_text: String = "Dedicate the Palace to Tlaloc, then build and maintain active Tlaloc structures to reveal natural pressure before rivals can react."
	if dedicated and detail_tier <= 0:
		headline = "Tlaloc foresight dormant"
		summary_text = "The palace is dedicated to Tlaloc, but no active Tlaloc palace structures are maintained and staffed this Veintena."
	elif dedicated and detail_tier > 0:
		headline = "Tlaloc Natural Calendar Foresight — " + tlaloc_forecast_detail_label(detail_tier)
		summary_text = "Active Tlaloc structures reveal natural pressures up to " + str(forecast_range) + " Veintenas ahead. This is a controlled prototype forecast; it does not apply event effects yet."
	return {
		"available": dedicated,
		"active": dedicated and detail_tier > 0,
		"detail_tier": detail_tier,
		"detail_label": tlaloc_forecast_detail_label(detail_tier),
		"forecast_range_veintenas": forecast_range,
		"current_veintena": _current_veintena(state),
		"headline": headline,
		"summary": summary_text,
		"active_structures": tlaloc_active_structure_names(state),
		"events": rows,
		"visible_event_count": rows.size(),
		"hidden_event_count": hidden_count,
		"mechanics_note": "Forecast rows are information only in v0.28. They do not yet alter production, markets, yields, disasters or rival behaviour."
	}

# -----------------------------------------------------------------------------
# Tezcatlipoca scarcity / intrigue overview
# -----------------------------------------------------------------------------

func tezcatlipoca_active_structure_tier(state: Node) -> int:
	if _palace_dedicated_god(state) != GOD_TEZCATLIPOCA:
		return 0
	var highest: int = 0
	var statuses: Dictionary = _palace_structure_runtime_statuses(state)
	for structure_id: String in _palace_built_structure_ids_in_tree_order(state, GOD_TEZCATLIPOCA):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(state, structure_id, GOD_TEZCATLIPOCA)
		if structure.is_empty():
			continue
		highest = maxi(highest, int(structure.get("tier", 1)))
	return highest

func tezcatlipoca_active_structure_names(state: Node) -> Array[String]:
	var names: Array[String] = []
	if _palace_dedicated_god(state) != GOD_TEZCATLIPOCA:
		return names
	var statuses: Dictionary = _palace_structure_runtime_statuses(state)
	for structure_id: String in _palace_built_structure_ids_in_tree_order(state, GOD_TEZCATLIPOCA):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(state, structure_id, GOD_TEZCATLIPOCA)
		if not structure.is_empty():
			names.append(String(structure.get("name", structure_id)))
	return names

func tezcatlipoca_pressure_detail_label(tier: int) -> String:
	match tier:
		1:
			return "First pressure signs"
		2:
			return "Named shortages and rivals"
		3:
			return "Leverage reading"
		4:
			return "Deep mirror council"
	return "Dormant"

func tezcatlipoca_market_pressure_limit(tier: int) -> int:
	match tier:
		1:
			return 2
		2:
			return 4
		3:
			return 6
		4:
			return 8
	return 0

func tezcatlipoca_pressure_score(good: Dictionary) -> float:
	var score: float = 0.0
	var label: String = String(good.get("label", ""))
	var coverage: float = float(good.get("coverage", 0.0))
	var current_value: float = float(good.get("current_value", good.get("projected_value", 0.0)))
	var base_value: float = maxf(0.01, float(good.get("base_value", 1.0)))
	match label:
		"Crisis":
			score += 100.0
		"Shortage":
			score += 70.0
		"Tight":
			score += 40.0
		"Abundant":
			score -= 20.0
	if coverage > 0.0:
		score += maxf(0.0, 3.0 - coverage) * 12.0
	score += maxf(0.0, (current_value / base_value) - 1.0) * 25.0
	return score

func tezcatlipoca_market_pressure_row(state: Node, good: Dictionary, detail_tier: int) -> Dictionary:
	var good_id: String = String(good.get("id", ""))
	var good_name: String = String(good.get("name", _resource_name(state, good_id)))
	var label: String = String(good.get("label", "Unknown"))
	var trend: String = String(good.get("trend", "Stable"))
	var coverage_text: String = "Hidden"
	var value_text: String = "Hidden"
	var leverage_text: String = "Pressure exists, but the mirror has not revealed a usable hook."
	var exposure_text: String = "Hidden"
	if detail_tier >= 2:
		coverage_text = _format_amount(state, float(good.get("coverage", 0.0)))
		exposure_text = label + " / " + trend
	if detail_tier >= 3:
		value_text = _format_amount(state, float(good.get("current_value", good.get("projected_value", 0.0))))
		leverage_text = "Future hook: watch this good for market pressure, rival procurement pressure or scarcity manipulation."
	if detail_tier >= 4:
		leverage_text = "Deep mirror hook: future Tezcatlipoca actions may pressure this good, exploit shortage, or turn rival demand against them."
	return {
		"id": good_id,
		"name": good_name,
		"pressure": label,
		"trend": trend,
		"coverage": coverage_text,
		"current_value": value_text,
		"exposure": exposure_text,
		"leverage": leverage_text,
		"score": tezcatlipoca_pressure_score(good),
		"detail_tier": detail_tier
	}

func tezcatlipoca_rival_pressure_hooks(state: Node, detail_tier: int) -> Array[Dictionary]:
	return _rival_pressure_hooks(state, detail_tier)

func get_tezcatlipoca_pressure_overview(state: Node) -> Dictionary:
	var dedicated: bool = _palace_dedicated_god(state) == GOD_TEZCATLIPOCA
	var detail_tier: int = tezcatlipoca_active_structure_tier(state)
	var market_rows: Array[Dictionary] = []
	if dedicated and detail_tier > 0:
		var goods: Array = _market_resolution(state).get("goods", []) as Array
		var pressure_goods: Array[Dictionary] = []
		for good_variant: Variant in goods:
			if not (good_variant is Dictionary):
				continue
			var good: Dictionary = good_variant as Dictionary
			var label: String = String(good.get("label", ""))
			var score: float = tezcatlipoca_pressure_score(good)
			if score > 0.0 or label == "Crisis" or label == "Shortage" or label == "Tight":
				pressure_goods.append(good)
		pressure_goods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return tezcatlipoca_pressure_score(a) > tezcatlipoca_pressure_score(b)
		)
		var limit: int = tezcatlipoca_market_pressure_limit(detail_tier)
		for index: int in range(mini(limit, pressure_goods.size())):
			market_rows.append(tezcatlipoca_market_pressure_row(state, pressure_goods[index], detail_tier))
	var headline: String = "Tezcatlipoca pressure unavailable"
	var summary_text: String = "Dedicate the Palace to Tezcatlipoca, then build and maintain active Tezcatlipoca structures to read scarcity, rival pressure and hidden market leverage."
	if dedicated and detail_tier <= 0:
		headline = "Tezcatlipoca pressure dormant"
		summary_text = "The palace is dedicated to Tezcatlipoca, but no active Tezcatlipoca palace structures are maintained and staffed this Veintena."
	elif dedicated and detail_tier > 0:
		headline = "Tezcatlipoca Scarcity Mirror — " + tezcatlipoca_pressure_detail_label(detail_tier)
		summary_text = "Active Tezcatlipoca structures reveal market pressure and rival vulnerability hooks. This is an information-only prototype; it does not manipulate goods, sabotage rivals or alter prices yet."
	var rival_rows: Array[Dictionary] = tezcatlipoca_rival_pressure_hooks(state, detail_tier)
	return {
		"available": dedicated,
		"active": dedicated and detail_tier > 0,
		"detail_tier": detail_tier,
		"detail_label": tezcatlipoca_pressure_detail_label(detail_tier),
		"headline": headline,
		"summary": summary_text,
		"active_structures": tezcatlipoca_active_structure_names(state),
		"market_pressure_rows": market_rows,
		"rival_pressure_rows": rival_rows,
		"visible_market_pressure_count": market_rows.size(),
		"visible_rival_pressure_count": rival_rows.size(),
		"mechanics_note": "Tezcatlipoca pressure rows are information-only in v0.29. They do not yet change market stock, prices, rival behaviour, sabotage, prestige or diplomacy."
	}

# -----------------------------------------------------------------------------
# Quetzalcoatl legitimacy overview
# -----------------------------------------------------------------------------

func quetzalcoatl_active_structure_tier(state: Node) -> int:
	if _palace_dedicated_god(state) != GOD_QUETZALCOATL:
		return 0
	var max_tier: int = 0
	var statuses: Dictionary = _palace_structure_runtime_statuses(state)
	for structure_id: String in _palace_built_structure_ids_in_tree_order(state, GOD_QUETZALCOATL):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(state, structure_id, GOD_QUETZALCOATL)
		max_tier = maxi(max_tier, int(structure.get("tier", structure.get("level", 0))))
	return max_tier

func quetzalcoatl_active_structure_names(state: Node) -> Array[String]:
	var names: Array[String] = []
	if _palace_dedicated_god(state) != GOD_QUETZALCOATL:
		return names
	var statuses: Dictionary = _palace_structure_runtime_statuses(state)
	for structure_id: String in _palace_built_structure_ids_in_tree_order(state, GOD_QUETZALCOATL):
		var status: Dictionary = statuses.get(structure_id, {}) as Dictionary
		if not bool(status.get("active", false)):
			continue
		var structure: Dictionary = _palace_structure_by_id(state, structure_id, GOD_QUETZALCOATL)
		if not structure.is_empty():
			names.append(String(structure.get("name", structure_id)))
	return names

func quetzalcoatl_detail_label(tier: int) -> String:
	match tier:
		1:
			return "Household legitimacy signs"
		2:
			return "Tribute credibility reading"
		3:
			return "Ruler-facing trust hooks"
		4:
			return "Great legitimacy court"
	return "Dormant"

func quetzalcoatl_legitimacy_rows(detail_tier: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if detail_tier <= 0:
		return rows
	var raw_rows: Array[Dictionary] = [
		{"id": "palace_order", "name": "Palace Order", "domain": "Court order and visible authority", "summary": "The palace can present itself as orderly, deliberate and ruler-facing.", "future_hook": "Future hook: improves palace-performance confidence and reduces ambiguity around obligations."},
		{"id": "tribute_credibility", "name": "Tribute Credibility", "domain": "Demand delivery and tribute reliability", "summary": "The house can make promised goods and delivered goods appear more credible to higher authority.", "future_hook": "Future hook: clearer demand delivery quality and better ruler-facing trust."},
		{"id": "recognition_route", "name": "Recognition Route", "domain": "Regional legitimacy and public reputation", "summary": "The palace can frame estate success as lawful, civilised and worthy of recognition.", "future_hook": "Future hook: supports future formal recognition once that system is designed."},
		{"id": "court_witness", "name": "Ruler Witness", "domain": "Agents, witnesses and formal reporting", "summary": "The palace is prepared to impress agents of higher authority and make obligations visible.", "future_hook": "Future hook: stronger effect on court presentation and formal recognition."}
	]
	var max_rows: int = 1
	if detail_tier >= 2:
		max_rows = 2
	if detail_tier >= 3:
		max_rows = 3
	if detail_tier >= 4:
		max_rows = 4
	for index: int in range(mini(max_rows, raw_rows.size())):
		var source: Dictionary = raw_rows[index]
		var row: Dictionary = {
			"id": String(source.get("id", "legitimacy")),
			"name": String(source.get("name", "Legitimacy")),
			"domain": "Hidden",
			"summary": "The palace shows signs of legitimacy, but the route has not revealed clear political hooks yet.",
			"future_hook": "Build higher active Quetzalcoatl structures to reveal future legitimacy and recognition hooks.",
			"detail_tier": detail_tier
		}
		if detail_tier >= 1:
			row["domain"] = String(source.get("domain", "Legitimacy"))
			row["summary"] = String(source.get("summary", row["summary"]))
		if detail_tier >= 3:
			row["future_hook"] = String(source.get("future_hook", row["future_hook"]))
		rows.append(row)
	return rows

func quetzalcoatl_obligation_rows(detail_tier: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if detail_tier <= 0:
		return rows
	var raw_rows: Array[Dictionary] = [
		{"id": "raw_demand", "name": "Raw Demand Credibility", "domain": "Maize, wood, cotton, cacao, obsidian", "summary": "Future court needs can be read as material obligations rather than vague court pressure.", "future_hook": "Future hook: improves clarity around the Raw court-need slot."},
		{"id": "processed_demand", "name": "Processed Demand Credibility", "domain": "Tools, weapons, cloth", "summary": "The palace can prepare records that make processed-good delivery more legible.", "future_hook": "Future hook: improves clarity around the Processed court-need slot."},
		{"id": "luxury_special_demand", "name": "Luxury / Special Demand Credibility", "domain": "Fine textiles, captives and high-status goods", "summary": "The palace can frame elite deliveries as legitimate service rather than mere surplus spending.", "future_hook": "Future hook: improves clarity around the Luxury/Special court-need slot."}
	]
	var max_rows: int = 1
	if detail_tier >= 2:
		max_rows = 2
	if detail_tier >= 3:
		max_rows = 3
	for index: int in range(mini(max_rows, raw_rows.size())):
		var source: Dictionary = raw_rows[index]
		var row: Dictionary = {
			"id": String(source.get("id", "obligation")),
			"name": String(source.get("name", "Obligation")),
			"domain": "Hidden",
			"summary": "The palace senses future obligation pressure, but details are not implemented yet.",
			"future_hook": "Future hook: court need donation and presentation hooks can use this route later.",
			"detail_tier": detail_tier
		}
		if detail_tier >= 2:
			row["domain"] = String(source.get("domain", "Demand goods"))
			row["summary"] = String(source.get("summary", row["summary"]))
		if detail_tier >= 4:
			row["future_hook"] = String(source.get("future_hook", row["future_hook"]))
		rows.append(row)
	return rows

func get_quetzalcoatl_legitimacy_overview(state: Node) -> Dictionary:
	var dedicated: bool = _palace_dedicated_god(state) == GOD_QUETZALCOATL
	var detail_tier: int = quetzalcoatl_active_structure_tier(state)
	var headline: String = "Quetzalcoatl legitimacy unavailable"
	var summary_text: String = "Dedicate the Palace to Quetzalcoatl, then build and maintain active Quetzalcoatl structures to reveal legitimacy, recognition, tribute credibility and palace-trust hooks."
	if dedicated and detail_tier <= 0:
		headline = "Quetzalcoatl legitimacy dormant"
		summary_text = "The palace is dedicated to Quetzalcoatl, but no active Quetzalcoatl palace structures are maintained and staffed this Veintena."
	elif dedicated and detail_tier > 0:
		headline = "Quetzalcoatl Legitimacy Court — " + quetzalcoatl_detail_label(detail_tier)
		summary_text = "Active Quetzalcoatl structures reveal legitimacy, tribute credibility and recognition-route hooks. This route is information-only; court-need donations create prestige separately by base value."
	var legitimacy_rows: Array[Dictionary] = []
	var obligation_rows: Array[Dictionary] = []
	if dedicated and detail_tier > 0:
		legitimacy_rows = quetzalcoatl_legitimacy_rows(detail_tier)
		obligation_rows = quetzalcoatl_obligation_rows(detail_tier)
	return {
		"available": dedicated,
		"active": dedicated and detail_tier > 0,
		"detail_tier": detail_tier,
		"detail_label": quetzalcoatl_detail_label(detail_tier),
		"headline": headline,
		"summary": summary_text,
		"active_structures": quetzalcoatl_active_structure_names(state),
		"legitimacy_rows": legitimacy_rows,
		"obligation_rows": obligation_rows,
		"visible_legitimacy_count": legitimacy_rows.size(),
		"visible_obligation_count": obligation_rows.size(),
		"mechanics_note": "Quetzalcoatl rows are information-only. They do not add recognition, royal favour, local stability or diplomacy effects; court-need donations create prestige separately by base value."
	}
