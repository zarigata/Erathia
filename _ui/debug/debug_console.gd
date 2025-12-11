class_name DebugConsole
extends Control

@onready var input_line = $VBoxContainer/LineEdit
@onready var log_label = $VBoxContainer/RichTextLabel

var player: Player
var history: Array[String] = []
var history_index: int = -1

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
	if event is InputEventKey and event.pressed:
		if event.is_action_pressed("toggle_console"):
			_toggle_console()
			if visible:
				get_viewport().set_input_as_handled() # Prevent key from being handled elsewhere
			elif visible:
				if event.keycode == KEY_UP:
					_history_up()
					get_viewport().set_input_as_handled()
				elif event.keycode == KEY_DOWN:
					_history_down()
					get_viewport().set_input_as_handled()

func _history_up():
	if history.size() == 0: return
	
	if history_index == -1:
		history_index = history.size() - 1
	elif history_index > 0:
		history_index -= 1
		
	if history_index >= 0 and history_index < history.size():
		input_line.text = history[history_index]
		input_line.caret_column = input_line.text.length()

func _history_down():
	if history.size() == 0 or history_index == -1: return
	
	if history_index < history.size() - 1:
		history_index += 1
		input_line.text = history[history_index]
		input_line.caret_column = input_line.text.length()
	else:
		history_index = -1
		input_line.text = ""

func _on_text_submitted(text: String):
	input_line.clear()
	# Keep focus for next command
	input_line.grab_focus()
	
	if text.strip_edges() == "":
		return
		
	# Add to history
	history.append(text)
	history_index = -1 # Reset history index
	
	_log("> " + text)
	_process_command(text.to_lower().strip_edges())

func _log(msg: String):
	log_label.text += msg + "\n"

func _process_command(cmd: String):
	var parts = cmd.split(" ", false) # false to skip empty strings
	if parts.size() == 0: return
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
		"god":
			if player:
				player.god_mode = not player.god_mode
				_log("God mode: " + str(player.god_mode))
		"heal":
			if player:
				player.heal(1000)
				_log("Player healed.")
		"die", "kill":
			if player:
				player.take_damage(10000)
				_log("You died.")
		"respawn":
			if player:
				player.global_position = Vector3(0, 100, 0)
				player.velocity = Vector3.ZERO
				player.heal(1000)
				_log("Respawned player.")
		"tp":
			if parts.size() < 4:
				_log("Usage: tp <x> <y> <z>")
				return
			if player:
				var x = float(parts[1])
				var y = float(parts[2])
				var z = float(parts[3])
				player.global_position = Vector3(x, y, z)
				_log("Teleported to " + str(Vector3(x, y, z)))
		"speed":
			if parts.size() < 2:
				_log("Usage: speed <value> (default 5.0)")
				return
			# This requires modifying Player or handling it there. 
			# Since WALK_SPEED is const in Player, we can't change it directly unless we remove const or use a multiplier.
			# Let's assume we can't change consts. We might need a 'speed_multiplier' in Player.
			# For now, let's log that we can't fully do it without non-const, 
			# BUT, we can try to set a variable if we add it. 
			# Let's Skip for now or just inform user.
			_log("Speed change not fully implemented (requires Player update to support variable speed).")
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
		"give":
			if parts.size() < 2:
				_log("Usage: give <item_id> [amount]")
				return
			
			var item_id = parts[1]
			var amount = 1
			if parts.size() > 2:
				amount = int(parts[2])
			
			var rem = InventoryManager.add_item(item_id, amount)
			if rem == 0:
				_log("Added " + str(amount) + " " + item_id)
			else:
				_log("Added " + str(amount - rem) + " " + item_id + ". Inventory full.")
		"clear_inv":
			InventoryManager._init_inventory()
			_log("Inventory cleared.")
		"fps":
			# Simple toggle of a persistent label or just log it
			_log("FPS: " + str(Engine.get_frames_per_second()))
		"stats":
			if player:
				_log("Pos: " + str(player.global_position))
				_log("Health: " + str(player.health))
				_log("Biome: " + str(_get_biome_name(player.global_position)))
		"help":
			_log("--- Commands ---")
			_log("Player: fly, noclip, god, heal, die, respawn, tp <x> <y> <z>, give <item> [amt], clear_inv")
			_log("World: weather <type>, time <cmd>, xray")
			_log("Info: fps, stats")
		_:
			_log("Unknown command: " + command)

func _get_biome_name(pos: Vector3) -> String:
	# Attempt to get biome info if possible
	var tm = get_tree().root.find_child("TerrainManager", true, false)
	if tm and tm.biome_manager:
		return "Unknown (BiomeManager access pending)" 
	return "Unknown"
