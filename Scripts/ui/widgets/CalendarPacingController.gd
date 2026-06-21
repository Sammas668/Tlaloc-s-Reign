# CalendarPacingController.gd
# Godot 4.x
# Project path: res://Scripts/ui/widgets/CalendarPacingController.gd
#
# Extracted calendar strip, calendar report and advance-button label helper.
# The main GameScreenMarketOverviewPatch.gd remains the coordinator, but the
# bulky calendar-data/UI rules live here so the wrapper can keep shrinking.
# Reads calendar state through TRGameState/CampaignState runtime accessors instead
# of falling back to TRGameState compatibility mirror fields.
class_name CalendarPacingController
extends RefCounted

func build_calendar_row(host: Node, top_row: HBoxContainer, visible_veintenas: int) -> void:
	if host == null or top_row == null:
		return
	refresh_calendar_advance_button_label(host)
	var current_veintena: int = calendar_current_veintena(host)
	var cards_to_show: int = max(1, visible_veintenas)
	for offset: int in range(cards_to_show):
		var card_data: Dictionary = calendar_card_data(host, current_veintena, offset)
		var card_button: Button = Button.new()
		card_button.toggle_mode = false
		card_button.focus_mode = Control.FOCUS_NONE
		card_button.custom_minimum_size = Vector2(166, 112)
		card_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_button.text = String(card_data.get("button_text", "Calendar"))
		card_button.tooltip_text = String(card_data.get("tooltip", ""))
		card_button.add_theme_font_size_override("font_size", 15)
		card_button.add_theme_stylebox_override("normal", calendar_card_style(host, card_data, false))
		card_button.add_theme_stylebox_override("hover", calendar_card_style(host, card_data, true))
		card_button.add_theme_stylebox_override("pressed", calendar_card_style(host, card_data, true))
		var report_id: String = String(card_data.get("report_id", ""))
		card_button.pressed.connect(func() -> void:
			if host != null and host.has_method("_on_calendar_card_pressed"):
				host.call("_on_calendar_card_pressed", report_id)
		)
		top_row.add_child(card_button)

func calendar_card_style(host: Node, card_data: Dictionary, hover: bool) -> StyleBoxFlat:
	var is_current: bool = bool(card_data.get("current", false))
	var period: String = String(card_data.get("period", "veintena"))
	var god: String = String(card_data.get("god", "Minor / No major festival"))
	var base: Color = Color(0.055, 0.08, 0.075, 0.92)
	var border: Color = calendar_colour_for_god(god)
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
	return _make_panel_style(host, base, border, 10)

func calendar_colour_for_god(god: String) -> Color:
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

func calendar_card_data(host: Node, current_veintena: int, offset: int) -> Dictionary:
	var base_year: int = _ritual_year(host)
	var position: int = current_veintena + offset
	if _calendar_period(host) == "nemontemi":
		position = 19 + offset
	var year_value: int = base_year
	while position > 19:
		position -= 19
		year_value += 1
	if position == 19:
		return nemontemi_card_data(year_value, offset == 0)
	var veintena_number: int = clampi(position, 1, 18)
	var god: String = calendar_god_for_veintena(veintena_number)
	var detail: String = calendar_detail_for_veintena(veintena_number)
	var name: String = calendar_veintena_name(host, veintena_number)
	var current: bool = offset == 0 and _calendar_period(host) == "veintena"
	var prefix: String = "Upcoming"
	if current:
		prefix = "Current"
	var god_label: String = god
	if god == "Minor / No major festival":
		god_label = "Minor"
	var report_id: String = "calendar|" + str(year_value) + "|veintena|" + str(veintena_number)
	return {"period": "veintena", "year": year_value, "veintena": veintena_number, "name": name, "god": god, "detail": detail, "current": current, "report_id": report_id, "button_text": prefix + "\nY" + str(year_value) + " V" + str(veintena_number) + "\n" + god_label + "\n" + detail, "tooltip": "Ritual Year " + str(year_value) + ", Veintena " + str(veintena_number) + " — " + name + ". " + god + ": " + calendar_tooltip_for_veintena(veintena_number)}

