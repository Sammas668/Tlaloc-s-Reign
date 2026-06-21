# GameScreenMarketOverviewPatch.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenMarketOverviewPatch.gd
#
# Active coordinator over GameScreen.gd.
# Keeps the current GameScreen implementation intact while routing major screen
# responsibilities to extracted controllers/widgets.
#
# Patch 8K2: this file should contain routing/compatibility bridges only.
# Market, Palace, Barracks, Shrine, Flower War widgets, doctrine rules,
# religion state and turn resolution all live outside this wrapper.
#
# -----------------------------------------------------------------------------
# ACTIVE WRAPPER BOUNDARY
# -----------------------------------------------------------------------------
# This file is the current active gameplay UI wrapper.
# It may coordinate screens, compose existing views, connect UI signals and call
# backend systems, but new gameplay rule logic should not be added here.
#
# New rule logic belongs in res://Scripts/Systems/.
# New reusable UI panels/widgets belong in res://Scripts/ui/screens/ or
# res://Scripts/ui/widgets/.
#
# Keep future patches narrow: either wire UI to existing systems here, or extract
# self-contained UI pieces out of this wrapper. Do not make this file the
# permanent home for market, religion, palace, rival, warband or turn rules.
# -----------------------------------------------------------------------------
extends "res://Scripts/ui/GameScreen.gd"

const CALENDAR_PACING_CONTROLLER_SCRIPT: Script = preload("res://Scripts/ui/widgets/CalendarPacingController.gd")
const UI_SCREEN_CONTEXT_SCRIPT: Script = preload("res://Scripts/ui/UIScreenContext.gd")
const MARKET_SCREEN_CONTROLLER_SCRIPT: Script = preload("res://Scripts/ui/screens/MarketScreenController.gd")
const SHRINE_SCREEN_CONTROLLER_SCRIPT: Script = preload("res://Scripts/ui/screens/ShrineScreenController.gd")
const PalacePresentationRules: Script = preload("res://Scripts/Systems/PalacePresentationRules.gd")
const BARRACKS_SCREEN_CONTROLLER_SCRIPT: Script = preload("res://Scripts/ui/screens/BarracksScreenController.gd")
const PALACE_SCREEN_CONTROLLER_SCRIPT: Script = preload("res://Scripts/ui/screens/PalaceScreenController.gd")

@export_group("Shrine Tab Art")
@export var shrine_overview_art: Texture2D
@export var shrine_tlaloc_art: Texture2D
@export var shrine_huitzilopochtli_art: Texture2D
@export var shrine_tezcatlipoca_art: Texture2D
@export var shrine_quetzalcoatl_art: Texture2D
@export var shrine_offerings_art: Texture2D



var _optional_shrine_art_cache: Dictionary = {}

var _selected_palace_route_id: String = ""
var _pending_palace_dedication_confirm_id: String = ""
var _calendar_pacing_controller: RefCounted = null
var _market_screen_controller: RefCounted = null
var _shrine_screen_controller: RefCounted = null
var _barracks_screen_controller: RefCounted = null
var _palace_screen_controller: RefCounted = null


func _make_ui_screen_context() -> RefCounted:
	var context: RefCounted = UI_SCREEN_CONTEXT_SCRIPT.new() as RefCounted
	if context != null and context.has_method("setup"):
		context.call("setup", self, content_root, content_text, dynamic_view_host, notification_list)
	return context


func _ready() -> void:
	_remove_shrine_offerings_focus()
	_add_barracks_warbands_focus()
	_setup_palace_navigation_probe()
	super._ready()

func _add_barracks_warbands_focus() -> void:
	# Ensure the base screen profile exposes the extracted Barracks/Warbands screen.
	# Warband behaviour itself lives in BarracksScreenController and WarbandSystem.
	if not _screen_profiles.has("warriors"):
		return
	var profile: Dictionary = _screen_profiles["warriors"] as Dictionary
	var focuses: Array = profile.get("focuses", []) as Array
	for focus_variant: Variant in focuses:
		if focus_variant is Dictionary and String((focus_variant as Dictionary).get("id", "")) == "warbands":
			return
	var output: Array = []
	var inserted: bool = false
	for focus_variant: Variant in focuses:
		output.append(focus_variant)
		if focus_variant is Dictionary and String((focus_variant as Dictionary).get("id", "")) == "overview":
			output.append({"id": "warbands", "label": "Warbands"})
			inserted = true
	if not inserted:
		output.append({"id": "warbands", "label": "Warbands"})
	profile["focuses"] = output
	_screen_profiles["warriors"] = profile

