# GameScreenMarketOverviewPatch.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenMarketOverviewPatch.gd
#
# Thin drop-in wrapper over GameScreen.gd.
# Keeps the current GameScreen implementation intact, but changes the Market
# Overview, Trade and Rivals tabs so they open dashboard/report views instead of
# duplicating the Goods ledger or reintroducing stored Wealth.
extends "res://Scripts/ui/GameScreen.gd"

const TRADE_BASKET_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/TradeBasketView.tscn")

var _calendar_period: String = "veintena"
var _ritual_year: int = 1

func _show_market_view() -> void:
	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false
	var market_focus: String = _current_focus_id()

	# Trade is its own barter interface. It should not use the generic MarketView
	# placeholder because the player needs sliders, balance text and an accept
	# action in the image area.
	if market_focus == "trade":
		_show_trade_basket_view()
		return

	# Overview, Village, Rivals and Reports are screen-level reads.
	# Goods remains the full ledger/detail tab until a specific good is clicked.
	var auto_open_market_report: bool = market_focus == "overview" or market_focus == "village" or market_focus == "rivals" or market_focus == "reports"
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

func _show_trade_basket_view() -> void:
	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return
	dynamic_view_host.visible = true
	var trade_view: Control = TRADE_BASKET_VIEW_SCENE.instantiate() as Control
	if trade_view == null:
		return
	trade_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_view_host.add_child(trade_view)
	if trade_view.has_signal("trade_accepted"):
		trade_view.connect("trade_accepted", Callable(self, "_on_trade_basket_accepted"))
	if trade_view.has_signal("trade_changed"):
		trade_view.connect("trade_changed", Callable(self, "_on_trade_basket_changed"))
	if trade_view.has_method("setup"):
		trade_view.call("setup", _state())

func _on_trade_basket_accepted() -> void:
	selected_market_good_id = ""
	_refresh_main_content()
	_refresh_right_panel()

func _on_trade_basket_changed() -> void:
	_refresh_right_panel()

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
		elif market_focus == "trade":
			_build_market_trade_summary()
		elif market_focus == "rivals":
			_build_market_rivals_summary()
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

func _build_market_trade_summary() -> void:
	_add_notification("Trade Basket is a barter interface. Drag a good left to sell estate free stock, or right to buy from the market.")
	_add_notification("Accept Trade is enabled only when sold value covers bought value. Positive surplus is lost as barter inefficiency; it is not stored as Wealth or credit.")
	_add_notification("Sell caps use Storehouse free stock after reserves. Buy caps use current market stock.")
	_add_notification("This connects Storehouse and Market directly without creating a currency resource.")

func _build_market_rivals_summary() -> void:
	var goods: Array[Dictionary] = _market_goods()
	if goods.is_empty():
		_add_notification("No market data is connected yet.")
		return

	_add_notification("Rival Procurement is now a dashboard, not a duplicate goods ledger. Use it to read which goods each rival is likely to pressure once rival buying is connected.")
	_add_notification(_rival_pressure_line("War Rival", ["obsidian", "weapons", "armour", "cloth", "tools", "captives"], goods, "Wants Flower War readiness, warrior equipment and captive-taking capacity."))
	_add_notification(_rival_pressure_line("Cunning Rival", ["tools", "cloth", "wood", "cacao", "cotton"], goods, "Wants practical bottlenecks, flexible build materials and market leverage."))
	_add_notification(_rival_pressure_line("Diplomatic Rival", ["cacao", "fine_textiles", "cloth", "cotton", "tools"], goods, "Wants palace-facing goods, legitimacy goods and tribute-ready luxury supply."))

	var visible_signals: Array[String] = []
	for good: Dictionary in goods:
		var rival_note: String = String(good.get("rival_note", ""))
		if rival_note != "" and rival_note != "No rival signal recorded yet.":
			visible_signals.append(String(good.get("name", "Good")) + ": " + rival_note)
	if visible_signals.is_empty():
		_add_notification("No explicit rival buying signals are connected yet. This tab is ready for the rival procurement system to feed notes into market goods.")
	else:
		_add_notification("Visible rival signals: " + _patch_join_limited(visible_signals, 4) + ".")

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

