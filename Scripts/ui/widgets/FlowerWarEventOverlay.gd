# FlowerWarEventOverlay.gd
# Godot 4.x
# Project path: res://Scripts/ui/widgets/FlowerWarEventOverlay.gd
#
# Extracted full-screen Flower War attack / defence / return event panel.
# This can be hosted by GameScreenMarketOverviewPatch.gd or by the extracted
# BarracksScreenController. The self-contained event UI lives in a reusable widget file.
#
# Important: this is a GameScreen-wide modal event. The host adds this widget to
# the GameScreen Control itself, not to the left DynamicViewHost and not to the
# OS/window root. That matches the pre-extraction inline overlay sizing.
extends Control

const COLOR_TEXT: Color = Color(0.92, 0.88, 0.78, 1.0)
const COLOR_MUTED: Color = Color(0.70, 0.78, 0.74, 1.0)
const COLOR_TEAL: Color = Color(0.50, 0.92, 0.84, 1.0)

var host: Object = null

var _flower_war_event_overlay: Control = null
var _flower_war_event_option_id: String = "standard"
var _flower_war_event_provisioning_id: String = "standard"
var _flower_war_event_selected_warbands: Dictionary = {}
var _flower_war_event_report: Dictionary = {}
var _flower_war_defence_strategy_id: String = "balanced"

func open_attack_event(host_node: Object, option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> void:
	host = host_node
	_configure_overlay_root()
	_open_flower_war_attack_event(option_id, source_id, context)

func open_defence_event(host_node: Object, option_id: String = "standard", source_id: String = "rival", context: Dictionary = {}) -> void:
	host = host_node
	_configure_overlay_root()
	_open_flower_war_defence_event(option_id, source_id, context)

func _configure_overlay_root() -> void:
	name = "FlowerWarEventOverlayController"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 250
	custom_minimum_size = Vector2.ZERO

func _close_flower_war_event_overlay() -> void:
	queue_free()
	if host != null and host.has_method("_refresh_all"):
		host.call_deferred("_refresh_all")

# Fullscreen Flower War Event Flow v0.14
# -----------------------------------------------------------------------------

func _open_flower_war_attack_event(option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> void:
	var state: Node = _state()
	if state != null and state.has_method("start_flower_war_attack_event"):
		var hook_result_variant: Variant = state.call("start_flower_war_attack_event", option_id, source_id, context)
		if hook_result_variant is Dictionary:
			var hook_result: Dictionary = hook_result_variant as Dictionary
			if not bool(hook_result.get("ok", false)):
				_push_host_skill_web_report(String(hook_result.get("reason", hook_result.get("message", "Flower War attack event is blocked."))))
				_refresh_all()
				return
	_flower_war_event_option_id = option_id
	_flower_war_event_provisioning_id = "standard"
	_flower_war_event_report.clear()
	_flower_war_event_selected_warbands.clear()
	for warband_id: String in _all_ready_warband_ids():
		_flower_war_event_selected_warbands[warband_id] = true
	_show_flower_war_attack_event_overlay()

func _clear_flower_war_event_overlay() -> void:
	for child: Node in get_children():
		child.queue_free()
	_flower_war_event_overlay = null

func _create_flower_war_event_panel(panel_name: String, background_colour: Color, border_colour: Color, radius: int = 18) -> VBoxContainer:
	var shade: ColorRect = ColorRect.new()
	shade.name = panel_name + "Shade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.76)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var outer_margin: MarginContainer = MarginContainer.new()
	outer_margin.name = panel_name + "OuterMargin"
	outer_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 34)
	outer_margin.add_theme_constant_override("margin_top", 28)
	outer_margin.add_theme_constant_override("margin_right", 34)
	outer_margin.add_theme_constant_override("margin_bottom", 28)
	add_child(outer_margin)

	var event_panel: PanelContainer = PanelContainer.new()
	event_panel.name = panel_name
	event_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_panel.add_theme_stylebox_override("panel", _make_panel_style(background_colour, border_colour, radius))
	outer_margin.add_child(event_panel)
	_flower_war_event_overlay = event_panel

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	event_panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	return root

func _refresh_flower_war_event_overlay() -> void:
	_clear_flower_war_event_overlay()
	_show_flower_war_attack_event_overlay()

func _selected_flower_war_warband_ids() -> Array:
	var selected: Array = []
	for id_variant: Variant in _flower_war_event_selected_warbands.keys():
		var warband_id: String = String(id_variant)
		if bool(_flower_war_event_selected_warbands.get(warband_id, false)):
			selected.append(warband_id)
	return selected

func _all_ready_warband_ids() -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in _barracks_warband_rows():
		var warband_id: String = String(row.get("id", ""))
		if warband_id != "" and int(row.get("ready", row.get("warriors", 0))) > 0:
			ids.append(warband_id)
	return ids

func _show_flower_war_attack_event_overlay() -> void:
	_clear_flower_war_event_overlay()
	var root: VBoxContainer = _create_flower_war_event_panel("FlowerWarEventPanel", Color(0.045, 0.035, 0.020, 0.96), Color(0.78, 0.58, 0.30, 0.88))
	_build_flower_war_event_header(root)
	_build_flower_war_scale_row(root)

	var selected_ids: Array = _selected_flower_war_warband_ids()
	var preview: Dictionary = _barracks_preview_for_selected_warbands(selected_ids, _flower_war_event_option_id, _flower_war_event_provisioning_id)
	var status: Dictionary = _barracks_can_launch_selected_warbands(selected_ids, _flower_war_event_option_id, _flower_war_event_provisioning_id)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	_build_flower_war_warband_muster_column(body)
	_build_flower_war_provision_column(body, preview, status)
	_build_flower_war_event_footer(root, preview, status)

func _build_flower_war_event_header(parent: VBoxContainer) -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	parent.add_child(header)
	var title_stack: VBoxContainer = VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 2)
	header.add_child(title_stack)
	title_stack.add_child(_barracks_label("FLOWER WAR MUSTER", 34, COLOR_TEXT))
	title_stack.add_child(_barracks_wrapped_label("The drums sound across the estate. Choose which warbands march and how well the expedition is provisioned.", 17, COLOR_MUTED))
	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(96, 38)
	close_button.add_theme_font_size_override("font_size", 15)
	close_button.pressed.connect(func() -> void:
		_close_flower_war_event_overlay()
	)
	header.add_child(close_button)

