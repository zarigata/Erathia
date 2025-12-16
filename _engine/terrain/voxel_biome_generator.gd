class_name VoxelBiomeGenerator
extends VoxelGeneratorScript

@export var world_seed: int = 0

@export var continental_frequency: float = 0.0003
@export var temperature_frequency: float = 0.0004
@export var humidity_frequency: float = 0.0005
@export var erosion_frequency: float = 0.003

@export var sea_level_threshold: float = 0.0
@export var beach_band: float = 0.08
@export var deep_ocean_depth: float = 0.35

@export var mountain_threshold: float = 0.55
@export var spires_threshold: float = 0.72
@export var inland_min_continental: float = 0.05

@export var continental_domain_warp_enabled: bool = true
@export var continental_domain_warp_amplitude: float = 800.0
@export var continental_domain_warp_frequency: float = 0.0002

@export var terrain_height_scale: float = 80.0
@export var sea_floor_height: float = -30.0
@export var sdf_scale: float = 0.1

var _noise_continental: FastNoiseLite
var _noise_temperature: FastNoiseLite
var _noise_humidity: FastNoiseLite
var _noise_erosion: FastNoiseLite
var _noise_domain_warp: FastNoiseLite

const CH_SDF: int = VoxelBuffer.CHANNEL_SDF
const CH_INDICES: int = VoxelBuffer.CHANNEL_INDICES
const CH_WEIGHTS: int = VoxelBuffer.CHANNEL_WEIGHTS

enum BiomeIndex {
	DEEP_OCEAN = 0,
	OCEAN = 1,
	BEACH = 2,
	PLAINS = 3,
	FOREST = 4,
	SWAMP = 5,
	DESERT = 6,
	SAVANNA = 7,
	JUNGLE = 8,
	TUNDRA = 9,
	MOUNTAIN = 10,
	ICE_SPIRES = 11,
	VOLCANIC = 12,
	MUSHROOM = 13
}

func _init(p_seed: int = 0):
	if p_seed != 0:
		world_seed = p_seed
	_setup_noise()

func _get_used_channels_mask() -> int:
	return (1 << CH_SDF) | (1 << CH_INDICES) | (1 << CH_WEIGHTS)

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	var step := 1 << lod
	var size := out_buffer.get_size()
	var sx := size.x
	var sy := size.y
	var sz := size.z

	var w_packed := _pack_4x4bits(15, 0, 0, 0)

	for z in range(sz):
		var wz := origin_in_voxels.z + z * step
		for x in range(sx):
			var wx := origin_in_voxels.x + x * step

			var biome_info := _get_biome_info(wx, wz)
			var biome_index: int = biome_info[0]
			var height: float = biome_info[1]

			var i_packed := _pack_4x4bits(biome_index, biome_index, biome_index, biome_index)

			for y in range(sy):
				var wy := origin_in_voxels.y + y * step
				var sdf := (float(wy) - height) * sdf_scale
				out_buffer.set_voxel_f(sdf, x, y, z, CH_SDF)
				out_buffer.set_voxel(i_packed, x, y, z, CH_INDICES)
				out_buffer.set_voxel(w_packed, x, y, z, CH_WEIGHTS)

func _setup_noise() -> void:
	_noise_continental = FastNoiseLite.new()
	_noise_continental.seed = world_seed
	_noise_continental.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_continental.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_continental.fractal_octaves = 5
	_noise_continental.fractal_gain = 0.5
	_noise_continental.fractal_lacunarity = 2.0
	_noise_continental.frequency = continental_frequency

	_noise_temperature = FastNoiseLite.new()
	_noise_temperature.seed = world_seed + 1013
	_noise_temperature.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_temperature.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_temperature.fractal_octaves = 4
	_noise_temperature.fractal_gain = 0.5
	_noise_temperature.fractal_lacunarity = 2.0
	_noise_temperature.frequency = temperature_frequency

	_noise_humidity = FastNoiseLite.new()
	_noise_humidity.seed = world_seed + 2027
	_noise_humidity.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_humidity.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_humidity.fractal_octaves = 4
	_noise_humidity.fractal_gain = 0.5
	_noise_humidity.fractal_lacunarity = 2.0
	_noise_humidity.frequency = humidity_frequency

	_noise_erosion = FastNoiseLite.new()
	_noise_erosion.seed = world_seed + 3049
	_noise_erosion.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_erosion.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_erosion.fractal_octaves = 5
	_noise_erosion.fractal_gain = 0.55
	_noise_erosion.fractal_lacunarity = 2.2
	_noise_erosion.frequency = erosion_frequency

	_noise_domain_warp = FastNoiseLite.new()
	_noise_domain_warp.seed = world_seed + 4093
	_noise_domain_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_domain_warp.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_domain_warp.fractal_octaves = 3
	_noise_domain_warp.fractal_gain = 0.5
	_noise_domain_warp.fractal_lacunarity = 2.0
	_noise_domain_warp.frequency = continental_domain_warp_frequency

