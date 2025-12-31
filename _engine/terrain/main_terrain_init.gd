extends Node3D

## Main scene initialization script
## Handles terrain system setup, map generation coordination, and TerrainEditSystem initialization
## Integrates with WorldInitManager for Minecraft-style loading sequence

@export var terrain_path: NodePath = "VoxelLodTerrain"
@export var map_generator_path: NodePath = "MapGenerator"
@export var player_path: NodePath = "Player"
@export var loading_screen_path: NodePath = "LoadingScreen"

## If true, uses WorldInitManager for staged initialization
@export var use_world_init_manager: bool = true

## Default spawn position (Y will be adjusted to ground level)
@export var default_spawn_position: Vector3 = Vector3(0, 50, 0)

var _terrain: VoxelLodTerrain
var _map_generator: MapGenerator
var _biome_generator: BiomeAwareGenerator
var _gpu_generator: VoxelGeneratorScript
var _player: Node3D
var _loading_screen: CanvasLayer
var _world_init_manager: Node


func _validate_gpu_support() -> bool:
	print_rich("[color=cyan][MainTerrainInit][/color] Checking GPU compute support...")
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		print_rich("[color=red][MainTerrainInit] CRITICAL: RenderingDevice is null - GPU compute unavailable. Possible reasons: Compatibility renderer, headless mode, or driver issues.[/color]")
		push_error("[MainTerrainInit] RenderingDevice not available - GPU compute disabled")
		return false
	var device_name := rd.get_device_name()
	print_rich("[color=green][MainTerrainInit] GPU Device: %s[/color]" % device_name)
	print_rich("[color=cyan][MainTerrainInit] GPU Vendor: %s, API: %s[/color]" % [rd.get_device_vendor_name(), rd.get_device_api_version()])
	# Quick compute capability probe
	var compute_list := rd.compute_list_begin()
	if compute_list == 0:
		print_rich("[color=red][MainTerrainInit] Compute shaders not supported - GPU lacks compute capability[/color]")
		push_error("[MainTerrainInit] Compute shaders not supported on this GPU")
		return false
	rd.compute_list_end()
	print_rich("[color=green][MainTerrainInit] GPU compute validation PASSED[/color]")
	return true


func _ready() -> void:
	var gpu_supported := _validate_gpu_support()
	if not gpu_supported:
		push_warning("[MainTerrainInit] GPU compute validation failed; continuing with fallback-capable initialization")
	# Delete old world map to force regeneration with new seed
	_delete_old_world_map()
	
	_terrain = get_node_or_null(terrain_path) as VoxelLodTerrain
	_map_generator = get_node_or_null(map_generator_path) as MapGenerator
	_player = get_node_or_null(player_path) as Node3D
	_loading_screen = get_node_or_null(loading_screen_path) as CanvasLayer
	
	# Get BiomeAwareGenerator from terrain
	if _terrain and _terrain.generator:
		_biome_generator = _terrain.generator as BiomeAwareGenerator
	
	# Connect to MapGenerator signals
	if _map_generator:
		_map_generator.map_generated.connect(_on_map_generated)
		_map_generator.seed_randomized.connect(_on_seed_randomized)
		print("[MainTerrainInit] Connected to MapGenerator signals")
	else:
		print("[MainTerrainInit] MapGenerator not found, biomes may not load correctly")
	
	# Setup terrain connections and start initialization
	_setup_terrain_and_connections()


## Delete old world map files to force regeneration with new seed
func _delete_old_world_map() -> void:
	# Delete from user:// (runtime generated)
	var user_map_path := "user://world_map.png"
	if FileAccess.file_exists(user_map_path):
		DirAccess.remove_absolute(user_map_path)
		print("[MainTerrainInit] Deleted old world map from user://")
	
	# Note: We don't delete from res:// as that's read-only at runtime
	print("[MainTerrainInit] World will regenerate with new seed")


func _setup_terrain_and_connections() -> void:
	# Connect to WorldSeedManager for seed changes
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if seed_manager:
		seed_manager.seed_changed.connect(_on_world_seed_changed)
	
	if _terrain:
		_initialize_generator(seed_manager)
		# Initialize TerrainEditSystem with the terrain reference
		if TerrainEditSystem:
			TerrainEditSystem.set_terrain(_terrain)
			print("[MainTerrainInit] TerrainEditSystem initialized with terrain")
		else:
			push_warning("[MainTerrainInit] TerrainEditSystem autoload not found")
	else:
		push_warning("[MainTerrainInit] VoxelLodTerrain not found at path: %s" % terrain_path)
	
	# Start world initialization
	if use_world_init_manager:
		call_deferred("_start_world_initialization")
	else:
		# Legacy mode: enable player immediately
		_enable_player()
	
	# Explicitly connect terrain generator to vegetation instancer as fallback
	_connect_generator_to_vegetation()