func _build_flower_war_scale_row(parent: VBoxContainer) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	for option: Dictionary in _barracks_flower_options():
		var option_id: String = String(option.get("id", "minor"))
		var button: Button = Button.new()
		button.text = String(option.get("name", option_id.capitalize()))
		button.toggle_mode = true
		button.button_pressed = option_id == _flower_war_event_option_id
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(func() -> void:
			_flower_war_event_option_id = option_id
			_refresh_flower_war_event_overlay()
		)
		row.add_child(button)

func _build_flower_war_warband_muster_column(parent: HBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.038, 0.036, 0.86), Color(0.50, 0.82, 0.74, 0.48), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Warbands to Send", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("All warbands with ready warriors are selected by default. Injured warriors are shown but do not fight.", 15, COLOR_MUTED))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for row: Dictionary in _barracks_warband_rows():
		_add_flower_war_event_warband_card(list, row)

func _add_flower_war_event_warband_card(parent: VBoxContainer, row: Dictionary) -> void:
	var warband_id: String = String(row.get("id", ""))
	var ready: int = int(row.get("ready", row.get("warriors", 0)))
	var selected: bool = bool(_flower_war_event_selected_warbands.get(warband_id, false)) and ready > 0
	var stats: Dictionary = _warband_combat_stats(row)
	var border: Color = Color(0.50, 0.82, 0.74, 0.58) if selected else Color(0.40, 0.42, 0.38, 0.45)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.050, 0.046, 0.82), border, 10))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var label_stack: VBoxContainer = VBoxContainer.new()
	label_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_stack.add_theme_constant_override("separation", 2)
	top.add_child(label_stack)
	label_stack.add_child(_barracks_label(String(row.get("name", "Warband")), 20, COLOR_TEXT))
	label_stack.add_child(_barracks_wrapped_label("Doctrine: " + String(stats.get("doctrine_name", "Unspecialised")) + " | Ready " + str(ready) + " | Injured ✚ " + str(int(stats.get("injured", 0))), 14, COLOR_TEAL))
	var toggle: Button = Button.new()
	toggle.text = "Send" if selected else "Stand Down"
	toggle.toggle_mode = true
	toggle.button_pressed = selected
	toggle.disabled = ready <= 0
	toggle.custom_minimum_size = Vector2(116, 38)
	toggle.add_theme_font_size_override("font_size", 15)
	toggle.pressed.connect(func() -> void:
		_flower_war_event_selected_warbands[warband_id] = not selected
		_refresh_flower_war_event_overlay()
	)
	top.add_child(toggle)
	root.add_child(_barracks_wrapped_label("Effective offence " + _format_float(float(stats.get("effective_offence", 0.0))) + " | effective defence " + _format_float(float(stats.get("effective_defence", 0.0))) + ".", 14, COLOR_MUTED))
	if int(stats.get("injured", 0)) > 0:
		root.add_child(_barracks_wrapped_label("✚ Injured warriors are not fighting and will recover next Veintena.", 13, Color(1.0, 0.74, 0.40, 1.0)))
	if ready <= 0:
		root.add_child(_barracks_wrapped_label("Cannot march: no ready warriors. Injured warriors must recover first.", 14, Color(1.0, 0.74, 0.40, 1.0)))

