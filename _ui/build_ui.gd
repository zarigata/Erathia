extends CanvasLayer
## BuildUI - Main building interface with piece browser and HUD overlay
## Displays when SnapSystem enters build mode, showing categorized pieces,
## resource costs with real-time validation, rotation controls, and placement hints.
##
## Build Mode Toggle Behavior:
## - Press B when idle: Enter build mode + show browser
## - Press B when browser visible: Hide browser (stay in build mode)
## - Press B when browser hidden: Show browser
## - Press ESC: Exit build mode completely

# Node references - Browser Panel
@onready var background: ColorRect = $Background
@onready var browser_panel: PanelContainer = $BrowserPanel
@onready var header_label: Label = $BrowserPanel/VBoxContainer/HeaderContainer/HeaderLabel
@onready var close_button: Button = $BrowserPanel/VBoxContainer/HeaderContainer/CloseButton
@onready var search_edit: LineEdit = $BrowserPanel/VBoxContainer/SearchContainer/SearchEdit
@onready var tier_filter_container: HBoxContainer = $BrowserPanel/VBoxContainer/TierFilterContainer
@onready var category_tabs: TabContainer = $BrowserPanel/VBoxContainer/CategoryTabs

# Node references - HUD Overlay
@onready var hud_overlay: PanelContainer = $HUDOverlay
@onready var piece_name_label: Label = $HUDOverlay/HBoxContainer/PieceNameLabel
@onready var cost_display: HBoxContainer = $HUDOverlay/HBoxContainer/CostDisplay
@onready var rotation_label: Label = $HUDOverlay/HBoxContainer/RotationLabel
@onready var snap_mode_label: Label = $HUDOverlay/HBoxContainer/SnapModeLabel
@onready var validity_indicator: ColorRect = $HUDOverlay/HBoxContainer/ValidityIndicator
@onready var keybind_hints: Label = $HUDOverlay/HBoxContainer/KeybindHints

# Preloaded scenes
var _piece_card_scene: PackedScene = null

# State
var _current_tier_filter: int = -1  # -1 = All tiers
var _current_category: int = BuildPieceData.Category.WALL
var _search_query: String = ""
var _browser_visible: bool = false

# Piece card cache
var _piece_cards: Dictionary = {}  # piece_id -> BuildPieceCard

# Category grid containers
var _category_grids: Dictionary = {}  # Category enum -> GridContainer

# Tier filter buttons
var _tier_buttons: Array[Button] = []

# Recent/Favorites
var _recent_pieces: Array[String] = []
var _favorite_pieces: Array[String] = []
const MAX_RECENT: int = 10

# Tutorial state
var _tutorial_shown: bool = false

# Placement feedback
var _placement_flash_timer: float = 0.0
const PLACEMENT_FLASH_DURATION: float = 0.3


func _ready() -> void:
	# Add to group for easy access
	add_to_group("build_ui")
	
	# Preload piece card scene
	_piece_card_scene = preload("res://_ui/build_piece_card.tscn")
	
	# Setup UI components
	_setup_browser_panel()
	_setup_hud_overlay()
	_setup_tier_filters()
	_setup_category_tabs()
	
	# Connect to viewport size changes for responsive UI
	get_viewport().size_changed.connect(_update_ui_scale)
	_update_ui_scale()
	
	# Connect to SnapSystem signals
	if SnapSystem:
		SnapSystem.build_mode_changed.connect(_on_build_mode_changed)
		SnapSystem.piece_selection_changed.connect(_on_piece_selection_changed)
		SnapSystem.preview_validity_changed.connect(_on_preview_validity_changed)
		SnapSystem.piece_placed.connect(_on_piece_placed)
	
	# Connect to Inventory signals
	if Inventory:
		Inventory.inventory_changed.connect(_on_inventory_changed)
	
	# Connect UI signals
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	if search_edit:
		search_edit.text_changed.connect(_on_search_text_changed)
	
	# Populate piece cards
	_populate_all_categories()
	
	# Load settings
	_load_settings()
	
	# Start hidden
	visible = false
	_browser_visible = false
	if browser_panel:
		browser_panel.visible = false
	if hud_overlay:
		hud_overlay.visible = false
	if background:
		background.visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	
	# Update rotation display in real-time
	if hud_overlay and hud_overlay.visible and SnapSystem:
		_update_rotation_display()
	
	# Handle placement flash feedback
	if _placement_flash_timer > 0.0:
		_placement_flash_timer -= delta
		if hud_overlay:
			var flash_alpha: float = _placement_flash_timer / PLACEMENT_FLASH_DURATION
			hud_overlay.modulate = Color(1.0 + flash_alpha * 0.5, 1.0 + flash_alpha * 0.5, 1.0, 1.0)
		if _placement_flash_timer <= 0.0 and hud_overlay:
			hud_overlay.modulate = Color.WHITE


