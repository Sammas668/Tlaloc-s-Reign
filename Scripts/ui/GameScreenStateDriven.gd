# GameScreenStateDriven.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenStateDriven.gd
#
# State-driven wrapper over the existing GameScreen shell.
# Also applies larger, more readable text across the main game shell.
extends "res://Scripts/ui/GameScreen.gd"

const STATE_STOREHOUSE_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/StorehouseView.tscn")
const STATE_STOCKPILE_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/StockpileLedgerRow.tscn")
const STATE_MARKET_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/MarketView.tscn")
const STATE_MARKET_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/MarketLedgerRow.tscn")

@onready var chinampa_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/ChinampaButton") as Button
@onready var housing_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/HousingButton") as Button
@onready var teocalli_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/TeocalliButton") as Button
@onready var calmecac_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/CalmecacButton") as Button
@onready var tecpan_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/TecpanButton") as Button
@onready var yaotl_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/YaotlButton") as Button

# Renamed/new screens introduced by the current bottom-bar pass.
var _renamed_screen_profiles: Dictionary = {
	"chinampa": {
		"title": "Chinampa",
		"report_title": "Chinampa Reports",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Chinampa Overview", "body": "The chinampa screen covers estate farming, maize security, crop production, field labour and rain pressure.", "lines": ["Total agricultural output: placeholder", "Rain/drought modifier: placeholder", "Field labour coverage: placeholder"], "reports": ["Chinampa replaces the old Fields bottom-bar label.", "Maize should be the first real output connected here."]},
			{"id": "maize", "label": "Maize", "title": "Maize Chinampas", "body": "Maize is the food and ritual base of the estate.", "lines": ["Stored maize: placeholder", "Expected maize output: placeholder", "Population food demand: placeholder", "Tlaloc pressure: placeholder"], "reports": ["Warn before maize shortage hits upkeep.", "Tlaloc favour should affect this screen first."]},
			{"id": "cacao", "label": "Cacao", "title": "Cacao Gardens", "body": "Cacao supports status, ritual, tribute and high-value trade.", "lines": ["Cacao output: placeholder", "Cacao stored: placeholder", "Main uses: nobles, rituals, tecpan goods"], "reports": ["Cacao should feel valuable but not universal."]},
			{"id": "cotton", "label": "Cotton", "title": "Cotton Plots", "body": "Cotton feeds the cloth and fine textile chains.", "lines": ["Cotton output: placeholder", "Cotton stored: placeholder", "Linked buildings: Cloth Workshop, Fine Textile House"], "reports": ["Cotton pressure should foreshadow cloth and fine textile bottlenecks."]},
			{"id": "labour", "label": "Labour", "title": "Chinampa Labour", "body": "Farm labour determines whether land actually produces.", "lines": ["Assigned Macehualtin: placeholder", "Assigned Tlacotin: placeholder", "Unstaffed chinampas: placeholder"], "reports": ["Chinampa labour should compete with construction, workshops and war preparation."]},
			{"id": "rain", "label": "Rain", "title": "Rain & Tlaloc Pressure", "body": "Rain makes farming sacred as well as economic.", "lines": ["Rain outlook: uncertain", "Tlaloc favour: placeholder", "Drought risk: placeholder"], "reports": ["Rain pressure belongs here and in the Estate calendar."]}
		]
	},
	"housing": {
		"title": "Housing",
		"report_title": "Housing Reports",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Housing Overview", "body": "Housing and calpulli support determine how safely the estate can hold workers, families, specialists and dependants.", "lines": ["Free population capacity: placeholder", "Housing pressure: placeholder", "Most urgent housing need: placeholder"], "reports": ["Housing should limit safe growth rather than act as decoration.", "Overbuilding housing without food or work should create pressure later."]},
			{"id": "commoners", "label": "Commoners", "title": "Commoner Housing", "body": "Commoner housing supports Macehualtin labourers and the ordinary working base of the estate.", "lines": ["Macehualtin supported: placeholder", "Wood/cloth construction need: placeholder", "Food demand link: placeholder"], "reports": ["Commoner support protects the estate labour base."]},
			{"id": "tlacotin", "label": "Tlacotin", "title": "Tlacotin Quarters", "body": "Tlacotin quarters support enslaved or bonded labour capacity where the estate uses it.", "lines": ["Tlacotin capacity: placeholder", "Maize upkeep: placeholder", "Labour use: placeholder"], "reports": ["Special labour should remain distinct from ordinary free population."]},
			{"id": "specialists", "label": "Specialists", "title": "Specialist Housing", "body": "Specialist housing supports craftsmen, priests, warriors and nobles through the institutions that depend on them.", "lines": ["Tolteca support: placeholder", "Warrior support: placeholder", "Priest/noble support: placeholder"], "reports": ["Specialists should be useful but expensive to maintain."]},
			{"id": "pressure", "label": "Pressure", "title": "Housing Pressure", "body": "Housing pressure shows where population growth is becoming fragile.", "lines": ["Crowding: placeholder", "Food strain: placeholder", "Unmet support: placeholder"], "reports": ["Housing warnings should appear before population instability becomes severe."]}
		]
	},
	"teocalli": {
		"title": "Teocalli",
		"report_title": "Omens & Priest Reports",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Teocalli Overview", "body": "The teocalli is the estate's sacred centre for shrines, offerings, sacrifice and divine favour.", "lines": ["Tlaloc: placeholder", "Huitzilopochtli: placeholder", "Tezcatlipoca: placeholder", "Quetzalcoatl: placeholder"], "reports": ["Teocalli replaces the old Shrines bottom-bar label.", "Offerings to one god should mean neglecting another."]},
			{"id": "tlaloc", "label": "Tlaloc", "title": "Tlaloc Shrine", "body": "Tlaloc governs rain, maize and drought pressure.", "lines": ["Favour: placeholder", "Rain outlook: placeholder", "Maize risk: placeholder"], "reports": ["Tlaloc pressure should be most visible through farming."]},
			{"id": "huitzilopochtli", "label": "Huitzilopochtli", "title": "Huitzilopochtli Shrine", "body": "Huitzilopochtli governs war, captives and martial prestige.", "lines": ["Favour: placeholder", "Captives: placeholder", "War momentum: placeholder"], "reports": ["War success should feed religious value through captives."]},
			{"id": "tezcatlipoca", "label": "Tezcatlipoca", "title": "Tezcatlipoca Shrine", "body": "Tezcatlipoca governs power, danger, rivalry and political uncertainty.", "lines": ["Favour: placeholder", "Yaotl pressure: placeholder", "Risk events: placeholder"], "reports": ["This god should feel dangerous rather than simply beneficial."]},
			{"id": "quetzalcoatl", "label": "Quetzalcoatl", "title": "Quetzalcoatl Shrine", "body": "Quetzalcoatl governs legitimacy, order and recognition.", "lines": ["Favour: placeholder", "Stability link: placeholder", "Recognition link: placeholder"], "reports": ["Quetzalcoatl supports the civil face of authority."]},
			{"id": "offerings", "label": "Offerings", "title": "Offerings", "body": "Offerings transform maize, goods and captives into divine favour.", "lines": ["Maize offering: placeholder", "Goods offering: placeholder", "Captive sacrifice: placeholder"], "reports": ["Offering costs must compete with food, tecpan, war and construction."]}
		]
	},
	"calmecac": {
		"title": "Calmecac",
		"report_title": "Training Reports",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Calmecac Overview", "body": "The Calmecac represents elite training, discipline, military preparation and noble/priestly education.", "lines": ["Training capacity: placeholder", "Warrior readiness: placeholder", "Priest/noble education: placeholder"], "reports": ["Calmecac replaces the old Warriors bottom-bar label.", "This screen can cover warrior training, priest formation and elite discipline."]},
			{"id": "warriors", "label": "Warriors", "title": "Warrior Capacity", "body": "Warriors require food, support, weapons and training.", "lines": ["Yaotequihuaqueh supported: placeholder", "Training capacity: placeholder", "Warrior upkeep: placeholder"], "reports": ["Warriors are a costly population group, not free power."]},
			{"id": "weapons", "label": "Weapons", "title": "Weapons & Armour", "body": "Weapons and armour connect workshops to Flower Wars readiness.", "lines": ["Weapons: placeholder", "Armour: placeholder", "Replacement need: placeholder"], "reports": ["Equipment shortages should block or weaken war commitments."]},
			{"id": "flower_wars", "label": "Flower Wars", "title": "Flower Wars Commitment", "body": "Commit prepared warriors for captives, looted goods and prestige.", "lines": ["Available opportunity: placeholder", "Expected captives: placeholder", "Loss risk: placeholder"], "reports": ["Flower Wars should resolve strategically, not tactically."]},
			{"id": "priests", "label": "Priests", "title": "Priest Training", "body": "Priest training links elite education to ritual capacity and shrine operation.", "lines": ["Tlamacazqueh supported: placeholder", "Priest House capacity: placeholder", "Ritual support need: placeholder"], "reports": ["Priest capacity belongs here if Calmecac becomes the training institution screen."]},
			{"id": "returns", "label": "Returns", "title": "Captives, Loot & Losses", "body": "War returns feed the economy, religion and prestige race.", "lines": ["Captives gained: placeholder", "Looted goods: placeholder", "Warrior losses: placeholder"], "reports": ["Loot is secondary; captives remain the unique war output."]}
		]
	},
	"tecpan": {
		"title": "Tecpan",
		"report_title": "Tecpan Messages",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Tecpan Overview", "body": "The tecpan screen covers ruler obligations, tribute, recognition and political standing.", "lines": ["Royal favour: placeholder", "Prestige from tecpan service: placeholder", "Current demand: placeholder"], "reports": ["Tecpan replaces the old Palace bottom-bar label.", "The ruler should feel distant but consequential."]},
			{"id": "demand", "label": "Demand", "title": "Current Tecpan Demand", "body": "The ruler names desired goods that compete with local needs.", "lines": ["Desired raw good: placeholder", "Desired processed good: placeholder", "Desired luxury/special good: placeholder"], "reports": ["Demands should be predictable enough to plan around."]},
			{"id": "tribute", "label": "Tribute", "title": "Tribute Delivery", "body": "Tribute proves that the house is useful to the ruler.", "lines": ["Goods reserved for tribute: placeholder", "Delivery value: placeholder", "Failure risk: placeholder"], "reports": ["Tribute should cost enough to create opportunity cost."]},
			{"id": "favour", "label": "Favour", "title": "Royal Favour", "body": "Royal favour measures political acceptance from above.", "lines": ["Current favour: placeholder", "Recent change: placeholder", "Main risk: placeholder"], "reports": ["Royal favour should support recognition, not become spendable currency."]},
			{"id": "recognition", "label": "Recognition", "title": "Recognition", "body": "Recognition is the long-term claim to become the leading lordly house.", "lines": ["Player claim: placeholder", "Yaotl claim: placeholder", "Tecpan judgement: placeholder"], "reports": ["Victory should be recognition, not conquest."]}
		]
	},
	"yaotl": {
		"title": "Yaotl",
		"report_title": "Yaotl Reports",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Yaotl Overview", "body": "The Yaotl screen tracks rival houses, enemy pressure, prestige comparison and visible procurement behaviour.", "lines": ["Player prestige: placeholder", "War Rival prestige: placeholder", "Cunning Rival prestige: placeholder", "Diplomatic Rival prestige: placeholder"], "reports": ["Yaotl replaces the old Rivals bottom-bar label.", "Rivals should not be decorative score entries."]},
			{"id": "war", "label": "War", "title": "War Rival — Huitzilopochtli", "body": "The War Rival focuses on weapons, captives, Flower Wars and martial prestige.", "lines": ["Likely first build: Weapon Yard", "Primary hoards: obsidian, weapons, captives", "Procurement style: aggressive"], "reports": ["Watch obsidian, weapons and warrior capacity."]},
			{"id": "cunning", "label": "Cunning", "title": "Cunning Rival — Tezcatlipoca", "body": "The Cunning Rival focuses on market leverage, tools, cloth and hidden pressure.", "lines": ["Likely first build: Storehouse / Market Storage", "Primary hoards: tools, cloth, cacao", "Procurement style: opportunistic"], "reports": ["Watch practical bottlenecks and suspicious market behaviour."]},
			{"id": "diplomatic", "label": "Diplomatic", "title": "Diplomatic Rival — Quetzalcoatl", "body": "The Diplomatic Rival focuses on fine textiles, cacao, tribute goods and legitimacy.", "lines": ["Likely first build: Fine Textile House", "Primary hoards: fine textiles and cacao", "Procurement style: steady"], "reports": ["Watch tecpan-facing goods and status production."]},
			{"id": "prestige", "label": "Prestige", "title": "Prestige Race", "body": "Prestige makes every system comparative.", "lines": ["Economic prestige: placeholder", "War prestige: placeholder", "Ritual prestige: placeholder", "Tecpan prestige: placeholder"], "reports": ["The player should understand why each rival gained standing."]}
		]
	}
}

