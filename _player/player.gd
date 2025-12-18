extends CharacterBody3D

# Camera mode enum
enum CameraMode { THIRD_PERSON, FIRST_PERSON }

# Movement parameters
@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var acceleration: float = 10.0
@export var friction: float = 15.0
@export var climb_speed: float = 3.0
@export var climb_detection_distance: float = 1.5
@export var climb_angle_threshold: float = 50.0
@export var climb_stamina_cost: float = 20.0

# Jump parameters
@export_group("Jump")
@export var jump_velocity: float = 6.0
@export var jump_stamina_cost: float = 25.0

# Stamina parameters
@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var stamina_regen_rate: float = 20.0
@export var stamina_regen_delay: float = 1.0
@export var sprint_stamina_cost: float = 15.0

# Camera parameters
@export_group("Camera")
@export var mouse_sensitivity: float = 0.002
@export var camera_distance: float = 3.0
@export var min_pitch: float = -60.0
@export var max_pitch: float = 60.0

# Camera View parameters
@export_group("Camera View")
@export var first_person_fov: float = 90.0
@export var third_person_fov: float = 75.0
@export var camera_transition_speed: float = 10.0
@export var first_person_min_pitch: float = -89.0
@export var first_person_max_pitch: float = 89.0

# Physics
@export_group("Physics")
@export var gravity: float = 15.0

# State variables
var current_stamina: float
var stamina_regen_timer: float = 0.0
var is_sprinting: bool = false

# Raycast visualization state
var raycast_update_timer: float = 0.0
var last_raycast_hit: VoxelRaycastResult = null
var raycast_hit_marker: MeshInstance3D = null
var raycast_normal_indicator: MeshInstance3D = null

# Climbing state
var is_climbing: bool = false
var climb_surface_normal: Vector3 = Vector3.ZERO

# Camera state variables
var current_camera_mode: CameraMode = CameraMode.THIRD_PERSON
var target_camera_distance: float
var first_person_distance: float = 0.0

# Pickup detection
var nearby_pickups: Array[Node3D] = []
var closest_pickup: Node3D = null
var pickup_detector: Area3D = null

# Cheat state variables (controlled by DevConsole)
var god_mode_active: bool = false
var fly_mode_active: bool = false
var noclip_active: bool = false
var speed_multiplier: float = 1.0
var _original_collision_layer: int = 0
var _original_collision_mask: int = 0

# Node references
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var tool_manager: ToolManager = $ToolManager
@onready var tool_feedback: ToolFeedback = $ToolFeedback


func _ready() -> void:
	current_stamina = max_stamina
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.position.z = camera_distance
	target_camera_distance = camera_distance
	camera.fov = third_person_fov
	_setup_raycast_visualization()
	_setup_default_tool()
	_setup_pickup_detector()
	_setup_cheat_integration()
	
	# Add to player group for easy lookup
	add_to_group("player")


func _physics_process(delta: float) -> void:
	_handle_climbing(delta)
	if not is_climbing:
		_apply_gravity(delta)
	_handle_movement(delta)
	_handle_jump()
	move_and_slide()
	_handle_stamina_regen(delta)
	_update_camera_position(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_handle_camera_rotation(event)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	_handle_camera_toggle(event)
	_handle_tool_switching(event)
	
	if event.is_action_pressed("toggle_raycast_viz"):
		show_raycast_visualization = not show_raycast_visualization
		if not show_raycast_visualization:
			_hide_raycast_markers()
	
	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()


func _apply_gravity(delta: float) -> void:
	# Skip gravity in fly mode
	if fly_mode_active:
		return
	
	if not is_on_floor():
		velocity.y -= gravity * delta


func _handle_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_dir.y = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	
	var direction := Vector3.ZERO
	direction.x = input_dir.x
	direction.z = input_dir.y
	direction = global_transform.basis * direction
	
	# In fly mode, allow vertical movement and don't zero Y
	if fly_mode_active:
		_handle_fly_movement(delta, direction)
		return
	
	direction.y = 0.0
	
	# Handle sprinting
	var wants_sprint := Input.is_action_pressed("sprint") and direction.length() > 0.0
	if wants_sprint and current_stamina > 0.0:
		is_sprinting = true
		if not god_mode_active:
			_consume_stamina(sprint_stamina_cost * delta)
	else:
		is_sprinting = false
	
	var target_speed := sprint_speed if is_sprinting else walk_speed
	target_speed *= speed_multiplier
	
	if direction.length() > 0.0:
		var target_velocity := direction.normalized() * target_speed
		velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, friction * delta)
		velocity.z = lerp(velocity.z, 0.0, friction * delta)


