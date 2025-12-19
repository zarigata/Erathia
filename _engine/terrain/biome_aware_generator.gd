@tool
extends VoxelGeneratorScript
class_name BiomeAwareGenerator

## Biome-Aware Generator - Wraps VoxelGeneratorNoise and adds biome-specific terrain modulation
## 
## Architecture:
## - Wraps VoxelGeneratorNoise (basic_generator.tres) for proven SDF generation
## - Samples world_map.png per-chunk (not per-voxel) for O(1) biome lookup
## - Applies height offset based on biome (additive to base SDF)
## - Assigns materials based on biome + depth
## - Emits chunk_generated signal for vegetation spawning

# =============================================================================
# SIGNALS
# =============================================================================

signal chunk_generated(origin: Vector3i, biome_id: int)

# =============================================================================
# MATERIAL IDS
# =============================================================================

const MAT_AIR: int = 0
const MAT_DIRT: int = 1
const MAT_STONE: int = 2
const MAT_IRON_ORE: int = 3
const MAT_SAND: int = 4
const MAT_SNOW: int = 5
const MAT_GRASS: int = 6

# =============================================================================
# LAYER THICKNESSES
# =============================================================================

const SURFACE_LAYER_THICKNESS: float = 4.0
const DIRT_LAYER_THICKNESS: float = 6.0

# =============================================================================
# EXPORT PARAMETERS
# =============================================================================

@export var ore_frequency: float = 0.02:
	set(value):
		ore_frequency = value
		if _ore_noise:
			_ore_noise.frequency = ore_frequency

@export var ore_threshold: float = 0.6
@export var ore_material_id: int = MAT_IRON_ORE
@export var min_ore_depth: float = 5.0

# Height modulation strength (scales biome height offsets)
# 1.0 = full effect (mountains 60-80m higher, oceans 80m lower)
# Lower values for gentler terrain variation
@export_range(0.0, 1.0, 0.1) var height_modulation_strength: float = 1.0

# =============================================================================
# INTERNAL STATE
# =============================================================================

var _base_generator: VoxelGeneratorNoise
var _ore_noise: FastNoiseLite
var _world_map_image: Image
var _world_map_loaded: bool = false

# Chunk biome cache (avoids re-sampling)
var _chunk_biome_cache: Dictionary = {}

# Biome blending settings - LARGE for smooth slopes (not cliffs)
const BIOME_BLEND_DISTANCE: float = 200.0  # Meters for smooth transitions (was 15m - way too small)
const MAX_SLOPE_GRADIENT: float = 0.35  # tan(~19 degrees) for gentle walkable slopes

# Mutex for thread-safe access to shared mutable state
var _cache_mutex: Mutex = Mutex.new()

# World map dimensions (computed from MapGenerator or loaded image)
var _map_size: int = 0
var _world_size: float = 0.0
var _pixel_scale: float = 0.0

# Biome height offsets (relative to base terrain)
# Positive = raise terrain, Negative = lower terrain
var _biome_height_offsets: Dictionary = {}

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init() -> void:
	# Load the base terrain generator (proven SDF generation)
	_base_generator = preload("res://_engine/terrain/basic_generator.tres")
	
	# Configure ore vein noise (copied from OreGenerator)
	_ore_noise = FastNoiseLite.new()
	_ore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ore_noise.seed = 67890
	_ore_noise.frequency = ore_frequency
	_ore_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_ore_noise.fractal_octaves = 2
	_ore_noise.fractal_lacunarity = 2.0
	_ore_noise.fractal_gain = 0.5
	
	# Load world map
	_load_world_map()
	
	# Initialize biome height offsets
	_init_biome_height_offsets()


