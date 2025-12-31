extends Node
class_name VegetationPrebaker

const VegetationMeshVariants := preload("res://_world/vegetation/vegetation_mesh_variants.gd")
const VegetationPositionData := preload("res://_world/vegetation/vegetation_position_data.gd")
const TreeGenerator := preload("res://_world/vegetation/mesh_generators/tree_generator.gd")
const BushGenerator := preload("res://_world/vegetation/mesh_generators/bush_generator.gd")
const RockGenerator := preload("res://_world/vegetation/mesh_generators/rock_generator.gd")
const GrassGenerator := preload("res://_world/vegetation/mesh_generators/grass_generator.gd")
const MapGenerator := preload("res://_world/map_generator.gd")
const VegetationManager := preload("res://_world/vegetation/vegetation_manager.gd")

@onready var _veg_mgr: VegetationManager = (
	get_node_or_null("/root/VegetationManager") as VegetationManager
	if get_node_or_null("/root/VegetationManager") != null
	else VegetationManager.new()
)

## VegetationPrebaker
## ------------------
## Offline prebaking pipeline for vegetation meshes and placements.
## Generates deterministic mesh variants per biome/type and samples terrain
## to find valid positions, then writes data to user://veg_cache/{seed}/.
## Consumers: VegetationLoader (runtime instancing) and dev console tools.

signal prebake_progress(current: int, total: int, stage_name: String)
signal prebake_complete()

const VARIANTS_PER_TYPE: int = 8
const GRID_RESOLUTION: int = 512  ## 16 km / 512 ≈ 31.25 m spacing
const CACHE_ROOT: String = "user://veg_cache"

var _stage_total: int = 1
var _stage_current: int = 0

var _prebake_thread: Thread = null
var _thread_mutex: Mutex = Mutex.new()
var _thread_should_exit: bool = false
var _progress_batch_size: int = 50


func prebake_vegetation(world_seed: int, terrain_generator: VoxelGeneratorScript) -> void:
	if terrain_generator == null:
		push_error("[VegetationPrebaker] Terrain generator missing; aborting prebake.")
		return
	
	if _check_cache_exists(world_seed):
		print("[VegetationPrebaker] Cache exists for seed %d; skipping." % world_seed)
		prebake_complete.emit()
		return
	
	if _prebake_thread != null and _prebake_thread.is_alive():
		push_warning("[VegetationPrebaker] Prebake already running.")
		return
	
	_thread_should_exit = false
	_prebake_thread = Thread.new()
	var thread_data := {"seed": world_seed, "generator": terrain_generator}
	var job := Callable(self, "_threaded_prebake").bind(thread_data)
	_prebake_thread.start(job)
	print("[VegetationPrebaker] Started async prebake for seed %d" % world_seed)


func _threaded_prebake(data: Dictionary) -> void:
	var world_seed: int = data["seed"]
	var terrain_generator: VoxelGeneratorScript = data["generator"]
	
	var biome_keys := _veg_mgr.BIOME_VEGETATION_RULES.keys()
	biome_keys.sort()
	_stage_total = biome_keys.size() * 2
	_stage_current = 0
	
	# Phase 1: Sample candidate positions per biome
	var candidate_positions_per_biome: Dictionary = {}
	for biome_id in biome_keys:
		if _thread_should_exit:
			return
		_stage_current += 1
		call_deferred("emit_signal", "prebake_progress", _stage_current, _stage_total, "biome_%d_candidates" % biome_id)
		candidate_positions_per_biome[biome_id] = _sample_candidate_positions(biome_id, terrain_generator, world_seed)
	
	# Phase 2: Generate meshes and subsample positions per type
	var item_count := 0
	for biome_id in biome_keys:
		for veg_type in _veg_mgr.VegetationType.values():
			if _thread_should_exit:
				return
			var type_name := str(veg_type)
			var meshes := _generate_mesh_variants(biome_id, veg_type, world_seed)
			var candidates: Array[Vector3] = candidate_positions_per_biome.get(biome_id, [])
			var positions := _subsample_positions_for_type(candidates, veg_type, biome_id, terrain_generator, world_seed)
			_save_prebaked_data(world_seed, biome_id, type_name, meshes, positions)
			
			item_count += 1
			if item_count % _progress_batch_size == 0:
				call_deferred("emit_signal", "prebake_progress", item_count, biome_keys.size() * _veg_mgr.VegetationType.size(), "processing")
		_stage_current += 1
	
	call_deferred("emit_signal", "prebake_complete")
	print("[VegetationPrebaker] Thread complete for seed %d" % world_seed)


