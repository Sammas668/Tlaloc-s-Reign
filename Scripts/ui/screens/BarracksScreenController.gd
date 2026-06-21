# BarracksScreenController.gd
# Godot 4.x
# Project path: res://Scripts/ui/screens/BarracksScreenController.gd
#
# Extracted Barracks / Warbands / Flower War bridge UI controller.
# GameScreenMarketOverviewPatch.gd remains the active screen coordinator; this
# controller owns the large Barracks content/report composition and keeps the
# extracted Flower War event modal + Warband Skill Web widget connected.
extends RefCounted

const WARBAND_SKILL_WEB_CANVAS_SCRIPT: Script = preload("res://Scripts/ui/widgets/WarbandSkillWebCanvas.gd")
const FLOWER_WAR_EVENT_OVERLAY_SCRIPT: Script = preload("res://Scripts/ui/widgets/FlowerWarEventOverlay.gd")
const WAR_DOCTRINE_RULES_SCRIPT: Script = preload("res://Scripts/Systems/WarDoctrineRules.gd")

const COLOR_TEXT: Color = Color(0.92, 0.88, 0.78, 1.0)
const COLOR_MUTED: Color = Color(0.70, 0.78, 0.74, 1.0)
const COLOR_TEAL: Color = Color(0.50, 0.92, 0.84, 1.0)

var host: Node = null
var content_root: Control = null
var content_text: RichTextLabel = null
var dynamic_view_host: VBoxContainer = null
var notification_list: VBoxContainer = null
var screen_context: RefCounted = null

var _selected_warband_skill_web_id: String = ""
var _selected_skill_web_node_id: String = ""
var _hovered_skill_web_node_id: String = ""
var _skill_web_pan_by_warband: Dictionary = {}
var _skill_web_zoom_by_warband: Dictionary = {}
var _last_skill_web_report: Array[String] = []
var _flower_war_event_overlay: Control = null
var _flower_war_event_option_id: String = "standard"
var _flower_war_event_provisioning_id: String = "standard"
var _flower_war_event_selected_warbands: Dictionary = {}
var _flower_war_event_report: Dictionary = {}
var _flower_war_defence_strategy_id: String = "balanced"

func show_content(host_node: Node, content_root_node: Control, content_text_node: RichTextLabel, dynamic_view_host_node: VBoxContainer) -> void:
	host = host_node
	content_root = content_root_node
	content_text = content_text_node
	dynamic_view_host = dynamic_view_host_node
	_show_barracks_content()

func build_reports(host_node: Node) -> void:
	host = host_node
	_build_barracks_reports()

func reset_skill_web_selection() -> void:
	_selected_warband_skill_web_id = ""
	_selected_skill_web_node_id = ""
	_hovered_skill_web_node_id = ""
	_last_skill_web_report.clear()

func open_attack_event(host_node: Node, option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> void:
	host = host_node
	_open_flower_war_attack_event(option_id, source_id, context)

func open_defence_event(host_node: Node, option_id: String = "standard", source_id: String = "rival", context: Dictionary = {}) -> void:
	host = host_node
	_open_flower_war_defence_event(option_id, source_id, context)

func show_content_with_context(context: RefCounted) -> void:
	_apply_screen_context(context)
	_show_barracks_content()

func build_reports_with_context(context: RefCounted) -> void:
	_apply_screen_context(context)
	_build_barracks_reports()

func open_attack_event_with_context(context: RefCounted, option_id: String = "standard", source_id: String = "player", event_context: Dictionary = {}) -> void:
	_apply_screen_context(context)
	_open_flower_war_attack_event(option_id, source_id, event_context)

func open_defence_event_with_context(context: RefCounted, option_id: String = "standard", source_id: String = "rival", event_context: Dictionary = {}) -> void:
	_apply_screen_context(context)
	_open_flower_war_defence_event(option_id, source_id, event_context)

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

func _format_float(value: float) -> String:
	if host != null and host.has_method("_format_float"):
		return String(host.call("_format_float", value))
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _format_religion_amount(value: float) -> String:
	if host != null and host.has_method("_format_religion_amount"):
		return String(host.call("_format_religion_amount", value))
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func _resource_display_name(resource_id: String) -> String:
	if host != null and host.has_method("_resource_display_name"):
		return String(host.call("_resource_display_name", resource_id))
	return resource_id.replace("_", " ").capitalize()

func _format_cost(cost: Dictionary) -> String:
	if host != null and host.has_method("_format_cost"):
		return String(host.call("_format_cost", cost))
	if cost.is_empty():
		return "none"
	var parts: Array[String] = []
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		parts.append(_resource_display_name(resource_id) + " " + _format_religion_amount(float(cost[resource_variant])))
	return ", ".join(parts)

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


func _clear_children(node: Node) -> void:
	if node == null:
		return
	if host != null and host.has_method("_clear_children"):
		host.call("_clear_children", node)
		return
	for child in node.get_children():
		child.queue_free()

# -----------------------------------------------------------------------------
# Barracks / Flower Wars UI v0.12.3 — instant hover detail patch over clean tiered draggable Skill Web UI
# -----------------------------------------------------------------------------

func _show_barracks_content() -> void:
	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false
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

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)

	match _current_focus_id():
		"warbands":
			_build_barracks_warbands_panel(root)
		"warriors":
			_build_barracks_warriors_panel(root)
		"weapons":
			_build_barracks_weapons_panel(root)
		"flower_wars":
			_build_barracks_flower_wars_panel(root)
		"returns":
			_build_barracks_returns_panel(root)
		_:
			_build_barracks_overview_panel(root)


func _format_signed_prestige_ui(amount: float) -> String:
	var prefix: String = "+" if amount >= 0.0 else ""
	return prefix + _format_religion_amount(amount)

func _build_barracks_reports() -> void:
	var focus_id: String = _current_focus_id()
	if focus_id == "flower_wars":
		_add_notification("Flower Wars now launch with all ready warbands. The selected-warband path is retained only as a safe debug wrapper.")
		_add_notification(_barracks_palace_gate_text())
		var rows: Array[Dictionary] = _barracks_warband_rows()
		var ready_total: int = 0
		for row: Dictionary in rows:
			ready_total += int(row.get("ready", row.get("warriors", 0)))
		_add_notification("All-warband muster: " + str(ready_total) + " ready warriors across " + str(rows.size()) + " warbands.")
		for option: Dictionary in _barracks_flower_options():
			var preview: Dictionary = _barracks_preview_for_all_warbands_option(option)
			_add_notification(String(option.get("name", "War")) + ": " + String(preview.get("result", "Preview unavailable")) + "; committed " + str(int(preview.get("committed_warriors", preview.get("warriors_committed", 0)))) + "; captives " + str(int(preview.get("captives", 0))) + "; losses " + str(int(preview.get("attacker_losses", preview.get("attacker_casualties", 0)))) + "; XP +" + str(int(preview.get("xp_gained", 0))) + "; Prestige " + _format_signed_prestige_ui(float(preview.get("prestige_gain", 0.0))) + ".")
		return
	if focus_id == "returns":
		for line: String in _barracks_last_report_lines():
			_add_notification(line)
		return
	if focus_id == "warbands":
		var rows: Array[Dictionary] = _barracks_warband_rows()
		if _selected_warband_skill_web_id != "":
			_build_barracks_skill_web_report_notifications(_selected_warband_skill_web_id)
			return
		_add_notification("Persistent warbands are now visible here. Reserve warriors can reinforce damaged bands. Injured warriors do not fight and return on the next Veintena advance.")
		if rows.is_empty():
			_add_notification("No warbands exist yet.")
		else:
			for row: Dictionary in rows:
				_add_notification(String(row.get("name", "Warband")) + ": ready " + str(int(row.get("ready", row.get("warriors", 0)))) + "; injured " + str(int(row.get("injured", 0))) + "; XP " + str(int(row.get("xp", 0))) + "; skill points " + str(int(row.get("trait_points", 0))) + "; specialisation " + String(row.get("specialisation_name", row.get("doctrine_name", "Unspecialised"))) + ".")
		return
	var summary: Dictionary = _barracks_summary()
	_add_notification("Warriors: " + str(int(summary.get("warriors", 0))) + " / capacity " + str(int(summary.get("capacity", 0))) + ".")
	_add_notification("Free warrior capacity: " + str(int(summary.get("free_capacity", 0))) + ".")
	_add_notification("Weapons available: " + _format_float(float(summary.get("weapons", 0.0))) + ".")
	_add_notification("Flower War Prestige is active: outcome, enemy casualties, captives and a small share of loot value create Prestige. Doctrine has no hidden Prestige bonus.")

func _build_barracks_overview_panel(parent: VBoxContainer) -> void:
	var summary: Dictionary = _barracks_summary()
	parent.add_child(_barracks_label("Barracks Overview", 31, COLOR_TEXT))
	parent.add_child(_barracks_wrapped_label("The Barracks now manages persistent warbands. Flower Wars commit every ready warband together, distribute casualties and XP across participating warbands. Palace-gate infrastructure exists, but the gate is temporarily inactive until the Palace screen is implemented.", 20, COLOR_MUTED))
	parent.add_child(_barracks_wrapped_label("Warriors: " + str(int(summary.get("warriors", 0))) + " / " + str(int(summary.get("capacity", 0))) + " capacity. Free capacity: " + str(int(summary.get("free_capacity", 0))) + ".", 22, COLOR_TEAL))
	parent.add_child(_barracks_wrapped_label("Weapons in Storehouse: " + _format_float(float(summary.get("weapons", 0.0))) + ". Captives held: " + str(int(summary.get("captives", 0))) + ".", 20, COLOR_MUTED))
	parent.add_child(_barracks_wrapped_label("Use Flower Wars to choose the scale, selected warbands and provisions. Injured warriors do not fight and recover on the next Veintena advance. Prestige now comes from outcome, enemy casualties, captives and small loot value.", 19, COLOR_MUTED))

func _build_barracks_warbands_panel(parent: VBoxContainer) -> void:
	if _selected_warband_skill_web_id != "":
		_build_barracks_skill_web_panel(parent, _selected_warband_skill_web_id)
		return
	parent.add_child(_barracks_label("Warbands", 31, COLOR_TEXT))
	parent.add_child(_barracks_wrapped_label("Warbands are persistent military units inside the Barracks. Rename them, reinforce them from reserve warriors, watch XP bars fill, and open the Skill Web. Injured warriors recover when the Veintena advances.", 19, COLOR_MUTED))
	parent.add_child(_barracks_wrapped_label("Reserve warriors: " + str(_barracks_unassigned_warriors()) + ".", 20, COLOR_TEAL))
	var rows: Array[Dictionary] = _barracks_warband_rows()
	if rows.is_empty():
		parent.add_child(_barracks_wrapped_label("No warbands exist yet. The backend should normally create a Household Warband automatically.", 20, Color(1.0, 0.74, 0.40, 1.0)))
		return
	for row: Dictionary in rows:
		_add_warband_roster_card(parent, row)

