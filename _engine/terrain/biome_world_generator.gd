@tool
extends VoxelGeneratorScript
class_name BiomeWorldGenerator

## Biome World Generator
## 
## A complete terrain generator with:
## - Smooth height transitions via buffer zones (no 90-degree cliffs)
## - Valheim-style islands and continents
## - Biome-specific materials
## - Procedural vegetation support

signal chunk_generated(origin: Vector3i, biome_id: int)

# =============================================================================
# MATERIAL CONSTANTS (must match shader)
# =============================================================================

const MAT_AIR: int = 0
const MAT_DIRT: int = 1
const MAT_STONE: int = 2
const MAT_IRON_ORE: int = 3
const MAT_SAND: int = 4
const MAT_SNOW: int = 5
const MAT_GRASS: int = 6

# =============================================================================
# TERRAIN PARAMETERS
# =============================================================================

const SEA_LEVEL: float = 0.0
const SURFACE_THICKNESS: float = 3.0
const DIRT_THICKNESS: float = 6.0

# Maximum slope angle in degrees (35 degrees = ~0.7 height per meter)
const MAX_SLOPE_DEGREES: float = 35.0
const MAX_SLOPE_GRADIENT: float = 0.7  # tan(35°) ≈ 0.7

# Buffer zone settings - controls how smoothly biomes blend
const BUFFER_ZONE_RADIUS: float = 500.0  # Increased for smoother transitions
const HEIGHT_SAMPLE_RADIUS: float = 400.0  # How far to sample for height blending
const HEIGHT_BLEND_STRENGTH: float = 0.3  # Modulation factor for height offsets

# =============================================================================
# NOISE GENERATORS
# =============================================================================

var _continent_noise: FastNoiseLite  # Large scale land/ocean
var _terrain_noise: FastNoiseLite    # Medium scale hills
var _detail_noise: FastNoiseLite     # Small scale variation
var _biome_noise: FastNoiseLite      # Biome regions
var _temperature_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite
var _mountain_noise: FastNoiseLite   # Mountain ridges

var _world_seed: int = 0
var _initialized: bool = false
var _emit_debug_enabled: bool = false
var _emission_count: int = 0
var _emitted_chunks: Dictionary = {}
var _last_emitted_chunk: Vector3i = Vector3i.ZERO
var _last_emitted_biome: int = MapGenerator.Biome.PLAINS

# =============================================================================
# BIOME BASE HEIGHTS (meters above sea level) - HIGH ALTITUDES PRESERVED
# =============================================================================

var _biome_base_heights: Dictionary = {
	# Reduced heights for smoother transitions
	MapGenerator.Biome.PLAINS: 10.0,
	MapGenerator.Biome.FOREST: 15.0,        # Was 20.0
	MapGenerator.Biome.DESERT: 12.0,        # Was 15.0
	MapGenerator.Biome.SWAMP: 3.0,
	MapGenerator.Biome.TUNDRA: 35.0,        # Was 40.0
	MapGenerator.Biome.JUNGLE: 8.0,
	MapGenerator.Biome.SAVANNA: 12.0,
	MapGenerator.Biome.MOUNTAIN: 80.0,      # Was 120.0 - REDUCED
	MapGenerator.Biome.BEACH: 2.0,
	MapGenerator.Biome.DEEP_OCEAN: -50.0,
	MapGenerator.Biome.ICE_SPIRES: 100.0,   # Was 150.0 - REDUCED
	MapGenerator.Biome.VOLCANIC: 70.0,      # Was 100.0 - REDUCED
	MapGenerator.Biome.MUSHROOM: 25.0,      # Was 30.0
	# Transition biomes - interpolated heights
	MapGenerator.Biome.SLOPE_PLAINS: 10.0,
	MapGenerator.Biome.SLOPE_FOREST: 20.0,
	MapGenerator.Biome.SLOPE_MOUNTAIN: 50.0,  # Was 60.0
	MapGenerator.Biome.SLOPE_SNOW: 65.0,      # Was 80.0
	MapGenerator.Biome.SLOPE_VOLCANIC: 45.0,  # Was 50.0
	MapGenerator.Biome.CLIFF_COASTAL: 5.0,
	MapGenerator.Biome.SLOPE_DESERT: 15.0,
}

