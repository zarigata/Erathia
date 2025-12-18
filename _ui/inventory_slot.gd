extends PanelContainer
## InventorySlot - UI component for a single inventory slot
## Supports drag-drop, visual states, and automatic updates from Inventory singleton

## Slot index in the inventory
@export var slot_index: int = 0
## Whether to show empty slot background
@export var show_empty: bool = true

## Visual states
enum SlotState { NORMAL, HOVER, SELECTED, EMPTY, DRAG_VALID, DRAG_INVALID }

## Current visual state
var current_state: SlotState = SlotState.EMPTY

## Child node references
@onready var icon_rect: TextureRect = $MarginContainer/IconRect
@onready var amount_label: Label = $AmountLabel
@onready var highlight_overlay: ColorRect = $HighlightOverlay

## Cached slot data
var _cached_data: Dictionary = {}

## Colors for visual states
const COLOR_NORMAL := Color(0.15, 0.15, 0.18, 1.0)
const COLOR_HOVER := Color(0.25, 0.25, 0.3, 1.0)
const COLOR_SELECTED := Color(0.3, 0.4, 0.5, 1.0)
const COLOR_EMPTY := Color(0.1, 0.1, 0.12, 1.0)
const COLOR_DRAG_VALID := Color(0.2, 0.4, 0.2, 1.0)
const COLOR_DRAG_INVALID := Color(0.4, 0.2, 0.2, 1.0)
const COLOR_HIGHLIGHT_HOVER := Color(1.0, 1.0, 1.0, 0.1)
const COLOR_HIGHLIGHT_NONE := Color(1.0, 1.0, 1.0, 0.0)


func _ready() -> void:
	# Connect to Inventory signals
	if Inventory:
		Inventory.inventory_changed.connect(_on_inventory_changed)
	
	# Setup mouse events
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Initial update
	update_display()


func _on_inventory_changed(changed_slot_index: int) -> void:
	if changed_slot_index == slot_index:
		update_display()


func update_display() -> void:
	if not Inventory:
		return
	
	_cached_data = Inventory.get_slot_data(slot_index)
	
	if _cached_data.is_empty():
		# Empty slot
		_set_state(SlotState.EMPTY)
		if icon_rect:
			icon_rect.texture = null
		if amount_label:
			amount_label.text = ""
			amount_label.visible = false
	else:
		# Slot has item
		_set_state(SlotState.NORMAL)
		
		var resource_type: String = _cached_data.get("resource_type", "")
		var amount: int = _cached_data.get("amount", 0)
		
		# Load icon
		if icon_rect:
			var info: Dictionary = Inventory.get_resource_info(resource_type)
			var icon_path: String = info.get("icon_path", "")
			if icon_path and ResourceLoader.exists(icon_path):
				icon_rect.texture = load(icon_path)
			else:
				# Use placeholder colored texture
				icon_rect.texture = _create_placeholder_texture(resource_type)
		
		# Update amount label
		if amount_label:
			if amount > 1:
				amount_label.text = str(amount)
				amount_label.visible = true
			else:
				amount_label.text = ""
				amount_label.visible = false


func _set_state(new_state: SlotState) -> void:
	current_state = new_state
	_update_visuals()


func _update_visuals() -> void:
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if not style:
		style = StyleBoxFlat.new()
	
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	
	match current_state:
		SlotState.NORMAL:
			style.bg_color = COLOR_NORMAL
		SlotState.HOVER:
			style.bg_color = COLOR_HOVER
			style.border_color = Color(0.5, 0.5, 0.6, 1.0)
		SlotState.SELECTED:
			style.bg_color = COLOR_SELECTED
			style.border_color = Color(0.6, 0.7, 0.8, 1.0)
		SlotState.EMPTY:
			style.bg_color = COLOR_EMPTY if show_empty else Color.TRANSPARENT
		SlotState.DRAG_VALID:
			style.bg_color = COLOR_DRAG_VALID
			style.border_color = Color(0.4, 0.8, 0.4, 1.0)
		SlotState.DRAG_INVALID:
			style.bg_color = COLOR_DRAG_INVALID
			style.border_color = Color(0.8, 0.4, 0.4, 1.0)
	
	add_theme_stylebox_override("panel", style)
	
	# Update highlight overlay
	if highlight_overlay:
		highlight_overlay.color = COLOR_HIGHLIGHT_HOVER if current_state == SlotState.HOVER else COLOR_HIGHLIGHT_NONE