func _build_flower_war_provision_column(parent: HBoxContainer, preview: Dictionary, status: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.030, 0.020, 0.88), Color(0.78, 0.58, 0.30, 0.58), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Provisions", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Provisioning applies to the whole attacking expedition. Defence events do not use provisioning.", 15, COLOR_MUTED))
	for provisioning_id: String in ["standard", "well", "royal"]:
		_add_flower_war_provision_card(stack, provisioning_id)
	stack.add_child(_barracks_label("Muster Summary", 22, COLOR_TEXT))
	if bool(preview.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Outcome preview: " + String(preview.get("result", "Unknown")) + ".", 16, COLOR_TEAL))
		stack.add_child(_barracks_wrapped_label("Selected warbands: " + str(int(preview.get("participating_warband_count", 0))) + ". Ready warriors: " + str(int(preview.get("warriors_committed", 0))) + ".", 15, COLOR_MUTED))
		stack.add_child(_barracks_wrapped_label("Effective offence " + _format_float(float(preview.get("attacker_attack", 0.0))) + " | effective defence " + _format_float(float(preview.get("attacker_defence", 0.0))) + ".", 15, COLOR_MUTED))
		stack.add_child(_barracks_wrapped_label("Cost: " + _flower_war_event_cost_text(preview.get("provisioning_cost", {}) as Dictionary) + ".", 15, COLOR_MUTED))
	else:
		stack.add_child(_barracks_wrapped_label("Preview unavailable: " + String(preview.get("reason", "No selected warbands.")), 16, Color(1.0, 0.74, 0.40, 1.0)))
	if not bool(status.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Blocked: " + String(status.get("reason", "Cannot launch.")), 15, Color(1.0, 0.74, 0.40, 1.0)))

func _add_flower_war_provision_card(parent: VBoxContainer, provisioning_id: String) -> void:
	var selected: bool = provisioning_id == _flower_war_event_provisioning_id
	var selected_ids: Array = _selected_flower_war_warband_ids()
	var preview: Dictionary = _barracks_preview_for_selected_warbands(selected_ids, _flower_war_event_option_id, provisioning_id)
	var title: String = provisioning_id.capitalize()
	match provisioning_id:
		"standard":
			title = "Standard Provisioning"
		"well":
			title = "Well-Provisioned"
		"royal":
			title = "Royal Provisioning"
	var button: Button = Button.new()
	button.toggle_mode = true
	button.button_pressed = selected
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 54)
	button.add_theme_font_size_override("font_size", 15)
	var cost_text: String = "Cost unavailable"
	if bool(preview.get("ok", false)):
		cost_text = _flower_war_event_cost_text(preview.get("provisioning_cost", {}) as Dictionary)
	button.text = title + "\n" + cost_text
	button.tooltip_text = "Choose " + title + "."
	button.pressed.connect(func() -> void:
		_flower_war_event_provisioning_id = provisioning_id
		_refresh_flower_war_event_overlay()
	)
	parent.add_child(button)

func _build_flower_war_event_footer(parent: VBoxContainer, preview: Dictionary, status: Dictionary) -> void:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 10)
	parent.add_child(footer)
	var summary: Label = _barracks_wrapped_label("Deaths, captives, loot and XP will be shown in the full Flower War Return after resolution.", 15, COLOR_MUTED)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(summary)
	var cancel_button: Button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(120, 42)
	cancel_button.add_theme_font_size_override("font_size", 16)
	cancel_button.pressed.connect(func() -> void:
		_close_flower_war_event_overlay()
	)
	footer.add_child(cancel_button)
	var begin_button: Button = Button.new()
	begin_button.text = "Begin Flower War"
	begin_button.custom_minimum_size = Vector2(190, 42)
	begin_button.add_theme_font_size_override("font_size", 16)
	begin_button.disabled = not bool(status.get("ok", false))
	begin_button.tooltip_text = String(status.get("reason", ""))
	begin_button.pressed.connect(func() -> void:
		_resolve_flower_war_attack_event()
	)
	footer.add_child(begin_button)

