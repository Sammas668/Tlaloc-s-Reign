# BuildingView.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/BuildingView.gd
extends Control

signal building_closed
signal build_requested(building_id: String)
signal destroy_requested(building_id: String)

@onready var overlay_panel: PanelContainer = get_node_or_null(^"OverlayPanel") as PanelContainer
@onready var overlay_stack: VBoxContainer = get_node_or_null(^"OverlayPanel/Margin/Stack") as VBoxContainer
@onready var title_label: Label = get_node_or_null(^"OverlayPanel/Margin/Stack/Header/TitleLabel") as Label
@onready var close_button: Button = get_node_or_null(^"OverlayPanel/Margin/Stack/Header/CloseButton") as Button
@onready var detail_text: RichTextLabel = get_node_or_null(^"OverlayPanel/Margin/Stack/DetailText") as RichTextLabel
@onready var build_button: Button = get_node_or_null(^"OverlayPanel/Margin/Stack/ActionRow/BuildButton") as Button
@onready var destroy_button: Button = get_node_or_null(^"OverlayPanel/Margin/Stack/ActionRow/DestroyButton") as Button

var buildings: Array[Dictionary] = []
var selected_building_id: String = ""

func _ready() -> void:
	_ensure_action_buttons()
	_apply_styles()
	if close_button:
		close_button.pressed.connect(close_detail)
	if build_button:
		build_button.pressed.connect(_on_build_pressed)
	if destroy_button:
		destroy_button.pressed.connect(_on_destroy_pressed)
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
	_update_action_buttons(data)

func _update_action_buttons(data: Dictionary) -> void:
	var is_labour: bool = bool(data.get("is_labour", false))
	if build_button:
		build_button.visible = not is_labour
		if not is_labour:
			var can_build_now: bool = bool(data.get("can_build", false))
			build_button.disabled = not can_build_now
			build_button.text = "Build one" if can_build_now else String(data.get("build_status", "Cannot build"))
	if destroy_button:
		destroy_button.visible = not is_labour
		if not is_labour:
			var can_destroy_now: bool = bool(data.get("can_destroy", int(data.get("count", 0)) > 0))
			destroy_button.disabled = not can_destroy_now
			destroy_button.text = "Destroy one" if can_destroy_now else String(data.get("destroy_status", "None built"))

func _find_building(building_id: String) -> Dictionary:
	for item_variant: Variant in buildings:
		var item: Dictionary = item_variant as Dictionary
		if String(item.get("id", "")) == building_id:
			return item
	return {}

func _build_detail_text(data: Dictionary) -> String:
	if bool(data.get("is_labour", false)):
		return _build_labour_detail_text(data)

	var count: int = int(data.get("count", 0))
	var operating: int = int(data.get("operating", 0))
	var blocked: int = int(data.get("blocked", 0))
	var text: String = ""
	text += String(data.get("description", "")) + "\n\n"
	text += "[b]Current building state[/b]\n"
	text += "• Built: " + str(count) + "\n"
	text += "• Operating: " + str(operating) + " / " + str(count) + "\n"
	text += "• Blocked: " + str(blocked) + "\n"
	text += "• Status: " + String(data.get("status_text", "")) + "\n"
	text += "• Build time: " + _build_time_text(data) + "\n\n"

	text += "[b]One building needs each Veintena[/b]\n"
	text += "Staff: " + _dictionary_inline(data.get("staff", {}) as Dictionary) + "\n"
	text += "Inputs: " + _dictionary_inline(data.get("inputs", {}) as Dictionary) + "\n\n"

	text += "[b]One building makes each Veintena[/b]\n"
	text += _dictionary_lines(data.get("outputs", {}) as Dictionary)
	text += "\n"

	text += "[b]All built copies need each Veintena[/b]\n"
	text += "Staff: " + _dictionary_inline(data.get("staff_total", _multiply_dictionary(data.get("staff", {}) as Dictionary, count)) as Dictionary) + "\n"
	text += "Inputs: " + _dictionary_inline(data.get("inputs_total", _multiply_dictionary(data.get("inputs", {}) as Dictionary, count)) as Dictionary) + "\n\n"

	text += "[b]All built copies make each Veintena[/b]\n"
	text += _dictionary_lines(data.get("outputs_total", _multiply_dictionary(data.get("outputs", {}) as Dictionary, count)) as Dictionary)
	text += "\n"

	text += "[b]Build one more[/b]\n"
	text += "Cost now:\n" + _dictionary_lines(data.get("build_cost", {}) as Dictionary)
	text += "Status: " + String(data.get("build_status", "")) + "\n"
	text += "After building one more: " + str(count + 1) + " total.\n"
	text += "Projected total inputs: " + _dictionary_inline(_multiply_dictionary(data.get("inputs", {}) as Dictionary, count + 1)) + "\n"
	text += "Projected total outputs: " + _dictionary_inline(_multiply_dictionary(data.get("outputs", {}) as Dictionary, count + 1)) + "\n\n"

	text += "[b]Destroy one[/b]\n"
	var after_destroy: int = max(0, count - 1)
	text += "Status: " + String(data.get("destroy_status", "")) + "\n"
	text += "After destroying one: " + str(after_destroy) + " total.\n"
	text += "Projected total inputs: " + _dictionary_inline(_multiply_dictionary(data.get("inputs", {}) as Dictionary, after_destroy)) + "\n"
	text += "Projected total outputs: " + _dictionary_inline(_multiply_dictionary(data.get("outputs", {}) as Dictionary, after_destroy)) + "\n"
	text += "No refund is currently given in the prototype."
	return text.strip_edges()

