## ResourcePickup - Physical resource drop that can be collected by the player
##
## Spawned by MiningSystem when terrain is mined. Uses RigidBody3D for physics-based
## scatter effect. Player collects by walking near the pickup.
extends RigidBody3D

## Type of resource ("stone", "iron_ore", etc.)
@export var resource_type: String = "stone"
## Amount of resource in this pickup
@export var amount: int = 1
## Delay before pickup can be collected (prevents instant pickup during spawn)
@export var pickup_delay: float = 0.5
## Time before pickup despawns (seconds)
@export var lifetime: float = 300.0
## Distance at which pickup is attracted to player (0 = disabled)
@export var magnetic_range: float = 0.0
## Speed of magnetic attraction
@export var magnetic_speed: float = 8.0
## Enable magnetic attraction behavior
@export var enable_magnetic_attraction: bool = false
## Duration of invulnerability after being dropped by player
@export var invulnerability_duration: float = 2.0

## Whether pickup can be collected yet
var can_be_picked_up: bool = false
## Reference to player for magnetic attraction
var _player: Node3D = null
## Time since spawn
var _time_alive: float = 0.0
## Bobbing animation offset
var _bob_offset: float = 0.0
## Initial Y position for bobbing
var _base_y: float = 0.0
## Whether we're being magnetically attracted
var _is_attracted: bool = false
## Whether this pickup was dropped by the player
var dropped_by_player: bool = false
## Remaining invulnerability time (cannot be picked up while > 0)
var invulnerability_timer: float = 0.0
## Whether player is currently nearby
var _player_nearby: bool = false
## Original material for restoring after invulnerability
var _original_material: Material = null

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D
@onready var pickup_area: Area3D = $PickupArea
@onready var pickup_timer: Timer = $PickupTimer
@onready var lifetime_timer: Timer = $LifetimeTimer


func _ready() -> void:
	# Setup visual appearance based on resource type
	_setup_visuals()
	
	# Update label
	_update_label()
	
	# Connect signals
	pickup_area.body_entered.connect(_on_pickup_area_body_entered)
	pickup_timer.timeout.connect(_on_pickup_timer_timeout)
	lifetime_timer.timeout.connect(_on_lifetime_timer_timeout)
	
	# Start timers
	pickup_timer.wait_time = pickup_delay
	pickup_timer.one_shot = true
	pickup_timer.start()
	
	lifetime_timer.wait_time = lifetime
	lifetime_timer.one_shot = true
	lifetime_timer.start()
	
	# Apply random spawn impulse for scatter effect
	_apply_spawn_impulse()
	
	# Random bob offset so pickups don't all bob in sync
	_bob_offset = randf() * TAU
	
	# Find player reference
	_find_player()
	
	# Add to pickups group for easy querying
	add_to_group("pickups")


func _physics_process(delta: float) -> void:
	_time_alive += delta
	
	# Update invulnerability timer
	if invulnerability_timer > 0.0:
		invulnerability_timer -= delta
		if invulnerability_timer <= 0.0:
			_restore_normal_appearance()
	
	# Bobbing animation (only when not moving fast)
	if linear_velocity.length() < 0.5 and can_be_picked_up:
		if _base_y == 0.0:
			_base_y = global_position.y
		
		var bob_amount: float = sin(_time_alive * 3.0 + _bob_offset) * 0.1
		global_position.y = _base_y + bob_amount
	
	# Magnetic attraction to player (only if enabled)
	if enable_magnetic_attraction and can_be_picked_up and invulnerability_timer <= 0.0 and _player and is_instance_valid(_player):
		var distance: float = global_position.distance_to(_player.global_position)
		
		if distance < magnetic_range and magnetic_range > 0.0:
			_is_attracted = true
			# Disable physics and move toward player
			freeze = true
			var direction: Vector3 = (_player.global_position - global_position).normalized()
			global_position += direction * magnetic_speed * delta
		elif _is_attracted:
			# Was attracted but player moved away
			_is_attracted = false
			freeze = false


func _setup_visuals() -> void:
	if not mesh_instance:
		return
	
	# Get color from MiningSystem
	var color: Color = Color.WHITE
	if MiningSystem:
		color = MiningSystem.get_resource_color(resource_type)
	
	# Create material
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.3
	material.emission_energy_multiplier = 0.5
	
	mesh_instance.material_override = material


