# ShrineScreenController.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/ShrineScreenController.gd
#
# Extracted Shrines / Religion UI controller.
# GameScreenMarketOverviewPatch.gd remains the active screen coordinator.
# This controller owns shrine main-view and shrine report-card composition, but
# mutable religion state is now obtained from runtime/CampaignState via
# UIScreenContext. Runtime metadata remains only as an old-file fallback.
extends RefCounted

const SHRINE_RITUAL_RULES_SCRIPT: Script = preload("res://Scripts/Systems/ShrineRitualRules.gd")
const RELIGION_STATE_SYSTEM_SCRIPT: Script = preload("res://Scripts/Systems/ReligionStateSystem.gd")
const RELIGION_STATE_META_KEY: String = "tr_religion_state_system" # fallback only

const COLOR_TEXT: Color = Color(0.92, 0.88, 0.78, 1.0)
const COLOR_MUTED: Color = Color(0.70, 0.78, 0.74, 1.0)
const COLOR_TEAL: Color = Color(0.50, 0.92, 0.84, 1.0)

# Display defaults only. Authoritative turn decay values live in TurnResolutionSystem.
const RELIGION_DISPLAY_STARTING_FAVOUR: float = 40.0
const RELIGION_DISPLAY_NORMAL_DECAY: float = 2.0
const RELIGION_DISPLAY_NEMONTEMI_DECAY: float = 4.0
const GOD_IDS: Array[String] = ["tlaloc", "huitzilopochtli", "tezcatlipoca", "quetzalcoatl"]

var host: Node = null
var content_root: Control = null
var content_text: RichTextLabel = null
var dynamic_view_host: VBoxContainer = null
var notification_list: VBoxContainer = null
var screen_context: RefCounted = null

var _selected_shrine_panel_id: String = ""
var _calendar_period: String = "veintena"

func show_content(host_node: Node, content_root_node: Control, content_text_node: RichTextLabel, dynamic_view_host_node: VBoxContainer) -> void:
	host = host_node
	content_root = content_root_node
	content_text = content_text_node
	dynamic_view_host = dynamic_view_host_node
	_sync_calendar_from_host()
	_show_shrine_content()

func build_reports(host_node: Node) -> void:
	host = host_node
	_sync_calendar_from_host()
	_build_shrine_reports()

func reset_panel_selection() -> void:
	_selected_shrine_panel_id = ""

# Legacy compatibility bridge only. Normal turn decay now belongs to TurnResolutionSystem.
func apply_divine_favour_decay(host_node: Node, report: Array, decay_amount: float = RELIGION_DISPLAY_NORMAL_DECAY) -> void:
	host = host_node
	_sync_calendar_from_host()
	_apply_divine_favour_decay(report, decay_amount)

# Legacy compatibility bridge only. TurnResolutionSystem resets ritual capacity after decay.
func reset_religion_veintena_capacity(host_node: Node) -> void:
	host = host_node
	_reset_religion_veintena_capacity()

func current_festival_god_id(host_node: Node) -> String:
	host = host_node
	_sync_calendar_from_host()
	return _current_festival_god_id()

func current_festival_text(host_node: Node) -> String:
	host = host_node
	_sync_calendar_from_host()
	return _current_festival_text()

func show_content_with_context(context: RefCounted) -> void:
	_apply_screen_context(context)
	_sync_calendar_from_host()
	_show_shrine_content()

func build_reports_with_context(context: RefCounted) -> void:
	_apply_screen_context(context)
	_sync_calendar_from_host()
	_build_shrine_reports()

# Legacy compatibility bridge only. Kept so older wrappers fail softly.
func apply_divine_favour_decay_with_context(context: RefCounted, report: Array, decay_amount: float = RELIGION_DISPLAY_NORMAL_DECAY) -> void:
	_apply_screen_context(context)
	_sync_calendar_from_host()
	_apply_divine_favour_decay(report, decay_amount)

# Legacy compatibility bridge only. Kept so older wrappers fail softly.
func reset_religion_veintena_capacity_with_context(context: RefCounted) -> void:
	_apply_screen_context(context)
	_reset_religion_veintena_capacity()

func current_festival_god_id_with_context(context: RefCounted) -> String:
	_apply_screen_context(context)
	_sync_calendar_from_host()
	return _current_festival_god_id()

