extends CharacterBody3D

# Camera mode enum
enum CameraMode { THIRD_PERSON, FIRST_PERSON }

# Movement parameters
@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var acceleration: float = 10.0
@export var friction: float = 15.0

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

# Camera state variables
var current_camera_mode: CameraMode = CameraMode.THIRD_PERSON
var target_camera_distance: float
var first_person_distance: float = 0.0

# Node references
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D


func _ready() -> void:
	current_stamina = max_stamina
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.position.z = camera_distance
	target_camera_distance = camera_distance
	camera.fov = third_person_fov


func _physics_process(delta: float) -> void:
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
	
	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()


func _apply_gravity(delta: float) -> void:
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
	direction.y = 0.0
	
	# Handle sprinting
	var wants_sprint := Input.is_action_pressed("sprint") and direction.length() > 0.0
	if wants_sprint and current_stamina > 0.0:
		is_sprinting = true
		_consume_stamina(sprint_stamina_cost * delta)
	else:
		is_sprinting = false
	
	var target_speed := sprint_speed if is_sprinting else walk_speed
	
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


func _update_camera_position(delta: float) -> void:
	camera.position.z = lerp(camera.position.z, target_camera_distance, camera_transition_speed * delta)


func _consume_stamina(amount: float) -> void:
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
