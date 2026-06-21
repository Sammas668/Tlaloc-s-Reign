# MarketScreenController.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/MarketScreenController.gd
#
# Extracted Market / Trade Basket screen controller.
#
# Owns market main-view routing, Trade Basket wiring, Savvy Trade Prestige
# preview UI, and market report-card composition that previously lived in
# GameScreenMarketOverviewPatch.gd.
#
# This is UI/controller code only. Market pricing, validation, application and
# prestige rules remain in TRGameState / MarketTradeSystem / PrestigeSystem.
class_name MarketScreenController
extends RefCounted

const MARKET_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/MarketView.tscn")
const TRADE_BASKET_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/TradeBasketView.tscn")

const COLOR_TEXT: Color = Color(0.92, 0.88, 0.78, 1.0)

var _active_trade_basket_view: Control = null
var _trade_basket_savvy_preview_label: RichTextLabel = null
var _last_trade_basket_savvy_lines: Array = []
var _last_trade_basket_savvy_preview: Dictionary = {}
var _last_context: RefCounted = null

# -----------------------------------------------------------------------------
# Main market view routing
# -----------------------------------------------------------------------------

func show_market_view_with_context(context: RefCounted) -> void:
	_last_context = context
	if context == null:
		return
	context.call("set_content_root_layout", true)
	var content_text: Control = context.get("content_text") as Control
	if content_text != null:
		content_text.visible = false

	var market_focus: String = _current_focus_id(context)
	if market_focus == "trade":
		_show_trade_basket_view(context)
		return

	var selected_market_good_id: String = _selected_market_good_id(context)
	var auto_open_market_report: bool = market_focus == "overview" or market_focus == "village" or market_focus == "rivals" or market_focus == "reports"
	if selected_market_good_id == "" and not auto_open_market_report:
		var content_root: Control = context.get("content_root") as Control
		if content_root != null:
			content_root.visible = false
		return

	var content_root: Control = context.get("content_root") as Control
	if content_root != null:
		content_root.visible = true
	var dynamic_view_host: VBoxContainer = context.get("dynamic_view_host") as VBoxContainer
	if dynamic_view_host == null:
		return
	dynamic_view_host.visible = true

	var market_view: Control = MARKET_VIEW_SCENE.instantiate() as Control
	if market_view == null:
		return
	market_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_view_host.add_child(market_view)
	_set_host_value(context, "market_view", market_view)
	if market_view.has_signal("good_selected") and _host(context) != null and _host(context).has_method("_on_market_good_selected"):
		market_view.connect("good_selected", Callable(_host(context), "_on_market_good_selected"))
	if market_view.has_signal("good_closed") and _host(context) != null and _host(context).has_method("_on_market_good_closed"):
		market_view.connect("good_closed", Callable(_host(context), "_on_market_good_closed"))
	if market_view.has_method("setup"):
		market_view.call("setup", _market_goods(context), market_focus, selected_market_good_id)

func _show_trade_basket_view(context: RefCounted) -> void:
	var content_root: Control = context.get("content_root") as Control
	if content_root != null:
		content_root.visible = true
	var dynamic_view_host: VBoxContainer = context.get("dynamic_view_host") as VBoxContainer
	if dynamic_view_host == null:
		return
	dynamic_view_host.visible = true

	var trade_view: Control = TRADE_BASKET_VIEW_SCENE.instantiate() as Control
	if trade_view == null:
		return
	trade_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_view_host.add_child(trade_view)
	_active_trade_basket_view = trade_view
	_trade_basket_savvy_preview_label = null
	if trade_view.has_signal("trade_accepted"):
		trade_view.connect("trade_accepted", Callable(self, "_on_trade_basket_accepted"))
	if trade_view.has_signal("trade_changed"):
		trade_view.connect("trade_changed", Callable(self, "_on_trade_basket_changed"))
	if trade_view.has_method("setup"):
		trade_view.call("setup", _state(context))
	_ensure_trade_basket_savvy_preview_label()
	_capture_trade_basket_savvy_preview()
	_update_trade_basket_savvy_summary_display()

# -----------------------------------------------------------------------------
# Trade Basket / Savvy Trade Prestige preview
# -----------------------------------------------------------------------------

