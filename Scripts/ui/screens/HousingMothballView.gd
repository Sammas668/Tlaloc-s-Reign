# HousingMothballView.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/HousingMothballView.gd
extends PanelContainer

signal active_housing_changed(housing_id: String, active_count: int)

var _data: Dictionary = {}
var _scroll: ScrollContainer = null

func _ready() -> void:
	_apply_panel_style()

func setup(data: Dictionary) -> void:
	_data = data.duplicate(true)
	_rebuild()

func refresh_from_data(data: Dictionary) -> void:
	var old_scroll: int = 0
	if _scroll:
		old_scroll = int(_scroll.scroll_vertical)
	setup(data)
	if _scroll:
		_scroll.set_deferred("scroll_vertical", old_scroll)

func _rebuild() -> void:
	_clear_children(self)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title: Label = _make_label("Mothball Housing", 31, true)
	root.add_child(title)
	var intro: Label = _make_label("Deactivate housing to reduce active population and population upkeep. Buildings still exist and still pay building maintenance.", 20, false)
	root.add_child(intro)

	var summary: Dictionary = _data.get("summary", {}) as Dictionary
	var summary_line: String = "Active population " + str(int(summary.get("total_active_population", 0))) + " / total " + str(int(summary.get("total_population", 0)))
	summary_line += " | Inactive " + str(int(summary.get("total_inactive_population", 0)))
	root.add_child(_make_label(summary_line, 20, false))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	_scroll.add_child(list)

	var rows: Array = _data.get("rows", []) as Array
	if rows.is_empty():
		list.add_child(_make_label("No built housing can be mothballed yet.", 21, false))
		return
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant as Dictionary
		list.add_child(_make_row(row))

func _make_row(row_data: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 142)
	panel.add_theme_stylebox_override("panel", _make_style(Color(0.035, 0.06, 0.055, 0.92), Color(0.34, 0.71, 0.63, 0.42), 10))
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	margin.add_child(stack)

	var housing_id: String = String(row_data.get("id", ""))
	var built: int = int(row_data.get("count", 0))
	var active: int = clampi(int(row_data.get("active_count", built)), 0, built)
	var title: String = String(row_data.get("name", "Housing"))
	title += " — active " + str(active) + " / built " + str(built)
	stack.add_child(_make_label(title, 22, true))
	stack.add_child(_make_label("Provides if active: " + _dictionary_text(row_data.get("housing_capacity", {}) as Dictionary) + " | Upkeep paid on all built: " + _dictionary_text(row_data.get("housing_maintenance", {}) as Dictionary), 18, false))

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	stack.add_child(row)
	var slider: HSlider = HSlider.new()
	slider.min_value = 0
	slider.max_value = built
	slider.step = 1
	slider.value = active
	slider.rounded = true
	slider.scrollable = false
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label: Label = _make_label(str(active) + " active", 19, false)
	value_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = str(int(round(value))) + " active"
	)
	slider.drag_ended.connect(func(value_changed: bool) -> void:
		if value_changed:
			emit_signal("active_housing_changed", housing_id, int(round(slider.value)))
	)
	slider.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse_event: InputEventMouseButton = event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				slider.accept_event()
	)
	return panel

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

func _make_label(text_value: String, font_size: int, bold: bool) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	if bold:
		label.add_theme_color_override("font_color", Color(0.94, 0.88, 0.68, 1.0))
	return label

func _apply_panel_style() -> void:
	add_theme_stylebox_override("panel", _make_style(Color(0.0, 0.0, 0.0, 0.64), Color(0.50, 0.82, 0.74, 0.36), 14))

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
