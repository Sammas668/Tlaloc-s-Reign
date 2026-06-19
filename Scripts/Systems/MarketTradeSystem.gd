# MarketTradeSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/MarketTradeSystem.gd
#
# v0.43.0 architecture split scaffold only.
# This file intentionally does not change gameplay yet.
#
# Intended ownership:
# - Trade-basket validation and barter-value resolution.
# - Buy/sell caps, free stock checks, and market stock transfer logic.
# - Future integration point for Savvy Trade preview inputs.
#
# Migration note: Should eventually move trade application out of TradeBasketView.gd / TRGameState.gd.
#
# Extraction rule: UI should continue to call TRGameState / future CampaignState.
# Systems should own rules, not scene/UI code.
class_name MarketTradeSystem
extends RefCounted

const SCAFFOLD_VERSION: String = "v0.43.0"

func system_name() -> String:
	return "MarketTradeSystem"
