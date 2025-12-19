extends Node
## Inventory Singleton - Manages player inventory with slot-based system
## Autoload: Inventory

# Constants
const MAX_SLOTS: int = 40
const DEFAULT_STACK_SIZE: int = 100

# Resource categories
enum Category { MATERIAL, TOOL, WEAPON, ARMOR, CONSUMABLE, BUILDING, MISC }

# Signals
signal inventory_changed(slot_index: int)
signal item_added(resource_type: String, amount: int)
signal item_removed(resource_type: String, amount: int)
signal slot_swapped(from_index: int, to_index: int)
signal item_dropped_to_world(resource_type: String, amount: int, drop_position: Vector3)
signal building_piece_crafted(piece_id: String, amount: int)

# Slot structure: {slot_index: {resource_type: String, amount: int, max_stack: int}}
var slots: Dictionary = {}

# Cheat state variables
var _infinite_building_active: bool = false
var _infinite_crafting_active: bool = false

# Resource database mapping resource types to properties
var resource_database: Dictionary = {
	"stone": {
		"display_name": "Stone",
		"icon_path": "res://_assets/icons/resources/stone.png",
		"stack_size": 100,
		"category": Category.MATERIAL,
		"description": "Common stone, useful for building."
	},
	"dirt": {
		"display_name": "Dirt",
		"icon_path": "res://_assets/icons/resources/dirt.png",
		"stack_size": 100,
		"category": Category.MATERIAL,
		"description": "Basic dirt block."
	},
	"iron_ore": {
		"display_name": "Iron Ore",
		"icon_path": "res://_assets/icons/resources/iron_ore.png",
		"stack_size": 50,
		"category": Category.MATERIAL,
		"description": "Raw iron ore, can be smelted."
	},
	"wood": {
		"display_name": "Wood",
		"icon_path": "res://_assets/icons/resources/wood.png",
		"stack_size": 100,
		"category": Category.MATERIAL,
		"description": "Wooden logs for crafting and building."
	},
	"rare_crystal": {
		"display_name": "Rare Crystal",
		"icon_path": "res://_assets/icons/resources/rare_crystal.png",
		"stack_size": 20,
		"category": Category.MATERIAL,
		"description": "A rare crystal with magical properties."
	},
	"faction_core": {
		"display_name": "Faction Core",
		"icon_path": "res://_assets/icons/resources/faction_core.png",
		"stack_size": 10,
		"category": Category.MATERIAL,
		"description": "A powerful core imbued with faction energy."
	},
	# Building pieces
	"thatch_wall": {
		"display_name": "Thatch Wall",
		"icon_path": "res://_assets/icons/building/thatch_wall.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A simple wall made of thatch and sticks."
	},
	"dirt_floor": {
		"display_name": "Dirt Floor",
		"icon_path": "res://_assets/icons/building/dirt_floor.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "Packed dirt floor tile."
	},
	"thatch_roof": {
		"display_name": "Thatch Roof",
		"icon_path": "res://_assets/icons/building/thatch_roof.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A simple thatched roof."
	},
	"simple_door": {
		"display_name": "Simple Door",
		"icon_path": "res://_assets/icons/building/simple_door.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A basic wooden door."
	},
	"ladder": {
		"display_name": "Ladder",
		"icon_path": "res://_assets/icons/building/ladder.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A simple wooden ladder."
	},
	"wood_wall": {
		"display_name": "Wood Wall",
		"icon_path": "res://_assets/icons/building/wood_wall.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A sturdy wooden plank wall."
	},
	"wood_floor": {
		"display_name": "Wood Floor",
		"icon_path": "res://_assets/icons/building/wood_floor.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "Wooden plank flooring."
	},
	"wood_roof": {
		"display_name": "Wood Shingle Roof",
		"icon_path": "res://_assets/icons/building/wood_roof.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A roof with wooden shingles."
	},
	"wood_door": {
		"display_name": "Wood Door",
		"icon_path": "res://_assets/icons/building/wood_door.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A solid wooden door."
	},
	"wood_foundation": {
		"display_name": "Wood Foundation",
		"icon_path": "res://_assets/icons/building/wood_foundation.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A wooden foundation for building."
	},
	"wood_stairs": {
		"display_name": "Wood Stairs",
		"icon_path": "res://_assets/icons/building/wood_stairs.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "Wooden staircase."
	},
	"stone_wall": {
		"display_name": "Stone Wall",
		"icon_path": "res://_assets/icons/building/stone_wall.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A solid stone block wall."
	},
	"stone_floor": {
		"display_name": "Stone Floor",
		"icon_path": "res://_assets/icons/building/stone_floor.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "Stone tile flooring."
	},
	"stone_roof": {
		"display_name": "Stone Roof",
		"icon_path": "res://_assets/icons/building/stone_roof.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A roof with stone tiles."
	},
	"reinforced_door": {
		"display_name": "Reinforced Door",
		"icon_path": "res://_assets/icons/building/reinforced_door.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A wooden door reinforced with metal bands."
	},
	"stone_foundation": {
		"display_name": "Stone Foundation",
		"icon_path": "res://_assets/icons/building/stone_foundation.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A solid stone foundation."
	},
	"stone_stairs": {
		"display_name": "Stone Stairs",
		"icon_path": "res://_assets/icons/building/stone_stairs.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "Stone staircase."
	},
	"metal_wall": {
		"display_name": "Reinforced Wall",
		"icon_path": "res://_assets/icons/building/metal_wall.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A stone wall reinforced with metal."
	},
	"polished_floor": {
		"display_name": "Polished Floor",
		"icon_path": "res://_assets/icons/building/polished_floor.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "Polished stone flooring."
	},
	"slate_roof": {
		"display_name": "Slate Roof",
		"icon_path": "res://_assets/icons/building/slate_roof.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A roof with slate tiles."
	},
	"ornate_door": {
		"display_name": "Ornate Door",
		"icon_path": "res://_assets/icons/building/ornate_door.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "An ornately decorated door."
	},
	"reinforced_foundation": {
		"display_name": "Reinforced Foundation",
		"icon_path": "res://_assets/icons/building/reinforced_foundation.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "A metal-reinforced stone foundation."
	},
	"spiral_stairs": {
		"display_name": "Spiral Stairs",
		"icon_path": "res://_assets/icons/building/spiral_stairs.png",
		"stack_size": 50,
		"category": Category.BUILDING,
		"description": "Elegant spiral staircase."
	}
}


