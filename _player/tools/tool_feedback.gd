extends Node
class_name ToolFeedback

@export var show_feedback_messages: bool = true
@export var feedback_message_duration: float = 1.5

var tool_manager: ToolManager = null
var player: CharacterBody3D = null

# Feedback state
var current_message: String = ""
var message_timer: float = 0.0

# Signals for UI integration
signal feedback_message(message: String, message_type: String)
signal hit_effect_requested(position: Vector3, material_id: int, success: bool)


func _ready() -> void:
	player = get_parent() as CharacterBody3D
	
	# Find ToolManager sibling
	tool_manager = get_parent().get_node_or_null("ToolManager") as ToolManager
	if tool_manager:
		tool_manager.tool_action_performed.connect(_on_tool_action_performed)
		tool_manager.tool_action_failed.connect(_on_tool_action_failed)
		tool_manager.tool_equipped.connect(_on_tool_equipped)
		tool_manager.tool_unequipped.connect(_on_tool_unequipped)


func _process(delta: float) -> void:
	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0:
			current_message = ""


func _on_tool_action_performed(tool: BaseTool, position: Vector3, success: bool) -> void:
	if success:
		# Successful hit - request particle/sound effects
		var material_id := -1
		if tool is Pickaxe:
			material_id = (tool as Pickaxe).last_hit_material_id
		
		hit_effect_requested.emit(position, material_id, true)
		
		# Show durability warning if low
		if tool.get_durability_percent() < 0.2:
			_show_message("Tool durability low!", "warning")
	else:
		hit_effect_requested.emit(position, -1, false)


func _on_tool_action_failed(tool: BaseTool, reason: String) -> void:
	_show_message(reason, "error")
	
	# Request failed hit effect (sparks, clang sound)
	if tool is Pickaxe:
		var pickaxe := tool as Pickaxe
		hit_effect_requested.emit(pickaxe.last_hit_position, pickaxe.last_hit_material_id, false)


func _on_tool_equipped(tool: BaseTool) -> void:
	var tier_name := ToolConstants.get_tier_name(tool.tool_tier)
	_show_message("%s %s equipped" % [tier_name, tool.name], "info")


func _on_tool_unequipped(_tool: BaseTool) -> void:
	pass


func _show_message(message: String, message_type: String = "info") -> void:
	if not show_feedback_messages:
		return
	
	current_message = message
	message_timer = feedback_message_duration
	feedback_message.emit(message, message_type)


## Public method for external callers (e.g., player.gd)
func show_message(message: String, message_type: String = "info") -> void:
	_show_message(message, message_type)


func get_current_message() -> String:
	return current_message


func has_active_message() -> bool:
	return message_timer > 0.0
