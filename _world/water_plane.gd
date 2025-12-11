extends MeshInstance3D

@export var follow_target: Node3D
@export var update_interval: float = 0.1

var timer: float = 0.0

func _process(delta):
	if not follow_target:
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			follow_target = players[0]
		return

	timer += delta
	if timer >= update_interval:
		timer = 0.0
		# Snap to a grid to avoid jittering UVs if the shader uses world coordinates
		# But since our shader uses world_pos for noise, smooth movement is fine if handled correctly.
		# For simplicity, we just follow the player's XZ.
		global_position.x = follow_target.global_position.x
		global_position.z = follow_target.global_position.z
		# Keep Y at 0 or whatever the water level is set to in editor
		
		# Pass player pos to shader for ripples
		var mat = get_active_material(0)
		if mat:
			mat.set_shader_parameter("player_pos", follow_target.global_position)
			
			# Ensure noise textures are present (Fix for flat water)
			if not mat.get_shader_parameter("wave"):
				var noise = FastNoiseLite.new()
				noise.noise_type = FastNoiseLite.TYPE_PERLIN
				noise.frequency = 0.02
				var noise_tex = NoiseTexture2D.new()
				noise_tex.noise = noise
				noise_tex.seamless = true
				mat.set_shader_parameter("wave", noise_tex)
				mat.set_shader_parameter("texture_normal", noise_tex)
				mat.set_shader_parameter("texture_normal2", noise_tex)
