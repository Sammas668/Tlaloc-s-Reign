# GameScreen.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreen.gd
#
# Shared game shell with data-backed prototype systems:
# - Estate keeps the Veintena calendar.
# - Production combines Chinampas, Workshops and Labour in one bottom-bar department.
# - Storehouse and Market read from TRGameState instead of hard-coded UI placeholder data.
# - Bottom bar order locked: Estate | Production | Storehouse | Market | Housing | Shrines | Barracks | Palace | Rivals | Advance Veintena.
extends Control

const TR_GAME_STATE_SCRIPT: Script = preload("res://Scripts/autoload/TRGameState.gd")
const STOREHOUSE_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/StorehouseView.tscn")
const STOCKPILE_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/StockpileLedgerRow.tscn")
const MARKET_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/MarketView.tscn")
const MARKET_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/MarketLedgerRow.tscn")
const BUILDING_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/BuildingView.tscn")
const LABOUR_ASSIGNMENT_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/LabourAssignmentView.tscn")
const HOUSING_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/HousingView.tscn")
const BUILDING_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/BuildingLedgerRow.tscn")
const HOUSING_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/HousingLedgerRow.tscn")

@export_group("Main Screen Art")
@export var estate_art: Texture2D
@export var production_art: Texture2D
@export var storehouse_art: Texture2D
@export var market_art: Texture2D
@export var housing_art: Texture2D
@export var shrines_art: Texture2D
@export var barracks_art: Texture2D
@export var palace_art: Texture2D
@export var rivals_art: Texture2D

@export_group("Production Tab Art")
@export var production_overview_art: Texture2D
@export var production_chinampas_art: Texture2D
@export var production_workshops_art: Texture2D
@export var production_labour_art: Texture2D

@export_group("Housing Tab Art")
@export var housing_overview_art: Texture2D
@export var housing_commoners_art: Texture2D
@export var housing_tlacotin_art: Texture2D
@export var housing_warriors_art: Texture2D
@export var housing_priests_art: Texture2D
@export var housing_nobles_art: Texture2D
@export var housing_captives_art: Texture2D

@export_group("UI Emblems")
@export var prestige_emblem_art: Texture2D

@export_group("Legacy Art Fallbacks")
@export var chinampas_art: Texture2D
@export var fields_art: Texture2D # Backwards-compatible fallback if you already assigned art to the older Fields Art slot.
@export var workshops_art: Texture2D
@export var warriors_art: Texture2D

@export var visible_veintenas: int = 7

@onready var top_row: HBoxContainer = get_node_or_null(^"SafeArea/MainVBox/CalendarPanel/Margin/CardRow") as HBoxContainer
@onready var location_title: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/LocationTitle") as Label
@onready var location_art: TextureRect = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/LocationArt") as TextureRect
@onready var content_root: VBoxContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/ContentRoot") as VBoxContainer
@onready var content_text: RichTextLabel = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/ContentRoot/ContentText") as RichTextLabel
@onready var dynamic_view_host: VBoxContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/ContentRoot/DynamicViewHost") as VBoxContainer
@onready var notification_title: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/NotificationTitle") as Label
@onready var notification_list: VBoxContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/NotificationScroll/NotificationList") as VBoxContainer

@onready var house_claim_panel: PanelContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/HouseClaimPanel") as PanelContainer
@onready var prestige_emblem: TextureRect = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/HouseClaimPanel/Margin/ClaimRow/EmblemFrame/PrestigeEmblem") as TextureRect
@onready var prestige_glyph_label: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/HouseClaimPanel/Margin/ClaimRow/EmblemFrame/PrestigeGlyphLabel") as Label
@onready var prestige_title_label: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/HouseClaimPanel/Margin/ClaimRow/ClaimText/PrestigeTitleLabel") as Label
@onready var prestige_value_label: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/HouseClaimPanel/Margin/ClaimRow/ClaimText/PrestigeValueLabel") as Label
@onready var prestige_standing_label: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/HouseClaimPanel/Margin/ClaimRow/ClaimText/PrestigeStandingLabel") as Label
@onready var prestige_recognition_label: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/HouseClaimPanel/Margin/ClaimRow/ClaimText/PrestigeRecognitionLabel") as Label
@onready var prestige_recent_label: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/HouseClaimPanel/Margin/ClaimRow/ClaimText/PrestigeRecentLabel") as Label

@onready var estate_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/EstateButton") as Button
@onready var production_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/ProductionButton") as Button
@onready var storehouse_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/StorehouseButton") as Button
@onready var market_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/MarketButton") as Button
@onready var housing_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/HousingButton") as Button
@onready var shrines_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/ShrinesButton") as Button
@onready var warriors_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/WarriorsButton") as Button
@onready var palace_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/PalaceButton") as Button
@onready var rivals_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/RivalsButton") as Button
@onready var advance_turn_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/AdvanceTurnButton") as Button

var current_location_id: String = "estate"
var current_focus_by_location: Dictionary = {}
var selected_storehouse_good_id: String = ""
var selected_market_good_id: String = ""
var selected_production_report_id: String = ""
var selected_housing_building_id: String = ""
var selected_building_id_by_location: Dictionary = {}

var storehouse_view: Control = null
var market_view: Control = null
var building_view: Control = null
var labour_assignment_view: Control = null
var housing_view: Control = null
var _local_state: Node = null
var _state_connected: bool = false

var _veintenas: Array[Dictionary] = [
	{"name": "Atlcahualo", "type": "Rain", "detail": "Opening rains", "tooltip": "Opening rain signs and early Tlaloc pressure."},
	{"name": "Tlacaxipehualiztli", "type": "War", "detail": "War rites", "tooltip": "War rites, martial display and warrior preparation."},
	{"name": "Tozoztontli", "type": "Maize", "detail": "Fields", "tooltip": "Field labour, early maize stores and agricultural vigilance."},
	{"name": "Huey Tozoztli", "type": "Maize", "detail": "Great vigil", "tooltip": "Great agricultural vigil and major maize pressure."},
	{"name": "Toxcatl", "type": "Ritual", "detail": "Offering", "tooltip": "Ritual pressure, offerings and divine favour."},
	{"name": "Etzalcualiztli", "type": "Rain", "detail": "Tlaloc", "tooltip": "Tlaloc, water, rain and food-security pressure."},
	{"name": "Tecuilhuitontli", "type": "Palace", "detail": "Lords", "tooltip": "Noble status, palace attention and social obligation."},
	{"name": "Huey Tecuilhuitl", "type": "Palace", "detail": "Great lords", "tooltip": "Greater noble display, palace pressure and tribute preparation."},
	{"name": "Tlaxochimaco", "type": "Ritual", "detail": "Flowers", "tooltip": "Flowers, offerings and public ritual display."},
	{"name": "Xocotl Huetzi", "type": "Ritual", "detail": "Festival", "tooltip": "Festival pressure, public prestige and ritual display."},
	{"name": "Ochpaniztli", "type": "Stores", "detail": "Sweeping", "tooltip": "Sweeping, stores, obligations and preparation."},
	{"name": "Teotleco", "type": "Ritual", "detail": "Gods arrive", "tooltip": "The gods arrive; omens and divine pressure are prominent."},
	{"name": "Tepeilhuitl", "type": "Rain", "detail": "Mountains", "tooltip": "Mountains, water, rain and agricultural-risk pressure."},
	{"name": "Quecholli", "type": "War", "detail": "Muster", "tooltip": "Muster, hunting, warriors and military readiness."},
	{"name": "Panquetzaliztli", "type": "War", "detail": "Huitzilopochtli", "tooltip": "Huitzilopochtli, war, captives and martial prestige."},
	{"name": "Atemoztli", "type": "Rain", "detail": "Waters", "tooltip": "Water descent, late rain and drought warning pressure."},
	{"name": "Tititl", "type": "Warning", "detail": "Year-end", "tooltip": "Late-year strain, unresolved obligations and warning signs."},
	{"name": "Izcalli", "type": "Warning", "detail": "Reckoning", "tooltip": "Final renewal, reckoning and preparation for Nemontemi."}
]

