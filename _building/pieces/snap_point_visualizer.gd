class_name SnapPointVisualizer
extends Node3D

const SNAP_SPHERE_RADIUS: float = 0.15
const SNAP_DETECTION_DISTANCE: float = 1.0

var _snap_meshes: Array[MeshInstance3D] = []
var _parent_piece: BuildPiece = null
var _material_valid: StandardMaterial3D
var _material_invalid: StandardMaterial3D
var _material_nearby: StandardMaterial3D


func _ready() -> void:
	_setup_materials()
	
	if get_parent() is BuildPiece:
		_parent_piece = get_parent() as BuildPiece
		_create_snap_point_meshes()


func _setup_materials() -> void:
	_material_valid = StandardMaterial3D.new()
	_material_valid.albedo_color = Color(0.2, 0.9, 0.2, 0.7)
	_material_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	_material_invalid = StandardMaterial3D.new()
	_material_invalid.albedo_color = Color(0.9, 0.2, 0.2, 0.7)
	_material_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	_material_nearby = StandardMaterial3D.new()
	_material_nearby.albedo_color = Color(0.9, 0.9, 0.2, 0.7)
	_material_nearby.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material_nearby.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _create_snap_point_meshes() -> void:
	_clear_snap_meshes()
	
	if not _parent_piece or not _parent_piece.piece_data:
		return
	
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = SNAP_SPHERE_RADIUS
	sphere_mesh.height = SNAP_SPHERE_RADIUS * 2
	sphere_mesh.radial_segments = 8
	sphere_mesh.rings = 4
	
	for snap_point in _parent_piece.piece_data.snap_points:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = sphere_mesh
		mesh_instance.material_override = _material_valid
		mesh_instance.position = snap_point.get("offset", Vector3.ZERO)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_instance)
		_snap_meshes.append(mesh_instance)


func _clear_snap_meshes() -> void:
	for mesh in _snap_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_snap_meshes.clear()


func set_visible_snap_points(visible: bool) -> void:
	for mesh in _snap_meshes:
		if is_instance_valid(mesh):
			mesh.visible = visible


func update_snap_visualization(nearby_pieces: Array) -> void:
	if not _parent_piece or not _parent_piece.piece_data:
		return
	
	var snap_points := _parent_piece.piece_data.snap_points
	
	for i in range(min(snap_points.size(), _snap_meshes.size())):
		var snap_point: Dictionary = snap_points[i]
		var mesh: MeshInstance3D = _snap_meshes[i]
		
		if not is_instance_valid(mesh):
			continue
		
		var local_offset: Vector3 = snap_point.get("offset", Vector3.ZERO)
		var world_pos: Vector3 = _parent_piece.global_transform * local_offset
		var snap_type: int = snap_point.get("type", BuildPieceData.SnapType.EDGE)
		var compatible_types: Array = snap_point.get("compatible_types", [])
		
		var status := _check_snap_status(world_pos, snap_type, compatible_types, nearby_pieces)
		
		match status:
			0:  # Valid - can snap
				mesh.material_override = _material_valid
			1:  # Nearby but not aligned
				mesh.material_override = _material_nearby
			2:  # Blocked/invalid
				mesh.material_override = _material_invalid


func _check_snap_status(world_pos: Vector3, snap_type: int, compatible_types: Array, nearby_pieces: Array) -> int:
	var closest_distance := INF
	var has_compatible_nearby := false
	
	for piece in nearby_pieces:
		if not piece is BuildPiece:
			continue
		if piece == _parent_piece:
			continue
		
		var other_snap_data := piece.get_snap_point_data() as Array[Dictionary]
		
		for other_point in other_snap_data:
			var other_pos: Vector3 = other_point.get("position", Vector3.ZERO)
			var other_type: int = other_point.get("type", BuildPieceData.SnapType.EDGE)
			
			var distance := world_pos.distance_to(other_pos)
			
			if distance < closest_distance:
				closest_distance = distance
			
			if distance < SNAP_DETECTION_DISTANCE:
				if compatible_types.has(other_type) or compatible_types.is_empty():
					has_compatible_nearby = true
					
					if distance < SNAP_SPHERE_RADIUS * 2:
						return 0  # Valid snap
	
	if has_compatible_nearby:
		return 1  # Nearby but not aligned
	
	if closest_distance < SNAP_SPHERE_RADIUS * 3:
		return 2  # Blocked
	
	return 0  # Default valid (no conflicts)


func get_nearest_snap_point(world_position: Vector3) -> Dictionary:
	if not _parent_piece or not _parent_piece.piece_data:
		return {}
	
	var nearest_point := {}
	var nearest_distance := INF
	
	var snap_points := _parent_piece.piece_data.snap_points
	
	for snap_point in snap_points:
		var local_offset: Vector3 = snap_point.get("offset", Vector3.ZERO)
		var world_pos: Vector3 = _parent_piece.global_transform * local_offset
		
		var distance := world_position.distance_to(world_pos)
		
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_point = {
				"position": world_pos,
				"normal": _parent_piece.global_basis * snap_point.get("normal", Vector3.UP),
				"type": snap_point.get("type", BuildPieceData.SnapType.EDGE),
				"distance": distance
			}
	
	return nearest_point


func highlight_snap_point(index: int, highlighted: bool) -> void:
	if index < 0 or index >= _snap_meshes.size():
		return
	
	var mesh := _snap_meshes[index]
	if not is_instance_valid(mesh):
		return
	
	if highlighted:
		mesh.scale = Vector3(1.5, 1.5, 1.5)
	else:
		mesh.scale = Vector3.ONE
