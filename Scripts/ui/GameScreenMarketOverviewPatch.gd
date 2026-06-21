# GameScreenMarketOverviewPatch.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenMarketOverviewPatch.gd
#
# Thin drop-in wrapper over GameScreen.gd.
# Keeps the current GameScreen implementation intact, while adding:
# - Market Overview / Trade Basket / Rival Procurement dashboard behaviour.
# - Safe gameplay-led Ritual Calendar strip and Nemontemi pacing.
# - Turn Resolution Pipeline v1 hooks.
# - Religion / Shrine Upgrades v2 with tiered rituals, random favour rolls, no separate Offerings tab, and overview-only global favour/priest cards.
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

const TRADE_BASKET_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/TradeBasketView.tscn")
const WARBAND_SKILL_WEB_CANVAS_SCRIPT: Script = preload("res://Scripts/ui/widgets/WarbandSkillWebCanvas.gd")
const FLOWER_WAR_EVENT_OVERLAY_SCRIPT: Script = preload("res://Scripts/ui/widgets/FlowerWarEventOverlay.gd")
const CALENDAR_PACING_CONTROLLER_SCRIPT: Script = preload("res://Scripts/ui/widgets/CalendarPacingController.gd")
const UI_SCREEN_CONTEXT_SCRIPT: Script = preload("res://Scripts/ui/UIScreenContext.gd")
const SHRINE_RITUAL_RULES_SCRIPT: Script = preload("res://Scripts/Systems/ShrineRitualRules.gd")
const RELIGION_STATE_SYSTEM_SCRIPT: Script = preload("res://Scripts/Systems/ReligionStateSystem.gd")
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


# Local UI colours for the religion/offering panels.
# These are declared here instead of relying on inherited theme constants so the
# wrapper compiles cleanly as a direct replacement patch.
const COLOR_TEXT: Color = Color(0.92, 0.88, 0.78, 1.0)
const COLOR_MUTED: Color = Color(0.70, 0.78, 0.74, 1.0)
const COLOR_TEAL: Color = Color(0.50, 0.92, 0.84, 1.0)

const RELIGION_STARTING_FAVOUR: float = 40.0
const RELIGION_NORMAL_DECAY: float = 2.0
const RELIGION_NEMONTEMI_DECAY: float = 4.0

const GOD_IDS: Array[String] = ["tlaloc", "huitzilopochtli", "tezcatlipoca", "quetzalcoatl"]
const OFFERING_RESOURCE_IDS: Array[String] = ["maize", "cacao", "ritual_goods", "fine_textiles", "captives"]

var _calendar_period: String = "veintena"
var _ritual_year: int = 1

var _optional_shrine_art_cache: Dictionary = {}

var _active_trade_basket_view: Control = null
var _trade_basket_savvy_preview_label: RichTextLabel = null
var _last_trade_basket_savvy_lines: Array = []
var _last_trade_basket_savvy_preview: Dictionary = {}
var _selected_palace_route_id: String = ""
var _pending_palace_dedication_confirm_id: String = ""
var _calendar_pacing_controller: RefCounted = null
var _shrine_screen_controller: RefCounted = null
var _barracks_screen_controller: RefCounted = null
var _palace_screen_controller: RefCounted = null


# Warband Skill Web canvas is now a standalone widget.
# Gameplay rules still live in backend systems; this wrapper only instantiates
# and wires the widget into the current Barracks screen.

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
	# Warbands belong inside the Barracks bottom/focus row. This is display-only:
	# it exposes the persistent roster backend without changing Flower War launch yet.
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
	# Palace v0.22: Divine Seat visual + structure node data.
	# Uses the existing base Palace button/profile, but the Divine Seat choice now
	# lives in the big middle-left DynamicViewHost instead of being buried in the
	# right-hand report list.
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
	# v0.37.3: The persistent corner/claim panel belongs in the Palace area,
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
# Palace main-view content v0.24
# -----------------------------------------------------------------------------
# Palace main-view content v0.24
# -----------------------------------------------------------------------------

func _palace_controller() -> RefCounted:
	if _palace_screen_controller == null:
		_palace_screen_controller = PALACE_SCREEN_CONTROLLER_SCRIPT.new()
	return _palace_screen_controller

func _show_palace_content() -> void:
	_palace_controller().call("show_palace_content_with_context", _make_ui_screen_context())

# -----------------------------------------------------------------------------
# Palace navigation probe v0.20.3
# -----------------------------------------------------------------------------

func _build_palace_navigation_probe_reports() -> void:
	_palace_controller().call("build_palace_navigation_probe_reports_with_context", _make_ui_screen_context())
