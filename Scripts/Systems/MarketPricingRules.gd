# MarketPricingRules.gd
# Godot 4.x
# Project path: res://Scripts/Systems/MarketPricingRules.gd
#
# Canonical Prototype 0 market scarcity pricing rules.
# All market display, village projection and trade-basket pricing paths should
# call this helper so the scarcity floor does not drift between systems.
class_name MarketPricingRules
extends RefCounted

const MIN_SCARCITY_MULTIPLIER: float = 0.50
const MAX_SCARCITY_MULTIPLIER: float = 3.0
const TARGET_COVERAGE_TURNS: float = 3.0

static func scarcity_multiplier(coverage: float, demand: float) -> float:
	if demand <= 0.001:
		return 1.0
	if coverage <= 0.001:
		return MAX_SCARCITY_MULTIPLIER
	return clampf(TARGET_COVERAGE_TURNS / coverage, MIN_SCARCITY_MULTIPLIER, MAX_SCARCITY_MULTIPLIER)
