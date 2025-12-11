class_name InventorySlotData
extends Resource

@export var item_id: String = ""
@export var count: int = 0
@export var max_stack: int = 4096
@export var icon_path: String = ""
@export var metadata: Dictionary = {}

func _init(p_item_id: String = "", p_count: int = 0, p_max_stack: int = 4096, p_icon_path: String = ""):
	item_id = p_item_id
	count = p_count
	max_stack = p_max_stack
	icon_path = p_icon_path

func can_stack_with(other: InventorySlotData) -> bool:
	return item_id == other.item_id

func is_empty() -> bool:
	return item_id == "" or count <= 0

func add(amount: int) -> int:
	var total = count + amount
	if total <= max_stack:
		count = total
		return 0 # All added
	else:
		count = max_stack
		return total - max_stack # Return remainder
