# TradeBasketView.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/TradeBasketView.gd
#
# Barter-only trade basket. There is no stored Wealth, coin or market credit.
# Negative slider values sell estate free stock into the market.
# Positive slider values buy market stock into the estate.
# Balance buttons can set a row to the amount needed to balance the rest of the basket.
extends PanelContainer

signal trade_changed()
signal trade_accepted()

const COLOR_TEXT: Color = Color(0.90, 0.86, 0.76, 1.0)
const COLOR_MUTED: Color = Color(0.67, 0.63, 0.54, 1.0)
const COLOR_POSITIVE: Color = Color(0.48, 0.92, 0.62, 1.0)
const COLOR_NEGATIVE: Color = Color(1.00, 0.38, 0.32, 1.0)
const COLOR_WARNING: Color = Color(1.00, 0.76, 0.35, 1.0)
const COLOR_TEAL: Color = Color(0.56, 0.90, 0.82, 1.0)

var state: Node = null
var trade_plan: Dictionary = {}
var row_info_by_id: Dictionary = {}
var market_good_by_id: Dictionary = {}
var store_good_by_id: Dictionary = {}

var summary_label: RichTextLabel = null
var accept_button: Button = null
var clear_button: Button = null
var list_root: VBoxContainer = null
var error_label: Label = null

func _ready() -> void:
	_add_styles()
	if state == null:
		state = _find_state()
	_build_ui()
	_refresh_rows()
	_refresh_summary()

func setup(new_state: Node) -> void:
	state = new_state
	if is_node_ready():
		_refresh_rows()
		_refresh_summary()

func _find_state() -> Node:
	var autoload_state: Node = get_node_or_null("/root/TRGameState")
	if autoload_state != null:
		return autoload_state
	return get_node_or_null("/root/GameState")

func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var heading: Label = Label.new()
	heading.text = "Trade Basket"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(heading)

	summary_label = RichTextLabel.new()
	summary_label.bbcode_enabled = true
	summary_label.fit_content = true
	summary_label.scroll_active = false
	summary_label.custom_minimum_size = Vector2(0, 92)
	summary_label.add_theme_font_size_override("normal_font_size", 22)
	summary_label.add_theme_font_size_override("bold_font_size", 24)
	summary_label.add_theme_constant_override("line_separation", 5)
	root.add_child(summary_label)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	root.add_child(button_row)

	accept_button = Button.new()
	accept_button.text = "Accept Trade"
	accept_button.custom_minimum_size = Vector2(210, 50)
	accept_button.add_theme_font_size_override("font_size", 22)
	accept_button.pressed.connect(_on_accept_pressed)
	button_row.add_child(accept_button)

	clear_button = Button.new()
	clear_button.text = "Clear Basket"
	clear_button.custom_minimum_size = Vector2(190, 50)
	clear_button.add_theme_font_size_override("font_size", 22)
	clear_button.pressed.connect(_on_clear_pressed)
	button_row.add_child(clear_button)

	error_label = Label.new()
	error_label.text = ""
	error_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_size_override("font_size", 20)
	error_label.add_theme_color_override("font_color", COLOR_WARNING)
	button_row.add_child(error_label)

	var helper: Label = Label.new()
	helper.text = "Drag left to sell estate free stock. Drag right to buy market stock. Prices use projected market value and marginal barter pricing: each unit bought raises the next unit price, and each unit sold lowers the next unit value. Use a row's Balance button to set that good to the amount needed to balance the rest of the basket."
	helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	helper.add_theme_font_size_override("font_size", 19)
	helper.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(helper)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	list_root = VBoxContainer.new()
	list_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_root.add_theme_constant_override("separation", 8)
	scroll.add_child(list_root)

