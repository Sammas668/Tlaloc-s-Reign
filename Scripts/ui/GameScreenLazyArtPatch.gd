# GameScreenLazyArtPatch.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreenLazyArtPatch.gd
#
# Patch 8P1E: lazy-load screen art.
#
# The previous active GameScreen scene assigned every major screen background as
# an exported Texture2D. Godot loads those ext_resources when the scene opens,
# even though the player only sees the Estate screen first. This wrapper keeps
# the 8P1B coalesced refresh and 8P1C Estate snapshot cache, but resolves art
# from paths only when a screen/focus first asks for it.
extends "res://Scripts/ui/GameScreenEstateSnapshotPatch.gd"

const LAZY_ART_PATHS: Dictionary = {
	"estate": "res://Assets/main_menu/Main menu.png",
	"production": "res://Assets/main_menu/Chinampa.png",
	"production_overview": "res://Assets/main_menu/Workshop and Chinampa.png",
	"production_chinampas": "res://Assets/main_menu/Chinampa.png",
	"production_workshops": "res://Assets/main_menu/Workshop.png",
	"storehouse": "res://Assets/main_menu/Storehouse.png",
	"market": "res://Assets/main_menu/Marketpalce.png",
	"housing": "res://Assets/main_menu/Housing.png",
	"shrines": "res://Assets/main_menu/Shrines.png",
	"warriors": "res://Assets/main_menu/Barracks.png",
	"palace": "res://Assets/main_menu/Palace.png",
	"rivals": "res://Assets/main_menu/Rivals.png"
}

var _lazy_screen_art_cache: Dictionary = {}


func _ready() -> void:
	# Estate is the starting screen, so load only the Estate image up front. Other
	# screen images are loaded on first open and then kept in this small cache.
	_lazy_art("estate")
	super._ready()


func _art_for_location(location_id: String) -> Texture2D:
	match location_id:
		"estate":
			return _lazy_art("estate")
		"production":
			return _art_for_production_focus(_current_focus_id())
		"storehouse":
			return _lazy_art("storehouse")
		"market":
			return _lazy_art("market")
		"housing":
			return _art_for_housing_focus(_current_focus_id())
		"shrines":
			var shrine_art: Texture2D = null
			if has_method("_art_for_shrine_focus"):
				shrine_art = call("_art_for_shrine_focus", _current_focus_id()) as Texture2D
			if shrine_art != null:
				return shrine_art
			return _lazy_art("shrines")
		"warriors":
			return _lazy_art("warriors")
		"palace":
			return _lazy_art("palace")
		"rivals":
			return _lazy_art("rivals")
	return null


func _art_for_production_focus(focus_id: String) -> Texture2D:
	match focus_id:
		"overview":
			return _first_available_lazy_art(["production_overview", "production"])
		"chinampas":
			return _first_available_lazy_art(["production_chinampas", "production"])
		"workshops":
			return _first_available_lazy_art(["production_workshops", "production"])
		"labour":
			return _lazy_art("production")
	return _first_available_lazy_art(["production", "estate"])


func _art_for_housing_focus(_focus_id: String) -> Texture2D:
	return _first_available_lazy_art(["housing", "estate"])


func _first_available_lazy_art(keys: Array[String]) -> Texture2D:
	for key: String in keys:
		var texture: Texture2D = _lazy_art(key)
		if texture != null:
			return texture
	return null


func _lazy_art(key: String) -> Texture2D:
	if _lazy_screen_art_cache.has(key):
		return _lazy_screen_art_cache[key] as Texture2D
	var path: String = String(LAZY_ART_PATHS.get(key, ""))
	if path == "" or not ResourceLoader.exists(path):
		_lazy_screen_art_cache[key] = null
		return null
	var loaded: Resource = load(path)
	if loaded is Texture2D:
		_lazy_screen_art_cache[key] = loaded as Texture2D
		return loaded as Texture2D
	_lazy_screen_art_cache[key] = null
	return null
