# HousingView.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/HousingView.gd
extends Control

signal housing_closed
signal build_requested(housing_id: String)
signal destroy_requested(housing_id: String)

var _rows: Array[Dictionary] = []
var _focus_id: String = "overview"
var _selected_id: String = ""
var _root: PanelContainer = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent(self)

func setup(summary: Dictionary, rows: Array, focus_id: String, selected_id: String) -> void:
	_rows.clear()
	for row_variant: Variant in rows:
		_rows.append((row_variant as Dictionary).duplicate(true))
	_focus_id = focus_id
	_selected_id = selected_id
	_rebuild()

func select_housing(housing_id: String) -> void:
	_selected_id = housing_id
	_rebuild()

func _rebuild() -> void:
	_fill_parent(self)
	_clear_children(self)
	if _selected_id == "":
		visible = false
		return
	visible = true
	_build_detail_panel(_selected_id)

func _build_detail_panel(housing_id: String) -> void:
	var row: Dictionary = _row_by_id(housing_id)
	if row.is_empty() or bool(row.get("is_summary", false)):
		visible = false
		return
	_root = _make_panel()
	add_child(_root)
	_fill_parent(_root)
	var margin: MarginContainer = _make_margin(18, 18, 16, 16)
	_root.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)

	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	stack.add_child(header)
	var title: Label = _make_label(String(row.get("name", "Housing")), 30, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(48, 44)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(func() -> void:
		emit_signal("housing_closed")
	)
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
	body.text = _detail_text(row)
	stack.add_child(body)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	stack.add_child(actions)
	var build_button: Button = _make_action_button("+ Build one", true, bool(row.get("can_build", false)))
	build_button.tooltip_text = String(row.get("build_status", "Build one"))
	build_button.pressed.connect(func() -> void:
		emit_signal("build_requested", housing_id)
	)
	actions.add_child(build_button)
	var destroy_button: Button = _make_action_button("− Destroy one", false, bool(row.get("can_destroy", false)))
	destroy_button.tooltip_text = String(row.get("destroy_status", "Destroy one"))
	destroy_button.pressed.connect(func() -> void:
		emit_signal("destroy_requested", housing_id)
	)
	actions.add_child(destroy_button)

func _detail_text(row: Dictionary) -> String:
	var count: int = int(row.get("count", 0))
	var active_count: int = int(row.get("active_count", count))
	var mothballed: int = int(row.get("mothballed_count", max(0, count - active_count)))
	var text: String = ""
	text += String(row.get("description", "")) + "\n\n"
	text += "[b]Current building state[/b]\n"
	text += "• Built: " + str(count) + "\n"
	text += "• Active: " + str(active_count) + " / " + str(count) + "\n"
	text += "• Mothballed: " + str(mothballed) + "\n"
	text += "• Status: " + String(row.get("status_text", "")) + "\n\n"

	text += "[b]One building needs each Veintena[/b]\n"
	text += "Building upkeep: " + _dictionary_inline(row.get("housing_maintenance", {}) as Dictionary) + "\n\n"

	text += "[b]One building provides[/b]\n"
	text += _dictionary_lines(row.get("housing_capacity", {}) as Dictionary, "capacity")
	text += "\n"

	text += "[b]All built copies need each Veintena[/b]\n"
	text += "Building upkeep: " + _dictionary_inline(row.get("maintenance_total", {}) as Dictionary) + "\n"
	text += "[i]Mothballed housing still pays this building upkeep.[/i]\n\n"

	text += "[b]All active copies provide[/b]\n"
	text += _dictionary_lines(row.get("active_capacity_total", {}) as Dictionary, "active capacity")
	text += "\n"

	text += "[b]All built copies could provide[/b]\n"
	text += _dictionary_lines(row.get("capacity_total", {}) as Dictionary, "built capacity")
	text += "\n"

	text += "[b]Build one more[/b]\n"
	text += "Cost now:\n" + _dictionary_lines(row.get("build_cost", {}) as Dictionary)
	text += "Status: " + String(row.get("build_status", "")) + "\n"
	text += "After building one more: " + str(count + 1) + " total. New housing starts active.\n"
	text += "Projected total upkeep: " + _dictionary_inline(row.get("maintenance_after_build", {}) as Dictionary) + "\n"
	text += "Projected built capacity: " + _dictionary_inline(row.get("capacity_after_build", {}) as Dictionary) + "\n\n"

	text += "[b]Destroy one[/b]\n"
	var after_destroy: int = max(0, count - 1)
	text += "Status: " + String(row.get("destroy_status", "")) + "\n"
	text += "After destroying one: " + str(after_destroy) + " total.\n"
	text += "Projected total upkeep: " + _dictionary_inline(row.get("maintenance_after_destroy", {}) as Dictionary) + "\n"
	text += "Projected built capacity: " + _dictionary_inline(row.get("capacity_after_destroy", {}) as Dictionary) + "\n"
	text += "No refund is currently given in the prototype."
	return text.strip_edges()

func _row_by_id(housing_id: String) -> Dictionary:
	for row: Dictionary in _rows:
		if String(row.get("id", "")) == housing_id:
			return row
	return {}

func _make_action_button(text_value: String, positive: bool, enabled: bool) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(0, 56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 21)
	var bg: Color = Color(0.06, 0.24, 0.14, 0.96) if positive else Color(0.28, 0.08, 0.06, 0.96)
	var border: Color = Color(0.2, 0.8, 0.42, 0.75) if positive else Color(0.9, 0.28, 0.22, 0.75)
	button.add_theme_stylebox_override("normal", _make_style(bg, border, 10))
	button.add_theme_stylebox_override("hover", _make_style(bg.lightened(0.08), border.lightened(0.1), 10))
	button.add_theme_stylebox_override("pressed", _make_style(bg.darkened(0.08), border, 10))
	button.add_theme_stylebox_override("disabled", _make_style(Color(0.12, 0.13, 0.13, 0.88), Color(0.35, 0.36, 0.34, 0.65), 10))
	return button

func _make_panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fill_parent(panel)
	panel.add_theme_stylebox_override("panel", _make_style(Color(0.0, 0.0, 0.0, 0.64), Color(0.50, 0.82, 0.74, 0.36), 14))
	return panel

func _make_margin(left: int, right: int, top: int, bottom: int) -> MarginContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin

func _make_label(text_value: String, font_size: int, bold: bool) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	if bold:
		label.add_theme_color_override("font_color", Color(0.94, 0.88, 0.68, 1.0))
	return label

func _dictionary_lines(values: Dictionary, suffix: String = "") -> String:
	if values.is_empty():
		return "• None\n"
	var lines: String = ""
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		var line: String = "• " + _display_name(key) + ": " + _format_amount(float(values[key_variant]))
		if suffix != "":
			line += " " + suffix
		lines += line + "\n"
	return lines

func _dictionary_inline(values: Dictionary) -> String:
	var parts: Array[String] = []
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		parts.append(_display_name(key) + " " + _format_amount(float(values[key_variant])))
	if parts.is_empty():
		return "None"
	return "; ".join(parts)

func _display_name(id: String) -> String:
	match id:
		"macehualtin":
			return "Macehualtin"
		"tlacotin":
			return "Tlacotin"
		"tolteca":
			return "Tolteca"
		"yaotequihuaqueh":
			return "Warriors"
		"tlamacazqueh":
			return "Priests"
		"pipiltin":
			return "Nobles"
		"malli":
			return "Captives"
	return id.replace("_", " ").capitalize()

func _format_amount(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _make_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	return style

func _fill_parent(control: Control) -> void:
	if control == null:
		return
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		child.queue_free()