func _refresh_rows() -> void:
	if list_root == null:
		return
	for child: Node in list_root.get_children():
		child.queue_free()
	row_info_by_id.clear()
	market_good_by_id = _market_goods_by_id()
	store_good_by_id = _store_goods_by_id()

	if state == null:
		_add_empty_row("Trade data is not connected yet.")
		return

	var ids: Array[String] = _resource_ids_in_order()
	if ids.is_empty():
		_add_empty_row("No goods are available for barter.")
		return

	for resource_id: String in ids:
		_add_trade_row(resource_id)

func _resource_ids_in_order() -> Array[String]:
	var ids: Array[String] = []
	for key_variant: Variant in store_good_by_id.keys():
		ids.append(String(key_variant))
	for key_variant: Variant in market_good_by_id.keys():
		var id: String = String(key_variant)
		if not ids.has(id):
			ids.append(id)
	return ids

func _add_empty_row(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	list_root.add_child(label)

func _add_trade_row(resource_id: String) -> void:
	var store_good: Dictionary = store_good_by_id.get(resource_id, {}) as Dictionary
	var market_good: Dictionary = market_good_by_id.get(resource_id, {}) as Dictionary
	var display_name: String = _good_name(resource_id, store_good, market_good)
	var estate_free: float = maxf(0.0, float(store_good.get("free", 0.0)))
	var estate_stored: float = maxf(0.0, float(store_good.get("stored", 0.0)))
	var estate_reserved: float = maxf(0.0, float(store_good.get("reserved", 0.0)))
	var market_stock: float = maxf(0.0, float(market_good.get("market_stock", 0.0)))
	var unit_value: float = maxf(0.0, float(market_good.get("current_value", market_good.get("projected_value", market_good.get("base_value", 1.0)))))
	var market_state: String = String(market_good.get("label", "Unknown"))

	var sell_cap: int = int(floor(estate_free))
	var buy_cap: int = int(floor(market_stock))
	var existing_value: float = float(trade_plan.get(resource_id, 0.0))
	existing_value = clampf(existing_value, -float(sell_cap), float(buy_cap))
	if absf(existing_value) <= 0.001:
		trade_plan.erase(resource_id)
	else:
		trade_plan[resource_id] = existing_value

	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.05, 0.05, 0.74), _state_colour(market_state), 10))
	list_root.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	stack.add_child(header)

	var name_label: Label = Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(name_label)

	var balance_button: Button = Button.new()
	balance_button.text = "Balance"
	balance_button.custom_minimum_size = Vector2(120, 38)
	balance_button.add_theme_font_size_override("font_size", 18)
	balance_button.tooltip_text = "Set this row to the buy/sell amount needed to balance the rest of the basket."
	balance_button.disabled = sell_cap <= 0 and buy_cap <= 0
	balance_button.pressed.connect(func() -> void:
		_on_balance_pressed(resource_id)
	)
	header.add_child(balance_button)

	var amount_label: Label = Label.new()
	amount_label.custom_minimum_size = Vector2(190, 0)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.add_theme_font_size_override("font_size", 21)
	header.add_child(amount_label)

	var slider_row: HBoxContainer = HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 8)
	stack.add_child(slider_row)

	var sell_label: Label = Label.new()
	sell_label.text = "Sell " + str(sell_cap)
	sell_label.custom_minimum_size = Vector2(90, 0)
	sell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sell_label.add_theme_font_size_override("font_size", 17)
	sell_label.add_theme_color_override("font_color", COLOR_NEGATIVE)
	slider_row.add_child(sell_label)

	var slider: HSlider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = -float(sell_cap)
	slider.max_value = float(buy_cap)
	slider.step = 1.0
	slider.value = existing_value
	slider.editable = sell_cap > 0 or buy_cap > 0
	# Do not let mouse-wheel scrolling over the trade list change barter amounts.
	# The wheel should scroll the list; bars should only change when dragged or balanced.
	slider.scrollable = false
	slider.tick_count = 3
	slider.ticks_on_borders = true
	slider.value_changed.connect(func(value: float) -> void:
		_on_slider_changed(resource_id, value)
	)
	slider_row.add_child(slider)

	var buy_label: Label = Label.new()
	buy_label.text = "Buy " + str(buy_cap)
	buy_label.custom_minimum_size = Vector2(90, 0)
	buy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	buy_label.add_theme_font_size_override("font_size", 17)
	buy_label.add_theme_color_override("font_color", COLOR_POSITIVE)
	slider_row.add_child(buy_label)

	var meta_label: Label = Label.new()
	meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_label.add_theme_font_size_override("font_size", 17)
	meta_label.add_theme_color_override("font_color", COLOR_MUTED)
	stack.add_child(meta_label)

	row_info_by_id[resource_id] = {
		"slider": slider,
		"balance_button": balance_button,
		"amount_label": amount_label,
		"meta_label": meta_label,
		"name": display_name,
		"unit_value": unit_value,
		"estate_free": estate_free,
		"estate_stored": estate_stored,
		"estate_reserved": estate_reserved,
		"market_stock": market_stock,
		"market_state": market_state,
		"sell_cap": sell_cap,
		"buy_cap": buy_cap
	}
	_update_row_labels(resource_id)

