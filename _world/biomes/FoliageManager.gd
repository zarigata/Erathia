class_name FoliageManager
extends Node3D
## Manages procedural foliage using MultiMeshInstance3D for efficient GPU-based rendering.
## Implements "Instance-Swap" pattern: visual instances swap to RigidBody on destruction.
## Works with custom chunk-based terrain system.

@export var world_seed: int = 0
@export var update_radius: float = 128.0
@export var update_interval: float = 1.0

## Foliage density settings
@export_group("Grass Settings")
@export var grass_enabled: bool = true
@export var grass_density: float = 0.5
@export var grass_per_chunk: int = 50
@export var grass_mesh: Mesh
@export var grass_material: Material

@export_group("Tree Settings")
@export var trees_enabled: bool = true
@export var tree_density: float = 0.1
@export var trees_per_chunk: int = 3
@export var tree_mesh: Mesh
@export var tree_material: Material

@export_group("Bush Settings")
@export var bushes_enabled: bool = true
@export var bush_density: float = 0.25
@export var bushes_per_chunk: int = 8
@export var bush_mesh: Mesh
@export var bush_material: Material

## Internal state
var _terrain_manager: TerrainManager
var _biome_manager: BiomeManager
var _player: Node3D
var _placement_noise: FastNoiseLite
var _tree_noise: FastNoiseLite
var _bush_noise: FastNoiseLite

## MultiMesh instances per chunk
var _grass_instances: Dictionary = {}  # Vector3i -> MultiMeshInstance3D
var _tree_instances: Dictionary = {}   # Vector3i -> Array[TreeInstance]
var _bush_instances: Dictionary = {}   # Vector3i -> MultiMeshInstance3D

## Loaded chunks tracking
var _loaded_chunks: Dictionary = {}
var _update_timer: float = 0.0

## Item IDs
const ITEM_GRASS: int = 0
const ITEM_TREE: int = 1
const ITEM_BUSH: int = 2

## Tree instance data for destruction
class TreeInstance:
	var position: Vector3
	var transform: Transform3D
	var is_destroyed: bool = false

var _tree_data: Dictionary = {}  # Vector3i -> Array[TreeInstance]

signal tree_destroyed(position: Vector3, item_id: int)


func _ready() -> void:
	_setup_noise()
	call_deferred("_find_references")


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_update_foliage()


func _setup_noise() -> void:
	_placement_noise = FastNoiseLite.new()
	_placement_noise.seed = world_seed
	_placement_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_placement_noise.frequency = 0.1
	
	_tree_noise = FastNoiseLite.new()
	_tree_noise.seed = world_seed + 1000
	_tree_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_tree_noise.frequency = 0.02
	
	_bush_noise = FastNoiseLite.new()
	_bush_noise.seed = world_seed + 2000
	_bush_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_bush_noise.frequency = 0.05


func _find_references() -> void:
	var root: Node = get_tree().root
	_terrain_manager = root.find_child("TerrainManager", true, false) as TerrainManager
	if _terrain_manager:
		_biome_manager = _terrain_manager.biome_manager
	
	var players: Array = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		_player = players[0]


func _update_foliage() -> void:
	if _player == null or _terrain_manager == null:
		_find_references()
		return
	
	var player_pos: Vector3 = _player.global_position
	var chunk_size: int = 16  # Match TerrainManager.CHUNK_SIZE
	var player_chunk := Vector3i(
		int(floor(player_pos.x / chunk_size)),
		0,  # Foliage only on surface
		int(floor(player_pos.z / chunk_size))
	)
	
	var view_distance: int = int(ceil(update_radius / chunk_size))
	
	# Load new chunks
	for x in range(player_chunk.x - view_distance, player_chunk.x + view_distance + 1):
		for z in range(player_chunk.z - view_distance, player_chunk.z + view_distance + 1):
			var chunk_key := Vector3i(x, 0, z)
			if not _loaded_chunks.has(chunk_key):
				_generate_chunk_foliage(chunk_key)
				_loaded_chunks[chunk_key] = true
	
	# Unload distant chunks
	var chunks_to_remove: Array[Vector3i] = []
	for chunk_key: Vector3i in _loaded_chunks.keys():
		var dx: int = absi(chunk_key.x - player_chunk.x)
		var dz: int = absi(chunk_key.z - player_chunk.z)
		if dx > view_distance + 2 or dz > view_distance + 2:
			chunks_to_remove.append(chunk_key)
	
	for chunk_key in chunks_to_remove:
		_unload_chunk_foliage(chunk_key)
		_loaded_chunks.erase(chunk_key)


func _generate_chunk_foliage(chunk_key: Vector3i) -> void:
	var chunk_size: int = 16
	var chunk_origin := Vector3(
		chunk_key.x * chunk_size,
		0,
		chunk_key.z * chunk_size
	)
	
	# Generate grass
	if grass_enabled:
		_generate_grass_for_chunk(chunk_key, chunk_origin, chunk_size)
	
	# Generate trees
	if trees_enabled:
		_generate_trees_for_chunk(chunk_key, chunk_origin, chunk_size)
	
	# Generate bushes
	if bushes_enabled:
		_generate_bushes_for_chunk(chunk_key, chunk_origin, chunk_size)


