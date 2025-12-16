class_name TerrainTool
extends Node3D
## Terrain editing tool for custom chunk-based SDF terrain.
## Uses RayCast3D for hit detection and TerrainManager.modify_terrain for deformation.

@export var max_reach: float = 6.0
@export var dig_radius: float = 2.5
@export var build_radius: float = 2.5
@export var dig_amount: float = -50.0
@export var build_amount: float = 50.0
@export var mining_cooldown: float = 0.2

## Internal references
var _camera: Camera3D
var _terrain_manager: TerrainManager
var _raycast: RayCast3D
var _cooldown_timer: float = 0.0

## Current tool type (uses MiningSystem.ToolType)
var current_tool: int = MiningSystem.ToolType.PICKAXE
var current_tier: int = MiningSystem.ToolTier.STONE

signal terrain_modified(position: Vector3, is_digging: bool)
signal hit_nothing()
signal material_mined(material_id: int, position: Vector3)


func _ready() -> void:
	_setup_raycast()
	call_deferred("_find_references")


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func _setup_raycast() -> void:
	_raycast = RayCast3D.new()
	_raycast.enabled = true
	_raycast.exclude_parent = true
	_raycast.target_position = Vector3(0, 0, -max_reach)
	_raycast.collision_mask = 1  # Terrain layer
	add_child(_raycast)


func _find_references() -> void:
	# Find camera - traverse up to find player, then get camera
	if _camera == null:
		var parent: Node = get_parent()
		while parent != null:
			if parent is CharacterBody3D:
				_camera = parent.get_node_or_null("Camera3D") as Camera3D
				break
			if parent is Camera3D:
				_camera = parent as Camera3D
				break
			parent = parent.get_parent()
	
	if _camera == null:
		push_warning("TerrainTool: Could not find Camera3D!")
	
	# Find TerrainManager
	if _terrain_manager == null:
		var root: Node = get_tree().root
		_terrain_manager = root.find_child("TerrainManager", true, false) as TerrainManager
		if _terrain_manager == null:
			push_warning("TerrainTool: Could not find TerrainManager in scene tree!")


func _input(event: InputEvent) -> void:
	# Only process when mouse is captured (gameplay mode)
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	
	if _terrain_manager == null:
		return
	
	if _cooldown_timer > 0.0:
		return
	
	# Tool switching
	if event.is_action_pressed("equip_1"):
		current_tool = MiningSystem.ToolType.PICKAXE
	elif event.is_action_pressed("equip_2"):
		current_tool = MiningSystem.ToolType.SHOVEL
	elif event.is_action_pressed("equip_3"):
		current_tool = MiningSystem.ToolType.HOE
	
	# Primary action (dig) - Left Click
	if event.is_action_pressed("attack"):
		_perform_terrain_edit(true)
		_cooldown_timer = mining_cooldown
	
	# Secondary action (build) - Right Click
	elif event.is_action_pressed("use"):
		_perform_terrain_edit(false)
		_cooldown_timer = mining_cooldown


func _perform_terrain_edit(is_digging: bool) -> void:
	if not _raycast.is_colliding():
		hit_nothing.emit()
		return
	
	var hit_point: Vector3 = _raycast.get_collision_point()
	var hit_normal: Vector3 = _raycast.get_collision_normal()
	
	if is_digging:
		_handle_dig(hit_point, hit_normal)
	else:
		_handle_build(hit_point, hit_normal)


func _handle_dig(hit_point: Vector3, hit_normal: Vector3) -> void:
	# Offset into terrain for digging
	var dig_point: Vector3 = hit_point - hit_normal * 0.5
	
	# Check material and tool compatibility
	var mat_id: int = _terrain_manager.get_material_at(dig_point)
	var hardness: float = MiningSystem.get_material_hardness(mat_id)
	var best_tool: int = MiningSystem.get_preferred_tool(mat_id)
	var power: float = MiningSystem.get_tool_power(current_tier)
	
	# Calculate effective dig amount
	var amount: float = dig_amount * power
	
	# Bonus for correct tool
	if current_tool == best_tool:
		amount *= 2.0
	
	# Hardness reduction
	if hardness > 0:
		amount /= (hardness / 10.0)
	
	# Special tool behaviors
	if current_tool == MiningSystem.ToolType.HOE or current_tool == MiningSystem.ToolType.STAFF:
		# Smoothing mode
		if _terrain_manager.has_method("smooth_terrain"):
			_terrain_manager.smooth_terrain(hit_point, dig_radius)
		return
	
	# Apply terrain modification
	_terrain_manager.modify_terrain(dig_point, amount)
	terrain_modified.emit(dig_point, true)
	
	# Loot logic
	if mat_id != MiningSystem.MaterialID.AIR:
		material_mined.emit(mat_id, dig_point)
		var loot: String = MiningSystem.get_loot_item(mat_id)
		if loot != "":
			var remainder: int = InventoryManager.add_item(loot, 1)
			if remainder == 0:
				print("Mined: ", loot)


func _handle_build(hit_point: Vector3, hit_normal: Vector3) -> void:
	# Offset outside terrain for building
	var build_point: Vector3 = hit_point + hit_normal * 0.5
	
	# Special tool behaviors
	if current_tool == MiningSystem.ToolType.HOE or current_tool == MiningSystem.ToolType.STAFF:
		# Flatten mode
		if _terrain_manager.has_method("flatten_terrain"):
			_terrain_manager.flatten_terrain(hit_point, build_radius, hit_point.y)
		return
	
	# Apply terrain modification (add material)
	_terrain_manager.modify_terrain(build_point, build_amount)
	terrain_modified.emit(build_point, false)


## Raycast and return hit info without modifying terrain
func raycast_terrain() -> Dictionary:
	if not _raycast.is_colliding():
		return {}
	
	return {
		"position": _raycast.get_collision_point(),
		"normal": _raycast.get_collision_normal(),
		"collider": _raycast.get_collider()
	}


## Get the material at a global position
func get_material_at(global_pos: Vector3) -> int:
	if _terrain_manager == null:
		return 0
	return _terrain_manager.get_material_at(global_pos)


## Set current tool type
func set_tool(tool_type: int) -> void:
	current_tool = tool_type


## Set current tool tier
func set_tier(tier: int) -> void:
	current_tier = tier
