extends Node
## Developer Console Singleton
##
## Provides command execution for debug/cheat functionality.
## Registered as autoload "DevConsole" in project.godot

# Signals
signal command_executed(command: String, success: bool, message: String)
signal cheat_toggled(cheat_name: String, enabled: bool)

# Cheat state flags
var god_mode: bool = false
var fly_mode: bool = false
var xray_mode: bool = false
var noclip_mode: bool = false
var speed_multiplier: float = 1.0

# Command registry: maps command name to callable
var _commands: Dictionary = {}

# Command history for autocomplete
var command_history: Array[String] = []
const MAX_HISTORY: int = 50

# Position bookmarks
var _saved_positions: Dictionary = {}

# Child managers
var xray_manager: Node = null


func _ready() -> void:
	_register_core_commands()
	_setup_xray_manager()


func _setup_xray_manager() -> void:
	var xray_script := load("res://_core/xray_manager.gd")
	if xray_script:
		xray_manager = xray_script.new()
		xray_manager.name = "XRayManager"
		add_child(xray_manager)


func _register_core_commands() -> void:
	register_command("help", _cmd_help, "List all available commands")
	register_command("god", _cmd_god, "Toggle god mode (invincibility)")
	register_command("fly", _cmd_fly, "Toggle fly mode (free 3D movement)")
	register_command("xray", _cmd_xray, "Toggle x-ray vision (transparent terrain)")
	register_command("noclip", _cmd_noclip, "Toggle noclip (pass through terrain)")
	register_command("speed", _cmd_speed, "Set movement speed multiplier: speed <multiplier>")
	register_command("tp", _cmd_teleport, "Teleport to coordinates: tp <x> <y> <z>")
	register_command("pos", _cmd_pos, "Show current player position")
	register_command("save_pos", _cmd_save_pos, "Save current position: save_pos <name>")
	register_command("load_pos", _cmd_load_pos, "Teleport to saved position: load_pos <name>")
	register_command("biome", _cmd_biome, "Show current biome info")
	register_command("spawn", _cmd_spawn, "Add resources to inventory: spawn <resource> <amount>")
	register_command("clear_inventory", _cmd_clear_inventory, "Clear all inventory items")
	register_command("reload_terrain", _cmd_reload_terrain, "Force terrain regeneration")
	register_command("cheats", _cmd_cheats, "List all active cheats")
	register_command("clear", _cmd_clear, "Clear console history")
	# Vegetation commands
	register_command("veg_stats", _cmd_veg_stats, "Show vegetation instance statistics")
	register_command("veg_reload", _cmd_veg_reload, "Reload all vegetation")
	register_command("veg_toggle", _cmd_veg_toggle, "Toggle vegetation type: veg_toggle <tree|bush|rock|grass>")
	register_command("veg_show_zones", _cmd_veg_show_zones, "Toggle vegetation placement zone visualization")
	register_command("veg_clear_cache", _cmd_veg_clear_cache, "Clear vegetation mesh cache")


## Register a new command
func register_command(name: String, callable: Callable, description: String = "") -> void:
	_commands[name] = {
		"callable": callable,
		"description": description
	}


## Get list of all command names
func get_command_names() -> Array[String]:
	var names: Array[String] = []
	for key in _commands.keys():
		names.append(key)
	names.sort()
	return names


## Get command description
func get_command_description(name: String) -> String:
	if _commands.has(name):
		return _commands[name].description
	return ""


## Execute a command string
func execute_command(input: String) -> void:
	var trimmed := input.strip_edges()
	if trimmed.is_empty():
		return
	
	# Add to history
	if command_history.is_empty() or command_history[-1] != trimmed:
		command_history.append(trimmed)
		if command_history.size() > MAX_HISTORY:
			command_history.pop_front()
	
	# Parse command
	var parts := trimmed.split(" ", false)
	if parts.is_empty():
		return
	
	var cmd_name := parts[0].to_lower()
	var args: Array[String] = []
	for i in range(1, parts.size()):
		args.append(parts[i])
	
	# Execute
	if not _commands.has(cmd_name):
		command_executed.emit(input, false, "Unknown command: %s" % cmd_name)
		return
	
	var cmd_data: Dictionary = _commands[cmd_name]
	var callable: Callable = cmd_data.callable
	var result: String = callable.call(args)
	var success := not result.begins_with("Error:")
	command_executed.emit(input, success, result)


## Get suggestions for partial input
func get_suggestions(partial: String) -> Array[String]:
	var suggestions: Array[String] = []
	var lower := partial.to_lower()
	for cmd_name in _commands.keys():
		if cmd_name.begins_with(lower):
			suggestions.append(cmd_name)
	suggestions.sort()
	return suggestions


## Get player node
func _get_player() -> CharacterBody3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as CharacterBody3D
	# Fallback: find by path
	var root := get_tree().current_scene
	if root:
		var player := root.get_node_or_null("Player")
		if player is CharacterBody3D:
			return player
	return null


