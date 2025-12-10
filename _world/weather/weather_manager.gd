class_name WeatherManager
extends Node3D

enum WeatherState { CLEAR, RAIN, SNOW }
var current_state = WeatherState.CLEAR

var rain_particles: GPUParticles3D
var snow_particles: GPUParticles3D
var player: Node3D

func _ready():
	_setup_particles()
	_update_weather(WeatherState.CLEAR)
	
	# Find player
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0]

func _process(_delta):
	# Follow player
	if player:
		global_position = player.global_position

func set_weather(state: int):
	current_state = state
	_update_weather(state)

func _update_weather(state: int):
	if rain_particles: rain_particles.emitting = (state == WeatherState.RAIN)
	if snow_particles: snow_particles.emitting = (state == WeatherState.SNOW)

func _setup_particles():
	# Rain Setup
	rain_particles = GPUParticles3D.new()
	rain_particles.name = "RainParticles"
	add_child(rain_particles)
	rain_particles.amount = 1000
	rain_particles.lifetime = 1.0
	rain_particles.preprocess = 0.5
	rain_particles.visibility_aabb = AABB(Vector3(-20,-10,-20), Vector3(40,40,40))
	
	var rain_mat = ParticleProcessMaterial.new()
	rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rain_mat.emission_box_extents = Vector3(15, 1, 15)
	rain_mat.direction = Vector3(0, -1, 0)
	rain_mat.initial_velocity_min = 20.0
	rain_mat.initial_velocity_max = 25.0
	rain_particles.process_material = rain_mat
	rain_particles.position = Vector3(0, 15, 0) # Above player
	
	var rain_mesh = QuadMesh.new()
	rain_mesh.size = Vector2(0.05, 1.0) # Long thin streaks
	var rain_draw_mat = StandardMaterial3D.new()
	rain_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_draw_mat.albedo_color = Color(0.6, 0.7, 1.0, 0.6)
	rain_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rain_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	rain_mesh.material = rain_draw_mat
	rain_particles.draw_pass_1 = rain_mesh

	# Snow Setup
	snow_particles = GPUParticles3D.new()
	snow_particles.name = "SnowParticles"
	add_child(snow_particles)
	snow_particles.amount = 500
	snow_particles.lifetime = 3.0
	snow_particles.preprocess = 1.0
	snow_particles.visibility_aabb = AABB(Vector3(-20,-10,-20), Vector3(40,40,40))
	
	var snow_mat = ParticleProcessMaterial.new()
	snow_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	snow_mat.emission_box_extents = Vector3(15, 1, 15)
	snow_mat.direction = Vector3(0, -1, 0)
	snow_mat.spread = 10.0
	snow_mat.gravity = Vector3(0, -2.0, 0) # Slow fall
	snow_mat.initial_velocity_min = 2.0
	snow_mat.initial_velocity_max = 4.0
	snow_mat.turbulence_enabled = true
	snow_mat.turbulence_noise_strength = 2.0
	snow_particles.process_material = snow_mat
	snow_particles.position = Vector3(0, 15, 0)
	
	var snow_mesh = QuadMesh.new()
	snow_mesh.size = Vector2(0.1, 0.1) # Small flakes
	var snow_draw_mat = StandardMaterial3D.new()
	snow_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snow_draw_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	snow_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snow_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	snow_mesh.material = snow_draw_mat
	snow_particles.draw_pass_1 = snow_mesh
