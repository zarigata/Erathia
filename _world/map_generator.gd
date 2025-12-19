@tool
extends Node
class_name MapGenerator
## World Map Generator
## 
## Generates a 2048x2048 PNG world map encoding:
## - R channel: Biome ID (0-12)
## - G channel: Faction ID (0-7, 255=unclaimed)
## - B channel: Elevation (0-255 normalized)
##
## Output: res://_assets/world_map.png
## Debug output: res://_assets/world_map_debug.png
##
## To modify biome distribution, adjust thresholds in _determine_biome()
## To adjust faction territory density, change FACTION_NOISE_FREQUENCY

# =============================================================================
# CONSTANTS
# =============================================================================

const MAP_SIZE: int = 2048
const WORLD_SIZE: float = 16000.0  # 16km x 16km
const PIXEL_SCALE: float = WORLD_SIZE / MAP_SIZE  # ~7.8125m per pixel

const FACTION_NOISE_FREQUENCY: float = 0.0005

# =============================================================================
# BIOME ENUM
# =============================================================================

enum Biome {
	# Primary biomes (0-12)
	PLAINS = 0,
	FOREST = 1,
	DESERT = 2,
	SWAMP = 3,
	TUNDRA = 4,
	JUNGLE = 5,        # Only spawns near water/coast
	SAVANNA = 6,
	MOUNTAIN = 7,
	BEACH = 8,         # Coastal biome with palm trees, coconuts
	DEEP_OCEAN = 9,
	ICE_SPIRES = 10,
	VOLCANIC = 11,
	MUSHROOM = 12,
	# Transition biomes (13-19) - handle slopes between biomes at max 35 degrees
	SLOPE_PLAINS = 13,      # Gentle grassy slopes
	SLOPE_FOREST = 14,      # Forested hillsides
	SLOPE_MOUNTAIN = 15,    # Rocky mountain slopes
	SLOPE_SNOW = 16,        # Snowy slopes (ice/tundra transitions)
	SLOPE_VOLCANIC = 17,    # Ashen slopes near volcanoes
	CLIFF_COASTAL = 18,     # Coastal cliffs (beach to highlands)
	SLOPE_DESERT = 19,      # Sandy dune slopes
}

# =============================================================================
# FACTION ENUM
# =============================================================================

enum Faction {
	CASTLE = 0,
	RAMPART = 1,
	TOWER = 2,
	INFERNO = 3,
	NECROPOLIS = 4,
	DUNGEON = 5,
	STRONGHOLD = 6,
	FORTRESS = 7,
	UNCLAIMED = 255
}

# =============================================================================
# FACTION-TO-BIOMES MAPPING
# =============================================================================

const FACTION_BIOMES: Dictionary = {
	Faction.CASTLE: [Biome.PLAINS, Biome.BEACH],
	Faction.RAMPART: [Biome.FOREST],
	Faction.TOWER: [Biome.MOUNTAIN, Biome.ICE_SPIRES],
	Faction.INFERNO: [Biome.VOLCANIC, Biome.DESERT],
	Faction.NECROPOLIS: [Biome.SWAMP, Biome.TUNDRA],
	Faction.DUNGEON: [Biome.MOUNTAIN, Biome.FOREST],
	Faction.STRONGHOLD: [Biome.SAVANNA, Biome.DESERT],
	Faction.FORTRESS: [Biome.SWAMP, Biome.JUNGLE]
}

# =============================================================================
# BIOME DEBUG COLORS
# =============================================================================

