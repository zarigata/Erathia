class_name BiomeManager
extends Node

var noise_temp: FastNoiseLite
var noise_humid: FastNoiseLite

# Biome Colors
const COLOR_SNOW = Color(1.0, 1.0, 1.0)
const COLOR_ROCK = Color(0.4, 0.4, 0.4)
const COLOR_GRASS = Color(0.2, 0.6, 0.1)
const COLOR_SAND = Color(0.9, 0.8, 0.5)
const COLOR_WATER = Color(0.1, 0.3, 0.8) # Not used for terrain usually, but for low altitude
const COLOR_DIRT = Color(0.45, 0.3, 0.15)
const COLOR_DRY_GRASS = Color(0.5, 0.6, 0.1)

func _init():
	_setup_noise()

func _setup_noise():
	noise_temp = FastNoiseLite.new()
	noise_temp.seed = 12345
	noise_temp.frequency = 0.005 # Large scale
	
	noise_humid = FastNoiseLite.new()
	noise_humid.seed = 67890
	noise_humid.frequency = 0.005

func get_biome_data(global_x: int, global_z: int, height: float) -> Color:
	# 1. Height based overrides
	if height > 40:
		return COLOR_SNOW # Peaks
	if height > 25:
		return _mix_colors(COLOR_ROCK, COLOR_SNOW, (height - 25) / 15.0)
	if height < 2:
		return COLOR_SAND # Beach

	# 2. Moisture/Temp based
	var temp = noise_temp.get_noise_2d(global_x, global_z)
	var humid = noise_humid.get_noise_2d(global_x, global_z)
	
	if temp > 0.5: # Hot
		if humid < -0.2:
			return COLOR_SAND # Desert
		else:
			return COLOR_DRY_GRASS # Savanna
	elif temp < -0.5: # Cold
		return COLOR_SNOW # Tundra
	else: # Moderate
		if humid > 0.2:
			return COLOR_GRASS # Forest
		else:
			return COLOR_DIRT.lerp(COLOR_GRASS, 0.5) # Plains
			
	return COLOR_GRASS # Default

func _mix_colors(c1: Color, c2: Color, weight: float) -> Color:
	return c1.lerp(c2, clamp(weight, 0.0, 1.0))
