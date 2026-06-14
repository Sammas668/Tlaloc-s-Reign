from pathlib import Path
import sys

ROOT = Path.cwd()
game_path = ROOT / "Scripts" / "ui" / "GameScreen.gd"
if not game_path.exists():
    print(f"ERROR: Could not find {game_path}")
    sys.exit(1)

text = game_path.read_text(encoding="utf-8")
original = text

def insert_after_once(src: str, needle: str, insertion: str, marker: str) -> str:
    if marker in src:
        return src
    if needle not in src:
        raise RuntimeError(f"Could not find insertion point: {needle!r}")
    return src.replace(needle, needle + insertion, 1)

def replace_once(src: str, old: str, new: str, marker: str) -> str:
    if marker in src:
        return src
    if old not in src:
        raise RuntimeError(f"Could not find replacement block starting: {old[:80]!r}")
    return src.replace(old, new, 1)

# 1) Add selected Estate report state.
text = insert_after_once(
    text,
    'var selected_housing_report_id: String = ""\n',
    'var selected_estate_report_id: String = "" # ESTATE_PREVIEW_VISIBLE_PATCH_STATE\n',
    'ESTATE_PREVIEW_VISIBLE_PATCH_STATE'
)

# 2) Route Estate main content through a report-aware view.
old_main = '''func _refresh_main_content() -> void:\n\t_clear_dynamic_views()\n\tvar profile: Dictionary = _profile(current_location_id)\n\tif location_title:\n\t\tlocation_title.text = String(profile.get("title", "Estate"))\n\tif location_art:\n\t\tlocation_art.texture = _art_for_location(current_location_id)\n\tvar special_view: String = String(profile.get("special_view", ""))\n\tif current_location_id == "production" and _current_focus_id() == "overview":\n'''
new_main = '''func _refresh_main_content() -> void:\n\t_clear_dynamic_views()\n\tvar profile: Dictionary = _profile(current_location_id)\n\tif location_title:\n\t\tlocation_title.text = String(profile.get("title", "Estate"))\n\tif location_art:\n\t\tlocation_art.texture = _art_for_location(current_location_id)\n\tvar special_view: String = String(profile.get("special_view", ""))\n\tif current_location_id == "estate": # ESTATE_PREVIEW_VISIBLE_PATCH_MAIN\n\t\t_show_estate_report_content(profile)\n\telif current_location_id == "production" and _current_focus_id() == "overview":\n'''
text = replace_once(text, old_main, new_main, 'ESTATE_PREVIEW_VISIBLE_PATCH_MAIN')

# 3) Route Estate right panel to report buttons.
old_right = '''\tif special_view == "storehouse":\n\t\t_build_storehouse_ledger()\n'''
new_right = '''\tif current_location_id == "estate": # ESTATE_PREVIEW_VISIBLE_PATCH_RIGHT\n\t\t_build_estate_overview_reports()\n\telif special_view == "storehouse":\n\t\t_build_storehouse_ledger()\n'''
text = replace_once(text, old_right, new_right, 'ESTATE_PREVIEW_VISIBLE_PATCH_RIGHT')

