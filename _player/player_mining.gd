class_name PlayerMining
extends RayCast3D
## Mining system that detects terrain hits and modifies terrain height.
## This script IS a RayCast3D, so we use self for collision detection.

@export var dig_amount: float = -2.0
@export var build_amount: float = 2.0
@export var mining_cooldown: float = 0.25  # Seconds between actions

# Tool types affect mining behavior
# Using MiningSystem.ToolType instead of local enum
var current_tool: int = MiningSystem.ToolType.PICKAXE  # Default

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
	
	# Handle tool switching
	if Input.is_action_just_pressed("equip_1"):
		current_tool = MiningSystem.ToolType.PICKAXE
		print("Equipped: Pickaxe")
	elif Input.is_action_just_pressed("equip_2"):
		current_tool = MiningSystem.ToolType.SHOVEL
		print("Equipped: Shovel")
	elif Input.is_action_just_pressed("equip_3"):
		current_tool = MiningSystem.ToolType.HOE  # Using Hoe for smooth/flatten
		print("Equipped: Hoe/Staff")
	
	# Check if we're hitting terrain
	if not is_colliding():
		return
	
	var collider = get_collider()
	
	# Verify we hit a Chunk (terrain)
	if not collider is Chunk:
		return
	
	# Handle mining/primary action (left click)
	if Input.is_action_pressed("attack") and cooldown_timer <= 0:
		_handle_primary_action()
		cooldown_timer = mining_cooldown
	
	# Handle specific secondary actions (right click)
	if Input.is_action_pressed("use") and cooldown_timer <= 0:
		_handle_secondary_action()
		cooldown_timer = mining_cooldown

func _handle_primary_action():
	if not terrain_manager: return
	
	var hit_point = get_collision_point()
	var hit_normal = get_collision_normal()
	
	if current_tool == MiningSystem.ToolType.HOE or current_tool == MiningSystem.ToolType.STAFF:
		# Smoothing Mode
		terrain_manager.smooth_terrain(hit_point, 3.0) # Radius 3
		print("Smoothing terrain...")
	else:
		# Digging Mode
		# Offset slightly into the terrain
		var dig_point = hit_point - hit_normal * 0.5
		
		# Get material
		var mat_id = terrain_manager.get_material_at(dig_point)
		var hardness = MiningSystem.get_material_hardness(mat_id)
		
		# Check tool compatibility
		var best_tool = MiningSystem.get_preferred_tool(mat_id)
		
		# Calculate effective power
		# For simplicity, assuming DIAMOND tier for now or base multiplier
		var power = MiningSystem.get_tool_power(MiningSystem.ToolTier.DIAMOND) # Testing with high power
		
		# Effective dig amount
		var amount = dig_amount * power
		
		if current_tool == best_tool:
			amount *= 2.0 # Bonus for correct tool
		
		# Hardness reduction
		if hardness > 0:
			amount /= (hardness / 10.0) # Simple formula
			
		terrain_manager.modify_terrain(dig_point, amount)
		
		# Loot Logic
		if mat_id != MiningSystem.MaterialID.AIR:
			var loot = MiningSystem.get_loot_item(mat_id)
			if loot != "":
				print("Mined: " + loot)

func _handle_secondary_action():
	if not terrain_manager: return
	
	var hit_point = get_collision_point()
	var hit_normal = get_collision_normal()
	
	if current_tool == MiningSystem.ToolType.HOE or current_tool == MiningSystem.ToolType.STAFF:
		# Flatten Mode
		# Flatten to player height or hit height? Let's flatten to hit height
		terrain_manager.flatten_terrain(hit_point, 3.0, hit_point.y)
		print("Flattening terrain...")
	else:
		# Build Mode (Place block/dirt)
		var build_point = hit_point + hit_normal * 0.5
		terrain_manager.modify_terrain(build_point, build_amount)

func set_tool(tool: int):
	current_tool = tool

func get_tool() -> int:
	return current_tool
