extends BaseTool
class_name Shovel

@export_group("Shovel Settings")
@export var sphere_radius: float = 2.0  # Larger radius for smoother digging
@export var dig_strength: float = 8.0  # Higher strength for more terrain removal
@export var smooth_mode: bool = false  # Toggle between dig and smooth operations
@export var post_smooth_passes: int = 2  # Smoothing passes after digging

# Last hit material for feedback
var last_hit_material_id: int = -1
var last_hit_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	super._ready()
	tool_tier = ToolConstants.ToolTier.HAND
	cooldown_duration = 0.3  # Faster than pickaxe
	stamina_cost_per_use = 7.0  # Lower than pickaxe
	durability_max = 150  # Higher durability for soft material work
	current_durability = durability_max


func _can_dig_at_position(hit_position: Vector3) -> bool:
	if not TerrainEditSystem:
		return false
	
	var material_id := TerrainEditSystem.get_material_at_position(hit_position)
	last_hit_material_id = material_id
	
	return can_dig_material(material_id)


func can_dig_material(material_id: int) -> bool:
	var hardness := ToolConstants.get_material_hardness(material_id)
	# Shovel can only dig SOFT or NONE (air) materials
	return hardness <= ToolConstants.Hardness.SOFT


func get_material_at_position(pos: Vector3) -> int:
	if not TerrainEditSystem:
		return -1
	return TerrainEditSystem.get_material_at_position(pos)


func _use(hit_result: VoxelRaycastResult) -> bool:
	if not TerrainEditSystem:
		push_warning("[Shovel] TerrainEditSystem not available")
		tool_use_failed.emit("System error")
		return false
	
	var hit_position := Vector3(hit_result.position)
	last_hit_position = hit_position
	
	# Check material hardness - shovel only works on soft materials
	if not _can_dig_at_position(hit_position):
		var _material_name := ToolConstants.get_material_name(last_hit_material_id)
		tool_use_failed.emit("Can only dig soft materials (dirt, sand)")
		tool_used.emit(hit_position, false)
		return false
	
	# Consume stamina BEFORE terrain modification
	if not _consume_player_stamina():
		tool_use_failed.emit("Not enough stamina")
		return false
	
	# Determine operation type based on mode
	var operation: int
	if smooth_mode:
		operation = TerrainEditSystem.Operation.SMOOTH
	else:
		operation = TerrainEditSystem.Operation.SUBTRACT
	
	# Apply terrain modification using SPHERE brush (no grid snapping for smooth results)
	TerrainEditSystem.apply_brush(
		hit_position,
		TerrainEditSystem.BrushType.SPHERE,
		operation,
		sphere_radius,
		dig_strength,
		tool_tier
	)
	
	# Apply post-dig smoothing to reduce jagged edges (only for SUBTRACT operations)
	if operation == TerrainEditSystem.Operation.SUBTRACT and post_smooth_passes > 0:
		for i in range(post_smooth_passes):
			TerrainEditSystem.apply_brush(
				hit_position,
				TerrainEditSystem.BrushType.SPHERE,
				TerrainEditSystem.Operation.SMOOTH,
				sphere_radius * 1.2,
				3.0,
				0
			)
	
	# Reduce durability
	_reduce_durability(1)
	
	# Start cooldown
	_start_cooldown()
	
	# Emit success signal
	tool_used.emit(hit_position, true)
	
	return true


func toggle_smooth_mode() -> void:
	smooth_mode = not smooth_mode
	var mode_name := "Smooth" if smooth_mode else "Dig"
	print("[Shovel] Mode switched to: %s" % mode_name)


func _on_cooldown_complete() -> void:
	# Ready for next dig
	pass
