class_name PlayerMining
extends RayCast3D
## Mining system that detects terrain hits and modifies terrain height.
## This script IS a RayCast3D, so we use self for collision detection.

@export var dig_amount: float = -2.0
@export var build_amount: float = 2.0
@export var mining_cooldown: float = 0.25  # Seconds between actions

# Tool types affect mining behavior
enum ToolType { HAND, PICKAXE, SHOVEL }
var current_tool: ToolType = ToolType.HAND

var terrain_manager: TerrainManager
var cooldown_timer: float = 0.0
var is_mining: bool = false

func _ready():
	# Configure raycast
	enabled = true
	exclude_parent = true
	target_position = Vector3(0, 0, -5)  # 5 meters reach
	collision_mask = 1  # Terrain layer
	
	# Find TerrainManager on next frame (after tree is ready)
	call_deferred("_find_terrain_manager")

func _find_terrain_manager():
	terrain_manager = get_tree().root.find_child("TerrainManager", true, false)
	if not terrain_manager:
		push_warning("PlayerMining: Could not find TerrainManager!")

func _process(delta):
	# Handle cooldown
	if cooldown_timer > 0:
		cooldown_timer -= delta
	
	# Handle tool switching (1, 2, 3 keys)
	if Input.is_action_just_pressed("equip_1"):
		current_tool = ToolType.PICKAXE
		print("Equipped: Pickaxe")
	elif Input.is_action_just_pressed("equip_2"):
		current_tool = ToolType.SHOVEL
		print("Equipped: Shovel")
	elif Input.is_action_just_pressed("equip_3"):
		current_tool = ToolType.HAND
		print("Equipped: Hand")
	
	# Check if we're hitting terrain
	if not is_colliding():
		return
	
	var collider = get_collider()
	
	# Verify we hit a Chunk (terrain)
	if not collider is Chunk:
		return
	
	# Handle mining (left click / attack)
	if Input.is_action_pressed("attack") and cooldown_timer <= 0:
		_perform_dig()
		cooldown_timer = mining_cooldown
	
	# Handle building (right click / interact_alt or use)
	if Input.is_action_pressed("use") and cooldown_timer <= 0:
		_perform_build()
		cooldown_timer = mining_cooldown

func _perform_dig():
	if not terrain_manager:
		return
	
	var hit_point = get_collision_point()
	var hit_normal = get_collision_normal()
	
	# Offset slightly into the terrain for digging
	var dig_point = hit_point - hit_normal * 0.5
	
	# Tool modifiers
	var amount = dig_amount
	match current_tool:
		ToolType.PICKAXE:
			amount = dig_amount * 1.5  # Pickaxe digs deeper
		ToolType.SHOVEL:
			amount = dig_amount * 1.2  # Shovel is faster for soft terrain
		ToolType.HAND:
			amount = dig_amount * 0.3  # Hand is slow
	
	terrain_manager.modify_terrain(dig_point, amount)
	
	# Visual/audio feedback placeholder
	_spawn_mining_particles(hit_point)

func _perform_build():
	if not terrain_manager:
		return
	
	var hit_point = get_collision_point()
	var hit_normal = get_collision_normal()
	
	# Offset slightly above the terrain for building
	var build_point = hit_point + hit_normal * 0.5
	
	terrain_manager.modify_terrain(build_point, build_amount)

func _spawn_mining_particles(pos: Vector3):
	# Placeholder for particle effects
	# TODO: Add actual particle system
	pass

# Public API for tool management
func set_tool(tool: ToolType):
	current_tool = tool

func get_tool() -> ToolType:
	return current_tool
