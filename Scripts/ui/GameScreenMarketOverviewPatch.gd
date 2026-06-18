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
var _active_trade_basket_view: Control = null
var _trade_basket_savvy_preview_label: RichTextLabel = null
var _last_trade_basket_savvy_lines: Array = []
var _last_trade_basket_savvy_preview: Dictionary = {}
var _selected_palace_route_id: String = ""
var _pending_palace_dedication_confirm_id: String = ""


class WarbandSkillWebCanvas:
	extends Control

	signal node_selected(trait_id: String)
	signal node_hovered(trait_id: String)
	signal pan_changed(new_pan: Vector2)
	signal zoom_changed(new_zoom: float)

	var web: Dictionary = {}
	var selected_node_id: String = ""
	var hovered_node_id: String = ""
	var pan_offset: Vector2 = Vector2.ZERO
	var zoom_level: float = 0.74
	var min_zoom: float = 0.36
	var max_zoom: float = 1.70
	var node_positions: Dictionary = {}
	var node_radius: float = 22.0
	var keystone_radius: float = 28.0
	var capstone_radius: float = 31.0
	var grid_scale: float = 112.0
	var edge_padding: float = 96.0
	var _dragging: bool = false
	var _drag_started: bool = false
	var _drag_start_mouse: Vector2 = Vector2.ZERO
	var _drag_start_pan: Vector2 = Vector2.ZERO

	func setup(new_web: Dictionary, selected_id: String, hover_id: String, saved_pan: Vector2, saved_zoom: float = 0.74) -> void:
		web = new_web
		selected_node_id = selected_id
		hovered_node_id = hover_id
		zoom_level = clampf(saved_zoom, min_zoom, max_zoom)
		pan_offset = _clamped_pan(saved_pan)
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			var clamped: Vector2 = _clamped_pan(pan_offset)
			if clamped != pan_offset:
				pan_offset = clamped
				pan_changed.emit(pan_offset)
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse_event: InputEventMouseButton = event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
				_zoom_at_position(1.12, mouse_event.position)
				accept_event()
				return
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
				_zoom_at_position(1.0 / 1.12, mouse_event.position)
				accept_event()
				return
			if mouse_event.button_index == MOUSE_BUTTON_LEFT:
				if mouse_event.pressed:
					_dragging = true
					_drag_started = false
					_drag_start_mouse = mouse_event.position
					_drag_start_pan = pan_offset
					accept_event()
				else:
					if _dragging and not _drag_started:
						var clicked_node: String = _node_id_at_position(mouse_event.position)
						if clicked_node != "":
							node_selected.emit(clicked_node)
					_dragging = false
					_drag_started = false
					accept_event()
		elif event is InputEventMouseMotion:
			var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
			if _dragging:
				var delta: Vector2 = motion_event.position - _drag_start_mouse
				if delta.length() > 4.0:
					_drag_started = true
				pan_offset = _clamped_pan(_drag_start_pan + delta)
				pan_changed.emit(pan_offset)
				queue_redraw()
				accept_event()
			else:
				var hovered: String = _node_id_at_position(motion_event.position)
				if hovered != hovered_node_id:
					hovered_node_id = hovered
					node_hovered.emit(hovered_node_id)
					queue_redraw()

	func _draw() -> void:
		node_positions.clear()
		_draw_background()
		var nodes: Array = web.get("nodes", []) as Array
		for node_variant: Variant in nodes:
			if node_variant is Dictionary:
				var node: Dictionary = node_variant as Dictionary
				var node_id: String = String(node.get("id", ""))
				if node_id != "":
					node_positions[node_id] = _screen_position_for_node(node)
		_draw_connections(nodes)
		_draw_nodes(nodes)
		_draw_help_text()

	func _draw_background() -> void:
		var rect: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0.012, 0.020, 0.022, 0.92), true)
		var centre: Vector2 = size * 0.5 + pan_offset
		var step: float = _effective_grid_scale()
		# Keep the grid very quiet. Earlier axis-highlight lines ran directly through
		# the four terminal capstones and looked like connection lines continuing off
		# the screen. The web structure should be read from node links, not from axes.
		var grid_colour: Color = Color(0.18, 0.27, 0.27, 0.10)
		for x_index: int in range(-20, 21):
			var x: float = centre.x + float(x_index) * step
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), grid_colour, 1.0)
		for y_index: int in range(-20, 21):
			var y: float = centre.y + float(y_index) * step
			draw_line(Vector2(0.0, y), Vector2(size.x, y), grid_colour, 1.0)

	func _draw_connections(nodes: Array) -> void:
		var statuses: Dictionary = web.get("statuses", {}) as Dictionary
		var children_by_parent: Dictionary = _direct_children_by_parent(nodes)
		var split_parent_ids: Dictionary = {}

		# Draw intentional fork shapes first. Specialist gateways and elite rejoin
		# nodes should read as one trunk that splits into three branches, rather than
		# three unrelated lines leaving the same node.
		for parent_variant: Variant in children_by_parent.keys():
			var parent_id: String = String(parent_variant)
			var parent_node: Dictionary = _canvas_node_by_id(nodes, parent_id)
			if parent_node.is_empty() or not node_positions.has(parent_id):
				continue
			var visible_children: Array = _visible_split_children_for_parent(children_by_parent[parent_variant] as Array, nodes)
			if _should_draw_split_outgoing(parent_node, visible_children):
				split_parent_ids[parent_id] = visible_children.duplicate()
				_draw_split_outgoing(parent_id, visible_children, parent_node, statuses, nodes)

		for node_variant: Variant in nodes:
			if not (node_variant is Dictionary):
				continue
			var node: Dictionary = node_variant as Dictionary
			var node_id: String = String(node.get("id", ""))
			if not node_positions.has(node_id):
				continue

			# Rejoin nodes merge branch endings into one trunk before entering the node.
			# This makes Elite / Chosen junctions read as: complete any one branch ->
			# merge -> buy the rejoin node -> continue from that node. It also avoids the
			# visual impression that later paths can bypass the Elite node.
			if _is_rejoin_node(node):
				_draw_merge_incoming(node, statuses)
				continue

			var requirements: Array = node.get("requires", []) as Array
			for req_variant: Variant in requirements:
				var req_id: String = String(req_variant)
				if split_parent_ids.has(req_id) and (split_parent_ids[req_id] as Array).has(node_id):
					continue
				_draw_connection_between(req_id, node_id, node, statuses, false)

			var any_requirements: Array = node.get("requires_any", []) as Array
			for req_variant: Variant in any_requirements:
				var req_id: String = String(req_variant)
				_draw_connection_between(req_id, node_id, node, statuses, true)

	func _direct_children_by_parent(nodes: Array) -> Dictionary:
		var result: Dictionary = {}
		for node_variant: Variant in nodes:
			if not (node_variant is Dictionary):
				continue
			var node: Dictionary = node_variant as Dictionary
			var node_id: String = String(node.get("id", ""))
			if node_id == "":
				continue
			var requirements: Array = node.get("requires", []) as Array
			for req_variant: Variant in requirements:
				var req_id: String = String(req_variant)
				if req_id == "":
					continue
				var req_node: Dictionary = _canvas_node_by_id(nodes, req_id)
				if _is_terminal_node(req_node):
					continue
				if not result.has(req_id):
					result[req_id] = []
				(result[req_id] as Array).append(node_id)
		return result

	func _canvas_node_by_id(nodes: Array, node_id: String) -> Dictionary:
		for node_variant: Variant in nodes:
			if not (node_variant is Dictionary):
				continue
			var node: Dictionary = node_variant as Dictionary
			if String(node.get("id", "")) == node_id:
				return node
		return {}

	func _is_rejoin_node(node: Dictionary) -> bool:
		if node.is_empty():
			return false
		var any_requirements: Array = node.get("requires_any", []) as Array
		return bool(node.get("rejoin", false)) and not any_requirements.is_empty()

	func _is_terminal_node(node: Dictionary) -> bool:
		# Final capstones are hard visual endpoints. They may have incoming merge
		# lines, but they should never act as a source for any outgoing line.
		if node.is_empty():
			return false
		return bool(node.get("capstone", false)) or bool(node.get("chosen_capstone", false))

	func _visible_split_children_for_parent(child_ids: Array, nodes: Array) -> Array:
		var output: Array = []
		for child_variant: Variant in child_ids:
			var child_id: String = String(child_variant)
			var child_node: Dictionary = _canvas_node_by_id(nodes, child_id)
			if child_node.is_empty():
				continue
			# Rejoin nodes also list the gateway/elite as a hard prerequisite in data,
			# but visually they should be reached through the branch merge, not through a
			# direct shortcut line from the gateway.
			if _is_rejoin_node(child_node):
				continue
			output.append(child_id)
		return output

	func _should_draw_split_outgoing(parent_node: Dictionary, visible_child_ids: Array) -> bool:
		if visible_child_ids.size() < 2:
			return false
		# Final capstones must be visual end-points. Even if future data accidentally
		# gives them children, do not draw a trunk continuing beyond the final node.
		if bool(parent_node.get("capstone", false)) or bool(parent_node.get("chosen_capstone", false)):
			return false
		if bool(parent_node.get("specialisation", false)):
			return true
		if bool(parent_node.get("rejoin", false)):
			return true
		return false

	func _draw_split_outgoing(parent_id: String, child_ids: Array, parent_node: Dictionary, statuses: Dictionary, nodes: Array) -> void:
		if child_ids.size() < 2 or not node_positions.has(parent_id):
			return
		var from_pos: Vector2 = node_positions[parent_id] as Vector2
		var child_positions: Array[Vector2] = []
		for child_variant: Variant in child_ids:
			var child_id: String = String(child_variant)
			if node_positions.has(child_id):
				child_positions.append(node_positions[child_id] as Vector2)
		if child_positions.size() < 2:
			return
		var average_child: Vector2 = Vector2.ZERO
		for child_pos: Vector2 in child_positions:
			average_child += child_pos
		average_child /= float(child_positions.size())
		var direction: Vector2 = average_child - from_pos
		if direction.length() < 0.001:
			direction = _cluster_forward_direction(String(parent_node.get("cluster", "core")))
		else:
			direction = direction.normalized()
		var junction: Vector2 = from_pos + direction * _junction_trunk_length()
		var trunk_style: Dictionary = _parent_trunk_style(parent_id, parent_node, statuses)
		var trunk_colour: Color = trunk_style.get("colour", Color(0.38, 0.45, 0.42, 0.70)) as Color
		var trunk_width: float = float(trunk_style.get("width", 2.5))
		var from_edge: Vector2 = _node_edge_toward(parent_node, from_pos, junction)
		draw_line(from_edge, junction, trunk_colour, trunk_width, true)
		for child_variant: Variant in child_ids:
			var child_id: String = String(child_variant)
			var child_node: Dictionary = _canvas_node_by_id(nodes, child_id)
			if child_node.is_empty() or not node_positions.has(child_id):
				continue
			var style: Dictionary = _connection_style(parent_id, child_id, child_node, statuses, false)
			var line_colour: Color = style.get("colour", trunk_colour) as Color
			var line_width: float = float(style.get("width", trunk_width))
			var child_pos: Vector2 = node_positions[child_id] as Vector2
			var child_edge: Vector2 = _node_edge_toward(child_node, child_pos, junction)
			draw_line(junction, child_edge, line_colour, maxf(1.5, line_width - 0.25), true)
		draw_circle(junction, maxf(3.0, 5.0 * sqrt(zoom_level)), trunk_colour.lightened(0.08))

	func _draw_merge_incoming(node: Dictionary, statuses: Dictionary) -> void:
		var node_id: String = String(node.get("id", ""))
		if node_id == "" or not node_positions.has(node_id):
			return
		var any_requirements: Array = node.get("requires_any", []) as Array
		var input_positions: Array[Vector2] = []
		for req_variant: Variant in any_requirements:
			var req_id: String = String(req_variant)
			if node_positions.has(req_id):
				input_positions.append(node_positions[req_id] as Vector2)
		if input_positions.is_empty():
			return
		var to_pos: Vector2 = node_positions[node_id] as Vector2
		var average_input: Vector2 = Vector2.ZERO
		for input_pos: Vector2 in input_positions:
			average_input += input_pos
		average_input /= float(input_positions.size())
		var direction: Vector2 = to_pos - average_input
		if direction.length() < 0.001:
			direction = _cluster_forward_direction(String(node.get("cluster", "core")))
		else:
			direction = direction.normalized()
		var junction: Vector2 = to_pos - direction * _junction_trunk_length()
		var trunk_style: Dictionary = _connection_style(String(any_requirements[0]), node_id, node, statuses, true)
		var trunk_colour: Color = trunk_style.get("colour", Color(0.38, 0.45, 0.42, 0.70)) as Color
		var trunk_width: float = float(trunk_style.get("width", 3.0))
		var all_nodes: Array = web.get("nodes", []) as Array
		for req_variant: Variant in any_requirements:
			var req_id: String = String(req_variant)
			if not node_positions.has(req_id):
				continue
			var req_node: Dictionary = _canvas_node_by_id(all_nodes, req_id)
			var style: Dictionary = _connection_style(req_id, node_id, node, statuses, true)
			var line_colour: Color = style.get("colour", trunk_colour) as Color
			var line_width: float = float(style.get("width", trunk_width))
			var req_pos: Vector2 = node_positions[req_id] as Vector2
			var req_edge: Vector2 = req_pos
			if not req_node.is_empty():
				req_edge = _node_edge_toward(req_node, req_pos, junction)
			draw_line(req_edge, junction, line_colour, maxf(1.5, line_width - 0.25), true)
		var to_edge: Vector2 = _node_edge_toward(node, to_pos, junction)
		draw_line(junction, to_edge, trunk_colour, trunk_width + 0.5, true)
		if _is_terminal_node(node):
			_draw_terminal_line_blocker(to_edge, to_pos - junction, trunk_width + 0.5)
			_draw_terminal_end_cap(to_edge, to_pos - junction, trunk_colour, trunk_width + 0.5)
		draw_circle(junction, maxf(3.0, 5.0 * sqrt(zoom_level)), trunk_colour.lightened(0.08))

	func _draw_terminal_line_blocker(edge_pos: Vector2, incoming_direction: Vector2, line_width: float) -> void:
		# Final capstones sit on the main vertical/horizontal axes. If the background
		# grid or any accidental future link continues past them, it reads as a
		# connection line going off-screen. Mask the far side of the terminal node so
		# the branch visibly ends there. Nodes are drawn afterwards, so this mask does
		# not damage the capstone itself.
		if incoming_direction.length() < 0.001:
			return
		var dir: Vector2 = incoming_direction.normalized()
		var start_pos: Vector2 = edge_pos + dir * maxf(3.0, line_width)
		var end_pos: Vector2 = edge_pos + dir * (maxf(size.x, size.y) + 240.0)
		var mask_colour: Color = Color(0.012, 0.020, 0.022, 1.0)
		draw_line(start_pos, end_pos, mask_colour, maxf(18.0, line_width + 12.0), true)

	func _draw_terminal_end_cap(edge_pos: Vector2, incoming_direction: Vector2, line_colour: Color, line_width: float) -> void:
		# A short perpendicular stopper makes final capstones read as true endpoints
		# instead of a path that continues visually beyond the node.
		if incoming_direction.length() < 0.001:
			return
		var dir: Vector2 = incoming_direction.normalized()
		var normal: Vector2 = Vector2(-dir.y, dir.x)
		var half_len: float = clampf(13.0 * sqrt(zoom_level), 7.0, 18.0)
		draw_line(edge_pos - normal * half_len, edge_pos + normal * half_len, line_colour.lightened(0.15), maxf(2.0, line_width), true)

	func _connection_style(req_id: String, node_id: String, node: Dictionary, statuses: Dictionary, is_rejoin_line: bool) -> Dictionary:
		var target_status: Dictionary = {}
		if statuses.has(node_id):
			target_status = statuses[node_id] as Dictionary
		var source_status: Dictionary = {}
		if statuses.has(req_id):
			source_status = statuses[req_id] as Dictionary
		var target_purchased: bool = bool(target_status.get("purchased", false))
		var target_can_purchase: bool = bool(target_status.get("can_purchase", false))
		var target_requirements_met: bool = bool(target_status.get("requirements_met", false))
		var source_purchased: bool = bool(source_status.get("purchased", false))

		# Connection colours are intentionally calmer than node colours. The central
		# training hub should read as one neutral household web; strong doctrine colours
		# only begin once a line is actually entering Eagle / Jaguar / Otomi / Coyote
		# territory. This prevents the start node from appearing to split into random
		# purple/white routes.
		var base_colour: Color = _connection_base_colour(req_id, node)
		var line_colour: Color = Color(0.27, 0.34, 0.33, 0.50)
		var line_width: float = 2.0
		if target_purchased:
			line_colour = base_colour.lightened(0.25)
			line_width = 4.0
		elif target_can_purchase or source_purchased:
			line_colour = base_colour
			line_width = 3.0
		elif target_requirements_met:
			line_colour = _neutral_connection_colour(0.70)
		if is_rejoin_line:
			line_width += 0.5
			if not source_purchased and not target_purchased and not target_can_purchase:
				line_colour.a = 0.42
		return {"colour": line_colour, "width": line_width}

	func _connection_base_colour(req_id: String, target_node: Dictionary) -> Color:
		var target_cluster: String = String(target_node.get("cluster", "core"))
		# Every line leaving the founding node is neutral, even if the target node is
		# a veteran/support-flavoured early training node. Doctrine colour should not
		# start until after the first neutral training step.
		if req_id == "household_muster":
			return _neutral_connection_colour()
		# Early non-doctrine support clusters should stay visually tied to the central
		# household web rather than drawing attention with a separate purple route.
		if target_cluster == "core" or target_cluster == "veteran" or target_cluster == "supply":
			return _neutral_connection_colour()
		return _cluster_colour(target_cluster)

	func _neutral_connection_colour(alpha: float = 0.88) -> Color:
		return Color(0.74, 0.79, 0.73, alpha)

	func _parent_trunk_style(parent_id: String, parent_node: Dictionary, statuses: Dictionary) -> Dictionary:
		var parent_status: Dictionary = {}
		if statuses.has(parent_id):
			parent_status = statuses[parent_id] as Dictionary
		var base_colour: Color = _cluster_colour(String(parent_node.get("cluster", "core")))
		if parent_id == "household_muster" or String(parent_node.get("cluster", "core")) == "core" or String(parent_node.get("cluster", "core")) == "veteran" or String(parent_node.get("cluster", "core")) == "supply":
			base_colour = _neutral_connection_colour()
		if bool(parent_status.get("purchased", false)):
			return {"colour": base_colour.lightened(0.12), "width": 3.5}
		if bool(parent_status.get("can_purchase", false)):
			return {"colour": base_colour.darkened(0.08), "width": 3.0}
		return {"colour": Color(0.27, 0.34, 0.33, 0.50), "width": 2.0}

	func _junction_trunk_length() -> float:
		return clampf(64.0 * zoom_level, 34.0, 96.0)

	func _cluster_forward_direction(cluster_id: String) -> Vector2:
		match cluster_id:
			"eagle":
				return Vector2(0.0, -1.0)
			"jaguar":
				return Vector2(1.0, 0.0)
			"otomi":
				return Vector2(-1.0, 0.0)
			"coyote":
				return Vector2(0.0, 1.0)
		return Vector2(1.0, 0.0)

	func _draw_connection_between(req_id: String, node_id: String, node: Dictionary, statuses: Dictionary, is_rejoin_line: bool) -> void:
		if not node_positions.has(req_id) or not node_positions.has(node_id):
			return
		var all_nodes_for_terminal_check: Array = web.get("nodes", []) as Array
		var terminal_source: Dictionary = _canvas_node_by_id(all_nodes_for_terminal_check, req_id)
		if _is_terminal_node(terminal_source):
			return
		var raw_from_pos: Vector2 = node_positions[req_id] as Vector2
		var raw_to_pos: Vector2 = node_positions[node_id] as Vector2
		var all_nodes: Array = web.get("nodes", []) as Array
		var req_node: Dictionary = _canvas_node_by_id(all_nodes, req_id)
		var from_pos: Vector2 = raw_from_pos
		if not req_node.is_empty():
			from_pos = _node_edge_toward(req_node, raw_from_pos, raw_to_pos)
		var to_pos: Vector2 = _node_edge_toward(node, raw_to_pos, raw_from_pos)
		var style: Dictionary = _connection_style(req_id, node_id, node, statuses, is_rejoin_line)
		var line_colour: Color = style.get("colour", Color(0.27, 0.34, 0.33, 0.50)) as Color
		var line_width: float = float(style.get("width", 2.0))
		_draw_elbow_connection(from_pos, to_pos, line_colour, line_width, is_rejoin_line)

	func _node_edge_toward(node: Dictionary, centre_pos: Vector2, toward_pos: Vector2) -> Vector2:
		var direction: Vector2 = toward_pos - centre_pos
		if direction.length() < 0.001:
			return centre_pos
		return centre_pos + direction.normalized() * (_radius_for_node(node) + 3.0)

	func _draw_elbow_connection(from_pos: Vector2, to_pos: Vector2, line_colour: Color, line_width: float, emphasise_rejoin: bool) -> void:
		# Symmetric routed links: straight when aligned, otherwise a two-bend route
		# on the dominant axis. This avoids long random diagonals crossing the web.
		if absf(from_pos.x - to_pos.x) < 8.0 or absf(from_pos.y - to_pos.y) < 8.0:
			draw_line(from_pos, to_pos, line_colour, line_width, true)
			return
		if absf(from_pos.x - to_pos.x) >= absf(from_pos.y - to_pos.y):
			var mid_x: float = (from_pos.x + to_pos.x) * 0.5
			var p1: Vector2 = Vector2(mid_x, from_pos.y)
			var p2: Vector2 = Vector2(mid_x, to_pos.y)
			draw_line(from_pos, p1, line_colour, line_width, true)
			draw_line(p1, p2, line_colour.darkened(0.08), maxf(1.0, line_width - (0.0 if emphasise_rejoin else 0.5)), true)
			draw_line(p2, to_pos, line_colour, line_width, true)
		else:
			var mid_y: float = (from_pos.y + to_pos.y) * 0.5
			var p1: Vector2 = Vector2(from_pos.x, mid_y)
			var p2: Vector2 = Vector2(to_pos.x, mid_y)
			draw_line(from_pos, p1, line_colour, line_width, true)
			draw_line(p1, p2, line_colour.darkened(0.08), maxf(1.0, line_width - (0.0 if emphasise_rejoin else 0.5)), true)
			draw_line(p2, to_pos, line_colour, line_width, true)

	func _draw_nodes(nodes: Array) -> void:
		var statuses: Dictionary = web.get("statuses", {}) as Dictionary
		for node_variant: Variant in nodes:
			if not (node_variant is Dictionary):
				continue
			var node: Dictionary = node_variant as Dictionary
			var node_id: String = String(node.get("id", ""))
			if not node_positions.has(node_id):
				continue
			var pos: Vector2 = node_positions[node_id] as Vector2
			var cluster_id: String = String(node.get("cluster", "core"))
			var status: Dictionary = {}
			if statuses.has(node_id):
				status = statuses[node_id] as Dictionary
			var purchased: bool = bool(status.get("purchased", false))
			var can_purchase: bool = bool(status.get("can_purchase", false))
			var requirements_met: bool = bool(status.get("requirements_met", false))
			var is_keystone: bool = bool(node.get("specialisation", false))
			var is_capstone: bool = bool(node.get("capstone", false))
			var radius: float = _radius_for_node(node)
			var base_colour: Color = _cluster_colour(cluster_id)
			var fill_colour: Color = Color(0.09, 0.11, 0.105, 0.96)
			var ring_colour: Color = Color(0.38, 0.40, 0.37, 0.78)
			if purchased:
				fill_colour = base_colour.darkened(0.35)
				ring_colour = base_colour.lightened(0.25)
			elif can_purchase:
				fill_colour = Color(0.10, 0.15, 0.14, 0.98)
				ring_colour = base_colour
			elif requirements_met:
				fill_colour = Color(0.07, 0.085, 0.08, 0.92)
				ring_colour = Color(0.62, 0.58, 0.46, 0.80)
			draw_circle(pos, radius + 4.0, Color(0.0, 0.0, 0.0, 0.55))
			draw_circle(pos, radius, fill_colour)
			draw_arc(pos, radius, 0.0, TAU, 40, ring_colour, 3.0, true)
			if is_keystone:
				draw_arc(pos, radius + 6.0, 0.0, TAU, 40, ring_colour, 2.0, true)
			if is_capstone:
				draw_arc(pos, radius + 10.0, 0.0, TAU, 48, Color(1.0, 0.72, 0.34, 0.92), 3.0, true)
			if node_id == hovered_node_id and node_id != selected_node_id:
				draw_arc(pos, radius + 8.0, 0.0, TAU, 48, Color(0.78, 0.96, 0.90, 0.82), 2.0, true)
			if node_id == selected_node_id:
				draw_arc(pos, radius + 10.0, 0.0, TAU, 48, Color(1.0, 0.92, 0.50, 0.95), 3.0, true)
			_draw_node_symbol(node, pos, radius, purchased, can_purchase, requirements_met)
			_draw_node_label(node, pos, radius, purchased, can_purchase)

	func _draw_node_symbol(node: Dictionary, pos: Vector2, radius: float, purchased: bool, can_purchase: bool, requirements_met: bool) -> void:
		var font: Font = get_theme_default_font()
		if font == null:
			return
		var symbol: String = _node_symbol(node)
		if symbol == "":
			return
		var colour: Color = Color(0.70, 0.73, 0.68, 0.72)
		if purchased:
			colour = Color(1.0, 0.92, 0.62, 1.0)
		elif can_purchase:
			colour = Color(0.86, 1.0, 0.91, 1.0)
		elif requirements_met:
			colour = Color(0.86, 0.76, 0.52, 0.88)
		var font_size: int = 12
		if bool(node.get("specialisation", false)):
			font_size = 13
		if bool(node.get("capstone", false)):
			font_size = 14
		font_size = clampi(int(round(float(font_size) * sqrt(zoom_level))), 9, 16)
		var width: float = radius * 2.2
		draw_string(font, pos + Vector2(-width * 0.5, float(font_size) * 0.42), symbol, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, colour)

	func _node_symbol(node: Dictionary) -> String:
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
		var effect_symbol: String = _primary_effect_symbol(effects)
		if effect_symbol != "":
			return effect_symbol
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

	func _primary_effect_symbol(effects: Dictionary) -> String:
		if effects.is_empty():
			return ""
		var priority: Array[String] = [
			"capture_chance_add",
			"offence_add",
			"defence_add",
			"loot_value_add",
			"prestige_pending_add",
			"provisioning_discount_add",
			"xp_gain_add",
			"death_chance_add",
			"casualty_chance_add",
			"injury_recovery_add",
			"weapon_efficiency_add",
			"weapon_loss_add",
			"ready_warriors_add",
			"enemy_defence_add"
		]
		for effect_id: String in priority:
			if effects.has(effect_id):
				match effect_id:
					"capture_chance_add":
						return "CAP"
					"offence_add":
						return "ATK"
					"defence_add":
						return "DEF"
					"loot_value_add":
						return "LOOT"
					"prestige_pending_add":
						return "PRE"
					"provisioning_discount_add":
						return "SUP"
					"xp_gain_add":
						return "XP"
					"death_chance_add", "casualty_chance_add":
						return "SURV"
					"injury_recovery_add":
						return "REC"
					"weapon_efficiency_add", "weapon_loss_add":
						return "WPN"
					"ready_warriors_add":
						return "RDY"
					"enemy_defence_add":
						return "BRK"
		return "•"

	func _draw_node_label(node: Dictionary, pos: Vector2, radius: float, purchased: bool, can_purchase: bool) -> void:
		var font: Font = get_theme_default_font()
		var label: String = String(node.get("name", "Node"))
		if label.length() > 18:
			label = label.substr(0, 16) + "…"
		var colour: Color = Color(0.75, 0.79, 0.73, 0.90)
		if purchased:
			colour = Color(0.94, 0.91, 0.72, 1.0)
		elif can_purchase:
			colour = Color(0.82, 0.95, 0.88, 1.0)
		if font != null:
			draw_string(font, pos + Vector2(-58.0, radius + 17.0), label, HORIZONTAL_ALIGNMENT_CENTER, 116.0, 12, colour)

	func _draw_help_text() -> void:
		var font: Font = get_theme_default_font()
		if font == null:
			return
		var text_colour: Color = Color(0.72, 0.80, 0.76, 0.86)
		draw_string(font, Vector2(18.0, 34.0), "Drag to pan. Wheel/buttons zoom. Hover for details; click to pin. One specialism per warband.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 36.0, 14, text_colour)

	func _effective_grid_scale() -> float:
		return grid_scale * zoom_level

	func _radius_for_node(node: Dictionary) -> float:
		var base: float = node_radius
		if bool(node.get("specialisation", false)):
			base = keystone_radius
		if bool(node.get("capstone", false)):
			base = capstone_radius
		return clampf(base * sqrt(zoom_level), 14.0, 40.0)

	func zoom_by_factor(factor: float) -> void:
		_zoom_at_position(factor, size * 0.5)

	func reset_zoom() -> void:
		zoom_level = 0.74
		pan_offset = _clamped_pan(pan_offset)
		zoom_changed.emit(zoom_level)
		pan_changed.emit(pan_offset)
		queue_redraw()

	func _zoom_at_position(factor: float, mouse_pos: Vector2) -> void:
		var old_zoom: float = zoom_level
		var new_zoom: float = clampf(zoom_level * factor, min_zoom, max_zoom)
		if is_equal_approx(old_zoom, new_zoom):
			return
		var old_scale: float = grid_scale * old_zoom
		var new_scale: float = grid_scale * new_zoom
		var centre: Vector2 = size * 0.5
		var world_under_mouse: Vector2 = (mouse_pos - centre - pan_offset) / old_scale
		zoom_level = new_zoom
		pan_offset = mouse_pos - centre - world_under_mouse * new_scale
		pan_offset = _clamped_pan(pan_offset)
		zoom_changed.emit(zoom_level)
		pan_changed.emit(pan_offset)
		queue_redraw()

	func _clamped_pan(raw_pan: Vector2) -> Vector2:
		if size.x <= 8.0 or size.y <= 8.0:
			return Vector2.ZERO
		var nodes: Array = web.get("nodes", []) as Array
		if nodes.is_empty():
			return Vector2.ZERO
		var min_world: Vector2 = Vector2(999999.0, 999999.0)
		var max_world: Vector2 = Vector2(-999999.0, -999999.0)
		for node_variant: Variant in nodes:
			if not (node_variant is Dictionary):
				continue
			var node: Dictionary = node_variant as Dictionary
			var world: Vector2 = Vector2(float(node.get("x", 0.0)) * _effective_grid_scale(), -float(node.get("y", 0.0)) * _effective_grid_scale())
			min_world.x = minf(min_world.x, world.x)
			min_world.y = minf(min_world.y, world.y)
			max_world.x = maxf(max_world.x, world.x)
			max_world.y = maxf(max_world.y, world.y)

		# Expand the content bounds so node labels and capstone rings do not sit hard
		# against the clamp edge. This prevents infinite scrolling while still letting
		# the player inspect the outer specialist branches.
		var content_pad: float = 160.0 * sqrt(zoom_level) + 40.0
		min_world -= Vector2(content_pad, content_pad)
		max_world += Vector2(content_pad, content_pad)

		var result: Vector2 = raw_pan
		var viewport_centre: Vector2 = size * 0.5
		var min_x: float = edge_padding - viewport_centre.x - min_world.x
		var max_x: float = size.x - edge_padding - viewport_centre.x - max_world.x
		if min_x < max_x:
			result.x = -(min_world.x + max_world.x) * 0.5
		else:
			result.x = clampf(raw_pan.x, max_x, min_x)

		var min_y: float = edge_padding - viewport_centre.y - min_world.y
		var max_y: float = size.y - edge_padding - viewport_centre.y - max_world.y
		if min_y < max_y:
			result.y = -(min_world.y + max_world.y) * 0.5
		else:
			result.y = clampf(raw_pan.y, max_y, min_y)
		return result

	func _screen_position_for_node(node: Dictionary) -> Vector2:
		var centre: Vector2 = size * 0.5 + pan_offset
		var node_x: float = float(node.get("x", 0.0))
		var node_y: float = float(node.get("y", 0.0))
		return centre + Vector2(node_x * _effective_grid_scale(), -node_y * _effective_grid_scale())

	func _node_id_at_position(position: Vector2) -> String:
		var nodes: Array = web.get("nodes", []) as Array
		var best_id: String = ""
		var best_distance: float = 999999.0
		for node_variant: Variant in nodes:
			if not (node_variant is Dictionary):
				continue
			var node: Dictionary = node_variant as Dictionary
			var node_id: String = String(node.get("id", ""))
			var pos: Vector2 = _screen_position_for_node(node)
			var radius: float = _radius_for_node(node)
			var distance: float = position.distance_to(pos)
			if distance <= radius + 8.0 and distance < best_distance:
				best_distance = distance
				best_id = node_id
		return best_id

	func _cluster_colour(cluster_id: String) -> Color:
		match cluster_id:
			"core":
				return Color(0.70, 0.78, 0.74, 0.96)
			"eagle":
				return Color(0.90, 0.78, 0.35, 0.96)
			"jaguar":
				return Color(0.88, 0.42, 0.28, 0.96)
			"otomi":
				return Color(0.37, 0.76, 0.86, 0.96)
			"coyote":
				return Color(0.58, 0.82, 0.42, 0.96)
			"veteran":
				return Color(0.72, 0.77, 0.72, 0.96)
			"supply":
				return Color(0.68, 0.80, 0.73, 0.96)
		return Color(0.50, 0.82, 0.74, 0.96)

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
		_selected_shrine_panel_id = ""
	if location_id != "warriors":
		_selected_warband_skill_web_id = ""
	super.show_location(location_id)

func show_focus(location_id: String, focus_id: String) -> void:
	if location_id == "shrines":
		# The old Offerings tab has been removed; rituals now live inside each
		# god's Ritual Tiers panel. Redirect any stale/manual reference safely.
		if focus_id == "offerings":
			focus_id = "overview"
		_selected_shrine_panel_id = ""
	if location_id == "warriors" and focus_id != "warbands":
		_selected_warband_skill_web_id = ""
	if location_id == "palace" and focus_id != "divine_seat":
		_selected_palace_route_id = ""
		_pending_palace_dedication_confirm_id = ""
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
	var suffix: String = "th"
	var mod_100: int = value % 100
	if mod_100 < 11 or mod_100 > 13:
		match value % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return str(value) + suffix

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

func _show_palace_content() -> void:
	_set_content_root_layout(true)
	if content_text:
		content_text.visible = false
	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return
	dynamic_view_host.visible = true
	match _current_focus_id():
		"prestige":
			_build_palace_prestige_main_view()
		"divine_seat":
			_build_palace_divine_seat_main_view()
		"authority":
			_build_palace_authority_main_view()
		"ruler_demands":
			_build_palace_ruler_demands_main_view()
		_:
			_build_palace_overview_main_view()

func _build_palace_placeholder_main_view(title_text: String, body_text: String) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.030, 0.024, 0.90), Color(0.70, 0.58, 0.34, 0.55), 16))
	dynamic_view_host.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)
	var title_label: Label = _palace_label(title_text, 34, Color(0.96, 0.86, 0.58, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title_label)
	var body: RichTextLabel = _palace_wrapped_label(body_text, 20, Color(0.80, 0.82, 0.76, 1.0))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(body)


func _build_palace_ruler_demands_main_view() -> void:
	var state: Node = _state()
	var demands: Dictionary = {}
	if state != null and state.has_method("get_palace_ruler_demands_summary"):
		demands = state.call("get_palace_ruler_demands_summary") as Dictionary
	elif state != null and state.has_method("get_palace_summary"):
		var summary: Dictionary = state.call("get_palace_summary") as Dictionary
		demands = summary.get("ruler_demands", {}) as Dictionary
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.026, 0.020, 0.92), Color(0.78, 0.62, 0.34, 0.62), 18))
	dynamic_view_host.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title_label: Label = _palace_label("COURT NEEDS", 33, Color(1.0, 0.86, 0.50, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title_label)
	if demands.is_empty():
		root.add_child(_palace_wrapped_label("Court-needs backend data is not connected yet.", 18, Color(0.86, 0.80, 0.68, 1.0)))
		return
	root.add_child(_palace_wrapped_label(String(demands.get("title", "Current Court Needs")), 22, Color(0.96, 0.78, 0.46, 1.0)))
	root.add_child(_palace_wrapped_label(String(demands.get("flavour", "The court currently needs these goods. Donating them creates public prestige.")), 16, Color(0.82, 0.84, 0.76, 1.0)))
	root.add_child(_palace_wrapped_label(String(demands.get("headline", "Court needs donation prototype active.")), 15, Color(0.74, 0.94, 0.72, 1.0)))

	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_theme_constant_override("separation", 10)
	root.add_child(status_row)
	_add_palace_summary_card(status_row, "Cycle", String(demands.get("veintena_band", "Prototype")), String(demands.get("cycle_window", "Controlled test need, not random politics.")), Color(0.88, 0.70, 0.40, 1.0))
	_add_palace_summary_card(status_row, "Deadline", String(demands.get("urgency_label", "Time remains")), str(int(demands.get("veintenas_remaining", 0))) + " Veintena" + ("s" if int(demands.get("veintenas_remaining", 0)) != 1 else "") + " remaining including the current turn.", Color(0.92, 0.64, 0.42, 1.0))
	_add_palace_summary_card(status_row, "Donated", String(demands.get("donation_label", "0 / 3 needs donated to")), "Donation is optional and can be partial; prestige comes from value donated.", Color(0.72, 0.92, 0.70, 1.0))
	_add_palace_summary_card(status_row, "Prestige", "+" + _format_religion_amount(float(demands.get("total_donated_prestige", 0.0))) + " this cycle", "Player Prestige: " + _format_religion_amount(float(demands.get("player_prestige", 0.0))) + ". Prestige is score only, never spent.", Color(0.96, 0.80, 0.52, 1.0))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var rows: Array = demands.get("rows", []) as Array
	for row_variant: Variant in rows:
		if row_variant is Dictionary:
			_add_palace_ruler_demand_row_card(list, row_variant as Dictionary)
	_add_palace_ruler_demand_cycle_archive_panel(list, demands.get("cycle_archive", []) as Array)
	var note_panel: PanelContainer = PanelContainer.new()
	note_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.020, 0.018, 0.88), Color(0.42, 0.42, 0.34, 0.50), 10))
	list.add_child(note_panel)
	var note_margin: MarginContainer = MarginContainer.new()
	note_margin.add_theme_constant_override("margin_left", 12)
	note_margin.add_theme_constant_override("margin_top", 8)
	note_margin.add_theme_constant_override("margin_right", 12)
	note_margin.add_theme_constant_override("margin_bottom", 8)
	note_panel.add_child(note_margin)
	note_margin.add_child(_palace_wrapped_label(String(demands.get("mechanics_note", "Donations create prestige by base value. Prestige is score only.")), 14, Color(0.74, 0.76, 0.68, 1.0)))

