# LabourAssignmentView.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/LabourAssignmentView.gd
#
# Production > Labour working panel.
# The player chooses a productive worker type at the top, then staffs built
# chinampas/workshops of that type with drag sliders. The slider assigns
# BUILDING COPIES to be staffed, not individual people one-by-one.
extends Control

signal staffing_group_changed(building_id: String, group_id: String, staffed_count: int)
# Backwards-compatible signal names used by older GameScreen.gd patches.
signal staffing_changed(building_id: String, staffed_count: int)
signal assignment_changed(building_id: String, group_id: String, amount: int)

var data: Dictionary = {}
var active_group_id: String = "field_labour"

var _root_panel: PanelContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _worker_button_row: HBoxContainer
var _is_setting_slider_value: bool = false

func _ready() -> void:
	_ensure_ui()
	_apply_styles()

func setup(labour_data: Dictionary) -> void:
	data = labour_data
	_ensure_ui()
	_ensure_valid_active_group()
	_rebuild(false)

func refresh_from_data(labour_data: Dictionary) -> void:
	# Used after a slider changes. Rebuilds values and max staffing limits
	# without snapping the player back to the top of the Labour screen.
	data = labour_data
	_ensure_ui()
	_ensure_valid_active_group()
	_rebuild(true)

func _ensure_ui() -> void:
	if _root_panel != null:
		return

	for child: Node in get_children():
		child.queue_free()

	_root_panel = PanelContainer.new()
	_root_panel.name = "LabourAssignmentPanel"
	_root_panel.anchor_left = 0.0
	_root_panel.anchor_top = 0.0
	_root_panel.anchor_right = 1.0
	_root_panel.anchor_bottom = 1.0
	_root_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_root_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_root_panel.add_child(margin)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 14)
	_scroll.add_child(_content)

func _ensure_valid_active_group() -> void:
	var groups: Array = data.get("groups", []) as Array
	if groups.is_empty():
		return
	for group_variant: Variant in groups:
		var group: Dictionary = group_variant as Dictionary
		if String(group.get("id", "")) == active_group_id:
			return
	active_group_id = String((groups[0] as Dictionary).get("id", active_group_id))

func _rebuild(preserve_scroll: bool = false) -> void:
	var old_scroll: int = 0
	if preserve_scroll and _scroll != null:
		old_scroll = int(_scroll.scroll_vertical)

	_clear_children(_content)
	_add_title("Labour Assignment")
	_add_description("Choose a worker pool, then drag the bars to decide how many built chinampas or workshops are staffed. Field Labour combines Macehualtin and Tlacotin for the same raw-production buildings; Tolteca remain separate for artisan workshops. Warriors are handled later in Barracks, not here.")
	_add_worker_type_buttons()
	_add_active_group_summary()
	_add_building_assignment_section()

	if preserve_scroll and _scroll != null:
		call_deferred("_restore_scroll_position", old_scroll)

func _restore_scroll_position(scroll_position: int) -> void:
	if _scroll == null:
		return
	_scroll.scroll_vertical = scroll_position

func _add_title(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(0.96, 0.98, 0.92, 1.0))
	_content.add_child(label)

func _add_description(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.82, 0.91, 0.86, 1.0))
	_content.add_child(label)

func _add_section_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.76, 0.63, 0.32, 1.0))
	_content.add_child(label)