func _resolve_flower_war_attack_event() -> void:
	var state: Node = _state()
	if state == null:
		return
	var selected_ids: Array = _selected_flower_war_warband_ids()
	var report: Dictionary = {}
	if state.has_method("launch_flower_war_with_selected_warbands"):
		var raw: Variant = state.call("launch_flower_war_with_selected_warbands", selected_ids, _flower_war_event_option_id, _flower_war_event_provisioning_id)
		if raw is Dictionary:
			report = raw as Dictionary
	elif state.has_method("launch_flower_war_with_all_warbands"):
		var fallback_raw: Variant = state.call("launch_flower_war_with_all_warbands", _flower_war_event_option_id, _flower_war_event_provisioning_id)
		if fallback_raw is Dictionary:
			report = fallback_raw as Dictionary
	if report.is_empty():
		report = {"ok": false, "reason": "Flower War resolver is not available."}
	_flower_war_event_report = report.duplicate(true)
	_show_flower_war_return_event_overlay(report)

func _open_flower_war_defence_event(option_id: String = "standard", source_id: String = "rival", context: Dictionary = {}) -> void:
	var state: Node = _state()
	if state != null and state.has_method("start_flower_war_defence_event"):
		state.call("start_flower_war_defence_event", option_id, source_id, context)
	_flower_war_event_option_id = option_id
	_flower_war_defence_strategy_id = "balanced"
	_flower_war_event_report.clear()
	_show_flower_war_defence_event_overlay()

func _refresh_flower_war_defence_event_overlay() -> void:
	_clear_flower_war_event_overlay()
	_show_flower_war_defence_event_overlay()

func _show_flower_war_defence_event_overlay() -> void:
	_clear_flower_war_event_overlay()
	var root: VBoxContainer = _create_flower_war_event_panel("FlowerWarDefenceEventPanel", Color(0.035, 0.038, 0.052, 0.96), Color(0.36, 0.68, 0.92, 0.88))
	_build_flower_war_defence_event_header(root)
	_build_flower_war_defence_scale_row(root)

	var preview: Dictionary = _barracks_preview_for_defence(_flower_war_event_option_id, _flower_war_defence_strategy_id)
	var status: Dictionary = _barracks_can_resolve_defence(_flower_war_event_option_id, _flower_war_defence_strategy_id)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	_build_flower_war_defending_warbands_column(body)
	_build_flower_war_defence_strategy_column(body, preview, status)
	_build_flower_war_defence_event_footer(root, preview, status)

func _build_flower_war_defence_event_header(parent: VBoxContainer) -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	parent.add_child(header)
	var title_stack: VBoxContainer = VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 2)
	header.add_child(title_stack)
	title_stack.add_child(_barracks_label("FLOWER WAR DEFENCE", 34, COLOR_TEXT))
	title_stack.add_child(_barracks_wrapped_label("A rival house has come seeking captives and glory. Choose how your warbands answer.", 17, COLOR_MUTED))
	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(96, 38)
	close_button.add_theme_font_size_override("font_size", 15)
	close_button.pressed.connect(func() -> void:
		_close_flower_war_event_overlay()
	)
	header.add_child(close_button)

func _build_flower_war_defence_scale_row(parent: VBoxContainer) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	for option: Dictionary in _barracks_flower_options():
		var option_id: String = String(option.get("id", "minor"))
		var button: Button = Button.new()
		button.text = String(option.get("name", option_id.capitalize()))
		button.toggle_mode = true
		button.button_pressed = option_id == _flower_war_event_option_id
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(func() -> void:
			_flower_war_event_option_id = option_id
			_refresh_flower_war_defence_event_overlay()
		)
		row.add_child(button)

func _build_flower_war_defending_warbands_column(parent: HBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.038, 0.036, 0.86), Color(0.50, 0.82, 0.74, 0.48), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Warbands Defending", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Defensive Flower Wars commit all ready warbands. There is no provisioning choice on defence.", 15, COLOR_MUTED))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for row: Dictionary in _barracks_warband_rows():
		_add_flower_war_defending_warband_card(list, row)