func _on_mouse_entered() -> void:
	if current_state != SlotState.DRAG_VALID and current_state != SlotState.DRAG_INVALID:
		if _cached_data.is_empty():
			_set_state(SlotState.HOVER)
		else:
			_set_state(SlotState.HOVER)


func _on_mouse_exited() -> void:
	if current_state != SlotState.DRAG_VALID and current_state != SlotState.DRAG_INVALID:
		if _cached_data.is_empty():
			_set_state(SlotState.EMPTY)
		else:
			_set_state(SlotState.NORMAL)


# ============================================================================
# DRAG AND DROP (Step 13)
# ============================================================================

func _get_drag_data(_at_position: Vector2) -> Variant:
	if _cached_data.is_empty():
		return null
	
	var drag_amount: int = _cached_data.get("amount", 0)
	
	# Shift+drag to split stack
	if Input.is_key_pressed(KEY_SHIFT) and drag_amount > 1:
		@warning_ignore("integer_division")
		var split_amount: int = drag_amount / 2  # Split half by default
		if split_amount > 0:
			var new_slot_index: int = Inventory.split_slot(slot_index, split_amount)
			if new_slot_index != -1:
				# Drag the newly split stack
				var new_slot_data: Dictionary = Inventory.get_slot_data(new_slot_index)
				var split_preview := _create_drag_preview_for_amount(split_amount)
				set_drag_preview(split_preview)
				return {
					"type": "inventory_slot",
					"slot_index": new_slot_index,
					"resource_type": new_slot_data.get("resource_type", ""),
					"amount": split_amount,
					"is_split": true
				}
	
	# Create drag preview
	var preview := _create_drag_preview()
	set_drag_preview(preview)
	
	# Return drag data
	return {
		"type": "inventory_slot",
		"slot_index": slot_index,
		"resource_type": _cached_data.get("resource_type", ""),
		"amount": drag_amount
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		_set_state(SlotState.DRAG_INVALID)
		return false
	
	if data.get("type") != "inventory_slot":
		_set_state(SlotState.DRAG_INVALID)
		return false
	
	var from_index: int = data.get("slot_index", -1)
	if from_index == slot_index:
		_set_state(SlotState.DRAG_INVALID)
		return false  # Can't drop on self
	
	# Can always drop on empty slot
	if _cached_data.is_empty():
		_set_state(SlotState.DRAG_VALID)
		return true
	
	var from_type: String = data.get("resource_type", "")
	var to_type: String = _cached_data.get("resource_type", "")
	
	# Same resource type - can merge (valid)
	if from_type == to_type:
		_set_state(SlotState.DRAG_VALID)
		return true
	
	# Different types - can swap (valid but show as swap indicator)
	_set_state(SlotState.DRAG_VALID)
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	
	var from_index: int = data.get("slot_index", -1)
	if from_index < 0 or from_index == slot_index:
		return
	
	if not Inventory:
		return
	
	var from_type: String = data.get("resource_type", "")
	var to_type: String = _cached_data.get("resource_type", "")
	
	# If same type, try to merge
	if not _cached_data.is_empty() and from_type == to_type:
		Inventory.merge_slots(from_index, slot_index)
	else:
		# Swap slots
		Inventory.swap_slots(from_index, slot_index)
	
	# Play drop SFX if available
	_play_drop_sfx()
	
	# Reset visual state
	_set_state(SlotState.NORMAL if not _cached_data.is_empty() else SlotState.EMPTY)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		var drag_data: Variant = get_viewport().gui_get_drag_data()
		if drag_data is Dictionary and drag_data.get("type") == "inventory_slot":
			# Check if drag ended outside inventory UI
			var inventory_ui := get_tree().get_first_node_in_group("inventory_ui")
			if inventory_ui and not inventory_ui.visible:
				# Inventory closed during drag - reset state only
				pass
			else:
				var mouse_pos := get_viewport().get_mouse_position()
				var inventory_rect := _get_inventory_screen_rect()
				
				# If mouse is outside inventory bounds, drop to world
				if inventory_rect.size.x > 0 and not inventory_rect.has_point(mouse_pos):
					_drop_to_world(drag_data)
		
		# Reset state when drag ends
		if _cached_data.is_empty():
			_set_state(SlotState.EMPTY)
		else:
			_set_state(SlotState.NORMAL)


func _get_inventory_screen_rect() -> Rect2:
	var inventory_ui := get_tree().get_first_node_in_group("inventory_ui")
	if not inventory_ui:
		return Rect2()
	
	var main_panel := inventory_ui.get_node_or_null("CenterContainer/MainPanel")
	if not main_panel:
		# Try alternative path - look for any PanelContainer child
		for child in inventory_ui.get_children():
			if child is PanelContainer:
				return child.get_global_rect()
		# Fallback to inventory_ui itself
		if inventory_ui is Control:
			return inventory_ui.get_global_rect()
		return Rect2()
	
	return main_panel.get_global_rect()


func _drop_to_world(drag_data: Dictionary) -> void:
	var drag_slot_index: int = drag_data.get("slot_index", -1)
	var drop_amount: int = drag_data.get("amount", 0)
	
	if drag_slot_index < 0 or not Inventory:
		return
	
	# Get player position for drop location
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	var drop_position: Vector3 = player.global_position + player.global_transform.basis.z * -1.5
	drop_position.y += 1.0  # Drop at chest height
	
	# Drop item
	Inventory.drop_item_to_world(drag_slot_index, drop_amount, drop_position)


func _create_drag_preview_for_amount(amount: int) -> Control:
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(48, 48)
	preview.modulate.a = 0.8
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	preview.add_theme_stylebox_override("panel", style)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	preview.add_child(margin)
	
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	
	var tex_rect := TextureRect.new()
	tex_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.custom_minimum_size = Vector2(32, 32)
	
	if icon_rect and icon_rect.texture:
		tex_rect.texture = icon_rect.texture
	else:
		var resource_type: String = _cached_data.get("resource_type", "")
		tex_rect.texture = _create_placeholder_texture(resource_type)
	
	vbox.add_child(tex_rect)
	
	# Add amount label for split preview
	if amount > 1:
		var amount_lbl := Label.new()
		amount_lbl.text = str(amount)
		amount_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount_lbl.add_theme_font_size_override("font_size", 10)
		amount_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8, 1.0))
		vbox.add_child(amount_lbl)
	
	return preview