func _setup_palace_navigation_probe() -> void:
	# Ensure the base screen profile exposes the extracted Palace controller tabs.
	# Palace behaviour itself lives in PalaceScreenController / PalaceSystem.
	var profile: Dictionary = {}
	if _screen_profiles.has("palace"):
		profile = (_screen_profiles["palace"] as Dictionary).duplicate(true)
	profile["title"] = "Palace"
	profile["report_title"] = "Palace Reports"
	profile["body"] = "The Palace is the estate's political and divine centre. The Divine Seat is a ceremonial dedication hall: choose one route, then view that god's palace structure construction data."
	profile["focuses"] = [
		{"id": "overview", "label": "Overview"},
		{"id": "prestige", "label": "Prestige"},
		{"id": "divine_seat", "label": "Divine Seat"},
		{"id": "authority", "label": "Authority"},
		{"id": "ruler_demands", "label": "Court Needs"}
	]
	profile["reports"] = []
	_screen_profiles["palace"] = profile

func _remove_shrine_offerings_focus() -> void:
	# Offerings are now handled inside each god's Ritual Tiers panel, not as a
	# separate top Shrine tab. This mutates the inherited screen profile before
	# the base GameScreen builds the top focus row.
	if not _screen_profiles.has("shrines"):
		return
	var shrine_profile: Dictionary = _screen_profiles["shrines"] as Dictionary
	var focuses: Array = shrine_profile.get("focuses", []) as Array
	var filtered: Array = []
	for focus_variant: Variant in focuses:
		if focus_variant is Dictionary:
			var focus: Dictionary = focus_variant as Dictionary
			if String(focus.get("id", "")) == "offerings":
				continue
		filtered.append(focus_variant)
	shrine_profile["focuses"] = filtered
	_screen_profiles["shrines"] = shrine_profile

# -----------------------------------------------------------------------------
# Shrine background art
# -----------------------------------------------------------------------------

func _art_for_location(location_id: String) -> Texture2D:
	if location_id == "shrines":
		return _art_for_shrine_focus(_current_focus_id())
	return super._art_for_location(location_id)

func _art_for_shrine_focus(focus_id: String) -> Texture2D:
	match focus_id:
		"tlaloc":
			return _first_texture([shrine_tlaloc_art, _optional_shrine_art([
				"res://Assets/main_menu/Tlaloc Shrine.png",
				"res://Assets/main_menu/Tlaloc.png",
				"res://Assets/main_menu/Shrine_Tlaloc.png",
				"res://Assets/main_menu/Tlaloc shrine.png"
			])])
		"huitzilopochtli":
			return _first_texture([shrine_huitzilopochtli_art, _optional_shrine_art([
				"res://Assets/main_menu/Huitzilopochtli Shrine.png",
				"res://Assets/main_menu/Huitzilopochtli.png",
				"res://Assets/main_menu/Shrine_Huitzilopochtli.png",
				"res://Assets/main_menu/War Shrine.png"
			])])
		"tezcatlipoca":
			return _first_texture([shrine_tezcatlipoca_art, _optional_shrine_art([
				"res://Assets/main_menu/Tezcatlipoca Shrine.png",
				"res://Assets/main_menu/Tezcatlipoca.png",
				"res://Assets/main_menu/Shrine_Tezcatlipoca.png",
				"res://Assets/main_menu/Night Shrine.png"
			])])
		"quetzalcoatl":
			return _first_texture([shrine_quetzalcoatl_art, _optional_shrine_art([
				"res://Assets/main_menu/Quetzalcoatl Shrine.png",
				"res://Assets/main_menu/Quetzalcoatl.png",
				"res://Assets/main_menu/Shrine_Quetzalcoatl.png",
				"res://Assets/main_menu/Feathered Serpent Shrine.png"
			])])
		"offerings":
			var festival_god: String = _current_festival_god_id()
			if shrine_offerings_art != null:
				return shrine_offerings_art
			var offerings_art: Texture2D = _optional_shrine_art([
				"res://Assets/main_menu/Shrine Offerings.png",
				"res://Assets/main_menu/Offerings.png",
				"res://Assets/main_menu/Ritual Offerings.png"
			])
			if offerings_art != null:
				return offerings_art
			if festival_god != "":
				return _art_for_shrine_focus(festival_god)
		_:
			pass
	return _first_texture([shrine_overview_art, _optional_shrine_art([
		"res://Assets/main_menu/Shrine Overview.png",
		"res://Assets/main_menu/Shrines Overview.png",
		"res://Assets/main_menu/Shrines.png"
	]), shrines_art])

