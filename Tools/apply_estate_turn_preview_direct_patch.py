from pathlib import Path
import sys

ROOT = Path.cwd()
GAME = ROOT / "Scripts" / "ui" / "GameScreen.gd"
STATE_CANDIDATES = [
    ROOT / "Scripts" / "Autoload" / "TRGameState.gd",
    ROOT / "Scripts" / "autoload" / "TRGameState.gd",
]
STATE = next((p for p in STATE_CANDIDATES if p.exists()), STATE_CANDIDATES[0])


def fail(msg: str) -> None:
    print("ERROR:", msg)
    sys.exit(1)


def patch_file(path: Path, transform) -> None:
    if not path.exists():
        fail(f"Missing file: {path}")
    original = path.read_text(encoding="utf-8")
    updated = transform(original)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        print(f"Patched {path}")
    else:
        print(f"No changes needed for {path}")


ESTATE_REPORT_FUNCTIONS = r'''
func _show_estate_report_content() -> void:
	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false
	if selected_estate_report_id == "":
		if content_root:
			content_root.visible = false
		return
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

ESTATE_REPORT_RIGHT_PANEL = r'''
func _build_estate_overview_reports() -> void:
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
			var outputs: Dictionary = resolution.get("production_outputs", {}) as Dictionary
			var output_text: String = _resource_dictionary_inline(outputs, 3)
			return output_text if output_text != "" else "No output expected"
		"critical_shortages":
			var warnings: Array = resolution.get("critical_warnings", []) as Array
			return "No critical warnings" if warnings.is_empty() else str(warnings.size()) + " warning(s)"
		"population_housing":
			var housing: Dictionary = resolution.get("housing_summary", {}) as Dictionary
			return "Active " + str(int(housing.get("total_active_population", 0))) + " / total " + str(int(housing.get("total_population", 0)))
		"production_result":
			var reports: Array = resolution.get("production_reports", []) as Array
			return "No production reports" if reports.is_empty() else str(reports.size()) + " production note(s)"
		"stockpile_after_turn":
			var projected: Dictionary = resolution.get("projected_stockpile", {}) as Dictionary
			return _resource_dictionary_inline(projected, 3)
		"last_turn_report":
			var state: Node = _state()
			if state != null and state.has_method("get_last_report"):
				var last: Array = state.call("get_last_report") as Array
				return str(last.size()) + " last-turn note(s)"
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
			return _build_estate_turn_preview_text()
		"critical_shortages":
			return _build_estate_critical_shortages_text()
		"population_housing":
			return _build_estate_population_housing_text()
		"production_result":
			return _build_estate_production_result_text()
		"stockpile_after_turn":
			return _build_estate_stockpile_after_turn_text()
		"last_turn_report":
			return _build_estate_last_turn_report_text()
	return "Select an Estate report from the right-hand panel."

func _build_estate_turn_preview_text() -> String:
	var resolution: Dictionary = _turn_resolution()
	var text: String = "[b]Turn Preview[/b]\n"
	text += "This previews what should happen if you press Advance Veintena now. It combines population upkeep, housing maintenance, production inputs and production output.\n\n"
	text += "[b]Population upkeep[/b]\n"
	text += _resource_dictionary_lines(resolution.get("population_upkeep", {}) as Dictionary, "No active population upkeep required.", 12)
	text += "\n[b]Housing building maintenance[/b]\n"
	text += _resource_dictionary_lines(resolution.get("housing_maintenance", {}) as Dictionary, "No housing maintenance required.", 12)
	text += "\n[b]Production inputs[/b]\n"
	text += _resource_dictionary_lines(resolution.get("production_inputs", {}) as Dictionary, "No production inputs expected.", 12)
	text += "\n[b]Production outputs[/b]\n"
	text += _resource_dictionary_lines(resolution.get("production_outputs", {}) as Dictionary, "No production outputs expected.", 12)
	text += "\n[b]Critical warnings[/b]\n"
	var warnings: Array = resolution.get("critical_warnings", []) as Array
	if warnings.is_empty():
		text += "• No critical warnings.\n"
	else:
		for warning_variant: Variant in warnings:
			text += "• " + String(warning_variant) + "\n"
	return text.strip_edges()

func _build_estate_critical_shortages_text() -> String:
	var resolution: Dictionary = _turn_resolution()
	var text: String = "[b]Critical Shortages[/b]\n"
	text += "These are the warnings most likely to make the next turn resolve differently from your plan.\n\n"
	var warnings: Array = resolution.get("critical_warnings", []) as Array
	if warnings.is_empty():
		text += "• No critical shortages detected.\n"
	else:
		for warning_variant: Variant in warnings:
			text += "• " + String(warning_variant) + "\n"
	return text.strip_edges()