func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	# Toggle browser visibility with build mode toggle
	if event.is_action_pressed("build_mode_toggle"):
		if _browser_visible:
			# Browser visible -> hide it (stay in build mode)
			_hide_browser()
		else:
			# Browser hidden but build mode active -> show it
			_show_browser()
		get_viewport().set_input_as_handled()
		return
	
	# Close on Escape
	if event.is_action_pressed("ui_cancel"):
		if _browser_visible:
			_hide_browser()
		else:
			if SnapSystem:
				SnapSystem.exit_build_mode()
		get_viewport().set_input_as_handled()


func _setup_browser_panel() -> void:
	if not browser_panel:
		return
	
	# Apply dark semi-transparent style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	browser_panel.add_theme_stylebox_override("panel", style)


func _setup_hud_overlay() -> void:
	if not hud_overlay:
		return
	
	# Apply compact dark style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	style.border_color = Color(0.25, 0.25, 0.3, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	hud_overlay.add_theme_stylebox_override("panel", style)


func _setup_tier_filters() -> void:
	if not tier_filter_container:
		return
	
	# Clear existing buttons
	for child in tier_filter_container.get_children():
		child.queue_free()
	
	_tier_buttons.clear()
	
	# Create "All" button
	var all_btn := Button.new()
	all_btn.text = "All"
	all_btn.toggle_mode = true
	all_btn.button_pressed = true
	all_btn.pressed.connect(_on_tier_filter_pressed.bind(-1))
	_apply_tier_button_style(all_btn, true)
	tier_filter_container.add_child(all_btn)
	_tier_buttons.append(all_btn)
	
	# Create tier buttons
	for tier in range(4):
		var btn := Button.new()
		btn.text = "T%d" % tier
		btn.toggle_mode = true
		btn.pressed.connect(_on_tier_filter_pressed.bind(tier))
		_apply_tier_button_style(btn, false)
		tier_filter_container.add_child(btn)
		_tier_buttons.append(btn)


func _apply_tier_button_style(button: Button, is_active: bool) -> void:
	button.custom_minimum_size = Vector2(40, 28)
	
	var style := StyleBoxFlat.new()
	if is_active:
		style.bg_color = Color(0.3, 0.4, 0.5, 0.9)
		style.border_color = Color(0.5, 0.6, 0.7, 1.0)
	else:
		style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
		style.border_color = Color(0.25, 0.25, 0.3, 1.0)
	
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", style)
	
	var hover_style := style.duplicate()
	hover_style.bg_color = style.bg_color.lightened(0.1)
	button.add_theme_stylebox_override("hover", hover_style)


func _setup_category_tabs() -> void:
	if not category_tabs:
		return
	
	# Clear existing tabs
	for child in category_tabs.get_children():
		child.queue_free()
	
	_category_grids.clear()
	
	# Create tabs for each category
	var categories := [
		{"name": "Walls", "category": BuildPieceData.Category.WALL},
		{"name": "Floors", "category": BuildPieceData.Category.FLOOR},
		{"name": "Roofs", "category": BuildPieceData.Category.ROOF},
		{"name": "Doors", "category": BuildPieceData.Category.DOOR},
		{"name": "Foundations", "category": BuildPieceData.Category.FOUNDATION},
		{"name": "Stairs", "category": BuildPieceData.Category.STAIRS},
	]
	
	for cat_data in categories:
		var scroll := ScrollContainer.new()
		scroll.name = cat_data["name"]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(280, 300)
		
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		
		scroll.add_child(grid)
		category_tabs.add_child(scroll)
		
		_category_grids[cat_data["category"]] = grid
	
	# Connect tab changed signal
	category_tabs.tab_changed.connect(_on_category_tab_changed)


func _populate_all_categories() -> void:
	var piece_db := get_node_or_null("/root/PieceDatabase")
	if not piece_db:
		push_warning("BuildUI: PieceDatabase not available")
		return
	
	# Populate each category grid
	for category in _category_grids.keys():
		_populate_category_grid(category)