func _ready() -> void:
	# Initialize empty slots dictionary
	slots = {}
	
	# Connect to DevConsole cheat signals
	if DevConsole:
		DevConsole.cheat_toggled.connect(_on_cheat_toggled)


func _on_cheat_toggled(cheat_name: String, enabled: bool) -> void:
	match cheat_name:
		"infinite_build":
			_infinite_building_active = enabled
		"infinite_craft":
			_infinite_crafting_active = enabled


## Add resource to inventory. Returns amount that couldn't fit (0 if all fit).
func add_resource(resource_type: String, amount: int) -> int:
	if amount <= 0:
		return 0
	
	var remaining: int = amount
	var max_stack: int = _get_stack_size(resource_type)
	
	# First, try to fill existing stacks of the same type
	for slot_index in slots.keys():
		if remaining <= 0:
			break
		var slot_data: Dictionary = slots[slot_index]
		if slot_data.get("resource_type") == resource_type:
			var current_amount: int = slot_data.get("amount", 0)
			var space_available: int = max_stack - current_amount
			if space_available > 0:
				var to_add: int = min(remaining, space_available)
				slots[slot_index]["amount"] = current_amount + to_add
				remaining -= to_add
				inventory_changed.emit(slot_index)
	
	# Then, fill empty slots
	while remaining > 0:
		var empty_slot: int = find_empty_slot()
		if empty_slot == -1:
			break  # Inventory full
		
		var to_add: int = min(remaining, max_stack)
		slots[empty_slot] = {
			"resource_type": resource_type,
			"amount": to_add,
			"max_stack": max_stack
		}
		remaining -= to_add
		inventory_changed.emit(empty_slot)
	
	var added_amount: int = amount - remaining
	if added_amount > 0:
		item_added.emit(resource_type, added_amount)
	
	return remaining


