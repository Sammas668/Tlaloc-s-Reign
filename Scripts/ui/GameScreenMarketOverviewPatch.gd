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
extends "res://Scripts/ui/GameScreen.gd"

const TRADE_BASKET_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/TradeBasketView.tscn")

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

var _religion_initialized: bool = false
var _divine_favour: Dictionary = {}
var _last_offering_report: Array[String] = []
var _pending_offering_amounts: Dictionary = {}
var _offering_slider_controls: Dictionary = {}
var _offering_amount_labels: Dictionary = {}
var _offering_summary_label: RichTextLabel = null
var _offering_commit_button: Button = null
var _offering_target_god: String = "tlaloc"
var _shrine_levels: Dictionary = {}
var _shrine_upgrades: Dictionary = {}
var _ritual_capacity_used_this_veintena: float = 0.0
var _selected_shrine_panel_id: String = ""
var _optional_shrine_art_cache: Dictionary = {}

func _ready() -> void:
	_remove_shrine_offerings_focus()
	super._ready()

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
		_selected_shrine_panel_id = ""
	super.show_location(location_id)

func show_focus(location_id: String, focus_id: String) -> void:
	if location_id == "shrines":
		# The old Offerings tab has been removed; rituals now live inside each
		# god's Ritual Tiers panel. Redirect any stale/manual reference safely.
		if focus_id == "offerings":
			focus_id = "overview"
		_selected_shrine_panel_id = ""
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
	super._refresh_main_content()

func _refresh_right_panel() -> void:
	_clear_children(notification_list)
	var profile: Dictionary = _profile(current_location_id)
	if notification_title:
		notification_title.text = _report_title_for_current_focus(profile)

	_refresh_house_claim()

	if current_location_id == "shrines":
		_build_shrine_reports()
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
	return super._report_title_for_current_focus(profile)

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
# Religion / Shrine Upgrades + Tiered Rituals v2
# -----------------------------------------------------------------------------

func _ensure_religion_state() -> void:
	if _religion_initialized:
		return
	for god_id: String in GOD_IDS:
		_divine_favour[god_id] = RELIGION_STARTING_FAVOUR
		_shrine_levels[god_id] = 1
		_shrine_upgrades[god_id] = []
	_religion_initialized = true

func _show_shrine_content() -> void:
	_ensure_religion_state()
	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false

	# Shrine screens now behave like the other information views: the right-hand
	# report bar is the navigation layer, and the left image area only opens a
	# detail/action panel after the player selects a shrine report card.
	# With nothing selected, the shrine background art remains visible.
	if _selected_shrine_panel_id == "":
		if content_root:
			content_root.visible = false
		return

	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return
	dynamic_view_host.visible = true

	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.0, 0.0, 0.0, 0.64), Color(0.50, 0.82, 0.74, 0.36), 14))
	dynamic_view_host.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var title_label: Label = _religion_label(_shrine_panel_title(_selected_shrine_panel_id), 29, COLOR_TEXT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	header.add_child(title_label)

	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(48, 44)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(_on_shrine_panel_closed)
	header.add_child(close_button)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	_build_selected_shrine_panel(list, _selected_shrine_panel_id)

func _build_shrine_overview_content(root: VBoxContainer) -> void:
	var heading: Label = _religion_label("Divine Favour, Shrines & Rituals", 30, COLOR_TEXT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(heading)
	root.add_child(_religion_wrapped_label("Religion now uses shrine levels, shrine upgrades, priest capacity and fixed ritual tiers. Build stronger shrines, perform Minor / Medium / Large rituals, roll random favour gains, and spend real estate goods without creating Wealth.", 20, COLOR_MUTED))
	root.add_child(_religion_wrapped_label("Current ritual focus: " + _current_festival_text() + ". Remaining priest ritual capacity this Veintena: " + _format_religion_amount(_religion_remaining_ritual_capacity()) + " / " + _format_religion_amount(_religion_priest_conversion_cap()) + ".", 19, COLOR_TEAL))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	for god_id: String in GOD_IDS:
		_add_god_summary_panel(list, god_id)

func _build_god_content(root: VBoxContainer, god_id: String) -> void:
	if god_id == "":
		god_id = "tlaloc"
	var title: Label = _religion_label(_god_name(god_id), 30, COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(_religion_wrapped_label(_god_domain(god_id), 20, _god_colour(god_id)))
	root.add_child(_religion_wrapped_label(_god_description(god_id), 19, COLOR_MUTED))
	_add_favour_bar(root, god_id)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	_build_shrine_level_panel(list, god_id)
	_build_shrine_upgrade_cards(list, god_id)
	_build_ritual_tier_cards(list, god_id)

func _build_offerings_content(root: VBoxContainer, suggested_god_id: String) -> void:
	var title: Label = _religion_label("Offerings", 30, COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	if suggested_god_id == "":
		root.add_child(_religion_wrapped_label("No major god dominates this Veintena. This is a breathing-room period: conserve goods, upgrade shrines, or open a god tab to perform a ritual without a festival visibility bonus.", 20, COLOR_MUTED))
		_build_shrine_overview_content(root)
		return
	root.add_child(_religion_wrapped_label("The current festival focus is " + _god_name(suggested_god_id) + ". Rituals to this god roll extra favour this Veintena.", 20, COLOR_MUTED))
	_build_god_content(root, suggested_god_id)

func _add_god_summary_panel(parent: VBoxContainer, god_id: String) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.05, 0.05, 0.74), _god_colour(god_id), 10))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	stack.add_child(row)
	var name_label: Label = _religion_label(_god_name(god_id), 22, COLOR_TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var level_label: Label = _religion_label("Shrine L" + str(_shrine_level(god_id)), 19, COLOR_TEAL)
	level_label.custom_minimum_size = Vector2(120, 0)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(level_label)
	var value_label: Label = _religion_label(_format_religion_amount(float(_divine_favour.get(god_id, 0.0))) + " / 100", 21, _god_colour(god_id))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(140, 0)
	row.add_child(value_label)
	_add_favour_bar(stack, god_id)
	var upgrade_count: int = _purchased_upgrade_ids(god_id).size()
	stack.add_child(_religion_wrapped_label(_god_short_role(god_id), 17, COLOR_MUTED))
	stack.add_child(_religion_wrapped_label("Unlocked rituals: " + _unlocked_ritual_text(god_id) + ". Upgrades built: " + str(upgrade_count) + "/" + str(_god_upgrade_definitions(god_id).size()) + ".", 16, COLOR_MUTED))

func _add_favour_bar(parent: VBoxContainer, god_id: String) -> void:
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = clampf(float(_divine_favour.get(god_id, RELIGION_STARTING_FAVOUR)), 0.0, 100.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 24)
	bar.add_theme_stylebox_override("background", _make_panel_style(Color(0.03, 0.04, 0.04, 0.84), Color(0.15, 0.18, 0.18, 0.5), 6))
	bar.add_theme_stylebox_override("fill", _make_panel_style(_god_colour(god_id).darkened(0.15), _god_colour(god_id), 6))
	parent.add_child(bar)

func _build_shrine_level_panel(parent: VBoxContainer, god_id: String) -> void:
	var level: int = _shrine_level(god_id)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.015, 0.035, 0.035, 0.78), _god_colour(god_id), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	stack.add_child(_religion_label(_god_name(god_id) + " Shrine Level " + str(level), 24, COLOR_TEXT))
	stack.add_child(_religion_wrapped_label(_shrine_level_description(level), 17, COLOR_MUTED))
	stack.add_child(_religion_wrapped_label("Unlocked rituals: " + _unlocked_ritual_text(god_id) + ". Active priest support: " + str(_religion_active_priest_count()) + " priests.", 17, COLOR_TEAL))
	if level >= 4:
		stack.add_child(_religion_wrapped_label("Maximum shrine level reached. Level 4 is ready for future boon-spending systems.", 17, COLOR_MUTED))
		return
	var next_level: int = level + 1
	var cost: Dictionary = _shrine_level_cost(next_level)
	var status: Dictionary = _can_upgrade_shrine_level(god_id)
	stack.add_child(_religion_wrapped_label("Upgrade to Level " + str(next_level) + " cost: " + _format_cost(cost) + ". Requires " + str(_shrine_level_priest_requirement(next_level)) + " active priests.", 17, COLOR_MUTED))
	var button: Button = Button.new()
	button.text = "Upgrade Shrine to Level " + str(next_level)
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 20)
	button.disabled = not bool(status.get("ok", false))
	button.tooltip_text = String(status.get("reason", ""))
	button.pressed.connect(func() -> void:
		_upgrade_shrine_level(god_id)
	)
	stack.add_child(button)
	if not bool(status.get("ok", false)):
		stack.add_child(_religion_wrapped_label("Blocked: " + String(status.get("reason", "")), 16, Color(1.0, 0.74, 0.40, 1.0)))