var _screen_profiles: Dictionary = {
	"estate": {
		"title": "Estate Court",
		"top_mode": "calendar",
		"report_title": "House Warnings & Reports",
		"body": "The estate court is the whole-house planning screen. It keeps the Veintena calendar because this is where you read the year, review warnings and advance time.",
		"sections": [
			{"heading": "Estate overview", "lines": ["The top row shows the Veintena calendar.", "The right panel summarises the last turn and major warnings.", "Production now drives Storehouse totals through chinampas, workshops and labour.", "Use Advance Veintena to run upkeep, building inputs and building output."]}
		],
		"reports": []
	},
	"production": {
		"title": "Production",
		"special_view": "buildings",
		"building_screen": "production",
		"report_title": "Production Ledger",
		"body": "Production is where the estate turns land, labour and buildings into goods. The Overview tab is a dashboard: it summarises expected output, input bottlenecks, blocked buildings and productive labour pressure instead of repeating the Chinampas or Workshops ledgers.",
		"focuses": [
			{"id": "overview", "label": "Overview"},
			{"id": "chinampas", "label": "Chinampas"},
			{"id": "workshops", "label": "Workshops"},
			{"id": "labour", "label": "Labour"}
		],
		"sections": [
			{"heading": "Production dashboard", "lines": ["Expected output this Veintena from built production buildings.", "Input goods that production will consume.", "Buildings blocked by missing inputs, staffing or lack of construction.", "Labour pressure across chinampas and workshops."]}
		]
	},
	"storehouse": {
		"title": "Storehouse",
		"special_view": "storehouse",
		"report_title": "Stockpile Ledger",
		"focuses": [
			{"id": "overview", "label": "Overview"},
			{"id": "food", "label": "Food"},
			{"id": "raw", "label": "Raw"},
			{"id": "processed", "label": "Processed"},
			{"id": "luxury", "label": "Luxury"},
			{"id": "special", "label": "Special"}
		]
	},
	"market": {
		"title": "Marketplace",
		"special_view": "market",
		"report_title": "Market Ledger",
		"focuses": [
			{"id": "overview", "label": "Overview"},
			{"id": "prices", "label": "Prices"},
			{"id": "buy", "label": "Buy"},
			{"id": "sell", "label": "Sell"},
			{"id": "rivals", "label": "Rivals"},
			{"id": "reports", "label": "Reports"}
		]
	},
	"housing": {
		"title": "Housing",
		"special_view": "housing",
		"report_title": "Housing Ledger",
		"body": "Housing controls how many people the estate can support. Overview reads population pressure; each population tab builds small, medium and large housing for that group.",
		"focuses": [
			{"id": "overview", "label": "Overview"},
			{"id": "commoners", "label": "Commoners"},
			{"id": "tlacotin", "label": "Tlacotin"},
			{"id": "warriors", "label": "Warriors"},
			{"id": "priests", "label": "Priests"},
			{"id": "nobles", "label": "Nobles"},
			{"id": "captives", "label": "Captives"}
		]
	},
	"shrines": {"title": "Shrines", "report_title": "Omens & Priest Reports", "body": "Offerings to Tlaloc, Huitzilopochtli, Tezcatlipoca and Quetzalcoatl will be managed here.", "focuses": [{"id": "overview", "label": "Overview"}, {"id": "tlaloc", "label": "Tlaloc"}, {"id": "huitzilopochtli", "label": "Huitzilopochtli"}, {"id": "tezcatlipoca", "label": "Tezcatlipoca"}, {"id": "quetzalcoatl", "label": "Quetzalcoatl"}, {"id": "offerings", "label": "Offerings"}], "reports": ["Shrine systems are not connected yet.", "Offerings will later consume goods from the Storehouse."]},
	"warriors": {"title": "Barracks", "report_title": "Barracks Reports", "body": "Warriors, weapons and Flower Wars preparation will be managed here. The Barracks is the estate's military support screen.", "focuses": [{"id": "overview", "label": "Overview"}, {"id": "warriors", "label": "Warriors"}, {"id": "weapons", "label": "Weapons"}, {"id": "flower_wars", "label": "Flower Wars"}, {"id": "returns", "label": "Returns"}], "reports": ["Warrior systems are not connected yet.", "Weapons will come from the Workshop system."]},
	"palace": {"title": "Palace", "report_title": "Palace Messages", "body": "Tribute, royal favour and recognition pressure will be managed here.", "focuses": [{"id": "overview", "label": "Overview"}, {"id": "demand", "label": "Demand"}, {"id": "tribute", "label": "Tribute"}, {"id": "royal_favour", "label": "Royal Favour"}, {"id": "recognition", "label": "Recognition"}], "reports": ["Palace systems are not connected yet.", "Tribute will later reserve goods from the Storehouse."]},
	"rivals": {"title": "Rival Houses", "report_title": "Rival Reports", "body": "War Rival, Cunning Rival and Diplomatic Rival pressure will be shown here.", "focuses": [{"id": "overview", "label": "Overview"}, {"id": "war_rival", "label": "War Rival"}, {"id": "cunning_rival", "label": "Cunning Rival"}, {"id": "diplomatic_rival", "label": "Diplomatic Rival"}, {"id": "prestige", "label": "Prestige"}], "reports": ["Rival systems are not connected yet.", "Market procurement is the next natural hook."]}
}

func _ready() -> void:
	_connect_state()
	_wire_buttons()
	_apply_style()
	_apply_bottom_bar_labels()
	show_location("estate")

func _state() -> Node:
	var autoload_state: Node = get_node_or_null("/root/TRGameState")
	if autoload_state != null:
		return autoload_state
	if _local_state == null:
		_local_state = TR_GAME_STATE_SCRIPT.new() as Node
		add_child(_local_state)
		if _local_state.has_method("new_game"):
			_local_state.call("new_game")
	return _local_state

func _connect_state() -> void:
	if _state_connected:
		return
	var state: Node = _state()
	if state != null and state.has_signal("state_changed"):
		state.connect("state_changed", Callable(self, "_on_state_changed"))
	_state_connected = true

func _wire_buttons() -> void:
	if estate_button:
		estate_button.pressed.connect(func() -> void: show_location("estate"))
	if production_button:
		production_button.pressed.connect(func() -> void: show_location("production"))
	if storehouse_button:
		storehouse_button.pressed.connect(func() -> void: show_location("storehouse"))
	if market_button:
		market_button.pressed.connect(func() -> void: show_location("market"))
	if housing_button:
		housing_button.pressed.connect(func() -> void: show_location("housing"))
	if shrines_button:
		shrines_button.pressed.connect(func() -> void: show_location("shrines"))
	if warriors_button:
		warriors_button.pressed.connect(func() -> void: show_location("warriors"))
	if palace_button:
		palace_button.pressed.connect(func() -> void: show_location("palace"))
	if rivals_button:
		rivals_button.pressed.connect(func() -> void: show_location("rivals"))
	if advance_turn_button:
		advance_turn_button.pressed.connect(_on_advance_turn_pressed)

func _apply_bottom_bar_labels() -> void:
	if estate_button:
		estate_button.text = "Estate"
	if production_button:
		production_button.text = "Production"
	if storehouse_button:
		storehouse_button.text = "Storehouse"
	if market_button:
		market_button.text = "Market"
	if housing_button:
		housing_button.text = "Housing"
	if shrines_button:
		shrines_button.text = "Shrines"
	if warriors_button:
		warriors_button.text = "Barracks"
	if palace_button:
		palace_button.text = "Palace"
	if rivals_button:
		rivals_button.text = "Rivals"
	if advance_turn_button:
		advance_turn_button.text = "Advance Veintena"

func show_location(location_id: String) -> void:
	current_location_id = location_id
	_ensure_focus_for_location(location_id)
	_refresh_all()

func show_focus(location_id: String, focus_id: String) -> void:
	current_location_id = location_id
	current_focus_by_location[location_id] = focus_id
	if location_id == "storehouse":
		selected_storehouse_good_id = ""
	if location_id == "market":
		selected_market_good_id = ""
	if location_id == "production":
		selected_production_report_id = ""
		selected_building_id_by_location[location_id] = ""
	if location_id == "housing":
		selected_housing_building_id = ""
		selected_building_id_by_location[location_id] = ""
	_refresh_all()

func _refresh_all() -> void:
	_refresh_top_area()
	_refresh_main_content()
	_refresh_right_panel()
	_update_button_pressed_state()