func _add_flower_war_defending_warband_card(parent: VBoxContainer, row: Dictionary) -> void:
	var ready: int = int(row.get("ready", row.get("warriors", 0)))
	var stats: Dictionary = _warband_combat_stats(row)
	var border: Color = Color(0.50, 0.82, 0.74, 0.58) if ready > 0 else Color(0.40, 0.42, 0.38, 0.45)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.050, 0.046, 0.82), border, 10))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)
	root.add_child(_barracks_label(String(row.get("name", "Warband")), 20, COLOR_TEXT))
	root.add_child(_barracks_wrapped_label("Doctrine: " + String(stats.get("doctrine_name", "Unspecialised")) + " | Ready " + str(ready) + " | Injured ✚ " + str(int(stats.get("injured", 0))), 14, COLOR_TEAL))
	root.add_child(_barracks_wrapped_label("Effective offence " + _format_float(float(stats.get("effective_offence", 0.0))) + " | effective defence " + _format_float(float(stats.get("effective_defence", 0.0))) + ".", 14, COLOR_MUTED))
	if ready <= 0:
		root.add_child(_barracks_wrapped_label("Cannot defend: no ready warriors.", 14, Color(1.0, 0.74, 0.40, 1.0)))

func _build_flower_war_defence_strategy_column(parent: HBoxContainer, preview: Dictionary, status: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.030, 0.020, 0.88), Color(0.78, 0.58, 0.30, 0.58), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Defensive Strategy", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Choose one posture. Balanced is safe; the other two trade offence and defence against each other.", 15, COLOR_MUTED))
	for strategy: Dictionary in _barracks_defence_strategies():
		_add_flower_war_defence_strategy_card(stack, strategy)
	stack.add_child(_barracks_label("Defence Summary", 22, COLOR_TEXT))
	if bool(preview.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Outcome preview: " + String(preview.get("result", "Unknown")) + ".", 16, COLOR_TEAL))
		stack.add_child(_barracks_wrapped_label("Defending warbands: " + str(int(preview.get("participating_warband_count", 0))) + ". Ready warriors: " + str(int(preview.get("warriors_committed", 0))) + ".", 15, COLOR_MUTED))
		stack.add_child(_barracks_wrapped_label("Defence Off x" + _format_float(float(preview.get("offence_multiplier", 1.0))) + " | Def x" + _format_float(float(preview.get("defence_multiplier", 1.0))) + ". Enemy casualties " + str(int(preview.get("enemy_casualties", 0))) + "; expected losses " + str(int(preview.get("defender_casualties", preview.get("attacker_casualties", 0)))) + ".", 15, COLOR_MUTED))
	else:
		stack.add_child(_barracks_wrapped_label("Preview unavailable: " + String(preview.get("reason", "No defending warbands.")), 16, Color(1.0, 0.74, 0.40, 1.0)))
	if not bool(status.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Blocked: " + String(status.get("reason", "Cannot resolve defence.")), 15, Color(1.0, 0.74, 0.40, 1.0)))

func _add_flower_war_defence_strategy_card(parent: VBoxContainer, strategy: Dictionary) -> void:
	var strategy_id: String = String(strategy.get("id", "balanced"))
	var selected: bool = strategy_id == _flower_war_defence_strategy_id
	var button: Button = Button.new()
	button.toggle_mode = true
	button.button_pressed = selected
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 70)
	button.add_theme_font_size_override("font_size", 15)
	button.text = String(strategy.get("name", "Strategy")) + "\nOff x" + _format_float(float(strategy.get("offence_multiplier", 1.0))) + " | Def x" + _format_float(float(strategy.get("defence_multiplier", 1.0)))
	button.tooltip_text = String(strategy.get("description", ""))
	button.pressed.connect(func() -> void:
		_flower_war_defence_strategy_id = strategy_id
		_refresh_flower_war_defence_event_overlay()
	)
	parent.add_child(button)

func _build_flower_war_defence_event_footer(parent: VBoxContainer, preview: Dictionary, status: Dictionary) -> void:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 10)
	parent.add_child(footer)
	var summary: Label = _barracks_wrapped_label("Defensive Flower Wars use all ready warbands, no provisions, and one strategy choice. Deaths and injuries appear in the return event.", 15, COLOR_MUTED)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(summary)
	var cancel_button: Button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(120, 42)
	cancel_button.add_theme_font_size_override("font_size", 16)
	cancel_button.pressed.connect(func() -> void:
		_close_flower_war_event_overlay()
	)
	footer.add_child(cancel_button)
	var resolve_button: Button = Button.new()
	resolve_button.text = "Resolve Defence"
	resolve_button.custom_minimum_size = Vector2(190, 42)
	resolve_button.add_theme_font_size_override("font_size", 16)
	resolve_button.disabled = not bool(status.get("ok", false))
	resolve_button.tooltip_text = String(status.get("reason", ""))
	resolve_button.pressed.connect(func() -> void:
		_resolve_flower_war_defence_event()
	)
	footer.add_child(resolve_button)

