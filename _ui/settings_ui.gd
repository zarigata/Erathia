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

## Whether the panel is currently visible
var is_open: bool = false


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
	
	# Load current settings
	_load_settings_to_ui()
	
	# Start hidden
	visible = false


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