func _add_warband_roster_card(parent: VBoxContainer, row: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.05, 0.048, 0.78), Color(0.50, 0.82, 0.74, 0.48), 10))
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
	var name_text: String = String(row.get("name", "Warband"))
	var commander_text: String = String(row.get("commander", "Household captain"))
	var doctrine_text: String = String(row.get("doctrine_name", row.get("doctrine", "Unspecialised")))
	var specialism_text: String = String(row.get("specialisation_name", "None"))
	var ready: int = int(row.get("ready", row.get("warriors", 0)))
	var xp: int = int(row.get("xp", 0))
	var level: int = int(row.get("level", 1))
	_add_warband_name_row(stack, row)
	stack.add_child(_barracks_wrapped_label("Commander: " + commander_text + ". Combat Doctrine: " + doctrine_text + ". Skill Web specialism: " + specialism_text + ".", 18, COLOR_TEAL))
	_add_warband_condition_strip(stack, row)
	if int(row.get("injured", 0)) > 0:
		stack.add_child(_barracks_wrapped_label("✚ Injured warriors recover on the next Veintena advance and cannot be unassigned until then.", 14, Color(1.0, 0.74, 0.40, 1.0)))
	_add_warband_recent_record(stack, row)
	_add_warband_combat_tally(stack, row)
	var xp_start: int = int(row.get("xp_current_level_start", 0))
	var xp_next: int = int(row.get("xp_next_level", max(1, xp + 10)))
	var xp_in_level: int = int(row.get("xp_in_level", xp - xp_start))
	var xp_needed: int = max(1, int(row.get("xp_needed_in_level", xp_next - xp_start)))
	stack.add_child(_barracks_wrapped_label("Level " + str(level) + " — XP " + str(xp_in_level) + " / " + str(xp_needed) + " (total " + str(xp) + ").", 17, COLOR_MUTED))
	var unspent_points: int = int(row.get("trait_points", 0))
	var total_points: int = int(row.get("total_trait_points", max(0, level - 1)))
	var spent_points: int = int(row.get("spent_trait_points", max(0, total_points - unspent_points)))
	stack.add_child(_barracks_wrapped_label("Skill Web: " + str(unspent_points) + " unspent / " + str(total_points) + " earned skill points. Spent: " + str(spent_points) + ".", 17, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Skill Web rule: buying a specialism gateway sets this warband's combat doctrine. Other node effects are recorded only and are not connected to Flower War combat yet.", 15, Color(1.0, 0.74, 0.40, 1.0)))
	var xp_bar: ProgressBar = ProgressBar.new()
	xp_bar.min_value = 0.0
	xp_bar.max_value = float(xp_needed)
	xp_bar.value = clampf(float(xp_in_level), 0.0, float(xp_needed))
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(0, 22)
	xp_bar.add_theme_stylebox_override("background", _make_panel_style(Color(0.03, 0.04, 0.04, 0.84), Color(0.15, 0.18, 0.18, 0.5), 6))
	xp_bar.add_theme_stylebox_override("fill", _make_panel_style(Color(0.34, 0.60, 0.90, 0.92), Color(0.56, 0.85, 1.0, 0.95), 6))
	stack.add_child(xp_bar)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	stack.add_child(actions)
	var assign_button: Button = _barracks_action_button("+ Reinforce", true)
	assign_button.disabled = _barracks_unassigned_warriors() <= 0
	assign_button.tooltip_text = "Reinforce this warband with 1 reserve warrior."
	assign_button.pressed.connect(func() -> void:
		_barracks_assign_warrior(String(row.get("id", "")), 1)
	)
	actions.add_child(assign_button)
	var unassign_button: Button = _barracks_action_button("− Return to Reserve", false)
	unassign_button.disabled = ready <= 0
	unassign_button.tooltip_text = "Return 1 ready warrior to the reserve pool. Injured warriors cannot be moved until they recover."
	unassign_button.pressed.connect(func() -> void:
		_barracks_unassign_warrior(String(row.get("id", "")), 1)
	)
	actions.add_child(unassign_button)
	var traits_button: Button = _barracks_action_button("Open Skill Web", true)
	traits_button.tooltip_text = "Open this warband's basic Skill Web UI."
	traits_button.pressed.connect(func() -> void:
		_barracks_open_skill_web_ui(row)
	)
	actions.add_child(traits_button)


func _add_warband_name_row(parent: VBoxContainer, row: Dictionary) -> void:
	var warband_id: String = String(row.get("id", ""))
	var current_name: String = String(row.get("name", "Warband"))
	var row_box: HBoxContainer = HBoxContainer.new()
	row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_theme_constant_override("separation", 8)
	parent.add_child(row_box)

	var name_edit: LineEdit = LineEdit.new()
	name_edit.text = current_name
	name_edit.placeholder_text = "Warband name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(260, 38)
	name_edit.add_theme_font_size_override("font_size", 22)
	name_edit.add_theme_color_override("font_color", COLOR_TEXT)
	name_edit.add_theme_color_override("font_placeholder_color", COLOR_MUTED)
	name_edit.add_theme_stylebox_override("normal", _make_panel_style(Color(0.030, 0.045, 0.042, 0.88), Color(0.50, 0.82, 0.74, 0.42), 8))
	name_edit.add_theme_stylebox_override("focus", _make_panel_style(Color(0.045, 0.065, 0.060, 0.94), Color(0.56, 0.95, 0.86, 0.68), 8))
	row_box.add_child(name_edit)

	var rename_button: Button = _barracks_action_button("Rename", true)
	rename_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	rename_button.custom_minimum_size = Vector2(112, 38)
	rename_button.add_theme_font_size_override("font_size", 16)
	rename_button.tooltip_text = "Rename this warband. This changes the display name only; battle records and identity stay with the same warband."
	rename_button.pressed.connect(func() -> void:
		_barracks_rename_warband(warband_id, name_edit.text)
	)
	row_box.add_child(rename_button)

	name_edit.text_submitted.connect(func(submitted_text: String) -> void:
		_barracks_rename_warband(warband_id, submitted_text)
	)


func _add_warband_recent_record(parent: VBoxContainer, row: Dictionary) -> void:
	var history: Array = row.get("battle_history", []) as Array
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.042, 0.038, 0.72), Color(0.46, 0.72, 0.64, 0.36), 8))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	margin.add_child(stack)
	stack.add_child(_barracks_wrapped_label("Recent war record", 15, COLOR_TEXT))
	if history.is_empty():
		stack.add_child(_barracks_wrapped_label("No Flower Wars recorded for this warband yet.", 14, COLOR_MUTED))
		return
	var shown: int = 0
	var index: int = history.size() - 1
	while index >= 0 and shown < 2:
		var entry_variant: Variant = history[index]
		if entry_variant is Dictionary:
			stack.add_child(_barracks_wrapped_label(_warband_recent_record_line(entry_variant as Dictionary), 14, COLOR_MUTED))
			shown += 1
		index -= 1
	stack.add_child(_barracks_wrapped_label("Full losses and dead are kept under War Returns.", 13, Color(1.0, 0.74, 0.40, 1.0)))

func _warband_recent_record_line(entry: Dictionary) -> String:
	var veintena: int = int(entry.get("veintena", 0))
	var result_text: String = String(entry.get("result", "Flower War"))
	var mode_text: String = "Defence" if bool(entry.get("defensive", false)) else "Muster"
	var sent: int = int(entry.get("sent", entry.get("committed", 0)))
	var injured: int = int(entry.get("injured", 0))
	var xp_gain: int = int(entry.get("xp_gained", 0))
	var captives: int = int(entry.get("captives", 0))
	var line: String = "• "
	if veintena > 0:
		line += "V" + str(veintena) + " "
	line += mode_text + " — " + result_text + ": sent " + str(sent) + ", ✚ " + str(injured) + ", XP +" + str(xp_gain)
	if captives > 0:
		line += ", captives " + str(captives)
	line += "."
	return line


func _warband_combat_stats(row: Dictionary) -> Dictionary:
	if row.has("combat_stats") and row["combat_stats"] is Dictionary:
		return (row["combat_stats"] as Dictionary).duplicate(true)
	var ready: int = int(row.get("ready", row.get("warriors", 0)))
	var doctrine_id: String = WAR_DOCTRINE_RULES_SCRIPT.normalise_doctrine_id(String(row.get("doctrine", "unspecialised")))
	var doctrine: Dictionary = WAR_DOCTRINE_RULES_SCRIPT.doctrine_data(doctrine_id) as Dictionary
	var offence: float = float(doctrine.get("offence", 1.0))
	var defence: float = float(doctrine.get("defence", 1.0))
	return {
		"ready": ready,
		"injured": int(row.get("injured", 0)),
		"dead_total": int(row.get("dead_total", 0)),
		"doctrine_name": String(row.get("doctrine_name", doctrine.get("name", doctrine_id.capitalize()))),
		"offence_modifier": offence,
		"defence_modifier": defence,
		"effective_offence": snappedf(float(ready) * offence, 0.01),
		"effective_defence": snappedf(float(ready) * defence, 0.01)
	}

func _add_warband_condition_strip(parent: VBoxContainer, row: Dictionary) -> void:
	var stats: Dictionary = _warband_combat_stats(row)
	var ready: int = int(stats.get("ready", 0))
	var injured: int = int(stats.get("injured", 0))
	var strip: HBoxContainer = HBoxContainer.new()
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_theme_constant_override("separation", 6)
	parent.add_child(strip)
	_add_warband_tally_chip(strip, "Ready", "SPEAR", ready, COLOR_TEAL)
	_add_warband_tally_chip(strip, "Injured", "✚", injured, Color(1.0, 0.74, 0.40, 1.0))

