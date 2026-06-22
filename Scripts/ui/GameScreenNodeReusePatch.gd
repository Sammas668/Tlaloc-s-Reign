# GameScreenNodeReusePatch.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenNodeReusePatch.gd
#
# Patch 8P1F: optional UI node reuse.
#
# This wrapper sits on top of the 8P1E lazy-art screen. The heavy performance
# wins already come from coalesced refresh, Estate snapshots and production
# preview caching; this pass trims the remaining UI churn by reusing stable top
# navigation nodes and right-panel report buttons instead of queue_free/new on
# every refresh.
extends "res://Scripts/ui/GameScreenLazyArtPatch.gd"

var _top_area_reuse_key: String = ""
var _top_focus_buttons: Dictionary = {}
var _right_report_panel_key: String = ""
var _right_report_buttons: Dictionary = {}
var _right_report_close_button: Button = null


# -----------------------------------------------------------------------------
# Top-area reuse
# -----------------------------------------------------------------------------

func _refresh_top_area() -> void:
	if top_row == null:
		return

	var profile: Dictionary = _profile(current_location_id)
	var top_mode: String = String(profile.get("top_mode", "focus"))
	if top_mode == "calendar":
		_refresh_reused_calendar_row()
	else:
		_refresh_reused_focus_row(profile)


func _refresh_reused_calendar_row() -> void:
	var state: Node = _state()
	var current_veintena: int = 1
	if state != null and state.has_method("get_current_veintena"):
		current_veintena = int(state.call("get_current_veintena"))
	var start_index: int = clampi(current_veintena - 1, 0, _veintenas.size() - 1)
	var end_index: int = mini(start_index + visible_veintenas, _veintenas.size())
	var key: String = "calendar|" + str(start_index) + "|" + str(end_index) + "|" + str(visible_veintenas)

	if _top_area_reuse_key == key and top_row.get_child_count() > 0:
		return

	_top_area_reuse_key = key
	_top_focus_buttons.clear()
	_clear_children_immediate(top_row)
	_build_reused_calendar_cards(start_index, end_index)


func _build_reused_calendar_cards(start_index: int, end_index: int) -> void:
	for i: int in range(start_index, end_index):
		var card_data: Dictionary = _veintenas[i] as Dictionary
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(166, 106)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = "Veintena " + str(i + 1) + " — " + String(card_data.get("name", "")) + ". " + String(card_data.get("tooltip", ""))
		var style: StyleBoxFlat = _make_panel_style(Color(0.055, 0.08, 0.075, 0.92), Color(0.33, 0.70, 0.62, 0.55), 10)
		if i == start_index:
			style = _make_panel_style(Color(0.09, 0.13, 0.115, 0.98), Color(0.76, 0.63, 0.32, 0.85), 10)
		card.add_theme_stylebox_override("panel", style)

		var margin: MarginContainer = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_top", 7)
		margin.add_theme_constant_override("margin_bottom", 7)
		card.add_child(margin)

		var stack: VBoxContainer = VBoxContainer.new()
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		margin.add_child(stack)
		_add_center_label(stack, "Veintena " + str(i + 1), 17)
		_add_center_label(stack, String(card_data.get("name", "")), 15)
		_add_center_label(stack, String(card_data.get("type", "")), 17)
		_add_center_label(stack, String(card_data.get("detail", "")), 15)
		top_row.add_child(card)


func _refresh_reused_focus_row(profile: Dictionary) -> void:
	var focuses: Array = profile.get("focuses", []) as Array
	if focuses.is_empty():
		_top_area_reuse_key = ""
		_top_focus_buttons.clear()
		_clear_children_immediate(top_row)
		return

	var key: String = _focus_row_reuse_key(current_location_id, focuses)
	if _top_area_reuse_key == key and top_row.get_child_count() > 0:
		_update_reused_focus_button_states()
		return

	_top_area_reuse_key = key
	_top_focus_buttons.clear()
	_clear_children_immediate(top_row)

	for focus_variant: Variant in focuses:
		if not (focus_variant is Dictionary):
			continue
		var focus: Dictionary = focus_variant as Dictionary
		var focus_id: String = String(focus.get("id", "overview"))
		var button: Button = Button.new()
		button.text = String(focus.get("label", focus_id.capitalize()))
		button.toggle_mode = true
		button.button_pressed = focus_id == _current_focus_id()
		button.custom_minimum_size = Vector2(150, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 21)
		button.pressed.connect(Callable(self, "_on_reused_focus_pressed").bind(current_location_id, focus_id))
		top_row.add_child(button)
		_top_focus_buttons[focus_id] = button


func _focus_row_reuse_key(location_id: String, focuses: Array) -> String:
	var parts: Array[String] = ["focus", location_id]
	for focus_variant: Variant in focuses:
		if focus_variant is Dictionary:
			var focus: Dictionary = focus_variant as Dictionary
			parts.append(String(focus.get("id", "")) + ":" + String(focus.get("label", "")))
	return "|".join(parts)