func _on_slider_changed(resource_id: String, value: float) -> void:
	if absf(value) <= 0.001:
		trade_plan.erase(resource_id)
	else:
		trade_plan[resource_id] = value
	_update_row_labels(resource_id)
	_refresh_summary()
	emit_signal("trade_changed")

func _on_balance_pressed(resource_id: String) -> void:
	if not row_info_by_id.has(resource_id):
		return
	var info: Dictionary = row_info_by_id[resource_id] as Dictionary
	var slider: HSlider = info.get("slider", null) as HSlider
	if slider == null:
		return

	# Balance against the rest of the basket, ignoring this row's current value.
	# If the rest of the basket is surplus, this row should buy enough goods to spend it.
	# If the rest of the basket is deficit, this row should sell enough goods to cover it.
	var totals: Dictionary = _basket_totals_excluding(resource_id)
	var sold_without: float = float(totals.get("sold_value", 0.0))
	var bought_without: float = float(totals.get("bought_value", 0.0))
	var balance_without: float = sold_without - bought_without
	var new_amount: float = 0.0

	if balance_without > 0.001:
		var buy_cap: int = int(info.get("buy_cap", 0))
		new_amount = float(_largest_buy_amount_within_value(resource_id, balance_without, buy_cap))
		if new_amount <= 0.0:
			_set_error_text("No " + String(info.get("name", resource_id)) + " can be bought to spend the current surplus.")
	elif balance_without < -0.001:
		var sell_cap: int = int(info.get("sell_cap", 0))
		new_amount = -float(_smallest_sell_amount_covering_value(resource_id, absf(balance_without), sell_cap))
		if new_amount >= 0.0:
			_set_error_text("Not enough free " + String(info.get("name", resource_id)) + " to balance this basket.")
	else:
		new_amount = 0.0
		_set_error_text("The basket is already balanced without " + String(info.get("name", resource_id)) + ".")

	if absf(new_amount) <= 0.001:
		trade_plan.erase(resource_id)
	else:
		trade_plan[resource_id] = new_amount

	# Clamp again against the live slider limits and push the UI to the selected amount.
	new_amount = clampf(new_amount, float(slider.min_value), float(slider.max_value))
	if not is_equal_approx(slider.value, new_amount):
		slider.value = new_amount
	else:
		_update_row_labels(resource_id)
		_refresh_summary()
		emit_signal("trade_changed")

func _set_error_text(text: String) -> void:
	if error_label:
		error_label.text = text

