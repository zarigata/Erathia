extends Node
## VegetationManager Singleton
##
## Coordinates all vegetation instancing, mesh caching, and biome-specific rules.
## Registered as autoload "VegetationManager" in project.godot

const ProceduralTreeGeneratorScript = preload("res://_world/vegetation/procedural_tree_generator.gd")

# =============================================================================
# SIGNALS
# =============================================================================

signal vegetation_populated(chunk_origin: Vector3i, instance_count: int)
signal vegetation_cleared(center: Vector3, radius: float, count: int)

# =============================================================================
# ENUMS
# =============================================================================

enum VegetationType {
	TREE,
	BUSH,
	ROCK_SMALL,
	ROCK_MEDIUM,
	GRASS_TUFT,
	# Ore boulders - surface mineable rocks
	ORE_IRON,
	ORE_COPPER,
	ORE_STONE
}

# =============================================================================
# CONSTANTS
# =============================================================================

const MAX_MESH_CACHE_SIZE: int = 200
const MAX_SEED_VARIATIONS: int = 10
const EMPTY_RULES: Dictionary = {"types": []}

# Biome vegetation rules
# density: base spawn density (0.0-1.0), multiplied by biome's vegetation_density
# slope_max: maximum slope in degrees for placement
# height_range: min/max world Y for placement
const BIOME_VEGETATION_RULES: Dictionary = {
	MapGenerator.Biome.PLAINS: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.02, "variants": ["oak"]},
			{"type": VegetationType.BUSH, "density": 0.1, "variants": ["green_bush", "flowering_bush"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.05, "variants": ["stone"]},
			{"type": VegetationType.GRASS_TUFT, "density": 0.15, "variants": ["grass"]},
			{"type": VegetationType.ORE_STONE, "density": 0.008, "variants": ["boulder"]},
			{"type": VegetationType.ORE_COPPER, "density": 0.003, "variants": ["copper_boulder"]}
		],
		"slope_max": 35.0,
		"height_range": {"min": -10, "max": 100}
	},
	MapGenerator.Biome.FOREST: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.15, "variants": ["oak", "birch", "pine"]},
			{"type": VegetationType.BUSH, "density": 0.2, "variants": ["green_bush", "fern", "undergrowth"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.03, "variants": ["mossy_stone"]},
			{"type": VegetationType.GRASS_TUFT, "density": 0.12, "variants": ["grass"]}
		],
		"slope_max": 50.0,
		"height_range": {"min": -20, "max": 200}
	},
	MapGenerator.Biome.DESERT: {
		"types": [
			{"type": VegetationType.BUSH, "density": 0.02, "variants": ["desert_shrub", "tumbleweed"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.08, "variants": ["sandstone"]},
			{"type": VegetationType.ROCK_MEDIUM, "density": 0.02, "variants": ["sandstone"]}
		],
		"slope_max": 45.0,
		"height_range": {"min": -30, "max": 150}
	},
	MapGenerator.Biome.SWAMP: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.08, "variants": ["willow", "dead"]},
			{"type": VegetationType.BUSH, "density": 0.15, "variants": ["swamp_bush", "moss_clump"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.04, "variants": ["mossy_stone"]},
			{"type": VegetationType.GRASS_TUFT, "density": 0.1, "variants": ["grass"]}
		],
		"slope_max": 25.0,
		"height_range": {"min": -40, "max": 50}
	},
	MapGenerator.Biome.TUNDRA: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.06, "variants": ["dead_pine"]},
			{"type": VegetationType.BUSH, "density": 0.08, "variants": ["frost_bush"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.1, "variants": ["frost_stone"]},
			{"type": VegetationType.ROCK_MEDIUM, "density": 0.04, "variants": ["frost_stone"]}
		],
		"slope_max": 45.0,
		"height_range": {"min": -50, "max": 300}
	},
	MapGenerator.Biome.JUNGLE: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.2, "variants": ["palm", "tropical"]},
			{"type": VegetationType.BUSH, "density": 0.3, "variants": ["tropical_bush", "fern", "giant_fern"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.02, "variants": ["mossy_stone"]},
			{"type": VegetationType.GRASS_TUFT, "density": 0.15, "variants": ["grass"]}
		],
		"slope_max": 45.0,
		"height_range": {"min": -10, "max": 120}
	},
	MapGenerator.Biome.SAVANNA: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.04, "variants": ["acacia"]},
			{"type": VegetationType.BUSH, "density": 0.08, "variants": ["dry_bush", "grass_clump"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.04, "variants": ["stone"]},
			{"type": VegetationType.GRASS_TUFT, "density": 0.15, "variants": ["grass"]}
		],
		"slope_max": 30.0,
		"height_range": {"min": 0, "max": 80}
	},
	MapGenerator.Biome.MOUNTAIN: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.06, "variants": ["pine"]},
			{"type": VegetationType.BUSH, "density": 0.08, "variants": ["alpine_bush", "lichen"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.12, "variants": ["granite"]},
			{"type": VegetationType.ROCK_MEDIUM, "density": 0.06, "variants": ["granite"]},
			{"type": VegetationType.ORE_STONE, "density": 0.015, "variants": ["boulder"]},
			{"type": VegetationType.ORE_IRON, "density": 0.008, "variants": ["iron_boulder"]},
			{"type": VegetationType.ORE_COPPER, "density": 0.005, "variants": ["copper_boulder"]}
		],
		"slope_max": 65.0,
		"height_range": {"min": -50, "max": 500}
	},
	MapGenerator.Biome.BEACH: {
		# Enhanced beach with palm trees and coconuts
		"types": [
			{"type": VegetationType.TREE, "density": 0.12, "variants": ["palm"]},  # More palm trees
			{"type": VegetationType.BUSH, "density": 0.08, "variants": ["beach_grass", "dune_bush", "coconut_pile"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.04, "variants": ["shell", "driftwood"]},
			{"type": VegetationType.GRASS_TUFT, "density": 0.1, "variants": ["beach_grass"]}
		],
		"slope_max": 25.0,
		"height_range": {"min": -5, "max": 25}
	},
	MapGenerator.Biome.DEEP_OCEAN: {
		"types": [],  # No vegetation underwater
		"slope_max": 90.0,
		"height_range": {"min": -250, "max": -40}
	},
	MapGenerator.Biome.ICE_SPIRES: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.06, "variants": ["pine"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.08, "variants": ["ice"]},
			{"type": VegetationType.ROCK_MEDIUM, "density": 0.04, "variants": ["ice"]}
		],
		"slope_max": 35.0,  # Max 35 degrees
		"height_range": {"min": -50, "max": 500}
	},
	MapGenerator.Biome.VOLCANIC: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.02, "variants": ["charred"]},
			{"type": VegetationType.BUSH, "density": 0.03, "variants": ["ash_bush"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.1, "variants": ["obsidian"]},
			{"type": VegetationType.ROCK_MEDIUM, "density": 0.05, "variants": ["obsidian"]}
		],
		"slope_max": 35.0,  # Max 35 degrees
		"height_range": {"min": -60, "max": 300}
	},
	MapGenerator.Biome.MUSHROOM: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.12, "variants": ["giant_mushroom"]},
			{"type": VegetationType.BUSH, "density": 0.25, "variants": ["small_mushroom", "mushroom_cluster"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.03, "variants": ["fungal_stone"]},
			{"type": VegetationType.GRASS_TUFT, "density": 0.15, "variants": ["spore_grass"]}
		],
		"slope_max": 35.0,
		"height_range": {"min": -50, "max": 100}
	},
	# =========================================================================
	# TRANSITION BIOMES - Sloped terrain between biomes (max 35 degrees)
	# =========================================================================
	MapGenerator.Biome.SLOPE_PLAINS: {
		"types": [
			{"type": VegetationType.GRASS_TUFT, "density": 0.15, "variants": ["grass"]},
			{"type": VegetationType.BUSH, "density": 0.06, "variants": ["shrub"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.04, "variants": ["stone"]}
		],
		"slope_max": 35.0,
		"height_range": {"min": -50, "max": 200}
	},
	MapGenerator.Biome.SLOPE_FOREST: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.08, "variants": ["pine", "oak"]},
			{"type": VegetationType.BUSH, "density": 0.1, "variants": ["shrub", "fern"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.05, "variants": ["mossy_stone"]}
		],
		"slope_max": 35.0,
		"height_range": {"min": -50, "max": 200}
	},
	MapGenerator.Biome.SLOPE_MOUNTAIN: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.03, "variants": ["pine"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.12, "variants": ["granite"]},
			{"type": VegetationType.ROCK_MEDIUM, "density": 0.06, "variants": ["granite"]}
		],
		"slope_max": 35.0,
		"height_range": {"min": -50, "max": 300}
	},
	MapGenerator.Biome.SLOPE_SNOW: {
		"types": [
			{"type": VegetationType.TREE, "density": 0.04, "variants": ["pine"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.08, "variants": ["frost_stone"]},
			{"type": VegetationType.ROCK_MEDIUM, "density": 0.04, "variants": ["ice"]}
		],
		"slope_max": 35.0,
		"height_range": {"min": -50, "max": 400}
	},
	MapGenerator.Biome.SLOPE_VOLCANIC: {
		"types": [
			{"type": VegetationType.ROCK_SMALL, "density": 0.1, "variants": ["obsidian"]},
			{"type": VegetationType.ROCK_MEDIUM, "density": 0.05, "variants": ["obsidian"]}
		],
		"slope_max": 35.0,
		"height_range": {"min": -50, "max": 250}
	},
	MapGenerator.Biome.CLIFF_COASTAL: {
		"types": [
			{"type": VegetationType.BUSH, "density": 0.06, "variants": ["beach_grass"]},
			{"type": VegetationType.ROCK_SMALL, "density": 0.08, "variants": ["stone"]}
		],
		"slope_max": 35.0,
		"height_range": {"min": -20, "max": 100}
	},
	MapGenerator.Biome.SLOPE_DESERT: {
		"types": [
			{"type": VegetationType.ROCK_SMALL, "density": 0.06, "variants": ["sandstone"]},
			{"type": VegetationType.BUSH, "density": 0.02, "variants": ["dead_bush"]}
		],
		"slope_max": 35.0,
		"height_range": {"min": -50, "max": 150}
	},
}

