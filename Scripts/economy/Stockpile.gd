# Stockpile.gd
# Godot 4.x
# Project path: res://Scripts/economy/Stockpile.gd
#
# Runtime stockpile structure.
# This is live state, not static balance data.
class_name Stockpile
extends RefCounted

var good_id: String = ""
var stored: float = 0.0
var incoming_flows: Array[GoodsFlow] = []
var outgoing_flows: Array[GoodsFlow] = []
var reservations: Array[Reservation] = []

func _init(new_good_id: String = "", new_stored: float = 0.0) -> void:
	good_id = new_good_id
	stored = maxf(0.0, new_stored)

func clear_turn_data() -> void:
	incoming_flows.clear()
	outgoing_flows.clear()
	reservations.clear()

func add_flow(flow: GoodsFlow) -> void:
	if flow.good_id != good_id:
		return
	if flow.direction == "outgoing":
		outgoing_flows.append(flow)
	else:
		incoming_flows.append(flow)

func add_reservation(reservation: Reservation) -> void:
	if reservation.good_id != good_id:
		return
	reservations.append(reservation)

func incoming_amount() -> float:
	var total: float = 0.0
	for flow: GoodsFlow in incoming_flows:
		total += flow.amount
	return total

func outgoing_amount() -> float:
	var total: float = 0.0
	for flow: GoodsFlow in outgoing_flows:
		total += flow.amount
	return total

func net_change() -> float:
	return incoming_amount() - outgoing_amount()

func projected_amount() -> float:
	return maxf(0.0, stored + net_change())

func reserved_amount() -> float:
	var total: float = 0.0
	for reservation: Reservation in reservations:
		total += reservation.amount
	return total

func free_amount() -> float:
	return maxf(0.0, stored - reserved_amount())

func projected_free_amount() -> float:
	return maxf(0.0, projected_amount() - reserved_amount())

func apply_turn() -> void:
	stored = projected_amount()

func incoming_lines() -> Array[String]:
	var lines: Array[String] = []
	for flow: GoodsFlow in incoming_flows:
		lines.append(flow.to_line())
	return lines

func outgoing_lines() -> Array[String]:
	var lines: Array[String] = []
	for flow: GoodsFlow in outgoing_flows:
		lines.append(flow.to_line())
	return lines

func reservation_lines() -> Array[String]:
	var sorted_reservations: Array[Reservation] = reservations.duplicate()
	sorted_reservations.sort_custom(_sort_reservations_desc)
	var lines: Array[String] = []
	for reservation: Reservation in sorted_reservations:
		lines.append(reservation.to_line())
	return lines

func pressure_label() -> String:
	if stored <= 0.0 and incoming_amount() <= outgoing_amount():
		return "Absent"
	if stored < reserved_amount():
		return "Crisis"
	if stored <= reserved_amount() + outgoing_amount():
		return "Tight"
	if incoming_amount() < outgoing_amount():
		return "Falling"
	return "Comfortable"

func to_save_dictionary() -> Dictionary:
	return {
		"good_id": good_id,
		"stored": stored
	}

static func _sort_reservations_desc(a: Reservation, b: Reservation) -> bool:
	return a.priority > b.priority