func _update_row_labels(resource_id: String) -> void:
	if not row_info_by_id.has(resource_id):
		return
	var info: Dictionary = row_info_by_id[resource_id] as Dictionary
	var amount: float = float(trade_plan.get(resource_id, 0.0))
	var amount_label: Label = info.get("amount_label", null) as Label
	var meta_label: Label = info.get("meta_label", null) as Label
	var estate_free: float = float(info.get("estate_free", 0.0))
	var estate_stored: float = float(info.get("estate_stored", 0.0))
	var estate_reserved: float = float(info.get("estate_reserved", 0.0))
	var market_stock: float = float(info.get("market_stock", 0.0))
	var market_state: String = String(info.get("market_state", "Unknown"))
	var pricing: Dictionary = _trade_pricing(resource_id, amount)
	var current_unit_value: float = _current_unit_value_for(resource_id)
	var after_slider_value: float = float(pricing.get("next_unit_value", current_unit_value))

	if amount_label:
		if amount < -0.001:
			amount_label.text = "Sell " + _fmt(absf(amount))
			amount_label.add_theme_color_override("font_color", COLOR_NEGATIVE)
		elif amount > 0.001:
			amount_label.text = "Buy " + _fmt(amount)
			amount_label.add_theme_color_override("font_color", COLOR_POSITIVE)
		else:
			amount_label.text = "No trade"
			amount_label.add_theme_color_override("font_color", COLOR_TEAL)

	if meta_label:
		var value_text: String = "Projected value now " + _fmt(current_unit_value)
		if absf(amount) > 0.001:
			value_text += " → after slider " + _fmt(after_slider_value)
			value_text += " | Basket total " + _fmt(float(pricing.get("total_value", 0.0)))
			value_text += " | Avg " + _fmt(float(pricing.get("average_value", 0.0)))
		value_text += " | Estate stored " + _fmt(estate_stored)
		value_text += " | Free " + _fmt(estate_free)
		if estate_reserved > 0.001:
			value_text += " | Reserved " + _fmt(estate_reserved)
		value_text += " | Market " + _fmt(market_stock)
		value_text += " | " + market_state
		meta_label.text = value_text

func _refresh_summary() -> void:
	var totals: Dictionary = _basket_totals()
	var sold_value: float = float(totals.get("sold_value", 0.0))
	var bought_value: float = float(totals.get("bought_value", 0.0))
	var balance: float = sold_value - bought_value
	var line_colour: String = "#8FE6D1"
	if balance < -0.001:
		line_colour = "#FF6152"
	elif balance > 0.001:
		line_colour = "#7AF09D"

	if summary_label:
		summary_label.text = "[b]Barter Balance[/b]: [color=" + line_colour + "][b]" + _signed_fmt(balance) + "[/b][/color]\n"
		summary_label.text += "Sold value: [b]" + _fmt(sold_value) + "[/b]   Bought value: [b]" + _fmt(bought_value) + "[/b]\n"
		if balance < -0.001:
			summary_label.text += "[color=#FF6152]Offer more goods or buy less to make the barter acceptable. Use Balance on a sellable good to cover the gap.[/color]"
		elif bought_value <= 0.001 and sold_value <= 0.001:
			summary_label.text += "Move a slider to build a barter offer."
		elif balance > 0.001:
			summary_label.text += "[color=#FFC25A]Surplus value will be lost when accepted; use Balance on a buyable good to spend it.[/color]"
		else:
			summary_label.text += "[color=#7AF09D]Balanced barter ready.[/color]"

	if accept_button:
		accept_button.disabled = balance < -0.001 or (sold_value <= 0.001 and bought_value <= 0.001)
	if clear_button:
		clear_button.disabled = trade_plan.is_empty()
	if error_label:
		if balance < -0.001:
			error_label.text = "Trade asks for " + _fmt(absf(balance)) + " more value than offered."
		elif error_label.text.begins_with("Trade asks for"):
			error_label.text = ""

func _basket_totals() -> Dictionary:
	return _basket_totals_excluding("")

func _basket_totals_excluding(excluded_resource_id: String) -> Dictionary:
	var sold_value: float = 0.0
	var bought_value: float = 0.0
	for key_variant: Variant in trade_plan.keys():
		var resource_id: String = String(key_variant)
		if excluded_resource_id != "" and resource_id == excluded_resource_id:
			continue
		var amount: float = float(trade_plan[key_variant])
		var pricing: Dictionary = _trade_pricing(resource_id, amount)
		var value: float = float(pricing.get("total_value", 0.0))
		if amount < -0.001:
			sold_value += value
		elif amount > 0.001:
			bought_value += value
	return {"sold_value": sold_value, "bought_value": bought_value}