func _load_world_map() -> void:
	_cache_mutex.lock()
	
	# Check user:// first (runtime generated), then res:// (editor/shipped)
	var map_path := "user://world_map.png"
	if not FileAccess.file_exists(map_path):
		map_path = "res://_assets/world_map.png"
	
	if FileAccess.file_exists(map_path):
		var loaded_image := Image.load_from_file(map_path)
		if loaded_image:
			_world_map_image = loaded_image
			_world_map_loaded = true
			# Compute map dimensions from MapGenerator constants
			_map_size = MapGenerator.MAP_SIZE
			_world_size = MapGenerator.WORLD_SIZE
			_pixel_scale = _world_size / float(_map_size) if _map_size > 0 else 1.0
			print("[BiomeAwareGenerator] World map loaded from %s: %dx%d (map_size=%d, world_size=%.0f, pixel_scale=%.4f)" % [map_path, _world_map_image.get_width(), _world_map_image.get_height(), _map_size, _world_size, _pixel_scale])
		else:
			push_warning("[BiomeAwareGenerator] Failed to load world map image from: %s" % map_path)
	else:
		push_warning("[BiomeAwareGenerator] World map not found (checked user:// and res://)")
	_cache_mutex.unlock()


func _init_biome_height_offsets() -> void:
	# HEIGHT OFFSETS DISABLED - Let base terrain handle all elevation
	# Biomes only affect MATERIALS, not height
	# This prevents the 90-degree cliff problem at biome boundaries
	# The base VoxelGeneratorNoise already creates natural terrain variation
	
	_biome_height_offsets = {
		# ALL BIOMES AT ZERO - no height modification
		MapGenerator.Biome.BEACH: 0.0,
		MapGenerator.Biome.DEEP_OCEAN: 0.0,
		MapGenerator.Biome.SWAMP: 0.0,
		MapGenerator.Biome.PLAINS: 0.0,
		MapGenerator.Biome.SAVANNA: 0.0,
		MapGenerator.Biome.DESERT: 0.0,
		MapGenerator.Biome.JUNGLE: 0.0,
		MapGenerator.Biome.FOREST: 0.0,
		MapGenerator.Biome.MUSHROOM: 0.0,
		MapGenerator.Biome.TUNDRA: 0.0,
		MapGenerator.Biome.VOLCANIC: 0.0,
		MapGenerator.Biome.MOUNTAIN: 0.0,
		MapGenerator.Biome.ICE_SPIRES: 0.0
	}


# =============================================================================
# PUBLIC METHODS
# =============================================================================

## Reload world map (called when map is regenerated)
func reload_world_map_and_notify() -> void:
	_cache_mutex.lock()
	_chunk_biome_cache.clear()
	_cache_mutex.unlock()
	_load_world_map()
	print("[BiomeAwareGenerator] World map reloaded, cache cleared")


## Update generator seed
func update_seed(new_seed: int) -> void:
	_ore_noise.seed = new_seed + 100
	_cache_mutex.lock()
	_chunk_biome_cache.clear()
	_cache_mutex.unlock()
	print("[BiomeAwareGenerator] Seed updated to: %d" % new_seed)


# =============================================================================
# VOXEL GENERATOR INTERFACE
# =============================================================================

