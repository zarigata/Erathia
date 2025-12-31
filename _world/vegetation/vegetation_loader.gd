extends Node3D
class_name VegetationLoader

const VegetationMeshVariants := preload("res://_world/vegetation/vegetation_mesh_variants.gd")
const VegetationPositionData := preload("res://_world/vegetation/vegetation_position_data.gd")

## VegetationLoader
## ----------------
## Loads prebaked vegetation meshes and positions from user://veg_cache/{seed}
## and instantiates static MultiMeshInstance3D nodes. Replaces runtime chunk
## streaming to eliminate CPU spikes during exploration.

signal cache_missing(world_seed: int)

const CACHE_ROOT: String = "user://veg_cache"
const VARIANTS_PER_TYPE: int = 32

var _loaded_instances: Array[MultiMeshInstance3D] = []
var _stats: Dictionary = {
	"total_instances": 0,
	"by_type": {}
}


func _ready() -> void:
	## Loader is driven externally via load_vegetation(world_seed).
	pass


func load_vegetation(world_seed: int) -> void:
	## Entry point to load all prebaked data for a seed.
	_clear_loaded()
	if not _check_cache_complete(world_seed):
		cache_missing.emit(world_seed)
		return
	
	var biome_keys := VegetationManager.BIOME_VEGETATION_RULES.keys()
	biome_keys.sort()
	for biome_id in biome_keys:
		for type_data in VegetationManager.get_biome_rules(biome_id).get("types", []):
			var veg_type: int = type_data.get("type", 0)
			var type_name := str(veg_type)
			var data := _load_biome_type_data(world_seed, biome_id, type_name)
			if data.is_empty():
				continue
			_create_multimesh_instances(biome_id, veg_type, data.get("meshes", []), data.get("positions", []))


func _clear_loaded() -> void:
	for inst in _loaded_instances:
		if is_instance_valid(inst):
			inst.queue_free()
	_loaded_instances.clear()
	_stats = {"total_instances": 0, "by_type": {}}


func _check_cache_complete(world_seed: int) -> bool:
	var base_dir := "%s/%d" % [CACHE_ROOT, world_seed]
	if not DirAccess.dir_exists_absolute(base_dir):
		return false
	var rules_keys := VegetationManager.BIOME_VEGETATION_RULES.keys()
	for biome_id in rules_keys:
		for type_data in VegetationManager.get_biome_rules(biome_id).get("types", []):
			var veg_type: int = type_data.get("type", 0)
			var type_name := str(veg_type)
			var mesh_path := "%s/meshes_%d_%s.res" % [base_dir, biome_id, type_name]
			var pos_path := "%s/positions_%d_%s.res" % [base_dir, biome_id, type_name]
			if not FileAccess.file_exists(mesh_path) or not FileAccess.file_exists(pos_path):
				return false
	return true


func _load_biome_type_data(world_seed: int, biome_id: int, type_name: String) -> Dictionary:
	var base_dir := "%s/%d" % [CACHE_ROOT, world_seed]
	var mesh_path := "%s/meshes_%d_%s.res" % [base_dir, biome_id, type_name]
	var pos_path := "%s/positions_%d_%s.res" % [base_dir, biome_id, type_name]
	
	var mesh_res: Variant = ResourceLoader.load(mesh_path)
	var pos_res: Variant = ResourceLoader.load(pos_path)
	if mesh_res == null or pos_res == null:
		push_warning("[VegetationLoader] Missing cached data for biome %d type %s" % [biome_id, type_name])
		return {}
	
	var meshes: Array[ArrayMesh] = []
	if mesh_res is VegetationMeshVariants:
		meshes = (mesh_res as VegetationMeshVariants).meshes
	elif mesh_res is ArrayMesh:
		meshes.append(mesh_res)
	elif mesh_res is Array:
		for m in mesh_res:
			if m is ArrayMesh:
				meshes.append(m)
	else:
		push_warning("[VegetationLoader] Mesh cache type unsupported for biome %d type %s" % [biome_id, type_name])
	
	var positions: Array[Vector3] = []
	if pos_res is VegetationPositionData:
		positions = (pos_res as VegetationPositionData).positions
	elif pos_res is PackedVector3Array:
		positions = Array(pos_res)
	elif pos_res is Array:
		for p in pos_res:
			if p is Vector3:
				positions.append(p)
	else:
		push_warning("[VegetationLoader] Position cache type unsupported for biome %d type %s" % [biome_id, type_name])
	
	return {"meshes": meshes, "positions": positions}


func _create_multimesh_instances(biome_id: int, veg_type: int, meshes: Array, positions: Array) -> void:
	if meshes.is_empty() or positions.is_empty():
		return
	
	var variant_count: int = min(meshes.size(), VARIANTS_PER_TYPE)
	var positions_by_variant: Array = []
	positions_by_variant.resize(variant_count)
	for i in range(variant_count):
		positions_by_variant[i] = []
	
	for idx in range(positions.size()):
		var variant_idx: int = idx % variant_count
		positions_by_variant[variant_idx].append(positions[idx])
	
	for variant_idx in range(variant_count):
		var mesh: Mesh = meshes[variant_idx]
		if mesh == null:
			continue
		var positions_for_variant: Array = positions_by_variant[variant_idx]
		if positions_for_variant.is_empty():
			continue
		
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Veg_%d_%d_%d" % [biome_id, veg_type, variant_idx]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = positions_for_variant.size()
		mm.visible_instance_count = positions_for_variant.size()
		mm.mesh = mesh
		
		for i in range(positions_for_variant.size()):
			var pos: Vector3 = positions_for_variant[i]
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		
		mmi.multimesh = mm
		_configure_visibility_and_shadows(mmi, veg_type)
		add_child(mmi)
		_loaded_instances.append(mmi)
		
		_stats["total_instances"] += positions_for_variant.size()
		var type_key := str(veg_type)
		_stats["by_type"][type_key] = _stats["by_type"].get(type_key, 0) + positions_for_variant.size()


func _configure_visibility_and_shadows(mmi: MultiMeshInstance3D, veg_type: int) -> void:
	var vis := _get_visibility_range(veg_type)
	mmi.visibility_range_begin = 0.0
	mmi.visibility_range_end = vis
	match veg_type:
		VegetationManager.VegetationType.GRASS_TUFT:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _get_visibility_range(veg_type: int) -> float:
	match veg_type:
		VegetationManager.VegetationType.TREE:
			return 512.0
		VegetationManager.VegetationType.BUSH:
			return 256.0
		VegetationManager.VegetationType.GRASS_TUFT:
			return 128.0
		_:
			return 256.0


func get_stats() -> Dictionary:
	return _stats.duplicate()
