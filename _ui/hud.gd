extends CanvasLayer

@export var player_path: NodePath
@export var show_crosshair: bool = true

@onready var player: CharacterBody3D = null
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HBoxContainer/HealthContainer/HealthBar
@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/HBoxContainer/StaminaContainer/StaminaBar
@onready var crosshair: ColorRect = $CenterContainer/Crosshair
@onready var tool_message_label: Label = $ToolMessageLabel
@onready var climbing_indicator: Label = $ClimbingIndicator
@onready var resource_display: HBoxContainer = $ResourceDisplay
@onready var inventory_hint: Label = $InventoryHint
@onready var pickup_prompt: Label = $PickupPrompt

var tool_message_timer: float = 0.0
const TOOL_MESSAGE_DURATION: float = 2.0
var inventory_hint_timer: float = 10.0
const INVENTORY_HINT_DURATION: float = 10.0


func _ready() -> void:
	if player_path:
		player = get_node_or_null(player_path)
	
	if player == null:
		push_warning("HUD: Player node not found at path: %s" % player_path)
	
	# Initialize health bar (placeholder until combat system)
	health_bar.value = 100
	# TODO: Connect to player health system when combat is implemented
	
	# Initialize stamina bar
	if player:
		stamina_bar.max_value = player.get_max_stamina()
		stamina_bar.value = player.get_stamina()
		
		# Connect to ToolManager signals if available
		var tool_manager = player.get_node_or_null("ToolManager")
		if tool_manager:
			tool_manager.tool_action_failed.connect(_on_tool_action_failed)
	
	# Set crosshair visibility
	crosshair.visible = show_crosshair
	
	# Initialize tool message label
	if tool_message_label:
		tool_message_label.visible = false
	
	# Initialize climbing indicator
	if climbing_indicator:
		climbing_indicator.visible = false
	
	# Connect to Inventory signals
	if Inventory:
		Inventory.inventory_changed.connect(_on_inventory_changed)
		Inventory.item_added.connect(_on_item_added)
	
	# Initialize resource display
	_update_resource_display()
	
	# Initialize inventory hint
	if inventory_hint:
		inventory_hint.visible = true
		inventory_hint_timer = INVENTORY_HINT_DURATION


func _process(delta: float) -> void:
	if player == null:
		return
	
	# Update stamina bar
	var current: float = player.get_stamina()
	var maximum: float = player.get_max_stamina()
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	
	# Update tool message timer
	if tool_message_timer > 0.0:
		tool_message_timer -= delta
		if tool_message_timer <= 0.0 and tool_message_label:
			tool_message_label.visible = false
	
	# Update climbing indicator
	if climbing_indicator:
		climbing_indicator.visible = player.is_climbing
	
	# Update inventory hint timer (fade after 10 seconds)
	if inventory_hint_timer > 0.0:
		inventory_hint_timer -= delta
		if inventory_hint and inventory_hint_timer <= 2.0:
			# Fade out over last 2 seconds
			inventory_hint.modulate.a = inventory_hint_timer / 2.0
		if inventory_hint_timer <= 0.0 and inventory_hint:
			inventory_hint.visible = false
	
	# Update pickup prompt
	_update_pickup_prompt()


# TODO: Connect to player health system when combat is implemented
func update_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func _on_tool_action_failed(_tool: Variant, reason: String) -> void:
	if tool_message_label:
		tool_message_label.text = reason
		tool_message_label.visible = true
		tool_message_timer = TOOL_MESSAGE_DURATION


func _on_inventory_changed(_slot_index: int) -> void:
	_update_resource_display()


func _on_item_added(_resource_type: String, _amount: int) -> void:
	_update_resource_display()


func _update_resource_display() -> void:
	if not resource_display or not Inventory:
		return
	
	# Clear existing children except the template ones
	for child in resource_display.get_children():
		if child.name.begins_with("Resource_"):
			child.queue_free()
	
	# Key resources to display
	var key_resources: Array[String] = ["stone", "wood", "iron_ore", "rare_crystal"]
	
	for resource_type in key_resources:
		var count: int = Inventory.get_resource_count(resource_type)
		if count > 0:
			var container := HBoxContainer.new()
			container.name = "Resource_" + resource_type
			container.add_theme_constant_override("separation", 4)
			
			# Icon
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(20, 20)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			
			var info: Dictionary = Inventory.get_resource_info(resource_type)
			var icon_path: String = info.get("icon_path", "")
			if icon_path and ResourceLoader.exists(icon_path):
				icon.texture = load(icon_path)
			else:
				# Create placeholder
				icon.texture = _create_placeholder_icon(resource_type)
			
			container.add_child(icon)
			
			# Count label
			var label := Label.new()
			label.text = str(count)
			label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
			label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
			container.add_child(label)
			
			resource_display.add_child(container)


func _create_placeholder_icon(resource_type: String) -> ImageTexture:
	var color: Color = Color.GRAY
	if MiningSystem:
		color = MiningSystem.get_resource_color(resource_type)
	
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _update_pickup_prompt() -> void:
	if not pickup_prompt:
		return
	
	if not player:
		pickup_prompt.visible = false
		return
	
	var closest_pickup = player.closest_pickup
	if closest_pickup and is_instance_valid(closest_pickup):
		# Check if pickup is invulnerable
		var invuln_timer: float = closest_pickup.get("invulnerability_timer") if closest_pickup.get("invulnerability_timer") != null else 0.0
		if invuln_timer <= 0.0:
			var resource_type: String = closest_pickup.resource_type
			var amount: int = closest_pickup.amount
			pickup_prompt.text = "[E] Pick up %s x%d" % [resource_type.capitalize(), amount]
			pickup_prompt.visible = true
		else:
			pickup_prompt.visible = false
	else:
		pickup_prompt.visible = false
