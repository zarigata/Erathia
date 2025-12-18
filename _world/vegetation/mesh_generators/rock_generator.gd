extends RefCounted
class_name RockGenerator
## Procedural Rock Mesh Generator
##
## Generates random rock meshes using noise-displaced geometry.
## Supports size variants and biome-specific materials.

# =============================================================================
# CONSTANTS
# =============================================================================

# Size categories
const SIZE_RANGES: Dictionary = {
	"small": {"min": 0.3, "max": 0.8},
	"medium": {"min": 1.0, "max": 2.0},
	"large": {"min": 3.0, "max": 5.0}
}

# Rock colors per biome
const BIOME_ROCK_COLORS: Dictionary = {
	MapGenerator.Biome.PLAINS: Color(0.5, 0.48, 0.45),
	MapGenerator.Biome.FOREST: Color(0.45, 0.48, 0.42),  # Mossy
	MapGenerator.Biome.DESERT: Color(0.7, 0.6, 0.45),  # Sandstone
	MapGenerator.Biome.SWAMP: Color(0.35, 0.38, 0.32),  # Dark mossy
	MapGenerator.Biome.TUNDRA: Color(0.6, 0.62, 0.65),  # Frost-covered
	MapGenerator.Biome.JUNGLE: Color(0.4, 0.45, 0.38),  # Mossy
	MapGenerator.Biome.SAVANNA: Color(0.6, 0.55, 0.45),  # Tan
	MapGenerator.Biome.MOUNTAIN: Color(0.55, 0.52, 0.5),  # Gray granite
	MapGenerator.Biome.BEACH: Color(0.65, 0.6, 0.55),  # Light
	MapGenerator.Biome.DEEP_OCEAN: Color(0.4, 0.45, 0.5),  # Wet stone
	MapGenerator.Biome.ICE_SPIRES: Color(0.75, 0.8, 0.85),  # Ice blue
	MapGenerator.Biome.VOLCANIC: Color(0.15, 0.12, 0.1),  # Obsidian black
	MapGenerator.Biome.MUSHROOM: Color(0.55, 0.5, 0.55)  # Purple-gray
}

# =============================================================================
# PUBLIC API
# =============================================================================

## Get rock material/color for a biome
static func get_rock_color(biome_id: int) -> Color:
	return BIOME_ROCK_COLORS.get(biome_id, Color(0.5, 0.5, 0.5))


## Generate a rock mesh
static func generate_rock(biome_id: int, size_category: String, seed_value: int, lod_level: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var size_range: Dictionary = SIZE_RANGES.get(size_category, SIZE_RANGES["small"])
	var size := rng.randf_range(size_range["min"], size_range["max"])
	
	var color := get_rock_color(biome_id)
	# Add variation
	color = color * rng.randf_range(0.85, 1.15)
	
	# LOD adjustments
	var subdivisions := 2
	match lod_level:
		1:
			subdivisions = 1
		2, 3:
			subdivisions = 0
	
	return _generate_deformed_rock(size, color, subdivisions, rng)


## Generate a rock with collision shape data
static func generate_rock_with_collision(biome_id: int, size_category: String, seed_value: int) -> Dictionary:
	var mesh := generate_rock(biome_id, size_category, seed_value, 0)
	
	var size_range: Dictionary = SIZE_RANGES.get(size_category, SIZE_RANGES["small"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var size := rng.randf_range(size_range["min"], size_range["max"])
	
	# Create simple box collision shape
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, size * 0.7, size)
	
	return {
		"mesh": mesh,
		"collision_shape": shape,
		"size": size
	}


# =============================================================================
# MESH GENERATION HELPERS
# =============================================================================

static func _generate_deformed_rock(size: float, color: Color, subdivisions: int, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Start with a cube and deform it
	var vertices: Array[Vector3] = []
	var faces: Array[Array] = []
	
	# Create cube vertices
	var half := 0.5
	vertices.append(Vector3(-half, -half, -half))  # 0
	vertices.append(Vector3(half, -half, -half))   # 1
	vertices.append(Vector3(half, half, -half))    # 2
	vertices.append(Vector3(-half, half, -half))   # 3
	vertices.append(Vector3(-half, -half, half))   # 4
	vertices.append(Vector3(half, -half, half))    # 5
	vertices.append(Vector3(half, half, half))     # 6
	vertices.append(Vector3(-half, half, half))    # 7
	
	# Cube faces (as triangles)
	faces = [
		# Front
		[0, 1, 2], [0, 2, 3],
		# Back
		[5, 4, 7], [5, 7, 6],
		# Top
		[3, 2, 6], [3, 6, 7],
		# Bottom
		[4, 5, 1], [4, 1, 0],
		# Right
		[1, 5, 6], [1, 6, 2],
		# Left
		[4, 0, 3], [4, 3, 7]
	]
	
	# Subdivide faces
	for _sub in range(subdivisions):
		var new_faces: Array[Array] = []
		var edge_midpoints: Dictionary = {}
		
		for face in faces:
			var v0: int = face[0]
			var v1: int = face[1]
			var v2: int = face[2]
			
			var m01 := _get_edge_midpoint(vertices, v0, v1, edge_midpoints)
			var m12 := _get_edge_midpoint(vertices, v1, v2, edge_midpoints)
			var m20 := _get_edge_midpoint(vertices, v2, v0, edge_midpoints)
			
			new_faces.append([v0, m01, m20])
			new_faces.append([m01, v1, m12])
			new_faces.append([m20, m12, v2])
			new_faces.append([m01, m12, m20])
		
		faces = new_faces
	
	# Apply noise deformation to vertices
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 1.5
	
	var deformed_vertices: Array[Vector3] = []
	for v in vertices:
		var noise_val := noise.get_noise_3d(v.x * 10, v.y * 10, v.z * 10)
		var deform := v.normalized() * noise_val * 0.3
		var new_v := (v + deform) * size
		# Flatten bottom slightly
		if new_v.y < 0:
			new_v.y *= 0.5
		deformed_vertices.append(new_v)
	
	# Build mesh
	for face in faces:
		var shade := rng.randf_range(0.8, 1.2)
		st.set_color(color * shade)
		
		for idx in face:
			st.add_vertex(deformed_vertices[idx])
	
	st.generate_normals()
	return st.commit()


static func _get_edge_midpoint(vertices: Array[Vector3], i1: int, i2: int, cache: Dictionary) -> int:
	var key := mini(i1, i2) * 10000 + maxi(i1, i2)
	if cache.has(key):
		return cache[key]
	
	var mid := (vertices[i1] + vertices[i2]) * 0.5
	vertices.append(mid)
	var idx := vertices.size() - 1
	cache[key] = idx
	return idx


## Create a StandardMaterial3D for rocks in a biome
static func get_rock_material(biome_id: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var color := get_rock_color(biome_id)
	
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.metallic = 0.0
	
	# Special cases
	match biome_id:
		MapGenerator.Biome.VOLCANIC:
			mat.roughness = 0.3  # Obsidian is smooth
			mat.metallic = 0.1
		MapGenerator.Biome.ICE_SPIRES:
			mat.roughness = 0.2
			mat.metallic = 0.05
		MapGenerator.Biome.DEEP_OCEAN:
			mat.roughness = 0.6  # Wet
	
	return mat