# =============================================================================
# COMMAND IMPLEMENTATIONS
# =============================================================================

func _cmd_help(args: Array[String]) -> String:
	var lines: Array[String] = ["Available commands:"]
	var names := get_command_names()
	for cmd_name in names:
		var desc := get_command_description(cmd_name)
		lines.append("  %s - %s" % [cmd_name, desc])
	return "\n".join(lines)


func _cmd_god(args: Array[String]) -> String:
	god_mode = not god_mode
	cheat_toggled.emit("god", god_mode)
	return "God mode: %s" % ("ON" if god_mode else "OFF")


func _cmd_fly(args: Array[String]) -> String:
	fly_mode = not fly_mode
	cheat_toggled.emit("fly", fly_mode)
	return "Fly mode: %s" % ("ON" if fly_mode else "OFF")


func _cmd_xray(args: Array[String]) -> String:
	xray_mode = not xray_mode
	cheat_toggled.emit("xray", xray_mode)
	if xray_manager:
		if xray_mode:
			xray_manager.enable_xray()
		else:
			xray_manager.disable_xray()
	return "X-Ray mode: %s" % ("ON" if xray_mode else "OFF")


func _cmd_noclip(args: Array[String]) -> String:
	noclip_mode = not noclip_mode
	cheat_toggled.emit("noclip", noclip_mode)
	return "Noclip mode: %s" % ("ON" if noclip_mode else "OFF")


func _cmd_speed(args: Array[String]) -> String:
	if args.is_empty():
		return "Current speed multiplier: %.1f" % speed_multiplier
	
	var value := args[0].to_float()
	if value <= 0.0:
		return "Error: Speed must be positive"
	
	var old_multiplier := speed_multiplier
	speed_multiplier = clampf(value, 0.1, 20.0)
	
	# Treat values <= 1.0 as disabling the speed cheat
	var is_speed_cheat := speed_multiplier > 1.0
	var was_speed_cheat := old_multiplier > 1.0
	
	# Only emit if state changed
	if is_speed_cheat != was_speed_cheat:
		cheat_toggled.emit("speed", is_speed_cheat)
	
	return "Speed multiplier set to: %.1f" % speed_multiplier


func _cmd_teleport(args: Array[String]) -> String:
	if args.size() < 3:
		return "Error: Usage: tp <x> <y> <z>"
	
	var x := args[0].to_float()
	var y := args[1].to_float()
	var z := args[2].to_float()
	
	var player := _get_player()
	if not player:
		return "Error: Player not found"
	
	player.global_position = Vector3(x, y, z)
	player.velocity = Vector3.ZERO
	return "Teleported to (%.1f, %.1f, %.1f)" % [x, y, z]


func _cmd_pos(args: Array[String]) -> String:
	var player := _get_player()
	if not player:
		return "Error: Player not found"
	
	var pos := player.global_position
	return "Position: (%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z]


func _cmd_save_pos(args: Array[String]) -> String:
	if args.is_empty():
		return "Error: Usage: save_pos <name>"
	
	var player := _get_player()
	if not player:
		return "Error: Player not found"
	
	var name := args[0]
	_saved_positions[name] = player.global_position
	return "Position '%s' saved" % name


func _cmd_load_pos(args: Array[String]) -> String:
	if args.is_empty():
		if _saved_positions.is_empty():
			return "No saved positions"
		return "Saved positions: %s" % ", ".join(_saved_positions.keys())
	
	var name := args[0]
	if not _saved_positions.has(name):
		return "Error: Position '%s' not found" % name
	
	var player := _get_player()
	if not player:
		return "Error: Player not found"
	
	var pos: Vector3 = _saved_positions[name]
	player.global_position = pos
	player.velocity = Vector3.ZERO
	return "Teleported to '%s' (%.1f, %.1f, %.1f)" % [name, pos.x, pos.y, pos.z]


func _cmd_biome(args: Array[String]) -> String:
	var player := _get_player()
	if not player:
		return "Error: Player not found"
	
	if not BiomeManager:
		return "Error: BiomeManager not available"
	
	var biome_name := BiomeManager.get_biome_at_position(player.global_position)
	return "Current biome: %s" % biome_name


func _cmd_spawn(args: Array[String]) -> String:
	if args.size() < 2:
		return "Error: Usage: spawn <resource> <amount>"
	
	var resource_type := args[0].to_lower()
	var amount := args[1].to_int()
	
	if amount <= 0:
		return "Error: Amount must be positive"
	
	if not Inventory:
		return "Error: Inventory not available"
	
	Inventory.add_resource(resource_type, amount)
	return "Spawned %d x %s" % [amount, resource_type]


func _cmd_clear_inventory(args: Array[String]) -> String:
	if not Inventory:
		return "Error: Inventory not available"
	
	Inventory.clear_all()
	return "Inventory cleared"