const BIOME_COLORS: Dictionary = {
	# Primary biomes
	Biome.PLAINS: Color(0.6, 0.8, 0.4),       # Light green
	Biome.FOREST: Color(0.2, 0.5, 0.2),       # Dark green
	Biome.DESERT: Color(0.9, 0.8, 0.5),       # Sandy yellow
	Biome.SWAMP: Color(0.4, 0.5, 0.3),        # Murky green
	Biome.TUNDRA: Color(0.8, 0.85, 0.9),      # Pale blue-white
	Biome.JUNGLE: Color(0.1, 0.4, 0.15),      # Deep green
	Biome.SAVANNA: Color(0.8, 0.7, 0.4),      # Tan/brown
	Biome.MOUNTAIN: Color(0.5, 0.5, 0.5),     # Gray
	Biome.BEACH: Color(0.95, 0.9, 0.7),       # Sand color
	Biome.DEEP_OCEAN: Color(0.1, 0.2, 0.5),   # Deep blue
	Biome.ICE_SPIRES: Color(0.9, 0.95, 1.0),  # Ice white-blue
	Biome.VOLCANIC: Color(0.3, 0.1, 0.1),     # Dark red
	Biome.MUSHROOM: Color(0.6, 0.3, 0.6),     # Purple
	# Transition biomes
	Biome.SLOPE_PLAINS: Color(0.5, 0.7, 0.35),   # Darker green slopes
	Biome.SLOPE_FOREST: Color(0.25, 0.45, 0.2),  # Forest hill green
	Biome.SLOPE_MOUNTAIN: Color(0.45, 0.45, 0.45), # Mountain slope gray
	Biome.SLOPE_SNOW: Color(0.85, 0.9, 0.95),    # Snowy slope
	Biome.SLOPE_VOLCANIC: Color(0.25, 0.15, 0.1), # Ashen slope
	Biome.CLIFF_COASTAL: Color(0.7, 0.65, 0.5),  # Coastal cliff tan
	Biome.SLOPE_DESERT: Color(0.85, 0.75, 0.45), # Desert dune slope
}

const FACTION_BORDER_COLORS: Dictionary = {
	Faction.CASTLE: Color(1.0, 1.0, 1.0),     # White
	Faction.RAMPART: Color(0.0, 1.0, 0.0),    # Green
	Faction.TOWER: Color(0.0, 0.5, 1.0),      # Blue
	Faction.INFERNO: Color(1.0, 0.0, 0.0),    # Red
	Faction.NECROPOLIS: Color(0.5, 0.0, 0.5), # Purple
	Faction.DUNGEON: Color(0.3, 0.3, 0.3),    # Dark gray
	Faction.STRONGHOLD: Color(1.0, 0.5, 0.0), # Orange
	Faction.FORTRESS: Color(0.0, 0.5, 0.0),   # Dark green
	Faction.UNCLAIMED: Color(0.2, 0.2, 0.2)   # Very dark gray
}

# =============================================================================
# NOISE LAYERS
# =============================================================================

var _continentalness_noise: FastNoiseLite
var _altitude_noise: FastNoiseLite
var _temperature_noise: FastNoiseLite
var _humidity_noise: FastNoiseLite
var _faction_noise: FastNoiseLite

# =============================================================================
# EXPORT VARIABLES
# =============================================================================

@export var world_seed: int = 12345
@export var auto_generate_on_ready: bool = true
@export var generate_map: bool = false:
	set(value):
		if value:
			generate_world_map()
		generate_map = false

@export var generate_debug: bool = false:
	set(value):
		if value:
			generate_debug_map()
		generate_debug = false

# =============================================================================
# INITIALIZATION
# =============================================================================

signal map_generated(seed_value: int)
signal seed_randomized(new_seed: int)

func _ready() -> void:
	# Get seed from WorldSeedManager if available (use get_node to avoid @tool parsing issues)
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if seed_manager:
		world_seed = seed_manager.get_world_seed()
		seed_manager.seed_changed.connect(_on_world_seed_changed)
	
	_setup_noise_layers()
	
	# Auto-generate world map if missing
	if auto_generate_on_ready:
		call_deferred("_check_and_generate_map")