func cancel_prebake() -> void:
	if _prebake_thread == null or not _prebake_thread.is_alive():
		return
	_thread_should_exit = true
	_prebake_thread.wait_to_finish()
	_prebake_thread = null
	print("[VegetationPrebaker] Prebake cancelled.")


func _exit_tree() -> void:
	cancel_prebake()


func _process_biome_type(world_seed: int, biome_id: int, veg_type: int, terrain_generator: VoxelGeneratorScript) -> void:
	## Generate mesh variants and positions for a biome/type, then save both resources.
	var type_name := str(veg_type)
	var meshes := _generate_mesh_variants(biome_id, veg_type, world_seed)
	var positions := _sample_positions_for_biome(biome_id, veg_type, terrain_generator, world_seed)
	_save_prebaked_data(world_seed, biome_id, type_name, meshes, positions)


func _generate_mesh_variants(biome_id: int, veg_type: int, world_seed: int) -> Array[ArrayMesh]:
	## Create deterministic mesh variants using existing generators.
	var variants: Array[ArrayMesh] = []
	if _veg_mgr == null:
		push_error("[VegetationPrebaker] VegetationManager autoload missing; aborting mesh generation.")
		return variants
	var type_rules := _veg_mgr.get_biome_rules(biome_id)
	var type_array: Array = type_rules.get("types", [])
	var variant_names: Array[String] = []
	for data in type_array:
		if data.get("type", -1) == veg_type:
			for v in data.get("variants", []):
				if v not in variant_names:
					variant_names.append(v)
	if variant_names.is_empty():
		variant_names.append("default")
	
	for variant_index in range(VARIANTS_PER_TYPE):
		var variant_name := variant_names[variant_index % variant_names.size()]
		var seed_value := world_seed + biome_id * 1000 + veg_type * 100 + variant_index
		var mesh: Mesh = _generate_mesh_for_type(veg_type, biome_id, variant_name, seed_value)
		if mesh and mesh is ArrayMesh:
			variants.append(mesh)
	
	return variants


func _generate_mesh_for_type(veg_type: int, biome_id: int, variant: String, seed_value: int) -> Mesh:
	## Delegates to VegetationManager generators; LOD0 only.
	if _veg_mgr == null:
		return null
	match veg_type:
		_veg_mgr.VegetationType.TREE:
			return TreeGenerator.generate_tree(biome_id, variant, seed_value, 0)
		_veg_mgr.VegetationType.BUSH:
			return BushGenerator.generate_bush(biome_id, variant, seed_value, 0)
		_veg_mgr.VegetationType.ROCK_SMALL:
			return RockGenerator.generate_rock(biome_id, "small", seed_value, 0)
		_veg_mgr.VegetationType.ROCK_MEDIUM:
			return RockGenerator.generate_rock(biome_id, "medium", seed_value, 0)
		_veg_mgr.VegetationType.GRASS_TUFT:
			return GrassGenerator.generate_grass_tuft(biome_id, seed_value, 0)
		_veg_mgr.VegetationType.ORE_STONE, _veg_mgr.VegetationType.ORE_IRON, _veg_mgr.VegetationType.ORE_COPPER:
			return RockGenerator.generate_ore_boulder(veg_type, seed_value, 0)
		_:
			return null


func _sample_positions_for_biome(
	biome_id: int,
	veg_type: int,
	terrain_generator: VoxelGeneratorScript,
	world_seed: int
) -> Array[Vector3]:
	## Offline sampling on a fixed grid; filters by biome match, slope, density.
	var positions: Array[Vector3] = []
	var rules := _veg_mgr.get_biome_rules(biome_id)
	var type_entry: Dictionary = {}
	for d in rules.get("types", []):
		if d.get("type", -1) == veg_type:
			type_entry = d
			break
	if type_entry.is_empty():
		return positions
	
	var candidates := _sample_candidate_positions(biome_id, terrain_generator, world_seed)
	var filtered := _subsample_positions_for_type(candidates, veg_type, biome_id, terrain_generator, world_seed)
	return filtered


func _sample_candidate_positions(
	biome_id: int,
	terrain_generator: VoxelGeneratorScript,
	world_seed: int
) -> Array[Vector3]:
	## Shared biome-level sampling: scans grid once to collect matching biome positions.
	var positions: Array[Vector3] = []
	var world_size: float = MapGenerator.WORLD_SIZE
	var half_world := world_size * 0.5
	var step: float = world_size / float(GRID_RESOLUTION)
	for ix in range(GRID_RESOLUTION):
		var x := -half_world + ix * step
		for iz in range(GRID_RESOLUTION):
			var z := -half_world + iz * step
			var sampled_biome := _safe_sample_biome(terrain_generator, x, z)
			if sampled_biome != biome_id:
				continue
			
			var height := _safe_sample_height(terrain_generator, x, z)
			var pos := Vector3(x, height, z)
			positions.append(pos)
	return positions