func _largest_buy_amount_within_value(resource_id: String, target_value: float, max_amount: int) -> int:
	var best_amount: int = 0
	for amount: int in range(1, max_amount + 1):
		var value: float = float(_trade_pricing(resource_id, float(amount)).get("total_value", 0.0))
		if value <= target_value + 0.001:
			best_amount = amount
		else:
			break
	return best_amount

func _smallest_sell_amount_covering_value(resource_id: String, target_value: float, max_amount: int) -> int:
	for amount: int in range(1, max_amount + 1):
		var value: float = float(_trade_pricing(resource_id, -float(amount)).get("total_value", 0.0))
		if value >= target_value - 0.001:
			return amount
	return 0

func _on_clear_pressed() -> void:
	trade_plan.clear()
	for key_variant: Variant in row_info_by_id.keys():
		var id: String = String(key_variant)
		var info: Dictionary = row_info_by_id[id] as Dictionary
		var slider: HSlider = info.get("slider", null) as HSlider
		if slider:
			slider.value = 0.0
		_update_row_labels(id)
	_refresh_summary()
	emit_signal("trade_changed")

func _on_accept_pressed() -> void:
	var validation: Dictionary = _validate_against_current_state()
	if not bool(validation.get("valid", false)):
		if error_label:
			error_label.text = String(validation.get("reason", "Trade could not be accepted."))
		_refresh_rows()
		_refresh_summary()
		return
	_apply_trade(validation)
	trade_plan.clear()
	_refresh_rows()
	_refresh_summary()
	emit_signal("trade_accepted")

func _validate_against_current_state() -> Dictionary:
	if state == null:
		return {"valid": false, "reason": "Trade data is not connected."}
	market_good_by_id = _market_goods_by_id()
	store_good_by_id = _store_goods_by_id()
	var sold_value: float = 0.0
	var bought_value: float = 0.0
	var clean_plan: Dictionary = {}
	var sold_parts: Array[String] = []
	var bought_parts: Array[String] = []

	for key_variant: Variant in trade_plan.keys():
		var resource_id: String = String(key_variant)
		var amount: float = float(trade_plan[key_variant])
		if absf(amount) <= 0.001:
			continue
		var store_good: Dictionary = store_good_by_id.get(resource_id, {}) as Dictionary
		var market_good: Dictionary = market_good_by_id.get(resource_id, {}) as Dictionary
		var free_value: float = maxf(0.0, float(store_good.get("free", 0.0)))
		var market_stock: float = maxf(0.0, float(market_good.get("market_stock", 0.0)))
		var pricing: Dictionary = _trade_pricing(resource_id, amount)
		var trade_value: float = float(pricing.get("total_value", 0.0))
		if amount < -0.001:
			var sell_amount: float = absf(amount)
			if sell_amount > free_value + 0.001:
				return {"valid": false, "reason": "Not enough free " + _good_name(resource_id, store_good, market_good) + " to sell after reserves."}
			sold_value += trade_value
			sold_parts.append(_good_name(resource_id, store_good, market_good) + " " + _fmt(sell_amount) + " value " + _fmt(trade_value))
			clean_plan[resource_id] = -sell_amount
		elif amount > 0.001:
			if amount > market_stock + 0.001:
				return {"valid": false, "reason": "Not enough " + _good_name(resource_id, store_good, market_good) + " in the market to buy."}
			bought_value += trade_value
			bought_parts.append(_good_name(resource_id, store_good, market_good) + " " + _fmt(amount) + " value " + _fmt(trade_value))
			clean_plan[resource_id] = amount

	if clean_plan.is_empty():
		return {"valid": false, "reason": "No barter offer selected."}
	var balance: float = sold_value - bought_value
	if balance < -0.001:
		return {"valid": false, "reason": "Trade asks for " + _fmt(absf(balance)) + " more value than offered."}
	return {
		"valid": true,
		"plan": clean_plan,
		"sold_value": sold_value,
		"bought_value": bought_value,
		"balance": balance,
		"sold_parts": sold_parts,
		"bought_parts": bought_parts
	}