func _on_trade_basket_accepted() -> void:
	# TradeBasketView clears its internal plan before emitting trade_accepted, so the
	# last captured trade_changed preview is used to award Economic Prestige safely.
	var context: RefCounted = _last_context
	var state: Node = _state(context)
	if state != null and state.has_method("record_savvy_trade_prestige") and not _last_trade_basket_savvy_lines.is_empty():
		state.call("record_savvy_trade_prestige", _last_trade_basket_savvy_lines, "Savvy market trade")
	_last_trade_basket_savvy_lines.clear()
	_last_trade_basket_savvy_preview.clear()
	_trade_basket_savvy_preview_label = null
	if context != null:
		_set_host_value(context, "selected_market_good_id", "")
		context.call("refresh_main_content")
		context.call("refresh_right_panel")

func _on_trade_basket_changed() -> void:
	_capture_trade_basket_savvy_preview()
	_update_trade_basket_savvy_summary_display()
	if _last_context != null:
		_last_context.call("refresh_right_panel")

func _capture_trade_basket_savvy_preview() -> void:
	_last_trade_basket_savvy_lines.clear()
	_last_trade_basket_savvy_preview.clear()
	if _active_trade_basket_view == null:
		return
	var plan_variant: Variant = _active_trade_basket_view.get("trade_plan")
	if not (plan_variant is Dictionary):
		return
	var plan: Dictionary = plan_variant as Dictionary
	for key_variant: Variant in plan.keys():
		var resource_id: String = String(key_variant)
		var amount: float = float(plan[key_variant])
		if absf(amount) <= 0.001:
			continue
		# Do not call TradeBasketView private methods from this controller.
		# The preview only needs the public market-facing value for the selected good.
		var average_value: float = _average_market_value_for_good(resource_id)
		_last_trade_basket_savvy_lines.append({"resource_id": resource_id, "amount": amount, "average_unit_value": average_value})
	var state: Node = _state(_last_context)
	if state != null and state.has_method("get_savvy_trade_prestige_preview"):
		var preview_variant: Variant = state.call("get_savvy_trade_prestige_preview", _last_trade_basket_savvy_lines)
		if preview_variant is Dictionary:
			_last_trade_basket_savvy_preview = preview_variant as Dictionary

func _average_market_value_for_good(resource_id: String) -> float:
	var state_for_base: Node = _state(_last_context)
	if state_for_base != null and state_for_base.has_method("get_market_goods"):
		var goods_raw: Variant = state_for_base.call("get_market_goods")
		if goods_raw is Array:
			for good_variant: Variant in goods_raw as Array:
				if good_variant is Dictionary and String((good_variant as Dictionary).get("id", "")) == resource_id:
					var good: Dictionary = good_variant as Dictionary
					return maxf(0.0, float(good.get("current_value", good.get("base_value", 1.0))))
	return 0.0

func _trade_basket_summary_label() -> RichTextLabel:
	if _active_trade_basket_view == null:
		return null
	var label_variant: Variant = _active_trade_basket_view.get("summary_label")
	if label_variant is RichTextLabel:
		return label_variant as RichTextLabel
	return _find_trade_basket_summary_label(_active_trade_basket_view)

func _find_trade_basket_summary_label(node: Node) -> RichTextLabel:
	if node == null:
		return null
	if node is RichTextLabel:
		var candidate: RichTextLabel = node as RichTextLabel
		var candidate_text: String = candidate.text.to_lower()
		if candidate_text.contains("sold") or candidate_text.contains("bought") or candidate_text.contains("selected") or candidate_text.contains("value"):
			return candidate
	for child_index: int in range(node.get_child_count()):
		var child: Node = node.get_child(child_index)
		var found: RichTextLabel = _find_trade_basket_summary_label(child)
		if found != null:
			return found
	return null