func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor() and current_stamina >= jump_stamina_cost:
		velocity.y = jump_velocity
		_consume_stamina(jump_stamina_cost)


func _handle_climbing(delta: float) -> void:
	var climb_data := _detect_climbable_surface()
	
	# Check if we can climb: surface detected, forward pressed, has stamina
	var forward_pressed := Input.get_action_strength("move_forward") > 0.5
	
	if climb_data["can_climb"] and forward_pressed and current_stamina > 0.0:
		is_climbing = true
		climb_surface_normal = climb_data["normal"]
		
		# Apply upward velocity
		velocity.y = climb_speed
		
		# Apply slight forward movement along surface
		var forward_dir := -global_transform.basis.z
		forward_dir.y = 0.0
		forward_dir = forward_dir.normalized()
		velocity.x = forward_dir.x * climb_speed * 0.3
		velocity.z = forward_dir.z * climb_speed * 0.3
		
		# Consume stamina
		_consume_stamina(climb_stamina_cost * delta)
	else:
		is_climbing = false
		climb_surface_normal = Vector3.ZERO


func _detect_climbable_surface() -> Dictionary:
	var result := {"can_climb": false, "normal": Vector3.ZERO, "position": Vector3.ZERO}
	
	if not TerrainEditSystem:
		return result
	
	# Cast raycasts forward from player at chest height
	var chest_offset := Vector3(0, 0.8, 0)
	var origin := global_position + chest_offset
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	
	# Cast 3 rays: center, left, right
	var ray_offsets := [
		Vector3.ZERO,
		global_transform.basis.x * 0.3,
		-global_transform.basis.x * 0.3
	]
	
	for i in range(ray_offsets.size()):
		var offset: Vector3 = ray_offsets[i]
		var ray_origin: Vector3 = origin + offset
		var hit := TerrainEditSystem.raycast(ray_origin, forward, climb_detection_distance)
		
		if hit:
			var slope_angle := _calculate_slope_angle(hit.normal)
			if slope_angle >= climb_angle_threshold:
				result["can_climb"] = true
				result["normal"] = hit.normal
				result["position"] = hit.position
				return result
	
	return result


func _calculate_slope_angle(normal: Vector3) -> float:
	# Calculate angle between surface normal and Vector3.UP
	var dot := normal.dot(Vector3.UP)
	var angle_rad := acos(clampf(dot, -1.0, 1.0))
	return rad_to_deg(angle_rad)


func _handle_stamina_regen(delta: float) -> void:
	if stamina_regen_timer > 0.0:
		stamina_regen_timer -= delta
	elif current_stamina < max_stamina:
		current_stamina += stamina_regen_rate * delta
		current_stamina = clampf(current_stamina, 0.0, max_stamina)


func _handle_camera_rotation(event: InputEventMouseMotion) -> void:
	rotation.y -= event.relative.x * mouse_sensitivity
	camera_pivot.rotation.x -= event.relative.y * mouse_sensitivity
	
	var current_min_pitch: float
	var current_max_pitch: float
	if current_camera_mode == CameraMode.FIRST_PERSON:
		current_min_pitch = first_person_min_pitch
		current_max_pitch = first_person_max_pitch
	else:
		current_min_pitch = min_pitch
		current_max_pitch = max_pitch
	
	camera_pivot.rotation.x = clampf(
		camera_pivot.rotation.x,
		deg_to_rad(current_min_pitch),
		deg_to_rad(current_max_pitch)
	)