# Height variation per biome - natural terrain variation within each biome
var _biome_variation: Dictionary = {
	MapGenerator.Biome.PLAINS: 12.0,      # Rolling hills
	MapGenerator.Biome.FOREST: 18.0,      # Hilly forest
	MapGenerator.Biome.DESERT: 15.0,      # Dunes
	MapGenerator.Biome.SWAMP: 5.0,        # Low wetlands
	MapGenerator.Biome.TUNDRA: 20.0,      # Moderate hills
	MapGenerator.Biome.JUNGLE: 15.0,      # Tropical hills
	MapGenerator.Biome.SAVANNA: 10.0,     # Gentle grasslands
	MapGenerator.Biome.MOUNTAIN: 50.0,    # Mountain peaks
	MapGenerator.Biome.BEACH: 3.0,        # Flat beach
	MapGenerator.Biome.DEEP_OCEAN: 15.0,  # Ocean floor variation
	MapGenerator.Biome.ICE_SPIRES: 60.0,  # Ice mountain peaks
	MapGenerator.Biome.VOLCANIC: 40.0,    # Volcanic mountains
	MapGenerator.Biome.MUSHROOM: 20.0,    # Moderate hills
	# Transition biomes
	MapGenerator.Biome.SLOPE_PLAINS: 8.0,
	MapGenerator.Biome.SLOPE_FOREST: 12.0,
	MapGenerator.Biome.SLOPE_MOUNTAIN: 20.0,
	MapGenerator.Biome.SLOPE_SNOW: 25.0,
	MapGenerator.Biome.SLOPE_VOLCANIC: 20.0,
	MapGenerator.Biome.CLIFF_COASTAL: 5.0,
	MapGenerator.Biome.SLOPE_DESERT: 10.0,
}

# Slope aggressiveness - transition biomes are always at max 35 degrees
var _biome_slope: Dictionary = {
	MapGenerator.Biome.PLAINS: 0.1,
	MapGenerator.Biome.FOREST: 0.2,
	MapGenerator.Biome.DESERT: 0.15,
	MapGenerator.Biome.SWAMP: 0.05,
	MapGenerator.Biome.TUNDRA: 0.2,
	MapGenerator.Biome.JUNGLE: 0.25,
	MapGenerator.Biome.SAVANNA: 0.1,
	MapGenerator.Biome.MOUNTAIN: 0.3,         # Internal mountain slopes
	MapGenerator.Biome.BEACH: 0.05,
	MapGenerator.Biome.DEEP_OCEAN: 0.1,
	MapGenerator.Biome.ICE_SPIRES: 0.35,      # Max slope within biome
	MapGenerator.Biome.VOLCANIC: 0.3,
	MapGenerator.Biome.MUSHROOM: 0.2,
	# Transition biomes - all at 35 degree max (tan(35°) ≈ 0.7)
	MapGenerator.Biome.SLOPE_PLAINS: 0.7,
	MapGenerator.Biome.SLOPE_FOREST: 0.7,
	MapGenerator.Biome.SLOPE_MOUNTAIN: 0.7,
	MapGenerator.Biome.SLOPE_SNOW: 0.7,
	MapGenerator.Biome.SLOPE_VOLCANIC: 0.7,
	MapGenerator.Biome.CLIFF_COASTAL: 0.7,
	MapGenerator.Biome.SLOPE_DESERT: 0.7,
}

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init() -> void:
	_initialize_noise()


