## MiningSystem - Singleton for handling mining drops and resource collection
##
## Listens to TerrainEditSystem.terrain_edited signals and spawns resource pickups.
## Manages temporary resource storage until inventory system is implemented.
##
## Signals:
##   resource_dropped(resource_type, amount, position) - When pickup spawns
##   resource_collected(resource_type, amount) - When player collects pickup
##   inventory_updated(resources) - When collected_resources changes
extends Node

## Emitted when a resource pickup is spawned
signal resource_dropped(resource_type: String, amount: int, position: Vector3)
## Emitted when player collects a resource
signal resource_collected(resource_type: String, amount: int)
## Emitted when collected_resources dictionary changes
signal inventory_updated(resources: Dictionary)

## Resource type enum for internal use
enum ResourceType {
	DIRT,
	STONE,
	IRON_ORE,
	RARE_CRYSTAL,
	WOOD,
	COPPER_ORE,
}

## Resource type string names
const RESOURCE_NAMES: Dictionary = {
	ResourceType.DIRT: "dirt",
	ResourceType.STONE: "stone",
	ResourceType.IRON_ORE: "iron_ore",
	ResourceType.RARE_CRYSTAL: "rare_crystal",
}

## Resource colors for visual feedback
const RESOURCE_COLORS: Dictionary = {
	"dirt": Color(0.4, 0.3, 0.2),
	"stone": Color(0.5, 0.5, 0.5),
	"iron_ore": Color(0.6, 0.4, 0.3),
	"rare_crystal": Color(0.8, 0.2, 0.9),
}

## Loot tables mapping material IDs to resource drops (amount per cubic meter)
## Reduced by 50% for balanced gameplay
const LOOT_TABLES: Dictionary = {
	1: {"dirt": 0.5},  # DIRT
	2: {"stone": 0.75},  # STONE
	3: {"stone": 0.4, "iron_ore": 0.15},  # IRON_ORE - mixed drops
	4: {"stone": 0.25, "rare_crystal": 0.05},  # RARE_CRYSTAL - mixed drops
}

## Minimum volume threshold to spawn drops
const MIN_VOLUME_THRESHOLD: float = 0.5
## Maximum pickups per single edit to prevent spam
const MAX_PICKUPS_PER_EDIT: int = 5
## Stack threshold - amounts above this create stacks instead of individual pickups
const STACK_THRESHOLD: int = 10

## Preloaded pickup scene
var _pickup_scene: PackedScene = null

## DEPRECATED: Temporary storage for collected resources
## Use Inventory singleton instead. Kept for backward compatibility.
var collected_resources: Dictionary = {}


func _ready() -> void:
	# Connect to TerrainEditSystem signal (deferred to ensure autoload is ready)
	call_deferred("_connect_terrain_system")
	
	# Preload pickup scene
	_pickup_scene = preload("res://_engine/mining/resource_pickup.tscn")
	
	# Migration: Transfer any existing collected_resources to Inventory singleton
	call_deferred("_migrate_to_inventory")
	
	# Connect to Inventory drop signal
	if Inventory:
		Inventory.item_dropped_to_world.connect(_on_item_dropped_to_world)


func _migrate_to_inventory() -> void:
	if collected_resources.is_empty():
		return
	
	if not Inventory:
		push_warning("[MiningSystem] Inventory singleton not available for migration")
		return
	
	for resource_type in collected_resources:
		var amount: int = collected_resources[resource_type]
		Inventory.add_resource(resource_type, amount)
	
	print("[MiningSystem] Migrated %d resource types to Inventory" % collected_resources.size())
	collected_resources.clear()


func _connect_terrain_system() -> void:
	var terrain_system = get_node_or_null("/root/TerrainEditSystem")
	if terrain_system:
		terrain_system.terrain_edited.connect(_on_terrain_edited)
		print("[MiningSystem] Connected to TerrainEditSystem.terrain_edited signal")
	else:
		push_warning("[MiningSystem] TerrainEditSystem not found - mining drops disabled")


