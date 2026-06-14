# MarketView.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/MarketView.gd
extends PanelContainer

signal good_selected(good_id: String)
signal good_closed()

const BB_POSITIVE: String = "#7AF09D"
const BB_NEGATIVE: String = "#FF6152"
const BB_WARNING: String = "#FFC25A"
const BB_TIGHT: String = "#FFA340"
const BB_TEAL: String = "#8FE6D1"
const BB_MUTED: String = "#BBB19A"

@onready var heading_label: Label = get_node_or_null(^"Margin/Root/Header/HeadingLabel") as Label
@onready var close_button: Button = get_node_or_null(^"Margin/Root/Header/CloseButton") as Button
@onready var detail_panel: PanelContainer = get_node_or_null(^"Margin/Root/DetailPanel") as PanelContainer
@onready var detail_title: Label = get_node_or_null(^"Margin/Root/DetailPanel/Margin/DetailRoot/DetailTitle") as Label
@onready var detail_stats: RichTextLabel = get_node_or_null(^"Margin/Root/DetailPanel/Margin/DetailRoot/DetailScroll/DetailStack/DetailStats") as RichTextLabel
@onready var trade_list: VBoxContainer = get_node_or_null(^"Margin/Root/DetailPanel/Margin/DetailRoot/DetailScroll/DetailStack/TradeList") as VBoxContainer
@onready var rival_list: VBoxContainer = get_node_or_null(^"Margin/Root/DetailPanel/Margin/DetailRoot/DetailScroll/DetailStack/RivalList") as VBoxContainer
@onready var empty_hint: RichTextLabel = get_node_or_null(^"Margin/Root/EmptyHint") as RichTextLabel

var market_goods: Array[Dictionary] = []
var focus_id: String = "overview"
var selected_good_id: String = ""

func _ready() -> void:
	_lock_layout_sizes()
	_add_styles()
	if close_button and not close_button.pressed.is_connected(close_good):
		close_button.pressed.connect(close_good)
	_refresh()

func setup(new_market_goods: Array, new_focus_id: String, new_selected_good_id: String) -> void:
	market_goods.clear()
	for item_variant: Variant in new_market_goods:
		var item: Dictionary = item_variant as Dictionary
		market_goods.append(item.duplicate(true))
	focus_id = new_focus_id
	selected_good_id = new_selected_good_id
	_ensure_selected_good_is_valid()
	_refresh()

func select_good(good_id: String) -> void:
	selected_good_id = good_id
	_ensure_selected_good_is_valid()
	_refresh()

func close_good() -> void:
	selected_good_id = ""
	_refresh()
	emit_signal("good_closed")

func _ensure_selected_good_is_valid() -> void:
	if selected_good_id == "":
		return
	for good: Dictionary in _filtered_goods():
		if String(good.get("id", "")) == selected_good_id:
			return
	selected_good_id = ""

func _refresh() -> void:
	if heading_label:
		heading_label.text = _focus_title()

	# A clicked good must always take priority over screen-level reports.
	# Previously Overview opened its general report first, so selecting a good from
	# the right ledger never showed the stock detail.
	if selected_good_id != "":
		var selected_good: Dictionary = _selected_good()
		if selected_good.is_empty():
			_show_closed_detail()
			return
		_update_good_detail(selected_good)
		return

	# These tabs are intentionally report screens and can open without a good.
	if focus_id == "reports":
		_update_reports_detail()
		return
	if focus_id == "village":
		_update_village_overview_detail()
		return
	if focus_id == "trade":
		_update_trade_placeholder_detail()
		return

	# Overview / Goods / Rivals stay closed until a good is selected.
	_show_closed_detail()

func _focus_title() -> String:
	match focus_id:
		"goods":
			return "Market Goods"
		"village":
			return "Village Economy"
		"trade":
			return "Trade Basket"
		"rivals":
			return "Rival Procurement"
		"reports":
			return "Marketplace Reports"
		_:
			return "Marketplace Overview"

func _show_closed_detail() -> void:
	visible = false
	if detail_panel:
		detail_panel.visible = false
	if empty_hint:
		empty_hint.visible = false