func _initialize_noise() -> void:
	# Get world seed
	var seed_manager = Engine.get_singleton("WorldSeedManager") if Engine.has_singleton("WorldSeedManager") else null
	if seed_manager:
		_world_seed = seed_manager.get_world_seed()
	else:
		randomize()
		_world_seed = randi() % 999999999
	
	# Continent noise - Valheim-style islands/continents
	_continent_noise = FastNoiseLite.new()
	_continent_noise.seed = _world_seed
	_continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent_noise.frequency = 0.0003  # Very large scale
	_continent_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_continent_noise.fractal_octaves = 4
	_continent_noise.fractal_lacunarity = 2.0
	_continent_noise.fractal_gain = 0.5
	
	# Main terrain noise - hills and valleys
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = _world_seed + 50
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.003  # Balanced frequency
	_terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_terrain_noise.fractal_octaves = 4  # Restored for terrain detail
	_terrain_noise.fractal_lacunarity = 2.0
	_terrain_noise.fractal_gain = 0.5  # Normal gain
	
	# Detail noise - small bumps and texture
	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = _world_seed + 100
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail_noise.frequency = 0.03
	_detail_noise.fractal_octaves = 3
	
	# Mountain ridge noise - creates mountain chains
	_mountain_noise = FastNoiseLite.new()
	_mountain_noise.seed = _world_seed + 150
	_mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mountain_noise.frequency = 0.001  # Mountain scale
	_mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED  # Ridged for mountain peaks
	_mountain_noise.fractal_octaves = 3  # Moderate detail
	_mountain_noise.fractal_gain = 0.5  # Normal gain
	
	# Biome noise - cellular for distinct regions
	_biome_noise = FastNoiseLite.new()
	_biome_noise.seed = _world_seed + 200
	_biome_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	_biome_noise.frequency = 0.0006
	_biome_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	
	# Temperature noise - latitude-like bands
	_temperature_noise = FastNoiseLite.new()
	_temperature_noise.seed = _world_seed + 300
	_temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_temperature_noise.frequency = 0.0008
	_temperature_noise.fractal_octaves = 3
	
	# Moisture noise
	_moisture_noise = FastNoiseLite.new()
	_moisture_noise.seed = _world_seed + 400
	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moisture_noise.frequency = 0.001
	_moisture_noise.fractal_octaves = 3
	
	_initialized = true
	print("[BiomeWorldGenerator] Initialized with seed: %d" % _world_seed)


func update_seed(new_seed: int) -> void:
	_world_seed = new_seed
	_initialize_noise()


# =============================================================================
# VOXEL GENERATOR INTERFACE
# =============================================================================

func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES)


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if not _initialized:
		_initialize_noise()
	
	var block_size: Vector3i = out_buffer.get_size()
	var lod_scale: int = 1 << lod
	
	# Get primary biome for this chunk (for vegetation signal)
	var chunk_center_x: float = origin.x + (block_size.x * lod_scale) * 0.5
	var chunk_center_z: float = origin.z + (block_size.z * lod_scale) * 0.5
	var primary_biome: int = _get_biome_at(chunk_center_x, chunk_center_z)
	
	for z in range(block_size.z):
		for x in range(block_size.x):
			var world_x: float = origin.x + x * lod_scale
			var world_z: float = origin.z + z * lod_scale
			
			# Get SMOOTH terrain height with buffer zone blending
			var terrain_height: float = _get_smooth_terrain_height(world_x, world_z)
			var biome: int = _get_biome_at(world_x, world_z)
			
			for y in range(block_size.y):
				var world_y: float = origin.y + y * lod_scale
				
				# Calculate SDF (negative = solid, positive = air)
				var sdf: float = world_y - terrain_height
				
				# Add 3D detail noise scaled by LOD
				var detail_scale: float = 1.5 / (1.0 + lod * 0.5)
				var detail: float = _detail_noise.get_noise_3d(world_x, world_y, world_z) * detail_scale
				sdf += detail
				
				# Write SDF
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
				
				# Get material for this voxel
				var material: int = _get_material(biome, sdf, world_y, terrain_height, Vector3(world_x, world_y, world_z))
				out_buffer.set_voxel(material, x, y, z, VoxelBuffer.CHANNEL_INDICES)
	
	# Emit signal for vegetation spawning (LOD 0 only)
	if lod == 0:
		_emission_count += 1
		_last_emitted_chunk = origin
		_last_emitted_biome = primary_biome
		_emitted_chunks[origin] = primary_biome
		if _emit_debug_enabled:
			print("[BiomeWorldGenerator] Emitting chunk_generated #%d origin=%s biome=%d" % [_emission_count, origin, primary_biome])
		chunk_generated.emit(origin, primary_biome)


