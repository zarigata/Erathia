## TerrainCleanupSystem - Detects and removes floating/disconnected terrain after mining
##
## This system uses a flood-fill algorithm to identify disconnected terrain pieces
## and removes them to prevent jagged edges and floating blocks after mining.
##
## Usage:
##   TerrainCleanupSystem.cleanup_floating_terrain(center_position, check_radius)
extends Node

## SDF threshold to consider terrain as "solid" (negative = solid, positive = air)
const SDF_SOLID_THRESHOLD: float = 0.0
## Sample step size for checking terrain connectivity (in voxels)
const SAMPLE_STEP: float = 1.0
## Minimum connected voxels required to keep a chunk (prevents removing small floating pieces)
const MIN_CONNECTED_VOXELS: int = 8
## Maximum samples to process in one cleanup (performance limit)
const MAX_SAMPLES_PER_CLEANUP: int = 2000
## Directions for 3D flood fill (6-connectivity: up, down, left, right, forward, back)
const DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1)
]

## Reference to the terrain
var _terrain: VoxelLodTerrain = null
var _voxel_tool: VoxelTool = null

## Debug mode
@export var debug_mode: bool = false


func _ready() -> void:
	# Connect to TerrainEditSystem's terrain_edited signal
	call_deferred("_connect_to_terrain_system")


func _connect_to_terrain_system() -> void:
	var terrain_edit_system = get_node_or_null("/root/TerrainEditSystem")
	if terrain_edit_system:
		terrain_edit_system.terrain_edited.connect(_on_terrain_edited)
		print("[TerrainCleanupSystem] Connected to TerrainEditSystem")
	else:
		push_warning("[TerrainCleanupSystem] TerrainEditSystem not found")


## Called when terrain is edited
func _on_terrain_edited(position: Vector3, _volume: float, _material_id: int, operation: int) -> void:
	# Only cleanup after SUBTRACT (mining) operations
	if operation != TerrainEditSystem.Operation.SUBTRACT:
		return
	
	# Defer cleanup to next frame to allow voxel system to update
	call_deferred("cleanup_floating_terrain", position, 5.0)


## Sets the terrain reference
func set_terrain(terrain: VoxelLodTerrain) -> void:
	_terrain = terrain
	_voxel_tool = null
	if _terrain:
		_voxel_tool = _terrain.get_voxel_tool()
		if _voxel_tool:
			print("[TerrainCleanupSystem] Terrain set successfully")


## Main cleanup function - detects and removes floating terrain near the given position
## @param center: World position to check around
## @param radius: Radius to check for floating terrain
func cleanup_floating_terrain(center: Vector3, radius: float) -> void:
	if not _ensure_voxel_tool():
		return
	
	# Find all solid voxels in the check area
	var solid_positions: Array[Vector3i] = _find_solid_voxels_in_radius(center, radius)
	
	if solid_positions.is_empty():
		return
	
	# Find disconnected groups using flood fill
	var floating_groups: Array = _find_floating_groups(solid_positions, center, radius)
	
	# Remove floating terrain groups
	for group in floating_groups:
		_remove_terrain_group(group)
	
	if debug_mode and floating_groups.size() > 0:
		print("[TerrainCleanupSystem] Removed %d floating terrain groups near %s" % [floating_groups.size(), center])


## Finds all solid voxel positions within a radius
func _find_solid_voxels_in_radius(center: Vector3, radius: float) -> Array[Vector3i]:
	var solid_positions: Array[Vector3i] = []
	var check_radius_int: int = int(ceil(radius))
	var center_i := Vector3i(int(center.x), int(center.y), int(center.z))
	
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	
	for x in range(-check_radius_int, check_radius_int + 1):
		for y in range(-check_radius_int, check_radius_int + 1):
			for z in range(-check_radius_int, check_radius_int + 1):
				var offset := Vector3i(x, y, z)
				var check_pos := center_i + offset
				
				# Check if within spherical radius
				if offset.length() > radius:
					continue
				
				# Check if position has solid terrain (negative SDF = solid)
				var world_pos := Vector3(check_pos.x, check_pos.y, check_pos.z)
				var sdf_value: float = _voxel_tool.get_voxel_f(world_pos)
				
				if sdf_value < SDF_SOLID_THRESHOLD:
					solid_positions.append(check_pos)
	
	return solid_positions