func current_festival_text_with_context(context: RefCounted) -> String:
	_apply_screen_context(context)
	_sync_calendar_from_host()
	return _current_festival_text()

func _apply_screen_context(context: RefCounted) -> void:
	if context == null:
		return
	screen_context = context
	var raw_host: Variant = context.get("host")
	if raw_host is Node:
		host = raw_host as Node
	var raw_root: Variant = context.get("content_root")
	if raw_root is Control:
		content_root = raw_root as Control
	var raw_text: Variant = context.get("content_text")
	if raw_text is RichTextLabel:
		content_text = raw_text as RichTextLabel
	var raw_dynamic: Variant = context.get("dynamic_view_host")
	if raw_dynamic is VBoxContainer:
		dynamic_view_host = raw_dynamic as VBoxContainer
	var raw_notifications: Variant = context.get("notification_list")
	if raw_notifications is VBoxContainer:
		notification_list = raw_notifications as VBoxContainer

# -----------------------------------------------------------------------------
# Host bridge helpers
# -----------------------------------------------------------------------------

func _sync_calendar_from_host() -> void:
	var state: Node = _state()
	if state != null:
		# Patch 8G: CampaignState is the calendar authority. Prefer the
		# TRGameState facade snapshot before temporary metadata mirrors.
		if state.has_method("get_campaign_state_snapshot"):
			var snapshot_raw: Variant = state.call("get_campaign_state_snapshot")
			if snapshot_raw is RefCounted and (snapshot_raw as RefCounted).has_method("get_calendar_period_value"):
				_calendar_period = String((snapshot_raw as RefCounted).call("get_calendar_period_value"))
				return
		if state.has_method("get_calendar_period"):
			_calendar_period = String(state.call("get_calendar_period"))
			return
		if state.has_meta("calendar_period"):
			_calendar_period = String(state.get_meta("calendar_period"))
			return
		var state_period: Variant = state.get("calendar_period")
		if state_period != null:
			_calendar_period = String(state_period)
			return
	# Wrapper-owned _calendar_period was removed in Patch 8F. Keep no host fallback
	# here so Shrine festival focus does not silently depend on UI-owned state.

func _state() -> Node:
	if host != null and host.has_method("_state"):
		var raw: Variant = host.call("_state")
		if raw is Node:
			return raw as Node
	return null

func _current_focus_id() -> String:
	if host != null and host.has_method("_current_focus_id"):
		return String(host.call("_current_focus_id"))
	return "overview"

func _set_content_root_layout(expanded: bool) -> void:
	if host != null and host.has_method("_set_content_root_layout"):
		host.call("_set_content_root_layout", expanded)

func _make_panel_style(bg_colour: Color, border_colour: Color, radius: int = 10) -> StyleBox:
	if host != null and host.has_method("_make_panel_style"):
		var raw: Variant = host.call("_make_panel_style", bg_colour, border_colour, radius)
		if raw is StyleBox:
			return raw as StyleBox
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_colour
	style.border_color = border_colour
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

func _refresh_all() -> void:
	if host != null and host.has_method("_refresh_all"):
		host.call("_refresh_all")

func _refresh_main_content() -> void:
	if host != null and host.has_method("_refresh_main_content"):
		host.call("_refresh_main_content")

func _refresh_right_panel() -> void:
	if host != null and host.has_method("_refresh_right_panel"):
		host.call("_refresh_right_panel")

func _add_notification(text: String) -> void:
	if host != null and host.has_method("_add_notification"):
		host.call("_add_notification", text)

func _add_notification_control(control: Control) -> void:
	if host == null or control == null:
		return
	var list_variant: Variant = host.get("notification_list")
	if list_variant is Node:
		(list_variant as Node).add_child(control)

func _calendar_current_veintena() -> int:
	if host != null and host.has_method("_calendar_current_veintena"):
		return int(host.call("_calendar_current_veintena"))
	return 1

func _calendar_god_for_veintena(veintena_number: int) -> String:
	if host != null and host.has_method("_calendar_god_for_veintena"):
		return String(host.call("_calendar_god_for_veintena", veintena_number))
	return ""

# -----------------------------------------------------------------------------
# Religion / Shrine Upgrades + Tiered Rituals v2
# -----------------------------------------------------------------------------