func _resolve_flower_war_defence_event() -> void:
	var state: Node = _state()
	if state == null:
		return
	var report: Dictionary = {}
	if state.has_method("resolve_flower_war_defence"):
		var raw: Variant = state.call("resolve_flower_war_defence", _flower_war_event_option_id, _flower_war_defence_strategy_id)
		if raw is Dictionary:
			report = raw as Dictionary
	if report.is_empty():
		report = {"ok": false, "reason": "Flower War defence resolver is not available.", "war_direction": "defence"}
	_flower_war_event_report = report.duplicate(true)
	_show_flower_war_return_event_overlay(report)

func _show_flower_war_return_event_overlay(report: Dictionary) -> void:
	_clear_flower_war_event_overlay()
	var root: VBoxContainer = _create_flower_war_event_panel("FlowerWarReturnPanel", Color(0.045, 0.035, 0.020, 0.97), Color(0.78, 0.58, 0.30, 0.90))
	var ok: bool = bool(report.get("ok", false))
	var direction: String = String(report.get("war_direction", "attack"))
	var return_title: String = "FLOWER WAR RETURN"
	if direction == "defence":
		return_title = "FLOWER WAR DEFENCE RETURN"
	root.add_child(_barracks_label(return_title, 34, COLOR_TEXT))
	if not ok:
		root.add_child(_barracks_wrapped_label("The muster failed: " + String(report.get("reason", "unknown reason")) + ".", 20, Color(1.0, 0.74, 0.40, 1.0)))
		_build_flower_war_return_footer(root)
		return
	root.add_child(_barracks_label(String(report.get("result", "Unknown")).to_upper(), 30, COLOR_TEAL))
	if direction == "defence":
		root.add_child(_barracks_wrapped_label("Strategy: " + String(report.get("defence_strategy_name", "Balanced Defence")) + " | Enemy casualties: " + str(int(report.get("enemy_casualties", 0))) + " | Prestige " + _format_signed_prestige_ui(float(report.get("prestige_gain", 0.0))) + " | Warriors defending: " + str(int(report.get("warriors_committed", 0))) + " | Returned ready: " + str(int(report.get("warriors_returned", 0))), 18, COLOR_MUTED))
	else:
		root.add_child(_barracks_wrapped_label("Captives taken: " + str(int(report.get("captives", 0))) + " | Loot value: " + _format_float(float(report.get("loot_value", 0.0))) + " | Prestige " + _format_signed_prestige_ui(float(report.get("prestige_gain", 0.0))) + " | Warriors sent: " + str(int(report.get("warriors_committed", 0))) + " | Returned ready: " + str(int(report.get("warriors_returned", 0))), 18, COLOR_MUTED))

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	_build_flower_war_return_warband_cards(body, report)
	_build_flower_war_return_spoils_panel(body, report)
	_build_flower_war_return_footer(root)

func _build_flower_war_return_warband_cards(parent: HBoxContainer, report: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.038, 0.036, 0.88), Color(0.50, 0.82, 0.74, 0.50), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)
	stack.add_child(_barracks_label("Warbands Returned", 24, COLOR_TEXT))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	stack.add_child(grid)
	var reports: Array = report.get("participant_reports", []) as Array
	if reports.is_empty():
		grid.add_child(_barracks_wrapped_label("No per-warband report was recorded.", 17, COLOR_MUTED))
		return
	for participant_variant: Variant in reports:
		var participant: Dictionary = participant_variant as Dictionary
		_add_flower_war_return_single_warband_card(grid, participant)

