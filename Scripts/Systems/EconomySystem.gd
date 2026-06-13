# EconomySystem.gd
# Godot 4.x
# Project path: res://Scripts/systems/EconomySystem.gd
#
# Calculates estate stockpile flows, reservations and display rows.
# Later, population/building/construction/ritual systems should feed this system with flows.
class_name EconomySystem
extends RefCounted

func rebuild_estate_flows(estate_stockpiles: Dictionary, flow_sources: Dictionary) -> void:
	for stockpile_variant: Variant in estate_stockpiles.values():
		var stockpile: Stockpile = stockpile_variant as Stockpile
		if stockpile:
			stockpile.clear_turn_data()

	_add_flows(estate_stockpiles, flow_sources.get("incoming", []) as Array, "incoming")
	_add_flows(estate_stockpiles, flow_sources.get("outgoing", []) as Array, "outgoing")
	_add_reservations(estate_stockpiles, flow_sources.get("reservations", []) as Array)

func get_estate_stockpile_rows(estate_stockpiles: Dictionary, static_data: StaticData) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for good_id: String in static_data.resource_order:
		if not estate_stockpiles.has(good_id):
			continue

		var stockpile: Stockpile = estate_stockpiles[good_id] as Stockpile
		var row: Dictionary = static_data.get_resource_definition(good_id)
		row["stored"] = stockpile.stored
		row["incoming"] = stockpile.incoming_amount()
		row["outgoing"] = stockpile.outgoing_amount()
		row["net"] = stockpile.net_change()
		row["projected"] = stockpile.projected_amount()
		row["reserved"] = stockpile.reserved_amount()
		row["free"] = stockpile.free_amount()
		row["projected_free"] = stockpile.projected_free_amount()
		row["pressure"] = stockpile.pressure_label()
		row["incoming_breakdown"] = _default_if_empty(stockpile.incoming_lines(), "No incoming flow")
		row["outgoing_breakdown"] = _default_if_empty(stockpile.outgoing_lines(), "No outgoing flow")
		row["reserved_breakdown"] = _default_if_empty(stockpile.reservation_lines(), "No reserve committed")
		rows.append(row)

	return rows

func apply_estate_turn(estate_stockpiles: Dictionary) -> void:
	for stockpile_variant: Variant in estate_stockpiles.values():
		var stockpile: Stockpile = stockpile_variant as Stockpile
		if stockpile:
			stockpile.apply_turn()

func _add_flows(estate_stockpiles: Dictionary, source_rows: Array, direction: String) -> void:
	for row_variant: Variant in source_rows:
		var row: Dictionary = row_variant as Dictionary
		var flow: GoodsFlow = GoodsFlow.from_dictionary(row, direction)
		if estate_stockpiles.has(flow.good_id):
			var stockpile: Stockpile = estate_stockpiles[flow.good_id] as Stockpile
			stockpile.add_flow(flow)

func _add_reservations(estate_stockpiles: Dictionary, reservation_rows: Array) -> void:
	for row_variant: Variant in reservation_rows:
		var row: Dictionary = row_variant as Dictionary
		var reservation: Reservation = Reservation.from_dictionary(row)
		if estate_stockpiles.has(reservation.good_id):
			var stockpile: Stockpile = estate_stockpiles[reservation.good_id] as Stockpile
			stockpile.add_reservation(reservation)

func _default_if_empty(lines: Array[String], fallback: String) -> Array[String]:
	if lines.is_empty():
		return [fallback]
	return lines