func _add_worker_type_buttons() -> void:
	_add_section_label("Worker Type")
	_worker_button_row = HBoxContainer.new()
	_worker_button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_worker_button_row.add_theme_constant_override("separation", 10)
	_content.add_child(_worker_button_row)

	var groups: Array = data.get("groups", []) as Array
	for group_variant: Variant in groups:
		var group: Dictionary = group_variant as Dictionary
		var group_id: String = String(group.get("id", ""))
		var button: Button = Button.new()
		button.text = String(group.get("name", group_id.capitalize()))
		button.toggle_mode = true
		button.button_pressed = group_id == active_group_id
		button.custom_minimum_size = Vector2(0, 58)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 20)
		var normal_border: Color = Color(0.34, 0.71, 0.63, 0.45)
		if group_id == active_group_id:
			normal_border = Color(0.76, 0.63, 0.32, 0.86)
		button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.04, 0.07, 0.065, 0.94), normal_border, 10))
		button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.06, 0.095, 0.085, 0.97), Color(0.50, 0.82, 0.74, 0.78), 10))
		button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.10, 0.12, 0.095, 0.98), Color(0.76, 0.63, 0.32, 0.86), 10))
		button.pressed.connect(func() -> void:
			active_group_id = group_id
			_rebuild(true)
		)
		_worker_button_row.add_child(button)