func _build_estate_population_housing_text() -> String:
	var resolution: Dictionary = _turn_resolution()
	var housing: Dictionary = resolution.get("housing_summary", _housing_summary()) as Dictionary
	var text: String = "[b]Population & Housing[/b]\n"
	text += "Active population consumes upkeep and can work. Inactive population is not currently supported by active housing.\n\n"
	text += "• Total population: " + str(int(housing.get("total_population", 0))) + "\n"
	text += "• Active population: " + str(int(housing.get("total_active_population", 0))) + "\n"
	text += "• Inactive population: " + str(int(housing.get("total_inactive_population", 0))) + "\n"
	text += "• Active capacity: " + str(int(housing.get("total_active_capacity", 0))) + "\n"
	text += "• Built capacity: " + str(int(housing.get("total_capacity", 0))) + "\n\n"
	for tier: Dictionary in housing.get("tiers", []) as Array:
		text += "• " + String(tier.get("name", "Housing")) + ": active " + str(int(tier.get("active_population", 0))) + " / total " + str(int(tier.get("population", 0))) + "; active capacity " + str(int(tier.get("active_capacity", 0))) + "; " + String(tier.get("status", "Unknown")) + "\n"
	return text.strip_edges()

func _build_estate_production_result_text() -> String:
	var resolution: Dictionary = _turn_resolution()
	var text: String = "[b]Production Result[/b]\n"
	text += "This summarises which productive buildings are expected to operate, block, or sit unstaffed next turn.\n\n"
	var reports: Array = resolution.get("production_reports", []) as Array
	if reports.is_empty():
		text += "• No production activity expected.\n"
	else:
		for report_variant: Variant in reports:
			text += "• " + String(report_variant) + "\n"
	return text.strip_edges()

func _build_estate_stockpile_after_turn_text() -> String:
	var resolution: Dictionary = _turn_resolution()
	var text: String = "[b]Projected Storehouse After Turn[/b]\n"
	text += "Projected values after population upkeep, housing maintenance, production inputs and production outputs resolve.\n\n"
	text += _resource_dictionary_lines(resolution.get("projected_stockpile", {}) as Dictionary, "No projected stockpile data available.", 20)
	return text.strip_edges()

func _build_estate_last_turn_report_text() -> String:
	var text: String = "[b]Last Turn Report[/b]\n"
	var state: Node = _state()
	if state == null or not state.has_method("get_last_report"):
		return text + "• Last-turn report is not connected."
	var reports: Array = state.call("get_last_report") as Array
	if reports.is_empty():
		text += "• No last-turn reports yet.\n"
	else:
		for report_variant: Variant in reports:
			text += "• " + String(report_variant) + "\n"
	return text.strip_edges()

func _turn_resolution() -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("estimate_turn_resolution"):
		return state.call("estimate_turn_resolution") as Dictionary
	return {
		"population_upkeep": _population_upkeep_totals(),
		"housing_maintenance": (_housing_summary().get("maintenance", {}) as Dictionary),
		"production_inputs": _production_input_totals(),
		"production_outputs": _production_output_totals(),
		"housing_summary": _housing_summary(),
		"projected_stockpile": {},
		"critical_warnings": ["Backend estimate_turn_resolution() is not connected yet."],
		"production_reports": []
	}

'''

ESTATE_REPORT_HANDLERS = r'''
func _on_estate_report_selected(report_id: String) -> void:
	selected_estate_report_id = report_id
	_refresh_all()

func _on_estate_report_closed() -> void:
	selected_estate_report_id = ""
	_refresh_all()