func _initialize_generator(seed_manager: Node) -> void:
	var seed_value := 0
	if seed_manager and seed_manager.has_method("get_world_seed"):
		seed_value = seed_manager.get_world_seed()
	
	print_rich("[color=cyan][MainTerrainInit] Attempting GPU terrain generator initialization...[/color]")
	var gpu_generator := preload("res://_engine/terrain/gpu_terrain_generator.gd").new()
	if gpu_generator and gpu_generator.is_gpu_available():
		_gpu_generator = gpu_generator
		if _gpu_generator.has_method("update_seed"):
			_gpu_generator.update_seed(seed_value)
		_terrain.generator = _gpu_generator
		print_rich("[color=green][MainTerrainInit] GPU terrain generator initialized successfully[/color]")
	else:
		push_warning("[MainTerrainInit] GPU compute unavailable; falling back to CPU BiomeAwareGenerator")
		if gpu_generator and gpu_generator.has_method("get_gpu_dispatcher"):
			var dispatcher: Object = gpu_generator.get_gpu_dispatcher()
			if dispatcher == null:
				print_rich("[color=yellow][MainTerrainInit] GPU dispatcher not ready[/color]")
			elif dispatcher.has_method("is_ready") and not dispatcher.is_ready():
				print_rich("[color=yellow][MainTerrainInit] GPU dispatcher failed initialization (shader/pipeline issue)[/color]")
		if gpu_generator and gpu_generator.has_method("has_biome_texture") and not gpu_generator.has_biome_texture():
			print_rich("[color=yellow][MainTerrainInit] Biome map texture not loaded[/color]")
		print_rich("[color=yellow][MainTerrainInit] Falling back to CPU BiomeAwareGenerator[/color]")
		var cpu_generator := preload("res://_engine/terrain/biome_aware_generator.gd").new()
		if cpu_generator:
			_biome_generator = cpu_generator
			if _biome_generator.has_method("update_seed"):
				_biome_generator.update_seed(seed_value)
			_terrain.generator = _biome_generator
			print("[MainTerrainInit] CPU BiomeAwareGenerator assigned")
		else:
			push_error("[MainTerrainInit] Failed to instantiate BiomeAwareGenerator fallback")
			return

	# Connect GPU biome map updates if applicable
	if _gpu_generator:
		var biome_map_gen := get_node_or_null("BiomeMapGeneratorGPU")
		if biome_map_gen and biome_map_gen.has_signal("map_generated"):
			var update_callable := Callable(_gpu_generator, "update_biome_texture")
			if not biome_map_gen.is_connected("map_generated", update_callable):
				biome_map_gen.map_generated.connect(update_callable)
				print("[MainTerrainInit] Connected BiomeMapGeneratorGPU to GPU terrain wrapper")
			# Ensure the GPU biome map is produced before terrain generation
			if biome_map_gen.has_method("generate_map"):
				biome_map_gen.call_deferred("generate_map", seed_value)
		else:
			push_warning("[MainTerrainInit] BiomeMapGeneratorGPU not found; GPU generator may lack biome updates")


func _connect_generator_to_vegetation() -> void:
	if not _terrain or not _terrain.generator:
		return
	var veg_instancer := _terrain.get_node_or_null("VegetationInstancer")
	if veg_instancer and _terrain.generator.has_signal("chunk_generated"):
		if not _terrain.generator.is_connected("chunk_generated", Callable(veg_instancer, "_on_chunk_generated")):
			_terrain.generator.chunk_generated.connect(Callable(veg_instancer, "_on_chunk_generated"))
			print("[MainTerrainInit] Connected generator.chunk_generated to VegetationInstancer")


func _start_world_initialization() -> void:
	_world_init_manager = get_node_or_null("/root/WorldInitManager")
	
	if not _world_init_manager:
		push_warning("[MainTerrainInit] WorldInitManager not found, using legacy initialization")
		_enable_player()
		return
	
	# Disable player until world is ready
	_disable_player()
	
	# Connect to WorldInitManager signals
	_world_init_manager.initialization_complete.connect(_on_world_init_complete)
	_world_init_manager.initialization_failed.connect(_on_world_init_failed)
	
	# Start initialization
	var spawn_pos := default_spawn_position
	if _player:
		spawn_pos = _player.global_position
	
	print("[MainTerrainInit] Starting world initialization at: %s" % spawn_pos)
	_world_init_manager.start_initialization(spawn_pos)