func _open_detail(title: String, body_text: String) -> void:
	visible = true
	if empty_hint:
		empty_hint.visible = false
	if detail_panel:
		detail_panel.visible = true
	if detail_title:
		detail_title.text = title
	if detail_stats:
		detail_stats.bbcode_enabled = true
		detail_stats.text = body_text

func _update_reports_detail() -> void:
	_open_detail("Marketplace Reports", _build_market_reports_text())
	_clear_list(trade_list)
	_add_list_heading(trade_list, "Read this screen as")
	_add_list_line(trade_list, "Stock is current shared market storage before this turn's spreadsheet-backed market movement.")
	_add_list_line(trade_list, "Need is village population consumption, village production inputs, construction pressure and starter-estate model pressure.")
	_add_list_line(trade_list, "Net shows whether village production naturally fills or drains the market this turn.")
	_add_list_line(trade_list, "Value is projected from post-village coverage so prices can move before trade is added.")
	_clear_list(rival_list)
	_add_list_heading(rival_list, "Current pressure")
	for good: Dictionary in market_goods:
		var label: String = String(good.get("label", ""))
		if label == "Crisis" or label == "Shortage":
			_add_list_line(rival_list, String(good.get("name", "Good")) + ": " + _fmt(float(good.get("village_net_change", 0.0))) + " net / turn; " + String(good.get("village_note", "No note.")))

func _update_village_overview_detail() -> void:
	_open_detail("Village Economy", _build_village_overview_text())
	_clear_list(trade_list)
	_add_list_heading(trade_list, "Village flows")
	_add_list_line(trade_list, "Natural production covers village fields, gathering and raw-output buildings from the balance workbook.")
	_add_list_line(trade_list, "Building output covers village workshops and specialist production from the balance workbook.")
	_add_list_line(trade_list, "Population consumption, building inputs, construction demand and starter-estate baseline pressure create the demand side of the market.")
	_clear_list(rival_list)
	_add_list_heading(rival_list, "Design note")
	_add_list_line(rival_list, "This is intentionally aggregated and uses the spreadsheet balance values as source of truth. It can later respond to events, player actions and rival procurement without simulating every household.")

func _update_trade_placeholder_detail() -> void:
	_open_detail("Trade Basket", _build_trade_placeholder_text())
	_clear_list(trade_list)
	_add_list_heading(trade_list, "Next system")
	_add_list_line(trade_list, "Sell only free estate goods after reserves.")
	_add_list_line(trade_list, "Spend temporary trade value immediately on market goods.")
	_add_list_line(trade_list, "Unused trade value should be lost so Wealth does not return as a stored currency.")
	_clear_list(rival_list)
	_add_list_heading(rival_list, "Why this waits")
	_add_list_line(rival_list, "The market now has village flows. Trade should be added on top of these real supply and demand numbers.")

func _build_market_reports_text() -> String:
	var crisis_goods: Array[String] = []
	var shortage_goods: Array[String] = []
	var surplus_goods: Array[String] = []
	var biggest_drains: Array[String] = []
	for good: Dictionary in market_goods:
		var name: String = String(good.get("name", "Good"))
		var label: String = String(good.get("label", "Unknown"))
		var net_change: float = float(good.get("village_net_change", 0.0))
		if label == "Crisis":
			crisis_goods.append(name)
		elif label == "Shortage":
			shortage_goods.append(name)
		elif label == "Abundant":
			surplus_goods.append(name)
		if net_change < -0.01:
			biggest_drains.append(name + " " + _fmt(net_change))
	var text: String = "[b]Regional market summary[/b]\n"
	text += "The market now reads the spreadsheet-balanced village economy before trade. This means prices can move because the background economy is short, stable or oversupplied.\n\n"
	text += "• Goods tracked: " + str(market_goods.size()) + "\n"
	if not crisis_goods.is_empty():
		text += "• Crisis goods: [color=" + BB_NEGATIVE + "][b]" + ", ".join(crisis_goods) + "[/b][/color]\n"
	if not shortage_goods.is_empty():
		text += "• Shortage goods: [color=" + BB_TIGHT + "][b]" + ", ".join(shortage_goods) + "[/b][/color]\n"
	if not surplus_goods.is_empty():
		text += "• Abundant goods: [color=" + BB_POSITIVE + "][b]" + ", ".join(surplus_goods) + "[/b][/color]\n"
	if not biggest_drains.is_empty():
		text += "• Natural market drains: " + _join_limited(biggest_drains, 5) + "\n"
	if crisis_goods.is_empty() and shortage_goods.is_empty() and surplus_goods.is_empty():
		text += "• No severe market pressure currently visible.\n"
	return text.strip_edges()