func _ensure_trade_basket_savvy_preview_label() -> RichTextLabel:
	if _active_trade_basket_view == null:
		return null
	if _trade_basket_savvy_preview_label != null and is_instance_valid(_trade_basket_savvy_preview_label) and _trade_basket_savvy_preview_label.get_parent() != null:
		return _trade_basket_savvy_preview_label

	var summary_label: RichTextLabel = _trade_basket_summary_label()
	var target_parent: Node = _active_trade_basket_view
	var insert_index: int = -1
	if summary_label != null and summary_label.get_parent() != null:
		target_parent = summary_label.get_parent()
		insert_index = summary_label.get_index() + 1

	var preview_label: RichTextLabel = RichTextLabel.new()
	preview_label.name = "SavvyTradePrestigePreview"
	preview_label.bbcode_enabled = true
	preview_label.fit_content = true
	preview_label.scroll_active = false
	preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_label.add_theme_color_override("default_color", COLOR_TEXT)
	preview_label.add_theme_font_size_override("normal_font_size", 15)
	target_parent.add_child(preview_label)
	if insert_index >= 0:
		target_parent.move_child(preview_label, min(insert_index, target_parent.get_child_count() - 1))
	_trade_basket_savvy_preview_label = preview_label
	return preview_label

func _trade_basket_savvy_preview_bbcode() -> String:
	var total: float = 0.0
	if not _last_trade_basket_savvy_preview.is_empty():
		total = float(_last_trade_basket_savvy_preview.get("total_prestige", 0.0))
	var preview_text: String = "[b]Savvy Trade Prestige if accepted[/b]: "
	if total > 0.001:
		preview_text += "[color=#7AF09D][b]+" + _format_float(total) + "[/b][/color]"
		var positive_lines: Array = _last_trade_basket_savvy_preview.get("positive_lines", []) as Array
		if not positive_lines.is_empty():
			var line_parts: Array[String] = []
			for line_variant: Variant in positive_lines:
				if line_parts.size() >= 3:
					break
				line_parts.append(String(line_variant))
			preview_text += "\n[color=#CDEFD5]" + "; ".join(line_parts) + "[/color]"
	else:
		preview_text += "[color=#9AA69B]0[/color]"
		if not _last_trade_basket_savvy_lines.is_empty():
			preview_text += "\n[color=#9AA69B]No selected good is currently being bought below base value or sold above base value.[/color]"
		else:
			preview_text += "\n[color=#9AA69B]Move a trade slider to preview market-skill Prestige.[/color]"
	return preview_text

func _strip_trade_basket_savvy_from_summary_label() -> void:
	var trade_summary: RichTextLabel = _trade_basket_summary_label()
	if trade_summary == null:
		return
	var marker: String = "\n\n[b]Savvy Trade Prestige[/b]:"
	var marker_index: int = trade_summary.text.find(marker)
	if marker_index >= 0:
		trade_summary.text = trade_summary.text.substr(0, marker_index)

func _update_trade_basket_savvy_summary_display() -> void:
	if _active_trade_basket_view == null:
		return
	_strip_trade_basket_savvy_from_summary_label()
	var preview_label: RichTextLabel = _ensure_trade_basket_savvy_preview_label()
	if preview_label == null:
		return
	preview_label.text = _trade_basket_savvy_preview_bbcode()
	preview_label.visible = true

# -----------------------------------------------------------------------------
# Market report cards
# -----------------------------------------------------------------------------