func _first_texture(textures: Array) -> Texture2D:
	for texture_variant: Variant in textures:
		if texture_variant is Texture2D:
			return texture_variant as Texture2D
	return null

func _optional_shrine_art(paths: Array[String]) -> Texture2D:
	var cache_key: String = "|".join(paths)
	if _optional_shrine_art_cache.has(cache_key):
		return _optional_shrine_art_cache[cache_key] as Texture2D
	for path: String in paths:
		if ResourceLoader.exists(path):
			var loaded: Resource = load(path)
			if loaded is Texture2D:
				_optional_shrine_art_cache[cache_key] = loaded
				return loaded as Texture2D
	_optional_shrine_art_cache[cache_key] = null
	return null

# -----------------------------------------------------------------------------
# Main content intercepts
# -----------------------------------------------------------------------------

func show_location(location_id: String) -> void:
	if location_id == "shrines" and current_location_id != "shrines":
		_reset_shrine_panel_selection()
	if location_id != "warriors":
		_reset_barracks_skill_web_selection()
	super.show_location(location_id)

func show_focus(location_id: String, focus_id: String) -> void:
	if location_id == "shrines":
		# The old Offerings tab has been removed; rituals now live inside each
		# god's Ritual Tiers panel. Redirect any stale/manual reference safely.
		if focus_id == "offerings":
			focus_id = "overview"
		_reset_shrine_panel_selection()
	if location_id == "warriors" and focus_id != "warbands":
		_reset_barracks_skill_web_selection()
	if location_id == "palace" and focus_id != "divine_seat":
		_selected_palace_route_id = ""
		_pending_palace_dedication_confirm_id = ""
		if _palace_screen_controller != null and _palace_screen_controller.has_method("reset_divine_seat_selection"):
			_palace_screen_controller.call("reset_divine_seat_selection")
	super.show_focus(location_id, focus_id)

func _refresh_main_content() -> void:
	if current_location_id == "shrines":
		_clear_dynamic_views()
		if location_title:
			location_title.text = "Shrines"
		if location_art:
			location_art.texture = _art_for_location(current_location_id)
		_show_shrine_content()
		return
	if current_location_id == "warriors":
		_clear_dynamic_views()
		if location_title:
			location_title.text = "Barracks"
		if location_art:
			location_art.texture = _art_for_location(current_location_id)
		_show_barracks_content()
		return
	if current_location_id == "palace":
		_clear_dynamic_views()
		if location_title:
			location_title.text = "Palace"
		if location_art:
			location_art.texture = _art_for_location(current_location_id)
		_show_palace_content()
		return
	super._refresh_main_content()

func _refresh_house_claim() -> void:
	# The persistent corner/claim panel belongs in the Palace area,
	# not on every screen. Estate Overview has its own compact Prestige summary
	# in the normal report list.
	if current_location_id != "palace":
		if house_claim_panel:
			house_claim_panel.visible = false
		return
	if house_claim_panel:
		house_claim_panel.visible = true
	var state: Node = _state()
	var prestige: Dictionary = {}
	if state != null and state.has_method("get_prestige_summary"):
		prestige = state.call("get_prestige_summary") as Dictionary
	var player_value: float = float(prestige.get("player_prestige", 0.0))
	var player_rank: Dictionary = prestige.get("player_rank", {}) as Dictionary
	var rank_number: int = int(player_rank.get("rank", 0))
	if prestige_glyph_label:
		prestige_glyph_label.text = "PRE"
	if prestige_title_label:
		prestige_title_label.text = "Prestige Standing"
	if prestige_value_label:
		prestige_value_label.text = _format_religion_amount(player_value) + " Prestige"
	if prestige_standing_label:
		var rank_text: String = "Rank pending"
		if rank_number > 0:
			rank_text = _ordinal_number(rank_number) + " of 4 houses"
		prestige_standing_label.text = rank_text
	if prestige_recognition_label:
		prestige_recognition_label.text = "Main score. Never spent."
	if prestige_recent_label:
		var recent: Array = prestige.get("recent_history", []) as Array
		if recent.is_empty():
			prestige_recent_label.text = "No prestige gains recorded yet."
		else:
			var last_record: Dictionary = recent[0] as Dictionary
			var amount: float = float(last_record.get("amount", 0.0))
			prestige_recent_label.text = "Recent: " + ("+" if amount >= 0.0 else "") + _format_religion_amount(amount) + " — " + String(last_record.get("detail", "Prestige changed"))