func _populate_category_grid(category: int) -> void:
	var grid: GridContainer = _category_grids.get(category)
	if not grid:
		return
	
	var piece_db := get_node_or_null("/root/PieceDatabase")
	if not piece_db:
		return
	
	# Get pieces for this category
	var pieces: Array[BuildPieceData] = piece_db.get_pieces_by_category(category)
	
	# Filter by tier if needed
	if _current_tier_filter >= 0:
		var filtered: Array[BuildPieceData] = []
		for piece in pieces:
			if piece.tier == _current_tier_filter:
				filtered.append(piece)
		pieces = filtered
	
	# Filter by search query
	if not _search_query.is_empty():
		var filtered: Array[BuildPieceData] = []
		var query_lower := _search_query.to_lower()
		for piece in pieces:
			if piece.display_name.to_lower().contains(query_lower) or piece.piece_id.to_lower().contains(query_lower):
				filtered.append(piece)
		pieces = filtered
	
	# Sort by tier, then by name
	pieces.sort_custom(func(a, b):
		if a.tier != b.tier:
			return a.tier < b.tier
		return a.display_name < b.display_name
	)
	
	# Clear grid
	for child in grid.get_children():
		child.visible = false
		child.get_parent().remove_child(child)
	
	# Add piece cards
	for piece_data in pieces:
		var card: BuildPieceCard = _get_or_create_piece_card(piece_data)
		if card.get_parent():
			card.get_parent().remove_child(card)
		grid.add_child(card)
		card.visible = true


func _get_or_create_piece_card(piece_data: BuildPieceData) -> BuildPieceCard:
	if _piece_cards.has(piece_data.piece_id):
		var card: BuildPieceCard = _piece_cards[piece_data.piece_id]
		card.update_affordability()
		return card
	
	# Create new card
	var card: BuildPieceCard = _piece_card_scene.instantiate()
	card.setup(piece_data)
	card.piece_selected.connect(_on_piece_card_selected)
	
	_piece_cards[piece_data.piece_id] = card
	return card


func _on_build_mode_changed(mode: int) -> void:
	match mode:
		SnapSystem.BuildMode.IDLE:
			_hide_all()
		SnapSystem.BuildMode.PREVIEW:
			_show_build_ui()
		SnapSystem.BuildMode.PLACING:
			pass  # Keep current state


func _show_build_ui() -> void:
	visible = true
	
	# Show browser panel
	_show_browser()
	
	# Show HUD overlay
	if hud_overlay:
		hud_overlay.visible = true
	
	# Update HUD with current piece
	_update_hud_overlay()
	
	# Show tutorial if first time
	_check_tutorial()


func _show_browser() -> void:
	_browser_visible = true
	if browser_panel:
		browser_panel.visible = true
	if background:
		background.visible = true
	
	# Show mouse for UI interaction when browser is visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Refresh affordability for all visible cards
	_refresh_all_affordability()


func _hide_browser() -> void:
	_browser_visible = false
	if browser_panel:
		browser_panel.visible = false
	if background:
		background.visible = false
	
	# Return mouse to captured for gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _hide_all() -> void:
	visible = false
	_browser_visible = false
	
	if browser_panel:
		browser_panel.visible = false
	if hud_overlay:
		hud_overlay.visible = false
	if background:
		background.visible = false
	
	# Re-capture mouse when exiting build mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_hud_overlay() -> void:
	if not SnapSystem:
		return
	
	var piece_id: String = SnapSystem.get_selected_piece_id()
	if piece_id.is_empty():
		return
	
	var piece_db := get_node_or_null("/root/PieceDatabase")
	if not piece_db:
		return
	
	var piece_data: BuildPieceData = piece_db.get_piece_data(piece_id)
	if not piece_data:
		return
	
	# Update piece name
	if piece_name_label:
		piece_name_label.text = piece_data.display_name
	
	# Update cost display
	_update_cost_display(piece_data)
	
	# Update rotation
	_update_rotation_display()
	
	# Update snap mode
	_update_snap_mode_display()
	
	# Update validity indicator
	_update_validity_indicator(SnapSystem.is_preview_valid())
	
	# Update keybind hints
	_update_keybind_hints()