func _build_shrine_upgrade_cards(parent: VBoxContainer, god_id: String) -> void:
	var heading: Label = _religion_label("Shrine Upgrades", 24, COLOR_TEXT)
	parent.add_child(heading)
	parent.add_child(_religion_wrapped_label("Upgrades make a shrine more powerful. They cost goods, require shrine level, and need enough active priests to function. Their mechanical effects are deliberately small now, but they already improve ritual rolls and favour decay.", 17, COLOR_MUTED))
	for upgrade: Dictionary in _god_upgrade_definitions(god_id):
		_add_single_upgrade_card(parent, god_id, upgrade)

func _add_single_upgrade_card(parent: VBoxContainer, god_id: String, upgrade: Dictionary) -> void:
	var upgrade_id: String = String(upgrade.get("id", ""))
	var purchased: bool = _has_shrine_upgrade(god_id, upgrade_id)
	var active: bool = purchased and _upgrade_is_active(upgrade)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border: Color = _god_colour(god_id)
	if not active:
		border = Color(0.55, 0.55, 0.50, 0.45)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.045, 0.045, 0.72), border, 8))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	var title: String = String(upgrade.get("title", "Upgrade"))
	var req_level: int = int(upgrade.get("level", 1))
	var req_priests: int = int(upgrade.get("priests", 0))
	var state_text: String = "Available"
	if purchased:
		state_text = "Active"
		if not active:
			state_text = "Built, but inactive"
	stack.add_child(_religion_label(title + " — " + state_text, 20, COLOR_TEXT))
	stack.add_child(_religion_wrapped_label(String(upgrade.get("description", "")), 16, COLOR_MUTED))
	stack.add_child(_religion_wrapped_label("Requires Shrine L" + str(req_level) + ", " + str(req_priests) + " active priests. Cost: " + _format_cost(upgrade.get("cost", {}) as Dictionary) + ". Effect: " + _upgrade_effect_text(upgrade) + ".", 15, COLOR_MUTED))
	if purchased:
		if active:
			stack.add_child(_religion_wrapped_label("This upgrade is functioning.", 15, Color(0.55, 1.0, 0.65, 1.0)))
		else:
			stack.add_child(_religion_wrapped_label("Inactive: not enough active priests are currently supported.", 15, Color(1.0, 0.74, 0.40, 1.0)))
		return
	var status: Dictionary = _can_build_shrine_upgrade(god_id, upgrade)
	var button: Button = Button.new()
	button.text = "Build Upgrade"
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 18)
	button.disabled = not bool(status.get("ok", false))
	button.tooltip_text = String(status.get("reason", ""))
	button.pressed.connect(func() -> void:
		_build_shrine_upgrade(god_id, upgrade_id)
	)
	stack.add_child(button)
	if not bool(status.get("ok", false)):
		stack.add_child(_religion_wrapped_label("Blocked: " + String(status.get("reason", "")), 15, Color(1.0, 0.74, 0.40, 1.0)))

func _build_ritual_tier_cards(parent: VBoxContainer, god_id: String) -> void:
	var heading: Label = _religion_label("Rituals", 24, COLOR_TEXT)
	parent.add_child(heading)
	parent.add_child(_religion_wrapped_label("Choose a fixed ritual tier. The favour gain is random within the shown range. Current festival focus and active shrine upgrades improve the roll. No ritual value is stored.", 17, COLOR_MUTED))
	for tier_id: String in ["minor", "medium", "large"]:
		_add_ritual_tier_card(parent, god_id, tier_id)

func _add_ritual_tier_card(parent: VBoxContainer, god_id: String, tier_id: String) -> void:
	var data: Dictionary = _ritual_data(god_id, tier_id)
	var status: Dictionary = _can_perform_ritual(god_id, tier_id)
	var range: Array = _ritual_favour_range(god_id, tier_id)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.045, 0.045, 0.76), _god_colour(god_id), 9))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_religion_label(String(data.get("title", tier_id.capitalize())), 21, COLOR_TEXT))
	stack.add_child(_religion_wrapped_label(String(data.get("description", "")), 16, COLOR_MUTED))
	stack.add_child(_religion_wrapped_label("Requires Shrine L" + str(int(data.get("level", 1))) + ". Cost: " + _format_cost(data.get("cost", {}) as Dictionary) + ". Priest capacity: " + _format_religion_amount(float(data.get("capacity", 0.0))) + ".", 15, COLOR_MUTED))
	stack.add_child(_religion_wrapped_label("Favour roll: +" + str(int(range[0])) + " to +" + str(int(range[1])) + ". Current favour: " + _format_religion_amount(float(_divine_favour.get(god_id, RELIGION_STARTING_FAVOUR))) + "/100.", 16, COLOR_TEAL))
	var button: Button = Button.new()
	button.text = "Perform " + String(data.get("title", "Ritual"))
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 19)
	button.disabled = not bool(status.get("ok", false))
	button.tooltip_text = String(status.get("reason", ""))
	button.pressed.connect(func() -> void:
		_perform_ritual(god_id, tier_id)
	)
	stack.add_child(button)
	if not bool(status.get("ok", false)):
		stack.add_child(_religion_wrapped_label("Blocked: " + String(status.get("reason", "")), 15, Color(1.0, 0.74, 0.40, 1.0)))