# =============================================================================
# STATE
# =============================================================================

var _mesh_cache: Dictionary = {}  # "type_biome_variant_seed" -> Mesh
var _mesh_cache_order: Array[String] = []  # LRU order tracking

var _populated_chunks: Dictionary = {}  # Vector3i -> Array of instance data
var _instance_spatial_hash: Dictionary = {}  # Grid cell -> Array of positions

var debug_show_zones: bool = false
var debug_enabled: bool = true
var _biome_rule_queries: Dictionary = {}

# Procedural generators
var _tree_generator: RefCounted

# Statistics
var _stats: Dictionary = {
	"total_instances": 0,
	"tree_count": 0,
	"bush_count": 0,
	"rock_count": 0,
	"grass_count": 0,
	"cache_size": 0,
	"cache_hits": 0,
	"cache_misses": 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	_tree_generator = ProceduralTreeGeneratorScript.new()
	print("[VegetationManager] Initialized with procedural tree generator")


# =============================================================================
# PUBLIC API - MESH GENERATION
# =============================================================================

## Get or generate a mesh for a vegetation type
func get_mesh_for_type(type: VegetationType, biome_id: int, variant: String, seed_value: int, lod_level: int = 0) -> Mesh:
	# Limit seed variations to reduce cache size
	var limited_seed := seed_value % MAX_SEED_VARIATIONS
	var cache_key := "%d_%d_%s_%d_%d" % [type, biome_id, variant, limited_seed, lod_level]
	
	if _mesh_cache.has(cache_key):
		_stats["cache_hits"] += 1
		# Move to end of LRU
		_mesh_cache_order.erase(cache_key)
		_mesh_cache_order.append(cache_key)
		_log_debug("cache-hit", {"key": cache_key, "type": type, "biome": biome_id, "variant": variant, "lod": lod_level})
		return _mesh_cache[cache_key]
	
	_stats["cache_misses"] += 1
	_log_debug("cache-miss", {"key": cache_key, "type": type, "biome": biome_id, "variant": variant, "lod": lod_level})
	
	# Generate mesh
	var mesh: Mesh = null
	match type:
		VegetationType.TREE:
			# Use new procedural tree generator
			if _tree_generator:
				var tree_style: int = _tree_generator.get_tree_style_for_biome(biome_id, seed_value)
				_log_debug("generator-call", {"type": "tree_procedural", "style": tree_style, "seed": seed_value, "lod": lod_level, "biome": biome_id})
				mesh = _tree_generator.generate_tree_mesh(tree_style, seed_value, lod_level)
			else:
				_log_debug("generator-call", {"type": "tree_legacy", "variant": variant, "seed": seed_value, "lod": lod_level, "biome": biome_id})
				mesh = TreeGenerator.generate_tree(biome_id, variant, seed_value, lod_level)
		VegetationType.BUSH:
			_log_debug("generator-call", {"type": "bush", "variant": variant, "seed": seed_value, "lod": lod_level, "biome": biome_id})
			mesh = BushGenerator.generate_bush(biome_id, variant, seed_value, lod_level)
		VegetationType.ROCK_SMALL:
			_log_debug("generator-call", {"type": "rock_small", "variant": variant, "seed": seed_value, "lod": lod_level, "biome": biome_id})
			mesh = RockGenerator.generate_rock(biome_id, "small", seed_value, lod_level)
		VegetationType.ROCK_MEDIUM:
			_log_debug("generator-call", {"type": "rock_medium", "variant": variant, "seed": seed_value, "lod": lod_level, "biome": biome_id})
			mesh = RockGenerator.generate_rock(biome_id, "medium", seed_value, lod_level)
		VegetationType.GRASS_TUFT:
			_log_debug("generator-call", {"type": "grass", "seed": seed_value, "lod": lod_level, "biome": biome_id})
			mesh = GrassGenerator.generate_grass_tuft(biome_id, seed_value, lod_level)
		VegetationType.ORE_STONE, VegetationType.ORE_IRON, VegetationType.ORE_COPPER:
			# Generate ore boulder - large rocks with ore material
			var ore_size := "large" if type == VegetationType.ORE_IRON else "medium"
			_log_debug("generator-call", {"type": "ore", "ore_size": ore_size, "seed": seed_value, "lod": lod_level, "biome": biome_id})
			mesh = RockGenerator.generate_ore_boulder(type, seed_value, lod_level)
	
	if mesh:
		var validation: Dictionary = _validate_mesh(mesh)
		var validation_ok: bool = validation.get("ok", false) as bool
		if validation_ok:
			_log_debug("mesh-valid", {"key": cache_key, "surface_count": validation.get("surface_count", 0), "vertex_count": validation.get("vertex_count", 0)})
			_cache_mesh(cache_key, mesh)
		else:
			push_warning("[VegetationManager] Mesh validation failed for key %s: %s" % [cache_key, str(validation)])
			mesh = null
	
	return mesh


## Get billboard mesh for distant vegetation
func get_billboard_mesh(type: VegetationType, biome_id: int, variant: String, seed_value: int) -> Mesh:
	var cache_key := "billboard_%d_%d_%s_%d" % [type, biome_id, variant, seed_value % MAX_SEED_VARIATIONS]
	
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
	
	var mesh: Mesh = null
	match type:
		VegetationType.TREE:
			mesh = TreeGenerator.generate_billboard(biome_id, variant, seed_value)
		VegetationType.BUSH:
			mesh = BushGenerator.generate_billboard(biome_id, seed_value)
		VegetationType.GRASS_TUFT:
			mesh = GrassGenerator.generate_billboard(biome_id, seed_value)
	
	if mesh:
		_cache_mesh(cache_key, mesh)
	
	return mesh


# =============================================================================
# PUBLIC API - VEGETATION RULES
# =============================================================================

## Get vegetation rules for a biome
func get_biome_rules(biome_id: int) -> Dictionary:
	_biome_rule_queries[biome_id] = _biome_rule_queries.get(biome_id, 0) + 1
	if not BIOME_VEGETATION_RULES.has(biome_id):
		push_warning("[VegetationManager] Unknown biome id %s requested, returning default rules" % str(biome_id))
		return {"types": [], "slope_max": 45.0, "height_range": {"min": -100, "max": 300}}
	return BIOME_VEGETATION_RULES[biome_id]


## Validate that biome vegetation rules are consistent (densities, variants)
func validate_biome_rules() -> Dictionary:
	var issues: Array[String] = []
	for biome_id in MapGenerator.Biome.values():
		if not BIOME_VEGETATION_RULES.has(biome_id):
			issues.append("Biome %s missing rules" % str(biome_id))
			continue
		
		var rules: Dictionary = BIOME_VEGETATION_RULES[biome_id]
		var types: Array = rules.get("types", [])
		for type_data: Dictionary in types:
			var density: float = type_data.get("density", 0.0)
			var veg_type: int = type_data.get("type", -1)
			var variants: Array = type_data.get("variants", [])
			if variants.is_empty():
				issues.append("Biome %d type %d has no variants" % [biome_id, veg_type])
			if veg_type == VegetationType.GRASS_TUFT and density > 0.15:
				issues.append("Biome %d grass density %.3f exceeds 0.15" % [biome_id, density])
	
	if issues.is_empty():
		print("[VegetationManager] Biome vegetation rules validated: OK")
	else:
		for issue in issues:
			push_warning(issue)
	
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"query_counts": _biome_rule_queries.duplicate()
	}