func _add_warband_tally_chip(parent: HBoxContainer, label_text: String, symbol_text: String, value: int, border_colour: Color) -> void:
	var chip: PanelContainer = PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.035, 0.033, 0.86), border_colour, 8))
	parent.add_child(chip)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 5)
	chip.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	margin.add_child(stack)
	var title: Label = _barracks_label(symbol_text, 13, border_colour)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var value_label: Label = _barracks_label(label_text + " " + str(value), 16, COLOR_TEXT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(value_label)

func _add_warband_ratio_bar(parent: VBoxContainer, label_text: String, value: float, max_value: float, fill_colour: Color) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label: Label = _barracks_label(label_text, 14, COLOR_MUTED)
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = maxf(1.0, max_value)
	bar.value = clampf(value, 0.0, maxf(1.0, max_value))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", _make_panel_style(Color(0.03, 0.04, 0.04, 0.84), Color(0.15, 0.18, 0.18, 0.5), 5))
	bar.add_theme_stylebox_override("fill", _make_panel_style(fill_colour.darkened(0.18), fill_colour, 5))
	row.add_child(bar)

func _add_warband_combat_tally(parent: VBoxContainer, row: Dictionary) -> void:
	var stats: Dictionary = _warband_combat_stats(row)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.038, 0.036, 0.80), Color(0.62, 0.50, 0.28, 0.58), 9))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Combat Tally", 18, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Doctrine: " + String(stats.get("doctrine_name", "Unspecialised")) + " | Offence x" + _format_float(float(stats.get("offence_modifier", 1.0))) + " | Defence x" + _format_float(float(stats.get("defence_modifier", 1.0))) + ".", 15, COLOR_MUTED))
	var row_line: HBoxContainer = HBoxContainer.new()
	row_line.add_theme_constant_override("separation", 8)
	stack.add_child(row_line)
	_add_warband_tally_chip(row_line, "Off " + _format_float(float(stats.get("effective_offence", 0.0))), "ATK", int(round(float(stats.get("effective_offence", 0.0)))), Color(0.88, 0.42, 0.32, 1.0))
	_add_warband_tally_chip(row_line, "Def " + _format_float(float(stats.get("effective_defence", 0.0))), "DEF", int(round(float(stats.get("effective_defence", 0.0)))), Color(0.36, 0.68, 0.92, 1.0))