func nemontemi_card_data(year_value: int, current: bool) -> Dictionary:
	var prefix: String = "Upcoming"
	if current:
		prefix = "Current"
	var report_id: String = "calendar|" + str(year_value) + "|nemontemi|0"
	return {"period": "nemontemi", "year": year_value, "veintena": 0, "name": "Nemontemi", "god": "Nemontemi", "detail": "Year review", "current": current, "report_id": report_id, "button_text": prefix + "\nY" + str(year_value) + "\nNemontemi\nUnlucky Days", "tooltip": "Nemontemi — five unlucky days, annual reckoning, restrictions, omens, review and next-year setup."}

func calendar_current_veintena(host: Node) -> int:
	var state: Node = _host_state(host)
	if state != null and state.has_method("get_current_veintena"):
		return clampi(int(state.call("get_current_veintena")), 1, 18)
	var snapshot: RefCounted = _campaign_snapshot(host)
	if snapshot != null and snapshot.has_method("get_current_veintena_value"):
		return clampi(int(snapshot.call("get_current_veintena_value")), 1, 18)
	return 1

func calendar_veintena_name(host: Node, veintena_number: int) -> String:
	var veintenas_variant: Variant = null
	if host != null:
		veintenas_variant = host.get("_veintenas")
	if veintenas_variant is Array:
		var veintenas: Array = veintenas_variant as Array
		var index: int = veintena_number - 1
		if index >= 0 and index < veintenas.size() and veintenas[index] is Dictionary:
			var data: Dictionary = veintenas[index] as Dictionary
			return String(data.get("name", "Veintena " + str(veintena_number)))
	return "Veintena " + str(veintena_number)

func calendar_god_for_veintena(veintena_number: int) -> String:
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

func calendar_detail_for_veintena(veintena_number: int) -> String:
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

func calendar_tooltip_for_veintena(veintena_number: int) -> String:
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
			return "Quetzalcoatl closes the ordinary year through transition, order, legitimacy and ceremonial donation."
	return "Calendar planning pressure."

func calendar_report_data_from_id(host: Node, report_id: String) -> Dictionary:
	var parts: PackedStringArray = report_id.split("|")
	var year_value: int = _ritual_year(host)
	var period: String = "veintena"
	var veintena_number: int = calendar_current_veintena(host)
	if parts.size() >= 4:
		year_value = int(parts[1])
		period = String(parts[2])
		veintena_number = int(parts[3])
	return {"year": year_value, "period": period, "veintena": veintena_number}

func build_calendar_report_detail_text(host: Node, report_id: String) -> String:
	var data: Dictionary = calendar_report_data_from_id(host, report_id)
	var year_value: int = int(data.get("year", _ritual_year(host)))
	var period: String = String(data.get("period", "veintena"))
	var veintena_number: int = int(data.get("veintena", 1))
	if period == "nemontemi":
		return build_nemontemi_report_text(year_value)
	var god: String = calendar_god_for_veintena(veintena_number)
	var text: String = "[b]Ritual Year " + str(year_value) + ", Veintena " + str(veintena_number) + "[/b]\n"
	text += "[b]Inspired name:[/b] " + calendar_veintena_name(host, veintena_number) + "\n"
	text += "[b]Festival focus:[/b] " + god + "\n"
	text += "[b]Gameplay pressure:[/b] " + calendar_detail_for_veintena(veintena_number) + "\n\n"
	text += calendar_tooltip_for_veintena(veintena_number) + "\n\n"
	text += "[b]Religion hook[/b]\n"
	if god == "Minor / No major festival":
		text += "• This is a breathing-room Veintena. No major god receives a festival visibility bonus.\n"
	elif god == "Tlaloc":
		text += "• Offerings to Tlaloc are especially visible this Veintena.\n"
	elif god == "Huitzilopochtli":
		text += "• Offerings to Huitzilopochtli are especially visible this Veintena.\n"
	elif god == "Tezcatlipoca":
		text += "• Offerings to Tezcatlipoca are especially visible this Veintena.\n"
	elif god == "Quetzalcoatl":
		text += "• Offerings to Quetzalcoatl are especially visible this Veintena.\n"
	text += "• Divine favour decays on Advance. Offerings are made through the Shrines screen.\n\n"
	text += "[b]Prototype turn pipeline[/b]\n"
	text += "• Omens & Events: hook only for now.\n"
	text += "• World upkeep: population upkeep and housing maintenance resolve on Advance.\n"
	text += "• Production: staffed buildings consume inputs and add outputs on Advance.\n"
	text += "• Religion: divine favour decays; offerings are player actions before Advance.\n"
	text += "• Market / trade: player barter happens before Advance through the Market Trade Basket.\n"
	text += "• Rival AI, Flower Wars, palace and prestige are future hooks.\n\n"
	if veintena_number == 18:
		text += "[color=#FFC25A][b]Next advance enters Nemontemi.[/b][/color]"
	else:
		text += "Next ordinary advance resolves this Veintena and moves to Veintena " + str(veintena_number + 1) + "."
	return text

