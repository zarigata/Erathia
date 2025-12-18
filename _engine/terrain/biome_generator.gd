@tool
extends VoxelGeneratorScript
class_name BiomeGenerator

## BiomeGenerator - Wraps OreGenerator and samples world map for biome-specific terrain
## Modifies terrain height, materials, and ore distribution based on biome type

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
var _biome_manager: BiomeManager

# Caches
var _biome_cache: Dictionary = {}  # Vector3i -> int (chunk origin -> biome_id)
var _biome_property_cache: Dictionary = {}  # int -> Dictionary (biome_id -> properties)

# Secondary noise for biome-specific terrain modulation
var _biome_noise: FastNoiseLite

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init() -> void:
	# Instantiate base generator
	_base_generator = OreGenerator.new()
	
	# Create BiomeManager instance
	_biome_manager = BiomeManager.new()
	
	# Configure biome modulation noise
	_biome_noise = FastNoiseLite.new()
	_biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_biome_noise.seed = 12345
	_biome_noise.frequency = 0.005
	_biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_biome_noise.fractal_octaves = 3
	_biome_noise.fractal_lacunarity = 2.0
	_biome_noise.fractal_gain = 0.5
	
	# Load world map
	_load_world_map()


func _load_world_map() -> void:
	_world_map_image = Image.new()
	var error := _world_map_image.load(world_map_path)
	
	if error != OK:
		push_warning("[BiomeGenerator] Failed to load world map from '%s'. Using default biome (PLAINS)." % world_map_path)
		_world_map_image = null
		return
	
	# Validate image format and size
	if _world_map_image.get_width() != map_size or _world_map_image.get_height() != map_size:
		push_warning("[BiomeGenerator] World map size mismatch. Expected %dx%d, got %dx%d. Scaling may occur." % [
			map_size, map_size, _world_map_image.get_width(), _world_map_image.get_height()
		])
	
	if debug_mode:
		print("[BiomeGenerator] World map loaded successfully: %s" % world_map_path)


# =============================================================================
# COORDINATE CONVERSION
# =============================================================================

## Converts world X/Z coordinates to map pixel coordinates
func _world_to_map_coords(world_pos: Vector3) -> Vector2i:
	# World coordinates range from 0 to world_size
	# Map coordinates range from 0 to map_size-1
	var pixel_x := int(world_pos.x / PIXEL_SCALE)
	var pixel_z := int(world_pos.z / PIXEL_SCALE)
	
	# Clamp to valid map bounds
	pixel_x = clampi(pixel_x, 0, map_size - 1)
	pixel_z = clampi(pixel_z, 0, map_size - 1)
	
	return Vector2i(pixel_x, pixel_z)


## Bilinear sampling for smooth biome transitions (returns interpolated biome weights)
func _sample_biome_smooth(world_pos: Vector3) -> Dictionary:
	var map_x := world_pos.x / PIXEL_SCALE
	var map_z := world_pos.z / PIXEL_SCALE
	
	# Get integer and fractional parts
	var x0 := int(floor(map_x))
	var z0 := int(floor(map_z))
	var x1 := mini(x0 + 1, map_size - 1)
	var z1 := mini(z0 + 1, map_size - 1)
	x0 = maxi(x0, 0)
	z0 = maxi(z0, 0)
	
	var fx := map_x - floor(map_x)
	var fz := map_z - floor(map_z)
	
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

