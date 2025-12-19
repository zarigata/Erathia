@tool
extends VoxelGeneratorScript
class_name BiomeGenerator

## BiomeGenerator - Wraps OreGenerator and samples world map for biome-specific terrain
## Modifies terrain height, materials, and ore distribution based on biome type

# =============================================================================
# SIGNALS
# =============================================================================

signal chunk_generated(chunk_origin: Vector3i, biome_id: int)

# =============================================================================
# EXPORT VARIABLES
# =============================================================================

@export var world_map_path: String = "res://_assets/world_map.png"
@export var world_size: float = 16000.0
@export var map_size: int = 2048
@export var debug_mode: bool = false

# =============================================================================
# CONSTANTS
# =============================================================================

# World-to-map coordinate conversion
var PIXEL_SCALE: float:
	get:
		return world_size / float(map_size)

# Material IDs (matching OreGenerator)
const MAT_AIR: int = 0
const MAT_DIRT: int = 1
const MAT_STONE: int = 2
const MAT_ORE: int = 3

# Dirt layer thickness (SDF units)
const DIRT_LAYER_THICKNESS: float = 2.0

# Biome transition blend zone (in meters)
const BIOME_BLEND_DISTANCE: float = 15.0

# =============================================================================
# INTERNAL REFERENCES
# =============================================================================

var _world_map_image: Image
var _base_generator: OreGenerator
var _biome_manager: Node  # BiomeManager autoload singleton (accessed at runtime)

# Caches
var _biome_cache: Dictionary = {}  # Vector3i -> int (chunk origin -> biome_id)
var _biome_property_cache: Dictionary = {}  # int -> Dictionary (biome_id -> properties)
var map_ready: bool = false  # True when world map is loaded successfully

# Per-biome noise instances (thread-safe, immutable after init)
var _biome_noise_instances: Dictionary = {}  # biome_id -> FastNoiseLite

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init() -> void:
	# Instantiate base generator
	_base_generator = OreGenerator.new()
	
	# BiomeManager is an autoload singleton - will be accessed at runtime
	# Cannot use .new() on Node-based classes
	_biome_manager = null
	
	# Get seed from WorldSeedManager if available
	# Note: In @tool scripts, autoloads may not be available during _init()
	# The seed will be updated later via update_seed() when the scene runs
	var seed_value: int = 12345
	if Engine.is_editor_hint():
		seed_value = 12345  # Editor fallback
	else:
		var seed_mgr = Engine.get_singleton("WorldSeedManager")
		if seed_mgr and seed_mgr.has_method("get_world_seed"):
			seed_value = seed_mgr.get_world_seed()
	
	# Also set seed on ore noise (base generator is a resource, not directly seedable)
	if _base_generator and _base_generator._ore_noise:
		_base_generator._ore_noise.seed = seed_value
	
	# Create per-biome noise instances (thread-safe: read-only after init)
	_create_biome_noise_instances(seed_value)
	
	# Load world map
	_load_world_map()


func _load_world_map() -> void:
	_world_map_image = Image.new()
	var error := _world_map_image.load(world_map_path)
	
	if error != OK:
		push_warning("[BiomeGenerator] Failed to load world map from '%s'. Using default biome (PLAINS)." % world_map_path)
		_world_map_image = null
		map_ready = false
		return
	
	# Validate image format and size
	if _world_map_image.get_width() != map_size or _world_map_image.get_height() != map_size:
		push_warning("[BiomeGenerator] World map size mismatch. Expected %dx%d, got %dx%d. Scaling may occur." % [
			map_size, map_size, _world_map_image.get_width(), _world_map_image.get_height()
		])
	
	map_ready = true
	if debug_mode:
		print("[BiomeGenerator] World map loaded successfully: %s" % world_map_path)


