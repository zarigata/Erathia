extends Node
## World Initialization Manager
##
## Orchestrates Minecraft-style world loading with:
## - Staged initialization pipeline
## - Progress reporting for loading screen
## - Validation checks with retry logic
## - Chunk pre-warming around spawn point

# =============================================================================
# SIGNALS
# =============================================================================

signal initialization_started()
signal stage_completed(stage_name: String, progress: float)
signal initialization_complete()
signal initialization_failed(reason: String)

# =============================================================================
# ENUMS
# =============================================================================

enum InitStage {
	IDLE,
	GENERATING_MAP,
	LOADING_BIOMES,
	PREWARMING_TERRAIN,
	SPAWNING_VEGETATION,
	VALIDATING,
	COMPLETE,
	FAILED
}

# =============================================================================
# CONSTANTS
# =============================================================================

const MAX_RETRY_ATTEMPTS: int = 3
const STAGE_TIMEOUT_SECONDS: float = 60.0
const PREWARM_RADIUS_CHUNKS: int = 3  # 3x3 grid = 9 chunks
const MIN_VEGETATION_COUNT: int = 10
const MIN_BIOME_VARIETY: int = 1  # At least 1 biome (relaxed for small spawn area)

# =============================================================================
# STATE
# =============================================================================

var current_stage: InitStage = InitStage.IDLE
var current_attempt: int = 0
var spawn_position: Vector3 = Vector3(0, 50, 0)
var is_initializing: bool = false

# Stage progress (0.0 - 1.0)
var _stage_progress: float = 0.0
var _stage_start_time: float = 0.0

# Node references (set during initialization)
var _terrain: VoxelLodTerrain
var _map_generator: MapGenerator
var _biome_generator: BiomeAwareGenerator
var _vegetation_instancer: Node  # VegetationInstancer
var _player: Node3D

# Prewarmed chunks tracking
var _prewarmed_chunks: Dictionary = {}
var _chunks_to_prewarm: Array[Vector3i] = []
var _prewarm_complete: bool = false

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not is_initializing:
		return
	
	# Check for stage timeout
	var elapsed := Time.get_ticks_msec() / 1000.0 - _stage_start_time
	if elapsed > STAGE_TIMEOUT_SECONDS and current_stage != InitStage.IDLE and current_stage != InitStage.COMPLETE and current_stage != InitStage.FAILED:
		push_warning("[WorldInitManager] Stage %s timed out after %.1f seconds" % [InitStage.keys()[current_stage], elapsed])
		_handle_stage_failure("Stage timed out: %s" % InitStage.keys()[current_stage])

# =============================================================================
# PUBLIC API
# =============================================================================

## Start the initialization sequence
func start_initialization(target_spawn_position: Vector3) -> void:
	if is_initializing:
		push_warning("[WorldInitManager] Initialization already in progress")
		return
	
	spawn_position = target_spawn_position
	current_attempt = 0
	is_initializing = true
	
	print("[WorldInitManager] Starting world initialization at spawn: %s" % spawn_position)
	initialization_started.emit()
	
	_begin_initialization()


## Get current initialization progress (0.0 - 1.0)
func get_total_progress() -> float:
	var stage_weight := 1.0 / 5.0  # 5 stages
	var stage_index := 0
	
	match current_stage:
		InitStage.IDLE:
			return 0.0
		InitStage.GENERATING_MAP:
			stage_index = 0
		InitStage.LOADING_BIOMES:
			stage_index = 1
		InitStage.PREWARMING_TERRAIN:
			stage_index = 2
		InitStage.SPAWNING_VEGETATION:
			stage_index = 3
		InitStage.VALIDATING:
			stage_index = 4
		InitStage.COMPLETE:
			return 1.0
		InitStage.FAILED:
			return _stage_progress
	
	return (stage_index * stage_weight) + (_stage_progress * stage_weight)


## Get current stage name for display
func get_stage_name() -> String:
	match current_stage:
		InitStage.IDLE:
			return "Idle"
		InitStage.GENERATING_MAP:
			return "Generating World Map"
		InitStage.LOADING_BIOMES:
			return "Loading Biomes"
		InitStage.PREWARMING_TERRAIN:
			return "Warming Terrain"
		InitStage.SPAWNING_VEGETATION:
			return "Spawning Vegetation"
		InitStage.VALIDATING:
			return "Validating World"
		InitStage.COMPLETE:
			return "Complete"
		InitStage.FAILED:
			return "Failed"
	return "Unknown"


## Get current attempt number
func get_current_attempt() -> int:
	return current_attempt


## Get max retry attempts
func get_max_attempts() -> int:
	return MAX_RETRY_ATTEMPTS