func _generate_grass_for_chunk(chunk_key: Vector3i, origin: Vector3, size: int) -> void:
	var transforms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_key)
	
	for i in range(grass_per_chunk):
		var local_x: float = rng.randf() * size
		var local_z: float = rng.randf() * size
		var world_x: float = origin.x + local_x
		var world_z: float = origin.z + local_z
		
		# Check biome suitability
		if _biome_manager:
			var biome: BiomeDefinition = _biome_manager.get_biome_data(world_x, world_z)
			if biome.biome_name in [&"OCEAN", &"BEACH", &"DESERT"]:
				continue
		
		# Get terrain height
		var height: float = 0.0
		if _biome_manager:
			height = _biome_manager.get_terrain_height(world_x, world_z)
		
		# Skip underwater
		if height < 1.0:
			continue
		
		# Noise-based density
		var noise_val: float = _placement_noise.get_noise_2d(world_x, world_z)
		if noise_val < (1.0 - grass_density * 2.0):
			continue
		
		var pos := Vector3(world_x, height, world_z)
		var rot: float = rng.randf() * TAU
		var scale_factor: float = rng.randf_range(0.7, 1.3)
		
		var t := Transform3D.IDENTITY
		t = t.rotated(Vector3.UP, rot)
		t = t.scaled(Vector3.ONE * scale_factor)
		t.origin = pos
		transforms.append(t)
	
	if transforms.size() > 0:
		var mmi := _create_multimesh_instance(transforms, _get_grass_mesh())
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_grass_instances[chunk_key] = mmi


func _generate_trees_for_chunk(chunk_key: Vector3i, origin: Vector3, size: int) -> void:
	var tree_list: Array[TreeInstance] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_key) + 1000
	
	for i in range(trees_per_chunk):
		var local_x: float = rng.randf() * size
		var local_z: float = rng.randf() * size
		var world_x: float = origin.x + local_x
		var world_z: float = origin.z + local_z
		
		# Check biome suitability
		if _biome_manager:
			var biome: BiomeDefinition = _biome_manager.get_biome_data(world_x, world_z)
			if biome.biome_name in [&"OCEAN", &"BEACH", &"DESERT", &"TUNDRA"]:
				continue
		
		# Get terrain height
		var height: float = 0.0
		if _biome_manager:
			height = _biome_manager.get_terrain_height(world_x, world_z)
		
		# Skip underwater or too high
		if height < 5.0 or height > 100.0:
			continue
		
		# Noise-based density
		var noise_val: float = _tree_noise.get_noise_2d(world_x, world_z)
		if noise_val < (1.0 - tree_density * 2.0):
			continue
		
		var pos := Vector3(world_x, height, world_z)
		var rot: float = rng.randf() * TAU
		var scale_factor: float = rng.randf_range(0.7, 1.4)
		
		var t := Transform3D.IDENTITY
		t = t.rotated(Vector3.UP, rot)
		t = t.scaled(Vector3.ONE * scale_factor)
		t.origin = pos
		
		var tree_inst := TreeInstance.new()
		tree_inst.position = pos
		tree_inst.transform = t
		tree_list.append(tree_inst)
	
	_tree_data[chunk_key] = tree_list
	
	# Create visual instances for trees (individual nodes for destruction)
	var tree_nodes: Array = []
	for tree_inst in tree_list:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = _get_tree_mesh()
		mesh_inst.transform = tree_inst.transform
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mesh_inst)
		tree_nodes.append(mesh_inst)
	
	_tree_instances[chunk_key] = tree_nodes


func _generate_bushes_for_chunk(chunk_key: Vector3i, origin: Vector3, size: int) -> void:
	var transforms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_key) + 2000
	
	for i in range(bushes_per_chunk):
		var local_x: float = rng.randf() * size
		var local_z: float = rng.randf() * size
		var world_x: float = origin.x + local_x
		var world_z: float = origin.z + local_z
		
		# Check biome suitability
		if _biome_manager:
			var biome: BiomeDefinition = _biome_manager.get_biome_data(world_x, world_z)
			if biome.biome_name in [&"OCEAN", &"BEACH", &"DESERT"]:
				continue
		
		# Get terrain height
		var height: float = 0.0
		if _biome_manager:
			height = _biome_manager.get_terrain_height(world_x, world_z)
		
		# Skip underwater
		if height < 2.0:
			continue
		
		# Noise-based density
		var noise_val: float = _bush_noise.get_noise_2d(world_x, world_z)
		if noise_val < (1.0 - bush_density * 2.0):
			continue
		
		var pos := Vector3(world_x, height, world_z)
		var rot: float = rng.randf() * TAU
		var scale_factor: float = rng.randf_range(0.6, 1.2)
		
		var t := Transform3D.IDENTITY
		t = t.rotated(Vector3.UP, rot)
		t = t.scaled(Vector3.ONE * scale_factor)
		t.origin = pos
		transforms.append(t)
	
	if transforms.size() > 0:
		var mmi := _create_multimesh_instance(transforms, _get_bush_mesh())
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_bush_instances[chunk_key] = mmi


