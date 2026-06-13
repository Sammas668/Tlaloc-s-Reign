# StorehouseView.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/StorehouseView.gd
extends PanelContainer

signal good_selected(good_id: String)
signal good_closed()

const BB_POSITIVE: String = "#7AF09D"
const BB_NEGATIVE: String = "#FF6152"
const BB_WARNING: String = "#FFC25A"
const BB_TEAL: String = "#8FE6D1"
const BB_MUTED: String = "#BBB19A"

@onready var heading_label: Label = get_node_or_null(^"Margin/Root/Header/HeadingLabel") as Label
@onready var detail_panel: PanelContainer = get_node_or_null(^"Margin/Root/DetailPanel") as PanelContainer
@onready var detail_title: Label = get_node_or_null(^"Margin/Root/DetailPanel/Margin/DetailRoot/DetailTitle") as Label
@onready var close_button: Button = get_node_or_null(^"Margin/Root/Header/CloseButton") as Button
@onready var detail_stats: RichTextLabel = get_node_or_null(^"Margin/Root/DetailPanel/Margin/DetailRoot/DetailScroll/DetailStack/DetailStats") as RichTextLabel
@onready var uses_list: VBoxContainer = get_node_or_null(^"Margin/Root/DetailPanel/Margin/DetailRoot/DetailScroll/DetailStack/UsesList") as VBoxContainer
@onready var reserve_list: VBoxContainer = get_node_or_null(^"Margin/Root/DetailPanel/Margin/DetailRoot/DetailScroll/DetailStack/ReserveList") as VBoxContainer
@onready var empty_hint: RichTextLabel = get_node_or_null(^"Margin/Root/EmptyHint") as RichTextLabel

var stockpiles: Array[Dictionary] = []
var focus_id: String = "overview"
var selected_good_id: String = ""
var overview_closed_by_user: bool = false

func _ready() -> void:
	_lock_layout_sizes()
	_add_styles()
	if close_button and not close_button.pressed.is_connected(close_good):
		close_button.pressed.connect(close_good)
	_refresh()

func setup(new_stockpiles: Array, new_focus_id: String, new_selected_good_id: String) -> void:
	stockpiles.clear()
	for item_variant: Variant in new_stockpiles:
		var item: Dictionary = item_variant as Dictionary
		stockpiles.append(item)
	focus_id = new_focus_id
	selected_good_id = new_selected_good_id
	if selected_good_id != "":
		overview_closed_by_user = false
	_ensure_selected_good_is_valid()
	_refresh()

func select_good(good_id: String) -> void:
	overview_closed_by_user = false
	selected_good_id = good_id
	_ensure_selected_good_is_valid()
	_refresh()

func close_good() -> void:
	selected_good_id = ""
	overview_closed_by_user = true
	_refresh()
	emit_signal("good_closed")

func _ensure_selected_good_is_valid() -> void:
	if selected_good_id == "":
		return
	var filtered: Array[Dictionary] = _filtered_goods()
	for good_variant: Variant in filtered:
		var good: Dictionary = good_variant as Dictionary
		if String(good.get("id", "")) == selected_good_id:
			return
	selected_good_id = ""

func _refresh() -> void:
	if heading_label:
		heading_label.text = _focus_title()

	if selected_good_id == "":
		_show_overview()
		return

	var selected_good: Dictionary = _selected_good()
	if selected_good.is_empty():
		_show_overview()
		return
	_update_good_detail(selected_good)

func _focus_title() -> String:
	match focus_id:
		"food":
			return "Food Stores"
		"raw":
			return "Raw Goods"
		"processed":
			return "Processed Goods"
		"luxury":
			return "Luxury Goods"
		"special":
			return "Special Stores"
		_:
			return "Storehouse Overview"

func _show_overview() -> void:
	if overview_closed_by_user:
		visible = false
		if detail_panel:
			detail_panel.visible = false
		if empty_hint:
			empty_hint.visible = false
		return

	visible = true
	if detail_panel:
		detail_panel.visible = false
	if empty_hint:
		empty_hint.visible = true
		empty_hint.bbcode_enabled = true
		empty_hint.text = _build_overview_text()

func _update_good_detail(good: Dictionary) -> void:
	visible = true
	if empty_hint:
		empty_hint.visible = false
	if detail_panel:
		detail_panel.visible = true
	if detail_title:
		detail_title.text = String(good.get("name", "Good"))
	if detail_stats:
		detail_stats.bbcode_enabled = true
		detail_stats.text = _build_good_stats(good)

	_clear_list(uses_list)
	_add_list_heading(uses_list, "Main uses")
	var uses: Array = good.get("uses", []) as Array
	if uses.is_empty():
		_add_list_line(uses_list, "No uses recorded yet.")
	else:
		for use_variant: Variant in uses:
			_add_list_line(uses_list, String(use_variant))

	_clear_list(reserve_list)
	_add_list_heading(reserve_list, "Reserved for")
	var reserved_breakdown: Array = good.get("reserved_breakdown", []) as Array
	if reserved_breakdown.is_empty():
		_add_list_line(reserve_list, "No reserve breakdown recorded yet.")
	else:
		for reserve_variant: Variant in reserved_breakdown:
			_add_list_line(reserve_list, String(reserve_variant))