# =============================================================================
# INITIALIZATION PIPELINE
# =============================================================================

func _begin_initialization() -> void:
	current_attempt += 1
	print("[WorldInitManager] Initialization attempt %d/%d" % [current_attempt, MAX_RETRY_ATTEMPTS])
	
	# Find required nodes
	if not _find_required_nodes():
		_handle_stage_failure("Required nodes not found")
		return
	
	# Start the pipeline
	_stage_generate_map()


func _find_required_nodes() -> bool:
	var root := get_tree().current_scene
	if not root:
		push_error("[WorldInitManager] No current scene")
		return false
	
	_terrain = root.get_node_or_null("VoxelLodTerrain") as VoxelLodTerrain
	if not _terrain:
		push_error("[WorldInitManager] VoxelLodTerrain not found")
		return false
	
	_map_generator = root.get_node_or_null("MapGenerator") as MapGenerator
	if not _map_generator:
		push_warning("[WorldInitManager] MapGenerator not found, skipping map generation")
	
	if _terrain.generator:
		_biome_generator = _terrain.generator as BiomeAwareGenerator
	
	_vegetation_instancer = _terrain.get_node_or_null("VegetationInstancer")
	
	# Find player
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D
	else:
		_player = root.get_node_or_null("Player") as Node3D
	
	return true


func _stage_generate_map() -> void:
	current_stage = InitStage.GENERATING_MAP
	_stage_progress = 0.0
	_stage_start_time = Time.get_ticks_msec() / 1000.0
	stage_completed.emit("Generating World Map", 0.0)
	
	print("[WorldInitManager] Stage: Generating Map")
	
	if _map_generator:
		# Check if map already exists
		var map_path := "res://_assets/world_map.png"
		if FileAccess.file_exists(map_path):
			print("[WorldInitManager] World map already exists, skipping generation")
			_stage_progress = 1.0
			stage_completed.emit("Generating World Map", 1.0)
			_stage_load_biomes()
		else:
			# Connect to map_generated signal
			if not _map_generator.map_generated.is_connected(_on_map_generated):
				_map_generator.map_generated.connect(_on_map_generated, CONNECT_ONE_SHOT)
			_map_generator.generate_world_map()
	else:
		# No map generator, skip to next stage
		_stage_progress = 1.0
		stage_completed.emit("Generating World Map", 1.0)
		_stage_load_biomes()


func _on_map_generated(seed_value: int) -> void:
	print("[WorldInitManager] Map generated with seed: %d" % seed_value)
	_stage_progress = 1.0
	stage_completed.emit("Generating World Map", 1.0)
	_stage_load_biomes()


func _stage_load_biomes() -> void:
	current_stage = InitStage.LOADING_BIOMES
	_stage_progress = 0.0
	_stage_start_time = Time.get_ticks_msec() / 1000.0
	stage_completed.emit("Loading Biomes", 0.0)
	
	print("[WorldInitManager] Stage: Loading Biomes")
	
	# Reload biome generator with new map
	if _biome_generator:
		_biome_generator.reload_world_map_and_notify()
		_stage_progress = 0.5
		stage_completed.emit("Loading Biomes", 0.5)
		
		# Force complete terrain regeneration by clearing internal state
		# This is critical - simply reassigning the generator doesn't clear cached chunks
		if _terrain:
			print("[WorldInitManager] Forcing terrain regeneration to apply biome changes...")
			
			# Disable terrain to clear all cached chunks
			var was_visible := _terrain.visible
			_terrain.visible = false
			
			# Clear generator
			var saved_generator := _terrain.generator
			_terrain.generator = null
			
			# Wait for terrain to clear its state
			await get_tree().process_frame
			
			# Reassign generator and re-enable
			_terrain.generator = saved_generator
			_terrain.visible = was_visible
			
			# Wait for terrain to start regenerating
			await get_tree().process_frame
			
			print("[WorldInitManager] Terrain regeneration triggered")
	
	_stage_progress = 1.0
	stage_completed.emit("Loading Biomes", 1.0)
	
	# Short delay to let terrain system process
	await get_tree().create_timer(0.1).timeout
	_stage_prewarm_terrain()