func _add_army_muster_summary_card(parent: VBoxContainer, rows: Array[Dictionary]) -> void:
	var ready_total: int = 0
	var injured_total: int = 0
	var effective_offence: float = 0.0
	var effective_defence: float = 0.0
	var active_count: int = 0
	for row: Dictionary in rows:
		var stats: Dictionary = _warband_combat_stats(row)
		var ready: int = int(stats.get("ready", 0))
		ready_total += ready
		injured_total += int(stats.get("injured", 0))
		effective_offence += float(stats.get("effective_offence", 0.0))
		effective_defence += float(stats.get("effective_defence", 0.0))
		if ready > 0:
			active_count += 1
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.038, 0.036, 0.84), Color(0.50, 0.82, 0.74, 0.58), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Army Muster", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Warbands committed: " + str(active_count) + " / " + str(rows.size()) + ". Ready warriors: " + str(ready_total) + ". Injured not fighting: " + str(injured_total) + ".", 17, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label("Total effective offence: " + _format_float(effective_offence) + ". Total effective defence: " + _format_float(effective_defence) + ".", 17, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Stats use the doctrine set by the Skill Web specialism. Other Skill Web node effects are not connected to Flower War resolution yet.", 15, Color(1.0, 0.74, 0.40, 1.0)))

func _build_skill_web_warband_stats_header(parent: VBoxContainer, web: Dictionary) -> void:
	var warband: Dictionary = web.get("warband", {}) as Dictionary
	var stats: Dictionary = {}
	if web.has("combat_stats") and web["combat_stats"] is Dictionary:
		stats = web["combat_stats"] as Dictionary
	else:
		stats = _warband_combat_stats(warband)
	parent.add_child(_barracks_label(String(warband.get("name", "Warband")), 21, COLOR_TEXT))
	parent.add_child(_barracks_wrapped_label("Doctrine: " + String(stats.get("doctrine_name", "Unspecialised")) + " | Ready " + str(int(stats.get("ready", 0))) + " | Injured " + str(int(stats.get("injured", 0))) + ".", 15, COLOR_TEAL))
	parent.add_child(_barracks_wrapped_label("Eff. Off " + _format_float(float(stats.get("effective_offence", 0.0))) + " | Eff. Def " + _format_float(float(stats.get("effective_defence", 0.0))) + " | Specialism sets doctrine.", 15, COLOR_MUTED))


# -----------------------------------------------------------------------------
# Full-screen Flower War Event Flow bridge v0.14
# -----------------------------------------------------------------------------
# Patch 6A: the Flower War event UI now lives in
# res://Scripts/ui/widgets/FlowerWarEventOverlay.gd.
# This wrapper keeps the old public methods used by the Barracks buttons, but the
# event itself is intentionally a full-screen modal event. It is added to the
# GameScreen root, not to DynamicViewHost, so it is not constrained to the
# left/main content panel.

func _open_flower_war_attack_event(option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> void:
	_show_flower_war_event_panel(true, option_id, source_id, context)

func _open_flower_war_defence_event(option_id: String = "standard", source_id: String = "rival", context: Dictionary = {}) -> void:
	_show_flower_war_event_panel(false, option_id, source_id, context)

func _show_flower_war_event_panel(is_attack: bool, option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> void:
	# Flower War is a modal event screen, like later events.
	# Match the pre-extraction behaviour: add the modal to the GameScreen itself,
	# not to DynamicViewHost / ContentRoot and not to get_tree().root. Adding it to
	# the viewport root made the panel overrun the visible game area on some window
	# sizes. As a child of this full-screen GameScreen Control, PRESET_FULL_RECT
	# fills the actual game UI area exactly like the original inline overlay did.
	_clear_flower_war_event_overlay()
	var event_panel: Control = FLOWER_WAR_EVENT_OVERLAY_SCRIPT.new() as Control
	if event_panel == null:
		return
	event_panel.name = "FlowerWarEventOverlayRoot"
	event_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	event_panel.z_index = 250
	event_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	if host != null:
		host.add_child(event_panel)
	else:
		return
	_flower_war_event_overlay = event_panel
	if is_attack:
		if event_panel.has_method("open_attack_event"):
			event_panel.call("open_attack_event", self, option_id, source_id, context)
	else:
		if event_panel.has_method("open_defence_event"):
			event_panel.call("open_defence_event", self, option_id, source_id, context)

func _clear_flower_war_event_overlay() -> void:
	if _flower_war_event_overlay != null and is_instance_valid(_flower_war_event_overlay):
		_flower_war_event_overlay.queue_free()
	_flower_war_event_overlay = null

func _flower_war_event_cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "none"
	var parts: Array[String] = []
	var state: Node = _state()
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var label: String = resource_id.replace("_", " ").capitalize()
		if state != null and state.has_method("get_resource_name"):
			label = String(state.call("get_resource_name", resource_id))
		parts.append(label + " " + _format_float(float(cost[resource_variant])))
	return ", ".join(parts)

func _flower_war_event_loot_text(loot: Dictionary) -> String:
	if loot.is_empty():
		return "none"
	return _flower_war_event_cost_text(loot)

func _barracks_preview_for_selected_warbands(warband_ids: Array, option_id: String, provisioning_id: String) -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("get_flower_war_preview_with_selected_warbands"):
		var raw: Variant = state.call("get_flower_war_preview_with_selected_warbands", warband_ids, option_id, provisioning_id)
		if raw is Dictionary:
			return raw as Dictionary
	return _barracks_preview_for_all_warbands_option({"id": option_id})

func _barracks_can_launch_selected_warbands(warband_ids: Array, option_id: String, provisioning_id: String) -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("can_launch_flower_war_with_selected_warbands"):
		var raw: Variant = state.call("can_launch_flower_war_with_selected_warbands", warband_ids, option_id, provisioning_id)
		if raw is Dictionary:
			return raw as Dictionary
	return _barracks_can_launch_all_warbands(option_id, provisioning_id)

func _all_ready_warband_ids() -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in _barracks_warband_rows():
		var warband_id: String = String(row.get("id", ""))
		if warband_id != "" and int(row.get("ready", row.get("warriors", 0))) > 0:
			ids.append(warband_id)
	return ids

func _barracks_defence_strategies() -> Array[Dictionary]:
	var state: Node = _state()
	if state != null and state.has_method("get_flower_war_defence_strategies"):
		var raw: Variant = state.call("get_flower_war_defence_strategies")
		if raw is Array:
			var output: Array[Dictionary] = []
			for item: Variant in raw as Array:
				if item is Dictionary:
					output.append(item as Dictionary)
			return output
	return [
		{"id": "balanced", "name": "Balanced Defence", "offence_multiplier": 1.0, "defence_multiplier": 1.0, "description": "A steady response with no bonus or penalty."},
		{"id": "depth", "name": "Defence in Depth", "offence_multiplier": 0.85, "defence_multiplier": 1.25, "description": "More defence, less offence."},
		{"id": "good_offence", "name": "The Best Defence is a Good Offence", "offence_multiplier": 1.25, "defence_multiplier": 0.85, "description": "More offence, less defence."}
	]

func _barracks_preview_for_defence(option_id: String, strategy_id: String) -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("get_flower_war_defence_preview"):
		var raw: Variant = state.call("get_flower_war_defence_preview", option_id, strategy_id)
		if raw is Dictionary:
			return raw as Dictionary
	return {"ok": false, "reason": "Defence preview backend is not connected."}

func _barracks_can_resolve_defence(option_id: String, strategy_id: String) -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("can_resolve_flower_war_defence"):
		var raw: Variant = state.call("can_resolve_flower_war_defence", option_id, strategy_id)
		if raw is Dictionary:
			return raw as Dictionary
	return {"ok": false, "reason": "Defence resolver backend is not connected."}

func _build_barracks_warriors_panel(parent: VBoxContainer) -> void:
	var summary: Dictionary = _barracks_summary()
	parent.add_child(_barracks_label("Warriors", 31, COLOR_TEXT))
	parent.add_child(_barracks_wrapped_label("Current Yaotequihuaqueh warriors: " + str(int(summary.get("warriors", 0))) + ".", 22, COLOR_TEAL))
	parent.add_child(_barracks_wrapped_label("Warrior housing capacity: " + str(int(summary.get("capacity", 0))) + ". Free warrior capacity: " + str(int(summary.get("free_capacity", 0))) + ".", 20, COLOR_MUTED))
	parent.add_child(_barracks_wrapped_label("Recruitment is not wired into this UI step. Warrior Houses and warrior housing remain handled by the existing Housing system for now.", 19, COLOR_MUTED))

func _build_barracks_weapons_panel(parent: VBoxContainer) -> void:
	var summary: Dictionary = _barracks_summary()
	parent.add_child(_barracks_label("Weapons & Supplies", 31, COLOR_TEXT))
	parent.add_child(_barracks_wrapped_label("Weapons available after reserves: " + _format_float(float(summary.get("weapons", 0.0))) + ".", 22, COLOR_TEAL))
	parent.add_child(_barracks_wrapped_label("Provisioning is paid when launching a Flower War. Standard uses 1x supplies, Well Provisioned uses 2x, and Royal Provision uses 4x.", 20, COLOR_MUTED))
	parent.add_child(_barracks_wrapped_label("Defensive provisioning is not implemented here because defenders do not choose provisioning in the canonical design.", 19, COLOR_MUTED))

func _build_barracks_flower_wars_panel(parent: VBoxContainer) -> void:
	parent.add_child(_barracks_label("Flower Wars", 31, COLOR_TEXT))
	parent.add_child(_barracks_wrapped_label("Attacking Flower Wars now use the Palace authority gate. A Huitzilopochtli Palace authorises the war route; defensive Flower Wars can still occur regardless of dedication.", 19, COLOR_MUTED))
	parent.add_child(_barracks_wrapped_label(_barracks_palace_gate_text(), 18, _barracks_palace_gate_colour()))
	var rows: Array[Dictionary] = _barracks_warband_rows()
	if rows.is_empty():
		parent.add_child(_barracks_wrapped_label("No warbands exist yet. Open Warbands to create or initialise the roster.", 20, Color(1.0, 0.74, 0.40, 1.0)))
		return
	_add_army_muster_summary_card(parent, rows)
	parent.add_child(_barracks_wrapped_label("Select a Flower War scale. All ready warbands are selected by default in the muster, but you can stand down damaged or valuable warbands before committing.", 17, COLOR_MUTED))
	for option: Dictionary in _barracks_flower_options():
		_add_flower_war_all_warbands_option_card(parent, option)
	_add_flower_war_defence_event_card(parent)

func _add_flower_war_all_warbands_option_card(parent: VBoxContainer, option: Dictionary) -> void:
	var option_id: String = String(option.get("id", "minor"))
	var preview: Dictionary = _barracks_preview_for_selected_warbands(_all_ready_warband_ids(), option_id, "standard")
	var status: Dictionary = _barracks_can_launch_selected_warbands(_all_ready_warband_ids(), option_id, "standard")
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.05, 0.048, 0.78), Color(0.50, 0.82, 0.74, 0.48), 10))
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
	stack.add_child(_barracks_label(String(option.get("name", option_id.capitalize())), 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label(String(option.get("description", "A sanctioned Flower War scale.")), 17, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Default muster preview: " + String(preview.get("result", "Preview unavailable")) + ". Ready warriors " + str(int(preview.get("committed_warriors", preview.get("warriors_committed", 0)))) + " across " + str(int(preview.get("participating_warband_count", 0))) + " warbands.", 18, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label("Expected losses " + str(int(preview.get("attacker_losses", preview.get("attacker_casualties", 0)))) + "; captives " + str(int(preview.get("captives", 0))) + "; XP +" + str(int(preview.get("xp_gained", 0))) + "; loot value " + _format_float(float(preview.get("loot_value", 0.0))) + ".", 17, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Prestige preview: " + _format_signed_prestige_ui(float(preview.get("prestige_gain", 0.0))) + ". Skill Web specialism sets doctrine; other node effects are not connected to combat yet.", 15, Color(1.0, 0.74, 0.40, 1.0)))
	var button: Button = Button.new()
	button.text = "Open Flower War Muster"
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 17)
	button.disabled = not bool(status.get("ok", false))
	button.tooltip_text = String(status.get("reason", ""))
	button.pressed.connect(func() -> void:
		_open_flower_war_attack_event(option_id)
	)
	stack.add_child(button)
	if not bool(status.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Blocked: " + String(status.get("reason", "")), 15, Color(1.0, 0.74, 0.40, 1.0)))

func _add_flower_war_defence_event_card(parent: VBoxContainer) -> void:
	var preview: Dictionary = _barracks_preview_for_defence("standard", "balanced")
	var status: Dictionary = _barracks_can_resolve_defence("standard", "balanced")
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.038, 0.052, 0.82), Color(0.36, 0.68, 0.92, 0.52), 10))
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
	stack.add_child(_barracks_label("Defensive Flower War Event", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Prototype event entry for rival-started Flower Wars. Defenders do not choose provisions; they choose a defensive strategy.", 17, COLOR_MUTED))
	if bool(preview.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Default defence preview: " + String(preview.get("result", "Preview unavailable")) + ". Defending warriors " + str(int(preview.get("warriors_committed", 0))) + "; enemy casualties " + str(int(preview.get("enemy_casualties", 0))) + "; expected losses " + str(int(preview.get("defender_casualties", preview.get("attacker_casualties", 0)))) + ".", 17, COLOR_TEAL))
	else:
		stack.add_child(_barracks_wrapped_label("Defence preview unavailable: " + String(preview.get("reason", "No ready warbands.")), 17, Color(1.0, 0.74, 0.40, 1.0)))
	var button: Button = Button.new()
	button.text = "Open Flower War Defence"
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 17)
	button.disabled = not bool(status.get("ok", false))
	button.tooltip_text = String(status.get("reason", ""))
	button.pressed.connect(func() -> void:
		_open_flower_war_defence_event("standard")
	)
	stack.add_child(button)
	if not bool(status.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Blocked: " + String(status.get("reason", "Cannot defend.")), 15, Color(1.0, 0.74, 0.40, 1.0)))

func _add_flower_war_warband_section(parent: VBoxContainer, row: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.040, 0.038, 0.78), Color(0.50, 0.82, 0.74, 0.52), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	var ready: int = int(row.get("ready", row.get("warriors", 0)))
	var injured: int = int(row.get("injured", 0))
	var level: int = int(row.get("level", 1))
	var doctrine: String = String(row.get("doctrine_name", row.get("doctrine", "Unspecialised")))
	stack.add_child(_barracks_label(String(row.get("name", "Warband")) + " — Level " + str(level), 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Ready " + str(ready) + "; injured " + str(injured) + "; doctrine " + doctrine + ".", 17, COLOR_MUTED))
	for option: Dictionary in _barracks_flower_options():
		_add_flower_war_option_card(stack, row, option)

func _build_barracks_returns_panel(parent: VBoxContainer) -> void:
	parent.add_child(_barracks_label("War Returns", 31, COLOR_TEXT))
	parent.add_child(_barracks_wrapped_label("Flower War aftermaths are recorded here as codex return reports. Deaths and detailed losses belong in these reports, not on normal warband cards.", 18, COLOR_MUTED))
	var archive: Array[Dictionary] = _barracks_flower_war_report_archive()
	if archive.is_empty():
		for line: String in _barracks_last_report_lines():
			parent.add_child(_barracks_wrapped_label("• " + line, 20, COLOR_MUTED))
		return
	for report: Dictionary in archive:
		_add_war_return_archive_card(parent, report)

func _barracks_flower_war_report_archive() -> Array[Dictionary]:
	var state: Node = _state()
	if state != null and state.has_method("get_flower_war_report_archive"):
		var raw: Variant = state.call("get_flower_war_report_archive", 8)
		if raw is Array:
			var output: Array[Dictionary] = []
			for item: Variant in raw as Array:
				if item is Dictionary:
					output.append(item as Dictionary)
			return output
	return []

func _add_war_return_archive_card(parent: VBoxContainer, report: Dictionary) -> void:
	var direction: String = String(report.get("war_direction", "attack"))
	var title_text: String = String(report.get("archive_title", "Flower War Return"))
	var result_text: String = String(report.get("result", "Unknown"))
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.030, 0.020, 0.90), Color(0.78, 0.58, 0.30, 0.58), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	stack.add_child(header)
	var title_stack: VBoxContainer = VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 2)
	header.add_child(title_stack)
	title_stack.add_child(_barracks_label(title_text, 23, COLOR_TEXT))
	var veintena_text: String = "Veintena " + str(int(report.get("archive_veintena", 0)))
	if int(report.get("archive_veintena", 0)) <= 0:
		veintena_text = "Recorded Flower War"
	title_stack.add_child(_barracks_wrapped_label(veintena_text + " | " + ("Defence" if direction == "defence" else "Muster") + " | " + result_text, 15, COLOR_TEAL))
	var summary: GridContainer = GridContainer.new()
	summary.columns = 4
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_constant_override("h_separation", 8)
	summary.add_theme_constant_override("v_separation", 6)
	stack.add_child(summary)
	_add_war_return_chip(summary, "Warriors", str(int(report.get("warriors_committed", report.get("committed_warriors", 0)))), COLOR_MUTED)
	_add_war_return_chip(summary, "Returned", str(int(report.get("warriors_returned", 0))), COLOR_TEAL)
	_add_war_return_chip(summary, "✚ Injured", str(int(report.get("attacker_injured", 0))), Color(0.80, 1.0, 0.88, 1.0))
	_add_war_return_chip(summary, "Dead", str(int(report.get("attacker_dead", 0))), Color(0.72, 0.70, 0.66, 1.0))
	if direction == "defence":
		_add_war_return_chip(summary, "Strategy", String(report.get("defence_strategy_name", "Balanced Defence")), COLOR_MUTED)
		_add_war_return_chip(summary, "Enemy losses", str(int(report.get("enemy_casualties", 0))), COLOR_MUTED)
	else:
		_add_war_return_chip(summary, "Captives", str(int(report.get("captives", 0))), COLOR_TEAL)
		_add_war_return_chip(summary, "Loot", _flower_war_event_loot_text(report.get("loot", {}) as Dictionary), COLOR_MUTED)
	_add_war_return_chip(summary, "XP", "+" + str(int(report.get("xp_gained", 0))), COLOR_TEAL)
	_add_war_return_chip(summary, "Prestige", _format_signed_prestige_ui(float(report.get("prestige_gain", 0.0))), Color(1.0, 0.82, 0.44, 1.0))

	var participants: Array = report.get("participant_reports", []) as Array
	if not participants.is_empty():
		var list: VBoxContainer = VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		stack.add_child(list)
		list.add_child(_barracks_wrapped_label("Warband returns", 16, COLOR_TEXT))
		for participant_variant: Variant in participants:
			if not (participant_variant is Dictionary):
				continue
			var participant: Dictionary = participant_variant as Dictionary
			var sent: int = int(participant.get("sent", participant.get("committed", 0)))
			var returned_ready: int = int(participant.get("returned_ready", max(0, sent - int(participant.get("casualties", 0)))))
			list.add_child(_barracks_wrapped_label("• " + String(participant.get("name", "Warband")) + ": sent " + str(sent) + ", returned " + str(returned_ready) + ", ✚ " + str(int(participant.get("injured", 0))) + ", dead " + str(int(participant.get("dead", 0))) + ", XP +" + str(int(participant.get("xp_gained", 0))) + ".", 15, COLOR_MUTED))
	var level_reports: Array = report.get("level_reports", []) as Array
	for level_variant: Variant in level_reports:
		stack.add_child(_barracks_wrapped_label(String(level_variant) + ".", 15, COLOR_TEAL))

func _add_war_return_chip(parent: GridContainer, label_text: String, value_text: String, colour: Color) -> void:
	var chip: PanelContainer = PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.038, 0.036, 0.82), colour.darkened(0.25), 8))
	parent.add_child(chip)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	chip.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 1)
	margin.add_child(stack)
	stack.add_child(_barracks_wrapped_label(label_text, 12, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label(value_text, 15, colour))

func _add_flower_war_option_card(parent: VBoxContainer, row: Dictionary, option: Dictionary) -> void:
	var warband_id: String = String(row.get("id", ""))
	var option_id: String = String(option.get("id", "minor"))
	var doctrine_id: String = String(row.get("doctrine", "unspecialised"))
	if doctrine_id == "":
		doctrine_id = "unspecialised"
	var preview: Dictionary = _barracks_preview_for_warband_option(row, option)
	var status: Dictionary = _barracks_can_launch_warband(warband_id, option_id, doctrine_id, "standard")
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.05, 0.048, 0.78), Color(0.50, 0.82, 0.74, 0.38), 9))
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
	stack.add_child(_barracks_label(String(option.get("name", option_id.capitalize())), 21, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label(String(option.get("description", "Auto-resolved Flower War.")), 16, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Doctrine: " + String(preview.get("doctrine_name", doctrine_id.capitalize())) + ". Provisioning: Standard. Result preview: " + String(preview.get("result", "Unknown")) + ".", 17, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label("Committed warriors: " + str(int(preview.get("committed_warriors", preview.get("warriors_committed", 0)))) + "; expected losses: " + str(int(preview.get("attacker_losses", preview.get("attacker_casualties", 0)))) + "; captives: " + str(int(preview.get("captives", 0))) + "; XP: +" + str(int(preview.get("xp_gained", 0))) + "; loot value: " + _format_float(float(preview.get("loot_value", 0.0))) + ".", 16, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Prestige preview: " + _format_signed_prestige_ui(float(preview.get("prestige_gain", 0.0))) + ".", 15, Color(1.0, 0.74, 0.40, 1.0)))
	var button: Button = Button.new()
	button.text = "Launch with " + String(row.get("name", "Warband"))
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 17)
	button.disabled = not bool(status.get("ok", false))
	button.tooltip_text = String(status.get("reason", ""))
	button.pressed.connect(func() -> void:
		_launch_flower_war_with_warband_from_ui(warband_id, option_id, doctrine_id, "standard")
	)
	stack.add_child(button)
	if not bool(status.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Blocked: " + String(status.get("reason", "")), 15, Color(1.0, 0.74, 0.40, 1.0)))

func _launch_flower_war_from_ui(option_id: String, doctrine_id: String, provisioning_id: String) -> void:
	var state: Node = _state()
	if state == null or not state.has_method("launch_flower_war"):
		return
	state.call("launch_flower_war", option_id, doctrine_id, provisioning_id)
	_refresh_all()

func _launch_flower_war_with_warband_from_ui(warband_id: String, option_id: String, doctrine_id: String, provisioning_id: String) -> void:
	var state: Node = _state()
	if state == null:
		return
	if state.has_method("launch_flower_war_with_warband"):
		state.call("launch_flower_war_with_warband", warband_id, option_id, doctrine_id, provisioning_id)
	elif state.has_method("launch_flower_war"):
		state.call("launch_flower_war", option_id, doctrine_id, provisioning_id)
	_refresh_all()

func _launch_flower_war_all_warbands_from_ui(option_id: String, provisioning_id: String) -> void:
	var state: Node = _state()
	if state == null:
		return
	if state.has_method("launch_flower_war_with_all_warbands"):
		state.call("launch_flower_war_with_all_warbands", option_id, provisioning_id)
	elif state.has_method("launch_flower_war"):
		state.call("launch_flower_war", option_id, "unspecialised", provisioning_id)
	_refresh_all()

func _barracks_warband_rows() -> Array[Dictionary]:
	var state: Node = _state()
	if state != null and state.has_method("get_warband_rows"):
		var raw: Variant = state.call("get_warband_rows")
		if raw is Array:
			var output: Array[Dictionary] = []
			for item: Variant in raw as Array:
				if item is Dictionary:
					output.append(item as Dictionary)
			return output
	return []

func _barracks_has_war_god_palace() -> bool:
	var state: Node = _state()
	if state != null and state.has_method("has_war_god_palace"):
		return bool(state.call("has_war_god_palace"))
	return false

func _barracks_flower_war_palace_gate_enabled() -> bool:
	var state: Node = _state()
	if state != null and state.has_method("is_flower_war_palace_gate_enabled"):
		return bool(state.call("is_flower_war_palace_gate_enabled"))
	return false

func _barracks_flower_war_palace_gate_passed() -> bool:
	var state: Node = _state()
	if state != null and state.has_method("flower_war_palace_gate_passed"):
		return bool(state.call("flower_war_palace_gate_passed"))
	if not _barracks_flower_war_palace_gate_enabled():
		return true
	return _barracks_has_war_god_palace()

func _barracks_palace_gate_colour() -> Color:
	if _barracks_flower_war_palace_gate_passed():
		return COLOR_TEAL
	return Color(1.0, 0.74, 0.40, 1.0)

func _barracks_palace_gate_text() -> String:
	var state: Node = _state()
	if state != null and state.has_method("flower_war_palace_gate_status_text"):
		return String(state.call("flower_war_palace_gate_status_text"))
	var dedicated: String = ""
	if state != null and state.has_method("get_player_palace_dedicated_god"):
		dedicated = String(state.call("get_player_palace_dedicated_god"))
	if not _barracks_flower_war_palace_gate_enabled():
		return "Palace gate inactive: attacking Flower Wars are open for testing."
	if _barracks_has_war_god_palace():
		return "Huitzilopochtli Palace authority active: attacking Flower Wars are authorised."
	if dedicated == "":
		return "Attacking Flower Wars locked: dedicate the Palace to Huitzilopochtli. Defensive Flower Wars can still occur."
	return "Attacking Flower Wars locked: current palace dedication is " + dedicated.capitalize() + "; Huitzilopochtli is required. Defensive Flower Wars can still occur."


func _barracks_action_button(text_value: String, positive: bool) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	var border: Color = Color(0.50, 0.82, 0.74, 0.60)
	if not positive:
		border = Color(0.90, 0.45, 0.36, 0.60)
	button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.035, 0.055, 0.052, 0.86), border, 8))
	button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.055, 0.08, 0.075, 0.94), border.lightened(0.12), 8))
	button.add_theme_stylebox_override("disabled", _make_panel_style(Color(0.08, 0.08, 0.08, 0.78), Color(0.35, 0.35, 0.35, 0.50), 8))
	return button