# -----------------------------------------------------------------------------
# Market / Trade Basket patch
# -----------------------------------------------------------------------------

func _show_market_view() -> void:
	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false
	var market_focus: String = _current_focus_id()

	if market_focus == "trade":
		_show_trade_basket_view()
		return

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
	_active_trade_basket_view = trade_view
	_trade_basket_savvy_preview_label = null
	if trade_view.has_signal("trade_accepted"):
		trade_view.connect("trade_accepted", Callable(self, "_on_trade_basket_accepted"))
	if trade_view.has_signal("trade_changed"):
		trade_view.connect("trade_changed", Callable(self, "_on_trade_basket_changed"))
	if trade_view.has_method("setup"):
		trade_view.call("setup", _state())
	_ensure_trade_basket_savvy_preview_label()
	_capture_trade_basket_savvy_preview()
	_update_trade_basket_savvy_summary_display()

func _on_trade_basket_accepted() -> void:
	# TradeBasketView clears its internal plan before emitting trade_accepted, so the
	# last captured trade_changed preview is used to award Economic Prestige safely.
	var state: Node = _state()
	if state != null and state.has_method("record_savvy_trade_prestige") and not _last_trade_basket_savvy_lines.is_empty():
		state.call("record_savvy_trade_prestige", _last_trade_basket_savvy_lines, "Savvy market trade")
	_last_trade_basket_savvy_lines.clear()
	_last_trade_basket_savvy_preview.clear()
	_trade_basket_savvy_preview_label = null
	selected_market_good_id = ""
	_refresh_main_content()
	_refresh_right_panel()

func _on_trade_basket_changed() -> void:
	_capture_trade_basket_savvy_preview()
	_update_trade_basket_savvy_summary_display()
	_refresh_right_panel()

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
		var average_value: float = 0.0
		if _active_trade_basket_view.has_method("_trade_pricing"):
			var pricing_variant: Variant = _active_trade_basket_view.call("_trade_pricing", resource_id, amount)
			if pricing_variant is Dictionary:
				var pricing: Dictionary = pricing_variant as Dictionary
				average_value = float(pricing.get("average_value", 0.0))
		if average_value <= 0.001:
			var state_for_base: Node = _state()
			if state_for_base != null and state_for_base.has_method("get_market_goods"):
				for good_variant: Variant in (state_for_base.call("get_market_goods") as Array):
					if good_variant is Dictionary and String((good_variant as Dictionary).get("id", "")) == resource_id:
						average_value = float((good_variant as Dictionary).get("current_value", (good_variant as Dictionary).get("base_value", 1.0)))
						break
		_last_trade_basket_savvy_lines.append({"resource_id": resource_id, "amount": amount, "average_unit_value": average_value})
	var state: Node = _state()
	if state != null and state.has_method("get_savvy_trade_prestige_preview"):
		var preview_variant: Variant = state.call("get_savvy_trade_prestige_preview", _last_trade_basket_savvy_lines)
		if preview_variant is Dictionary:
			_last_trade_basket_savvy_preview = preview_variant as Dictionary

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
	_add_notification("Economic Prestige now comes from savvy trade only: selling above base value or buying below base value. No passive surplus, maize stockpile or production-output Prestige is granted.")
	if not _last_trade_basket_savvy_preview.is_empty():
		_add_notification(String(_last_trade_basket_savvy_preview.get("headline", "No savvy trade Prestige.")))
	var state: Node = _state()
	if state != null and state.has_method("get_economic_prestige_summary"):
		var economic: Dictionary = state.call("get_economic_prestige_summary") as Dictionary
		_add_notification("Savvy trade scale: " + _format_float(float(economic.get("scale", 0.25))) + " × value advantage. Recent savvy trades: " + str((economic.get("recent_savvy_trades", []) as Array).size()) + ".")
	_add_notification("Sell caps use Storehouse free stock after reserves. Buy caps use current market stock.")
	_add_notification("This connects Storehouse and Market directly without creating a currency resource.")

func _build_market_rivals_summary() -> void:
	var goods: Array[Dictionary] = _market_goods()
	if goods.is_empty():
		_add_notification("No market data is connected yet.")
		return
	_add_notification("Rival Procurement is a dashboard, not a duplicate goods ledger. Use it to read which goods each rival is likely to pressure once proper Rival AI is connected.")
	_add_notification(_rival_pressure_line("War Rival", ["obsidian", "weapons", "armour", "cloth", "tools", "captives"], goods, "Wants Flower War readiness, warrior equipment and captive-taking capacity."))
	_add_notification(_rival_pressure_line("Cunning Rival", ["tools", "cloth", "wood", "cacao", "cotton"], goods, "Wants practical bottlenecks, flexible build materials and market leverage."))
	_add_notification(_rival_pressure_line("Diplomatic Rival", ["cacao", "fine_textiles", "cloth", "cotton", "tools"], goods, "Wants palace-facing goods, legitimacy goods and tribute-ready luxury supply."))

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

