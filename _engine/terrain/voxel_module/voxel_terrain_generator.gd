class_name VoxelTerrainGenerator
extends VoxelGeneratorScript
## Voxel terrain generator using BiomeManager for height and biome data.
## This script generates smooth SDF terrain compatible with VoxelLodTerrain.

# Noise for terrain generation (mirrors BiomeManager settings)
var noise_continental: FastNoiseLite
var noise_temperature: FastNoiseLite
var noise_humidity: FastNoiseLite
var noise_erosion: FastNoiseLite
var noise_domain_warp: FastNoiseLite

# Configuration (should match BiomeManager)
var world_seed: int = 0
var continental_frequency: float = 0.0003
var temperature_frequency: float = 0.0004
var humidity_frequency: float = 0.0005
var erosion_frequency: float = 0.002

var sea_level_threshold: float = 0.0
var beach_band: float = 0.08
var mountain_threshold: float = 0.6
var inland_min_continental: float = 0.1

var continental_domain_warp_enabled: bool = true
var continental_domain_warp_amplitude: float = 600.0
var continental_domain_warp_frequency: float = 0.0002

var terrain_height_scale: float = 80.0
var sea_floor_height: float = -20.0

# Material IDs
const MAT_AIR: int = 0
const MAT_STONE: int = 1
const MAT_DIRT: int = 2
const MAT_GRASS: int = 3
const MAT_SAND: int = 4
const MAT_SNOW: int = 5
const MAT_GRAVEL: int = 6


func _init():
	_setup_noise()


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var block_size: int = out_buffer.get_size().x
	var lod_scale: int = 1 << lod
	
	for z in range(block_size):
		for x in range(block_size):
			var world_x: float = origin.x + x * lod_scale
			var world_z: float = origin.z + z * lod_scale
			
			# Get terrain height using BiomeManager-style calculation
			var height: float = _get_terrain_height(world_x, world_z)
			
			for y in range(block_size):
				var world_y: float = origin.y + y * lod_scale
				
				# SDF: negative = inside (solid), positive = outside (air)
				# We use height - world_y so below height is solid
				var sdf: float = world_y - height
				
				# Normalize SDF for voxel system
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)


func _get_terrain_height(x: float, z: float) -> float:
	var continental_pos: Vector2 = _sample_continental_pos(x, z)
	var continental: float = noise_continental.get_noise_2d(continental_pos.x, continental_pos.y)
	
	# Ocean floor
	if continental < sea_level_threshold:
		var depth_factor: float = clampf((sea_level_threshold - continental) / 0.4, 0.0, 1.0)
		return lerpf(sea_floor_height * 0.5, sea_floor_height, depth_factor)
	
	# Beach - gentle slope near sea level
	if absf(continental - sea_level_threshold) <= beach_band:
		var beach_progress: float = (continental - sea_level_threshold) / beach_band
		return lerpf(1.0, 5.0, clampf(beach_progress, 0.0, 1.0))
	
	# Land height based on continental value
	var land_factor: float = clampf((continental - sea_level_threshold - beach_band) / (1.0 - sea_level_threshold - beach_band), 0.0, 1.0)
	
	# Smooth curve for base terrain - gradual rise inland
	var inland_curve: float = pow(land_factor, 0.6)
	var base_height: float = lerpf(6.0, terrain_height_scale * 0.35, inland_curve)
	
	# Erosion creates hills - use smooth pow curve
	var erosion: float = _remap_noise01(noise_erosion.get_noise_2d(x, z))
	var erosion_curve: float = pow(erosion, 2.0)
	var hills: float = erosion_curve * terrain_height_scale * 0.6 * land_factor
	
	# Enhanced mountain peaks for high erosion areas
	if erosion > mountain_threshold and land_factor > 0.3:
		var mountain_factor: float = (erosion - mountain_threshold) / (1.0 - mountain_threshold)
		var peak_boost: float = pow(mountain_factor, 1.5) * terrain_height_scale * 0.8
		hills += peak_boost
	
	# Add local detail noise for micro-variation
	var detail: float = noise_temperature.get_noise_2d(x * 3.0, z * 3.0) * 2.0 * land_factor
	
	return base_height + hills + detail


func _sample_continental_pos(x: float, z: float) -> Vector2:
	if not continental_domain_warp_enabled:
		return Vector2(x, z)
	
	var dx: float = noise_domain_warp.get_noise_2d(x, z) * continental_domain_warp_amplitude
	var dz: float = noise_domain_warp.get_noise_2d(x + 1337.0, z + 1337.0) * continental_domain_warp_amplitude
	return Vector2(x + dx, z + dz)


func _remap_noise01(v: float) -> float:
	return clamp((v + 1.0) * 0.5, 0.0, 1.0)


func _setup_noise() -> void:
	noise_continental = FastNoiseLite.new()
	noise_continental.seed = world_seed
	noise_continental.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_continental.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_continental.fractal_octaves = 5
	noise_continental.fractal_gain = 0.5
	noise_continental.fractal_lacunarity = 2.0
	noise_continental.frequency = continental_frequency

	noise_temperature = FastNoiseLite.new()
	noise_temperature.seed = world_seed + 1013
	noise_temperature.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_temperature.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_temperature.fractal_octaves = 4
	noise_temperature.fractal_gain = 0.5
	noise_temperature.fractal_lacunarity = 2.0
	noise_temperature.frequency = temperature_frequency

	noise_humidity = FastNoiseLite.new()
	noise_humidity.seed = world_seed + 2027
	noise_humidity.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_humidity.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_humidity.fractal_octaves = 4
	noise_humidity.fractal_gain = 0.5
	noise_humidity.fractal_lacunarity = 2.0
	noise_humidity.frequency = humidity_frequency

	noise_erosion = FastNoiseLite.new()
	noise_erosion.seed = world_seed + 3049
	noise_erosion.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_erosion.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_erosion.fractal_octaves = 5
	noise_erosion.fractal_gain = 0.55
	noise_erosion.fractal_lacunarity = 2.2
	noise_erosion.frequency = erosion_frequency

	noise_domain_warp = FastNoiseLite.new()
	noise_domain_warp.seed = world_seed + 4093
	noise_domain_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_domain_warp.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_domain_warp.fractal_octaves = 3
	noise_domain_warp.fractal_gain = 0.5
	noise_domain_warp.fractal_lacunarity = 2.0
	noise_domain_warp.frequency = continental_domain_warp_frequency


func set_world_seed(seed_value: int) -> void:
	world_seed = seed_value
	_setup_noise()
