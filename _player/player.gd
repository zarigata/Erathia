class_name Player
extends CharacterBody3D

const WALK_SPEED = 5.0
const SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003
const JOY_SENSITIVITY = 2.0 # Higher sensitivity for sticks

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera = $Camera3D

const CLIMB_SPEED = 3.0
const CLIMB_HORIZONTAL_SPEED = 2.0

# Climbing Components
var climb_cast: ShapeCast3D

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("Player")
	_setup_climb_cast()

func _setup_climb_cast():
	climb_cast = ShapeCast3D.new()
	add_child(climb_cast)
	climb_cast.shape = CylinderShape3D.new()
	climb_cast.shape.radius = 0.5
	climb_cast.shape.height = 1.0
	climb_cast.position = Vector3(0, 1.0, 0) # Chest height
	climb_cast.target_position = Vector3(0, 0, -0.8) # Forward cast
	climb_cast.max_results = 1
	climb_cast.collision_mask = 1 # Terrain layer usually 1
	climb_cast.enabled = true

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

# Cheat Modes
var fly_mode = false
var noclip_mode = false

func toggle_fly_mode():
	fly_mode = not fly_mode
	if not fly_mode: noclip_mode = false # turning off fly turns off noclip
	if not fly_mode:
		collision_mask = 1 # Reset collision
	
	if fly_mode:
		velocity = Vector3.ZERO

func toggle_noclip_mode():
	noclip_mode = not noclip_mode
	fly_mode = noclip_mode # noclip implies fly
	
	if noclip_mode:
		collision_mask = 0 # No collision
	else:
		collision_mask = 1

func _physics_process(delta):
	if fly_mode:
		_handle_fly_movement(delta)
	else:
		var is_climbing = false
		if not is_on_floor():
			# Check for climbing
			if Input.is_action_pressed("move_forward") and climb_cast.is_colliding():
				is_climbing = true
		
		if is_climbing:
			_handle_climb_movement(delta)
		else:
			_handle_standard_movement(delta)

func _handle_climb_movement(delta):
	# Climbing Logic (Blue Zone)
	velocity.y = CLIMB_SPEED
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * CLIMB_HORIZONTAL_SPEED
		velocity.z = direction.z * CLIMB_HORIZONTAL_SPEED
		
	_handle_controller_look(delta)
	move_and_slide()

func _handle_standard_movement(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# Handle Sprint
	var current_speed = WALK_SPEED
	if Input.is_action_pressed("sprint"):
		current_speed = SPRINT_SPEED

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
		
	# Controller Look (Right Stick)
	_handle_controller_look(delta)

	move_and_slide()

func _handle_fly_movement(delta):
	var speed = SPRINT_SPEED * 2.0 if Input.is_action_pressed("sprint") else SPRINT_SPEED
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (camera.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Vertical movement with Jump/Crouch (Space/Ctrl or similar)
	if Input.is_action_pressed("jump"):
		direction.y += 1.0
	# We don't have a crouch action mapped yet, let's just use camera pitch components for now in "direction"
	
	if direction:
		velocity = direction * speed
	else:
		velocity = Vector3.ZERO
		
	_handle_controller_look(delta)
	move_and_slide()

func _handle_controller_look(delta):
	# Simple Right Stick support (Axes 2 and 3 usually)
	var look_vector = Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	
	if look_vector.length() > 0.1:
		rotate_y(-look_vector.x * JOY_SENSITIVITY * delta)
		camera.rotate_x(-look_vector.y * JOY_SENSITIVITY * delta)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))
