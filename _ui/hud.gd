extends CanvasLayer

@export var player_path: NodePath
@export var show_crosshair: bool = true

@onready var player: CharacterBody3D = null
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HBoxContainer/HealthContainer/HealthBar
@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/HBoxContainer/StaminaContainer/StaminaBar
@onready var crosshair: ColorRect = $CenterContainer/Crosshair


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
	
	# Set crosshair visibility
	crosshair.visible = show_crosshair


func _process(_delta: float) -> void:
	if player == null:
		return
	
	# Update stamina bar
	var current: float = player.get_stamina()
	var maximum: float = player.get_max_stamina()
	stamina_bar.max_value = maximum
	stamina_bar.value = current


# TODO: Connect to player health system when combat is implemented
func update_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