func _religion_state() -> RefCounted:
	# Patch 8H: the Shrine UI does not own religion state. Prefer the shared UI
	# context, which returns a CampaignState-backed ReligionStateSystem. Metadata is
	# retained only as fallback for older local files.
	if screen_context != null and screen_context.has_method("religion_state_system"):
		var context_raw: Variant = screen_context.call("religion_state_system")
		if context_raw is RefCounted:
			return context_raw as RefCounted
	var runtime_state: Node = _state()
	if runtime_state != null:
		if runtime_state.has_method("get_religion_state_system"):
			var public_raw: Variant = runtime_state.call("get_religion_state_system")
			if public_raw is RefCounted:
				return public_raw as RefCounted
		if runtime_state.has_method("_get_religion_state_system"):
			var private_raw: Variant = runtime_state.call("_get_religion_state_system")
			if private_raw is RefCounted:
				return private_raw as RefCounted
		if runtime_state.has_method("get_campaign_state_snapshot"):
			var snapshot_raw: Variant = runtime_state.call("get_campaign_state_snapshot")
			if snapshot_raw is RefCounted:
				var campaign_backed: RefCounted = RELIGION_STATE_SYSTEM_SCRIPT.new() as RefCounted
				if campaign_backed.has_method("bind_campaign_state"):
					campaign_backed.call("bind_campaign_state", snapshot_raw as RefCounted, GOD_IDS)
				return campaign_backed
		if runtime_state.has_meta(RELIGION_STATE_META_KEY):
			var meta_raw: Variant = runtime_state.get_meta(RELIGION_STATE_META_KEY)
			if meta_raw is RefCounted:
				return meta_raw as RefCounted
		var runtime_owned: RefCounted = RELIGION_STATE_SYSTEM_SCRIPT.new() as RefCounted
		runtime_state.set_meta(RELIGION_STATE_META_KEY, runtime_owned)
		return runtime_owned
	return null

func _ensure_religion_state() -> void:
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("ensure"):
		system.call("ensure", GOD_IDS)

func _religion_favour(god_id: String) -> float:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("favour"):
		return float(system.call("favour", god_id, RELIGION_DISPLAY_STARTING_FAVOUR))
	return RELIGION_DISPLAY_STARTING_FAVOUR

func _set_religion_favour(god_id: String, value: float) -> void:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("set_favour"):
		system.call("set_favour", god_id, value)

func _religion_offering_report() -> Array[String]:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	var output: Array[String] = []
	if system != null and system.has_method("last_offering_report"):
		var raw: Variant = system.call("last_offering_report")
		if raw is Array:
			var raw_array: Array = raw as Array
			for item: Variant in raw_array:
				output.append(String(item))
	return output

func _clear_religion_offering_report() -> void:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("clear_offering_report"):
		system.call("clear_offering_report")

func _append_religion_offering_report(line: String) -> void:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("append_offering_report"):
		system.call("append_offering_report", line)

func _religion_ritual_capacity_used() -> float:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("ritual_capacity_used"):
		return float(system.call("ritual_capacity_used"))
	return 0.0

func _add_religion_ritual_capacity(amount: float) -> void:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("add_ritual_capacity"):
		system.call("add_ritual_capacity", amount)

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
	var value_label: Label = _religion_label(_format_religion_amount(_religion_favour(god_id)) + " / 100", 21, _god_colour(god_id))
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
	bar.value = clampf(_religion_favour(god_id), 0.0, 100.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 24)
	bar.add_theme_stylebox_override("background", _make_panel_style(Color(0.03, 0.04, 0.04, 0.84), Color(0.15, 0.18, 0.18, 0.5), 6))
	bar.add_theme_stylebox_override("fill", _make_panel_style(_god_colour(god_id).darkened(0.15), _god_colour(god_id), 6))
	parent.add_child(bar)

func _religion_ritual_prestige_value(tier_id: String) -> float:
	return float(SHRINE_RITUAL_RULES_SCRIPT.religion_ritual_prestige_value(tier_id))


func _religion_shrine_level_prestige_value(level: int) -> float:
	return float(SHRINE_RITUAL_RULES_SCRIPT.religion_shrine_level_prestige_value(level))


