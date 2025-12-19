extends Node
## GameSettings - Singleton for managing gameplay settings
##
## Stores player preferences including auto-collection behavior.
## Registered as autoload "GameSettings" in project.godot

## Emitted when any setting changes
signal settings_changed(setting_name: String, value: Variant)

## Settings file path
const SETTINGS_FILE := "user://game_settings.cfg"

## Default settings
const DEFAULT_SETTINGS := {
	"gameplay": {
		"auto_collect_items": true,
		"show_pickup_prompts": true,
		"show_collection_indicator": true,
	},
	"controls": {
		"mouse_sensitivity": 0.002,
		"invert_y": false,
	},
	"audio": {
		"master_volume": 1.0,
		"sfx_volume": 1.0,
		"music_volume": 0.8,
	},
	"video": {
		"vsync": false,
		"fullscreen": false,
		"fov": 75.0,
	},
	"graphics": {
		"biome_height_variation": 0.25,
		"vegetation_density": 1.0,
		"vegetation_distance": 1,
	},
	"ui": {
		"scale": 1.0,
	},
	"tutorial": {
		"build_ui_shown": false,
		"inventory_shown": false,
		"tools_shown": false,
	},
}

## Current settings (loaded from file or defaults)
var _settings: Dictionary = {}


func _ready() -> void:
	_settings = DEFAULT_SETTINGS.duplicate(true)
	load_settings()


## Load settings from file
func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE)
	
	if err != OK:
		print("[GameSettings] No settings file found, using defaults")
		return
	
	# Load each section
	for section in DEFAULT_SETTINGS.keys():
		if not _settings.has(section):
			_settings[section] = {}
		
		for key in DEFAULT_SETTINGS[section].keys():
			if config.has_section_key(section, key):
				_settings[section][key] = config.get_value(section, key)
			else:
				_settings[section][key] = DEFAULT_SETTINGS[section][key]
	
	print("[GameSettings] Settings loaded from %s" % SETTINGS_FILE)


## Save settings to file
func save_settings() -> void:
	var config := ConfigFile.new()
	
	for section in _settings.keys():
		for key in _settings[section].keys():
			config.set_value(section, key, _settings[section][key])
	
	var err := config.save(SETTINGS_FILE)
	if err == OK:
		print("[GameSettings] Settings saved to %s" % SETTINGS_FILE)
	else:
		push_warning("[GameSettings] Failed to save settings: %d" % err)


## Get a setting value
## @param key: Setting key in format "section.key" (e.g., "gameplay.auto_collect_items")
## @return: The setting value, or null if not found
func get_setting(key: String) -> Variant:
	var parts := key.split(".")
	if parts.size() != 2:
		push_warning("[GameSettings] Invalid setting key format: %s (use 'section.key')" % key)
		return null
	
	var section := parts[0]
	var setting_key := parts[1]
	
	if not _settings.has(section):
		push_warning("[GameSettings] Unknown section: %s" % section)
		return null
	
	if not _settings[section].has(setting_key):
		push_warning("[GameSettings] Unknown setting: %s.%s" % [section, setting_key])
		return null
	
	return _settings[section][setting_key]


## Set a setting value
## @param key: Setting key in format "section.key" (e.g., "gameplay.auto_collect_items")
## @param value: The value to set
func set_setting(key: String, value: Variant) -> void:
	var parts := key.split(".")
	if parts.size() != 2:
		push_warning("[GameSettings] Invalid setting key format: %s (use 'section.key')" % key)
		return
	
	var section := parts[0]
	var setting_key := parts[1]
	
	if not _settings.has(section):
		_settings[section] = {}
	
	var old_value = _settings[section].get(setting_key)
	_settings[section][setting_key] = value
	
	if old_value != value:
		settings_changed.emit(key, value)
		save_settings()


## Get all settings in a section
## @param section: The section name (e.g., "gameplay")
## @return: Dictionary of settings in that section
func get_section(section: String) -> Dictionary:
	if _settings.has(section):
		return _settings[section].duplicate()
	return {}


## Reset a setting to default
## @param key: Setting key in format "section.key"
func reset_setting(key: String) -> void:
	var parts := key.split(".")
	if parts.size() != 2:
		return
	
	var section := parts[0]
	var setting_key := parts[1]
	
	if DEFAULT_SETTINGS.has(section) and DEFAULT_SETTINGS[section].has(setting_key):
		set_setting(key, DEFAULT_SETTINGS[section][setting_key])


## Reset all settings to defaults
func reset_all_settings() -> void:
	_settings = DEFAULT_SETTINGS.duplicate(true)
	save_settings()
	settings_changed.emit("all", null)


## Convenience method: Check if auto-collect is enabled
func is_auto_collect_enabled() -> bool:
	return get_setting("gameplay.auto_collect_items") == true