## Get all vegetation types for a biome
func get_vegetation_types_for_biome(biome_id: int) -> Array:
	var rules := get_biome_rules(biome_id)
	return rules.get("types", [])


## Calculate effective density for a vegetation type in a biome
func get_effective_density(biome_id: int, veg_type_data: Dictionary) -> float:
	var base_density: float = veg_type_data.get("density", 0.1)
	var biome_veg_density := BiomeManager.get_vegetation_density(biome_id)
	return base_density * biome_veg_density


# =============================================================================
# PUBLIC API - VEGETATION CLEARING
# =============================================================================

## Clear vegetation instances within a radius (for mining/building)
func clear_vegetation_in_radius(center: Vector3, radius: float) -> void:
	var cleared_count := 0
	var chunks_to_update: Array[Vector3i] = []
	
	# Find affected chunks
	for chunk_origin: Vector3i in _populated_chunks.keys():
		var chunk_center := Vector3(chunk_origin) + Vector3(16, 16, 16)
		if chunk_center.distance_to(center) < radius + 32.0:  # 32 = chunk diagonal
			chunks_to_update.append(chunk_origin)
	
	# Remove instances within radius
	for chunk_origin in chunks_to_update:
		var instances: Array = _populated_chunks[chunk_origin]
		var remaining: Array = []
		
		for instance_data: Dictionary in instances:
			var pos: Vector3 = instance_data.get("position", Vector3.ZERO)
			if pos.distance_to(center) >= radius:
				remaining.append(instance_data)
			else:
				cleared_count += 1
				_update_stats_on_remove(instance_data.get("type", VegetationType.BUSH))
		
		_populated_chunks[chunk_origin] = remaining
	
	if cleared_count > 0:
		vegetation_cleared.emit(center, radius, cleared_count)