func _barracks_unassigned_warriors() -> int:
	var state: Node = _state()
	if state != null and state.has_method("get_unassigned_warrior_pool"):
		return int(state.call("get_unassigned_warrior_pool"))
	return 0

func _barracks_assign_warrior(warband_id: String, amount: int) -> void:
	var state: Node = _state()
	if state == null or not state.has_method("assign_warriors_to_warband"):
		return
	state.call("assign_warriors_to_warband", warband_id, amount)
	_refresh_all()

func _barracks_unassign_warrior(warband_id: String, amount: int) -> void:
	var state: Node = _state()
	if state == null or not state.has_method("unassign_warriors_from_warband"):
		return
	state.call("unassign_warriors_from_warband", warband_id, amount)
	_refresh_all()


func _barracks_rename_warband(warband_id: String, new_name: String) -> void:
	var state: Node = _state()
	if state == null:
		return
	if state.has_method("rename_warband"):
		state.call("rename_warband", warband_id, new_name)
	elif state.has_method("set_warband_name"):
		state.call("set_warband_name", warband_id, new_name)
	_refresh_all()


func _barracks_open_skill_web_ui(row: Dictionary) -> void:
	var new_id: String = String(row.get("id", ""))
	if new_id != _selected_warband_skill_web_id:
		_last_skill_web_report.clear()
		_selected_skill_web_node_id = ""
		_hovered_skill_web_node_id = ""
	_selected_warband_skill_web_id = new_id
	_refresh_all()

func _barracks_close_skill_web_ui() -> void:
	_selected_warband_skill_web_id = ""
	_selected_skill_web_node_id = ""
	_hovered_skill_web_node_id = ""
	_last_skill_web_report.clear()
	_refresh_all()