func _add_palace_ruler_demand_cycle_archive_panel(parent: VBoxContainer, archive_rows: Array) -> void:
	if archive_rows.is_empty():
		return
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.026, 0.026, 0.022, 0.92), Color(0.66, 0.55, 0.34, 0.58), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	margin.add_child(stack)
	stack.add_child(_palace_label("Court Need Donation Record", 20, Color(0.96, 0.78, 0.46, 1.0)))
	stack.add_child(_palace_wrapped_label("A compact record of visible court-need cycles and the prestige generated by donations.", 14, Color(0.76, 0.80, 0.70, 1.0)))
	for cycle_variant: Variant in archive_rows:
		if not (cycle_variant is Dictionary):
			continue
		var cycle: Dictionary = cycle_variant as Dictionary
		var line_colour: Color = Color(0.74, 0.76, 0.68, 1.0)
		if bool(cycle.get("is_current", false)):
			line_colour = Color(0.92, 0.86, 0.56, 1.0)
		var prefix: String = "Current — " if bool(cycle.get("is_current", false)) else "Record — "
		var line: String = prefix + String(cycle.get("title", "Court Need Cycle")) + " (" + String(cycle.get("cycle_window", cycle.get("veintena_band", "Prototype"))) + "): " + str(int(cycle.get("donation_count", 0))) + " donations; +" + _format_religion_amount(float(cycle.get("donated_prestige", 0.0))) + " Prestige."
		stack.add_child(_palace_wrapped_label(line, 14, line_colour))