func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _handle_camera_toggle(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera_view"):
		if current_camera_mode == CameraMode.THIRD_PERSON:
			current_camera_mode = CameraMode.FIRST_PERSON
			target_camera_distance = first_person_distance
			camera.fov = first_person_fov
		else:
			current_camera_mode = CameraMode.THIRD_PERSON
			target_camera_distance = camera_distance
			camera.fov = third_person_fov


func _handle_tool_switching(event: InputEvent) -> void:
	if event.is_action_pressed("equip_pickaxe") and pickaxe_instance:
		if tool_manager:
			tool_manager.equip_tool(pickaxe_instance)
	elif event.is_action_pressed("equip_shovel") and shovel_instance:
		if tool_manager:
			tool_manager.equip_tool(shovel_instance)
	elif event.is_action_pressed("toggle_smooth_mode"):
		var current_tool := tool_manager.get_current_tool() if tool_manager else null
		if current_tool is Shovel:
			(current_tool as Shovel).toggle_smooth_mode()
			if tool_feedback:
				var mode_name := "Smooth" if (current_tool as Shovel).smooth_mode else "Dig"
				tool_feedback.show_message("Shovel mode: %s" % mode_name)


func _update_camera_position(delta: float) -> void:
	camera.position.z = lerp(camera.position.z, target_camera_distance, camera_transition_speed * delta)


# =============================================================================
# CHEAT INTEGRATION (DevConsole)
# =============================================================================

func _setup_cheat_integration() -> void:
	# Store original collision settings
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask
	
	# Connect to DevConsole if available
	if DevConsole:
		DevConsole.cheat_toggled.connect(_on_cheat_toggled)


func _on_cheat_toggled(cheat_name: String, enabled: bool) -> void:
	match cheat_name:
		"god":
			god_mode_active = enabled
			if enabled:
				current_stamina = max_stamina
		"fly":
			fly_mode_active = enabled
			if enabled:
				velocity.y = 0.0
		"noclip":
			noclip_active = enabled
			if enabled:
				collision_layer = 0
				collision_mask = 0
			else:
				collision_layer = _original_collision_layer
				collision_mask = _original_collision_mask
		"speed":
			if DevConsole:
				speed_multiplier = DevConsole.speed_multiplier


func _handle_fly_movement(delta: float, direction: Vector3) -> void:
	# Vertical movement with jump/crouch
	var vertical_input := 0.0
	if Input.is_action_pressed("jump"):
		vertical_input = 1.0
	elif Input.is_action_pressed("sprint"):
		vertical_input = -1.0
	
	direction.y = vertical_input
	
	var fly_speed := sprint_speed * speed_multiplier * 1.5
	
	if direction.length() > 0.0:
		var target_velocity := direction.normalized() * fly_speed
		velocity = velocity.lerp(target_velocity, acceleration * delta)
	else:
		velocity = velocity.lerp(Vector3.ZERO, friction * delta)


## Apply a cheat state directly (called by DevConsole)
func apply_cheat_state(cheat: String, value: Variant) -> void:
	match cheat:
		"god":
			god_mode_active = value as bool
		"fly":
			fly_mode_active = value as bool
		"noclip":
			_on_cheat_toggled("noclip", value as bool)
		"speed":
			speed_multiplier = value as float


func _consume_stamina(amount: float) -> void:
	# Skip stamina consumption in god mode
	if god_mode_active:
		return
	
	current_stamina -= amount
	current_stamina = clampf(current_stamina, 0.0, max_stamina)
	stamina_regen_timer = stamina_regen_delay


# Public API for future HUD and tool integration
func get_stamina() -> float:
	return current_stamina


func get_max_stamina() -> float:
	return max_stamina


func consume_stamina(amount: float) -> bool:
	if current_stamina >= amount:
		_consume_stamina(amount)
		return true
	return false


func get_camera() -> Camera3D:
	return camera


# ============================================================================
# TERRAIN EDITING TEST CONTROLS
# ============================================================================

@export_group("Terrain Editing")
@export var terrain_edit_enabled: bool = true
@export var terrain_edit_distance: float = 10.0
@export var terrain_brush_radius: float = 2.0
@export var terrain_brush_strength: float = 5.0
@export var terrain_tool_tier: int = 1
@export var show_raycast_visualization: bool = true
@export var raycast_update_rate: float = 0.05


func _process(delta: float) -> void:
	_handle_pickup_interaction()
	
	if not terrain_edit_enabled:
		_hide_raycast_markers()
		return
	
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_hide_raycast_markers()
		return
	
	_update_raycast_visualization(delta)
	_handle_terrain_editing()


func _handle_terrain_editing() -> void:
	# Digging is now handled by ToolManager via equipped tool
	# Only handle building here (right-click)
	var build_pressed := Input.is_action_just_pressed("terrain_build")
	
	if not build_pressed:
		return
	
	if not TerrainEditSystem:
		push_warning("[Player] TerrainEditSystem not available")
		return
	
	var hit := TerrainEditSystem.raycast_from_camera(camera, terrain_edit_distance)
	
	if not hit:
		return
	
	# Check for required resources before building
	if Inventory and not Inventory.has_resources({"stone": 1}):
		if tool_feedback:
			tool_feedback.show_message("Not enough stone!")
		return
	
	# Consume resources
	if Inventory:
		Inventory.remove_resource("stone", 1)
	
	TerrainEditSystem.apply_brush(
		hit.position,
		TerrainEditSystem.BrushType.SPHERE,
		TerrainEditSystem.Operation.ADD,
		terrain_brush_radius,
		terrain_brush_strength,
		terrain_tool_tier
	)


# ============================================================================
# RAYCAST VISUALIZATION
# ============================================================================

func _setup_raycast_visualization() -> void:
	# Create hit marker sphere
	raycast_hit_marker = MeshInstance3D.new()
	raycast_hit_marker.name = "RaycastHitMarker"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.12
	sphere_mesh.height = 0.24
	raycast_hit_marker.mesh = sphere_mesh
	
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(0.0, 1.0, 1.0, 0.6)  # Cyan
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	raycast_hit_marker.material_override = marker_material
	raycast_hit_marker.visible = false
	add_child(raycast_hit_marker)
	
	# Create normal indicator arrow
	raycast_normal_indicator = MeshInstance3D.new()
	raycast_normal_indicator.name = "RaycastNormalIndicator"
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = 0.02
	cylinder_mesh.bottom_radius = 0.02
	cylinder_mesh.height = 0.5
	raycast_normal_indicator.mesh = cylinder_mesh
	
	var normal_material := StandardMaterial3D.new()
	normal_material.albedo_color = Color(0.0, 1.0, 0.0, 0.8)  # Green
	normal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	normal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	raycast_normal_indicator.material_override = normal_material
	raycast_normal_indicator.visible = false
	add_child(raycast_normal_indicator)


func _update_raycast_visualization(delta: float) -> void:
	if not show_raycast_visualization or not terrain_edit_enabled:
		_hide_raycast_markers()
		return
	
	raycast_update_timer -= delta
	if raycast_update_timer > 0.0:
		return
	
	raycast_update_timer = raycast_update_rate
	
	if not TerrainEditSystem:
		_hide_raycast_markers()
		return
	
	var hit := TerrainEditSystem.raycast_from_camera(camera, terrain_edit_distance)
	last_raycast_hit = hit
	
	if hit:
		_show_raycast_markers(hit)
	else:
		_hide_raycast_markers()


func _show_raycast_markers(hit: VoxelRaycastResult) -> void:
	# Position hit marker at terrain surface
	raycast_hit_marker.global_position = Vector3(hit.position)
	raycast_hit_marker.visible = true
	
	# Update marker color based on tool hardness check
	_update_marker_color_for_hardness(hit)
	
	# Position and orient normal indicator
	if hit.normal.length_squared() > 0.01:  # Check if normal is valid
		var normal_start := Vector3(hit.position)
		var normal_end := normal_start + hit.normal * 0.5  # 0.5m arrow length
		
		raycast_normal_indicator.global_position = normal_start + hit.normal * 0.25
		# Avoid colinear vectors by using a different up vector when normal is close to UP
		var up_vector := Vector3.FORWARD if absf(hit.normal.dot(Vector3.UP)) > 0.99 else Vector3.UP
		raycast_normal_indicator.look_at(normal_end, up_vector)
		raycast_normal_indicator.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
		raycast_normal_indicator.visible = true
	else:
		raycast_normal_indicator.visible = false


func _hide_raycast_markers() -> void:
	if raycast_hit_marker:
		raycast_hit_marker.visible = false
	if raycast_normal_indicator:
		raycast_normal_indicator.visible = false


func _update_marker_color_for_hardness(hit: VoxelRaycastResult) -> void:
	if not raycast_hit_marker or not raycast_hit_marker.material_override:
		return
	
	var marker_material := raycast_hit_marker.material_override as StandardMaterial3D
	if not marker_material:
		return
	
	# Default color: cyan (can mine)
	var color := Color(0.0, 1.0, 1.0, 0.6)
	
	# Check if we have an equipped tool
	if tool_manager and tool_manager.has_tool_equipped():
		var current_tool := tool_manager.get_current_tool()
		var material_id := -1
		var can_use := false
		var durability_percent := 1.0
		
		if current_tool is Pickaxe:
			var pickaxe := current_tool as Pickaxe
			material_id = pickaxe.get_material_at_position(Vector3(hit.position))
			can_use = pickaxe.can_mine_material(material_id)
			durability_percent = pickaxe.get_durability_percent()
		elif current_tool is Shovel:
			var shovel := current_tool as Shovel
			material_id = shovel.get_material_at_position(Vector3(hit.position))
			can_use = shovel.can_dig_material(material_id)
			durability_percent = shovel.get_durability_percent()
		
		if material_id >= 0:
			if not can_use:
				# Red: too hard for current tool
				color = Color(1.0, 0.2, 0.2, 0.6)
			elif durability_percent < 0.2:
				# Yellow: low durability warning
				color = Color(1.0, 1.0, 0.0, 0.6)
			else:
				# Green: can use
				color = Color(0.2, 1.0, 0.2, 0.6)
	
	marker_material.albedo_color = color


# Tool references
var pickaxe_instance: Pickaxe = null
var shovel_instance: Shovel = null


func _setup_default_tool() -> void:
	# Instantiate pickaxe
	var pickaxe_scene := preload("res://_player/tools/pickaxe.tscn")
	pickaxe_instance = pickaxe_scene.instantiate() as Pickaxe
	camera_pivot.add_child(pickaxe_instance)
	pickaxe_instance.position = Vector3(0.4, -0.3, -0.6)
	
	# Instantiate shovel
	var shovel_scene := preload("res://_player/tools/shovel.tscn")
	shovel_instance = shovel_scene.instantiate() as Shovel
	camera_pivot.add_child(shovel_instance)
	shovel_instance.position = Vector3(0.4, -0.3, -0.6)
	shovel_instance.visible = false
	
	# Equip pickaxe by default
	if tool_manager:
		tool_manager.equip_tool(pickaxe_instance)


# ============================================================================
# PICKUP DETECTION SYSTEM
# ============================================================================

func _setup_pickup_detector() -> void:
	pickup_detector = Area3D.new()
	pickup_detector.name = "PickupDetector"
	add_child(pickup_detector)
	
	var collision_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.5
	collision_shape.shape = sphere
	pickup_detector.add_child(collision_shape)
	
	pickup_detector.body_entered.connect(_on_pickup_detector_body_entered)
	pickup_detector.body_exited.connect(_on_pickup_detector_body_exited)
	pickup_detector.area_entered.connect(_on_pickup_detector_area_entered)
	pickup_detector.area_exited.connect(_on_pickup_detector_area_exited)


func _on_pickup_detector_body_entered(body: Node3D) -> void:
	if body.is_in_group("pickups"):
		nearby_pickups.append(body)
		_update_closest_pickup()


func _on_pickup_detector_body_exited(body: Node3D) -> void:
	nearby_pickups.erase(body)
	_update_closest_pickup()


func _on_pickup_detector_area_entered(area: Node3D) -> void:
	var parent := area.get_parent()
	if parent and parent.is_in_group("pickups"):
		if not nearby_pickups.has(parent):
			nearby_pickups.append(parent)
			_update_closest_pickup()


func _on_pickup_detector_area_exited(area: Node3D) -> void:
	var parent := area.get_parent()
	nearby_pickups.erase(parent)
	_update_closest_pickup()


func _update_closest_pickup() -> void:
	closest_pickup = null
	var closest_distance: float = INF
	
	# Clean up invalid references
	var valid_pickups: Array[Node3D] = []
	for pickup in nearby_pickups:
		if is_instance_valid(pickup):
			valid_pickups.append(pickup)
	nearby_pickups = valid_pickups
	
	for pickup in nearby_pickups:
		var distance: float = global_position.distance_to(pickup.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_pickup = pickup


func _handle_pickup_interaction() -> void:
	if Input.is_action_just_pressed("pickup_item") and closest_pickup:
		if closest_pickup.has_method("attempt_pickup"):
			var success: bool = closest_pickup.attempt_pickup(self)
			if success and tool_feedback:
				var resource_type: String = closest_pickup.resource_type
				var amount: int = closest_pickup.amount
				tool_feedback.show_message("Picked up %s x%d" % [resource_type.capitalize(), amount])