func _build_barracks_skill_web_panel(parent: VBoxContainer, warband_id: String) -> void:
	var web: Dictionary = _barracks_skill_web_data(warband_id)
	if not bool(web.get("ok", false)):
		parent.add_child(_barracks_label("Warband Skill Web", 31, COLOR_TEXT))
		parent.add_child(_barracks_wrapped_label("Could not open Skill Web: " + String(web.get("reason", "Unknown warband.")), 20, Color(1.0, 0.74, 0.40, 1.0)))
		var back_error: Button = _barracks_action_button("Back to Warbands", false)
		back_error.pressed.connect(_barracks_close_skill_web_ui)
		parent.add_child(back_error)
		return

	var warband: Dictionary = web.get("warband", {}) as Dictionary
	var name_text: String = String(warband.get("name", "Warband"))
	var level: int = int(warband.get("level", 1))
	var xp: int = int(warband.get("xp", 0))
	var points_available: int = int(web.get("points_available", 0))
	var points_total: int = int(web.get("points_total", max(0, level - 1)))
	var points_spent: int = int(web.get("points_spent", max(0, points_total - points_available)))
	var spec: Dictionary = web.get("specialisation", {}) as Dictionary

	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 6)
	parent.add_child(header_row)

	var title_stack: VBoxContainer = VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 1)
	header_row.add_child(title_stack)
	title_stack.add_child(_barracks_label(name_text + " Skill Web", 24, COLOR_TEXT))
	var header_stats: Dictionary = {}
	if web.has("combat_stats") and web["combat_stats"] is Dictionary:
		header_stats = web["combat_stats"] as Dictionary
	else:
		header_stats = _warband_combat_stats(warband)
	title_stack.add_child(_barracks_wrapped_label("Level " + str(level) + " | XP " + str(xp) + " | Skill points " + str(points_available) + "/" + str(points_total) + " | Specialism " + String(spec.get("name", "None")), 16, COLOR_TEAL))
	title_stack.add_child(_barracks_wrapped_label("Doctrine " + String(header_stats.get("doctrine_name", "Unspecialised")) + " | Ready " + str(int(header_stats.get("ready", 0))) + " | Eff. Off " + _format_float(float(header_stats.get("effective_offence", 0.0))) + " | Eff. Def " + _format_float(float(header_stats.get("effective_defence", 0.0))) + ".", 14, COLOR_MUTED))

	var zoom_out_button: Button = _barracks_action_button("−", true)
	zoom_out_button.custom_minimum_size = Vector2(44, 32)
	header_row.add_child(zoom_out_button)

	var zoom_in_button: Button = _barracks_action_button("+", true)
	zoom_in_button.custom_minimum_size = Vector2(44, 32)
	header_row.add_child(zoom_in_button)

	var recenter_button: Button = _barracks_action_button("Centre", true)
	recenter_button.custom_minimum_size = Vector2(82, 32)
	recenter_button.pressed.connect(func() -> void:
		_skill_web_pan_by_warband[warband_id] = Vector2.ZERO
		_refresh_all()
	)
	header_row.add_child(recenter_button)

	var back_button: Button = _barracks_action_button("Back", false)
	back_button.custom_minimum_size = Vector2(66, 32)
	back_button.pressed.connect(_barracks_close_skill_web_ui)
	header_row.add_child(back_button)

	if not _last_skill_web_report.is_empty():
		for line: String in _last_skill_web_report:
			parent.add_child(_barracks_wrapped_label(line, 17, COLOR_TEAL))

	var graph_row: HBoxContainer = HBoxContainer.new()
	graph_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_row.clip_contents = true
	graph_row.add_theme_constant_override("separation", 8)
	parent.add_child(graph_row)

	graph_row.custom_minimum_size = Vector2(0, 640)

	var graph_panel: PanelContainer = PanelContainer.new()
	graph_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_panel.clip_contents = true
	graph_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.012, 0.020, 0.022, 0.94), Color(0.50, 0.82, 0.74, 0.36), 12))
	graph_row.add_child(graph_panel)

	var graph_margin: MarginContainer = MarginContainer.new()
	graph_margin.clip_contents = true
	graph_margin.add_theme_constant_override("margin_left", 4)
	graph_margin.add_theme_constant_override("margin_top", 4)
	graph_margin.add_theme_constant_override("margin_right", 4)
	graph_margin.add_theme_constant_override("margin_bottom", 4)
	graph_panel.add_child(graph_margin)

	var canvas: Control = WARBAND_SKILL_WEB_CANVAS_SCRIPT.new() as Control
	canvas.custom_minimum_size = Vector2(920, 640)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var saved_pan: Vector2 = Vector2.ZERO
	if _skill_web_pan_by_warband.has(warband_id):
		saved_pan = _skill_web_pan_by_warband[warband_id] as Vector2
	var saved_zoom: float = 0.74
	if _skill_web_zoom_by_warband.has(warband_id):
		saved_zoom = float(_skill_web_zoom_by_warband[warband_id])
	canvas.setup(web, _selected_skill_web_node_id, _hovered_skill_web_node_id, saved_pan, saved_zoom)
	# Keep panning cheap: only store the new pan offset. Do not rebuild the
	# whole Barracks screen while the player is dragging the web.
	canvas.pan_changed.connect(func(new_pan: Vector2) -> void:
		_skill_web_pan_by_warband[warband_id] = new_pan
	)
	canvas.zoom_changed.connect(func(new_zoom: float) -> void:
		_skill_web_zoom_by_warband[warband_id] = new_zoom
	)
	zoom_out_button.pressed.connect(func() -> void:
		canvas.zoom_by_factor(1.0 / 1.12)
	)
	zoom_in_button.pressed.connect(func() -> void:
		canvas.zoom_by_factor(1.12)
	)
	graph_margin.add_child(canvas)

	var detail_panel: PanelContainer = PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(300, 640)
	detail_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.05, 0.048, 0.82), Color(0.50, 0.82, 0.74, 0.48), 10))
	graph_row.add_child(detail_panel)

	var detail_margin: MarginContainer = MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 12)
	detail_margin.add_theme_constant_override("margin_top", 12)
	detail_margin.add_theme_constant_override("margin_right", 12)
	detail_margin.add_theme_constant_override("margin_bottom", 12)
	detail_panel.add_child(detail_margin)

	var detail_stack: VBoxContainer = VBoxContainer.new()
	detail_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_stack.add_theme_constant_override("separation", 8)
	detail_margin.add_child(detail_stack)
	var detail_node_id: String = _hovered_skill_web_node_id if _hovered_skill_web_node_id != "" else _selected_skill_web_node_id
	_build_skill_web_warband_stats_header(detail_stack, web)
	_build_skill_web_selected_node_detail(detail_stack, warband_id, web, detail_node_id)

	# Hover and click should feel instant. v0.12.2 rebuilt the entire screen on
	# every hover change, which made the side panel lag behind the mouse. This
	# patch only redraws the canvas highlight and rebuilds the small node-detail
	# stack. Purchase still refreshes the full screen because it changes backend
	# state and node availability.
	canvas.node_selected.connect(func(trait_id: String) -> void:
		_selected_skill_web_node_id = trait_id
		_hovered_skill_web_node_id = trait_id
		canvas.selected_node_id = trait_id
		canvas.hovered_node_id = trait_id
		canvas.queue_redraw()
		_clear_children(detail_stack)
		_build_skill_web_warband_stats_header(detail_stack, web)
		_build_skill_web_selected_node_detail(detail_stack, warband_id, web, trait_id)
	)
	canvas.node_hovered.connect(func(trait_id: String) -> void:
		if trait_id != _hovered_skill_web_node_id:
			_hovered_skill_web_node_id = trait_id
			canvas.hovered_node_id = trait_id
			canvas.queue_redraw()
			var hover_detail_id: String = _hovered_skill_web_node_id if _hovered_skill_web_node_id != "" else _selected_skill_web_node_id
			_clear_children(detail_stack)
			_build_skill_web_warband_stats_header(detail_stack, web)
			_build_skill_web_selected_node_detail(detail_stack, warband_id, web, hover_detail_id)
	)

	var available: Array = web.get("available_traits", []) as Array
	var locked: Array = web.get("locked_traits", []) as Array
	var purchased: Array = web.get("purchased_traits", []) as Array
	parent.add_child(_barracks_wrapped_label("Map key: node symbols show their role — ATK offence, DEF defence, CAP captives, LOOT loot, PRE prestige, SUP supply, XP veterans, WPN weapons, SURV survival. Specialist gateways use EAG/JAG/OTO/COY; buying one sets combat doctrine and locks the others. Purchased " + str(purchased.size()) + "; connected " + str(available.size()) + "; locked deeper " + str(locked.size()) + ".", 16, COLOR_MUTED))

func _build_skill_web_selected_node_detail(parent: VBoxContainer, warband_id: String, web: Dictionary, trait_id: String) -> void:
	parent.add_child(_barracks_label("Node Detail", 24, COLOR_TEXT))
	if trait_id == "":
		parent.add_child(_barracks_wrapped_label("Hover over a node to inspect it. Click a node to pin/select it for purchase. Left-click and hold anywhere on the map to drag around the tree. The camera stops at the map edge.", 18, COLOR_MUTED))
		parent.add_child(_barracks_wrapped_label("Each warband can choose only one major specialism. A specialist gateway sets the combat doctrine, opens that troop tradition, and locks the other specialist gateways.", 17, COLOR_MUTED))
		return
	var node: Dictionary = _skill_web_node_by_id(web, trait_id)
	if node.is_empty():
		parent.add_child(_barracks_wrapped_label("Selected node could not be found.", 18, Color(1.0, 0.74, 0.40, 1.0)))
		return
	var statuses: Dictionary = web.get("statuses", {}) as Dictionary
	var status: Dictionary = {}
	if statuses.has(trait_id):
		status = statuses[trait_id] as Dictionary
	var cluster_id: String = String(node.get("cluster", "core"))
	var purchased: bool = bool(status.get("purchased", false))
	var can_purchase: bool = bool(status.get("can_purchase", false))
	var requirements_met: bool = bool(status.get("requirements_met", false))
	var title_suffix: String = ""
	if bool(node.get("specialisation", false)):
		title_suffix = " — Keystone"
	elif purchased:
		title_suffix = " — Purchased"
	var symbol_text: String = _skill_web_node_symbol(node)
	var display_title: String = String(node.get("name", "Node")) + title_suffix
	if symbol_text != "":
		display_title = symbol_text + " — " + display_title
	parent.add_child(_barracks_label(display_title, 21, COLOR_TEXT))
	var node_type_text: String = "Specialisation gateway" if bool(node.get("specialisation", false)) else "Skill node"
	if bool(node.get("capstone", false)):
		node_type_text = "Rare capstone"
	parent.add_child(_barracks_wrapped_label(node_type_text + " — " + _skill_web_cluster_label(cluster_id) + " cluster. Tier " + str(int(node.get("tier", 0))) + ". Cost: " + str(int(node.get("cost", 1))) + " point(s).", 16, _skill_web_cluster_colour(cluster_id)))
	parent.add_child(_barracks_wrapped_label("Symbol: " + symbol_text + " — " + _skill_web_symbol_meaning(symbol_text) + ".", 15, COLOR_TEAL))
	if bool(node.get("specialisation", false)):
		parent.add_child(_barracks_wrapped_label("Doctrine link: purchasing this specialism sets the warband's combat doctrine to " + _skill_web_cluster_label(cluster_id) + " and locks the other specialism gateways.", 16, COLOR_TEAL))
	parent.add_child(_barracks_wrapped_label(String(node.get("description", "")), 16, COLOR_MUTED))
	parent.add_child(_barracks_wrapped_label("Prototype effects: " + _skill_web_effects_text(node.get("effects", {}) as Dictionary) + ". Specialism gateways set combat doctrine; other node effects are not connected to Flower War combat yet.", 16, COLOR_MUTED))
	var requirements: Array = node.get("requires", []) as Array
	var any_requirements: Array = node.get("requires_any", []) as Array
	if requirements.is_empty() and any_requirements.is_empty():
		parent.add_child(_barracks_wrapped_label("Prerequisites: none.", 15, COLOR_MUTED))
	else:
		if not requirements.is_empty():
			parent.add_child(_barracks_wrapped_label("Prerequisites: " + _skill_web_requirement_names(web, requirements) + ".", 15, COLOR_MUTED))
		if not any_requirements.is_empty():
			parent.add_child(_barracks_wrapped_label("Rejoin requirement: one of " + _skill_web_requirement_names(web, any_requirements) + ".", 15, COLOR_MUTED))
	if purchased:
		if bool(node.get("specialisation", false)):
			parent.add_child(_barracks_wrapped_label("Status: purchased. This specialism is the warband's active combat doctrine.", 16, COLOR_TEAL))
		else:
			parent.add_child(_barracks_wrapped_label("Status: purchased and recorded.", 16, COLOR_TEAL))
		return
	if not requirements_met:
		parent.add_child(_barracks_wrapped_label("Locked: " + String(status.get("reason", "Requires prerequisite nodes.")), 16, Color(1.0, 0.74, 0.40, 1.0)))
		return
	if not can_purchase:
		parent.add_child(_barracks_wrapped_label("Connected but blocked: " + String(status.get("reason", "Needs more skill points.")), 16, Color(1.0, 0.74, 0.40, 1.0)))
	else:
		parent.add_child(_barracks_wrapped_label("Status: connected and purchasable.", 16, COLOR_TEAL))
	var buy_button: Button = _barracks_action_button("Purchase Node", true)
	buy_button.disabled = not can_purchase
	buy_button.tooltip_text = String(status.get("reason", ""))
	buy_button.pressed.connect(func() -> void:
		_barracks_purchase_skill_node(warband_id, trait_id)
	)
	parent.add_child(buy_button)

