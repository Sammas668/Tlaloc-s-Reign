# GameScreen.gd
# Godot 4.x
# Suggested project path: res://scripts/ui/GameScreen.gd
extends Control

@export var estate_art: Texture2D
@export var fields_art: Texture2D
@export var storehouse_art: Texture2D
@export var workshops_art: Texture2D
@export var shrines_art: Texture2D
@export var warriors_art: Texture2D
@export var market_art: Texture2D
@export var palace_art: Texture2D
@export var rivals_art: Texture2D

@export var visible_veintenas: int = 7

@onready var calendar_card_row: HBoxContainer = get_node_or_null(^"SafeArea/MainVBox/CalendarPanel/Margin/CardRow") as HBoxContainer
@onready var location_title: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/LocationTitle") as Label
@onready var location_art: TextureRect = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/LocationArt") as TextureRect
@onready var content_text: RichTextLabel = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ContentText") as RichTextLabel
@onready var notification_list: VBoxContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/NotificationScroll/NotificationList") as VBoxContainer

@onready var estate_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/EstateButton") as Button
@onready var fields_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/FieldsButton") as Button
@onready var storehouse_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/StorehouseButton") as Button
@onready var workshops_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/WorkshopsButton") as Button
@onready var shrines_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/ShrinesButton") as Button
@onready var warriors_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/WarriorsButton") as Button
@onready var market_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/MarketButton") as Button
@onready var palace_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/PalaceButton") as Button
@onready var rivals_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/RivalsButton") as Button
@onready var advance_turn_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/AdvanceTurnButton") as Button

var current_veintena: int = 1
var current_location_id: String = "estate"

var _location_text: Dictionary = {
	"estate": {
		"title": "Estate Court",
		"body": "This is the heart of your noble house. Prestige, household identity, broad estate problems and current strategic pressure will be summarised here."
	},
	"fields": {
		"title": "Estate Fields",
		"body": "Maize fields, cacao gardens and cotton fields will be managed here. This is where rain, labour, food security and Tlaloc pressure become visible."
	},
	"storehouse": {
		"title": "Storehouse",
		"body": "All stockpiles belong here: maize, wood, cotton, cacao, obsidian, cloth, tools, weapons, ritual goods, fine textiles, captives and looted goods. Later this tab will show stored amount, net change, market state and main uses."
	},
	"workshops": {
		"title": "Workshops",
		"body": "Tools, cloth, weapons, ritual goods and fine textiles will be produced here. Workshops should show inputs, outputs, staffing and whether each building can operate this Veintena."
	},
	"shrines": {
		"title": "Shrines of the Four Gods",
		"body": "Offerings, priests, sacrifices and divine favour will be managed here for Tlaloc, Huitzilopochtli, Tezcatlipoca and Quetzalcoatl."
	},
	"warriors": {
		"title": "Warrior House",
		"body": "Warriors, weapons, readiness and Flower Wars preparation will be managed here. War should feel tempting, expensive and risky."
	},
	"market": {
		"title": "Marketplace",
		"body": "Scarcity, buying, selling and rival procurement signals will be managed here. The market is the shared exchange layer, not a replacement for estate stockpiles."
	},
	"palace": {
		"title": "Palace Obligations",
		"body": "Tribute, royal favour, desired goods and recognition pressure will be managed here. This is where the estate proves its usefulness to the ruler."
	},
	"rivals": {
		"title": "Rival Houses",
		"body": "The War Rival, Cunning Rival and Diplomatic Rival will be compared here through prestige, patron god, economic pressure and visible intentions."
	}
}