func _ensure_focus_for_location(location_id: String) -> void:
	if current_focus_by_location.has(location_id):
		return
	current_focus_by_location[location_id] = "overview"

func _current_focus_id() -> String:
	return String(current_focus_by_location.get(current_location_id, "overview"))

func _profile(location_id: String) -> Dictionary:
	if _screen_profiles.has(location_id):
		return _screen_profiles[location_id] as Dictionary
	return _screen_profiles["estate"] as Dictionary

func _refresh_top_area() -> void:
	if top_row == null:
		return
	_clear_children(top_row)
	var profile: Dictionary = _profile(current_location_id)
	if String(profile.get("top_mode", "focus")) == "calendar":
		_build_calendar_row()
	else:
		_build_focus_row(profile)

func _build_calendar_row() -> void:
	var state: Node = _state()
	var current_veintena: int = 1
	if state != null and state.has_method("get_current_veintena"):
		current_veintena = int(state.call("get_current_veintena"))
	var start_index: int = clampi(current_veintena - 1, 0, _veintenas.size() - 1)
	var end_index: int = mini(start_index + visible_veintenas, _veintenas.size())
	for i: int in range(start_index, end_index):
		var card_data: Dictionary = _veintenas[i] as Dictionary
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(166, 106)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = "Veintena " + str(i + 1) + " — " + String(card_data.get("name", "")) + ". " + String(card_data.get("tooltip", ""))
		var style: StyleBoxFlat = _make_panel_style(Color(0.055, 0.08, 0.075, 0.92), Color(0.33, 0.70, 0.62, 0.55), 10)
		if i == start_index:
			style = _make_panel_style(Color(0.09, 0.13, 0.115, 0.98), Color(0.76, 0.63, 0.32, 0.85), 10)
		card.add_theme_stylebox_override("panel", style)
		var margin: MarginContainer = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_top", 7)
		margin.add_theme_constant_override("margin_bottom", 7)
		card.add_child(margin)
		var stack: VBoxContainer = VBoxContainer.new()
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		margin.add_child(stack)
		_add_center_label(stack, "Veintena " + str(i + 1), 17)
		_add_center_label(stack, String(card_data.get("name", "")), 15)
		_add_center_label(stack, String(card_data.get("type", "")), 17)
		_add_center_label(stack, String(card_data.get("detail", "")), 15)
		top_row.add_child(card)

func _build_focus_row(profile: Dictionary) -> void:
	var focuses: Array = profile.get("focuses", []) as Array
	if focuses.is_empty():
		return
	var selected_focus: String = _current_focus_id()
	for focus_variant: Variant in focuses:
		var focus: Dictionary = focus_variant as Dictionary
		var focus_id: String = String(focus.get("id", "overview"))
		var button: Button = Button.new()
		button.text = String(focus.get("label", focus_id.capitalize()))
		button.toggle_mode = true
		button.button_pressed = focus_id == selected_focus
		button.custom_minimum_size = Vector2(150, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 21)
		button.pressed.connect(func() -> void:
			show_focus(current_location_id, focus_id)
		)
		top_row.add_child(button)

func _refresh_main_content() -> void:
	_clear_dynamic_views()
	var profile: Dictionary = _profile(current_location_id)
	if location_title:
		location_title.text = String(profile.get("title", "Estate"))
	if location_art:
		location_art.texture = _art_for_location(current_location_id)
	var special_view: String = String(profile.get("special_view", ""))
	if current_location_id == "production" and _current_focus_id() == "overview":
		_show_production_overview_content()
	elif current_location_id == "production" and _current_focus_id() == "labour":
		_show_labour_assignment_view()
	elif special_view == "storehouse":
		_show_storehouse_view()
	elif special_view == "market":
		_show_market_view()
	elif special_view == "housing":
		_show_housing_view()
	elif special_view == "buildings":
		_show_building_view(profile)
	else:
		_show_text_content(profile)

func _set_content_root_layout(expanded: bool) -> void:
	if content_root == null:
		return

	# ContentRoot sits over the image area. Most screens use a lower overlay;
	# Production Overview reports use the full left image area, like a larger
	# version of the Storehouse/Market detail panel.
	content_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.custom_minimum_size = Vector2.ZERO

	if expanded:
		content_root.anchor_left = 0.0
		content_root.anchor_top = 0.0
		content_root.anchor_right = 1.0
		content_root.anchor_bottom = 1.0
		content_root.offset_left = 18.0
		content_root.offset_top = 18.0
		content_root.offset_right = -18.0
		content_root.offset_bottom = -18.0
	else:
		content_root.anchor_left = 0.0
		content_root.anchor_top = 1.0
		content_root.anchor_right = 1.0
		content_root.anchor_bottom = 1.0
		content_root.offset_left = 18.0
		content_root.offset_top = -280.0
		content_root.offset_right = -18.0
		content_root.offset_bottom = -18.0

func _show_text_content(profile: Dictionary) -> void:
	_set_content_root_layout(false)
	if content_root:
		content_root.visible = true
	if content_text:
		content_text.visible = true
		content_text.bbcode_enabled = true
		content_text.scroll_active = true
		content_text.fit_content = false
		content_text.custom_minimum_size = Vector2(0, 230)
		content_text.text = _build_standard_text(profile)

func _show_production_overview_content() -> void:
	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false

	if selected_production_report_id == "":
		if content_root:
			content_root.visible = false
		return

	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return

	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.0, 0.0, 0.0, 0.62), Color(0.50, 0.82, 0.74, 0.35), 14))
	dynamic_view_host.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)

	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	stack.add_child(header)

	var title_label: Label = Label.new()
	title_label.text = _production_report_title(selected_production_report_id)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 27)
	title_label.clip_text = true
	header.add_child(title_label)

	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(46, 42)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(_on_production_report_closed)
	header.add_child(close_button)

	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = false
	body.scroll_active = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 22)
	body.add_theme_font_size_override("bold_font_size", 24)
	body.add_theme_constant_override("line_separation", 6)
	body.text = _build_production_report_detail_text(selected_production_report_id)
	stack.add_child(body)

func _build_production_report_detail_text(report_id: String) -> String:
	match report_id:
		"expected_output":
			return _build_expected_output_report_text()
		"input_demand":
			return _build_input_demand_report_text()
		"labour_pressure":
			return _build_labour_pressure_report_text()
		"building_times":
			return _build_building_times_report_text()
	return "Select a production report from the right-hand panel."

func _build_expected_output_report_text() -> String:
	var text: String = ""
	text += "[b]Expected Output This Veintena[/b]\n"
	text += "This shows what built and operating production buildings are expected to add to the estate Storehouse when the Veintena advances.\n\n"
	text += _resource_dictionary_lines(_production_output_totals(), "No output expected. Build or staff productive buildings first.", 10)
	text += "\n"
	var summary: Dictionary = _production_building_summary()
	text += "[b]Operating read[/b]\n"
	text += "• Built production buildings: " + str(int(summary.get("built", 0))) + "\n"
	text += "• Expected operating instances: " + str(int(summary.get("operating", 0))) + "\n"
	text += "• Blocked instances: " + str(int(summary.get("blocked", 0))) + "\n"
	return text.strip_edges()

func _build_input_demand_report_text() -> String:
	var text: String = ""
	var inputs: Dictionary = _production_input_totals()
	text += "[b]Input Demand This Veintena[/b]\n"
	text += "These goods will be consumed by productive buildings before output is created. This does not include population upkeep or construction costs.\n\n"
	text += _resource_dictionary_lines(inputs, "No production inputs currently required.", 10)
	text += "\n"
	text += "[b]Input pressure[/b]\n"
	var pressure_lines: Array[String] = _input_pressure_lines(inputs)
	if pressure_lines.is_empty():
		text += "• No input pressure detected.\n"
	else:
		for line: String in pressure_lines:
			text += "• " + line + "\n"
	return text.strip_edges()

func _build_labour_pressure_report_text() -> String:
	var text: String = ""
	text += "[b]Labour Pressure[/b]\n"
	text += "This reads the productive workforce attached to chinampas and workshops. It should help show whether production is limited by people rather than goods.\n\n"
	var labour_lines: Array[String] = _production_labour_dashboard_lines(12)
	if labour_lines.is_empty():
		text += "• Labour data is not connected yet.\n"
	else:
		for labour_line: String in labour_lines:
			text += "• " + labour_line + "\n"
	return text.strip_edges()