## Check if a position has vegetation nearby
func has_vegetation_near(position: Vector3, min_distance: float) -> bool:
	var grid_cell := _get_spatial_hash_cell(position)
	
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell := Vector2i(grid_cell.x + dx, grid_cell.y + dz)
			if _instance_spatial_hash.has(cell):
				for pos: Vector3 in _instance_spatial_hash[cell]:
					if pos.distance_to(position) < min_distance:
						return true
	
	return false


## Register a vegetation instance position
func register_instance_position(position: Vector3, chunk_origin: Vector3i, type: VegetationType, transform: Transform3D) -> void:
	var grid_cell := _get_spatial_hash_cell(position)
	
	if not _instance_spatial_hash.has(grid_cell):
		_instance_spatial_hash[grid_cell] = []
	_instance_spatial_hash[grid_cell].append(position)
	
	if not _populated_chunks.has(chunk_origin):
		_populated_chunks[chunk_origin] = []
	_populated_chunks[chunk_origin].append({
		"position": position,
		"type": type,
		"transform": transform
	})
	
	_update_stats_on_add(type)


## Unload a chunk and remove its instances from tracking
func unload_chunk(chunk_origin: Vector3i) -> void:
	if not _populated_chunks.has(chunk_origin):
		return
	
	var instances: Array = _populated_chunks[chunk_origin]
	
	# Remove positions from spatial hash and update stats
	for instance_data: Dictionary in instances:
		var pos: Vector3 = instance_data.get("position", Vector3.ZERO)
		var veg_type: VegetationType = instance_data.get("type", VegetationType.BUSH)
		
		# Remove from spatial hash
		var grid_cell := _get_spatial_hash_cell(pos)
		if _instance_spatial_hash.has(grid_cell):
			var cell_positions: Array = _instance_spatial_hash[grid_cell]
			var idx := cell_positions.find(pos)
			if idx >= 0:
				cell_positions.remove_at(idx)
			if cell_positions.is_empty():
				_instance_spatial_hash.erase(grid_cell)
		
		_update_stats_on_remove(veg_type)
	
	_populated_chunks.erase(chunk_origin)


