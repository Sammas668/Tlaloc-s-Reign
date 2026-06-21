# PalaceScreenController.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/PalaceScreenController.gd
#
# Extracted Palace / Prestige presentation controller.
# GameScreenMarketOverviewPatch.gd remains the coordinator, but the large
# Palace main view and Palace report UI live here so the wrapper does not keep
# absorbing major screen code.
extends RefCounted

const PalacePresentationRules: Script = preload("res://Scripts/Systems/PalacePresentationRules.gd")

var host: Node = null
var dynamic_view_host: VBoxContainer = null
var content_root: Control = null
var content_text: Control = null
var notification_list: VBoxContainer = null

var _selected_palace_route_id: String = ""
var _pending_palace_dedication_confirm_id: String = ""

func show_palace_content(host_node: Node, dynamic_host: VBoxContainer, root_node: Control, text_node: Control) -> void:
	host = host_node
	dynamic_view_host = dynamic_host
	content_root = root_node
	content_text = text_node
	_show_palace_content()

func build_palace_navigation_probe_reports(host_node: Node, notifications: VBoxContainer) -> void:
	host = host_node
	notification_list = notifications
	_build_palace_navigation_probe_reports()

func reset_divine_seat_selection() -> void:
	_selected_palace_route_id = ""
	_pending_palace_dedication_confirm_id = ""

# -----------------------------------------------------------------------------

func _show_palace_content() -> void:
	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false
	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return
	dynamic_view_host.visible = true
	match _current_focus_id():
		"prestige":
			_build_palace_prestige_main_view()
		"divine_seat":
			_build_palace_divine_seat_main_view()
		"authority":
			_build_palace_authority_main_view()
		"ruler_demands":
			_build_palace_ruler_demands_main_view()
		_:
			_build_palace_overview_main_view()

func _build_palace_placeholder_main_view(title_text: String, body_text: String) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.030, 0.024, 0.90), Color(0.70, 0.58, 0.34, 0.55), 16))
	dynamic_view_host.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)
	var title_label: Label = _palace_label(title_text, 34, Color(0.96, 0.86, 0.58, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title_label)
	var body: RichTextLabel = _palace_wrapped_label(body_text, 20, Color(0.80, 0.82, 0.76, 1.0))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(body)


func _build_palace_ruler_demands_main_view() -> void:
	var state: Node = _state()
	var demands: Dictionary = {}
	if state != null and state.has_method("get_palace_ruler_demands_summary"):
		demands = state.call("get_palace_ruler_demands_summary") as Dictionary
	elif state != null and state.has_method("get_palace_summary"):
		var summary: Dictionary = state.call("get_palace_summary") as Dictionary
		demands = summary.get("ruler_demands", {}) as Dictionary
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.026, 0.020, 0.92), Color(0.78, 0.62, 0.34, 0.62), 18))
	dynamic_view_host.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title_label: Label = _palace_label("COURT NEEDS", 33, Color(1.0, 0.86, 0.50, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title_label)
	if demands.is_empty():
		root.add_child(_palace_wrapped_label("Court-needs backend data is not connected yet.", 18, Color(0.86, 0.80, 0.68, 1.0)))
		return
	root.add_child(_palace_wrapped_label(String(demands.get("title", "Current Court Needs")), 22, Color(0.96, 0.78, 0.46, 1.0)))
	root.add_child(_palace_wrapped_label(String(demands.get("flavour", "The court currently needs these goods. Donating them creates public prestige.")), 16, Color(0.82, 0.84, 0.76, 1.0)))
	root.add_child(_palace_wrapped_label(String(demands.get("headline", "Court needs donation prototype active.")), 15, Color(0.74, 0.94, 0.72, 1.0)))

	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_theme_constant_override("separation", 10)
	root.add_child(status_row)
	_add_palace_summary_card(status_row, "Cycle", String(demands.get("veintena_band", "Prototype")), String(demands.get("cycle_window", "Controlled test need, not random politics.")), Color(0.88, 0.70, 0.40, 1.0))
	_add_palace_summary_card(status_row, "Deadline", String(demands.get("urgency_label", "Time remains")), str(int(demands.get("veintenas_remaining", 0))) + " Veintena" + ("s" if int(demands.get("veintenas_remaining", 0)) != 1 else "") + " remaining including the current turn.", Color(0.92, 0.64, 0.42, 1.0))
	_add_palace_summary_card(status_row, "Donated", String(demands.get("donation_label", "0 / 3 needs donated to")), "Donation is optional and can be partial; prestige comes from value donated.", Color(0.72, 0.92, 0.70, 1.0))
	_add_palace_summary_card(status_row, "Prestige", "+" + _format_religion_amount(float(demands.get("total_donated_prestige", 0.0))) + " this cycle", "Player Prestige: " + _format_religion_amount(float(demands.get("player_prestige", 0.0))) + ". Prestige is score only, never spent.", Color(0.96, 0.80, 0.52, 1.0))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var rows: Array = demands.get("rows", []) as Array
	for row_variant: Variant in rows:
		if row_variant is Dictionary:
			_add_palace_ruler_demand_row_card(list, row_variant as Dictionary)
	_add_palace_ruler_demand_cycle_archive_panel(list, demands.get("cycle_archive", []) as Array)
	var note_panel: PanelContainer = PanelContainer.new()
	note_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.020, 0.018, 0.88), Color(0.42, 0.42, 0.34, 0.50), 10))
	list.add_child(note_panel)
	var note_margin: MarginContainer = MarginContainer.new()
	note_margin.add_theme_constant_override("margin_left", 12)
	note_margin.add_theme_constant_override("margin_top", 8)
	note_margin.add_theme_constant_override("margin_right", 12)
	note_margin.add_theme_constant_override("margin_bottom", 8)
	note_panel.add_child(note_margin)
	note_margin.add_child(_palace_wrapped_label(String(demands.get("mechanics_note", "Donations create prestige by base value. Prestige is score only.")), 14, Color(0.74, 0.76, 0.68, 1.0)))

func _add_palace_ruler_demand_cycle_archive_panel(parent: VBoxContainer, archive_rows: Array) -> void:
	if archive_rows.is_empty():
		return
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.026, 0.026, 0.022, 0.92), Color(0.66, 0.55, 0.34, 0.58), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	margin.add_child(stack)
	stack.add_child(_palace_label("Court Need Donation Record", 20, Color(0.96, 0.78, 0.46, 1.0)))
	stack.add_child(_palace_wrapped_label("A compact record of visible court-need cycles and the prestige generated by donations.", 14, Color(0.76, 0.80, 0.70, 1.0)))
	for cycle_variant: Variant in archive_rows:
		if not (cycle_variant is Dictionary):
			continue
		var cycle: Dictionary = cycle_variant as Dictionary
		var line_colour: Color = Color(0.74, 0.76, 0.68, 1.0)
		if bool(cycle.get("is_current", false)):
			line_colour = Color(0.92, 0.86, 0.56, 1.0)
		var prefix: String = "Current — " if bool(cycle.get("is_current", false)) else "Record — "
		var line: String = prefix + String(cycle.get("title", "Court Need Cycle")) + " (" + String(cycle.get("cycle_window", cycle.get("veintena_band", "Prototype"))) + "): " + str(int(cycle.get("donation_count", 0))) + " donations; +" + _format_religion_amount(float(cycle.get("donated_prestige", 0.0))) + " Prestige."
		stack.add_child(_palace_wrapped_label(line, 14, line_colour))