# =============================================================================
# SMOOTH TERRAIN HEIGHT WITH BUFFER ZONES
# =============================================================================

func _get_smooth_terrain_height(world_x: float, world_z: float) -> float:
	## Calculate terrain height with smooth buffer zone blending between biomes
	## This prevents 90-degree cliff transitions
	
	# Get continent value for island/ocean determination
	var continent_val: float = _continent_noise.get_noise_2d(world_x, world_z)
	continent_val = (continent_val + 1.0) * 0.5  # 0-1
	
	# Distance from world center (for Valheim-style ring ocean)
	var dist_from_center: float = sqrt(world_x * world_x + world_z * world_z)
	var world_radius: float = 5000.0
	var ocean_start: float = world_radius * 0.85
	
	# Calculate ocean factor (0 = land, 1 = deep ocean)
	var ocean_factor: float = 0.0
	if dist_from_center > ocean_start:
		ocean_factor = smoothstep(ocean_start, world_radius, dist_from_center)
	
	# Also use continent noise for internal oceans/lakes
	var internal_ocean: float = 0.0
	if continent_val < 0.35:
		internal_ocean = smoothstep(0.35, 0.2, continent_val)
	
	ocean_factor = maxf(ocean_factor, internal_ocean)
	
	# Sample heights from multiple nearby points for smooth blending
	var blended_height: float = _sample_blended_height(world_x, world_z)
	
	# NEW: Clamp slope gradient to max 35 degrees
	blended_height = _apply_slope_limiting(world_x, world_z, blended_height)
	
	# Apply ocean depth
	var ocean_depth: float = -35.0
	var final_height: float = lerpf(blended_height, ocean_depth, ocean_factor)
	
	# Add beach transition
	if ocean_factor > 0.0 and ocean_factor < 0.3:
		var beach_blend: float = smoothstep(0.0, 0.3, ocean_factor)
		final_height = lerpf(blended_height, 1.0, beach_blend * 0.5)
	
	return final_height


func _sample_blended_height(world_x: float, world_z: float) -> float:
	## ENHANCED: 16-point radial sampling with distance-weighted blending
	
	var center_biome: int = _get_primary_biome_at(world_x, world_z)
	var center_height: float = _get_raw_biome_height(world_x, world_z, center_biome)
	
	# Sample 16 points in radial pattern at 3 distances
	var sample_distances: Array[float] = [
		HEIGHT_SAMPLE_RADIUS * 0.33,  # ~133m
		HEIGHT_SAMPLE_RADIUS * 0.66,  # ~266m
		HEIGHT_SAMPLE_RADIUS          # ~400m
	]
	
	var total_weight: float = 1.0  # Center point weight
	var weighted_height_sum: float = center_height
	var biomes_found: Dictionary = {center_biome: true}
	
	# 16 directions (every 22.5 degrees)
	for angle_idx in range(16):
		var angle: float = (float(angle_idx) / 16.0) * TAU
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		
		for dist in sample_distances:
			var sample_x: float = world_x + dir.x * dist
			var sample_z: float = world_z + dir.y * dist
			var sample_biome: int = _get_primary_biome_at(sample_x, sample_z)
			
			# If different biome found, add to blend
			if sample_biome != center_biome:
				biomes_found[sample_biome] = true
				var sample_height: float = _get_raw_biome_height(sample_x, sample_z, sample_biome)
				
				# Distance-based weight (closer = more influence)
				var weight: float = 1.0 - (dist / HEIGHT_SAMPLE_RADIUS)
				weight = weight * weight  # Quadratic falloff
				
				weighted_height_sum += sample_height * weight
				total_weight += weight
				break  # Found boundary in this direction, stop sampling further
	
	# If only one biome, return raw height
	if biomes_found.size() == 1:
		return center_height
	
	# Compute blended height
	var blended_height: float = weighted_height_sum / total_weight
	
	# Apply smoothstep to prevent sharp transitions
	var blend_factor: float = clampf(float(biomes_found.size() - 1) / 3.0, 0.0, 1.0)
	blend_factor = blend_factor * blend_factor * (3.0 - 2.0 * blend_factor)  # Smoothstep
	
	return lerpf(center_height, blended_height, blend_factor * HEIGHT_BLEND_STRENGTH)