## Get BiomeManager autoload singleton (lazy initialization)
func _get_biome_manager() -> Node:
	if _biome_manager == null:
		# Try to get from Engine singleton (works in runtime)
		if not Engine.is_editor_hint():
			_biome_manager = Engine.get_singleton("BiomeManager")
		# Fallback: try scene tree if available
		if _biome_manager == null:
			var tree := Engine.get_main_loop() as SceneTree
			if tree and tree.root:
				_biome_manager = tree.root.get_node_or_null("/root/BiomeManager")
	return _biome_manager


# =============================================================================
# COORDINATE CONVERSION
# =============================================================================

## Converts world X/Z coordinates to map pixel coordinates
## World is centered at origin, so coordinates range from -world_size/2 to +world_size/2
func _world_to_map_coords(world_pos: Vector3) -> Vector2i:
	# Offset world coordinates to map space (world center = map center)
	var half_world := world_size * 0.5
	var pixel_x := int((world_pos.x + half_world) / PIXEL_SCALE)
	var pixel_z := int((world_pos.z + half_world) / PIXEL_SCALE)
	
	# Clamp to valid map bounds
	pixel_x = clampi(pixel_x, 0, map_size - 1)
	pixel_z = clampi(pixel_z, 0, map_size - 1)
	
	return Vector2i(pixel_x, pixel_z)


## Bilinear sampling for smooth biome transitions (returns interpolated biome weights)
func _sample_biome_smooth(world_pos: Vector3) -> Dictionary:
	var half_world := world_size * 0.5
	var map_x := (world_pos.x + half_world) / PIXEL_SCALE
	var map_z := (world_pos.z + half_world) / PIXEL_SCALE
	
	# Get integer and fractional parts
	var x0 := int(floor(map_x))
	var z0 := int(floor(map_z))
	var x1 := mini(x0 + 1, map_size - 1)
	var z1 := mini(z0 + 1, map_size - 1)
	x0 = maxi(x0, 0)
	z0 = maxi(z0, 0)
	
	var fx: float = map_x - floor(map_x)
	var fz: float = map_z - floor(map_z)
	
	# Sample 4 corners
	var biomes: Dictionary = {}
	var positions := [
		[Vector2i(x0, z0), (1.0 - fx) * (1.0 - fz)],
		[Vector2i(x1, z0), fx * (1.0 - fz)],
		[Vector2i(x0, z1), (1.0 - fx) * fz],
		[Vector2i(x1, z1), fx * fz]
	]
	
	for pos_weight in positions:
		var coords: Vector2i = pos_weight[0]
		var weight: float = pos_weight[1]
		var biome_id := _sample_biome_at_pixel(coords)
		if biomes.has(biome_id):
			biomes[biome_id] += weight
		else:
			biomes[biome_id] = weight
	
	return biomes


## Sample biome ID from a specific pixel
func _sample_biome_at_pixel(coords: Vector2i) -> int:
	if _world_map_image == null:
		return MapGenerator.Biome.PLAINS
	
	var pixel := _world_map_image.get_pixel(coords.x, coords.y)
	# R channel contains biome ID (0-255, but we only use 0-12)
	var biome_id := int(pixel.r8)
	
	# Validate biome ID
	if biome_id < 0 or biome_id > 12:
		return MapGenerator.Biome.PLAINS
	
	return biome_id


# =============================================================================
# BIOME SAMPLING
# =============================================================================

## Returns the primary biome ID at a world position
func _get_biome_at_position(world_pos: Vector3) -> int:
	var coords := _world_to_map_coords(world_pos)
	return _sample_biome_at_pixel(coords)


## Returns biome ID for a chunk, with caching
func _get_biome_for_chunk(origin: Vector3i) -> int:
	if _biome_cache.has(origin):
		return _biome_cache[origin]
	
	# Sample at chunk center
	var center := Vector3(origin) + Vector3(16, 16, 16)  # Assuming 32-voxel chunks
	var biome_id := _get_biome_at_position(center)
	
	_biome_cache[origin] = biome_id
	return biome_id


# =============================================================================
# BIOME HEIGHT MODIFIERS
# =============================================================================