func _check_and_generate_map() -> void:
	var map_path := "res://_assets/world_map.png"
	if not FileAccess.file_exists(map_path):
		print("[MapGenerator] World map not found, generating...")
		generate_world_map()
	else:
		print("[MapGenerator] World map exists at: %s" % map_path)
		map_generated.emit(world_seed)


func _on_world_seed_changed(new_seed: int) -> void:
	world_seed = new_seed
	_setup_noise_layers()
	print("[MapGenerator] Seed changed to: %d, regenerating map..." % new_seed)
	generate_world_map()
	seed_randomized.emit(new_seed)


func _setup_noise_layers() -> void:
	# Continentalness Noise - Voronoi-like for continental features
	_continentalness_noise = FastNoiseLite.new()
	_continentalness_noise.seed = world_seed
	_continentalness_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	_continentalness_noise.frequency = 0.0008
	_continentalness_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	_continentalness_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	
	# Altitude/Erosion Noise - Medium-scale mountains/valleys
	_altitude_noise = FastNoiseLite.new()
	_altitude_noise.seed = world_seed + 1
	_altitude_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_altitude_noise.frequency = 0.002
	_altitude_noise.fractal_octaves = 4
	
	# Temperature Noise - Gradual temperature zones
	_temperature_noise = FastNoiseLite.new()
	_temperature_noise.seed = world_seed + 2
	_temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_temperature_noise.frequency = 0.001
	_temperature_noise.fractal_octaves = 3
	
	# Humidity Noise - Rainfall patterns
	_humidity_noise = FastNoiseLite.new()
	_humidity_noise.seed = world_seed + 3
	_humidity_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_humidity_noise.frequency = 0.0015
	_humidity_noise.fractal_octaves = 3
	
	# Faction Territory Noise - Large Voronoi cells for faction placement
	_faction_noise = FastNoiseLite.new()
	_faction_noise.seed = world_seed + 4
	_faction_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	_faction_noise.frequency = FACTION_NOISE_FREQUENCY
	_faction_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	_faction_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE


# =============================================================================
# BIOME DETERMINATION
# =============================================================================

func _determine_biome(continentalness: float, altitude: float, temperature: float, humidity: float) -> int:
	# Normalize all noise values from [-1, 1] to [0, 1]
	var c := (continentalness + 1.0) * 0.5
	var a := (altitude + 1.0) * 0.5
	var t := (temperature + 1.0) * 0.5
	var h := (humidity + 1.0) * 0.5
	
	# Deep Ocean
	if c < 0.35:
		return Biome.DEEP_OCEAN
	
	# Beach
	if c < 0.45:
		return Biome.BEACH
	
	# Ice Spires - High altitude, very cold
	if a > 0.7 and t < 0.3:
		return Biome.ICE_SPIRES
	
	# Mountain - High altitude
	if a > 0.7:
		return Biome.MOUNTAIN
	
	# Tundra - Medium-high altitude, cold
	if a > 0.6 and t < 0.25:
		return Biome.TUNDRA
	
	# Volcanic - Low altitude, very hot (rare)
	if a < 0.3 and t > 0.8:
		return Biome.VOLCANIC
	
	# Desert - Hot and dry
	if t > 0.75 and h < 0.3:
		return Biome.DESERT
	
	# Jungle - Hot and wet
	if t > 0.7 and h > 0.6:
		return Biome.JUNGLE
	
	# Savanna - Warm and semi-dry
	if t > 0.6 and h < 0.4:
		return Biome.SAVANNA
	
	# Swamp - Very humid
	if h > 0.65:
		return Biome.SWAMP
	
	# Mushroom - Medium-high altitude and very humid (rare)
	if a > 0.5 and h > 0.7:
		return Biome.MUSHROOM
	
	# Forest vs Plains based on altitude
	if a > 0.45:
		return Biome.FOREST
	
	return Biome.PLAINS


# =============================================================================
# FACTION DETERMINATION
# =============================================================================

