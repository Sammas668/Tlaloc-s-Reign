# MainMenu.gd
# Godot 4.x
# Suggested project path: res://scripts/ui/main_menu.gd
extends Control

@export_file("*.tscn") var game_scene_path: String = "res://scenes/main/Main.tscn"
@export var background_image: Texture2D
@export var title_text: String = "Tlaloc's Reign"
@export var subtitle_text: String = "Maize. Rain. Tribute. Blood. Recognition."
@export var play_music: bool = false
@export var music_stream: AudioStream

@onready var background_colour: ColorRect = get_node_or_null(^"BackgroundColour") as ColorRect
@onready var background: TextureRect = get_node_or_null(^"Background") as TextureRect
@onready var dim: ColorRect = get_node_or_null(^"Dim") as ColorRect

@onready var menu_panel: PanelContainer = get_node_or_null(^"MenuPanel") as PanelContainer
@onready var title_label: Label = get_node_or_null(^"MenuPanel/Margin/VBox/Title") as Label
@onready var subtitle_label: Label = get_node_or_null(^"MenuPanel/Margin/VBox/Subtitle") as Label
@onready var new_game_button: Button = get_node_or_null(^"MenuPanel/Margin/VBox/NewGameButton") as Button
@onready var continue_button: Button = get_node_or_null(^"MenuPanel/Margin/VBox/ContinueButton") as Button
@onready var load_button: Button = get_node_or_null(^"MenuPanel/Margin/VBox/LoadButton") as Button
@onready var settings_button: Button = get_node_or_null(^"MenuPanel/Margin/VBox/SettingsButton") as Button
@onready var quit_button: Button = get_node_or_null(^"MenuPanel/Margin/VBox/QuitButton") as Button

@onready var version_label: Label = get_node_or_null(^"Footer/VersionLabel") as Label
@onready var latest_save_label: Label = get_node_or_null(^"Footer/LatestSaveLabel") as Label
@onready var music_player: AudioStreamPlayer = get_node_or_null(^"Music") as AudioStreamPlayer

@onready var overlay: Control = get_node_or_null(^"Overlay") as Control
@onready var modal_dim: ColorRect = get_node_or_null(^"Overlay/ModalDim") as ColorRect
@onready var load_panel: PanelContainer = get_node_or_null(^"Overlay/LoadPanel") as PanelContainer
@onready var load_status_label: Label = get_node_or_null(^"Overlay/LoadPanel/Margin/VBox/LoadStatusLabel") as Label
@onready var slot_list: VBoxContainer = get_node_or_null(^"Overlay/LoadPanel/Margin/VBox/Scroll/SlotList") as VBoxContainer
@onready var load_close_button: Button = get_node_or_null(^"Overlay/LoadPanel/Margin/VBox/Header/CloseButton") as Button

@onready var settings_panel: PanelContainer = get_node_or_null(^"Overlay/SettingsPanel") as PanelContainer
@onready var fullscreen_check: CheckBox = get_node_or_null(^"Overlay/SettingsPanel/Margin/VBox/FullscreenRow/FullscreenCheck") as CheckBox
@onready var vsync_check: CheckBox = get_node_or_null(^"Overlay/SettingsPanel/Margin/VBox/VSyncRow/VSyncCheck") as CheckBox
@onready var settings_close_button: Button = get_node_or_null(^"Overlay/SettingsPanel/Margin/VBox/CloseButton") as Button


func _ready() -> void:
	_apply_initial_text()
	_apply_style()
	_apply_background()
	_wire_buttons()
	_prepare_overlay()
	_update_save_buttons()
	_start_music_if_needed()
	_fade_in()
	_log_missing_nodes()


func _apply_initial_text() -> void:
	if title_label:
		title_label.text = title_text
	if subtitle_label:
		subtitle_label.text = subtitle_text
	if version_label:
		version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.1")
	if latest_save_label:
		latest_save_label.text = _latest_save_text()


