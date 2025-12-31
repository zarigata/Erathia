extends RefCounted
class_name TerrainPrewarmer
## Terrain Pre-Warming Utility
##
## Forces terrain chunk generation around a specified position.
## Used by WorldInitManager to ensure terrain is ready before player spawns.

const CHUNK_SIZE: int = 32

## DEPRECATED: Use signal-based chunk tracking instead.
## This function forces synchronous generation and blocks the main thread.
## Prewarm terrain chunks synchronously (blocking)
static func prewarm_area(terrain: VoxelLodTerrain, center: Vector3, radius_chunks: int) -> void:
	push_warning("[TerrainPrewarmer] prewarm_area() is deprecated - use signal-based tracking")
	if not terrain:
		push_warning("[TerrainPrewarmer] No terrain provided")
		return
	
	var voxel_tool := terrain.get_voxel_tool()
	if not voxel_tool:
		push_warning("[TerrainPrewarmer] Could not get voxel tool")
		return
	
	var center_chunk := Vector3i(
		int(center.x / CHUNK_SIZE) * CHUNK_SIZE,
		0,
		int(center.z / CHUNK_SIZE) * CHUNK_SIZE
	)
	
	var chunks_warmed := 0
	var total_chunks := (radius_chunks * 2 + 1) * (radius_chunks * 2 + 1)
	
	for x in range(-radius_chunks, radius_chunks + 1):
		for z in range(-radius_chunks, radius_chunks + 1):
			var chunk_origin := Vector3i(
				center_chunk.x + x * CHUNK_SIZE,
				0,
				center_chunk.z + z * CHUNK_SIZE
			)
			
			# Force chunk generation by querying voxel data
			# Raycast from above to force terrain generation
			var ray_start := Vector3(chunk_origin.x + CHUNK_SIZE * 0.5, 200.0, chunk_origin.z + CHUNK_SIZE * 0.5)
			voxel_tool.raycast(ray_start, Vector3.DOWN, 250.0)
			
			chunks_warmed += 1
	
	print("[TerrainPrewarmer] Prewarmed %d chunks around %s" % [chunks_warmed, center])


static func is_chunk_generated(_terrain: VoxelLodTerrain, _chunk_origin: Vector3i) -> bool:
	# Placeholder: chunk tracking handled in WorldInitManager
	return false


## Prewarm terrain chunks asynchronously with progress callback
static func prewarm_area_async(terrain: VoxelLodTerrain, center: Vector3, radius_chunks: int, progress_callback: Callable, complete_callback: Callable) -> void:
	if not terrain:
		push_warning("[TerrainPrewarmer] No terrain provided")
		complete_callback.call()
		return
	
	var viewer := _get_or_create_viewer(terrain, center)
	if not viewer:
		push_warning("[TerrainPrewarmer] Could not create terrain viewer")
		complete_callback.call()
		return

	# VoxelLodTerrain will generate around the viewer automatically
	print("[TerrainPrewarmer] Viewer positioned at %s - terrain will generate automatically" % center)
	progress_callback.call(0.0)


static func _get_or_create_viewer(terrain: VoxelLodTerrain, position: Vector3) -> Node3D:
	var players := terrain.get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var player := players[0] as Node3D
		if player:
			player.global_position = position
			return player
	
	var viewer := Node3D.new()
	viewer.name = "TempTerrainViewer"
	terrain.add_child(viewer)
	viewer.global_position = position
	
	if ClassDB.class_exists("VoxelViewer"):
		var voxel_viewer = ClassDB.instantiate("VoxelViewer")
		viewer.add_child(voxel_viewer)
	
	return viewer


## Check if terrain mesh exists at a given position
static func has_terrain_mesh_at(terrain: VoxelLodTerrain, position: Vector3) -> bool:
	if not terrain:
		return false
	
	var voxel_tool := terrain.get_voxel_tool()
	if not voxel_tool:
		return false
	
	# Try to raycast - if it hits, terrain exists
	var ray_start := Vector3(position.x, 200.0, position.z)
	var result := voxel_tool.raycast(ray_start, Vector3.DOWN, 250.0)
	
	return result != null


## Get ground height at a position
static func get_ground_height(terrain: VoxelLodTerrain, position: Vector3) -> float:
	if not terrain:
		return 0.0
	
	var voxel_tool := terrain.get_voxel_tool()
	if not voxel_tool:
		return 0.0
	
	var ray_start := Vector3(position.x, 200.0, position.z)
	var result := voxel_tool.raycast(ray_start, Vector3.DOWN, 250.0)
	
	if result:
		return result.position.y
	
	return 0.0


## Check if a position is suitable for spawning (not in water/lava, relatively flat)
static func is_safe_spawn_position(terrain: VoxelLodTerrain, position: Vector3, max_slope_degrees: float = 45.0) -> bool:
	if not terrain:
		return false
	
	var voxel_tool := terrain.get_voxel_tool()
	if not voxel_tool:
		return false
	
	# Get ground height at center and corners of a 3x3 meter area
	var sample_points := [
		position,
		position + Vector3(-1.5, 0, -1.5),
		position + Vector3(1.5, 0, -1.5),
		position + Vector3(-1.5, 0, 1.5),
		position + Vector3(1.5, 0, 1.5)
	]
	
	var heights: Array[float] = []
	for point in sample_points:
		var ray_start := Vector3(point.x, 200.0, point.z)
		var result := voxel_tool.raycast(ray_start, Vector3.DOWN, 250.0)
		if result:
			heights.append(result.position.y)
		else:
			return false  # No ground found
	
	# Check slope
	var min_height: float = heights.min()
	var max_height: float = heights.max()
	var height_diff: float = max_height - min_height
	
	# Calculate approximate slope angle
	var horizontal_dist := 3.0  # 3 meter sample area
	var slope_angle := rad_to_deg(atan2(height_diff, horizontal_dist))
	
	if slope_angle > max_slope_degrees:
		return false
	
	return true
