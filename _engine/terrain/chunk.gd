class_name Chunk
extends StaticBody3D

const CHUNK_SIZE = 32
const VOXEL_SIZE = 1.0

var noise: FastNoiseLite
var chunk_position: Vector2i
var biome_manager: BiomeManager
var height_data = {} # Stores modified heights: Vector2i(x, z) -> float

# Preload terrain material
var terrain_material: Material = null

func _init(p_noise: FastNoiseLite, p_pos: Vector2i, p_biome_mgr: BiomeManager):
	noise = p_noise
	chunk_position = p_pos
	biome_manager = p_biome_mgr
	
	# Try to load the terrain shader material
	var mat_path = "res://_assets/shaders/terrain_material.tres"
	if ResourceLoader.exists(mat_path):
		terrain_material = load(mat_path)

func generate_chunk():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for x in range(CHUNK_SIZE):
		for z in range(CHUNK_SIZE):
			var global_x = (chunk_position.x * CHUNK_SIZE) + x
			var global_z = (chunk_position.y * CHUNK_SIZE) + z
			
			var h1 = _get_height(global_x, global_z)
			var h2 = _get_height(global_x + 1, global_z)
			var h3 = _get_height(global_x, global_z + 1)
			var h4 = _get_height(global_x + 1, global_z + 1)
			
			# Quad vertices (world position for shader)
			var v1 = Vector3(x, h1, z)
			var v2 = Vector3(x + 1, h2, z)
			var v3 = Vector3(x, h3, z + 1)
			var v4 = Vector3(x + 1, h4, z + 1)
			
			# Calculate normals for proper lighting and slope detection
			var n1 = _calculate_normal(global_x, global_z)
			var n2 = _calculate_normal(global_x + 1, global_z)
			var n3 = _calculate_normal(global_x, global_z + 1)
			var n4 = _calculate_normal(global_x + 1, global_z + 1)
			
			# Triangle 1
			st.set_normal(n1); st.add_vertex(v1)
			st.set_normal(n2); st.add_vertex(v2)
			st.set_normal(n3); st.add_vertex(v3)
			
			# Triangle 2
			st.set_normal(n2); st.add_vertex(v2)
			st.set_normal(n4); st.add_vertex(v4)
			st.set_normal(n3); st.add_vertex(v3)
	
	var array_mesh = st.commit()
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	
	# Apply terrain shader or fallback
	if terrain_material:
		mesh_instance.material_override = terrain_material
	else:
		# Fallback to simple vertex colors if shader not found
		var mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mesh_instance.material_override = mat
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = array_mesh.create_trimesh_shape()
	
	# Clear old children (for regeneration)
	for child in get_children():
		child.queue_free()
			
	add_child(mesh_instance)
	add_child(collision_shape)

func modify_height(local_x: int, local_z: int, amount: float):
	var global_x = (chunk_position.x * CHUNK_SIZE) + local_x
	var global_z = (chunk_position.y * CHUNK_SIZE) + local_z
	
	var current = _get_height(global_x, global_z)
	
	var key = Vector2i(local_x, local_z)
	var new_h = current + amount
	height_data[key] = new_h
	
	# Regenerate
	generate_chunk()

func _get_height(wx: int, wz: int) -> float:
	# Convert global to local to check storage
	var local_x = wx - (chunk_position.x * CHUNK_SIZE)
	var local_z = wz - (chunk_position.y * CHUNK_SIZE)
	var key = Vector2i(local_x, local_z)
	
	if height_data.has(key):
		return height_data[key]
		
	return noise.get_noise_2d(wx, wz) * 50.0 # Height scale

func _calculate_normal(wx: int, wz: int) -> Vector3:
	# Sample heights around this point for gradient
	var h_center = _get_height(wx, wz)
	var h_left = _get_height(wx - 1, wz)
	var h_right = _get_height(wx + 1, wz)
	var h_up = _get_height(wx, wz - 1)
	var h_down = _get_height(wx, wz + 1)
	
	# Calculate gradient (slope in X and Z directions)
	var dx = (h_right - h_left) / 2.0
	var dz = (h_down - h_up) / 2.0
	
	# Normal is perpendicular to the surface
	var normal = Vector3(-dx, 1.0, -dz).normalized()
	return normal
