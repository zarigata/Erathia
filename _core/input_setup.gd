extends Node

func _ready():
	_setup_inputs()

func _setup_inputs():
	# Keyboard Inputs
	var key_inputs = {
		"move_forward": [KEY_W, KEY_UP],
		"move_backward": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"pause": [KEY_ESCAPE]
	}
	
	# Joypad Button Inputs
	var joy_inputs = {
		"jump": [JOY_BUTTON_A],
		"sprint": [JOY_BUTTON_LEFT_STICK],
		"pause": [JOY_BUTTON_START]
	}

	# 1. Clear and Add Actions
	var all_actions = key_inputs.keys()
	for a in joy_inputs:
		if not a in all_actions:
			all_actions.append(a)
			
	for action in all_actions:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action)
		
	# 2. Add Keys
	for action in key_inputs:
		for k in key_inputs[action]:
			var ev = InputEventKey.new()
			ev.keycode = k
			InputMap.action_add_event(action, ev)

	# 3. Add Joy Buttons
	for action in joy_inputs:
		for b in joy_inputs[action]:
			var ev = InputEventJoypadButton.new()
			ev.button_index = b
			InputMap.action_add_event(action, ev)
			
	# 4. Add Joy Axes (Analog Movement)
	_setup_joypad_motion("move_left", JOY_AXIS_LEFT_X, -1.0)
	_setup_joypad_motion("move_right", JOY_AXIS_LEFT_X, 1.0)
	_setup_joypad_motion("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_setup_joypad_motion("move_backward", JOY_AXIS_LEFT_Y, 1.0)
	
	print("InputSetup: Fixed Inputs Applied.")

func _setup_joypad_motion(action, axis, value):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		
	var ev = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