func _update_cost_display(piece_data: BuildPieceData) -> void:
	if not cost_display:
		return
	
	# Clear existing
	for child in cost_display.get_children():
		child.queue_free()
	
	# Add cost items
	for resource_type in piece_data.resource_costs:
		var required: int = piece_data.resource_costs[resource_type]
		var current: int = 0
		if Inventory:
			current = Inventory.get_resource_count(resource_type)
		
		var container := HBoxContainer.new()
		container.add_theme_constant_override("separation", 2)
		
		# Icon
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(16, 16)
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
		
		# Amount label with current/required
		var label := Label.new()
		label.text = "%d/%d" % [current, required]
		label.add_theme_font_size_override("font_size", 11)
		
		if current >= required:
			label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		else:
			label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
		
		container.add_child(label)
		cost_display.add_child(container)


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
	
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _update_rotation_display() -> void:
	if not rotation_label or not SnapSystem:
		return
	
	var rotation_rad: float = SnapSystem.get_preview_rotation()
	var rotation_deg: int = int(rad_to_deg(rotation_rad)) % 360
	if rotation_deg < 0:
		rotation_deg += 360
	
	rotation_label.text = "%d°" % rotation_deg


func _update_snap_mode_display() -> void:
	if not snap_mode_label or not SnapSystem:
		return
	
	var snap_mode: int = SnapSystem.get_current_snap_mode()
	
	match snap_mode:
		SnapSystem.SnapMode.SNAP_POINT:
			snap_mode_label.text = "🧲 Snap"
			snap_mode_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		SnapSystem.SnapMode.GRID:
			snap_mode_label.text = "▦ Grid"
			snap_mode_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
		_:
			snap_mode_label.text = "◇ Free"
			snap_mode_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))


func _update_validity_indicator(is_valid: bool) -> void:
	if not validity_indicator:
		return
	
	if is_valid:
		validity_indicator.color = Color(0.3, 0.8, 0.3, 0.9)
	else:
		validity_indicator.color = Color(0.8, 0.3, 0.3, 0.9)


func _update_keybind_hints() -> void:
	if not keybind_hints:
		return
	
	# Get actual keybinds from InputMap
	var rotate_cw := _get_action_key("build_rotate_cw", "E")
	var rotate_ccw := _get_action_key("build_rotate_ccw", "Q")
	var place := _get_action_key("build_place", "LMB")
	var cancel := _get_action_key("build_cancel", "RMB")
	
	keybind_hints.text = "[%s/%s] Rotate  [%s] Place  [%s] Cancel  [B] Menu" % [rotate_ccw, rotate_cw, place, cancel]
	keybind_hints.add_theme_font_size_override("font_size", 10)
	keybind_hints.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))


func _get_action_key(action_name: String, default: String) -> String:
	if not InputMap.has_action(action_name):
		return default
	
	var events := InputMap.action_get_events(action_name)
	if events.is_empty():
		return default
	
	var event: InputEvent = events[0]
	if event is InputEventKey:
		return OS.get_keycode_string(event.keycode) if event.keycode != 0 else OS.get_keycode_string(event.physical_keycode)
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
	
	return default


func _on_piece_selection_changed(piece_id: String) -> void:
	_update_hud_overlay()
	
	# Add to recent pieces
	_add_to_recent(piece_id)


func _on_preview_validity_changed(is_valid: bool) -> void:
	_update_validity_indicator(is_valid)


func _on_piece_placed(_piece: BuildPiece, _position: Vector3) -> void:
	# Flash HUD green
	_placement_flash_timer = PLACEMENT_FLASH_DURATION
	if hud_overlay:
		hud_overlay.modulate = Color(0.5, 1.5, 0.5, 1.0)
	
	# Update cost displays
	_update_hud_overlay()
	_refresh_all_affordability()


func _on_inventory_changed(_slot_index: int) -> void:
	# Refresh affordability for all cards
	_refresh_all_affordability()
	
	# Update HUD cost display
	if hud_overlay and hud_overlay.visible:
		_update_hud_overlay()


func _refresh_all_affordability() -> void:
	for piece_id in _piece_cards:
		var card: BuildPieceCard = _piece_cards[piece_id]
		card.update_affordability()


func _on_tier_filter_pressed(tier: int) -> void:
	_current_tier_filter = tier
	
	# Update button states
	for i in range(_tier_buttons.size()):
		var btn: Button = _tier_buttons[i]
		var btn_tier: int = i - 1  # -1 for "All", 0-3 for tiers
		btn.button_pressed = (btn_tier == tier)
		_apply_tier_button_style(btn, btn_tier == tier)
	
	# Refresh all category grids
	for category in _category_grids.keys():
		_populate_category_grid(category)