func _shrine_level(god_id: String) -> int:
	_ensure_religion_state()
	return clampi(int(_shrine_levels.get(god_id, 1)), 1, 4)

func _purchased_upgrade_ids(god_id: String) -> Array[String]:
	_ensure_religion_state()
	var output: Array[String] = []
	var raw: Array = _shrine_upgrades.get(god_id, []) as Array
	for item: Variant in raw:
		output.append(String(item))
	return output

func _has_shrine_upgrade(god_id: String, upgrade_id: String) -> bool:
	return _purchased_upgrade_ids(god_id).has(upgrade_id)

func _unlocked_ritual_text(god_id: String) -> String:
	var level: int = _shrine_level(god_id)
	if level >= 3:
		return "Minor, Medium and Large"
	if level >= 2:
		return "Minor and Medium"
	return "Minor"

func _shrine_level_description(level: int) -> String:
	match level:
		1:
			return "A founded household shrine. It supports Minor Rites and basic divine maintenance."
		2:
			return "An established shrine. It unlocks Medium Ceremonies and stronger upgrade branches."
		3:
			return "A major shrine. It unlocks Large Festivals and serious public religious statements."
		4:
			return "A regional religious complex. It prepares the shrine for future boon-spending and late-game divine power."
	return "Shrine level."

func _shrine_level_cost(next_level: int) -> Dictionary:
	match next_level:
		2:
			return {"wood": 20.0, "cloth": 6.0, "ritual_goods": 1.0}
		3:
			return {"wood": 50.0, "cloth": 15.0, "ritual_goods": 4.0, "cacao": 2.0}
		4:
			return {"wood": 100.0, "cloth": 30.0, "ritual_goods": 8.0, "cacao": 4.0, "fine_textiles": 1.0}
	return {}

func _shrine_level_priest_requirement(next_level: int) -> int:
	match next_level:
		2:
			return 2
		3:
			return 5
		4:
			return 8
	return 0

func _can_upgrade_shrine_level(god_id: String) -> Dictionary:
	var level: int = _shrine_level(god_id)
	if level >= 4:
		return {"ok": false, "reason": "Shrine is already Level 4."}
	var next_level: int = level + 1
	var priest_req: int = _shrine_level_priest_requirement(next_level)
	if _religion_active_priest_count() < priest_req:
		return {"ok": false, "reason": "Requires " + str(priest_req) + " active priests."}
	return _can_pay_religion_cost(_shrine_level_cost(next_level))

func _upgrade_shrine_level(god_id: String) -> void:
	var status: Dictionary = _can_upgrade_shrine_level(god_id)
	if not bool(status.get("ok", false)):
		_last_offering_report.clear()
		_last_offering_report.append("Shrine upgrade failed: " + String(status.get("reason", "")))
		_refresh_all()
		return
	var next_level: int = _shrine_level(god_id) + 1
	_pay_religion_cost(_shrine_level_cost(next_level))
	_shrine_levels[god_id] = next_level
	_last_offering_report.clear()
	_last_offering_report.append(_god_name(god_id) + " Shrine upgraded to Level " + str(next_level) + ". " + _shrine_level_description(next_level))
	_emit_religion_state_changed()
	_refresh_all()