func _add_palace_ruler_demand_row_card(parent: VBoxContainer, row: Dictionary) -> void:
	var can_donate: bool = bool(row.get("can_donate", false))
	var donated: bool = bool(row.get("delivered", false))
	var border: Color = Color(0.54, 0.90, 0.58, 0.80) if can_donate else Color(1.0, 0.58, 0.34, 0.82)
	if donated:
		border = Color(0.96, 0.78, 0.42, 0.90)
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.022, 0.024, 0.022, 0.92), border, 11))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 9)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	var top: HBoxContainer = HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 8)
	stack.add_child(top)
	var title: Label = _palace_label(String(row.get("slot_name", "Court need")) + " — " + String(row.get("resource_name", "Good")), 19, border.lightened(0.20))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var status: Label = _palace_label(String(row.get("status", "Unknown")), 15, border.lightened(0.10))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.custom_minimum_size = Vector2(150, 0)
	top.add_child(status)
	stack.add_child(_palace_wrapped_label(String(row.get("note", "Court-facing need.")), 14, Color(0.82, 0.84, 0.76, 1.0)))
	var need_marker: float = float(row.get("needed_marker", row.get("requested", 0.0)))
	var stored: float = float(row.get("stored", 0.0))
	var free_value: float = float(row.get("free_after_reserves", 0.0))
	var base_value: float = float(row.get("base_value", 1.0))
	var donated_amount: float = float(row.get("donated_amount", row.get("delivered_amount", 0.0)))
	var donated_prestige: float = float(row.get("donated_prestige", 0.0))
	stack.add_child(_palace_wrapped_label("Visible need marker: " + _format_religion_amount(need_marker) + " | Stored: " + _format_religion_amount(stored) + " | Free after reserves: " + _format_religion_amount(free_value), 14, Color(0.76, 0.82, 0.74, 1.0)))
	stack.add_child(_palace_wrapped_label("Prestige formula: donated amount × base value. Base value of " + String(row.get("resource_name", "Good")) + ": " + _format_religion_amount(base_value) + ". Need marker value: +" + _format_religion_amount(float(row.get("prestige_for_need_marker", 0.0))) + " Prestige.", 13, Color(0.84, 0.82, 0.66, 1.0)))
	if donated_amount > 0.001:
		stack.add_child(_palace_wrapped_label("Donated this cycle: " + _format_religion_amount(donated_amount) + " " + String(row.get("resource_name", "Good")) + " → +" + _format_religion_amount(donated_prestige) + " Prestige.", 13, Color(0.96, 0.82, 0.48, 1.0)))
	elif can_donate:
		stack.add_child(_palace_wrapped_label("You may donate any free amount of this needed good. More value donated creates more prestige.", 13, Color(0.66, 0.92, 0.68, 1.0)))
	else:
		stack.add_child(_palace_wrapped_label("No free stock is available for this needed good after reserves.", 13, Color(1.0, 0.72, 0.45, 1.0)))

	var max_donation: float = maxf(0.0, float(row.get("max_donation", free_value)))
	var starting_amount: float = 0.0
	if max_donation > 0.001:
		starting_amount = minf(maxf(1.0, need_marker), max_donation)

	var donate_box: VBoxContainer = VBoxContainer.new()
	donate_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	donate_box.add_theme_constant_override("separation", 4)
	stack.add_child(donate_box)

	var control_row: HBoxContainer = HBoxContainer.new()
	control_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_row.add_theme_constant_override("separation", 8)
	donate_box.add_child(control_row)

	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = max_donation
	slider.step = 1.0
	slider.value = starting_amount
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220, 34)
	slider.editable = can_donate
	slider.focus_mode = Control.FOCUS_NONE
	control_row.add_child(slider)

	var amount_box: LineEdit = LineEdit.new()
	amount_box.text = _format_religion_amount(starting_amount)
	amount_box.placeholder_text = "0"
	amount_box.custom_minimum_size = Vector2(118, 38)
	amount_box.editable = can_donate
	amount_box.focus_mode = Control.FOCUS_CLICK
	amount_box.tooltip_text = "Type a donation amount. Mouse-wheel scrolling will not alter this value."
	control_row.add_child(amount_box)

	var button: Button = Button.new()
	button.text = "Donate"
	button.custom_minimum_size = Vector2(120, 38)
	button.add_theme_font_size_override("font_size", 16)
	button.disabled = (not can_donate) or starting_amount <= 0.001
	button.tooltip_text = String(row.get("donation_status", row.get("delivery_status", "")))
	control_row.add_child(button)

	var preview_label: Label = _palace_label("", 14, Color(0.96, 0.82, 0.48, 1.0))
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	donate_box.add_child(preview_label)

	var donation_input_state: Dictionary = {"amount": starting_amount, "syncing": false}

	var update_preview := func(value: float, sync_text: bool) -> void:
		var clamped_value: float = clampf(value, 0.0, max_donation)
		donation_input_state["amount"] = clamped_value
		donation_input_state["syncing"] = true
		if not is_equal_approx(float(slider.value), clamped_value):
			slider.value = clamped_value
		if sync_text:
			amount_box.text = _format_religion_amount(clamped_value)
		donation_input_state["syncing"] = false
		var prestige_preview: float = clamped_value * base_value
		preview_label.text = "Donate " + _format_religion_amount(clamped_value) + " / " + _format_religion_amount(max_donation) + " free " + String(row.get("resource_name", "Good")) + "  →  Prestige +" + _format_religion_amount(prestige_preview)
		button.disabled = (not can_donate) or clamped_value <= 0.001

	var apply_typed_amount := func(finalise_text: bool) -> void:
		if bool(donation_input_state.get("syncing", false)):
			return
		var raw_text: String = amount_box.text.strip_edges()
		if raw_text == "":
			update_preview.call(0.0, finalise_text)
			return
		if not raw_text.is_valid_float():
			if finalise_text:
				amount_box.text = _format_religion_amount(float(donation_input_state.get("amount", 0.0)))
			return
		update_preview.call(float(raw_text), finalise_text)

	# Godot Range controls can respond to mouse-wheel input when hovered/focused.
	# This row deliberately ignores wheel events on the donation slider so normal
	# page scrolling cannot silently change the planned tribute amount. The amount
	# can still be changed by dragging the slider or typing in the box.
	slider.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse_event: InputEventMouseButton = event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN or mouse_event.button_index == MOUSE_BUTTON_WHEEL_LEFT or mouse_event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
				slider.accept_event()
				update_preview.call(float(donation_input_state.get("amount", 0.0)), true)
	)

	slider.value_changed.connect(func(value: float) -> void:
		if bool(donation_input_state.get("syncing", false)):
			return
		update_preview.call(value, true)
	)
	amount_box.text_changed.connect(func(_new_text: String) -> void:
		apply_typed_amount.call(false)
	)
	amount_box.text_submitted.connect(func(_submitted_text: String) -> void:
		apply_typed_amount.call(true)
	)
	amount_box.focus_exited.connect(func() -> void:
		apply_typed_amount.call(true)
	)
	update_preview.call(starting_amount, true)

	var slot_id: String = String(row.get("slot", ""))
	button.pressed.connect(func() -> void:
		var state: Node = _state()
		if state != null and state.has_method("donate_palace_need"):
			state.call("donate_palace_need", slot_id, float(donation_input_state.get("amount", 0.0)))
		elif state != null and state.has_method("deliver_palace_ruler_demand"):
			state.call("deliver_palace_ruler_demand", slot_id)
		_refresh_all()
	)


func _build_palace_authority_main_view() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var authority: Dictionary = {}
	if summary.has("authority_summary") and summary["authority_summary"] is Dictionary:
		authority = summary["authority_summary"] as Dictionary
	else:
		authority = {"dedicated": bool(summary.get("dedicated", false)), "god_id": String(summary.get("dedicated_god", "")), "god_name": String(summary.get("dedicated_god_name", "None")), "route_name": String(summary.get("route_name", "No dedication")), "headline": String(summary.get("authority_status", "Palace authority not connected.")), "body": String(summary.get("power_summary", "")), "active_structures": [], "inactive_structures": [], "next_locked_structures": [], "mechanics_note": "Authority summary backend not connected."}
	var god_id: String = String(authority.get("god_id", summary.get("dedicated_god", "")))
	var colour: Color = _palace_route_colour(god_id)
	var outer: PanelContainer = PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", _make_panel_style(Color(0.024, 0.022, 0.018, 0.94), colour.darkened(0.24), 18))
	dynamic_view_host.add_child(outer)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	outer.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var title: Label = _palace_label("PALACE AUTHORITY", 33, Color(1.0, 0.86, 0.50, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(_palace_wrapped_label(String(authority.get("headline", "Palace Authority")), 21, colour.lightened(0.24)))
	root.add_child(_palace_wrapped_label(String(authority.get("body", "Dedicate and build palace structures to reveal this route's authority.")), 17, Color(0.82, 0.86, 0.78, 1.0)))
	root.add_child(_palace_wrapped_label(String(authority.get("mechanics_note", "This screen reads active palace structures only.")), 14, Color(0.92, 0.74, 0.48, 1.0)))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	scroll.add_child(stack)

	var active_rows: Array = authority.get("active_structures", []) as Array
	var inactive_rows: Array = authority.get("inactive_structures", []) as Array
	var locked_rows: Array = authority.get("next_locked_structures", []) as Array
	if god_id == "tlaloc":
		var forecast: Dictionary = {}
		var state: Node = _state()
		if state != null and state.has_method("get_tlaloc_natural_calendar_forecast"):
			forecast = state.call("get_tlaloc_natural_calendar_forecast") as Dictionary
		_add_tlaloc_forecast_panel(stack, forecast, colour)
	elif god_id == "tezcatlipoca":
		var pressure: Dictionary = {}
		var tez_state: Node = _state()
		if tez_state != null and tez_state.has_method("get_tezcatlipoca_pressure_overview"):
			pressure = tez_state.call("get_tezcatlipoca_pressure_overview") as Dictionary
		_add_tezcatlipoca_pressure_panel(stack, pressure, colour)
	elif god_id == "quetzalcoatl":
		var legitimacy: Dictionary = {}
		var quetz_state: Node = _state()
		if quetz_state != null and quetz_state.has_method("get_quetzalcoatl_legitimacy_overview"):
			legitimacy = quetz_state.call("get_quetzalcoatl_legitimacy_overview") as Dictionary
		_add_quetzalcoatl_legitimacy_panel(stack, legitimacy, colour)
	_add_palace_authority_section(stack, "Active Authority Structures", active_rows, colour, true)
	_add_palace_authority_section(stack, "Inactive Built Structures", inactive_rows, Color(1.0, 0.58, 0.34, 1.0), false)
	_add_palace_authority_locked_section(stack, locked_rows, colour)

func _add_tlaloc_forecast_panel(parent: VBoxContainer, forecast: Dictionary, colour: Color) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.032, 0.038, 0.92), colour.lightened(0.08), 14))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(forecast.get("headline", "Tlaloc Natural Calendar Foresight")), 22, colour.lightened(0.26)))
	stack.add_child(_palace_wrapped_label(String(forecast.get("summary", "Build and maintain active Tlaloc palace structures to reveal upcoming natural pressure.")), 15, Color(0.82, 0.88, 0.80, 1.0)))
	var active_structures: Array = forecast.get("active_structures", []) as Array
	if not active_structures.is_empty():
		stack.add_child(_palace_wrapped_label("Reading through: " + ", ".join(active_structures) + ".", 13, Color(0.70, 0.90, 0.86, 1.0)))
	var events: Array = forecast.get("events", []) as Array
	if events.is_empty():
		stack.add_child(_palace_wrapped_label("No natural pressures are currently visible at this palace authority level.", 14, Color(0.72, 0.76, 0.70, 1.0)))
	else:
		for event_variant: Variant in events:
			if event_variant is Dictionary:
				_add_tlaloc_forecast_event_card(stack, event_variant as Dictionary, colour)
	stack.add_child(_palace_wrapped_label(String(forecast.get("mechanics_note", "Forecast rows are information-only for now.")), 13, Color(0.94, 0.76, 0.48, 1.0)))

func _add_tlaloc_forecast_event_card(parent: VBoxContainer, row: Dictionary, colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.010, 0.020, 0.024, 0.86), colour.darkened(0.06), 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(row.get("timing", "Soon")) + " — " + String(row.get("name", "Natural pressure")), 18, colour.lightened(0.22)))
	stack.add_child(_palace_wrapped_label(String(row.get("category", "Natural pressure")) + ": " + String(row.get("summary", "The palace senses pressure in the natural calendar.")), 14, Color(0.82, 0.86, 0.78, 1.0)))
	stack.add_child(_palace_wrapped_label("Severity: " + String(row.get("severity", "Hidden")) + " | Goods: " + String(row.get("affected_goods", "Hidden")) + " | Duration: " + String(row.get("duration", "Hidden")), 13, Color(0.72, 0.80, 0.74, 1.0)))
	if int(row.get("detail_tier", 0)) >= 4:
		stack.add_child(_palace_wrapped_label("Preparation: " + String(row.get("preparation", "No preparation advice revealed.")), 13, Color(0.86, 0.84, 0.62, 1.0)))