func _add_palace_ruler_demand_row_card(parent: VBoxContainer, row: Dictionary) -> void:
	var can_donate: bool = bool(row.get("can_donate", false))
	var donated: bool = bool(row.get("delivered", false))
	var border: Color = Color(0.54, 0.90, 0.58, 0.80) if can_donate else Color(1.0, 0.58, 0.34, 0.82)
	if donated:
		border = Color(0.96, 0.78, 0.42, 0.90)
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.022, 0.024, 0.022, 0.92), border, 11))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 9)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	var top: HBoxContainer = HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 8)
	stack.add_child(top)
	var title: Label = _palace_label(String(row.get("slot_name", "Court need")) + " — " + String(row.get("resource_name", "Good")), 19, border.lightened(0.20))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var status: Label = _palace_label(String(row.get("status", "Unknown")), 15, border.lightened(0.10))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.custom_minimum_size = Vector2(150, 0)
	top.add_child(status)
	stack.add_child(_palace_wrapped_label(String(row.get("note", "Court-facing need.")), 14, Color(0.82, 0.84, 0.76, 1.0)))
	var need_marker: float = float(row.get("needed_marker", row.get("requested", 0.0)))
	var stored: float = float(row.get("stored", 0.0))
	var free_value: float = float(row.get("free_after_reserves", 0.0))
	var base_value: float = float(row.get("base_value", 1.0))
	var donated_amount: float = float(row.get("donated_amount", row.get("delivered_amount", 0.0)))
	var donated_prestige: float = float(row.get("donated_prestige", 0.0))
	stack.add_child(_palace_wrapped_label("Visible need marker: " + _format_religion_amount(need_marker) + " | Stored: " + _format_religion_amount(stored) + " | Free after reserves: " + _format_religion_amount(free_value), 14, Color(0.76, 0.82, 0.74, 1.0)))
	stack.add_child(_palace_wrapped_label("Prestige formula: donated amount × base value. Base value of " + String(row.get("resource_name", "Good")) + ": " + _format_religion_amount(base_value) + ". Need marker value: +" + _format_religion_amount(float(row.get("prestige_for_need_marker", 0.0))) + " Prestige.", 13, Color(0.84, 0.82, 0.66, 1.0)))
	if donated_amount > 0.001:
		stack.add_child(_palace_wrapped_label("Donated this cycle: " + _format_religion_amount(donated_amount) + " " + String(row.get("resource_name", "Good")) + " → +" + _format_religion_amount(donated_prestige) + " Prestige.", 13, Color(0.96, 0.82, 0.48, 1.0)))
	elif can_donate:
		stack.add_child(_palace_wrapped_label("You may donate any free amount of this needed good. More value donated creates more prestige.", 13, Color(0.66, 0.92, 0.68, 1.0)))
	else:
		stack.add_child(_palace_wrapped_label("No free stock is available for this needed good after reserves.", 13, Color(1.0, 0.72, 0.45, 1.0)))

	var max_donation: float = maxf(0.0, float(row.get("max_donation", free_value)))
	var starting_amount: float = 0.0
	if max_donation > 0.001:
		starting_amount = minf(maxf(1.0, need_marker), max_donation)

	var donate_box: VBoxContainer = VBoxContainer.new()
	donate_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	donate_box.add_theme_constant_override("separation", 4)
	stack.add_child(donate_box)

	var control_row: HBoxContainer = HBoxContainer.new()
	control_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_row.add_theme_constant_override("separation", 8)
	donate_box.add_child(control_row)

	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = max_donation
	slider.step = 1.0
	slider.value = starting_amount
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220, 34)
	slider.editable = can_donate
	slider.focus_mode = Control.FOCUS_NONE
	control_row.add_child(slider)

	var amount_box: LineEdit = LineEdit.new()
	amount_box.text = _format_religion_amount(starting_amount)
	amount_box.placeholder_text = "0"
	amount_box.custom_minimum_size = Vector2(118, 38)
	amount_box.editable = can_donate
	amount_box.focus_mode = Control.FOCUS_CLICK
	amount_box.tooltip_text = "Type a donation amount. Mouse-wheel scrolling will not alter this value."
	control_row.add_child(amount_box)

	var button: Button = Button.new()
	button.text = "Donate"
	button.custom_minimum_size = Vector2(120, 38)
	button.add_theme_font_size_override("font_size", 16)
	button.disabled = (not can_donate) or starting_amount <= 0.001
	button.tooltip_text = String(row.get("donation_status", row.get("delivery_status", "")))
	control_row.add_child(button)

	var preview_label: Label = _palace_label("", 14, Color(0.96, 0.82, 0.48, 1.0))
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	donate_box.add_child(preview_label)

	var donation_input_state: Dictionary = {"amount": starting_amount, "syncing": false}

	var update_preview := func(value: float, sync_text: bool) -> void:
		var clamped_value: float = clampf(value, 0.0, max_donation)
		donation_input_state["amount"] = clamped_value
		donation_input_state["syncing"] = true
		if not is_equal_approx(float(slider.value), clamped_value):
			slider.value = clamped_value
		if sync_text:
			amount_box.text = _format_religion_amount(clamped_value)
		donation_input_state["syncing"] = false
		var prestige_preview: float = clamped_value * base_value
		preview_label.text = "Donate " + _format_religion_amount(clamped_value) + " / " + _format_religion_amount(max_donation) + " free " + String(row.get("resource_name", "Good")) + "  →  Prestige +" + _format_religion_amount(prestige_preview)
		button.disabled = (not can_donate) or clamped_value <= 0.001

	var apply_typed_amount := func(finalise_text: bool) -> void:
		if bool(donation_input_state.get("syncing", false)):
			return
		var raw_text: String = amount_box.text.strip_edges()
		if raw_text == "":
			update_preview.call(0.0, finalise_text)
			return
		if not raw_text.is_valid_float():
			if finalise_text:
				amount_box.text = _format_religion_amount(float(donation_input_state.get("amount", 0.0)))
			return
		update_preview.call(float(raw_text), finalise_text)

	# Godot Range controls can respond to mouse-wheel input when hovered/focused.
	# This row deliberately ignores wheel events on the donation slider so normal
	# page scrolling cannot silently change the planned tribute amount. The amount
	# can still be changed by dragging the slider or typing in the box.
	slider.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse_event: InputEventMouseButton = event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN or mouse_event.button_index == MOUSE_BUTTON_WHEEL_LEFT or mouse_event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
				slider.accept_event()
				update_preview.call(float(donation_input_state.get("amount", 0.0)), true)
	)

	slider.value_changed.connect(func(value: float) -> void:
		if bool(donation_input_state.get("syncing", false)):
			return
		update_preview.call(value, true)
	)
	amount_box.text_changed.connect(func(_new_text: String) -> void:
		apply_typed_amount.call(false)
	)
	amount_box.text_submitted.connect(func(_submitted_text: String) -> void:
		apply_typed_amount.call(true)
	)
	amount_box.focus_exited.connect(func() -> void:
		apply_typed_amount.call(true)
	)
	update_preview.call(starting_amount, true)

	var slot_id: String = String(row.get("slot", ""))
	button.pressed.connect(func() -> void:
		var state: Node = _state()
		if state != null and state.has_method("donate_palace_need"):
			state.call("donate_palace_need", slot_id, float(donation_input_state.get("amount", 0.0)))
		elif state != null and state.has_method("deliver_palace_ruler_demand"):
			state.call("deliver_palace_ruler_demand", slot_id)
		_refresh_all()
	)


func _build_palace_authority_main_view() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var authority: Dictionary = {}
	if summary.has("authority_summary") and summary["authority_summary"] is Dictionary:
		authority = summary["authority_summary"] as Dictionary
	else:
		authority = {"dedicated": bool(summary.get("dedicated", false)), "god_id": String(summary.get("dedicated_god", "")), "god_name": String(summary.get("dedicated_god_name", "None")), "route_name": String(summary.get("route_name", "No dedication")), "headline": String(summary.get("authority_status", "Palace authority not connected.")), "body": String(summary.get("power_summary", "")), "active_structures": [], "inactive_structures": [], "next_locked_structures": [], "mechanics_note": "Authority summary backend not connected."}
	var god_id: String = String(authority.get("god_id", summary.get("dedicated_god", "")))
	var colour: Color = _palace_route_colour(god_id)
	var outer: PanelContainer = PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", _make_panel_style(Color(0.024, 0.022, 0.018, 0.94), colour.darkened(0.24), 18))
	dynamic_view_host.add_child(outer)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	outer.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var title: Label = _palace_label("PALACE AUTHORITY", 33, Color(1.0, 0.86, 0.50, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(_palace_wrapped_label(String(authority.get("headline", "Palace Authority")), 21, colour.lightened(0.24)))
	root.add_child(_palace_wrapped_label(String(authority.get("body", "Dedicate and build palace structures to reveal this route's authority.")), 17, Color(0.82, 0.86, 0.78, 1.0)))
	root.add_child(_palace_wrapped_label(String(authority.get("mechanics_note", "This screen reads active palace structures only.")), 14, Color(0.92, 0.74, 0.48, 1.0)))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	scroll.add_child(stack)

	var active_rows: Array = authority.get("active_structures", []) as Array
	var inactive_rows: Array = authority.get("inactive_structures", []) as Array
	var locked_rows: Array = authority.get("next_locked_structures", []) as Array
	if god_id == "tlaloc":
		var forecast: Dictionary = {}
		var state: Node = _state()
		if state != null and state.has_method("get_tlaloc_natural_calendar_forecast"):
			forecast = state.call("get_tlaloc_natural_calendar_forecast") as Dictionary
		_add_tlaloc_forecast_panel(stack, forecast, colour)
	elif god_id == "tezcatlipoca":
		var pressure: Dictionary = {}
		var tez_state: Node = _state()
		if tez_state != null and tez_state.has_method("get_tezcatlipoca_pressure_overview"):
			pressure = tez_state.call("get_tezcatlipoca_pressure_overview") as Dictionary
		_add_tezcatlipoca_pressure_panel(stack, pressure, colour)
	elif god_id == "quetzalcoatl":
		var legitimacy: Dictionary = {}
		var quetz_state: Node = _state()
		if quetz_state != null and quetz_state.has_method("get_quetzalcoatl_legitimacy_overview"):
			legitimacy = quetz_state.call("get_quetzalcoatl_legitimacy_overview") as Dictionary
		_add_quetzalcoatl_legitimacy_panel(stack, legitimacy, colour)
	_add_palace_authority_section(stack, "Active Authority Structures", active_rows, colour, true)
	_add_palace_authority_section(stack, "Inactive Built Structures", inactive_rows, Color(1.0, 0.58, 0.34, 1.0), false)
	_add_palace_authority_locked_section(stack, locked_rows, colour)

func _add_tlaloc_forecast_panel(parent: VBoxContainer, forecast: Dictionary, colour: Color) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.032, 0.038, 0.92), colour.lightened(0.08), 14))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(forecast.get("headline", "Tlaloc Natural Calendar Foresight")), 22, colour.lightened(0.26)))
	stack.add_child(_palace_wrapped_label(String(forecast.get("summary", "Build and maintain active Tlaloc palace structures to reveal upcoming natural pressure.")), 15, Color(0.82, 0.88, 0.80, 1.0)))
	var active_structures: Array = forecast.get("active_structures", []) as Array
	if not active_structures.is_empty():
		stack.add_child(_palace_wrapped_label("Reading through: " + ", ".join(active_structures) + ".", 13, Color(0.70, 0.90, 0.86, 1.0)))
	var events: Array = forecast.get("events", []) as Array
	if events.is_empty():
		stack.add_child(_palace_wrapped_label("No natural pressures are currently visible at this palace authority level.", 14, Color(0.72, 0.76, 0.70, 1.0)))
	else:
		for event_variant: Variant in events:
			if event_variant is Dictionary:
				_add_tlaloc_forecast_event_card(stack, event_variant as Dictionary, colour)
	stack.add_child(_palace_wrapped_label(String(forecast.get("mechanics_note", "Forecast rows are information-only for now.")), 13, Color(0.94, 0.76, 0.48, 1.0)))