func _apply_divine_favour_decay(report: Array, decay_amount: float = RELIGION_NORMAL_DECAY) -> void:
	_shrine_controller().call("apply_divine_favour_decay_with_context", _make_ui_screen_context(), report, decay_amount)

func _reset_religion_veintena_capacity() -> void:
	_shrine_controller().call("reset_religion_veintena_capacity_with_context", _make_ui_screen_context())

func _current_festival_god_id() -> String:
	return String(_shrine_controller().call("current_festival_god_id_with_context", _make_ui_screen_context()))

func _current_festival_text() -> String:
	return String(_shrine_controller().call("current_festival_text_with_context", _make_ui_screen_context()))

func _format_religion_amount(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _resource_display_name(resource_id: String) -> String:
	var state: Node = _state()
	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))
	return resource_id.replace("_", " ").capitalize()

func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "none"
	var parts: Array[String] = []
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		parts.append(_resource_display_name(resource_id) + " " + _format_religion_amount(float(cost[resource_variant])))
	return ", ".join(parts)

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
	# v0.37.6: Estate report bar keeps clickable report cards, while Prestige
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

# Turn Resolution Pipeline v1
# -----------------------------------------------------------------------------

func _on_advance_turn_pressed() -> void:
	var state: Node = _state()
	if state == null:
		return
	if _calendar_period == "nemontemi":
		_resolve_nemontemi(state)
		_refresh_all()
		return
	_resolve_ordinary_veintena(state)
	_refresh_all()

func _resolve_ordinary_veintena(state: Node) -> void:
	if not bool(state.get("initialized")) and state.has_method("new_game"):
		state.call("new_game")
	var current_veintena: int = _calendar_current_veintena()
	state.set("current_veintena", current_veintena)
	var report: Array = []
	state.set("last_report", report)
	report.append("Veintena " + str(current_veintena) + " resolves through the Turn Resolution Pipeline.")
	report.append("1. Omens & Events: placeholder only; no full event pool connected yet.")
	report.append("2. Population upkeep resolves.")
	if state.has_method("_pay_population_upkeep"):
		state.call("_pay_population_upkeep")
	report.append("3. Housing upkeep resolves.")
	if state.has_method("_pay_housing_maintenance"):
		state.call("_pay_housing_maintenance")
	report.append("4. Building input consumption and production resolve.")
	if state.has_method("_operate_buildings"):
		state.call("_operate_buildings")
	report.append("5. Market recalculation: market values refresh from current stock, demand and projected pressure after state change.")
	report.append("6. Calendar and religion: " + _current_festival_text() + ".")
	_apply_divine_favour_decay(report, RELIGION_NORMAL_DECAY)
	_reset_religion_veintena_capacity()
	report.append("7. Rival AI hook: not active yet.")
	report.append("8. Flower Wars hook: not active yet.")
	report.append("9. Palace hook: not active yet.")
	report.append("10. Prestige hook: not active yet.")
	if current_veintena >= 18:
		report.append("11. Report summary: final ordinary Veintena complete. Now entering Nemontemi for Ritual Year " + str(_ritual_year) + ".")
		_calendar_period = "nemontemi"
		state.set("current_veintena", 18)
	else:
		var next_veintena: int = current_veintena + 1
		report.append("11. Report summary: now entering Veintena " + str(next_veintena) + ".")
		state.set("current_veintena", next_veintena)
	state.set("last_report", report)
	_refresh_calendar_advance_button_label()
	if state.has_signal("turn_advanced"):
		state.emit_signal("turn_advanced", report)
	if state.has_signal("state_changed"):
		state.emit_signal("state_changed")

func _resolve_nemontemi(state: Node) -> void:
	var report: Array = []
	report.append("Nemontemi reckoning resolves for Ritual Year " + str(_ritual_year) + ".")
	report.append("Nemontemi restrictions hook: no Flower Wars; construction, market activity and productivity restrictions can be connected later.")
	_apply_divine_favour_decay(report, RELIGION_NEMONTEMI_DECAY)
	_reset_religion_veintena_capacity()
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
	_calendar_controller().call("refresh_calendar_advance_button_label", self)
