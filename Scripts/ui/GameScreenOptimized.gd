# GameScreenOptimized.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenOptimized.gd
#
# Patch 8P2B: consolidated active GameScreen wrapper.
#
# This class folds the 8P1B-F wrapper stack into one active script:
# - coalesced UI refresh
# - Estate per-refresh snapshot cache
# - lazy screen-art loading
# - stable top-row / report-button node reuse
#
# It intentionally extends the pre-existing GameScreenMarketOverviewPatch.gd
# coordinator so no gameplay systems, CampaignState ownership, or UI controllers
# are moved in this patch. Old wrapper scripts/scenes are left as retired
# compatibility shims only.
extends "res://Scripts/ui/GameScreenMarketOverviewPatch.gd"

var _refresh_pending: bool = false
var _refresh_flushing: bool = false
var _estate_overview_snapshot: Dictionary = {}
var _estate_snapshot_active: bool = false
const LAZY_ART_PATHS: Dictionary = {
	"estate": "res://Assets/main_menu/Main menu.png",
	"production": "res://Assets/main_menu/Chinampa.png",
	"production_overview": "res://Assets/main_menu/Workshop and Chinampa.png",
	"production_chinampas": "res://Assets/main_menu/Chinampa.png",
	"production_workshops": "res://Assets/main_menu/Workshop.png",
	"storehouse": "res://Assets/main_menu/Storehouse.png",
	"market": "res://Assets/main_menu/Marketpalce.png",
	"housing": "res://Assets/main_menu/Housing.png",
	"shrines": "res://Assets/main_menu/Shrines.png",
	"warriors": "res://Assets/main_menu/Barracks.png",
	"palace": "res://Assets/main_menu/Palace.png",
	"rivals": "res://Assets/main_menu/Rivals.png"
}

var _lazy_screen_art_cache: Dictionary = {}
var _top_area_reuse_key: String = ""
var _top_focus_buttons: Dictionary = {}
var _right_report_panel_key: String = ""
var _right_report_buttons: Dictionary = {}
var _right_report_close_button: Button = null


# -----------------------------------------------------------------------------
# Coalesced full-screen refresh
# -----------------------------------------------------------------------------

func _ready() -> void:
	# Estate is the starting screen, so load only the Estate image up front. Other
	# screen images are loaded on first open and then kept in this small cache.
	_lazy_art("estate")
	super._ready()


func _refresh_all() -> void:
	# Base GameScreen and extracted wrapper handlers still call _refresh_all()
	# directly. Route those calls through a single deferred flush so duplicated
	# requests from state_changed + manual handlers collapse into one rebuild.
	if _refresh_flushing:
		super._refresh_all()
		return
	_request_refresh_all()


func _request_refresh_all() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_flush_refresh_all")


func _flush_refresh_all() -> void:
	if not _refresh_pending:
		return
	_prepare_estate_overview_snapshot_for_refresh()
	_refresh_pending = false
	_refresh_flushing = true
	super._refresh_all()
	_refresh_flushing = false


func _on_state_changed() -> void:
	# State changes can arrive during the same frame as a user action that also
	# requested a refresh. Keep this as a refresh request, not an immediate rebuild.
	_request_refresh_all()


# -----------------------------------------------------------------------------
# Estate per-refresh snapshot cache
# -----------------------------------------------------------------------------


func _prepare_estate_overview_snapshot_for_refresh() -> void:
	_estate_overview_snapshot.clear()
	_estate_snapshot_active = false
	if current_location_id != "estate":
		return
	_estate_overview_snapshot = _build_estate_overview_snapshot()
	_estate_snapshot_active = true


func get_estate_overview_snapshot() -> Dictionary:
	if _estate_snapshot_active:
		return _estate_overview_snapshot.duplicate(true)
	return _build_estate_overview_snapshot()