func _add_active_group_summary() -> void:
	var group: Dictionary = _group_data(active_group_id)
	if group.is_empty():
		_add_plain_line("No selected worker group.")
		return

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.06, 0.055, 0.92), Color(0.34, 0.71, 0.63, 0.42), 10))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)

	var title: Label = Label.new()
	title.text = String(group.get("name", "Labour"))
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 0.92, 1.0))
	stack.add_child(title)

	var description: Label = Label.new()
	description.text = String(group.get("description", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 17)
	description.add_theme_color_override("font_color", Color(0.82, 0.91, 0.86, 1.0))
	stack.add_child(description)

	var line: Label = Label.new()
	line.text = "Pool total " + str(int(group.get("total", 0))) + " | Assigned " + str(int(group.get("assigned", 0))) + " | Unassigned " + str(int(group.get("unassigned", 0)))
	line.clip_text = true
	line.add_theme_font_size_override("font_size", 19)
	line.add_theme_color_override("font_color", Color(0.82, 0.91, 0.86, 1.0))
	stack.add_child(line)

	var members: Array = group.get("members", []) as Array
	if not members.is_empty():
		var member_title: Label = Label.new()
		member_title.text = "Population in this pool"
		member_title.add_theme_font_size_override("font_size", 18)
		member_title.add_theme_color_override("font_color", Color(0.76, 0.63, 0.32, 1.0))
		stack.add_child(member_title)
		for member_variant: Variant in members:
			var member: Dictionary = member_variant as Dictionary
			var member_line: Label = Label.new()
			member_line.text = String(member.get("name", "Population")) + ": total " + str(int(member.get("total", 0))) + " | assigned " + str(int(member.get("assigned", 0))) + " | unassigned " + str(int(member.get("unassigned", 0)))
			member_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			member_line.add_theme_font_size_override("font_size", 18)
			member_line.add_theme_color_override("font_color", Color(0.88, 0.94, 0.90, 1.0))
			stack.add_child(member_line)

	var pressure: Label = Label.new()
	var shortfall: int = int(group.get("shortfall", 0))
	pressure.text = "Shortfall " + str(shortfall) if shortfall > 0 else "Enough unassigned labour for current staffed buildings"
	pressure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pressure.add_theme_font_size_override("font_size", 18)
	pressure.add_theme_color_override("font_color", Color(0.95, 0.35, 0.30, 1.0) if shortfall > 0 else Color(0.62, 0.92, 0.68, 1.0))
	stack.add_child(pressure)

func _add_building_assignment_section() -> void:
	var group_name: String = String(_group_data(active_group_id).get("name", active_group_id.capitalize()))
	_add_section_label("Staff Buildings with " + group_name)
	_add_description("Drag a bar to staff more or fewer built copies using the selected worker pool. The row shows how many workers each building copy needs before it can operate. Storehouse incoming/outgoing and the right-hand labour ledger update when the slider changes.")

	var buildings: Array = data.get("buildings", []) as Array
	var visible_count: int = 0
	for building_variant: Variant in buildings:
		var building: Dictionary = building_variant as Dictionary
		if not _building_can_use_group(building, active_group_id):
			continue
		visible_count += 1
		_add_building_panel(building)

	if visible_count == 0:
		_add_plain_line("No built productive buildings can currently use " + group_name + ". Build a matching chinampa or workshop first, or choose another worker type.")

func _add_building_panel(building: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	var status: String = String(building.get("status_text", ""))
	var border: Color = Color(0.34, 0.71, 0.63, 0.46)
	if status.to_lower().find("blocked") >= 0 or status.to_lower().find("short") >= 0 or status.to_lower().find("unstaffed") >= 0:
		border = Color(0.90, 0.55, 0.22, 0.75)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.0, 0.0, 0.0, 0.54), border, 12))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 10)
	stack.add_child(header)

	var title: Label = Label.new()
	title.text = String(building.get("name", "Building"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 0.92, 1.0))
	header.add_child(title)

	var count: int = int(building.get("count", 0))
	var active_assigned: int = _assigned_count_for_group(building, active_group_id)
	var max_for_active: int = int((building.get("max_staffable_by_group", {}) as Dictionary).get(active_group_id, count))
	var total_staffed: int = int(building.get("staffed_count", 0))
	var operating: int = int(building.get("operating", 0))
	var people_per_copy: int = _staff_per_copy_for_group(building, active_group_id)

	var count_label: Label = Label.new()
	count_label.text = _count_text(count, total_staffed, operating, active_assigned, people_per_copy)
	count_label.add_theme_font_size_override("font_size", 19)
	count_label.add_theme_color_override("font_color", Color(0.82, 0.91, 0.86, 1.0))
	header.add_child(count_label)

	var pop_label: Label = Label.new()
	pop_label.text = _building_staff_requirement_text(building)
	pop_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pop_label.add_theme_font_size_override("font_size", 18)
	pop_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.78, 1.0))
	stack.add_child(pop_label)

	var status_label: Label = Label.new()
	status_label.text = status
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color", Color(0.94, 0.88, 0.68, 1.0))
	stack.add_child(status_label)

	var effect_label: Label = Label.new()
	effect_label.text = _effect_text_for_building(building)
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 18)
	effect_label.add_theme_color_override("font_color", Color(0.72, 0.94, 0.77, 1.0))
	stack.add_child(effect_label)

	var value_label: Label = Label.new()
	value_label.text = _staffing_value_text(active_assigned, count, max_for_active, people_per_copy)
	value_label.add_theme_font_size_override("font_size", 19)
	value_label.add_theme_color_override("font_color", Color(0.96, 0.98, 0.92, 1.0))
	stack.add_child(value_label)

	var slider: HSlider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Taller slider row makes the handle easier to grab and drag inside the scroll view.
	slider.custom_minimum_size = Vector2(0, 72)
	slider.min_value = 0.0
	slider.max_value = float(count)
	slider.step = 1.0
	slider.value = float(active_assigned)
	slider.editable = count > 0 and people_per_copy > 0
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	slider.tooltip_text = "Click and drag left or right to choose how many built copies are staffed by " + String(_group_data(active_group_id).get("name", active_group_id.capitalize())) + ". Release the mouse to apply the staffing change."
	slider.set_meta("last_committed_value", active_assigned)
	stack.add_child(slider)

	var building_id: String = String(building.get("id", ""))
	slider.value_changed.connect(func(value: float) -> void:
		if _is_setting_slider_value:
			return
		var rounded: int = _rounded_slider_value(value, count, max_for_active)
		if rounded != int(roundf(slider.value)):
			_is_setting_slider_value = true
			slider.value = float(rounded)
			_is_setting_slider_value = false

		# Instant local preview only. Do not emit here, because emitting on every
		# movement causes GameScreen to rebuild the Labour page while the player is
		# dragging, which makes the bar feel like it cannot be dragged.
		_update_building_slider_preview(building, active_group_id, rounded, count, max_for_active, people_per_copy, count_label, pop_label, effect_label, value_label)
	)

	# Commit on release / drag end. This lets the player drag smoothly, then
	# updates the right panel and Storehouse once the chosen value is released.
	slider.drag_ended.connect(func(value_changed: bool) -> void:
		if value_changed:
			_commit_staffing_slider_value(slider, building_id, count, max_for_active)
	)
	slider.gui_input.connect(func(event: InputEvent) -> void:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_commit_staffing_slider_value(slider, building_id, count, max_for_active)
	)

