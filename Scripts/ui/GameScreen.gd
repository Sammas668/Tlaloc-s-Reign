# GameScreen.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreen.gd
#
# Shared game shell with data-backed prototype systems:
# - Estate keeps the Veintena calendar.
# - Chinampas and Workshops use real building definitions, build costs, staff, inputs and outputs.
# - Storehouse and Market read from TRGameState instead of hard-coded UI placeholder data.
# - Bottom bar order locked: Estate | Chinampas | Workshops | Storehouse | Marketplace | Shrines | Warrior House | Palace | Rival Houses | Advance Veintena.
extends Control

const TR_GAME_STATE_SCRIPT: Script = preload("res://Scripts/autoload/TRGameState.gd")
const STOREHOUSE_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/StorehouseView.tscn")
const STOCKPILE_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/StockpileLedgerRow.tscn")
const MARKET_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/MarketView.tscn")
const MARKET_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/MarketLedgerRow.tscn")
const BUILDING_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/BuildingView.tscn")
const BUILDING_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/BuildingLedgerRow.tscn")

@export var estate_art: Texture2D
@export var chinampas_art: Texture2D
@export var fields_art: Texture2D # Backwards-compatible fallback if you already assigned art to the older Fields Art slot.
@export var storehouse_art: Texture2D
@export var workshops_art: Texture2D
@export var shrines_art: Texture2D
@export var warriors_art: Texture2D
@export var market_art: Texture2D
@export var palace_art: Texture2D
@export var rivals_art: Texture2D

@export var visible_veintenas: int = 7

@onready var top_row: HBoxContainer = get_node_or_null(^"SafeArea/MainVBox/CalendarPanel/Margin/CardRow") as HBoxContainer
@onready var location_title: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/LocationTitle") as Label
@onready var location_art: TextureRect = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/LocationArt") as TextureRect
@onready var content_root: VBoxContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/ContentRoot") as VBoxContainer
@onready var content_text: RichTextLabel = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/ContentRoot/ContentText") as RichTextLabel
@onready var dynamic_view_host: VBoxContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/ContentRoot/DynamicViewHost") as VBoxContainer
@onready var notification_title: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/NotificationTitle") as Label
@onready var notification_list: VBoxContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/NotificationScroll/NotificationList") as VBoxContainer

@onready var estate_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/EstateButton") as Button
@onready var chinampas_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/FieldsButton") as Button
@onready var workshops_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/WorkshopsButton") as Button
@onready var storehouse_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/StorehouseButton") as Button
@onready var market_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/MarketButton") as Button
@onready var shrines_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/ShrinesButton") as Button
@onready var warriors_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/WarriorsButton") as Button
@onready var palace_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/PalaceButton") as Button
@onready var rivals_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/RivalsButton") as Button
@onready var advance_turn_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/AdvanceTurnButton") as Button

var current_location_id: String = "estate"
var current_focus_by_location: Dictionary = {}
var selected_storehouse_good_id: String = ""
var selected_market_good_id: String = ""
var selected_building_id_by_location: Dictionary = {}