func _build_barracks_skill_web_summary(parent: VBoxContainer, web: Dictionary) -> void:
	var spec: Dictionary = web.get("specialisation", {}) as Dictionary
	var effects: Dictionary = web.get("effect_totals", {}) as Dictionary
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.05, 0.048, 0.78), Color(0.50, 0.82, 0.74, 0.48), 10))
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
	stack.add_child(_barracks_label("Specialism & Doctrine", 23, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Specialism: " + String(spec.get("name", "Unspecialised")) + ". Combat Doctrine: " + String(spec.get("doctrine_name", "Unspecialised")) + ".", 17, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label("Prototype effect totals: " + _skill_web_effects_text(effects) + ". Specialism gateways set combat doctrine; other node effects are not connected to Flower War combat yet.", 17, COLOR_MUTED))
	var points_by_cluster: Dictionary = spec.get("points_by_cluster", {}) as Dictionary
	stack.add_child(_barracks_wrapped_label("Points by cluster: " + _skill_web_cluster_points_text(points_by_cluster) + ".", 16, COLOR_MUTED))

func _add_skill_web_node_card(parent: VBoxContainer, warband_id: String, node: Dictionary, web: Dictionary, show_purchase: bool) -> void:
	var trait_id: String = String(node.get("id", ""))
	var statuses: Dictionary = web.get("statuses", {}) as Dictionary
	var status: Dictionary = {}
	if statuses.has(trait_id):
		status = statuses[trait_id] as Dictionary
	var purchased: bool = bool(status.get("purchased", false))
	var requirements_met: bool = bool(status.get("requirements_met", false))
	var can_purchase: bool = bool(status.get("can_purchase", false))
	var cluster_id: String = String(node.get("cluster", "core"))
	var border: Color = _skill_web_cluster_colour(cluster_id)
	if purchased:
		border = border.lightened(0.22)
	elif not requirements_met:
		border = Color(0.42, 0.42, 0.40, 0.55)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.040, 0.038, 0.78), border, 9))
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
	var title_suffix: String = ""
	if bool(node.get("specialisation", false)):
		title_suffix = " — Keystone"
	elif purchased:
		title_suffix = " — Purchased"
	stack.add_child(_barracks_label(String(node.get("name", "Node")) + title_suffix, 20, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label(_skill_web_cluster_label(cluster_id) + " cluster. Tier " + str(int(node.get("tier", 0))) + ". Position " + str(int(node.get("x", 0))) + ", " + str(int(node.get("y", 0))) + ". Cost: " + str(int(node.get("cost", 1))) + " point(s).", 15, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label(String(node.get("description", "")), 15, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Effects: " + _skill_web_effects_text(node.get("effects", {}) as Dictionary) + ".", 15, COLOR_MUTED))
	if not requirements_met and not purchased:
		stack.add_child(_barracks_wrapped_label("Locked: " + String(status.get("reason", "Requires prerequisite nodes.")), 15, Color(1.0, 0.74, 0.40, 1.0)))
	elif not can_purchase and not purchased:
		stack.add_child(_barracks_wrapped_label("Connected but blocked: " + String(status.get("reason", "Needs more skill points.")), 15, Color(1.0, 0.74, 0.40, 1.0)))
	if show_purchase and not purchased:
		var buy_button: Button = _barracks_action_button("Purchase Node", true)
		buy_button.disabled = not can_purchase
		buy_button.tooltip_text = String(status.get("reason", ""))
		buy_button.pressed.connect(func() -> void:
			_barracks_purchase_skill_node(warband_id, trait_id)
		)
		stack.add_child(buy_button)

func _barracks_purchase_skill_node(warband_id: String, trait_id: String) -> void:
	var state: Node = _state()
	_last_skill_web_report.clear()
	if state == null or not state.has_method("purchase_warband_trait"):
		_last_skill_web_report.append("Skill Web purchase failed: backend purchase method is not available.")
		_refresh_all()
		return
	var raw: Variant = state.call("purchase_warband_trait", warband_id, trait_id)
	if raw is Dictionary:
		var result: Dictionary = raw as Dictionary
		_last_skill_web_report.append(String(result.get("reason", "Skill Web purchase resolved.")))
	else:
		_last_skill_web_report.append("Skill Web purchase resolved.")
	_refresh_all()

func _barracks_skill_web_data(warband_id: String) -> Dictionary:
	var state: Node = _state()
	if state == null or not state.has_method("get_warband_skill_web"):
		return {"ok": false, "reason": "Skill Web backend is not available on TRGameState."}
	var raw: Variant = state.call("get_warband_skill_web", warband_id)
	if raw is Dictionary:
		return raw as Dictionary
	return {"ok": false, "reason": "Skill Web backend returned invalid data."}

func _skill_web_node_by_id(web: Dictionary, trait_id: String) -> Dictionary:
	var nodes: Array = web.get("nodes", []) as Array
	for node_variant: Variant in nodes:
		if node_variant is Dictionary:
			var node: Dictionary = node_variant as Dictionary
			if String(node.get("id", "")) == trait_id:
				return node
	return {}

func _skill_web_requirement_names(web: Dictionary, requirements: Array) -> String:
	var parts: Array[String] = []
	for req_variant: Variant in requirements:
		var req_id: String = String(req_variant)
		var req_node: Dictionary = _skill_web_node_by_id(web, req_id)
		if req_node.is_empty():
			parts.append(req_id)
		else:
			parts.append(String(req_node.get("name", req_id)))
	if parts.is_empty():
		return "none"
	return ", ".join(parts)

func _skill_web_nodes_for_ids(web: Dictionary, ids: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var nodes: Array = web.get("nodes", []) as Array
	for wanted_variant: Variant in ids:
		var wanted_id: String = String(wanted_variant)
		for node_variant: Variant in nodes:
			if node_variant is Dictionary:
				var node: Dictionary = node_variant as Dictionary
				if String(node.get("id", "")) == wanted_id:
					output.append(node)
					break
	return output

func _skill_web_node_symbol(node: Dictionary) -> String:
	if node.has("symbol"):
		return String(node.get("symbol", ""))
	var cluster_id: String = String(node.get("cluster", "core"))
	if bool(node.get("capstone", false)):
		match cluster_id:
			"eagle":
				return "E III"
			"jaguar":
				return "J III"
			"otomi":
				return "O III"
			"coyote":
				return "C III"
		return "III"
	if bool(node.get("specialisation", false)):
		match cluster_id:
			"eagle":
				return "EAG"
			"jaguar":
				return "JAG"
			"otomi":
				return "OTO"
			"coyote":
				return "COY"
		return "SPEC"
	var effects: Dictionary = node.get("effects", {}) as Dictionary
	if effects.has("capture_chance_add"):
		return "CAP"
	if effects.has("offence_add"):
		return "ATK"
	if effects.has("defence_add"):
		return "DEF"
	if effects.has("loot_value_add"):
		return "LOOT"
	if effects.has("prestige_pending_add"):
		return "PRE"
	if effects.has("provisioning_discount_add"):
		return "SUP"
	if effects.has("xp_gain_add"):
		return "XP"
	if effects.has("death_chance_add") or effects.has("casualty_chance_add"):
		return "SURV"
	if effects.has("injury_recovery_add"):
		return "REC"
	if effects.has("weapon_efficiency_add") or effects.has("weapon_loss_add"):
		return "WPN"
	if effects.has("ready_warriors_add"):
		return "RDY"
	if effects.has("enemy_defence_add"):
		return "BRK"
	match cluster_id:
		"core":
			return "CORE"
		"eagle":
			return "E"
		"jaguar":
			return "J"
		"otomi":
			return "O"
		"coyote":
			return "C"
		"veteran":
			return "XP"
		"supply":
			return "SUP"
	return "•"

func _skill_web_symbol_meaning(symbol: String) -> String:
	match symbol:
		"ATK":
			return "offence or killing power"
		"DEF":
			return "defence and staying power"
		"CAP":
			return "captive-taking"
		"LOOT":
			return "looted goods"
		"PRE":
			return "prestige hook"
		"SUP":
			return "supply or provisioning efficiency"
		"XP":
			return "veteran growth"
		"SURV":
			return "casualty survival"
		"REC":
			return "injury recovery"
		"WPN":
			return "weapon use"
		"RDY":
			return "readiness"
		"BRK":
			return "enemy disruption"
		"EAG":
			return "Eagle specialism gateway"
		"JAG":
			return "Jaguar specialism gateway"
		"OTO":
			return "Otomi specialism gateway"
		"COY":
			return "Coyote specialism gateway"
		"E III", "J III", "O III", "C III", "III":
			return "final capstone"
		"CORE":
			return "shared warband core"
	return "troop tradition node"

func _skill_web_effects_text(effects: Dictionary) -> String:
	if effects.is_empty():
		return "none yet"
	var parts: Array[String] = []
	for key_variant: Variant in effects.keys():
		var key: String = String(key_variant)
		var value: float = float(effects[key_variant])
		parts.append(_skill_web_effect_name(key) + " " + _skill_web_signed_percent_or_number(value))
	if parts.is_empty():
		return "none yet"
	return ", ".join(parts)

func _skill_web_effect_name(effect_id: String) -> String:
	match effect_id:
		"capture_chance_add":
			return "capture chance"
		"loot_value_add":
			return "loot value"
		"offence_add":
			return "offence"
		"defence_add":
			return "defence"
		"death_chance_add":
			return "death chance"
		"casualty_chance_add":
			return "casualty chance"
		"xp_gain_add":
			return "XP gain"
		"weapon_efficiency_add":
			return "weapon efficiency"
		"weapon_loss_add":
			return "weapon loss"
		"provisioning_discount_add":
			return "provisioning discount"
		"injury_recovery_add":
			return "injury recovery"
		"ready_warriors_add":
			return "ready warriors"
		"enemy_defence_add":
			return "enemy defence"
		"prestige_pending_add":
			return "prestige hook"
	return effect_id.replace("_", " ").capitalize()

func _skill_web_signed_percent_or_number(value: float) -> String:
	var sign: String = "+" if value >= 0.0 else ""
	if absf(value) < 1.0:
		return sign + str(roundi(value * 100.0)) + "%"
	return sign + _format_float(value)

func _skill_web_cluster_points_text(points_by_cluster: Dictionary) -> String:
	if points_by_cluster.is_empty():
		return "none yet"
	var order: Array[String] = ["eagle", "jaguar", "otomi", "coyote", "veteran", "supply", "core"]
	var parts: Array[String] = []
	for cluster_id: String in order:
		var points: int = int(points_by_cluster.get(cluster_id, 0))
		if points > 0:
			parts.append(_skill_web_cluster_label(cluster_id) + " " + str(points))
	for key_variant: Variant in points_by_cluster.keys():
		var key: String = String(key_variant)
		if order.has(key):
			continue
		var points_other: int = int(points_by_cluster.get(key, 0))
		if points_other > 0:
			parts.append(_skill_web_cluster_label(key) + " " + str(points_other))
	if parts.is_empty():
		return "none yet"
	return ", ".join(parts)

func _skill_web_cluster_label(cluster_id: String) -> String:
	match cluster_id:
		"eagle":
			return "Eagle"
		"jaguar":
			return "Jaguar"
		"otomi":
			return "Otomi"
		"coyote":
			return "Coyote"
		"veteran":
			return "Veteran"
		"supply":
			return "Supply"
		"core":
			return "Household"
	return cluster_id.capitalize()

func _skill_web_cluster_colour(cluster_id: String) -> Color:
	match cluster_id:
		"eagle":
			return Color(0.82, 0.78, 0.46, 0.75)
		"jaguar":
			return Color(0.88, 0.48, 0.28, 0.75)
		"otomi":
			return Color(0.45, 0.68, 0.92, 0.75)
		"coyote":
			return Color(0.64, 0.78, 0.42, 0.75)
		"veteran":
			return Color(0.78, 0.66, 0.94, 0.75)
		"supply":
			return Color(0.56, 0.82, 0.78, 0.75)
		"core":
			return Color(0.50, 0.82, 0.74, 0.75)
	return Color(0.50, 0.82, 0.74, 0.55)

func _build_barracks_skill_web_report_notifications(warband_id: String) -> void:
	var web: Dictionary = _barracks_skill_web_data(warband_id)
	if not bool(web.get("ok", false)):
		_add_notification("Skill Web could not be read: " + String(web.get("reason", "Unknown warband.")))
		return
	var warband: Dictionary = web.get("warband", {}) as Dictionary
	var spec: Dictionary = web.get("specialisation", {}) as Dictionary
	_add_notification(String(warband.get("name", "Warband")) + " Skill Web open. Points: " + str(int(web.get("points_available", 0))) + " unspent / " + str(int(web.get("points_total", 0))) + " earned.")
	_add_notification("Specialisation: " + String(spec.get("name", "Unspecialised")) + ". Effects: " + _skill_web_effects_text(web.get("effect_totals", {}) as Dictionary) + ".")
	_add_notification("Use the main panel to buy connected nodes. Locked nodes show their prerequisite chain.")
	if not _last_skill_web_report.is_empty():
		for line: String in _last_skill_web_report:
			_add_notification(line)

func _barracks_open_skill_web_preview(row: Dictionary) -> void:
	var name_text: String = String(row.get("name", "Warband"))
	var warband_id: String = String(row.get("id", ""))
	var level: int = int(row.get("level", 1))
	var state: Node = _state()
	if state == null or not state.has_method("get_warband_skill_web"):
		var fallback_points: int = int(row.get("trait_points", 0))
		_add_notification(name_text + " Skill Web preview: Level " + str(level) + ", unspent skill points " + str(fallback_points) + ".")
		_add_notification("Skill Web backend is not available on the current TRGameState file.")
		return
	var raw: Variant = state.call("get_warband_skill_web", warband_id)
	if not (raw is Dictionary):
		_add_notification(name_text + " Skill Web preview could not be read.")
		return
	var web: Dictionary = raw as Dictionary
	if not bool(web.get("ok", false)):
		_add_notification(name_text + " Skill Web blocked: " + String(web.get("reason", "Unknown warband.")))
		return
	var points_available: int = int(web.get("points_available", 0))
	var points_total: int = int(web.get("points_total", max(0, level - 1)))
	var points_spent: int = int(web.get("points_spent", max(0, points_total - points_available)))
	var spec: Dictionary = web.get("specialisation", {}) as Dictionary
	var purchased: Array = web.get("purchased_traits", []) as Array
	var available: Array = web.get("available_traits", []) as Array
	var locked: Array = web.get("locked_traits", []) as Array
	_add_notification(name_text + " Skill Web: Level " + str(level) + "; points " + str(points_available) + " unspent / " + str(points_total) + " earned; spent " + str(points_spent) + ".")
	_add_notification("Specialisation: " + String(spec.get("name", "Unspecialised")) + ". One specialist gateway locks the other specialist gateways.")
	_add_notification("Purchased nodes: " + str(purchased.size()) + ". Locked nodes: " + str(locked.size()) + ".")
	if available.is_empty():
		_add_notification("No affordable connected nodes are currently available. Gain a level or purchase prerequisites once the full UI is connected.")
	else:
		var parts: Array[String] = []
		for item_variant: Variant in available:
			if parts.size() >= 5:
				break
			if item_variant is Dictionary:
				var node: Dictionary = item_variant as Dictionary
				var affordability: String = ""
				if not bool(node.get("can_afford", true)):
					affordability = " needs points"
				parts.append(String(node.get("name", "Node")) + " [" + String(node.get("cluster", "core")).capitalize() + ", cost " + str(int(node.get("cost", 1))) + affordability + "]")
		_add_notification("Connected nodes: " + ", ".join(parts) + ("." if available.size() <= 5 else ", +" + str(available.size() - 5) + " more."))
	_add_notification("The visual Skill Web is active. Buying a specialism gateway sets the warband's combat doctrine and locks the other specialism gateways. The map is symmetrical, bounded, and zoomable.")

func _barracks_summary() -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("get_barracks_summary"):
		var raw: Variant = state.call("get_barracks_summary")
		if raw is Dictionary:
			return raw as Dictionary
	return {"warriors": 0, "capacity": 0, "free_capacity": 0, "weapons": 0.0, "captives": 0}

func _barracks_flower_options() -> Array[Dictionary]:
	var state: Node = _state()
	if state != null and state.has_method("get_flower_war_options"):
		var raw: Variant = state.call("get_flower_war_options")
		if raw is Array:
			var output: Array[Dictionary] = []
			for item: Variant in raw as Array:
				if item is Dictionary:
					output.append(item as Dictionary)
			return output
	return []

func _barracks_preview_for_option(option: Dictionary) -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("get_flower_war_preview"):
		var raw: Variant = state.call("get_flower_war_preview", String(option.get("id", "minor")), "unspecialised", "standard")
		if raw is Dictionary:
			return raw as Dictionary
	return {}

func _barracks_preview_for_all_warbands_option(option: Dictionary) -> Dictionary:
	var state: Node = _state()
	var option_id: String = String(option.get("id", "minor"))
	if state != null and state.has_method("get_flower_war_preview_with_all_warbands"):
		var raw: Variant = state.call("get_flower_war_preview_with_all_warbands", option_id, "standard")
		if raw is Dictionary:
			return raw as Dictionary
	return _barracks_preview_for_option(option)

func _barracks_preview_for_warband_option(row: Dictionary, option: Dictionary) -> Dictionary:
	var state: Node = _state()
	var warband_id: String = String(row.get("id", ""))
	var option_id: String = String(option.get("id", "minor"))
	var doctrine_id: String = String(row.get("doctrine", "unspecialised"))
	if doctrine_id == "":
		doctrine_id = "unspecialised"
	if state != null and state.has_method("get_flower_war_preview_with_warband"):
		var raw: Variant = state.call("get_flower_war_preview_with_warband", warband_id, option_id, doctrine_id, "standard")
		if raw is Dictionary:
			return raw as Dictionary
	return _barracks_preview_for_option(option)

func _barracks_can_launch(option_id: String, doctrine_id: String, provisioning_id: String) -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("can_launch_flower_war"):
		var raw: Variant = state.call("can_launch_flower_war", option_id, doctrine_id, provisioning_id)
		if raw is Dictionary:
			return raw as Dictionary
	return {"ok": false, "reason": "Flower War launch backend is not connected."}

func _barracks_can_launch_all_warbands(option_id: String, provisioning_id: String) -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("can_launch_flower_war_with_all_warbands"):
		var raw: Variant = state.call("can_launch_flower_war_with_all_warbands", option_id, provisioning_id)
		if raw is Dictionary:
			return raw as Dictionary
	return _barracks_can_launch(option_id, "unspecialised", provisioning_id)

func _barracks_can_launch_warband(warband_id: String, option_id: String, doctrine_id: String, provisioning_id: String) -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("can_launch_flower_war_with_warband"):
		var raw: Variant = state.call("can_launch_flower_war_with_warband", warband_id, option_id, doctrine_id, provisioning_id)
		if raw is Dictionary:
			return raw as Dictionary
	return _barracks_can_launch(option_id, doctrine_id, provisioning_id)

func _barracks_last_report_lines() -> Array[String]:
	var state: Node = _state()
	if state != null and state.has_method("get_last_flower_war_report"):
		var raw: Variant = state.call("get_last_flower_war_report")
		if raw is Dictionary:
			var report: Dictionary = raw as Dictionary
			if report.is_empty():
				return ["No Flower War has been launched yet."]
			if not bool(report.get("ok", false)):
				return ["Flower War blocked: " + String(report.get("reason", "Unknown reason")) + "."]
			var lines: Array[String] = []
			lines.append(String(report.get("warband_name", "Warband")) + " fought " + String(report.get("option_name", "Flower War")) + ": " + String(report.get("result", "Unknown")) + ".")
			lines.append("Committed " + str(int(report.get("committed_warriors", report.get("warriors_committed", 0)))) + "; casualties " + str(int(report.get("attacker_losses", report.get("attacker_casualties", 0)))) + " (injured " + str(int(report.get("attacker_injured", 0))) + ", dead " + str(int(report.get("attacker_dead", 0))) + "); captives " + str(int(report.get("captives", 0))) + "; XP +" + str(int(report.get("xp_gained", 0))) + ".")
			var participant_reports: Array = report.get("participant_reports", []) as Array
			if not participant_reports.is_empty():
				for participant_variant: Variant in participant_reports:
					var participant: Dictionary = participant_variant as Dictionary
					lines.append(String(participant.get("name", "Warband")) + ": committed " + str(int(participant.get("committed", 0))) + "; casualties " + str(int(participant.get("casualties", 0))) + "; injured " + str(int(participant.get("injured", 0))) + "; dead " + str(int(participant.get("dead", 0))) + "; XP +" + str(int(participant.get("xp_gained", 0))) + ".")
			var level_reports: Array = report.get("level_reports", []) as Array
			for level_variant: Variant in level_reports:
				lines.append(String(level_variant) + ".")
			if int(report.get("level_after", 0)) > int(report.get("level_before", 0)):
				lines.append(String(report.get("warband_name", "Warband")) + " reached Level " + str(int(report.get("level_after", 0))) + ".")
			lines.append("Loot value " + _format_float(float(report.get("loot_value", 0.0))) + ". Prestige " + _format_signed_prestige_ui(float(report.get("prestige_gain", 0.0))) + ".")
			return lines
		if raw is Array:
			var output: Array[String] = []
			for item: Variant in raw as Array:
				output.append(String(item))
			if output.is_empty():
				output.append("No Flower War has been launched yet.")
			return output
	return ["No Flower War has been launched yet."]

func _barracks_label(text: String, font_size: int, colour: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.clip_text = true
	return label

func _barracks_wrapped_label(text: String, font_size: int, colour: Color) -> Label:
	var label: Label = _barracks_label(text, font_size, colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	return label
