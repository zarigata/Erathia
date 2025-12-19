## TerrainEditSystem - Singleton for all voxel terrain editing operations
##
## Usage:
##   var hit = TerrainEditSystem.raycast_from_camera(camera, 10.0)
##   if hit:
##     TerrainEditSystem.apply_brush(hit.position, TerrainEditSystem.BrushType.SPHERE,
##                                    TerrainEditSystem.Operation.SUBTRACT, 2.0, 5.0)
##
## Signals:
##   terrain_edited(position, volume, material_id) - Emitted after successful edit
##
## Notes:
##   - Material data (INDICES channel) is automatically preserved by keeping
##     the VoxelTool locked to CHANNEL_SDF during all edit operations.
##   - Use begin_batch()/end_batch() for multiple edits in a single frame.
extends Node

## Emitted after a successful terrain edit operation
## @param position: World position where the edit occurred
## @param volume: Approximate volume of terrain modified
## @param material_id: Material ID at the edit location (0 if unknown)
## @param operation: Operation type (SUBTRACT, ADD, SMOOTH)
signal terrain_edited(position: Vector3, volume: float, material_id: int, operation: Operation)

## Brush shape types for terrain editing
enum BrushType {
	SPHERE,   ## Spherical brush - smooth, natural-looking edits
	CAPSULE,  ## Capsule brush - elongated sphere, good for tunnels
	BOX       ## Box brush - grid-aligned, sharp edges
}

## Operation modes for terrain modification
enum Operation {
	SUBTRACT, ## Remove terrain (dig/mine)
	ADD,      ## Add terrain (build/fill)
	SMOOTH    ## Smooth terrain surface (multiple passes)
}

## Maximum raycast distance for terrain queries
@export var default_max_raycast_distance: float = 10.0
## Default radius for brush operations
@export var default_brush_radius: float = 2.5
## Default strength for brush operations
@export var default_brush_strength: float = 8.0
## Enable debug visualization of edit operations
@export var enable_debug_visualization: bool = false
## Maximum number of operations allowed in a single batch
@export var batch_operation_limit: int = 100

# Internal references
var _terrain: VoxelLodTerrain = null
var _voxel_tool: VoxelTool = null

# Batch operation state
var _batch_mode: bool = false
var _batch_operations: Array[Dictionary] = []

# Debug visualization
var _debug_mesh_instance: MeshInstance3D = null


func _ready() -> void:
	# Create debug mesh instance for visualization
	if enable_debug_visualization:
		_setup_debug_visualization()


## Sets the active VoxelLodTerrain node for editing operations
## @param terrain: The VoxelLodTerrain node to use for terrain edits
func set_terrain(terrain: VoxelLodTerrain) -> void:
	_terrain = terrain
	_voxel_tool = null  # Force recreation of voxel tool
	
	if _terrain:
		_voxel_tool = _terrain.get_voxel_tool()
		if _voxel_tool:
			_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
			_voxel_tool.set_raycast_binary_search_iterations(4)
			print("[TerrainEditSystem] Terrain set successfully, VoxelTool acquired")
		else:
			push_warning("[TerrainEditSystem] Failed to get VoxelTool from terrain")
	else:
		push_warning("[TerrainEditSystem] Terrain set to null")


## Returns the current terrain reference
func get_terrain() -> VoxelLodTerrain:
	return _terrain


## Performs a raycast from the camera into the terrain
## @param camera: The Camera3D to raycast from
## @param max_distance: Maximum raycast distance (default: default_max_raycast_distance)
## @return: VoxelRaycastResult if hit, null otherwise
func raycast_from_camera(camera: Camera3D, max_distance: float = -1.0) -> VoxelRaycastResult:
	if not _ensure_voxel_tool():
		return null
	
	if not camera:
		push_warning("[TerrainEditSystem] raycast_from_camera called with null camera")
		return null
	
	if max_distance < 0:
		max_distance = default_max_raycast_distance
	
	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z
	
	var result: VoxelRaycastResult = _voxel_tool.raycast(origin, direction, max_distance)
	
	if result and enable_debug_visualization:
		_draw_debug_line(origin, result.position)
	
	return result


## Performs a raycast from an arbitrary origin and direction
## @param origin: World position to start the raycast
## @param direction: Normalized direction vector
## @param max_distance: Maximum raycast distance
## @return: VoxelRaycastResult if hit, null otherwise
func raycast(origin: Vector3, direction: Vector3, max_distance: float = -1.0) -> VoxelRaycastResult:
	if not _ensure_voxel_tool():
		return null
	
	if max_distance < 0:
		max_distance = default_max_raycast_distance
	
	return _voxel_tool.raycast(origin, direction.normalized(), max_distance)


