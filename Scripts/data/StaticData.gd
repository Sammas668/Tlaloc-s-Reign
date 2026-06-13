# StaticData.gd
# Godot 4.x
# Project path: res://Scripts/data/StaticData.gd
#
# Loads static balance/design data from JSON.
# StaticData should contain definitions only. It should not mutate campaign state.
class_name StaticData
extends RefCounted

const RESOURCES_PATH: String = "res://Data/resources.json"
const ESTATE_START_PATH: String = "res://Data/estate_start.json"
const ESTATE_FLOW_SOURCES_PATH: String = "res://Data/estate_flow_sources.json"
const MARKET_START_PATH: String = "res://Data/market_start.json"

var resource_order: Array[String] = []
var market_order: Array[String] = []
var resources: Dictionary = {}
var estate_start: Dictionary = {}
var estate_flow_sources: Dictionary = {}
var market_start: Dictionary = {}
var load_errors: Array[String] = []

func load_all() -> bool:
	load_errors.clear()

	var resource_doc: Dictionary = _load_dictionary(RESOURCES_PATH)
	resource_order = _to_string_array(resource_doc.get("resource_order", []))
	market_order = _to_string_array(resource_doc.get("market_order", []))
	resources = resource_doc.get("resources", {}) as Dictionary

	estate_start = _load_dictionary(ESTATE_START_PATH)
	estate_flow_sources = _load_dictionary(ESTATE_FLOW_SOURCES_PATH)
	market_start = _load_dictionary(MARKET_START_PATH)

	if resource_order.is_empty():
		load_errors.append("No resource_order loaded.")
	if resources.is_empty():
		load_errors.append("No resources loaded.")
	if estate_start.is_empty():
		load_errors.append("No estate_start loaded.")
	if market_start.is_empty():
		load_errors.append("No market_start loaded.")

	return load_errors.is_empty()

func get_resource_definition(good_id: String) -> Dictionary:
	if not resources.has(good_id):
		return {}
	var output: Dictionary = (resources[good_id] as Dictionary).duplicate(true)
	output["id"] = good_id
	return output

func get_base_value(good_id: String) -> float:
	var definition: Dictionary = get_resource_definition(good_id)
	return float(definition.get("base_value", 0.0))

func get_category(good_id: String) -> String:
	var definition: Dictionary = get_resource_definition(good_id)
	return String(definition.get("category", ""))

func get_uses(good_id: String) -> Array:
	var definition: Dictionary = get_resource_definition(good_id)
	return definition.get("uses", []) as Array

func _load_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		load_errors.append("Missing JSON file: " + path)
		return {}

	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		load_errors.append("Could not parse JSON file: " + path)
		return {}
	if not (parsed is Dictionary):
		load_errors.append("JSON root is not a Dictionary: " + path)
		return {}

	return parsed as Dictionary

func _to_string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if not (value is Array):
		return output
	var input_array: Array = value as Array
	for item_variant: Variant in input_array:
		output.append(String(item_variant))
	return output
