# GameScreenMarketOverviewPatch.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenMarketOverviewPatch.gd
#
# Thin drop-in wrapper over GameScreen.gd.
# Keeps the current GameScreen implementation intact, but changes the Market
# Overview tab so it opens a dashboard instead of duplicating the Goods ledger.
extends "res://Scripts/ui/GameScreen.gd"

func _show_market_view() -> void:
	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false
	var market_focus: String = _current_focus_id()

	# Overview, Village, Trade and Reports are screen-level reads.
	# Goods and Rivals remain ledger/detail tabs until a specific good is clicked.
	var auto_open_market_report: bool = market_focus == "overview" or market_focus == "village" or market_focus == "trade" or market_focus == "reports"
	if selected_market_good_id == "" and not auto_open_market_report:
		if content_root:
			content_root.visible = false
		return
	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return
	dynamic_view_host.visible = true
	market_view = MARKET_VIEW_SCENE.instantiate() as Control
	if market_view == null:
		return
	market_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_view_host.add_child(market_view)
	if market_view.has_signal("good_selected"):
		market_view.connect("good_selected", Callable(self, "_on_market_good_selected"))
	if market_view.has_signal("good_closed"):
		market_view.connect("good_closed", Callable(self, "_on_market_good_closed"))
	if market_view.has_method("setup"):
		market_view.call("setup", _market_goods(), _current_focus_id(), selected_market_good_id)

func _refresh_right_panel() -> void:
	_clear_children(notification_list)
	var profile: Dictionary = _profile(current_location_id)
	if notification_title:
		notification_title.text = _report_title_for_current_focus(profile)

	_refresh_house_claim()

	var special_view: String = String(profile.get("special_view", ""))
	if current_location_id == "estate":
		_build_estate_reports()
	elif special_view == "storehouse":
		_build_storehouse_ledger()
	elif special_view == "market":
		var market_focus: String = _current_focus_id()
		if market_focus == "overview":
			_build_market_overview()
		elif market_focus == "reports":
			_build_market_reports()
		else:
			_build_market_ledger()
	elif special_view == "housing":
		if _current_focus_id() == "overview":
			_build_housing_overview_reports()
		elif _current_focus_id() == "mothball":
			_build_housing_mothball_summary()
		else:
			_build_housing_ledger()
	elif special_view == "buildings":
		if current_location_id == "production" and _current_focus_id() == "overview":
			_build_production_overview_reports()
		elif current_location_id == "production" and _current_focus_id() == "labour":
			_build_labour_assignment_summary()
		else:
			_build_building_ledger(profile)
	else:
		_build_report_list(profile)

func _build_market_overview() -> void:
	var goods: Array[Dictionary] = _market_goods()
	if goods.is_empty():
		_add_notification("No market data is connected yet.")
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

	_add_notification("Overview is the quick pressure read. Use Goods for the full good-by-good ledger and click a good for its supply, demand and price detail.")
	_add_notification("Market pressure: " + _market_group_summary(crisis_goods, "Crisis", shortage_goods, "Shortage", tight_goods, "Tight"))

	if not high_value_goods.is_empty():
		_add_notification("Best sale/value pressure: " + _patch_join_limited(high_value_goods, 4) + ".")
	else:
		_add_notification("No obvious high-value sale pressure yet.")

	if not falling_goods.is_empty():
		_add_notification("Draining goods: " + _patch_join_limited(falling_goods, 5) + ".")
	else:
		_add_notification("No major market drains currently visible.")

	if not rising_goods.is_empty():
		_add_notification("Recovering/supplied goods: " + _patch_join_limited(rising_goods, 5) + ".")
	elif not abundant_goods.is_empty():
		_add_notification("Abundant goods: " + _patch_join_limited(abundant_goods, 5) + ".")

	if not low_value_goods.is_empty():
		_add_notification("Cheap buying opportunities: " + _patch_join_limited(low_value_goods, 4) + ".")

func _market_group_summary(first: Array[String], first_label: String, second: Array[String], second_label: String, third: Array[String], third_label: String) -> String:
	var parts: Array[String] = []
	if not first.is_empty():
		parts.append(first_label + " — " + _patch_join_limited(first, 4))
	if not second.is_empty():
		parts.append(second_label + " — " + _patch_join_limited(second, 4))
	if not third.is_empty():
		parts.append(third_label + " — " + _patch_join_limited(third, 4))
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