func _add_tezcatlipoca_pressure_panel(parent: VBoxContainer, pressure: Dictionary, colour: Color) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.022, 0.034, 0.92), colour.lightened(0.08), 14))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(pressure.get("headline", "Tezcatlipoca Scarcity Mirror")), 22, colour.lightened(0.26)))
	stack.add_child(_palace_wrapped_label(String(pressure.get("summary", "Build and maintain active Tezcatlipoca palace structures to reveal scarcity and rival pressure hooks.")), 15, Color(0.84, 0.82, 0.88, 1.0)))
	var active_structures: Array = pressure.get("active_structures", []) as Array
	if not active_structures.is_empty():
		stack.add_child(_palace_wrapped_label("Reading through: " + ", ".join(active_structures) + ".", 13, Color(0.86, 0.78, 0.96, 1.0)))
	var market_rows: Array = pressure.get("market_pressure_rows", []) as Array
	if market_rows.is_empty():
		stack.add_child(_palace_wrapped_label("No market pressure is currently visible at this palace authority level.", 14, Color(0.74, 0.72, 0.76, 1.0)))
	else:
		stack.add_child(_palace_label("Market Pressure Readings", 18, Color(1.0, 0.84, 0.54, 1.0)))
		for row_variant: Variant in market_rows:
			if row_variant is Dictionary:
				_add_tezcatlipoca_market_pressure_card(stack, row_variant as Dictionary, colour)
	var rival_rows: Array = pressure.get("rival_pressure_rows", []) as Array
	if not rival_rows.is_empty():
		stack.add_child(_palace_label("Rival Pressure Hooks", 18, Color(1.0, 0.84, 0.54, 1.0)))
		for row_variant: Variant in rival_rows:
			if row_variant is Dictionary:
				_add_tezcatlipoca_rival_pressure_card(stack, row_variant as Dictionary, colour)
	stack.add_child(_palace_wrapped_label(String(pressure.get("mechanics_note", "Tezcatlipoca pressure rows are information-only for now.")), 13, Color(0.94, 0.76, 0.48, 1.0)))

func _add_tezcatlipoca_market_pressure_card(parent: VBoxContainer, row: Dictionary, colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.014, 0.022, 0.88), colour.darkened(0.08), 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(row.get("name", "Good")) + " — " + String(row.get("pressure", "Pressure")), 18, colour.lightened(0.24)))
	stack.add_child(_palace_wrapped_label("Exposure: " + String(row.get("exposure", "Hidden")) + " | Coverage: " + String(row.get("coverage", "Hidden")) + " | Value: " + String(row.get("current_value", "Hidden")), 13, Color(0.78, 0.82, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label(String(row.get("leverage", "Future market-pressure hook.")), 13, Color(0.86, 0.80, 0.62, 1.0)))

func _add_tezcatlipoca_rival_pressure_card(parent: VBoxContainer, row: Dictionary, colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.014, 0.022, 0.84), colour.darkened(0.14), 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(row.get("rival", "Rival")) + " — pressure point", 18, colour.lightened(0.22)))
	stack.add_child(_palace_wrapped_label("Domain: " + String(row.get("domain", "Hidden")), 13, Color(0.78, 0.82, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label(String(row.get("summary", "The mirror reveals an unclear rival weakness.")), 13, Color(0.82, 0.84, 0.78, 1.0)))
	stack.add_child(_palace_wrapped_label(String(row.get("future_hook", "Future manipulation hook.")), 13, Color(0.86, 0.80, 0.62, 1.0)))


func _add_quetzalcoatl_legitimacy_panel(parent: VBoxContainer, legitimacy: Dictionary, colour: Color) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.024, 0.034, 0.026, 0.92), colour.lightened(0.08), 14))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(legitimacy.get("headline", "Quetzalcoatl Legitimacy Court")), 22, colour.lightened(0.26)))
	stack.add_child(_palace_wrapped_label(String(legitimacy.get("summary", "Build and maintain active Quetzalcoatl palace structures to reveal legitimacy, recognition and tribute-credibility hooks.")), 15, Color(0.84, 0.88, 0.80, 1.0)))
	var active_structures: Array = legitimacy.get("active_structures", []) as Array
	if not active_structures.is_empty():
		stack.add_child(_palace_wrapped_label("Reading through: " + ", ".join(active_structures) + ".", 13, Color(0.86, 0.94, 0.76, 1.0)))
	var legitimacy_rows: Array = legitimacy.get("legitimacy_rows", []) as Array
	if legitimacy_rows.is_empty():
		stack.add_child(_palace_wrapped_label("No legitimacy hooks are currently visible at this palace authority level.", 14, Color(0.74, 0.76, 0.70, 1.0)))
	else:
		stack.add_child(_palace_label("Legitimacy and Recognition Hooks", 18, Color(1.0, 0.88, 0.56, 1.0)))
		for row_variant: Variant in legitimacy_rows:
			if row_variant is Dictionary:
				_add_quetzalcoatl_legitimacy_card(stack, row_variant as Dictionary, colour)
	var obligation_rows: Array = legitimacy.get("obligation_rows", []) as Array
	if not obligation_rows.is_empty():
		stack.add_child(_palace_label("Tribute Credibility Readings", 18, Color(1.0, 0.88, 0.56, 1.0)))
		for row_variant: Variant in obligation_rows:
			if row_variant is Dictionary:
				_add_quetzalcoatl_legitimacy_card(stack, row_variant as Dictionary, colour)
	stack.add_child(_palace_wrapped_label(String(legitimacy.get("mechanics_note", "Quetzalcoatl authority rows are information-only for now.")), 13, Color(0.94, 0.76, 0.48, 1.0)))

func _add_quetzalcoatl_legitimacy_card(parent: VBoxContainer, row: Dictionary, colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.014, 0.022, 0.016, 0.88), colour.darkened(0.08), 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_palace_label(String(row.get("name", "Legitimacy")), 18, colour.lightened(0.24)))
	stack.add_child(_palace_wrapped_label("Domain: " + String(row.get("domain", "Hidden")), 13, Color(0.78, 0.82, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label(String(row.get("summary", "The palace reveals a legitimacy hook.")), 13, Color(0.82, 0.86, 0.78, 1.0)))
	stack.add_child(_palace_wrapped_label(String(row.get("future_hook", "Future recognition hook.")), 13, Color(0.86, 0.82, 0.62, 1.0)))

func _add_palace_authority_section(parent: VBoxContainer, title_text: String, rows: Array, colour: Color, active_section: bool) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.026, 0.028, 0.023, 0.90), colour.darkened(0.08), 12))
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
	stack.add_child(_palace_label(title_text, 21, Color(1.0, 0.84, 0.54, 1.0)))
	if rows.is_empty():
		var empty_text: String = "No active palace structures yet. Build structures, pay their maintenance and provide staff to activate authority."
		if not active_section:
			empty_text = "No built structures are currently inactive."
		stack.add_child(_palace_wrapped_label(empty_text, 14, Color(0.70, 0.74, 0.68, 1.0)))
		return
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		_add_palace_authority_structure_card(stack, row, colour, active_section)

func _add_palace_authority_structure_card(parent: VBoxContainer, row: Dictionary, colour: Color, active_section: bool) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border: Color = colour
	if not active_section:
		border = Color(1.0, 0.58, 0.34, 0.72)
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.020, 0.017, 0.86), border, 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	var status_text: String = "Active" if active_section else "Inactive"
	stack.add_child(_palace_label(String(row.get("name", "Palace Structure")) + " — " + status_text, 18, border.lightened(0.20)))
	stack.add_child(_palace_wrapped_label("Tier " + str(int(row.get("tier", 1))) + ". " + String(row.get("effect_summary", "Future authority hook.")), 14, Color(0.80, 0.84, 0.76, 1.0)))
	if active_section:
		stack.add_child(_palace_wrapped_label("Maintenance paid: " + _format_cost(row.get("maintenance_paid", {}) as Dictionary) + ". Staff assigned: " + _palace_format_staff_requirement(row.get("staff_assigned", {}) as Dictionary) + ".", 13, Color(0.70, 0.90, 0.66, 1.0)))
	else:
		stack.add_child(_palace_wrapped_label(String(row.get("inactive_reason", "Missing maintenance or staff.")), 13, Color(1.0, 0.72, 0.45, 1.0)))

func _add_palace_authority_locked_section(parent: VBoxContainer, rows: Array, colour: Color) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.022, 0.020, 0.84), Color(0.45, 0.48, 0.38, 0.55), 10))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	stack.add_child(_palace_label("Future Authority Locked Behind Structures", 18, Color(1.0, 0.84, 0.54, 1.0)))
	if rows.is_empty():
		stack.add_child(_palace_wrapped_label("No further palace structure data is visible for this route.", 14, Color(0.70, 0.74, 0.68, 1.0)))
		return
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		var line: String = String(row.get("name", "Structure")) + " — Tier " + str(int(row.get("tier", 1))) + ": " + String(row.get("effect_summary", "Future authority hook."))
		stack.add_child(_palace_wrapped_label(line, 14, Color(0.72, 0.78, 0.70, 1.0)))
		stack.add_child(_palace_wrapped_label("Status: " + String(row.get("build_status", "Locked.")), 13, Color(0.62, 0.68, 0.62, 1.0)))


func _build_palace_prestige_main_view() -> void:
	var state: Node = _state()
	var prestige: Dictionary = {}
	if state != null and state.has_method("get_prestige_summary"):
		prestige = state.call("get_prestige_summary") as Dictionary

	var outer: PanelContainer = PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", _make_panel_style(Color(0.026, 0.024, 0.019, 0.94), Color(0.76, 0.60, 0.34, 0.68), 18))
	dynamic_view_host.add_child(outer)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	outer.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title: Label = _palace_label("PALACE PRESTIGE", 33, Color(1.0, 0.86, 0.50, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(_palace_wrapped_label("Prestige is the house's public standing and main score. It is earned from visible actions such as court-need donations, Flower Wars, ritual sacrifice and savvy market trade. It is never spent.", 17, Color(0.83, 0.86, 0.78, 1.0)))

	if prestige.is_empty():
		root.add_child(_palace_wrapped_label("Prestige backend score data is not connected yet.", 18, Color(1.0, 0.72, 0.45, 1.0)))
		return

	var player_value: float = float(prestige.get("player_prestige", 0.0))
	var leaderboard: Array = prestige.get("leaderboard", []) as Array
	var player_rank: Dictionary = prestige.get("player_rank", {}) as Dictionary
	var rank_number: int = int(player_rank.get("rank", 0))
	var rank_text: String = "Rank pending"
	if rank_number > 0:
		rank_text = _ordinal_number(rank_number) + " of " + str(max(1, leaderboard.size())) + " houses"
	var recent: Array = prestige.get("recent_history", []) as Array
	var all_history: Array = prestige.get("prestige_history", []) as Array
	var source_rows: Array[Dictionary] = _prestige_source_rows(all_history)
	var latest_text: String = "No recent prestige gains recorded."
	if not recent.is_empty() and recent[0] is Dictionary:
		var latest: Dictionary = recent[0] as Dictionary
		latest_text = _prestige_signed_amount(float(latest.get("amount", 0.0))) + " — " + String(latest.get("detail", "Prestige changed"))
	var leader_text: String = "No leaderboard data"
	if not leaderboard.is_empty() and leaderboard[0] is Dictionary:
		var leader: Dictionary = leaderboard[0] as Dictionary
		leader_text = String(leader.get("name", "House")) + " " + _format_religion_amount(float(leader.get("prestige", 0.0)))

	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_theme_constant_override("separation", 10)
	root.add_child(status_row)
	_add_palace_summary_card(status_row, "Total", _format_religion_amount(player_value), "Current Player House Prestige.", Color(0.96, 0.80, 0.52, 1.0))
	_add_palace_summary_card(status_row, "Standing", rank_text, "Prestige is compared against rival houses.", Color(0.72, 0.92, 0.70, 1.0))
	_add_palace_summary_card(status_row, "Leader", leader_text, "Rival values are prototype comparison data until full rival turns are connected.", Color(0.90, 0.72, 0.44, 1.0))
	_add_palace_summary_card(status_row, "Latest", latest_text, "Most recent recorded Prestige change.", Color(0.68, 0.86, 0.94, 1.0))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	scroll.add_child(stack)

	stack.add_child(_palace_label("Prestige Source Breakdown", 23, Color(1.0, 0.84, 0.54, 1.0)))
	stack.add_child(_palace_wrapped_label("This shows where the score has actually come from so gains are not hidden in the background.", 14, Color(0.76, 0.80, 0.70, 1.0)))
	if source_rows.is_empty():
		stack.add_child(_palace_wrapped_label("No source history yet. Make a qualifying market trade, donate to a court need, win a Flower War or complete a prestige-granting ritual to create the first entry.", 15, Color(0.74, 0.78, 0.70, 1.0)))
	else:
		for row: Dictionary in source_rows:
			_add_palace_prestige_source_row_card(stack, row)

	stack.add_child(_palace_label("Recent Prestige Ledger", 23, Color(1.0, 0.84, 0.54, 1.0)))
	if recent.is_empty():
		stack.add_child(_palace_wrapped_label("No recent prestige entries recorded yet.", 15, Color(0.74, 0.78, 0.70, 1.0)))
	else:
		var recent_count: int = 0
		for item_variant: Variant in recent:
			if recent_count >= 12:
				break
			if item_variant is Dictionary:
				_add_palace_prestige_history_row_card(stack, item_variant as Dictionary)
				recent_count += 1

	stack.add_child(_palace_label("House Standing", 23, Color(1.0, 0.84, 0.54, 1.0)))
	if leaderboard.is_empty():
		stack.add_child(_palace_wrapped_label("No leaderboard data is available.", 15, Color(0.74, 0.78, 0.70, 1.0)))
	else:
		for row_variant: Variant in leaderboard:
			if row_variant is Dictionary:
				_add_palace_prestige_leaderboard_row_card(stack, row_variant as Dictionary)

	var note_panel: PanelContainer = PanelContainer.new()
	note_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.023, 0.020, 0.84), Color(0.45, 0.48, 0.38, 0.55), 10))
	stack.add_child(note_panel)
	var note_margin: MarginContainer = MarginContainer.new()
	note_margin.add_theme_constant_override("margin_left", 12)
	note_margin.add_theme_constant_override("margin_top", 9)
	note_margin.add_theme_constant_override("margin_right", 12)
	note_margin.add_theme_constant_override("margin_bottom", 9)
	note_panel.add_child(note_margin)
	note_margin.add_child(_palace_wrapped_label(String(prestige.get("mechanics_note", "Prestige is the main score. It is earned, lost, displayed and compared against rivals. It is never spent.")), 15, Color(0.74, 0.78, 0.70, 1.0)))

func _prestige_source_rows(history: Array) -> Array[Dictionary]:
	var totals: Dictionary = {}
	for item_variant: Variant in history:
		if not (item_variant is Dictionary):
			continue
		var item: Dictionary = item_variant as Dictionary
		var source_id: String = String(item.get("source_id", "unknown"))
		var amount: float = float(item.get("amount", 0.0))
		if not totals.has(source_id):
			totals[source_id] = {"source_id": source_id, "amount": 0.0, "count": 0, "latest_detail": "", "latest_veintena": 0}
		var row: Dictionary = totals[source_id] as Dictionary
		row["amount"] = float(row.get("amount", 0.0)) + amount
		row["count"] = int(row.get("count", 0)) + 1
		row["latest_detail"] = String(item.get("detail", row.get("latest_detail", "Prestige changed")))
		row["latest_veintena"] = int(item.get("veintena", row.get("latest_veintena", 0)))
		totals[source_id] = row
	var rows: Array[Dictionary] = []
	for key_variant: Variant in totals.keys():
		var row_value: Dictionary = totals[key_variant] as Dictionary
		rows.append(row_value.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_amount: float = absf(float(a.get("amount", 0.0)))
		var b_amount: float = absf(float(b.get("amount", 0.0)))
		if is_equal_approx(a_amount, b_amount):
			return _prestige_source_display_name(String(a.get("source_id", ""))) < _prestige_source_display_name(String(b.get("source_id", "")))
		return a_amount > b_amount
	)
	return rows

func _add_palace_prestige_source_row_card(parent: VBoxContainer, row: Dictionary) -> void:
	var source_id: String = String(row.get("source_id", "unknown"))
	var colour: Color = _prestige_source_colour(source_id)
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.022, 0.024, 0.020, 0.90), colour.darkened(0.08), 10))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	var top: HBoxContainer = HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 8)
	stack.add_child(top)
	var title: Label = _palace_label(_prestige_source_display_name(source_id), 19, colour.lightened(0.22))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var value: Label = _palace_label(_prestige_signed_amount(float(row.get("amount", 0.0))) + " Prestige", 18, colour.lightened(0.18))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(160, 0)
	top.add_child(value)
	stack.add_child(_palace_wrapped_label(str(int(row.get("count", 0))) + " recorded entr" + ("y" if int(row.get("count", 0)) == 1 else "ies") + ". Latest: " + String(row.get("latest_detail", "Prestige changed")), 14, Color(0.80, 0.84, 0.76, 1.0)))

func _add_palace_prestige_history_row_card(parent: VBoxContainer, record: Dictionary) -> void:
	var source_id: String = String(record.get("source_id", "unknown"))
	var colour: Color = _prestige_source_colour(source_id)
	var amount: float = float(record.get("amount", 0.0))
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.020, 0.018, 0.86), colour.darkened(0.14), 8))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	margin.add_child(stack)
	stack.add_child(_palace_wrapped_label(_prestige_record_time_text(record) + " • " + _prestige_source_display_name(source_id) + " • " + _prestige_signed_amount(amount) + " Prestige", 15, colour.lightened(0.22)))
	stack.add_child(_palace_wrapped_label(String(record.get("detail", "Prestige changed")), 13, Color(0.76, 0.80, 0.72, 1.0)))

func _add_palace_prestige_leaderboard_row_card(parent: VBoxContainer, row: Dictionary) -> void:
	var is_player: bool = bool(row.get("is_player", false))
	var border: Color = Color(0.76, 0.63, 0.32, 0.78) if is_player else Color(0.42, 0.46, 0.38, 0.58)
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.023, 0.020, 0.86), border, 8))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)
	var line: HBoxContainer = HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 8)
	margin.add_child(line)
	var name_label: Label = _palace_label(str(int(row.get("rank", 0))) + ". " + String(row.get("name", "House")) + (" (you)" if is_player else ""), 16, Color(0.95, 0.88, 0.62, 1.0) if is_player else Color(0.78, 0.82, 0.74, 1.0))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var value_label: Label = _palace_label(_format_religion_amount(float(row.get("prestige", 0.0))) + " Prestige", 16, Color(0.95, 0.88, 0.62, 1.0) if is_player else Color(0.78, 0.82, 0.74, 1.0))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(150, 0)
	line.add_child(value_label)