func _apply_background() -> void:
	if background and background_image:
		background.texture = background_image
	if background:
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if background_colour:
		background_colour.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim:
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _wire_buttons() -> void:
	if new_game_button:
		new_game_button.pressed.connect(_on_new_game_pressed)
	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)
	if load_button:
		load_button.pressed.connect(_on_load_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	if load_close_button:
		load_close_button.pressed.connect(_close_overlay)
	if settings_close_button:
		settings_close_button.pressed.connect(_close_overlay)
	if fullscreen_check:
		fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	if vsync_check:
		vsync_check.toggled.connect(_on_vsync_toggled)

	if new_game_button:
		new_game_button.grab_focus()


func _prepare_overlay() -> void:
	if overlay:
		overlay.visible = false
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if modal_dim:
		modal_dim.visible = false
		modal_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	if load_panel:
		load_panel.visible = false
	if settings_panel:
		settings_panel.visible = false

	if fullscreen_check:
		fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if vsync_check:
		vsync_check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED


func _start_music_if_needed() -> void:
	if play_music and music_stream and music_player:
		music_player.stream = music_stream
		music_player.play()


func _fade_in() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.30)


func _save_manager() -> Node:
	for path in ["/root/SaveLoad", "/root/SaveLoadData", "/root/SaveManager"]:
		var node := get_node_or_null(path)
		if node != null:
			return node
	return null


func _game_state() -> Node:
	for path in ["/root/GameState", "/root/Game"]:
		var node := get_node_or_null(path)
		if node != null:
			return node
	return null


func _on_new_game_pressed() -> void:
	var game_state := _game_state()
	if game_state:
		for method_name in ["new_game", "reset_runtime_state", "reset"]:
			if game_state.has_method(method_name):
				game_state.call(method_name)
				break
	_change_to_game_scene()


func _on_continue_pressed() -> void:
	if _load_latest_save():
		_change_to_game_scene()


func _on_load_pressed() -> void:
	_rebuild_load_slots()
	_show_overlay(load_panel)


func _on_settings_pressed() -> void:
	_show_overlay(settings_panel)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _show_overlay(panel_to_show: Control) -> void:
	if overlay == null or panel_to_show == null:
		return
	overlay.visible = true
	if modal_dim:
		modal_dim.visible = true
	if load_panel:
		load_panel.visible = false
	if settings_panel:
		settings_panel.visible = false
	panel_to_show.visible = true

	var first_button := panel_to_show.find_child("CloseButton", true, false) as Button
	if first_button:
		first_button.grab_focus()


func _close_overlay() -> void:
	if overlay:
		overlay.visible = false
	if modal_dim:
		modal_dim.visible = false
	if load_panel:
		load_panel.visible = false
	if settings_panel:
		settings_panel.visible = false
	if new_game_button:
		new_game_button.grab_focus()


func _update_save_buttons() -> void:
	var has_save := _has_any_save()
	if continue_button:
		continue_button.disabled = not has_save
	if load_button:
		load_button.disabled = false
	if latest_save_label:
		latest_save_label.text = _latest_save_text()


func _has_any_save() -> bool:
	var saves := _list_saves()
	return saves.size() > 0


func _latest_save_text() -> String:
	var saves := _list_saves()
	if saves.is_empty():
		return "No saves found"

	var latest := saves[0] as Dictionary
	var id := String(latest.get("id", latest.get("name", "Save")))
	var timestamp := int(latest.get("timestamp", 0))
	if timestamp > 0:
		return "Latest save: %s — %s" % [id, Time.get_datetime_string_from_unix_time(timestamp)]
	return "Latest save: %s" % id


func _list_saves() -> Array:
	var save_manager := _save_manager()
	if save_manager == null:
		return []
	if save_manager.has_method("list_saves"):
		var result = save_manager.call("list_saves")
		if result is Array:
			return result
	return []


func _load_latest_save() -> bool:
	var save_manager := _save_manager()
	if save_manager == null:
		return false

	var save_id := ""
	if save_manager.has_method("latest_save_id"):
		save_id = String(save_manager.call("latest_save_id"))
	else:
		var saves := _list_saves()
		if not saves.is_empty():
			save_id = String((saves[0] as Dictionary).get("id", ""))

	if save_id == "":
		return false
	return _load_save_by_id(save_id)