## Modifies base height based on biome type
func _get_biome_height_modifier(biome_id: int, base_sdf: float, world_pos: Vector3) -> float:
	var height_range := _biome_manager.get_height_range(biome_id)
	var min_height: float = height_range.get("min", 0)
	var max_height: float = height_range.get("max", 100)
	
	# Remap base_sdf into the biome's elevation window
	# Convert SDF to approximate height in meters (negative SDF = underground)
	# world_pos.y gives the actual height; base_sdf indicates distance to surface
	var current_height: float = world_pos.y
	var height_range_span: float = max_height - min_height
	if height_range_span <= 0.0:
		height_range_span = 100.0  # Fallback to avoid division by zero
	
	# Calculate where current height falls relative to biome's elevation window
	# and adjust SDF to enforce the biome's intended elevation range
	var elevation_factor: float = 0.0
	if current_height < min_height:
		# Below biome's minimum - push terrain up (make more solid)
		elevation_factor = (min_height - current_height) * 0.1
	elif current_height > max_height:
		# Above biome's maximum - push terrain down (make more air)
		elevation_factor = (current_height - max_height) * 0.1
	
	# Apply elevation clamping to base SDF
	var elevation_adjusted_sdf: float = base_sdf + elevation_factor
	
	# Get biome-specific noise parameters
	var noise_params := _get_biome_noise_params(biome_id)
	_biome_noise.frequency = noise_params.get("frequency", 0.005)
	
	# Sample secondary noise for biome-specific terrain variation
	var biome_noise_value := _biome_noise.get_noise_3d(world_pos.x, world_pos.y, world_pos.z)
	var amplitude: float = noise_params.get("amplitude", 1.0)
	
	# Calculate height offset based on biome type
	var height_offset: float = 0.0
	
	match biome_id:
		MapGenerator.Biome.MOUNTAIN, MapGenerator.Biome.ICE_SPIRES:
			# Amplify peaks - push terrain up
			height_offset = -biome_noise_value * amplitude * 30.0
			# Extra peak amplification for high areas
			if base_sdf < -10.0:
				height_offset -= 20.0
		
		MapGenerator.Biome.DEEP_OCEAN:
			# Flatten and lower terrain
			height_offset = 50.0 + biome_noise_value * 10.0
		
		MapGenerator.Biome.BEACH:
			# Clamp to narrow range near sea level
			height_offset = biome_noise_value * 5.0
		
		MapGenerator.Biome.VOLCANIC:
			# Sharp ridges and jagged terrain
			var voronoi_like := abs(biome_noise_value) * amplitude * 25.0
			height_offset = -voronoi_like
		
		MapGenerator.Biome.SWAMP:
			# Very flat with occasional bumps
			height_offset = biome_noise_value * 8.0 + 5.0
		
		MapGenerator.Biome.DESERT:
			# Rolling dunes
			height_offset = sin(world_pos.x * 0.02) * cos(world_pos.z * 0.02) * 15.0
			height_offset += biome_noise_value * amplitude * 10.0
		
		MapGenerator.Biome.PLAINS:
			# Gentle rolling hills
			height_offset = biome_noise_value * amplitude * 8.0
		
		MapGenerator.Biome.FOREST, MapGenerator.Biome.JUNGLE:
			# Moderate terrain variation
			height_offset = biome_noise_value * amplitude * 15.0
		
		MapGenerator.Biome.TUNDRA:
			# Frozen rolling terrain
			height_offset = biome_noise_value * amplitude * 12.0 - 10.0
		
		MapGenerator.Biome.SAVANNA:
			# Mostly flat with gentle rises
			height_offset = biome_noise_value * amplitude * 6.0
		
		MapGenerator.Biome.MUSHROOM:
			# Unusual terrain with pockets
			height_offset = biome_noise_value * amplitude * 18.0
		
		_:
			height_offset = biome_noise_value * amplitude * 10.0
	
	return elevation_adjusted_sdf + height_offset


# =============================================================================
# BIOME MATERIALS
# =============================================================================

## Returns material ID based on biome and depth
func _get_biome_material(biome_id: int, sdf: float, world_pos: Vector3) -> int:
	if sdf > 0.0:
		return MAT_AIR
	
	# Get ore richness for this biome
	var ore_richness := _biome_manager.get_ore_richness(biome_id)
	
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
# BIOME NOISE PARAMETERS
# =============================================================================

## Returns noise parameters for biome-specific terrain generation
func _get_biome_noise_params(biome_id: int) -> Dictionary:
	match biome_id:
		MapGenerator.Biome.PLAINS:
			return {"frequency": 0.003, "amplitude": 1.0, "octaves": 2}
		
		MapGenerator.Biome.MOUNTAIN:
			return {"frequency": 0.008, "amplitude": 2.0, "octaves": 4}
		
		MapGenerator.Biome.ICE_SPIRES:
			return {"frequency": 0.01, "amplitude": 2.5, "octaves": 4}
		
		MapGenerator.Biome.DESERT:
			return {"frequency": 0.005, "amplitude": 1.2, "octaves": 2}
		
		MapGenerator.Biome.SWAMP:
			return {"frequency": 0.002, "amplitude": 0.5, "octaves": 2}
		
		MapGenerator.Biome.VOLCANIC:
			return {"frequency": 0.01, "amplitude": 1.8, "octaves": 3}
		
		MapGenerator.Biome.FOREST:
			return {"frequency": 0.004, "amplitude": 1.3, "octaves": 3}
		
		MapGenerator.Biome.JUNGLE:
			return {"frequency": 0.005, "amplitude": 1.4, "octaves": 3}
		
		MapGenerator.Biome.TUNDRA:
			return {"frequency": 0.004, "amplitude": 1.1, "octaves": 2}
		
		MapGenerator.Biome.SAVANNA:
			return {"frequency": 0.003, "amplitude": 0.8, "octaves": 2}
		
		MapGenerator.Biome.BEACH:
			return {"frequency": 0.002, "amplitude": 0.3, "octaves": 1}
		
		MapGenerator.Biome.DEEP_OCEAN:
			return {"frequency": 0.003, "amplitude": 0.4, "octaves": 2}
		
		MapGenerator.Biome.MUSHROOM:
			return {"frequency": 0.006, "amplitude": 1.5, "octaves": 3}
		
		_:
			return {"frequency": 0.005, "amplitude": 1.0, "octaves": 2}