func _prestige_source_display_name(source_id: String) -> String:
	match source_id:
		"economic_savvy_trade":
			return "Savvy Trade"
		"court_need_donation":
			return "Court Need Donations"
		"flower_war_attack":
			return "Flower War Musters"
		"flower_war_defence":
			return "Flower War Defence"
		"religion_sacrifice":
			return "Ritual Sacrifice"
		"shrine_level":
			return "Shrine Recognition"
		"palace_recognition":
			return "Palace Recognition"
	return source_id.replace("_", " ").capitalize()

func _prestige_source_colour(source_id: String) -> Color:
	match source_id:
		"economic_savvy_trade":
			return Color(0.50, 0.82, 0.74, 0.90)
		"court_need_donation":
			return Color(0.96, 0.78, 0.42, 0.90)
		"flower_war_attack", "flower_war_defence":
			return Color(0.90, 0.42, 0.30, 0.90)
		"religion_sacrifice":
			return Color(0.70, 0.55, 0.92, 0.90)
		"shrine_level":
			return Color(0.42, 0.70, 0.96, 0.90)
		"palace_recognition":
			return Color(0.95, 0.86, 0.54, 0.90)
	return Color(0.70, 0.74, 0.68, 0.85)

func _prestige_signed_amount(amount: float) -> String:
	return ("+" if amount >= 0.0 else "") + _format_religion_amount(amount)

func _prestige_record_time_text(record: Dictionary) -> String:
	var veintena: int = int(record.get("veintena", 0))
	if veintena > 0:
		return "Veintena " + str(veintena)
	return "Current turn"

func _build_palace_overview_main_view() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var god_id: String = String(summary.get("dedicated_god", ""))
	var colour: Color = _palace_route_colour(god_id)
	var outer: PanelContainer = PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", _make_panel_style(Color(0.026, 0.024, 0.019, 0.94), Color(0.76, 0.60, 0.34, 0.68), 18))
	dynamic_view_host.add_child(outer)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	outer.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var title: Label = _palace_label("PALACE OVERVIEW", 33, Color(1.0, 0.86, 0.50, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var dedication_text: String = "No dedication chosen"
	if bool(summary.get("dedicated", false)):
		dedication_text = String(summary.get("dedicated_god_name", "Chosen")) + " — " + String(summary.get("route_name", "Palace Route"))
	root.add_child(_palace_wrapped_label(dedication_text + ". " + String(summary.get("power_summary", "Choose a Divine Seat to define the palace route.")), 18, Color(0.83, 0.86, 0.78, 1.0)))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	scroll.add_child(stack)

	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_theme_constant_override("separation", 10)
	stack.add_child(status_row)
	_add_palace_summary_card(status_row, "Palace Level", str(int(summary.get("palace_level", 1))), "Highest built palace structure tier.", colour)
	_add_palace_summary_card(status_row, "Structures", str(int(summary.get("built_structure_count", 0))) + " built", str(int(summary.get("active_structure_count", 0))) + " active; " + str(int(summary.get("inactive_structure_count", 0))) + " inactive.", colour)
	_add_palace_summary_card(status_row, "Authority", str(int(summary.get("active_structure_count", 0))) + " active", "Authority tab now reads active palace structures; effects remain display-only.", colour)

	_build_palace_staff_summary_panel(stack, summary, false)
	_build_palace_maintenance_summary_panel(stack, summary)

	var note_panel: PanelContainer = PanelContainer.new()
	note_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.023, 0.020, 0.84), Color(0.45, 0.48, 0.38, 0.55), 10))
	stack.add_child(note_panel)
	var note_margin: MarginContainer = MarginContainer.new()
	note_margin.add_theme_constant_override("margin_left", 12)
	note_margin.add_theme_constant_override("margin_top", 9)
	note_margin.add_theme_constant_override("margin_right", 12)
	note_margin.add_theme_constant_override("margin_bottom", 9)
	note_panel.add_child(note_margin)
	note_margin.add_child(_palace_wrapped_label("Palace structures consume maintenance and reserve existing active staff when the Veintena resolves. The Prestige tab now explains score, source history and rival standing. The Authority tab reads active structures; Huitzilopochtli gates attacking Flower Wars, Tlaloc shows natural foresight, Tezcatlipoca shows scarcity pressure, and Quetzalcoatl shows legitimacy hooks. Court needs can now be delivered, but prestige is generated by donation value.", 15, Color(0.74, 0.78, 0.70, 1.0)))

func _add_palace_summary_card(parent: HBoxContainer, heading: String, value: String, detail: String, colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.032, 0.026, 0.90), colour.darkened(0.10), 11))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_palace_label(heading, 15, Color(0.72, 0.76, 0.70, 1.0)))
	stack.add_child(_palace_label(value, 24, colour.lightened(0.24)))
	stack.add_child(_palace_wrapped_label(detail, 13, Color(0.74, 0.78, 0.70, 1.0)))

func _build_palace_staff_summary_panel(parent: VBoxContainer, summary: Dictionary, compact: bool = false) -> void:
	var staff_summary: Dictionary = {}
	if summary.has("staff_summary") and summary["staff_summary"] is Dictionary:
		staff_summary = summary["staff_summary"] as Dictionary
	var rows: Array = staff_summary.get("rows", []) as Array
	var border_colour: Color = Color(0.72, 0.58, 0.36, 0.72)
	if int(staff_summary.get("total_shortfall", 0)) > 0:
		border_colour = Color(1.0, 0.52, 0.28, 0.88)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.026, 0.022, 0.90), border_colour, 12))
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
	stack.add_child(_palace_label("Palace Staff", 21 if not compact else 17, Color(1.0, 0.84, 0.54, 1.0)))
	stack.add_child(_palace_wrapped_label(String(staff_summary.get("headline", "No palace staff required yet.")), 15, Color(0.82, 0.84, 0.76, 1.0)))
	if rows.is_empty():
		stack.add_child(_palace_wrapped_label("No built palace structure currently requires staff.", 14, Color(0.70, 0.74, 0.68, 1.0)))
		return
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		var line_colour: Color = Color(0.76, 0.80, 0.72, 1.0)
		if int(row.get("shortfall", 0)) > 0:
			line_colour = Color(1.0, 0.70, 0.42, 1.0)
		var line: String = String(row.get("name", "Staff")) + ": " + str(int(row.get("assigned_to_active_structures", 0))) + " assigned / " + str(int(row.get("required_by_built_structures", 0))) + " required; available " + str(int(row.get("available", 0))) + ". " + String(row.get("status", ""))
		if int(row.get("shortfall", 0)) > 0:
			line += " — short " + str(int(row.get("shortfall", 0)))
		stack.add_child(_palace_wrapped_label(line, 14 if not compact else 13, line_colour))
	if not compact:
		stack.add_child(_palace_wrapped_label(String(staff_summary.get("note", "Uses existing active population groups.")), 13, Color(0.66, 0.70, 0.64, 1.0)))

func _build_palace_maintenance_summary_panel(parent: VBoxContainer, summary: Dictionary) -> void:
	var total_maintenance: Dictionary = summary.get("total_maintenance", {}) as Dictionary
	var operation: Dictionary = summary.get("palace_operation_preview", {}) as Dictionary
	var paid: Dictionary = operation.get("maintenance_paid", {}) as Dictionary
	var shortfalls: Dictionary = operation.get("maintenance_shortfalls", {}) as Dictionary
	var border_colour: Color = Color(0.64, 0.70, 0.52, 0.70)
	if not shortfalls.is_empty():
		border_colour = Color(1.0, 0.52, 0.28, 0.88)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.024, 0.026, 0.022, 0.90), border_colour, 12))
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
	stack.add_child(_palace_label("Palace Maintenance", 21, Color(1.0, 0.84, 0.54, 1.0)))
	stack.add_child(_palace_wrapped_label("Total built-structure upkeep: " + _format_cost(total_maintenance), 15, Color(0.82, 0.84, 0.76, 1.0)))
	if paid.is_empty() and total_maintenance.is_empty():
		stack.add_child(_palace_wrapped_label("No built palace structures require maintenance yet.", 14, Color(0.70, 0.74, 0.68, 1.0)))
	else:
		stack.add_child(_palace_wrapped_label("Preview paid this Veintena if resolved now: " + _format_cost(paid), 14, Color(0.70, 0.90, 0.66, 1.0)))
	if not shortfalls.is_empty():
		stack.add_child(_palace_wrapped_label("Maintenance shortfall: " + _format_cost(shortfalls), 14, Color(1.0, 0.70, 0.42, 1.0)))

func _build_palace_divine_seat_main_view() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var outer: PanelContainer = PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.022, 0.018, 0.94), Color(0.76, 0.60, 0.34, 0.70), 18))
	dynamic_view_host.add_child(outer)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	outer.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title_label: Label = _palace_label("PALACE DIVINE SEAT", 32, Color(1.0, 0.86, 0.48, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title_label)

	if bool(summary.get("dedicated", false)):
		_build_palace_dedicated_main_tree(root, summary)
	else:
		_build_palace_undedicated_main_choice(root)

func _build_palace_undedicated_main_choice(root: VBoxContainer) -> void:
	root.add_child(_palace_wrapped_label("Choose the god whose authority will sit at the heart of your house. This dedication is permanent for Prototype 0.", 18, Color(0.80, 0.84, 0.78, 1.0)))

	var routes: Array[Dictionary] = _palace_probe_routes()
	if _selected_palace_route_id == "" and routes.size() > 0:
		_selected_palace_route_id = String(routes[0].get("id", routes[0].get("god_id", "")))

	var hall: HBoxContainer = HBoxContainer.new()
	hall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hall.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hall.add_theme_constant_override("separation", 14)
	root.add_child(hall)

	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 12)
	hall.add_child(left_col)

	var centre_col: VBoxContainer = VBoxContainer.new()
	centre_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre_col.add_theme_constant_override("separation", 12)
	centre_col.custom_minimum_size = Vector2(330, 0)
	hall.add_child(centre_col)

	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 12)
	hall.add_child(right_col)

	var route_tlaloc: Dictionary = _palace_route_by_id("tlaloc")
	var route_tez: Dictionary = _palace_route_by_id("tezcatlipoca")
	var route_huitz: Dictionary = _palace_route_by_id("huitzilopochtli")
	var route_quetz: Dictionary = _palace_route_by_id("quetzalcoatl")
	if not route_tlaloc.is_empty():
		left_col.add_child(_make_palace_route_button_card(route_tlaloc))
	if not route_tez.is_empty():
		left_col.add_child(_make_palace_route_button_card(route_tez))
	_build_palace_central_seat_panel(centre_col)
	var selected_route: Dictionary = _palace_route_by_id(_selected_palace_route_id)
	_build_palace_route_detail_panel(centre_col, selected_route)
	if not route_huitz.is_empty():
		right_col.add_child(_make_palace_route_button_card(route_huitz))
	if not route_quetz.is_empty():
		right_col.add_child(_make_palace_route_button_card(route_quetz))

func _make_palace_route_button_card(route: Dictionary) -> Button:
	var god_id: String = String(route.get("id", route.get("god_id", "")))
	var god_name: String = String(route.get("god_name", route.get("name", god_id.capitalize())))
	var route_name: String = String(route.get("route_name", "Palace Route"))
	var selected: bool = god_id == _selected_palace_route_id
	var colour: Color = _palace_route_colour(god_id)
	var button: Button = Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(210, 145)
	button.text = god_name.to_upper() + "\n" + _palace_route_domain_line(god_id) + "\n\n" + route_name
	button.tooltip_text = String(route.get("power_summary", ""))
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.035, 0.034, 0.028, 0.94), colour.darkened(0.10), 13))
	button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.055, 0.050, 0.038, 0.98), colour.lightened(0.14), 13))
	button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.070, 0.055, 0.038, 1.0), colour.lightened(0.25), 13))
	if selected:
		button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.065, 0.050, 0.035, 0.98), colour.lightened(0.32), 13))
	button.pressed.connect(func() -> void:
		_on_palace_route_selected(god_id)
	)
	return button

func _build_palace_central_seat_panel(parent: VBoxContainer) -> void:
	var selected_route: Dictionary = _palace_route_by_id(_selected_palace_route_id)
	var god_id: String = String(selected_route.get("id", selected_route.get("god_id", "")))
	var colour: Color = _palace_route_colour(god_id)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 145)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.018, 0.016, 0.95), colour, 18))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	var title_text: String = "EMPTY DIVINE SEAT"
	var subtitle_text: String = "Select a god to preview the authority route."
	if not selected_route.is_empty():
		title_text = String(selected_route.get("god_name", "Chosen")).to_upper() + " SELECTED"
		subtitle_text = String(selected_route.get("route_name", "Palace Route"))
	var title: Label = _palace_label(title_text, 24, Color(1.0, 0.88, 0.54, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var subtitle: Label = _palace_label(subtitle_text, 18, Color(0.82, 0.88, 0.80, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(subtitle)
	var glyph: Label = _palace_label(_palace_route_seat_glyph(god_id), 34, colour.lightened(0.20))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(glyph)

func _build_palace_route_detail_panel(parent: VBoxContainer, route: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.040, 0.035, 0.026, 0.96), Color(0.72, 0.58, 0.34, 0.55), 14))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	if route.is_empty():
		stack.add_child(_palace_label("No route selected", 22, Color(0.92, 0.84, 0.62, 1.0)))
		stack.add_child(_palace_wrapped_label("Choose a god card to preview the Divine Seat route.", 17, Color(0.78, 0.80, 0.74, 1.0)))
		return
	var god_id: String = String(route.get("id", route.get("god_id", "")))
	var colour: Color = _palace_route_colour(god_id)
	stack.add_child(_palace_label(String(route.get("god_name", "Chosen")).to_upper(), 25, colour.lightened(0.18)))
	stack.add_child(_palace_wrapped_label(_palace_route_domain_line(god_id), 16, Color(0.82, 0.82, 0.72, 1.0)))
	stack.add_child(_palace_wrapped_label("Power: " + String(route.get("route_name", "Palace Route")), 18, Color(1.0, 0.86, 0.52, 1.0)))
	stack.add_child(_palace_wrapped_label(_palace_route_flavour(god_id), 17, Color(0.80, 0.84, 0.78, 1.0)))
	stack.add_child(_palace_wrapped_label("Future palace structures: " + ", ".join(_palace_tree_preview_names(god_id)) + ".", 15, Color(0.68, 0.78, 0.74, 1.0)))
	var status: Dictionary = {"ok": false, "reason": "Dedication backend not connected."}
	var state: Node = _state()
	if state != null and state.has_method("can_dedicate_palace_to_god"):
		status = state.call("can_dedicate_palace_to_god", god_id) as Dictionary
	var confirm: Button = Button.new()
	confirm.text = "Dedicate Palace to " + String(route.get("god_name", "Chosen"))
	confirm.custom_minimum_size = Vector2(0, 46)
	confirm.add_theme_font_size_override("font_size", 20)
	confirm.add_theme_stylebox_override("normal", _make_panel_style(Color(0.055, 0.045, 0.030, 0.94), colour, 10))
	confirm.add_theme_stylebox_override("hover", _make_panel_style(Color(0.075, 0.055, 0.034, 1.0), colour.lightened(0.18), 10))
	confirm.disabled = not bool(status.get("ok", false))
	confirm.tooltip_text = String(status.get("reason", ""))
	confirm.pressed.connect(func() -> void:
		_on_palace_confirm_dedication_pressed(god_id)
	)
	stack.add_child(confirm)
	stack.add_child(_palace_wrapped_label("Permanent for Prototype 0. The Divine Seat will become this god's palace structure node data.", 14, Color(0.92, 0.72, 0.50, 1.0)))

func _build_palace_dedicated_main_tree(root: VBoxContainer, summary: Dictionary) -> void:
	var god_id: String = String(summary.get("dedicated_god", ""))
	var colour: Color = _palace_route_colour(god_id)
	var header: PanelContainer = PanelContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_stylebox_override("panel", _make_panel_style(Color(0.026, 0.026, 0.020, 0.96), colour, 16))
	root.add_child(header)
	var header_margin: MarginContainer = MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 18)
	header_margin.add_theme_constant_override("margin_top", 12)
	header_margin.add_theme_constant_override("margin_right", 18)
	header_margin.add_theme_constant_override("margin_bottom", 12)
	header.add_child(header_margin)
	var header_stack: VBoxContainer = VBoxContainer.new()
	header_stack.add_theme_constant_override("separation", 6)
	header_margin.add_child(header_stack)
	var title: Label = _palace_label("PALACE DEDICATED TO " + String(summary.get("dedicated_god_name", "Chosen")).to_upper(), 28, colour.lightened(0.24))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_stack.add_child(title)
	header_stack.add_child(_palace_wrapped_label(String(summary.get("route_name", "Palace Route")) + ". " + String(summary.get("power_summary", "")), 17, Color(0.84, 0.86, 0.78, 1.0)))

	_build_palace_staff_summary_panel(root, summary, true)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var tree_stack: VBoxContainer = VBoxContainer.new()
	tree_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_stack.add_theme_constant_override("separation", 10)
	scroll.add_child(tree_stack)
	var tree: Dictionary = {}
	if summary.has("structure_tree_shell") and summary["structure_tree_shell"] is Dictionary:
		tree = summary["structure_tree_shell"] as Dictionary
	else:
		var state: Node = _state()
		if state != null and state.has_method("get_palace_structure_tree_shell"):
			tree = state.call("get_palace_structure_tree_shell", god_id) as Dictionary
	if tree.is_empty():
		tree_stack.add_child(_palace_wrapped_label("Palace structure node data is not connected yet.", 18, Color(0.82, 0.76, 0.62, 1.0)))
		return
	var tiers: Array = tree.get("tiers", []) as Array
	for tier_variant: Variant in tiers:
		if tier_variant is Dictionary:
			_add_palace_tree_tier_card(tree_stack, tier_variant as Dictionary, colour)
	_add_palace_paths_not_chosen_panel(tree_stack, god_id)

func _add_palace_tree_tier_card(parent: VBoxContainer, tier: Dictionary, colour: Color) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.033, 0.026, 0.90), colour.darkened(0.10), 12))
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
	stack.add_child(_palace_label(String(tier.get("title", "Palace Tier")), 21, Color(1.0, 0.84, 0.54, 1.0)))
	var structures: Array = tier.get("structures", []) as Array
	for structure_variant: Variant in structures:
		if structure_variant is Dictionary:
			var structure: Dictionary = structure_variant as Dictionary
			_add_palace_structure_node_card(stack, structure, colour)

