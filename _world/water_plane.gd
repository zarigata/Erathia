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
