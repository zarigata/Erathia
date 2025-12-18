extends CanvasLayer
## Developer Console UI Overlay
##
## Provides visual interface for the DevConsole singleton.
## Toggle with backtick (`) key.

@onready var panel: PanelContainer = $Panel
@onready var history_label: RichTextLabel = $Panel/VBoxContainer/ScrollContainer/HistoryLabel
@onready var input_line: LineEdit = $Panel/VBoxContainer/InputContainer/InputLine
@onready var scroll_container: ScrollContainer = $Panel/VBoxContainer/ScrollContainer
@onready var suggestions_popup: PanelContainer = $Panel/VBoxContainer/InputContainer/SuggestionsPopup
@onready var suggestions_list: ItemList = $Panel/VBoxContainer/InputContainer/SuggestionsPopup/SuggestionsList

var _history_index: int = -1
var _visible: bool = false
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _autocomplete_enabled: bool = true
var _max_history_lines: int = 100

const MAX_HISTORY_LINES: int = 100


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	
	# Add to group for discovery by debug_settings
	add_to_group("dev_console_ui")
	
	panel.visible = false
	suggestions_popup.visible = false
	
	# Connect to DevConsole signals
	if DevConsole:
		DevConsole.command_executed.connect(_on_command_executed)
	
	# Connect input signals
	input_line.text_submitted.connect(_on_input_submitted)
	input_line.text_changed.connect(_on_input_changed)
	suggestions_list.item_activated.connect(_on_suggestion_activated)
	
	# Initial message
	_append_to_history("[color=gray]Developer Console - Type 'help' for commands[/color]")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_dev_console"):
		_toggle_console()
		get_viewport().set_input_as_handled()
		return
	
	if not _visible:
		return
	
	# Handle escape to close
	if event.is_action_pressed("ui_cancel"):
		_hide_console()
		get_viewport().set_input_as_handled()
		return
	
	# Handle up/down for history navigation
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			_navigate_history(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			_navigate_history(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB:
			_autocomplete()
			get_viewport().set_input_as_handled()


func _toggle_console() -> void:
	if _visible:
		_hide_console()
	else:
		_show_console()


func _show_console() -> void:
	_visible = true
	panel.visible = true
	
	# Store and change mouse mode
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Focus input
	input_line.grab_focus()
	input_line.clear()
	_history_index = -1


func _hide_console() -> void:
	_visible = false
	panel.visible = false
	suggestions_popup.visible = false
	
	# Restore mouse mode
	Input.mouse_mode = _previous_mouse_mode
	
	# Release focus
	input_line.release_focus()


func _on_input_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	
	# Execute command
	if DevConsole:
		DevConsole.execute_command(text)
	
	# Clear input and reset history navigation
	input_line.clear()
	_history_index = -1
	suggestions_popup.visible = false


func _on_command_executed(command: String, success: bool, message: String) -> void:
	# Handle clear command
	if message == "[CLEAR]":
		history_label.clear()
		_append_to_history("[color=gray]Console cleared[/color]")
		return
	
	# Add command to history
	_append_to_history("[color=white]> %s[/color]" % command)
	
	# Add result with color coding
	if success:
		_append_to_history("[color=lime]%s[/color]" % message)
	else:
		_append_to_history("[color=red]%s[/color]" % message)


func _append_to_history(text: String) -> void:
	history_label.append_text(text + "\n")
	
	# Scroll to bottom
	await get_tree().process_frame
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value


func _on_input_changed(new_text: String) -> void:
	_update_suggestions(new_text)


func _update_suggestions(text: String) -> void:
	if not _autocomplete_enabled or text.is_empty() or not DevConsole:
		suggestions_popup.visible = false
		return
	
	# Get first word (command name)
	var parts := text.split(" ", false)
	if parts.is_empty():
		suggestions_popup.visible = false
		return
	
	# Only show suggestions for first word (command name)
	if parts.size() > 1:
		suggestions_popup.visible = false
		return
	
	var suggestions := DevConsole.get_suggestions(parts[0])
	
	if suggestions.is_empty():
		suggestions_popup.visible = false
		return
	
	suggestions_list.clear()
	for suggestion in suggestions:
		var desc := DevConsole.get_command_description(suggestion)
		suggestions_list.add_item("%s - %s" % [suggestion, desc])
	
	suggestions_popup.visible = true


func _on_suggestion_activated(index: int) -> void:
	if index < 0:
		return
	
	var item_text := suggestions_list.get_item_text(index)
	var cmd_name := item_text.split(" - ")[0]
	input_line.text = cmd_name + " "
	input_line.caret_column = input_line.text.length()
	suggestions_popup.visible = false
	input_line.grab_focus()


func _autocomplete() -> void:
	if not DevConsole:
		return
	
	var text := input_line.text
	if text.is_empty():
		return
	
	var suggestions := DevConsole.get_suggestions(text)
	if suggestions.size() == 1:
		input_line.text = suggestions[0] + " "
		input_line.caret_column = input_line.text.length()
		suggestions_popup.visible = false
	elif suggestions.size() > 1:
		# Find common prefix
		var common := suggestions[0]
		for suggestion in suggestions:
			var i := 0
			while i < common.length() and i < suggestion.length() and common[i] == suggestion[i]:
				i += 1
			common = common.substr(0, i)
		
		if common.length() > text.length():
			input_line.text = common
			input_line.caret_column = input_line.text.length()


func _navigate_history(direction: int) -> void:
	if not DevConsole or DevConsole.command_history.is_empty():
		return
	
	var history := DevConsole.command_history
	
	if direction < 0:  # Up - older
		if _history_index < 0:
			_history_index = history.size() - 1
		elif _history_index > 0:
			_history_index -= 1
	else:  # Down - newer
		if _history_index >= 0:
			_history_index += 1
			if _history_index >= history.size():
				_history_index = -1
				input_line.clear()
				return
	
	if _history_index >= 0 and _history_index < history.size():
		input_line.text = history[_history_index]
		input_line.caret_column = input_line.text.length()


## Apply settings from debug settings panel
func apply_settings(settings: Dictionary) -> void:
	# Font size for history label
	var font_size: int = settings.get("console_font_size", 14)
	if history_label:
		history_label.add_theme_font_size_override("normal_font_size", font_size)
		history_label.add_theme_font_size_override("bold_font_size", font_size)
		history_label.add_theme_font_size_override("mono_font_size", font_size)
	
	# History length cap
	_max_history_lines = settings.get("console_history_length", 100)
	
	# Autocomplete toggle
	_autocomplete_enabled = settings.get("console_autocomplete", true)