func _add_palace_structure_node_card(parent: VBoxContainer, structure: Dictionary, route_colour: Color) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.020, 0.023, 0.021, 0.92), route_colour.darkened(0.22), 9))
	parent.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_theme_constant_override("separation", 8)
	stack.add_child(title_row)
	var title: Label = _palace_label(String(structure.get("name", "Palace Structure")), 19, route_colour.lightened(0.24))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var status: Label = _palace_label(String(structure.get("status", "Not built")), 14, Color(0.92, 0.74, 0.48, 1.0))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.custom_minimum_size = Vector2(110, 0)
	title_row.add_child(status)

	stack.add_child(_palace_wrapped_label("Tier " + str(int(structure.get("tier", structure.get("level", 1)))) + " — " + String(structure.get("route", "Palace Route")), 14, Color(0.72, 0.78, 0.72, 1.0)))
	stack.add_child(_palace_wrapped_label(String(structure.get("description", structure.get("summary", "Future palace structure."))), 15, Color(0.80, 0.83, 0.76, 1.0)))

	var build_cost: Dictionary = structure.get("build_cost", {}) as Dictionary
	var maintenance_cost: Dictionary = structure.get("maintenance_cost", {}) as Dictionary
	var staff_requirement: Dictionary = structure.get("staff_requirement", {}) as Dictionary
	var prerequisite_text: String = String(structure.get("prerequisite_text", "None"))
	var effect_summary: String = String(structure.get("effect_summary", structure.get("summary", "Future palace authority hook.")))
	stack.add_child(_palace_wrapped_label("Build cost: " + _format_cost(build_cost), 14, Color(0.77, 0.83, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label("Maintenance: " + _format_cost(maintenance_cost), 14, Color(0.77, 0.83, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label("Staff: " + _palace_format_staff_requirement(staff_requirement), 14, Color(0.77, 0.83, 0.76, 1.0)))
	stack.add_child(_palace_wrapped_label("Prerequisites: " + prerequisite_text, 14, Color(0.70, 0.76, 0.70, 1.0)))
	stack.add_child(_palace_wrapped_label("Effect: " + effect_summary, 14, Color(0.92, 0.82, 0.55, 1.0)))

	var structure_id: String = String(structure.get("id", ""))
	var built: bool = bool(structure.get("built", false))
	if built:
		var active: bool = bool(structure.get("active", false))
		var paid_preview: Dictionary = structure.get("maintenance_paid_preview", {}) as Dictionary
		var staff_preview: Dictionary = structure.get("staff_assigned_preview", {}) as Dictionary
		if not paid_preview.is_empty():
			stack.add_child(_palace_wrapped_label("Maintenance covered: " + _format_cost(paid_preview), 13, Color(0.70, 0.86, 0.68, 1.0)))
		if not staff_preview.is_empty():
			stack.add_child(_palace_wrapped_label("Staff assigned: " + _palace_format_staff_requirement(staff_preview), 13, Color(0.70, 0.86, 0.68, 1.0)))
		if active:
			stack.add_child(_palace_wrapped_label("Active. Maintenance and staff are currently covered; authority effects will be connected later.", 13, Color(0.62, 0.95, 0.70, 1.0)))
		else:
			stack.add_child(_palace_wrapped_label("Built but inactive: " + String(structure.get("inactive_reason", "missing maintenance or staff.")), 13, Color(1.0, 0.72, 0.45, 1.0)))
		return
	var build_status: Dictionary = {"ok": bool(structure.get("can_build", false)), "reason": String(structure.get("build_status", ""))}
	var state: Node = _state()
	if state != null and state.has_method("can_build_palace_structure"):
		build_status = state.call("can_build_palace_structure", structure_id) as Dictionary
	var build_button: Button = Button.new()
	build_button.text = "Build Palace Structure"
	build_button.custom_minimum_size = Vector2(0, 38)
	build_button.add_theme_font_size_override("font_size", 16)
	build_button.disabled = not bool(build_status.get("ok", false))
	build_button.tooltip_text = String(build_status.get("reason", ""))
	build_button.pressed.connect(func() -> void:
		var build_state: Node = _state()
		if build_state != null and build_state.has_method("build_palace_structure"):
			build_state.call("build_palace_structure", structure_id)
		_refresh_all()
	)
	stack.add_child(build_button)
	if not bool(build_status.get("ok", false)):
		stack.add_child(_palace_wrapped_label("Blocked: " + String(build_status.get("reason", "")), 13, Color(1.0, 0.72, 0.45, 1.0)))
	else:
		stack.add_child(_palace_wrapped_label("Construction pays the build cost now. The structure must then be maintained and staffed each Veintena to stay active.", 13, Color(0.72, 0.78, 0.66, 1.0)))

func _palace_format_staff_requirement(staff: Dictionary) -> String:
	if staff.is_empty():
		return "none"
	var parts: Array[String] = []
	for staff_variant: Variant in staff.keys():
		var staff_id: String = String(staff_variant)
		parts.append(_palace_staff_display_name(staff_id) + " " + str(int(staff[staff_variant])))
	return ", ".join(parts)

func _palace_staff_display_name(staff_id: String) -> String:
	match staff_id:
		"tlamacazqueh":
			return "Priests"
		"pipiltin":
			return "Nobles"
		"tlacotin":
			return "Tlacotin"
		"macehualtin":
			return "Macehualtin"
		"tolteca":
			return "Tolteca"
		"yaotequihuaqueh":
			return "Warriors"
		"malli":
			return "Captives"
	return staff_id.replace("_", " ").capitalize()

func _add_palace_paths_not_chosen_panel(parent: VBoxContainer, chosen_id: String) -> void:
	var muted: Array[String] = []
	for route: Dictionary in _palace_probe_routes():
		var route_id: String = String(route.get("id", route.get("god_id", "")))
		if route_id == chosen_id:
			continue
		muted.append(String(route.get("god_name", route_id.capitalize())) + " — not chosen")
	if muted.is_empty():
		return
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.022, 0.024, 0.022, 0.82), Color(0.38, 0.40, 0.34, 0.55), 10))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	margin.add_child(_palace_wrapped_label("Other divine routes sealed for Prototype 0: " + "; ".join(muted) + ".", 15, Color(0.66, 0.68, 0.62, 1.0)))

func _on_palace_route_selected(god_id: String) -> void:
	_selected_palace_route_id = god_id
	_pending_palace_dedication_confirm_id = ""
	_refresh_main_content()
	_refresh_right_panel()

func _on_palace_confirm_dedication_pressed(god_id: String) -> void:
	var state: Node = _state()
	if state == null:
		return
	if state.has_method("dedicate_palace_to_god"):
		state.call("dedicate_palace_to_god", god_id)
	elif state.has_method("set_player_palace_dedicated_god"):
		state.call("set_player_palace_dedicated_god", god_id)
	_selected_palace_route_id = ""
	_pending_palace_dedication_confirm_id = ""
	_refresh_all()

func _palace_route_by_id(god_id: String) -> Dictionary:
	for route: Dictionary in _palace_probe_routes():
		var route_id: String = String(route.get("id", route.get("god_id", "")))
		if route_id == god_id:
			return route
	return {}

func _palace_tree_preview_names(god_id: String) -> Array[String]:
	var tree: Dictionary = {}
	var state: Node = _state()
	if state != null and state.has_method("get_palace_structure_tree_shell"):
		tree = state.call("get_palace_structure_tree_shell", god_id) as Dictionary
	var names: Array[String] = []
	var tiers: Array = tree.get("tiers", []) as Array
	for tier_variant: Variant in tiers:
		if not (tier_variant is Dictionary):
			continue
		var tier: Dictionary = tier_variant as Dictionary
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if structure_variant is Dictionary:
				names.append(String((structure_variant as Dictionary).get("name", "Structure")))
			if names.size() >= 5:
				return names
	return names

func _palace_route_colour(god_id: String) -> Color:
	match god_id:
		"tlaloc":
			return Color(0.32, 0.86, 0.92, 0.96)
		"huitzilopochtli":
			return Color(0.92, 0.36, 0.26, 0.96)
		"tezcatlipoca":
			return Color(0.62, 0.48, 0.88, 0.96)
		"quetzalcoatl":
			return Color(0.52, 0.90, 0.58, 0.96)
	return Color(0.72, 0.62, 0.42, 0.94)

func _palace_route_domain_line(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Rain • Drought • Flood • Harvest Signs"
		"huitzilopochtli":
			return "War • Captives • Sacrifice • Martial Authority"
		"tezcatlipoca":
			return "Scarcity • Intrigue • Rival Pressure • Hidden Power"
		"quetzalcoatl":
			return "Legitimacy • Recognition • Tribute Trust • Palace Order"
	return "Divine authority"

func _palace_route_flavour(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Read the coming pressure of sky, lake and field before rival houses can react."
		"huitzilopochtli":
			return "Formally authorise the house to launch Flower Wars and pursue the war route."
		"tezcatlipoca":
			return "Exploit shortage, fear, ambition and rival weakness through dangerous palace power."
		"quetzalcoatl":
			return "Strengthen the house's credibility before ruler, court and region."
	return "The palace route will define the house's authority."

func _palace_route_seat_glyph(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "WATER SEAT"
		"huitzilopochtli":
			return "WAR SEAT"
		"tezcatlipoca":
			return "MIRROR SEAT"
		"quetzalcoatl":
			return "FEATHER SEAT"
	return "EMPTY ALTAR"

func _palace_label(text: String, font_size: int, colour: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label

func _palace_wrapped_label(text: String, font_size: int, colour: Color) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = false
	label.text = text
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", colour)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

# -----------------------------------------------------------------------------
# Palace navigation probe v0.20.3
# -----------------------------------------------------------------------------

func _build_palace_navigation_probe_reports() -> void:
	var focus_id: String = _current_focus_id()
	match focus_id:
		"prestige":
			_build_palace_prestige_probe_reports()
		"divine_seat":
			_build_palace_divine_seat_probe_reports()
		"authority":
			_build_palace_authority_probe_reports()
		"ruler_demands":
			_build_palace_ruler_demands_probe_reports()
		_:
			_build_palace_overview_probe_reports()

func _build_palace_overview_probe_reports() -> void:
	_add_prestige_estate_score_card()
	var summary: Dictionary = _palace_probe_summary()
	_add_notification("Palace Overview. Level " + str(int(summary.get("palace_level", 1))) + ". Dedication: " + String(summary.get("dedicated_god_name", "None")) + ".")
	_add_notification("Route: " + String(summary.get("route_name", "No dedication")) + ". " + String(summary.get("power_summary", "No palace route has been chosen yet.")))
	_add_notification("Authority status: " + String(summary.get("authority_status", "Palace authority mechanics are not active yet.")))
	_add_notification("Structures: " + str(int(summary.get("built_structure_count", 0))) + " built; " + str(int(summary.get("active_structure_count", 0))) + " active; " + str(int(summary.get("inactive_structure_count", 0))) + " inactive.")
	var staff_summary: Dictionary = summary.get("staff_summary", {}) as Dictionary
	_add_notification(String(staff_summary.get("headline", "No palace staff required yet.")))
	_add_notification("Palace upkeep and staff now resolve on Veintena advance. The Palace → Prestige tab now explains score sources and recent gains. Huitzilopochtli dedication gates attacking Flower Wars; other authority effects and court needs now show a display-only readiness prototype.")

func _build_palace_prestige_probe_reports() -> void:
	_add_prestige_estate_score_card()
	var state: Node = _state()
	if state == null or not state.has_method("get_prestige_summary"):
		_add_notification("Prestige: backend score data is not connected yet.")
		return
	var prestige: Dictionary = state.call("get_prestige_summary") as Dictionary
	var history: Array = prestige.get("prestige_history", []) as Array
	var source_rows: Array[Dictionary] = _prestige_source_rows(history)
	_add_notification("Palace → Prestige: explains why the main score changed, with recent entries and source totals.")
	if source_rows.is_empty():
		_add_notification("Prestige source breakdown: no recorded gains or losses yet.")
	else:
		var parts: Array[String] = []
		var count: int = 0
		for row: Dictionary in source_rows:
			if count >= 4:
				break
			parts.append(_prestige_source_display_name(String(row.get("source_id", "unknown"))) + " " + _prestige_signed_amount(float(row.get("amount", 0.0))))
			count += 1
		_add_notification("Prestige source totals: " + "; ".join(parts) + ".")
	_add_notification("Market trades remain previewed in the Market basket, but the full Prestige history now lives here in the Palace tab.")

func _build_palace_divine_seat_probe_reports() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var dedicated: bool = bool(summary.get("dedicated", false))
	if dedicated:
		_add_notification("Divine Seat: Palace dedicated to " + String(summary.get("dedicated_god_name", "Chosen")) + ".")
		_add_notification("The large palace view now shows palace structures with build costs, maintenance, staff, prerequisites, effect summaries and active/inactive status.")
		_build_palace_not_chosen_routes(summary)
		return
	_add_notification("Divine Seat: choose one palace route in the large centre-left dedication hall.")
	_add_notification("This is permanent for Prototype 0. Select a divine route, review the central route panel, then confirm dedication from the main Palace view.")
	_add_notification("Tlaloc = foresight. Huitzilopochtli = Flower Wars. Tezcatlipoca = scarcity and intrigue. Quetzalcoatl = legitimacy and recognition.")

func _add_palace_dedication_route_card(route: Dictionary) -> void:
	var god_id: String = String(route.get("id", route.get("god_id", "")))
	var god_name: String = String(route.get("god_name", route.get("name", god_id.capitalize())))
	var route_name: String = String(route.get("route_name", route.get("route", "Palace Route")))
	var summary: String = String(route.get("power_summary", ""))
	_add_notification(god_name + " — " + route_name + ". " + summary)
	var state: Node = _state()
	var can_dedicate: bool = bool(route.get("can_dedicate", false))
	var reason: String = String(route.get("dedication_status", ""))
	if state != null and state.has_method("can_dedicate_palace_to_god"):
		var status: Dictionary = state.call("can_dedicate_palace_to_god", god_id) as Dictionary
		can_dedicate = bool(status.get("ok", false))
		reason = String(status.get("reason", reason))
	var button: Button = Button.new()
	button.text = "Dedicate to " + god_name
	button.custom_minimum_size = Vector2(0, 38)
	button.add_theme_font_size_override("font_size", 16)
	button.disabled = not can_dedicate
	button.tooltip_text = reason
	button.pressed.connect(func() -> void:
		_on_palace_dedication_pressed(god_id)
	)
	notification_list.add_child(button)
	if reason != "":
		_add_notification("Dedication status: " + reason)

func _on_palace_dedication_pressed(god_id: String) -> void:
	var state: Node = _state()
	if state == null:
		return
	if state.has_method("dedicate_palace_to_god"):
		state.call("dedicate_palace_to_god", god_id)
	elif state.has_method("set_player_palace_dedicated_god"):
		state.call("set_player_palace_dedicated_god", god_id)
	_refresh_all()

func _build_palace_dedicated_tree_reports(summary: Dictionary) -> void:
	var god_name: String = String(summary.get("dedicated_god_name", "Chosen"))
	var route_name: String = String(summary.get("route_name", "Palace Route"))
	_add_notification("Divine Seat: Palace dedicated to " + god_name + ".")
	_add_notification(route_name + ". " + String(summary.get("power_summary", "")))
	var tree: Dictionary = {}
	if summary.has("structure_tree_shell") and summary["structure_tree_shell"] is Dictionary:
		tree = summary["structure_tree_shell"] as Dictionary
	else:
		var state: Node = _state()
		if state != null and state.has_method("get_palace_structure_tree_shell"):
			tree = state.call("get_palace_structure_tree_shell", String(summary.get("dedicated_god", ""))) as Dictionary
	if tree.is_empty():
		_add_notification("Tree shell not connected yet.")
		return
	_add_notification(String(tree.get("note", "Palace structure construction data.")))
	var tiers: Array = tree.get("tiers", []) as Array
	for tier_variant: Variant in tiers:
		if not (tier_variant is Dictionary):
			continue
		var tier: Dictionary = tier_variant as Dictionary
		_add_notification(String(tier.get("title", "Palace Tier")))
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if not (structure_variant is Dictionary):
				continue
			var structure: Dictionary = structure_variant as Dictionary
			_add_notification("• " + String(structure.get("name", "Structure")) + " — " + String(structure.get("summary", "Future palace structure.")))
	_build_palace_not_chosen_routes(summary)

func _build_palace_not_chosen_routes(summary: Dictionary) -> void:
	var chosen_id: String = String(summary.get("dedicated_god", ""))
	var routes: Array[Dictionary] = _palace_probe_routes()
	var parts: Array[String] = []
	for route: Dictionary in routes:
		var route_id: String = String(route.get("id", route.get("god_id", "")))
		if route_id == chosen_id:
			continue
		parts.append(String(route.get("god_name", route.get("name", route_id.capitalize()))) + " — not chosen")
	if not parts.is_empty():
		_add_notification("Other Divine Routes: " + "; ".join(parts) + ".")

func _build_palace_authority_probe_reports() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var authority: Dictionary = {}
	if summary.has("authority_summary") and summary["authority_summary"] is Dictionary:
		authority = summary["authority_summary"] as Dictionary
	var route_id: String = String(summary.get("dedicated_god", ""))
	if route_id == "":
		_add_notification("No Palace Authority. Dedicate the palace on the Divine Seat tab to unlock a route-specific authority screen.")
		_add_notification("Tlaloc = natural calendar foresight. Huitzilopochtli = Flower Wars authority. Tezcatlipoca = scarcity/intrigue pressure. Quetzalcoatl = legitimacy and palace trust.")
		return
	_add_notification(String(authority.get("headline", String(summary.get("dedicated_god_name", "Chosen")) + " Authority")))
	_add_notification(String(authority.get("body", summary.get("power_summary", ""))))
	if route_id == "tlaloc" and summary.has("tlaloc_forecast") and summary["tlaloc_forecast"] is Dictionary:
		var forecast: Dictionary = summary["tlaloc_forecast"] as Dictionary
		_add_notification("Tlaloc forecast: " + str(int(forecast.get("visible_event_count", 0))) + " visible natural pressures; range " + str(int(forecast.get("forecast_range_veintenas", 0))) + " Veintenas. Information-only prototype.")
	if route_id == "tezcatlipoca" and summary.has("tezcatlipoca_pressure") and summary["tezcatlipoca_pressure"] is Dictionary:
		var pressure: Dictionary = summary["tezcatlipoca_pressure"] as Dictionary
		_add_notification("Tezcatlipoca pressure: " + str(int(pressure.get("visible_market_pressure_count", 0))) + " market readings; " + str(int(pressure.get("visible_rival_pressure_count", 0))) + " rival hooks. Information-only prototype.")
	if route_id == "quetzalcoatl" and summary.has("quetzalcoatl_legitimacy") and summary["quetzalcoatl_legitimacy"] is Dictionary:
		var legitimacy: Dictionary = summary["quetzalcoatl_legitimacy"] as Dictionary
		_add_notification("Quetzalcoatl legitimacy: " + str(int(legitimacy.get("visible_legitimacy_count", 0))) + " legitimacy hooks; " + str(int(legitimacy.get("visible_obligation_count", 0))) + " tribute credibility readings. Information-only prototype.")
	_add_notification("Structures: " + str(int(authority.get("active_structure_count", 0))) + " active; " + str(int(authority.get("inactive_structure_count", 0))) + " inactive. Implemented route effects currently are the Huitzilopochtli Flower War gate, Tlaloc forecast display, Tezcatlipoca pressure display, and Quetzalcoatl legitimacy display.")

func _build_palace_ruler_demands_probe_reports() -> void:
	var summary: Dictionary = _palace_probe_summary()
	var demands: Dictionary = {}
	if summary.has("ruler_demands") and summary["ruler_demands"] is Dictionary:
		demands = summary["ruler_demands"] as Dictionary
	else:
		var state: Node = _state()
		if state != null and state.has_method("get_palace_ruler_demands_summary"):
			demands = state.call("get_palace_ruler_demands_summary") as Dictionary
	if demands.is_empty():
		_add_notification("Court Needs. Backend data is not connected yet.")
		return
	_add_notification(String(demands.get("title", "Current Court Needs")) + ". " + String(demands.get("headline", "Court needs donation prototype active.")))
	_add_notification("Deadline: " + String(demands.get("cycle_window", "Court need cycle timing unavailable.")) + " Urgency: " + String(demands.get("urgency_label", "Time remains")) + ".")
	_add_notification("Prestige from court-need donations this cycle: +" + _format_religion_amount(float(demands.get("total_donated_prestige", 0.0))) + ". Player Prestige: " + _format_religion_amount(float(demands.get("player_prestige", 0.0))) + ".")
	_add_notification(String(demands.get("flavour", "The court needs goods; donations create public prestige.")))
	var rows: Array = demands.get("rows", []) as Array
	for row_variant: Variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant as Dictionary
		var line: String = String(row.get("slot_name", "Need")) + ": " + String(row.get("resource_name", "Good")) + " need marker " + _format_religion_amount(float(row.get("needed_marker", row.get("requested", 0.0)))) + "; free " + _format_religion_amount(float(row.get("free_after_reserves", 0.0))) + "; base value " + _format_religion_amount(float(row.get("base_value", 1.0)))
		if float(row.get("donated_amount", 0.0)) > 0.001:
			line += "; donated " + _format_religion_amount(float(row.get("donated_amount", 0.0))) + " for +" + _format_religion_amount(float(row.get("donated_prestige", 0.0))) + " Prestige"
		_add_notification(line + ".")
	_add_notification(String(demands.get("mechanics_note", "Donations create prestige by base value. Prestige is score only and never spent.")))

func _palace_probe_summary() -> Dictionary:
	var state: Node = _state()
	if state != null and state.has_method("get_palace_summary"):
		return state.call("get_palace_summary") as Dictionary
	return {"palace_level": 1, "dedicated": false, "dedicated_god": "", "dedicated_god_name": "None", "route_name": "No dedication", "power_summary": "Palace backend summary is not connected.", "authority_status": "Not connected.", "built_structure_count": 0}

func _palace_probe_routes() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var state: Node = _state()
	if state != null and state.has_method("get_palace_dedication_routes"):
		var raw_routes: Variant = state.call("get_palace_dedication_routes")
		if raw_routes is Array:
			var route_rows: Array = raw_routes as Array
			for route_variant: Variant in route_rows:
				if route_variant is Dictionary:
					output.append(route_variant as Dictionary)
	return output

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

func _religion_ritual_prestige_value(tier_id: String) -> float:
	match tier_id:
		"minor":
			return 1.0
		"medium":
			return 3.0
		"large":
			return 8.0
	return 0.0

func _religion_shrine_level_prestige_value(level: int) -> float:
	match level:
		2:
			return 5.0
		3:
			return 15.0
		4:
			return 30.0
	return 0.0

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
	stack.add_child(_religion_wrapped_label("Favour roll: +" + str(int(range[0])) + " to +" + str(int(range[1])) + ". Current favour: " + _format_religion_amount(float(_divine_favour.get(god_id, RELIGION_STARTING_FAVOUR))) + "/100.", 16, COLOR_TEAL))
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
	_last_offering_report.clear()
	if state == null or not state.has_method("sacrifice_for_prestige"):
		_last_offering_report.append("Sacrifice failed: backend is not connected.")
		_refresh_all()
		return
	var result_variant: Variant = state.call("sacrifice_for_prestige", sacrifice_id, 1, god_id)
	if result_variant is Dictionary:
		var result: Dictionary = result_variant as Dictionary
		if bool(result.get("ok", false)):
			var favour_gain: float = float(result.get("favour_gain", 0.0))
			if favour_gain > 0.0001 and god_id != "":
				var before: float = float(_divine_favour.get(god_id, RELIGION_STARTING_FAVOUR))
				var after: float = clampf(before + favour_gain, 0.0, 100.0)
				_divine_favour[god_id] = after
				_last_offering_report.append(String(result.get("message", result.get("reason", "Sacrifice resolved."))) + " " + _god_name(god_id) + " favour " + _format_religion_amount(before) + " → " + _format_religion_amount(after) + ".")
			else:
				_last_offering_report.append(String(result.get("message", result.get("reason", "Sacrifice resolved."))))
		else:
			_last_offering_report.append(String(result.get("reason", "Sacrifice failed.")))
	else:
		_last_offering_report.append("Sacrifice resolved.")
	_emit_religion_state_changed()
	_refresh_all()

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
	var prestige_gain: float = _religion_shrine_level_prestige_value(next_level)
	var report_line: String = _god_name(god_id) + " Shrine upgraded to Level " + str(next_level) + ". " + _shrine_level_description(next_level)
	if prestige_gain > 0.0001:
		_award_religion_prestige(prestige_gain, "religion_shrine_level", _god_name(god_id) + " Shrine Level " + str(next_level), {"god_id": god_id, "shrine_level": next_level})
		report_line += " Prestige +" + _format_religion_amount(prestige_gain) + "."
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
	var prestige_gain: float = _religion_ritual_prestige_value(tier_id)
	if prestige_gain > 0.0001:
		_award_religion_prestige(prestige_gain, "religion_ritual", String(data.get("title", "Ritual")) + " for " + _god_name(god_id), {"god_id": god_id, "tier_id": tier_id, "favour_gain": gain})
		report_line += " Prestige +" + _format_religion_amount(prestige_gain) + "."
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
		_add_shrine_report_card("god|" + god_id + "|sacrifices", "Sacrifices", "Captives, priests and Tlacotin can be sacrificed for religious Prestige and favour.", god_id)
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
	var doctrine_id: String = String(row.get("doctrine", "unspecialised"))
	var offence: float = 1.0
	var defence: float = 1.0
	match doctrine_id:
		"eagle":
			offence = 1.0
			defence = 1.2
		"jaguar":
			offence = 1.3
			defence = 1.0
		"otomi":
			offence = 0.8
			defence = 1.5
		"coyote":
			offence = 1.4
			defence = 0.5
		_:
			offence = 1.0
			defence = 1.0
	return {
		"ready": ready,
		"injured": int(row.get("injured", 0)),
		"dead_total": int(row.get("dead_total", 0)),
		"doctrine_name": String(row.get("doctrine_name", doctrine_id.capitalize())),
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
# Full-screen Flower War Event Flow v0.14
# -----------------------------------------------------------------------------

func _open_flower_war_attack_event(option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> void:
	var state: Node = _state()
	if state != null and state.has_method("start_flower_war_attack_event"):
		var hook_result_variant: Variant = state.call("start_flower_war_attack_event", option_id, source_id, context)
		if hook_result_variant is Dictionary:
			var hook_result: Dictionary = hook_result_variant as Dictionary
			if not bool(hook_result.get("ok", false)):
				_last_skill_web_report.clear()
				_last_skill_web_report.append(String(hook_result.get("reason", hook_result.get("message", "Flower War attack event is blocked."))))
				_refresh_all()
				return
	_flower_war_event_option_id = option_id
	_flower_war_event_provisioning_id = "standard"
	_flower_war_event_report.clear()
	_flower_war_event_selected_warbands.clear()
	for warband_id: String in _all_ready_warband_ids():
		_flower_war_event_selected_warbands[warband_id] = true
	_show_flower_war_attack_event_overlay()

func _clear_flower_war_event_overlay() -> void:
	if _flower_war_event_overlay != null and is_instance_valid(_flower_war_event_overlay):
		_flower_war_event_overlay.queue_free()
	_flower_war_event_overlay = null

func _refresh_flower_war_event_overlay() -> void:
	_clear_flower_war_event_overlay()
	_show_flower_war_attack_event_overlay()

func _selected_flower_war_warband_ids() -> Array:
	var selected: Array = []
	for id_variant: Variant in _flower_war_event_selected_warbands.keys():
		var warband_id: String = String(id_variant)
		if bool(_flower_war_event_selected_warbands.get(warband_id, false)):
			selected.append(warband_id)
	return selected

func _all_ready_warband_ids() -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in _barracks_warband_rows():
		var warband_id: String = String(row.get("id", ""))
		if warband_id != "" and int(row.get("ready", row.get("warriors", 0))) > 0:
			ids.append(warband_id)
	return ids

func _show_flower_war_attack_event_overlay() -> void:
	_clear_flower_war_event_overlay()
	var overlay: Control = Control.new()
	overlay.name = "FlowerWarEventOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 250
	add_child(overlay)
	_flower_war_event_overlay = overlay

	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.76)
	overlay.add_child(shade)

	var outer_margin: MarginContainer = MarginContainer.new()
	outer_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 34)
	outer_margin.add_theme_constant_override("margin_top", 28)
	outer_margin.add_theme_constant_override("margin_right", 34)
	outer_margin.add_theme_constant_override("margin_bottom", 28)
	overlay.add_child(outer_margin)

	var event_panel: PanelContainer = PanelContainer.new()
	event_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.045, 0.035, 0.020, 0.96), Color(0.78, 0.58, 0.30, 0.88), 18))
	outer_margin.add_child(event_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	event_panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_build_flower_war_event_header(root)
	_build_flower_war_scale_row(root)

	var selected_ids: Array = _selected_flower_war_warband_ids()
	var preview: Dictionary = _barracks_preview_for_selected_warbands(selected_ids, _flower_war_event_option_id, _flower_war_event_provisioning_id)
	var status: Dictionary = _barracks_can_launch_selected_warbands(selected_ids, _flower_war_event_option_id, _flower_war_event_provisioning_id)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	_build_flower_war_warband_muster_column(body)
	_build_flower_war_provision_column(body, preview, status)
	_build_flower_war_event_footer(root, preview, status)

func _build_flower_war_event_header(parent: VBoxContainer) -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	parent.add_child(header)
	var title_stack: VBoxContainer = VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 2)
	header.add_child(title_stack)
	title_stack.add_child(_barracks_label("FLOWER WAR MUSTER", 34, COLOR_TEXT))
	title_stack.add_child(_barracks_wrapped_label("The drums sound across the estate. Choose which warbands march and how well the expedition is provisioned.", 17, COLOR_MUTED))
	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(96, 38)
	close_button.add_theme_font_size_override("font_size", 15)
	close_button.pressed.connect(func() -> void:
		_clear_flower_war_event_overlay()
	)
	header.add_child(close_button)

func _build_flower_war_scale_row(parent: VBoxContainer) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	for option: Dictionary in _barracks_flower_options():
		var option_id: String = String(option.get("id", "minor"))
		var button: Button = Button.new()
		button.text = String(option.get("name", option_id.capitalize()))
		button.toggle_mode = true
		button.button_pressed = option_id == _flower_war_event_option_id
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(func() -> void:
			_flower_war_event_option_id = option_id
			_refresh_flower_war_event_overlay()
		)
		row.add_child(button)

func _build_flower_war_warband_muster_column(parent: HBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.038, 0.036, 0.86), Color(0.50, 0.82, 0.74, 0.48), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Warbands to Send", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("All warbands with ready warriors are selected by default. Injured warriors are shown but do not fight.", 15, COLOR_MUTED))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for row: Dictionary in _barracks_warband_rows():
		_add_flower_war_event_warband_card(list, row)

func _add_flower_war_event_warband_card(parent: VBoxContainer, row: Dictionary) -> void:
	var warband_id: String = String(row.get("id", ""))
	var ready: int = int(row.get("ready", row.get("warriors", 0)))
	var selected: bool = bool(_flower_war_event_selected_warbands.get(warband_id, false)) and ready > 0
	var stats: Dictionary = _warband_combat_stats(row)
	var border: Color = Color(0.50, 0.82, 0.74, 0.58) if selected else Color(0.40, 0.42, 0.38, 0.45)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.050, 0.046, 0.82), border, 10))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var label_stack: VBoxContainer = VBoxContainer.new()
	label_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_stack.add_theme_constant_override("separation", 2)
	top.add_child(label_stack)
	label_stack.add_child(_barracks_label(String(row.get("name", "Warband")), 20, COLOR_TEXT))
	label_stack.add_child(_barracks_wrapped_label("Doctrine: " + String(stats.get("doctrine_name", "Unspecialised")) + " | Ready " + str(ready) + " | Injured ✚ " + str(int(stats.get("injured", 0))), 14, COLOR_TEAL))
	var toggle: Button = Button.new()
	toggle.text = "Send" if selected else "Stand Down"
	toggle.toggle_mode = true
	toggle.button_pressed = selected
	toggle.disabled = ready <= 0
	toggle.custom_minimum_size = Vector2(116, 38)
	toggle.add_theme_font_size_override("font_size", 15)
	toggle.pressed.connect(func() -> void:
		_flower_war_event_selected_warbands[warband_id] = not selected
		_refresh_flower_war_event_overlay()
	)
	top.add_child(toggle)
	root.add_child(_barracks_wrapped_label("Effective offence " + _format_float(float(stats.get("effective_offence", 0.0))) + " | effective defence " + _format_float(float(stats.get("effective_defence", 0.0))) + ".", 14, COLOR_MUTED))
	if int(stats.get("injured", 0)) > 0:
		root.add_child(_barracks_wrapped_label("✚ Injured warriors are not fighting and will recover next Veintena.", 13, Color(1.0, 0.74, 0.40, 1.0)))
	if ready <= 0:
		root.add_child(_barracks_wrapped_label("Cannot march: no ready warriors. Injured warriors must recover first.", 14, Color(1.0, 0.74, 0.40, 1.0)))

