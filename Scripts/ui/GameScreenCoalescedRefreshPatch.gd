# GameScreenCoalescedRefreshPatch.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenCoalescedRefreshPatch.gd
#
# Patch 8P1B: active GameScreen wrapper that coalesces repeated full UI
# refresh requests into one deferred refresh per frame. This keeps the existing
# GameScreenMarketOverviewPatch behaviour intact while preventing state_changed
# signals and button handlers from rebuilding the Estate screen multiple times
# during the same action.
extends "res://Scripts/ui/GameScreenMarketOverviewPatch.gd"

var _refresh_pending: bool = false
var _refresh_flushing: bool = false


func _refresh_all() -> void:
	# Base GameScreen and extracted wrapper handlers still call _refresh_all()
	# directly. Route those calls through a single deferred flush so duplicated
	# requests from state_changed + manual handlers collapse into one rebuild.
	if _refresh_flushing:
		super._refresh_all()
		return
	_request_refresh_all()


func _request_refresh_all() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_flush_refresh_all")


func _flush_refresh_all() -> void:
	if not _refresh_pending:
		return
	_refresh_pending = false
	_refresh_flushing = true
	super._refresh_all()
	_refresh_flushing = false


func _on_state_changed() -> void:
	# State changes can arrive during the same frame as a user action that also
	# requested a refresh. Keep this as a refresh request, not an immediate rebuild.
	_request_refresh_all()