func _load_save_by_id(save_id: String) -> bool:
	var save_manager := _save_manager()
	if save_manager == null:
		return false

	for method_name in ["load_game", "load_grove", "load_save", "load"]:
		if save_manager.has_method(method_name):
			return bool(save_manager.call(method_name, save_id))
	return false


func _rebuild_load_slots() -> void:
	if slot_list == null:
		return
	for child in slot_list.get_children():
		child.queue_free()

	var saves := _list_saves()
	if saves.is_empty():
		if load_status_label:
			load_status_label.text = "No saves found yet. Start a new Ritual Year first."
		return

	if load_status_label:
		load_status_label.text = "Choose a saved game."

	for save_entry in saves:
		var data := save_entry as Dictionary
		var save_id := String(data.get("id", data.get("name", "Save")))
		var timestamp := int(data.get("timestamp", 0))
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 44)
		button.text = save_id
		if timestamp > 0:
			button.text += " — " + Time.get_datetime_string_from_unix_time(timestamp)
		button.pressed.connect(func() -> void:
			if _load_save_by_id(save_id):
				_change_to_game_scene()
			else:
				if load_status_label:
					load_status_label.text = "Could not load save: %s" % save_id
		)
		slot_list.add_child(button)


func _change_to_game_scene() -> void:
	if not ResourceLoader.exists(game_scene_path):
		push_error("Game scene not found: %s" % game_scene_path)
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.20)
	tween.tween_callback(Callable(self, "_go_to_game_scene"))


func _go_to_game_scene() -> void:
	get_tree().change_scene_to_file(game_scene_path)


func _on_fullscreen_toggled(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)


func _on_vsync_toggled(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)


func _apply_style() -> void:
	if menu_panel:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(0.045, 0.075, 0.070, 0.88)
		panel_style.border_color = Color(0.35, 0.72, 0.64, 0.55)
		panel_style.set_border_width_all(2)
		panel_style.set_corner_radius_all(18)
		panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
		panel_style.shadow_size = 16
		menu_panel.add_theme_stylebox_override("panel", panel_style)

	for panel_node in [load_panel, settings_panel]:
		if panel_node:
			var modal_style := StyleBoxFlat.new()
			modal_style.bg_color = Color(0.055, 0.075, 0.070, 0.96)
			modal_style.border_color = Color(0.40, 0.77, 0.68, 0.70)
			modal_style.set_border_width_all(2)
			modal_style.set_corner_radius_all(16)
			modal_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
			modal_style.shadow_size = 18
			panel_node.add_theme_stylebox_override("panel", modal_style)

	if title_label:
		title_label.add_theme_font_size_override("font_size", 42)
	if subtitle_label:
		subtitle_label.add_theme_font_size_override("font_size", 15)

	for button in [new_game_button, continue_button, load_button, settings_button, quit_button]:
		if button:
			button.custom_minimum_size = Vector2(0, 48)
			button.add_theme_font_size_override("font_size", 20)


func _log_missing_nodes() -> void:
	var missing: Array[String] = []
	for pair in [
		["BackgroundColour", background_colour],
		["Background", background],
		["Dim", dim],
		["MenuPanel", menu_panel],
		["MenuPanel/Margin/VBox/Title", title_label],
		["MenuPanel/Margin/VBox/NewGameButton", new_game_button],
		["MenuPanel/Margin/VBox/ContinueButton", continue_button],
		["MenuPanel/Margin/VBox/LoadButton", load_button],
		["MenuPanel/Margin/VBox/SettingsButton", settings_button],
		["MenuPanel/Margin/VBox/QuitButton", quit_button],
		["Overlay", overlay]
	]:
		if pair[1] == null:
			missing.append(String(pair[0]))
	if not missing.is_empty():
		push_warning("MainMenu missing optional/required nodes: " + ", ".join(missing))
