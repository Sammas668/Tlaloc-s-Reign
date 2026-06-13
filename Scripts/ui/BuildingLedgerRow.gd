# BuildingLedgerRow.gd
# Godot 4.x
# Project path: res://Scripts/ui/BuildingLedgerRow.gd
extends Button

signal building_selected(building_id: String)

var building_id: String = ""

@onready var name_label: Label = get_node_or_null(^"Margin/Stack/NameLabel") as Label
@onready var count_label: Label = get_node_or_null(^"Margin/Stack/CountLabel") as Label
@onready var one_label: Label = get_node_or_null(^"Margin/Stack/OneLabel") as Label
@onready var all_label: Label = get_node_or_null(^"Margin/Stack/AllLabel") as Label
@onready var status_label: Label = get_node_or_null(^"Margin/Stack/StatusLabel") as Label
@onready var cost_label: Label = get_node_or_null(^"Margin/Stack/CostLabel") as Label

func _ready() -> void:
	custom_minimum_size = Vector2(0, 230)
	clip_text = true
	pressed.connect(_on_pressed)
	_apply_text_sizes()

func set_building_data(data: Dictionary, selected: bool) -> void:
	building_id = String(data.get("id", ""))
	button_pressed = selected
	var is_labour: bool = bool(data.get("is_labour", false))
	if name_label:
		name_label.text = String(data.get("name", "Building"))
	if count_label:
		if is_labour:
			count_label.text = "Population: " + str(int(data.get("count", 0)))
		else:
			count_label.text = "Built: " + str(int(data.get("count", 0))) + "    Operating: " + str(int(data.get("operating", 0))) + " / " + str(int(data.get("count", 0)))
	if one_label:
		if is_labour:
			one_label.text = _labour_short_text(data)
		else:
			one_label.text = "One: needs " + _dictionary_inline(data.get("inputs", {}) as Dictionary) + " | makes " + _dictionary_inline(data.get("outputs", {}) as Dictionary)
	if all_label:
		if is_labour:
			all_label.text = String(data.get("build_status", "Managed through population and housing."))
		else:
			var count: int = int(data.get("count", 0))
			var total_inputs: Dictionary = data.get("inputs_total", _multiply_dictionary(data.get("inputs", {}) as Dictionary, count)) as Dictionary
			var total_outputs: Dictionary = data.get("outputs_total", _multiply_dictionary(data.get("outputs", {}) as Dictionary, count)) as Dictionary
			all_label.text = "All: need " + _dictionary_inline(total_inputs) + " | make " + _dictionary_inline(total_outputs)
	if status_label:
		status_label.text = String(data.get("status_text", ""))
	if cost_label:
		if is_labour:
			cost_label.text = "Open for full labour pressure."
		else:
			var can_build: bool = bool(data.get("can_build", false))
			var can_destroy: bool = bool(data.get("can_destroy", int(data.get("count", 0)) > 0))
			var build_status: String = "Build ready" if can_build else String(data.get("build_status", "Cannot build"))
			var destroy_status: String = "Destroy ready" if can_destroy else String(data.get("destroy_status", "Nothing to destroy"))
			cost_label.text = build_status + " | " + destroy_status
	tooltip_text = String(data.get("description", ""))

func _labour_short_text(data: Dictionary) -> String:
	var staff: Dictionary = data.get("staff", {}) as Dictionary
	var total: int = int(staff.get("total_population", data.get("count", 0)))
	var required: int = int(staff.get("required_by_built_production", data.get("operating", 0)))
	var free: int = int(staff.get("free_or_background_labour", max(0, total - required)))
	return "Required: " + str(required) + " | Available: " + str(total) + " | Free/background: " + str(free)

func _dictionary_inline(values: Dictionary) -> String:
	if values.is_empty():
		return "none"
	var parts: Array[String] = []
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant).replace("_", " ").capitalize()
		parts.append(key + " " + _format_amount(float(values[key_variant])))
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

func _on_pressed() -> void:
	if building_id != "":
		emit_signal("building_selected", building_id)

func _apply_text_sizes() -> void:
	if name_label:
		name_label.add_theme_font_size_override("font_size", 22)
	if count_label:
		count_label.add_theme_font_size_override("font_size", 18)
	if one_label:
		one_label.add_theme_font_size_override("font_size", 17)
		one_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if all_label:
		all_label.add_theme_font_size_override("font_size", 17)
		all_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if status_label:
		status_label.add_theme_font_size_override("font_size", 18)
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if cost_label:
		cost_label.add_theme_font_size_override("font_size", 17)
		cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