func _build_village_overview_text() -> String:
	var text: String = "[b]Village economic flow[/b]\n"
	text += "This tab shows the background village as an aggregated economic actor using the balance workbook as source of truth. These values should later be modified by events, player actions and rival procurement.\n\n"
	for good: Dictionary in market_goods:
		var net_change: float = float(good.get("village_net_change", 0.0))
		if absf(net_change) <= 0.001:
			continue
		text += "• " + String(good.get("name", "Good")) + ": production " + _fmt(float(good.get("village_total_production", 0.0)))
		text += "; need " + _fmt(float(good.get("village_total_demand", 0.0)))
		text += "; net " + _colour_amount(net_change) + "\n"
	return text.strip_edges()

func _build_trade_placeholder_text() -> String:
	return "[b]Trade Basket Placeholder[/b]\nThe next patch should make this tab interactive. The basket should sell estate free goods into temporary trade value, then spend that value on bought goods from the market. No permanent Wealth resource should be added."

func _update_good_detail(good: Dictionary) -> void:
	_open_detail(String(good.get("name", "Good")), _build_good_stats(good))
	_clear_list(trade_list)
	_add_list_heading(trade_list, "Supply breakdown")
	_add_list_line(trade_list, "Natural village production: " + _fmt(float(good.get("village_natural_production", 0.0))))
	_add_list_line(trade_list, "Village building output: " + _fmt(float(good.get("village_building_output", 0.0))))
	var estate_output: float = float(good.get("market_estate_output_supply", 0.0))
	if absf(estate_output) > 0.001:
		_add_list_line(trade_list, "Starter-estate model output: " + _fmt(estate_output))
	var event_delta: float = float(good.get("village_event_delta", 0.0))
	if absf(event_delta) > 0.001:
		_add_list_line(trade_list, "Event modifier: " + _fmt(event_delta))
	_add_list_heading(trade_list, "Demand breakdown")
	_add_list_line(trade_list, "Population consumption: " + _fmt(float(good.get("village_population_consumption", 0.0))))
	_add_list_line(trade_list, "Village building input demand: " + _fmt(float(good.get("village_building_input_demand", 0.0))))
	var construction_need: float = float(good.get("market_construction_demand", 0.0))
	if absf(construction_need) > 0.001:
		_add_list_line(trade_list, "Year-one construction pressure: " + _fmt(construction_need))
	var estate_need: float = float(good.get("market_estate_input_demand", 0.0))
	if absf(estate_need) > 0.001:
		_add_list_line(trade_list, "Starter-estate model input: " + _fmt(estate_need))
	_clear_list(rival_list)
	_add_list_heading(rival_list, "Notes")
	_add_list_line(rival_list, String(good.get("village_note", "No village note recorded yet.")))
	_add_list_line(rival_list, "Rivals later: " + String(good.get("rival_note", "No rival signal recorded yet.")))

func _build_good_stats(good: Dictionary) -> String:
	var start_stock: float = float(good.get("starting_market_stock", good.get("market_stock", 0.0)))
	var projected_stock: float = float(good.get("projected_market_stock", good.get("market_stock", 0.0)))
	var total_production: float = float(good.get("village_total_production", 0.0))
	var total_demand: float = float(good.get("village_total_demand", good.get("demand", 0.0)))
	var net_change: float = float(good.get("village_net_change", 0.0))
	var coverage: float = float(good.get("coverage", 0.0))
	var base_value: float = float(good.get("base_value", 0.0))
	var current_value: float = float(good.get("current_value", 0.0))
	var label: String = String(good.get("label", "Unknown"))
	var trend: String = String(good.get("trend", "Stable"))
	var text: String = ""
	text += "[b]Market stock movement[/b]\n"
	text += "• Starting market stock: [b]" + _fmt(start_stock) + "[/b]\n"
	text += "• Village production: [color=" + BB_POSITIVE + "][b]+" + _fmt(total_production) + "[/b][/color]\n"
	text += "• Village need: [color=" + BB_TIGHT + "][b]-" + _fmt(total_demand) + "[/b][/color]\n"
	text += "• Net change: " + _colour_amount(net_change) + "\n"
	text += "• Projected market stock: [b]" + _fmt(projected_stock) + "[/b]\n\n"
	text += "[b]Price pressure[/b]\n"
	text += "• Coverage after village flow: [b]" + _fmt(coverage) + " turns[/b]\n"
	text += "• Base value: [b]" + _fmt(base_value) + "[/b]\n"
	text += "• Projected barter value: [color=" + _value_colour_hex(base_value, current_value) + "][b]" + _fmt(current_value) + "[/b][/color]\n"
	text += "• Market state: [color=" + _state_colour_hex(label) + "][b]" + label + "[/b][/color]\n"
	text += "• Trend: [color=" + _trend_colour_hex(trend, label) + "][b]" + trend + "[/b][/color]"
	return text