func _disable_player() -> void:
	if not _player:
		return
	
	# Disable player physics and input
	if _player is CharacterBody3D:
		_player.set_physics_process(false)
		_player.set_process(false)
		_player.set_process_input(false)
		_player.set_process_unhandled_input(false)
	
	# Hide player
	_player.visible = false
	
	print("[MainTerrainInit] Player disabled during world initialization")


func _enable_player() -> void:
	if not _player:
		return
	
	# Enable player physics and input
	if _player is CharacterBody3D:
		_player.set_physics_process(true)
		_player.set_process(true)
		_player.set_process_input(true)
		_player.set_process_unhandled_input(true)
	
	# Show player
	_player.visible = true
	
	# Capture mouse for gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	print("[MainTerrainInit] Player enabled")


func _on_world_init_complete() -> void:
	print("[MainTerrainInit] World initialization complete!")
	
	# Update player spawn position to safe location
	if _world_init_manager and _player:
		var safe_spawn: Vector3 = _world_init_manager.spawn_position
		_player.global_position = safe_spawn
		print("[MainTerrainInit] Player spawned at: %s" % safe_spawn)
	
	# Enable player
	_enable_player()


func _on_world_init_failed(reason: String) -> void:
	push_error("[MainTerrainInit] World initialization failed: %s" % reason)
	# Still enable player so user can at least explore/debug
	_enable_player()


func _on_map_generated(seed_value: int) -> void:
	print("[MainTerrainInit] Map generated with seed: %d" % seed_value)
	
	# Skip if WorldInitManager is handling this
	if use_world_init_manager and _world_init_manager:
		return
	
	# Reload biome generator to pick up new map
	if _biome_generator:
		_biome_generator.reload_world_map_and_notify()
		print("[MainTerrainInit] BiomeGenerator reloaded with new map")
	
	# Force terrain to regenerate
	_force_terrain_regeneration()


func _on_seed_randomized(new_seed: int) -> void:
	print("[MainTerrainInit] Seed randomized to: %d" % new_seed)
	
	# Update generator seed
	if _gpu_generator and _gpu_generator.has_method("update_seed"):
		_gpu_generator.update_seed(new_seed)
	elif _biome_generator:
		_biome_generator.update_seed(new_seed)
	
	# Force terrain to regenerate by reassigning the generator
	if _terrain:
		_terrain.generator = _gpu_generator if _gpu_generator else _biome_generator
		print("[MainTerrainInit] Terrain generator reassigned to trigger regeneration")


func _on_world_seed_changed(new_seed: int) -> void:
	print("[MainTerrainInit] WorldSeedManager seed changed to: %d" % new_seed)
	# MapGenerator will handle regeneration via its own connection
	if _gpu_generator and _gpu_generator.has_method("update_seed"):
		_gpu_generator.update_seed(new_seed)


## Force terrain to completely regenerate by clearing its internal state
func _force_terrain_regeneration() -> void:
	if not _terrain or not _biome_generator:
		return
	
	print("[MainTerrainInit] Forcing terrain regeneration...")
	
	# Method 1: Toggle the terrain node off and on to clear internal state
	# This forces VoxelLodTerrain to discard all cached chunks
	var was_visible := _terrain.visible
	_terrain.visible = false
	
	# Clear the generator temporarily
	var saved_generator := _terrain.generator
	_terrain.generator = null
	
	# Wait one frame for the terrain to clear its state
	await get_tree().process_frame
	
	# Reassign the generator and make visible
	_terrain.generator = saved_generator
	_terrain.visible = was_visible
	
	# Wait another frame for terrain to start regenerating
	await get_tree().process_frame
	
	print("[MainTerrainInit] Terrain regeneration triggered")


func get_gpu_info() -> Dictionary:
	var rd := RenderingServer.get_rendering_device()
	var device_name := ""
	var vendor := ""
	var api_version := ""
	var compute_available := false
	if rd:
		device_name = rd.get_device_name()
		vendor = rd.get_device_vendor_name()
		api_version = rd.get_device_api_version()
		var compute_list := rd.compute_list_begin()
		if compute_list != 0:
			compute_available = true
			rd.compute_list_end()
	var generator_type := "CPU"
	var dispatcher_ready := false
	if _gpu_generator:
		generator_type = "GPU"
		if _gpu_generator.has_method("get_gpu_dispatcher"):
			var dispatcher := _gpu_generator.get_gpu_dispatcher()
			if dispatcher and dispatcher.has_method("is_ready"):
				dispatcher_ready = dispatcher.is_ready()
	return {
		"device_name": device_name,
		"vendor": vendor,
		"api_version": api_version,
		"compute_available": compute_available,
		"generator_type": generator_type,
		"dispatcher_ready": dispatcher_ready
	}