func _build_building_times_report_text() -> String:
	var text: String = ""
	text += "[b]Building Times / Build Readiness[/b]\n"
	text += "This panel separates building readiness from the Chinampas and Workshops construction ledgers. In the current prototype, new buildings complete immediately when built; this section is ready for multi-Veintena build timers later.\n\n"
	var build_lines: Array[String] = _production_build_time_lines(12)
	if build_lines.is_empty():
		text += "• No production buildings are available yet.\n"
	else:
		for build_line: String in build_lines:
			text += "• " + build_line + "\n"
	return text.strip_edges()

func _build_standard_text(profile: Dictionary) -> String:
	var text: String = String(profile.get("body", "")) + "\n\n"
	var sections: Array = profile.get("sections", []) as Array
	for section_variant: Variant in sections:
		var section: Dictionary = section_variant as Dictionary
		text += "[b]" + String(section.get("heading", "Section")) + "[/b]\n"
		var lines: Array = section.get("lines", []) as Array
		for line_variant: Variant in lines:
			text += "• " + String(line_variant) + "\n"
		text += "\n"
	return text.strip_edges()

func _show_storehouse_view() -> void:
	_set_content_root_layout(false)
	if content_root:
		content_root.visible = true
	if content_text:
		content_text.visible = false
	if dynamic_view_host == null:
		return
	storehouse_view = STOREHOUSE_VIEW_SCENE.instantiate() as Control
	if storehouse_view == null:
		return
	storehouse_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storehouse_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_view_host.add_child(storehouse_view)
	if storehouse_view.has_signal("good_selected"):
		storehouse_view.connect("good_selected", Callable(self, "_on_storehouse_good_selected"))
	if storehouse_view.has_signal("good_closed"):
		storehouse_view.connect("good_closed", Callable(self, "_on_storehouse_good_closed"))
	if storehouse_view.has_method("setup"):
		storehouse_view.call("setup", _storehouse_goods(), _current_focus_id(), selected_storehouse_good_id)

func _show_market_view() -> void:
	_set_content_root_layout(false)
	if content_root:
		content_root.visible = true
	if content_text:
		content_text.visible = false
	if dynamic_view_host == null:
		return
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


func _show_labour_assignment_view() -> void:
	_set_content_root_layout(true)
	if content_root:
		content_root.visible = true
	if content_text:
		content_text.visible = false
	if dynamic_view_host == null:
		return
	labour_assignment_view = LABOUR_ASSIGNMENT_VIEW_SCENE.instantiate() as Control
	if labour_assignment_view == null:
		return
	labour_assignment_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labour_assignment_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_view_host.add_child(labour_assignment_view)
	if labour_assignment_view.has_signal("staffing_preview_changed"):
		labour_assignment_view.connect("staffing_preview_changed", Callable(self, "_on_labour_staffing_preview_changed"))
	if labour_assignment_view.has_signal("staffing_group_changed"):
		labour_assignment_view.connect("staffing_group_changed", Callable(self, "_on_labour_staffing_group_changed"))
	elif labour_assignment_view.has_signal("staffing_changed"):
		labour_assignment_view.connect("staffing_changed", Callable(self, "_on_labour_staffing_changed"))
	elif labour_assignment_view.has_signal("assignment_changed"):
		labour_assignment_view.connect("assignment_changed", Callable(self, "_on_labour_assignment_changed"))
	var state: Node = _state()
	if state != null and state.has_method("get_labour_assignment_data") and labour_assignment_view.has_method("setup"):
		labour_assignment_view.call("setup", state.call("get_labour_assignment_data"))

func _show_housing_view() -> void:
	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false
	if _current_focus_id() != "overview" and selected_housing_building_id == "":
		if content_root:
			content_root.visible = false
		return
	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return
	housing_view = HOUSING_VIEW_SCENE.instantiate() as Control
	if housing_view == null:
		return
	housing_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	housing_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_view_host.add_child(housing_view)
	if housing_view.has_signal("housing_closed"):
		housing_view.connect("housing_closed", Callable(self, "_on_housing_closed"))
	if housing_view.has_signal("build_requested"):
		housing_view.connect("build_requested", Callable(self, "_on_housing_build_requested"))
	if housing_view.has_signal("destroy_requested"):
		housing_view.connect("destroy_requested", Callable(self, "_on_housing_destroy_requested"))
	var state: Node = _state()
	if state != null and state.has_method("get_housing_summary") and state.has_method("get_housing_rows") and housing_view.has_method("setup"):
		housing_view.call("setup", state.call("get_housing_summary"), state.call("get_housing_rows", _current_focus_id()), _current_focus_id(), selected_housing_building_id)

func _show_building_view(profile: Dictionary) -> void:
	_set_content_root_layout(false)
	if content_root:
		content_root.visible = true
	if content_text:
		content_text.visible = false
	if dynamic_view_host == null:
		return
	building_view = BUILDING_VIEW_SCENE.instantiate() as Control
	if building_view == null:
		return
	building_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_view_host.add_child(building_view)
	if building_view.has_signal("build_requested"):
		building_view.connect("build_requested", Callable(self, "_on_build_requested"))
	if building_view.has_signal("destroy_requested"):
		building_view.connect("destroy_requested", Callable(self, "_on_destroy_requested"))
	if building_view.has_signal("building_closed"):
		building_view.connect("building_closed", Callable(self, "_on_building_closed"))
	var building_data: Array[Dictionary] = _buildings_for_current_screen(profile)
	var selected_id: String = String(selected_building_id_by_location.get(current_location_id, ""))
	if building_view.has_method("setup"):
		building_view.call("setup", building_data, selected_id)

func _clear_dynamic_views() -> void:
	storehouse_view = null
	market_view = null
	building_view = null
	labour_assignment_view = null
	housing_view = null
	if dynamic_view_host:
		_clear_children(dynamic_view_host)

func _refresh_right_panel() -> void:
	_clear_children(notification_list)
	var profile: Dictionary = _profile(current_location_id)
	if notification_title:
		notification_title.text = _report_title_for_current_focus(profile)

	_refresh_house_claim()

	var special_view: String = String(profile.get("special_view", ""))
	if special_view == "storehouse":
		_build_storehouse_ledger()
	elif special_view == "market":
		if _current_focus_id() == "reports":
			_build_market_reports()
		else:
			_build_market_ledger()
	elif special_view == "housing":
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

func _refresh_house_claim() -> void:
	if house_claim_panel == null:
		return

	var estate_visible: bool = current_location_id == "estate"
	house_claim_panel.visible = estate_visible
	if not estate_visible:
		return

	var summary: Dictionary = _prestige_summary()
	var prestige_value: float = float(summary.get("prestige", 0.0))
	var standing_text: String = String(summary.get("standing", "Standing: not ranked yet"))
	var recognition_text: String = String(summary.get("recognition", "Recognition: unproven"))
	var recent_text: String = String(summary.get("recent", "Last change: none"))

	if prestige_emblem:
		prestige_emblem.texture = prestige_emblem_art
		prestige_emblem.visible = prestige_emblem_art != null
	if prestige_glyph_label:
		prestige_glyph_label.visible = prestige_emblem_art == null
	if prestige_title_label:
		prestige_title_label.text = "House Claim"
	if prestige_value_label:
		prestige_value_label.text = "Prestige: " + _format_float(prestige_value)
	if prestige_standing_label:
		prestige_standing_label.text = standing_text
	if prestige_recognition_label:
		prestige_recognition_label.text = recognition_text
	if prestige_recent_label:
		prestige_recent_label.text = recent_text

	house_claim_panel.tooltip_text = "Prestige is public recognition of the house. The Estate screen shows the quick claim; the Rivals and Palace screens should later show full comparison."

