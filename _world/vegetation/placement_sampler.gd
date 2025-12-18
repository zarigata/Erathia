extends RefCounted
class_name PlacementSampler
## Noise-Based Vegetation Placement Sampler
##
## Samples terrain surface points and determines valid placement locations
## using noise-based distribution and constraint checking.

# =============================================================================
# CONSTANTS
# =============================================================================

# Grid spacing per vegetation type (in meters)
const GRID_SPACING: Dictionary = {
	VegetationManager.VegetationType.TREE: 4.0,
	VegetationManager.VegetationType.BUSH: 2.0,
	VegetationManager.VegetationType.ROCK_SMALL: 3.0,
	VegetationManager.VegetationType.ROCK_MEDIUM: 6.0,
	VegetationManager.VegetationType.GRASS_TUFT: 1.0
}

# Noise frequency per vegetation type
const NOISE_FREQUENCY: Dictionary = {
	VegetationManager.VegetationType.TREE: 0.05,
	VegetationManager.VegetationType.BUSH: 0.1,
	VegetationManager.VegetationType.ROCK_SMALL: 0.08,
	VegetationManager.VegetationType.ROCK_MEDIUM: 0.06,
	VegetationManager.VegetationType.GRASS_TUFT: 0.2
}

# Minimum distance between same-type instances
const MIN_DISTANCE: Dictionary = {
	VegetationManager.VegetationType.TREE: 3.0,
	VegetationManager.VegetationType.BUSH: 1.0,
	VegetationManager.VegetationType.ROCK_SMALL: 1.5,
	VegetationManager.VegetationType.ROCK_MEDIUM: 4.0,
	VegetationManager.VegetationType.GRASS_TUFT: 0.3
}

# =============================================================================
# STATE
# =============================================================================

var _placement_noise: FastNoiseLite
var _variation_noise: FastNoiseLite
var _world_seed: int = 12345

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(seed_value: int = 12345) -> void:
	_world_seed = seed_value
	
	_placement_noise = FastNoiseLite.new()
	_placement_noise.seed = seed_value
	_placement_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_placement_noise.frequency = 0.1
	
	_variation_noise = FastNoiseLite.new()
	_variation_noise.seed = seed_value + 1000
	_variation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_variation_noise.frequency = 0.5


# =============================================================================
# PUBLIC API
# =============================================================================

## Sample placement positions for a chunk
## Returns array of dictionaries with position, transform, type, variant
func sample_chunk(
	chunk_origin: Vector3i,
	chunk_size: int,
	biome_id: int,
	terrain: Node,  # VoxelLodTerrain
	rules: Dictionary
) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	var veg_types: Array = rules.get("types", [])
	var slope_max: float = rules.get("slope_max", 45.0)
	var height_range: Dictionary = rules.get("height_range", {"min": -100, "max": 300})
	
	if veg_types.is_empty():
		return placements
	
	# Get VoxelTool for terrain queries
	var voxel_tool: VoxelTool = null
	if terrain and terrain.has_method("get_voxel_tool"):
		voxel_tool = terrain.get_voxel_tool()
	
	# Process each vegetation type
	for veg_type_data: Dictionary in veg_types:
		var veg_type: int = veg_type_data.get("type", VegetationManager.VegetationType.BUSH)
		var density: float = VegetationManager.get_effective_density(biome_id, veg_type_data)
		var variants: Array = veg_type_data.get("variants", [])
		
		if variants.is_empty() or density <= 0.0:
			continue
		
		var grid_spacing: float = GRID_SPACING.get(veg_type, 2.0)
		var noise_freq: float = NOISE_FREQUENCY.get(veg_type, 0.1)
		var min_dist: float = MIN_DISTANCE.get(veg_type, 1.0)
		
		# Configure noise for this type
		_placement_noise.frequency = noise_freq
		_placement_noise.seed = _world_seed + veg_type * 1000
		
		# Sample grid within chunk
		var type_placements := _sample_grid_for_type(
			chunk_origin,
			chunk_size,
			veg_type,
			density,
			grid_spacing,
			min_dist,
			variants,
			slope_max,
			height_range,
			voxel_tool,
			biome_id
		)
		
		placements.append_array(type_placements)
	
	return placements


## Check if a single position is valid for placement
func check_placement_valid(
	position: Vector3,
	normal: Vector3,
	slope_max: float,
	height_range: Dictionary
) -> bool:
	# Height check
	var min_height: float = height_range.get("min", -100)
	var max_height: float = height_range.get("max", 300)
	if position.y < min_height or position.y > max_height:
		return false
	
	# Slope check (normal.y = cos of angle from vertical)
	var slope_angle := rad_to_deg(acos(clampf(normal.y, 0.0, 1.0)))
	if slope_angle > slope_max:
		return false
	
	return true


## Get surface position and normal at a world XZ coordinate
func get_surface_info(voxel_tool: VoxelTool, world_x: float, world_z: float, search_height: float = 200.0) -> Dictionary:
	if voxel_tool == null:
		return {}
	
	# Raycast from above to find surface
	var ray_origin := Vector3(world_x, search_height, world_z)
	var ray_dir := Vector3.DOWN
	var max_distance := search_height + 100.0
	
	var result: VoxelRaycastResult = voxel_tool.raycast(ray_origin, ray_dir, max_distance)
	
	if result == null:
		return {}
	
	var hit_pos: Vector3 = result.position
	# VoxelRaycastResult doesn't provide normal directly, estimate from SDF gradient
	var hit_normal: Vector3 = _estimate_normal(voxel_tool, hit_pos)
	
	return {
		"position": hit_pos,
		"normal": hit_normal
	}