func _determine_faction(world_x: float, world_y: float, biome_id: int) -> int:
	# Get faction cell value from noise
	var faction_value := _faction_noise.get_noise_2d(world_x, world_y)
	# Normalize from [-1, 1] to [0, 1]
	var normalized := (faction_value + 1.0) * 0.5
	# Map to faction ID (0-7)
	var faction_id := int(normalized * 8.0) % 8
	
	# Validate: Check if biome is valid for this faction
	if FACTION_BIOMES.has(faction_id):
		var allowed_biomes: Array = FACTION_BIOMES[faction_id]
		if biome_id in allowed_biomes:
			return faction_id
	
	# Invalid biome for faction - mark as unclaimed
	return Faction.UNCLAIMED


# =============================================================================
# ELEVATION CALCULATION
# =============================================================================

func _calculate_elevation(continentalness: float, altitude: float) -> int:
	# Normalize values
	var c := (continentalness + 1.0) * 0.5
	var a := (altitude + 1.0) * 0.5
	
	# Combine altitude and continentalness
	var elevation := a * 0.7 + c * 0.3
	
	# Post-processing: boost mountain peaks
	if elevation > 0.7:
		elevation = elevation * 1.2
	
	# Flatten ocean floors
	if c < 0.35:
		elevation = elevation * 0.3
	
	# Clamp and convert to 0-255 range
	elevation = clampf(elevation, 0.0, 1.0)
	return int(elevation * 255.0)


# =============================================================================
# MAP GENERATION
# =============================================================================

func generate_world_map() -> void:
	print("[MapGenerator] Starting world map generation...")
	print("[MapGenerator] Map size: %d x %d pixels" % [MAP_SIZE, MAP_SIZE])
	print("[MapGenerator] World size: %.0f x %.0f meters" % [WORLD_SIZE, WORLD_SIZE])
	print("[MapGenerator] Seed: %d" % world_seed)
	
	_setup_noise_layers()
	
	var image := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	
	# Statistics tracking
	var biome_counts: Dictionary = {}
	var faction_counts: Dictionary = {}
	for b in Biome.values():
		biome_counts[b] = 0
	for f in Faction.values():
		faction_counts[f] = 0
	
	var last_progress := -1
	
	for y in range(MAP_SIZE):
		# Progress reporting every 10%
		var progress := int((float(y) / MAP_SIZE) * 100.0)
		if progress % 10 == 0 and progress != last_progress:
			print("[MapGenerator] Progress: %d%%" % progress)
			last_progress = progress
		
		for x in range(MAP_SIZE):
			# Convert pixel to world coordinates
			var world_x := float(x) * PIXEL_SCALE
			var world_y := float(y) * PIXEL_SCALE
			
			# Sample noise layers
			var continentalness := _continentalness_noise.get_noise_2d(world_x, world_y)
			var altitude := _altitude_noise.get_noise_2d(world_x, world_y)
			var temperature := _temperature_noise.get_noise_2d(world_x, world_y)
			var humidity := _humidity_noise.get_noise_2d(world_x, world_y)
			
			# Determine biome
			var biome_id := _determine_biome(continentalness, altitude, temperature, humidity)
			biome_counts[biome_id] += 1
			
			# Determine faction (with validation)
			var faction_id := _determine_faction(world_x, world_y, biome_id)
			faction_counts[faction_id] += 1
			
			# Calculate elevation
			var elevation := _calculate_elevation(continentalness, altitude)
			
			# Encode RGB: Biome (R), Faction (G), Elevation (B)
			var color := Color8(biome_id, faction_id, elevation)
			image.set_pixel(x, y, color)
	
	# Save to user:// for runtime accessibility (res:// is read-only at runtime)
	var save_path := "user://world_map.png"
	
	# Also save to res:// for editor use if in editor
	if Engine.is_editor_hint():
		var dir := DirAccess.open("res://_assets")
		if dir == null:
			DirAccess.make_dir_recursive_absolute("res://_assets")
		image.save_png("res://_assets/world_map.png")
	var error := image.save_png(save_path)
	if error != OK:
		push_error("[MapGenerator] Failed to save world map: %s" % error_string(error))
		return
	
	print("[MapGenerator] Progress: 100%%")
	print("[MapGenerator] World map saved to: %s" % save_path)
	
	# Emit signal that map is ready
	map_generated.emit(world_seed)
	
	# Print statistics
	print("\n[MapGenerator] === BIOME DISTRIBUTION ===")
	var total_pixels := MAP_SIZE * MAP_SIZE
	for biome_id in biome_counts.keys():
		var count: int = biome_counts[biome_id]
		var percentage := (float(count) / total_pixels) * 100.0
		var biome_name: String = Biome.keys()[biome_id]
		print("  %s: %d pixels (%.2f%%)" % [biome_name, count, percentage])
	
	print("\n[MapGenerator] === FACTION TERRITORIES ===")
	for faction_id in faction_counts.keys():
		var count: int = faction_counts[faction_id]
		if count > 0:
			var percentage := (float(count) / total_pixels) * 100.0
			var faction_name: String
			if faction_id == Faction.UNCLAIMED:
				faction_name = "UNCLAIMED"
			else:
				faction_name = Faction.keys()[faction_id]
			print("  %s: %d pixels (%.2f%%)" % [faction_name, count, percentage])
	
	print("\n[MapGenerator] Generation complete!")


