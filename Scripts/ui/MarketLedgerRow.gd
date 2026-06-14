# MarketLedgerRow.gd
# Godot 4.x
# Project path: res://Scripts/ui/MarketLedgerRow.gd
#
# Marketplace ledger row with restored colour functionality and full market info.
# Shows: Stock, Demand, Value, Coverage, State and Trend.
extends Button

signal good_selected(good_id: String)

const COLOR_TEXT: Color = Color(0.90, 0.86, 0.76, 1.0)
const COLOR_MUTED: Color = Color(0.67, 0.63, 0.54, 1.0)
const COLOR_POSITIVE: Color = Color(0.48, 0.92, 0.62, 1.0)
const COLOR_NEGATIVE: Color = Color(1.00, 0.38, 0.32, 1.0)
const COLOR_WARNING: Color = Color(1.00, 0.76, 0.35, 1.0)
const COLOR_TIGHT: Color = Color(1.00, 0.64, 0.25, 1.0)
const COLOR_TEAL: Color = Color(0.56, 0.90, 0.82, 1.0)

@onready var name_label: Label = get_node_or_null(^"Margin/Stack/NameLabel") as Label

@onready var stock_title: Label = get_node_or_null(^"Margin/Stack/Metrics/StockRow/Title") as Label
@onready var stock_value: Label = get_node_or_null(^"Margin/Stack/Metrics/StockRow/Value") as Label
@onready var demand_title: Label = get_node_or_null(^"Margin/Stack/Metrics/DemandRow/Title") as Label
@onready var demand_value: Label = get_node_or_null(^"Margin/Stack/Metrics/DemandRow/Value") as Label
@onready var value_title: Label = get_node_or_null(^"Margin/Stack/Metrics/ValueRow/Title") as Label
@onready var value_value: Label = get_node_or_null(^"Margin/Stack/Metrics/ValueRow/Value") as Label
@onready var coverage_title: Label = get_node_or_null(^"Margin/Stack/Metrics/CoverageRow/Title") as Label
@onready var coverage_value: Label = get_node_or_null(^"Margin/Stack/Metrics/CoverageRow/Value") as Label
@onready var state_title: Label = get_node_or_null(^"Margin/Stack/Metrics/StateRow/Title") as Label
@onready var state_value: Label = get_node_or_null(^"Margin/Stack/Metrics/StateRow/Value") as Label
@onready var trend_title: Label = get_node_or_null(^"Margin/Stack/Metrics/TrendRow/Title") as Label
@onready var trend_value: Label = get_node_or_null(^"Margin/Stack/Metrics/TrendRow/Value") as Label

var good_id: String = ""
var _pending_data: Dictionary = {}
var _pending_selected: bool = false
var _has_pending_data: bool = false

func _ready() -> void:
	text = ""
	clip_contents = true
	custom_minimum_size = Vector2(0, 236)
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
	custom_minimum_size = Vector2(0, 236)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tooltip_text = _build_tooltip(data)

	if is_node_ready():
		_apply_pending_data()

func set_selected(selected: bool) -> void:
	_pending_selected = selected
	button_pressed = selected
	if is_node_ready() and _has_pending_data:
		_apply_base_style(_state_colour(String(_pending_data.get("label", "Unknown"))), selected)

func _apply_pending_data() -> void:
	if not _has_pending_data:
		return

	var data: Dictionary = _pending_data
	var good_name: String = String(data.get("name", "Good"))
	var market_stock: float = float(data.get("market_stock", 0.0))
	var demand: float = float(data.get("village_total_demand", data.get("demand", data.get("outgoing", 0.0))))
	var current_value: float = float(data.get("projected_value", data.get("current_value", 0.0)))
	var coverage: float = float(data.get("projected_coverage", data.get("coverage", 0.0)))
	var market_state: String = String(data.get("label", "Unknown"))
	var trend: String = String(data.get("trend", "Stable"))
	var net_change: float = float(data.get("village_net_change", 0.0))

	button_pressed = _pending_selected

	if name_label:
		name_label.text = good_name
		name_label.add_theme_color_override("font_color", COLOR_TEXT)

	if stock_value:
		stock_value.text = _fmt(market_stock)
		stock_value.add_theme_color_override("font_color", COLOR_TEXT)
	if demand_value:
		demand_value.text = _fmt(demand)
		demand_value.add_theme_color_override("font_color", COLOR_MUTED)
	if value_value:
		value_value.text = _fmt(current_value)
		value_value.add_theme_color_override("font_color", _value_colour(data))
	if coverage_value:
		coverage_value.text = _fmt(coverage) + " turns"
		coverage_value.add_theme_color_override("font_color", COLOR_TEXT)
	if state_value:
		state_value.text = market_state
		state_value.add_theme_color_override("font_color", _state_colour(market_state))
	if trend_value:
		trend_value.text = _signed_fmt(net_change)
		trend_value.add_theme_color_override("font_color", _net_colour(net_change))

	_apply_base_style(_state_colour(market_state), _pending_selected)