# -----------------------------------------------------------------------------
# Calendar Pacing v2 — safe version
# This section deliberately patches only the active wrapper script. It does not
# replace GameScreen.tscn and does not preload a new calendar scene, so failure
# risk stays much lower than the previous calendar patch.
# -----------------------------------------------------------------------------

func _build_calendar_row() -> void:
	_refresh_calendar_advance_button_label()
	var state: Node = _state()
	var current_veintena: int = _calendar_current_veintena()
	var cards_to_show: int = max(1, visible_veintenas)
	for offset: int in range(cards_to_show):
		var card_data: Dictionary = _calendar_card_data(current_veintena, offset)
		var card_button: Button = Button.new()
		card_button.toggle_mode = false
		card_button.focus_mode = Control.FOCUS_NONE
		card_button.custom_minimum_size = Vector2(166, 112)
		card_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_button.text = String(card_data.get("button_text", "Calendar"))
		card_button.tooltip_text = String(card_data.get("tooltip", ""))
		card_button.add_theme_font_size_override("font_size", 15)
		card_button.add_theme_stylebox_override("normal", _calendar_card_style(card_data, false))
		card_button.add_theme_stylebox_override("hover", _calendar_card_style(card_data, true))
		card_button.add_theme_stylebox_override("pressed", _calendar_card_style(card_data, true))
		var report_id: String = String(card_data.get("report_id", ""))
		card_button.pressed.connect(func() -> void:
			_on_calendar_card_pressed(report_id)
		)
		top_row.add_child(card_button)

func _calendar_card_style(card_data: Dictionary, hover: bool) -> StyleBoxFlat:
	var is_current: bool = bool(card_data.get("current", false))
	var period: String = String(card_data.get("period", "veintena"))
	var god: String = String(card_data.get("god", "Minor / No major festival"))
	var base: Color = Color(0.055, 0.08, 0.075, 0.92)
	var border: Color = _calendar_colour_for_god(god)
	if is_current:
		base = Color(0.09, 0.13, 0.115, 0.98)
		border = border.lightened(0.20)
	elif period == "nemontemi":
		base = Color(0.08, 0.055, 0.09, 0.95)
		border = Color(0.73, 0.46, 0.82, 0.70)
	elif god == "Minor / No major festival":
		base = Color(0.045, 0.065, 0.065, 0.90)
	if hover:
		base = base.lightened(0.07)
		border = border.lightened(0.12)
	return _make_panel_style(base, border, 10)

func _calendar_colour_for_god(god: String) -> Color:
	match god:
		"Tlaloc":
			return Color(0.22, 0.68, 0.86, 0.72)
		"Huitzilopochtli":
			return Color(0.84, 0.35, 0.24, 0.74)
		"Tezcatlipoca":
			return Color(0.62, 0.45, 0.84, 0.72)
		"Quetzalcoatl":
			return Color(0.37, 0.82, 0.57, 0.72)
		"Nemontemi":
			return Color(0.73, 0.46, 0.82, 0.72)
	return Color(0.56, 0.62, 0.58, 0.58)

func _calendar_card_data(current_veintena: int, offset: int) -> Dictionary:
	var base_year: int = _ritual_year
	var position: int = current_veintena + offset
	if _calendar_period == "nemontemi":
		position = 19 + offset

	var year_value: int = base_year
	while position > 19:
		position -= 19
		year_value += 1

	if position == 19:
		return _nemontemi_card_data(year_value, offset == 0)

	var veintena_number: int = clampi(position, 1, 18)
	var god: String = _calendar_god_for_veintena(veintena_number)
	var pressure: String = _calendar_pressure_for_veintena(veintena_number)
	var detail: String = _calendar_detail_for_veintena(veintena_number)
	var name: String = _calendar_veintena_name(veintena_number)
	var current: bool = offset == 0 and _calendar_period == "veintena"
	var prefix: String = "Upcoming"
	if current:
		prefix = "Current"
	var god_label: String = god
	if god == "Minor / No major festival":
		god_label = "Minor"
	var report_id: String = "calendar|" + str(year_value) + "|veintena|" + str(veintena_number)
	return {
		"period": "veintena",
		"year": year_value,
		"veintena": veintena_number,
		"name": name,
		"god": god,
		"pressure": pressure,
		"detail": detail,
		"current": current,
		"report_id": report_id,
		"button_text": prefix + "\nY" + str(year_value) + " V" + str(veintena_number) + "\n" + god_label + "\n" + detail,
		"tooltip": "Ritual Year " + str(year_value) + ", Veintena " + str(veintena_number) + " — " + name + ". " + god + ": " + _calendar_tooltip_for_veintena(veintena_number)
	}