# =============================================================================
# DEBUG MAP GENERATION
# =============================================================================

func generate_debug_map() -> void:
	print("[MapGenerator] Generating debug visualization map...")
	
	# First check if world map exists (check user:// first, then res://)
	var world_map_path := "user://world_map.png"
	if not FileAccess.file_exists(world_map_path):
		world_map_path = "res://_assets/world_map.png"
	if not FileAccess.file_exists(world_map_path):
		print("[MapGenerator] World map not found. Generating it first...")
		generate_world_map()
	
	# Load the world map
	var world_map := Image.load_from_file(world_map_path)
	if world_map == null:
		push_error("[MapGenerator] Failed to load world map for debug visualization")
		return
	
	var debug_image := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	
	for y in range(MAP_SIZE):
		for x in range(MAP_SIZE):
			var pixel := world_map.get_pixel(x, y)
			var biome_id := int(pixel.r8)
			var faction_id := int(pixel.g8)
			
			# Get biome color
			var base_color: Color = BIOME_COLORS.get(biome_id, Color(1, 0, 1))  # Magenta for unknown
			
			# Blend with faction border color if claimed
			if faction_id != Faction.UNCLAIMED:
				# Check if this pixel is on a faction border
				var is_border := _is_faction_border(world_map, x, y, faction_id)
				if is_border:
					var faction_color: Color = FACTION_BORDER_COLORS.get(faction_id, Color.WHITE)
					base_color = faction_color
				else:
					# Slight tint based on faction
					var faction_color: Color = FACTION_BORDER_COLORS.get(faction_id, Color.WHITE)
					base_color = base_color.lerp(faction_color, 0.15)
			
			debug_image.set_pixel(x, y, base_color)
	
	# Save debug image
	var save_path := "res://_assets/world_map_debug.png"
	var error := debug_image.save_png(save_path)
	if error != OK:
		push_error("[MapGenerator] Failed to save debug map: %s" % error_string(error))
		return
	
	print("[MapGenerator] Debug map saved to: %s" % save_path)


func _is_faction_border(image: Image, x: int, y: int, faction_id: int) -> bool:
	# Check 4-connected neighbors for different faction
	var offsets := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	
	for offset in offsets:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		
		if nx < 0 or nx >= MAP_SIZE or ny < 0 or ny >= MAP_SIZE:
			continue
		
		var neighbor_pixel := image.get_pixel(nx, ny)
		var neighbor_faction := int(neighbor_pixel.g8)
		
		if neighbor_faction != faction_id:
			return true
	
	return false
