class_name Chunk
extends StaticBody3D

const CHUNK_SIZE = 32
const VOXEL_SIZE = 1.0

var noise: FastNoiseLite
var chunk_position: Vector2i
var biome_manager: BiomeManager

func _init(p_noise: FastNoiseLite, p_pos: Vector2i, p_biome_mgr: BiomeManager):
	noise = p_noise
	chunk_position = p_pos
	biome_manager = p_biome_mgr

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
			
			# Quad vertices
			var v1 = Vector3(x, h1, z)
			var v2 = Vector3(x + 1, h2, z)
			var v3 = Vector3(x, h3, z + 1)
			var v4 = Vector3(x + 1, h4, z + 1)
			
			# Colors
			var c1 = biome_manager.get_biome_data(global_x, global_z, h1)
			var c2 = biome_manager.get_biome_data(global_x + 1, global_z, h2)
			var c3 = biome_manager.get_biome_data(global_x, global_z + 1, h3)
			var c4 = biome_manager.get_biome_data(global_x + 1, global_z + 1, h4)
			
			# Triangle 1
			st.set_color(c1); st.add_vertex(v1)
			st.set_color(c2); st.add_vertex(v2)
			st.set_color(c3); st.add_vertex(v3)
			
			# Triangle 2
			st.set_color(c2); st.add_vertex(v2)
			st.set_color(c4); st.add_vertex(v4)
			st.set_color(c3); st.add_vertex(v3)
	
	st.generate_normals()
	
	var array_mesh = st.commit()
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	
	# Material with Vertex Color
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh_instance.material_override = mat
	
	add_child(mesh_instance)
	
	# Collision
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = array_mesh.create_trimesh_shape()
	add_child(collision_shape)

func _get_height(wx: int, wz: int) -> float:
	return noise.get_noise_2d(wx, wz) * 50.0 # Height scale
