class_name VoxelTerrainManager
extends Node3D

@export var terrain_path: NodePath
@export var world_seed: int = 0

@export var viewer_distance_voxels: int = 1024

@export var lod_count: int = 5
@export var lod_distance: float = 64.0
@export var mesh_block_size: int = 32

@export var dig_radius: float = 2.5
@export var build_radius: float = 2.5

@export var tool_sdf_scale: float = 0.05
@export var tool_sdf_strength: float = 1.0

var _terrain: VoxelLodTerrain

func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as VoxelLodTerrain
	if _terrain == null:
		push_error("VoxelTerrainManager: terrain_path is invalid")
		return

	_terrain.lod_count = lod_count
	_terrain.lod_distance = lod_distance
	_terrain.mesh_block_size = mesh_block_size
	_terrain.view_distance = viewer_distance_voxels
	_terrain.generate_collisions = true
	_terrain.collision_layer = 1

	var gen := VoxelBiomeGenerator.new(world_seed)
	_terrain.generator = gen

	var cam := get_tree().get_root().find_child("Camera3D", true, false)
	if cam != null:
		_ensure_voxel_viewer(cam)

func _ensure_voxel_viewer(camera: Node) -> void:
	for child in camera.get_children():
		if child is VoxelViewer:
			(child as VoxelViewer).view_distance = viewer_distance_voxels
			return

	var vv := VoxelViewer.new()
	vv.view_distance = viewer_distance_voxels
	camera.add_child(vv)

func modify_terrain(global_pos: Vector3, amount: float) -> void:
	if _terrain == null:
		return
	var tool := _terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF
	tool.sdf_scale = tool_sdf_scale
	tool.sdf_strength = maxf(0.001, absf(amount) * tool_sdf_strength)
	tool.mode = VoxelTool.MODE_REMOVE if amount < 0.0 else VoxelTool.MODE_ADD
	tool.do_sphere(global_pos, dig_radius if amount < 0.0 else build_radius)

func smooth_terrain(global_pos: Vector3, radius: float) -> void:
	if _terrain == null:
		return
	var tool := _terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF
	tool.sdf_scale = tool_sdf_scale
	tool.sdf_strength = tool_sdf_strength * 0.25
	tool.mode = VoxelTool.MODE_ADD
	tool.do_sphere(global_pos, radius)

func flatten_terrain(global_pos: Vector3, radius: float, target_height: float) -> void:
	if _terrain == null:
		return
	var tool := _terrain.get_voxel_tool() as VoxelToolLodTerrain
	tool.channel = VoxelBuffer.CHANNEL_SDF
	tool.sdf_scale = tool_sdf_scale
	tool.sdf_strength = tool_sdf_strength
	tool.mode = VoxelTool.MODE_ADD
	tool.do_hemisphere(Vector3(global_pos.x, target_height, global_pos.z), radius, Vector3.UP, 0.5)

func get_material_at(global_pos: Vector3) -> int:
	if _terrain == null:
		return 0
	var tool := _terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_INDICES
	var v := tool.get_voxel(Vector3i(int(floor(global_pos.x)), int(floor(global_pos.y)), int(floor(global_pos.z))))
	return v & 0xF