func _prestige_summary() -> Dictionary:
	var summary: Dictionary = {
		"prestige": 0.0,
		"standing": "Standing: not ranked yet",
		"recognition": "Recognition: unproven",
		"recent": "Last change: none"
	}

	var state: Node = _state()
	if state == null:
		return summary

	if state.has_method("get_prestige_summary"):
		var raw_summary: Variant = state.call("get_prestige_summary")
		if raw_summary is Dictionary:
			var state_summary: Dictionary = raw_summary as Dictionary
			for key_variant: Variant in state_summary.keys():
				var key: String = String(key_variant)
				summary[key] = state_summary[key]
			return summary

	if state.has_method("get_player_prestige"):
		summary["prestige"] = float(state.call("get_player_prestige"))
	if state.has_method("get_prestige_standing_text"):
		summary["standing"] = String(state.call("get_prestige_standing_text"))
	if state.has_method("get_recognition_text"):
		summary["recognition"] = String(state.call("get_recognition_text"))
	if state.has_method("get_recent_prestige_text"):
		summary["recent"] = String(state.call("get_recent_prestige_text"))

	return summary

func _report_title_for_current_focus(profile: Dictionary) -> String:
	if current_location_id == "housing":
		match _current_focus_id():
			"overview":
				return "Housing Overview"
			"commoners":
				return "Commoner Housing"
			"tlacotin":
				return "Tlacotin Housing"
			"warriors":
				return "Warrior Housing"
			"priests":
				return "Priest Housing"
			"nobles":
				return "Noble Housing"
			"captives":
				return "Captive Holding"
		return "Housing Ledger"
	if current_location_id != "production":
		return String(profile.get("report_title", "Warnings & Reports"))
	match _current_focus_id():
		"overview":
			return "Production Reports"
		"chinampas":
			return "Chinampa Ledger"
		"workshops":
			return "Workshop Ledger"
		"labour":
			return "Productive Labour"
	return "Production Reports"

func _build_production_overview_reports() -> void:
	for report: Dictionary in _production_report_definitions():
		_add_production_report_button(report)
	if selected_production_report_id != "":
		var close_button: Button = Button.new()
		close_button.text = "Close Report"
		close_button.custom_minimum_size = Vector2(0, 54)
		close_button.add_theme_font_size_override("font_size", 19)
		close_button.pressed.connect(_on_production_report_closed)
		notification_list.add_child(close_button)

func _production_report_definitions() -> Array[Dictionary]:
	return [
		{"id": "expected_output", "title": "Expected Output", "subtitle": _production_report_subtitle("expected_output")},
		{"id": "input_demand", "title": "Input Demand", "subtitle": _production_report_subtitle("input_demand")},
		{"id": "labour_pressure", "title": "Labour Pressure", "subtitle": _production_report_subtitle("labour_pressure")},
		{"id": "building_times", "title": "Building Times", "subtitle": _production_report_subtitle("building_times")}
	]

func _production_report_title(report_id: String) -> String:
	match report_id:
		"expected_output":
			return "Expected Output"
		"input_demand":
			return "Input Demand"
		"labour_pressure":
			return "Labour Pressure"
		"building_times":
			return "Building Times / Build Readiness"
	return "Production Report"

func _production_report_subtitle(report_id: String) -> String:
	match report_id:
		"expected_output":
			var output_summary: String = _resource_dictionary_inline(_production_output_totals(), 3)
			if output_summary == "":
				return "No output expected"
			return output_summary
		"input_demand":
			var input_summary: String = _resource_dictionary_inline(_production_input_totals(), 3)
			if input_summary == "":
				return "No inputs consumed"
			return input_summary
		"labour_pressure":
			var labour_lines: Array[String] = _production_labour_dashboard_lines(1)
			if labour_lines.is_empty():
				return "No labour data yet"
			return labour_lines[0]
		"building_times":
			var buildable_count: int = _production_buildable_count()
			if buildable_count > 0:
				return str(buildable_count) + " buildable now"
			return "No build fully affordable"
	return "Open report"

func _add_production_report_button(report: Dictionary) -> void:
	if notification_list == null:
		return
	var report_id: String = String(report.get("id", ""))
	var selected: bool = report_id == selected_production_report_id
	var button: Button = Button.new()
	button.text = String(report.get("title", "Report")) + "\n" + String(report.get("subtitle", "Open report"))
	button.custom_minimum_size = Vector2(0, 94)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_pressed = selected
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 19)
	var border: Color = Color(0.34, 0.71, 0.63, 0.45)
	if selected:
		border = Color(0.76, 0.63, 0.32, 0.86)
	button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.04, 0.07, 0.065, 0.93), border, 10))
	button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.06, 0.095, 0.085, 0.96), Color(0.50, 0.82, 0.74, 0.75), 10))
	button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.10, 0.12, 0.095, 0.98), Color(0.76, 0.63, 0.32, 0.86), 10))
	button.pressed.connect(func() -> void:
		_on_production_report_selected(report_id)
	)
	notification_list.add_child(button)

func _production_overview_report_messages() -> Array[String]:
	var output: Array[String] = []
	var outputs: Dictionary = _production_output_totals()
	var inputs: Dictionary = _production_input_totals()
	var summary: Dictionary = _production_building_summary()

	var output_summary: String = _resource_dictionary_inline(outputs, 4)
	if output_summary == "":
		output.append("No expected output. Build production buildings or check staffing.")
	else:
		output.append("Output this Veintena: " + output_summary + ".")

	var input_summary: String = _resource_dictionary_inline(inputs, 4)
	if input_summary == "":
		output.append("No production input demand this Veintena.")
	else:
		output.append("Inputs consumed: " + input_summary + ".")

	var blocked_count: int = int(summary.get("blocked", 0))
	if blocked_count > 0:
		var blocked_lines: Array = summary.get("blocked_lines", []) as Array
		output.append("Blocked production: " + _join_string_items(blocked_lines, "; ", 2) + ".")
	else:
		output.append("No built production buildings are currently blocked.")

	var buildable_count: int = _production_buildable_count()
	if buildable_count > 0:
		output.append(str(buildable_count) + " production buildings can be built now. Open Chinampas or Workshops to choose one.")
	else:
		output.append("No new production building is fully affordable right now.")

	return output

func _production_output_totals() -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("estimate_building_outputs"):
		return state.call("estimate_building_outputs") as Dictionary
	return {}

func _production_input_totals() -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("estimate_building_inputs"):
		return state.call("estimate_building_inputs") as Dictionary
	return {}

func _production_building_summary() -> Dictionary:
	var result: Dictionary = {
		"built": 0,
		"operating": 0,
		"blocked": 0,
		"blocked_lines": [],
		"unbuilt_lines": []
	}

	var all_buildings: Array[Dictionary] = []
	var state: Node = _state()
	if state != null and state.has_method("get_buildings_for_screen"):
		var chinampas: Array = state.call("get_buildings_for_screen", "chinampas", "overview") as Array
		for item_variant: Variant in chinampas:
			all_buildings.append(item_variant as Dictionary)
		var workshops: Array = state.call("get_buildings_for_screen", "workshops", "overview") as Array
		for item_variant: Variant in workshops:
			all_buildings.append(item_variant as Dictionary)

	var blocked_lines: Array[String] = []
	var unbuilt_lines: Array[String] = []
	var built_count: int = 0
	var operating_count: int = 0
	var blocked_count: int = 0

	for building: Dictionary in all_buildings:
		var count: int = int(building.get("count", 0))
		var operating: int = int(building.get("operating", 0))
		var blocked: int = int(building.get("blocked", 0))
		var name: String = String(building.get("name", "Building"))
		built_count += count
		operating_count += operating
		blocked_count += blocked
		if count <= 0:
			unbuilt_lines.append(name + " not built")
		elif blocked > 0:
			blocked_lines.append(name + " " + String(building.get("status_text", "blocked")))

	result["built"] = built_count
	result["operating"] = operating_count
	result["blocked"] = blocked_count
	result["blocked_lines"] = blocked_lines
	result["unbuilt_lines"] = unbuilt_lines
	return result

