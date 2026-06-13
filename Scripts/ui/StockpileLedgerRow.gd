# StockpileLedgerRow.gd
# Godot 4.x
# Project path: res://Scripts/ui/StockpileLedgerRow.gd
#
# Storehouse ledger row redesigned for shortage readability.
# The row now highlights:
# - status/risk
# - current stored stock
# - free stock after reservations
# - projected stock after this Veintena
# - net movement
extends Button

signal good_selected(good_id: String)

const COLOR_TEXT: Color = Color(0.90, 0.86, 0.76, 1.0)
const COLOR_MUTED: Color = Color(0.67, 0.63, 0.54, 1.0)
const COLOR_POSITIVE: Color = Color(0.48, 0.92, 0.62, 1.0)
const COLOR_NEGATIVE: Color = Color(1.00, 0.38, 0.32, 1.0)
const COLOR_WARNING: Color = Color(1.00, 0.76, 0.35, 1.0)
const COLOR_TEAL: Color = Color(0.56, 0.90, 0.82, 1.0)

@onready var name_label: Label = get_node_or_null(^"Margin/Stack/NameLabel") as Label

@onready var status_title: Label = get_node_or_null(^"Margin/Stack/Metrics/StatusRow/Title") as Label
@onready var status_value: Label = get_node_or_null(^"Margin/Stack/Metrics/StatusRow/Value") as Label
@onready var stored_title: Label = get_node_or_null(^"Margin/Stack/Metrics/StoredRow/Title") as Label
@onready var stored_value: Label = get_node_or_null(^"Margin/Stack/Metrics/StoredRow/Value") as Label
@onready var free_title: Label = get_node_or_null(^"Margin/Stack/Metrics/FreeRow/Title") as Label
@onready var free_value: Label = get_node_or_null(^"Margin/Stack/Metrics/FreeRow/Value") as Label
@onready var projected_title: Label = get_node_or_null(^"Margin/Stack/Metrics/ProjectedRow/Title") as Label
@onready var projected_value: Label = get_node_or_null(^"Margin/Stack/Metrics/ProjectedRow/Value") as Label
@onready var net_title: Label = get_node_or_null(^"Margin/Stack/Metrics/NetRow/Title") as Label
@onready var net_value: Label = get_node_or_null(^"Margin/Stack/Metrics/NetRow/Value") as Label
@onready var reserved_title: Label = get_node_or_null(^"Margin/Stack/Metrics/ReservedRow/Title") as Label
@onready var reserved_value: Label = get_node_or_null(^"Margin/Stack/Metrics/ReservedRow/Value") as Label

var good_id: String = ""
var _pending_data: Dictionary = {}
var _pending_selected: bool = false
var _has_pending_data: bool = false

func _ready() -> void:
	text = ""
	clip_contents = true
	custom_minimum_size = Vector2(0, 188)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	toggle_mode = true

	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

	_apply_static_text()
	_apply_text_sizes()
	_apply_base_style(COLOR_TEAL, false)

	if _has_pending_data:
		_apply_pending_data()

func set_good_data(data: Dictionary, selected: bool) -> void:
	_pending_data = data.duplicate(true)
	_pending_selected = selected
	_has_pending_data = true
	good_id = String(data.get("id", ""))

	text = ""
	button_pressed = selected
	custom_minimum_size = Vector2(0, 188)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tooltip_text = _build_tooltip(data)

	if is_node_ready():
		_apply_pending_data()

func set_selected(selected: bool) -> void:
	_pending_selected = selected
	button_pressed = selected
	if is_node_ready() and _has_pending_data:
		var status_text: String = _status_for(_pending_data)
		_apply_base_style(_status_colour(status_text), selected)

func _apply_pending_data() -> void:
	if not _has_pending_data:
		return

	var data: Dictionary = _pending_data
	var good_name: String = String(data.get("name", "Good"))
	var stored: float = float(data.get("stored", 0.0))
	var incoming: float = float(data.get("incoming", 0.0))
	var outgoing: float = float(data.get("outgoing", 0.0))
	var reserved: float = float(data.get("reserved", 0.0))
	var free: float = maxf(0.0, stored - reserved)
	var projected: float = float(data.get("projected", maxf(0.0, stored + incoming - outgoing)))
	var net: float = incoming - outgoing
	var status_text: String = _status_for(data)
	var status_colour: Color = _status_colour(status_text)

	button_pressed = _pending_selected

	if name_label:
		name_label.text = good_name
		name_label.add_theme_color_override("font_color", COLOR_TEXT)
	if status_value:
		status_value.text = status_text
		status_value.add_theme_color_override("font_color", status_colour)
	if stored_value:
		stored_value.text = _fmt(stored)
		stored_value.add_theme_color_override("font_color", COLOR_TEXT)
	if free_value:
		free_value.text = _fmt(free)
		free_value.add_theme_color_override("font_color", _free_colour(free))
	if projected_value:
		projected_value.text = _fmt(projected)
		projected_value.add_theme_color_override("font_color", _projected_colour(projected, reserved))
	if net_value:
		net_value.text = _signed_fmt(net)
		net_value.add_theme_color_override("font_color", _net_colour(net))
	if reserved_value:
		reserved_value.text = _fmt(reserved)
		reserved_value.add_theme_color_override("font_color", COLOR_MUTED)

	_apply_base_style(status_colour, _pending_selected)

