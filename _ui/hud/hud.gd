extends Control
## HUD: Heads-Up Display with Health, Stamina, Magic bars and Hotbar
## Skyrim-inspired minimalist design

# Scene node references
@onready var status_container = $Status
@onready var health_bar = $Status/Health
@onready var stamina_bar = $Status/Stamina
@onready var magic_bar = $Status/Magic
@onready var hotbar_container = $Hotbar

func _ready():
	# Make sure HUD fills the screen
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Style the existing bars
	_style_status_bars()
	
	# Create hotbar slots
	_create_hotbar()
	
	# Create compass
	_create_compass()
	
	print("HUD: Initialized successfully")

func _style_status_bars():
	if not status_container:
		push_error("HUD: Status container not found!")
		return
	
	# Position status container
	status_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_container.custom_minimum_size = Vector2(220, 100)
	status_container.position = Vector2(20, -120)
	
	# Style each bar
	if health_bar:
		_style_bar(health_bar, Color(0.8, 0.15, 0.15))
		health_bar.value = 75
	
	if stamina_bar:
		_style_bar(stamina_bar, Color(0.2, 0.7, 0.2))
		stamina_bar.value = 100
	
	if magic_bar:
		_style_bar(magic_bar, Color(0.2, 0.3, 0.8))
		magic_bar.value = 50

func _style_bar(bar: ProgressBar, color: Color):
	bar.custom_minimum_size = Vector2(180, 22)
	bar.show_percentage = false
	
	# Fill style
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill_style)
	
	# Background style
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	bg_style.border_color = Color(0.3, 0.3, 0.3)
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg_style)

func _create_hotbar():
	if not hotbar_container:
		push_error("HUD: Hotbar container not found!")
		return
	
	# Clear existing children
	for child in hotbar_container.get_children():
		child.queue_free()
	
	# Position hotbar
	hotbar_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_container.custom_minimum_size = Vector2(450, 60)
	hotbar_container.position = Vector2(-225, -70)
	hotbar_container.add_theme_constant_override("separation", 5)
	
	# Create 8 slots
	for i in range(8):
		var slot = _create_hotbar_slot(i + 1)
		hotbar_container.add_child(slot)

func _create_hotbar_slot(number: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(52, 52)
	
	# Panel style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.9)
	style.border_color = Color(0.5, 0.45, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	
	# Content container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	# Icon placeholder
	var icon_rect = ColorRect.new()
	icon_rect.custom_minimum_size = Vector2(30, 30)
	icon_rect.color = Color(0.3, 0.3, 0.3, 0.5)
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(icon_rect)
	
	# Number label
	var num_label = Label.new()
	num_label.text = str(number)
	num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_label.add_theme_font_size_override("font_size", 11)
	num_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	vbox.add_child(num_label)
	
	return panel

func _create_compass():
	# Compass bar at top center
	var compass = Panel.new()
	compass.name = "Compass"
	compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass.custom_minimum_size = Vector2(350, 28)
	compass.position = Vector2(-175, 15)
	
	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.7)
	style.border_color = Color(0.3, 0.3, 0.3, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	compass.add_theme_stylebox_override("panel", style)
	
	# Direction label
	var dir_label = Label.new()
	dir_label.name = "DirectionLabel"
	dir_label.text = "— N —"
	dir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dir_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dir_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	dir_label.add_theme_font_size_override("font_size", 14)
	dir_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	compass.add_child(dir_label)
	
	add_child(compass)

# Public API
func update_health(current: float, maximum: float):
	if health_bar:
		health_bar.value = (current / maximum) * 100.0

func update_stamina(current: float, maximum: float):
	if stamina_bar:
		stamina_bar.value = (current / maximum) * 100.0

func update_magic(current: float, maximum: float):
	if magic_bar:
		magic_bar.value = (current / maximum) * 100.0