func _build_estate_overview_snapshot() -> Dictionary:
	var state: Node = _state()
	var snapshot: Dictionary = {
		"previous_turn_lines": _read_last_turn_report_lines_uncached(state),
		"production_resolution": {},
		"production_output_totals": {},
		"production_input_totals": {},
		"storehouse_goods": [],
		"goods_warning_lines": [],
		"housing_summary": {},
		"production_building_summary": {},
		"production_buildable_count": 0,
		"action_priority_lines": []
	}

	if state == null:
		return snapshot

	var production_resolution: Dictionary = _read_production_resolution_uncached(state)
	snapshot["production_resolution"] = production_resolution
	snapshot["production_output_totals"] = _dictionary_copy(production_resolution.get("outputs", {}) as Dictionary)
	snapshot["production_input_totals"] = _dictionary_copy(production_resolution.get("inputs", {}) as Dictionary)
	snapshot["housing_summary"] = super._housing_summary()
	snapshot["production_building_summary"] = _build_production_summary_from_resolution(state, production_resolution)
	snapshot["production_buildable_count"] = _read_production_buildable_count_uncached(state)
	snapshot["storehouse_goods"] = _build_storehouse_goods_from_snapshot(state, snapshot)
	snapshot["goods_warning_lines"] = _build_goods_warning_lines_from_goods(snapshot["storehouse_goods"] as Array, 99)
	snapshot["action_priority_lines"] = _build_action_priority_lines_from_snapshot(snapshot, 99)

	return snapshot


# -----------------------------------------------------------------------------
# Estate helper overrides
# -----------------------------------------------------------------------------

func _last_turn_report_lines() -> Array[String]:
	if _estate_snapshot_active and _estate_overview_snapshot.has("previous_turn_lines"):
		return _string_array_copy(_estate_overview_snapshot.get("previous_turn_lines", []))
	return super._last_turn_report_lines()


func _storehouse_goods() -> Array[Dictionary]:
	if _estate_snapshot_active and _estate_overview_snapshot.has("storehouse_goods"):
		return _dictionary_array_copy(_estate_overview_snapshot.get("storehouse_goods", []))
	return super._storehouse_goods()


func _production_output_totals() -> Dictionary:
	if _estate_snapshot_active and _estate_overview_snapshot.has("production_output_totals"):
		return _dictionary_copy(_estate_overview_snapshot.get("production_output_totals", {}) as Dictionary)
	return super._production_output_totals()


func _production_input_totals() -> Dictionary:
	if _estate_snapshot_active and _estate_overview_snapshot.has("production_input_totals"):
		return _dictionary_copy(_estate_overview_snapshot.get("production_input_totals", {}) as Dictionary)
	return super._production_input_totals()


func _housing_summary() -> Dictionary:
	if _estate_snapshot_active and _estate_overview_snapshot.has("housing_summary"):
		return _dictionary_copy(_estate_overview_snapshot.get("housing_summary", {}) as Dictionary)
	return super._housing_summary()


func _production_building_summary() -> Dictionary:
	if _estate_snapshot_active and _estate_overview_snapshot.has("production_building_summary"):
		return _dictionary_copy(_estate_overview_snapshot.get("production_building_summary", {}) as Dictionary)
	return super._production_building_summary()


func _production_buildable_count() -> int:
	if _estate_snapshot_active and _estate_overview_snapshot.has("production_buildable_count"):
		return int(_estate_overview_snapshot.get("production_buildable_count", 0))
	return super._production_buildable_count()


func _estate_goods_warning_lines(max_items: int = 8) -> Array[String]:
	if _estate_snapshot_active and _estate_overview_snapshot.has("goods_warning_lines"):
		return _limited_string_array(_estate_overview_snapshot.get("goods_warning_lines", []), max_items)
	return super._estate_goods_warning_lines(max_items)


func _estate_action_priority_lines(max_items: int = 8) -> Array[String]:
	if _estate_snapshot_active and _estate_overview_snapshot.has("action_priority_lines"):
		return _limited_string_array(_estate_overview_snapshot.get("action_priority_lines", []), max_items)
	return super._estate_action_priority_lines(max_items)


# -----------------------------------------------------------------------------
# Snapshot construction helpers
# -----------------------------------------------------------------------------