var _calendar_templates: Array[Dictionary] = [
	{"name": "Atlcahualo", "type": "Rain", "detail": "Opening rains", "tooltip": "Veintena 1 — Atlcahualo. Opening rain signs and early Tlaloc pressure."},
	{"name": "Tlacaxipehualiztli", "type": "War", "detail": "War rites", "tooltip": "Veintena 2 — Tlacaxipehualiztli. A good place for war omens, warrior preparation or public martial pressure."},
	{"name": "Tozoztontli", "type": "Maize", "detail": "Fields", "tooltip": "Veintena 3 — Tozoztontli. Farming, maize stores and early field labour need attention."},
	{"name": "Huey Tozoztli", "type": "Maize", "detail": "Great vigil", "tooltip": "Veintena 4 — Huey Tozoztli. A major agricultural pressure point for maize, food and offerings."},
	{"name": "Toxcatl", "type": "Ritual", "detail": "Offering", "tooltip": "Veintena 5 — Toxcatl. Ritual pressure and divine favour should be visible here."},
	{"name": "Etzalcualiztli", "type": "Rain", "detail": "Tlaloc", "tooltip": "Veintena 6 — Etzalcualiztli. Strong Tlaloc, water, rain and food-security pressure."},
	{"name": "Tecuilhuitontli", "type": "Palace", "detail": "Lords", "tooltip": "Veintena 7 — Tecuilhuitontli. A useful timing slot for noble, palace or status pressure."},
	{"name": "Huey Tecuilhuitl", "type": "Palace", "detail": "Great lords", "tooltip": "Veintena 8 — Huey Tecuilhuitl. A stronger palace, noble display or tribute pressure point."},
	{"name": "Tlaxochimaco", "type": "Ritual", "detail": "Flowers", "tooltip": "Veintena 9 — Tlaxochimaco. A ritual, offering or public celebration pressure point."},
	{"name": "Xocotl Huetzi", "type": "Ritual", "detail": "Festival", "tooltip": "Veintena 10 — Xocotl Huetzi. Festival pressure, offerings or public prestige can be surfaced here."},
	{"name": "Ochpaniztli", "type": "Market", "detail": "Sweeping", "tooltip": "Veintena 11 — Ochpaniztli. A good place to review stores, clear shortages and prepare obligations."},
	{"name": "Teotleco", "type": "Ritual", "detail": "Gods arrive", "tooltip": "Veintena 12 — Teotleco. Divine pressure, omens and religious events can become prominent."},
	{"name": "Tepeilhuitl", "type": "Rain", "detail": "Mountains", "tooltip": "Veintena 13 — Tepeilhuitl. Mountain, rain and agricultural-risk pressure can be shown here."},
	{"name": "Quecholli", "type": "War", "detail": "Muster", "tooltip": "Veintena 14 — Quecholli. A good Flower Wars, hunting, warrior or military readiness period."},
	{"name": "Panquetzaliztli", "type": "War", "detail": "Huitzilopochtli", "tooltip": "Veintena 15 — Panquetzaliztli. Strong Huitzilopochtli, war, captives and martial-prestige pressure."},
	{"name": "Atemoztli", "type": "Rain", "detail": "Waters", "tooltip": "Veintena 16 — Atemoztli. Late water, rain, drought and Tlaloc-linked warnings fit here."},
	{"name": "Tititl", "type": "Warning", "detail": "Year-end", "tooltip": "Veintena 17 — Tititl. Late-year pressure, shortages and unresolved obligations should become visible."},
	{"name": "Izcalli", "type": "Warning", "detail": "Reckoning", "tooltip": "Veintena 18 — Izcalli. Final preparations before Nemontemi and annual reckoning."}
]

func _ready() -> void:
	_wire_buttons()
	_apply_style()
	refresh_calendar()
	refresh_notifications()
	show_location("estate")

func _wire_buttons() -> void:
	if estate_button:
		estate_button.pressed.connect(func() -> void: show_location("estate"))
	if fields_button:
		fields_button.pressed.connect(func() -> void: show_location("fields"))
	if storehouse_button:
		storehouse_button.pressed.connect(func() -> void: show_location("storehouse"))
	if workshops_button:
		workshops_button.pressed.connect(func() -> void: show_location("workshops"))
	if shrines_button:
		shrines_button.pressed.connect(func() -> void: show_location("shrines"))
	if warriors_button:
		warriors_button.pressed.connect(func() -> void: show_location("warriors"))
	if market_button:
		market_button.pressed.connect(func() -> void: show_location("market"))
	if palace_button:
		palace_button.pressed.connect(func() -> void: show_location("palace"))
	if rivals_button:
		rivals_button.pressed.connect(func() -> void: show_location("rivals"))
	if advance_turn_button:
		advance_turn_button.pressed.connect(_on_advance_turn_pressed)

func show_location(location_id: String) -> void:
	current_location_id = location_id
	var data: Dictionary = _location_text.get(location_id, _location_text["estate"])
	if location_title:
		location_title.text = String(data.get("title", "Estate"))
	if content_text:
		content_text.text = String(data.get("body", ""))
	if location_art:
		location_art.texture = _art_for_location(location_id)
	_update_button_pressed_state()