func _build_flower_war_provision_column(parent: HBoxContainer, preview: Dictionary, status: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.030, 0.020, 0.88), Color(0.78, 0.58, 0.30, 0.58), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Provisions", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Provisioning applies to the whole attacking expedition. Defence events do not use provisioning.", 15, COLOR_MUTED))
	for provisioning_id: String in ["standard", "well", "royal"]:
		_add_flower_war_provision_card(stack, provisioning_id)
	stack.add_child(_barracks_label("Muster Summary", 22, COLOR_TEXT))
	if bool(preview.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Outcome preview: " + String(preview.get("result", "Unknown")) + ".", 16, COLOR_TEAL))
		stack.add_child(_barracks_wrapped_label("Selected warbands: " + str(int(preview.get("participating_warband_count", 0))) + ". Ready warriors: " + str(int(preview.get("warriors_committed", 0))) + ".", 15, COLOR_MUTED))
		stack.add_child(_barracks_wrapped_label("Effective offence " + _format_float(float(preview.get("attacker_attack", 0.0))) + " | effective defence " + _format_float(float(preview.get("attacker_defence", 0.0))) + ".", 15, COLOR_MUTED))
		stack.add_child(_barracks_wrapped_label("Cost: " + _flower_war_event_cost_text(preview.get("provisioning_cost", {}) as Dictionary) + ".", 15, COLOR_MUTED))
	else:
		stack.add_child(_barracks_wrapped_label("Preview unavailable: " + String(preview.get("reason", "No selected warbands.")), 16, Color(1.0, 0.74, 0.40, 1.0)))
	if not bool(status.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Blocked: " + String(status.get("reason", "Cannot launch.")), 15, Color(1.0, 0.74, 0.40, 1.0)))

func _add_flower_war_provision_card(parent: VBoxContainer, provisioning_id: String) -> void:
	var selected: bool = provisioning_id == _flower_war_event_provisioning_id
	var selected_ids: Array = _selected_flower_war_warband_ids()
	var preview: Dictionary = _barracks_preview_for_selected_warbands(selected_ids, _flower_war_event_option_id, provisioning_id)
	var title: String = provisioning_id.capitalize()
	match provisioning_id:
		"standard":
			title = "Standard Provisioning"
		"well":
			title = "Well-Provisioned"
		"royal":
			title = "Royal Provisioning"
	var button: Button = Button.new()
	button.toggle_mode = true
	button.button_pressed = selected
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 54)
	button.add_theme_font_size_override("font_size", 15)
	var cost_text: String = "Cost unavailable"
	if bool(preview.get("ok", false)):
		cost_text = _flower_war_event_cost_text(preview.get("provisioning_cost", {}) as Dictionary)
	button.text = title + "\n" + cost_text
	button.tooltip_text = "Choose " + title + "."
	button.pressed.connect(func() -> void:
		_flower_war_event_provisioning_id = provisioning_id
		_refresh_flower_war_event_overlay()
	)
	parent.add_child(button)

func _build_flower_war_event_footer(parent: VBoxContainer, preview: Dictionary, status: Dictionary) -> void:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 10)
	parent.add_child(footer)
	var summary: Label = _barracks_wrapped_label("Deaths, captives, loot and XP will be shown in the full Flower War Return after resolution.", 15, COLOR_MUTED)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(summary)
	var cancel_button: Button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(120, 42)
	cancel_button.add_theme_font_size_override("font_size", 16)
	cancel_button.pressed.connect(func() -> void:
		_clear_flower_war_event_overlay()
	)
	footer.add_child(cancel_button)
	var begin_button: Button = Button.new()
	begin_button.text = "Begin Flower War"
	begin_button.custom_minimum_size = Vector2(190, 42)
	begin_button.add_theme_font_size_override("font_size", 16)
	begin_button.disabled = not bool(status.get("ok", false))
	begin_button.tooltip_text = String(status.get("reason", ""))
	begin_button.pressed.connect(func() -> void:
		_resolve_flower_war_attack_event()
	)
	footer.add_child(begin_button)