func _update_reused_focus_button_states() -> void:
	var selected_focus: String = _current_focus_id()
	for key_variant: Variant in _top_focus_buttons.keys():
		var focus_id: String = String(key_variant)
		var button: Button = _top_focus_buttons[key_variant] as Button
		if button != null:
			button.button_pressed = focus_id == selected_focus


func _on_reused_focus_pressed(location_id: String, focus_id: String) -> void:
	show_focus(location_id, focus_id)


# -----------------------------------------------------------------------------
# Right-panel report-button reuse
# -----------------------------------------------------------------------------

func _refresh_right_panel() -> void:
	var profile: Dictionary = _profile(current_location_id)
	if notification_title:
		notification_title.text = _report_title_for_current_focus(profile)

	_refresh_house_claim()

	if current_location_id == "estate":
		_build_or_update_reused_report_buttons(
			"estate|" + selected_estate_report_id,
			_estate_report_definitions(),
			selected_estate_report_id,
			Callable(self, "_on_estate_report_selected"),
			Callable(self, "_on_estate_report_closed")
		)
		return

	if current_location_id == "production" and _current_focus_id() == "overview":
		_build_or_update_reused_report_buttons(
			"production|overview|" + selected_production_report_id,
			_production_report_definitions(),
			selected_production_report_id,
			Callable(self, "_on_production_report_selected"),
			Callable(self, "_on_production_report_closed")
		)
		return

	if current_location_id == "housing" and _current_focus_id() == "overview":
		_build_or_update_reused_report_buttons(
			"housing|overview|" + selected_housing_report_id,
			_housing_report_definitions(),
			selected_housing_report_id,
			Callable(self, "_on_housing_report_selected"),
			Callable(self, "_on_housing_report_closed")
		)
		return

	_right_report_panel_key = ""
	_right_report_buttons.clear()
	_right_report_close_button = null
	super._refresh_right_panel()


func _build_or_update_reused_report_buttons(panel_key: String, reports: Array, selected_id: String, select_callable: Callable, close_callable: Callable) -> void:
	if notification_list == null:
		return

	var can_update_existing: bool = _right_report_panel_key == panel_key and _right_report_buttons.size() == reports.size()
	if can_update_existing:
		for report_variant: Variant in reports:
			if not (report_variant is Dictionary):
				can_update_existing = false
				break
			var report_id: String = String((report_variant as Dictionary).get("id", ""))
			if report_id == "" or not _right_report_buttons.has(report_id):
				can_update_existing = false
				break

	if not can_update_existing:
		_clear_children_immediate(notification_list)
		_right_report_buttons.clear()
		_right_report_panel_key = panel_key
		for report_variant: Variant in reports:
			if not (report_variant is Dictionary):
				continue
			var report: Dictionary = report_variant as Dictionary
			var button: Button = _make_reused_report_button(report, selected_id, select_callable)
			notification_list.add_child(button)
			_right_report_buttons[String(report.get("id", ""))] = button
		_right_report_close_button = null
		if selected_id != "":
			_right_report_close_button = _make_reused_report_close_button(close_callable)
			notification_list.add_child(_right_report_close_button)
		return

	for report_variant: Variant in reports:
		if not (report_variant is Dictionary):
			continue
		var report: Dictionary = report_variant as Dictionary
		var report_id: String = String(report.get("id", ""))
		var button: Button = _right_report_buttons.get(report_id, null) as Button
		if button != null:
			_configure_reused_report_button(button, report, selected_id)


func _make_reused_report_button(report: Dictionary, selected_id: String, select_callable: Callable) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 94)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.04, 0.07, 0.065, 0.93), Color(0.34, 0.71, 0.63, 0.45), 10))
	button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.06, 0.095, 0.085, 0.96), Color(0.50, 0.82, 0.74, 0.75), 10))
	button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.10, 0.12, 0.095, 0.98), Color(0.76, 0.63, 0.32, 0.86), 10))
	var report_id: String = String(report.get("id", ""))
	button.pressed.connect(select_callable.bind(report_id))
	_configure_reused_report_button(button, report, selected_id)
	return button


func _configure_reused_report_button(button: Button, report: Dictionary, selected_id: String) -> void:
	var report_id: String = String(report.get("id", ""))
	var title: String = String(report.get("title", "Report"))
	var subtitle: String = String(report.get("subtitle", "Open report"))
	button.text = title + "\n" + subtitle
	button.button_pressed = report_id == selected_id
	button.tooltip_text = subtitle


func _make_reused_report_close_button(close_callable: Callable) -> Button:
	var button: Button = Button.new()
	button.text = "Close Report"
	button.custom_minimum_size = Vector2(0, 54)
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(close_callable)
	return button


# -----------------------------------------------------------------------------
# Utility
# -----------------------------------------------------------------------------

func _clear_children_immediate(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
