# BuildingView.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/BuildingView.gd
extends Control

signal building_closed
signal build_requested(building_id: String)

@onready var overlay_panel: PanelContainer = get_node_or_null(^"OverlayPanel") as PanelContainer
@onready var title_label: Label = get_node_or_null(^"OverlayPanel/Margin/Stack/Header/TitleLabel") as Label
@onready var close_button: Button = get_node_or_null(^"OverlayPanel/Margin/Stack/Header/CloseButton") as Button
@onready var detail_text: RichTextLabel = get_node_or_null(^"OverlayPanel/Margin/Stack/DetailText") as RichTextLabel
@onready var build_button: Button = get_node_or_null(^"OverlayPanel/Margin/Stack/BuildButton") as Button

var buildings: Array[Dictionary] = []
var selected_building_id: String = ""

func _ready() -> void:
	_apply_styles()
	if close_button:
		close_button.pressed.connect(close_detail)
	if build_button:
		build_button.pressed.connect(_on_build_pressed)
	_hide_detail()

func setup(building_data: Array[Dictionary], selected_id: String = "") -> void:
	buildings = building_data
	selected_building_id = selected_id
	if selected_building_id == "":
		_hide_detail()
	else:
		_update_detail()

func select_building(building_id: String) -> void:
	selected_building_id = building_id
	_update_detail()

func close_detail() -> void:
	selected_building_id = ""
	_hide_detail()
	emit_signal("building_closed")

func refresh(building_data: Array[Dictionary]) -> void:
	buildings = building_data
	if selected_building_id == "":
		_hide_detail()
	else:
		_update_detail()

func _hide_detail() -> void:
	if overlay_panel:
		overlay_panel.visible = false

func _update_detail() -> void:
	var data: Dictionary = _find_building(selected_building_id)
	if data.is_empty():
		_hide_detail()
		return
	if overlay_panel:
		overlay_panel.visible = true
	if title_label:
		title_label.text = String(data.get("name", "Building"))
	if detail_text:
		detail_text.bbcode_enabled = true
		detail_text.text = _build_detail_text(data)
	if build_button:
		var is_labour: bool = bool(data.get("is_labour", false))
		build_button.visible = not is_labour
		if not is_labour:
			build_button.disabled = not bool(data.get("can_build", false))
			build_button.text = "Build" if bool(data.get("can_build", false)) else String(data.get("build_status", "Cannot build"))

func _find_building(building_id: String) -> Dictionary:
	for item_variant: Variant in buildings:
		var item: Dictionary = item_variant as Dictionary
		if String(item.get("id", "")) == building_id:
			return item
	return {}

func _build_detail_text(data: Dictionary) -> String:
	var text: String = ""
	text += String(data.get("description", "")) + "\n\n"
	text += "[b]Built[/b]: " + str(int(data.get("count", 0))) + "\n"
	text += "[b]Operation[/b]: " + String(data.get("status_text", "")) + "\n\n"
	text += "[b]Staff required[/b]\n"
	text += _dictionary_lines(data.get("staff", {}) as Dictionary)
	text += "\n[b]Inputs per Veintena[/b]\n"
	text += _dictionary_lines(data.get("inputs", {}) as Dictionary)
	text += "\n[b]Outputs per Veintena[/b]\n"
	text += _dictionary_lines(data.get("outputs", {}) as Dictionary)
	text += "\n[b]Build cost[/b]\n"
	text += _dictionary_lines(data.get("build_cost", {}) as Dictionary)
	text += "\n[b]Build status[/b]: " + String(data.get("build_status", ""))
	return text

func _dictionary_lines(values: Dictionary) -> String:
	if values.is_empty():
		return "• None\n"
	var lines: String = ""
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant).replace("_", " ").capitalize()
		lines += "• " + key + ": " + _format_amount(float(values[key_variant])) + "\n"
	return lines

func _format_amount(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))

func _on_build_pressed() -> void:
	if selected_building_id != "":
		emit_signal("build_requested", selected_building_id)


func _apply_styles() -> void:
	if title_label:
		title_label.add_theme_font_size_override("font_size", 28)
	if detail_text:
		detail_text.add_theme_font_size_override("normal_font_size", 21)
		detail_text.add_theme_font_size_override("bold_font_size", 21)
		detail_text.add_theme_constant_override("line_separation", 4)
	if build_button:
		build_button.custom_minimum_size = Vector2(0, 54)
		build_button.add_theme_font_size_override("font_size", 21)
	if close_button:
		close_button.custom_minimum_size = Vector2(44, 38)
		close_button.add_theme_font_size_override("font_size", 21)