func _god_upgrade_definitions(god_id: String) -> Array[Dictionary]:
	match god_id:
		"tlaloc":
			return [
				{"id": "rain_basin", "title": "Rain Basin", "level": 1, "priests": 1, "cost": {"wood": 8.0, "ritual_goods": 1.0}, "description": "A basin for reading water, clouds and lake signs.", "favour_bonus": 1, "decay_reduction": 0.0},
				{"id": "canal_offering_steps", "title": "Canal Offering Steps", "level": 2, "priests": 2, "cost": {"wood": 20.0, "cloth": 5.0, "ritual_goods": 2.0}, "description": "Ritual steps linking shrine offerings to fields, canals and chinampas.", "favour_bonus": 2, "decay_reduction": 0.25},
				{"id": "harvest_idol", "title": "Harvest Idol", "level": 3, "priests": 4, "cost": {"wood": 35.0, "cacao": 1.0, "ritual_goods": 4.0}, "description": "A major idol for harvest gratitude and drought protection hooks.", "favour_bonus": 3, "decay_reduction": 0.35},
				{"id": "storm_court", "title": "Storm Court", "level": 4, "priests": 6, "cost": {"wood": 70.0, "cloth": 15.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, "description": "A full court for future rain boons, drought softening and agricultural rites.", "favour_bonus": 5, "decay_reduction": 0.50}
			]
		"huitzilopochtli":
			return [
				{"id": "war_banners", "title": "War Banners", "level": 1, "priests": 1, "cost": {"wood": 8.0, "ritual_goods": 1.0}, "description": "Battle banners sanctify warrior musters and small martial rites.", "favour_bonus": 1, "decay_reduction": 0.0},
				{"id": "captive_stone", "title": "Captive Stone", "level": 2, "priests": 2, "cost": {"wood": 18.0, "cacao": 1.0, "ritual_goods": 2.0}, "description": "A ritual stone for future captive sacrifice and Flower War payoff.", "favour_bonus": 2, "decay_reduction": 0.20},
				{"id": "eagle_arsenal_altar", "title": "Eagle Arsenal Altar", "level": 3, "priests": 4, "cost": {"wood": 35.0, "cloth": 8.0, "ritual_goods": 4.0}, "description": "An altar binding weapon preparation to martial prestige.", "favour_bonus": 3, "decay_reduction": 0.30},
				{"id": "sun_war_court", "title": "Sun-War Court", "level": 4, "priests": 6, "cost": {"wood": 70.0, "cloth": 15.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, "description": "A full war court for future Flower War boons, captive yield and martial recognition.", "favour_bonus": 5, "decay_reduction": 0.45}
			]
		"tezcatlipoca":
			return [
				{"id": "obsidian_mirror", "title": "Obsidian Mirror", "level": 1, "priests": 1, "cost": {"wood": 8.0, "ritual_goods": 1.0}, "description": "A mirror for reading first omens and hidden danger.", "favour_bonus": 1, "decay_reduction": 0.0},
				{"id": "smoke_vestry", "title": "Smoke Vestry", "level": 2, "priests": 2, "cost": {"wood": 18.0, "cacao": 1.0, "ritual_goods": 2.0}, "description": "A chamber for controlled smoke rites, future warnings and rival pressure hooks.", "favour_bonus": 2, "decay_reduction": 0.25},
				{"id": "jaguar_shadow_wall", "title": "Jaguar Shadow Wall", "level": 3, "priests": 4, "cost": {"wood": 35.0, "cloth": 8.0, "ritual_goods": 4.0}, "description": "A symbolic barrier against plots, scandals and sabotage.", "favour_bonus": 3, "decay_reduction": 0.35},
				{"id": "night_court", "title": "Night Court", "level": 4, "priests": 6, "cost": {"wood": 70.0, "cloth": 15.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, "description": "A court for future intrigue boons, counter-plots and hidden information.", "favour_bonus": 5, "decay_reduction": 0.50}
			]
		"quetzalcoatl":
			return [
				{"id": "feathered_brazier", "title": "Feathered Brazier", "level": 1, "priests": 1, "cost": {"wood": 8.0, "ritual_goods": 1.0}, "description": "A civilising fire for transition rites and household legitimacy.", "favour_bonus": 1, "decay_reduction": 0.0},
				{"id": "scribe_mat", "title": "Scribe Mat", "level": 2, "priests": 2, "cost": {"wood": 18.0, "cacao": 1.0, "ritual_goods": 2.0}, "description": "A ritual space for record, order, tribute promises and palace-facing legitimacy.", "favour_bonus": 2, "decay_reduction": 0.25},
				{"id": "market_wind_gate", "title": "Market Wind Gate", "level": 3, "priests": 4, "cost": {"wood": 35.0, "cloth": 8.0, "ritual_goods": 4.0}, "description": "A ceremonial gate linking trade, diplomacy and public order.", "favour_bonus": 3, "decay_reduction": 0.35},
				{"id": "feathered_court", "title": "Feathered Court", "level": 4, "priests": 6, "cost": {"wood": 70.0, "cloth": 15.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, "description": "A full court for future recognition boons, ruler interactions and legitimacy protection.", "favour_bonus": 5, "decay_reduction": 0.50}
			]
	return []

func _upgrade_by_id(god_id: String, upgrade_id: String) -> Dictionary:
	for data: Dictionary in _god_upgrade_definitions(god_id):
		if String(data.get("id", "")) == upgrade_id:
			return data
	return {}

func _upgrade_is_active(upgrade: Dictionary) -> bool:
	return _religion_active_priest_count() >= int(upgrade.get("priests", 0))

func _upgrade_effect_text(upgrade: Dictionary) -> String:
	var parts: Array[String] = []
	var favour_bonus: int = int(upgrade.get("favour_bonus", 0))
	var decay_reduction: float = float(upgrade.get("decay_reduction", 0.0))
	if favour_bonus > 0:
		parts.append("+" + str(favour_bonus) + " ritual favour roll")
	if decay_reduction > 0.001:
		parts.append("-" + _format_religion_amount(decay_reduction) + " favour decay")
	if parts.is_empty():
		return "future system hook"
	return ", ".join(parts)

func _can_build_shrine_upgrade(god_id: String, upgrade: Dictionary) -> Dictionary:
	if _has_shrine_upgrade(god_id, String(upgrade.get("id", ""))):
		return {"ok": false, "reason": "Already built."}
	var req_level: int = int(upgrade.get("level", 1))
	if _shrine_level(god_id) < req_level:
		return {"ok": false, "reason": "Requires Shrine Level " + str(req_level) + "."}
	var req_priests: int = int(upgrade.get("priests", 0))
	if _religion_active_priest_count() < req_priests:
		return {"ok": false, "reason": "Requires " + str(req_priests) + " active priests."}
	return _can_pay_religion_cost(upgrade.get("cost", {}) as Dictionary)

func _build_shrine_upgrade(god_id: String, upgrade_id: String) -> void:
	var upgrade: Dictionary = _upgrade_by_id(god_id, upgrade_id)
	if upgrade.is_empty():
		return
	var status: Dictionary = _can_build_shrine_upgrade(god_id, upgrade)
	if not bool(status.get("ok", false)):
		_last_offering_report.clear()
		_last_offering_report.append("Shrine upgrade failed: " + String(status.get("reason", "")))
		_refresh_all()
		return
	_pay_religion_cost(upgrade.get("cost", {}) as Dictionary)
	var upgrades: Array[String] = _purchased_upgrade_ids(god_id)
	upgrades.append(upgrade_id)
	_shrine_upgrades[god_id] = upgrades
	_last_offering_report.clear()
	_last_offering_report.append("Built " + String(upgrade.get("title", "upgrade")) + " for " + _god_name(god_id) + ". " + _upgrade_effect_text(upgrade) + ".")
	_emit_religion_state_changed()
	_refresh_all()

func _ritual_data(god_id: String, tier_id: String) -> Dictionary:
	var title_prefix: String = "Ritual"
	match tier_id:
		"minor":
			title_prefix = "Minor Rite"
		"medium":
			title_prefix = "Medium Ceremony"
		"large":
			title_prefix = "Large Festival"
	var data: Dictionary = {"tier": tier_id, "title": title_prefix, "level": 1, "capacity": 4.0, "min": 3, "max": 7, "cost": {}, "description": ""}
	match tier_id:
		"minor":
			data["level"] = 1
			data["capacity"] = 4.0
			data["min"] = 3
			data["max"] = 7
		"medium":
			data["level"] = 2
			data["capacity"] = 10.0
			data["min"] = 8
			data["max"] = 16
		"large":
			data["level"] = 3
			data["capacity"] = 18.0
			data["min"] = 18
			data["max"] = 32
	match god_id:
		"tlaloc":
			if tier_id == "minor":
				data["cost"] = {"maize": 10.0}
				data["description"] = "A small food and water rite to maintain rain favour."
			elif tier_id == "medium":
				data["cost"] = {"maize": 25.0, "cacao": 1.0, "ritual_goods": 1.0}
				data["description"] = "A serious agricultural ceremony for rain, canals and fertility."
			else:
				data["cost"] = {"maize": 60.0, "cacao": 2.0, "ritual_goods": 3.0, "fine_textiles": 1.0}
				data["description"] = "A public harvest and rain festival with major future drought-protection hooks."
		"huitzilopochtli":
			if tier_id == "minor":
				data["cost"] = {"maize": 8.0, "ritual_goods": 1.0}
				data["description"] = "A small martial rite for warrior courage and public discipline."
			elif tier_id == "medium":
				data["cost"] = {"maize": 15.0, "cacao": 1.0, "ritual_goods": 2.0}
				data["description"] = "A warrior ceremony preparing the house for Flower Wars and sacrifice."
			else:
				data["cost"] = {"cacao": 2.0, "ritual_goods": 4.0, "fine_textiles": 1.0, "captives": 2.0}
				data["description"] = "A great war festival using captives for major future martial-prestige hooks."
		"tezcatlipoca":
			if tier_id == "minor":
				data["cost"] = {"cacao": 1.0}
				data["description"] = "A small omen rite using elite goods to read hidden pressure."
			elif tier_id == "medium":
				data["cost"] = {"cacao": 2.0, "ritual_goods": 2.0}
				data["description"] = "A smoke and mirror ceremony for intrigue, ambition and rival danger."
			else:
				data["cost"] = {"cacao": 4.0, "ritual_goods": 4.0, "fine_textiles": 1.0, "captives": 1.0}
				data["description"] = "A dangerous night festival for future sabotage, counter-plot and scandal hooks."
		"quetzalcoatl":
			if tier_id == "minor":
				data["cost"] = {"maize": 5.0, "cacao": 1.0}
				data["description"] = "A small legitimacy rite for order, wisdom and transition."
			elif tier_id == "medium":
				data["cost"] = {"cacao": 2.0, "ritual_goods": 1.0}
				data["description"] = "A civil ceremony for trade, diplomacy and palace-facing legitimacy."
			else:
				data["cost"] = {"cacao": 3.0, "ritual_goods": 3.0, "fine_textiles": 2.0}
				data["description"] = "A great ceremonial festival for future recognition and ruler-interaction hooks."
	return data

func _ritual_favour_range(god_id: String, tier_id: String) -> Array:
	var data: Dictionary = _ritual_data(god_id, tier_id)
	var min_value: int = int(data.get("min", 0))
	var max_value: int = int(data.get("max", 0))
	var bonus: int = _ritual_favour_bonus(god_id, tier_id)
	return [min_value + bonus, max_value + bonus]

func _ritual_favour_bonus(god_id: String, tier_id: String) -> int:
	var bonus: int = max(0, _shrine_level(god_id) - 1)
	if _current_festival_god_id() == god_id:
		match tier_id:
			"minor":
				bonus += 1
			"medium":
				bonus += 2
			"large":
				bonus += 4
	for upgrade_id: String in _purchased_upgrade_ids(god_id):
		var upgrade: Dictionary = _upgrade_by_id(god_id, upgrade_id)
		if not upgrade.is_empty() and _upgrade_is_active(upgrade):
			bonus += int(upgrade.get("favour_bonus", 0))
	return bonus

func _can_perform_ritual(god_id: String, tier_id: String) -> Dictionary:
	if _calendar_period == "nemontemi":
		return {"ok": false, "reason": "Rituals are suspended during Nemontemi."}
	var data: Dictionary = _ritual_data(god_id, tier_id)
	var req_level: int = int(data.get("level", 1))
	if _shrine_level(god_id) < req_level:
		return {"ok": false, "reason": "Requires Shrine Level " + str(req_level) + "."}
	var capacity_cost: float = float(data.get("capacity", 0.0))
	if _religion_remaining_ritual_capacity() + 0.001 < capacity_cost:
		return {"ok": false, "reason": "Not enough remaining priest ritual capacity this Veintena."}
	return _can_pay_religion_cost(data.get("cost", {}) as Dictionary)

func _perform_ritual(god_id: String, tier_id: String) -> void:
	var status: Dictionary = _can_perform_ritual(god_id, tier_id)
	if not bool(status.get("ok", false)):
		_last_offering_report.clear()
		_last_offering_report.append("Ritual failed: " + String(status.get("reason", "")))
		_refresh_all()
		return
	var data: Dictionary = _ritual_data(god_id, tier_id)
	_pay_religion_cost(data.get("cost", {}) as Dictionary)
	_ritual_capacity_used_this_veintena += float(data.get("capacity", 0.0))
	var range: Array = _ritual_favour_range(god_id, tier_id)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var gain: int = rng.randi_range(int(range[0]), int(range[1]))
	var before: float = float(_divine_favour.get(god_id, RELIGION_STARTING_FAVOUR))
	var after: float = clampf(before + float(gain), 0.0, 100.0)
	_divine_favour[god_id] = after
	var report_line: String = String(data.get("title", "Ritual")) + " performed for " + _god_name(god_id) + ". Cost: " + _format_cost(data.get("cost", {}) as Dictionary) + ". Favour roll: +" + str(gain) + " (range +" + str(int(range[0])) + "–+" + str(int(range[1])) + "). Favour " + _format_religion_amount(before) + " → " + _format_religion_amount(after) + "."
	if _current_festival_god_id() == god_id:
		report_line += " Festival focus improved the ritual roll."
	if _ritual_favour_bonus(god_id, tier_id) > 0:
		report_line += " Shrine level/upgrades contributed to the result."
	_last_offering_report.clear()
	_last_offering_report.append(report_line)
	var state: Node = _state()
	if state != null:
		var report_variant: Variant = state.get("last_report")
		if report_variant is Array:
			var report: Array = report_variant as Array
			report.append(report_line)
			state.set("last_report", report)
	_emit_religion_state_changed()
	_refresh_all()

func _can_pay_religion_cost(cost: Dictionary) -> Dictionary:
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(cost[resource_variant])
		if _free_stock_for_offering(resource_id) + 0.001 < needed:
			return {"ok": false, "reason": "Need " + _format_religion_amount(needed) + " free " + _resource_display_name(resource_id) + " after reserves."}
	return {"ok": true, "reason": "Ready."}

func _pay_religion_cost(cost: Dictionary) -> void:
	var state: Node = _state()
	if state == null:
		return
	var stock_variant: Variant = state.get("estate_stockpiles")
	if not (stock_variant is Dictionary):
		return
	var stockpiles: Dictionary = stock_variant as Dictionary
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		stockpiles[resource_id] = maxf(0.0, float(stockpiles.get(resource_id, 0.0)) - float(cost[resource_variant]))
	state.set("estate_stockpiles", stockpiles)

func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "none"
	var parts: Array[String] = []
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		parts.append(_resource_display_name(resource_id) + " " + _format_religion_amount(float(cost[resource_variant])))
	return ", ".join(parts)

func _build_shrine_reports() -> void:
	_ensure_religion_state()
	var focus_id: String = _current_focus_id()
	if focus_id == "offerings":
		focus_id = "overview"

	if focus_id == "overview":
		# Global religion information belongs only on the Overview tab.
		# Individual god tabs should stay focused on that god's shrine level,
		# upgrades, ritual tiers and future boons.
		_add_shrine_report_card("overview|favour", "Divine Favour", "All four favour meters, bands, decay and festival focus.", "")
		_add_shrine_report_card("overview|priests", "Priest Capacity", "Active priests, remaining ritual capacity and capacity spent this Veintena.", "")
		_add_shrine_report_card("overview|shrines", "Shrine Overview", "Levels, unlocked ritual tiers and upgrade progress for every god.", "")
		_add_shrine_report_card("overview|upgrades", "Upgrade Overview", "Built, available and locked upgrades across all shrines.", "")
		_add_shrine_report_card("overview|recent", "Recent Ritual Reports", "Last shrine upgrade, ritual result or religion warning.", "")
	else:
		var god_id: String = _god_id_from_focus(focus_id)
		if god_id == "":
			god_id = "tlaloc"
		_add_shrine_report_card("god|" + god_id + "|summary", _god_name(god_id) + " Summary", _god_short_role(god_id), god_id)
		_add_shrine_report_card("god|" + god_id + "|level", "Shrine Level", "Level " + str(_shrine_level(god_id)) + ". Unlocks: " + _unlocked_ritual_text(god_id) + ".", god_id)
		_add_shrine_report_card("god|" + god_id + "|upgrades", "Shrine Upgrades", str(_purchased_upgrade_ids(god_id).size()) + "/" + str(_god_upgrade_definitions(god_id).size()) + " built. Upgrade the shrine to strengthen rituals.", god_id)
		_add_shrine_report_card("god|" + god_id + "|rituals", "Ritual Tiers", "Minor, Medium and Large rites with fixed costs and random favour rolls.", god_id)
		_add_shrine_report_card("god|" + god_id + "|boons", "Boons", "Future favour-spending powers unlocked by higher shrine development.", god_id)

	if _last_offering_report.is_empty():
		_add_notification("No ritual or shrine upgrade has been performed this session yet.")
	else:
		for line: String in _last_offering_report:
			_add_notification(line)

func _add_shrine_report_card(panel_id: String, title: String, subtitle: String, god_id: String = "") -> void:
	var button: Button = Button.new()
	button.toggle_mode = true
	button.button_pressed = panel_id == _selected_shrine_panel_id
	button.custom_minimum_size = Vector2(0, 82)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	# Keep the Button itself textless and draw wrapped labels inside it.
	# Long shrine subtitles were overflowing into the right-hand border when they
	# were placed directly into Button.text.
	button.text = ""
	button.tooltip_text = title + " — " + subtitle
	var border: Color = COLOR_TEAL
	if god_id != "":
		border = _god_colour(god_id)
	if panel_id == _selected_shrine_panel_id:
		button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.08, 0.12, 0.11, 0.96), border.lightened(0.18), 10))
		button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.08, 0.12, 0.11, 0.96), border.lightened(0.18), 10))
	else:
		button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.035, 0.055, 0.052, 0.86), border.darkened(0.12), 10))
		button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.055, 0.08, 0.075, 0.94), border, 10))

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 10.0
	margin.offset_top = 7.0
	margin.offset_right = -10.0
	margin.offset_bottom = -7.0
	button.add_child(margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)

	var title_label: Label = Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.text = title
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", COLOR_TEXT)
	stack.add_child(title_label)

	var subtitle_label: Label = Label.new()
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_label.text = subtitle
	subtitle_label.clip_text = true
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle_label.add_theme_font_size_override("font_size", 13)
	subtitle_label.add_theme_color_override("font_color", COLOR_MUTED)
	stack.add_child(subtitle_label)

	button.pressed.connect(func() -> void:
		_on_shrine_panel_pressed(panel_id)
	)
	notification_list.add_child(button)