func _add_tlaloc_forecast_event_card(parent: VBoxContainer, row: Dictionary, colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.010, 0.020, 0.024, 0.86), colour.darkened(0.06), 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(row.get("timing", "Soon")) + " — " + String(row.get("name", "Natural pressure")), 18, colour.lightened(0.22)))
	stack.add_child(_palace_wrapped_label(String(row.get("category", "Natural pressure")) + ": " + String(row.get("summary", "The palace senses pressure in the natural calendar.")), 14, Color(0.82, 0.86, 0.78, 1.0)))
	stack.add_child(_palace_wrapped_label("Severity: " + String(row.get("severity", "Hidden")) + " | Goods: " + String(row.get("affected_goods", "Hidden")) + " | Duration: " + String(row.get("duration", "Hidden")), 13, Color(0.72, 0.80, 0.74, 1.0)))
	if int(row.get("detail_tier", 0)) >= 4:
		stack.add_child(_palace_wrapped_label("Preparation: " + String(row.get("preparation", "No preparation advice revealed.")), 13, Color(0.86, 0.84, 0.62, 1.0)))


func _add_tezcatlipoca_pressure_panel(parent: VBoxContainer, pressure: Dictionary, colour: Color) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.022, 0.034, 0.92), colour.lightened(0.08), 14))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(pressure.get("headline", "Tezcatlipoca Scarcity Mirror")), 22, colour.lightened(0.26)))
	stack.add_child(_palace_wrapped_label(String(pressure.get("summary", "Build and maintain active Tezcatlipoca palace structures to reveal scarcity and rival pressure hooks.")), 15, Color(0.84, 0.82, 0.88, 1.0)))
	var active_structures: Array = pressure.get("active_structures", []) as Array
	if not active_structures.is_empty():
		stack.add_child(_palace_wrapped_label("Reading through: " + ", ".join(active_structures) + ".", 13, Color(0.86, 0.78, 0.96, 1.0)))
	var market_rows: Array = pressure.get("market_pressure_rows", []) as Array
	if market_rows.is_empty():
		stack.add_child(_palace_wrapped_label("No market pressure is currently visible at this palace authority level.", 14, Color(0.74, 0.72, 0.76, 1.0)))
	else:
		stack.add_child(_palace_label("Market Pressure Readings", 18, Color(1.0, 0.84, 0.54, 1.0)))
		for row_variant: Variant in market_rows:
			if row_variant is Dictionary:
				_add_tezcatlipoca_market_pressure_card(stack, row_variant as Dictionary, colour)
	var rival_rows: Array = pressure.get("rival_pressure_rows", []) as Array
	if not rival_rows.is_empty():
		stack.add_child(_palace_label("Rival Pressure Hooks", 18, Color(1.0, 0.84, 0.54, 1.0)))
		for row_variant: Variant in rival_rows:
			if row_variant is Dictionary:
				_add_tezcatlipoca_rival_pressure_card(stack, row_variant as Dictionary, colour)
	stack.add_child(_palace_wrapped_label(String(pressure.get("mechanics_note", "Tezcatlipoca pressure rows are information-only for now.")), 13, Color(0.94, 0.76, 0.48, 1.0)))

func _add_tezcatlipoca_market_pressure_card(parent: VBoxContainer, row: Dictionary, colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.014, 0.022, 0.88), colour.darkened(0.08), 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(row.get("name", "Good")) + " — " + String(row.get("pressure", "Pressure")), 18, colour.lightened(0.24)))
	stack.add_child(_palace_wrapped_label("Exposure: " + String(row.get("exposure", "Hidden")) + " | Coverage: " + String(row.get("coverage", "Hidden")) + " | Value: " + String(row.get("current_value", "Hidden")), 13, Color(0.78, 0.82, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label(String(row.get("leverage", "Future market-pressure hook.")), 13, Color(0.86, 0.80, 0.62, 1.0)))

func _add_tezcatlipoca_rival_pressure_card(parent: VBoxContainer, row: Dictionary, colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.014, 0.022, 0.84), colour.darkened(0.14), 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(row.get("rival", "Rival")) + " — pressure point", 18, colour.lightened(0.22)))
	stack.add_child(_palace_wrapped_label("Domain: " + String(row.get("domain", "Hidden")), 13, Color(0.78, 0.82, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label(String(row.get("summary", "The mirror reveals an unclear rival weakness.")), 13, Color(0.82, 0.84, 0.78, 1.0)))
	stack.add_child(_palace_wrapped_label(String(row.get("future_hook", "Future manipulation hook.")), 13, Color(0.86, 0.80, 0.62, 1.0)))


func _add_quetzalcoatl_legitimacy_panel(parent: VBoxContainer, legitimacy: Dictionary, colour: Color) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.024, 0.034, 0.026, 0.92), colour.lightened(0.08), 14))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(legitimacy.get("headline", "Quetzalcoatl Legitimacy Court")), 22, colour.lightened(0.26)))
	stack.add_child(_palace_wrapped_label(String(legitimacy.get("summary", "Build and maintain active Quetzalcoatl palace structures to reveal legitimacy, recognition and tribute-credibility hooks.")), 15, Color(0.84, 0.88, 0.80, 1.0)))
	var active_structures: Array = legitimacy.get("active_structures", []) as Array
	if not active_structures.is_empty():
		stack.add_child(_palace_wrapped_label("Reading through: " + ", ".join(active_structures) + ".", 13, Color(0.86, 0.94, 0.76, 1.0)))
	var legitimacy_rows: Array = legitimacy.get("legitimacy_rows", []) as Array
	if legitimacy_rows.is_empty():
		stack.add_child(_palace_wrapped_label("No legitimacy hooks are currently visible at this palace authority level.", 14, Color(0.74, 0.76, 0.70, 1.0)))
	else:
		stack.add_child(_palace_label("Legitimacy and Recognition Hooks", 18, Color(1.0, 0.88, 0.56, 1.0)))
		for row_variant: Variant in legitimacy_rows:
			if row_variant is Dictionary:
				_add_quetzalcoatl_legitimacy_card(stack, row_variant as Dictionary, colour)
	var obligation_rows: Array = legitimacy.get("obligation_rows", []) as Array
	if not obligation_rows.is_empty():
		stack.add_child(_palace_label("Tribute Credibility Readings", 18, Color(1.0, 0.88, 0.56, 1.0)))
		for row_variant: Variant in obligation_rows:
			if row_variant is Dictionary:
				_add_quetzalcoatl_legitimacy_card(stack, row_variant as Dictionary, colour)
	stack.add_child(_palace_wrapped_label(String(legitimacy.get("mechanics_note", "Quetzalcoatl authority rows are information-only for now.")), 13, Color(0.94, 0.76, 0.48, 1.0)))

func _add_quetzalcoatl_legitimacy_card(parent: VBoxContainer, row: Dictionary, colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.014, 0.022, 0.016, 0.88), colour.darkened(0.08), 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(row.get("name", "Legitimacy")), 18, colour.lightened(0.24)))
	stack.add_child(_palace_wrapped_label("Domain: " + String(row.get("domain", "Hidden")), 13, Color(0.78, 0.82, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label(String(row.get("summary", "The palace reveals a legitimacy hook.")), 13, Color(0.82, 0.86, 0.78, 1.0)))
	stack.add_child(_palace_wrapped_label(String(row.get("future_hook", "Future recognition hook.")), 13, Color(0.86, 0.82, 0.62, 1.0)))

func _add_palace_authority_section(parent: VBoxContainer, title_text: String, rows: Array, colour: Color, active_section: bool) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.026, 0.028, 0.023, 0.90), colour.darkened(0.08), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	stack.add_child(_palace_label(title_text, 21, Color(1.0, 0.84, 0.54, 1.0)))
	if rows.is_empty():
		var empty_text: String = "No active palace structures yet. Build structures, pay their maintenance and provide staff to activate authority."
		if not active_section:
			empty_text = "No built structures are currently inactive."
		stack.add_child(_palace_wrapped_label(empty_text, 14, Color(0.70, 0.74, 0.68, 1.0)))
		return
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		_add_palace_authority_structure_card(stack, row, colour, active_section)

func _add_palace_authority_structure_card(parent: VBoxContainer, row: Dictionary, colour: Color, active_section: bool) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border: Color = colour
	if not active_section:
		border = Color(1.0, 0.58, 0.34, 0.72)
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.020, 0.017, 0.86), border, 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	var status_text: String = "Active" if active_section else "Inactive"
	stack.add_child(_palace_label(String(row.get("name", "Palace Structure")) + " — " + status_text, 18, border.lightened(0.20)))
	stack.add_child(_palace_wrapped_label("Tier " + str(int(row.get("tier", 1))) + ". " + String(row.get("effect_summary", "Future authority hook.")), 14, Color(0.80, 0.84, 0.76, 1.0)))
	if active_section:
		stack.add_child(_palace_wrapped_label("Maintenance paid: " + _format_cost(row.get("maintenance_paid", {}) as Dictionary) + ". Staff assigned: " + _palace_format_staff_requirement(row.get("staff_assigned", {}) as Dictionary) + ".", 13, Color(0.70, 0.90, 0.66, 1.0)))
	else:
		stack.add_child(_palace_wrapped_label(String(row.get("inactive_reason", "Missing maintenance or staff.")), 13, Color(1.0, 0.72, 0.45, 1.0)))

func _add_palace_authority_locked_section(parent: VBoxContainer, rows: Array, colour: Color) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.022, 0.020, 0.84), Color(0.45, 0.48, 0.38, 0.55), 10))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	stack.add_child(_palace_label("Future Authority Locked Behind Structures", 18, Color(1.0, 0.84, 0.54, 1.0)))
	if rows.is_empty():
		stack.add_child(_palace_wrapped_label("No further palace structure data is visible for this route.", 14, Color(0.70, 0.74, 0.68, 1.0)))
		return
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		var line: String = String(row.get("name", "Structure")) + " — Tier " + str(int(row.get("tier", 1))) + ": " + String(row.get("effect_summary", "Future authority hook."))
		stack.add_child(_palace_wrapped_label(line, 14, Color(0.72, 0.78, 0.70, 1.0)))
		stack.add_child(_palace_wrapped_label("Status: " + String(row.get("build_status", "Locked.")), 13, Color(0.62, 0.68, 0.62, 1.0)))


