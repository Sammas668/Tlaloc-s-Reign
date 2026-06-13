# BuildingLedgerRow.gd
# Godot 4.x
# Project path: res://Scripts/ui/BuildingLedgerRow.gd
extends Button

signal building_selected(building_id: String)

var building_id: String = ""

@onready var name_label: Label = get_node_or_null(^"Margin/Stack/NameLabel") as Label
@onready var count_label: Label = get_node_or_null(^"Margin/Stack/CountLabel") as Label
@onready var status_label: Label = get_node_or_null(^"Margin/Stack/StatusLabel") as Label
@onready var cost_label: Label = get_node_or_null(^"Margin/Stack/CostLabel") as Label

func _ready() -> void:
	custom_minimum_size = Vector2(0, 118)
	clip_text = true
	pressed.connect(_on_pressed)

func set_building_data(data: Dictionary, selected: bool) -> void:
	building_id = String(data.get("id", ""))
	button_pressed = selected
	if name_label:
		name_label.text = String(data.get("name", "Building"))
	if count_label:
		count_label.text = "Built: " + str(int(data.get("count", 0)))
	if status_label:
		status_label.text = String(data.get("status_text", ""))
	if cost_label:
		var can_build: bool = bool(data.get("can_build", false))
		var build_status: String = String(data.get("build_status", ""))
		cost_label.text = "Build: " + ("ready" if can_build else build_status)
	tooltip_text = String(data.get("description", ""))

func _on_pressed() -> void:
	if building_id != "":
		emit_signal("building_selected", building_id)