func _build_overview_text() -> String:
	var visible_goods: Array[Dictionary] = _filtered_goods()
	var crisis_count: int = 0
	var short_next_count: int = 0
	var falling_count: int = 0
	var fully_reserved_count: int = 0
	var building_count: int = 0
	var worst_name: String = "None"
	var worst_status: String = "Stable"

	for good_variant: Variant in visible_goods:
		var good: Dictionary = good_variant as Dictionary
		var status: String = _status_for(good)
		match status:
			"EMPTY", "RESERVE SHORT", "RUNS OUT":
				crisis_count += 1
				if worst_status == "Stable":
					worst_status = status
					worst_name = String(good.get("name", "Good"))
			"SHORT NEXT":
				short_next_count += 1
				if worst_status == "Stable":
					worst_status = status
					worst_name = String(good.get("name", "Good"))
			"FALLING":
				falling_count += 1
			"FULLY RESERVED":
				fully_reserved_count += 1
			"BUILDING":
				building_count += 1

	var text: String = "[b]" + _focus_title() + "[/b]\n"
	text += "Select a good from the stockpile ledger on the right.\n\n"
	text += "Visible goods: [b]" + str(visible_goods.size()) + "[/b]\n"
	text += "Immediate shortage risk: [color=" + BB_NEGATIVE + "][b]" + str(crisis_count) + "[/b][/color]\n"
	text += "Short next Veintena: [color=" + BB_NEGATIVE + "][b]" + str(short_next_count) + "[/b][/color]\n"
	text += "Falling stock: [color=" + BB_WARNING + "][b]" + str(falling_count) + "[/b][/color]\n"
	text += "Fully reserved: [color=" + BB_WARNING + "][b]" + str(fully_reserved_count) + "[/b][/color]\n"
	text += "Building stock: [color=" + BB_POSITIVE + "][b]" + str(building_count) + "[/b][/color]\n"
	if worst_name != "None":
		text += "\nMost urgent: [color=" + BB_NEGATIVE + "][b]" + worst_name + " — " + worst_status + "[/b][/color]\n"
	text += "\nThe right ledger now shows projected stock and risk status. SHORT NEXT only appears when projected stock will not cover the next Veintena's required outgoing demand."
	return text

func _build_good_stats(good: Dictionary) -> String:
	var stored: float = float(good.get("stored", 0.0))
	var incoming: float = float(good.get("incoming", 0.0))
	var outgoing: float = float(good.get("outgoing", 0.0))
	var reserved: float = float(good.get("reserved", 0.0))
	var projected: float = float(good.get("projected", maxf(0.0, stored + incoming - outgoing)))
	var net: float = incoming - outgoing
	var free: float = _free_amount(good)
	var projected_free: float = maxf(0.0, projected - reserved)
	var status: String = _status_for(good)

	var text: String = ""
	text += "Status: [color=" + _status_colour_hex(status) + "][b]" + status + "[/b][/color]\n"
	text += "Stored now: [b]" + _fmt(stored) + "[/b]\n"
	text += "Reserved before spending: [b]" + _fmt(reserved) + "[/b]\n"
	text += "Free to spend now: [color=" + _free_colour_hex(free) + "][b]" + _fmt(free) + "[/b][/color]\n"
	text += "Incoming this Veintena: [b]+" + _fmt(incoming) + "[/b]\n"
	text += "Outgoing this Veintena: [b]-" + _fmt(outgoing) + "[/b]\n"
	text += "Net change: [color=" + _net_colour_hex(net) + "][b]" + _signed_fmt(net) + "[/b][/color]\n"
	text += "Projected after turn: [color=" + _projected_colour_hex(projected, reserved) + "][b]" + _fmt(projected) + "[/b][/color]\n"
	text += "Projected free after reserves: [b]" + _fmt(projected_free) + "[/b]"
	return text