func _cmd_reload_terrain(args: Array[String]) -> String:
	var terrain_nodes := get_tree().get_nodes_in_group("terrain")
	if terrain_nodes.is_empty():
		return "Error: No terrain found"
	
	for terrain in terrain_nodes:
		if terrain.has_method("restart_stream"):
			terrain.restart_stream()
	
	return "Terrain regeneration triggered"


func _cmd_cheats(args: Array[String]) -> String:
	var active: Array[String] = []
	if god_mode:
		active.append("god")
	if fly_mode:
		active.append("fly")
	if xray_mode:
		active.append("xray")
	if noclip_mode:
		active.append("noclip")
	if speed_multiplier != 1.0:
		active.append("speed (%.1fx)" % speed_multiplier)
	
	if active.is_empty():
		return "No cheats active"
	return "Active cheats: %s" % ", ".join(active)


func _cmd_clear(args: Array[String]) -> String:
	return "[CLEAR]"


# =============================================================================
# VEGETATION COMMANDS
# =============================================================================

func _cmd_veg_stats(args: Array[String]) -> String:
	if not VegetationManager:
		return "Error: VegetationManager not available"
	
	var stats := VegetationManager.get_stats()
	var lines: Array[String] = [
		"=== Vegetation Statistics ===",
		"Total Instances: %d" % stats["total_instances"],
		"  Trees: %d" % stats["tree_count"],
		"  Bushes: %d" % stats["bush_count"],
		"  Rocks: %d" % stats["rock_count"],
		"  Grass: %d" % stats["grass_count"],
		"Mesh Cache: %d meshes" % stats["cache_size"],
		"Cache Hits: %d | Misses: %d" % [stats["cache_hits"], stats["cache_misses"]]
	]
	return "\n".join(lines)


func _cmd_veg_reload(args: Array[String]) -> String:
	if not VegetationManager:
		return "Error: VegetationManager not available"
	
	VegetationManager.reload_all_vegetation()
	
	# Also reload the instancer if available
	var instancer := _get_vegetation_instancer()
	if instancer:
		instancer.reload_vegetation()
	
	return "Vegetation reload triggered"


func _cmd_veg_toggle(args: Array[String]) -> String:
	if args.is_empty():
		return "Usage: veg_toggle <tree|bush|rock|grass|all>"
	
	var instancer := _get_vegetation_instancer()
	if not instancer:
		return "Error: VegetationInstancer not found"
	
	var type_name := args[0].to_lower()
	var veg_type: int = -1
	
	match type_name:
		"tree", "trees":
			veg_type = VegetationManager.VegetationType.TREE
		"bush", "bushes":
			veg_type = VegetationManager.VegetationType.BUSH
		"rock", "rocks":
			veg_type = VegetationManager.VegetationType.ROCK_SMALL
		"grass":
			veg_type = VegetationManager.VegetationType.GRASS_TUFT
		"all":
			# Toggle all types using public API
			for t: int in VegetationManager.VegetationType.values():
				var type_variants: Dictionary = instancer._multimesh_instances.get(t, {})
				for variant: String in type_variants.keys():
					var mmi: MultiMeshInstance3D = type_variants[variant]
					if mmi:
						mmi.visible = not mmi.visible
			return "Toggled all vegetation types"
		_:
			return "Error: Unknown type '%s'. Use: tree, bush, rock, grass, all" % type_name
	
	if veg_type >= 0:
		var type_variants: Dictionary = instancer._multimesh_instances.get(veg_type, {})
		var toggled := false
		var new_visible := false
		for variant: String in type_variants.keys():
			var mmi: MultiMeshInstance3D = type_variants[variant]
			if mmi:
				mmi.visible = not mmi.visible
				new_visible = mmi.visible
				toggled = true
		if toggled:
			return "%s visibility: %s" % [type_name.capitalize(), "ON" if new_visible else "OFF"]
	
	return "Error: Could not toggle %s" % type_name


func _cmd_veg_show_zones(args: Array[String]) -> String:
	var debug_node := _get_vegetation_debug()
	if not debug_node:
		return "Error: VegetationDebug not found"
	
	debug_node.toggle_zones()
	return "Vegetation zone visualization toggled"


func _cmd_veg_clear_cache(args: Array[String]) -> String:
	if not VegetationManager:
		return "Error: VegetationManager not available"
	
	VegetationManager.clear_mesh_cache()
	return "Vegetation mesh cache cleared"


func _get_vegetation_instancer() -> Node:
	var root := get_tree().current_scene
	if root:
		var terrain := root.get_node_or_null("VoxelLodTerrain")
		if terrain:
			return terrain.get_node_or_null("VegetationInstancer")
	return null


func _get_vegetation_debug() -> Node:
	var root := get_tree().current_scene
	if root:
		var terrain := root.get_node_or_null("VoxelLodTerrain")
		if terrain:
			return terrain.get_node_or_null("VegetationDebug")
	return null
