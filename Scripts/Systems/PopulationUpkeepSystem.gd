# PopulationUpkeepSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/PopulationUpkeepSystem.gd
#
# Owns population-upkeep rules for the live campaign state.
#
# TRGameState / future CampaignState owns the actual live dictionaries.
# This system calculates required upkeep and applies payment to a supplied
# stockpile dictionary without knowing anything about UI, scenes or saves.
class_name PopulationUpkeepSystem
extends RefCounted

const UPKEEP_POPULATION_DIVISOR: float = 5.0

func calculate_population_upkeep(active_population_by_group: Dictionary, upkeep_rates_by_group: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for group_variant: Variant in active_population_by_group.keys():
		var group_id: String = String(group_variant)
		var count: int = int(active_population_by_group.get(group_id, 0))
		if count <= 0:
			continue
		var rates: Dictionary = upkeep_rates_by_group.get(group_id, {}) as Dictionary
		for resource_variant: Variant in rates.keys():
			var resource_id: String = String(resource_variant)
			var amount: float = float(rates[resource_variant]) * float(count) / UPKEEP_POPULATION_DIVISOR
			if amount <= 0.0:
				continue
			result[resource_id] = float(result.get(resource_id, 0.0)) + amount
	return result

func resolve_population_upkeep(estate_stockpiles: Dictionary, active_population_by_group: Dictionary, upkeep_rates_by_group: Dictionary) -> Dictionary:
	var needed: Dictionary = calculate_population_upkeep(active_population_by_group, upkeep_rates_by_group)
	var paid: Dictionary = {}
	var shortfalls: Dictionary = {}
	var payments: Array[Dictionary] = []

	for resource_variant: Variant in needed.keys():
		var resource_id: String = String(resource_variant)
		var needed_amount: float = float(needed[resource_variant])
		var available: float = maxf(0.0, float(estate_stockpiles.get(resource_id, 0.0)))
		var paid_amount: float = minf(available, needed_amount)
		estate_stockpiles[resource_id] = maxf(0.0, available - paid_amount)
		paid[resource_id] = paid_amount
		var shortfall: float = maxf(0.0, needed_amount - paid_amount)
		if shortfall > 0.001:
			shortfalls[resource_id] = shortfall
		payments.append({
			"resource_id": resource_id,
			"needed": needed_amount,
			"paid": paid_amount,
			"shortfall": shortfall,
			"ok": shortfall <= 0.001
		})

	return {
		"schema_version": "population_upkeep_resolution_v0_43_4",
		"needed": needed,
		"paid": paid,
		"shortfalls": shortfalls,
		"payments": payments,
		"ok": shortfalls.is_empty()
	}
