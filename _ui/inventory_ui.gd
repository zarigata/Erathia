extends CanvasLayer
## InventoryUI - Main inventory interface with grid layout
## Toggle visibility with "toggle_inventory" action (Tab key)

## Grid layout columns
@export var columns: int = 8

## Node references
@onready var background: ColorRect = $Background
@onready var main_panel: PanelContainer = $CenterContainer/MainPanel
@onready var title_label: Label = $CenterContainer/MainPanel/VBoxContainer/HeaderContainer/TitleLabel
@onready var close_button: Button = $CenterContainer/MainPanel/VBoxContainer/HeaderContainer/CloseButton
@onready var filter_option: OptionButton = $CenterContainer/MainPanel/VBoxContainer/ControlsContainer/FilterOption
@onready var sort_button: Button = $CenterContainer/MainPanel/VBoxContainer/ControlsContainer/SortButton
@onready var grid_container: GridContainer = $CenterContainer/MainPanel/VBoxContainer/ScrollContainer/GridContainer
@onready var summary_label: Label = $CenterContainer/MainPanel/VBoxContainer/SummaryLabel
@onready var settings_button: Button = $CenterContainer/MainPanel/VBoxContainer/HeaderContainer/SettingsButton

## Preloaded slot scene
var _slot_scene: PackedScene = null

## Settings UI reference
var _settings_ui: CanvasLayer = null

## Currently dragged slot for visual feedback (reserved for future use)
#var _dragged_slot_index: int = -1

## Filter categories
const FILTER_ALL := "All"
const FILTER_MATERIALS := "Materials"
const FILTER_TOOLS := "Tools"
const FILTER_CONSUMABLES := "Consumables"
const FILTER_MISC := "Misc"

## Current filter
var _current_filter: String = FILTER_ALL

## Sort mode
var _sort_by_type: bool = true  # Toggle between type and amount


func _ready() -> void:
	# Add to inventory_ui group for drag-to-world detection
	add_to_group("inventory_ui")
	
	# Preload slot scene
	_slot_scene = preload("res://_ui/inventory_slot.tscn")
	
	# Setup UI
	_setup_ui()
	
	# Connect signals
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	if sort_button:
		sort_button.pressed.connect(_on_sort_button_pressed)
	if filter_option:
		filter_option.item_selected.connect(_on_filter_selected)
	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)
	
	# Setup settings UI
	_setup_settings_ui()
	
	# Connect to Inventory signals
	if Inventory:
		Inventory.inventory_changed.connect(_on_inventory_changed)
		Inventory.item_added.connect(_on_item_added)
		Inventory.item_removed.connect(_on_item_removed)
	
	# Create inventory slots
	_create_slots()
	
	# Initial update
	update_title()
	update_summary()
	
	# Start hidden
	visible = false


func _setup_ui() -> void:
	# Setup filter options
	if filter_option:
		filter_option.clear()
		filter_option.add_item(FILTER_ALL)
		filter_option.add_item(FILTER_MATERIALS)
		filter_option.add_item(FILTER_TOOLS)
		filter_option.add_item(FILTER_CONSUMABLES)
		filter_option.add_item(FILTER_MISC)
	
	# Setup grid columns
	if grid_container:
		grid_container.columns = columns


func _create_slots() -> void:
	if not grid_container or not _slot_scene:
		return
	
	# Clear existing slots
	for child in grid_container.get_children():
		child.queue_free()
	
	# Create slots
	for i in range(Inventory.MAX_SLOTS if Inventory else 40):
		var slot: PanelContainer = _slot_scene.instantiate()
		slot.slot_index = i
		grid_container.add_child(slot)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle_visibility()
		get_viewport().set_input_as_handled()
	
	# Close on Escape when visible
	if visible and event.is_action_pressed("ui_cancel"):
		hide_inventory()
		get_viewport().set_input_as_handled()


func toggle_visibility() -> void:
	if visible:
		hide_inventory()
	else:
		show_inventory()


func show_inventory() -> void:
	visible = true
	
	# Capture mouse for UI interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Update display
	update_title()
	update_summary()
	
	# Pause game (optional - depends on game design)
	# get_tree().paused = true