## Generates SDF directly from biome parameters
## Returns SDF value: negative = solid, positive = air
func _generate_biome_sdf(world_pos: Vector3, biome_id: int) -> float:
	var bm := _get_biome_manager()
	var height_range: Dictionary = {"min": 0, "max": 100}
	if bm:
		height_range = bm.get_height_range(biome_id)
	var min_height: float = height_range.get("min", 0)
	var max_height: float = height_range.get("max", 100)
	
	# Get preconfigured noise instance for this biome (thread-safe read)
	var biome_noise := _get_biome_noise(biome_id)
	
	# Sample noise at world position (use XZ for base terrain height)
	var noise_val := biome_noise.get_noise_2d(world_pos.x, world_pos.z)
	
	# Remap noise (-1 to 1) to biome's elevation window
	var normalized_noise := (noise_val + 1.0) * 0.5  # 0 to 1
	var target_height := lerpf(min_height, max_height, normalized_noise)
	
	# Apply biome-specific terrain features with aggressive height variation
	match biome_id:
		MapGenerator.Biome.MOUNTAIN:
			# Sharp peaks with pow() amplification
			if noise_val > 0.2:
				target_height += pow(noise_val, 1.5) * 150.0
			else:
				target_height += noise_val * 50.0
		
		MapGenerator.Biome.ICE_SPIRES:
			# Very sharp spires with extreme peaks
			if noise_val > 0.3:
				target_height += pow(noise_val, 2.0) * 200.0
			else:
				target_height += noise_val * 80.0
			# Add secondary noise for jagged detail (using same biome noise instance)
			var detail_noise := biome_noise.get_noise_3d(world_pos.x * 2.0, world_pos.y * 0.5, world_pos.z * 2.0)
			target_height += detail_noise * 30.0
		
		MapGenerator.Biome.DEEP_OCEAN:
			# Force negative heights with gentle variation
			target_height = -80.0 + noise_val * 15.0
		
		MapGenerator.Biome.BEACH:
			# Clamp to narrow range near sea level
			target_height = clampf(target_height, -5.0, 15.0)
			target_height += noise_val * 3.0
		
		MapGenerator.Biome.VOLCANIC:
			# Sharp ridges and jagged terrain with occasional peaks
			var voronoi_like: float = abs(noise_val) as float
			target_height += voronoi_like * 100.0
			# Add sharp ridges (using same biome noise instance)
			var ridge_noise: float = abs(biome_noise.get_noise_2d(world_pos.x * 3.0, world_pos.z * 3.0)) as float
			target_height += ridge_noise * 50.0
		
		MapGenerator.Biome.SWAMP:
			# Very flat with narrow height range
			target_height = clampf(target_height, -5.0, 10.0)
			target_height += noise_val * 3.0
		
		MapGenerator.Biome.DESERT:
			# Rolling dunes with sine-wave pattern
			var dune_pattern: float = sin(world_pos.x * 0.01) * cos(world_pos.z * 0.01)
			target_height += dune_pattern * 25.0
			target_height += noise_val * 20.0
		
		MapGenerator.Biome.PLAINS:
			# Gentle rolling hills
			target_height += noise_val * 15.0
		
		MapGenerator.Biome.FOREST:
			# Moderate terrain variation with gentle hills
			target_height += noise_val * 30.0
		
		MapGenerator.Biome.JUNGLE:
			# Moderate terrain with some steeper areas
			target_height += noise_val * 35.0
		
		MapGenerator.Biome.TUNDRA:
			# Frozen rolling terrain, slightly lower
			target_height += noise_val * 25.0 - 10.0
		
		MapGenerator.Biome.SAVANNA:
			# Mostly flat with gentle rises
			target_height += noise_val * 12.0
		
		MapGenerator.Biome.MUSHROOM:
			# Unusual terrain with pockets and bumps (using same biome noise instance)
			var pocket_noise: float = abs(biome_noise.get_noise_2d(world_pos.x * 2.0, world_pos.z * 2.0)) as float
			target_height += noise_val * 30.0
			target_height -= pocket_noise * 20.0  # Create depressions
		
		_:
			target_height += noise_val * 20.0
	
	# Calculate SDF: positive = air (above surface), negative = solid (below surface)
	var sdf: float = world_pos.y - target_height
	return sdf