## Called when terrain is edited (mined/built)
func _on_terrain_edited(position: Vector3, volume: float, material_id: int, operation: int) -> void:
	# Only spawn drops for SUBTRACT operations (mining), not ADD (building)
	if operation != TerrainEditSystem.Operation.SUBTRACT:
		return
	
	# AIR material (0) means no drops
	if material_id == 0:
		return
	
	# Check minimum volume threshold
	if volume < MIN_VOLUME_THRESHOLD:
		return
	
	# Calculate drops based on material and volume
	var drops: Dictionary = calculate_drops(material_id, volume)
	
	if drops.is_empty():
		return
	
	# Spawn pickups for each resource type
	for resource_type in drops:
		var amount: int = drops[resource_type]
		if amount > 0:
			spawn_pickup(resource_type, amount, position)


## Calculates resource drops based on material ID and volume mined
## @param material_id: The material that was mined
## @param volume: Approximate volume of terrain modified
## @return: Dictionary of resource_type -> amount
func calculate_drops(material_id: int, volume: float) -> Dictionary:
	var drops: Dictionary = {}
	
	if not LOOT_TABLES.has(material_id):
		# Unknown material defaults to stone
		drops["stone"] = int(volume * 0.5)
		return drops
	
	var loot_table: Dictionary = LOOT_TABLES[material_id]
	
	for resource_type in loot_table:
		var rate: float = loot_table[resource_type]
		var amount: int = int(volume * rate)
		if amount > 0:
			drops[resource_type] = amount
	
	return drops


## Spawns a resource pickup at the specified position
## @param resource_type: Type of resource ("stone", "iron_ore", etc.)
## @param amount: Amount of resource in this pickup
## @param position: World position to spawn at
## @param dropped_by_player: If true, marks pickup with invulnerability
func spawn_pickup(resource_type: String, amount: int, position: Vector3, dropped_by_player: bool = false) -> void:
	if not _pickup_scene:
		push_warning("[MiningSystem] Pickup scene not loaded")
		return
	
	# Handle large amounts by creating stacks
	var pickups_to_spawn: Array[Dictionary] = []
	
	if amount > STACK_THRESHOLD:
		# Create stacked pickups
		var remaining: int = amount
		while remaining > 0 and pickups_to_spawn.size() < MAX_PICKUPS_PER_EDIT:
			var stack_amount: int = min(remaining, STACK_THRESHOLD * 2)
			pickups_to_spawn.append({"type": resource_type, "amount": stack_amount})
			remaining -= stack_amount
		# Merge leftover into last stack if we hit the pickup limit
		if remaining > 0 and pickups_to_spawn.size() > 0:
			pickups_to_spawn[-1]["amount"] += remaining
	else:
		pickups_to_spawn.append({"type": resource_type, "amount": amount})
	
	# Get world node to add pickups to
	var world_node: Node = _get_world_node()
	if not world_node:
		push_warning("[MiningSystem] Could not find world node for pickup spawning")
		return
	
	# Spawn each pickup
	for pickup_data in pickups_to_spawn:
		var pickup: RigidBody3D = _pickup_scene.instantiate()
		
		# Configure pickup properties
		pickup.resource_type = pickup_data["type"]
		pickup.amount = pickup_data["amount"]
		
		# Add to world first (before setting global_position)
		world_node.add_child(pickup)
		
		# Calculate spawn position with random offset for scatter
		var spawn_offset := Vector3(
			randf_range(-1.0, 1.0),
			0.5,
			randf_range(-1.0, 1.0)
		)
		pickup.global_position = position + spawn_offset
		
		# Apply physics impulse for scatter effect
		var impulse := Vector3(
			randf_range(-2.0, 2.0),
			randf_range(3.0, 5.0),
			randf_range(-2.0, 2.0)
		)
		pickup.apply_impulse(impulse)
		
		# Explicitly enable magnetic attraction for mined resources
		pickup.enable_magnetic_attraction = true
		
		# Mark as dropped by player for invulnerability
		if dropped_by_player and pickup.has_method("set_dropped_by_player"):
			pickup.set_dropped_by_player()
		
		# Emit signal
		resource_dropped.emit(pickup_data["type"], pickup_data["amount"], position)
		
		print("[MiningSystem] Spawned %s x%d at %s" % [pickup_data["type"], pickup_data["amount"], position])