func _apply_static_text() -> void:
	if status_title:
		status_title.text = "Status"
	if stored_title:
		stored_title.text = "Stored"
	if free_title:
		free_title.text = "Free"
	if projected_title:
		projected_title.text = "Projected"
	if net_title:
		net_title.text = "Net"
	if reserved_title:
		reserved_title.text = "Reserved"

	var title_labels: Array[Label] = [status_title, stored_title, free_title, projected_title, net_title, reserved_title]
	for label: Label in title_labels:
		if label:
			label.add_theme_color_override("font_color", COLOR_MUTED)

func _on_pressed() -> void:
	emit_signal("good_selected", good_id)

func _status_for(data: Dictionary) -> String:
	var stored: float = float(data.get("stored", 0.0))
	var incoming: float = float(data.get("incoming", 0.0))
	var outgoing: float = float(data.get("outgoing", 0.0))
	var reserved: float = float(data.get("reserved", 0.0))
	var projected: float = float(data.get("projected", maxf(0.0, stored + incoming - outgoing)))
	var free: float = maxf(0.0, stored - reserved)
	var net: float = incoming - outgoing

	var next_turn_required_need: float = outgoing

	if stored <= 0.0 and projected <= 0.0:
		return "EMPTY"
	if stored < reserved:
		return "RESERVE SHORT"
	if projected <= 0.0 and outgoing > 0.0:
		return "RUNS OUT"
	if next_turn_required_need > 0.0 and projected < next_turn_required_need:
		return "SHORT NEXT"
	if free <= 0.0 and reserved > 0.0:
		return "FULLY RESERVED"
	if net < -0.01:
		return "FALLING"
	if net > 0.01:
		return "BUILDING"
	return "STABLE"

func _status_colour(status_text: String) -> Color:
	match status_text:
		"EMPTY", "RESERVE SHORT", "RUNS OUT", "SHORT NEXT":
			return COLOR_NEGATIVE
		"FULLY RESERVED", "FALLING":
			return COLOR_WARNING
		"BUILDING":
			return COLOR_POSITIVE
		"STABLE":
			return COLOR_TEAL
		_:
			return COLOR_MUTED

func _projected_colour(projected: float, reserved: float) -> Color:
	if projected <= 0.0:
		return COLOR_NEGATIVE
	if projected < reserved:
		return COLOR_NEGATIVE
	if reserved > 0.0 and projected <= reserved * 1.25:
		return COLOR_WARNING
	return COLOR_TEXT

func _free_colour(free: float) -> Color:
	if free <= 0.0:
		return COLOR_WARNING
	return COLOR_TEAL

func _net_colour(value: float) -> Color:
	if value > 0.01:
		return COLOR_POSITIVE
	if value < -0.01:
		return COLOR_NEGATIVE
	return COLOR_MUTED

func _build_tooltip(data: Dictionary) -> String:
	var good_name: String = String(data.get("name", "Good"))
	var stored: float = float(data.get("stored", 0.0))
	var incoming: float = float(data.get("incoming", 0.0))
	var outgoing: float = float(data.get("outgoing", 0.0))
	var reserved: float = float(data.get("reserved", 0.0))
	var projected: float = float(data.get("projected", maxf(0.0, stored + incoming - outgoing)))
	var free: float = maxf(0.0, stored - reserved)
	var net: float = incoming - outgoing
	var status_text: String = _status_for(data)

	return good_name \
		+ "\nStatus: " + status_text \
		+ "\nStored: " + _fmt(stored) \
		+ "\nIncoming: +" + _fmt(incoming) \
		+ "\nOutgoing: -" + _fmt(outgoing) \
		+ "\nNet: " + _signed_fmt(net) \
		+ "\nProjected after turn: " + _fmt(projected) \
		+ "\nReserved: " + _fmt(reserved) \
		+ "\nFree: " + _fmt(free)

func _apply_text_sizes() -> void:
	if name_label:
		name_label.add_theme_font_size_override("font_size", 19)

	var title_labels: Array[Label] = [status_title, stored_title, free_title, projected_title, net_title, reserved_title]
	for label: Label in title_labels:
		if label:
			label.add_theme_font_size_override("font_size", 15)

	var value_labels: Array[Label] = [status_value, stored_value, free_value, projected_value, net_value, reserved_value]
	for label: Label in value_labels:
		if label:
			label.add_theme_font_size_override("font_size", 16)

func _apply_base_style(border_colour: Color, selected: bool) -> void:
	var normal_style: StyleBoxFlat = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.02, 0.05, 0.05, 0.74)
	normal_style.border_color = Color(border_colour.r, border_colour.g, border_colour.b, 0.38)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(10)
	normal_style.set_content_margin_all(6)

	var hover_style: StyleBoxFlat = normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.03, 0.08, 0.08, 0.88)
	hover_style.border_color = Color(border_colour.r, border_colour.g, border_colour.b, 0.65)

	var pressed_style: StyleBoxFlat = normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.06, 0.13, 0.12, 0.94)
	pressed_style.border_color = Color(border_colour.r, border_colour.g, border_colour.b, 0.90)
	pressed_style.set_border_width_all(2)

	if selected:
		add_theme_stylebox_override("normal", pressed_style)
	else:
		add_theme_stylebox_override("normal", normal_style)
	add_theme_stylebox_override("hover", hover_style)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("focus", pressed_style)

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value

func _signed_fmt(value: float) -> String:
	if value >= 0.0:
		return "+" + _fmt(value)
	return "-" + _fmt(absf(value))