func _on_shrine_panel_pressed(panel_id: String) -> void:
	_selected_shrine_panel_id = panel_id
	_refresh_main_content()
	_refresh_right_panel()

func _on_shrine_panel_closed() -> void:
	_selected_shrine_panel_id = ""
	_refresh_main_content()
	_refresh_right_panel()

func _shrine_panel_title(panel_id: String) -> String:
	var parts: PackedStringArray = panel_id.split("|")
	if parts.size() >= 3 and String(parts[0]) == "god":
		var god_id: String = String(parts[1])
		var section: String = String(parts[2])
		match section:
			"summary":
				return _god_name(god_id) + " Shrine"
			"favour":
				return _god_name(god_id) + " Favour"
			"level":
				return _god_name(god_id) + " Shrine Level"
			"upgrades":
				return _god_name(god_id) + " Shrine Upgrades"
			"rituals":
				return _god_name(god_id) + " Rituals"
			"boons":
				return _god_name(god_id) + " Boons"
	if panel_id == "overview|favour":
		return "Divine Favour"
	if panel_id == "overview|priests":
		return "Priest Capacity"
	if panel_id == "overview|shrines":
		return "Shrine Overview"
	if panel_id == "overview|upgrades":
		return "Upgrade Overview"
	if panel_id == "overview|recent":
		return "Recent Ritual Reports"
	return "Shrine Report"

