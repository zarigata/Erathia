class_name BuildPieceCard
extends Button
## BuildPieceCard - Individual piece button for the Build UI browser
## Displays piece icon, name, and resource cost with affordability indication

signal piece_selected(piece_id: String)

var piece_data: BuildPieceData = null
var is_affordable: bool = true
var _thumbnail_viewport: SubViewport = null

@onready var icon_rect: TextureRect = $VBoxContainer/IconContainer/IconRect
@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var cost_container: HBoxContainer = $VBoxContainer/CostContainer
@onready var tier_badge: Label = $VBoxContainer/IconContainer/TierBadge
@onready var locked_overlay: ColorRect = $LockedOverlay


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Apply base styling
	_apply_base_style()


func _apply_base_style() -> void:
	custom_minimum_size = Vector2(140, 120)
	
	# Create StyleBoxFlat for normal state
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	style_normal.border_color = Color(0.3, 0.3, 0.35, 1.0)
	style_normal.set_border_width_all(1)
	style_normal.set_corner_radius_all(4)
	style_normal.set_content_margin_all(6)
	add_theme_stylebox_override("normal", style_normal)
	
	# Hover state
	var style_hover := style_normal.duplicate()
	style_hover.bg_color = Color(0.2, 0.2, 0.25, 0.95)
	style_hover.border_color = Color(0.5, 0.5, 0.6, 1.0)
	add_theme_stylebox_override("hover", style_hover)
	
	# Pressed state
	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = Color(0.25, 0.25, 0.3, 1.0)
	style_pressed.border_color = Color(0.6, 0.7, 0.9, 1.0)
	add_theme_stylebox_override("pressed", style_pressed)
	
	# Disabled state
	var style_disabled := style_normal.duplicate()
	style_disabled.bg_color = Color(0.1, 0.1, 0.12, 0.7)
	style_disabled.border_color = Color(0.2, 0.2, 0.22, 0.5)
	add_theme_stylebox_override("disabled", style_disabled)


func setup(data: BuildPieceData) -> void:
	piece_data = data
	
	if not is_node_ready():
		await ready
	
	# Set name
	if name_label:
		name_label.text = data.display_name
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# Set tier badge
	if tier_badge:
		tier_badge.text = "T%d" % data.tier
		_apply_tier_badge_color(data.tier)
	
	# Generate or load icon
	_setup_icon()
	
	# Populate cost display
	_populate_cost_display()
	
	# Update affordability
	update_affordability()


func _apply_tier_badge_color(tier: int) -> void:
	if not tier_badge:
		return
	
	var color: Color
	match tier:
		0:
			color = Color(0.6, 0.5, 0.4)  # Brown - basic
		1:
			color = Color(0.5, 0.6, 0.5)  # Green - workbench
		2:
			color = Color(0.5, 0.5, 0.7)  # Blue - arcane
		3:
			color = Color(0.7, 0.5, 0.7)  # Purple - faction
		_:
			color = Color(0.5, 0.5, 0.5)
	
	tier_badge.add_theme_color_override("font_color", color)
	
	# Style the badge background
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.1, 0.1, 0.12, 0.8)
	badge_style.set_corner_radius_all(3)
	badge_style.set_content_margin_all(2)
	tier_badge.add_theme_stylebox_override("normal", badge_style)


func _setup_icon() -> void:
	if not icon_rect or not piece_data:
		return
	
	# Try to load icon from inventory database first
	var icon_path: String = ""
	if Inventory:
		var info: Dictionary = Inventory.get_resource_info(piece_data.piece_id)
		icon_path = info.get("icon_path", "")
	
	if icon_path and ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
	else:
		# Create placeholder icon based on category
		icon_rect.texture = _create_category_placeholder()
	
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(48, 48)


func _create_category_placeholder() -> ImageTexture:
	var color: Color
	match piece_data.category:
		BuildPieceData.Category.WALL:
			color = Color(0.6, 0.5, 0.4)
		BuildPieceData.Category.FLOOR:
			color = Color(0.5, 0.5, 0.5)
		BuildPieceData.Category.ROOF:
			color = Color(0.5, 0.4, 0.3)
		BuildPieceData.Category.DOOR:
			color = Color(0.4, 0.35, 0.3)
		BuildPieceData.Category.FOUNDATION:
			color = Color(0.45, 0.45, 0.45)
		BuildPieceData.Category.STAIRS:
			color = Color(0.5, 0.45, 0.4)
		_:
			color = Color(0.5, 0.5, 0.5)
	
	# Adjust color based on material type
	match piece_data.material_type:
		BuildPieceData.MaterialType.WOOD:
			color = color.lerp(Color(0.6, 0.4, 0.2), 0.3)
		BuildPieceData.MaterialType.STONE:
			color = color.lerp(Color(0.5, 0.5, 0.55), 0.3)
		BuildPieceData.MaterialType.METAL:
			color = color.lerp(Color(0.55, 0.55, 0.6), 0.3)
		BuildPieceData.MaterialType.FACTION_SPECIFIC:
			color = color.lerp(Color(0.6, 0.4, 0.6), 0.3)
	
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(color)
	
	# Add simple category symbol
	_draw_category_symbol(img, piece_data.category)
	
	return ImageTexture.create_from_image(img)