func _get_raw_biome_height(world_x: float, world_z: float, biome: int) -> float:
	## Get raw terrain height for a specific biome without blending
	
	# Base terrain noise
	var terrain_val: float = _terrain_noise.get_noise_2d(world_x, world_z)
	terrain_val = (terrain_val + 1.0) * 0.5  # 0-1
	
	# Mountain ridge contribution
	var mountain_val: float = _mountain_noise.get_noise_2d(world_x, world_z)
	mountain_val = absf(mountain_val)  # Ridged noise gives sharp peaks
	
	# Get biome parameters
	var base_height: float = _biome_base_heights.get(biome, 10.0)
	var variation: float = _biome_variation.get(biome, 10.0)
	var slope_factor: float = _biome_slope.get(biome, 0.3)
	
	# Calculate height
	var height: float = base_height + terrain_val * variation
	
	# Add mountain ridges for mountain/volcanic/ice biomes
	if biome == MapGenerator.Biome.MOUNTAIN or biome == MapGenerator.Biome.ICE_SPIRES or biome == MapGenerator.Biome.VOLCANIC:
		height += mountain_val * variation * slope_factor
	
	# NEW: Add subtle detail noise (+/-2m) for micro-variation
	var detail_val: float = _detail_noise.get_noise_2d(world_x, world_z)
	height += detail_val * 2.0 * HEIGHT_BLEND_STRENGTH  # +/-0.6m effective
	
	return height


func _apply_slope_limiting(world_x: float, world_z: float, target_height: float) -> float:
	## Limit slope to MAX_SLOPE_GRADIENT (35 degrees) by clamping height changes
	var sample_dist: float = 8.0  # Check 8m radius
	var max_height_change: float = sample_dist * MAX_SLOPE_GRADIENT  # ~5.6m over 8m
	
	# Sample 4 cardinal neighbors
	var neighbors: Array[float] = [
		_sample_blended_height(world_x + sample_dist, world_z),
		_sample_blended_height(world_x - sample_dist, world_z),
		_sample_blended_height(world_x, world_z + sample_dist),
		_sample_blended_height(world_x, world_z - sample_dist)
	]
	
	# Find average neighbor height
	var avg_neighbor_h: float = 0.0
	for h in neighbors:
		avg_neighbor_h += h
	if neighbors.size() > 0:
		avg_neighbor_h /= neighbors.size()
	
	# Clamp target height to max slope from average
	var height_diff: float = target_height - avg_neighbor_h
	if absf(height_diff) > max_height_change:
		target_height = avg_neighbor_h + signf(height_diff) * max_height_change
	
	return target_height


# =============================================================================
# BIOME DETERMINATION
# =============================================================================

func _get_primary_biome_at(world_x: float, world_z: float) -> int:
	## Get the PRIMARY biome at a position (used internally for transition calculations)
	## This determines the base biome without considering transition zones
	return _get_biome_at(world_x, world_z)


