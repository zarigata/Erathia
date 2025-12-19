extends Node3D
## Water Plane
##
## Creates a large water plane at sea level that follows the player.
## Uses a simple transparent blue material for water appearance.

@export var water_level: float = 0.0
@export var water_size: float = 2000.0  # Size of water plane
@export var water_color: Color = Color(0.1, 0.3, 0.5, 0.7)
@export var follow_player: bool = true

var _water_mesh: MeshInstance3D
var _player: Node3D

func _ready() -> void:
	_create_water_plane()
	
	# Find player
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	if not _player:
		_player = get_node_or_null("../Player")


func _create_water_plane() -> void:
	_water_mesh = MeshInstance3D.new()
	_water_mesh.name = "WaterMesh"
	add_child(_water_mesh)
	
	# Create plane mesh
	var plane := PlaneMesh.new()
	plane.size = Vector2(water_size, water_size)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	_water_mesh.mesh = plane
	
	# Create water material
	var material := StandardMaterial3D.new()
	material.albedo_color = water_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from below too
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	material.metallic = 0.0
	material.roughness = 0.1
	
	# Add subtle emission for underwater glow effect
	material.emission_enabled = true
	material.emission = Color(0.05, 0.1, 0.15)
	material.emission_energy_multiplier = 0.3
	
	_water_mesh.material_override = material
	_water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Position at water level
	_water_mesh.position.y = water_level
	
	print("[WaterPlane] Water plane created at y=%.1f, size=%.0f" % [water_level, water_size])


func _process(_delta: float) -> void:
	if follow_player and _player and _water_mesh:
		# Follow player XZ position
		_water_mesh.global_position.x = _player.global_position.x
		_water_mesh.global_position.z = _player.global_position.z
		# Keep Y at water level
		_water_mesh.global_position.y = water_level


## Update water level
func set_water_level(level: float) -> void:
	water_level = level
	if _water_mesh:
		_water_mesh.position.y = water_level
