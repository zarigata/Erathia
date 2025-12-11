extends Node

# Signal when inventory changes, passing the slot index that changed
signal inventory_updated(slot_index)

# 24 columns * 16 rows = 384 slots
const COLS = 24
const ROWS = 16
const TOTAL_SLOTS = COLS * ROWS
const DEFAULT_MAX_STACK = 4096

var slots: Array[InventorySlotData] = []

func _ready():
	_init_inventory()

func _init_inventory():
	slots.clear()
	slots.resize(TOTAL_SLOTS)
	for i in range(TOTAL_SLOTS):
		slots[i] = InventorySlotData.new()

# --- Public API ---

func add_item(item_id: String, amount: int, icon_path: String = "") -> int:
	var remaining = amount
	
	# 1. Try to stack with existing items
	for i in range(TOTAL_SLOTS):
		if not slots[i].is_empty() and slots[i].item_id == item_id:
			remaining = slots[i].add(remaining)
			emit_signal("inventory_updated", i)
			if remaining <= 0:
				return 0
	
	# 2. Place in first empty slot
	for i in range(TOTAL_SLOTS):
		if slots[i].is_empty():
			slots[i].item_id = item_id
			slots[i].icon_path = icon_path
			remaining = slots[i].add(remaining)
			emit_signal("inventory_updated", i)
			if remaining <= 0:
				return 0
				
	return remaining # Inventory full

func get_slot(index: int) -> InventorySlotData:
	if index >= 0 and index < slots.size():
		return slots[index]
	return null

func move_item(from_index: int, to_index: int):
	if from_index < 0 or from_index >= slots.size() or to_index < 0 or to_index >= slots.size():
		return
		
	var from_slot = slots[from_index]
	var to_slot = slots[to_index]
	
	if from_slot.is_empty():
		return

	if to_slot.is_empty():
		# Simple move
		slots[to_index] = from_slot
		slots[from_index] = InventorySlotData.new()
	elif to_slot.can_stack_with(from_slot):
		# Stack
		var remainder = to_slot.add(from_slot.count)
		if remainder == 0:
			slots[from_index] = InventorySlotData.new()
		else:
			from_slot.count = remainder
	else:
		# Swap
		slots[to_index] = from_slot
		slots[from_index] = to_slot
		
	emit_signal("inventory_updated", from_index)
	emit_signal("inventory_updated", to_index)

func remove_item_at(index: int, amount: int) -> bool:
	if index < 0 or index >= slots.size():
		return false
		
	var slot = slots[index]
	if slot.is_empty() or slot.count < amount:
		return false
		
	slot.count -= amount
	if slot.count <= 0:
		slots[index] = InventorySlotData.new() # Clear slot
		
	emit_signal("inventory_updated", index)
	return true