func _art_for_location(location_id: String) -> Texture2D:
	match location_id:
		"estate":
			return estate_art
		"fields":
			return fields_art
		"storehouse":
			return storehouse_art
		"workshops":
			return workshops_art
		"shrines":
			return shrines_art
		"warriors":
			return warriors_art
		"market":
			return market_art
		"palace":
			return palace_art
		"rivals":
			return rivals_art
	return null

func _update_button_pressed_state() -> void:
	var button_map: Dictionary = {
		"estate": estate_button,
		"fields": fields_button,
		"storehouse": storehouse_button,
		"workshops": workshops_button,
		"shrines": shrines_button,
		"warriors": warriors_button,
		"market": market_button,
		"palace": palace_button,
		"rivals": rivals_button
	}
	for key in button_map.keys():
		var button: Button = button_map[key] as Button
		if button:
			button.button_pressed = key == current_location_id

func refresh_calendar() -> void:
	if calendar_card_row == null:
		return
	for child in calendar_card_row.get_children():
		child.queue_free()

	var start_index: int = clampi(current_veintena - 1, 0, _calendar_templates.size() - 1)
	var end_index: int = mini(start_index + visible_veintenas, _calendar_templates.size())
	for i in range(start_index, end_index):
		var card_data: Dictionary = _calendar_templates[i].duplicate()
		card_data["number"] = i + 1
		card_data["is_current"] = i == start_index
		calendar_card_row.add_child(_make_veintena_card(card_data))

func _make_veintena_card(data: Dictionary) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(150, 94)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = String(data.get("tooltip", ""))

	var style: StyleBoxFlat = _make_panel_style(Color(0.055, 0.08, 0.075, 0.92), Color(0.33, 0.70, 0.62, 0.55), 10)
	if bool(data.get("is_current", false)):
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
	stack.add_theme_constant_override("separation", 1)
	margin.add_child(stack)

	var number_label: Label = Label.new()
	number_label.text = "Veintena %s" % String.num_int64(int(data.get("number", 0)))
	number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_label.add_theme_font_size_override("font_size", 13)
	stack.add_child(number_label)

	var name_label: Label = Label.new()
	name_label.text = String(data.get("name", ""))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 11)
	stack.add_child(name_label)

	var type_label: Label = Label.new()
	type_label.text = String(data.get("type", "?"))
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 13)
	stack.add_child(type_label)

	var detail_label: Label = Label.new()
	detail_label.text = String(data.get("detail", ""))
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.clip_text = true
	detail_label.add_theme_font_size_override("font_size", 11)
	stack.add_child(detail_label)

	return card

func refresh_notifications() -> void:
	if notification_list == null:
		return
	for child in notification_list.get_children():
		child.queue_free()

	var messages: Array[String] = [
		"Veintena %s of 18 is active." % String.num_int64(current_veintena),
		"Palace tribute pressure is visible in the calendar row.",
		"Weapons and fine textiles are likely early bottlenecks.",
		"Use Storehouse for stockpiles instead of crowding the top bar."
	]
	for message in messages:
		notification_list.add_child(_make_notification_label(message))

func _make_notification_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = "• " + text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	return label

func _on_advance_turn_pressed() -> void:
	current_veintena += 1
	if current_veintena > 18:
		current_veintena = 1
	refresh_calendar()
	refresh_notifications()

func _apply_style() -> void:
	var panel_nodes: Array[Node] = [
		get_node_or_null(^"SafeArea/MainVBox/CalendarPanel"),
		get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView"),
		get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel"),
		get_node_or_null(^"SafeArea/MainVBox/BottomNav")
	]
	for node in panel_nodes:
		var panel: PanelContainer = node as PanelContainer
		if panel:
			panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.055, 0.052, 0.90), Color(0.34, 0.71, 0.63, 0.45), 14))

	if location_title:
		location_title.add_theme_font_size_override("font_size", 26)
	if content_text:
		content_text.add_theme_font_size_override("normal_font_size", 16)

	for button in [estate_button, fields_button, storehouse_button, workshops_button, shrines_button, warriors_button, market_button, palace_button, rivals_button, advance_turn_button]:
		if button:
			button.custom_minimum_size = Vector2(0, 48)
			button.add_theme_font_size_override("font_size", 15)
			if button != advance_turn_button:
				button.toggle_mode = true

func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	return style