func _ready() -> void:
	_sync_veintena_from_state()
	super._ready()

func _game_state_node() -> Node:
	return get_node_or_null("/root/GameState")

func _estate_stockpile_rows() -> Array[Dictionary]:
	var state: Node = _game_state_node()
	if state != null and state.has_method("get_estate_stockpile_rows"):
		var result: Variant = state.call("get_estate_stockpile_rows")
		if result is Array:
			var rows: Array[Dictionary] = []
			for row_variant: Variant in result:
				rows.append(row_variant as Dictionary)
			return rows
	return _stockpiles

func _market_rows() -> Array[Dictionary]:
	var state: Node = _game_state_node()
	if state != null and state.has_method("get_market_rows"):
		var result: Variant = state.call("get_market_rows")
		if result is Array:
			var rows: Array[Dictionary] = []
			for row_variant: Variant in result:
				rows.append(row_variant as Dictionary)
			return rows
	return _market_goods

func _wire_buttons() -> void:
	if estate_button:
		estate_button.pressed.connect(func() -> void: show_location("estate"))
	if chinampa_button:
		chinampa_button.pressed.connect(func() -> void: show_location("chinampa"))
	if workshops_button:
		workshops_button.pressed.connect(func() -> void: show_location("workshops"))
	if storehouse_button:
		storehouse_button.pressed.connect(func() -> void: show_location("storehouse"))
	if housing_button:
		housing_button.pressed.connect(func() -> void: show_location("housing"))
	if teocalli_button:
		teocalli_button.pressed.connect(func() -> void: show_location("teocalli"))
	if calmecac_button:
		calmecac_button.pressed.connect(func() -> void: show_location("calmecac"))
	if market_button:
		market_button.pressed.connect(func() -> void: show_location("market"))
	if tecpan_button:
		tecpan_button.pressed.connect(func() -> void: show_location("tecpan"))
	if yaotl_button:
		yaotl_button.pressed.connect(func() -> void: show_location("yaotl"))
	if advance_turn_button:
		advance_turn_button.pressed.connect(_on_advance_turn_pressed)