func _apply_trade(validation: Dictionary) -> void:
	if state == null:
		return
	var plan: Dictionary = validation.get("plan", {}) as Dictionary
	var estate_variant: Variant = state.get("estate_stockpiles")
	var market_variant: Variant = state.get("market_stockpiles")
	if not (estate_variant is Dictionary) or not (market_variant is Dictionary):
		return
	var estate_stockpiles: Dictionary = estate_variant as Dictionary
	var market_stockpiles: Dictionary = market_variant as Dictionary

	for key_variant: Variant in plan.keys():
		var resource_id: String = String(key_variant)
		var amount: float = float(plan[key_variant])
		estate_stockpiles[resource_id] = maxf(0.0, float(estate_stockpiles.get(resource_id, 0.0)) + amount)
		market_stockpiles[resource_id] = maxf(0.0, float(market_stockpiles.get(resource_id, 0.0)) - amount)

	state.set("estate_stockpiles", estate_stockpiles)
	state.set("market_stockpiles", market_stockpiles)

	var sold_parts: Array = validation.get("sold_parts", []) as Array
	var bought_parts: Array = validation.get("bought_parts", []) as Array
	var balance: float = float(validation.get("balance", 0.0))
	var report_line: String = "Barter trade accepted."
	if not sold_parts.is_empty():
		report_line += " Sold: " + ", ".join(PackedStringArray(sold_parts)) + "."
	if not bought_parts.is_empty():
		report_line += " Bought: " + ", ".join(PackedStringArray(bought_parts)) + "."
	if balance > 0.001:
		report_line += " Surplus barter value " + _fmt(balance) + " lost."

	var report_variant: Variant = state.get("last_report")
	if report_variant is Array:
		var report: Array = report_variant as Array
		report.append(report_line)
		state.set("last_report", report)

	if state.has_signal("state_changed"):
		state.emit_signal("state_changed")

func _market_goods_by_id() -> Dictionary:
	var output: Dictionary = {}
	if state == null or not state.has_method("get_market_goods"):
		return output
	var goods: Array = state.call("get_market_goods") as Array
	for good_variant: Variant in goods:
		var good: Dictionary = good_variant as Dictionary
		output[String(good.get("id", ""))] = good
	return output

func _store_goods_by_id() -> Dictionary:
	var output: Dictionary = {}
	if state == null or not state.has_method("get_storehouse_goods"):
		return output
	var goods: Array = state.call("get_storehouse_goods") as Array
	for good_variant: Variant in goods:
		var good: Dictionary = good_variant as Dictionary
		output[String(good.get("id", ""))] = good
	return output

func _good_name(resource_id: String, store_good: Dictionary, market_good: Dictionary) -> String:
	var name: String = String(store_good.get("name", ""))
	if name != "":
		return name
	name = String(market_good.get("name", ""))
	if name != "":
		return name
	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))
	return resource_id.replace("_", " ").capitalize()

func _unit_value_for(resource_id: String) -> float:
	return _current_unit_value_for(resource_id)

func _current_unit_value_for(resource_id: String) -> float:
	var market_good: Dictionary = market_good_by_id.get(resource_id, {}) as Dictionary
	var pricing_stock: float = _market_stock_for_pricing(market_good)
	return _trade_price_for_stock(resource_id, pricing_stock)

