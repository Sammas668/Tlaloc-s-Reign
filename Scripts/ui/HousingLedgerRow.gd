# HousingLedgerRow.gd
# Godot 4.x
# Project path: res://Scripts/ui/HousingLedgerRow.gd
#
# Production-style Housing ledger row.
# Mirrors BuildingLedgerRow layout so Housing population tabs visually match
# Production > Chinampas / Workshops rows while keeping housing-specific wording.
extends PanelContainer

signal housing_selected(housing_id: String)
signal build_requested(housing_id: String)
signal destroy_requested(housing_id: String)

var _housing_id: String = ""
var _is_summary: bool = false
var _data: Dictionary = {}
var _selected: bool = false

var _name_label: Label
var _count_label: Label
var _provides_label: Label
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
		_apply_panel_style(_selected, String(_data.get("status_text", _data.get("status", ""))))
		_apply_action_button_styles()

func set_housing_data(data: Dictionary, selected: bool = false) -> void:
	_ensure_ui()
	_data = data
	_selected = selected
	_housing_id = String(data.get("id", ""))
	_is_summary = bool(data.get("is_summary", false))
	tooltip_text = _build_tooltip(data)

	if _is_summary:
		_set_summary_data(data)
		return

	_set_building_data(data)

func _set_summary_data(data: Dictionary) -> void:
	var display_name: String = String(data.get("name", "Housing"))
	var population: int = int(data.get("population", 0))
	var active_population: int = int(data.get("active_population", population))
	var inactive_population: int = int(data.get("inactive_population", max(0, population - active_population)))
	var active_capacity: int = int(data.get("active_capacity", data.get("capacity", 0)))
	var built_capacity: int = int(data.get("capacity", active_capacity))
	var free_capacity: int = int(data.get("free_capacity", max(0, active_capacity - active_population)))
	var status_text: String = String(data.get("status", "Unknown"))

	_name_label.text = display_name
	_count_label.text = "Total pop " + str(population) + " | Active " + str(active_population) + " | Inactive " + str(inactive_population)
	_provides_label.text = "Active capacity: " + str(active_capacity) + " | Built capacity: " + str(built_capacity)
	_needs_label.text = "Building upkeep: " + _dictionary_inline(data.get("maintenance", {}) as Dictionary, 2)
	_status_label.text = "Free active space " + str(free_capacity) + " | " + _short_status(status_text, false)
	_hint_label.text = "Open Housing reports for the full breakdown"

	_build_button.visible = false
	_destroy_button.visible = false
	_apply_panel_style(_selected, status_text)

func _set_building_data(data: Dictionary) -> void:
	var display_name: String = String(data.get("name", "Housing"))
	var count: int = int(data.get("count", 0))
	var active_count: int = int(data.get("active_count", count))
	var mothballed: int = int(data.get("mothballed_count", max(0, count - active_count)))
	var status_text: String = String(data.get("status_text", "Not built."))

	var capacity_one: Dictionary = data.get("housing_capacity", {}) as Dictionary
	var upkeep_one: Dictionary = data.get("housing_maintenance", {}) as Dictionary

	var active_capacity: Dictionary = data.get("active_capacity_total", {}) as Dictionary
	if active_capacity.is_empty() and active_count > 0:
		active_capacity = _multiply_dictionary(capacity_one, active_count)

	var built_capacity: Dictionary = data.get("capacity_total", {}) as Dictionary
	if built_capacity.is_empty() and count > 0:
		built_capacity = _multiply_dictionary(capacity_one, count)

	var upkeep_total: Dictionary = data.get("maintenance_total", {}) as Dictionary
	if upkeep_total.is_empty() and count > 0:
		upkeep_total = _multiply_dictionary(upkeep_one, count)

	_name_label.text = display_name
	_count_label.text = "Built " + str(count) + " | Active " + str(active_count) + "/" + str(count) + " | Mothballed " + str(mothballed)

	if count > 0:
		_provides_label.text = "Provides now: " + _dictionary_inline(active_capacity, 2)
		_needs_label.text = "Upkeep now: " + _dictionary_inline(upkeep_total, 2)
	else:
		_provides_label.text = "Provides if built: " + _dictionary_inline(capacity_one, 2)
		_needs_label.text = "Upkeep if built: " + _dictionary_inline(upkeep_one, 2)

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

	_apply_panel_style(_selected, status_text)
	_apply_action_button_styles()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if _housing_id != "":
				emit_signal("housing_selected", _housing_id)
			accept_event()

