class_name BuildPiece
extends Node3D

signal piece_placed(position: Vector3, rotation: float)
signal piece_destroyed()
signal snap_point_detected(point_position: Vector3)

@export var piece_data: BuildPieceData
@export var current_material_variant: int = 0
@export var is_placed: bool = false

var owner_player: Node = null
var mesh_instance: MeshInstance3D = null
var collision_shape: CollisionShape3D = null
var static_body: StaticBody3D = null

var _preview_material: Material = null
var _original_materials: Array[Material] = []
var _ghost_shader: Shader = null


func _ready() -> void:
	_setup_nodes()
	if piece_data:
		_initialize_from_data()


func _setup_nodes() -> void:
	static_body = StaticBody3D.new()
	static_body.name = "StaticBody"
	add_child(static_body)
	
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance"
	static_body.add_child(mesh_instance)
	
	collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape"
	static_body.add_child(collision_shape)


func _initialize_from_data() -> void:
	if not piece_data:
		return
	name = piece_data.piece_id


func set_mesh(mesh: Mesh) -> void:
	if mesh_instance:
		mesh_instance.mesh = mesh
		_store_original_materials()


func set_collision(shape: Shape3D) -> void:
	if collision_shape:
		collision_shape.shape = shape


func _store_original_materials() -> void:
	_original_materials.clear()
	if mesh_instance and mesh_instance.mesh:
		for i in range(mesh_instance.mesh.get_surface_count()):
			var mat = mesh_instance.get_surface_override_material(i)
			if mat:
				_original_materials.append(mat)
			elif mesh_instance.mesh.surface_get_material(i):
				_original_materials.append(mesh_instance.mesh.surface_get_material(i))
			else:
				_original_materials.append(null)


func set_material_variant(variant: int) -> void:
	current_material_variant = variant


func get_snap_points() -> Array[Vector3]:
	var world_points: Array[Vector3] = []
	if not piece_data:
		return world_points
	
	for snap_point in piece_data.snap_points:
		var local_offset: Vector3 = snap_point.get("offset", Vector3.ZERO)
		var world_pos: Vector3 = global_transform * local_offset
		world_points.append(world_pos)
	
	return world_points


func get_snap_point_data() -> Array[Dictionary]:
	var world_data: Array[Dictionary] = []
	if not piece_data:
		return world_data
	
	for snap_point in piece_data.snap_points:
		var local_offset: Vector3 = snap_point.get("offset", Vector3.ZERO)
		var local_normal: Vector3 = snap_point.get("normal", Vector3.UP)
		
		var world_pos: Vector3 = global_transform * local_offset
		var world_normal: Vector3 = global_basis * local_normal
		
		world_data.append({
			"position": world_pos,
			"normal": world_normal.normalized(),
			"type": snap_point.get("type", BuildPieceData.SnapType.EDGE),
			"compatible_types": snap_point.get("compatible_types", [])
		})
	
	return world_data


func can_afford(inventory: Node) -> bool:
	if not piece_data:
		return false
	if not inventory or not inventory.has_method("has_building_resources"):
		return false
	return inventory.has_building_resources(piece_data)


func place(pos: Vector3, rot: float, inventory: Node = null) -> bool:
	if is_placed:
		return false
	
	# Get inventory singleton if not provided
	if not inventory:
		inventory = Engine.get_singleton("Inventory")
	
	# Check affordability and consume resources
	if inventory and piece_data:
		if not inventory.has_building_resources(piece_data):
			push_warning("BuildPiece: Cannot afford to place '%s'" % piece_data.piece_id)
			return false
		if not inventory.consume_building_resources(piece_data):
			push_warning("BuildPiece: Failed to consume resources for '%s'" % piece_data.piece_id)
			return false
	
	global_position = pos
	rotation.y = rot
	is_placed = true
	
	preview_mode(false)
	
	if collision_shape:
		collision_shape.disabled = false
	
	piece_placed.emit(pos, rot)
	return true


func preview_mode(enabled: bool) -> void:
	if not mesh_instance:
		return
	
	if enabled:
		if not _preview_material:
			# Load ghost preview shader for X-ray effect
			_ghost_shader = load("res://_assets/materials/ghost_preview.gdshader")
			if _ghost_shader:
				_preview_material = ShaderMaterial.new()
				_preview_material.shader = _ghost_shader
				_preview_material.set_shader_parameter("valid_color", Color(0.3, 1.0, 0.4, 0.6))
				_preview_material.set_shader_parameter("invalid_color", Color(1.0, 0.3, 0.3, 0.6))
				_preview_material.set_shader_parameter("is_valid", true)
				_preview_material.set_shader_parameter("fresnel_power", 2.0)
				_preview_material.set_shader_parameter("grid_scale", 4.0)
				_preview_material.render_priority = 1
			else:
				# Fallback to standard material if shader not found
				var fallback := StandardMaterial3D.new()
				fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				fallback.albedo_color = Color(0.3, 0.7, 1.0, 0.5)
				fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_preview_material = fallback
		
		for i in range(mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0):
			mesh_instance.set_surface_override_material(i, _preview_material)
		
		if collision_shape:
			collision_shape.disabled = true
	else:
		for i in range(_original_materials.size()):
			mesh_instance.set_surface_override_material(i, _original_materials[i] if _original_materials[i] else null)
		
		if collision_shape:
			collision_shape.disabled = false


func set_preview_valid(valid: bool) -> void:
	if _preview_material:
		if _preview_material is ShaderMaterial:
			_preview_material.set_shader_parameter("is_valid", valid)
		elif _preview_material is StandardMaterial3D:
			if valid:
				(_preview_material as StandardMaterial3D).albedo_color = Color(0.3, 1.0, 0.3, 0.5)
			else:
				(_preview_material as StandardMaterial3D).albedo_color = Color(1.0, 0.3, 0.3, 0.5)


func get_structural_support() -> float:
	if not piece_data:
		return 0.0
	return piece_data.structural_weight


func destroy() -> void:
	piece_destroyed.emit()
	queue_free()
