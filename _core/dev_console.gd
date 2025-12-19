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
var infinite_building: bool = false
var infinite_crafting: bool = false

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
	# World seed commands
	register_command("show_seed", _cmd_show_seed, "Show current world seed")
	register_command("set_seed", _cmd_set_seed, "Set world seed: set_seed <value>")
	register_command("regenerate_world", _cmd_regenerate_world, "Generate new random seed and regenerate world")
	register_command("reload_biomes", _cmd_reload_biomes, "Force reload biome map from disk")
	# Pickup/collection commands
	register_command("autocollect", _cmd_autocollect, "Toggle auto-collection: autocollect <on|off>")
	register_command("spawn_pickup", _cmd_spawn_pickup, "Spawn pickup at player: spawn_pickup <resource_type> <amount>")
	register_command("clear_pickups", _cmd_clear_pickups, "Remove all pickups in scene")
	# Building cheat commands
	register_command("infinite_build", _cmd_infinite_build, "Toggle infinite building (no resource cost)")
	register_command("infinite_craft", _cmd_infinite_craft, "Toggle infinite crafting (no resource cost)")
	# World initialization commands
	register_command("set_biome_strength", _cmd_set_biome_strength, "Set biome height modulation: set_biome_strength <0.0-1.0>")
	register_command("prewarm_terrain", _cmd_prewarm_terrain, "Prewarm terrain chunks: prewarm_terrain <radius>")
	register_command("validate_world", _cmd_validate_world, "Run world validation checks")
	register_command("show_biome_boundaries", _cmd_show_biome_boundaries, "Toggle biome boundary debug visualization")
	register_command("world_status", _cmd_world_status, "Show world initialization status")


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
	var root := get_tree().current_scene
	if not root:
		return "Error: No current scene"
	
	var terrain := root.get_node_or_null("VoxelLodTerrain") as VoxelLodTerrain
	if not terrain:
		return "Error: VoxelLodTerrain not found"
	
	# Force terrain regeneration by reassigning the generator
	if terrain.generator:
		terrain.generator = terrain.generator
		return "Terrain regeneration triggered"
	
	return "Error: No generator assigned to terrain"


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
	if infinite_building:
		active.append("infinite_build")
	if infinite_crafting:
		active.append("infinite_craft")
	
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


# =============================================================================
# WORLD SEED COMMANDS
# =============================================================================

func _cmd_show_seed(args: Array[String]) -> String:
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if not seed_manager:
		return "Error: WorldSeedManager not available"
	
	return "Current world seed: %d" % seed_manager.get_world_seed()


func _cmd_set_seed(args: Array[String]) -> String:
	if args.is_empty():
		return "Error: Usage: set_seed <value>"
	
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if not seed_manager:
		return "Error: WorldSeedManager not available"
	
	var seed_value := args[0].to_int()
	if seed_value <= 0:
		return "Error: Seed must be a positive integer"
	
	seed_manager.set_world_seed(seed_value)
	return "World seed set to: %d (terrain will regenerate)" % seed_value


func _cmd_regenerate_world(args: Array[String]) -> String:
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if not seed_manager:
		return "Error: WorldSeedManager not available"
	
	seed_manager.regenerate_seed()
	
	# Reload the scene to force complete terrain regeneration
	# This is necessary because VoxelLodTerrain caches generated chunks
	print("[DevConsole] Reloading scene to regenerate world with new seed...")
	get_tree().call_deferred("reload_current_scene")
	
	return "New world seed generated: %d (reloading scene...)" % seed_manager.get_world_seed()


func _cmd_reload_biomes(args: Array[String]) -> String:
	var root := get_tree().current_scene
	if not root:
		return "Error: No current scene"
	
	var terrain := root.get_node_or_null("VoxelLodTerrain") as VoxelLodTerrain
	if not terrain or not terrain.generator:
		return "Error: VoxelLodTerrain or generator not found"
	
	var biome_gen := terrain.generator as BiomeGenerator
	if not biome_gen:
		return "Error: BiomeGenerator not found"
	
	biome_gen.reload_world_map_and_notify()
	return "Biome map reloaded from disk"