func _on_build_pressed() -> void:
	if _housing_id != "":
		emit_signal("build_requested", _housing_id)

func _on_destroy_pressed() -> void:
	if _housing_id != "":
		emit_signal("destroy_requested", _housing_id)

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
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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

	_provides_label = _make_row_label(18, Color(0.72, 0.94, 0.77, 1.0))
	_provides_label.name = "ProvidesLabel"
	stack.add_child(_provides_label)

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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label

func _apply_panel_style(selected: bool, status_text: String) -> void:
	var border: Color = Color(0.34, 0.71, 0.63, 0.45)
	if selected:
		border = Color(0.76, 0.63, 0.32, 0.86)
	elif status_text.to_lower().find("over") >= 0 or status_text.to_lower().find("short") >= 0:
		border = Color(0.90, 0.35, 0.26, 0.74)
	elif status_text.to_lower().find("full") >= 0 or status_text.to_lower().find("tight") >= 0:
		border = Color(0.95, 0.66, 0.22, 0.70)
	add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.06, 0.055, 0.94), border, 10))

func _apply_action_button_styles() -> void:
	if _build_button:
		_build_button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.06, 0.24, 0.14, 0.96), Color(0.2, 0.8, 0.42, 0.75), 10))
		_build_button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.08, 0.30, 0.18, 0.98), Color(0.35, 0.95, 0.55, 0.85), 10))
		_build_button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.04, 0.18, 0.10, 0.98), Color(0.2, 0.8, 0.42, 0.75), 10))
		_build_button.add_theme_stylebox_override("disabled", _make_panel_style(Color(0.12, 0.13, 0.13, 0.90), Color(0.35, 0.36, 0.34, 0.65), 10))
	if _destroy_button:
		_destroy_button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.28, 0.08, 0.06, 0.96), Color(0.9, 0.28, 0.22, 0.75), 10))
		_destroy_button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.36, 0.10, 0.08, 0.98), Color(1.0, 0.42, 0.35, 0.85), 10))
		_destroy_button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.22, 0.06, 0.05, 0.98), Color(0.9, 0.28, 0.22, 0.75), 10))
		_destroy_button.add_theme_stylebox_override("disabled", _make_panel_style(Color(0.12, 0.13, 0.13, 0.90), Color(0.35, 0.36, 0.34, 0.65), 10))

func _short_status(status_text: String, prefix: bool = true) -> String:
	var clean: String = status_text.strip_edges().replace("\n", " ")
	if clean == "":
		clean = "unknown"
	if clean.length() > 64:
		clean = clean.substr(0, 61) + "..."
	return ("Status: " if prefix else "") + clean

func _dictionary_inline(values: Dictionary, max_items: int = 2) -> String:
	if values.is_empty():
		return "none"
	var parts: Array[String] = []
	var added: int = 0
	for key_variant: Variant in values.keys():
		if added >= max_items:
			break
		var key: String = String(key_variant)
		var amount: float = float(values[key_variant])
		if absf(amount) <= 0.001:
			continue
		parts.append(_display_name(key) + " " + _format_amount(amount))
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

func _build_tooltip(data: Dictionary) -> String:
	if bool(data.get("is_summary", false)):
		return String(data.get("name", "Housing")) + " housing summary. Open reports from Overview for full detail."
	return String(data.get("name", "Housing")) + "\nBuild: " + String(data.get("build_status", "")) + "\nDestroy: " + String(data.get("destroy_status", ""))

func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	return style