func _nemontemi_card_data(year_value: int, current: bool) -> Dictionary:
	var prefix: String = "Upcoming"
	if current:
		prefix = "Current"
	var report_id: String = "calendar|" + str(year_value) + "|nemontemi|0"
	return {
		"period": "nemontemi",
		"year": year_value,
		"veintena": 0,
		"name": "Nemontemi",
		"god": "Nemontemi",
		"pressure": "Unlucky Days",
		"detail": "Year review",
		"current": current,
		"report_id": report_id,
		"button_text": prefix + "\nY" + str(year_value) + "\nNemontemi\nUnlucky Days",
		"tooltip": "Nemontemi — five unlucky days, annual reckoning, restrictions, omens, review and next-year setup."
	}

func _calendar_current_veintena() -> int:
	var state: Node = _state()
	if state != null and state.has_method("get_current_veintena"):
		return clampi(int(state.call("get_current_veintena")), 1, 18)
	if state != null:
		return clampi(int(state.get("current_veintena")), 1, 18)
	return 1

func _calendar_veintena_name(veintena_number: int) -> String:
	var index: int = veintena_number - 1
	if index >= 0 and index < _veintenas.size():
		var data: Dictionary = _veintenas[index] as Dictionary
		return String(data.get("name", "Veintena " + str(veintena_number)))
	return "Veintena " + str(veintena_number)

func _calendar_god_for_veintena(veintena_number: int) -> String:
	match veintena_number:
		1:
			return "Quetzalcoatl"
		2:
			return "Tlaloc"
		3:
			return "Minor / No major festival"
		4:
			return "Tezcatlipoca"
		5:
			return "Tlaloc"
		6:
			return "Quetzalcoatl"
		7:
			return "Huitzilopochtli"
		8:
			return "Huitzilopochtli"
		9:
			return "Tezcatlipoca"
		10:
			return "Tlaloc"
		11:
			return "Minor / No major festival"
		12:
			return "Tlaloc"
		13:
			return "Quetzalcoatl"
		14:
			return "Minor / No major festival"
		15:
			return "Huitzilopochtli"
		16:
			return "Minor / No major festival"
		17:
			return "Tezcatlipoca"
		18:
			return "Quetzalcoatl"
	return "Minor / No major festival"

func _calendar_pressure_for_veintena(veintena_number: int) -> String:
	match _calendar_god_for_veintena(veintena_number):
		"Tlaloc":
			return "Agriculture / Rain"
		"Huitzilopochtli":
			return "War / Flower Wars"
		"Tezcatlipoca":
			return "Intrigue / Omens"
		"Quetzalcoatl":
			return "Legitimacy / Transition"
	return "Estate Management"

func _calendar_detail_for_veintena(veintena_number: int) -> String:
	match veintena_number:
		1:
			return "Year opening"
		2:
			return "Early planting"
		3:
			return "Recovery/build"
		4:
			return "First omens"
		5:
			return "Mid rains"
		6:
			return "Trade/diplomacy"
		7:
			return "War prep"
		8:
			return "Flower Wars"
		9:
			return "Rival tension"
		10:
			return "Early harvest"
		11:
			return "Market reset"
		12:
			return "Great harvest"
		13:
			return "Legitimacy"
		14:
			return "Preparation"
		15:
			return "War review"
		16:
			return "Recovery"
		17:
			return "End-year plots"
		18:
			return "Closing rites"
	return "planning"