## Legacy function for compatibility - now wraps _generate_biome_sdf
func _get_biome_height_modifier(biome_id: int, base_sdf: float, world_pos: Vector3) -> float:
	# Use new direct SDF generation
	return _generate_biome_sdf(world_pos, biome_id)


# =============================================================================
# BIOME MATERIALS
# =============================================================================

## Returns material ID based on biome and depth
func _get_biome_material(biome_id: int, sdf: float, world_pos: Vector3) -> int:
	if sdf > 0.0:
		return MAT_AIR
	
	# Get ore richness for this biome
	var bm := _get_biome_manager()
	var ore_richness: float = 1.0
	if bm:
		ore_richness = bm.get_ore_richness(biome_id)
	
	# Surface layer (within DIRT_LAYER_THICKNESS of surface)
	if sdf > -DIRT_LAYER_THICKNESS:
		return MAT_DIRT
	
	# Underground - check for ore based on biome richness
	var ore_threshold := 0.6 - (ore_richness - 1.0) * 0.1  # Lower threshold = more ore
	ore_threshold = clampf(ore_threshold, 0.4, 0.75)
	
	# Only generate ore below minimum depth
	if sdf < -(5.0 + DIRT_LAYER_THICKNESS):
		var ore_noise_value := _base_generator._ore_noise.get_noise_3d(world_pos.x, world_pos.y, world_pos.z)
		ore_noise_value = (ore_noise_value + 1.0) * 0.5
		
		if ore_noise_value > ore_threshold:
			return MAT_ORE
	
	return MAT_STONE


# =============================================================================
# BIOME NOISE INSTANCES (THREAD-SAFE)
# =============================================================================

## Creates preconfigured noise instances for each biome (called once at init)
## These instances are immutable after creation, making them thread-safe
func _create_biome_noise_instances(seed_value: int) -> void:
	_biome_noise_instances.clear()
	
	# Define noise parameters for each biome
	var biome_params: Dictionary = {
		MapGenerator.Biome.PLAINS: {"frequency": 0.003, "octaves": 2},
		MapGenerator.Biome.MOUNTAIN: {"frequency": 0.008, "octaves": 4},
		MapGenerator.Biome.ICE_SPIRES: {"frequency": 0.01, "octaves": 4},
		MapGenerator.Biome.DESERT: {"frequency": 0.005, "octaves": 2},
		MapGenerator.Biome.SWAMP: {"frequency": 0.002, "octaves": 2},
		MapGenerator.Biome.VOLCANIC: {"frequency": 0.01, "octaves": 3},
		MapGenerator.Biome.FOREST: {"frequency": 0.004, "octaves": 3},
		MapGenerator.Biome.JUNGLE: {"frequency": 0.005, "octaves": 3},
		MapGenerator.Biome.TUNDRA: {"frequency": 0.004, "octaves": 2},
		MapGenerator.Biome.SAVANNA: {"frequency": 0.003, "octaves": 2},
		MapGenerator.Biome.BEACH: {"frequency": 0.002, "octaves": 1},
		MapGenerator.Biome.DEEP_OCEAN: {"frequency": 0.003, "octaves": 2},
		MapGenerator.Biome.MUSHROOM: {"frequency": 0.006, "octaves": 3},
	}
	
	# Create a noise instance for each biome with its specific parameters
	for biome_id in biome_params:
		var params: Dictionary = biome_params[biome_id]
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.seed = seed_value
		noise.frequency = params["frequency"]
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = params["octaves"]
		noise.fractal_lacunarity = 2.0
		noise.fractal_gain = 0.5
		_biome_noise_instances[biome_id] = noise
	
	# Create a default noise instance for unknown biomes
	var default_noise := FastNoiseLite.new()
	default_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	default_noise.seed = seed_value
	default_noise.frequency = 0.005
	default_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	default_noise.fractal_octaves = 2
	default_noise.fractal_lacunarity = 2.0
	default_noise.fractal_gain = 0.5
	_biome_noise_instances[-1] = default_noise  # -1 as default key