func _count_text(count: int, total_staffed: int, operating: int, active_assigned: int, people_per_copy: int) -> String:
	var needed_text: String = "needs " + str(people_per_copy) + " workers each" if people_per_copy > 0 else "cannot staff"
	return "Built " + str(count) + " | Staffed " + str(total_staffed) + "/" + str(count) + " | Operating " + str(operating) + " | Selected pool " + str(active_assigned) + " — " + needed_text

func _rounded_slider_value(value: float, count: int, max_for_active: int) -> int:
	var rounded: int = clampi(int(roundf(value)), 0, count)
	if rounded > max_for_active:
		rounded = max_for_active
	return rounded

func _update_building_slider_preview(building: Dictionary, group_id: String, rounded: int, count: int, max_for_active: int, people_per_copy: int, count_label: Label, pop_label: Label, effect_label: Label, value_label: Label) -> void:
	var preview_assignments: Dictionary = (building.get("staff_assignments", {}) as Dictionary).duplicate(true)
	for member_id: String in _group_member_ids(group_id):
		preview_assignments.erase(member_id)
	preview_assignments[group_id] = rounded
	building["staff_assignments"] = preview_assignments
	var total_staffed: int = _sum_int_dictionary(preview_assignments)
	count_label.text = _count_text(count, total_staffed, mini(total_staffed, count), rounded, people_per_copy)
	pop_label.text = _building_staff_requirement_text(building)
	effect_label.text = _effect_text_for_building(building)
	value_label.text = _staffing_value_text(rounded, count, max_for_active, people_per_copy)

func _commit_staffing_slider_value(slider: HSlider, building_id: String, count: int, max_for_active: int) -> void:
	if slider == null:
		return
	var rounded: int = _rounded_slider_value(float(slider.value), count, max_for_active)
	var last_committed: int = int(slider.get_meta("last_committed_value", -999999))
	if rounded == last_committed:
		return
	slider.set_meta("last_committed_value", rounded)
	if rounded != int(roundf(slider.value)):
		_is_setting_slider_value = true
		slider.value = float(rounded)
		_is_setting_slider_value = false
	emit_signal("staffing_group_changed", building_id, active_group_id, rounded)
	emit_signal("assignment_changed", building_id, active_group_id, rounded)

func _staffing_value_text(active_assigned: int, count: int, max_staffable: int, people_per_copy: int) -> String:
	var group_name: String = String(_group_data(active_group_id).get("name", active_group_id.capitalize()))
	var need_text: String = "Needs " + str(people_per_copy) + " " + group_name + " workers per staffed building" if people_per_copy > 0 else "This worker pool cannot staff this building"
	return "Selected pool: " + str(active_assigned) + " / " + str(count) + " building copies | " + need_text + " | Max now: " + str(max_staffable)

func _effect_text_for_building(building: Dictionary) -> String:
	var total_staffed: int = _sum_int_dictionary(building.get("staff_assignments", {}) as Dictionary)
	var inputs: Dictionary = building.get("inputs_per_instance", {}) as Dictionary
	var outputs: Dictionary = building.get("outputs_per_instance", {}) as Dictionary
	return "At " + str(total_staffed) + " total staffed — Inputs: " + _dictionary_inline(_dictionary_times(inputs, total_staffed)) + " | Outputs: " + _dictionary_inline(_dictionary_times(outputs, total_staffed))