func _get_used_channels_mask() -> int:
	# We write to SDF (terrain shape) and INDICES (material IDs)
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES)


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var block_size := out_buffer.get_size()
	var lod_scale := 1 << lod
	
	# Step 1: Generate base terrain SDF using VoxelGeneratorNoise
	_base_generator.generate_block(out_buffer, origin, lod)
	
	# Step 2: Get biome for this chunk (sample once per chunk)
	var primary_biome_id := _get_chunk_biome(origin, block_size, lod_scale)
	var ore_richness := _get_ore_richness(primary_biome_id)
	
	# Step 2.5: Check if this is a boundary chunk (needs per-voxel blending)
	var is_boundary_chunk := _is_boundary_chunk(origin, block_size, lod_scale)
	
	# Step 3: Apply height offset and assign materials
	for z in range(block_size.z):
		for y in range(block_size.y):
			for x in range(block_size.x):
				# Calculate world position
				var world_x: float = origin.x + x * lod_scale
				var world_y: float = origin.y + y * lod_scale
				var world_z: float = origin.z + z * lod_scale
				var world_pos := Vector3(world_x, world_y, world_z)
				
				# Get base SDF value
				var sdf: float = out_buffer.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
				
				# Apply biome height modulation
				var height_offset: float
				var biome_id_for_material: int = primary_biome_id
				
				if is_boundary_chunk and height_modulation_strength > 0.0:
					# Per-voxel biome blending at boundaries
					var blend_result := _sample_biome_blended(world_pos)
					height_offset = blend_result.blended_height_offset
					biome_id_for_material = blend_result.dominant_biome
				else:
					# Use cached primary biome (performance optimization)
					height_offset = _get_biome_height_offset(primary_biome_id)
				
				# Apply height modulation (additive)
				# Positive offset = terrain goes down (more air)
				# Negative offset = terrain goes up (more solid)
				sdf += height_offset * height_modulation_strength
				
				# Write modified SDF back
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
				
				# Determine material based on biome, SDF, and position
				var material_id := _get_material_for_biome(biome_id_for_material, sdf, world_pos, ore_richness)
				
				# Write material ID to INDICES channel
				out_buffer.set_voxel(material_id, x, y, z, VoxelBuffer.CHANNEL_INDICES)
	
	# Step 4: Emit signal for vegetation (LOD 0 only)
	# Emit synchronously - VegetationInstancer handles threading via its own deferred processing
	if lod == 0:
		chunk_generated.emit(origin, primary_biome_id)


# =============================================================================
# BIOME BOUNDARY DETECTION AND BLENDING
# =============================================================================

## Check if chunk is NEAR a biome boundary (within blend distance)
## With 200m blend distance, we need to check a much larger area
func _is_boundary_chunk(origin: Vector3i, block_size: Vector3i, lod_scale: int) -> bool:
	if not _world_map_loaded or _world_map_image == null:
		return false
	
	var chunk_width: float = block_size.x * lod_scale
	var chunk_depth: float = block_size.z * lod_scale
	var chunk_center := Vector3(origin.x + chunk_width * 0.5, 0, origin.z + chunk_depth * 0.5)
	
	# Sample at chunk center and at blend distance in 4 directions
	var center_biome := _sample_biome_at_world_pos(chunk_center)
	
	# Check if any different biome exists within blend distance
	var check_dist := BIOME_BLEND_DISTANCE
	var check_points := [
		chunk_center + Vector3(check_dist, 0, 0),
		chunk_center + Vector3(-check_dist, 0, 0),
		chunk_center + Vector3(0, 0, check_dist),
		chunk_center + Vector3(0, 0, -check_dist),
		chunk_center + Vector3(check_dist * 0.7, 0, check_dist * 0.7),
		chunk_center + Vector3(-check_dist * 0.7, 0, check_dist * 0.7),
		chunk_center + Vector3(check_dist * 0.7, 0, -check_dist * 0.7),
		chunk_center + Vector3(-check_dist * 0.7, 0, -check_dist * 0.7)
	]
	
	for point in check_points:
		var biome := _sample_biome_at_world_pos(point)
		if biome != center_biome:
			return true
	
	return false


## Sample biome at world position (for boundary detection)
func _sample_biome_at_world_pos(world_pos: Vector3) -> int:
	if not _world_map_loaded or _world_map_image == null or _map_size == 0:
		return MapGenerator.Biome.PLAINS
	
	# Convert world XZ to map pixel coordinates
	var pixel_x: int = int((world_pos.x + _world_size * 0.5) / _pixel_scale)
	var pixel_y: int = int((world_pos.z + _world_size * 0.5) / _pixel_scale)
	
	# Clamp to valid range
	pixel_x = clampi(pixel_x, 0, _map_size - 1)
	pixel_y = clampi(pixel_y, 0, _map_size - 1)
	
	var pixel := _world_map_image.get_pixel(pixel_x, pixel_y)
	return int(pixel.r8)