func _profile_for_location(location_id: String) -> Dictionary:
	var normalized_id: String = _normalize_location_id(location_id)
	if _renamed_screen_profiles.has(normalized_id):
		return _renamed_screen_profiles[normalized_id] as Dictionary
	if _screen_profiles.has(normalized_id):
		return _screen_profiles[normalized_id] as Dictionary
	return _screen_profiles["estate"] as Dictionary

func _normalize_location_id(location_id: String) -> String:
	match location_id:
		"fields":
			return "chinampa"
		"shrines":
			return "teocalli"
		"warriors":
			return "calmecac"
		"palace":
			return "tecpan"
		"rivals":
			return "yaotl"
		_:
			return location_id

func show_location(location_id: String) -> void:
	current_location_id = _normalize_location_id(location_id)
	_ensure_focus_for_location(current_location_id)
	_refresh_top_area()
	_refresh_main_content()
	_refresh_right_panel()
	_update_button_pressed_state()

func show_focus(location_id: String, focus_id: String) -> void:
	current_location_id = _normalize_location_id(location_id)
	current_focus_by_location[current_location_id] = focus_id
	_refresh_top_area()
	_refresh_main_content()
	_refresh_right_panel()
	_update_button_pressed_state()

func _refresh_top_area() -> void:
	if top_row == null:
		return
	for child: Node in top_row.get_children():
		child.queue_free()

	var profile: Dictionary = _profile_for_location(current_location_id)
	var top_mode: String = String(profile.get("top_mode", "focus"))
	if top_mode == "calendar":
		_build_calendar_cards()
	else:
		_build_focus_buttons(profile)