## Collects a resource and adds it to Inventory singleton
## @param resource_type: Type of resource collected
## @param amount: Amount collected
## @return: Amount that couldn't fit in inventory (0 if all fit)
func collect_resource(resource_type: String, amount: int) -> int:
	var overflow: int = 0
	
	# Forward to Inventory singleton
	if Inventory:
		overflow = Inventory.add_resource(resource_type, amount)
	else:
		# Fallback to deprecated local storage
		if not collected_resources.has(resource_type):
			collected_resources[resource_type] = 0
		collected_resources[resource_type] += amount
	
	# Emit signals for backward compatibility
	var collected_amount: int = amount - overflow
	if collected_amount > 0:
		resource_collected.emit(resource_type, collected_amount)
		inventory_updated.emit(get_all_resources())
		print("[MiningSystem] Collected %d %s (Total: %d)" % [collected_amount, resource_type, get_resource_count(resource_type)])
	
	return overflow


## Returns the count of a specific resource type
## @param resource_type: Type of resource to query
## @return: Amount of that resource collected
func get_resource_count(resource_type: String) -> int:
	# Forward to Inventory singleton
	if Inventory:
		return Inventory.get_resource_count(resource_type)
	
	# Fallback to deprecated local storage
	if collected_resources.has(resource_type):
		return collected_resources[resource_type]
	return 0


## Returns all collected resources
## @return: Dictionary of resource_type -> amount
func get_all_resources() -> Dictionary:
	# Forward to Inventory singleton
	if Inventory:
		return Inventory.get_all_resources()
	
	# Fallback to deprecated local storage
	return collected_resources.duplicate()


## Removes a specified amount of a resource (for crafting, etc.)
## @param resource_type: Type of resource to remove
## @param amount: Amount to remove
## @return: True if successful, false if insufficient resources
func remove_resource(resource_type: String, amount: int) -> bool:
	# Forward to Inventory singleton
	if Inventory:
		var success: bool = Inventory.remove_resource(resource_type, amount)
		if success:
			inventory_updated.emit(get_all_resources())
		return success
	
	# Fallback to deprecated local storage
	if not collected_resources.has(resource_type):
		return false
	
	if collected_resources[resource_type] < amount:
		return false
	
	collected_resources[resource_type] -= amount
	
	# Remove entry if zero
	if collected_resources[resource_type] <= 0:
		collected_resources.erase(resource_type)
	
	inventory_updated.emit(collected_resources)
	return true


## Transfers all resources to Inventory singleton (migration helper)
## @param inventory_node: Optional - ignored, uses Inventory singleton
func transfer_to_inventory(_inventory_node: Node = null) -> void:
	if not Inventory:
		push_warning("[MiningSystem] Inventory singleton not available")
		return
	
	for resource_type in collected_resources:
		var amount: int = collected_resources[resource_type]
		Inventory.add_resource(resource_type, amount)
	
	collected_resources.clear()
	inventory_updated.emit(get_all_resources())
	print("[MiningSystem] Transferred all resources to Inventory singleton")


## Gets the color for a resource type
## @param resource_type: Type of resource
## @return: Color for visual representation
func get_resource_color(resource_type: String) -> Color:
	if RESOURCE_COLORS.has(resource_type):
		return RESOURCE_COLORS[resource_type]
	return Color.WHITE


## Called when player drops item from inventory to world
func _on_item_dropped_to_world(resource_type: String, amount: int, drop_position: Vector3) -> void:
	spawn_pickup(resource_type, amount, drop_position, true)  # true = dropped by player


## Finds appropriate world node to add pickups to
func _get_world_node() -> Node:
	# Try to find Main scene first
	var main := get_tree().root.get_node_or_null("Main")
	if main:
		return main
	
	# Try current scene
	var current_scene := get_tree().current_scene
	if current_scene:
		return current_scene
	
	# Fallback to root
	return get_tree().root