func hide_inventory() -> void:
	visible = false
	
	# Return mouse to captured state for gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Unpause game
	# get_tree().paused = false


func _on_close_button_pressed() -> void:
	hide_inventory()


func _on_sort_button_pressed() -> void:
	if not Inventory:
		return
	
	if _sort_by_type:
		Inventory.sort_by_type()
		if sort_button:
			sort_button.text = "Sort: Type"
	else:
		Inventory.sort_by_amount()
		if sort_button:
			sort_button.text = "Sort: Amount"
	
	_sort_by_type = not _sort_by_type


func _on_filter_selected(index: int) -> void:
	if not filter_option:
		return
	
	_current_filter = filter_option.get_item_text(index)
	apply_filter(_current_filter)


func apply_filter(category: String) -> void:
	if not grid_container or not Inventory:
		return
	
	for i in range(grid_container.get_child_count()):
		var slot: Control = grid_container.get_child(i)
		if not slot:
			continue
		
		if category == FILTER_ALL:
			slot.visible = true
			continue
		
		var slot_data: Dictionary = Inventory.get_slot_data(i)
		if slot_data.is_empty():
			slot.visible = true  # Show empty slots
			continue
		
		var resource_type: String = slot_data.get("resource_type", "")
		var info: Dictionary = Inventory.get_resource_info(resource_type)
		var res_category: int = info.get("category", Inventory.Category.MISC)
		
		var should_show: bool = false
		match category:
			FILTER_MATERIALS:
				should_show = res_category == Inventory.Category.MATERIAL
			FILTER_TOOLS:
				should_show = res_category == Inventory.Category.TOOL
			FILTER_CONSUMABLES:
				should_show = res_category == Inventory.Category.CONSUMABLE
			FILTER_MISC:
				should_show = res_category == Inventory.Category.MISC or res_category == Inventory.Category.BUILDING
			_:
				should_show = true
		
		slot.visible = should_show


func update_title() -> void:
	if not title_label or not Inventory:
		return
	
	var used_slots: int = Inventory.get_used_slot_count()
	var max_slots: int = Inventory.MAX_SLOTS
	title_label.text = "Inventory (%d/%d)" % [used_slots, max_slots]


func update_summary() -> void:
	if not summary_label or not Inventory:
		return
	
	var resources: Dictionary = Inventory.get_all_resources()
	if resources.is_empty():
		summary_label.text = "No items"
		return
	
	# Show summary of key resources
	var summary_parts: Array[String] = []
	var key_resources: Array[String] = ["stone", "wood", "iron_ore", "rare_crystal"]
	
	for resource_type in key_resources:
		if resources.has(resource_type):
			var info: Dictionary = Inventory.get_resource_info(resource_type)
			var display_name: String = info.get("display_name", resource_type.capitalize())
			summary_parts.append("%s: %d" % [display_name, resources[resource_type]])
	
	if summary_parts.is_empty():
		# Show first few resources if no key resources
		var count: int = 0
		for resource_type in resources.keys():
			if count >= 4:
				break
			var info: Dictionary = Inventory.get_resource_info(resource_type)
			var display_name: String = info.get("display_name", resource_type.capitalize())
			summary_parts.append("%s: %d" % [display_name, resources[resource_type]])
			count += 1
	
	summary_label.text = " | ".join(summary_parts)


func _on_inventory_changed(_slot_index: int) -> void:
	update_title()
	update_summary()


func _on_item_added(_resource_type: String, _amount: int) -> void:
	update_title()
	update_summary()


func _on_item_removed(_resource_type: String, _amount: int) -> void:
	update_title()
	update_summary()


func _setup_settings_ui() -> void:
	# Load and instantiate settings UI
	var settings_scene := preload("res://_ui/settings_ui.tscn")
	_settings_ui = settings_scene.instantiate()
	add_child(_settings_ui)
	_settings_ui.visible = false


func _on_settings_button_pressed() -> void:
	if _settings_ui:
		_settings_ui.open_settings(0)  # Open to Gameplay tab