func _get_biome_info(x: float, z: float) -> Array:
	var continental_pos := _sample_continental_pos(x, z)
	var continental_raw := _noise_continental.get_noise_2d(continental_pos.x, continental_pos.y)

	if continental_raw < sea_level_threshold - deep_ocean_depth:
		var ocean_h := sea_floor_height
		return [BiomeIndex.DEEP_OCEAN, ocean_h]
	if continental_raw < sea_level_threshold:
		var ocean_h2 := lerp(sea_floor_height * 0.5, sea_floor_height, _remap_noise01(continental_raw))
		return [BiomeIndex.OCEAN, ocean_h2]
	if absf(continental_raw - sea_level_threshold) <= beach_band:
		return [BiomeIndex.BEACH, 1.5]

	var temperature01 := _remap_noise01(_noise_temperature.get_noise_2d(x, z))
	var humidity01 := _remap_noise01(_noise_humidity.get_noise_2d(x, z))
	var erosion01 := _remap_noise01(_noise_erosion.get_noise_2d(x, z))
	var inlandness := continental_raw

	var biome := _pick_whittaker_land_biome(temperature01, humidity01)

	if inlandness <= inland_min_continental and humidity01 >= 0.72 and erosion01 <= 0.45:
		biome = BiomeIndex.SWAMP

	if inlandness >= inland_min_continental:
		if temperature01 <= 0.22 and erosion01 >= spires_threshold:
			biome = BiomeIndex.ICE_SPIRES
		elif erosion01 >= mountain_threshold:
			biome = BiomeIndex.MOUNTAIN

	var fault_mask := absf(_noise_erosion.get_noise_2d(x * 0.5, z * 0.5))
	if inlandness >= inland_min_continental and temperature01 >= 0.65 and fault_mask <= 0.12 and erosion01 >= 0.55:
		biome = BiomeIndex.VOLCANIC

	var special := _remap_noise01(_noise_domain_warp.get_noise_2d(x * 0.8 + 771.0, z * 0.8 - 771.0))
	if inlandness >= inland_min_continental and temperature01 >= 0.35 and temperature01 <= 0.6 and humidity01 >= 0.65 and special >= 0.92:
		biome = BiomeIndex.MUSHROOM

	var height := _compute_height(continental_raw, erosion01, temperature01, biome)
	return [biome, height]

func _pick_whittaker_land_biome(temperature01: float, humidity01: float) -> int:
	if temperature01 >= 0.7:
		if humidity01 >= 0.7:
			return BiomeIndex.JUNGLE
		if humidity01 <= 0.25:
			return BiomeIndex.DESERT
		if humidity01 <= 0.55:
			return BiomeIndex.SAVANNA
		return BiomeIndex.PLAINS

	if temperature01 <= 0.28:
		return BiomeIndex.TUNDRA

	if humidity01 >= 0.6:
		return BiomeIndex.FOREST
	return BiomeIndex.PLAINS

func _compute_height(continental_raw: float, erosion01: float, temperature01: float, biome_index: int) -> float:
	var land01 := clamp((continental_raw - sea_level_threshold) / (1.0 - sea_level_threshold), 0.0, 1.0)
	# Smoother height curve - use sqrt for gentler slopes near coast
	var smooth_land := sqrt(land01)
	var base := lerp(3.0, terrain_height_scale * 0.4, smooth_land)
	var hills := pow(erosion01, 2.0) * terrain_height_scale * 0.5 * land01

	var biome_mul := 1.0
	match biome_index:
		BiomeIndex.BEACH:
			biome_mul = 0.35
		BiomeIndex.PLAINS:
			biome_mul = 0.55
		BiomeIndex.FOREST:
			biome_mul = 0.65
		BiomeIndex.SWAMP:
			biome_mul = 0.40
		BiomeIndex.DESERT:
			biome_mul = 0.50
		BiomeIndex.SAVANNA:
			biome_mul = 0.60
		BiomeIndex.JUNGLE:
			biome_mul = 0.70
		BiomeIndex.TUNDRA:
			biome_mul = 0.55
		BiomeIndex.MOUNTAIN:
			biome_mul = 1.25
		BiomeIndex.ICE_SPIRES:
			biome_mul = 1.45
		BiomeIndex.VOLCANIC:
			biome_mul = 1.35
		BiomeIndex.MUSHROOM:
			biome_mul = 0.65
		_:
			biome_mul = 0.6

	var polar := clamp((0.35 - temperature01) / 0.35, 0.0, 1.0)
	var polar_boost := polar * 10.0 * land01

	return base + hills * biome_mul + polar_boost

func _sample_continental_pos(x: float, z: float) -> Vector2:
	if not continental_domain_warp_enabled:
		return Vector2(x, z)
	var dx := _noise_domain_warp.get_noise_2d(x, z) * continental_domain_warp_amplitude
	var dz := _noise_domain_warp.get_noise_2d(x + 1337.0, z + 1337.0) * continental_domain_warp_amplitude
	return Vector2(x + dx, z + dz)

func _remap_noise01(v: float) -> float:
	return clamp((v + 1.0) * 0.5, 0.0, 1.0)

func _pack_4x4bits(a: int, b: int, c: int, d: int) -> int:
	return (a & 0xF) | ((b & 0xF) << 4) | ((c & 0xF) << 8) | ((d & 0xF) << 12)