# =============================================================================
# INTERNAL HELPERS
# =============================================================================

func _sample_grid_for_type(
	chunk_origin: Vector3i,
	chunk_size: int,
	veg_type: int,
	density: float,
	grid_spacing: float,
	min_dist: float,
	variants: Array,
	slope_max: float,
	height_range: Dictionary,
	voxel_tool: VoxelTool,
	biome_id: int
) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	var placed_positions: Array[Vector3] = []
	
	var steps_x := int(chunk_size / grid_spacing)
	var steps_z := int(chunk_size / grid_spacing)
	
	for gx in range(steps_x):
		for gz in range(steps_z):
			var world_x := chunk_origin.x + gx * grid_spacing
			var world_z := chunk_origin.z + gz * grid_spacing
			
			# Add jitter
			var jitter_x := _variation_noise.get_noise_2d(world_x * 0.5, world_z * 0.5) * grid_spacing * 0.4
			var jitter_z := _variation_noise.get_noise_2d(world_x * 0.5 + 100, world_z * 0.5 + 100) * grid_spacing * 0.4
			world_x += jitter_x
			world_z += jitter_z
			
			# Noise threshold check
			var noise_val := _placement_noise.get_noise_2d(world_x, world_z)
			noise_val = (noise_val + 1.0) * 0.5  # Normalize to 0-1
			
			var threshold := 1.0 - density
			if noise_val < threshold:
				continue
			
			# Get surface info
			var surface_info := get_surface_info(voxel_tool, world_x, world_z)
			if surface_info.is_empty():
				continue
			
			var surface_pos: Vector3 = surface_info["position"]
			var surface_normal: Vector3 = surface_info["normal"]
			
			# Validate placement
			if not check_placement_valid(surface_pos, surface_normal, slope_max, height_range):
				continue
			
			# Check minimum distance from other placements of same type
			var too_close := false
			for existing_pos: Vector3 in placed_positions:
				if existing_pos.distance_to(surface_pos) < min_dist:
					too_close = true
					break
			
			if too_close:
				continue
			
			# Check against global vegetation manager
			if VegetationManager.has_vegetation_near(surface_pos, min_dist * 0.5):
				continue
			
			# Select variant
			var variant_idx := int(abs(_variation_noise.get_noise_2d(world_x * 2, world_z * 2)) * variants.size()) % variants.size()
			var variant: String = variants[variant_idx]
			
			# Generate transform
			var transform := _generate_transform(surface_pos, surface_normal, veg_type)
			
			# Generate seed for mesh variation
			var instance_seed := int(world_x * 1000 + world_z) & 0x7FFFFFFF
			
			placements.append({
				"position": surface_pos,
				"normal": surface_normal,
				"transform": transform,
				"type": veg_type,
				"variant": variant,
				"biome_id": biome_id,
				"seed": instance_seed
			})
			
			placed_positions.append(surface_pos)
	
	return placements


func _generate_transform(position: Vector3, normal: Vector3, veg_type: int) -> Transform3D:
	var transform := Transform3D.IDENTITY
	
	# Position
	transform.origin = position
	
	# Random Y rotation
	var y_rotation := _variation_noise.get_noise_2d(position.x * 3, position.z * 3) * TAU
	transform = transform.rotated(Vector3.UP, y_rotation)
	
	# Scale variation
	var scale_var := 0.8 + _variation_noise.get_noise_2d(position.x * 5, position.z * 5) * 0.4
	transform = transform.scaled(Vector3.ONE * scale_var)
	
	# Slight tilt to match terrain (for non-trees)
	if veg_type != VegetationManager.VegetationType.TREE:
		if normal != Vector3.UP and normal.y > 0.7:
			var tilt_axis := Vector3.UP.cross(normal).normalized()
			var tilt_angle := acos(clampf(normal.y, -1.0, 1.0)) * 0.3  # Partial tilt
			if tilt_axis.length() > 0.01:
				transform = transform.rotated(tilt_axis, tilt_angle)
	
	return transform


func _estimate_normal(voxel_tool: VoxelTool, position: Vector3) -> Vector3:
	# Estimate normal from SDF gradient
	var epsilon := 0.5
	
	var dx := voxel_tool.get_voxel_f(position + Vector3(epsilon, 0, 0)) - voxel_tool.get_voxel_f(position - Vector3(epsilon, 0, 0))
	var dy := voxel_tool.get_voxel_f(position + Vector3(0, epsilon, 0)) - voxel_tool.get_voxel_f(position - Vector3(0, epsilon, 0))
	var dz := voxel_tool.get_voxel_f(position + Vector3(0, 0, epsilon)) - voxel_tool.get_voxel_f(position - Vector3(0, 0, epsilon))
	
	var gradient := Vector3(dx, dy, dz)
	if gradient.length() < 0.001:
		return Vector3.UP
	
	return gradient.normalized()
