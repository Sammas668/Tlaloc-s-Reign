# TurnResolutionSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/TurnResolutionSystem.gd
#
# Owns the live Veintena resolution order for the TRGameState/CampaignState
# migration path. This extracts turn orchestration from TRGameState while
# preserving the exact current order, report text, and signal behaviour.
class_name TurnResolutionSystem
extends RefCounted

func advance_veintena(state: Node) -> void:
	if state == null:
		return

	if not bool(state.get("initialized")):
		if state.has_method("new_game"):
			state.call("new_game")

	var report_variant: Variant = state.get("last_report")
	var report: Array = []
	if report_variant is Array:
		report = report_variant as Array
	report.clear()
	var current_veintena: int = int(state.get("current_veintena"))
	report.append("Veintena " + str(current_veintena) + " resolves.")

	var previous_demand_index: int = 0
	if state.has_method("_current_palace_ruler_demand_index"):
		previous_demand_index = int(state.call("_current_palace_ruler_demand_index"))

	var previous_demand_title: String = "Court Need"
	if state.has_method("_current_palace_ruler_demand_set"):
		var demand_set_variant: Variant = state.call("_current_palace_ruler_demand_set")
		if demand_set_variant is Dictionary:
			previous_demand_title = String((demand_set_variant as Dictionary).get("title", "Court Need"))

	var previous_demand_completion: Dictionary = {}
	if state.has_method("get_palace_ruler_demand_completion_summary"):
		var completion_variant: Variant = state.call("get_palace_ruler_demand_completion_summary")
		if completion_variant is Dictionary:
			previous_demand_completion = completion_variant as Dictionary

	_call_if_present(state, "_pay_population_upkeep")
	_call_if_present(state, "_pay_housing_maintenance")
	_call_if_present(state, "_pay_palace_maintenance")
	_call_if_present(state, "_operate_buildings")
	_call_if_present(state, "_recover_injured_warriors")

	current_veintena += 1
	if current_veintena > 18:
		current_veintena = 1
		report.append("Nemontemi reckoning placeholder: the next Ritual Year begins.")
	state.set("current_veintena", current_veintena)

	if state.has_method("_report_palace_ruler_demand_cycle_transition"):
		state.call("_report_palace_ruler_demand_cycle_transition", previous_demand_index, previous_demand_title, previous_demand_completion)

	report.append("Now entering Veintena " + str(current_veintena) + ".")
	state.set("last_report", report)

	if state.has_signal("turn_advanced"):
		state.emit_signal("turn_advanced", report)
	if state.has_signal("state_changed"):
		state.emit_signal("state_changed")

func _call_if_present(state: Node, method_name: String) -> void:
	if state != null and state.has_method(method_name):
		state.call(method_name)
