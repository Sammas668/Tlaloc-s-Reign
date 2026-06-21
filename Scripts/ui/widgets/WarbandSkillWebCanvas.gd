# WarbandSkillWebCanvas.gd
# Godot 4.x
# Project path: res://Scripts/ui/widgets/WarbandSkillWebCanvas.gd
#
# Extracted from GameScreenMarketOverviewPatch.gd as the first safe wrapper-shrink patch.
# This widget owns only skill-web drawing and input; gameplay rules remain in backend systems.
class_name WarbandSkillWebCanvas
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

