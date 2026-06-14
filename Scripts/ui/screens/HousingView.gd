# HousingView.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/HousingView.gd
extends Control

signal housing_closed
signal build_requested(housing_id: String)
signal destroy_requested(housing_id: String)

var _summary: Dictionary = {}
var _rows: Array[Dictionary] = []
var _focus_id: String = "overview"
var _selected_id: String = ""
var _root: PanelContainer = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(summary: Dictionary, rows: Array, focus_id: String, selected_id: String) -> void:
	_summary = summary.duplicate(true)
	_rows.clear()
	for row_variant: Variant in rows:
		_rows.append((row_variant as Dictionary).duplicate(true))
	_focus_id = focus_id
	_selected_id = selected_id
	_rebuild()

func select_housing(housing_id: String) -> void:
	_selected_id = housing_id
	_rebuild()

func _rebuild() -> void:
	_clear_children(self)
	if _focus_id == "overview":
		visible = true
		_build_overview_panel()
		return
	if _selected_id == "":
		visible = false
		return
	visible = true
	_build_detail_panel(_selected_id)

func _build_overview_panel() -> void:
	_root = _make_panel()
	add_child(_root)
	var margin: MarginContainer = _make_margin(16, 16, 14, 14)
	_root.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)

	var title: Label = _make_label("Housing Overview", 30, true)
	stack.add_child(title)
	var status: String = String(_summary.get("status_text", "Unknown"))
	var totals: String = "Estate population " + str(int(_summary.get("total_population", 0))) + " / capacity " + str(int(_summary.get("total_capacity", 0))) + " — " + status
	stack.add_child(_make_label(totals, 21, false))

	var maintenance: Dictionary = _summary.get("maintenance", {}) as Dictionary
	stack.add_child(_make_label("Housing building upkeep this Veintena: " + _dictionary_text(maintenance), 20, false))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	var tiers: Array = _summary.get("tiers", []) as Array
	for tier_variant: Variant in tiers:
		var tier: Dictionary = tier_variant as Dictionary
		list.add_child(_make_tier_card(tier))

func _make_tier_card(tier: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_style(Color(0.035, 0.06, 0.055, 0.88), Color(0.34, 0.71, 0.63, 0.42), 10))
	var margin: MarginContainer = _make_margin(12, 12, 10, 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	stack.add_child(_make_label(String(tier.get("name", "Housing")), 23, true))
	var line: String = "Population " + str(int(tier.get("population", 0))) + " / capacity " + str(int(tier.get("capacity", 0)))
	line += " | Free " + str(int(tier.get("free_capacity", 0)))
	var over: int = int(tier.get("over_capacity", 0))
	if over > 0:
		line += " | Over by " + str(over)
	line += " | " + String(tier.get("status", "Unknown"))
	stack.add_child(_make_label(line, 19, false))

	var members: Array = tier.get("members", []) as Array
	for member_variant: Variant in members:
		var member: Dictionary = member_variant as Dictionary
		var member_line: String = String(member.get("name", "Group")) + ": " + str(int(member.get("population", 0))) + " / " + str(int(member.get("capacity", 0)))
		member_line += " capacity; " + String(member.get("status", "Unknown"))
		stack.add_child(_make_label("• " + member_line, 17, false))

	var options: Array = tier.get("building_options", []) as Array
	if not options.is_empty():
		stack.add_child(_make_label("Housing options and costs:", 18, true))
		for option_variant: Variant in options:
			var option: Dictionary = option_variant as Dictionary
			var option_line: String = "• " + String(option.get("name", "Housing"))
			option_line += " | Adds " + _dictionary_text(option.get("housing_capacity", {}) as Dictionary)
			option_line += " | Cost " + _dictionary_text(option.get("build_cost", {}) as Dictionary)
			option_line += " | Upkeep " + _dictionary_text(option.get("housing_maintenance", {}) as Dictionary)
			stack.add_child(_make_label(option_line, 16, false))
	return panel

func _build_detail_panel(housing_id: String) -> void:
	var row: Dictionary = _row_by_id(housing_id)
	if row.is_empty():
		visible = false
		return
	_root = _make_panel()
	add_child(_root)
	var margin: MarginContainer = _make_margin(16, 16, 14, 14)
	_root.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)

	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	stack.add_child(header)
	var title: Label = _make_label(String(row.get("name", "Housing")), 28, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(46, 42)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(func() -> void:
		emit_signal("housing_closed")
	)
	header.add_child(close_button)

	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = false
	body.scroll_active = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 21)
	body.add_theme_font_size_override("bold_font_size", 23)
	body.add_theme_constant_override("line_separation", 6)
	body.text = _detail_text(row)
	stack.add_child(body)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	stack.add_child(actions)
	var build_button: Button = Button.new()
	build_button.text = "+ Build one"
	build_button.disabled = not bool(row.get("can_build", false))
	build_button.custom_minimum_size = Vector2(170, 50)
	build_button.add_theme_font_size_override("font_size", 20)
	build_button.add_theme_stylebox_override("normal", _make_style(Color(0.06, 0.24, 0.14, 0.95), Color(0.2, 0.8, 0.42, 0.75), 10))
	build_button.pressed.connect(func() -> void:
		emit_signal("build_requested", housing_id)
	)
	actions.add_child(build_button)
	var destroy_button: Button = Button.new()
	destroy_button.text = "− Destroy one"
	destroy_button.disabled = not bool(row.get("can_destroy", false))
	destroy_button.custom_minimum_size = Vector2(190, 50)
	destroy_button.add_theme_font_size_override("font_size", 20)
	destroy_button.add_theme_stylebox_override("normal", _make_style(Color(0.28, 0.08, 0.06, 0.95), Color(0.9, 0.28, 0.22, 0.75), 10))
	destroy_button.pressed.connect(func() -> void:
		emit_signal("destroy_requested", housing_id)
	)
	actions.add_child(destroy_button)

