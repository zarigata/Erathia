class_name PauseMenu
extends Control

@onready var resume_btn = $Panel/VBoxContainer/ResumeButton
@onready var quit_btn = $Panel/VBoxContainer/QuitButton

func _ready():
	# Resume button logic
	resume_btn.pressed.connect(_on_resume_pressed)
	
	# Quit button logic
	quit_btn.pressed.connect(_on_quit_pressed)
	
	# Ensure menu is hidden at start
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS # Important: Needs to process while paused

func _input(event):
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _toggle_pause():
	var is_paused = not get_tree().paused
	get_tree().paused = is_paused
	visible = is_paused
	
	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if resume_btn:
			resume_btn.grab_focus() # For controller support
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_resume_pressed():
	_toggle_pause()

func _on_quit_pressed():
	get_tree().quit()