func _calendar_tooltip_for_veintena(veintena_number: int) -> String:
	match veintena_number:
		1:
			return "Quetzalcoatl opens the Ritual Year. This is a transition, legitimacy and planning period."
		2:
			return "Tlaloc supports early planting, rain, lake fertility and food-security planning."
		3:
			return "No major god dominates. Use this as a quieter estate-management, construction, trade or recovery window."
		4:
			return "Tezcatlipoca brings first omens, ambition, manipulation and rival-house tension."
		5:
			return "Tlaloc returns for mid-season rain and fertility pressure. Drought protection and crop planning matter."
		6:
			return "Quetzalcoatl supports trade, diplomacy, legitimacy and civil order during the middle of the year."
		7:
			return "Huitzilopochtli begins military prominence. Prepare warriors, weapons and Flower War readiness."
		8:
			return "Huitzilopochtli dominates the main Flower Wars season. Later systems should centre captives, loot and martial prestige here."
		9:
			return "Tezcatlipoca pressure rises after the war season. Rival plots, omens and political manipulation fit here."
		10:
			return "Tlaloc governs early harvest, rain memory, lakes and agricultural return."
		11:
			return "No major god dominates. This is a breathing-room window for markets, stores, repairs and economic recovery."
		12:
			return "Tlaloc reaches the great harvest moment. Agricultural output, gratitude and food security should be prominent."
		13:
			return "Quetzalcoatl supports diplomacy, legitimacy, palace-facing order and civil recognition."
		14:
			return "No major god dominates. Use this as preparation before the late-year military and reckoning pressures."
		15:
			return "Huitzilopochtli returns for late-year military review, martial prestige and warrior standing."
		16:
			return "No major god dominates. This is a recovery and economic repositioning period before the end-year intrigue phase."
		17:
			return "Tezcatlipoca governs end-of-year intrigue, omens, hidden pressure and reckoning danger."
		18:
			return "Quetzalcoatl closes the ordinary year through transition, order, legitimacy and ceremonial completion."
	return "Calendar planning pressure."

func _calendar_player_advice_for_veintena(veintena_number: int) -> String:
	match veintena_number:
		1:
			return "Review stores, market value and immediate shortages before committing the year's direction."
		2:
			return "Protect maize security and consider whether Tlaloc-facing offerings or reserves are needed."
		3:
			return "Use the quieter window to build, trade, staff production or recover from early pressure."
		4:
			return "Watch rivals and prepare for future sabotage, omens or hidden information systems."
		5:
			return "Strengthen food security before the year moves into trade and war pressure."
		6:
			return "Use barter and diplomacy-facing preparation to reposition the estate."
		7:
			return "Inspect warriors, weapons, armour, cloth, food and support before Flower Wars."
		8:
			return "Main Flower Wars hook: later this should be the strongest captive, loot and martial-prestige window."
		9:
			return "Expect rival or political pressure after the Flower War season."
		10:
			return "Check harvest gains and decide what can be stored, traded, offered or prepared for tribute."
		11:
			return "Use breathing room for Storehouse and Market decisions rather than mandatory festival spending."
		12:
			return "Great harvest hook: agricultural success should shape food reserves and Tlaloc favour."
		13:
			return "Prepare palace-facing legitimacy, trade value and diplomatic goods."
		14:
			return "Recover and prepare before the late Huitzilopochtli and Tezcatlipoca pressures."
		15:
			return "Review military strength and public martial standing."
		16:
			return "Use the final quiet window for repairs, trade balancing and reserve protection."
		17:
			return "Prepare for end-year plots, omens and risks before the closing ceremonies."
		18:
			return "Final ordinary Veintena: prepare for Nemontemi and annual review."
	return "Use this period to prepare for the next pressure."

func _on_calendar_card_pressed(report_id: String) -> void:
	selected_estate_report_id = report_id
	show_location("estate")