func _award_religion_prestige(amount: float, source_id: String, detail: String, context: Dictionary = {}) -> float:
	if amount <= 0.0001:
		return 0.0
	var state: Node = _state()
	if state != null and state.has_method("add_player_prestige"):
		state.call("add_player_prestige", amount, source_id, detail, context)
		return amount
	return 0.0

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
	var level_prestige: float = _religion_shrine_level_prestige_value(next_level)
	stack.add_child(_religion_wrapped_label("Upgrade to Level " + str(next_level) + " cost: " + _format_cost(cost) + ". Requires " + str(_shrine_level_priest_requirement(next_level)) + " active priests. Prestige on upgrade: +" + _format_religion_amount(level_prestige) + ".", 17, COLOR_MUTED))
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
	parent.add_child(_religion_wrapped_label("Shrine levels and rituals now create Prestige as public signs of devotion. Individual shrine upgrades still improve ritual rolls and favour decay, but do not create separate hidden Prestige bonuses.", 17, COLOR_MUTED))
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
	stack.add_child(_religion_wrapped_label("Favour roll: +" + str(int(range[0])) + " to +" + str(int(range[1])) + ". Current favour: " + _format_religion_amount(_religion_favour(god_id)) + "/100.", 16, COLOR_TEAL))
	stack.add_child(_religion_wrapped_label("Prestige on successful ritual: +" + _format_religion_amount(_religion_ritual_prestige_value(tier_id)) + ". Prestige is score only and is never spent.", 15, Color(0.96, 0.82, 0.48, 1.0)))
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


func _build_sacrifice_prestige_cards(parent: VBoxContainer, god_id: String) -> void:
	var heading: Label = _religion_label("Sacrifices", 24, COLOR_TEXT)
	parent.add_child(heading)
	parent.add_child(_religion_wrapped_label("Sacrifices create religious Prestige and favour with the selected god. Prestige is score only and is never spent. Captives remain far more important than sacrificing priests or Tlacotin.", 17, COLOR_MUTED))
	var state: Node = _state()
	if state == null or not state.has_method("get_sacrifice_prestige_options"):
		parent.add_child(_religion_wrapped_label("Sacrifice Prestige backend is not connected.", 18, Color(1.0, 0.74, 0.40, 1.0)))
		return
	var raw_options: Variant = state.call("get_sacrifice_prestige_options")
	if not (raw_options is Array):
		parent.add_child(_religion_wrapped_label("No sacrifice options are available.", 18, COLOR_MUTED))
		return
	var options: Array = raw_options as Array
	for option_variant: Variant in options:
		if option_variant is Dictionary:
			_add_sacrifice_prestige_card(parent, god_id, option_variant as Dictionary)

func _add_sacrifice_prestige_card(parent: VBoxContainer, god_id: String, option: Dictionary) -> void:
	var option_id: String = String(option.get("id", ""))
	var available: int = int(option.get("available", 0))
	var prestige_each: float = float(option.get("prestige_each", 0.0))
	var favour_each: float = float(option.get("favour_each", option.get("favour_preview_one", prestige_each)))
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border: Color = _god_colour(god_id)
	if available <= 0:
		border = Color(0.55, 0.55, 0.50, 0.45)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.045, 0.045, 0.76), border, 9))
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
	stack.add_child(_religion_label(String(option.get("name", "Sacrifice")), 21, COLOR_TEXT))
	stack.add_child(_religion_wrapped_label(String(option.get("description", "")), 16, COLOR_MUTED))
	stack.add_child(_religion_wrapped_label("Available: " + str(available) + ". Prestige per sacrifice: +" + _format_religion_amount(prestige_each) + ". Favour with " + _god_name(god_id) + ": +" + _format_religion_amount(favour_each) + ".", 16, COLOR_TEAL))
	var button: Button = Button.new()
	button.text = "Sacrifice 1 " + String(option.get("name", ""))
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 18)
	button.disabled = available <= 0
	button.tooltip_text = "Sacrifice one for +" + _format_religion_amount(prestige_each) + " Prestige and +" + _format_religion_amount(favour_each) + " favour with " + _god_name(god_id) + "."
	button.pressed.connect(func() -> void:
		_sacrifice_one_for_prestige(god_id, option_id)
	)
	stack.add_child(button)
	if available <= 0:
		stack.add_child(_religion_wrapped_label("Blocked: none available.", 15, Color(1.0, 0.74, 0.40, 1.0)))