func _apply_static_text() -> void:
	if stock_title:
		stock_title.text = "Stock"
	if demand_title:
		demand_title.text = "Need"
	if value_title:
		value_title.text = "Value"
	if coverage_title:
		coverage_title.text = "Cover"
	if state_title:
		state_title.text = "State"
	if trend_title:
		trend_title.text = "Net"

	var title_labels: Array[Label] = [stock_title, demand_title, value_title, coverage_title, state_title, trend_title]
	for label: Label in title_labels:
		if label:
			label.add_theme_color_override("font_color", COLOR_MUTED)

func _on_pressed() -> void:
	emit_signal("good_selected", good_id)

func _build_tooltip(data: Dictionary) -> String:
	var good_name: String = String(data.get("name", "Good"))
	var market_stock: float = float(data.get("market_stock", 0.0))
	var projected_stock: float = float(data.get("projected_market_stock", market_stock))
	var demand: float = float(data.get("village_total_demand", data.get("demand", data.get("outgoing", 0.0))))
	var coverage: float = float(data.get("projected_coverage", data.get("coverage", 0.0)))
	var base_value: float = float(data.get("base_value", 0.0))
	var current_value: float = float(data.get("projected_value", data.get("current_value", 0.0)))
	var market_state: String = String(data.get("label", "Unknown"))
	var trend: String = String(data.get("trend", "Stable"))
	var net_change: float = float(data.get("village_net_change", 0.0))

	return good_name \
		+ "\nMarket stock: " + _fmt(market_stock) \
		+ "\nProjected stock: " + _fmt(projected_stock) \
		+ "\nVillage need / turn: " + _fmt(demand) \
		+ "\nVillage net / turn: " + _signed_fmt(net_change) \
		+ "\nCoverage: " + _fmt(coverage) + " turns" \
		+ "\nBase value: " + _fmt(base_value) \
		+ "\nProjected value: " + _fmt(current_value) \
		+ "\nState: " + market_state \
		+ "\nTrend: " + trend

func _apply_text_sizes() -> void:
	if name_label:
		name_label.add_theme_font_size_override("font_size", 23)

	var title_labels: Array[Label] = [stock_title, demand_title, value_title, coverage_title, state_title, trend_title]
	for label: Label in title_labels:
		if label:
			label.add_theme_font_size_override("font_size", 16)

	var value_labels: Array[Label] = [stock_value, demand_value, value_value, coverage_value, state_value, trend_value]
	for label: Label in value_labels:
		if label:
			label.add_theme_font_size_override("font_size", 18)

func _apply_base_style(border_colour: Color, selected: bool) -> void:
	var normal_style: StyleBoxFlat = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.02, 0.05, 0.05, 0.72)
	normal_style.border_color = Color(border_colour.r, border_colour.g, border_colour.b, 0.38)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(10)
	normal_style.set_content_margin_all(10)

	var hover_style: StyleBoxFlat = normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.03, 0.08, 0.08, 0.86)
	hover_style.border_color = Color(border_colour.r, border_colour.g, border_colour.b, 0.65)

	var pressed_style: StyleBoxFlat = normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.06, 0.13, 0.12, 0.92)
	pressed_style.border_color = Color(border_colour.r, border_colour.g, border_colour.b, 0.95)
	pressed_style.set_border_width_all(2)

	if selected:
		add_theme_stylebox_override("normal", pressed_style)
	else:
		add_theme_stylebox_override("normal", normal_style)
	add_theme_stylebox_override("hover", hover_style)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("focus", pressed_style)

func _state_colour(state: String) -> Color:
	match state:
		"Crisis":
			return COLOR_NEGATIVE
		"Shortage":
			return COLOR_TIGHT
		"Tight":
			return COLOR_WARNING
		"Abundant":
			return COLOR_POSITIVE
		"Comfortable":
			return COLOR_TEAL
		_:
			return COLOR_MUTED

func _trend_colour(trend: String, state: String) -> Color:
	match trend:
		"Critical":
			return COLOR_NEGATIVE
		"Rising":
			return COLOR_WARNING
		"Soft":
			return COLOR_POSITIVE
		"Stable":
			return COLOR_TEAL
		_:
			return _state_colour(state)

func _value_colour(data: Dictionary) -> Color:
	var base_value: float = float(data.get("base_value", 0.0))
	var current_value: float = float(data.get("current_value", 0.0))
	if base_value <= 0.0:
		return COLOR_TEXT
	if current_value >= base_value * 1.5:
		return COLOR_POSITIVE
	if current_value <= base_value * 0.8:
		return COLOR_MUTED
	return COLOR_TEXT

func _net_colour(value: float) -> Color:
	if value > 0.001:
		return COLOR_POSITIVE
	if value < -0.001:
		return COLOR_NEGATIVE
	return COLOR_TEAL

func _signed_fmt(value: float) -> String:
	if value > 0.001:
		return "+" + _fmt(value)
	return _fmt(value)

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value
