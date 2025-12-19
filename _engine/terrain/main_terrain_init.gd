extends Node3D

## Main scene initialization script
## Handles terrain system setup, map generation coordination, and TerrainEditSystem initialization

@export var terrain_path: NodePath = "VoxelLodTerrain"
@export var map_generator_path: NodePath = "MapGenerator"

var _terrain: VoxelLodTerrain
var _map_generator: MapGenerator
var _biome_generator: BiomeAwareGenerator


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as VoxelLodTerrain
	_map_generator = get_node_or_null(map_generator_path) as MapGenerator
	
	# Get BiomeAwareGenerator from terrain
	if _terrain and _terrain.generator:
		_biome_generator = _terrain.generator as BiomeAwareGenerator
	
	# Connect to MapGenerator signals
	if _map_generator:
		_map_generator.map_generated.connect(_on_map_generated)
		_map_generator.seed_randomized.connect(_on_seed_randomized)
		print("[MainTerrainInit] Connected to MapGenerator signals")
	else:
		print("[MainTerrainInit] MapGenerator not found, biomes may not load correctly")
	
	# Connect to WorldSeedManager for seed changes
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if seed_manager:
		seed_manager.seed_changed.connect(_on_world_seed_changed)
	
	if _terrain:
		# Initialize TerrainEditSystem with the terrain reference
		if TerrainEditSystem:
			TerrainEditSystem.set_terrain(_terrain)
			print("[MainTerrainInit] TerrainEditSystem initialized with terrain")
		else:
			push_warning("[MainTerrainInit] TerrainEditSystem autoload not found")
	else:
		push_warning("[MainTerrainInit] VoxelLodTerrain not found at path: %s" % terrain_path)


func _on_map_generated(seed_value: int) -> void:
	print("[MainTerrainInit] Map generated with seed: %d" % seed_value)
	
	# Reload biome generator to pick up new map
	if _biome_generator:
		_biome_generator.reload_world_map_and_notify()
		print("[MainTerrainInit] BiomeGenerator reloaded with new map")
	
	# Force terrain to regenerate by reassigning the generator
	# This triggers chunk regeneration with the new biome map data
	if _terrain and _biome_generator:
		_terrain.generator = _biome_generator
		print("[MainTerrainInit] Terrain generator reassigned to trigger regeneration")


func _on_seed_randomized(new_seed: int) -> void:
	print("[MainTerrainInit] Seed randomized to: %d" % new_seed)
	
	# Update biome generator seed
	if _biome_generator:
		_biome_generator.update_seed(new_seed)
	
	# Force terrain to regenerate by reassigning the generator
	if _terrain and _biome_generator:
		_terrain.generator = _biome_generator
		print("[MainTerrainInit] Terrain generator reassigned to trigger regeneration")


func _on_world_seed_changed(new_seed: int) -> void:
	print("[MainTerrainInit] WorldSeedManager seed changed to: %d" % new_seed)
	# MapGenerator will handle regeneration via its own connection