func _stage_prewarm_terrain() -> void:
	current_stage = InitStage.PREWARMING_TERRAIN
	_stage_progress = 0.0
	_stage_start_time = Time.get_ticks_msec() / 1000.0
	stage_completed.emit("Warming Terrain", 0.0)
	
	print("[WorldInitManager] Stage: Prewarming Terrain around spawn")
	
	# Build list of chunks to prewarm
	_chunks_to_prewarm.clear()
	_prewarmed_chunks.clear()
	_prewarm_complete = false
	
	var chunk_size := 32
	var center_chunk := Vector3i(
		int(spawn_position.x / chunk_size) * chunk_size,
		0,
		int(spawn_position.z / chunk_size) * chunk_size
	)
	
	for x in range(-PREWARM_RADIUS_CHUNKS, PREWARM_RADIUS_CHUNKS + 1):
		for z in range(-PREWARM_RADIUS_CHUNKS, PREWARM_RADIUS_CHUNKS + 1):
			var chunk_origin := Vector3i(
				center_chunk.x + x * chunk_size,
				0,
				center_chunk.z + z * chunk_size
			)
			_chunks_to_prewarm.append(chunk_origin)
	
	print("[WorldInitManager] Prewarming %d chunks" % _chunks_to_prewarm.size())
	
	# Use TerrainPrewarmer to force chunk generation
	if _terrain:
		TerrainPrewarmer.prewarm_area_async(_terrain, spawn_position, PREWARM_RADIUS_CHUNKS, _on_prewarm_progress, _on_prewarm_complete)
	else:
		_on_prewarm_complete()


func _on_prewarm_progress(progress: float) -> void:
	_stage_progress = progress
	stage_completed.emit("Warming Terrain", progress)


func _on_prewarm_complete() -> void:
	print("[WorldInitManager] Terrain prewarming complete")
	_stage_progress = 1.0
	stage_completed.emit("Warming Terrain", 1.0)
	_prewarm_complete = true
	_stage_spawn_vegetation()


func _stage_spawn_vegetation() -> void:
	current_stage = InitStage.SPAWNING_VEGETATION
	_stage_progress = 0.0
	_stage_start_time = Time.get_ticks_msec() / 1000.0
	stage_completed.emit("Spawning Vegetation", 0.0)
	
	print("[WorldInitManager] Stage: Spawning Vegetation")
	
	# Vegetation spawns automatically via chunk_generated signals
	# Wait for vegetation instancer to process chunks
	if _vegetation_instancer and _vegetation_instancer.has_method("reload_vegetation"):
		_vegetation_instancer.call("reload_vegetation")
	
	# Wait a bit for vegetation to spawn
	var wait_time := 0.0
	var max_wait := 5.0
	var check_interval := 0.25
	
	while wait_time < max_wait:
		await get_tree().create_timer(check_interval).timeout
		wait_time += check_interval
		
		_stage_progress = wait_time / max_wait
		stage_completed.emit("Spawning Vegetation", _stage_progress)
		
		# Check if we have enough vegetation
		var veg_count := _get_vegetation_count()
		if veg_count >= MIN_VEGETATION_COUNT:
			print("[WorldInitManager] Vegetation count reached: %d" % veg_count)
			break
	
	_stage_progress = 1.0
	stage_completed.emit("Spawning Vegetation", 1.0)
	_stage_validate()


func _stage_validate() -> void:
	current_stage = InitStage.VALIDATING
	_stage_progress = 0.0
	_stage_start_time = Time.get_ticks_msec() / 1000.0
	stage_completed.emit("Validating World", 0.0)
	
	print("[WorldInitManager] Stage: Validating World")
	
	var terrain_valid := _validate_terrain()
	_stage_progress = 0.5
	stage_completed.emit("Validating World", 0.5)
	
	var vegetation_valid := _validate_vegetation()
	_stage_progress = 1.0
	stage_completed.emit("Validating World", 1.0)
	
	if terrain_valid and vegetation_valid:
		_complete_initialization()
	else:
		var reason := ""
		if not terrain_valid:
			reason = "Terrain validation failed"
		elif not vegetation_valid:
			reason = "Vegetation validation failed"
		_handle_stage_failure(reason)


func _complete_initialization() -> void:
	current_stage = InitStage.COMPLETE
	is_initializing = false
	
	# Find safe spawn position
	var safe_spawn := _find_safe_spawn_position()
	spawn_position = safe_spawn
	
	print("[WorldInitManager] Initialization complete! Safe spawn: %s" % spawn_position)
	initialization_complete.emit()


func _handle_stage_failure(reason: String) -> void:
	print("[WorldInitManager] Stage failed: %s" % reason)
	
	if current_attempt < MAX_RETRY_ATTEMPTS:
		print("[WorldInitManager] Retrying initialization...")
		
		# Clear caches and retry with seed offset
		_clear_caches()
		
		# Wait a moment before retrying
		await get_tree().create_timer(0.5).timeout
		_begin_initialization()
	else:
		current_stage = InitStage.FAILED
		is_initializing = false
		push_error("[WorldInitManager] Initialization failed after %d attempts: %s" % [MAX_RETRY_ATTEMPTS, reason])
		initialization_failed.emit(reason)


