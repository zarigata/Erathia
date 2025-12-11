class_name InventoryMenu
extends Control
## Inventory Menu - Minecraft/Valheim style grid
## 24 columns x 16 rows = 384 slots, each holds up to 4096 items

@onready var grid = $GridContainer

const SLOT_SIZE = Vector2(40, 40)
const GRID_COLS = 12  # Reduced for visibility
const GRID_ROWS = 8   # Reduced for visibility
const VISIBLE_SLOTS = GRID_COLS * GRID_ROWS

var slot_scene = preload("res://_ui/menus/InventorySlotUI.tscn")
var slots: Array = []

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Create the inventory panel
	_create_inventory_panel()
	
	# Connect to inventory updates
	if InventoryManager:
		InventoryManager.inventory_updated.connect(_on_inventory_updated)
	
	print("InventoryMenu: Initialized with ", VISIBLE_SLOTS, " visible slots")

func _create_inventory_panel():
	# Clear existing content
	for child in get_children():
		child.queue_free()
	
	# Main container
	var main_container = VBoxContainer.new()
	main_container.set_anchors_preset(Control.PRESET_CENTER)
	main_container.custom_minimum_size = Vector2(600, 500)
	main_container.add_theme_constant_override("separation", 15)
	add_child(main_container)
	
	# Title
	var title = Label.new()
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	main_container.add_child(title)
	
	# Inventory panel background
	var panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	panel_style.border_color = Color(0.5, 0.45, 0.35)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	main_container.add_child(panel)
	
	# Scroll container for large inventory
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 380)
	panel.add_child(scroll)
	
	# Grid container
	var grid_container = GridContainer.new()
	grid_container.name = "InventoryGrid"
	grid_container.columns = GRID_COLS
	grid_container.add_theme_constant_override("h_separation", 4)
	grid_container.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid_container)
	
	# Create slots
	_populate_grid(grid_container)
	
	# Stats label at bottom
	var stats = Label.new()
	stats.text = "Slots: " + str(VISIBLE_SLOTS) + " | Weight: 0/500"
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 14)
	stats.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	main_container.add_child(stats)

func _populate_grid(grid_container: GridContainer):
	slots.clear()
	
	for i in range(VISIBLE_SLOTS):
		var slot = _create_slot(i)
		grid_container.add_child(slot)
		slots.append(slot)

func _create_slot(index: int) -> PanelContainer:
	var slot = PanelContainer.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.name = "Slot_" + str(index)
	
	# Slot style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	style.border_color = Color(0.35, 0.35, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", style)
	
	# Content container
	var content = Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(content)
	
	# Icon placeholder
	var icon = ColorRect.new()
	icon.name = "Icon"
	icon.color = Color(0.25, 0.25, 0.25, 0.3)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4
	icon.offset_top = 4
	icon.offset_right = -4
	icon.offset_bottom = -12
	content.add_child(icon)
	
	# Count label
	var count_label = Label.new()
	count_label.name = "CountLabel"
	count_label.text = ""
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	count_label.add_theme_font_size_override("font_size", 10)
	count_label.add_theme_color_override("font_color", Color(1, 1, 1))
	content.add_child(count_label)
	
	# Store index for later reference
	slot.set_meta("slot_index", index)
	
	return slot

func _on_inventory_updated(slot_index: int):
	if slot_index < 0 or slot_index >= slots.size():
		return
	
	var slot_data = InventoryManager.get_slot(slot_index)
	var slot_ui = slots[slot_index]
	
	_update_slot_visual(slot_ui, slot_data)

func _update_slot_visual(slot_ui: PanelContainer, slot_data):
	var content = slot_ui.get_child(0)
	var icon = content.get_node_or_null("Icon")
	var count_label = content.get_node_or_null("CountLabel")
	
	if slot_data == null or slot_data.is_empty():
		# Empty slot
		if icon: icon.color = Color(0.25, 0.25, 0.25, 0.3)
		if count_label: count_label.text = ""
	else:
		# Has item
		if icon: icon.color = Color(0.4, 0.5, 0.3, 0.8)  # Greenish tint for items
		if count_label and slot_data.count > 1:
			count_label.text = str(slot_data.count)
		elif count_label:
			count_label.text = ""

func refresh_all_slots():
	for i in range(slots.size()):
		if i < InventoryManager.TOTAL_SLOTS:
			var slot_data = InventoryManager.get_slot(i)
			_update_slot_visual(slots[i], slot_data)