func _estate_report_title(report_id: String) -> String:
	if report_id.begins_with("calendar|"):
		var data: Dictionary = _calendar_report_data_from_id(report_id)
		if String(data.get("period", "veintena")) == "nemontemi":
			return "Nemontemi — Unlucky Days"
		var veintena_number: int = int(data.get("veintena", 1))
		return "Calendar: V" + str(veintena_number) + " — " + _calendar_god_for_veintena(veintena_number)
	return super._estate_report_title(report_id)

func _build_estate_report_detail_text(report_id: String) -> String:
	if report_id.begins_with("calendar|"):
		return _build_calendar_report_detail_text(report_id)
	return super._build_estate_report_detail_text(report_id)

func _calendar_report_data_from_id(report_id: String) -> Dictionary:
	var parts: PackedStringArray = report_id.split("|")
	var year_value: int = _ritual_year
	var period: String = "veintena"
	var veintena_number: int = _calendar_current_veintena()
	if parts.size() >= 4:
		year_value = int(parts[1])
		period = String(parts[2])
		veintena_number = int(parts[3])
	return {"year": year_value, "period": period, "veintena": veintena_number}

func _build_calendar_report_detail_text(report_id: String) -> String:
	var data: Dictionary = _calendar_report_data_from_id(report_id)
	var year_value: int = int(data.get("year", _ritual_year))
	var period: String = String(data.get("period", "veintena"))
	var veintena_number: int = int(data.get("veintena", 1))
	if period == "nemontemi":
		return _build_nemontemi_report_text(year_value)

	var god: String = _calendar_god_for_veintena(veintena_number)
	var text: String = "[b]Ritual Year " + str(year_value) + ", Veintena " + str(veintena_number) + "[/b]\n"
	text += "[b]Inspired name:[/b] " + _calendar_veintena_name(veintena_number) + "\n"
	text += "[b]Festival focus:[/b] " + god + "\n"
	text += "[b]Gameplay pressure:[/b] " + _calendar_pressure_for_veintena(veintena_number) + " — " + _calendar_detail_for_veintena(veintena_number) + "\n\n"
	text += _calendar_tooltip_for_veintena(veintena_number) + "\n\n"
	text += "[b]Player rhythm[/b]\n"
	text += "• " + _calendar_player_advice_for_veintena(veintena_number) + "\n"
	if god == "Minor / No major festival":
		text += "• This is intentionally a breathing-room Veintena: estate management, trade, construction, recovery, rival actions and small events can matter without mandatory major festival spending.\n"
	elif god == "Tlaloc":
		text += "• Tlaloc periods should centre agriculture, rain, lakes, harvest, drought protection and food security.\n"
	elif god == "Huitzilopochtli":
		text += "• Huitzilopochtli periods should centre warriors, Flower Wars, captives, sacrifice and martial prestige.\n"
	elif god == "Tezcatlipoca":
		text += "• Tezcatlipoca periods should centre omens, intrigue, ambition, manipulation and rival-house pressure.\n"
	elif god == "Quetzalcoatl":
		text += "• Quetzalcoatl periods should centre transitions, wisdom, trade, diplomacy, palace influence and legitimacy.\n"
	text += "\n[b]Prototype turn pipeline[/b]\n"
	text += "• Omens & Events: hook only for now.\n"
	text += "• World upkeep: population upkeep and housing maintenance resolve on Advance.\n"
	text += "• Production: staffed buildings consume inputs and add outputs on Advance.\n"
	text += "• Market / trade: player barter happens before Advance through the Market Trade Basket.\n"
	text += "• Rival AI: deliberately not active yet.\n"
	text += "• Flower Wars: later hook for captives, loot, losses and prestige, especially around V8 and V15.\n"
	text += "• Palace: later hook for demands, tribute and recognition pressure, especially around Quetzalcoatl and preparation windows.\n"
	text += "• Prestige: later hook for public comparison and year-end recognition.\n\n"
	if veintena_number == 18:
		text += "[color=#FFC25A][b]Next advance enters Nemontemi.[/b][/color] It no longer loops straight back to Veintena 1."
	else:
		text += "Next ordinary advance resolves this Veintena and moves to Veintena " + str(veintena_number + 1) + "."
	return text

