class_name BiomeManager
extends Node

@export var world_seed: int = 0

@export var continental_frequency: float = 0.0003
@export var temperature_frequency: float = 0.0004
@export var humidity_frequency: float = 0.0005
@export var erosion_frequency: float = 0.002

@export var sea_level_threshold: float = 0.0
@export var beach_band: float = 0.08
@export var mountain_threshold: float = 0.6
@export var inland_min_continental: float = 0.1

@export var continental_domain_warp_enabled: bool = true
@export var continental_domain_warp_amplitude: float = 600.0
@export var continental_domain_warp_frequency: float = 0.0002

@export var terrain_height_scale: float = 80.0
@export var sea_floor_height: float = -20.0

var noise_continental: FastNoiseLite
var noise_temperature: FastNoiseLite
var noise_humidity: FastNoiseLite
var noise_erosion: FastNoiseLite
var noise_domain_warp: FastNoiseLite

var _biome_ocean: BiomeDefinition
var _biome_beach: BiomeDefinition
var _biome_plains: BiomeDefinition
var _biome_forest: BiomeDefinition
var _biome_desert: BiomeDefinition
var _biome_jungle: BiomeDefinition
var _biome_tundra: BiomeDefinition
var _biome_mountain: BiomeDefinition

func _init(p_seed: int = 0):
	if p_seed != 0:
		world_seed = p_seed
	_setup_default_biomes()
	_setup_noise()

func set_world_seed(seed_value: int) -> void:
	world_seed = seed_value
	_setup_noise()

func get_biome_data(x: float, z: float) -> BiomeDefinition:
	var continental_pos := _sample_continental_pos(x, z)
	var continental := noise_continental.get_noise_2d(continental_pos.x, continental_pos.y)

	if continental < sea_level_threshold:
		return _biome_ocean
	if absf(continental - sea_level_threshold) <= beach_band:
		return _biome_beach

	var temperature := _remap_noise01(noise_temperature.get_noise_2d(x, z))
	var humidity := _remap_noise01(noise_humidity.get_noise_2d(x, z))
	var biome := _pick_whittaker_biome(temperature, humidity)

	var inlandness := continental
	if inlandness >= inland_min_continental:
		var erosion := _remap_noise01(noise_erosion.get_noise_2d(x, z))
		if erosion > mountain_threshold:
			biome = _biome_mountain

	return biome

func get_terrain_height(x: float, z: float) -> float:
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
	
	# Erosion creates hills - use smooth pow curve, not hard threshold
	var erosion: float = _remap_noise01(noise_erosion.get_noise_2d(x, z))
	# Smooth erosion curve - gradual hills that become mountains
	var erosion_curve: float = pow(erosion, 2.0)
	var hills: float = erosion_curve * terrain_height_scale * 0.6 * land_factor
	
	# Add local detail noise for micro-variation (smaller scale)
	var detail: float = noise_temperature.get_noise_2d(x * 3.0, z * 3.0) * 2.0 * land_factor
	
	# Total height - no biome multiplier to avoid sharp transitions
	return base_height + hills + detail

func get_continental_value(x: float, z: float) -> float:
	var continental_pos := _sample_continental_pos(x, z)
	return noise_continental.get_noise_2d(continental_pos.x, continental_pos.y)

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

func _setup_default_biomes() -> void:
	_biome_ocean = BiomeDefinition.new()
	_biome_ocean.biome_name = &"OCEAN"
	_biome_ocean.base_color = Color(0.10, 0.30, 0.80)
	_biome_ocean.surface_material_id = 0
	_biome_ocean.height_modifier = 0.2

	_biome_beach = BiomeDefinition.new()
	_biome_beach.biome_name = &"BEACH"
	_biome_beach.base_color = Color(0.90, 0.80, 0.50)
	_biome_beach.surface_material_id = 0
	_biome_beach.height_modifier = 0.4

	_biome_plains = BiomeDefinition.new()
	_biome_plains.biome_name = &"PLAINS"
	_biome_plains.base_color = Color(0.45, 0.70, 0.20)
	_biome_plains.surface_material_id = 0
	_biome_plains.height_modifier = 1.0

	_biome_forest = BiomeDefinition.new()
	_biome_forest.biome_name = &"FOREST"
	_biome_forest.base_color = Color(0.20, 0.60, 0.10)
	_biome_forest.surface_material_id = 0
	_biome_forest.height_modifier = 1.0

	_biome_desert = BiomeDefinition.new()
	_biome_desert.biome_name = &"DESERT"
	_biome_desert.base_color = Color(0.93, 0.86, 0.55)
	_biome_desert.surface_material_id = 0
	_biome_desert.height_modifier = 0.9

	_biome_jungle = BiomeDefinition.new()
	_biome_jungle.biome_name = &"JUNGLE"
	_biome_jungle.base_color = Color(0.05, 0.50, 0.15)
	_biome_jungle.surface_material_id = 0
	_biome_jungle.height_modifier = 1.0

	_biome_tundra = BiomeDefinition.new()
	_biome_tundra.biome_name = &"TUNDRA"
	_biome_tundra.base_color = Color(0.85, 0.90, 0.95)
	_biome_tundra.surface_material_id = 0
	_biome_tundra.height_modifier = 0.95

	_biome_mountain = BiomeDefinition.new()
	_biome_mountain.biome_name = &"MOUNTAIN"
	_biome_mountain.base_color = Color(0.40, 0.40, 0.40)
	_biome_mountain.surface_material_id = 0
	_biome_mountain.height_modifier = 1.0

func _pick_whittaker_biome(temperature01: float, humidity01: float) -> BiomeDefinition:
	if temperature01 >= 0.66:
		if humidity01 >= 0.66:
			return _biome_jungle
		if humidity01 <= 0.33:
			return _biome_desert
		return _biome_plains

	if temperature01 <= 0.33:
		return _biome_tundra

	if humidity01 >= 0.55:
		return _biome_forest
	return _biome_plains

func _sample_continental_pos(x: float, z: float) -> Vector2:
	if not continental_domain_warp_enabled:
		return Vector2(x, z)

	var dx := noise_domain_warp.get_noise_2d(x, z) * continental_domain_warp_amplitude
	var dz := noise_domain_warp.get_noise_2d(x + 1337.0, z + 1337.0) * continental_domain_warp_amplitude
	return Vector2(x + dx, z + dz)

func _remap_noise01(v: float) -> float:
	return clamp((v + 1.0) * 0.5, 0.0, 1.0)