## Remove resource from inventory. Returns true if successful.
func remove_resource(resource_type: String, amount: int) -> bool:
	if amount <= 0:
		return true
	
	var total_available: int = get_resource_count(resource_type)
	if total_available < amount:
		return false
	
	var remaining: int = amount
	
	# Remove from slots, starting from partial stacks first
	var slot_indices: Array = slots.keys()
	# Sort by amount ascending to empty partial stacks first
	slot_indices.sort_custom(func(a, b):
		var amount_a: int = slots[a].get("amount", 0) if slots[a].get("resource_type") == resource_type else 999999
		var amount_b: int = slots[b].get("amount", 0) if slots[b].get("resource_type") == resource_type else 999999
		return amount_a < amount_b
	)
	
	for slot_index in slot_indices:
		if remaining <= 0:
			break
		var slot_data: Dictionary = slots[slot_index]
		if slot_data.get("resource_type") == resource_type:
			var current_amount: int = slot_data.get("amount", 0)
			var to_remove: int = min(remaining, current_amount)
			var new_amount: int = current_amount - to_remove
			
			if new_amount <= 0:
				slots.erase(slot_index)
			else:
				slots[slot_index]["amount"] = new_amount
			
			remaining -= to_remove
			inventory_changed.emit(slot_index)
	
	item_removed.emit(resource_type, amount)
	return true


## Get total count of a resource type across all slots
func get_resource_count(resource_type: String) -> int:
	var total: int = 0
	for slot_data in slots.values():
		if slot_data.get("resource_type") == resource_type:
			total += slot_data.get("amount", 0)
	return total


## Check if inventory has required resources (multiple types at once)
func has_resources(requirements: Dictionary) -> bool:
	for resource_type in requirements.keys():
		if get_resource_count(resource_type) < requirements[resource_type]:
			return false
	return true