func build_market_overview_with_context(context: RefCounted) -> void:
	_last_context = context
	var goods: Array[Dictionary] = _market_goods(context)
	if goods.is_empty():
		_add_notification(context, "No market data is connected yet.")
		return

	var crisis_goods: Array[String] = []
	var shortage_goods: Array[String] = []
	var tight_goods: Array[String] = []
	var abundant_goods: Array[String] = []
	var high_value_goods: Array[String] = []
	var low_value_goods: Array[String] = []
	var falling_goods: Array[String] = []
	var rising_goods: Array[String] = []

	for good: Dictionary in goods:
		var name: String = String(good.get("name", "Good"))
		var label: String = String(good.get("label", "Unknown"))
		var trend: String = String(good.get("trend", "Stable"))
		var current_value: float = float(good.get("current_value", good.get("projected_value", 0.0)))
		var base_value: float = float(good.get("base_value", 1.0))
		var net_change: float = float(good.get("village_net_change", 0.0))

		match label:
			"Crisis":
				crisis_goods.append(name)
			"Shortage":
				shortage_goods.append(name)
			"Tight":
				tight_goods.append(name)
			"Abundant":
				abundant_goods.append(name)

		if base_value > 0.0 and current_value >= base_value * 1.35:
			high_value_goods.append(name + " " + _format_float(current_value))
		elif base_value > 0.0 and current_value <= base_value * 0.75:
			low_value_goods.append(name + " " + _format_float(current_value))

		if net_change < -0.01 or trend == "Falling" or trend == "Falling fast":
			falling_goods.append(name + " " + _format_float(net_change))
		elif net_change > 0.01 or trend == "Rising" or trend == "Rising fast":
			rising_goods.append(name + " +" + _format_float(net_change))

	_add_notification(context, "Overview is the quick pressure read. Use Goods for the full good-by-good ledger and click a good for its supply, demand and price detail.")
	_add_notification(context, "Market pressure: " + _market_group_summary(crisis_goods, "Crisis", shortage_goods, "Shortage", tight_goods, "Tight"))
	if not high_value_goods.is_empty():
		_add_notification(context, "Best sale/value pressure: " + _patch_join_limited(high_value_goods, 4) + ".")
	else:
		_add_notification(context, "No obvious high-value sale pressure yet.")
	if not falling_goods.is_empty():
		_add_notification(context, "Draining goods: " + _patch_join_limited(falling_goods, 5) + ".")
	else:
		_add_notification(context, "No major market drains currently visible.")
	if not rising_goods.is_empty():
		_add_notification(context, "Recovering/supplied goods: " + _patch_join_limited(rising_goods, 5) + ".")
	elif not abundant_goods.is_empty():
		_add_notification(context, "Abundant goods: " + _patch_join_limited(abundant_goods, 5) + ".")
	if not low_value_goods.is_empty():
		_add_notification(context, "Cheap buying opportunities: " + _patch_join_limited(low_value_goods, 4) + ".")

func build_market_trade_summary_with_context(context: RefCounted) -> void:
	_last_context = context
	_add_notification(context, "Trade Basket is a barter interface. Drag a good left to sell estate free stock, or right to buy from the market.")
	_add_notification(context, "Accept Trade is enabled only when sold value covers bought value. Positive surplus is lost as barter inefficiency; it is not stored as Wealth or credit.")
	_add_notification(context, "Economic Prestige now comes from savvy trade only: selling above base value or buying below base value. No passive surplus, maize stockpile or production-output Prestige is granted.")
	if not _last_trade_basket_savvy_preview.is_empty():
		_add_notification(context, String(_last_trade_basket_savvy_preview.get("headline", "No savvy trade Prestige.")))
	var state: Node = _state(context)
	if state != null and state.has_method("get_economic_prestige_summary"):
		var economic: Dictionary = state.call("get_economic_prestige_summary") as Dictionary
		_add_notification(context, "Savvy trade scale: " + _format_float(float(economic.get("scale", 0.25))) + " × value advantage. Recent savvy trades: " + str((economic.get("recent_savvy_trades", []) as Array).size()) + ".")
	_add_notification(context, "Sell caps use Storehouse free stock after reserves. Buy caps use current market stock.")
	_add_notification(context, "This connects Storehouse and Market directly without creating a currency resource.")

func build_market_rivals_summary_with_context(context: RefCounted) -> void:
	_last_context = context
	var goods: Array[Dictionary] = _market_goods(context)
	if goods.is_empty():
		_add_notification(context, "No market data is connected yet.")
		return
	_add_notification(context, "Rival Procurement is a dashboard, not a duplicate goods ledger. Use it to read which goods each rival is likely to pressure once proper Rival AI is connected.")
	_add_notification(context, _rival_pressure_line("War Rival", ["obsidian", "weapons", "armour", "cloth", "tools", "captives"], goods, "Wants Flower War readiness, warrior equipment and captive-taking capacity."))
	_add_notification(context, _rival_pressure_line("Cunning Rival", ["tools", "cloth", "wood", "cacao", "cotton"], goods, "Wants practical bottlenecks, flexible build materials and market leverage."))
	_add_notification(context, _rival_pressure_line("Diplomatic Rival", ["cacao", "fine_textiles", "cloth", "cotton", "tools"], goods, "Wants palace-facing goods, legitimacy goods and tribute-ready luxury supply."))

