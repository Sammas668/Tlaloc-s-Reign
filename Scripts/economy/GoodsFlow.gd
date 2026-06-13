# GoodsFlow.gd
# Godot 4.x
# Project path: res://Scripts/economy/GoodsFlow.gd
#
# A calculated movement of one good for one turn.
# Future systems should generate these instead of writing raw incoming/outgoing totals.
class_name GoodsFlow
extends RefCounted

var good_id: String = ""
var source: String = ""
var amount: float = 0.0
var direction: String = "incoming"

func _init(new_good_id: String = "", new_source: String = "", new_amount: float = 0.0, new_direction: String = "incoming") -> void:
	good_id = new_good_id
	source = new_source
	amount = maxf(0.0, new_amount)
	direction = new_direction

static func from_dictionary(data: Dictionary, default_direction: String) -> GoodsFlow:
	return GoodsFlow.new(
		String(data.get("good_id", "")),
		String(data.get("source", "Unknown source")),
		float(data.get("amount", 0.0)),
		String(data.get("direction", default_direction))
	)

func to_line() -> String:
	return source + ": " + _fmt(amount)

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value
