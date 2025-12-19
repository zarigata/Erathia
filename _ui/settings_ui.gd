extends CanvasLayer
## SettingsUI - Game settings panel for player preferences
##
## Provides UI for toggling gameplay settings like auto-collection.
## Accessible via settings button in inventory or dedicated input action.

## Emitted when settings panel is opened
signal settings_opened
## Emitted when settings panel is closed
signal settings_closed

## Node references
@onready var background: ColorRect = $Background
@onready var main_panel: PanelContainer = $CenterContainer/MainPanel
@onready var title_label: Label = $CenterContainer/MainPanel/VBoxContainer/HeaderContainer/TitleLabel
@onready var close_button: Button = $CenterContainer/MainPanel/VBoxContainer/HeaderContainer/CloseButton
@onready var tab_container: TabContainer = $CenterContainer/MainPanel/VBoxContainer/TabContainer
@onready var apply_button: Button = $CenterContainer/MainPanel/VBoxContainer/ButtonContainer/ApplyButton
@onready var close_button_bottom: Button = $CenterContainer/MainPanel/VBoxContainer/ButtonContainer/CloseButtonBottom

## Gameplay tab controls
@onready var auto_collect_check: CheckBox = $CenterContainer/MainPanel/VBoxContainer/TabContainer/Gameplay/AutoCollectCheck
@onready var show_prompts_check: CheckBox = $CenterContainer/MainPanel/VBoxContainer/TabContainer/Gameplay/ShowPromptsCheck
@onready var show_indicator_check: CheckBox = $CenterContainer/MainPanel/VBoxContainer/TabContainer/Gameplay/ShowIndicatorCheck

## Graphics tab controls (biome/vegetation settings)
@onready var biome_strength_slider: HSlider = $CenterContainer/MainPanel/VBoxContainer/TabContainer/Graphics/BiomeStrengthSlider
@onready var biome_strength_label: Label = $CenterContainer/MainPanel/VBoxContainer/TabContainer/Graphics/BiomeStrengthLabel
@onready var vegetation_density_slider: HSlider = $CenterContainer/MainPanel/VBoxContainer/TabContainer/Graphics/VegetationDensitySlider
@onready var vegetation_density_label: Label = $CenterContainer/MainPanel/VBoxContainer/TabContainer/Graphics/VegetationDensityLabel
@onready var vegetation_distance_option: OptionButton = $CenterContainer/MainPanel/VBoxContainer/TabContainer/Graphics/VegetationDistanceOption

## Whether the panel is currently visible
var is_open: bool = false

## Cached references
var _biome_generator: BiomeAwareGenerator = null
var _vegetation_instancer: Node = null


func _ready() -> void:
	# Connect button signals
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if close_button_bottom:
		close_button_bottom.pressed.connect(_on_close_pressed)
	if apply_button:
		apply_button.pressed.connect(_on_apply_pressed)
	
	# Connect checkbox signals
	if auto_collect_check:
		auto_collect_check.toggled.connect(_on_auto_collect_toggled)
	if show_prompts_check:
		show_prompts_check.toggled.connect(_on_show_prompts_toggled)
	if show_indicator_check:
		show_indicator_check.toggled.connect(_on_show_indicator_toggled)
	
	# Connect graphics settings signals
	if biome_strength_slider:
		biome_strength_slider.value_changed.connect(_on_biome_strength_changed)
	if vegetation_density_slider:
		vegetation_density_slider.value_changed.connect(_on_vegetation_density_changed)
	if vegetation_distance_option:
		vegetation_distance_option.item_selected.connect(_on_vegetation_distance_changed)
		# Populate distance options
		vegetation_distance_option.clear()
		vegetation_distance_option.add_item("64m (Low)", 0)
		vegetation_distance_option.add_item("128m (Medium)", 1)
		vegetation_distance_option.add_item("256m (High)", 2)
		vegetation_distance_option.add_item("512m (Ultra)", 3)
	
	# Find terrain references
	call_deferred("_find_terrain_references")
	
	# Load current settings
	_load_settings_to_ui()
	
	# Start hidden
	visible = false


func _find_terrain_references() -> void:
	var root := get_tree().current_scene
	if not root:
		return
	
	var terrain := root.get_node_or_null("VoxelLodTerrain") as VoxelLodTerrain
	if terrain:
		if terrain.generator:
			_biome_generator = terrain.generator as BiomeAwareGenerator
		_vegetation_instancer = terrain.get_node_or_null("VegetationInstancer")


func _input(event: InputEvent) -> void:
	# Close on Escape when visible
	if is_open and event.is_action_pressed("ui_cancel"):
		close_settings()
		get_viewport().set_input_as_handled()