func _build_selected_shrine_panel(parent: VBoxContainer, panel_id: String) -> void:
	var parts: PackedStringArray = panel_id.split("|")
	if parts.size() >= 3 and String(parts[0]) == "god":
		var god_id: String = String(parts[1])
		var section: String = String(parts[2])
		_build_god_shrine_panel(parent, god_id, section)
		return
	match panel_id:
		"overview|favour":
			_build_divine_favour_panel(parent)
		"overview|priests":
			_build_priest_capacity_panel(parent)
		"overview|shrines":
			_build_all_shrines_overview_panel(parent)
		"overview|upgrades":
			_build_all_upgrades_overview_panel(parent)
		"overview|recent":
			_build_recent_ritual_reports_panel(parent)
		_:
			parent.add_child(_religion_wrapped_label("Select a shrine report from the right-hand bar.", 20, COLOR_MUTED))

func _build_god_shrine_panel(parent: VBoxContainer, god_id: String, section: String) -> void:
	if god_id == "":
		god_id = "tlaloc"
	match section:
		"summary":
			parent.add_child(_religion_wrapped_label(_god_domain(god_id), 20, _god_colour(god_id)))
			parent.add_child(_religion_wrapped_label(_god_description(god_id), 18, COLOR_MUTED))
			_add_favour_bar(parent, god_id)
			_add_god_summary_panel(parent, god_id)
		"favour":
			_build_single_god_favour_panel(parent, god_id)
		"level":
			_build_shrine_level_panel(parent, god_id)
		"upgrades":
			_build_shrine_upgrade_cards(parent, god_id)
		"rituals":
			_build_ritual_tier_cards(parent, god_id)
		"boons":
			_build_god_boons_placeholder(parent, god_id)
		_:
			parent.add_child(_religion_wrapped_label("Unknown shrine section.", 20, COLOR_MUTED))