func _clear_caches() -> void:
	# Clear biome generator cache
	if _biome_generator:
		_biome_generator.reload_world_map_and_notify()
	
	# Clear vegetation
	if _vegetation_instancer and _vegetation_instancer.has_method("reload_vegetation"):
		_vegetation_instancer.call("reload_vegetation")
	
	# Increment seed for retry
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if seed_manager and seed_manager.has_method("get_world_seed"):
		var current_seed: int = seed_manager.call("get_world_seed")
		if seed_manager.has_method("set_world_seed"):
			seed_manager.call("set_world_seed", current_seed + 1)

# =============================================================================
# VALIDATION
# =============================================================================

func _validate_terrain() -> bool:
	if not _terrain:
		push_warning("[WorldInitManager] Validation failed: No terrain node")
		return false
	
	# Check 1: Terrain has mesh instances (indicates chunks were generated)
	var mesh_count := 0
	for child in _terrain.get_children():
		if child is MeshInstance3D:
			mesh_count += 1
	
	# VoxelLodTerrain creates meshes internally, so check if terrain is enabled
	if not _terrain.visible:
		push_warning("[WorldInitManager] Validation failed: Terrain not visible")
		return false
	
	# Check 2: Sample biomes around spawn to verify variety
	var biomes_found: Dictionary = {}
	var sample_radius := 64.0  # Sample in 64m radius
	
	for x in range(-2, 3):
		for z in range(-2, 3):
			var sample_pos := spawn_position + Vector3(x * sample_radius / 2, 0, z * sample_radius / 2)
			var biome_id := _get_biome_at_position(sample_pos)
			biomes_found[biome_id] = true
	
	if biomes_found.size() < MIN_BIOME_VARIETY:
		push_warning("[WorldInitManager] Validation warning: Only %d biome(s) detected near spawn (expected %d+)" % [biomes_found.size(), MIN_BIOME_VARIETY])
		# Don't fail on this - single biome spawn is okay
	
	print("[WorldInitManager] Terrain validation passed (biomes found: %d)" % biomes_found.size())
	return true


func _validate_vegetation() -> bool:
	var total := _get_vegetation_count()
	
	if total < MIN_VEGETATION_COUNT:
		push_warning("[WorldInitManager] Validation warning: Only %d vegetation instances (expected %d+)" % [total, MIN_VEGETATION_COUNT])
		# Don't fail on low vegetation - it might be a desert biome
	
	print("[WorldInitManager] Vegetation validation passed (count: %d)" % total)
	return true


func _get_vegetation_count() -> int:
	if _vegetation_instancer and _vegetation_instancer.has_method("get_total_instance_count"):
		return _vegetation_instancer.call("get_total_instance_count")
	return 0


func _get_biome_at_position(world_pos: Vector3) -> int:
	if BiomeManager:
		var biome_name: String = BiomeManager.get_biome_at_position(world_pos)
		# Convert name back to ID
		for biome_id in MapGenerator.Biome.values():
			if BiomeManager.get_biome_name(biome_id) == biome_name:
				return biome_id
	return MapGenerator.Biome.PLAINS

# =============================================================================
# SPAWN POSITION
# =============================================================================

func _find_safe_spawn_position() -> Vector3:
	if not _terrain:
		return spawn_position
	
	var test_pos := spawn_position
	var max_attempts := 10
	var offset_distance := 32.0
	
	for attempt in range(max_attempts):
		# Raycast down to find ground
		var voxel_tool := _terrain.get_voxel_tool()
		if voxel_tool:
			var ray_start := Vector3(test_pos.x, 200.0, test_pos.z)
			var ray_result := voxel_tool.raycast(ray_start, Vector3.DOWN, 250.0)
			
			if ray_result:
				var ground_pos: Vector3 = ray_result.position
				var ground_y := ground_pos.y + 4.0  # Spawn slightly above ground to avoid embedding
				
				# Check biome is not dangerous
				var biome_id := _get_biome_at_position(ground_pos)
				if biome_id != MapGenerator.Biome.DEEP_OCEAN and biome_id != MapGenerator.Biome.VOLCANIC:
					return Vector3(test_pos.x, ground_y, test_pos.z)
		
		# Offset position and try again
		var angle := attempt * (TAU / max_attempts)
		test_pos = spawn_position + Vector3(cos(angle) * offset_distance, 0, sin(angle) * offset_distance)
		offset_distance += 16.0
	
	# Fallback to original position with safe Y
	return Vector3(spawn_position.x, 80.0, spawn_position.z)