func _load_settings_to_ui() -> void:
	if not GameSettings:
		return
	
	if auto_collect_check:
		auto_collect_check.button_pressed = GameSettings.get_setting("gameplay.auto_collect_items")
	if show_prompts_check:
		show_prompts_check.button_pressed = GameSettings.get_setting("gameplay.show_pickup_prompts")
	if show_indicator_check:
		show_indicator_check.button_pressed = GameSettings.get_setting("gameplay.show_collection_indicator")
	
	# Load graphics settings
	_load_graphics_settings()


func _load_graphics_settings() -> void:
	# Biome height modulation
	if biome_strength_slider and _biome_generator:
		biome_strength_slider.value = _biome_generator.height_modulation_strength
		_update_biome_strength_label(_biome_generator.height_modulation_strength)
	elif biome_strength_slider:
		var saved_value = GameSettings.get_setting("graphics.biome_height_variation")
		biome_strength_slider.value = saved_value if saved_value != null else 0.25
		_update_biome_strength_label(biome_strength_slider.value)
	
	# Vegetation density
	if vegetation_density_slider:
		var saved_density = GameSettings.get_setting("graphics.vegetation_density")
		var density: float = saved_density if saved_density != null else 1.0
		vegetation_density_slider.value = density
		_update_vegetation_density_label(density)
	
	# Vegetation distance
	if vegetation_distance_option:
		var saved_distance = GameSettings.get_setting("graphics.vegetation_distance")
		var distance: int = saved_distance if saved_distance != null else 1
		vegetation_distance_option.selected = clampi(distance, 0, 3)


func open_settings(tab_index: int = 0) -> void:
	if is_open:
		return
	
	is_open = true
	visible = true
	
	# Load current settings
	_load_settings_to_ui()
	
	# Set tab
	if tab_container and tab_index >= 0 and tab_index < tab_container.get_tab_count():
		tab_container.current_tab = tab_index
	
	# Show mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	settings_opened.emit()


func close_settings() -> void:
	if not is_open:
		return
	
	is_open = false
	visible = false
	
	# Return mouse to captured state if no other UI is open
	var inventory_ui = get_tree().get_first_node_in_group("inventory_ui")
	if inventory_ui and inventory_ui.visible:
		# Keep mouse visible for inventory
		pass
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	settings_closed.emit()


func toggle_settings() -> void:
	if is_open:
		close_settings()
	else:
		open_settings()


func _on_close_pressed() -> void:
	close_settings()


func _on_apply_pressed() -> void:
	# Settings are applied immediately on toggle, so just close
	close_settings()


func _on_auto_collect_toggled(pressed: bool) -> void:
	if GameSettings:
		GameSettings.set_setting("gameplay.auto_collect_items", pressed)


func _on_show_prompts_toggled(pressed: bool) -> void:
	if GameSettings:
		GameSettings.set_setting("gameplay.show_pickup_prompts", pressed)


func _on_show_indicator_toggled(pressed: bool) -> void:
	if GameSettings:
		GameSettings.set_setting("gameplay.show_collection_indicator", pressed)


func _on_biome_strength_changed(value: float) -> void:
	_update_biome_strength_label(value)
	
	# Apply to BiomeAwareGenerator
	if _biome_generator:
		_biome_generator.height_modulation_strength = value
	
	# Save setting
	if GameSettings:
		GameSettings.set_setting("graphics.biome_height_variation", value)


func _update_biome_strength_label(value: float) -> void:
	if not biome_strength_label:
		return
	
	var level_text := "Off"
	if value > 0.0 and value <= 0.15:
		level_text = "Low"
	elif value > 0.15 and value <= 0.35:
		level_text = "Medium"
	elif value > 0.35 and value <= 0.6:
		level_text = "High"
	elif value > 0.6:
		level_text = "Extreme"
	
	biome_strength_label.text = "Biome Height Variation: %.0f%% (%s)" % [value * 100, level_text]
	
	# Show warning for high values
	if value > 0.5:
		biome_strength_label.modulate = Color(1.0, 0.8, 0.2)  # Warning yellow
	else:
		biome_strength_label.modulate = Color.WHITE


func _on_vegetation_density_changed(value: float) -> void:
	_update_vegetation_density_label(value)
	
	# Save setting
	if GameSettings:
		GameSettings.set_setting("graphics.vegetation_density", value)
	
	# Note: Would need to reload vegetation to apply


func _update_vegetation_density_label(value: float) -> void:
	if not vegetation_density_label:
		return
	
	vegetation_density_label.text = "Vegetation Density: %.0f%%" % (value * 100)


func _on_vegetation_distance_changed(index: int) -> void:
	# Save setting
	if GameSettings:
		GameSettings.set_setting("graphics.vegetation_distance", index)
	
	# Apply to VegetationInstancer
	if _vegetation_instancer:
		var distances := [64.0, 128.0, 256.0, 512.0]
		if index >= 0 and index < distances.size():
			var new_distance: float = distances[index]
			# Note: Would need method on VegetationInstancer to update visibility ranges
			print("[SettingsUI] Vegetation distance set to: %.0fm" % new_distance)