func _build_divine_favour_panel(parent: VBoxContainer) -> void:
	parent.add_child(_religion_wrapped_label("Favour protects the estate from future god-linked dangers and will later power boons. It decays each Veintena, with harsher pressure during Nemontemi.", 19, COLOR_MUTED))
	parent.add_child(_religion_wrapped_label("Current ritual focus: " + _current_festival_text() + ".", 19, COLOR_TEAL))
	for god_id: String in GOD_IDS:
		_add_god_summary_panel(parent, god_id)

func _build_single_god_favour_panel(parent: VBoxContainer, god_id: String) -> void:
	var favour: float = float(_divine_favour.get(god_id, RELIGION_STARTING_FAVOUR))
	parent.add_child(_religion_wrapped_label(_god_short_role(god_id), 19, _god_colour(god_id)))
	_add_favour_bar(parent, god_id)
	parent.add_child(_religion_wrapped_label("Current favour: " + _format_religion_amount(favour) + "/100 — " + _favour_band(favour) + ".", 20, COLOR_TEXT))
	parent.add_child(_religion_wrapped_label("Normal decay next Veintena: -" + _format_religion_amount(_religion_decay_for_god(god_id, RELIGION_NORMAL_DECAY)) + ". Nemontemi decay: -" + _format_religion_amount(_religion_decay_for_god(god_id, RELIGION_NEMONTEMI_DECAY)) + ".", 18, COLOR_MUTED))
	parent.add_child(_religion_wrapped_label("Active upgrades reduce decay and improve ritual rolls while enough priests are supported.", 18, COLOR_MUTED))

func _build_priest_capacity_panel(parent: VBoxContainer) -> void:
	parent.add_child(_religion_wrapped_label("Priests limit how much ritual work can be performed in a single Veintena. This prevents the player from dumping unlimited goods into favour in one turn.", 19, COLOR_MUTED))
	parent.add_child(_religion_wrapped_label("Active priests: " + str(_religion_active_priest_count()) + ". Capacity used: " + _format_religion_amount(_ritual_capacity_used_this_veintena) + " / " + _format_religion_amount(_religion_priest_conversion_cap()) + ". Remaining: " + _format_religion_amount(_religion_remaining_ritual_capacity()) + ".", 20, COLOR_TEAL))
	parent.add_child(_religion_wrapped_label("Capacity resets when the Veintena advances. Later this should depend on functioning priest houses and shrine staffing rather than only population count.", 18, COLOR_MUTED))

func _build_all_shrines_overview_panel(parent: VBoxContainer) -> void:
	parent.add_child(_religion_wrapped_label("Each god begins with a Level 1 shrine. Higher levels unlock Medium Ceremonies, Large Festivals and future boon-spending powers.", 19, COLOR_MUTED))
	for god_id: String in GOD_IDS:
		_add_god_summary_panel(parent, god_id)

func _build_all_upgrades_overview_panel(parent: VBoxContainer) -> void:
	parent.add_child(_religion_wrapped_label("Shrine upgrades cost real goods, require shrine level, and need enough active priests to function. Built upgrades improve ritual favour rolls and reduce favour decay.", 19, COLOR_MUTED))
	for god_id: String in GOD_IDS:
		var built_count: int = _purchased_upgrade_ids(god_id).size()
		parent.add_child(_religion_label(_god_name(god_id) + " Upgrades — " + str(built_count) + "/" + str(_god_upgrade_definitions(god_id).size()) + " built", 22, _god_colour(god_id)))
		for upgrade: Dictionary in _god_upgrade_definitions(god_id):
			var upgrade_id: String = String(upgrade.get("id", ""))
			var status_text: String = "Locked / available later"
			if _has_shrine_upgrade(god_id, upgrade_id):
				if _upgrade_is_active(upgrade):
					status_text = "Built and active"
				else:
					status_text = "Built but inactive"
			else:
				var status: Dictionary = _can_build_shrine_upgrade(god_id, upgrade)
				if bool(status.get("ok", false)):
					status_text = "Buildable now"
				else:
					status_text = String(status.get("reason", "Locked"))
			parent.add_child(_religion_wrapped_label("• " + String(upgrade.get("title", "Upgrade")) + ": " + status_text + ". " + _upgrade_effect_text(upgrade) + ".", 16, COLOR_MUTED))

func _build_recent_ritual_reports_panel(parent: VBoxContainer) -> void:
	if _last_offering_report.is_empty():
		parent.add_child(_religion_wrapped_label("No ritual or shrine upgrade has been performed this session yet.", 20, COLOR_MUTED))
		return
	for line: String in _last_offering_report:
		parent.add_child(_religion_wrapped_label("• " + line, 19, COLOR_TEXT))

func _build_god_boons_placeholder(parent: VBoxContainer, god_id: String) -> void:
	parent.add_child(_religion_wrapped_label("Boons are the future favour-spending layer. They should consume favour for strong god-specific actions once farming, Flower Wars, rivals and palace systems exist.", 19, COLOR_MUTED))
	parent.add_child(_religion_wrapped_label(_god_name(god_id) + " boon direction: " + _god_description(god_id), 18, COLOR_MUTED))
	if _shrine_level(god_id) < 4:
		parent.add_child(_religion_wrapped_label("Upgrade this shrine to Level 4 before late shrine boons become available.", 18, Color(1.0, 0.74, 0.40, 1.0)))
	else:
		parent.add_child(_religion_wrapped_label("Shrine Level 4 reached. This shrine is ready for future boon implementation.", 18, COLOR_TEAL))

func _apply_divine_favour_decay(report: Array, decay_amount: float = RELIGION_NORMAL_DECAY) -> void:
	_ensure_religion_state()
	var parts: Array[String] = []
	for god_id: String in GOD_IDS:
		var before: float = float(_divine_favour.get(god_id, RELIGION_STARTING_FAVOUR))
		var actual_decay: float = _religion_decay_for_god(god_id, decay_amount)
		var after: float = clampf(before - actual_decay, 0.0, 100.0)
		_divine_favour[god_id] = after
		parts.append(_god_name(god_id) + " " + _format_religion_amount(before) + "→" + _format_religion_amount(after))
	report.append("Divine favour decays: " + "; ".join(parts) + ".")

func _religion_decay_for_god(god_id: String, base_decay: float) -> float:
	var reduction: float = 0.0
	for upgrade_id: String in _purchased_upgrade_ids(god_id):
		var upgrade: Dictionary = _upgrade_by_id(god_id, upgrade_id)
		if not upgrade.is_empty() and _upgrade_is_active(upgrade):
			reduction += float(upgrade.get("decay_reduction", 0.0))
	return maxf(0.0, base_decay - reduction)

