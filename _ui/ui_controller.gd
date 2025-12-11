extends CanvasLayer
## UIController: Manages all UI states
## ESC = Pause Menu (Settings, Save, Load, Quit)
## TAB = Skyrim-style Compass Menu (Skills, Magic, Items, Map)

@onready var cross_menu = $CrossMenu
@onready var hud = $HUD
@onready var pause_menu: Control = null  # Will be created dynamically

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Hide CrossMenu initially
	if cross_menu:
		cross_menu.visible = false
		cross_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Create Pause Menu
	_create_pause_menu()
	
	# Ensure HUD is visible
	if hud:
		hud.visible = true

func _create_pause_menu():
	pause_menu = Control.new()
	pause_menu.name = "PauseMenu"
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.visible = false
	add_child(pause_menu)
	
	# Dark background
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(bg)
	
	# Center container to properly center the menu
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(center)
	
	# Panel for the menu
	var panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.08, 0.95)
	panel_style.border_color = Color(0.5, 0.45, 0.35)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	
	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	# Margin container for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 25)
	margin.add_theme_constant_override("margin_bottom", 25)
	vbox.add_child(margin)
	
	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(inner_vbox)
	
	# Title
	var title = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	inner_vbox.add_child(title)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	inner_vbox.add_child(spacer)
	
	# Buttons
	_add_pause_button(inner_vbox, "Resume", _on_resume)
	_add_pause_button(inner_vbox, "Settings", _on_settings)
	_add_pause_button(inner_vbox, "Save Game", _on_save)
	_add_pause_button(inner_vbox, "Load Game", _on_load)
	_add_pause_button(inner_vbox, "Quit to Desktop", _on_quit)

func _add_pause_button(parent: Control, text: String, callback: Callable):
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 50)
	btn.pressed.connect(callback)
	
	# Style the button
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_color = Color(0.6, 0.5, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", style)
	
	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.25, 0.22, 0.18, 0.95)
	btn.add_theme_stylebox_override("hover", hover_style)
	
	parent.add_child(btn)

func _input(event):
	# TAB = Skyrim Compass Menu
	if event.is_action_pressed("inventory"):
		_toggle_compass_menu()
	# ESC = Pause Menu
	elif event.is_action_pressed("pause"):
		_toggle_pause_menu()

func _toggle_compass_menu():
	if pause_menu and pause_menu.visible:
		return  # Don't open compass if pause menu is open
	
	if not cross_menu: return
	
	cross_menu.visible = not cross_menu.visible
	get_tree().paused = cross_menu.visible
	
	print("Compass Menu: ", "OPENED" if cross_menu.visible else "CLOSED")
	
	if cross_menu.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if hud: hud.visible = false
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if hud: hud.visible = true

func _toggle_pause_menu():
	if cross_menu and cross_menu.visible:
		# If compass menu is open, close it instead
		cross_menu.visible = false
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if hud: hud.visible = true
		return
	
	if not pause_menu: return
	
	pause_menu.visible = not pause_menu.visible
	get_tree().paused = pause_menu.visible
	
	print("Pause Menu: ", "OPENED" if pause_menu.visible else "CLOSED")
	
	if pause_menu.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Pause Menu Callbacks
func _on_resume():
	_toggle_pause_menu()

func _on_settings():
	print("Settings not implemented yet")

func _on_save():
	print("Save not implemented yet")

func _on_load():
	print("Load not implemented yet")

func _on_quit():
	get_tree().quit()