func _build_palace_prestige_main_view() -> void:
	var state: Node = _state()
	var prestige: Dictionary = {}
	if state != null and state.has_method("get_prestige_summary"):
		prestige = state.call("get_prestige_summary") as Dictionary

	var outer: PanelContainer = PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", _make_panel_style(Color(0.026, 0.024, 0.019, 0.94), Color(0.76, 0.60, 0.34, 0.68), 18))
	dynamic_view_host.add_child(outer)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	outer.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title: Label = _palace_label("PALACE PRESTIGE", 33, Color(1.0, 0.86, 0.50, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(_palace_wrapped_label("Prestige is the house's public standing and main score. It is earned from visible actions such as court-need donations, Flower Wars, ritual sacrifice and savvy market trade. It is never spent.", 17, Color(0.83, 0.86, 0.78, 1.0)))

	if prestige.is_empty():
		root.add_child(_palace_wrapped_label("Prestige backend score data is not connected yet.", 18, Color(1.0, 0.72, 0.45, 1.0)))
		return

	var player_value: float = float(prestige.get("player_prestige", 0.0))
	var leaderboard: Array = prestige.get("leaderboard", []) as Array
	var player_rank: Dictionary = prestige.get("player_rank", {}) as Dictionary
	var rank_number: int = int(player_rank.get("rank", 0))
	var rank_text: String = "Rank pending"
	if rank_number > 0:
		rank_text = _ordinal_number(rank_number) + " of " + str(max(1, leaderboard.size())) + " houses"
	var recent: Array = prestige.get("recent_history", []) as Array
	var all_history: Array = prestige.get("prestige_history", []) as Array
	var source_rows: Array[Dictionary] = _prestige_source_rows(all_history)
	var latest_text: String = "No recent prestige gains recorded."
	if not recent.is_empty() and recent[0] is Dictionary:
		var latest: Dictionary = recent[0] as Dictionary
		latest_text = _prestige_signed_amount(float(latest.get("amount", 0.0))) + " — " + String(latest.get("detail", "Prestige changed"))
	var leader_text: String = "No leaderboard data"
	if not leaderboard.is_empty() and leaderboard[0] is Dictionary:
		var leader: Dictionary = leaderboard[0] as Dictionary
		leader_text = String(leader.get("name", "House")) + " " + _format_religion_amount(float(leader.get("prestige", 0.0)))

	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_theme_constant_override("separation", 10)
	root.add_child(status_row)
	_add_palace_summary_card(status_row, "Total", _format_religion_amount(player_value), "Current Player House Prestige.", Color(0.96, 0.80, 0.52, 1.0))
	_add_palace_summary_card(status_row, "Standing", rank_text, "Prestige is compared against rival houses.", Color(0.72, 0.92, 0.70, 1.0))
	_add_palace_summary_card(status_row, "Leader", leader_text, "Rival values are prototype comparison data until full rival turns are connected.", Color(0.90, 0.72, 0.44, 1.0))
	_add_palace_summary_card(status_row, "Latest", latest_text, "Most recent recorded Prestige change.", Color(0.68, 0.86, 0.94, 1.0))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	scroll.add_child(stack)

	stack.add_child(_palace_label("Prestige Source Breakdown", 23, Color(1.0, 0.84, 0.54, 1.0)))
	stack.add_child(_palace_wrapped_label("This shows where the score has actually come from so gains are not hidden in the background.", 14, Color(0.76, 0.80, 0.70, 1.0)))
	if source_rows.is_empty():
		stack.add_child(_palace_wrapped_label("No source history yet. Make a qualifying market trade, donate to a court need, win a Flower War or complete a prestige-granting ritual to create the first entry.", 15, Color(0.74, 0.78, 0.70, 1.0)))
	else:
		for row: Dictionary in source_rows:
			_add_palace_prestige_source_row_card(stack, row)

	stack.add_child(_palace_label("Recent Prestige Ledger", 23, Color(1.0, 0.84, 0.54, 1.0)))
	if recent.is_empty():
		stack.add_child(_palace_wrapped_label("No recent prestige entries recorded yet.", 15, Color(0.74, 0.78, 0.70, 1.0)))
	else:
		var recent_count: int = 0
		for item_variant: Variant in recent:
			if recent_count >= 12:
				break
			if item_variant is Dictionary:
				_add_palace_prestige_history_row_card(stack, item_variant as Dictionary)
				recent_count += 1

	stack.add_child(_palace_label("House Standing", 23, Color(1.0, 0.84, 0.54, 1.0)))
	if leaderboard.is_empty():
		stack.add_child(_palace_wrapped_label("No leaderboard data is available.", 15, Color(0.74, 0.78, 0.70, 1.0)))
	else:
		for row_variant: Variant in leaderboard:
			if row_variant is Dictionary:
				_add_palace_prestige_leaderboard_row_card(stack, row_variant as Dictionary)

	var note_panel: PanelContainer = PanelContainer.new()
	note_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.023, 0.020, 0.84), Color(0.45, 0.48, 0.38, 0.55), 10))
	stack.add_child(note_panel)
	var note_margin: MarginContainer = MarginContainer.new()
	note_margin.add_theme_constant_override("margin_left", 12)
	note_margin.add_theme_constant_override("margin_top", 9)
	note_margin.add_theme_constant_override("margin_right", 12)
	note_margin.add_theme_constant_override("margin_bottom", 9)
	note_panel.add_child(note_margin)
	note_margin.add_child(_palace_wrapped_label(String(prestige.get("mechanics_note", "Prestige is the main score. It is earned, lost, displayed and compared against rivals. It is never spent.")), 15, Color(0.74, 0.78, 0.70, 1.0)))

func _prestige_source_rows(history: Array) -> Array[Dictionary]:
	var totals: Dictionary = {}
	for item_variant: Variant in history:
		if not (item_variant is Dictionary):
			continue
		var item: Dictionary = item_variant as Dictionary
		var source_id: String = String(item.get("source_id", "unknown"))
		var amount: float = float(item.get("amount", 0.0))
		if not totals.has(source_id):
			totals[source_id] = {"source_id": source_id, "amount": 0.0, "count": 0, "latest_detail": "", "latest_veintena": 0}
		var row: Dictionary = totals[source_id] as Dictionary
		row["amount"] = float(row.get("amount", 0.0)) + amount
		row["count"] = int(row.get("count", 0)) + 1
		row["latest_detail"] = String(item.get("detail", row.get("latest_detail", "Prestige changed")))
		row["latest_veintena"] = int(item.get("veintena", row.get("latest_veintena", 0)))
		totals[source_id] = row
	var rows: Array[Dictionary] = []
	for key_variant: Variant in totals.keys():
		var row_value: Dictionary = totals[key_variant] as Dictionary
		rows.append(row_value.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_amount: float = absf(float(a.get("amount", 0.0)))
		var b_amount: float = absf(float(b.get("amount", 0.0)))
		if is_equal_approx(a_amount, b_amount):
			return _prestige_source_display_name(String(a.get("source_id", ""))) < _prestige_source_display_name(String(b.get("source_id", "")))
		return a_amount > b_amount
	)
	return rows

func _add_palace_prestige_source_row_card(parent: VBoxContainer, row: Dictionary) -> void:
	var source_id: String = String(row.get("source_id", "unknown"))
	var colour: Color = _prestige_source_colour(source_id)
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.022, 0.024, 0.020, 0.90), colour.darkened(0.08), 10))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	var top: HBoxContainer = HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 8)
	stack.add_child(top)
	var title: Label = _palace_label(_prestige_source_display_name(source_id), 19, colour.lightened(0.22))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var value: Label = _palace_label(_prestige_signed_amount(float(row.get("amount", 0.0))) + " Prestige", 18, colour.lightened(0.18))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(160, 0)
	top.add_child(value)
	stack.add_child(_palace_wrapped_label(str(int(row.get("count", 0))) + " recorded entr" + ("y" if int(row.get("count", 0)) == 1 else "ies") + ". Latest: " + String(row.get("latest_detail", "Prestige changed")), 14, Color(0.80, 0.84, 0.76, 1.0)))

func _add_palace_prestige_history_row_card(parent: VBoxContainer, record: Dictionary) -> void:
	var source_id: String = String(record.get("source_id", "unknown"))
	var colour: Color = _prestige_source_colour(source_id)
	var amount: float = float(record.get("amount", 0.0))
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.020, 0.018, 0.86), colour.darkened(0.14), 8))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	margin.add_child(stack)
	stack.add_child(_palace_wrapped_label(_prestige_record_time_text(record) + " • " + _prestige_source_display_name(source_id) + " • " + _prestige_signed_amount(amount) + " Prestige", 15, colour.lightened(0.22)))
	stack.add_child(_palace_wrapped_label(String(record.get("detail", "Prestige changed")), 13, Color(0.76, 0.80, 0.72, 1.0)))

func _add_palace_prestige_leaderboard_row_card(parent: VBoxContainer, row: Dictionary) -> void:
	var is_player: bool = bool(row.get("is_player", false))
	var border: Color = Color(0.76, 0.63, 0.32, 0.78) if is_player else Color(0.42, 0.46, 0.38, 0.58)
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.023, 0.020, 0.86), border, 8))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)
	var line: HBoxContainer = HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 8)
	margin.add_child(line)
	var name_label: Label = _palace_label(str(int(row.get("rank", 0))) + ". " + String(row.get("name", "House")) + (" (you)" if is_player else ""), 16, Color(0.95, 0.88, 0.62, 1.0) if is_player else Color(0.78, 0.82, 0.74, 1.0))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var value_label: Label = _palace_label(_format_religion_amount(float(row.get("prestige", 0.0))) + " Prestige", 16, Color(0.95, 0.88, 0.62, 1.0) if is_player else Color(0.78, 0.82, 0.74, 1.0))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(150, 0)
	line.add_child(value_label)

func _prestige_source_display_name(source_id: String) -> String:
	return PalacePresentationRules.prestige_source_display_name(source_id)

func _prestige_source_colour(source_id: String) -> Color:
	return PalacePresentationRules.prestige_source_colour(source_id)

func _prestige_signed_amount(amount: float) -> String:
	return ("+" if amount >= 0.0 else "") + _format_religion_amount(amount)

func _prestige_record_time_text(record: Dictionary) -> String:
	return PalacePresentationRules.prestige_record_time_text(record)