# =============================================================================
# PUBLIC API - STATISTICS & DEBUG
# =============================================================================

## Get current statistics
func get_stats() -> Dictionary:
	_stats["cache_size"] = _mesh_cache.size()
	return _stats.duplicate()


## Print statistics to console
func print_stats() -> void:
	var stats := get_stats()
	print("[VegetationManager] === STATISTICS ===")
	print("  Total Instances: %d" % stats["total_instances"])
	print("  Trees: %d | Bushes: %d | Rocks: %d | Grass: %d" % [
		stats["tree_count"], stats["bush_count"], stats["rock_count"], stats["grass_count"]
	])
	print("  Mesh Cache: %d meshes" % stats["cache_size"])
	print("  Cache Hits: %d | Misses: %d" % [stats["cache_hits"], stats["cache_misses"]])
	print("  Populated Chunks: %d" % _populated_chunks.size())


## Reload all vegetation (clear and regenerate)
func reload_all_vegetation() -> void:
	print("[VegetationManager] Reloading all vegetation...")
	_populated_chunks.clear()
	_instance_spatial_hash.clear()
	_reset_stats()
	# Note: Actual regeneration happens via VegetationInstancer when chunks are re-populated


## Clear mesh cache
func clear_mesh_cache() -> void:
	_mesh_cache.clear()
	_mesh_cache_order.clear()
	_stats["cache_size"] = 0
	_stats["cache_hits"] = 0
	_stats["cache_misses"] = 0
	print("[VegetationManager] Mesh cache cleared")


