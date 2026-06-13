# Reservation.gd
# Godot 4.x
# Project path: res://Scripts/economy/Reservation.gd
#
# A claim on stock before the player/rival is allowed to spend, sell, offer or trade it.
class_name Reservation
extends RefCounted

var good_id: String = ""
var source: String = ""
var amount: float = 0.0
var priority: int = 0
var required: bool = false

func _init(new_good_id: String = "", new_source: String = "", new_amount: float = 0.0, new_priority: int = 0, new_required: bool = false) -> void:
	good_id = new_good_id
	source = new_source
	amount = maxf(0.0, new_amount)
	priority = new_priority
	required = new_required

static func from_dictionary(data: Dictionary) -> Reservation:
	return Reservation.new(
		String(data.get("good_id", "")),
		String(data.get("source", "Unknown reserve")),
		float(data.get("amount", 0.0)),
		int(data.get("priority", 0)),
		bool(data.get("required", false))
	)

func to_line() -> String:
	var label: String = source + ": " + _fmt(amount)
	if required:
		label += " required"
	return label

func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value
