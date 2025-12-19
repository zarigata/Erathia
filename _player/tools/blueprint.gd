class_name Blueprint
extends BaseTool

## Blueprint Tool - Visual "build mode hand item" that replaces mining tools during building.
## Does not perform any action itself - placement is handled by SnapSystem.

var wireframe_mesh: MeshInstance3D = null


func _ready() -> void:
	super._ready()
	_setup_wireframe_mesh()
	# Blueprint has no durability or stamina cost
	durability_max = -1  # Infinite durability
	stamina_cost_per_use = 0.0
	cooldown_duration = 0.0


func _setup_wireframe_mesh() -> void:
	wireframe_mesh = MeshInstance3D.new()
	wireframe_mesh.name = "WireframeMesh"
	
	# Create procedural wireframe box (1x1x1m)
	var mesh := _create_wireframe_box(Vector3.ONE)
	wireframe_mesh.mesh = mesh
	
	# Create emissive material
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.9, 0.7, 0.8)  # Cyan/green
	material.emission_enabled = true
	material.emission = Color(0.1, 0.5, 0.4)
	material.emission_energy_multiplier = 1.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wireframe_mesh.material_override = material
	
	add_child(wireframe_mesh)
	wireframe_mesh.position = Vector3(0.3, -0.2, -0.5)


func _create_wireframe_box(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	
	var half := size / 2.0
	
	# Define the 8 corners of the box
	var corners := [
		Vector3(-half.x, -half.y, -half.z),  # 0: bottom-back-left
		Vector3(half.x, -half.y, -half.z),   # 1: bottom-back-right
		Vector3(half.x, -half.y, half.z),    # 2: bottom-front-right
		Vector3(-half.x, -half.y, half.z),   # 3: bottom-front-left
		Vector3(-half.x, half.y, -half.z),   # 4: top-back-left
		Vector3(half.x, half.y, -half.z),    # 5: top-back-right
		Vector3(half.x, half.y, half.z),     # 6: top-front-right
		Vector3(-half.x, half.y, half.z),    # 7: top-front-left
	]
	
	# Define the 12 edges
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],  # Bottom face
		[4, 5], [5, 6], [6, 7], [7, 4],  # Top face
		[0, 4], [1, 5], [2, 6], [3, 7],  # Vertical edges
	]
	
	st.set_color(Color(0.2, 0.9, 0.7))
	
	for edge in edges:
		st.add_vertex(corners[edge[0]])
		st.add_vertex(corners[edge[1]])
	
	return st.commit()


func equip() -> void:
	is_equipped = true
	visible = true
	if wireframe_mesh:
		wireframe_mesh.visible = true


func unequip() -> void:
	is_equipped = false
	visible = false
	if wireframe_mesh:
		wireframe_mesh.visible = false


func _can_use() -> bool:
	# Blueprint tool doesn't "use" in the traditional sense
	# Placement is handled by SnapSystem
	return false


func _use(_hit_result: VoxelRaycastResult) -> bool:
	# Do nothing - placement is handled by SnapSystem
	return false


func is_broken() -> bool:
	# Blueprint never breaks
	return false


func get_durability_percent() -> float:
	# Always full durability
	return 1.0