func _unload_chunk_foliage(chunk_key: Vector3i) -> void:
	if _grass_instances.has(chunk_key):
		_grass_instances[chunk_key].queue_free()
		_grass_instances.erase(chunk_key)
	
	if _tree_instances.has(chunk_key):
		for node in _tree_instances[chunk_key]:
			if is_instance_valid(node):
				node.queue_free()
		_tree_instances.erase(chunk_key)
		_tree_data.erase(chunk_key)
	
	if _bush_instances.has(chunk_key):
		_bush_instances[chunk_key].queue_free()
		_bush_instances.erase(chunk_key)


func _create_multimesh_instance(transforms: Array[Transform3D], mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


func _get_grass_mesh() -> Mesh:
	if grass_mesh:
		return grass_mesh
	return _create_default_grass_mesh()


func _get_tree_mesh() -> Mesh:
	if tree_mesh:
		return tree_mesh
	return _create_default_tree_mesh()


func _get_bush_mesh() -> Mesh:
	if bush_mesh:
		return bush_mesh
	return _create_default_bush_mesh()


func _create_default_grass_mesh() -> Mesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.3, 0.5)
	mesh.orientation = PlaneMesh.FACE_Z
	mesh.center_offset = Vector3(0, 0.25, 0)
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 0.2)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mesh.material = mat
	return mesh


func _create_default_tree_mesh() -> Mesh:
	var array_mesh := ArrayMesh.new()
	
	# Trunk
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.3
	trunk.height = 3.0
	
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.25, 0.1)
	trunk.material = trunk_mat
	
	# Foliage
	var foliage := CylinderMesh.new()
	foliage.top_radius = 0.0
	foliage.bottom_radius = 1.5
	foliage.height = 3.0
	
	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.15, 0.45, 0.1)
	foliage.material = foliage_mat
	
	var trunk_arrays := trunk.get_mesh_arrays()
	var foliage_arrays := foliage.get_mesh_arrays()
	
	# Offset foliage upward
	var verts: PackedVector3Array = foliage_arrays[Mesh.ARRAY_VERTEX]
	for i in range(verts.size()):
		verts[i].y += 4.0
	foliage_arrays[Mesh.ARRAY_VERTEX] = verts
	
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, trunk_arrays)
	array_mesh.surface_set_material(0, trunk_mat)
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, foliage_arrays)
	array_mesh.surface_set_material(1, foliage_mat)
	
	return array_mesh


func _create_default_bush_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.6
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.15)
	mesh.material = mat
	return mesh


## Instance-Swap: Convert visual tree to physics RigidBody on destruction
func swap_tree_to_physics(tree_position: Vector3) -> RigidBody3D:
	# Find the tree near this position
	var chunk_size: int = 16
	var chunk_key := Vector3i(
		int(floor(tree_position.x / chunk_size)),
		0,
		int(floor(tree_position.z / chunk_size))
	)
	
	if not _tree_instances.has(chunk_key):
		return null
	
	var tree_nodes: Array = _tree_instances[chunk_key]
	var closest_idx: int = -1
	var closest_dist: float = 3.0  # Max distance to consider
	
	for i in range(tree_nodes.size()):
		var node: Node3D = tree_nodes[i]
		if not is_instance_valid(node):
			continue
		var dist: float = node.global_position.distance_to(tree_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_idx = i
	
	if closest_idx < 0:
		return null
	
	var tree_node: MeshInstance3D = tree_nodes[closest_idx]
	var tree_transform: Transform3D = tree_node.global_transform
	
	# Remove visual instance
	tree_node.queue_free()
	tree_nodes.remove_at(closest_idx)
	
	# Create physics replacement
	var rigid := RigidBody3D.new()
	rigid.global_transform = tree_transform
	
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _get_tree_mesh()
	rigid.add_child(mesh_inst)
	
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 4.0
	collision.shape = capsule
	collision.position.y = 2.0
	rigid.add_child(collision)
	
	get_tree().root.add_child(rigid)
	
	# Apply falling impulse
	rigid.apply_central_impulse(Vector3(randf_range(-3, 3), 2, randf_range(-3, 3)))
	
	tree_destroyed.emit(tree_position, ITEM_TREE)
	
	return rigid


## Force regenerate foliage around player
func regenerate_foliage() -> void:
	# Clear all
	for chunk_key in _loaded_chunks.keys():
		_unload_chunk_foliage(chunk_key)
	_loaded_chunks.clear()
	
	# Will regenerate on next update
	_update_timer = update_interval