func _read_last_turn_report_lines_uncached(state: Node) -> Array[String]:
	var output: Array[String] = []
	if state != null and state.has_method("get_last_report"):
		var raw: Array = state.call("get_last_report") as Array
		for line_variant: Variant in raw:
			var line: String = String(line_variant)
			if line.strip_edges() != "":
				output.append(line)
	return output


func _read_production_resolution_uncached(state: Node) -> Dictionary:
	if state != null and state.has_method("estimate_production_resolution"):
		var raw: Variant = state.call("estimate_production_resolution")
		if raw is Dictionary:
			return (raw as Dictionary).duplicate(true)
	return {}


func _read_production_buildable_count_uncached(state: Node) -> int:
	var count: int = 0
	var campaign_state: RefCounted = _campaign_state_for_snapshot(state)
	if campaign_state == null:
		return super._production_buildable_count()
	if not campaign_state.has_method("get_buildings_copy") or not campaign_state.has_method("get_building_order_copy"):
		return super._production_buildable_count()

	var buildings: Dictionary = campaign_state.call("get_buildings_copy") as Dictionary
	var order: Array = campaign_state.call("get_building_order_copy") as Array
	for building_variant: Variant in order:
		var building_id: String = String(building_variant)
		if not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var screen_id: String = String(definition.get("screen", ""))
		if screen_id != "chinampas" and screen_id != "workshops":
			continue
		if state.has_method("can_build") and bool(state.call("can_build", building_id)):
			count += 1
	return count


func _build_production_summary_from_resolution(state: Node, production_resolution: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"built": 0,
		"operating": 0,
		"blocked": 0,
		"blocked_lines": [],
		"unbuilt_lines": []
	}

	var campaign_state: RefCounted = _campaign_state_for_snapshot(state)
	if campaign_state == null:
		return super._production_building_summary()
	if not campaign_state.has_method("get_buildings_copy") or not campaign_state.has_method("get_building_order_copy") or not campaign_state.has_method("get_estate_buildings_copy"):
		return super._production_building_summary()

	var buildings: Dictionary = campaign_state.call("get_buildings_copy") as Dictionary
	var order: Array = campaign_state.call("get_building_order_copy") as Array
	var estate_buildings: Dictionary = campaign_state.call("get_estate_buildings_copy") as Dictionary
	var statuses: Dictionary = production_resolution.get("building_statuses", {}) as Dictionary
	var blocked_lines: Array[String] = []
	var unbuilt_lines: Array[String] = []
	var built_count: int = 0
	var operating_count: int = 0
	var blocked_count: int = 0

	for building_variant: Variant in order:
		var building_id: String = String(building_variant)
		if not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var screen_id: String = String(definition.get("screen", ""))
		if screen_id != "chinampas" and screen_id != "workshops":
			continue

		var name: String = String(definition.get("name", building_id.capitalize()))
		var count: int = int(estate_buildings.get(building_id, 0))
		var status: Dictionary = statuses.get(building_id, {}) as Dictionary
		var operating: int = int(status.get("operating", 0))
		var blocked: int = int(status.get("blocked", 0))

		built_count += count
		operating_count += operating
		blocked_count += blocked

		if count <= 0:
			unbuilt_lines.append(name + " not built")
		elif blocked > 0:
			blocked_lines.append(name + " " + String(status.get("status_text", "blocked")))

	result["built"] = built_count
	result["operating"] = operating_count
	result["blocked"] = blocked_count
	result["blocked_lines"] = blocked_lines
	result["unbuilt_lines"] = unbuilt_lines
	return result


