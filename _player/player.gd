class_name Player
extends CharacterBody3D

const WALK_SPEED = 5.0
const SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003
const JOY_SENSITIVITY = 2.0 # Higher sensitivity for sticks

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

const WATER_LEVEL = 0.0
const WATER_SURFACE_OFFSET = 1.6 # Camera height/Head
const SWIM_SPEED = 4.0
const SWIM_UP_SPEED = 3.0
const BUOYANCY = 5.0 # Upward force when not moving down


var is_swimming = false
var underwater_effect: Control

var oxygen = 100.0
const MAX_OXYGEN = 100.0
const OXYGEN_DEPLETION_RATE = 10.0 # Seconds to empty = 10
const OXYGEN_REGEN_RATE = 20.0

@onready var camera = $Camera3D

const CLIMB_SPEED = 3.0
const CLIMB_HORIZONTAL_SPEED = 2.0

# Climbing Components
var climb_cast: ShapeCast3D

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("Player")
	_setup_climb_cast()
	_setup_underwater_effect()

func _setup_underwater_effect():
	# 1. UI Overlay (Blue Tint)
	var effect_scene = load("res://_player/underwater_post.tscn")
	if effect_scene:
		# Create a CanvasLayer to ensure Control nodes render over 3D world
		var canvas_layer = CanvasLayer.new()
		add_child(canvas_layer)
		
		underwater_effect = effect_scene.instantiate()
		canvas_layer.add_child(underwater_effect)
		
		# Apply Distortion Shader
		var blue_tint = underwater_effect.get_node("BlueTint")
		if blue_tint:
			var shader = load("res://_assets/shaders/underwater_distortion.gdshader")
			var mat = ShaderMaterial.new()
			mat.shader = shader
			blue_tint.material = mat
		
		# HACK: The scene contains 3D particles that shouldn't be under a CanvasLayer or Control.
		# We need to extract them or handle them separately.
		# Ideally we'd have separate scenes, but let's reparent them here.
		
		var bubbles = underwater_effect.get_node_or_null("Bubbles")
		var fish = underwater_effect.get_node_or_null("FishParticles")
		
		if bubbles:
			bubbles.get_parent().remove_child(bubbles)
			camera.add_child(bubbles) # Bubbles attached to camera
			bubbles.position = Vector3(0, 0, 0.5) # Behind camera (ears level)
			bubbles.emitting = false
			bubbles.name = "Bubbles3D"
			
			# Polish Bubbles: Float UP (Gravity negative)
			# Accessing material programmatically to ensure settings
			var mat: ParticleProcessMaterial = bubbles.process_material.duplicate()
			mat.gravity = Vector3(0, 1.0, 0) # Float UP
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			mat.emission_sphere_radius = 0.8 # Wide area
			mat.alpha_curve = null # Transparent? We need gradient.
			mat.color = Color(1, 1, 1, 0.3) # Transparent
			bubbles.process_material = mat
			
			# Polish Bubble Mesh
			var mesh: SphereMesh = bubbles.draw_pass_1.duplicate()
			mesh.radius = 0.02 # Smaller
			mesh.height = 0.04
			var m_mat = StandardMaterial3D.new()
			m_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m_mat.albedo_color = Color(1, 1, 1, 0.3)
			m_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh.material = m_mat
			bubbles.draw_pass_1 = mesh
		
		if fish:
			fish.get_parent().remove_child(fish)
			add_child(fish) # Fish attached to player base
			fish.emitting = false
			fish.name = "Fish3D"
			
			# Polish Fish: Swirl
			var f_mat: ParticleProcessMaterial = fish.process_material.duplicate()
			f_mat.gravity = Vector3(0, 0, 0)
			f_mat.turbulence_enabled = true
			f_mat.turbulence_noise_strength = 2.0
			f_mat.turbulence_noise_scale = 5.0
			# Flatten mesh for "fish" look
			var f_mesh: BoxMesh = fish.draw_pass_1.duplicate()
			f_mesh.size = Vector3(0.05, 0.1, 0.3) # Thin long fish
			var fm_mat = StandardMaterial3D.new()
			fm_mat.albedo_color = Color(0.2, 0.3, 0.8, 0.6) # Transparent blue
			fm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			f_mesh.material = fm_mat
			fish.draw_pass_1 = f_mesh
			fish.process_material = f_mat

		underwater_effect.visible = false
		# Ensure it covers screen
		underwater_effect.set_anchors_preset(Control.PRESET_FULL_RECT)

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
		# Check water depth
		# If head is below water level -> Swimming
		if global_position.y + 1.2 < WATER_LEVEL: # 1.2 approx chest/neck height
			is_swimming = true
		else:
			is_swimming = false
		
		if underwater_effect:
			underwater_effect.visible = is_swimming
			var bubbles = camera.get_node_or_null("Bubbles3D")
			if bubbles: bubbles.emitting = is_swimming
			
			var fish = get_node_or_null("Fish3D")
			if fish: fish.emitting = is_swimming
		
		# Oxygen logic
		if is_swimming:
			oxygen -= OXYGEN_DEPLETION_RATE * delta
			if oxygen < 0:
				oxygen = 0
				# TODO: Take damage
				# print("Drowning!") 
		else:
			oxygen += OXYGEN_REGEN_RATE * delta
			if oxygen > MAX_OXYGEN: oxygen = MAX_OXYGEN

		if is_swimming:
			_handle_swimming_movement(delta)
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
	
	# Anti-Stuck Mechanism
	_check_and_unstick(delta, input_dir)

func _handle_swimming_movement(delta):
	# Movement similar to fly mode but slower and with buoyancy
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (camera.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Swimming Up (Space) / Down (Ctrl - optional, or just camera look)
	if Input.is_action_pressed("jump"): # Space to ascend
		direction.y += 0.8
	
	# If not moving down, apply buoyancy (float up)
	# Only if not trying to dive
	if direction.y > -0.1 and global_position.y < WATER_LEVEL - 0.5:
		velocity.y += BUOYANCY * delta
		velocity.y = min(velocity.y, 2.0) # Cap upward drift
	
	if direction:
		velocity = velocity.lerp(direction * SWIM_SPEED, delta * 2.0)
	else:
		velocity = velocity.lerp(Vector3(0, velocity.y, 0), delta * 1.0) # Drag
	
	_handle_controller_look(delta)
	move_and_slide()

# Anti-Stuck variables
var _last_position: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0
const STUCK_THRESHOLD: float = 0.3  # seconds of being stuck before nudge
const NUDGE_FORCE: float = 2.0

func _check_and_unstick(delta: float, input_dir: Vector2):
	# Only check if player is trying to move
	if input_dir.length() > 0.1:
		var current_pos = global_position
		var distance_moved = current_pos.distance_to(_last_position)
		
		# If barely moved despite trying
		if distance_moved < 0.05:
			_stuck_timer += delta
			if _stuck_timer > STUCK_THRESHOLD:
				# Nudge player upward to escape geometry
				global_position.y += NUDGE_FORCE * delta * 10.0
				_stuck_timer = 0.0
		else:
			_stuck_timer = 0.0
		
		_last_position = current_pos
	else:
		_stuck_timer = 0.0
		_last_position = global_position

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