func _ordinal_number(value: int) -> String:
	return PalacePresentationRules.ordinal_number(value)

func _refresh_right_panel() -> void:
	_clear_children(notification_list)
	var profile: Dictionary = _profile(current_location_id)
	if notification_title:
		notification_title.text = _report_title_for_current_focus(profile)

	_refresh_house_claim()

	if current_location_id == "shrines":
		_build_shrine_reports()
		return
	if current_location_id == "warriors":
		_build_barracks_reports()
		return
	if current_location_id == "palace":
		_build_palace_navigation_probe_reports()
		return

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

func _report_title_for_current_focus(profile: Dictionary) -> String:
	if current_location_id == "shrines":
		match _current_focus_id():
			"overview":
				return "Divine Favour"
			"tlaloc":
				return "Tlaloc Reports"
			"huitzilopochtli":
				return "Huitzilopochtli Reports"
			"tezcatlipoca":
				return "Tezcatlipoca Reports"
			"quetzalcoatl":
				return "Quetzalcoatl Reports"
		return "Shrine Reports"
	if current_location_id == "palace":
		match _current_focus_id():
			"overview":
				return "Palace Overview"
			"prestige":
				return "Prestige"
			"divine_seat":
				return "Divine Seat"
			"authority":
				return "Palace Authority"
			"ruler_demands":
				return "Court Needs"
		return "Palace Reports"
	if current_location_id == "warriors":
		match _current_focus_id():
			"overview":
				return "Barracks Overview"
			"warbands":
				return "Warbands"
			"warriors":
				return "Warrior Status"
			"weapons":
				return "Weapons & Supplies"
			"flower_wars":
				return "Flower Wars"
			"returns":
				return "War Returns"
		return "Barracks Reports"
	return super._report_title_for_current_focus(profile)


# -----------------------------------------------------------------------------
# Palace UI bridge — extracted controller
# -----------------------------------------------------------------------------

func _palace_controller() -> RefCounted:
	if _palace_screen_controller == null:
		_palace_screen_controller = PALACE_SCREEN_CONTROLLER_SCRIPT.new()
	return _palace_screen_controller

func _show_palace_content() -> void:
	_palace_controller().call("show_palace_content_with_context", _make_ui_screen_context())

# -----------------------------------------------------------------------------
# Palace report bridge
# -----------------------------------------------------------------------------

func _build_palace_navigation_probe_reports() -> void:
	_palace_controller().call("build_palace_navigation_probe_reports_with_context", _make_ui_screen_context())

# -----------------------------------------------------------------------------
# Market / Trade Basket UI bridge — extracted controller
# -----------------------------------------------------------------------------

func _market_controller() -> RefCounted:
	if _market_screen_controller == null:
		_market_screen_controller = MARKET_SCREEN_CONTROLLER_SCRIPT.new() as RefCounted
	return _market_screen_controller

func _show_market_view() -> void:
	_market_controller().call("show_market_view_with_context", _make_ui_screen_context())

func _build_market_overview() -> void:
	_market_controller().call("build_market_overview_with_context", _make_ui_screen_context())

func _build_market_trade_summary() -> void:
	_market_controller().call("build_market_trade_summary_with_context", _make_ui_screen_context())

func _build_market_rivals_summary() -> void:
	_market_controller().call("build_market_rivals_summary_with_context", _make_ui_screen_context())

# -----------------------------------------------------------------------------
# Shrine / Religion UI bridge — extracted controller
# -----------------------------------------------------------------------------

func _shrine_controller() -> RefCounted:
	if _shrine_screen_controller == null:
		_shrine_screen_controller = SHRINE_SCREEN_CONTROLLER_SCRIPT.new() as RefCounted
	return _shrine_screen_controller

func _reset_shrine_panel_selection() -> void:
	_shrine_controller().call("reset_panel_selection")

func _show_shrine_content() -> void:
	_shrine_controller().call("show_content_with_context", _make_ui_screen_context())

func _build_shrine_reports() -> void:
	_shrine_controller().call("build_reports_with_context", _make_ui_screen_context())

func _current_festival_god_id() -> String:
	return String(_shrine_controller().call("current_festival_god_id_with_context", _make_ui_screen_context()))

func _current_festival_text() -> String:
	return String(_shrine_controller().call("current_festival_text_with_context", _make_ui_screen_context()))