## Sample biome with DISTANCE-BASED smooth blending for gradual slopes
func _sample_biome_blended(world_pos: Vector3) -> Dictionary:
	if not _world_map_loaded or _world_map_image == null or _map_size == 0:
		return {"blended_height_offset": 0.0, "dominant_biome": MapGenerator.Biome.PLAINS}
	
	# Get center biome
	var center_biome := _sample_biome_at_world_pos(world_pos)
	var center_offset := _get_biome_height_offset(center_biome)
	
	# Sample in 8 directions at multiple distances to find nearby different biomes
	var blend_radius := BIOME_BLEND_DISTANCE
	var nearest_different_dist := blend_radius + 1.0
	var nearest_different_biome := center_biome
	var nearest_different_offset := center_offset
	
	# Sample 8 directions at 3 distances each (24 samples total - reasonable for performance)
	var distances: Array[float] = [blend_radius * 0.33, blend_radius * 0.66, blend_radius]
	for angle_idx: int in range(8):
		var angle: float = float(angle_idx) * TAU / 8.0
		var dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		
		for dist: float in distances:
			var sample_pos: Vector3 = world_pos + dir * dist
			var sample_biome: int = _sample_biome_at_world_pos(sample_pos)
			
			if sample_biome != center_biome:
				if dist < nearest_different_dist:
					nearest_different_dist = dist
					nearest_different_biome = sample_biome
					nearest_different_offset = _get_biome_height_offset(sample_biome)
				break  # Found boundary in this direction, stop sampling further
	
	# If no different biome within blend radius, use center offset
	if nearest_different_dist > blend_radius:
		return {"blended_height_offset": center_offset, "dominant_biome": center_biome}
	
	# Calculate blend factor based on distance to boundary
	# At boundary (dist=0): 50/50 blend
	# At full blend radius: 100% center biome
	var blend_factor := nearest_different_dist / blend_radius  # 0 at boundary, 1 at edge of blend zone
	blend_factor = blend_factor * blend_factor * (3.0 - 2.0 * blend_factor)  # Smoothstep for natural transition
	
	# Interpolate height offset
	var boundary_offset := (center_offset + nearest_different_offset) * 0.5
	var blended_offset := lerpf(boundary_offset, center_offset, blend_factor)
	
	return {"blended_height_offset": blended_offset, "dominant_biome": center_biome}


# =============================================================================
# BIOME SAMPLING (Per-Chunk)
# =============================================================================

func _get_chunk_biome(origin: Vector3i, block_size: Vector3i, lod_scale: int) -> int:
	_cache_mutex.lock()
	
	# Check cache first
	if _chunk_biome_cache.has(origin):
		var cached_biome: int = _chunk_biome_cache[origin]
		_cache_mutex.unlock()
		return cached_biome
	
	# Default to plains if no world map
	if not _world_map_loaded or _world_map_image == null or _map_size == 0:
		_cache_mutex.unlock()
		return MapGenerator.Biome.PLAINS
	
	# Calculate chunk center in world coordinates
	var center_x: float = origin.x + (block_size.x * lod_scale) * 0.5
	var center_z: float = origin.z + (block_size.z * lod_scale) * 0.5
	
	# Convert world XZ to map pixel coordinates
	# World coordinates are centered at (0,0), map is 0 to _world_size
	var pixel_x: int = int((center_x + _world_size * 0.5) / _pixel_scale)
	var pixel_y: int = int((center_z + _world_size * 0.5) / _pixel_scale)
	
	# Clamp to valid range
	pixel_x = clampi(pixel_x, 0, _map_size - 1)
	pixel_y = clampi(pixel_y, 0, _map_size - 1)
	
	# Sample world map red channel (biome ID)
	var pixel := _world_map_image.get_pixel(pixel_x, pixel_y)
	var biome_id: int = int(pixel.r8)
	
	# Cache result
	_chunk_biome_cache[origin] = biome_id
	
	_cache_mutex.unlock()
	return biome_id


# =============================================================================
# HEIGHT MODULATION
# =============================================================================

func _get_biome_height_offset(biome_id: int) -> float:
	if _biome_height_offsets.has(biome_id):
		return _biome_height_offsets[biome_id]
	return 0.0


# =============================================================================
# ORE RICHNESS
# =============================================================================

