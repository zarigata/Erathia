extends Node
class_name ToolManager

@export var terrain_edit_distance: float = 10.0

var current_tool: BaseTool = null
var player: CharacterBody3D = null
var blueprint_tool: Blueprint = null
var pre_build_tool: BaseTool = null  # Store tool before build mode
var _in_build_mode: bool = false

# Signals for external feedback systems
signal tool_action_performed(tool: BaseTool, position: Vector3, success: bool)
signal tool_action_failed(tool: BaseTool, reason: String)
signal tool_equipped(tool: BaseTool)
signal tool_unequipped(tool: BaseTool)


func _ready() -> void:
	player = get_parent() as CharacterBody3D
	if not player:
		push_warning("[ToolManager] Parent is not a CharacterBody3D")


func _input(event: InputEvent) -> void:
	# Prevent tool usage when UI is focused or cursor is free
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if get_tree().root.gui_get_focus_owner() != null:
		return
	
	# Block tool usage when in build mode
	if _in_build_mode:
		return
	
	if event.is_action_pressed("terrain_dig") or event.is_action_pressed("tool_primary_use"):
		if use_tool():
			get_viewport().set_input_as_handled()


func equip_tool(tool: BaseTool) -> void:
	if current_tool:
		unequip_tool()
	
	current_tool = tool
	current_tool.set_player(player)
	current_tool.equip()
	
	# Connect tool signals
	if not current_tool.tool_used.is_connected(_on_tool_used):
		current_tool.tool_used.connect(_on_tool_used)
	if not current_tool.tool_use_failed.is_connected(_on_tool_use_failed):
		current_tool.tool_use_failed.connect(_on_tool_use_failed)
	if not current_tool.tool_broken.is_connected(_on_tool_broken):
		current_tool.tool_broken.connect(_on_tool_broken)
	
	tool_equipped.emit(current_tool)


func unequip_tool() -> void:
	if current_tool:
		# Disconnect signals
		if current_tool.tool_used.is_connected(_on_tool_used):
			current_tool.tool_used.disconnect(_on_tool_used)
		if current_tool.tool_use_failed.is_connected(_on_tool_use_failed):
			current_tool.tool_use_failed.disconnect(_on_tool_use_failed)
		if current_tool.tool_broken.is_connected(_on_tool_broken):
			current_tool.tool_broken.disconnect(_on_tool_broken)
		
		current_tool.unequip()
		var old_tool := current_tool
		current_tool = null
		tool_unequipped.emit(old_tool)


func get_current_tool() -> BaseTool:
	return current_tool


func has_tool_equipped() -> bool:
	return current_tool != null


func use_tool() -> bool:
	if not current_tool:
		print("[ToolManager] No tool equipped")
		tool_action_failed.emit(null, "No tool equipped")
		return false
	
	if not TerrainEditSystem:
		print("[ToolManager] TerrainEditSystem not available")
		tool_action_failed.emit(current_tool, "Terrain system unavailable")
		return false
	
	# Get camera from player
	if not player:
		print("[ToolManager] No player available")
		tool_action_failed.emit(current_tool, "No player")
		return false
	var camera: Camera3D = player.get_camera()
	if not camera:
		print("[ToolManager] No camera available")
		tool_action_failed.emit(current_tool, "No camera")
		return false
	
	# Perform raycast
	var hit := TerrainEditSystem.raycast_from_camera(camera, terrain_edit_distance)
	if not hit:
		print("[ToolManager] Raycast missed terrain")
		tool_action_failed.emit(current_tool, "No terrain in range")
		return false
	
	# Use the equipped tool
	var success := current_tool.use(hit)
	if not success:
		print("[ToolManager] Tool use failed (cooldown/stamina/broken)")
		# Note: specific failure reason already emitted by base_tool.use()
	return success


func get_raycast_hit() -> VoxelRaycastResult:
	if not TerrainEditSystem:
		return null
	
	if not player:
		return null
	var camera: Camera3D = player.get_camera()
	if not camera:
		return null
	
	return TerrainEditSystem.raycast_from_camera(camera, terrain_edit_distance)


# Signal handlers
func _on_tool_used(position: Vector3, success: bool) -> void:
	tool_action_performed.emit(current_tool, position, success)


func _on_tool_use_failed(reason: String) -> void:
	tool_action_failed.emit(current_tool, reason)


func _on_tool_broken() -> void:
	push_warning("[ToolManager] Tool broken: %s" % current_tool.name if current_tool else "Unknown")


# ============================================================================
# BUILD MODE INTEGRATION
# ============================================================================

func enter_build_mode() -> void:
	if _in_build_mode:
		return
	
	_in_build_mode = true
	
	# Store current tool before switching to blueprint
	pre_build_tool = current_tool
	
	# Unequip current tool using the helper to properly disconnect signals and emit tool_unequipped
	if current_tool and current_tool != blueprint_tool:
		unequip_tool()
	
	# Equip blueprint tool via equip_tool to ensure proper signal emission and connection
	if blueprint_tool:
		equip_tool(blueprint_tool)


func exit_build_mode() -> void:
	if not _in_build_mode:
		return
	
	_in_build_mode = false
	
	# Unequip blueprint tool
	if blueprint_tool:
		blueprint_tool.unequip()
	
	# Re-equip previous tool if valid
	if pre_build_tool and is_instance_valid(pre_build_tool):
		equip_tool(pre_build_tool)
	
	pre_build_tool = null


func is_in_build_mode() -> bool:
	return _in_build_mode