## Returns the preconfigured noise instance for a biome (thread-safe read)
func _get_biome_noise(biome_id: int) -> FastNoiseLite:
	if _biome_noise_instances.has(biome_id):
		return _biome_noise_instances[biome_id]
	return _biome_noise_instances[-1]  # Return default


# =============================================================================
# BIOME TRANSITION SMOOTHING
# =============================================================================

## Generates SDF with proper distance-based biome blending
## Uses BIOME_BLEND_DISTANCE to create smooth transitions between biomes
func _generate_blended_sdf(world_pos: Vector3) -> float:
	# Sample biome weights using bilinear interpolation
	var biome_weights := _sample_biome_smooth(world_pos)
	
	# If only one biome, no blending needed
	if biome_weights.size() == 1:
		var biome_id: int = biome_weights.keys()[0]
		return _generate_biome_sdf(world_pos, biome_id)
	
	# Calculate distance-based blend weights using BIOME_BLEND_DISTANCE
	# The bilinear weights from _sample_biome_smooth give us 0-1 based on pixel position
	# We need to scale these by BIOME_BLEND_DISTANCE for proper world-space blending
	var adjusted_weights := _adjust_weights_for_blend_distance(world_pos, biome_weights)
	
	# Generate SDF for each biome and blend proportionally
	var blended_sdf: float = 0.0
	var total_weight: float = 0.0
	
	for biome_id in adjusted_weights:
		var weight: float = adjusted_weights[biome_id]
		if weight > 0.001:  # Skip negligible weights
			var biome_sdf := _generate_biome_sdf(world_pos, biome_id)
			blended_sdf += biome_sdf * weight
			total_weight += weight
	
	# Normalize
	if total_weight > 0.0:
		blended_sdf /= total_weight
	
	return blended_sdf


## Adjusts biome weights based on distance to biome boundary
## Uses BIOME_BLEND_DISTANCE to create smooth falloff at transitions
func _adjust_weights_for_blend_distance(world_pos: Vector3, raw_weights: Dictionary) -> Dictionary:
	# Get the fractional position within the current pixel
	var map_x: float = world_pos.x / PIXEL_SCALE
	var map_z: float = world_pos.z / PIXEL_SCALE
	var frac_x: float = fmod(map_x, 1.0)
	var frac_z: float = fmod(map_z, 1.0)
	
	# Calculate distance to nearest pixel boundary (0 = at boundary, 0.5 = center)
	var dist_to_boundary_x := minf(frac_x, 1.0 - frac_x)
	var dist_to_boundary_z := minf(frac_z, 1.0 - frac_z)
	var dist_to_boundary := minf(dist_to_boundary_x, dist_to_boundary_z)
	
	# Convert pixel-space distance to world-space distance
	var world_dist_to_boundary := dist_to_boundary * PIXEL_SCALE
	
	# Calculate blend factor based on BIOME_BLEND_DISTANCE
	# 0 = fully at boundary (blend equally), 1 = outside blend zone (use primary biome)
	var blend_factor := clampf(world_dist_to_boundary / BIOME_BLEND_DISTANCE, 0.0, 1.0)
	
	# Apply smoothstep for smoother transitions
	blend_factor = blend_factor * blend_factor * (3.0 - 2.0 * blend_factor)
	
	# Find primary biome (highest raw weight)
	var primary_biome: int = -1
	var max_weight: float = 0.0
	for biome_id in raw_weights:
		if raw_weights[biome_id] > max_weight:
			max_weight = raw_weights[biome_id]
			primary_biome = biome_id
	
	# Adjust weights: interpolate between raw weights and primary-only
	var adjusted: Dictionary = {}
	for biome_id in raw_weights:
		var raw_weight: float = raw_weights[biome_id]
		if biome_id == primary_biome:
			# Primary biome weight increases as we move away from boundary
			adjusted[biome_id] = lerpf(raw_weight, 1.0, blend_factor)
		else:
			# Secondary biome weights decrease as we move away from boundary
			adjusted[biome_id] = lerpf(raw_weight, 0.0, blend_factor)
	
	return adjusted


