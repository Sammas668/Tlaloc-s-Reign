# MarketLedgerRow.gd
# Godot 4.x
# Project path: res://Scripts/ui/MarketLedgerRow.gd
extends Button

signal good_selected(good_id: String)

@onready var name_label: Label = get_node_or_null(^"Margin/Stack/NameLabel") as Label
@onready var stock_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/StockLabel") as Label
@onready var demand_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/DemandLabel") as Label
@onready var value_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/ValueLabel") as Label
@onready var coverage_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/CoverageLabel") as Label
@onready var label_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/LabelLabel") as Label
@onready var trend_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/TrendLabel") as Label

var good_id: String = ""

func _ready() -> void:
	text = ""
	clip_contents = true
	custom_minimum_size = Vector2(0, 132)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	toggle_mode = true
	pressed.connect(_on_pressed)
	_apply_text_sizes()

func set_good_data(data: Dictionary, selected: bool) -> void:
	good_id = String(data.get("id", ""))
	var good_name: String = String(data.get("name", "Good"))
	var market_stock: float = float(data.get("market_stock", 0.0))
	var demand: float = float(data.get("demand", 0.0))
	var current_value: float = float(data.get("current_value", 0.0))
	var coverage: float = float(data.get("coverage", 0.0))
	var market_label: String = String(data.get("label", "Unknown"))
	var trend: String = String(data.get("trend", "Stable"))

	text = ""
	button_pressed = selected
	custom_minimum_size = Vector2(0, 132)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	if name_label:
		name_label.text = good_name
	if stock_label:
		stock_label.text = "Stock " + _fmt(market_stock)
	if demand_label:
		demand_label.text = "Demand " + _fmt(demand)
	if value_label:
		value_label.text = "Value " + _fmt(current_value)
	if coverage_label:
		coverage_label.text = "Cover " + _fmt(coverage)
	if label_label:
		label_label.text = market_label
	if trend_label:
		trend_label.text = trend

	tooltip_text = good_name \
		+ "\nMarket stock: " + _fmt(market_stock) \
		+ "\nDemand / turn: " + _fmt(demand) \
		+ "\nCoverage: " + _fmt(coverage) + " turns" \
		+ "\nCurrent value: " + _fmt(current_value) \
		+ "\nState: " + market_label \
		+ "\nTrend: " + trend

func set_selected(selected: bool) -> void:
	button_pressed = selected

func _on_pressed() -> void:
	emit_signal("good_selected", good_id)

func _apply_text_sizes() -> void:
	if name_label:
		name_label.add_theme_font_size_override("font_size", 16)
	var metric_labels: Array[Label] = [stock_label, demand_label, value_label, coverage_label, label_label, trend_label]
	for label: Label in metric_labels:
		if label:
			label.add_theme_font_size_override("font_size", 13)

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value