func _add_flower_war_return_single_warband_card(parent: GridContainer, participant: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.050, 0.046, 0.82), Color(0.50, 0.82, 0.74, 0.46), 10))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_barracks_label(String(participant.get("name", "Warband")), 19, COLOR_TEXT))
	var sent: int = int(participant.get("sent", participant.get("committed", 0)))
	var returned_ready: int = int(participant.get("returned_ready", max(0, sent - int(participant.get("casualties", 0)))))
	stack.add_child(_barracks_wrapped_label("Sent: " + str(sent), 15, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Returned ready: " + str(returned_ready), 15, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label("✚ Injured: " + str(int(participant.get("injured", 0))), 15, Color(0.80, 1.0, 0.88, 1.0)))
	stack.add_child(_barracks_wrapped_label("Dead: " + str(int(participant.get("dead", 0))), 15, Color(0.72, 0.70, 0.66, 1.0)))
	stack.add_child(_barracks_wrapped_label("XP: +" + str(int(participant.get("xp_gained", 0))), 15, COLOR_TEAL))

func _build_flower_war_return_spoils_panel(parent: HBoxContainer, report: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.030, 0.020, 0.88), Color(0.78, 0.58, 0.30, 0.58), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Spoils & Consequences", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Captives: " + str(int(report.get("captives", 0))), 18, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label("Loot: " + _flower_war_event_loot_text(report.get("loot", {}) as Dictionary), 16, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Total injured: ✚ " + str(int(report.get("attacker_injured", 0))) + ". Dead: " + str(int(report.get("attacker_dead", 0))) + ".", 16, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Prestige: " + _format_signed_prestige_ui(float(report.get("prestige_gain", 0.0))), 18, Color(1.0, 0.82, 0.44, 1.0)))
	var prestige_breakdown: Dictionary = report.get("prestige_breakdown", {}) as Dictionary
	var prestige_lines: Array = prestige_breakdown.get("lines", []) as Array
	for prestige_line_variant: Variant in prestige_lines:
		stack.add_child(_barracks_wrapped_label("• " + String(prestige_line_variant), 14, COLOR_MUTED))
	var level_reports: Array = report.get("level_reports", []) as Array
	if not level_reports.is_empty():
		for line_variant: Variant in level_reports:
			stack.add_child(_barracks_wrapped_label(String(line_variant), 15, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label("The dead are recorded here and in war reports, not on normal warband cards. Injured warriors remain out of the ready pool until the next Veintena advance.", 15, COLOR_MUTED))

func _build_flower_war_return_footer(parent: VBoxContainer) -> void:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 10)
	parent.add_child(footer)
	var note: Label = _barracks_wrapped_label("This return is archived under Barracks → War Returns as a codex war report.", 15, COLOR_MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)
	var continue_button: Button = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(150, 42)
	continue_button.add_theme_font_size_override("font_size", 16)
	continue_button.pressed.connect(func() -> void:
		_close_flower_war_event_overlay()
		_refresh_all()
	)
	footer.add_child(continue_button)


# -----------------------------------------------------------------------------
# Host bridge helpers
# -----------------------------------------------------------------------------

func _state() -> Node:
	if host != null and host.has_method("_state"):
		var raw: Variant = host.call("_state")
		if raw is Node:
			return raw as Node
	return null

func _refresh_all() -> void:
	if host != null and host.has_method("_refresh_all"):
		host.call("_refresh_all")


func _push_host_skill_web_report(message: String) -> void:
	if host == null:
		return
	var report_variant: Variant = host.get("_last_skill_web_report")
	var report: Array[String] = []
	if report_variant is Array:
		for item: Variant in report_variant as Array:
			report.append(String(item))
	report.clear()
	report.append(message)
	host.set("_last_skill_web_report", report)

func _barracks_label(text: String, font_size: int, colour: Color) -> Label:
	if host != null and host.has_method("_barracks_label"):
		var raw: Variant = host.call("_barracks_label", text, font_size, colour)
		if raw is Label:
			return raw as Label
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label

func _barracks_wrapped_label(text: String, font_size: int, colour: Color) -> Label:
	if host != null and host.has_method("_barracks_wrapped_label"):
		var raw: Variant = host.call("_barracks_wrapped_label", text, font_size, colour)
		if raw is Label:
			return raw as Label
	var label: Label = _barracks_label(text, font_size, colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	return label

func _make_panel_style(bg_colour: Color, border_colour: Color, radius: int = 10) -> StyleBox:
	if host != null and host.has_method("_make_panel_style"):
		var raw: Variant = host.call("_make_panel_style", bg_colour, border_colour, radius)
		if raw is StyleBox:
			return raw as StyleBox
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_colour
	style.border_color = border_colour
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

func _format_float(value: float) -> String:
	if host != null and host.has_method("_format_float"):
		return String(host.call("_format_float", value))
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))