## Returns blended biome data for smooth transitions (legacy compatibility)
func _smooth_biome_transition(world_pos: Vector3, primary_biome: int) -> Dictionary:
	var biome_weights := _sample_biome_smooth(world_pos)
	
	# If only one biome, no blending needed
	if biome_weights.size() == 1:
		return {"biome_ids": [primary_biome], "weights": [1.0]}
	
	# Use distance-adjusted weights
	var adjusted_weights := _adjust_weights_for_blend_distance(world_pos, biome_weights)
	
	# Sort by weight descending
	var sorted_biomes: Array = []
	for biome_id in adjusted_weights:
		sorted_biomes.append([biome_id, adjusted_weights[biome_id]])
	sorted_biomes.sort_custom(func(a, b): return a[1] > b[1])
	
	var biome_ids: Array = []
	var weights: Array = []
	for entry in sorted_biomes:
		biome_ids.append(entry[0])
		weights.append(entry[1])
	
	return {"biome_ids": biome_ids, "weights": weights}


## Blends height modifiers from multiple biomes (legacy compatibility)
func _blend_height_modifiers(world_pos: Vector3, base_sdf: float, transition_data: Dictionary) -> float:
	var biome_ids: Array = transition_data.get("biome_ids", [])
	var weights: Array = transition_data.get("weights", [])
	
	if biome_ids.size() == 0:
		return base_sdf
	
	if biome_ids.size() == 1:
		return _get_biome_height_modifier(biome_ids[0], base_sdf, world_pos)
	
	# Blend height modifiers
	var blended_sdf: float = 0.0
	for i in range(biome_ids.size()):
		var modified_sdf := _get_biome_height_modifier(biome_ids[i], base_sdf, world_pos)
		blended_sdf += modified_sdf * weights[i]
	
	return blended_sdf


# =============================================================================
# VOXEL GENERATION
# =============================================================================

func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES)


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var block_size := out_buffer.get_size()
	var lod_scale := 1 << lod
	
	# Calculate chunk center for biome sampling (sample once per chunk)
	var center := Vector3(origin) + Vector3(block_size) * 0.5 * lod_scale
	var primary_biome := _get_biome_at_position(center)
	
	# Check if this is a boundary chunk (for per-voxel biome sampling)
	var is_boundary_chunk := _is_near_biome_boundary(center, block_size.x * lod_scale)
	
	# LOD-aware sampling frequency
	var sample_step := 1
	if lod >= 2:
		sample_step = 2  # Sample every 2nd voxel at high LOD
	if lod >= 4:
		sample_step = 4  # Sample every 4th voxel at very high LOD
	
	# Generate terrain directly from biome parameters (no base generator)
	for z in range(0, block_size.z, sample_step):
		for y in range(0, block_size.y, sample_step):
			for x in range(0, block_size.x, sample_step):
				# Calculate world position
				var world_x: float = origin.x + x * lod_scale
				var world_y: float = origin.y + y * lod_scale
				var world_z: float = origin.z + z * lod_scale
				var world_pos := Vector3(world_x, world_y, world_z)
				
				# Determine biome for this voxel
				var voxel_biome := primary_biome
				if is_boundary_chunk:
					# Per-voxel biome sampling at boundaries for smooth transitions
					voxel_biome = _get_biome_at_position(world_pos)
				
				# Generate SDF with proper biome blending at boundaries
				var sdf: float
				if is_boundary_chunk:
					# Use distance-based blending at biome boundaries
					sdf = _generate_blended_sdf(world_pos)
				else:
					# Single biome - no blending needed
					sdf = _generate_biome_sdf(world_pos, voxel_biome)
				
				# Determine material based on biome and SDF
				var material_id := _get_biome_material(voxel_biome, sdf, world_pos)
				
				# Write values
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
				out_buffer.set_voxel(material_id, x, y, z, VoxelBuffer.CHANNEL_INDICES)
				
				# Fill in skipped voxels at high LOD (simple copy)
				if sample_step > 1:
					for sz in range(sample_step):
						for sy in range(sample_step):
							for sx in range(sample_step):
								if sx == 0 and sy == 0 and sz == 0:
									continue
								var fx := x + sx
								var fy := y + sy
								var fz := z + sz
								if fx < block_size.x and fy < block_size.y and fz < block_size.z:
									out_buffer.set_voxel_f(sdf, fx, fy, fz, VoxelBuffer.CHANNEL_SDF)
									out_buffer.set_voxel(material_id, fx, fy, fz, VoxelBuffer.CHANNEL_INDICES)
	
	# Emit signal for vegetation placement (only at LOD 0 for performance)
	if lod == 0:
		chunk_generated.emit(origin, primary_biome)