func _build_storehouse_goods_from_snapshot(state: Node, snapshot: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var campaign_state: RefCounted = _campaign_state_for_snapshot(state)
	if campaign_state == null:
		return output
	if not campaign_state.has_method("get_resource_order_copy") or not campaign_state.has_method("get_resources_copy") or not campaign_state.has_method("get_estate_stock"):
		return output

	var resource_order: Array = campaign_state.call("get_resource_order_copy") as Array
	var resources: Dictionary = campaign_state.call("get_resources_copy") as Dictionary
	var incoming: Dictionary = snapshot.get("production_output_totals", {}) as Dictionary
	var building_inputs: Dictionary = snapshot.get("production_input_totals", {}) as Dictionary
	var production_resolution: Dictionary = snapshot.get("production_resolution", {}) as Dictionary
	var housing_maintenance: Dictionary = production_resolution.get("housing_maintenance_needed", {}) as Dictionary
	var upkeep: Dictionary = production_resolution.get("upkeep_needed", {}) as Dictionary

	if housing_maintenance.is_empty() and state.has_method("estimate_housing_maintenance"):
		housing_maintenance = state.call("estimate_housing_maintenance") as Dictionary
	if upkeep.is_empty() and state.has_method("estimate_population_upkeep"):
		upkeep = state.call("estimate_population_upkeep") as Dictionary

	for resource_variant: Variant in resource_order:
		var resource_id: String = String(resource_variant)
		if not resources.has(resource_id):
			continue

		var resource_data: Dictionary = resources[resource_id] as Dictionary
		var stored: float = float(campaign_state.call("get_estate_stock", resource_id))
		var in_value: float = float(incoming.get(resource_id, 0.0))
		var upkeep_value: float = float(upkeep.get(resource_id, 0.0))
		var input_value: float = float(building_inputs.get(resource_id, 0.0))
		var housing_value: float = float(housing_maintenance.get(resource_id, 0.0))
		var outgoing: float = upkeep_value + input_value + housing_value
		var reserved: float = outgoing
		var free_value: float = maxf(0.0, stored - reserved)

		output.append({
			"id": resource_id,
			"name": String(resource_data.get("name", resource_id.capitalize())),
			"category": String(resource_data.get("category", "raw")),
			"stored": stored,
			"incoming": in_value,
			"outgoing": outgoing,
			"reserved": reserved,
			"free": free_value,
			"net": in_value - outgoing,
			"pressure": _snapshot_pressure_label(stored, outgoing),
			"uses": resource_data.get("uses", []) as Array,
			"reserved_breakdown": _snapshot_reserve_breakdown(upkeep_value, input_value, housing_value)
		})

	return output


func _build_goods_warning_lines_from_goods(goods: Array, max_items: int) -> Array[String]:
	var output: Array[String] = []
	for good_variant: Variant in goods:
		if output.size() >= max_items:
			break
		if not (good_variant is Dictionary):
			continue
		var good: Dictionary = good_variant as Dictionary
		var name: String = String(good.get("name", "Good"))
		var stored: float = float(good.get("stored", 0.0))
		var incoming: float = float(good.get("incoming", 0.0))
		var outgoing: float = float(good.get("outgoing", 0.0))
		var free_value: float = float(good.get("free", maxf(0.0, stored - outgoing)))
		var projected: float = stored + incoming - outgoing
		if projected < -0.001:
			output.append(name + ": projected shortage of " + _format_float(absf(projected)) + " after next turn.")
		elif free_value <= 0.001 and outgoing > 0.001:
			output.append(name + ": fully reserved by upkeep, maintenance or inputs.")
		elif incoming - outgoing < -0.001:
			output.append(name + ": declining by " + _format_float(absf(incoming - outgoing)) + " this turn.")
	return output


func _build_action_priority_lines_from_snapshot(snapshot: Dictionary, max_items: int) -> Array[String]:
	var output: Array[String] = []
	var warnings: Array[String] = _limited_string_array(snapshot.get("goods_warning_lines", []), 4)
	for warning: String in warnings:
		output.append("Resolve goods pressure — " + warning)

	var housing: Dictionary = snapshot.get("housing_summary", {}) as Dictionary
	var inactive: int = int(housing.get("total_inactive_population", 0))
	if inactive > 0:
		output.append("Open Housing or Mothball — " + str(inactive) + " people are inactive.")

	var production_summary: Dictionary = snapshot.get("production_building_summary", {}) as Dictionary
	var blocked: int = int(production_summary.get("blocked", 0))
	if blocked > 0:
		output.append("Open Production — " + str(blocked) + " production instance(s) are blocked or unstaffed.")

	var buildable_count: int = int(snapshot.get("production_buildable_count", 0))
	if buildable_count > 0:
		output.append("Consider Production expansion — " + str(buildable_count) + " production building type(s) are buildable now.")

	if output.is_empty():
		var outputs: String = _resource_dictionary_inline(snapshot.get("production_output_totals", {}) as Dictionary, 3)
		if outputs != "":
			output.append("Production looks stable. Expected output: " + outputs + ".")
		else:
			output.append("No urgent warning, but production output is low. Consider building or staffing production.")

	while output.size() > max_items:
		output.pop_back()
	return output


# -----------------------------------------------------------------------------
# Small local utilities
# -----------------------------------------------------------------------------

func _campaign_state_for_snapshot(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null


func _snapshot_pressure_label(stored: float, outgoing: float) -> String:
	if outgoing <= 0.0:
		if stored > 0.0:
			return "Surplus"
		return "Idle"
	var coverage: float = stored / outgoing
	if coverage >= 3.0:
		return "Secure"
	if coverage >= 1.5:
		return "Watch"
	if coverage >= 1.0:
		return "Tight"
	return "Shortfall"


func _snapshot_reserve_breakdown(upkeep_value: float, input_value: float, housing_value: float) -> Array[String]:
	var lines: Array[String] = []
	if upkeep_value > 0.0:
		lines.append("Population upkeep: " + _format_float(upkeep_value))
	if input_value > 0.0:
		lines.append("Production inputs: " + _format_float(input_value))
	if housing_value > 0.0:
		lines.append("Housing maintenance: " + _format_float(housing_value))
	if lines.is_empty():
		lines.append("No current reserve.")
	return lines


func _dictionary_copy(values: Dictionary) -> Dictionary:
	return values.duplicate(true)


func _dictionary_array_copy(values: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if values is Array:
		for item_variant: Variant in values as Array:
			if item_variant is Dictionary:
				output.append((item_variant as Dictionary).duplicate(true))
	return output


func _string_array_copy(values: Variant) -> Array[String]:
	var output: Array[String] = []
	if values is Array:
		for item_variant: Variant in values as Array:
			output.append(String(item_variant))
	return output


func _limited_string_array(values: Variant, max_items: int) -> Array[String]:
	var output: Array[String] = []
	if not (values is Array):
		return output
	for item_variant: Variant in values as Array:
		if output.size() >= max_items:
			break
		output.append(String(item_variant))
	return output


# -----------------------------------------------------------------------------
# Lazy screen-art loading
# -----------------------------------------------------------------------------


func _art_for_location(location_id: String) -> Texture2D:
	match location_id:
		"estate":
			return _lazy_art("estate")
		"production":
			return _art_for_production_focus(_current_focus_id())
		"storehouse":
			return _lazy_art("storehouse")
		"market":
			return _lazy_art("market")
		"housing":
			return _art_for_housing_focus(_current_focus_id())
		"shrines":
			var shrine_art: Texture2D = null
			if has_method("_art_for_shrine_focus"):
				shrine_art = call("_art_for_shrine_focus", _current_focus_id()) as Texture2D
			if shrine_art != null:
				return shrine_art
			return _lazy_art("shrines")
		"warriors":
			return _lazy_art("warriors")
		"palace":
			return _lazy_art("palace")
		"rivals":
			return _lazy_art("rivals")
	return null


func _art_for_production_focus(focus_id: String) -> Texture2D:
	match focus_id:
		"overview":
			return _first_available_lazy_art(["production_overview", "production"])
		"chinampas":
			return _first_available_lazy_art(["production_chinampas", "production"])
		"workshops":
			return _first_available_lazy_art(["production_workshops", "production"])
		"labour":
			return _lazy_art("production")
	return _first_available_lazy_art(["production", "estate"])


func _art_for_housing_focus(_focus_id: String) -> Texture2D:
	return _first_available_lazy_art(["housing", "estate"])


func _first_available_lazy_art(keys: Array[String]) -> Texture2D:
	for key: String in keys:
		var texture: Texture2D = _lazy_art(key)
		if texture != null:
			return texture
	return null


func _lazy_art(key: String) -> Texture2D:
	if _lazy_screen_art_cache.has(key):
		return _lazy_screen_art_cache[key] as Texture2D
	var path: String = String(LAZY_ART_PATHS.get(key, ""))
	if path == "" or not ResourceLoader.exists(path):
		_lazy_screen_art_cache[key] = null
		return null
	var loaded: Resource = load(path)
	if loaded is Texture2D:
		_lazy_screen_art_cache[key] = loaded as Texture2D
		return loaded as Texture2D
	_lazy_screen_art_cache[key] = null
	return null


# -----------------------------------------------------------------------------
# Stable UI node reuse
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# Top-area reuse
# -----------------------------------------------------------------------------

func _refresh_top_area() -> void:
	if top_row == null:
		return

	var profile: Dictionary = _profile(current_location_id)
	var top_mode: String = String(profile.get("top_mode", "focus"))
	if top_mode == "calendar":
		_refresh_reused_calendar_row()
	else:
		_refresh_reused_focus_row(profile)


func _refresh_reused_calendar_row() -> void:
	var state: Node = _state()
	var current_veintena: int = 1
	if state != null and state.has_method("get_current_veintena"):
		current_veintena = int(state.call("get_current_veintena"))
	var start_index: int = clampi(current_veintena - 1, 0, _veintenas.size() - 1)
	var end_index: int = mini(start_index + visible_veintenas, _veintenas.size())
	var key: String = "calendar|" + str(start_index) + "|" + str(end_index) + "|" + str(visible_veintenas)

	if _top_area_reuse_key == key and top_row.get_child_count() > 0:
		return

	_top_area_reuse_key = key
	_top_focus_buttons.clear()
	_clear_children_immediate(top_row)
	_build_reused_calendar_cards(start_index, end_index)


func _build_reused_calendar_cards(start_index: int, end_index: int) -> void:
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


func _refresh_reused_focus_row(profile: Dictionary) -> void:
	var focuses: Array = profile.get("focuses", []) as Array
	if focuses.is_empty():
		_top_area_reuse_key = ""
		_top_focus_buttons.clear()
		_clear_children_immediate(top_row)
		return

	var key: String = _focus_row_reuse_key(current_location_id, focuses)
	if _top_area_reuse_key == key and top_row.get_child_count() > 0:
		_update_reused_focus_button_states()
		return

	_top_area_reuse_key = key
	_top_focus_buttons.clear()
	_clear_children_immediate(top_row)

	for focus_variant: Variant in focuses:
		if not (focus_variant is Dictionary):
			continue
		var focus: Dictionary = focus_variant as Dictionary
		var focus_id: String = String(focus.get("id", "overview"))
		var button: Button = Button.new()
		button.text = String(focus.get("label", focus_id.capitalize()))
		button.toggle_mode = true
		button.button_pressed = focus_id == _current_focus_id()
		button.custom_minimum_size = Vector2(150, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 21)
		button.pressed.connect(Callable(self, "_on_reused_focus_pressed").bind(current_location_id, focus_id))
		top_row.add_child(button)
		_top_focus_buttons[focus_id] = button


func _focus_row_reuse_key(location_id: String, focuses: Array) -> String:
	var parts: Array[String] = ["focus", location_id]
	for focus_variant: Variant in focuses:
		if focus_variant is Dictionary:
			var focus: Dictionary = focus_variant as Dictionary
			parts.append(String(focus.get("id", "")) + ":" + String(focus.get("label", "")))
	return "|".join(parts)


func _update_reused_focus_button_states() -> void:
	var selected_focus: String = _current_focus_id()
	for key_variant: Variant in _top_focus_buttons.keys():
		var focus_id: String = String(key_variant)
		var button: Button = _top_focus_buttons[key_variant] as Button
		if button != null:
			button.button_pressed = focus_id == selected_focus


func _on_reused_focus_pressed(location_id: String, focus_id: String) -> void:
	show_focus(location_id, focus_id)


# -----------------------------------------------------------------------------
# Right-panel report-button reuse
# -----------------------------------------------------------------------------

func _refresh_right_panel() -> void:
	var profile: Dictionary = _profile(current_location_id)
	if notification_title:
		notification_title.text = _report_title_for_current_focus(profile)

	_refresh_house_claim()

	if current_location_id == "estate":
		_build_or_update_reused_report_buttons(
			"estate|" + selected_estate_report_id,
			_estate_report_definitions(),
			selected_estate_report_id,
			Callable(self, "_on_estate_report_selected"),
			Callable(self, "_on_estate_report_closed")
		)
		return

	if current_location_id == "production" and _current_focus_id() == "overview":
		_build_or_update_reused_report_buttons(
			"production|overview|" + selected_production_report_id,
			_production_report_definitions(),
			selected_production_report_id,
			Callable(self, "_on_production_report_selected"),
			Callable(self, "_on_production_report_closed")
		)
		return

	if current_location_id == "housing" and _current_focus_id() == "overview":
		_build_or_update_reused_report_buttons(
			"housing|overview|" + selected_housing_report_id,
			_housing_report_definitions(),
			selected_housing_report_id,
			Callable(self, "_on_housing_report_selected"),
			Callable(self, "_on_housing_report_closed")
		)
		return

	_right_report_panel_key = ""
	_right_report_buttons.clear()
	_right_report_close_button = null
	super._refresh_right_panel()


func _build_or_update_reused_report_buttons(panel_key: String, reports: Array, selected_id: String, select_callable: Callable, close_callable: Callable) -> void:
	if notification_list == null:
		return

	var can_update_existing: bool = _right_report_panel_key == panel_key and _right_report_buttons.size() == reports.size()
	if can_update_existing:
		for report_variant: Variant in reports:
			if not (report_variant is Dictionary):
				can_update_existing = false
				break
			var report_id: String = String((report_variant as Dictionary).get("id", ""))
			if report_id == "" or not _right_report_buttons.has(report_id):
				can_update_existing = false
				break

	if not can_update_existing:
		_clear_children_immediate(notification_list)
		_right_report_buttons.clear()
		_right_report_panel_key = panel_key
		for report_variant: Variant in reports:
			if not (report_variant is Dictionary):
				continue
			var report: Dictionary = report_variant as Dictionary
			var button: Button = _make_reused_report_button(report, selected_id, select_callable)
			notification_list.add_child(button)
			_right_report_buttons[String(report.get("id", ""))] = button
		_right_report_close_button = null
		if selected_id != "":
			_right_report_close_button = _make_reused_report_close_button(close_callable)
			notification_list.add_child(_right_report_close_button)
		return

	for report_variant: Variant in reports:
		if not (report_variant is Dictionary):
			continue
		var report: Dictionary = report_variant as Dictionary
		var report_id: String = String(report.get("id", ""))
		var button: Button = _right_report_buttons.get(report_id, null) as Button
		if button != null:
			_configure_reused_report_button(button, report, selected_id)


func _make_reused_report_button(report: Dictionary, selected_id: String, select_callable: Callable) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 94)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.04, 0.07, 0.065, 0.93), Color(0.34, 0.71, 0.63, 0.45), 10))
	button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.06, 0.095, 0.085, 0.96), Color(0.50, 0.82, 0.74, 0.75), 10))
	button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.10, 0.12, 0.095, 0.98), Color(0.76, 0.63, 0.32, 0.86), 10))
	var report_id: String = String(report.get("id", ""))
	button.pressed.connect(select_callable.bind(report_id))
	_configure_reused_report_button(button, report, selected_id)
	return button


func _configure_reused_report_button(button: Button, report: Dictionary, selected_id: String) -> void:
	var report_id: String = String(report.get("id", ""))
	var title: String = String(report.get("title", "Report"))
	var subtitle: String = String(report.get("subtitle", "Open report"))
	button.text = title + "\n" + subtitle
	button.button_pressed = report_id == selected_id
	button.tooltip_text = subtitle


func _make_reused_report_close_button(close_callable: Callable) -> Button:
	var button: Button = Button.new()
	button.text = "Close Report"
	button.custom_minimum_size = Vector2(0, 54)
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(close_callable)
	return button


# -----------------------------------------------------------------------------
# Utility
# -----------------------------------------------------------------------------

func _clear_children_immediate(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
