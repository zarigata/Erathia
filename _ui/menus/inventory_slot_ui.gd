class_name InventorySlotUI
extends Panel

@onready var icon = $Icon
@onready var count_lbl = $Label

var slot_index = -1

func update_slot(data: InventorySlotData):
	if data == null or data.is_empty():
		icon.texture = null
		count_lbl.text = ""
		return
		
	# Load icon from path (simplified for now)
	# icon.texture = load(data.icon_path) 
	count_lbl.text = str(data.count) if data.count > 1 else ""