func _build_palace_overview_main_view() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var god_id: String = String(summary.get("dedicated_god", ""))
	var colour: Color = _palace_route_colour(god_id)
	var outer: PanelContainer = PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", _make_panel_style(Color(0.026, 0.024, 0.019, 0.94), Color(0.76, 0.60, 0.34, 0.68), 18))
	dynamic_view_host.add_child(outer)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	outer.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var title: Label = _palace_label("PALACE OVERVIEW", 33, Color(1.0, 0.86, 0.50, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var dedication_text: String = "No dedication chosen"
	if bool(summary.get("dedicated", false)):
		dedication_text = String(summary.get("dedicated_god_name", "Chosen")) + " — " + String(summary.get("route_name", "Palace Route"))
	root.add_child(_palace_wrapped_label(dedication_text + ". " + String(summary.get("power_summary", "Choose a Divine Seat to define the palace route.")), 18, Color(0.83, 0.86, 0.78, 1.0)))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	scroll.add_child(stack)

	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_theme_constant_override("separation", 10)
	stack.add_child(status_row)
	_add_palace_summary_card(status_row, "Palace Level", str(int(summary.get("palace_level", 1))), "Highest built palace structure tier.", colour)
	_add_palace_summary_card(status_row, "Structures", str(int(summary.get("built_structure_count", 0))) + " built", str(int(summary.get("active_structure_count", 0))) + " active; " + str(int(summary.get("inactive_structure_count", 0))) + " inactive.", colour)
	_add_palace_summary_card(status_row, "Authority", str(int(summary.get("active_structure_count", 0))) + " active", "Authority tab now reads active palace structures; effects remain display-only.", colour)

	_build_palace_staff_summary_panel(stack, summary, false)
	_build_palace_maintenance_summary_panel(stack, summary)

	var note_panel: PanelContainer = PanelContainer.new()
	note_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.023, 0.020, 0.84), Color(0.45, 0.48, 0.38, 0.55), 10))
	stack.add_child(note_panel)
	var note_margin: MarginContainer = MarginContainer.new()
	note_margin.add_theme_constant_override("margin_left", 12)
	note_margin.add_theme_constant_override("margin_top", 9)
	note_margin.add_theme_constant_override("margin_right", 12)
	note_margin.add_theme_constant_override("margin_bottom", 9)
	note_panel.add_child(note_margin)
	note_margin.add_child(_palace_wrapped_label("Palace structures consume maintenance and reserve existing active staff when the Veintena resolves. The Prestige tab now explains score, source history and rival standing. The Authority tab reads active structures; Huitzilopochtli gates attacking Flower Wars, Tlaloc shows natural foresight, Tezcatlipoca shows scarcity pressure, and Quetzalcoatl shows legitimacy hooks. Court needs can now be delivered, but prestige is generated by donation value.", 15, Color(0.74, 0.78, 0.70, 1.0)))

func _add_palace_summary_card(parent: HBoxContainer, heading: String, value: String, detail: String, colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.032, 0.026, 0.90), colour.darkened(0.10), 11))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_palace_label(heading, 15, Color(0.72, 0.76, 0.70, 1.0)))
	stack.add_child(_palace_label(value, 24, colour.lightened(0.24)))
	stack.add_child(_palace_wrapped_label(detail, 13, Color(0.74, 0.78, 0.70, 1.0)))

func _build_palace_staff_summary_panel(parent: VBoxContainer, summary: Dictionary, compact: bool = false) -> void:
	var staff_summary: Dictionary = {}
	if summary.has("staff_summary") and summary["staff_summary"] is Dictionary:
		staff_summary = summary["staff_summary"] as Dictionary
	var rows: Array = staff_summary.get("rows", []) as Array
	var border_colour: Color = Color(0.72, 0.58, 0.36, 0.72)
	if int(staff_summary.get("total_shortfall", 0)) > 0:
		border_colour = Color(1.0, 0.52, 0.28, 0.88)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.026, 0.022, 0.90), border_colour, 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	stack.add_child(_palace_label("Palace Staff", 21 if not compact else 17, Color(1.0, 0.84, 0.54, 1.0)))
	stack.add_child(_palace_wrapped_label(String(staff_summary.get("headline", "No palace staff required yet.")), 15, Color(0.82, 0.84, 0.76, 1.0)))
	if rows.is_empty():
		stack.add_child(_palace_wrapped_label("No built palace structure currently requires staff.", 14, Color(0.70, 0.74, 0.68, 1.0)))
		return
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		var line_colour: Color = Color(0.76, 0.80, 0.72, 1.0)
		if int(row.get("shortfall", 0)) > 0:
			line_colour = Color(1.0, 0.70, 0.42, 1.0)
		var line: String = String(row.get("name", "Staff")) + ": " + str(int(row.get("assigned_to_active_structures", 0))) + " assigned / " + str(int(row.get("required_by_built_structures", 0))) + " required; available " + str(int(row.get("available", 0))) + ". " + String(row.get("status", ""))
		if int(row.get("shortfall", 0)) > 0:
			line += " — short " + str(int(row.get("shortfall", 0)))
		stack.add_child(_palace_wrapped_label(line, 14 if not compact else 13, line_colour))
	if not compact:
		stack.add_child(_palace_wrapped_label(String(staff_summary.get("note", "Uses existing active population groups.")), 13, Color(0.66, 0.70, 0.64, 1.0)))

func _build_palace_maintenance_summary_panel(parent: VBoxContainer, summary: Dictionary) -> void:
	var total_maintenance: Dictionary = summary.get("total_maintenance", {}) as Dictionary
	var operation: Dictionary = summary.get("palace_operation_preview", {}) as Dictionary
	var paid: Dictionary = operation.get("maintenance_paid", {}) as Dictionary
	var shortfalls: Dictionary = operation.get("maintenance_shortfalls", {}) as Dictionary
	var border_colour: Color = Color(0.64, 0.70, 0.52, 0.70)
	if not shortfalls.is_empty():
		border_colour = Color(1.0, 0.52, 0.28, 0.88)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.024, 0.026, 0.022, 0.90), border_colour, 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	stack.add_child(_palace_label("Palace Maintenance", 21, Color(1.0, 0.84, 0.54, 1.0)))
	stack.add_child(_palace_wrapped_label("Total built-structure upkeep: " + _format_cost(total_maintenance), 15, Color(0.82, 0.84, 0.76, 1.0)))
	if paid.is_empty() and total_maintenance.is_empty():
		stack.add_child(_palace_wrapped_label("No built palace structures require maintenance yet.", 14, Color(0.70, 0.74, 0.68, 1.0)))
	else:
		stack.add_child(_palace_wrapped_label("Preview paid this Veintena if resolved now: " + _format_cost(paid), 14, Color(0.70, 0.90, 0.66, 1.0)))
	if not shortfalls.is_empty():
		stack.add_child(_palace_wrapped_label("Maintenance shortfall: " + _format_cost(shortfalls), 14, Color(1.0, 0.70, 0.42, 1.0)))

func _build_palace_divine_seat_main_view() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var outer: PanelContainer = PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.022, 0.018, 0.94), Color(0.76, 0.60, 0.34, 0.70), 18))
	dynamic_view_host.add_child(outer)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	outer.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title_label: Label = _palace_label("PALACE DIVINE SEAT", 32, Color(1.0, 0.86, 0.48, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title_label)

	if bool(summary.get("dedicated", false)):
		_build_palace_dedicated_main_tree(root, summary)
	else:
		_build_palace_undedicated_main_choice(root)

func _build_palace_undedicated_main_choice(root: VBoxContainer) -> void:
	root.add_child(_palace_wrapped_label("Choose the god whose authority will sit at the heart of your house. This dedication is permanent for Prototype 0.", 18, Color(0.80, 0.84, 0.78, 1.0)))

	var routes: Array[Dictionary] = _palace_probe_routes()
	if _selected_palace_route_id == "" and routes.size() > 0:
		_selected_palace_route_id = String(routes[0].get("id", routes[0].get("god_id", "")))

	var hall: HBoxContainer = HBoxContainer.new()
	hall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hall.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hall.add_theme_constant_override("separation", 14)
	root.add_child(hall)

	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 12)
	hall.add_child(left_col)

	var centre_col: VBoxContainer = VBoxContainer.new()
	centre_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre_col.add_theme_constant_override("separation", 12)
	centre_col.custom_minimum_size = Vector2(330, 0)
	hall.add_child(centre_col)

	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 12)
	hall.add_child(right_col)

	var route_tlaloc: Dictionary = _palace_route_by_id("tlaloc")
	var route_tez: Dictionary = _palace_route_by_id("tezcatlipoca")
	var route_huitz: Dictionary = _palace_route_by_id("huitzilopochtli")
	var route_quetz: Dictionary = _palace_route_by_id("quetzalcoatl")
	if not route_tlaloc.is_empty():
		left_col.add_child(_make_palace_route_button_card(route_tlaloc))
	if not route_tez.is_empty():
		left_col.add_child(_make_palace_route_button_card(route_tez))
	_build_palace_central_seat_panel(centre_col)
	var selected_route: Dictionary = _palace_route_by_id(_selected_palace_route_id)
	_build_palace_route_detail_panel(centre_col, selected_route)
	if not route_huitz.is_empty():
		right_col.add_child(_make_palace_route_button_card(route_huitz))
	if not route_quetz.is_empty():
		right_col.add_child(_make_palace_route_button_card(route_quetz))

func _make_palace_route_button_card(route: Dictionary) -> Button:
	var god_id: String = String(route.get("id", route.get("god_id", "")))
	var god_name: String = String(route.get("god_name", route.get("name", god_id.capitalize())))
	var route_name: String = String(route.get("route_name", "Palace Route"))
	var selected: bool = god_id == _selected_palace_route_id
	var colour: Color = _palace_route_colour(god_id)
	var button: Button = Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(210, 145)
	button.text = god_name.to_upper() + "\n" + _palace_route_domain_line(god_id) + "\n\n" + route_name
	button.tooltip_text = String(route.get("power_summary", ""))
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.035, 0.034, 0.028, 0.94), colour.darkened(0.10), 13))
	button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.055, 0.050, 0.038, 0.98), colour.lightened(0.14), 13))
	button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.070, 0.055, 0.038, 1.0), colour.lightened(0.25), 13))
	if selected:
		button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.065, 0.050, 0.035, 0.98), colour.lightened(0.32), 13))
	button.pressed.connect(func() -> void:
		_on_palace_route_selected(god_id)
	)
	return button