func _format_religion_amount(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

# -----------------------------------------------------------------------------
# Barracks / Flower Wars UI bridge — extracted controller
# -----------------------------------------------------------------------------

func _barracks_controller() -> RefCounted:
	if _barracks_screen_controller == null:
		_barracks_screen_controller = BARRACKS_SCREEN_CONTROLLER_SCRIPT.new() as RefCounted
	return _barracks_screen_controller

func _reset_barracks_skill_web_selection() -> void:
	_barracks_controller().call("reset_skill_web_selection")

func _show_barracks_content() -> void:
	_barracks_controller().call("show_content_with_context", _make_ui_screen_context())

func _build_barracks_reports() -> void:
	_barracks_controller().call("build_reports_with_context", _make_ui_screen_context())

func _open_flower_war_attack_event(option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> void:
	_barracks_controller().call("open_attack_event_with_context", _make_ui_screen_context(), option_id, source_id, context)

func _open_flower_war_defence_event(option_id: String = "standard", source_id: String = "rival", context: Dictionary = {}) -> void:
	_barracks_controller().call("open_defence_event_with_context", _make_ui_screen_context(), option_id, source_id, context)

# -----------------------------------------------------------------------------
# Calendar Pacing v2 — extracted coordinator bridge
# -----------------------------------------------------------------------------

func _calendar_controller() -> RefCounted:
	if _calendar_pacing_controller == null:
		_calendar_pacing_controller = CALENDAR_PACING_CONTROLLER_SCRIPT.new() as RefCounted
	return _calendar_pacing_controller

func _build_calendar_row() -> void:
	_calendar_controller().call("build_calendar_row", self, top_row, visible_veintenas)

func _calendar_card_style(card_data: Dictionary, hover: bool) -> StyleBoxFlat:
	var raw: Variant = _calendar_controller().call("calendar_card_style", self, card_data, hover)
	if raw is StyleBoxFlat:
		return raw as StyleBoxFlat
	var fallback: StyleBoxFlat = StyleBoxFlat.new()
	fallback.bg_color = Color(0.055, 0.08, 0.075, 0.92)
	fallback.border_color = Color(0.56, 0.62, 0.58, 0.58)
	fallback.set_border_width_all(1)
	fallback.set_corner_radius_all(10)
	return fallback

func _calendar_colour_for_god(god: String) -> Color:
	return _calendar_controller().call("calendar_colour_for_god", god) as Color

func _calendar_card_data(current_veintena: int, offset: int) -> Dictionary:
	return _calendar_controller().call("calendar_card_data", self, current_veintena, offset) as Dictionary

func _nemontemi_card_data(year_value: int, current: bool) -> Dictionary:
	return _calendar_controller().call("nemontemi_card_data", year_value, current) as Dictionary

func _calendar_current_veintena() -> int:
	return int(_calendar_controller().call("calendar_current_veintena", self))

func _calendar_veintena_name(veintena_number: int) -> String:
	return String(_calendar_controller().call("calendar_veintena_name", self, veintena_number))

func _calendar_god_for_veintena(veintena_number: int) -> String:
	return String(_calendar_controller().call("calendar_god_for_veintena", veintena_number))

func _calendar_detail_for_veintena(veintena_number: int) -> String:
	return String(_calendar_controller().call("calendar_detail_for_veintena", veintena_number))

func _calendar_tooltip_for_veintena(veintena_number: int) -> String:
	return String(_calendar_controller().call("calendar_tooltip_for_veintena", veintena_number))

func _on_calendar_card_pressed(report_id: String) -> void:
	selected_estate_report_id = report_id
	show_location("estate")

func _build_estate_reports() -> void:
	# Estate report bar keeps clickable report cards, while Prestige
	# is shown as a fixed summary card at the bottom rather than a pop-out report.
	super._build_estate_reports()
	_add_estate_prestige_bottom_card()

func _add_estate_prestige_bottom_card() -> void:
	if notification_list == null:
		return
	var state: Node = _state()
	var prestige: Dictionary = {}
	if state != null and state.has_method("get_prestige_summary"):
		prestige = state.call("get_prestige_summary") as Dictionary
	var player_value: float = float(prestige.get("player_prestige", 0.0))
	var player_rank: Dictionary = prestige.get("player_rank", {}) as Dictionary
	var rank_number: int = int(player_rank.get("rank", 0))
	var leaderboard: Array = prestige.get("leaderboard", []) as Array
	var rank_text: String = "Rank pending"
	if rank_number > 0:
		rank_text = _ordinal_number(rank_number) + " of " + str(max(1, leaderboard.size())) + " houses"
	var recent_text: String = "No prestige gains recorded yet."
	var recent: Array = prestige.get("recent_history", []) as Array
	if not recent.is_empty() and recent[0] is Dictionary:
		var last_record: Dictionary = recent[0] as Dictionary
		var amount: float = float(last_record.get("amount", 0.0))
		recent_text = "Recent: " + ("+" if amount >= 0.0 else "") + _format_religion_amount(amount) + " — " + String(last_record.get("detail", "Prestige changed"))

	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.050, 0.047, 0.96), Color(0.76, 0.63, 0.32, 0.72), 10))
	notification_list.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	margin.add_child(stack)

	var title: Label = Label.new()
	title.text = "Prestige Standing"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.62, 1.0))
	stack.add_child(title)

	var value_label: Label = Label.new()
	value_label.text = _format_religion_amount(player_value) + " Prestige  •  " + rank_text
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.add_theme_color_override("font_color", Color(0.90, 0.88, 0.78, 1.0))
	value_label.clip_text = true
	stack.add_child(value_label)

	var note: Label = Label.new()
	note.text = recent_text
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.72, 0.78, 0.72, 1.0))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(note)

	panel.tooltip_text = "Prestige is the main score of the game. It is never spent."