'''

TURN_RESOLUTION_FUNCTION = r'''
func estimate_turn_resolution() -> Dictionary:
	var production: Dictionary = estimate_production_resolution()
	var housing: Dictionary = get_housing_summary()
	var population_upkeep: Dictionary = production.get("upkeep_needed", estimate_population_upkeep()) as Dictionary
	var housing_maintenance: Dictionary = production.get("housing_maintenance_needed", estimate_housing_maintenance()) as Dictionary
	var production_inputs: Dictionary = production.get("inputs", {}) as Dictionary
	var production_outputs: Dictionary = production.get("outputs", {}) as Dictionary
	var projected_stockpile: Dictionary = production.get("stockpile_after_upkeep_and_production", {}) as Dictionary
	var warnings: Array[String] = []

	var upkeep_shortfalls: Dictionary = production.get("upkeep_shortfalls", {}) as Dictionary
	for resource_variant: Variant in upkeep_shortfalls.keys():
		var resource_id: String = String(resource_variant)
		warnings.append("Population upkeep shortfall: " + _format_amount(float(upkeep_shortfalls[resource_variant])) + " " + get_resource_name(resource_id) + ".")

	var maintenance_shortfalls: Dictionary = production.get("housing_maintenance_shortfalls", {}) as Dictionary
	for resource_variant: Variant in maintenance_shortfalls.keys():
		var resource_id: String = String(resource_variant)
		warnings.append("Housing maintenance shortfall: " + _format_amount(float(maintenance_shortfalls[resource_variant])) + " " + get_resource_name(resource_id) + ".")

	var inactive_people: int = int(housing.get("total_inactive_population", 0))
	if inactive_people > 0:
		warnings.append(str(inactive_people) + " people are inactive because active housing capacity is too low.")

	var statuses: Dictionary = production.get("building_statuses", {}) as Dictionary
	for building_variant: Variant in statuses.keys():
		var building_id: String = String(building_variant)
		var status: Dictionary = statuses[building_variant] as Dictionary
		var blocked: int = int(status.get("blocked", 0))
		if blocked > 0 and int(estate_buildings.get(building_id, 0)) > 0 and _is_productive_building_id(building_id):
			warnings.append(get_building_name(building_id) + " has " + str(blocked) + " blocked or unstaffed instance(s).")

	return {
		"population_upkeep": population_upkeep.duplicate(true),
		"housing_maintenance": housing_maintenance.duplicate(true),
		"production_inputs": production_inputs.duplicate(true),
		"production_outputs": production_outputs.duplicate(true),
		"housing_summary": housing.duplicate(true),
		"projected_stockpile": projected_stockpile.duplicate(true),
		"critical_warnings": warnings,
		"production_reports": (production.get("reports", []) as Array).duplicate(true),
		"production_resolution": production.duplicate(true)
	}

'''


def patch_game(text: str) -> str:
    if 'var selected_estate_report_id: String = ""' not in text:
        text = text.replace('var selected_production_report_id: String = ""\n', 'var selected_production_report_id: String = ""\nvar selected_estate_report_id: String = ""\n')

    if 'func _show_estate_report_content() -> void:' not in text:
        marker = 'func _show_storehouse_view() -> void:'
        if marker not in text:
            fail('Could not find _show_storehouse_view insertion point in GameScreen.gd')
        text = text.replace(marker, ESTATE_REPORT_FUNCTIONS + marker)

    old = 'var special_view: String = String(profile.get("special_view", ""))\n\tif current_location_id == "production" and _current_focus_id() == "overview":'
    new = 'var special_view: String = String(profile.get("special_view", ""))\n\tif current_location_id == "estate":\n\t\t_show_estate_report_content()\n\telif current_location_id == "production" and _current_focus_id() == "overview":'
    if old in text and '_show_estate_report_content()' not in text[text.find(old):text.find(old)+300]:
        text = text.replace(old, new)

    old = 'var special_view: String = String(profile.get("special_view", ""))\n\tif special_view == "storehouse":'
    new = 'var special_view: String = String(profile.get("special_view", ""))\n\tif current_location_id == "estate":\n\t\t_build_estate_overview_reports()\n\telif special_view == "storehouse":'
    if old in text:
        text = text.replace(old, new)

    if 'func _build_estate_overview_reports() -> void:' not in text:
        marker = 'func _build_production_overview_reports() -> void:'
        if marker not in text:
            fail('Could not find _build_production_overview_reports insertion point in GameScreen.gd')
        text = text.replace(marker, ESTATE_REPORT_RIGHT_PANEL + marker)

    if 'func _on_estate_report_selected(report_id: String) -> void:' not in text:
        marker = 'func _on_production_report_selected(report_id: String) -> void:'
        if marker not in text:
            fail('Could not find _on_production_report_selected insertion point in GameScreen.gd')
        text = text.replace(marker, ESTATE_REPORT_HANDLERS + marker)

    return text


def patch_state(text: str) -> str:
    if 'func estimate_turn_resolution() -> Dictionary:' not in text:
        marker = 'func estimate_population_upkeep() -> Dictionary:'
        if marker not in text:
            fail('Could not find estimate_population_upkeep insertion point in TRGameState.gd')
        text = text.replace(marker, TURN_RESOLUTION_FUNCTION + marker)
    return text


patch_file(GAME, patch_game)
patch_file(STATE, patch_state)
print("Done. Reload Godot, open Estate, and check the right-hand House Warnings & Reports panel.")