# =============================================================================
# PICKUP/COLLECTION COMMANDS
# =============================================================================

func _cmd_autocollect(args: Array[String]) -> String:
	if not GameSettings:
		return "Error: GameSettings not available"
	
	if args.is_empty():
		var current: bool = GameSettings.is_auto_collect_enabled()
		return "Auto-collect is currently: %s" % ("ON" if current else "OFF")
	
	var value := args[0].to_lower()
	match value:
		"on", "true", "1":
			GameSettings.set_setting("gameplay.auto_collect_items", true)
			return "Auto-collect: ON"
		"off", "false", "0":
			GameSettings.set_setting("gameplay.auto_collect_items", false)
			return "Auto-collect: OFF"
		_:
			return "Error: Usage: autocollect <on|off>"


func _cmd_spawn_pickup(args: Array[String]) -> String:
	if args.size() < 2:
		return "Error: Usage: spawn_pickup <resource_type> <amount>"
	
	var resource_type := args[0].to_lower()
	var amount := args[1].to_int()
	
	if amount <= 0:
		return "Error: Amount must be positive"
	
	var player := _get_player()
	if not player:
		return "Error: Player not found"
	
	if not MiningSystem:
		return "Error: MiningSystem not available"
	
	# Spawn pickup at player position with slight offset
	var spawn_pos: Vector3 = player.global_position + Vector3(0, 1.5, 0)
	MiningSystem.spawn_pickup(resource_type, amount, spawn_pos, false)
	
	return "Spawned %s x%d at player position" % [resource_type, amount]


func _cmd_clear_pickups(args: Array[String]) -> String:
	var pickups := get_tree().get_nodes_in_group("pickups")
	var count := pickups.size()
	
	for pickup in pickups:
		pickup.queue_free()
	
	return "Cleared %d pickups" % count


# =============================================================================
# BUILDING CHEAT COMMANDS
# =============================================================================

func _cmd_infinite_build(args: Array[String]) -> String:
	infinite_building = not infinite_building
	cheat_toggled.emit("infinite_build", infinite_building)
	return "Infinite building: %s" % ("ON" if infinite_building else "OFF")


func _cmd_infinite_craft(args: Array[String]) -> String:
	infinite_crafting = not infinite_crafting
	cheat_toggled.emit("infinite_craft", infinite_crafting)
	return "Infinite crafting: %s" % ("ON" if infinite_crafting else "OFF")


# =============================================================================
# WORLD INITIALIZATION COMMANDS
# =============================================================================

func _cmd_set_biome_strength(args: Array[String]) -> String:
	if args.is_empty():
		# Show current value
		var biome_gen := _get_biome_generator()
		if biome_gen:
			return "Current biome height modulation: %.2f" % biome_gen.height_modulation_strength
		return "Error: BiomeAwareGenerator not found"
	
	var value := args[0].to_float()
	if value < 0.0 or value > 1.0:
		return "Error: Value must be between 0.0 and 1.0"
	
	var biome_gen := _get_biome_generator()
	if not biome_gen:
		return "Error: BiomeAwareGenerator not found"
	
	biome_gen.height_modulation_strength = value
	
	# Optionally reload terrain to apply changes
	if args.size() > 1 and args[1].to_lower() == "reload":
		_cmd_reload_terrain([])
		return "Biome height modulation set to %.2f (terrain reloading...)" % value
	
	return "Biome height modulation set to %.2f (use 'reload_terrain' to apply)" % value


func _cmd_prewarm_terrain(args: Array[String]) -> String:
	var radius := 3  # Default radius
	if not args.is_empty():
		radius = args[0].to_int()
		if radius < 1 or radius > 10:
			return "Error: Radius must be between 1 and 10"
	
	var root := get_tree().current_scene
	if not root:
		return "Error: No current scene"
	
	var terrain := root.get_node_or_null("VoxelLodTerrain") as VoxelLodTerrain
	if not terrain:
		return "Error: VoxelLodTerrain not found"
	
	var player := _get_player()
	var center := Vector3.ZERO
	if player:
		center = player.global_position
	
	# Use TerrainPrewarmer
	TerrainPrewarmer.prewarm_area(terrain, center, radius)
	
	var chunk_count := (radius * 2 + 1) * (radius * 2 + 1)
	return "Prewarmed %d chunks around position %s" % [chunk_count, center]