func _play_drop_sfx() -> void:
	# Hook for SFX - plays drop sound if AudioManager exists
	if Engine.has_singleton("AudioManager"):
		var audio_manager = Engine.get_singleton("AudioManager")
		if audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("inventory_drop")
	# Alternative: Check for autoload
	elif has_node("/root/AudioManager"):
		var audio_manager = get_node("/root/AudioManager")
		if audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("inventory_drop")


func _create_drag_preview() -> Control:
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(48, 48)
	preview.modulate.a = 0.8
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	preview.add_theme_stylebox_override("panel", style)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	preview.add_child(margin)
	
	var tex_rect := TextureRect.new()
	tex_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.custom_minimum_size = Vector2(40, 40)
	
	if icon_rect and icon_rect.texture:
		tex_rect.texture = icon_rect.texture
	else:
		var resource_type: String = _cached_data.get("resource_type", "")
		tex_rect.texture = _create_placeholder_texture(resource_type)
	
	margin.add_child(tex_rect)
	
	return preview


func _create_placeholder_texture(resource_type: String) -> ImageTexture:
	# Create a simple colored placeholder based on resource type
	var color: Color = Color.GRAY
	if MiningSystem:
		color = MiningSystem.get_resource_color(resource_type)
	
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(color)
	
	# Add a simple border
	for x in range(32):
		img.set_pixel(x, 0, color.darkened(0.3))
		img.set_pixel(x, 31, color.darkened(0.3))
	for y in range(32):
		img.set_pixel(0, y, color.darkened(0.3))
		img.set_pixel(31, y, color.darkened(0.3))
	
	return ImageTexture.create_from_image(img)


## Get tooltip text for this slot
func _get_slot_tooltip_text() -> String:
	if _cached_data.is_empty():
		return "Empty Slot"
	
	var resource_type: String = _cached_data.get("resource_type", "")
	var amount: int = _cached_data.get("amount", 0)
	
	if Inventory:
		var info: Dictionary = Inventory.get_resource_info(resource_type)
		var display_name: String = info.get("display_name", resource_type.capitalize())
		var description: String = info.get("description", "")
		var max_stack: int = info.get("stack_size", 100)
		
		return "%s\n%s\nAmount: %d/%d" % [display_name, description, amount, max_stack]
	
	return "%s x%d" % [resource_type.capitalize(), amount]


func _make_custom_tooltip(_for_text: String) -> Object:
	var tooltip := PanelContainer.new()
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	tooltip.add_theme_stylebox_override("panel", style)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	tooltip.add_child(margin)
	
	var label := Label.new()
	label.text = _get_slot_tooltip_text()
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	margin.add_child(label)
	
	return tooltip