# =============================================================================
# BIOME TRANSITION SMOOTHING
# =============================================================================

## Returns blended biome data for smooth transitions
func _smooth_biome_transition(world_pos: Vector3, primary_biome: int) -> Dictionary:
	var biome_weights := _sample_biome_smooth(world_pos)
	
	# If only one biome, no blending needed
	if biome_weights.size() == 1:
		return {"biome_ids": [primary_biome], "weights": [1.0]}
	
	# Sort by weight descending
	var sorted_biomes: Array = []
	for biome_id in biome_weights:
		sorted_biomes.append([biome_id, biome_weights[biome_id]])
	sorted_biomes.sort_custom(func(a, b): return a[1] > b[1])
	
	var biome_ids: Array = []
	var weights: Array = []
	for entry in sorted_biomes:
		biome_ids.append(entry[0])
		weights.append(entry[1])
	
	return {"biome_ids": biome_ids, "weights": weights}


## Blends height modifiers from multiple biomes
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
	
	# First pass: Generate base terrain SDF using the base generator
	_base_generator._base_generator.generate_block(out_buffer, origin, lod)
	
	# Calculate chunk center for biome sampling
	var center := Vector3(origin) + Vector3(block_size) * 0.5 * lod_scale
	var primary_biome := _get_biome_at_position(center)
	
	# Get transition data for smooth blending
	var transition_data := _smooth_biome_transition(center, primary_biome)
	
	# LOD-aware sampling frequency
	var sample_step := 1
	if lod >= 2:
		sample_step = 2  # Sample every 2nd voxel at high LOD
	if lod >= 4:
		sample_step = 4  # Sample every 4th voxel at very high LOD
	
	# Second pass: Apply biome modifications
	for z in range(0, block_size.z, sample_step):
		for y in range(0, block_size.y, sample_step):
			for x in range(0, block_size.x, sample_step):
				# Calculate world position
				var world_x: float = origin.x + x * lod_scale
				var world_y: float = origin.y + y * lod_scale
				var world_z: float = origin.z + z * lod_scale
				var world_pos := Vector3(world_x, world_y, world_z)
				
				# Get base SDF value
				var base_sdf: float = out_buffer.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
				
				# Apply biome height modifier with blending
				var modified_sdf: float
				var transition_biome_ids: Array = transition_data.get("biome_ids", [])
				var voxel_transition: Dictionary = {}
				
				if transition_biome_ids.size() > 1:
					# Per-voxel transition sampling for accuracy at biome boundaries
					voxel_transition = _smooth_biome_transition(world_pos, primary_biome)
					modified_sdf = _blend_height_modifiers(world_pos, base_sdf, voxel_transition)
				else:
					modified_sdf = _get_biome_height_modifier(primary_biome, base_sdf, world_pos)
				
				# Determine material based on biome - use highest-weight biome from voxel_transition
				var material_biome: int = primary_biome
				var voxel_biome_ids: Array = voxel_transition.get("biome_ids", [])
				if voxel_biome_ids.size() > 0:
					# Use the highest-weight biome (first in sorted array) for material
					material_biome = voxel_biome_ids[0]
				
				var material_id := _get_biome_material(material_biome, modified_sdf, world_pos)
				
				# Write modified values
				out_buffer.set_voxel_f(modified_sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
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
									out_buffer.set_voxel_f(modified_sdf, fx, fy, fz, VoxelBuffer.CHANNEL_SDF)
									out_buffer.set_voxel(material_id, fx, fy, fz, VoxelBuffer.CHANNEL_INDICES)


# =============================================================================
# DEBUG VISUALIZATION
# =============================================================================

## Debug: Print biome info at a world position
func debug_draw_biome_info(world_pos: Vector3) -> void:
	if not debug_mode:
		return
	
	var biome_id := _get_biome_at_position(world_pos)
	var biome_name := _biome_manager.get_biome_name(biome_id)
	var danger := _biome_manager.get_danger_rating(biome_id)
	var factions := _biome_manager.get_allowed_factions(biome_id)
	var ore_richness := _biome_manager.get_ore_richness(biome_id)
	
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