## Print detailed cache contents (LRU order)
func debug_print_cache_contents() -> void:
	print("[VegetationManager] Cache contents (oldest -> newest):")
	for key in _mesh_cache_order:
		print("  %s" % key)
	print("  Size: %d | Hits: %d | Misses: %d" % [_mesh_cache.size(), _stats["cache_hits"], _stats["cache_misses"]])


## Run generator validation across biomes and variants
func debug_validate_generators() -> Dictionary:
	var results: Dictionary = {}
	for biome_id in MapGenerator.Biome.values():
		results[biome_id] = {}
		results[biome_id]["tree"] = _debug_validate_type(VegetationType.TREE, biome_id)
		results[biome_id]["bush"] = _debug_validate_type(VegetationType.BUSH, biome_id)
		results[biome_id]["grass"] = _debug_validate_type(VegetationType.GRASS_TUFT, biome_id)
		results[biome_id]["rock_small"] = _debug_validate_type(VegetationType.ROCK_SMALL, biome_id)
		results[biome_id]["rock_medium"] = _debug_validate_type(VegetationType.ROCK_MEDIUM, biome_id)
	return results


## Test cache behavior including eviction and seed limiting
func debug_test_cache_behavior() -> Dictionary:
	clear_mesh_cache()
	var report := {
		"initial": {"size": _mesh_cache.size(), "order": _mesh_cache_order.duplicate()},
		"first_pass_hits": 0,
		"second_pass_hits": 0,
		"evicted": [],
		"final_size": 0
	}
	var combos: Array = []
	for i in range(10):
		combos.append({"type": VegetationType.TREE, "biome": MapGenerator.Biome.PLAINS, "variant": "oak", "seed": i})
	combos.append({"type": VegetationType.BUSH, "biome": MapGenerator.Biome.FOREST, "variant": "fern", "seed": 1})
	# First pass - cache misses expected
	for c in combos:
		var mesh := get_mesh_for_type(c["type"], c["biome"], c["variant"], c["seed"], 0)
		if mesh:
			report["first_pass_hits"] += 0
	# Second pass - all should be hits
	for c in combos:
		var mesh := get_mesh_for_type(c["type"], c["biome"], c["variant"], c["seed"], 0)
		if mesh:
			report["second_pass_hits"] += 1
	# Fill cache to force eviction
	for i in range(200):
		var seed := i + 100
		var key := "cache_stress_%d" % i
		var mesh := get_mesh_for_type(VegetationType.ROCK_SMALL, MapGenerator.Biome.MOUNTAIN, "granite", seed, i % 4)
		if mesh:
			report["evicted"].append(key) if _mesh_cache_order.size() > MAX_MESH_CACHE_SIZE else null
	report["final_size"] = _mesh_cache.size()
	report["order_tail"] = _mesh_cache_order.slice(maxi(0, _mesh_cache_order.size() - 5), _mesh_cache_order.size())
	return report