func _reset_religion_veintena_capacity() -> void:
	_ritual_capacity_used_this_veintena = 0.0

func _free_stock_for_offering(resource_id: String) -> float:
	var state: Node = _state()
	if state == null:
		return 0.0
	if state.has_method("free_stock_after_reserves"):
		return maxf(0.0, float(state.call("free_stock_after_reserves", resource_id)))
	var stock_variant: Variant = state.get("estate_stockpiles")
	if stock_variant is Dictionary:
		var stockpiles: Dictionary = stock_variant as Dictionary
		return maxf(0.0, float(stockpiles.get(resource_id, 0.0)))
	return 0.0

func _religion_priest_conversion_cap() -> float:
	var priests: int = _religion_active_priest_count()
	return 8.0 + float(priests) * 2.0

func _religion_remaining_ritual_capacity() -> float:
	return maxf(0.0, _religion_priest_conversion_cap() - _ritual_capacity_used_this_veintena)

func _religion_active_priest_count() -> int:
	var state: Node = _state()
	if state == null:
		return 0
	var population_variant: Variant = state.get("population")
	if population_variant is Dictionary:
		var population_data: Dictionary = population_variant as Dictionary
		return int(population_data.get("tlamacazqueh", 0))
	return 0

func _favour_band(value: float) -> String:
	if value < 20.0:
		return "Neglected"
	if value < 40.0:
		return "Weak"
	if value < 60.0:
		return "Honoured"
	if value < 80.0:
		return "Favoured"
	return "Greatly favoured"

func _current_festival_god_id() -> String:
	if _calendar_period == "nemontemi":
		return ""
	var god_name: String = _calendar_god_for_veintena(_calendar_current_veintena())
	match god_name:
		"Tlaloc":
			return "tlaloc"
		"Huitzilopochtli":
			return "huitzilopochtli"
		"Tezcatlipoca":
			return "tezcatlipoca"
		"Quetzalcoatl":
			return "quetzalcoatl"
	return ""

func _current_festival_text() -> String:
	if _calendar_period == "nemontemi":
		return "Nemontemi — Unlucky Days"
	var god_id: String = _current_festival_god_id()
	if god_id == "":
		return "Minor / No major festival"
	return _god_name(god_id) + " festival"

func _god_id_from_focus(focus_id: String) -> String:
	match focus_id:
		"tlaloc":
			return "tlaloc"
		"huitzilopochtli":
			return "huitzilopochtli"
		"tezcatlipoca":
			return "tezcatlipoca"
		"quetzalcoatl":
			return "quetzalcoatl"
	return ""

func _god_name(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Tlaloc"
		"huitzilopochtli":
			return "Huitzilopochtli"
		"tezcatlipoca":
			return "Tezcatlipoca"
		"quetzalcoatl":
			return "Quetzalcoatl"
	return "Unknown God"

func _god_short_role(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Rain, lakes, agriculture, fertility, harvest and drought protection."
		"huitzilopochtli":
			return "War, sacrifice, Flower Wars, warriors, captives and martial prestige."
		"tezcatlipoca":
			return "Intrigue, fate, omens, ambition, manipulation and rival-house danger."
		"quetzalcoatl":
			return "Wisdom, legitimacy, trade, diplomacy, civilisation and transitions."
	return ""

func _god_domain(god_id: String) -> String:
	return _god_short_role(god_id)

func _god_description(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Build the Tlaloc shrine to strengthen rain, agriculture and harvest religion. Upgrades prepare future drought protection, maize output and water-omen systems."
		"huitzilopochtli":
			return "Build the Huitzilopochtli shrine to strengthen war religion. Upgrades prepare future Flower War, captive, warrior and martial-prestige systems."
		"tezcatlipoca":
			return "Build the Tezcatlipoca shrine to strengthen omen and intrigue religion. Upgrades prepare future sabotage warnings, rival disruption and scandal resistance."
		"quetzalcoatl":
			return "Build the Quetzalcoatl shrine to strengthen legitimacy, order and diplomacy. Upgrades prepare future palace interpretation, trade and recognition systems."
	return ""

func _god_colour(god_id: String) -> Color:
	match god_id:
		"tlaloc":
			return Color(0.22, 0.68, 0.86, 0.95)
		"huitzilopochtli":
			return Color(0.84, 0.35, 0.24, 0.95)
		"tezcatlipoca":
			return Color(0.62, 0.45, 0.84, 0.95)
		"quetzalcoatl":
			return Color(0.37, 0.82, 0.57, 0.95)
	return COLOR_MUTED

func _resource_display_name(resource_id: String) -> String:
	var state: Node = _state()
	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))
	return resource_id.replace("_", " ").capitalize()

func _religion_label(text: String, font_size: int, colour: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.clip_text = true
	return label

func _religion_wrapped_label(text: String, font_size: int, colour: Color) -> Label:
	var label: Label = _religion_label(text, font_size, colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	return label

func _format_religion_amount(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _emit_religion_state_changed() -> void:
	var state: Node = _state()
	if state != null and state.has_signal("state_changed"):
		state.emit_signal("state_changed")

# -----------------------------------------------------------------------------
# Calendar Pacing v2 — safe gameplay-led order
# -----------------------------------------------------------------------------

func _build_calendar_row() -> void:
	_refresh_calendar_advance_button_label()
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
	return {"period": "veintena", "year": year_value, "veintena": veintena_number, "name": name, "god": god, "detail": detail, "current": current, "report_id": report_id, "button_text": prefix + "\nY" + str(year_value) + " V" + str(veintena_number) + "\n" + god_label + "\n" + detail, "tooltip": "Ritual Year " + str(year_value) + ", Veintena " + str(veintena_number) + " — " + name + ". " + god + ": " + _calendar_tooltip_for_veintena(veintena_number)}

func _nemontemi_card_data(year_value: int, current: bool) -> Dictionary:
	var prefix: String = "Upcoming"
	if current:
		prefix = "Current"
	var report_id: String = "calendar|" + str(year_value) + "|nemontemi|0"
	return {"period": "nemontemi", "year": year_value, "veintena": 0, "name": "Nemontemi", "god": "Nemontemi", "detail": "Year review", "current": current, "report_id": report_id, "button_text": prefix + "\nY" + str(year_value) + "\nNemontemi\nUnlucky Days", "tooltip": "Nemontemi — five unlucky days, annual reckoning, restrictions, omens, review and next-year setup."}

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
	text += "[b]Gameplay pressure:[/b] " + _calendar_detail_for_veintena(veintena_number) + "\n\n"
	text += _calendar_tooltip_for_veintena(veintena_number) + "\n\n"
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

func _build_nemontemi_report_text(year_value: int) -> String:
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

# -----------------------------------------------------------------------------
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