func _format_signed_prestige_ui(value: float) -> String:
	if host != null and host.has_method("_format_signed_prestige_ui"):
		return String(host.call("_format_signed_prestige_ui", value))
	return ("+" if value >= 0.0 else "") + _format_float(value)

func _barracks_flower_options() -> Array[Dictionary]:
	if host != null and host.has_method("_barracks_flower_options"):
		var raw: Variant = host.call("_barracks_flower_options")
		if raw is Array:
			var output: Array[Dictionary] = []
			for item: Variant in raw as Array:
				if item is Dictionary:
					output.append(item as Dictionary)
			return output
	return []

func _barracks_warband_rows() -> Array[Dictionary]:
	if host != null and host.has_method("_barracks_warband_rows"):
		var raw: Variant = host.call("_barracks_warband_rows")
		if raw is Array:
			var output: Array[Dictionary] = []
			for item: Variant in raw as Array:
				if item is Dictionary:
					output.append(item as Dictionary)
			return output
	return []

func _warband_combat_stats(row: Dictionary) -> Dictionary:
	if host != null and host.has_method("_warband_combat_stats"):
		var raw: Variant = host.call("_warband_combat_stats", row)
		if raw is Dictionary:
			return raw as Dictionary
	return row.get("combat_stats", {}) as Dictionary

func _barracks_preview_for_selected_warbands(warband_ids: Array, option_id: String, provisioning_id: String) -> Dictionary:
	if host != null and host.has_method("_barracks_preview_for_selected_warbands"):
		var raw: Variant = host.call("_barracks_preview_for_selected_warbands", warband_ids, option_id, provisioning_id)
		if raw is Dictionary:
			return raw as Dictionary
	return {"ok": false, "reason": "Flower War preview bridge is not connected."}

func _barracks_can_launch_selected_warbands(warband_ids: Array, option_id: String, provisioning_id: String) -> Dictionary:
	if host != null and host.has_method("_barracks_can_launch_selected_warbands"):
		var raw: Variant = host.call("_barracks_can_launch_selected_warbands", warband_ids, option_id, provisioning_id)
		if raw is Dictionary:
			return raw as Dictionary
	return {"ok": false, "reason": "Flower War launch bridge is not connected."}

func _barracks_defence_strategies() -> Array[Dictionary]:
	if host != null and host.has_method("_barracks_defence_strategies"):
		var raw: Variant = host.call("_barracks_defence_strategies")
		if raw is Array:
			var output: Array[Dictionary] = []
			for item: Variant in raw as Array:
				if item is Dictionary:
					output.append(item as Dictionary)
			return output
	return []

func _barracks_preview_for_defence(option_id: String, strategy_id: String) -> Dictionary:
	if host != null and host.has_method("_barracks_preview_for_defence"):
		var raw: Variant = host.call("_barracks_preview_for_defence", option_id, strategy_id)
		if raw is Dictionary:
			return raw as Dictionary
	return {"ok": false, "reason": "Defence preview bridge is not connected."}

func _barracks_can_resolve_defence(option_id: String, strategy_id: String) -> Dictionary:
	if host != null and host.has_method("_barracks_can_resolve_defence"):
		var raw: Variant = host.call("_barracks_can_resolve_defence", option_id, strategy_id)
		if raw is Dictionary:
			return raw as Dictionary
	return {"ok": false, "reason": "Defence resolver bridge is not connected."}

func _flower_war_event_cost_text(cost: Dictionary) -> String:
	if host != null and host.has_method("_flower_war_event_cost_text"):
		return String(host.call("_flower_war_event_cost_text", cost))
	if cost.is_empty():
		return "none"
	var parts: Array[String] = []
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		parts.append(resource_id.replace("_", " ").capitalize() + " " + _format_float(float(cost[resource_variant])))
	return ", ".join(parts)

func _flower_war_event_loot_text(loot: Dictionary) -> String:
	if host != null and host.has_method("_flower_war_event_loot_text"):
		return String(host.call("_flower_war_event_loot_text", loot))
	return _flower_war_event_cost_text(loot)
