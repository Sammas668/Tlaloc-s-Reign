# MarketView.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/MarketView.gd
extends PanelContainer

signal good_selected(good_id: String)
signal good_closed()

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
	if close_button:
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
			return "Market Prices"
		"buy":
			return "Buy Goods"
		"sell":
			return "Sell Goods"
		"rivals":
			return "Rival Procurement"
		"reports":
			return "Market Reports"
		_:
			return "Market Overview"

func _show_closed_detail() -> void:
	visible = false
	if detail_panel:
		detail_panel.visible = false
	if empty_hint:
		empty_hint.visible = false

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
	text += "Market stock: [b]" + _fmt(market_stock) + "[/b]\n"
	text += "Demand / turn: [b]" + _fmt(demand) + "[/b]\n"
	text += "Coverage: [b]" + _fmt(coverage) + " turns[/b]\n"
	text += "Base value: [b]" + _fmt(base_value) + "[/b]\n"
	text += "Current value: [b]" + _fmt(current_value) + "[/b]\n"
	text += "Market state: [b]" + label + "[/b]\n"
	text += "Trend: [b]" + trend + "[/b]"
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
	list.add_child(label)

func _add_list_line(list: VBoxContainer, text: String) -> void:
	if list == null:
		return
	var label: Label = Label.new()
	label.text = "• " + text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	list.add_child(label)

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _lock_layout_sizes() -> void:
	if detail_stats:
		detail_stats.custom_minimum_size = Vector2(0, 170)
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
	style.set_content_margin_all(4)
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
	if detail_title:
		detail_title.add_theme_font_size_override("font_size", 20)
	if detail_stats:
		detail_stats.add_theme_font_size_override("normal_font_size", 15)
		detail_stats.add_theme_font_size_override("bold_font_size", 15)
