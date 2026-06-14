# BuildingLedgerRow.gd
# Godot 4.x
# Project path: res://Scripts/ui/BuildingLedgerRow.gd
#
# Production / Housing building ledger row.
# Shows only vital quick-read information in the right ledger and provides
# separate green build and red destroy action buttons.
extends PanelContainer

signal building_selected(building_id: String)
signal build_requested(building_id: String)
signal destroy_requested(building_id: String)

var building_id: String = ""
var _data: Dictionary = {}
var _selected: bool = false

var _name_label: Label
var _count_label: Label
var _makes_label: Label
var _needs_label: Label
var _status_label: Label
var _hint_label: Label
var _build_button: Button
var _destroy_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 214)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ensure_ui()
	if _data.is_empty():
		_apply_panel_style(false, "")
	else:
		_apply_panel_style(_selected, String(_data.get("status_text", "")))
		_apply_action_button_styles()

func set_building_data(data: Dictionary, selected: bool) -> void:
	_ensure_ui()
	_data = data
	_selected = selected
	building_id = String(data.get("id", ""))
	tooltip_text = _build_tooltip(data)

	if bool(data.get("is_labour", false)):
		_set_labour_data(data)
		return

	var display_name: String = String(data.get("name", "Building"))
	var count: int = int(data.get("count", 0))
	var operating: int = int(data.get("operating", 0))
	var blocked: int = int(data.get("blocked", 0))
	var status_text: String = String(data.get("status_text", "Not built."))

	var inputs: Dictionary = data.get("inputs", {}) as Dictionary
	var outputs: Dictionary = data.get("outputs", {}) as Dictionary
	var staff: Dictionary = data.get("staff", {}) as Dictionary

	_name_label.text = display_name
	_count_label.text = _count_text(count, operating, blocked)

	var output_total: Dictionary = outputs
	var input_total: Dictionary = inputs
	var staff_total: Dictionary = staff
	if count > 0:
		output_total = _multiply_dictionary(outputs, max(0, operating))
		input_total = _multiply_dictionary(inputs, max(0, operating))
		staff_total = _multiply_dictionary(staff, max(0, operating))

	_makes_label.text = ("Makes now: " if count > 0 else "Makes if built: ") + _dictionary_inline(output_total, 2)
	_needs_label.text = ("Needs now: " if count > 0 else "Needs if built: ") + _need_summary(input_total, staff_total, 2)
	_status_label.text = _short_status(status_text)
	_hint_label.text = "Click row for details"

	var can_build: bool = bool(data.get("can_build", false))
	var can_destroy: bool = bool(data.get("can_destroy", count > 0))
	_build_button.visible = true
	_destroy_button.visible = true
	_build_button.disabled = not can_build
	_destroy_button.disabled = not can_destroy
	_build_button.tooltip_text = "Build one " + display_name + ". " + String(data.get("build_status", ""))
	_destroy_button.tooltip_text = "Destroy one " + display_name + ". " + String(data.get("destroy_status", "No refund in this prototype."))

	_apply_panel_style(selected, status_text)
	_apply_action_button_styles()

func _set_labour_data(data: Dictionary) -> void:
	var display_name: String = String(data.get("name", "Labour"))
	var count: int = int(data.get("count", 0))
	var staff: Dictionary = data.get("staff", {}) as Dictionary
	var total: int = int(staff.get("total_population", count))
	var required: int = int(staff.get("required_by_built_production", data.get("operating", 0)))
	var free: int = int(staff.get("free_or_background_labour", max(0, total - required)))
	var short: int = max(0, required - total)
	var status_text: String = String(data.get("status_text", ""))

	_name_label.text = display_name
	_count_label.text = "Available " + str(total) + " | Required " + str(required) + (" | Short " + str(short) if short > 0 else "")
	_makes_label.text = "Free/background: " + str(free)
	_needs_label.text = "Used by built production buildings."
	_status_label.text = _short_status(status_text)
	_hint_label.text = "Click row for details"
	_build_button.visible = false
	_destroy_button.visible = false
	_apply_panel_style(_selected, status_text)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if building_id != "":
				emit_signal("building_selected", building_id)
			accept_event()

func _on_build_pressed() -> void:
	if building_id != "":
		emit_signal("build_requested", building_id)

func _on_destroy_pressed() -> void:
	if building_id != "":
		emit_signal("destroy_requested", building_id)

func _ensure_ui() -> void:
	if _name_label != null:
		return

	for child: Node in get_children():
		child.queue_free()

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.name = "Stack"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 8)
	stack.add_child(header)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(0.96, 0.98, 0.92, 1.0))
	header.add_child(_name_label)

	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.name = "ActionButtons"
	action_row.add_theme_constant_override("separation", 6)
	header.add_child(action_row)

	_build_button = Button.new()
	_build_button.name = "BuildButton"
	_build_button.text = "+"
	_build_button.custom_minimum_size = Vector2(42, 38)
	_build_button.add_theme_font_size_override("font_size", 24)
	_build_button.pressed.connect(_on_build_pressed)
	action_row.add_child(_build_button)

	_destroy_button = Button.new()
	_destroy_button.name = "DestroyButton"
	_destroy_button.text = "−"
	_destroy_button.custom_minimum_size = Vector2(42, 38)
	_destroy_button.add_theme_font_size_override("font_size", 25)
	_destroy_button.pressed.connect(_on_destroy_pressed)
	action_row.add_child(_destroy_button)

	_count_label = _make_row_label(18, Color(0.82, 0.91, 0.86, 1.0))
	_count_label.name = "CountLabel"
	stack.add_child(_count_label)

	_makes_label = _make_row_label(18, Color(0.72, 0.94, 0.77, 1.0))
	_makes_label.name = "MakesLabel"
	stack.add_child(_makes_label)

	_needs_label = _make_row_label(18, Color(0.97, 0.88, 0.67, 1.0))
	_needs_label.name = "NeedsLabel"
	stack.add_child(_needs_label)

	_status_label = _make_row_label(17, Color(0.90, 0.93, 0.88, 1.0))
	_status_label.name = "StatusLabel"
	stack.add_child(_status_label)

	_hint_label = _make_row_label(15, Color(0.63, 0.73, 0.68, 1.0))
	_hint_label.name = "HintLabel"
	stack.add_child(_hint_label)

