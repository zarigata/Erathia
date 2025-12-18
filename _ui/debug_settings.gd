extends Control
## Debug Settings Panel
##
## Configuration panel for debug tools.
## Toggle with F10 key or 'settings' console command.

signal settings_changed()

@onready var panel: PanelContainer = $Panel
@onready var console_font_size: SpinBox = $Panel/TabContainer/Console/VBoxContainer/FontSizeContainer/FontSizeSpinBox
@onready var console_history_length: SpinBox = $Panel/TabContainer/Console/VBoxContainer/HistoryLengthContainer/HistoryLengthSpinBox
@onready var console_autocomplete: CheckBox = $Panel/TabContainer/Console/VBoxContainer/AutocompleteCheck
@onready var overlay_update_rate: SpinBox = $Panel/TabContainer/Performance/VBoxContainer/UpdateRateContainer/UpdateRateSpinBox
@onready var overlay_show_graph: CheckBox = $Panel/TabContainer/Performance/VBoxContainer/ShowGraphCheck
@onready var xray_label_distance: SpinBox = $Panel/TabContainer/XRay/VBoxContainer/LabelDistanceContainer/LabelDistanceSpinBox
@onready var xray_transparency: Slider = $Panel/TabContainer/XRay/VBoxContainer/TransparencyContainer/TransparencySlider

var _visible: bool = false
var _settings: Dictionary = {}

const SETTINGS_PATH: String = "user://debug_settings.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	
	_load_settings()
	_apply_settings_to_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_settings"):
		_toggle_panel()
		get_viewport().set_input_as_handled()


func _toggle_panel() -> void:
	_visible = not _visible
	panel.visible = _visible
	
	if _visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	
	if err != OK:
		# Use defaults
		_settings = {
			"console_font_size": 14,
			"console_history_length": 50,
			"console_autocomplete": true,
			"overlay_update_rate": 0.1,
			"overlay_show_graph": true,
			"xray_label_distance": 50.0,
			"xray_transparency": 0.3
		}
		return
	
	_settings = {
		"console_font_size": config.get_value("console", "font_size", 14),
		"console_history_length": config.get_value("console", "history_length", 50),
		"console_autocomplete": config.get_value("console", "autocomplete", true),
		"overlay_update_rate": config.get_value("performance", "update_rate", 0.1),
		"overlay_show_graph": config.get_value("performance", "show_graph", true),
		"xray_label_distance": config.get_value("xray", "label_distance", 50.0),
		"xray_transparency": config.get_value("xray", "transparency", 0.3)
	}


func _save_settings() -> void:
	var config := ConfigFile.new()
	
	config.set_value("console", "font_size", _settings.console_font_size)
	config.set_value("console", "history_length", _settings.console_history_length)
	config.set_value("console", "autocomplete", _settings.console_autocomplete)
	config.set_value("performance", "update_rate", _settings.overlay_update_rate)
	config.set_value("performance", "show_graph", _settings.overlay_show_graph)
	config.set_value("xray", "label_distance", _settings.xray_label_distance)
	config.set_value("xray", "transparency", _settings.xray_transparency)
	
	config.save(SETTINGS_PATH)


func _apply_settings_to_ui() -> void:
	if console_font_size:
		console_font_size.value = _settings.console_font_size
	if console_history_length:
		console_history_length.value = _settings.console_history_length
	if console_autocomplete:
		console_autocomplete.button_pressed = _settings.console_autocomplete
	if overlay_update_rate:
		overlay_update_rate.value = _settings.overlay_update_rate
	if overlay_show_graph:
		overlay_show_graph.button_pressed = _settings.overlay_show_graph
	if xray_label_distance:
		xray_label_distance.value = _settings.xray_label_distance
	if xray_transparency:
		xray_transparency.value = _settings.xray_transparency


func get_setting(key: String) -> Variant:
	return _settings.get(key, null)


func _on_font_size_changed(value: float) -> void:
	_settings.console_font_size = int(value)
	_save_settings()
	settings_changed.emit()


func _on_history_length_changed(value: float) -> void:
	_settings.console_history_length = int(value)
	_save_settings()
	settings_changed.emit()


func _on_autocomplete_toggled(toggled_on: bool) -> void:
	_settings.console_autocomplete = toggled_on
	_save_settings()
	settings_changed.emit()


func _on_update_rate_changed(value: float) -> void:
	_settings.overlay_update_rate = value
	_save_settings()
	settings_changed.emit()


func _on_show_graph_toggled(toggled_on: bool) -> void:
	_settings.overlay_show_graph = toggled_on
	_save_settings()
	settings_changed.emit()


func _on_label_distance_changed(value: float) -> void:
	_settings.xray_label_distance = value
	_save_settings()
	settings_changed.emit()


func _on_transparency_changed(value: float) -> void:
	_settings.xray_transparency = value
	_save_settings()
	settings_changed.emit()


func _on_close_pressed() -> void:
	_toggle_panel()
