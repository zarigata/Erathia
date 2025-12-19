extends BaseTool
class_name Pickaxe

@export_group("Pickaxe Settings")
@export var brush_radius: float = 1.8  # Mining radius - larger for more removal
@export var dig_strength: float = 10.0  # Higher strength for more terrain removal
@export var use_smooth_mining: bool = true  # Use sphere brush for smoother edges
@export var post_smooth_passes: int = 2  # Smoothing passes after mining for cleaner edges

# Last hit material for feedback
var last_hit_material_id: int = -1
var last_hit_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	super._ready()
	tool_tier = ToolConstants.ToolTier.STONE


func _get_mining_position(pos: Vector3, hit_normal: Vector3) -> Vector3:
	# Offset slightly into the terrain for better mining results
	return pos - hit_normal * 0.3


func _can_mine_at_position(hit_position: Vector3) -> bool:
	if not TerrainEditSystem:
		return false
	
	var material_id := TerrainEditSystem.get_material_at_position(hit_position)
	last_hit_material_id = material_id
	
	return ToolConstants.can_mine_material(tool_tier, material_id)


func can_mine_material(material_id: int) -> bool:
	return ToolConstants.can_mine_material(tool_tier, material_id)


func get_material_at_position(pos: Vector3) -> int:
	if not TerrainEditSystem:
		return -1
	return TerrainEditSystem.get_material_at_position(pos)


func _use(hit_result: VoxelRaycastResult) -> bool:
	if not TerrainEditSystem:
		push_warning("[Pickaxe] TerrainEditSystem not available")
		tool_use_failed.emit("System error")
		return false
	
	var hit_position := Vector3(hit_result.position)
	var hit_normal := Vector3(hit_result.previous_position - hit_result.position).normalized()
	last_hit_position = hit_position
	
	# Check material hardness
	if not _can_mine_at_position(hit_position):
		var _material_name := ToolConstants.get_material_name(last_hit_material_id)
		var hardness := ToolConstants.get_material_hardness(last_hit_material_id)
		var required_tier := ToolConstants.get_required_tier(hardness)
		var required_tier_name := ToolConstants.get_tier_name(required_tier)
		tool_use_failed.emit("Too hard! Need %s pickaxe" % required_tier_name)
		tool_used.emit(hit_position, false)
		return false
	
	# Consume stamina BEFORE terrain modification
	if not _consume_player_stamina():
		tool_use_failed.emit("Not enough stamina")
		return false
	
	# Calculate mining position (slightly inside terrain for better results)
	var mining_position := _get_mining_position(hit_position, hit_normal)
	
	# Choose brush type based on settings
	var brush_type: int
	if use_smooth_mining:
		brush_type = TerrainEditSystem.BrushType.SPHERE
	else:
		brush_type = TerrainEditSystem.BrushType.BOX
	
	# Apply terrain modification
	TerrainEditSystem.apply_brush(
		mining_position,
		brush_type,
		TerrainEditSystem.Operation.SUBTRACT,
		brush_radius,
		dig_strength,
		tool_tier
	)
	
	# Apply post-mining smoothing to reduce jagged edges
	if post_smooth_passes > 0 and use_smooth_mining:
		for i in range(post_smooth_passes):
			TerrainEditSystem.apply_brush(
				mining_position,
				TerrainEditSystem.BrushType.SPHERE,
				TerrainEditSystem.Operation.SMOOTH,
				brush_radius * 1.2,
				3.0,
				0
			)
	
	# Reduce durability
	_reduce_durability(1)
	
	# Start cooldown
	_start_cooldown()
	
	# Emit success signal
	tool_used.emit(mining_position, true)
	
	return true


func _on_cooldown_complete() -> void:
	# Ready for next swing
	pass