func _selected_good() -> Dictionary:
	for good: Dictionary in market_goods:
		if String(good.get("id", "")) == selected_good_id:
			return good
	return {}

func _filtered_goods() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for good: Dictionary in market_goods:
		var category: String = String(good.get("category", ""))
		var include_good: bool = false
		match focus_id:
			"overview", "goods", "village", "trade", "rivals":
				include_good = true
			_:
				include_good = category == focus_id
		if include_good:
			output.append(good)
	return output

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
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.56, 0.90, 0.82, 1.0))
	list.add_child(label)

func _add_list_line(list: VBoxContainer, text: String) -> void:
	if list == null:
		return
	var label: Label = Label.new()
	label.text = "• " + text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76, 1.0))
	list.add_child(label)

func _state_colour_hex(state: String) -> String:
	match state:
		"Crisis":
			return BB_NEGATIVE
		"Shortage":
			return BB_TIGHT
		"Tight":
			return BB_WARNING
		"Abundant":
			return BB_POSITIVE
		"Comfortable":
			return BB_TEAL
		_:
			return BB_MUTED

func _trend_colour_hex(trend: String, state: String) -> String:
	match trend:
		"Falling fast", "Falling", "Critical":
			return BB_NEGATIVE
		"Rising", "Rising fast":
			return BB_POSITIVE
		"Stable":
			return BB_TEAL
		_:
			return _state_colour_hex(state)

func _value_colour_hex(base_value: float, current_value: float) -> String:
	if base_value <= 0.0:
		return BB_TEAL
	if current_value >= base_value * 1.5:
		return BB_POSITIVE
	if current_value <= base_value * 0.8:
		return BB_MUTED
	return BB_TEAL

func _colour_amount(value: float) -> String:
	if value > 0.001:
		return "[color=" + BB_POSITIVE + "][b]+" + _fmt(value) + "[/b][/color]"
	if value < -0.001:
		return "[color=" + BB_NEGATIVE + "][b]" + _fmt(value) + "[/b][/color]"
	return "[color=" + BB_TEAL + "][b]0[/b][/color]"

func _join_limited(values: Array[String], max_items: int) -> String:
	var parts: Array[String] = []
	for value: String in values:
		if parts.size() >= max_items:
			break
		parts.append(value)
	var text: String = ", ".join(parts)
	if values.size() > max_items:
		text += ", +" + str(values.size() - max_items) + " more"
	return text

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _lock_layout_sizes() -> void:
	if detail_stats:
		detail_stats.custom_minimum_size = Vector2(0, 300)
		detail_stats.fit_content = false
		detail_stats.scroll_active = true
	if empty_hint:
		empty_hint.fit_content = true
		empty_hint.scroll_active = false

func _add_styles() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.border_color = Color(0.50, 0.82, 0.74, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
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
		heading_label.add_theme_font_size_override("font_size", 34)
		heading_label.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76, 1.0))
	if detail_title:
		detail_title.add_theme_font_size_override("font_size", 31)
		detail_title.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76, 1.0))
	if close_button:
		close_button.custom_minimum_size = Vector2(52, 46)
		close_button.add_theme_font_size_override("font_size", 22)
	if detail_stats:
		detail_stats.add_theme_font_size_override("normal_font_size", 24)
		detail_stats.add_theme_font_size_override("bold_font_size", 26)
		detail_stats.add_theme_constant_override("line_separation", 8)