func _trade_pricing(resource_id: String, amount: float) -> Dictionary:
	var market_good: Dictionary = market_good_by_id.get(resource_id, {}) as Dictionary
	var start_stock: float = _market_stock_for_pricing(market_good)
	var actual_market_stock: float = maxf(0.0, float(market_good.get("market_stock", start_stock)))
	var remaining_amount: int = int(absf(roundf(amount)))
	var working_stock: float = start_stock
	var total_value: float = 0.0
	var first_unit_value: float = _trade_price_for_stock(resource_id, working_stock)
	var last_paid_unit_value: float = first_unit_value

	if remaining_amount <= 0:
		return {
			"total_value": 0.0,
			"average_value": 0.0,
			"first_unit_value": first_unit_value,
			"last_unit_value": first_unit_value,
			"next_unit_value": first_unit_value,
			"start_stock": start_stock,
			"final_stock": start_stock
		}

	if amount > 0.001:
		remaining_amount = mini(remaining_amount, int(floor(actual_market_stock)))
		for index: int in range(remaining_amount):
			var buy_unit_value: float = _trade_price_for_stock(resource_id, working_stock)
			total_value += buy_unit_value
			last_paid_unit_value = buy_unit_value
			working_stock = maxf(0.0, working_stock - 1.0)
	elif amount < -0.001:
		for index: int in range(remaining_amount):
			var sell_unit_value: float = _trade_price_for_stock(resource_id, working_stock)
			total_value += sell_unit_value
			last_paid_unit_value = sell_unit_value
			working_stock += 1.0

	var average_value: float = 0.0
	if remaining_amount > 0:
		average_value = total_value / float(remaining_amount)
	return {
		"total_value": total_value,
		"average_value": average_value,
		"first_unit_value": first_unit_value,
		"last_unit_value": last_paid_unit_value,
		"next_unit_value": _trade_price_for_stock(resource_id, working_stock),
		"start_stock": start_stock,
		"final_stock": working_stock
	}

func _market_stock_for_pricing(market_good: Dictionary) -> float:
	# The Market rows price goods from projected post-village stock when available.
	# Using the same value here keeps the Trade Basket aligned with the visible
	# projected market price, while the final accepted trade still moves the actual stockpile.
	return maxf(0.0, float(market_good.get("projected_market_stock", market_good.get("market_stock", 0.0))))

func _trade_price_for_stock(resource_id: String, stock_value: float) -> float:
	var market_good: Dictionary = market_good_by_id.get(resource_id, {}) as Dictionary
	var base_value: float = maxf(0.0, float(market_good.get("base_value", 1.0)))
	var demand_value: float = _market_demand_for_pricing(market_good)
	if demand_value <= 0.001:
		return base_value
	var coverage: float = maxf(0.0, stock_value) / demand_value
	return base_value * _local_scarcity_multiplier(coverage, demand_value)

func _market_demand_for_pricing(market_good: Dictionary) -> float:
	var demand_value: float = maxf(0.0, float(market_good.get("village_total_demand", 0.0)))
	if demand_value <= 0.001:
		demand_value = maxf(0.0, float(market_good.get("demand", 0.0)))
	return demand_value

func _local_scarcity_multiplier(coverage: float, demand: float) -> float:
	if demand <= 0.001:
		return 1.0
	if coverage <= 0.001:
		return 3.0
	return clampf(3.0 / coverage, 0.50, 3.0)

func _state_colour(state_label: String) -> Color:
	match state_label:
		"Crisis":
			return COLOR_NEGATIVE
		"Shortage":
			return Color(1.00, 0.64, 0.25, 1.0)
		"Tight":
			return COLOR_WARNING
		"Abundant":
			return COLOR_POSITIVE
		"Comfortable":
			return COLOR_TEAL
		_:
			return COLOR_MUTED

func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(border.r, border.g, border.b, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(8)
	return style

func _add_styles() -> void:
	add_theme_stylebox_override("panel", _make_panel_style(Color(0.0, 0.0, 0.0, 0.58), COLOR_TEAL, 12))

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _signed_fmt(value: float) -> String:
	if value > 0.001:
		return "+" + _fmt(value)
	return _fmt(value)
