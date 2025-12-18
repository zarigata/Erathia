extends BaseTool
class_name Pickaxe

@export_group("Pickaxe Settings")
@export var box_radius: float = 1.0  # 2x2x2 voxel removal
@export var grid_snap_size: float = 1.0
@export var dig_strength: float = 5.0

# Last hit material for feedback
var last_hit_material_id: int = -1
var last_hit_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	super._ready()
	tool_tier = ToolConstants.ToolTier.STONE


func _snap_to_grid(pos: Vector3) -> Vector3:
	return (pos / grid_snap_size).floor() * grid_snap_size + Vector3(grid_snap_size * 0.5, grid_snap_size * 0.5, grid_snap_size * 0.5)


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
	
	# Snap position to grid for BOX brush
	var snapped_position := _snap_to_grid(hit_position)
	
	# Apply terrain modification using BOX brush
	TerrainEditSystem.apply_brush(
		snapped_position,
		TerrainEditSystem.BrushType.BOX,
		TerrainEditSystem.Operation.SUBTRACT,
		box_radius,
		dig_strength,
		tool_tier
	)
	
	# Reduce durability
	_reduce_durability(1)
	
	# Start cooldown
	_start_cooldown()
	
	# Emit success signal
	tool_used.emit(snapped_position, true)
	
	return true


func _on_cooldown_complete() -> void:
	# Ready for next swing
	pass