func _make_row_label(font_size: int, colour: Color) -> Label:
	var label: Label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label

func _count_text(count: int, operating: int, blocked: int) -> String:
	var text_value: String = "Built " + str(count) + " | Operating " + str(operating) + "/" + str(count)
	if blocked > 0:
		text_value += " | Blocked " + str(blocked)
	return text_value

func _need_summary(inputs: Dictionary, staff: Dictionary, max_items: int = 2) -> String:
	var parts: Array[String] = []
	var input_text: String = _dictionary_inline(inputs, max_items)
	if input_text != "none":
		parts.append(input_text)
	var staff_text: String = _dictionary_inline(staff, max_items)
	if staff_text != "none":
		parts.append("Staff " + staff_text)
	if parts.is_empty():
		return "none"
	return " | ".join(parts)

func _short_status(status_text: String) -> String:
	var clean: String = status_text.strip_edges().replace("\n", " ")
	if clean == "":
		clean = "unknown"
	if clean.length() > 64:
		clean = clean.substr(0, 61) + "..."
	return "Status: " + clean

func _dictionary_inline(values: Dictionary, max_items: int = 2) -> String:
	if values.is_empty():
		return "none"
	var parts: Array[String] = []
	var added: int = 0
	for key_variant: Variant in values.keys():
		if added >= max_items:
			break
		var key: String = String(key_variant).replace("_", " ").capitalize()
		var amount: float = float(values[key_variant])
		if absf(amount) <= 0.001:
			continue
		parts.append(key + " " + _format_amount(amount))
		added += 1
	if values.size() > max_items:
		parts.append("+" + str(values.size() - max_items) + " more")
	if parts.is_empty():
		return "none"
	return "; ".join(parts)

func _multiply_dictionary(values: Dictionary, multiplier: int) -> Dictionary:
	var result: Dictionary = {}
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		result[key] = float(values[key_variant]) * float(multiplier)
	return result

func _format_amount(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))

func _build_tooltip(data: Dictionary) -> String:
	var tooltip: String = String(data.get("description", ""))
	if tooltip != "":
		tooltip += "\n\n"
	tooltip += "Click the row for the full building detail panel. Use + to build one and − to destroy one. Destroying gives no refund in the current prototype."
	return tooltip

func _apply_panel_style(selected: bool, status_text: String) -> void:
	var border: Color = Color(0.34, 0.71, 0.63, 0.50)
	var background: Color = Color(0.035, 0.06, 0.055, 0.95)
	var lower_status: String = status_text.to_lower()
	if lower_status.find("blocked") >= 0 or lower_status.find("not enough") >= 0 or lower_status.find("overstretched") >= 0:
		border = Color(0.90, 0.27, 0.22, 0.80)
	elif lower_status.find("operating") >= 0 or lower_status.find("available") >= 0:
		border = Color(0.35, 0.82, 0.52, 0.70)
	if selected:
		background = Color(0.09, 0.11, 0.085, 0.98)
		border = Color(0.76, 0.63, 0.32, 0.92)
	add_theme_stylebox_override("panel", _make_panel_style(background, border, 10))

func _apply_action_button_styles() -> void:
	if _build_button:
		_build_button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.06, 0.20, 0.10, 0.96), Color(0.35, 0.90, 0.45, 0.88), 8))
		_build_button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.08, 0.28, 0.13, 0.98), Color(0.50, 1.0, 0.60, 0.95), 8))
		_build_button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.04, 0.15, 0.08, 1.0), Color(0.25, 0.75, 0.35, 1.0), 8))
		_build_button.add_theme_stylebox_override("disabled", _make_panel_style(Color(0.08, 0.10, 0.085, 0.75), Color(0.28, 0.34, 0.30, 0.55), 8))
	if _destroy_button:
		_destroy_button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.22, 0.06, 0.055, 0.96), Color(0.95, 0.32, 0.25, 0.88), 8))
		_destroy_button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.32, 0.08, 0.07, 0.98), Color(1.0, 0.48, 0.38, 0.95), 8))
		_destroy_button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.16, 0.04, 0.04, 1.0), Color(0.85, 0.22, 0.18, 1.0), 8))
		_destroy_button.add_theme_stylebox_override("disabled", _make_panel_style(Color(0.10, 0.08, 0.08, 0.75), Color(0.34, 0.28, 0.28, 0.55), 8))

func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.26)
	style.shadow_size = 5
	return style