func _sacrifice_one_for_prestige(god_id: String, sacrifice_id: String) -> void:
	var state: Node = _state()
	_clear_religion_offering_report()
	if state == null or not state.has_method("sacrifice_for_prestige"):
		_append_religion_offering_report("Sacrifice failed: backend is not connected.")
		_refresh_all()
		return
	var result_variant: Variant = state.call("sacrifice_for_prestige", sacrifice_id, 1, god_id)
	if result_variant is Dictionary:
		var result: Dictionary = result_variant as Dictionary
		if bool(result.get("ok", false)):
			var favour_gain: float = float(result.get("favour_gain", 0.0))
			if favour_gain > 0.0001 and god_id != "":
				var before: float = _religion_favour(god_id)
				var after: float = clampf(before + favour_gain, 0.0, 100.0)
				_set_religion_favour(god_id, after)
				_append_religion_offering_report(String(result.get("message", result.get("reason", "Sacrifice resolved."))) + " " + _god_name(god_id) + " favour " + _format_religion_amount(before) + " → " + _format_religion_amount(after) + ".")
			else:
				_append_religion_offering_report(String(result.get("message", result.get("reason", "Sacrifice resolved."))))
		else:
			_append_religion_offering_report(String(result.get("reason", "Sacrifice failed.")))
	else:
		_append_religion_offering_report("Sacrifice resolved.")
	_emit_religion_state_changed()
	_refresh_all()

func _shrine_level(god_id: String) -> int:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("shrine_level"):
		return int(system.call("shrine_level", god_id))
	return 1

func _set_shrine_level(god_id: String, level: int) -> void:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("set_shrine_level"):
		system.call("set_shrine_level", god_id, level)

func _purchased_upgrade_ids(god_id: String) -> Array[String]:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("purchased_upgrade_ids"):
		var raw: Variant = system.call("purchased_upgrade_ids", god_id)
		var output: Array[String] = []
		if raw is Array:
			var raw_array: Array = raw as Array
			for item: Variant in raw_array:
				output.append(String(item))
		return output
	return []

func _has_shrine_upgrade(god_id: String, upgrade_id: String) -> bool:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("has_upgrade"):
		return bool(system.call("has_upgrade", god_id, upgrade_id))
	return _purchased_upgrade_ids(god_id).has(upgrade_id)

func _add_shrine_upgrade_to_state(god_id: String, upgrade_id: String) -> void:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("add_upgrade"):
		system.call("add_upgrade", god_id, upgrade_id)

func _unlocked_ritual_text(god_id: String) -> String:
	var level: int = _shrine_level(god_id)
	if level >= 3:
		return "Minor, Medium and Large"
	if level >= 2:
		return "Minor and Medium"
	return "Minor"

func _shrine_level_description(level: int) -> String:
	return String(SHRINE_RITUAL_RULES_SCRIPT.shrine_level_description(level))


func _shrine_level_cost(next_level: int) -> Dictionary:
	return SHRINE_RITUAL_RULES_SCRIPT.shrine_level_cost(next_level) as Dictionary


func _shrine_level_priest_requirement(next_level: int) -> int:
	return int(SHRINE_RITUAL_RULES_SCRIPT.shrine_level_priest_requirement(next_level))


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
		_clear_religion_offering_report()
		_append_religion_offering_report("Shrine upgrade failed: " + String(status.get("reason", "")))
		_refresh_all()
		return
	var next_level: int = _shrine_level(god_id) + 1
	_pay_religion_cost(_shrine_level_cost(next_level))
	_set_shrine_level(god_id, next_level)
	var prestige_gain: float = _religion_shrine_level_prestige_value(next_level)
	var report_line: String = _god_name(god_id) + " Shrine upgraded to Level " + str(next_level) + ". " + _shrine_level_description(next_level)
	if prestige_gain > 0.0001:
		_award_religion_prestige(prestige_gain, "religion_shrine_level", _god_name(god_id) + " Shrine Level " + str(next_level), {"god_id": god_id, "shrine_level": next_level})
		report_line += " Prestige +" + _format_religion_amount(prestige_gain) + "."
	_clear_religion_offering_report()
	_append_religion_offering_report(report_line)
	var state: Node = _state()
	if state != null:
		var report_variant: Variant = state.get("last_report")
		if report_variant is Array:
			var report: Array = report_variant as Array
			report.append(report_line)
			state.set("last_report", report)
	_emit_religion_state_changed()
	_refresh_all()