func _build_palace_central_seat_panel(parent: VBoxContainer) -> void:
	var selected_route: Dictionary = _palace_route_by_id(_selected_palace_route_id)
	var god_id: String = String(selected_route.get("id", selected_route.get("god_id", "")))
	var colour: Color = _palace_route_colour(god_id)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 145)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.018, 0.016, 0.95), colour, 18))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	var title_text: String = "EMPTY DIVINE SEAT"
	var subtitle_text: String = "Select a god to preview the authority route."
	if not selected_route.is_empty():
		title_text = String(selected_route.get("god_name", "Chosen")).to_upper() + " SELECTED"
		subtitle_text = String(selected_route.get("route_name", "Palace Route"))
	var title: Label = _palace_label(title_text, 24, Color(1.0, 0.88, 0.54, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var subtitle: Label = _palace_label(subtitle_text, 18, Color(0.82, 0.88, 0.80, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(subtitle)
	var glyph: Label = _palace_label(_palace_route_seat_glyph(god_id), 34, colour.lightened(0.20))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(glyph)

func _build_palace_route_detail_panel(parent: VBoxContainer, route: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.040, 0.035, 0.026, 0.96), Color(0.72, 0.58, 0.34, 0.55), 14))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	if route.is_empty():
		stack.add_child(_palace_label("No route selected", 22, Color(0.92, 0.84, 0.62, 1.0)))
		stack.add_child(_palace_wrapped_label("Choose a god card to preview the Divine Seat route.", 17, Color(0.78, 0.80, 0.74, 1.0)))
		return
	var god_id: String = String(route.get("id", route.get("god_id", "")))
	var colour: Color = _palace_route_colour(god_id)
	stack.add_child(_palace_label(String(route.get("god_name", "Chosen")).to_upper(), 25, colour.lightened(0.18)))
	stack.add_child(_palace_wrapped_label(_palace_route_domain_line(god_id), 16, Color(0.82, 0.82, 0.72, 1.0)))
	stack.add_child(_palace_wrapped_label("Power: " + String(route.get("route_name", "Palace Route")), 18, Color(1.0, 0.86, 0.52, 1.0)))
	stack.add_child(_palace_wrapped_label(_palace_route_flavour(god_id), 17, Color(0.80, 0.84, 0.78, 1.0)))
	stack.add_child(_palace_wrapped_label("Future palace structures: " + ", ".join(_palace_tree_preview_names(god_id)) + ".", 15, Color(0.68, 0.78, 0.74, 1.0)))
	var status: Dictionary = {"ok": false, "reason": "Dedication backend not connected."}
	var state: Node = _state()
	if state != null and state.has_method("can_dedicate_palace_to_god"):
		status = state.call("can_dedicate_palace_to_god", god_id) as Dictionary
	var confirm: Button = Button.new()
	confirm.text = "Dedicate Palace to " + String(route.get("god_name", "Chosen"))
	confirm.custom_minimum_size = Vector2(0, 46)
	confirm.add_theme_font_size_override("font_size", 20)
	confirm.add_theme_stylebox_override("normal", _make_panel_style(Color(0.055, 0.045, 0.030, 0.94), colour, 10))
	confirm.add_theme_stylebox_override("hover", _make_panel_style(Color(0.075, 0.055, 0.034, 1.0), colour.lightened(0.18), 10))
	confirm.disabled = not bool(status.get("ok", false))
	confirm.tooltip_text = String(status.get("reason", ""))
	confirm.pressed.connect(func() -> void:
		_on_palace_confirm_dedication_pressed(god_id)
	)
	stack.add_child(confirm)
	stack.add_child(_palace_wrapped_label("Permanent for Prototype 0. The Divine Seat will become this god's palace structure node data.", 14, Color(0.92, 0.72, 0.50, 1.0)))

func _build_palace_dedicated_main_tree(root: VBoxContainer, summary: Dictionary) -> void:
	var god_id: String = String(summary.get("dedicated_god", ""))
	var colour: Color = _palace_route_colour(god_id)
	var header: PanelContainer = PanelContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_stylebox_override("panel", _make_panel_style(Color(0.026, 0.026, 0.020, 0.96), colour, 16))
	root.add_child(header)
	var header_margin: MarginContainer = MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 18)
	header_margin.add_theme_constant_override("margin_top", 12)
	header_margin.add_theme_constant_override("margin_right", 18)
	header_margin.add_theme_constant_override("margin_bottom", 12)
	header.add_child(header_margin)
	var header_stack: VBoxContainer = VBoxContainer.new()
	header_stack.add_theme_constant_override("separation", 6)
	header_margin.add_child(header_stack)
	var title: Label = _palace_label("PALACE DEDICATED TO " + String(summary.get("dedicated_god_name", "Chosen")).to_upper(), 28, colour.lightened(0.24))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_stack.add_child(title)
	header_stack.add_child(_palace_wrapped_label(String(summary.get("route_name", "Palace Route")) + ". " + String(summary.get("power_summary", "")), 17, Color(0.84, 0.86, 0.78, 1.0)))

	_build_palace_staff_summary_panel(root, summary, true)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var tree_stack: VBoxContainer = VBoxContainer.new()
	tree_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_stack.add_theme_constant_override("separation", 10)
	scroll.add_child(tree_stack)
	var tree: Dictionary = {}
	if summary.has("structure_tree_shell") and summary["structure_tree_shell"] is Dictionary:
		tree = summary["structure_tree_shell"] as Dictionary
	else:
		var state: Node = _state()
		if state != null and state.has_method("get_palace_structure_tree_shell"):
			tree = state.call("get_palace_structure_tree_shell", god_id) as Dictionary
	if tree.is_empty():
		tree_stack.add_child(_palace_wrapped_label("Palace structure node data is not connected yet.", 18, Color(0.82, 0.76, 0.62, 1.0)))
		return
	var tiers: Array = tree.get("tiers", []) as Array
	for tier_variant: Variant in tiers:
		if tier_variant is Dictionary:
			_add_palace_tree_tier_card(tree_stack, tier_variant as Dictionary, colour)
	_add_palace_paths_not_chosen_panel(tree_stack, god_id)

func _add_palace_tree_tier_card(parent: VBoxContainer, tier: Dictionary, colour: Color) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.033, 0.026, 0.90), colour.darkened(0.10), 12))
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
	stack.add_child(_palace_label(String(tier.get("title", "Palace Tier")), 21, Color(1.0, 0.84, 0.54, 1.0)))
	var structures: Array = tier.get("structures", []) as Array
	for structure_variant: Variant in structures:
		if structure_variant is Dictionary:
			var structure: Dictionary = structure_variant as Dictionary
			_add_palace_structure_node_card(stack, structure, colour)