func _build_nemontemi_report_text(year_value: int) -> String:
	var text: String = "[b]Nemontemi — Ritual Year " + str(year_value) + " Unlucky Days[/b]\n"
	text += "Nemontemi is the five-day end-of-year reckoning phase, not a nineteenth ordinary Veintena.\n\n"
	text += "[b]Prototype restrictions / hooks[/b]\n"
	text += "• No Flower Wars.\n"
	text += "• Construction and productivity can later be restricted or reduced here.\n"
	text += "• Market actions can later be limited to emergency or preparation choices.\n"
	text += "• Special omens and unique end-year events belong here.\n"
	text += "• Review previous-turn reports, shortages, prestige, rivals, palace pressure, offerings and Flower War results.\n\n"
	text += "Press [b]Resolve Nemontemi[/b] to begin Ritual Year " + str(year_value + 1) + " at Veintena 1."
	return text

func _on_advance_turn_pressed() -> void:
	var state: Node = _state()
	if state == null:
		return
	if _calendar_period == "nemontemi":
		_resolve_nemontemi(state)
		_refresh_all()
		return
	var current_veintena: int = _calendar_current_veintena()
	if current_veintena >= 18:
		_resolve_final_veintena_to_nemontemi(state)
		_refresh_all()
		return
	if state.has_method("advance_veintena"):
		state.call("advance_veintena")
	_refresh_all()

func _resolve_final_veintena_to_nemontemi(state: Node) -> void:
	if not bool(state.get("initialized")) and state.has_method("new_game"):
		state.call("new_game")
	state.set("current_veintena", 18)
	var report: Array = []
	state.set("last_report", report)
	report.append("Veintena 18 resolves.")
	report.append("Calendar Pacing v2: final ordinary Veintena enters Nemontemi instead of looping straight to Veintena 1.")
	if state.has_method("_pay_population_upkeep"):
		state.call("_pay_population_upkeep")
	if state.has_method("_pay_housing_maintenance"):
		state.call("_pay_housing_maintenance")
	if state.has_method("_operate_buildings"):
		state.call("_operate_buildings")
	report.append("Market/trade actions have already been handled by player choices before Advance.")
	report.append("Rival AI, Flower Wars, palace demands and prestige resolution are future pipeline hooks.")
	report.append("Now entering Nemontemi: annual reckoning for Ritual Year " + str(_ritual_year) + ".")
	state.set("last_report", report)
	_calendar_period = "nemontemi"
	_refresh_calendar_advance_button_label()
	if state.has_signal("turn_advanced"):
		state.emit_signal("turn_advanced", report)
	if state.has_signal("state_changed"):
		state.emit_signal("state_changed")

func _resolve_nemontemi(state: Node) -> void:
	var report: Array = []
	report.append("Nemontemi reckoning resolves for Ritual Year " + str(_ritual_year) + ".")
	report.append("Annual review hooks: prestige, palace recognition, rival comparison, Flower War results and offering history will be connected later.")
	_ritual_year += 1
	_calendar_period = "veintena"
	state.set("current_veintena", 1)
	report.append("Ritual Year " + str(_ritual_year) + " begins at Veintena 1.")
	state.set("last_report", report)
	_refresh_calendar_advance_button_label()
	if state.has_signal("turn_advanced"):
		state.emit_signal("turn_advanced", report)
	if state.has_signal("state_changed"):
		state.emit_signal("state_changed")

func _refresh_calendar_advance_button_label() -> void:
	if advance_turn_button == null:
		return
	if _calendar_period == "nemontemi":
		advance_turn_button.text = "Resolve Nemontemi"
	else:
		var current_veintena: int = _calendar_current_veintena()
		if current_veintena >= 18:
			advance_turn_button.text = "Enter Nemontemi"
		else:
			advance_turn_button.text = "Advance Veintena"