func _resolve_flower_war_attack_event() -> void:
	var state: Node = _state()
	if state == null:
		return
	var selected_ids: Array = _selected_flower_war_warband_ids()
	var report: Dictionary = {}
	if state.has_method("launch_flower_war_with_selected_warbands"):
		var raw: Variant = state.call("launch_flower_war_with_selected_warbands", selected_ids, _flower_war_event_option_id, _flower_war_event_provisioning_id)
		if raw is Dictionary:
			report = raw as Dictionary
	elif state.has_method("launch_flower_war_with_all_warbands"):
		var fallback_raw: Variant = state.call("launch_flower_war_with_all_warbands", _flower_war_event_option_id, _flower_war_event_provisioning_id)
		if fallback_raw is Dictionary:
			report = fallback_raw as Dictionary
	if report.is_empty():
		report = {"ok": false, "reason": "Flower War resolver is not available."}
	_flower_war_event_report = report.duplicate(true)
	_show_flower_war_return_event_overlay(report)

func _open_flower_war_defence_event(option_id: String = "standard", source_id: String = "rival", context: Dictionary = {}) -> void:
	var state: Node = _state()
	if state != null and state.has_method("start_flower_war_defence_event"):
		state.call("start_flower_war_defence_event", option_id, source_id, context)
	_flower_war_event_option_id = option_id
	_flower_war_defence_strategy_id = "balanced"
	_flower_war_event_report.clear()
	_show_flower_war_defence_event_overlay()

func _refresh_flower_war_defence_event_overlay() -> void:
	_clear_flower_war_event_overlay()
	_show_flower_war_defence_event_overlay()

func _show_flower_war_defence_event_overlay() -> void:
	_clear_flower_war_event_overlay()
	var overlay: Control = Control.new()
	overlay.name = "FlowerWarDefenceEventOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 250
	add_child(overlay)
	_flower_war_event_overlay = overlay

	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.76)
	overlay.add_child(shade)

	var outer_margin: MarginContainer = MarginContainer.new()
	outer_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 34)
	outer_margin.add_theme_constant_override("margin_top", 28)
	outer_margin.add_theme_constant_override("margin_right", 34)
	outer_margin.add_theme_constant_override("margin_bottom", 28)
	overlay.add_child(outer_margin)

	var event_panel: PanelContainer = PanelContainer.new()
	event_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.038, 0.052, 0.96), Color(0.36, 0.68, 0.92, 0.88), 18))
	outer_margin.add_child(event_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	event_panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_build_flower_war_defence_event_header(root)
	_build_flower_war_defence_scale_row(root)

	var preview: Dictionary = _barracks_preview_for_defence(_flower_war_event_option_id, _flower_war_defence_strategy_id)
	var status: Dictionary = _barracks_can_resolve_defence(_flower_war_event_option_id, _flower_war_defence_strategy_id)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	_build_flower_war_defending_warbands_column(body)
	_build_flower_war_defence_strategy_column(body, preview, status)
	_build_flower_war_defence_event_footer(root, preview, status)

func _build_flower_war_defence_event_header(parent: VBoxContainer) -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	parent.add_child(header)
	var title_stack: VBoxContainer = VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 2)
	header.add_child(title_stack)
	title_stack.add_child(_barracks_label("FLOWER WAR DEFENCE", 34, COLOR_TEXT))
	title_stack.add_child(_barracks_wrapped_label("A rival house has come seeking captives and glory. Choose how your warbands answer.", 17, COLOR_MUTED))
	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(96, 38)
	close_button.add_theme_font_size_override("font_size", 15)
	close_button.pressed.connect(func() -> void:
		_clear_flower_war_event_overlay()
	)
	header.add_child(close_button)

func _build_flower_war_defence_scale_row(parent: VBoxContainer) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	for option: Dictionary in _barracks_flower_options():
		var option_id: String = String(option.get("id", "minor"))
		var button: Button = Button.new()
		button.text = String(option.get("name", option_id.capitalize()))
		button.toggle_mode = true
		button.button_pressed = option_id == _flower_war_event_option_id
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(func() -> void:
			_flower_war_event_option_id = option_id
			_refresh_flower_war_defence_event_overlay()
		)
		row.add_child(button)

func _build_flower_war_defending_warbands_column(parent: HBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.038, 0.036, 0.86), Color(0.50, 0.82, 0.74, 0.48), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Warbands Defending", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Defensive Flower Wars commit all ready warbands. There is no provisioning choice on defence.", 15, COLOR_MUTED))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for row: Dictionary in _barracks_warband_rows():
		_add_flower_war_defending_warband_card(list, row)

func _add_flower_war_defending_warband_card(parent: VBoxContainer, row: Dictionary) -> void:
	var ready: int = int(row.get("ready", row.get("warriors", 0)))
	var stats: Dictionary = _warband_combat_stats(row)
	var border: Color = Color(0.50, 0.82, 0.74, 0.58) if ready > 0 else Color(0.40, 0.42, 0.38, 0.45)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.050, 0.046, 0.82), border, 10))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)
	root.add_child(_barracks_label(String(row.get("name", "Warband")), 20, COLOR_TEXT))
	root.add_child(_barracks_wrapped_label("Doctrine: " + String(stats.get("doctrine_name", "Unspecialised")) + " | Ready " + str(ready) + " | Injured ✚ " + str(int(stats.get("injured", 0))), 14, COLOR_TEAL))
	root.add_child(_barracks_wrapped_label("Effective offence " + _format_float(float(stats.get("effective_offence", 0.0))) + " | effective defence " + _format_float(float(stats.get("effective_defence", 0.0))) + ".", 14, COLOR_MUTED))
	if ready <= 0:
		root.add_child(_barracks_wrapped_label("Cannot defend: no ready warriors.", 14, Color(1.0, 0.74, 0.40, 1.0)))

func _build_flower_war_defence_strategy_column(parent: HBoxContainer, preview: Dictionary, status: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.030, 0.020, 0.88), Color(0.78, 0.58, 0.30, 0.58), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	stack.add_child(_barracks_label("Defensive Strategy", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Choose one posture. Balanced is safe; the other two trade offence and defence against each other.", 15, COLOR_MUTED))
	for strategy: Dictionary in _barracks_defence_strategies():
		_add_flower_war_defence_strategy_card(stack, strategy)
	stack.add_child(_barracks_label("Defence Summary", 22, COLOR_TEXT))
	if bool(preview.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Outcome preview: " + String(preview.get("result", "Unknown")) + ".", 16, COLOR_TEAL))
		stack.add_child(_barracks_wrapped_label("Defending warbands: " + str(int(preview.get("participating_warband_count", 0))) + ". Ready warriors: " + str(int(preview.get("warriors_committed", 0))) + ".", 15, COLOR_MUTED))
		stack.add_child(_barracks_wrapped_label("Defence Off x" + _format_float(float(preview.get("offence_multiplier", 1.0))) + " | Def x" + _format_float(float(preview.get("defence_multiplier", 1.0))) + ". Enemy casualties " + str(int(preview.get("enemy_casualties", 0))) + "; expected losses " + str(int(preview.get("defender_casualties", preview.get("attacker_casualties", 0)))) + ".", 15, COLOR_MUTED))
	else:
		stack.add_child(_barracks_wrapped_label("Preview unavailable: " + String(preview.get("reason", "No defending warbands.")), 16, Color(1.0, 0.74, 0.40, 1.0)))
	if not bool(status.get("ok", false)):
		stack.add_child(_barracks_wrapped_label("Blocked: " + String(status.get("reason", "Cannot resolve defence.")), 15, Color(1.0, 0.74, 0.40, 1.0)))

func _add_flower_war_defence_strategy_card(parent: VBoxContainer, strategy: Dictionary) -> void:
	var strategy_id: String = String(strategy.get("id", "balanced"))
	var selected: bool = strategy_id == _flower_war_defence_strategy_id
	var button: Button = Button.new()
	button.toggle_mode = true
	button.button_pressed = selected
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 70)
	button.add_theme_font_size_override("font_size", 15)
	button.text = String(strategy.get("name", "Strategy")) + "\nOff x" + _format_float(float(strategy.get("offence_multiplier", 1.0))) + " | Def x" + _format_float(float(strategy.get("defence_multiplier", 1.0)))
	button.tooltip_text = String(strategy.get("description", ""))
	button.pressed.connect(func() -> void:
		_flower_war_defence_strategy_id = strategy_id
		_refresh_flower_war_defence_event_overlay()
	)
	parent.add_child(button)

func _build_flower_war_defence_event_footer(parent: VBoxContainer, preview: Dictionary, status: Dictionary) -> void:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 10)
	parent.add_child(footer)
	var summary: Label = _barracks_wrapped_label("Defensive Flower Wars use all ready warbands, no provisions, and one strategy choice. Deaths and injuries appear in the return event.", 15, COLOR_MUTED)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(summary)
	var cancel_button: Button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(120, 42)
	cancel_button.add_theme_font_size_override("font_size", 16)
	cancel_button.pressed.connect(func() -> void:
		_clear_flower_war_event_overlay()
	)
	footer.add_child(cancel_button)
	var resolve_button: Button = Button.new()
	resolve_button.text = "Resolve Defence"
	resolve_button.custom_minimum_size = Vector2(190, 42)
	resolve_button.add_theme_font_size_override("font_size", 16)
	resolve_button.disabled = not bool(status.get("ok", false))
	resolve_button.tooltip_text = String(status.get("reason", ""))
	resolve_button.pressed.connect(func() -> void:
		_resolve_flower_war_defence_event()
	)
	footer.add_child(resolve_button)

func _resolve_flower_war_defence_event() -> void:
	var state: Node = _state()
	if state == null:
		return
	var report: Dictionary = {}
	if state.has_method("resolve_flower_war_defence"):
		var raw: Variant = state.call("resolve_flower_war_defence", _flower_war_event_option_id, _flower_war_defence_strategy_id)
		if raw is Dictionary:
			report = raw as Dictionary
	if report.is_empty():
		report = {"ok": false, "reason": "Flower War defence resolver is not available.", "war_direction": "defence"}
	_flower_war_event_report = report.duplicate(true)
	_show_flower_war_return_event_overlay(report)

func _show_flower_war_return_event_overlay(report: Dictionary) -> void:
	_clear_flower_war_event_overlay()
	var overlay: Control = Control.new()
	overlay.name = "FlowerWarReturnOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 250
	add_child(overlay)
	_flower_war_event_overlay = overlay

	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.78)
	overlay.add_child(shade)

	var outer_margin: MarginContainer = MarginContainer.new()
	outer_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 38)
	outer_margin.add_theme_constant_override("margin_top", 30)
	outer_margin.add_theme_constant_override("margin_right", 38)
	outer_margin.add_theme_constant_override("margin_bottom", 30)
	overlay.add_child(outer_margin)

	var event_panel: PanelContainer = PanelContainer.new()
	event_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.045, 0.035, 0.020, 0.97), Color(0.78, 0.58, 0.30, 0.90), 18))
	outer_margin.add_child(event_panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	event_panel.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var ok: bool = bool(report.get("ok", false))
	var direction: String = String(report.get("war_direction", "attack"))
	var return_title: String = "FLOWER WAR RETURN"
	if direction == "defence":
		return_title = "FLOWER WAR DEFENCE RETURN"
	root.add_child(_barracks_label(return_title, 34, COLOR_TEXT))
	if not ok:
		root.add_child(_barracks_wrapped_label("The muster failed: " + String(report.get("reason", "unknown reason")) + ".", 20, Color(1.0, 0.74, 0.40, 1.0)))
		_build_flower_war_return_footer(root)
		return
	root.add_child(_barracks_label(String(report.get("result", "Unknown")).to_upper(), 30, COLOR_TEAL))
	if direction == "defence":
		root.add_child(_barracks_wrapped_label("Strategy: " + String(report.get("defence_strategy_name", "Balanced Defence")) + " | Enemy casualties: " + str(int(report.get("enemy_casualties", 0))) + " | Prestige " + _format_signed_prestige_ui(float(report.get("prestige_gain", 0.0))) + " | Warriors defending: " + str(int(report.get("warriors_committed", 0))) + " | Returned ready: " + str(int(report.get("warriors_returned", 0))), 18, COLOR_MUTED))
	else:
		root.add_child(_barracks_wrapped_label("Captives taken: " + str(int(report.get("captives", 0))) + " | Loot value: " + _format_float(float(report.get("loot_value", 0.0))) + " | Prestige " + _format_signed_prestige_ui(float(report.get("prestige_gain", 0.0))) + " | Warriors sent: " + str(int(report.get("warriors_committed", 0))) + " | Returned ready: " + str(int(report.get("warriors_returned", 0))), 18, COLOR_MUTED))

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	_build_flower_war_return_warband_cards(body, report)
	_build_flower_war_return_spoils_panel(body, report)
	_build_flower_war_return_footer(root)

func _build_flower_war_return_warband_cards(parent: HBoxContainer, report: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.018, 0.038, 0.036, 0.88), Color(0.50, 0.82, 0.74, 0.50), 12))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)
	stack.add_child(_barracks_label("Warbands Returned", 24, COLOR_TEXT))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	stack.add_child(grid)
	var reports: Array = report.get("participant_reports", []) as Array
	if reports.is_empty():
		grid.add_child(_barracks_wrapped_label("No per-warband report was recorded.", 17, COLOR_MUTED))
		return
	for participant_variant: Variant in reports:
		var participant: Dictionary = participant_variant as Dictionary
		_add_flower_war_return_single_warband_card(grid, participant)

func _add_flower_war_return_single_warband_card(parent: GridContainer, participant: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.050, 0.046, 0.82), Color(0.50, 0.82, 0.74, 0.46), 10))
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
	stack.add_child(_barracks_label(String(participant.get("name", "Warband")), 19, COLOR_TEXT))
	var sent: int = int(participant.get("sent", participant.get("committed", 0)))
	var returned_ready: int = int(participant.get("returned_ready", max(0, sent - int(participant.get("casualties", 0)))))
	stack.add_child(_barracks_wrapped_label("Sent: " + str(sent), 15, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Returned ready: " + str(returned_ready), 15, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label("✚ Injured: " + str(int(participant.get("injured", 0))), 15, Color(0.80, 1.0, 0.88, 1.0)))
	stack.add_child(_barracks_wrapped_label("Dead: " + str(int(participant.get("dead", 0))), 15, Color(0.72, 0.70, 0.66, 1.0)))
	stack.add_child(_barracks_wrapped_label("XP: +" + str(int(participant.get("xp_gained", 0))), 15, COLOR_TEAL))

func _build_flower_war_return_spoils_panel(parent: HBoxContainer, report: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.030, 0.020, 0.88), Color(0.78, 0.58, 0.30, 0.58), 12))
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
	stack.add_child(_barracks_label("Spoils & Consequences", 24, COLOR_TEXT))
	stack.add_child(_barracks_wrapped_label("Captives: " + str(int(report.get("captives", 0))), 18, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label("Loot: " + _flower_war_event_loot_text(report.get("loot", {}) as Dictionary), 16, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Total injured: ✚ " + str(int(report.get("attacker_injured", 0))) + ". Dead: " + str(int(report.get("attacker_dead", 0))) + ".", 16, COLOR_MUTED))
	stack.add_child(_barracks_wrapped_label("Prestige: " + _format_signed_prestige_ui(float(report.get("prestige_gain", 0.0))), 18, Color(1.0, 0.82, 0.44, 1.0)))
	var prestige_breakdown: Dictionary = report.get("prestige_breakdown", {}) as Dictionary
	var prestige_lines: Array = prestige_breakdown.get("lines", []) as Array
	for prestige_line_variant: Variant in prestige_lines:
		stack.add_child(_barracks_wrapped_label("• " + String(prestige_line_variant), 14, COLOR_MUTED))
	var level_reports: Array = report.get("level_reports", []) as Array
	if not level_reports.is_empty():
		for line_variant: Variant in level_reports:
			stack.add_child(_barracks_wrapped_label(String(line_variant), 15, COLOR_TEAL))
	stack.add_child(_barracks_wrapped_label("The dead are recorded here and in war reports, not on normal warband cards. Injured warriors remain out of the ready pool until the next Veintena advance.", 15, COLOR_MUTED))

func _build_flower_war_return_footer(parent: VBoxContainer) -> void:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 10)
	parent.add_child(footer)
	var note: Label = _barracks_wrapped_label("This return is archived under Barracks → War Returns as a codex war report.", 15, COLOR_MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)
	var continue_button: Button = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(150, 42)
	continue_button.add_theme_font_size_override("font_size", 16)
	continue_button.pressed.connect(func() -> void:
		_clear_flower_war_event_overlay()
		_refresh_all()
	)
	footer.add_child(continue_button)

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

	var canvas: WarbandSkillWebCanvas = WarbandSkillWebCanvas.new()
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
			return "Quetzalcoatl closes the ordinary year through transition, order, legitimacy and ceremonial donation."
	return "Calendar planning pressure."

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