func _build_calendar_cards() -> void:
	if top_row == null:
		return
	var start_index: int = clampi(current_veintena - 1, 0, _veintenas.size() - 1)
	var end_index: int = mini(start_index + visible_veintenas, _veintenas.size())
	for i: int in range(start_index, end_index):
		var data: Dictionary = _veintenas[i] as Dictionary
		var card_data: Dictionary = data.duplicate()
		card_data["number"] = i + 1
		card_data["is_current"] = i == start_index
		top_row.add_child(_make_readable_veintena_card(card_data))

func _make_readable_veintena_card(data: Dictionary) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(154, 98)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = "Veintena " + str(int(data.get("number", 0))) + " — " + String(data.get("name", "")) + ". " + String(data.get("tooltip", ""))

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

	_stack_label(stack, "Veintena " + str(int(data.get("number", 0))), 14)
	_stack_label(stack, String(data.get("name", "")), 13)
	_stack_label(stack, String(data.get("type", "?")), 15)
	_stack_label(stack, String(data.get("detail", "")), 13)
	return card

func _build_focus_buttons(profile: Dictionary) -> void:
	if top_row == null:
		return
	var focuses: Array = profile.get("focuses", []) as Array
	var focus_id: String = _current_focus_id()
	for focus_variant: Variant in focuses:
		var focus: Dictionary = focus_variant as Dictionary
		var button: Button = Button.new()
		button.text = String(focus.get("label", "Focus"))
		button.toggle_mode = true
		button.button_pressed = String(focus.get("id", "")) == focus_id
		button.custom_minimum_size = Vector2(118, 50)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 17)
		var next_focus_id: String = String(focus.get("id", "overview"))
		button.pressed.connect(func() -> void: show_focus(current_location_id, next_focus_id))
		top_row.add_child(button)