func _god_upgrade_definitions(god_id: String) -> Array[Dictionary]:
	return SHRINE_RITUAL_RULES_SCRIPT.god_upgrade_definitions(god_id)


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
		_clear_religion_offering_report()
		_append_religion_offering_report("Shrine upgrade failed: " + String(status.get("reason", "")))
		_refresh_all()
		return
	_pay_religion_cost(upgrade.get("cost", {}) as Dictionary)
	_add_shrine_upgrade_to_state(god_id, upgrade_id)
	_clear_religion_offering_report()
	_append_religion_offering_report("Built " + String(upgrade.get("title", "upgrade")) + " for " + _god_name(god_id) + ". " + _upgrade_effect_text(upgrade) + ".")
	_emit_religion_state_changed()
	_refresh_all()

func _ritual_data(god_id: String, tier_id: String) -> Dictionary:
	return SHRINE_RITUAL_RULES_SCRIPT.ritual_data(god_id, tier_id) as Dictionary


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
		_clear_religion_offering_report()
		_append_religion_offering_report("Ritual failed: " + String(status.get("reason", "")))
		_refresh_all()
		return
	var data: Dictionary = _ritual_data(god_id, tier_id)
	_pay_religion_cost(data.get("cost", {}) as Dictionary)
	_add_religion_ritual_capacity(float(data.get("capacity", 0.0)))
	var range: Array = _ritual_favour_range(god_id, tier_id)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var gain: int = rng.randi_range(int(range[0]), int(range[1]))
	var before: float = _religion_favour(god_id)
	var after: float = clampf(before + float(gain), 0.0, 100.0)
	_set_religion_favour(god_id, after)
	var report_line: String = String(data.get("title", "Ritual")) + " performed for " + _god_name(god_id) + ". Cost: " + _format_cost(data.get("cost", {}) as Dictionary) + ". Favour roll: +" + str(gain) + " (range +" + str(int(range[0])) + "–+" + str(int(range[1])) + "). Favour " + _format_religion_amount(before) + " → " + _format_religion_amount(after) + "."
	if _current_festival_god_id() == god_id:
		report_line += " Festival focus improved the ritual roll."
	if _ritual_favour_bonus(god_id, tier_id) > 0:
		report_line += " Shrine level/upgrades contributed to the result."
	var prestige_gain: float = _religion_ritual_prestige_value(tier_id)
	if prestige_gain > 0.0001:
		_award_religion_prestige(prestige_gain, "religion_ritual", String(data.get("title", "Ritual")) + " for " + _god_name(god_id), {"god_id": god_id, "tier_id": tier_id, "favour_gain": gain})
		report_line += " Prestige +" + _format_religion_amount(prestige_gain) + "."
	_clear_religion_offering_report()
	_append_religion_offering_report(report_line)
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
		_add_shrine_report_card("god|" + god_id + "|sacrifices", "Sacrifices", "Captives, priests and Tlacotin can be sacrificed for religious Prestige and favour.", god_id)
		_add_shrine_report_card("god|" + god_id + "|boons", "Boons", "Future favour-spending powers unlocked by higher shrine development.", god_id)

	var offering_report: Array[String] = _religion_offering_report()
	if offering_report.is_empty():
		_add_notification("No ritual or shrine upgrade has been performed this session yet.")
	else:
		for line: String in offering_report:
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
	_add_notification_control(button)

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
		"sacrifices":
			_build_sacrifice_prestige_cards(parent, god_id)
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
	var favour: float = _religion_favour(god_id)
	parent.add_child(_religion_wrapped_label(_god_short_role(god_id), 19, _god_colour(god_id)))
	_add_favour_bar(parent, god_id)
	parent.add_child(_religion_wrapped_label("Current favour: " + _format_religion_amount(favour) + "/100 — " + _favour_band(favour) + ".", 20, COLOR_TEXT))
	parent.add_child(_religion_wrapped_label("Normal decay next Veintena: -" + _format_religion_amount(_religion_decay_for_god(god_id, RELIGION_DISPLAY_NORMAL_DECAY)) + ". Nemontemi decay: -" + _format_religion_amount(_religion_decay_for_god(god_id, RELIGION_DISPLAY_NEMONTEMI_DECAY)) + ".", 18, COLOR_MUTED))
	parent.add_child(_religion_wrapped_label("Active upgrades reduce decay and improve ritual rolls while enough priests are supported.", 18, COLOR_MUTED))