func _add_prestige_estate_score_card() -> void:
	# Compact score summary used by Estate Overview and Palace reports.
	# Prestige is still not a persistent corner panel outside Palace.
	var state: Node = _state()
	if state == null or not state.has_method("get_prestige_summary"):
		_add_notification("Prestige: backend score data is not connected yet.")
		return
	var prestige: Dictionary = state.call("get_prestige_summary") as Dictionary
	var player_value: float = float(prestige.get("player_prestige", 0.0))
	var player_rank: Dictionary = prestige.get("player_rank", {}) as Dictionary
	var rank_number: int = int(player_rank.get("rank", 0))
	var leaderboard: Array = prestige.get("leaderboard", []) as Array
	var rank_text: String = "Rank pending"
	if rank_number > 0:
		rank_text = _ordinal_number(rank_number) + " of " + str(leaderboard.size()) + " houses"
	_add_notification("Prestige — Main Score: " + _format_religion_amount(player_value) + ". Standing: " + rank_text + ". Prestige is never spent.")
	var parts: Array[String] = []
	for row_variant: Variant in leaderboard:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		var label: String = str(int(row.get("rank", 0))) + ". " + String(row.get("name", "House")) + " " + _format_religion_amount(float(row.get("prestige", 0.0)))
		if bool(row.get("is_player", false)):
			label += " (you)"
		parts.append(label)
	_add_notification("Prestige leaderboard: " + "; ".join(parts) + ".")
	var recent: Array = prestige.get("recent_history", []) as Array
	if recent.is_empty():
		_add_notification("Prestige history: no gains or losses recorded yet. Court-need donations currently add Prestige by donated amount × base value.")
	else:
		var recent_parts: Array[String] = []
		var count: int = 0
		for item_variant: Variant in recent:
			if count >= 3:
				break
			if not (item_variant is Dictionary):
				continue
			var item: Dictionary = item_variant as Dictionary
			var amount: float = float(item.get("amount", 0.0))
			recent_parts.append(("+" if amount >= 0.0 else "") + _format_religion_amount(amount) + " " + String(item.get("detail", "Prestige changed")))
			count += 1
		_add_notification("Recent prestige: " + "; ".join(recent_parts) + ".")

func _add_palace_estate_probe_card() -> void:
	var state: Node = _state()
	if state == null or not state.has_method("get_palace_summary"):
		_add_notification("Palace: backend data is not connected yet.")
		return
	var summary: Dictionary = state.call("get_palace_summary") as Dictionary
	var dedicated: bool = bool(summary.get("dedicated", false))
	var dedication_name: String = String(summary.get("dedicated_god_name", "None"))
	var route_name: String = String(summary.get("route_name", "No dedication"))
	var power_summary: String = String(summary.get("power_summary", "No palace route has been chosen."))
	var palace_level: int = int(summary.get("palace_level", 1))
	var structure_count: int = int(summary.get("built_structure_count", 0))
	var authority_status: String = String(summary.get("authority_status", "No active palace authority mechanics are implemented yet."))
	var gate_status: String = String(summary.get("flower_war_gate_status", "Flower War palace gate not checked."))
	var title: String = "Palace — Dedication: " + dedication_name
	if not dedicated:
		title = "Palace — Dedication: None"
	_add_notification(title + ". Palace Level " + str(palace_level) + ". Built structures: " + str(structure_count) + ".")
	_add_notification("Palace route: " + route_name + ". " + power_summary)
	_add_notification("Palace status: " + authority_status + " Dedication and structure construction are handled on Palace → Divine Seat; maintenance and staff clarity are active, while court needs now accept donations for prestige.")
	_add_notification("Flower War authority check: " + gate_status)