func _input_pressure_lines(inputs: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if inputs.is_empty():
		return lines
	for key_variant: Variant in inputs.keys():
		var resource_id: String = String(key_variant)
		var needed: float = float(inputs[key_variant])
		if needed <= 0.001:
			continue
		var stored: float = _storehouse_value_for(resource_id, "stored")
		var free: float = _storehouse_value_for(resource_id, "free")
		var projected: float = stored - needed
		var line: String = _resource_name(resource_id) + ": needs " + _format_float(needed) + "; stored " + _format_float(stored) + "; free " + _format_float(free)
		if projected < 0.0:
			line += " — shortage risk"
		elif free < needed:
			line += " — tight after reserves"
		else:
			line += " — covered"
		lines.append(line)
	return lines

func _storehouse_value_for(resource_id: String, field_name: String) -> float:
	for good: Dictionary in _storehouse_goods():
		if String(good.get("id", "")) == resource_id:
			return float(good.get(field_name, 0.0))
	return 0.0

func _production_labour_summary_lines() -> Array[String]:
	var output: Array[String] = []
	var state: Node = _state()
	if state == null or not state.has_method("get_productive_labour_rows"):
		return output
	var rows: Array = state.call("get_productive_labour_rows") as Array
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant as Dictionary
		var name: String = String(row.get("name", "Labour"))
		var status: String = String(row.get("status_text", ""))
		output.append(name + " — " + status)
	return output

func _production_labour_dashboard_lines(max_items: int = 5) -> Array[String]:
	var output: Array[String] = []
	var state: Node = _state()
	if state == null or not state.has_method("get_productive_labour_rows"):
		return output
	var rows: Array = state.call("get_productive_labour_rows") as Array
	for row_variant: Variant in rows:
		if output.size() >= max_items:
			break
		var row: Dictionary = row_variant as Dictionary
		var name: String = String(row.get("name", "Labour"))
		var staff: Dictionary = row.get("staff", {}) as Dictionary
		var total: int = int(staff.get("total_population", row.get("count", 0)))
		var required: int = int(staff.get("required_by_built_production", row.get("operating", 0)))
		var free: int = int(staff.get("free_or_background_labour", max(0, total - required)))
		var status: String = String(row.get("status_text", ""))
		var short_status: String = "available"
		if status.find("Overstretched") >= 0:
			short_status = "overstretched"
		elif status.find("Fully") >= 0:
			short_status = "fully assigned"
		elif status.find("Tight") >= 0:
			short_status = "tight"
		elif status.find("Absent") >= 0:
			short_status = "absent"
		output.append(name + ": " + str(required) + " required / " + str(total) + " available; " + str(free) + " free — " + short_status + ".")
	return output

func _production_build_time_lines(max_items: int = 7) -> Array[String]:
	var output: Array[String] = []
	var buildings_for_view: Array[Dictionary] = _production_building_rows()
	var buildable: Array[String] = []
	var blocked: Array[String] = []
	var operating_notes: Array[String] = []

	for building: Dictionary in buildings_for_view:
		var name: String = String(building.get("name", "Building"))
		var count: int = int(building.get("count", 0))
		var operating: int = int(building.get("operating", 0))
		var blocked_instances: int = int(building.get("blocked", 0))
		var can_build: bool = bool(building.get("can_build", false))
		var build_status: String = String(building.get("build_status", ""))
		if count > 0:
			var status_line: String = name + ": built " + str(count) + ", operating " + str(operating) + " / " + str(count)
			if blocked_instances > 0:
				status_line += "; " + str(blocked_instances) + " blocked"
			operating_notes.append(status_line)
		if can_build:
			buildable.append(name + " — buildable now; completes immediately in this prototype.")
		elif build_status != "":
			blocked.append(name + " — " + build_status)

	output.append("Current prototype timing: new buildings complete immediately when built. This section is ready for multi-Veintena build timers later.")
	if not operating_notes.is_empty():
		output.append("Operating now: " + _join_string_items(operating_notes, "; ", 2) + ".")
	if not buildable.is_empty():
		output.append("Buildable now: " + _join_string_items(buildable, "; ", 2) + ".")
	if not blocked.is_empty():
		output.append("Blocked next builds: " + _join_string_items(blocked, "; ", 3) + ".")

	while output.size() > max_items:
		output.pop_back()
	return output

func _production_building_rows() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var state: Node = _state()
	if state == null or not state.has_method("get_buildings_for_screen"):
		return output
	var chinampas: Array = state.call("get_buildings_for_screen", "chinampas", "overview") as Array
	for item_variant: Variant in chinampas:
		output.append(item_variant as Dictionary)
	var workshops: Array = state.call("get_buildings_for_screen", "workshops", "overview") as Array
	for item_variant: Variant in workshops:
		output.append(item_variant as Dictionary)
	return output

func _production_buildable_count() -> int:
	var total: int = 0
	for building: Dictionary in _production_building_rows():
		if bool(building.get("can_build", false)):
			total += 1
	return total

func _resource_dictionary_lines(values: Dictionary, empty_text: String, max_items: int = 8) -> String:
	var keys: Array = values.keys()
	if keys.is_empty():
		return "• " + empty_text + "\n"
	var lines: String = ""
	var count: int = 0
	for key_variant: Variant in keys:
		if count >= max_items:
			var remaining: int = keys.size() - count
			lines += "• +" + str(remaining) + " more goods\n"
			break
		var resource_id: String = String(key_variant)
		var amount: float = float(values[key_variant])
		if absf(amount) <= 0.001:
			continue
		lines += "• " + _resource_name(resource_id) + ": " + _format_float(amount) + "\n"
		count += 1
	if lines == "":
		return "• " + empty_text + "\n"
	return lines

func _resource_dictionary_inline(values: Dictionary, max_items: int = 4) -> String:
	var parts: Array[String] = []
	for key_variant: Variant in values.keys():
		if parts.size() >= max_items:
			break
		var resource_id: String = String(key_variant)
		var amount: float = float(values[key_variant])
		if absf(amount) <= 0.001:
			continue
		parts.append(_resource_name(resource_id) + " " + _format_float(amount))
	return ", ".join(parts)

func _resource_name(resource_id: String) -> String:
	var state: Node = _state()
	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))
	return resource_id.replace("_", " ").capitalize()

func _build_storehouse_ledger() -> void:
	var focus_id: String = _current_focus_id()
	var goods: Array[Dictionary] = _filtered_storehouse_goods(focus_id)
	if goods.is_empty():
		_add_notification("No goods match this Storehouse focus.")
		return
	for good_variant: Variant in goods:
		var good: Dictionary = good_variant as Dictionary
		var row: Control = STOCKPILE_LEDGER_ROW_SCENE.instantiate() as Control
		if row == null:
			continue
		if row.has_method("set_good_data"):
			row.call("set_good_data", good, String(good.get("id", "")) == selected_storehouse_good_id)
		if row.has_signal("good_selected"):
			row.connect("good_selected", Callable(self, "_on_storehouse_good_selected"))
		notification_list.add_child(row)

func _build_market_ledger() -> void:
	var goods: Array[Dictionary] = _filtered_market_goods(_current_focus_id())
	if goods.is_empty():
		_add_notification("No market goods match this focus.")
		return
	for good_variant: Variant in goods:
		var good: Dictionary = good_variant as Dictionary
		var row: Control = MARKET_LEDGER_ROW_SCENE.instantiate() as Control
		if row == null:
			continue
		if row.has_method("set_good_data"):
			row.call("set_good_data", good, String(good.get("id", "")) == selected_market_good_id)
		if row.has_signal("good_selected"):
			row.connect("good_selected", Callable(self, "_on_market_good_selected"))
		notification_list.add_child(row)


func _build_market_reports() -> void:
	var messages: Array[String] = _market_report_messages()
	for message: String in messages:
		_add_notification(message)

func _market_report_messages() -> Array[String]:
	var goods: Array[Dictionary] = _market_goods()
	var output: Array[String] = []
	output.append("Market reports show stock, demand, coverage, value, trend and rival buying pressure.")
	var crisis_goods: Array[String] = []
	var shortage_goods: Array[String] = []
	var high_value_goods: Array[String] = []
	for good_variant: Variant in goods:
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
			high_value_goods.append(name + " (" + _format_float(current_value) + ")")
	if not crisis_goods.is_empty():
		output.append("Crisis goods: " + ", ".join(crisis_goods) + ".")
	if not shortage_goods.is_empty():
		output.append("Shortage goods: " + ", ".join(shortage_goods) + ".")
	if not high_value_goods.is_empty():
		output.append("High-value sale opportunities: " + ", ".join(high_value_goods) + ".")
	output.append("Rival procurement reports will become more specific once rival market buying is connected.")
	return output