func _building_staff_requirement_text(building: Dictionary) -> String:
	var people_per_copy: int = _staff_per_copy_for_group(building, active_group_id)
	var group_name: String = String(_group_data(active_group_id).get("name", active_group_id.capitalize()))
	var requirement_text: String = "Staff needed per building: " + (str(people_per_copy) + " " + group_name + " workers" if people_per_copy > 0 else "cannot use this pool")
	if active_group_id == "field_labour":
		requirement_text += " (Macehualtin and Tlacotin combine into this pool)"

	var assignments: Dictionary = building.get("staff_assignments", {}) as Dictionary
	var assignment_parts: Array[String] = []
	for group_variant: Variant in assignments.keys():
		var group_id: String = String(group_variant)
		var staffed_count: int = int(assignments[group_variant])
		if staffed_count <= 0:
			continue
		assignment_parts.append(_short_group_name(group_id) + " staffs " + str(staffed_count) + " building" + ("s" if staffed_count != 1 else ""))

	if assignment_parts.is_empty():
		return "No copies staffed. " + requirement_text
	return requirement_text + " | Current staffing: " + "; ".join(assignment_parts)


func _building_can_use_group(building: Dictionary, group_id: String) -> bool:
	var allowed: Array = building.get("allowed_worker_groups", []) as Array
	for member_id: String in _group_member_ids(group_id):
		for value: Variant in allowed:
			if String(value) == member_id:
				return true
	return false

func _assigned_count_for_group(building: Dictionary, group_id: String) -> int:
	var assignments: Dictionary = building.get("staff_assignments", {}) as Dictionary
	var total: int = 0
	for member_id: String in _group_member_ids(group_id):
		total += int(assignments.get(member_id, 0))
	return total

func _staff_per_copy_for_group(building: Dictionary, group_id: String) -> int:
	var staff_by_group: Dictionary = building.get("staff_per_instance_by_group", {}) as Dictionary
	for member_id: String in _group_member_ids(group_id):
		var amount: int = int(staff_by_group.get(member_id, 0))
		if amount > 0:
			return amount
	return 0

func _group_member_ids(group_id: String) -> Array[String]:
	var group: Dictionary = _group_data(group_id)
	var members: Array = group.get("members", []) as Array
	var output: Array[String] = []
	if members.is_empty():
		output.append(group_id)
		return output
	for member_variant: Variant in members:
		var member: Dictionary = member_variant as Dictionary
		var member_id: String = String(member.get("id", ""))
		if member_id != "":
			output.append(member_id)
	return output


func _group_data(group_id: String) -> Dictionary:
	var groups: Array = data.get("groups", []) as Array
	for group_variant: Variant in groups:
		var group: Dictionary = group_variant as Dictionary
		if String(group.get("id", "")) == group_id:
			return group
	return {}

func _short_group_name(group_id: String) -> String:
	var group: Dictionary = _group_data(group_id)
	if group.is_empty():
		return group_id.replace("_", " ").capitalize()
	var name: String = String(group.get("name", group_id.capitalize()))
	return name.replace(" Labourers", "").replace(" Artisans", "")

func _sum_int_dictionary(values: Dictionary) -> int:
	var total: int = 0
	for key: Variant in values.keys():
		total += int(values[key])
	return total

func _dictionary_times(values: Dictionary, multiplier: int) -> Dictionary:
	var result: Dictionary = {}
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		result[key] = float(values[key_variant]) * float(multiplier)
	return result

func _add_plain_line(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.82, 0.91, 0.86, 1.0))
	_content.add_child(label)

func _dictionary_inline(values: Dictionary) -> String:
	if values.is_empty():
		return "none"
	var parts: Array[String] = []
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant).replace("_", " ").capitalize()
		var amount: float = float(values[key_variant])
		if absf(amount) <= 0.001:
			continue
		parts.append(key + " " + _format_amount(amount))
	if parts.is_empty():
		return "none"
	return "; ".join(parts)

func _format_amount(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))

func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		child.queue_free()

func _apply_styles() -> void:
	if _root_panel:
		_root_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.0, 0.0, 0.0, 0.62), Color(0.50, 0.82, 0.74, 0.35), 14))

func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 6
	return style
