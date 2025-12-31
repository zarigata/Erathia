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
	VegetationManager.VegetationType.TREE: 2.0,
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
var _gpu_dispatcher: GPUVegetationDispatcher
var _terrain_dispatcher: BiomeMapGPUDispatcher
var _use_gpu: bool = true

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
	
	_gpu_dispatcher = GPUVegetationDispatcher.new()
	_use_gpu = _gpu_dispatcher.is_ready()


func set_terrain_dispatcher(dispatcher: BiomeMapGPUDispatcher) -> void:
	"""Provide reference to terrain GPU dispatcher for SDF texture access."""
	_terrain_dispatcher = dispatcher
	if _gpu_dispatcher:
		_gpu_dispatcher.set_terrain_dispatcher(dispatcher)


func is_using_gpu() -> bool:
	"""Returns true if GPU dispatcher is active and ready."""
	return _use_gpu and _gpu_dispatcher != null and _gpu_dispatcher.is_ready() and _terrain_dispatcher != null


func force_cpu_mode() -> void:
	"""Disable GPU and use CPU fallback."""
	_use_gpu = false
	print("[PlacementSampler] Forced to CPU mode")


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
	var slope_max: float = rules.get("slope_max", 30.0)
	var height_range: Dictionary = rules.get("height_range", {"min": -50, "max": 200})
	
	if veg_types.is_empty():
		return placements

	var gpu_available := is_using_gpu()
	
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
		
		if gpu_available:
			var gpu_results := _gpu_dispatcher.generate_placements(
				chunk_origin,
				veg_type,
				density,
				grid_spacing,
				noise_freq,
				slope_max,
				height_range,
				_world_seed,
				_terrain_dispatcher.get_biome_map_texture()
			)
			
			var placed_gpu_positions: Array[Vector3] = []
			for gpu_data: Dictionary in gpu_results:
				var surface_pos: Vector3 = gpu_data.get("position", Vector3.ZERO)
				
				var too_close := false
				for existing_pos: Vector3 in placed_gpu_positions:
					if existing_pos.distance_to(surface_pos) < min_dist:
						too_close = true
						break
				
				if too_close:
					continue
				
				if VegetationManager.has_vegetation_near(surface_pos, min_dist * 0.5):
					continue
				
				var placement_dict := _convert_gpu_placement_to_dict(
					gpu_data,
					veg_type,
					variants,
					biome_id
				)
				if not placement_dict.is_empty():
					placements.append(placement_dict)
					placed_gpu_positions.append(surface_pos)
		else:
			# CPU fallback path
			var voxel_tool: VoxelTool = null
			if terrain and terrain.has_method("get_voxel_tool"):
				voxel_tool = terrain.get_voxel_tool()
			
			if voxel_tool == null:
				push_warning("[PlacementSampler] No VoxelTool available for chunk %s" % chunk_origin)
				return placements
			
			# Configure noise for this type
			_placement_noise.frequency = noise_freq
			_placement_noise.seed = _world_seed + veg_type * 1000
			
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
func get_surface_info(voxel_tool: VoxelTool, world_x: float, world_z: float, search_height: float = 300.0) -> Dictionary:
	if voxel_tool == null:
		return {}
	
	# SDF convention in this project: NEGATIVE = solid, POSITIVE = air
	# Look for sign change from positive (air) to negative (solid) going DOWN
	var sample_step: float = 2.0
	var prev_sdf: float = 100.0  # Start assuming we're in air (positive)
	
	for h in range(int(search_height), -50, -int(sample_step)):
		var sample_pos := Vector3(world_x, float(h), world_z)
		var sdf: float = voxel_tool.get_voxel_f(sample_pos)
		
		# Surface is where SDF crosses from positive (air) to negative (solid)
		if prev_sdf > 0.0 and sdf <= 0.0:
			# Found surface - interpolate for better accuracy
			var t: float = prev_sdf / (prev_sdf - sdf + 0.001)
			var surface_y: float = float(h) + sample_step * (1.0 - t)
			var surface_pos := Vector3(world_x, surface_y, world_z)
			return {
				"position": surface_pos,
				"normal": Vector3.UP
			}
		prev_sdf = sdf
	
	# If SDF search failed, try direct raycast as fallback
	var ray_origin := Vector3(world_x, search_height, world_z)
	var result: VoxelRaycastResult = voxel_tool.raycast(ray_origin, Vector3.DOWN, search_height + 100.0)
	
	if result != null:
		return {
			"position": result.position,
			"normal": Vector3.UP
		}
	
	return {}


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


func _generate_transform_from_gpu_data(
	position: Vector3,
	normal: Vector3,
	rotation_y: float,
	scale: float,
	veg_type: int
) -> Transform3D:
	var transform := Transform3D.IDENTITY
	transform.origin = position
	transform = transform.rotated(Vector3.UP, rotation_y)
	transform = transform.scaled(Vector3.ONE * scale)
	
	if veg_type != VegetationManager.VegetationType.TREE:
		if normal != Vector3.UP and normal.y > 0.7:
			var tilt_axis := Vector3.UP.cross(normal).normalized()
			var tilt_angle := acos(clampf(normal.y, -1.0, 1.0)) * 0.3
			if tilt_axis.length() > 0.01:
				transform = transform.rotated(tilt_axis, tilt_angle)
	
	return transform


func _convert_gpu_placement_to_dict(
	gpu_data: Dictionary,
	veg_type: int,
	variants: Array,
	biome_id: int
) -> Dictionary:
	"""Map GPU placement payload to CPU placement dictionary structure."""
	# Convert GPU placement payload into the dictionary shape expected by CPU consumers.
	if gpu_data.is_empty():
		return {}
	
	var position: Vector3 = gpu_data.get("position", Vector3.ZERO)
	var normal: Vector3 = gpu_data.get("normal", Vector3.UP)
	var rotation_y: float = gpu_data.get("rotation_y", 0.0)
	var scale: float = gpu_data.get("scale", 1.0)
	var variant_index: int = gpu_data.get("variant_index", 0)
	var instance_seed: int = gpu_data.get("instance_seed", 0)
	
	if variants.is_empty():
		return {}
	
	var safe_variant_index: int = clampi(variant_index, 0, variants.size() - 1)
	var variant: String = variants[safe_variant_index]
	
	var transform := _generate_transform_from_gpu_data(
		position,
		normal,
		rotation_y,
		scale,
		veg_type
	)
	
	return {
		"position": position,
		"normal": normal,
		"transform": transform,
		"type": veg_type,
		"variant": variant,
		"biome_id": biome_id,
		"seed": instance_seed
	}


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