func _build_labour_assignment_summary() -> void:
	var state: Node = _state()
	if state == null or not state.has_method("get_labour_assignment_data"):
		_add_notification("Labour assignment data is not connected yet.")
		return
	var labour_data: Dictionary = state.call("get_labour_assignment_data") as Dictionary
	_add_notification("Use the assignment bars on the left to choose how many built chinampas and workshops are staffed.")
	var groups: Array = labour_data.get("groups", []) as Array
	for group_variant: Variant in groups:
		var group: Dictionary = group_variant as Dictionary
		var line: String = String(group.get("name", "Labour")) + ": "
		line += str(int(group.get("assigned", 0))) + " assigned / " + str(int(group.get("total", 0))) + " total; "
		line += str(int(group.get("unassigned", 0))) + " unassigned"
		var shortfall: int = int(group.get("shortfall", 0))
		if shortfall > 0:
			line += "; short " + str(shortfall)
		_add_notification(line)
	var buildings: Array = labour_data.get("buildings", []) as Array
	if buildings.is_empty():
		_add_notification("No built productive buildings currently need assigned labour.")
	else:
		_add_notification(str(buildings.size()) + " built productive building type(s) can be staffed.")

func _build_housing_ledger() -> void:
	var state: Node = _state()
	if state == null or not state.has_method("get_housing_rows"):
		_add_notification("Housing data is not connected yet.")
		return
	var rows: Array = state.call("get_housing_rows", _current_focus_id()) as Array
	if rows.is_empty():
		_add_notification("No housing entries match this focus.")
		return
	for row_variant: Variant in rows:
		var row_data: Dictionary = row_variant as Dictionary
		var row: Control = HOUSING_LEDGER_ROW_SCENE.instantiate() as Control
		if row == null:
			continue
		if row.has_method("set_housing_data"):
			row.call("set_housing_data", row_data, String(row_data.get("id", "")) == selected_housing_building_id)
		if row.has_signal("housing_selected"):
			row.connect("housing_selected", Callable(self, "_on_housing_selected"))
		if row.has_signal("build_requested"):
			row.connect("build_requested", Callable(self, "_on_housing_build_requested"))
		if row.has_signal("destroy_requested"):
			row.connect("destroy_requested", Callable(self, "_on_housing_destroy_requested"))
		notification_list.add_child(row)

func _build_building_ledger(profile: Dictionary) -> void:
	var buildings_for_view: Array[Dictionary] = _buildings_for_current_screen(profile)
	if buildings_for_view.is_empty():
		_add_notification("No buildings match this focus.")
		return
	var selected_id: String = String(selected_building_id_by_location.get(current_location_id, ""))
	for building_variant: Variant in buildings_for_view:
		var building: Dictionary = building_variant as Dictionary
		var row: Control = BUILDING_LEDGER_ROW_SCENE.instantiate() as Control
		if row == null:
			continue
		if row.has_method("set_building_data"):
			row.call("set_building_data", building, String(building.get("id", "")) == selected_id)
		if row.has_signal("building_selected"):
			row.connect("building_selected", Callable(self, "_on_building_selected"))
		if row.has_signal("build_requested"):
			row.connect("build_requested", Callable(self, "_on_build_requested"))
		if row.has_signal("destroy_requested"):
			row.connect("destroy_requested", Callable(self, "_on_destroy_requested"))
		notification_list.add_child(row)

func _build_report_list(profile: Dictionary) -> void:
	var reports: Array = profile.get("reports", []) as Array
	if current_location_id == "estate":
		var state: Node = _state()
		if state != null and state.has_method("get_last_report"):
			reports = state.call("get_last_report") as Array
	if reports.is_empty():
		_add_notification("No reports yet.")
		return
	for report_variant: Variant in reports:
		_add_notification(String(report_variant))

func _storehouse_goods() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var state: Node = _state()
	if state != null and state.has_method("get_storehouse_goods"):
		var raw: Array = state.call("get_storehouse_goods") as Array
		for item_variant: Variant in raw:
			output.append(item_variant as Dictionary)
	return output

func _market_goods() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var state: Node = _state()
	if state != null and state.has_method("get_market_goods"):
		var raw: Array = state.call("get_market_goods") as Array
		for item_variant: Variant in raw:
			output.append(item_variant as Dictionary)
	return output

