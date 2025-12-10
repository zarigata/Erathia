class_name DebugConsole
extends Control

@onready var input_line = $VBoxContainer/LineEdit
@onready var log_label = $VBoxContainer/RichTextLabel

var player: Player

func _ready():
	hide()
	input_line.text_submitted.connect(_on_text_submitted)
	
	# Find player
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0]

func _toggle_console():
	visible = not visible
	get_tree().paused = visible
	
	if visible:
		input_line.clear()
		input_line.grab_focus()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		input_line.clear()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT: # The ` key
		_toggle_console()
		if visible:
			get_viewport().set_input_as_handled() # Prevent ` from being typed

func _on_text_submitted(text: String):
	input_line.clear()
	# Keep focus for next command
	input_line.grab_focus()
	
	if text.strip_edges() == "":
		return
		
	_log("> " + text)
	_process_command(text.to_lower().strip_edges())

func _log(msg: String):
	log_label.text += msg + "\n"

func _process_command(cmd: String):
	var parts = cmd.split(" ")
	var command = parts[0]
	
	if not player:
		# Try to find player again
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			player = players[0]
	
	match command:
		"fly":
			if player:
				player.toggle_fly_mode()
				_log("Fly mode toggled: " + str(player.fly_mode))
		"noclip":
			if player:
				player.toggle_noclip_mode()
				_log("Noclip mode toggled: " + str(player.noclip_mode))
		"respawn":
			if player:
				player.global_position = Vector3(0, 100, 0)
				player.velocity = Vector3.ZERO
				_log("Respawned player.")
		"xray":
			var vp = get_viewport()
			var current = vp.debug_draw
			if current == Viewport.DEBUG_DRAW_WIREFRAME:
				vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
				_log("X-ray disabled.")
			else:
				vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
				_log("X-ray enabled.")
		"weather":
			if parts.size() < 2:
				_log("Usage: weather [clear|rain|snow]")
				return
			
			var state = parts[1]
			var weather_mgr = get_tree().root.find_child("WeatherManager", true, false)
			if weather_mgr:
				if state == "rain": weather_mgr.set_weather(WeatherManager.WeatherState.RAIN)
				elif state == "snow": weather_mgr.set_weather(WeatherManager.WeatherState.SNOW)
				else: weather_mgr.set_weather(WeatherManager.WeatherState.CLEAR)
				_log("Weather set to: " + state)
			else:
				_log("Error: WeatherManager not found.")
		"time":
			var cycle = get_tree().root.find_child("DirectionalLight3D", true, false)
			if not cycle or not cycle.has_method("_update_sun_position"):
				_log("Error: DayNightCycle not found.")
				return

			if parts.size() < 2:
				_log("Usage: time [set|scale|real] [value]")
				return
				
			var sub = parts[1]
			match sub:
				"set":
					if parts.size() < 3:
						_log("Usage: time set <hour 0-24>")
						return
					var hour = float(parts[2])
					cycle.use_real_time = false
					cycle.current_time = hour * 3600.0
					_log("Time set to hour: " + str(hour))
				"scale":
					if parts.size() < 3:
						_log("Usage: time scale <multiplier>")
						return
					var s = float(parts[2])
					cycle.use_real_time = false
					cycle.time_scale = s
					_log("Time scale set to: " + str(s))
				"real":
					cycle.use_real_time = not cycle.use_real_time
					_log("Real-time sync: " + str(cycle.use_real_time))
				_:
					_log("Unknown time command.")
		"help":
			_log("Commands: fly, noclip, respawn, xray, weather [...], time [set/scale/real]")
		_:
			_log("Unknown command: " + command)