# 4) Add all Estate preview/report functions before production report functions.
anchor = 'func _build_production_overview_reports() -> void:\n'
insert_block = r'''
# ESTATE_PREVIEW_VISIBLE_PATCH_FUNCTIONS_START
func _show_estate_report_content(profile: Dictionary) -> void:
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
		{"id": "last_turn_report", "title": "Last Turn Report", "subtitle": "Review the latest resolved messages"}
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
	match report_id:
		"turn_preview":
			return "Preview upkeep, housing, production and stockpile pressure"
		"critical_shortages":
			var shortages: Array[String] = _estate_shortage_lines(2)
			if shortages.is_empty():
				return "No critical shortage detected"
			return _join_string_items(shortages, "; ", 2)
		"population_housing":
			var summary: Dictionary = _housing_summary()
			return "Active " + str(int(summary.get("total_active_population", 0))) + " / total " + str(int(summary.get("total_population", 0)))
		"production_result":
			return _resource_dictionary_inline(_production_output_totals(), 3) if _resource_dictionary_inline(_production_output_totals(), 3) != "" else "No output expected"
		"stockpile_after_turn":
			return "Projected stock after upkeep and production"
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
	var text: String = "[b]Turn Preview[/b]\n"
	text += "This is the command-level read before pressing Advance Veintena. It combines active population upkeep, housing building maintenance, production inputs and expected production output.\n\n"
	text += "[b]Population upkeep[/b]\n" + _resource_dictionary_lines(_population_upkeep_totals(), "No active population upkeep currently required.", 10) + "\n"
	text += "[b]Housing building maintenance[/b]\n" + _resource_dictionary_lines(_housing_maintenance_totals(), "No housing maintenance currently required.", 10) + "\n"
	text += "[b]Production inputs[/b]\n" + _resource_dictionary_lines(_production_input_totals(), "No production inputs currently required.", 10) + "\n"
	text += "[b]Expected production outputs[/b]\n" + _resource_dictionary_lines(_production_output_totals(), "No production output expected.", 10)
	return text.strip_edges()

func _build_estate_critical_shortages_text() -> String:
	var text: String = "[b]Critical Shortages[/b]\n"
	var lines: Array[String] = _estate_shortage_lines(20)
	if lines.is_empty():
		text += "No critical shortage detected from current Storehouse reserved/outgoing values.\n"
	else:
		for line: String in lines:
			text += "• " + line + "\n"
	return text.strip_edges()

func _build_estate_population_housing_text() -> String:
	var summary: Dictionary = _housing_summary()
	var text: String = "[b]Population & Housing[/b]\n"
	text += "• Total population: " + str(int(summary.get("total_population", 0))) + "\n"
	text += "• Active population: " + str(int(summary.get("total_active_population", 0))) + "\n"
	text += "• Inactive population: " + str(int(summary.get("total_inactive_population", 0))) + "\n"
	text += "• Active housing capacity: " + str(int(summary.get("total_active_capacity", 0))) + "\n"
	text += "• Built housing capacity: " + str(int(summary.get("total_capacity", 0))) + "\n\n"
	for tier: Dictionary in summary.get("tiers", []) as Array:
		text += "• " + String(tier.get("name", "Housing")) + ": active " + str(int(tier.get("active_population", 0))) + " / total " + str(int(tier.get("population", 0))) + "; capacity " + str(int(tier.get("active_capacity", 0))) + "; " + String(tier.get("status", "Unknown")) + "\n"
	return text.strip_edges()

func _build_estate_production_result_text() -> String:
	var text: String = "[b]Production Result[/b]\n"
	var summary: Dictionary = _production_building_summary()
	text += "• Built production buildings: " + str(int(summary.get("built", 0))) + "\n"
	text += "• Expected operating instances: " + str(int(summary.get("operating", 0))) + "\n"
	text += "• Blocked instances: " + str(int(summary.get("blocked", 0))) + "\n\n"
	text += "[b]Expected outputs[/b]\n" + _resource_dictionary_lines(_production_output_totals(), "No output expected.", 10) + "\n"
	text += "[b]Inputs consumed[/b]\n" + _resource_dictionary_lines(_production_input_totals(), "No inputs consumed.", 10)
	return text.strip_edges()

func _build_estate_stockpile_after_turn_text() -> String:
	var text: String = "[b]Stockpile After Turn[/b]\n"
	text += "Projected values use current stored goods + expected production output − population upkeep − housing maintenance − production inputs.\n\n"
	for good: Dictionary in _storehouse_goods():
		var stored: float = float(good.get("stored", 0.0))
		var incoming: float = float(good.get("incoming", 0.0))
		var outgoing: float = float(good.get("outgoing", 0.0))
		var projected: float = stored + incoming - outgoing
		if absf(stored) <= 0.001 and absf(incoming) <= 0.001 and absf(outgoing) <= 0.001:
			continue
		text += "• " + String(good.get("name", "Good")) + ": " + _format_float(stored) + " → " + _format_float(projected)
		if projected < 0.0:
			text += "  [b]SHORT[/b]"
		text += "\n"
	return text.strip_edges()

func _build_estate_last_turn_report_text() -> String:
	var text: String = "[b]Last Turn Report[/b]\n"
	var reports: Array = []
	var state: Node = _state()
	if state != null and state.has_method("get_last_report"):
		reports = state.call("get_last_report") as Array
	if reports.is_empty():
		text += "No turn report yet.\n"
	else:
		for report_variant: Variant in reports:
			text += "• " + String(report_variant) + "\n"
	return text.strip_edges()

func _housing_maintenance_totals() -> Dictionary:
	var summary: Dictionary = _housing_summary()
	return summary.get("maintenance", {}) as Dictionary

func _estate_shortage_lines(max_items: int = 6) -> Array[String]:
	var output: Array[String] = []
	for good: Dictionary in _storehouse_goods():
		if output.size() >= max_items:
			break
		var stored: float = float(good.get("stored", 0.0))
		var outgoing: float = float(good.get("outgoing", 0.0))
		var incoming: float = float(good.get("incoming", 0.0))
		var projected: float = stored + incoming - outgoing
		if outgoing > stored + incoming + 0.001:
			output.append(String(good.get("name", "Good")) + " short by " + _format_float(absf(projected)))
		elif outgoing > stored * 0.85 and outgoing > 0.001:
			output.append(String(good.get("name", "Good")) + " tight: stored " + _format_float(stored) + ", outgoing " + _format_float(outgoing))
	return output

func _on_estate_report_selected(report_id: String) -> void:
	selected_estate_report_id = report_id
	_refresh_all()

func _on_estate_report_closed() -> void:
	selected_estate_report_id = ""
	_refresh_all()
# ESTATE_PREVIEW_VISIBLE_PATCH_FUNCTIONS_END

'''
if 'ESTATE_PREVIEW_VISIBLE_PATCH_FUNCTIONS_START' not in text:
    if anchor not in text:
        raise RuntimeError('Could not find function anchor for estate report functions')
    text = text.replace(anchor, insert_block + anchor, 1)

if text == original:
    print("No changes made; patch markers may already be present.")
else:
    game_path.write_text(text, encoding="utf-8")
    print("Patched Scripts/ui/GameScreen.gd with visible Estate report buttons.")
    print("Open Estate. The buttons appear in the right-hand House Warnings & Reports panel.")