func build_nemontemi_report_text(year_value: int) -> String:
	var text: String = "[b]Nemontemi — Ritual Year " + str(year_value) + " Unlucky Days[/b]\n"
	text += "Nemontemi is the five-day end-of-year reckoning phase, not a nineteenth ordinary Veintena.\n\n"
	text += "[b]Prototype restrictions / hooks[/b]\n"
	text += "• No Flower Wars.\n"
	text += "• Construction and productivity can later be restricted or reduced here.\n"
	text += "• Special omens and unique end-year events belong here.\n"
	text += "• Divine favour takes a sharper end-year decay when Nemontemi resolves.\n"
	text += "• Review previous-turn reports, shortages, prestige, rivals, palace pressure, offerings and Flower War results.\n\n"
	text += "Press [b]Resolve Nemontemi[/b] to begin Ritual Year " + str(year_value + 1) + " at Veintena 1."
	return text

func refresh_calendar_advance_button_label(host: Node) -> void:
	if host == null:
		return
	var button_variant: Variant = host.get("advance_turn_button")
	if not (button_variant is Button):
		return
	var advance_turn_button: Button = button_variant as Button
	if _calendar_period(host) == "nemontemi":
		advance_turn_button.text = "Resolve Nemontemi"
	else:
		var current_veintena: int = calendar_current_veintena(host)
		if current_veintena >= 18:
			advance_turn_button.text = "Enter Nemontemi"
		else:
			advance_turn_button.text = "Advance Veintena"

func _make_panel_style(host: Node, bg_colour: Color, border_colour: Color, radius: int = 10) -> StyleBoxFlat:
	if host != null and host.has_method("_make_panel_style"):
		var raw: Variant = host.call("_make_panel_style", bg_colour, border_colour, radius)
		if raw is StyleBoxFlat:
			return raw as StyleBoxFlat
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_colour
	style.border_color = border_colour
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

func _host_state(host: Node) -> Node:
	if host != null and host.has_method("_state"):
		var raw_state: Variant = host.call("_state")
		if raw_state is Node:
			return raw_state as Node
	return null

func _campaign_snapshot(host: Node) -> RefCounted:
	var state: Node = _host_state(host)
	if state != null and state.has_method("get_campaign_state_snapshot"):
		var snapshot_raw: Variant = state.call("get_campaign_state_snapshot")
		if snapshot_raw is RefCounted:
			return snapshot_raw as RefCounted
	if state != null and state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null

func _calendar_period(host: Node) -> String:
	var state: Node = _host_state(host)
	if state != null and state.has_method("get_calendar_period"):
		return String(state.call("get_calendar_period"))
	var snapshot: RefCounted = _campaign_snapshot(host)
	if snapshot != null and snapshot.has_method("get_calendar_period_value"):
		return String(snapshot.call("get_calendar_period_value"))
	return "veintena"

func _ritual_year(host: Node) -> int:
	var state: Node = _host_state(host)
	if state != null and state.has_method("get_ritual_year"):
		return max(1, int(state.call("get_ritual_year")))
	var snapshot: RefCounted = _campaign_snapshot(host)
	if snapshot != null and snapshot.has_method("get_ritual_year_value"):
		return max(1, int(snapshot.call("get_ritual_year_value")))
	return 1