func _get_biome_at(world_x: float, world_z: float) -> int:
	## Determine biome at world position
	## LARGER BIOMES: noise is sampled at reduced frequency for bigger biome regions
	
	# Scale down coordinates for larger biomes
	var biome_scale: float = 0.5  # Makes biomes 2x larger
	var bx: float = world_x * biome_scale
	var bz: float = world_z * biome_scale
	
	# Sample noise layers (at scaled coordinates for larger biomes)
	var biome_val: float = (_biome_noise.get_noise_2d(bx, bz) + 1.0) * 0.5
	var temp: float = (_temperature_noise.get_noise_2d(bx, bz) + 1.0) * 0.5
	var moisture: float = (_moisture_noise.get_noise_2d(bx, bz) + 1.0) * 0.5
	var continent: float = (_continent_noise.get_noise_2d(bx, bz) + 1.0) * 0.5
	
	# Distance from center for ring ocean
	var dist: float = sqrt(world_x * world_x + world_z * world_z)
	var world_radius: float = 5000.0
	
	# Check if near water (for jungle placement)
	var is_near_water: bool = _is_near_water(world_x, world_z, 200.0)
	
	# Deep ocean at world edges
	if dist > world_radius * 0.9:
		return MapGenerator.Biome.DEEP_OCEAN
	
	# Beach near ocean edge - enhanced beach biome with palm trees
	if dist > world_radius * 0.82 and dist < world_radius * 0.88:
		return MapGenerator.Biome.BEACH
	
	# Internal oceans from continent noise
	if continent < 0.25:
		return MapGenerator.Biome.DEEP_OCEAN
	elif continent < 0.38:
		return MapGenerator.Biome.BEACH
	
	# Mountain noise influence (at original scale for variation)
	var mountain_val: float = absf(_mountain_noise.get_noise_2d(world_x * 0.7, world_z * 0.7))
	
	# Temperature and moisture based biomes
	if temp > 0.70:
		# Hot biomes
		if moisture < 0.30:
			return MapGenerator.Biome.DESERT
		elif moisture > 0.58 and is_near_water:
			# JUNGLE ONLY NEAR WATER/COAST
			return MapGenerator.Biome.JUNGLE
		elif mountain_val > 0.55:
			return MapGenerator.Biome.VOLCANIC
		else:
			return MapGenerator.Biome.SAVANNA
	elif temp < 0.30:
		# Cold biomes
		if mountain_val > 0.45:
			return MapGenerator.Biome.ICE_SPIRES
		else:
			return MapGenerator.Biome.TUNDRA
	
	# Temperate biomes
	if mountain_val > 0.50:
		return MapGenerator.Biome.MOUNTAIN
	elif moisture > 0.62:
		return MapGenerator.Biome.SWAMP
	elif moisture > 0.40:
		return MapGenerator.Biome.FOREST
	elif biome_val > 0.72:
		return MapGenerator.Biome.MUSHROOM
	
	return MapGenerator.Biome.PLAINS


func _is_near_water(world_x: float, world_z: float, _radius: float) -> bool:
	## OPTIMIZED: Quick check if position is near water
	## Uses only distance check and single noise sample for performance
	
	# Check ring ocean proximity (fast distance check)
	var dist_sq: float = world_x * world_x + world_z * world_z
	var world_radius_sq: float = 5000.0 * 5000.0
	if dist_sq > world_radius_sq * 0.56:  # 0.75^2 = 0.5625
		return true  # Near ring ocean
	
	# Single continent noise check at this position (no sampling loop)
	var continent: float = (_continent_noise.get_noise_2d(world_x * 0.5, world_z * 0.5) + 1.0) * 0.5
	return continent < 0.45  # Slightly higher threshold for "near water"


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# =============================================================================
# MATERIAL ASSIGNMENT
# =============================================================================