## Get slot data at index. Returns empty dict if slot is empty.
func get_slot_data(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return {}
	return slots.get(slot_index, {})


## Swap contents of two slots (for drag-drop)
func swap_slots(from_index: int, to_index: int) -> void:
	if from_index == to_index:
		return
	if from_index < 0 or from_index >= MAX_SLOTS:
		return
	if to_index < 0 or to_index >= MAX_SLOTS:
		return
	
	var from_data: Dictionary = slots.get(from_index, {})
	var to_data: Dictionary = slots.get(to_index, {})
	
	if from_data.is_empty() and to_data.is_empty():
		return
	
	# Perform swap
	if from_data.is_empty():
		slots.erase(from_index)
	else:
		slots[to_index] = from_data.duplicate()
	
	if to_data.is_empty():
		slots.erase(to_index)
	else:
		slots[from_index] = to_data.duplicate()
	
	# Clean up empty entries
	if slots.has(from_index) and slots[from_index].is_empty():
		slots.erase(from_index)
	if slots.has(to_index) and slots[to_index].is_empty():
		slots.erase(to_index)
	
	slot_swapped.emit(from_index, to_index)
	inventory_changed.emit(from_index)
	inventory_changed.emit(to_index)


## Merge slots if they contain the same resource type
func merge_slots(from_index: int, to_index: int) -> void:
	if from_index == to_index:
		return
	
	var from_data: Dictionary = get_slot_data(from_index)
	var to_data: Dictionary = get_slot_data(to_index)
	
	if from_data.is_empty():
		return
	
	var from_type: String = from_data.get("resource_type", "")
	var to_type: String = to_data.get("resource_type", "")
	
	# If target is empty, just move
	if to_data.is_empty():
		slots[to_index] = from_data.duplicate()
		slots.erase(from_index)
		inventory_changed.emit(from_index)
		inventory_changed.emit(to_index)
		return
	
	# Can only merge same types
	if from_type != to_type:
		swap_slots(from_index, to_index)
		return
	
	var max_stack: int = _get_stack_size(from_type)
	var from_amount: int = from_data.get("amount", 0)
	var to_amount: int = to_data.get("amount", 0)
	var space_available: int = max_stack - to_amount
	
	if space_available <= 0:
		swap_slots(from_index, to_index)
		return
	
	var transfer_amount: int = min(from_amount, space_available)
	slots[to_index]["amount"] = to_amount + transfer_amount
	
	var remaining: int = from_amount - transfer_amount
	if remaining <= 0:
		slots.erase(from_index)
	else:
		slots[from_index]["amount"] = remaining
	
	inventory_changed.emit(from_index)
	inventory_changed.emit(to_index)


## Split a slot, moving specified amount to a new slot. Returns new slot index or -1 if failed.
func split_slot(slot_index: int, amount: int) -> int:
	var slot_data: Dictionary = get_slot_data(slot_index)
	if slot_data.is_empty():
		return -1
	
	var current_amount: int = slot_data.get("amount", 0)
	if amount <= 0 or amount >= current_amount:
		return -1
	
	var empty_slot: int = find_empty_slot()
	if empty_slot == -1:
		return -1
	
	# Split the stack
	slots[slot_index]["amount"] = current_amount - amount
	slots[empty_slot] = {
		"resource_type": slot_data.get("resource_type"),
		"amount": amount,
		"max_stack": slot_data.get("max_stack", DEFAULT_STACK_SIZE)
	}
	
	inventory_changed.emit(slot_index)
	inventory_changed.emit(empty_slot)
	
	return empty_slot


## Find first empty slot. Returns -1 if inventory is full.
func find_empty_slot() -> int:
	for i in range(MAX_SLOTS):
		if not slots.has(i):
			return i
	return -1


## Get all resources as a dictionary (for save/load compatibility)
func get_all_resources() -> Dictionary:
	var resources: Dictionary = {}
	for slot_data in slots.values():
		var resource_type: String = slot_data.get("resource_type", "")
		if resource_type.is_empty():
			continue
		var amount: int = slot_data.get("amount", 0)
		resources[resource_type] = resources.get(resource_type, 0) + amount
	return resources


## Get the stack size for a resource type
func _get_stack_size(resource_type: String) -> int:
	if resource_database.has(resource_type):
		return resource_database[resource_type].get("stack_size", DEFAULT_STACK_SIZE)
	return DEFAULT_STACK_SIZE


## Get resource info from database
func get_resource_info(resource_type: String) -> Dictionary:
	return resource_database.get(resource_type, {
		"display_name": resource_type.capitalize(),
		"icon_path": "",
		"stack_size": DEFAULT_STACK_SIZE,
		"category": Category.MISC,
		"description": "Unknown resource."
	})


## Get number of used slots
func get_used_slot_count() -> int:
	return slots.size()


## Check if inventory is full
func is_full() -> bool:
	return get_used_slot_count() >= MAX_SLOTS


## Clear all items from inventory
func clear_all() -> void:
	var old_slot_count: int = slots.size()
	slots.clear()
	
	# Emit changes for all cleared slots
	for i in range(old_slot_count):
		inventory_changed.emit(i)


## Drop item from slot into world at specified position
## @param slot_index: Slot to drop from
## @param amount: Amount to drop (0 = all)
## @param drop_position: World position to spawn pickup
## @return: True if successful
func drop_item_to_world(slot_index: int, amount: int, drop_position: Vector3) -> bool:
	var slot_data: Dictionary = get_slot_data(slot_index)
	if slot_data.is_empty():
		return false
	
	var resource_type: String = slot_data.get("resource_type", "")
	var current_amount: int = slot_data.get("amount", 0)
	
	# Drop all if amount is 0 or exceeds current
	var drop_amount: int = amount if amount > 0 and amount < current_amount else current_amount
	
	# Remove from inventory
	if not remove_resource(resource_type, drop_amount):
		return false
	
	# Emit signal for MiningSystem to spawn pickup
	item_dropped_to_world.emit(resource_type, drop_amount, drop_position)
	
	return true


# ============================================================================
# SORTING AND FILTERING (Step 12)
# ============================================================================

## Sort inventory by resource type (group similar resources together)
func sort_by_type() -> void:
	compact_stacks()
	
	var sorted_slots: Array = []
	for slot_index in slots.keys():
		sorted_slots.append({
			"index": slot_index,
			"data": slots[slot_index].duplicate()
		})
	
	# Sort by category first, then by resource type name
	sorted_slots.sort_custom(func(a, b):
		var type_a: String = a["data"].get("resource_type", "")
		var type_b: String = b["data"].get("resource_type", "")
		var cat_a: int = get_resource_info(type_a).get("category", Category.MISC)
		var cat_b: int = get_resource_info(type_b).get("category", Category.MISC)
		if cat_a != cat_b:
			return cat_a < cat_b
		return type_a < type_b
	)
	
	# Rebuild slots dictionary
	slots.clear()
	for i in range(sorted_slots.size()):
		slots[i] = sorted_slots[i]["data"]
		inventory_changed.emit(i)
	
	# Emit changes for cleared slots
	for i in range(sorted_slots.size(), MAX_SLOTS):
		inventory_changed.emit(i)


## Sort inventory by amount (descending order)
func sort_by_amount() -> void:
	compact_stacks()
	
	var sorted_slots: Array = []
	for slot_index in slots.keys():
		sorted_slots.append({
			"index": slot_index,
			"data": slots[slot_index].duplicate()
		})
	
	# Sort by amount descending
	sorted_slots.sort_custom(func(a, b):
		return a["data"].get("amount", 0) > b["data"].get("amount", 0)
	)
	
	# Rebuild slots dictionary
	slots.clear()
	for i in range(sorted_slots.size()):
		slots[i] = sorted_slots[i]["data"]
		inventory_changed.emit(i)
	
	# Emit changes for cleared slots
	for i in range(sorted_slots.size(), MAX_SLOTS):
		inventory_changed.emit(i)


## Merge partial stacks of the same resource type
func compact_stacks() -> void:
	# Group by resource type
	var resources_by_type: Dictionary = {}
	for slot_index in slots.keys():
		var slot_data: Dictionary = slots[slot_index]
		var resource_type: String = slot_data.get("resource_type", "")
		if resource_type.is_empty():
			continue
		if not resources_by_type.has(resource_type):
			resources_by_type[resource_type] = 0
		resources_by_type[resource_type] += slot_data.get("amount", 0)
	
	# Clear all slots
	var old_slot_count: int = slots.size()
	slots.clear()
	
	# Rebuild with compacted stacks
	var current_slot: int = 0
	for resource_type in resources_by_type.keys():
		var total_amount: int = resources_by_type[resource_type]
		var max_stack: int = _get_stack_size(resource_type)
		
		while total_amount > 0 and current_slot < MAX_SLOTS:
			var stack_amount: int = min(total_amount, max_stack)
			slots[current_slot] = {
				"resource_type": resource_type,
				"amount": stack_amount,
				"max_stack": max_stack
			}
			total_amount -= stack_amount
			current_slot += 1
	
	# Emit changes for all affected slots
	for i in range(max(old_slot_count, current_slot)):
		inventory_changed.emit(i)


## Get slot indices containing resources of a specific category
func get_resources_by_category(category: Category) -> Array[int]:
	var result: Array[int] = []
	for slot_index in slots.keys():
		var slot_data: Dictionary = slots[slot_index]
		var resource_type: String = slot_data.get("resource_type", "")
		var info: Dictionary = get_resource_info(resource_type)
		if info.get("category", Category.MISC) == category:
			result.append(slot_index)
	return result


# ============================================================================
# SAVE/LOAD SUPPORT (Step 14)
# ============================================================================

## Serialize inventory to save-friendly format
func serialize() -> Dictionary:
	var slot_data_array: Array = []
	for slot_index in range(MAX_SLOTS):
		if slots.has(slot_index):
			var slot_data: Dictionary = slots[slot_index]
			slot_data_array.append({
				"slot": slot_index,
				"resource_type": slot_data.get("resource_type", ""),
				"amount": slot_data.get("amount", 0)
			})
	
	return {
		"version": 1,
		"slots": slot_data_array
	}


## Restore inventory from save data
func deserialize(data: Dictionary) -> void:
	slots.clear()
	
	var slot_data_array: Array = data.get("slots", [])
	for entry in slot_data_array:
		var slot_index: int = entry.get("slot", -1)
		var resource_type: String = entry.get("resource_type", "")
		var amount: int = entry.get("amount", 0)
		
		if slot_index >= 0 and slot_index < MAX_SLOTS and not resource_type.is_empty() and amount > 0:
			slots[slot_index] = {
				"resource_type": resource_type,
				"amount": amount,
				"max_stack": _get_stack_size(resource_type)
			}
	
	# Emit changes for all slots
	for i in range(MAX_SLOTS):
		inventory_changed.emit(i)


# ============================================================================
# BUILDING PIECE SUPPORT
# ============================================================================

## Check if player has required resources for a building piece
func has_building_resources(piece_data: BuildPieceData) -> bool:
	# Bypass resource check when infinite building is active
	if _infinite_building_active:
		return true
	
	if not piece_data:
		return false
	return has_resources(piece_data.resource_costs)


## Consume resources when placing a building piece
func consume_building_resources(piece_data: BuildPieceData) -> bool:
	# Bypass resource consumption when infinite building is active
	if _infinite_building_active:
		if piece_data:
			building_piece_crafted.emit(piece_data.piece_id, 1)
		return true
	
	if not piece_data:
		return false
	
	if not has_building_resources(piece_data):
		return false
	
	for resource_type in piece_data.resource_costs:
		var amount: int = piece_data.resource_costs[resource_type]
		if not remove_resource(resource_type, amount):
			push_error("Inventory: Failed to remove resource '%s' x%d" % [resource_type, amount])
			return false
	
	building_piece_crafted.emit(piece_data.piece_id, 1)
	return true