## Validate biome variant mapping against generator-supported variants
func debug_validate_biome_variants() -> Dictionary:
	var issues: Array[String] = []
	for biome_id in MapGenerator.Biome.values():
		var rules: Dictionary = BIOME_VEGETATION_RULES.get(biome_id, EMPTY_RULES)
		for type_data: Dictionary in rules.get("types", []):
			var veg_type: int = type_data.get("type", -1)
			var variants: Array = type_data.get("variants", [])
			for variant in variants:
				if not _variant_supported(veg_type, biome_id, variant):
					issues.append("Biome %d variant %s unsupported for type %d" % [biome_id, variant, veg_type])
	return {
		"ok": issues.is_empty(),
		"issues": issues
	}


## Check LOD reduction vertex counts for each generator
func debug_check_lod_reduction() -> Dictionary:
	var summary: Dictionary = {}
	var sample_biome := MapGenerator.Biome.FOREST
	summary["tree"] = _debug_lod_counts(VegetationType.TREE, sample_biome, "oak")
	summary["bush"] = _debug_lod_counts(VegetationType.BUSH, sample_biome, "green_bush")
	summary["grass"] = _debug_lod_counts(VegetationType.GRASS_TUFT, sample_biome, "grass")
	summary["rock_small"] = _debug_lod_counts(VegetationType.ROCK_SMALL, MapGenerator.Biome.MOUNTAIN, "granite")
	return summary


## Validate seed variation diversity for first 10 seeds (mod limiting)
func debug_test_seed_variations() -> Dictionary:
	var biome := MapGenerator.Biome.FOREST
	var variant := "oak"
	var base_vertices: Array = []
	var distinct_count := 0
	for seed in range(10):
		var mesh := get_mesh_for_type(VegetationType.TREE, biome, variant, seed, 0)
		if not mesh:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var verts: Array = arrays[Mesh.ARRAY_VERTEX]
		if base_vertices.is_empty():
			base_vertices = verts.duplicate()
			distinct_count += 1
		elif not _vertices_equal(base_vertices, verts):
			distinct_count += 1
	return {
		"distinct_meshes": distinct_count,
		"expected": 10,
		"seed_limit_repeat": _vertices_equal(
			_get_vertices_for_seed(VegetationType.TREE, biome, variant, 0),
			_get_vertices_for_seed(VegetationType.TREE, biome, variant, 10)
		)
	}


# =============================================================================
# INTERNAL HELPERS
# =============================================================================

func _cache_mesh(key: String, mesh: Mesh) -> void:
	# Evict oldest if cache is full
	while _mesh_cache.size() >= MAX_MESH_CACHE_SIZE:
		var oldest: String = ""
		if _mesh_cache_order.size() > 0:
			oldest = _mesh_cache_order.pop_front()
		elif _mesh_cache.size() > 0:
			oldest = _mesh_cache.keys()[0]
		if oldest != "":
			_log_debug("cache-evict", {"oldest": oldest, "note": "order-empty" if _mesh_cache_order.is_empty() else "lru"})
			_mesh_cache.erase(oldest)
	
	_mesh_cache[key] = mesh
	_mesh_cache_order.append(key)
	_stats["cache_size"] = _mesh_cache.size()


func _get_spatial_hash_cell(position: Vector3) -> Vector2i:
	# 4m grid cells for spatial hashing
	return Vector2i(int(position.x / 4.0), int(position.z / 4.0))


