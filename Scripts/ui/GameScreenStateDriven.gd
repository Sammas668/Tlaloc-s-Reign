# GameScreenStateDriven.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenStateDriven.gd
#
# PATCH 8K2 — LEGACY / INACTIVE SCREEN WRAPPER.
#
# This file is not the active gameplay screen for Prototype 0.
# The active screen path is:
#
#   GameScreen.gd
#     <- GameScreenMarketOverviewPatch.gd
#       <- extracted screen controllers/widgets
#
# Do not add new Prototype 0 gameplay, market, shrine, palace, warband, rival or
# turn logic here. This shim is kept only so old scenes or local experiments that
# still reference GameScreenStateDriven.gd fail softly instead of crashing.
#
# Future active UI work should go through:
#   res://Scripts/ui/GameScreenMarketOverviewPatch.gd
#   res://Scripts/ui/screens/
#   res://Scripts/ui/widgets/

extends "res://Scripts/ui/GameScreen.gd"


func _ready() -> void:
	push_warning("Legacy GameScreenStateDriven.gd was instantiated. Prototype 0 should use GameScreenMarketOverviewPatch.gd instead.")
	super._ready()


func _game_state_node() -> Node:
	# Legacy compatibility only. GameState is no longer an active autoload.
	return get_node_or_null("/root/TRGameState")