func _rival_pressure_line(rival_name: String, target_ids: Array[String], goods: Array[Dictionary], motive: String) -> String:
	var pressure_goods: Array[String] = []
	var quiet_goods: Array[String] = []
	for good: Dictionary in goods:
		var good_id: String = String(good.get("id", ""))
		if not target_ids.has(good_id):
			continue
		var name: String = String(good.get("name", good_id.capitalize()))
		var label: String = String(good.get("label", "Unknown"))
		var trend: String = String(good.get("trend", "Stable"))
		var net_change: float = float(good.get("village_net_change", 0.0))
		if label == "Crisis" or label == "Shortage" or label == "Tight" or trend == "Falling" or trend == "Falling fast" or net_change < -0.01:
			pressure_goods.append(name + " (" + label + ", " + _format_float(net_change) + ")")
		else:
			quiet_goods.append(name)
	var line: String = rival_name + ": " + motive
	if not pressure_goods.is_empty():
		line += " Current pressure: " + _patch_join_limited(pressure_goods, 4) + "."
	elif not quiet_goods.is_empty():
		line += " Watched goods: " + _patch_join_limited(quiet_goods, 5) + "."
	else:
		line += " Target goods are not present in the market data yet."
	return line

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _market_goods(context: RefCounted) -> Array[Dictionary]:
	if context != null:
		var raw: Variant = context.call("call_host", "_market_goods")
		if raw is Array:
			var output: Array[Dictionary] = []
			for item: Variant in raw:
				if item is Dictionary:
					output.append(item as Dictionary)
			return output
	var state: Node = _state(context)
	if state != null and state.has_method("get_market_goods"):
		var goods_raw: Variant = state.call("get_market_goods")
		if goods_raw is Array:
			var goods: Array[Dictionary] = []
			for good_variant: Variant in goods_raw:
				if good_variant is Dictionary:
					goods.append(good_variant as Dictionary)
			return goods
	return []

func _current_focus_id(context: RefCounted) -> String:
	if context != null and context.has_method("current_focus_id"):
		return String(context.call("current_focus_id"))
	return "overview"

func _selected_market_good_id(context: RefCounted) -> String:
	var host: Node = _host(context)
	if host == null:
		return ""
	var raw: Variant = host.get("selected_market_good_id")
	if raw == null:
		return ""
	return String(raw)

func _state(context: RefCounted) -> Node:
	if context != null and context.has_method("state"):
		var raw: Variant = context.call("state")
		if raw is Node:
			return raw as Node
	return null

func _host(context: RefCounted) -> Node:
	if context == null:
		return null
	var raw: Variant = context.get("host")
	if raw is Node:
		return raw as Node
	return null

func _set_host_value(context: RefCounted, property_name: String, value: Variant) -> void:
	var host: Node = _host(context)
	if host == null:
		return
	host.set(property_name, value)

func _add_notification(context: RefCounted, text: String) -> void:
	if context != null and context.has_method("add_notification"):
		context.call("add_notification", text)

func _market_group_summary(first: Array[String], first_label: String, second: Array[String], second_label: String, third: Array[String], third_label: String) -> String:
	var parts: Array[String] = []
	if not first.is_empty(): parts.append(first_label + " — " + _patch_join_limited(first, 4))
	if not second.is_empty(): parts.append(second_label + " — " + _patch_join_limited(second, 4))
	if not third.is_empty(): parts.append(third_label + " — " + _patch_join_limited(third, 4))
	if parts.is_empty():
		return "no crisis, shortage or tight goods visible."
	return "; ".join(parts) + "."

func _patch_join_limited(values: Array[String], max_items: int) -> String:
	var parts: Array[String] = []
	for value: String in values:
		if parts.size() >= max_items:
			break
		parts.append(value)
	var text: String = ", ".join(parts)
	if values.size() > max_items:
		text += ", +" + str(values.size() - max_items) + " more"
	return text

func _format_float(value: float) -> String:
	var context: RefCounted = _last_context
	if context != null and context.has_method("call_host"):
		var raw: Variant = context.call("call_host", "_format_float", [value])
		if raw != null:
			return String(raw)
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value