func _update_stats_on_add(type: VegetationType) -> void:
	_stats["total_instances"] += 1
	match type:
		VegetationType.TREE:
			_stats["tree_count"] += 1
		VegetationType.BUSH:
			_stats["bush_count"] += 1
		VegetationType.ROCK_SMALL, VegetationType.ROCK_MEDIUM:
			_stats["rock_count"] += 1
		VegetationType.GRASS_TUFT:
			_stats["grass_count"] += 1


func _update_stats_on_remove(type: VegetationType) -> void:
	_stats["total_instances"] = maxi(0, _stats["total_instances"] - 1)
	match type:
		VegetationType.TREE:
			_stats["tree_count"] = maxi(0, _stats["tree_count"] - 1)
		VegetationType.BUSH:
			_stats["bush_count"] = maxi(0, _stats["bush_count"] - 1)
		VegetationType.ROCK_SMALL, VegetationType.ROCK_MEDIUM:
			_stats["rock_count"] = maxi(0, _stats["rock_count"] - 1)
		VegetationType.GRASS_TUFT:
			_stats["grass_count"] = maxi(0, _stats["grass_count"] - 1)


func _reset_stats() -> void:
	_stats["total_instances"] = 0
	_stats["tree_count"] = 0
	_stats["bush_count"] = 0
	_stats["rock_count"] = 0
	_stats["grass_count"] = 0


func _validate_mesh(mesh: Mesh) -> Dictionary:
	if mesh == null:
		return {"ok": false, "reason": "null mesh"}
	if mesh.get_surface_count() == 0:
		return {"ok": false, "reason": "no surfaces"}
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return {"ok": false, "reason": "empty arrays"}
	var vertices: Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return {"ok": false, "reason": "no vertices"}
	# Ensure assignable to MultiMesh
	var mm := MultiMesh.new()
	mm.mesh = mesh
	return {"ok": true, "surface_count": mesh.get_surface_count(), "vertex_count": vertices.size()}


func _debug_validate_type(veg_type: int, biome_id: int) -> Dictionary:
	var variants := _get_variants_for_type(veg_type, biome_id)
	if variants.is_empty():
		variants.append("default")
	var results: Dictionary = {}
	for variant in variants:
		var mesh := get_mesh_for_type(veg_type, biome_id, variant, randi(), 0)
		var validation := _validate_mesh(mesh)
		results[variant] = validation
	return results


func _get_variants_for_type(veg_type: int, biome_id: int) -> Array:
	match veg_type:
		VegetationType.TREE:
			return TreeGenerator.BIOME_TREE_VARIANTS.get(biome_id, [])
		VegetationType.BUSH:
			return BushGenerator.BIOME_BUSH_VARIANTS.get(biome_id, [])
		VegetationType.GRASS_TUFT:
			return ["grass"]
		VegetationType.ROCK_SMALL, VegetationType.ROCK_MEDIUM:
			return ["stone"]
		_:
			return []


func _variant_supported(veg_type: int, biome_id: int, variant: String) -> bool:
	var supported := _get_variants_for_type(veg_type, biome_id)
	if supported.is_empty():
		return true  # treat as open variant list
	return variant in supported


func _debug_lod_counts(veg_type: int, biome_id: int, variant: String) -> Dictionary:
	var counts: Array[int] = []
	for lod in range(4):
		var mesh := get_mesh_for_type(veg_type, biome_id, variant, 1234, lod)
		if mesh:
			var arrays := mesh.surface_get_arrays(0)
			var verts: Array = arrays[Mesh.ARRAY_VERTEX]
			counts.append(verts.size())
		else:
			counts.append(0)
	return {
		"lod_counts": counts,
		"monotonic": counts.size() == 4 and counts[0] >= counts[1] and counts[1] >= counts[2] and counts[2] >= counts[3]
	}


func _get_vertices_for_seed(veg_type: int, biome_id: int, variant: String, seed_value: int) -> Array:
	var mesh := get_mesh_for_type(veg_type, biome_id, variant, seed_value, 0)
	if not mesh:
		return []
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _vertices_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


func _log_debug(label: String, payload: Dictionary) -> void:
	if not debug_enabled:
		return
	print("[VegetationManager][%s] %s" % [label, str(payload)])