func _update_label() -> void:
	if not label:
		return
	
	# Capitalize resource type for display
	var display_name: String = resource_type.capitalize().replace("_", " ")
	
	if amount > 1:
		label.text = "%s x%d" % [display_name, amount]
	else:
		label.text = display_name
	
	# Make label always face camera
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _apply_spawn_impulse() -> void:
	# Random upward and outward impulse
	var impulse := Vector3(
		randf_range(-2.0, 2.0),
		randf_range(3.0, 5.0),
		randf_range(-2.0, 2.0)
	)
	apply_impulse(impulse)


func _find_player() -> void:
	# Try to find player in scene
	_player = get_tree().get_first_node_in_group("player")
	
	if not _player:
		# Try by name
		_player = get_tree().root.find_child("Player", true, false)


func _on_pickup_area_body_entered(body: Node3D) -> void:
	if not can_be_picked_up:
		return
	
	# Check if body is player - mark as nearby but don't auto-collect
	if body.is_in_group("player") or body.name == "Player":
		_player_nearby = true
		# Only auto-collect if magnetic attraction is enabled and not invulnerable
		if enable_magnetic_attraction and invulnerability_timer <= 0.0:
			_collect()


func _on_pickup_timer_timeout() -> void:
	can_be_picked_up = true


func _on_lifetime_timer_timeout() -> void:
	# Despawn with fade effect
	_despawn()


func _collect() -> void:
	# Prevent double collection
	can_be_picked_up = false
	
	# Add directly to Inventory singleton
	var overflow: int = 0
	if Inventory:
		overflow = Inventory.add_resource(resource_type, amount)
		# Emit MiningSystem signal for statistics/achievements
		if MiningSystem:
			var collected_amount: int = amount - overflow
			if collected_amount > 0:
				MiningSystem.resource_collected.emit(resource_type, collected_amount)
	else:
		# Fallback to MiningSystem if Inventory not available
		if MiningSystem:
			overflow = MiningSystem.collect_resource(resource_type, amount)
	
	# Handle overflow: spawn new pickup with remaining amount
	if overflow > 0:
		_spawn_overflow_pickup(overflow)
	
	# Play collection feedback
	_play_collect_feedback()
	
	# Remove from scene
	queue_free()


func _spawn_overflow_pickup(overflow_amount: int) -> void:
	# Spawn a new pickup with the overflow amount
	if MiningSystem:
		MiningSystem.spawn_pickup(resource_type, overflow_amount, global_position)


func _play_collect_feedback() -> void:
	# Spawn floating text (optional - could be enhanced with actual floating text scene)
	# For now, just print
	print("[ResourcePickup] Collected %s x%d" % [resource_type, amount])
	
	# TODO: Add particle effect
	# TODO: Add sound effect


func _despawn() -> void:
	# Could add fade-out effect here
	queue_free()


## Called externally to force collection (e.g., by inventory magnet upgrade)
func force_collect() -> void:
	if can_be_picked_up:
		_collect()


## Attempt to pick up this item manually (called by player)
## @param player: The player attempting pickup
## @return: True if pickup was successful
func attempt_pickup(player: Node3D) -> bool:
	if not can_be_picked_up:
		return false
	
	if invulnerability_timer > 0.0:
		return false
	
	_player = player
	_collect()
	return true


## Mark this pickup as dropped by player (enables invulnerability)
func set_dropped_by_player() -> void:
	dropped_by_player = true
	invulnerability_timer = invulnerability_duration
	_apply_invulnerability_appearance()


## Apply visual indicator for invulnerability (red tint)
func _apply_invulnerability_appearance() -> void:
	if mesh_instance and mesh_instance.material_override:
		_original_material = mesh_instance.material_override.duplicate()
		var invuln_material := mesh_instance.material_override as StandardMaterial3D
		if invuln_material:
			invuln_material.albedo_color = Color(1.0, 0.3, 0.3, 0.6)
			invuln_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


## Restore normal appearance after invulnerability ends
func _restore_normal_appearance() -> void:
	if mesh_instance and _original_material:
		mesh_instance.material_override = _original_material
		_original_material = null
	elif mesh_instance:
		_setup_visuals()  # Re-setup if no original saved