func _buildings_for_current_screen(profile: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var state: Node = _state()
	if state == null:
		return output

	if current_location_id == "production":
		var focus_id: String = _current_focus_id()
		if focus_id == "labour":
			if state.has_method("get_productive_labour_rows"):
				var labour_rows: Array = state.call("get_productive_labour_rows") as Array
				for item_variant: Variant in labour_rows:
					output.append(item_variant as Dictionary)
			return output
		if state.has_method("get_buildings_for_screen"):
			if focus_id == "chinampas":
				var raw_chinampas: Array = state.call("get_buildings_for_screen", "chinampas", "overview") as Array
				for item_variant: Variant in raw_chinampas:
					output.append(item_variant as Dictionary)
				return output
			if focus_id == "workshops":
				var raw_workshops: Array = state.call("get_buildings_for_screen", "workshops", "overview") as Array
				for item_variant: Variant in raw_workshops:
					output.append(item_variant as Dictionary)
				return output
			var raw_all_chinampas: Array = state.call("get_buildings_for_screen", "chinampas", "overview") as Array
			for item_variant: Variant in raw_all_chinampas:
				output.append(item_variant as Dictionary)
			var raw_all_workshops: Array = state.call("get_buildings_for_screen", "workshops", "overview") as Array
			for item_variant: Variant in raw_all_workshops:
				output.append(item_variant as Dictionary)
			if state.has_method("get_productive_labour_rows"):
				var labour_overview: Array = state.call("get_productive_labour_rows") as Array
				for item_variant: Variant in labour_overview:
					output.append(item_variant as Dictionary)
		return output

	if state.has_method("get_buildings_for_screen"):
		var screen_id: String = String(profile.get("building_screen", ""))
		var raw: Array = state.call("get_buildings_for_screen", screen_id, _current_focus_id()) as Array
		for item_variant: Variant in raw:
			output.append(item_variant as Dictionary)
	return output

func _filtered_storehouse_goods(focus_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for good_variant: Variant in _storehouse_goods():
		var good: Dictionary = good_variant as Dictionary
		var category: String = String(good.get("category", ""))
		var include_good: bool = focus_id == "overview" or category == focus_id
		if include_good:
			output.append(good)
	return output

func _filtered_market_goods(focus_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for good_variant: Variant in _market_goods():
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

func _on_production_report_selected(report_id: String) -> void:
	selected_production_report_id = report_id
	_refresh_all()

func _on_production_report_closed() -> void:
	selected_production_report_id = ""
	_refresh_all()

func _apply_labour_staffing_change(building_id: String, group_id: String, staffed_count: int) -> void:
	var state: Node = _state()
	if state != null and state.has_method("set_staffed_building_count_for_group"):
		state.call("set_staffed_building_count_for_group", building_id, group_id, staffed_count)
	elif state != null and state.has_method("assign_labour_to_building"):
		state.call("assign_labour_to_building", building_id, group_id, staffed_count)
	elif state != null and state.has_method("set_staffed_building_count"):
		state.call("set_staffed_building_count", building_id, staffed_count)

func _on_labour_staffing_preview_changed(building_id: String, group_id: String, staffed_count: int) -> void:
	# Live update while dragging. This updates the state, right-hand labour readout
	# and Storehouse projections, but deliberately does not rebuild the Labour page.
	_apply_labour_staffing_change(building_id, group_id, staffed_count)
	_refresh_right_panel()

func _on_labour_staffing_group_changed(building_id: String, group_id: String, staffed_count: int) -> void:
	_apply_labour_staffing_change(building_id, group_id, staffed_count)
	var state: Node = _state()

	# Do not call _refresh_all() here: that recreates the Labour screen and
	# makes the scroll position jump. Instead, update only the open Labour view
	# with fresh data so unassigned labour totals, slider limits, the right-hand
	# ledger, and future Storehouse incoming/outgoing all follow the slider.
	if current_location_id == "production" and _current_focus_id() == "labour" and labour_assignment_view != null:
		if state != null and state.has_method("get_labour_assignment_data") and labour_assignment_view.has_method("refresh_from_data"):
			labour_assignment_view.call_deferred("refresh_from_data", state.call("get_labour_assignment_data"))
	_refresh_right_panel()

func _on_labour_staffing_changed(building_id: String, staffed_count: int) -> void:
	_on_labour_staffing_group_changed(building_id, "", staffed_count)

func _on_labour_assignment_changed(building_id: String, group_id: String, amount: int) -> void:
	_on_labour_staffing_group_changed(building_id, group_id, amount)

func _on_housing_selected(housing_id: String) -> void:
	if _current_focus_id() == "overview":
		# Overview rows are summary cards. They keep the overview panel open rather
		# than selecting a buildable housing building.
		return
	selected_housing_building_id = housing_id
	_refresh_all()

func _on_housing_closed() -> void:
	selected_housing_building_id = ""
	if current_location_id == "housing":
		_refresh_all()

func _on_housing_build_requested(housing_id: String) -> void:
	var state: Node = _state()
	if state != null and state.has_method("build_building"):
		state.call("build_building", housing_id)
	_refresh_all()

func _on_housing_destroy_requested(housing_id: String) -> void:
	var state: Node = _state()
	if state != null and state.has_method("destroy_building"):
		state.call("destroy_building", housing_id)
	_refresh_all()

func _on_storehouse_good_selected(good_id: String) -> void:
	selected_storehouse_good_id = good_id
	if storehouse_view != null and storehouse_view.has_method("select_good"):
		storehouse_view.call("select_good", good_id)
	_refresh_right_panel()

func _on_storehouse_good_closed() -> void:
	selected_storehouse_good_id = ""
	_refresh_right_panel()

func _on_market_good_selected(good_id: String) -> void:
	selected_market_good_id = good_id
	if market_view != null and market_view.has_method("select_good"):
		market_view.call("select_good", good_id)
	_refresh_right_panel()

func _on_market_good_closed() -> void:
	selected_market_good_id = ""
	_refresh_right_panel()

func _on_building_selected(building_id: String) -> void:
	selected_building_id_by_location[current_location_id] = building_id
	if building_view != null and building_view.has_method("select_building"):
		building_view.call("select_building", building_id)
	_refresh_right_panel()

func _on_building_closed() -> void:
	selected_building_id_by_location[current_location_id] = ""
	_refresh_right_panel()

func _on_build_requested(building_id: String) -> void:
	var state: Node = _state()
	if state != null and state.has_method("build_building"):
		state.call("build_building", building_id)
	_refresh_all()

func _on_destroy_requested(building_id: String) -> void:
	var state: Node = _state()
	if state != null and state.has_method("destroy_building"):
		state.call("destroy_building", building_id)
	_refresh_all()

func _on_advance_turn_pressed() -> void:
	var state: Node = _state()
	if state != null and state.has_method("advance_veintena"):
		state.call("advance_veintena")
	_refresh_all()

func _on_state_changed() -> void:
	_refresh_all()

func _art_for_location(location_id: String) -> Texture2D:
	match location_id:
		"estate":
			return estate_art
		"production":
			return _art_for_production_focus(_current_focus_id())
		"storehouse":
			return storehouse_art
		"market":
			return market_art
		"housing":
			return _art_for_housing_focus(_current_focus_id())
		"shrines":
			return shrines_art
		"warriors":
			if barracks_art:
				return barracks_art
			return warriors_art
		"palace":
			return palace_art
		"rivals":
			return rivals_art
	return null

func _art_for_production_focus(focus_id: String) -> Texture2D:
	match focus_id:
		"overview":
			if production_overview_art:
				return production_overview_art
		"chinampas":
			if production_chinampas_art:
				return production_chinampas_art
			if chinampas_art:
				return chinampas_art
		"workshops":
			if production_workshops_art:
				return production_workshops_art
			if workshops_art:
				return workshops_art
		"labour":
			if production_labour_art:
				return production_labour_art
	if production_art:
		return production_art
	if fields_art:
		return fields_art
	return estate_art

func _art_for_housing_focus(focus_id: String) -> Texture2D:
	match focus_id:
		"overview":
			if housing_overview_art:
				return housing_overview_art
		"commoners":
			if housing_commoners_art:
				return housing_commoners_art
		"tlacotin":
			if housing_tlacotin_art:
				return housing_tlacotin_art
		"warriors":
			if housing_warriors_art:
				return housing_warriors_art
		"priests":
			if housing_priests_art:
				return housing_priests_art
		"nobles":
			if housing_nobles_art:
				return housing_nobles_art
		"captives":
			if housing_captives_art:
				return housing_captives_art
	if housing_art:
		return housing_art
	return estate_art

func _update_button_pressed_state() -> void:
	var button_map: Dictionary = {
		"estate": estate_button,
		"production": production_button,
		"storehouse": storehouse_button,
		"market": market_button,
		"housing": housing_button,
		"shrines": shrines_button,
		"warriors": warriors_button,
		"palace": palace_button,
		"rivals": rivals_button
	}
	for key_variant: Variant in button_map.keys():
		var key: String = String(key_variant)
		var button: Button = button_map[key] as Button
		if button:
			button.button_pressed = key == current_location_id

func _apply_style() -> void:
	var panel_nodes: Array[Node] = [
		get_node_or_null(^"SafeArea/MainVBox/CalendarPanel"),
		get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView"),
		get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel"),
		get_node_or_null(^"SafeArea/MainVBox/BottomNav")
	]
	for node: Node in panel_nodes:
		var panel: PanelContainer = node as PanelContainer
		if panel:
			panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.055, 0.052, 0.90), Color(0.34, 0.71, 0.63, 0.45), 14))
	if location_title:
		location_title.add_theme_font_size_override("font_size", 35)
	if content_text:
		content_text.add_theme_font_size_override("normal_font_size", 21)
		content_text.add_theme_font_size_override("bold_font_size", 22)
		content_text.add_theme_constant_override("line_separation", 5)
		var content_style: StyleBoxFlat = _make_panel_style(Color(0.0, 0.0, 0.0, 0.55), Color(0.50, 0.82, 0.74, 0.25), 12)
		content_text.add_theme_stylebox_override("normal", content_style)
	if notification_title:
		notification_title.add_theme_font_size_override("font_size", 25)
	if house_claim_panel:
		house_claim_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.0, 0.0, 0.0, 0.58), Color(0.76, 0.63, 0.32, 0.58), 12))
	if prestige_title_label:
		prestige_title_label.add_theme_font_size_override("font_size", 22)
	if prestige_value_label:
		prestige_value_label.add_theme_font_size_override("font_size", 23)
	if prestige_standing_label:
		prestige_standing_label.add_theme_font_size_override("font_size", 18)
	if prestige_recognition_label:
		prestige_recognition_label.add_theme_font_size_override("font_size", 18)
	if prestige_recent_label:
		prestige_recent_label.add_theme_font_size_override("font_size", 16)
	if prestige_glyph_label:
		prestige_glyph_label.add_theme_font_size_override("font_size", 42)

	var buttons: Array = [estate_button, production_button, storehouse_button, market_button, housing_button, shrines_button, warriors_button, palace_button, rivals_button, advance_turn_button]
	for button_variant: Variant in buttons:
		var button: Button = button_variant as Button
		if button:
			button.custom_minimum_size = Vector2(0, 62)
			button.add_theme_font_size_override("font_size", 20)
			if button != advance_turn_button:
				button.toggle_mode = true
			else:
				button.custom_minimum_size = Vector2(250, 62)
				button.add_theme_font_size_override("font_size", 21)



func _join_string_items(items: Array, separator: String = ", ", max_items: int = 0) -> String:
	var parts: Array[String] = []
	var limit: int = items.size()
	if max_items > 0:
		limit = mini(max_items, items.size())

	for i: int in range(limit):
		parts.append(String(items[i]))

	if max_items > 0 and items.size() > max_items:
		var remaining: int = items.size() - max_items
		parts.append("+" + str(remaining) + " more")

	return separator.join(parts)

func _format_float(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _add_center_label(parent: VBoxContainer, text: String, font_size: int) -> void:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)

func _add_notification(text: String) -> void:
	if notification_list == null:
		return
	var label: Label = Label.new()
	label.text = "• " + text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 19)
	notification_list.add_child(label)

func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		child.queue_free()

func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	return style