func _get_material(biome: int, sdf: float, world_y: float, terrain_height: float, world_pos: Vector3) -> int:
	# Air
	if sdf > 0.0:
		return MAT_AIR
	
	var depth: float = terrain_height - world_y
	
	# Surface layer
	if depth < SURFACE_THICKNESS:
		return _get_surface_material(biome, world_pos, terrain_height)
	
	# Subsurface layer
	if depth < SURFACE_THICKNESS + DIRT_THICKNESS:
		return _get_subsurface_material(biome)
	
	# Deep underground
	return MAT_STONE


func _get_surface_material(biome: int, world_pos: Vector3, terrain_height: float) -> int:
	## Enhanced with slope-based transitions
	
	# Calculate terrain slope at this position
	var slope: float = _calculate_slope_at(world_pos.x, world_pos.z)
	
	# If slope > 30 degrees (tan(30°) ≈ 0.577), use rock regardless of biome
	if slope > 0.577:
		return MAT_STONE
	
	match biome:
		MapGenerator.Biome.DESERT, MapGenerator.Biome.BEACH:
			return MAT_SAND
		MapGenerator.Biome.TUNDRA, MapGenerator.Biome.ICE_SPIRES:
			# Blend snow→rock on slopes 20-30 degrees
			if slope > 0.364:  # tan(20°)
				var blend: float = (slope - 0.364) / (0.577 - 0.364)
				return MAT_STONE if blend > 0.5 else MAT_SNOW
			return MAT_SNOW
		MapGenerator.Biome.VOLCANIC, MapGenerator.Biome.MOUNTAIN:
			return MAT_STONE
		MapGenerator.Biome.DEEP_OCEAN:
			return MAT_SAND
		MapGenerator.Biome.PLAINS, MapGenerator.Biome.FOREST, MapGenerator.Biome.JUNGLE, MapGenerator.Biome.SAVANNA:
			# Blend grass→rock on slopes 25-30 degrees
			if slope > 0.466:  # tan(25°)
				var blend: float = (slope - 0.466) / (0.577 - 0.466)
				return MAT_STONE if blend > 0.5 else MAT_GRASS
			return MAT_GRASS
		MapGenerator.Biome.SWAMP, MapGenerator.Biome.MUSHROOM:
			return MAT_DIRT
		_:
			return MAT_GRASS


func _calculate_slope_at(world_x: float, world_z: float) -> float:
	## Calculate terrain slope (rise/run) using 4-point gradient
	var center_h: float = _get_smooth_terrain_height(world_x, world_z)
	var sample_dist: float = 2.0  # 2 meters
	
	var h_east: float = _get_smooth_terrain_height(world_x + sample_dist, world_z)
	var h_west: float = _get_smooth_terrain_height(world_x - sample_dist, world_z)
	var h_north: float = _get_smooth_terrain_height(world_x, world_z + sample_dist)
	var h_south: float = _get_smooth_terrain_height(world_x, world_z - sample_dist)
	
	var dx: float = (h_east - h_west) / (2.0 * sample_dist)
	var dz: float = (h_north - h_south) / (2.0 * sample_dist)
	
	return sqrt(dx * dx + dz * dz)  # Gradient magnitude (tan of slope angle)


func _get_subsurface_material(biome: int) -> int:
	match biome:
		MapGenerator.Biome.DESERT, MapGenerator.Biome.BEACH:
			return MAT_SAND
		_:
			return MAT_DIRT


# =============================================================================
# PUBLIC API
# =============================================================================

func get_biome_at_position(pos: Vector3) -> int:
	return _get_biome_at(pos.x, pos.z)


func get_height_at_position(pos: Vector3) -> float:
	return _get_smooth_terrain_height(pos.x, pos.z)


func get_biome_slope(biome: int) -> float:
	return _biome_slope.get(biome, 0.3)


func get_signal_emission_stats() -> Dictionary:
	return {
		"emission_count": _emission_count,
		"last_chunk": _last_emitted_chunk,
		"last_biome": _last_emitted_biome,
		"unique_chunks": _emitted_chunks.size()
	}
