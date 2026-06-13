# StockpileLedgerRow.gd
# Godot 4.x
# Project path: res://Scripts/ui/StockpileLedgerRow.gd
extends Button

signal good_selected(good_id: String)

@onready var name_label: Label = get_node_or_null(^"Margin/Stack/NameLabel") as Label
@onready var stored_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/StoredLabel") as Label
@onready var free_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/FreeLabel") as Label
@onready var incoming_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/IncomingLabel") as Label
@onready var outgoing_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/OutgoingLabel") as Label
@onready var net_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/NetLabel") as Label
@onready var reserved_label: Label = get_node_or_null(^"Margin/Stack/MetricGrid/ReservedLabel") as Label

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
	var stored: float = float(data.get("stored", 0.0))
	var incoming: float = float(data.get("incoming", 0.0))
	var outgoing: float = float(data.get("outgoing", 0.0))
	var reserved: float = float(data.get("reserved", 0.0))
	var free: float = maxf(0.0, stored - reserved)
	var net: float = incoming - outgoing

	text = ""
	button_pressed = selected
	custom_minimum_size = Vector2(0, 132)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	if name_label:
		name_label.text = good_name
	if stored_label:
		stored_label.text = "Stored " + _fmt(stored)
	if free_label:
		free_label.text = "Free " + _fmt(free)
	if incoming_label:
		incoming_label.text = "In +" + _fmt(incoming)
	if outgoing_label:
		outgoing_label.text = "Out -" + _fmt(outgoing)
	if net_label:
		net_label.text = "Net " + _signed_fmt(net)
	if reserved_label:
		reserved_label.text = "Reserved " + _fmt(reserved)

	tooltip_text = good_name \
		+ "\nStored: " + _fmt(stored) \
		+ "\nIncoming: +" + _fmt(incoming) \
		+ "\nOutgoing: -" + _fmt(outgoing) \
		+ "\nNet: " + _signed_fmt(net) \
		+ "\nReserved: " + _fmt(reserved) \
		+ "\nFree: " + _fmt(free)

func set_selected(selected: bool) -> void:
	button_pressed = selected

func _on_pressed() -> void:
	emit_signal("good_selected", good_id)

func _apply_text_sizes() -> void:
	if name_label:
		name_label.add_theme_font_size_override("font_size", 16)
	var metric_labels: Array[Label] = [stored_label, free_label, incoming_label, outgoing_label, net_label, reserved_label]
	for label: Label in metric_labels:
		if label:
			label.add_theme_font_size_override("font_size", 13)

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value

func _signed_fmt(value: float) -> String:
	if value >= 0.0:
		return "+" + _fmt(value)
	return "-" + _fmt(absf(value))