func _estate_report_definitions() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	output.append({"id": "palace_status", "title": "Palace Status", "subtitle": _estate_report_subtitle("palace_status")})
	var base_reports: Array = super._estate_report_definitions()
	for report_variant: Variant in base_reports:
		if report_variant is Dictionary:
			output.append(report_variant as Dictionary)
	return output

func _estate_report_subtitle(report_id: String) -> String:
	match report_id:
		"palace_status":
			return _palace_estate_report_subtitle()
	return super._estate_report_subtitle(report_id)

func _estate_report_title(report_id: String) -> String:
	match report_id:
		"palace_status":
			return "Palace Status"
	if report_id.begins_with("calendar|"):
		var data: Dictionary = _calendar_report_data_from_id(report_id)
		if String(data.get("period", "veintena")) == "nemontemi":
			return "Nemontemi — Unlucky Days"
		var veintena_number: int = int(data.get("veintena", 1))
		return "Calendar: V" + str(veintena_number) + " — " + _calendar_god_for_veintena(veintena_number)
	return super._estate_report_title(report_id)

func _build_estate_report_detail_text(report_id: String) -> String:
	match report_id:
		"palace_status":
			return _build_palace_estate_report_detail_text()
	if report_id.begins_with("calendar|"):
		return _build_calendar_report_detail_text(report_id)
	return super._build_estate_report_detail_text(report_id)

func _prestige_estate_report_subtitle() -> String:
	var state: Node = _state()
	if state == null or not state.has_method("get_prestige_summary"):
		return "Prestige data not connected"
	var prestige: Dictionary = state.call("get_prestige_summary") as Dictionary
	var player_value: float = float(prestige.get("player_prestige", 0.0))
	var player_rank: Dictionary = prestige.get("player_rank", {}) as Dictionary
	var rank_number: int = int(player_rank.get("rank", 0))
	var leaderboard: Array = prestige.get("leaderboard", []) as Array
	if rank_number > 0:
		return _format_religion_amount(player_value) + " Prestige; " + _ordinal_number(rank_number) + " of " + str(leaderboard.size())
	return _format_religion_amount(player_value) + " Prestige; rank pending"

func _palace_estate_report_subtitle() -> String:
	var state: Node = _state()
	if state == null or not state.has_method("get_palace_summary"):
		return "Palace data not connected"
	var summary: Dictionary = state.call("get_palace_summary") as Dictionary
	var dedication_name: String = String(summary.get("dedicated_god_name", "None"))
	var palace_level: int = int(summary.get("palace_level", 1))
	var active_count: int = int(summary.get("active_structure_count", 0))
	var built_count: int = int(summary.get("built_structure_count", 0))
	return "Dedication: " + dedication_name + "; L" + str(palace_level) + "; active " + str(active_count) + " / built " + str(built_count)