func _on_category_tab_changed(tab_index: int) -> void:
	# Map tab index to category
	var categories := [
		BuildPieceData.Category.WALL,
		BuildPieceData.Category.FLOOR,
		BuildPieceData.Category.ROOF,
		BuildPieceData.Category.DOOR,
		BuildPieceData.Category.FOUNDATION,
		BuildPieceData.Category.STAIRS,
	]
	
	if tab_index >= 0 and tab_index < categories.size():
		_current_category = categories[tab_index]


func _on_piece_card_selected(piece_id: String) -> void:
	if SnapSystem:
		# If not in build mode, enter it
		if not SnapSystem.is_in_build_mode():
			SnapSystem.enter_build_mode(piece_id)
		else:
			SnapSystem.change_selected_piece(piece_id)
		
		# Hide browser to allow placement
		_hide_browser()


func _on_close_button_pressed() -> void:
	_hide_browser()


func _on_search_text_changed(new_text: String) -> void:
	_search_query = new_text
	
	# Refresh all category grids with search filter
	for category in _category_grids.keys():
		_populate_category_grid(category)


func _add_to_recent(piece_id: String) -> void:
	# Remove if already in list
	var idx := _recent_pieces.find(piece_id)
	if idx >= 0:
		_recent_pieces.remove_at(idx)
	
	# Add to front
	_recent_pieces.insert(0, piece_id)
	
	# Trim to max
	while _recent_pieces.size() > MAX_RECENT:
		_recent_pieces.pop_back()
	
	# Save to settings
	_save_settings()


func _toggle_favorite(piece_id: String) -> void:
	var idx := _favorite_pieces.find(piece_id)
	if idx >= 0:
		_favorite_pieces.remove_at(idx)
	else:
		_favorite_pieces.append(piece_id)
	
	_save_settings()


func _load_settings() -> void:
	if not GameSettings:
		return
	
	# Load tutorial shown state
	var tutorial_setting = GameSettings.get_setting("tutorial.build_ui_shown")
	if tutorial_setting != null:
		_tutorial_shown = tutorial_setting
	
	# Load recent pieces (would need to add to GameSettings)
	# For now, start fresh each session


func _save_settings() -> void:
	if not GameSettings:
		return
	
	# Save tutorial shown state
	if _tutorial_shown:
		GameSettings.set_setting("tutorial.build_ui_shown", true)


func _check_tutorial() -> void:
	if _tutorial_shown:
		return
	
	# Show tutorial hints (simplified version)
	_tutorial_shown = true
	_save_settings()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data is Dictionary and data.get("type") == "build_piece":
		return true
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary and data.get("type") == "build_piece":
		var piece_id: String = data.get("piece_id", "")
		if not piece_id.is_empty() and SnapSystem:
			SnapSystem.enter_build_mode(piece_id)
			_hide_browser()


func get_ui_scale() -> float:
	if GameSettings:
		var scale_setting = GameSettings.get_setting("ui.scale")
		if scale_setting != null:
			return scale_setting
	return 1.0


func _update_ui_scale() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var scale_factor: float = viewport_size.x / 1920.0
	scale_factor = clampf(scale_factor, 0.5, 2.5)
	
	# Update category tabs scroll container minimum size
	for category in _category_grids.keys():
		var grid: GridContainer = _category_grids.get(category)
		if grid and grid.get_parent() is ScrollContainer:
			var scroll: ScrollContainer = grid.get_parent()
			scroll.custom_minimum_size = Vector2(
				viewport_size.x * 0.2,
				viewport_size.y * 0.4
			)
	
	# Update font sizes based on scale
	if header_label:
		header_label.add_theme_font_size_override("font_size", int(18 * scale_factor))
	if piece_name_label:
		piece_name_label.add_theme_font_size_override("font_size", int(14 * scale_factor))
	if rotation_label:
		rotation_label.add_theme_font_size_override("font_size", int(12 * scale_factor))
	if snap_mode_label:
		snap_mode_label.add_theme_font_size_override("font_size", int(11 * scale_factor))
	if keybind_hints:
		keybind_hints.add_theme_font_size_override("font_size", int(10 * scale_factor))


func is_browser_visible() -> bool:
	return _browser_visible
