#!/usr/bin/env python3
"""
Apply the Tlaloc's Reign Turn Preview + Integration Audit patch.
Run this from the Godot project root.

This patch is designed to apply on top of the current main branch state around
2026-06-14, after the Housing Population Link patch.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path.cwd()

TR_PATH_OPTIONS = [
    ROOT / "Scripts" / "Autoload" / "TRGameState.gd",
    ROOT / "Scripts" / "autoload" / "TRGameState.gd",
]
GAME_PATH = ROOT / "Scripts" / "ui" / "GameScreen.gd"


def find_existing(paths: list[Path]) -> Path:
    for path in paths:
        if path.exists():
            return path
    raise FileNotFoundError("Could not find any of: " + ", ".join(str(p) for p in paths))


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f"Could not find patch anchor for {label}.")
    return text.replace(old, new, 1)


def insert_before(text: str, anchor: str, insertion: str, label: str) -> str:
    if insertion.strip() in text:
        print(f"Already applied: {label}")
        return text
    if anchor not in text:
        raise RuntimeError(f"Could not find insertion anchor for {label}.")
    return text.replace(anchor, insertion.rstrip() + "\n\n" + anchor, 1)


def patch_tr_game_state(path: Path) -> None:
    text = read_text(path)

    old_base = '''func _ensure_base_housing_capacity() -> void:\n\tfor group_variant: Variant in population.keys():\n\t\tvar group_id: String = String(group_variant)\n\t\tif not base_housing_capacity.has(group_id):\n\t\t\tbase_housing_capacity[group_id] = int(population[group_id])\n'''
    new_base = '''func _ensure_base_housing_capacity() -> void:\n\t# Base housing is now only a backwards-compatible data field. It should not\n\t# silently house new population groups for free, because the Housing screen\n\t# is meant to show real built housing capacity. Missing groups default to 0\n\t# and must be supported by housing buildings.\n\tfor group_variant: Variant in population.keys():\n\t\tvar group_id: String = String(group_variant)\n\t\tif not base_housing_capacity.has(group_id):\n\t\t\tbase_housing_capacity[group_id] = 0\n'''
    if old_base in text:
        text = text.replace(old_base, new_base, 1)
    elif "base_housing_capacity[group_id] = int(population[group_id])" in text:
        text = text.replace("base_housing_capacity[group_id] = int(population[group_id])", "base_housing_capacity[group_id] = 0", 1)

    turn_preview_block = r'''func estimate_turn_resolution() -> Dictionary:
	# Estate-level preview used by the Estate screen command reports. This is a
	# dry-run, not a turn advance. It follows the same resolution order as
	# advance_veintena(): population upkeep, housing maintenance, then production.
	_ensure_active_housing_counts()
	_ensure_labour_assignments()

	var production_resolution: Dictionary = estimate_production_resolution()
	var housing_summary: Dictionary = get_housing_summary()
	var projected_stockpile: Dictionary = (production_resolution.get("stockpile_after_upkeep_and_production", {}) as Dictionary).duplicate(true)
	var population_upkeep: Dictionary = (production_resolution.get("upkeep_needed", estimate_population_upkeep()) as Dictionary).duplicate(true)
	var housing_maintenance: Dictionary = (production_resolution.get("housing_maintenance_needed", estimate_housing_maintenance()) as Dictionary).duplicate(true)
	var production_inputs: Dictionary = (production_resolution.get("inputs", {}) as Dictionary).duplicate(true)
	var production_outputs: Dictionary = (production_resolution.get("outputs", {}) as Dictionary).duplicate(true)
	var upkeep_shortfalls: Dictionary = (production_resolution.get("upkeep_shortfalls", {}) as Dictionary).duplicate(true)
	var maintenance_shortfalls: Dictionary = (production_resolution.get("housing_maintenance_shortfalls", {}) as Dictionary).duplicate(true)

	var operating_buildings: Array[String] = []
	var blocked_buildings: Array[String] = []
	var unstaffed_buildings: Array[String] = []	
	var statuses: Dictionary = production_resolution.get("building_statuses", {}) as Dictionary

	for building_id: String in building_order:
		if not _is_productive_building_id(building_id):
			continue
		var built_count: int = int(estate_buildings.get(building_id, 0))
		if built_count <= 0:
			continue
		var status: Dictionary = statuses.get(building_id, {}) as Dictionary
		var operating: int = int(status.get("operating", 0))
		var blocked: int = int(status.get("blocked", 0))
		var unstaffed: int = int(status.get("unstaffed", 0))
		var input_blocked: int = int(status.get("input_blocked", 0))
		var building_name: String = get_building_name(building_id)
		if operating > 0:
			operating_buildings.append(building_name + " x" + str(operating))
		if blocked > 0:
			blocked_buildings.append(building_name + " x" + str(blocked) + " — " + String(status.get("status_text", "blocked")))
		if unstaffed > 0:
			unstaffed_buildings.append(building_name + " x" + str(unstaffed))
		elif input_blocked > 0:
			# Input-blocked buildings are also in blocked_buildings, but this keeps the
			# source of the problem clear for UI reports that want the shorter list.
			unstaffed_buildings.append(building_name + " input-blocked x" + str(input_blocked))

	var critical_warnings: Array[String] = []
	if _turn_preview_has_positive_values(upkeep_shortfalls):
		critical_warnings.append("Population upkeep shortfall: " + _turn_preview_dictionary_text(upkeep_shortfalls) + ".")
	if _turn_preview_has_positive_values(maintenance_shortfalls):
		critical_warnings.append("Housing maintenance shortfall: " + _turn_preview_dictionary_text(maintenance_shortfalls) + ".")
	if int(housing_summary.get("total_inactive_population", 0)) > 0:
		critical_warnings.append("Inactive population: " + str(int(housing_summary.get("total_inactive_population", 0))) + " people are not currently supported by active housing.")
	if int(housing_summary.get("total_over_capacity", 0)) > 0:
		critical_warnings.append("Housing over-capacity: " + str(int(housing_summary.get("total_over_capacity", 0))) + " people over active capacity.")
	if not blocked_buildings.is_empty():
		critical_warnings.append("Blocked production: " + str(blocked_buildings.size()) + " productive building type(s) have blocked copies.")
	if critical_warnings.is_empty():
		critical_warnings.append("No critical turn-resolution issues detected.")

	return {
		"current_veintena": current_veintena,
		"population": population.duplicate(true),
		"active_population": active_population_by_group(),
		"inactive_population": inactive_population_by_group(),
		"housing_summary": housing_summary,
		"population_upkeep": population_upkeep,
		"housing_maintenance": housing_maintenance,
		"production_inputs": production_inputs,
		"production_outputs": production_outputs,
		"projected_stockpile": projected_stockpile,
		"upkeep_shortfalls": upkeep_shortfalls,
		"housing_maintenance_shortfalls": maintenance_shortfalls,
		"production_resolution": production_resolution,
		"operating_buildings": operating_buildings,
		"blocked_buildings": blocked_buildings,
		"unstaffed_buildings": unstaffed_buildings,
		"critical_warnings": critical_warnings
	}

func _turn_preview_has_positive_values(values: Dictionary) -> bool:
	for key_variant: Variant in values.keys():
		if float(values[key_variant]) > 0.001:
			return true
	return false

func _turn_preview_dictionary_text(values: Dictionary) -> String:
	var parts: Array[String] = []
	for key_variant: Variant in values.keys():
		var resource_id: String = String(key_variant)
		var value: float = float(values[key_variant])
		if absf(value) <= 0.001:
			continue
		parts.append(_format_amount(value) + " " + get_resource_name(resource_id))
	if parts.is_empty():
		return "none"
	return ", ".join(parts)
'''
    text = insert_before(text, "func advance_veintena() -> void:", turn_preview_block, "TRGameState estimate_turn_resolution")
    write_text(path, text)


def patch_game_screen(path: Path) -> None:
    text = read_text(path)

    if "var selected_estate_report_id: String" not in text:
        text = replace_once(
            text,
            'var current_location_id: String = "estate"\nvar current_focus_by_location: Dictionary = {}\n',
            'var current_location_id: String = "estate"\nvar current_focus_by_location: Dictionary = {}\nvar selected_estate_report_id: String = ""\n',
            "GameScreen selected_estate_report_id"
        )

    text = replace_once(
        text,
        'if current_location_id == "production" and _current_focus_id() == "overview":\n\t\t_show_production_overview_content()\n',
        'if current_location_id == "estate":\n\t\t_show_estate_report_content(profile)\n\telif current_location_id == "production" and _current_focus_id() == "overview":\n\t\t_show_production_overview_content()\n',
        "GameScreen route Estate reports"
    ) if 'if current_location_id == "estate":\n\t\t_show_estate_report_content(profile)' not in text else text

    estate_show_block = r'''func _show_estate_report_content(profile: Dictionary) -> void:
	if selected_estate_report_id == "":
		_show_text_content(profile)
		return

	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false
	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return
	dynamic_view_host.visible = true

	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.0, 0.0, 0.0, 0.64), Color(0.50, 0.82, 0.74, 0.36), 14))
	dynamic_view_host.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)

	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	stack.add_child(header)

	var title_label: Label = Label.new()
	title_label.text = _estate_report_title(selected_estate_report_id)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 29)
	title_label.clip_text = true
	header.add_child(title_label)

	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(48, 44)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(_on_estate_report_closed)
	header.add_child(close_button)

	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = false
	body.scroll_active = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 22)
	body.add_theme_font_size_override("bold_font_size", 24)
	body.add_theme_constant_override("line_separation", 6)
	body.text = _build_estate_report_detail_text(selected_estate_report_id)
	stack.add_child(body)
'''
    text = insert_before(text, "func _show_production_overview_content() -> void:", estate_show_block, "GameScreen Estate report popout")

    if 'if current_location_id == "estate":\n\t\t_build_estate_overview_reports()' not in text:
        text = replace_once(
            text,
            'if special_view == "storehouse":\n\t\t_build_storehouse_ledger()\n',
            'if current_location_id == "estate":\n\t\t_build_estate_overview_reports()\n\telif special_view == "storehouse":\n\t\t_build_storehouse_ledger()\n',
            "GameScreen Estate right reports"
        )

    estate_helpers = r'''func _build_estate_overview_reports() -> void:
	for report: Dictionary in _estate_report_definitions():
		_add_estate_report_button(report)
	if selected_estate_report_id != "":
		var close_button: Button = Button.new()
		close_button.text = "Close Report"
		close_button.custom_minimum_size = Vector2(0, 54)
		close_button.add_theme_font_size_override("font_size", 19)
		close_button.pressed.connect(_on_estate_report_closed)
		notification_list.add_child(close_button)

func _estate_report_definitions() -> Array[Dictionary]:
	return [
		{"id": "turn_preview", "title": "Turn Preview", "subtitle": _estate_report_subtitle("turn_preview")},
		{"id": "critical_shortages", "title": "Critical Shortages", "subtitle": _estate_report_subtitle("critical_shortages")},
		{"id": "population_housing", "title": "Population & Housing", "subtitle": _estate_report_subtitle("population_housing")},
		{"id": "production_result", "title": "Production Result", "subtitle": _estate_report_subtitle("production_result")},
		{"id": "stockpile_after_turn", "title": "Stockpile After Turn", "subtitle": _estate_report_subtitle("stockpile_after_turn")},
		{"id": "last_turn_report", "title": "Last Turn Report", "subtitle": _estate_report_subtitle("last_turn_report")}
	]

func _estate_report_title(report_id: String) -> String:
	match report_id:
		"turn_preview":
			return "Turn Preview"
		"critical_shortages":
			return "Critical Shortages"
		"population_housing":
			return "Population & Housing"
		"production_result":
			return "Production Result"
		"stockpile_after_turn":
			return "Stockpile After Turn"
		"last_turn_report":
			return "Last Turn Report"
	return "Estate Report"

func _estate_report_subtitle(report_id: String) -> String:
	var resolution: Dictionary = _turn_resolution()
	match report_id:
		"turn_preview":
			var warnings: Array = resolution.get("critical_warnings", []) as Array
			if warnings.is_empty():
				return "No preview data"
			return String(warnings[0])
		"critical_shortages":
			var warning_count: int = int((resolution.get("critical_warnings", []) as Array).size())
			return str(warning_count) + " warning(s)"
		"population_housing":
			var housing: Dictionary = resolution.get("housing_summary", {}) as Dictionary
			return "Active " + str(int(housing.get("total_active_population", 0))) + " / total " + str(int(housing.get("total_population", 0)))
		"production_result":
			return _resource_dictionary_inline(resolution.get("production_outputs", {}) as Dictionary, 3)
		"stockpile_after_turn":
			var projected: Dictionary = resolution.get("projected_stockpile", {}) as Dictionary
			if projected.is_empty():
				return "No projection"
			return _resource_dictionary_inline(projected, 3)
		"last_turn_report":
			var state: Node = _state()
			if state != null and state.has_method("get_last_report"):
				var lines: Array = state.call("get_last_report") as Array
				if not lines.is_empty():
					return String(lines[0])
	return "Open report"

func _add_estate_report_button(report: Dictionary) -> void:
	if notification_list == null:
		return
	var report_id: String = String(report.get("id", ""))
	var selected: bool = report_id == selected_estate_report_id
	var button: Button = Button.new()
	button.text = String(report.get("title", "Report")) + "\n" + String(report.get("subtitle", "Open report"))
	button.custom_minimum_size = Vector2(0, 94)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_pressed = selected
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 19)
	var border: Color = Color(0.34, 0.71, 0.63, 0.45)
	if selected:
		border = Color(0.76, 0.63, 0.32, 0.86)
	button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.04, 0.07, 0.065, 0.93), border, 10))
	button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.06, 0.095, 0.085, 0.96), Color(0.50, 0.82, 0.74, 0.75), 10))
	button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.10, 0.12, 0.095, 0.98), Color(0.76, 0.63, 0.32, 0.86), 10))
	button.pressed.connect(func() -> void:
		_on_estate_report_selected(report_id)
	)
	notification_list.add_child(button)

func _build_estate_report_detail_text(report_id: String) -> String:
	match report_id:
		"turn_preview":
			return _build_estate_turn_preview_report_text()
		"critical_shortages":
			return _build_estate_critical_shortages_report_text()
		"population_housing":
			return _build_estate_population_housing_report_text()
		"production_result":
			return _build_estate_production_result_report_text()
		"stockpile_after_turn":
			return _build_estate_stockpile_after_turn_report_text()
		"last_turn_report":
			return _build_estate_last_turn_report_text()
	return "Select an Estate report from the right-hand panel."

func _build_estate_turn_preview_report_text() -> String:
	var resolution: Dictionary = _turn_resolution()
	var text: String = "[b]Turn Preview[/b]\n"
	text += "This is the estate-level dry run for pressing Advance Veintena. It combines population upkeep, housing building maintenance, production inputs, production outputs and projected Storehouse totals.\n\n"
	text += "[b]Warnings[/b]\n"
	for warning_variant: Variant in resolution.get("critical_warnings", []) as Array:
		text += "• " + String(warning_variant) + "\n"
	text += "\n[b]Outgoing this turn[/b]\n"
	text += "Population upkeep:\n" + _resource_dictionary_lines(resolution.get("population_upkeep", {}) as Dictionary, "No population upkeep required.", 12)
	text += "Housing maintenance:\n" + _resource_dictionary_lines(resolution.get("housing_maintenance", {}) as Dictionary, "No housing maintenance required.", 12)
	text += "Production inputs:\n" + _resource_dictionary_lines(resolution.get("production_inputs", {}) as Dictionary, "No production inputs required.", 12)
	text += "\n[b]Incoming this turn[/b]\n"
	text += _resource_dictionary_lines(resolution.get("production_outputs", {}) as Dictionary, "No production output expected.", 12)
	return text.strip_edges()

func _build_estate_critical_shortages_report_text() -> String:
	var resolution: Dictionary = _turn_resolution()
	var text: String = "[b]Critical Shortages[/b]\n"
	text += "These are the problems most likely to affect the next Veintena resolution.\n\n"
	for warning_variant: Variant in resolution.get("critical_warnings", []) as Array:
		text += "• " + String(warning_variant) + "\n"
	text += "\n[b]Population upkeep shortfalls[/b]\n"
	text += _resource_dictionary_lines(resolution.get("upkeep_shortfalls", {}) as Dictionary, "No population upkeep shortfall projected.", 12)
	text += "[b]Housing maintenance shortfalls[/b]\n"
	text += _resource_dictionary_lines(resolution.get("housing_maintenance_shortfalls", {}) as Dictionary, "No housing maintenance shortfall projected.", 12)
	var blocked: Array = resolution.get("blocked_buildings", []) as Array
	text += "\n[b]Blocked production[/b]\n"
	if blocked.is_empty():
		text += "• No productive buildings are projected to be blocked.\n"
	else:
		for blocked_variant: Variant in blocked:
			text += "• " + String(blocked_variant) + "\n"
	return text.strip_edges()

func _build_estate_population_housing_report_text() -> String:
	var resolution: Dictionary = _turn_resolution()
	var housing: Dictionary = resolution.get("housing_summary", {}) as Dictionary
	var text: String = "[b]Population & Housing[/b]\n"
	text += "Active population consumes upkeep and can work. Inactive population is not currently supported by active housing.\n\n"
	text += "• Total population: " + str(int(housing.get("total_population", 0))) + "\n"
	text += "• Active population: " + str(int(housing.get("total_active_population", 0))) + "\n"
	text += "• Inactive population: " + str(int(housing.get("total_inactive_population", 0))) + "\n"
	text += "• Active housing capacity: " + str(int(housing.get("total_active_capacity", 0))) + "\n"
	text += "• Built housing capacity: " + str(int(housing.get("total_capacity", 0))) + "\n\n"
	for tier_variant: Variant in housing.get("tiers", []) as Array:
		var tier: Dictionary = tier_variant as Dictionary
		text += "• " + String(tier.get("name", "Housing")) + ": active " + str(int(tier.get("active_population", 0))) + " / total " + str(int(tier.get("population", 0))) + "; active capacity " + str(int(tier.get("active_capacity", 0))) + "; " + String(tier.get("status", "Unknown")) + "\n"
	return text.strip_edges()

func _build_estate_production_result_report_text() -> String:
	var resolution: Dictionary = _turn_resolution()
	var text: String = "[b]Production Result[/b]\n"
	text += "This reads the same production dry-run used by Storehouse and Production.\n\n"
	text += "[b]Expected output[/b]\n"
	text += _resource_dictionary_lines(resolution.get("production_outputs", {}) as Dictionary, "No output expected.", 12)
	text += "\n[b]Expected production inputs[/b]\n"
	text += _resource_dictionary_lines(resolution.get("production_inputs", {}) as Dictionary, "No production inputs expected.", 12)
	var operating: Array = resolution.get("operating_buildings", []) as Array
	text += "\n[b]Operating buildings[/b]\n"
	if operating.is_empty():
		text += "• No productive buildings are projected to operate.\n"
	else:
		for operating_variant: Variant in operating:
			text += "• " + String(operating_variant) + "\n"
	var blocked: Array = resolution.get("blocked_buildings", []) as Array
	text += "\n[b]Blocked / unstaffed buildings[/b]\n"
	if blocked.is_empty():
		text += "• No productive buildings are projected to be blocked.\n"
	else:
		for blocked_variant: Variant in blocked:
			text += "• " + String(blocked_variant) + "\n"
	return text.strip_edges()

func _build_estate_stockpile_after_turn_report_text() -> String:
	var resolution: Dictionary = _turn_resolution()
	var projected: Dictionary = resolution.get("projected_stockpile", {}) as Dictionary
	var text: String = "[b]Projected Storehouse After Turn[/b]\n"
	text += "This is the projected stockpile after population upkeep, housing maintenance, production inputs and production outputs are resolved.\n\n"
	text += _resource_dictionary_lines(projected, "No stockpile projection available.", 20)
	return text.strip_edges()

func _build_estate_last_turn_report_text() -> String:
	var text: String = "[b]Last Turn Report[/b]\n"
	var state: Node = _state()
	if state == null or not state.has_method("get_last_report"):
		return text + "• Last turn report is not connected."
	var lines: Array = state.call("get_last_report") as Array
	if lines.is_empty():
		return text + "• No report yet."
	for line_variant: Variant in lines:
		text += "• " + String(line_variant) + "\n"
	return text.strip_edges()

func _turn_resolution() -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("estimate_turn_resolution"):
		return state.call("estimate_turn_resolution") as Dictionary
	return {}
'''
    text = insert_before(text, "func _build_production_overview_reports() -> void:", estate_helpers, "GameScreen Estate report helpers")

    estate_handlers = r'''func _on_estate_report_selected(report_id: String) -> void:
	selected_estate_report_id = report_id
	_refresh_all()

func _on_estate_report_closed() -> void:
	selected_estate_report_id = ""
	_refresh_all()
'''
    text = insert_before(text, "func _on_production_report_selected(report_id: String) -> void:", estate_handlers, "GameScreen Estate report handlers")

    write_text(path, text)


def main() -> int:
    try:
        tr_path = find_existing(TR_PATH_OPTIONS)
        if not GAME_PATH.exists():
            raise FileNotFoundError(f"Could not find {GAME_PATH}")
        patch_tr_game_state(tr_path)
        patch_game_screen(GAME_PATH)
    except Exception as exc:
        print(f"Patch failed: {exc}", file=sys.stderr)
        return 1
    print("Turn Preview + Integration Audit patch applied successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