## Finds groups of terrain that are not connected to the main ground
func _find_floating_groups(solid_positions: Array[Vector3i], center: Vector3, radius: float) -> Array:
	var floating_groups: Array = []
	var visited: Dictionary = {}
	var center_i := Vector3i(int(center.x), int(center.y), int(center.z))
	
	# Mark all solid positions for quick lookup
	var solid_set: Dictionary = {}
	for pos in solid_positions:
		solid_set[pos] = true
	
	# Process each unvisited solid position
	for start_pos in solid_positions:
		if visited.has(start_pos):
			continue
		
		# Flood fill to find connected group
		var group: Array[Vector3i] = _flood_fill_group(start_pos, solid_set, visited, radius * 2)
		
		# Check if this group is floating (not connected to ground below the check area)
		if _is_group_floating(group, center_i, radius):
			# Only remove small floating pieces
			if group.size() < MIN_CONNECTED_VOXELS * 4:
				floating_groups.append(group)
	
	return floating_groups


## Flood fill to find all connected voxels in a group
func _flood_fill_group(start: Vector3i, solid_set: Dictionary, visited: Dictionary, max_distance: float) -> Array[Vector3i]:
	var group: Array[Vector3i] = []
	var queue: Array[Vector3i] = [start]
	var start_vec := Vector3(start.x, start.y, start.z)
	
	while not queue.is_empty() and group.size() < MAX_SAMPLES_PER_CLEANUP:
		var current: Vector3i = queue.pop_front()
		
		if visited.has(current):
			continue
		
		# Check distance from start
		var current_vec := Vector3(current.x, current.y, current.z)
		if current_vec.distance_to(start_vec) > max_distance:
			continue
		
		visited[current] = true
		
		if solid_set.has(current):
			group.append(current)
			
			# Add neighbors to queue
			for dir in DIRECTIONS:
				var neighbor: Vector3i = current + dir
				if not visited.has(neighbor):
					queue.append(neighbor)
	
	return group


## Checks if a group of voxels is floating (not anchored to main terrain)
func _is_group_floating(group: Array[Vector3i], center: Vector3i, radius: float) -> bool:
	if group.is_empty():
		return false
	
	# A group is considered floating if:
	# 1. It's entirely above the center position (no ground connection below)
	# 2. None of its voxels extend beyond the check radius on the bottom
	
	var min_y: int = 999999
	var has_ground_connection: bool = false
	
	for pos in group:
		min_y = mini(min_y, pos.y)
		
		# Check if any voxel connects to terrain outside the check area (potential ground)
		for dir in DIRECTIONS:
			var check_pos: Vector3i = pos + dir
			var check_world := Vector3(check_pos.x, check_pos.y, check_pos.z)
			var center_world := Vector3(center.x, center.y, center.z)
			
			# If neighbor is outside our check radius and is solid, we have ground connection
			if check_world.distance_to(center_world) > radius:
				_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
				var sdf: float = _voxel_tool.get_voxel_f(check_world)
				if sdf < SDF_SOLID_THRESHOLD:
					has_ground_connection = true
					break
		
		if has_ground_connection:
			break
	
	# Consider floating if no ground connection found
	return not has_ground_connection


## Removes a group of terrain voxels
func _remove_terrain_group(group: Array[Vector3i]) -> void:
	if group.is_empty():
		return
	
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	
	# Remove each voxel in the group with a small sphere to create smooth edges
	for pos in group:
		var world_pos := Vector3(pos.x, pos.y, pos.z)
		# Use grow_sphere to carve out the floating terrain (positive value removes)
		_voxel_tool.grow_sphere(world_pos, 0.6, 2.0)
	
	if debug_mode:
		print("[TerrainCleanupSystem] Removed floating group of %d voxels" % group.size())


## Applies smoothing to an area after cleanup to reduce jaggedness
func smooth_area(center: Vector3, radius: float, strength: float = 0.5) -> void:
	if not _ensure_voxel_tool():
		return
	
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	_voxel_tool.smooth_sphere(center, radius, strength)


## Ensures voxel tool is available
func _ensure_voxel_tool() -> bool:
	if _voxel_tool:
		return true
	
	# Try to get terrain from TerrainEditSystem
	var terrain_edit_system = get_node_or_null("/root/TerrainEditSystem")
	if terrain_edit_system and terrain_edit_system._terrain:
		_terrain = terrain_edit_system._terrain
		_voxel_tool = _terrain.get_voxel_tool()
		return _voxel_tool != null
	
	# Try to find VoxelLodTerrain in scene tree
	var scene_root = get_tree().current_scene
	if scene_root:
		var terrain = scene_root.find_child("VoxelLodTerrain", true, false)
		if terrain is VoxelLodTerrain:
			_terrain = terrain
			_voxel_tool = _terrain.get_voxel_tool()
			return _voxel_tool != null
	
	return false
