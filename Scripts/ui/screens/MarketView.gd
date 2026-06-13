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
		market_goods.append(item)
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
	var filtered: Array[Dictionary] = _filtered_goods()
	for good_variant: Variant in filtered:
		var good: Dictionary = good_variant as Dictionary
		if String(good.get("id", "")) == selected_good_id:
			return
	selected_good_id = ""

func _refresh() -> void:
	if heading_label:
		heading_label.text = _focus_title()

	if focus_id == "reports":
		_update_reports_detail()
		return

	if selected_good_id == "":
		_show_closed_detail()
		return

	var selected_good: Dictionary = _selected_good()
	if selected_good.is_empty():
		_show_closed_detail()
		return
	_update_good_detail(selected_good)

func _focus_title() -> String:
	match focus_id:
		"prices":
			return "Marketplace Prices"
		"buy":
			return "Buy Goods"
		"sell":
			return "Sell Goods"
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


func _update_reports_detail() -> void:
	visible = true
	if empty_hint:
		empty_hint.visible = false
	if detail_panel:
		detail_panel.visible = true
	if detail_title:
		detail_title.text = "Marketplace Reports"
	if detail_stats:
		detail_stats.bbcode_enabled = true
		detail_stats.text = _build_market_reports_text()
	_clear_list(trade_list)
	_add_list_heading(trade_list, "Read this screen as")
	_add_list_line(trade_list, "Stock shows how much of the good is held in the shared market.")
	_add_list_line(trade_list, "Demand / turn and coverage explain whether price pressure is rising or falling.")
	_add_list_line(trade_list, "Current value is the usable barter value after scarcity is applied.")
	_clear_list(rival_list)
	_add_list_heading(rival_list, "Rival pressure")
	for good_variant: Variant in market_goods:
		var good: Dictionary = good_variant as Dictionary
		var label: String = String(good.get("label", ""))
		if label == "Crisis" or label == "Shortage":
			_add_list_line(rival_list, String(good.get("name", "Good")) + ": " + String(good.get("rival_note", "No rival signal recorded.")))

func _build_market_reports_text() -> String:
	var crisis_goods: Array[String] = []
	var shortage_goods: Array[String] = []
	var high_value_goods: Array[String] = []
	for good_variant: Variant in market_goods:
		var good: Dictionary = good_variant as Dictionary
		var name: String = String(good.get("name", "Good"))
		var label: String = String(good.get("label", "Unknown"))
		var current_value: float = float(good.get("current_value", 0.0))
		var base_value: float = float(good.get("base_value", 1.0))
		if label == "Crisis":
			crisis_goods.append(name)
		elif label == "Shortage":
			shortage_goods.append(name)
		if base_value > 0.0 and current_value >= base_value * 1.5:
			high_value_goods.append(name + " (" + _fmt(current_value) + ")")
	var text: String = "The marketplace is the shared regional exchange layer. Use it to see scarcity, barter value and rival buying pressure.
"
	if not crisis_goods.is_empty():
		text += "
Crisis goods: [color=" + BB_NEGATIVE + "][b]" + ", ".join(crisis_goods) + "[/b][/color]"
	if not shortage_goods.is_empty():
		text += "
Shortage goods: [color=" + BB_TIGHT + "][b]" + ", ".join(shortage_goods) + "[/b][/color]"
	if not high_value_goods.is_empty():
		text += "
High-value goods: [color=" + BB_POSITIVE + "][b]" + ", ".join(high_value_goods) + "[/b][/color]"
	if crisis_goods.is_empty() and shortage_goods.is_empty() and high_value_goods.is_empty():
		text += "
No severe market warnings are currently visible."
	return text

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

	_clear_list(trade_list)
	_add_list_heading(trade_list, "Trade notes")
	_add_list_line(trade_list, "Buy: " + String(good.get("buy_note", "No buy note yet.")))
	_add_list_line(trade_list, "Sell: " + String(good.get("sell_note", "No sell note yet.")))

	_clear_list(rival_list)
	_add_list_heading(rival_list, "Rival signal")
	_add_list_line(rival_list, String(good.get("rival_note", "No rival signal recorded yet.")))

func _build_good_stats(good: Dictionary) -> String:
	var market_stock: float = float(good.get("market_stock", 0.0))
	var demand: float = float(good.get("demand", 0.0))
	var coverage: float = float(good.get("coverage", 0.0))
	var base_value: float = float(good.get("base_value", 0.0))
	var current_value: float = float(good.get("current_value", 0.0))
	var label: String = String(good.get("label", "Unknown"))
	var trend: String = String(good.get("trend", "Stable"))

	var text: String = ""
	text += "Market stock: [b]" + _fmt(market_stock) + "[/b]
"
	text += "Demand / turn: [b]" + _fmt(demand) + "[/b]
"
	text += "Coverage: [b]" + _fmt(coverage) + " turns[/b]
"
	text += "Base value: [b]" + _fmt(base_value) + "[/b]
"
	text += "Current barter value: [color=" + _value_colour_hex(base_value, current_value) + "][b]" + _fmt(current_value) + "[/b][/color]
"
	text += "Market state: [color=" + _state_colour_hex(label) + "][b]" + label + "[/b][/color]
"
	text += "Trend: [color=" + _trend_colour_hex(trend, label) + "][b]" + trend + "[/b][/color]"
	return text

func _selected_good() -> Dictionary:
	for good_variant: Variant in market_goods:
		var good: Dictionary = good_variant as Dictionary
		if String(good.get("id", "")) == selected_good_id:
			return good
	return {}

func _filtered_goods() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for good_variant: Variant in market_goods:
		var good: Dictionary = good_variant as Dictionary
		var category: String = String(good.get("category", ""))
		var include_good: bool = false
		match focus_id:
			"overview", "prices", "buy", "sell", "rivals":
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
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.56, 0.90, 0.82, 1.0))
	list.add_child(label)

func _add_list_line(list: VBoxContainer, text: String) -> void:
	if list == null:
		return
	var label: Label = Label.new()
	label.text = "• " + text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
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
		"Critical":
			return BB_NEGATIVE
		"Rising":
			return BB_WARNING
		"Soft":
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

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _lock_layout_sizes() -> void:
	if detail_stats:
		detail_stats.custom_minimum_size = Vector2(0, 220)
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
		heading_label.add_theme_font_size_override("font_size", 22)
		heading_label.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76, 1.0))
	if detail_title:
		detail_title.add_theme_font_size_override("font_size", 20)
		detail_title.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76, 1.0))
	if detail_stats:
		detail_stats.add_theme_font_size_override("normal_font_size", 15)
		detail_stats.add_theme_font_size_override("bold_font_size", 15)