func _get_ore_richness(biome_id: int) -> float:
	# Use fallback ore richness values (BiomeManager is an autoload, not accessible from generator thread)
	match biome_id:
		MapGenerator.Biome.VOLCANIC:
			return 2.0
		MapGenerator.Biome.MOUNTAIN:
			return 1.8
		MapGenerator.Biome.ICE_SPIRES:
			return 1.5
		MapGenerator.Biome.MUSHROOM:
			return 1.3
		MapGenerator.Biome.DESERT:
			return 1.2
		MapGenerator.Biome.SAVANNA:
			return 1.1
		MapGenerator.Biome.PLAINS, MapGenerator.Biome.TUNDRA:
			return 1.0
		MapGenerator.Biome.JUNGLE:
			return 0.9
		MapGenerator.Biome.FOREST:
			return 0.8
		MapGenerator.Biome.DEEP_OCEAN:
			return 0.7
		MapGenerator.Biome.SWAMP:
			return 0.6
		MapGenerator.Biome.BEACH:
			return 0.5
		_:
			return 1.0


# =============================================================================
# MATERIAL ASSIGNMENT
# =============================================================================

func _get_material_for_biome(biome_id: int, sdf: float, world_pos: Vector3, ore_richness: float) -> int:
	# Air (positive SDF = empty space)
	if sdf > 0.0:
		return MAT_AIR
	
	# Surface layer - biome-specific material
	if sdf > -SURFACE_LAYER_THICKNESS:
		return _get_surface_material(biome_id)
	
	# Subsurface layer - transition material
	if sdf > -(SURFACE_LAYER_THICKNESS + DIRT_LAYER_THICKNESS):
		return _get_subsurface_material(biome_id)
	
	# Underground - stone with ore veins
	# Check for ore vein using 3D noise
	if sdf < -(min_ore_depth + SURFACE_LAYER_THICKNESS + DIRT_LAYER_THICKNESS):
		# Adjust ore threshold based on biome richness
		# Lower threshold = more ore
		var adjusted_threshold := ore_threshold - (ore_richness - 1.0) * 0.1
		adjusted_threshold = clampf(adjusted_threshold, 0.3, 0.9)
		
		# Sample ore noise at this position using proper 3D coordinates
		var ore_sample := _ore_noise.get_noise_3d(world_pos.x, world_pos.y, world_pos.z)
		ore_sample = (ore_sample + 1.0) * 0.5  # Normalize to 0-1
		
		if ore_sample > adjusted_threshold:
			return ore_material_id
	
	return MAT_STONE


func _get_surface_material(biome_id: int) -> int:
	match biome_id:
		MapGenerator.Biome.DESERT, MapGenerator.Biome.BEACH:
			return MAT_SAND
		MapGenerator.Biome.TUNDRA, MapGenerator.Biome.ICE_SPIRES:
			return MAT_SNOW
		MapGenerator.Biome.VOLCANIC:
			return MAT_STONE  # Volcanic rock/obsidian
		MapGenerator.Biome.DEEP_OCEAN:
			return MAT_SAND  # Sandy ocean floor
		MapGenerator.Biome.MOUNTAIN:
			return MAT_STONE  # Rocky mountain surface
		MapGenerator.Biome.PLAINS, MapGenerator.Biome.FOREST, MapGenerator.Biome.JUNGLE, MapGenerator.Biome.SAVANNA:
			return MAT_GRASS  # Grassy biomes
		MapGenerator.Biome.SWAMP:
			return MAT_DIRT  # Muddy swamp
		MapGenerator.Biome.MUSHROOM:
			return MAT_DIRT  # Fungal soil
		_:
			return MAT_GRASS  # Default: grass for unknown biomes


func _get_subsurface_material(biome_id: int) -> int:
	match biome_id:
		MapGenerator.Biome.DESERT, MapGenerator.Biome.BEACH:
			return MAT_SAND  # Deep sand
		MapGenerator.Biome.TUNDRA, MapGenerator.Biome.ICE_SPIRES:
			return MAT_DIRT  # Permafrost/frozen dirt
		_:
			return MAT_DIRT  # Default: dirt layer