func _cmd_validate_world(args: Array[String]) -> String:
	var world_init = get_node_or_null("/root/WorldInitManager")
	if not world_init:
		return "Error: WorldInitManager not available"
	
	var lines: Array[String] = ["=== World Validation ==="]
	
	# Get terrain
	var root := get_tree().current_scene
	var terrain := root.get_node_or_null("VoxelLodTerrain") as VoxelLodTerrain if root else null
	
	# Terrain check
	if terrain:
		lines.append("Terrain: OK (visible=%s)" % terrain.visible)
	else:
		lines.append("Terrain: MISSING")
	
	# Biome generator check
	var biome_gen := _get_biome_generator()
	if biome_gen:
		lines.append("BiomeGenerator: OK (strength=%.2f)" % biome_gen.height_modulation_strength)
	else:
		lines.append("BiomeGenerator: MISSING")
	
	# Vegetation check
	var veg_instancer := _get_vegetation_instancer()
	if veg_instancer:
		var count: int = veg_instancer.get_total_instance_count() if veg_instancer.has_method("get_total_instance_count") else 0
		lines.append("Vegetation: %d instances" % count)
	else:
		lines.append("Vegetation: NOT FOUND")
	
	# World init status
	if world_init.has_method("get_stage_name"):
		var stage: String = world_init.get_stage_name()
		var progress: float = world_init.get_total_progress() if world_init.has_method("get_total_progress") else 0.0
		lines.append("Init Status: %s (%.0f%%)" % [stage, progress * 100])
	
	return "\n".join(lines)


func _cmd_show_biome_boundaries(args: Array[String]) -> String:
	# This would toggle a debug visualization - for now just return info
	var biome_gen := _get_biome_generator()
	if not biome_gen:
		return "Error: BiomeAwareGenerator not found"
	
	return "Biome boundary visualization: Not yet implemented. Use performance overlay (F9) to see biome info."


func _cmd_world_status(args: Array[String]) -> String:
	var world_init = get_node_or_null("/root/WorldInitManager")
	var lines: Array[String] = ["=== World Status ==="]
	
	# Seed
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if seed_manager and seed_manager.has_method("get_world_seed"):
		lines.append("World Seed: %d" % seed_manager.get_world_seed())
	
	# Init status
	if world_init:
		var stage: String = world_init.get_stage_name() if world_init.has_method("get_stage_name") else "Unknown"
		var is_init: bool = world_init.is_initializing if "is_initializing" in world_init else false
		var attempt: int = world_init.get_current_attempt() if world_init.has_method("get_current_attempt") else 0
		lines.append("Stage: %s" % stage)
		lines.append("Initializing: %s" % ("Yes" if is_init else "No"))
		if attempt > 0:
			lines.append("Attempt: %d/%d" % [attempt, world_init.get_max_attempts() if world_init.has_method("get_max_attempts") else 3])
	else:
		lines.append("WorldInitManager: Not available")
	
	# Biome generator
	var biome_gen := _get_biome_generator()
	if biome_gen:
		lines.append("Height Modulation: %.2f" % biome_gen.height_modulation_strength)
		lines.append("Blend Distance: %.1fm" % biome_gen.BIOME_BLEND_DISTANCE)
	
	return "\n".join(lines)


func _get_biome_generator() -> BiomeAwareGenerator:
	var root := get_tree().current_scene
	if not root:
		return null
	
	var terrain := root.get_node_or_null("VoxelLodTerrain") as VoxelLodTerrain
	if terrain and terrain.generator:
		return terrain.generator as BiomeAwareGenerator
	return null
