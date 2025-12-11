class_name CrossMenu
extends Control
## Skyrim-style Compass Menu
## Press TAB to open, use Arrow Keys or WASD to navigate
## UP = Skills, DOWN = Map, LEFT = Magic, RIGHT = Inventory

@onready var menus_container = $Menus
@onready var center_container = $CenterContainer
@onready var center_label = $CenterContainer/Label

# Sub-menu references
@onready var menu_up = $Menus/SkillMenu
@onready var menu_down = $Menus/MapMenu
@onready var menu_left = $Menus/MagicMenu
@onready var menu_right = $Menus/InventoryMenu

enum State { CENTER, UP, DOWN, LEFT, RIGHT }
var current_state = State.CENTER

# Visual elements
var background: ColorRect
var direction_indicators: Dictionary = {}

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Create background overlay
	_create_background()
	
	# Create direction indicators (arrows)
	_create_direction_indicators()
	
	# Setup center label
	_setup_center_label()
	
	# Setup sub-menus
	_setup_submenus()
	
	# Initial state
	_update_visuals()
	print("CrossMenu: Initialized")

func _create_background():
	background = ColorRect.new()
	background.name = "Background"
	background.color = Color(0, 0, 0, 0.75)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	move_child(background, 0)

func _create_direction_indicators():
	var directions = {
		"UP": {"text": "▲ SKILLS", "preset": Control.PRESET_CENTER_TOP, "offset": Vector2(0, 80)},
		"DOWN": {"text": "▼ MAP", "preset": Control.PRESET_CENTER_BOTTOM, "offset": Vector2(0, -80)},
		"LEFT": {"text": "◀ MAGIC", "preset": Control.PRESET_CENTER_LEFT, "offset": Vector2(80, 0)},
		"RIGHT": {"text": "ITEMS ▶", "preset": Control.PRESET_CENTER_RIGHT, "offset": Vector2(-120, 0)}
	}
	
	for dir_name in directions:
		var info = directions[dir_name]
		var indicator = Label.new()
		indicator.name = dir_name + "Indicator"
		indicator.text = info.text
		indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		indicator.set_anchors_preset(info.preset)
		indicator.position = info.offset
		indicator.add_theme_font_size_override("font_size", 24)
		indicator.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
		add_child(indicator)
		direction_indicators[dir_name] = indicator

func _setup_center_label():
	if center_container:
		center_container.set_anchors_preset(Control.PRESET_CENTER)
	
	if center_label:
		center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center_label.add_theme_font_size_override("font_size", 36)
		center_label.add_theme_color_override("font_color", Color(1, 1, 1))

func _setup_submenus():
	if menus_container:
		menus_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Skills Menu (UP)
	if menu_up:
		menu_up.set_anchors_preset(Control.PRESET_FULL_RECT)
		_add_placeholder_content(menu_up, "SKILLS", "Level up your abilities here.\n\n(Coming Soon)")
	
	# Map Menu (DOWN)
	if menu_down:
		menu_down.set_anchors_preset(Control.PRESET_FULL_RECT)
		_add_placeholder_content(menu_down, "MAP", "View the world map.\n\n(Coming Soon)")
	
	# Magic Menu (LEFT)
	if menu_left:
		menu_left.set_anchors_preset(Control.PRESET_FULL_RECT)
		_add_placeholder_content(menu_left, "MAGIC", "Equip and manage spells.\n\n(Coming Soon)")
	
	# Inventory Menu (RIGHT) - Special handling
	if menu_right:
		menu_right.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Inventory will be populated by its own script

func _add_placeholder_content(menu: Control, title: String, description: String):
	# Clear existing children
	for child in menu.get_children():
		if child.name != "GridContainer":  # Keep GridContainer for inventory
			child.queue_free()
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 20)
	menu.add_child(vbox)
	
	# Title
	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 48)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	vbox.add_child(title_lbl)
	
	# Description
	var desc_lbl = Label.new()
	desc_lbl.text = description
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 18)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(desc_lbl)

func _input(event):
	if not visible:
		return
	
	var new_state = current_state
	
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		new_state = State.UP
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_backward"):
		new_state = State.DOWN
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		new_state = State.LEFT
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		new_state = State.RIGHT
	elif event.is_action_pressed("ui_cancel"):
		if current_state != State.CENTER:
			new_state = State.CENTER
	
	if new_state != current_state:
		_navigate(new_state)

func _navigate(new_state: State):
	current_state = new_state
	_update_visuals()
	_animate_transition()
	print("CrossMenu: Navigated to ", State.keys()[current_state])

func _update_visuals():
	# Hide all sub-menus and show direction indicators in CENTER
	var show_indicators = (current_state == State.CENTER)
	
	for dir_name in direction_indicators:
		direction_indicators[dir_name].visible = show_indicators
	
	# Hide all menus first
	if menu_up: menu_up.visible = false
	if menu_down: menu_down.visible = false
	if menu_left: menu_left.visible = false
	if menu_right: menu_right.visible = false
	
	# Show center label only in CENTER state
	if center_container:
		center_container.visible = (current_state == State.CENTER)
	
	# Show the selected menu
	match current_state:
		State.UP:
			if menu_up: menu_up.visible = true
		State.DOWN:
			if menu_down: menu_down.visible = true
		State.LEFT:
			if menu_left: menu_left.visible = true
		State.RIGHT:
			if menu_right: menu_right.visible = true
		State.CENTER:
			pass  # Direction indicators are shown

func _animate_transition():
	# Simple fade animation using Tween
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Get the current visible menu
	var target_menu: Control = null
	match current_state:
		State.UP: target_menu = menu_up
		State.DOWN: target_menu = menu_down
		State.LEFT: target_menu = menu_left
		State.RIGHT: target_menu = menu_right
	
	if target_menu:
		# Start slightly transparent and fade in
		target_menu.modulate.a = 0.0
		tween.tween_property(target_menu, "modulate:a", 1.0, 0.2)

func reset_state():
	current_state = State.CENTER
	_update_visuals()