func _art_for_location(location_id: String) -> Texture2D:
	match _normalize_location_id(location_id):
		"estate":
			return estate_art
		"chinampa":
			return fields_art
		"workshops":
			return workshops_art
		"housing":
			return estate_art
		"teocalli":
			return shrines_art
		"calmecac":
			return warriors_art
		"market":
			return market_art
		"tecpan":
			return palace_art
		"yaotl":
			return rivals_art
		"storehouse":
			return storehouse_art
	return null

func _update_button_pressed_state() -> void:
	var button_map: Dictionary = {
		"estate": estate_button,
		"chinampa": chinampa_button,
		"workshops": workshops_button,
		"storehouse": storehouse_button,
		"housing": housing_button,
		"teocalli": teocalli_button,
		"calmecac": calmecac_button,
		"market": market_button,
		"tecpan": tecpan_button,
		"yaotl": yaotl_button
	}

	for key_variant: Variant in button_map.keys():
		var key: String = String(key_variant)
		var button: Button = button_map[key] as Button
		if button:
			button.button_pressed = key == current_location_id

func _apply_style() -> void:
	var panel_nodes: Array = [
		get_node_or_null(^"SafeArea/MainVBox/CalendarPanel"),
		get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView"),
		get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel"),
		get_node_or_null(^"SafeArea/MainVBox/BottomNav")
	]
	for node_variant: Variant in panel_nodes:
		var panel: PanelContainer = node_variant as PanelContainer
		if panel:
			panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.055, 0.052, 0.90), Color(0.34, 0.71, 0.63, 0.45), 14))

	if location_title:
		location_title.add_theme_font_size_override("font_size", 30)
	if notification_title:
		notification_title.add_theme_font_size_override("font_size", 22)
	if content_text:
		content_text.add_theme_font_size_override("normal_font_size", 19)
		content_text.add_theme_font_size_override("bold_font_size", 20)
		content_text.add_theme_stylebox_override("normal", _make_text_overlay_style())

	for button_variant: Variant in _bottom_nav_buttons():
		var button: Button = button_variant as Button
		if button:
			button.custom_minimum_size = Vector2(0, 50)
			button.add_theme_font_size_override("font_size", 15)
			if button != advance_turn_button:
				button.toggle_mode = true

func _bottom_nav_buttons() -> Array:
	return [
		estate_button,
		chinampa_button,
		workshops_button,
		storehouse_button,
		housing_button,
		teocalli_button,
		calmecac_button,
		market_button,
		tecpan_button,
		yaotl_button,
		advance_turn_button
	]

func _show_storehouse_view() -> void:
	if content_text:
		content_text.visible = false
	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return

	storehouse_view = STATE_STOREHOUSE_VIEW_SCENE.instantiate() as Control
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
		storehouse_view.call("setup", _estate_stockpile_rows(), _current_focus_id(), selected_storehouse_good_id)

