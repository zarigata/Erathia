class_name Hoe
extends BaseTool

## Hoe Tool - Universal terrain flattening tool (no tiers).
## Flattens terrain to a target height within a radius around the hit point.

@export var brush_radius: float = 3.0
@export var flatten_strength: float = 8.0
@export var sample_points: int = 9  # Number of points to sample for average height


func _ready() -> void:
	super._ready()
	# Hoe has no tier system (universal tool)
	tool_tier = 0
	# No durability (infinite uses)
	durability_max = -1
	# Stamina cost per use
	stamina_cost_per_use = 10.0
	cooldown_duration = 0.3


func _can_use() -> bool:
	if is_on_cooldown():
		return false
	# Hoe never breaks
	if not _has_stamina():
		return false
	return true


func _use(hit_result: VoxelRaycastResult) -> bool:
	if not hit_result:
		return false
	
	if not TerrainEditSystem:
		push_warning("[Hoe] TerrainEditSystem not available")
		return false
	
	# Consume stamina
	if not _consume_player_stamina():
		tool_use_failed.emit("Not enough stamina")
		return false
	
	# Apply flatten operation at hit position
	var hit_position := Vector3(hit_result.position)
	
	# Sample average height within the brush radius to determine target height
	var target_height := _sample_average_height(hit_position)
	
	# Apply flatten operation to level terrain to the target height
	_apply_flatten(hit_position, target_height)
	
	_start_cooldown()
	tool_used.emit(hit_position, true)
	
	return true


## Samples terrain heights within the brush radius and returns the average
func _sample_average_height(center: Vector3) -> float:
	var total_height: float = 0.0
	var valid_samples: int = 0
	
	# Sample in a grid pattern within the brush radius
	var samples_per_axis: int = int(sqrt(sample_points))
	var step: float = (brush_radius * 2.0) / float(samples_per_axis)
	
	for x in range(samples_per_axis):
		for z in range(samples_per_axis):
			var offset_x: float = -brush_radius + step * (x + 0.5)
			var offset_z: float = -brush_radius + step * (z + 0.5)
			var sample_pos := Vector3(center.x + offset_x, center.y + 10.0, center.z + offset_z)
			
			# Raycast downward to find terrain surface
			var hit := TerrainEditSystem.raycast(sample_pos, Vector3.DOWN, 20.0)
			if hit:
				total_height += hit.position.y
				valid_samples += 1
	
	if valid_samples > 0:
		return total_height / float(valid_samples)
	else:
		return center.y


## Applies a flatten/level operation to bring terrain to the target height
func _apply_flatten(center: Vector3, target_height: float) -> void:
	# Sample points within the brush and adjust terrain to target height
	var samples_per_axis: int = int(sqrt(sample_points)) + 2  # More points for actual flattening
	var step: float = (brush_radius * 2.0) / float(samples_per_axis)
	
	TerrainEditSystem.begin_batch()
	
	for x in range(samples_per_axis):
		for z in range(samples_per_axis):
			var offset_x: float = -brush_radius + step * (x + 0.5)
			var offset_z: float = -brush_radius + step * (z + 0.5)
			
			# Check if point is within circular brush radius
			var dist_sq: float = offset_x * offset_x + offset_z * offset_z
			if dist_sq > brush_radius * brush_radius:
				continue
			
			var sample_pos := Vector3(center.x + offset_x, center.y + 10.0, center.z + offset_z)
			
			# Raycast downward to find current terrain height
			var hit := TerrainEditSystem.raycast(sample_pos, Vector3.DOWN, 20.0)
			if not hit:
				continue
			
			var current_height: float = hit.position.y
			var height_diff: float = current_height - target_height
			
			# Apply smooth falloff based on distance from center
			var dist: float = sqrt(dist_sq)
			var falloff: float = 1.0 - (dist / brush_radius)
			falloff = falloff * falloff  # Quadratic falloff for smoother edges
			
			var edit_pos := Vector3(center.x + offset_x, target_height, center.z + offset_z)
			var edit_strength: float = abs(height_diff) * falloff * flatten_strength * 0.1
			
			if height_diff > 0.1:  # Terrain is above target - remove
				TerrainEditSystem.apply_brush(
					edit_pos,
					TerrainEditSystem.BrushType.SPHERE,
					TerrainEditSystem.Operation.SUBTRACT,
					step * 0.6,
					edit_strength,
					0
				)
			elif height_diff < -0.1:  # Terrain is below target - add
				TerrainEditSystem.apply_brush(
					edit_pos,
					TerrainEditSystem.BrushType.SPHERE,
					TerrainEditSystem.Operation.ADD,
					step * 0.6,
					edit_strength,
					0
				)
	
	TerrainEditSystem.end_batch()


func is_broken() -> bool:
	# Hoe never breaks
	return false


func get_durability_percent() -> float:
	# Always full durability
	return 1.0


func _reduce_durability(_amount: int = 1) -> void:
	# Hoe has infinite durability - do nothing
	pass