func _draw_category_symbol(img: Image, category: int) -> void:
	var symbol_color := Color(1, 1, 1, 0.3)
	
	match category:
		BuildPieceData.Category.WALL:
			# Draw vertical rectangle
			for x in range(18, 30):
				for y in range(8, 40):
					img.set_pixel(x, y, symbol_color)
		BuildPieceData.Category.FLOOR:
			# Draw horizontal rectangle
			for x in range(8, 40):
				for y in range(20, 28):
					img.set_pixel(x, y, symbol_color)
		BuildPieceData.Category.ROOF:
			# Draw triangle
			for y in range(8, 32):
				var half_width: int = (y - 8) / 2
				for x in range(24 - half_width, 24 + half_width):
					if x >= 0 and x < 48:
						img.set_pixel(x, y, symbol_color)
		BuildPieceData.Category.DOOR:
			# Draw door shape
			for x in range(16, 32):
				for y in range(10, 38):
					img.set_pixel(x, y, symbol_color)
			# Door handle
			for x in range(26, 30):
				for y in range(22, 26):
					img.set_pixel(x, y, Color(0.8, 0.7, 0.3, 0.5))
		BuildPieceData.Category.FOUNDATION:
			# Draw foundation shape
			for x in range(8, 40):
				for y in range(28, 40):
					img.set_pixel(x, y, symbol_color)
		BuildPieceData.Category.STAIRS:
			# Draw stairs shape
			for step in range(4):
				var y_start: int = 32 - step * 6
				var x_start: int = 10 + step * 7
				for x in range(x_start, x_start + 10):
					for y in range(y_start, y_start + 6):
						if x < 48 and y < 48:
							img.set_pixel(x, y, symbol_color)


func _populate_cost_display() -> void:
	if not cost_container or not piece_data:
		return
	
	# Clear existing cost items
	for child in cost_container.get_children():
		child.queue_free()
	
	# Add cost items
	for resource_type in piece_data.resource_costs:
		var required: int = piece_data.resource_costs[resource_type]
		var current: int = 0
		if Inventory:
			current = Inventory.get_resource_count(resource_type)
		
		var cost_item := _create_cost_item(resource_type, current, required)
		cost_container.add_child(cost_item)


func _create_cost_item(resource_type: String, current: int, required: int) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	
	# Icon
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(14, 14)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	if Inventory:
		var info: Dictionary = Inventory.get_resource_info(resource_type)
		var icon_path: String = info.get("icon_path", "")
		if icon_path and ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		else:
			icon.texture = _create_resource_placeholder(resource_type)
	else:
		icon.texture = _create_resource_placeholder(resource_type)
	
	container.add_child(icon)
	
	# Amount label
	var label := Label.new()
	label.text = "%d" % required
	label.add_theme_font_size_override("font_size", 10)
	
	# Color based on affordability
	if current >= required:
		label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	else:
		label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	
	container.add_child(label)
	
	return container


func _create_resource_placeholder(resource_type: String) -> ImageTexture:
	var color: Color = Color(0.5, 0.5, 0.5)
	
	match resource_type:
		"wood":
			color = Color(0.6, 0.4, 0.2)
		"stone":
			color = Color(0.5, 0.5, 0.55)
		"iron_ore":
			color = Color(0.55, 0.45, 0.4)
		"rare_crystal":
			color = Color(0.6, 0.4, 0.7)
		"faction_core":
			color = Color(0.7, 0.5, 0.3)
		"dirt":
			color = Color(0.45, 0.35, 0.25)
	
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func update_affordability() -> void:
	if not piece_data:
		return
	
	is_affordable = true
	if Inventory:
		is_affordable = Inventory.has_building_resources(piece_data)
	
	# Keep cards clickable - placement is gated by SnapSystem/Inventory
	# Only show visual feedback (red cost/overlay) for unaffordable pieces
	
	# Update locked overlay for visual feedback only
	if locked_overlay:
		locked_overlay.visible = not is_affordable
		locked_overlay.color = Color(0, 0, 0, 0.5)
	
	# Refresh cost display colors
	_populate_cost_display()


func _on_pressed() -> void:
	if piece_data:
		piece_selected.emit(piece_data.piece_id)


func _on_mouse_entered() -> void:
	if piece_data:
		# Could show tooltip here
		pass


func _on_mouse_exited() -> void:
	pass


func get_drag_data(_at_position: Vector2) -> Variant:
	if not piece_data:
		return null
	
	# Create drag preview
	var preview := Label.new()
	preview.text = piece_data.display_name
	preview.add_theme_color_override("font_color", Color.WHITE)
	set_drag_preview(preview)
	
	return {
		"type": "build_piece",
		"piece_id": piece_data.piece_id
	}