func _detail_text(row: Dictionary) -> String:
	var text: String = ""
	text += String(row.get("description", "")) + "\n\n"
	text += "[b]Current state[/b]\n"
	text += "• Built: " + str(int(row.get("count", 0))) + "\n"
	text += "• Adds now: " + _dictionary_text(row.get("capacity_total", {}) as Dictionary) + "\n"
	text += "• Total building upkeep now: " + _dictionary_text(row.get("maintenance_total", {}) as Dictionary) + "\n\n"
	text += "[b]One building provides[/b]\n"
	text += "• Capacity: " + _dictionary_text(row.get("housing_capacity", {}) as Dictionary) + "\n"
	text += "• Building upkeep per Veintena: " + _dictionary_text(row.get("housing_maintenance", {}) as Dictionary) + "\n"
	text += "\n"
	text += "[b]Build one more[/b]\n"
	text += "• Build cost: " + _dictionary_text(row.get("build_cost", {}) as Dictionary) + "\n"
	text += "• Capacity after build: " + _dictionary_text(row.get("capacity_after_build", {}) as Dictionary) + "\n"
	text += "• Total upkeep after build: " + _dictionary_text(row.get("maintenance_after_build", {}) as Dictionary) + "\n"
	text += "• " + String(row.get("build_status", "")) + "\n\n"
	text += "[b]Destroy one[/b]\n"
	text += "• Capacity after destroy: " + _dictionary_text(row.get("capacity_after_destroy", {}) as Dictionary) + "\n"
	text += "• Total upkeep after destroy: " + _dictionary_text(row.get("maintenance_after_destroy", {}) as Dictionary) + "\n"
	text += "• " + String(row.get("destroy_status", "")) + "\n"
	return text.strip_edges()

func _row_by_id(housing_id: String) -> Dictionary:
	for row: Dictionary in _rows:
		if String(row.get("id", "")) == housing_id:
			return row
	return {}

func _make_panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_style(Color(0.0, 0.0, 0.0, 0.62), Color(0.50, 0.82, 0.74, 0.35), 14))
	return panel

func _make_margin(left: int, right: int, top: int, bottom: int) -> MarginContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin

func _make_label(text_value: String, font_size: int, bold: bool) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	if bold:
		label.add_theme_color_override("font_color", Color(0.94, 0.88, 0.68, 1.0))
	return label

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
