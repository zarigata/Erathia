extends Node3D
## Node Inspector for X-Ray Mode
##
## Creates floating labels showing node information when X-Ray is active.
## Managed as child of XRayManager.

var _is_active: bool = false
var _label_cache: Dictionary = {}  # node instance_id -> Label3D
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.5
var _max_distance: float = 50.0
const MAX_DISTANCE: float = 50.0  # Default

var _info_label: Label3D = null


func _ready() -> void:
	_create_info_label()


func _create_info_label() -> void:
	_info_label = Label3D.new()
	_info_label.name = "InfoLabel"
	_info_label.pixel_size = 0.005
	_info_label.font_size = 32
	_info_label.outline_size = 8
	_info_label.modulate = Color.CYAN
	_info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_info_label.no_depth_test = true
	_info_label.visible = false
	add_child(_info_label)


func set_active(active: bool) -> void:
	_is_active = active
	if not active:
		_clear_labels()
		if _info_label:
			_info_label.visible = false


func _clear_labels() -> void:
	for label in _label_cache.values():
		if is_instance_valid(label):
			label.queue_free()
	_label_cache.clear()


func _process(delta: float) -> void:
	if not _is_active:
		return
	
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	
	_update_timer = UPDATE_INTERVAL
	_update_raycast_info()


func _update_raycast_info() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		if _info_label:
			_info_label.visible = false
		return
	
	# Raycast from camera
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * _max_distance
	
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result := space_state.intersect_ray(query)
	
	if result.is_empty():
		if _info_label:
			_info_label.visible = false
		return
	
	var hit_pos: Vector3 = result.position
	var hit_normal: Vector3 = result.normal
	var collider: Object = result.collider
	
	if not _info_label:
		return
	
	# Build info text
	var lines: Array[String] = []
	
	if collider:
		lines.append("[%s]" % collider.name)
		lines.append("Type: %s" % collider.get_class())
	
	var distance := from.distance_to(hit_pos)
	lines.append("Distance: %.1fm" % distance)
	
	# Get biome info
	if BiomeManager and BiomeManager.has_method("get_biome_at_position"):
		var biome := BiomeManager.get_biome_at_position(hit_pos)
		lines.append("Biome: %s" % biome)
	
	# Get material info from terrain
	if TerrainEditSystem and TerrainEditSystem.has_method("get_material_at_position"):
		var mat_id: int = TerrainEditSystem.get_material_at_position(hit_pos)
		if mat_id >= 0:
			lines.append("Material ID: %d" % mat_id)
	
	_info_label.text = "\n".join(lines)
	_info_label.global_position = hit_pos + hit_normal * 0.2
	_info_label.visible = true
	
	# Color based on what we hit
	if collider and collider.is_in_group("terrain"):
		_info_label.modulate = Color.CYAN
	elif collider and collider.is_in_group("npcs"):
		_info_label.modulate = Color.YELLOW
	else:
		_info_label.modulate = Color.WHITE


## Apply settings from debug settings panel
func apply_settings(settings: Dictionary) -> void:
	_max_distance = settings.get("xray_label_distance", MAX_DISTANCE)