func _add_palace_structure_node_card(parent: VBoxContainer, structure: Dictionary, route_colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.023, 0.021, 0.92), route_colour.darkened(0.22), 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_theme_constant_override("separation", 8)
	stack.add_child(title_row)
	var title: Label = _palace_label(String(structure.get("name", "Palace Structure")), 19, route_colour.lightened(0.24))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var status: Label = _palace_label(String(structure.get("status", "Not built")), 14, Color(0.92, 0.74, 0.48, 1.0))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.custom_minimum_size = Vector2(110, 0)
	title_row.add_child(status)

	stack.add_child(_palace_wrapped_label("Tier " + str(int(structure.get("tier", structure.get("level", 1)))) + " — " + String(structure.get("route", "Palace Route")), 14, Color(0.72, 0.78, 0.72, 1.0)))
	stack.add_child(_palace_wrapped_label(String(structure.get("description", structure.get("summary", "Future palace structure."))), 15, Color(0.80, 0.83, 0.76, 1.0)))

	var build_cost: Dictionary = structure.get("build_cost", {}) as Dictionary
	var maintenance_cost: Dictionary = structure.get("maintenance_cost", {}) as Dictionary
	var staff_requirement: Dictionary = structure.get("staff_requirement", {}) as Dictionary
	var prerequisite_text: String = String(structure.get("prerequisite_text", "None"))
	var effect_summary: String = String(structure.get("effect_summary", structure.get("summary", "Future palace authority hook.")))
	stack.add_child(_palace_wrapped_label("Build cost: " + _format_cost(build_cost), 14, Color(0.77, 0.83, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label("Maintenance: " + _format_cost(maintenance_cost), 14, Color(0.77, 0.83, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label("Staff: " + _palace_format_staff_requirement(staff_requirement), 14, Color(0.77, 0.83, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label("Prerequisites: " + prerequisite_text, 14, Color(0.70, 0.76, 0.70, 1.0)))
	stack.add_child(_palace_wrapped_label("Effect: " + effect_summary, 14, Color(0.92, 0.82, 0.55, 1.0)))

	var structure_id: String = String(structure.get("id", ""))
	var built: bool = bool(structure.get("built", false))
	if built:
		var active: bool = bool(structure.get("active", false))
		var paid_preview: Dictionary = structure.get("maintenance_paid_preview", {}) as Dictionary
		var staff_preview: Dictionary = structure.get("staff_assigned_preview", {}) as Dictionary
		if not paid_preview.is_empty():
			stack.add_child(_palace_wrapped_label("Maintenance covered: " + _format_cost(paid_preview), 13, Color(0.70, 0.86, 0.68, 1.0)))
		if not staff_preview.is_empty():
			stack.add_child(_palace_wrapped_label("Staff assigned: " + _palace_format_staff_requirement(staff_preview), 13, Color(0.70, 0.86, 0.68, 1.0)))
		if active:
			stack.add_child(_palace_wrapped_label("Active. Maintenance and staff are currently covered; authority effects will be connected later.", 13, Color(0.62, 0.95, 0.70, 1.0)))
		else:
			stack.add_child(_palace_wrapped_label("Built but inactive: " + String(structure.get("inactive_reason", "missing maintenance or staff.")), 13, Color(1.0, 0.72, 0.45, 1.0)))
		return
	var build_status: Dictionary = {"ok": bool(structure.get("can_build", false)), "reason": String(structure.get("build_status", ""))}
	var state: Node = _state()
	if state != null and state.has_method("can_build_palace_structure"):
		build_status = state.call("can_build_palace_structure", structure_id) as Dictionary
	var build_button: Button = Button.new()
	build_button.text = "Build Palace Structure"
	build_button.custom_minimum_size = Vector2(0, 38)
	build_button.add_theme_font_size_override("font_size", 16)
	build_button.disabled = not bool(build_status.get("ok", false))
	build_button.tooltip_text = String(build_status.get("reason", ""))
	build_button.pressed.connect(func() -> void:
		var build_state: Node = _state()
		if build_state != null and build_state.has_method("build_palace_structure"):
			build_state.call("build_palace_structure", structure_id)
		_refresh_all()
	)
	stack.add_child(build_button)
	if not bool(build_status.get("ok", false)):
		stack.add_child(_palace_wrapped_label("Blocked: " + String(build_status.get("reason", "")), 13, Color(1.0, 0.72, 0.45, 1.0)))
	else:
		stack.add_child(_palace_wrapped_label("Construction pays the build cost now. The structure must then be maintained and staffed each Veintena to stay active.", 13, Color(0.72, 0.78, 0.66, 1.0)))

func _palace_format_staff_requirement(staff: Dictionary) -> String:
	if staff.is_empty():
		return "none"
	var parts: Array[String] = []
	for staff_variant: Variant in staff.keys():
		var staff_id: String = String(staff_variant)
		parts.append(_palace_staff_display_name(staff_id) + " " + str(int(staff[staff_variant])))
	return ", ".join(parts)

func _palace_staff_display_name(staff_id: String) -> String:
	return PalacePresentationRules.palace_staff_display_name(staff_id)

func _add_palace_paths_not_chosen_panel(parent: VBoxContainer, chosen_id: String) -> void:
	var muted: Array[String] = []
	for route: Dictionary in _palace_probe_routes():
		var route_id: String = String(route.get("id", route.get("god_id", "")))
		if route_id == chosen_id:
			continue
		muted.append(String(route.get("god_name", route_id.capitalize())) + " — not chosen")
	if muted.is_empty():
		return
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.022, 0.024, 0.022, 0.82), Color(0.38, 0.40, 0.34, 0.55), 10))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	margin.add_child(_palace_wrapped_label("Other divine routes sealed for Prototype 0: " + "; ".join(muted) + ".", 15, Color(0.66, 0.68, 0.62, 1.0)))

func _on_palace_route_selected(god_id: String) -> void:
	_selected_palace_route_id = god_id
	_pending_palace_dedication_confirm_id = ""
	_refresh_main_content()
	_refresh_right_panel()

func _on_palace_confirm_dedication_pressed(god_id: String) -> void:
	var state: Node = _state()
	if state == null:
		return
	if state.has_method("dedicate_palace_to_god"):
		state.call("dedicate_palace_to_god", god_id)
	elif state.has_method("set_player_palace_dedicated_god"):
		state.call("set_player_palace_dedicated_god", god_id)
	_selected_palace_route_id = ""
	_pending_palace_dedication_confirm_id = ""
	_refresh_all()

func _palace_route_by_id(god_id: String) -> Dictionary:
	for route: Dictionary in _palace_probe_routes():
		var route_id: String = String(route.get("id", route.get("god_id", "")))
		if route_id == god_id:
			return route
	return {}

func _palace_tree_preview_names(god_id: String) -> Array[String]:
	var tree: Dictionary = {}
	var state: Node = _state()
	if state != null and state.has_method("get_palace_structure_tree_shell"):
		tree = state.call("get_palace_structure_tree_shell", god_id) as Dictionary
	var names: Array[String] = []
	var tiers: Array = tree.get("tiers", []) as Array
	for tier_variant: Variant in tiers:
		if not (tier_variant is Dictionary):
			continue
		var tier: Dictionary = tier_variant as Dictionary
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if structure_variant is Dictionary:
				names.append(String((structure_variant as Dictionary).get("name", "Structure")))
			if names.size() >= 5:
				return names
	return names

func _palace_route_colour(god_id: String) -> Color:
	return PalacePresentationRules.route_colour(god_id)

func _palace_route_domain_line(god_id: String) -> String:
	return PalacePresentationRules.route_domain_line(god_id)

func _palace_route_flavour(god_id: String) -> String:
	return PalacePresentationRules.route_flavour(god_id)

func _palace_route_seat_glyph(god_id: String) -> String:
	return PalacePresentationRules.route_seat_glyph(god_id)

func _palace_label(text: String, font_size: int, colour: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label

func _palace_wrapped_label(text: String, font_size: int, colour: Color) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = false
	label.text = text
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", colour)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

# -----------------------------------------------------------------------------
# Palace navigation probe v0.20.3
# -----------------------------------------------------------------------------

func _build_palace_navigation_probe_reports() -> void:
	var focus_id: String = _current_focus_id()
	match focus_id:
		"prestige":
			_build_palace_prestige_probe_reports()
		"divine_seat":
			_build_palace_divine_seat_probe_reports()
		"authority":
			_build_palace_authority_probe_reports()
		"ruler_demands":
			_build_palace_ruler_demands_probe_reports()
		_:
			_build_palace_overview_probe_reports()

func _build_palace_overview_probe_reports() -> void:
	_add_prestige_estate_score_card()
	var summary: Dictionary = _palace_probe_summary()
	_add_notification("Palace Overview. Level " + str(int(summary.get("palace_level", 1))) + ". Dedication: " + String(summary.get("dedicated_god_name", "None")) + ".")
	_add_notification("Route: " + String(summary.get("route_name", "No dedication")) + ". " + String(summary.get("power_summary", "No palace route has been chosen yet.")))
	_add_notification("Authority status: " + String(summary.get("authority_status", "Palace authority mechanics are not active yet.")))
	_add_notification("Structures: " + str(int(summary.get("built_structure_count", 0))) + " built; " + str(int(summary.get("active_structure_count", 0))) + " active; " + str(int(summary.get("inactive_structure_count", 0))) + " inactive.")
	var staff_summary: Dictionary = summary.get("staff_summary", {}) as Dictionary
	_add_notification(String(staff_summary.get("headline", "No palace staff required yet.")))
	_add_notification("Palace upkeep and staff now resolve on Veintena advance. The Palace → Prestige tab now explains score sources and recent gains. Huitzilopochtli dedication gates attacking Flower Wars; other authority effects and court needs now show a display-only readiness prototype.")

func _build_palace_prestige_probe_reports() -> void:
	_add_prestige_estate_score_card()
	var state: Node = _state()
	if state == null or not state.has_method("get_prestige_summary"):
		_add_notification("Prestige: backend score data is not connected yet.")
		return
	var prestige: Dictionary = state.call("get_prestige_summary") as Dictionary
	var history: Array = prestige.get("prestige_history", []) as Array
	var source_rows: Array[Dictionary] = _prestige_source_rows(history)
	_add_notification("Palace → Prestige: explains why the main score changed, with recent entries and source totals.")
	if source_rows.is_empty():
		_add_notification("Prestige source breakdown: no recorded gains or losses yet.")
	else:
		var parts: Array[String] = []
		var count: int = 0
		for row: Dictionary in source_rows:
			if count >= 4:
				break
			parts.append(_prestige_source_display_name(String(row.get("source_id", "unknown"))) + " " + _prestige_signed_amount(float(row.get("amount", 0.0))))
			count += 1
		_add_notification("Prestige source totals: " + "; ".join(parts) + ".")
	_add_notification("Market trades remain previewed in the Market basket, but the full Prestige history now lives here in the Palace tab.")

func _build_palace_divine_seat_probe_reports() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var dedicated: bool = bool(summary.get("dedicated", false))
	if dedicated:
		_add_notification("Divine Seat: Palace dedicated to " + String(summary.get("dedicated_god_name", "Chosen")) + ".")
		_add_notification("The large palace view now shows palace structures with build costs, maintenance, staff, prerequisites, effect summaries and active/inactive status.")
		_build_palace_not_chosen_routes(summary)
		return
	_add_notification("Divine Seat: choose one palace route in the large centre-left dedication hall.")
	_add_notification("This is permanent for Prototype 0. Select a divine route, review the central route panel, then confirm dedication from the main Palace view.")
	_add_notification("Tlaloc = foresight. Huitzilopochtli = Flower Wars. Tezcatlipoca = scarcity and intrigue. Quetzalcoatl = legitimacy and recognition.")

func _add_palace_dedication_route_card(route: Dictionary) -> void:
	var god_id: String = String(route.get("id", route.get("god_id", "")))
	var god_name: String = String(route.get("god_name", route.get("name", god_id.capitalize())))
	var route_name: String = String(route.get("route_name", route.get("route", "Palace Route")))
	var summary: String = String(route.get("power_summary", ""))
	_add_notification(god_name + " — " + route_name + ". " + summary)
	var state: Node = _state()
	var can_dedicate: bool = bool(route.get("can_dedicate", false))
	var reason: String = String(route.get("dedication_status", ""))
	if state != null and state.has_method("can_dedicate_palace_to_god"):
		var status: Dictionary = state.call("can_dedicate_palace_to_god", god_id) as Dictionary
		can_dedicate = bool(status.get("ok", false))
		reason = String(status.get("reason", reason))
	var button: Button = Button.new()
	button.text = "Dedicate to " + god_name
	button.custom_minimum_size = Vector2(0, 38)
	button.add_theme_font_size_override("font_size", 16)
	button.disabled = not can_dedicate
	button.tooltip_text = reason
	button.pressed.connect(func() -> void:
		_on_palace_dedication_pressed(god_id)
	)
	notification_list.add_child(button)
	if reason != "":
		_add_notification("Dedication status: " + reason)

func _on_palace_dedication_pressed(god_id: String) -> void:
	var state: Node = _state()
	if state == null:
		return
	if state.has_method("dedicate_palace_to_god"):
		state.call("dedicate_palace_to_god", god_id)
	elif state.has_method("set_player_palace_dedicated_god"):
		state.call("set_player_palace_dedicated_god", god_id)
	_refresh_all()

func _build_palace_dedicated_tree_reports(summary: Dictionary) -> void:
	var god_name: String = String(summary.get("dedicated_god_name", "Chosen"))
	var route_name: String = String(summary.get("route_name", "Palace Route"))
	_add_notification("Divine Seat: Palace dedicated to " + god_name + ".")
	_add_notification(route_name + ". " + String(summary.get("power_summary", "")))
	var tree: Dictionary = {}
	if summary.has("structure_tree_shell") and summary["structure_tree_shell"] is Dictionary:
		tree = summary["structure_tree_shell"] as Dictionary
	else:
		var state: Node = _state()
		if state != null and state.has_method("get_palace_structure_tree_shell"):
			tree = state.call("get_palace_structure_tree_shell", String(summary.get("dedicated_god", ""))) as Dictionary
	if tree.is_empty():
		_add_notification("Tree shell not connected yet.")
		return
	_add_notification(String(tree.get("note", "Palace structure construction data.")))
	var tiers: Array = tree.get("tiers", []) as Array
	for tier_variant: Variant in tiers:
		if not (tier_variant is Dictionary):
			continue
		var tier: Dictionary = tier_variant as Dictionary
		_add_notification(String(tier.get("title", "Palace Tier")))
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if not (structure_variant is Dictionary):
				continue
			var structure: Dictionary = structure_variant as Dictionary
			_add_notification("• " + String(structure.get("name", "Structure")) + " — " + String(structure.get("summary", "Future palace structure.")))
	_build_palace_not_chosen_routes(summary)

func _build_palace_not_chosen_routes(summary: Dictionary) -> void:
	var chosen_id: String = String(summary.get("dedicated_god", ""))
	var routes: Array[Dictionary] = _palace_probe_routes()
	var parts: Array[String] = []
	for route: Dictionary in routes:
		var route_id: String = String(route.get("id", route.get("god_id", "")))
		if route_id == chosen_id:
			continue
		parts.append(String(route.get("god_name", route.get("name", route_id.capitalize()))) + " — not chosen")
	if not parts.is_empty():
		_add_notification("Other Divine Routes: " + "; ".join(parts) + ".")

func _build_palace_authority_probe_reports() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var authority: Dictionary = {}
	if summary.has("authority_summary") and summary["authority_summary"] is Dictionary:
		authority = summary["authority_summary"] as Dictionary
	var route_id: String = String(summary.get("dedicated_god", ""))
	if route_id == "":
		_add_notification("No Palace Authority. Dedicate the palace on the Divine Seat tab to unlock a route-specific authority screen.")
		_add_notification("Tlaloc = natural calendar foresight. Huitzilopochtli = Flower Wars authority. Tezcatlipoca = scarcity/intrigue pressure. Quetzalcoatl = legitimacy and palace trust.")
		return
	_add_notification(String(authority.get("headline", String(summary.get("dedicated_god_name", "Chosen")) + " Authority")))
	_add_notification(String(authority.get("body", summary.get("power_summary", ""))))
	if route_id == "tlaloc" and summary.has("tlaloc_forecast") and summary["tlaloc_forecast"] is Dictionary:
		var forecast: Dictionary = summary["tlaloc_forecast"] as Dictionary
		_add_notification("Tlaloc forecast: " + str(int(forecast.get("visible_event_count", 0))) + " visible natural pressures; range " + str(int(forecast.get("forecast_range_veintenas", 0))) + " Veintenas. Information-only prototype.")
	if route_id == "tezcatlipoca" and summary.has("tezcatlipoca_pressure") and summary["tezcatlipoca_pressure"] is Dictionary:
		var pressure: Dictionary = summary["tezcatlipoca_pressure"] as Dictionary
		_add_notification("Tezcatlipoca pressure: " + str(int(pressure.get("visible_market_pressure_count", 0))) + " market readings; " + str(int(pressure.get("visible_rival_pressure_count", 0))) + " rival hooks. Information-only prototype.")
	if route_id == "quetzalcoatl" and summary.has("quetzalcoatl_legitimacy") and summary["quetzalcoatl_legitimacy"] is Dictionary:
		var legitimacy: Dictionary = summary["quetzalcoatl_legitimacy"] as Dictionary
		_add_notification("Quetzalcoatl legitimacy: " + str(int(legitimacy.get("visible_legitimacy_count", 0))) + " legitimacy hooks; " + str(int(legitimacy.get("visible_obligation_count", 0))) + " tribute credibility readings. Information-only prototype.")
	_add_notification("Structures: " + str(int(authority.get("active_structure_count", 0))) + " active; " + str(int(authority.get("inactive_structure_count", 0))) + " inactive. Implemented route effects currently are the Huitzilopochtli Flower War gate, Tlaloc forecast display, Tezcatlipoca pressure display, and Quetzalcoatl legitimacy display.")

func _build_palace_ruler_demands_probe_reports() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var demands: Dictionary = {}
	if summary.has("ruler_demands") and summary["ruler_demands"] is Dictionary:
		demands = summary["ruler_demands"] as Dictionary
	else:
		var state: Node = _state()
		if state != null and state.has_method("get_palace_ruler_demands_summary"):
			demands = state.call("get_palace_ruler_demands_summary") as Dictionary
	if demands.is_empty():
		_add_notification("Court Needs. Backend data is not connected yet.")
		return
	_add_notification(String(demands.get("title", "Current Court Needs")) + ". " + String(demands.get("headline", "Court needs donation prototype active.")))
	_add_notification("Deadline: " + String(demands.get("cycle_window", "Court need cycle timing unavailable.")) + " Urgency: " + String(demands.get("urgency_label", "Time remains")) + ".")
	_add_notification("Prestige from court-need donations this cycle: +" + _format_religion_amount(float(demands.get("total_donated_prestige", 0.0))) + ". Player Prestige: " + _format_religion_amount(float(demands.get("player_prestige", 0.0))) + ".")
	_add_notification(String(demands.get("flavour", "The court needs goods; donations create public prestige.")))
	var rows: Array = demands.get("rows", []) as Array
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		var line: String = String(row.get("slot_name", "Need")) + ": " + String(row.get("resource_name", "Good")) + " need marker " + _format_religion_amount(float(row.get("needed_marker", row.get("requested", 0.0)))) + "; free " + _format_religion_amount(float(row.get("free_after_reserves", 0.0))) + "; base value " + _format_religion_amount(float(row.get("base_value", 1.0)))
		if float(row.get("donated_amount", 0.0)) > 0.001:
			line += "; donated " + _format_religion_amount(float(row.get("donated_amount", 0.0))) + " for +" + _format_religion_amount(float(row.get("donated_prestige", 0.0))) + " Prestige"
		_add_notification(line + ".")
	_add_notification(String(demands.get("mechanics_note", "Donations create prestige by base value. Prestige is score only and never spent.")))

func _palace_probe_summary() -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("get_palace_summary"):
		return state.call("get_palace_summary") as Dictionary
	return {"palace_level": 1, "dedicated": false, "dedicated_god": "", "dedicated_god_name": "None", "route_name": "No dedication", "power_summary": "Palace backend summary is not connected.", "authority_status": "Not connected.", "built_structure_count": 0}

func _palace_probe_routes() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var state: Node = _state()
	if state != null and state.has_method("get_palace_dedication_routes"):
		var raw_routes: Variant = state.call("get_palace_dedication_routes")
		if raw_routes is Array:
			var route_rows: Array = raw_routes as Array
			for route_variant: Variant in route_rows:
				if route_variant is Dictionary:
					output.append(route_variant as Dictionary)
	return output


# -----------------------------------------------------------------------------
# Host bridge helpers
# -----------------------------------------------------------------------------

func _state() -> Node:
	if host != null and host.has_method("_state"):
		var raw: Variant = host.call("_state")
		if raw is Node:
			return raw as Node
	return null

func _current_focus_id() -> String:
	if host != null and host.has_method("_current_focus_id"):
		return String(host.call("_current_focus_id"))
	return "overview"

func _set_content_root_layout(expanded: bool) -> void:
	if host != null and host.has_method("_set_content_root_layout"):
		host.call("_set_content_root_layout", expanded)

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

func _format_religion_amount(value: float) -> String:
	if host != null and host.has_method("_format_religion_amount"):
		return String(host.call("_format_religion_amount", value))
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _format_cost(cost: Dictionary) -> String:
	if host != null and host.has_method("_format_cost"):
		return String(host.call("_format_cost", cost))
	if cost.is_empty():
		return "none"
	var parts: Array[String] = []
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		parts.append(resource_id.replace("_", " ").capitalize() + " " + _format_religion_amount(float(cost[resource_variant])))
	return ", ".join(parts)

func _refresh_all() -> void:
	if host != null and host.has_method("_refresh_all"):
		host.call("_refresh_all")

func _refresh_main_content() -> void:
	if host != null and host.has_method("_refresh_main_content"):
		host.call("_refresh_main_content")

func _refresh_right_panel() -> void:
	if host != null and host.has_method("_refresh_right_panel"):
		host.call("_refresh_right_panel")

func _add_notification(text: String) -> void:
	if host != null and host.has_method("_add_notification"):
		host.call("_add_notification", text)
		return
	if notification_list == null:
		return
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notification_list.add_child(label)

func _add_prestige_estate_score_card() -> void:
	if host != null and host.has_method("_add_prestige_estate_score_card"):
		host.call("_add_prestige_estate_score_card")

func _ordinal_number(value: int) -> String:
	if host != null and host.has_method("_ordinal_number"):
		return String(host.call("_ordinal_number", value))
	return PalacePresentationRules.ordinal_number(value)