var storehouse_view: Control = null
var market_view: Control = null
var building_view: Control = null
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
			{"heading": "Estate overview", "lines": ["The top row shows the Veintena calendar.", "The right panel summarises the last turn and major warnings.", "Chinampas and Workshops now drive Storehouse totals through real production.", "Use Advance Veintena to run upkeep, building inputs and building output."]}
		],
		"reports": []
	},
	"chinampas": {
		"title": "Chinampas",
		"special_view": "buildings",
		"building_screen": "chinampas",
		"report_title": "Chinampa Ledger",
		"body": "Chinampas are the estate's agricultural engine. Built chinampas need staff and tool inputs before they feed the Storehouse.",
		"focuses": [
			{"id": "overview", "label": "Overview"},
			{"id": "maize", "label": "Maize"},
			{"id": "cacao", "label": "Cacao"},
			{"id": "cotton", "label": "Cotton"},
			{"id": "labour", "label": "Labour"},
			{"id": "build", "label": "Build"}
		]
	},
	"workshops": {
		"title": "Workshops",
		"special_view": "buildings",
		"building_screen": "workshops",
		"report_title": "Workshop Ledger",
		"body": "Workshops convert raw goods into tools, cloth, weapons and luxury goods. They only operate when built, staffed and supplied with their input goods.",
		"focuses": [
			{"id": "overview", "label": "Overview"},
			{"id": "tools", "label": "Tools"},
			{"id": "cloth", "label": "Cloth"},
			{"id": "weapons", "label": "Weapons"},
			{"id": "luxury", "label": "Luxury"},
			{"id": "build", "label": "Build"}
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
	"shrines": {"title": "Shrines", "report_title": "Omens & Priest Reports", "body": "Offerings to Tlaloc, Huitzilopochtli, Tezcatlipoca and Quetzalcoatl will be managed here.", "focuses": [{"id": "overview", "label": "Overview"}, {"id": "tlaloc", "label": "Tlaloc"}, {"id": "huitzilopochtli", "label": "Huitzilopochtli"}, {"id": "tezcatlipoca", "label": "Tezcatlipoca"}, {"id": "quetzalcoatl", "label": "Quetzalcoatl"}, {"id": "offerings", "label": "Offerings"}], "reports": ["Shrine systems are not connected yet.", "Offerings will later consume goods from the Storehouse."]},
	"warriors": {"title": "Warrior House", "report_title": "Warrior Reports", "body": "Warriors, weapons and Flower Wars preparation will be managed here.", "focuses": [{"id": "overview", "label": "Overview"}, {"id": "warriors", "label": "Warriors"}, {"id": "weapons", "label": "Weapons"}, {"id": "flower_wars", "label": "Flower Wars"}, {"id": "returns", "label": "Returns"}], "reports": ["Warrior systems are not connected yet.", "Weapons will come from the Workshop system."]},
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
	if chinampas_button:
		chinampas_button.pressed.connect(func() -> void: show_location("chinampas"))
	if workshops_button:
		workshops_button.pressed.connect(func() -> void: show_location("workshops"))
	if storehouse_button:
		storehouse_button.pressed.connect(func() -> void: show_location("storehouse"))
	if market_button:
		market_button.pressed.connect(func() -> void: show_location("market"))
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
	if chinampas_button:
		chinampas_button.text = "Chinampas"
	if workshops_button:
		workshops_button.text = "Workshops"
	if storehouse_button:
		storehouse_button.text = "Storehouse"
	if market_button:
		market_button.text = "Market"
	if shrines_button:
		shrines_button.text = "Shrines"
	if warriors_button:
		warriors_button.text = "Warriors"
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
		card.custom_minimum_size = Vector2(150, 94)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = "Veintena " + str(i + 1) + " — " + String(card_data.get("name", "")) + ". " + String(card_data.get("tooltip", ""))
		var style: StyleBoxFlat = _make_panel_style(Color(0.055, 0.08, 0.075, 0.92), Color(0.33, 0.70, 0.62, 0.55), 10)
		if i == start_index:
			style = _make_panel_style(Color(0.09, 0.13, 0.115, 0.98), Color(0.76, 0.63, 0.32, 0.85), 10)
		card.add_theme_stylebox_override("panel", style)
		var margin: MarginContainer = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 6)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		card.add_child(margin)
		var stack: VBoxContainer = VBoxContainer.new()
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		margin.add_child(stack)
		_add_center_label(stack, "Veintena " + str(i + 1), 13)
		_add_center_label(stack, String(card_data.get("name", "")), 11)
		_add_center_label(stack, String(card_data.get("type", "")), 13)
		_add_center_label(stack, String(card_data.get("detail", "")), 11)
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
		button.custom_minimum_size = Vector2(130, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	if special_view == "storehouse":
		_show_storehouse_view()
	elif special_view == "market":
		_show_market_view()
	elif special_view == "buildings":
		_show_building_view(profile)
	else:
		_show_text_content(profile)

func _show_text_content(profile: Dictionary) -> void:
	if content_root:
		content_root.visible = true
	if content_text:
		content_text.visible = true
		content_text.bbcode_enabled = true
		content_text.scroll_active = true
		content_text.fit_content = false
		content_text.text = _build_standard_text(profile)

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

func _show_building_view(profile: Dictionary) -> void:
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
	if dynamic_view_host:
		_clear_children(dynamic_view_host)

func _refresh_right_panel() -> void:
	_clear_children(notification_list)
	var profile: Dictionary = _profile(current_location_id)
	if notification_title:
		notification_title.text = String(profile.get("report_title", "Warnings & Reports"))
	var special_view: String = String(profile.get("special_view", ""))
	if special_view == "storehouse":
		_build_storehouse_ledger()
	elif special_view == "market":
		if _current_focus_id() == "reports":
			_build_market_reports()
		else:
			_build_market_ledger()
	elif special_view == "buildings":
		_build_building_ledger(profile)
	else:
		_build_report_list(profile)

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
	if state != null and state.has_method("get_buildings_for_screen"):
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
		"chinampas":
			if chinampas_art:
				return chinampas_art
			return fields_art
		"workshops":
			return workshops_art
		"storehouse":
			return storehouse_art
		"market":
			return market_art
		"shrines":
			return shrines_art
		"warriors":
			return warriors_art
		"palace":
			return palace_art
		"rivals":
			return rivals_art
	return null

func _update_button_pressed_state() -> void:
	var button_map: Dictionary = {
		"estate": estate_button,
		"chinampas": chinampas_button,
		"workshops": workshops_button,
		"storehouse": storehouse_button,
		"market": market_button,
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
		location_title.add_theme_font_size_override("font_size", 26)
	if content_text:
		content_text.add_theme_font_size_override("normal_font_size", 16)
		content_text.add_theme_font_size_override("bold_font_size", 17)
		var content_style: StyleBoxFlat = _make_panel_style(Color(0.0, 0.0, 0.0, 0.55), Color(0.50, 0.82, 0.74, 0.25), 12)
		content_text.add_theme_stylebox_override("normal", content_style)
	var buttons: Array = [estate_button, chinampas_button, workshops_button, storehouse_button, market_button, shrines_button, warriors_button, palace_button, rivals_button, advance_turn_button]
	for button_variant: Variant in buttons:
		var button: Button = button_variant as Button
		if button:
			button.custom_minimum_size = Vector2(0, 48)
			button.add_theme_font_size_override("font_size", 14)
			if button != advance_turn_button:
				button.toggle_mode = true


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
	label.add_theme_font_size_override("font_size", 14)
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