## Applies a brush operation to the terrain at the specified position
## @param hit_position: World position to apply the brush
## @param brush_type: Type of brush shape (BrushType enum)
## @param operation: Type of operation (Operation enum)
## @param radius: Brush radius (default: default_brush_radius)
## @param strength: Brush strength (default: default_brush_strength)
## @param tool_tier: Tool tier for strength scaling (default: 1)
func apply_brush(hit_position: Vector3, brush_type: BrushType, operation: Operation, 
				 radius: float = -1.0, strength: float = -1.0, tool_tier: int = 1) -> void:
	if not _ensure_voxel_tool():
		return
	
	if radius < 0:
		radius = default_brush_radius
	if strength < 0:
		strength = default_brush_strength
	
	# Apply tool tier multiplier
	var tier_multiplier: float = get_strength_multiplier(tool_tier)
	var final_strength: float = strength * tier_multiplier
	
	# If in batch mode, queue the operation
	if _batch_mode:
		if _batch_operations.size() < batch_operation_limit:
			_batch_operations.append({
				"position": hit_position,
				"brush_type": brush_type,
				"operation": operation,
				"radius": radius,
				"strength": final_strength
			})
		else:
			push_warning("[TerrainEditSystem] Batch operation limit reached")
		return
	
	# Execute immediately
	_execute_brush(hit_position, brush_type, operation, radius, final_strength)


## Returns the strength multiplier for a given tool tier
## @param tier: Tool tier (0 = hand, 1 = stone, 2 = iron, 3 = steel, 4+ = magic)
## @return: Strength multiplier value
func get_strength_multiplier(tier: int) -> float:
	match tier:
		0: return 0.5   # Hand
		1: return 1.0   # Stone tools
		2: return 1.5   # Iron tools
		3: return 2.0   # Steel tools
		_: return 3.0 if tier >= 4 else 1.0  # Magic tools or default


## Begins a batch of terrain edit operations
## All operations called after this will be queued until end_batch() is called
func begin_batch() -> void:
	_batch_mode = true
	_batch_operations.clear()


## Ends the batch and executes all queued operations
func end_batch() -> void:
	if not _batch_mode:
		return
	
	_batch_mode = false
	
	for op in _batch_operations:
		_execute_brush(op["position"], op["brush_type"], op["operation"], op["radius"], op["strength"])
	
	_batch_operations.clear()


## Cancels the current batch without executing any operations
func cancel_batch() -> void:
	_batch_mode = false
	_batch_operations.clear()


## Returns the number of operations currently queued in batch mode
func get_batch_count() -> int:
	return _batch_operations.size()


## Gets the material ID at a specific world position
## @param position: World position to query
## @return: Material ID at the position, or -1 if invalid
func get_material_at_position(position: Vector3) -> int:
	if not _ensure_voxel_tool():
		return -1
	
	# Temporarily switch to INDICES channel to read material
	var _original_channel: int = _voxel_tool.channel
	_voxel_tool.channel = VoxelBuffer.CHANNEL_INDICES
	
	var material_id: int = _voxel_tool.get_voxel(position)
	
	# Restore SDF channel
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	
	return material_id


## Gets the SDF value at a specific world position
## @param position: World position to query
## @return: SDF value (positive = solid, negative = air)
func get_sdf_at_position(position: Vector3) -> float:
	if not _ensure_voxel_tool():
		return 0.0
	
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	return _voxel_tool.get_voxel_f(position)


# ============================================================================
# PRIVATE METHODS
# ============================================================================

func _ensure_voxel_tool() -> bool:
	if _voxel_tool:
		# Always ensure we're on the SDF channel
		if _voxel_tool.channel != VoxelBuffer.CHANNEL_SDF:
			push_warning("[TerrainEditSystem] Channel was changed externally, resetting to SDF")
			_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
		return true
	
	if _terrain:
		_voxel_tool = _terrain.get_voxel_tool()
		if _voxel_tool:
			_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
			return true
	
	push_warning("[TerrainEditSystem] No terrain set. Call set_terrain() first.")
	return false