func _build_prestige_estate_report_detail_text() -> String:
	var state: Node = _state()
	if state == null or not state.has_method("get_prestige_summary"):
		return "[b]Prestige Standing[/b]\nPrestige data is not connected yet."
	var prestige: Dictionary = state.call("get_prestige_summary") as Dictionary
	var player_value: float = float(prestige.get("player_prestige", 0.0))
	var player_rank: Dictionary = prestige.get("player_rank", {}) as Dictionary
	var rank_number: int = int(player_rank.get("rank", 0))
	var leaderboard: Array = prestige.get("leaderboard", []) as Array
	var text: String = "[b]Prestige Standing[/b]\n"
	text += "Prestige is the main score. It is never spent.\n\n"
	text += "• Player Prestige: " + _format_religion_amount(player_value) + "\n"
	if rank_number > 0:
		text += "• Current standing: " + _ordinal_number(rank_number) + " of " + str(leaderboard.size()) + " houses\n"
	else:
		text += "• Current standing: rank pending\n"
	text += "\n[b]Leaderboard[/b]\n"
	if leaderboard.is_empty():
		text += "• No leaderboard data connected yet.\n"
	else:
		for row_variant: Variant in leaderboard:
			if not (row_variant is Dictionary):
				continue
			var row: Dictionary = row_variant as Dictionary
			var line: String = "• " + str(int(row.get("rank", 0))) + ". " + String(row.get("name", "House")) + " — " + _format_religion_amount(float(row.get("prestige", 0.0)))
			if bool(row.get("is_player", false)):
				line += " (you)"
			if String(row.get("source", "")) == "placeholder":
				line += " [placeholder]"
			text += line + "\n"
	var recent: Array = prestige.get("recent_history", []) as Array
	text += "\n[b]Recent Prestige[/b]\n"
	if recent.is_empty():
		text += "• No prestige gains or losses recorded yet. Court-need donations currently add Prestige by donated amount × base value.\n"
	else:
		var count: int = 0
		for item_variant: Variant in recent:
			if count >= 5:
				break
			if not (item_variant is Dictionary):
				continue
			var item: Dictionary = item_variant as Dictionary
			var amount: float = float(item.get("amount", 0.0))
			text += "• " + ("+" if amount >= 0.0 else "") + _format_religion_amount(amount) + " — " + String(item.get("detail", "Prestige changed")) + "\n"
			count += 1
	return text.strip_edges()

func _build_palace_estate_report_detail_text() -> String:
	var state: Node = _state()
	if state == null or not state.has_method("get_palace_summary"):
		return "[b]Palace Status[/b]\nPalace data is not connected yet."
	var summary: Dictionary = state.call("get_palace_summary") as Dictionary
	var dedicated: bool = bool(summary.get("dedicated", false))
	var dedication_name: String = String(summary.get("dedicated_god_name", "None"))
	var route_name: String = String(summary.get("route_name", "No dedication"))
	var power_summary: String = String(summary.get("power_summary", "No palace route has been chosen."))
	var palace_level: int = int(summary.get("palace_level", 1))
	var built_count: int = int(summary.get("built_structure_count", 0))
	var active_count: int = int(summary.get("active_structure_count", 0))
	var inactive_count: int = int(summary.get("inactive_structure_count", 0))
	var authority_status: String = String(summary.get("authority_status", "No active palace authority mechanics are implemented yet."))
	var gate_status: String = String(summary.get("flower_war_gate_status", "Flower War palace gate not checked."))
	var text: String = "[b]Palace Status[/b]\n"
	if dedicated:
		text += "• Dedication: " + dedication_name + "\n"
	else:
		text += "• Dedication: None\n"
	text += "• Palace Level: " + str(palace_level) + "\n"
	text += "• Route: " + route_name + "\n"
	text += "• Built structures: " + str(built_count) + "\n"
	text += "• Active structures: " + str(active_count) + "\n"
	text += "• Inactive structures: " + str(inactive_count) + "\n\n"
	text += "[b]Route Power[/b]\n"
	text += "• " + power_summary + "\n\n"
	text += "[b]Authority Status[/b]\n"
	text += "• " + authority_status + "\n\n"
	text += "[b]Flower War Authority[/b]\n"
	text += "• " + gate_status + "\n\n"
	text += "Use Palace → Divine Seat for dedication and palace structures, Palace → Authority for route effects, and Palace → Ruler Demands for court needs."
	return text.strip_edges()

func _calendar_report_data_from_id(report_id: String) -> Dictionary:
	return _calendar_controller().call("calendar_report_data_from_id", self, report_id) as Dictionary

func _build_calendar_report_detail_text(report_id: String) -> String:
	return String(_calendar_controller().call("build_calendar_report_detail_text", self, report_id))

func _build_nemontemi_report_text(year_value: int) -> String:
	return String(_calendar_controller().call("build_nemontemi_report_text", year_value))

# Turn Runtime Bridge
# -----------------------------------------------------------------------------
# The UI no longer owns Veintena/Nemontemi resolution. The advance
# button delegates to the runtime state, which delegates to TurnResolutionSystem.

func _on_advance_turn_pressed() -> void:
	var state: Node = _state()
	if state == null:
		return
	if state.has_method("advance_turn"):
		state.call("advance_turn")
	elif state.has_method("advance_veintena"):
		state.call("advance_veintena")
	else:
		push_warning("No runtime turn-advance method found on state.")
	_refresh_all()

func _refresh_calendar_advance_button_label() -> void:
	_calendar_controller().call("refresh_calendar_advance_button_label", self)