func _build_labour_detail_text(data: Dictionary) -> String:
	var text: String = ""
	text += String(data.get("description", "")) + "\n\n"
	text += "[b]Labour status[/b]\n"
	text += "• Population: " + str(int(data.get("count", 0))) + "\n"
	text += "• Status: " + String(data.get("status_text", "")) + "\n\n"
	text += "[b]Labour breakdown[/b]\n"
	text += _dictionary_lines(data.get("staff", {}) as Dictionary)
	return text.strip_edges()

func _dictionary_lines(values: Dictionary) -> String:
	if values.is_empty():
		return "• None\n"
	var lines: String = ""
	for key_variant: Variant in values.keys():
		var key: String = _display_key(String(key_variant))
		lines += "• " + key + ": " + _format_amount(float(values[key_variant])) + "\n"
	return lines

func _dictionary_inline(values: Dictionary) -> String:
	if values.is_empty():
		return "None"
	var parts: Array[String] = []
	for key_variant: Variant in values.keys():
		var key: String = _display_key(String(key_variant))
		parts.append(key + " " + _format_amount(float(values[key_variant])))
	return "; ".join(parts)

func _multiply_dictionary(values: Dictionary, multiplier: int) -> Dictionary:
	var result: Dictionary = {}
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		result[key] = float(values[key_variant]) * float(multiplier)
	return result

func _display_key(raw_key: String) -> String:
	return raw_key.replace("_", " ").capitalize()

func _build_time_text(data: Dictionary) -> String:
	var build_time: int = int(data.get("build_time_veintenas", 0))
	if build_time <= 0:
		return "Completes immediately in this prototype"
	if build_time == 1:
		return "1 Veintena"
	return str(build_time) + " Veintenas"

func _format_amount(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))

func _on_build_pressed() -> void:
	if selected_building_id != "":
		emit_signal("build_requested", selected_building_id)

func _on_destroy_pressed() -> void:
	if selected_building_id != "":
		emit_signal("destroy_requested", selected_building_id)

func _ensure_action_buttons() -> void:
	if build_button != null and destroy_button != null:
		return
	var stack: VBoxContainer = get_node_or_null(^"OverlayPanel/Margin/Stack") as VBoxContainer
	if stack == null:
		return
	var action_row: HBoxContainer = get_node_or_null(^"OverlayPanel/Margin/Stack/ActionRow") as HBoxContainer
	if action_row == null:
		action_row = HBoxContainer.new()
		action_row.name = "ActionRow"
		action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_row.add_theme_constant_override("separation", 10)
		var old_build: Button = get_node_or_null(^"OverlayPanel/Margin/Stack/BuildButton") as Button
		if old_build != null:
			stack.remove_child(old_build)
			action_row.add_child(old_build)
		stack.add_child(action_row)
	if build_button == null:
		build_button = get_node_or_null(^"OverlayPanel/Margin/Stack/ActionRow/BuildButton") as Button
	if build_button == null:
		build_button = Button.new()
		build_button.name = "BuildButton"
		action_row.add_child(build_button)
	if destroy_button == null:
		destroy_button = Button.new()
		destroy_button.name = "DestroyButton"
		action_row.add_child(destroy_button)

func _apply_styles() -> void:
	if overlay_panel:
		overlay_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		overlay_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		overlay_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.0, 0.0, 0.0, 0.62), Color(0.50, 0.82, 0.74, 0.35), 14))
	if overlay_stack:
		overlay_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		overlay_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
		overlay_stack.add_theme_constant_override("separation", 10)
	if title_label:
		title_label.add_theme_font_size_override("font_size", 28)
	if detail_text:
		detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		detail_text.custom_minimum_size = Vector2(0, 360)
		detail_text.fit_content = false
		detail_text.scroll_active = true
		detail_text.add_theme_font_size_override("normal_font_size", 21)
		detail_text.add_theme_font_size_override("bold_font_size", 23)
		detail_text.add_theme_constant_override("line_separation", 5)
	for button_variant: Variant in [build_button, destroy_button]:
		var button: Button = button_variant as Button
		if button:
			button.custom_minimum_size = Vector2(0, 56)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", 21)
	if close_button:
		close_button.custom_minimum_size = Vector2(44, 38)
		close_button.add_theme_font_size_override("font_size", 21)

func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	return style