func _subsample_positions_for_type(
	candidates: Array[Vector3],
	veg_type: int,
	biome_id: int,
	terrain_generator: VoxelGeneratorScript,
	world_seed: int
) -> Array[Vector3]:
	## Per-type subsampling using density RNG and slope checks on biome candidates.
	var positions: Array[Vector3] = []
	var rules := _veg_mgr.get_biome_rules(biome_id)
	var type_entry: Dictionary = {}
	for d in rules.get("types", []):
		if d.get("type", -1) == veg_type:
			type_entry = d
			break
	if type_entry.is_empty():
		return positions
	
	var density := _veg_mgr.get_effective_density(biome_id, type_entry)
	if density <= 0.0:
		return positions
	
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + biome_id * 17 + veg_type * 37
	
	for candidate in candidates:
		if rng.randf() > density:
			continue
		if not _is_slope_within_limit(terrain_generator, candidate.x, candidate.z, type_entry):
			continue
		positions.append(candidate)
	
	return positions


func _safe_sample_biome(generator: VoxelGeneratorScript, x: float, z: float) -> int:
	if generator and generator.has_method("sample_biome_at_position"):
		return int(generator.sample_biome_at_position(x, z))
	return MapGenerator.Biome.PLAINS


func _safe_sample_height(generator: VoxelGeneratorScript, x: float, z: float) -> float:
	if generator and generator.has_method("sample_height_at"):
		return generator.sample_height_at(x, z)
	return 0.0


func _is_slope_within_limit(generator: VoxelGeneratorScript, x: float, z: float, type_entry: Dictionary) -> bool:
	var slope_max: float = type_entry.get("slope_max", 45.0)
	if generator == null or not generator.has_method("sample_height_at"):
		return true
	var delta: float = 1.0
	var h_center: float = generator.sample_height_at(x, z)
	var h_xp: float = generator.sample_height_at(x + delta, z)
	var h_xn: float = generator.sample_height_at(x - delta, z)
	var h_zp: float = generator.sample_height_at(x, z + delta)
	var h_zn: float = generator.sample_height_at(x, z - delta)
	var grad_x: float = (h_xp - h_xn) * 0.5
	var grad_z: float = (h_zp - h_zn) * 0.5
	var slope: float = atan2(sqrt(grad_x * grad_x + grad_z * grad_z), 1.0) * 180.0 / PI
	return slope <= slope_max


func _save_prebaked_data(
	world_seed: int,
	biome_id: int,
	type_name: String,
	meshes: Array[ArrayMesh],
	positions: Array[Vector3]
) -> void:
	## Serialize meshes and positions to user://.
	var base_dir := "%s/%d" % [CACHE_ROOT, world_seed]
	DirAccess.make_dir_recursive_absolute(base_dir)
	
	var mesh_res := VegetationMeshVariants.new()
	mesh_res.meshes = meshes
	mesh_res.biome_id = biome_id
	mesh_res.type_name = type_name
	mesh_res.world_seed = world_seed
	var meshes_path := "%s/meshes_%d_%s.res" % [base_dir, biome_id, type_name]
	var mesh_save := ResourceSaver.save(mesh_res, meshes_path)
	if mesh_save != OK:
		push_warning("[VegetationPrebaker] Failed to save meshes for biome %d type %s" % [biome_id, type_name])
	
	var pos_res := VegetationPositionData.new()
	pos_res.positions = positions
	pos_res.biome_id = biome_id
	pos_res.type_name = type_name
	pos_res.world_seed = world_seed
	
	var positions_path := "%s/positions_%d_%s.res" % [base_dir, biome_id, type_name]
	var pos_save := ResourceSaver.save(pos_res, positions_path)
	if pos_save != OK:
		push_warning("[VegetationPrebaker] Failed to save positions for biome %d type %s" % [biome_id, type_name])


func _check_cache_exists(world_seed: int) -> bool:
	var base_dir := "%s/%d" % [CACHE_ROOT, world_seed]
	if not DirAccess.dir_exists_absolute(base_dir):
		return false
	# Simple existence check: verify at least one meshes_*.res file
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return false
	dir.list_dir_begin()
	var found := false
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("meshes_"):
			found = true
			break
		file_name = dir.get_next()
	dir.list_dir_end()
	return found
