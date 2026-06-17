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
	if current_location_id == "warriors":
		_build_barracks_reports()
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
			_add_notification(String(option.get("name", "War")) + ": " + String(preview.get("result", "Preview unavailable")) + "; committed " + str(int(preview.get("committed_warriors", preview.get("warriors_committed", 0)))) + "; captives " + str(int(preview.get("captives", 0))) + "; losses " + str(int(preview.get("attacker_losses", preview.get("attacker_casualties", 0)))) + "; XP +" + str(int(preview.get("xp_gained", 0))) + ".")
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
	_add_notification("Prestige from Flower Wars is pending calibration; no invented values are applied.")

func _build_barracks_overview_panel(parent: VBoxContainer) -> void:
	var summary: Dictionary = _barracks_summary()
	parent.add_child(_barracks_label("Barracks Overview", 31, COLOR_TEXT))
	parent.add_child(_barracks_wrapped_label("The Barracks now manages persistent warbands. Flower Wars commit every ready warband together, distribute casualties and XP across participating warbands. Palace-gate infrastructure exists, but the gate is temporarily inactive until the Palace screen is implemented.", 20, COLOR_MUTED))
	parent.add_child(_barracks_wrapped_label("Warriors: " + str(int(summary.get("warriors", 0))) + " / " + str(int(summary.get("capacity", 0))) + " capacity. Free capacity: " + str(int(summary.get("free_capacity", 0))) + ".", 22, COLOR_TEAL))
	parent.add_child(_barracks_wrapped_label("Weapons in Storehouse: " + _format_float(float(summary.get("weapons", 0.0))) + ". Captives held: " + str(int(summary.get("captives", 0))) + ".", 20, COLOR_MUTED))
	parent.add_child(_barracks_wrapped_label("Use Flower Wars to choose the scale, selected warbands and provisions. Injured warriors do not fight and recover on the next Veintena advance. Prestige remains pending calibration.", 19, COLOR_MUTED))

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
		state.call("start_flower_war_attack_event", option_id, source_id, context)
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
		root.add_child(_barracks_wrapped_label("Strategy: " + String(report.get("defence_strategy_name", "Balanced Defence")) + " | Enemy casualties: " + str(int(report.get("enemy_casualties", 0))) + " | Warriors defending: " + str(int(report.get("warriors_committed", 0))) + " | Returned ready: " + str(int(report.get("warriors_returned", 0))), 18, COLOR_MUTED))
	else:
		root.add_child(_barracks_wrapped_label("Captives taken: " + str(int(report.get("captives", 0))) + " | Loot value: " + _format_float(float(report.get("loot_value", 0.0))) + " | Warriors sent: " + str(int(report.get("warriors_committed", 0))) + " | Returned ready: " + str(int(report.get("warriors_returned", 0))), 18, COLOR_MUTED))

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
	parent.add_child(_barracks_wrapped_label("Flower Wars now open as full-screen ceremonial events. Choose a scale here, then muster warbands and provisions in the event screen.", 19, COLOR_MUTED))
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
	stack.add_child(_barracks_wrapped_label("Prestige: pending calibration. Skill Web specialism sets doctrine; other node effects are not connected to combat yet.", 15, Color(1.0, 0.74, 0.40, 1.0)))
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
	_add_war_return_chip(summary, "Prestige", "pending", Color(1.0, 0.74, 0.40, 1.0))

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
	stack.add_child(_barracks_wrapped_label("Prestige: pending calibration. No prestige value is awarded by this patch.", 15, Color(1.0, 0.74, 0.40, 1.0)))
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
		return "Palace gate inactive: Flower Wars are currently open. Future implementation will require a Huitzilopochtli palace."
	if _barracks_has_war_god_palace():
		return "War palace gate open: Palace dedicated to Huitzilopochtli."
	if dedicated == "":
		return "Flower Wars locked: Requires Palace dedicated to Huitzilopochtli."
	return "Flower Wars locked: current palace dedication is " + dedicated.capitalize() + "; requires Huitzilopochtli."


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
			lines.append("Loot value " + _format_float(float(report.get("loot_value", 0.0))) + ". Prestige pending calibration.")
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