func _status_for(good: Dictionary) -> String:
	var stored: float = float(good.get("stored", 0.0))
	var incoming: float = float(good.get("incoming", 0.0))
	var outgoing: float = float(good.get("outgoing", 0.0))
	var reserved: float = float(good.get("reserved", 0.0))
	var projected: float = float(good.get("projected", maxf(0.0, stored + incoming - outgoing)))
	var free: float = maxf(0.0, stored - reserved)
	var net: float = incoming - outgoing

	var next_turn_required_need: float = outgoing

	if stored <= 0.0 and projected <= 0.0:
		return "EMPTY"
	if stored < reserved:
		return "RESERVE SHORT"
	if projected <= 0.0 and outgoing > 0.0:
		return "RUNS OUT"
	if next_turn_required_need > 0.0 and projected < next_turn_required_need:
		return "SHORT NEXT"
	if free <= 0.0 and reserved > 0.0:
		return "FULLY RESERVED"
	if net < -0.01:
		return "FALLING"
	if net > 0.01:
		return "BUILDING"
	return "STABLE"

func _selected_good() -> Dictionary:
	for good_variant: Variant in stockpiles:
		var good: Dictionary = good_variant as Dictionary
		if String(good.get("id", "")) == selected_good_id:
			return good
	return {}

func _filtered_goods() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for good_variant: Variant in stockpiles:
		var good: Dictionary = good_variant as Dictionary
		var category: String = String(good.get("category", ""))
		var include_good: bool = false
		match focus_id:
			"overview":
				include_good = true
			"reserved":
				include_good = float(good.get("reserved", 0.0)) > 0.0
			_:
				include_good = category == focus_id
		if include_good:
			output.append(good)
	return output

func _free_amount(good: Dictionary) -> float:
	var stored: float = float(good.get("stored", 0.0))
	var reserved: float = float(good.get("reserved", 0.0))
	return maxf(0.0, stored - reserved)

func _clear_list(list: VBoxContainer) -> void:
	if list == null:
		return
	for child: Node in list.get_children():
		child.queue_free()

func _add_list_heading(list: VBoxContainer, text: String) -> void:
	if list == null:
		return
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.56, 0.90, 0.82, 1.0))
	list.add_child(label)

func _add_list_line(list: VBoxContainer, text: String) -> void:
	if list == null:
		return
	var label: Label = Label.new()
	label.text = "• " + text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76, 1.0))
	list.add_child(label)

func _status_colour_hex(status_text: String) -> String:
	match status_text:
		"EMPTY", "RESERVE SHORT", "RUNS OUT", "SHORT NEXT":
			return BB_NEGATIVE
		"FULLY RESERVED", "FALLING":
			return BB_WARNING
		"BUILDING":
			return BB_POSITIVE
		"STABLE":
			return BB_TEAL
		_:
			return BB_MUTED

func _net_colour_hex(value: float) -> String:
	if value > 0.01:
		return BB_POSITIVE
	if value < -0.01:
		return BB_NEGATIVE
	return BB_MUTED

func _projected_colour_hex(projected: float, reserved: float) -> String:
	if projected <= 0.0:
		return BB_NEGATIVE
	if projected < reserved:
		return BB_NEGATIVE
	if reserved > 0.0 and projected <= reserved * 1.25:
		return BB_WARNING
	return BB_TEAL

func _free_colour_hex(free: float) -> String:
	if free <= 0.0:
		return BB_WARNING
	return BB_TEAL

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value

func _signed_fmt(value: float) -> String:
	if value >= 0.0:
		return "+" + _fmt(value)
	return "-" + _fmt(absf(value))

func _lock_layout_sizes() -> void:
	if detail_stats:
		detail_stats.custom_minimum_size = Vector2(0, 235)
		detail_stats.fit_content = false
		detail_stats.scroll_active = true
	if empty_hint:
		empty_hint.fit_content = true
		empty_hint.scroll_active = false

func _add_styles() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.58)
	style.border_color = Color(0.50, 0.82, 0.74, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.40)
	style.shadow_size = 8
	add_theme_stylebox_override("panel", style)

	if detail_panel:
		var detail_style: StyleBoxFlat = StyleBoxFlat.new()
		detail_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		detail_style.border_color = Color(0.0, 0.0, 0.0, 0.0)
		detail_style.set_border_width_all(0)
		detail_style.set_corner_radius_all(0)
		detail_panel.add_theme_stylebox_override("panel", detail_style)

	if heading_label:
		heading_label.add_theme_font_size_override("font_size", 26)
		heading_label.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76, 1.0))
	if detail_title:
		detail_title.add_theme_font_size_override("font_size", 24)
		detail_title.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76, 1.0))
	if detail_stats:
		detail_stats.add_theme_font_size_override("normal_font_size", 17)
		detail_stats.add_theme_font_size_override("bold_font_size", 17)
	if empty_hint:
		empty_hint.add_theme_font_size_override("normal_font_size", 17)
		empty_hint.add_theme_font_size_override("bold_font_size", 18)