func _execute_brush(position: Vector3, brush_type: BrushType, operation: Operation, 
					radius: float, strength: float) -> void:
	# Ensure SDF channel before any edit
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	
	# Get material before edit for signal
	var material_id: int = get_material_at_position(position)
	
	# Ensure we're back on SDF after material query
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	
	match brush_type:
		BrushType.SPHERE:
			_apply_sphere_brush(position, operation, radius, strength)
		BrushType.CAPSULE:
			_apply_capsule_brush(position, operation, radius, strength)
		BrushType.BOX:
			_apply_box_brush(position, operation, radius, strength)
	
	# Calculate approximate volume for signal
	var volume: float = _calculate_brush_volume(brush_type, radius)
	
	# Emit signal for MiningSystem integration (includes operation type)
	terrain_edited.emit(position, volume, material_id, operation)
	
	# Debug visualization
	if enable_debug_visualization:
		_draw_debug_sphere(position, radius)


func _apply_sphere_brush(center: Vector3, operation: Operation, radius: float, strength: float) -> void:
	# grow_sphere: positive = expand solid (add terrain), negative = shrink solid (remove terrain)
	match operation:
		Operation.SUBTRACT:
			# Negative strength = shrink/remove terrain (mining/digging)
			_voxel_tool.grow_sphere(center, radius, -strength)
		Operation.ADD:
			# Positive strength = expand/add terrain (building)
			_voxel_tool.grow_sphere(center, radius, strength)
		Operation.SMOOTH:
			# Apply smoothing pass
			_voxel_tool.smooth_sphere(center, radius, strength * 0.5)


func _apply_capsule_brush(center: Vector3, operation: Operation, radius: float, strength: float) -> void:
	# Approximate capsule as series of overlapping spheres along vertical axis
	var capsule_length: float = radius * 2.0
	var sphere_count: int = maxi(3, int(capsule_length / radius))
	var step: float = capsule_length / float(sphere_count - 1)
	
	# Default to vertical capsule, could be extended to use hit normal
	var direction: Vector3 = Vector3.UP
	var start_pos: Vector3 = center - direction * (capsule_length * 0.5)
	
	for i in range(sphere_count):
		var sphere_pos: Vector3 = start_pos + direction * (step * i)
		_apply_sphere_brush(sphere_pos, operation, radius * 0.8, strength)


func _apply_box_brush(center: Vector3, operation: Operation, radius: float, strength: float) -> void:
	# Snap to voxel grid
	var half_size: Vector3 = Vector3.ONE * radius
	var min_pos: Vector3 = (center - half_size).floor()
	var max_pos: Vector3 = (center + half_size).ceil()
	
	match operation:
		Operation.SUBTRACT:
			_voxel_tool.mode = VoxelTool.MODE_REMOVE
			_voxel_tool.do_box(min_pos, max_pos)
		Operation.ADD:
			_voxel_tool.mode = VoxelTool.MODE_ADD
			_voxel_tool.do_box(min_pos, max_pos)
		Operation.SMOOTH:
			# Box doesn't support smooth directly, use sphere approximation
			_voxel_tool.smooth_sphere(center, radius, strength * 0.3)
	
	# Reset mode
	_voxel_tool.mode = VoxelTool.MODE_REMOVE


func _calculate_brush_volume(brush_type: BrushType, radius: float) -> float:
	match brush_type:
		BrushType.SPHERE:
			return (4.0 / 3.0) * PI * pow(radius, 3)
		BrushType.CAPSULE:
			# Approximate: sphere + cylinder
			var sphere_vol: float = (4.0 / 3.0) * PI * pow(radius * 0.8, 3)
			var cylinder_vol: float = PI * pow(radius * 0.8, 2) * radius * 2.0
			return sphere_vol + cylinder_vol
		BrushType.BOX:
			return pow(radius * 2.0, 3)
		_:
			return 0.0


func _setup_debug_visualization() -> void:
	_debug_mesh_instance = MeshInstance3D.new()
	_debug_mesh_instance.name = "TerrainEditDebug"
	add_child(_debug_mesh_instance)


func _draw_debug_line(from: Vector3, to: Vector3) -> void:
	if not enable_debug_visualization or not _debug_mesh_instance:
		return
	
	var immediate_mesh := ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(from)
	immediate_mesh.surface_add_vertex(to)
	immediate_mesh.surface_end()
	
	_debug_mesh_instance.mesh = immediate_mesh
	
	# Clear after short delay
	get_tree().create_timer(0.1).timeout.connect(func(): 
		if _debug_mesh_instance:
			_debug_mesh_instance.mesh = null
	)


func _draw_debug_sphere(center: Vector3, radius: float) -> void:
	if not enable_debug_visualization:
		return
	
	# Create temporary sphere visualization
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = sphere_mesh
	mesh_instance.global_position = center
	
	# Semi-transparent material
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.0, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	
	get_tree().root.add_child(mesh_instance)
	
	# Remove after short delay
	get_tree().create_timer(0.5).timeout.connect(func():
		mesh_instance.queue_free()
	)
