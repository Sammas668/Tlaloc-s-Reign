# UIScreenContext.gd
# Godot 4.x
# Project path: res://Scripts/ui/UIScreenContext.gd
#
# Shared lightweight context object for extracted screen controllers.
# It replaces long parameter lists and makes controller dependencies explicit.
# This object is UI-facing only: it should not own gameplay rules or live
# campaign state. Patch 8H routes religion through CampaignState rather than
# storing religion state on the UI controller.
class_name UIScreenContext
extends RefCounted

const RELIGION_STATE_SYSTEM_SCRIPT: Script = preload("res://Scripts/Systems/ReligionStateSystem.gd")
const RELIGION_STATE_META_KEY: String = "tr_religion_state_system" # fallback only

var host: Node = null
var content_root: Control = null
var content_text: Control = null
var dynamic_view_host: VBoxContainer = null
var notification_list: VBoxContainer = null
var _fallback_religion_state_system: RefCounted = null

func setup(host_node: Node, content_root_node: Control, content_text_node: Control, dynamic_view_host_node: VBoxContainer, notification_list_node: VBoxContainer) -> UIScreenContext:
	host = host_node
	content_root = content_root_node
	content_text = content_text_node
	dynamic_view_host = dynamic_view_host_node
	notification_list = notification_list_node
	return self

func state() -> Node:
	if host != null and host.has_method("_state"):
		var raw: Variant = host.call("_state")
		if raw is Node:
			return raw as Node
	return null

func religion_state_system() -> RefCounted:
	# Patch 8H: prefer a runtime/CampaignState-backed religion system. Runtime
	# metadata is kept only as a last-resort fallback for older local files.
	var runtime_state: Node = state()
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
					campaign_backed.call("bind_campaign_state", snapshot_raw as RefCounted, ["tlaloc", "huitzilopochtli", "tezcatlipoca", "quetzalcoatl"])
				return campaign_backed
		if runtime_state.has_meta(RELIGION_STATE_META_KEY):
			var meta_raw: Variant = runtime_state.get_meta(RELIGION_STATE_META_KEY)
			if meta_raw is RefCounted:
				return meta_raw as RefCounted
		var runtime_owned: RefCounted = RELIGION_STATE_SYSTEM_SCRIPT.new() as RefCounted
		runtime_state.set_meta(RELIGION_STATE_META_KEY, runtime_owned)
		return runtime_owned

	if _fallback_religion_state_system == null:
		_fallback_religion_state_system = RELIGION_STATE_SYSTEM_SCRIPT.new() as RefCounted
	return _fallback_religion_state_system

func current_focus_id() -> String:
	if host != null and host.has_method("_current_focus_id"):
		return String(host.call("_current_focus_id"))
	return "overview"

func current_location_id() -> String:
	if host != null:
		var raw: Variant = host.get("current_location_id")
		if raw != null:
			return String(raw)
	return ""

func call_host(method_name: String, args: Array = []) -> Variant:
	if host != null and host.has_method(method_name):
		return host.callv(method_name, args)
	return null

func set_content_root_layout(expanded: bool) -> void:
	call_host("_set_content_root_layout", [expanded])

func refresh_all() -> void:
	call_host("_refresh_all")

func refresh_main_content() -> void:
	call_host("_refresh_main_content")

func refresh_right_panel() -> void:
	call_host("_refresh_right_panel")

func add_notification(text: String) -> void:
	call_host("_add_notification", [text])

func make_panel_style(bg_colour: Color, border_colour: Color, radius: int = 10) -> StyleBox:
	var raw: Variant = call_host("_make_panel_style", [bg_colour, border_colour, radius])
	if raw is StyleBox:
		return raw as StyleBox
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_colour
	style.border_color = border_colour
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

func format_religion_amount(value: float) -> String:
	var raw: Variant = call_host("_format_religion_amount", [value])
	if raw != null:
		return String(raw)
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value

func resource_display_name(resource_id: String) -> String:
	var raw: Variant = call_host("_resource_display_name", [resource_id])
	if raw != null:
		return String(raw)
	return resource_id.replace("_", " ").capitalize()

func format_cost(cost: Dictionary) -> String:
	var raw: Variant = call_host("_format_cost", [cost])
	if raw != null:
		return String(raw)
	if cost.is_empty():
		return "none"
	var parts: Array[String] = []
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		parts.append(resource_display_name(resource_id) + " " + format_religion_amount(float(cost[resource_variant])))
	return ", ".join(parts)