## Check if chunk is near a biome boundary by sampling corners
func _is_near_biome_boundary(chunk_center: Vector3, chunk_size: float) -> bool:
	var half_size := chunk_size * 0.5
	var center_biome := _get_biome_at_position(chunk_center)
	
	# Sample 4 corners
	var corners := [
		Vector3(chunk_center.x - half_size, chunk_center.y, chunk_center.z - half_size),
		Vector3(chunk_center.x + half_size, chunk_center.y, chunk_center.z - half_size),
		Vector3(chunk_center.x - half_size, chunk_center.y, chunk_center.z + half_size),
		Vector3(chunk_center.x + half_size, chunk_center.y, chunk_center.z + half_size)
	]
	
	for corner in corners:
		if _get_biome_at_position(corner) != center_biome:
			return true
	
	return false


# =============================================================================
# DEBUG VISUALIZATION
# =============================================================================

## Debug: Print biome info at a world position
func debug_draw_biome_info(world_pos: Vector3) -> void:
	if not debug_mode:
		return
	
	var biome_id := _get_biome_at_position(world_pos)
	var bm := _get_biome_manager()
	var biome_name := "Unknown"
	var danger := 1.0
	var factions := []
	var ore_richness := 1.0
	if bm:
		biome_name = bm.get_biome_name(biome_id)
		danger = bm.get_danger_rating(biome_id)
		factions = bm.get_allowed_factions(biome_id)
		ore_richness = bm.get_ore_richness(biome_id)
	
	print("[BiomeGenerator] Position: %s" % world_pos)
	print("  Biome: %s (ID: %d)" % [biome_name, biome_id])
	print("  Danger Rating: %.1f" % danger)
	print("  Ore Richness: %.1f" % ore_richness)
	print("  Allowed Factions: %s" % str(factions))


# =============================================================================
# CACHE MANAGEMENT
# =============================================================================

## Clears all caches (call when world map changes)
func clear_caches() -> void:
	_biome_cache.clear()
	_biome_property_cache.clear()


## Reloads the world map (call after MapGenerator creates new map)
func reload_world_map() -> void:
	clear_caches()
	_load_world_map()


## Reloads the world map and emits signal to notify other systems
func reload_world_map_and_notify() -> void:
	reload_world_map()
	if map_ready:
		print("[BiomeGenerator] World map reloaded successfully")
		chunk_generated.emit(Vector3i.ZERO, MapGenerator.Biome.PLAINS)  # Trigger vegetation refresh
	else:
		push_warning("[BiomeGenerator] Failed to reload world map")


## Update seed from WorldSeedManager
func update_seed(new_seed: int) -> void:
	if _base_generator and _base_generator._base_generator:
		_base_generator._base_generator.seed = new_seed
	# Recreate all biome noise instances with new seed
	_create_biome_noise_instances(new_seed)
	clear_caches()
	print("[BiomeGenerator] Seed updated to: %d" % new_seed)
