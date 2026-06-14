# HousingLedgerRow.gd
# Godot 4.x
# Project path: res://Scripts/ui/HousingLedgerRow.gd
extends PanelContainer

signal housing_selected(housing_id: String)
signal build_requested(housing_id: String)
signal destroy_requested(housing_id: String)

var _housing_id: String = ""
var _is_summary: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_housing_data(data: Dictionary, selected: bool = false) -> void:
	_housing_id = String(data.get("id", ""))
	_is_summary = bool(data.get("is_summary", false))
	_clear_children(self)
	var row_height: int = 198
	if _is_summary:
		row_height = 168
	custom_minimum_size = Vector2(0, row_height)
	var border: Color = Color(0.34, 0.71, 0.63, 0.45)
	if selected:
		border = Color(0.76, 0.63, 0.32, 0.86)
	add_theme_stylebox_override("panel", _make_style(Color(0.035, 0.06, 0.055, 0.94), border, 10))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var main_button: Button = Button.new()
	main_button.text = _summary_text(data) if _is_summary else _building_text(data)
	main_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_button.clip_text = true
	main_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	main_button.add_theme_font_size_override("font_size", 17)
	main_button.pressed.connect(func() -> void:
		emit_signal("housing_selected", _housing_id)
	)
	row.add_child(main_button)

	if not _is_summary:
		var actions: VBoxContainer = VBoxContainer.new()
		actions.custom_minimum_size = Vector2(54, 0)
		actions.add_theme_constant_override("separation", 8)
		row.add_child(actions)

		var build_button: Button = Button.new()
		build_button.text = "+"
		build_button.disabled = not bool(data.get("can_build", false))
		build_button.custom_minimum_size = Vector2(52, 52)
		build_button.add_theme_font_size_override("font_size", 25)
		build_button.add_theme_stylebox_override("normal", _make_style(Color(0.06, 0.24, 0.14, 0.96), Color(0.2, 0.8, 0.42, 0.75), 10))
		build_button.tooltip_text = String(data.get("build_status", "Build one"))
		build_button.pressed.connect(func() -> void:
			emit_signal("build_requested", _housing_id)
		)
		actions.add_child(build_button)

		var destroy_button: Button = Button.new()
		destroy_button.text = "−"
		destroy_button.disabled = not bool(data.get("can_destroy", false))
		destroy_button.custom_minimum_size = Vector2(52, 52)
		destroy_button.add_theme_font_size_override("font_size", 25)
		destroy_button.add_theme_stylebox_override("normal", _make_style(Color(0.28, 0.08, 0.06, 0.96), Color(0.9, 0.28, 0.22, 0.75), 10))
		destroy_button.tooltip_text = String(data.get("destroy_status", "Destroy one"))
		destroy_button.pressed.connect(func() -> void:
			emit_signal("destroy_requested", _housing_id)
		)
		actions.add_child(destroy_button)

func _summary_text(data: Dictionary) -> String:
	var text: String = String(data.get("name", "Housing")) + "\n"
	text += "Pop " + str(int(data.get("population", 0))) + " / Cap " + str(int(data.get("capacity", 0)))
	text += " | Free " + str(int(data.get("free_capacity", 0)))
	var over: int = int(data.get("over_capacity", 0))
	if over > 0:
		text += " | Over " + str(over)
	text += "\nStatus: " + String(data.get("status", "Unknown"))
	text += "\nBuilding upkeep: " + _dictionary_text(data.get("maintenance", {}) as Dictionary)
	var options: Array = data.get("building_options", []) as Array
	if not options.is_empty():
		text += "\nOptions: "
		var option_names: Array[String] = []
		for option_variant: Variant in options:
			var option: Dictionary = option_variant as Dictionary
			option_names.append(String(option.get("name", "Housing")))
		text += ", ".join(option_names)
	return text

func _building_text(data: Dictionary) -> String:
	var text: String = String(data.get("name", "Housing")) + "\n"
	text += "Built: " + str(int(data.get("count", 0))) + " | " + String(data.get("tier", "")).capitalize() + "\n"
	text += "Adds: " + _dictionary_text(data.get("housing_capacity", {}) as Dictionary) + "\n"
	text += "Upkeep/building: " + _dictionary_text(data.get("housing_maintenance", {}) as Dictionary) + "\n"
	text += "Cost: " + _dictionary_text(data.get("build_cost", {}) as Dictionary) + "\n"
	return text

func _dictionary_text(values: Dictionary) -> String:
	var parts: Array[String] = []
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		parts.append(_display_name(key) + " " + _format_amount(float(values[key_variant])))
	if parts.is_empty():
		return "None"
	return "; ".join(parts)

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

func _make_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	return style

func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		child.queue_free()