func _build_priest_capacity_panel(parent: VBoxContainer) -> void:
	parent.add_child(_religion_wrapped_label("Priests limit how much ritual work can be performed in a single Veintena. This prevents the player from dumping unlimited goods into favour in one turn.", 19, COLOR_MUTED))
	parent.add_child(_religion_wrapped_label("Active priests: " + str(_religion_active_priest_count()) + ". Capacity used: " + _format_religion_amount(_religion_ritual_capacity_used()) + " / " + _format_religion_amount(_religion_priest_conversion_cap()) + ". Remaining: " + _format_religion_amount(_religion_remaining_ritual_capacity()) + ".", 20, COLOR_TEAL))
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
	var offering_report: Array[String] = _religion_offering_report()
	if offering_report.is_empty():
		parent.add_child(_religion_wrapped_label("No ritual or shrine upgrade has been performed this session yet.", 20, COLOR_MUTED))
		return
	for line: String in offering_report:
		parent.add_child(_religion_wrapped_label("• " + line, 19, COLOR_TEXT))

func _build_god_boons_placeholder(parent: VBoxContainer, god_id: String) -> void:
	parent.add_child(_religion_wrapped_label("Boons are the future favour-spending layer. They should consume favour for strong god-specific actions once farming, Flower Wars, rivals and palace systems exist.", 19, COLOR_MUTED))
	parent.add_child(_religion_wrapped_label(_god_name(god_id) + " boon direction: " + _god_description(god_id), 18, COLOR_MUTED))
	if _shrine_level(god_id) < 4:
		parent.add_child(_religion_wrapped_label("Upgrade this shrine to Level 4 before late shrine boons become available.", 18, Color(1.0, 0.74, 0.40, 1.0)))
	else:
		parent.add_child(_religion_wrapped_label("Shrine Level 4 reached. This shrine is ready for future boon implementation.", 18, COLOR_TEAL))

# Legacy decay implementation used only by the compatibility bridge above.
# Authoritative turn decay lives in TurnResolutionSystem.
func _apply_divine_favour_decay(report: Array, decay_amount: float = RELIGION_DISPLAY_NORMAL_DECAY) -> void:
	_ensure_religion_state()
	var parts: Array[String] = []
	for god_id: String in GOD_IDS:
		var before: float = _religion_favour(god_id)
		var actual_decay: float = _religion_decay_for_god(god_id, decay_amount)
		var after: float = clampf(before - actual_decay, 0.0, 100.0)
		_set_religion_favour(god_id, after)
		parts.append(_god_name(god_id) + " " + _format_religion_amount(before) + "→" + _format_religion_amount(after))
	report.append("Divine favour decays: " + "; ".join(parts) + ".")

func _religion_decay_for_god(god_id: String, base_decay: float) -> float:
	var reduction: float = 0.0
	for upgrade_id: String in _purchased_upgrade_ids(god_id):
		var upgrade: Dictionary = _upgrade_by_id(god_id, upgrade_id)
		if not upgrade.is_empty() and _upgrade_is_active(upgrade):
			reduction += float(upgrade.get("decay_reduction", 0.0))
	return maxf(0.0, base_decay - reduction)

# Legacy reset implementation used only by the compatibility bridge above.
func _reset_religion_veintena_capacity() -> void:
	_ensure_religion_state()
	var system: RefCounted = _religion_state()
	if system != null and system.has_method("reset_ritual_capacity"):
		system.call("reset_ritual_capacity")

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
	return maxf(0.0, _religion_priest_conversion_cap() - _religion_ritual_capacity_used())

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
	return String(SHRINE_RITUAL_RULES_SCRIPT.god_name(god_id))


func _god_short_role(god_id: String) -> String:
	return String(SHRINE_RITUAL_RULES_SCRIPT.god_short_role(god_id))


func _god_domain(god_id: String) -> String:
	return String(SHRINE_RITUAL_RULES_SCRIPT.god_domain(god_id))


func _god_description(god_id: String) -> String:
	return String(SHRINE_RITUAL_RULES_SCRIPT.god_description(god_id))


func _god_colour(god_id: String) -> Color:
	return SHRINE_RITUAL_RULES_SCRIPT.god_colour(god_id)


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
	if state != null:
		if state.has_method("_mirror_religion_state_from_campaign_state_to_legacy"):
			state.call("_mirror_religion_state_from_campaign_state_to_legacy")
		if state.has_signal("state_changed"):
			state.emit_signal("state_changed")