func _show_market_view() -> void:
	if content_text:
		content_text.visible = false
	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return

	market_view = STATE_MARKET_VIEW_SCENE.instantiate() as Control
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
		market_view.call("setup", _market_rows(), _current_focus_id(), selected_market_good_id)

func _build_storehouse_ledger() -> void:
	var focus_id: String = _current_focus_id()
	var goods: Array[Dictionary] = _filtered_stockpiles(focus_id)
	for good_variant: Variant in goods:
		var good: Dictionary = good_variant as Dictionary
		var row: Button = STATE_STOCKPILE_LEDGER_ROW_SCENE.instantiate() as Button
		if row == null:
			continue
		notification_list.add_child(row)
		if row.has_signal("good_selected"):
			row.connect("good_selected", Callable(self, "_on_storehouse_good_selected"))
		if row.has_method("set_good_data"):
			row.call("set_good_data", good, String(good.get("id", "")) == selected_storehouse_good_id)

func _filtered_stockpiles(focus_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for good_variant: Variant in _estate_stockpile_rows():
		var good: Dictionary = good_variant as Dictionary
		var category: String = String(good.get("category", ""))
		var include_good: bool = false
		match focus_id:
			"overview":
				include_good = true
			"reserved":
				include_good = float(good.get("reserved", 0.0)) > 0.0
			_:
				include_good = category == focus_id
		if include_good:
			output.append(good)
	return output

func _build_market_ledger() -> void:
	var focus_id: String = _current_focus_id()
	var goods: Array[Dictionary] = _filtered_market_goods(focus_id)
	for good_variant: Variant in goods:
		var good: Dictionary = good_variant as Dictionary
		var row: Button = STATE_MARKET_LEDGER_ROW_SCENE.instantiate() as Button
		if row == null:
			continue
		notification_list.add_child(row)
		if row.has_signal("good_selected"):
			row.connect("good_selected", Callable(self, "_on_market_good_selected"))
		if row.has_method("set_good_data"):
			row.call("set_good_data", good, String(good.get("id", "")) == selected_market_good_id)

func _filtered_market_goods(focus_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for good_variant: Variant in _market_rows():
		var good: Dictionary = good_variant as Dictionary
		var category: String = String(good.get("category", ""))
		var include_good: bool = false
		match focus_id:
			"overview", "prices", "buy", "sell", "rivals", "reports":
				include_good = true
			_:
				include_good = category == focus_id
		if include_good:
			output.append(good)
	return output

func _on_market_good_selected(good_id: String) -> void:
	if selected_market_good_id == good_id:
		_refresh_right_panel()
		return

	selected_market_good_id = good_id
	if market_view != null and market_view.has_method("setup"):
		market_view.call("setup", _market_rows(), _current_focus_id(), selected_market_good_id)
	elif market_view != null and market_view.has_method("select_good"):
		market_view.call("select_good", good_id)
	_refresh_right_panel()

func _on_storehouse_good_selected(good_id: String) -> void:
	if selected_storehouse_good_id == good_id:
		_refresh_right_panel()
		return

	selected_storehouse_good_id = good_id
	if storehouse_view != null and storehouse_view.has_method("setup"):
		storehouse_view.call("setup", _estate_stockpile_rows(), _current_focus_id(), selected_storehouse_good_id)
	elif storehouse_view != null and storehouse_view.has_method("select_good"):
		storehouse_view.call("select_good", good_id)
	_refresh_right_panel()

func _on_advance_turn_pressed() -> void:
	var state: Node = _game_state_node()
	if state != null and state.has_method("advance_placeholder_turn"):
		state.call("advance_placeholder_turn")
		_sync_veintena_from_state()
	else:
		current_veintena += 1
		if current_veintena > 18:
			current_veintena = 1

	_refresh_top_area()
	_refresh_main_content()
	_refresh_right_panel()

func _sync_veintena_from_state() -> void:
	var state: Node = _game_state_node()
	if state == null:
		return
	var state_veintena: Variant = state.get("current_veintena")
	if typeof(state_veintena) == TYPE_INT or typeof(state_veintena) == TYPE_FLOAT:
		current_veintena = int(state_veintena)
