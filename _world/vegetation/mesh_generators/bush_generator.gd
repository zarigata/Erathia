extends RefCounted
class_name BushGenerator
## Procedural Bush Mesh Generator
##
## Generates simple bush meshes (deformed icospheres) with biome-specific colors.

# =============================================================================
# CONSTANTS
# =============================================================================

const MIN_HEIGHT: float = 0.5
const MAX_HEIGHT: float = 2.0

# Bush colors per biome
const BIOME_BUSH_COLORS: Dictionary = {
	MapGenerator.Biome.PLAINS: [Color(0.25, 0.5, 0.15), Color(0.3, 0.55, 0.2)],
	MapGenerator.Biome.FOREST: [Color(0.2, 0.45, 0.15), Color(0.15, 0.4, 0.1)],
	MapGenerator.Biome.DESERT: [Color(0.5, 0.45, 0.3), Color(0.45, 0.4, 0.25)],
	MapGenerator.Biome.SWAMP: [Color(0.25, 0.35, 0.2), Color(0.3, 0.38, 0.22)],
	MapGenerator.Biome.TUNDRA: [Color(0.35, 0.4, 0.35), Color(0.4, 0.42, 0.38)],
	MapGenerator.Biome.JUNGLE: [Color(0.15, 0.5, 0.1), Color(0.1, 0.55, 0.15)],
	MapGenerator.Biome.SAVANNA: [Color(0.5, 0.45, 0.25), Color(0.55, 0.5, 0.3)],
	MapGenerator.Biome.MOUNTAIN: [Color(0.3, 0.35, 0.25), Color(0.35, 0.38, 0.28)],
	MapGenerator.Biome.BEACH: [Color(0.35, 0.5, 0.25), Color(0.4, 0.55, 0.3)],
	MapGenerator.Biome.DEEP_OCEAN: [Color(0.1, 0.3, 0.25)],  # Seaweed-like
	MapGenerator.Biome.ICE_SPIRES: [Color(0.5, 0.55, 0.6)],  # Frost-covered
	MapGenerator.Biome.VOLCANIC: [Color(0.2, 0.15, 0.1), Color(0.25, 0.18, 0.12)],
	MapGenerator.Biome.MUSHROOM: [Color(0.5, 0.2, 0.45), Color(0.6, 0.25, 0.5)]
}

# Bush variant names
const BIOME_BUSH_VARIANTS: Dictionary = {
	MapGenerator.Biome.PLAINS: ["green_bush", "flowering_bush"],
	MapGenerator.Biome.FOREST: ["green_bush", "fern", "undergrowth"],
	MapGenerator.Biome.DESERT: ["desert_shrub", "tumbleweed"],
	MapGenerator.Biome.SWAMP: ["swamp_bush", "moss_clump"],
	MapGenerator.Biome.TUNDRA: ["frost_bush"],
	MapGenerator.Biome.JUNGLE: ["tropical_bush", "fern", "giant_fern"],
	MapGenerator.Biome.SAVANNA: ["dry_bush", "grass_clump"],
	MapGenerator.Biome.MOUNTAIN: ["alpine_bush", "lichen"],
	MapGenerator.Biome.BEACH: ["beach_grass", "dune_bush"],
	MapGenerator.Biome.DEEP_OCEAN: [],
	MapGenerator.Biome.ICE_SPIRES: [],
	MapGenerator.Biome.VOLCANIC: ["ash_bush"],
	MapGenerator.Biome.MUSHROOM: ["small_mushroom", "mushroom_cluster"]
}

# =============================================================================
# PUBLIC API
# =============================================================================

## Returns array of bush variant names for a biome
static func get_bush_variants(biome_id: int) -> Array[String]:
	var variants: Array[String] = []
	if BIOME_BUSH_VARIANTS.has(biome_id):
		for v in BIOME_BUSH_VARIANTS[biome_id]:
			variants.append(v)
	return variants


## Get bush color for a biome
static func get_bush_color(biome_id: int, seed_value: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var colors: Array = BIOME_BUSH_COLORS.get(biome_id, [Color(0.3, 0.5, 0.2)])
	return colors[rng.randi() % colors.size()]


## Generate a bush mesh
static func generate_bush(biome_id: int, variant: String, seed_value: int, lod_level: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var height := rng.randf_range(MIN_HEIGHT, MAX_HEIGHT)
	var width := height * rng.randf_range(0.8, 1.4)
	var depth := height * rng.randf_range(0.8, 1.4)
	
	var color := get_bush_color(biome_id, seed_value)
	
	# LOD adjustments
	var subdivisions := 2
	match lod_level:
		1:
			subdivisions = 1
		2, 3:
			subdivisions = 0
	
	# Generate based on variant
	match variant:
		"fern", "giant_fern":
			return _generate_fern(height, color, rng, lod_level)
		"small_mushroom", "mushroom_cluster":
			return _generate_small_mushroom(height, color, rng, lod_level)
		"grass_clump", "beach_grass":
			return _generate_grass_clump(height, color, rng, lod_level)
		_:
			return _generate_icosphere_bush(width, height, depth, color, subdivisions, rng)


## Generate a billboard for distant bushes
static func generate_billboard(biome_id: int, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var color := get_bush_color(biome_id, seed_value)
	var height := rng.randf_range(MIN_HEIGHT, MAX_HEIGHT)
	var width := height * 1.2
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	_add_billboard_quad(st, Vector3(0, height * 0.5, 0), width, height, color)
	
	st.generate_normals()
	return st.commit()


# =============================================================================
# MESH GENERATION HELPERS
# =============================================================================

static func _generate_icosphere_bush(width: float, height: float, depth: float, color: Color, subdivisions: int, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate icosahedron base vertices
	var t := (1.0 + sqrt(5.0)) / 2.0
	var vertices: Array[Vector3] = []
	
	vertices.append(Vector3(-1, t, 0).normalized())
	vertices.append(Vector3(1, t, 0).normalized())
	vertices.append(Vector3(-1, -t, 0).normalized())
	vertices.append(Vector3(1, -t, 0).normalized())
	vertices.append(Vector3(0, -1, t).normalized())
	vertices.append(Vector3(0, 1, t).normalized())
	vertices.append(Vector3(0, -1, -t).normalized())
	vertices.append(Vector3(0, 1, -t).normalized())
	vertices.append(Vector3(t, 0, -1).normalized())
	vertices.append(Vector3(t, 0, 1).normalized())
	vertices.append(Vector3(-t, 0, -1).normalized())
	vertices.append(Vector3(-t, 0, 1).normalized())
	
	# Icosahedron faces
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)
	]
	
	# Subdivide
	for _sub in range(subdivisions):
		var new_faces: Array[Vector3i] = []
		var midpoint_cache: Dictionary = {}
		
		for face in faces:
			var a := _get_midpoint(vertices, face.x, face.y, midpoint_cache)
			var b := _get_midpoint(vertices, face.y, face.z, midpoint_cache)
			var c := _get_midpoint(vertices, face.z, face.x, midpoint_cache)
			
			new_faces.append(Vector3i(face.x, a, c))
			new_faces.append(Vector3i(face.y, b, a))
			new_faces.append(Vector3i(face.z, c, b))
			new_faces.append(Vector3i(a, b, c))
		
		faces = new_faces
	
	# Apply deformation and scale
	var scale := Vector3(width * 0.5, height * 0.5, depth * 0.5)
	var center_y := height * 0.5
	
	for face in faces:
		var shade := rng.randf_range(0.85, 1.15)
		st.set_color(color * shade)
		
		for idx in [face.x, face.y, face.z]:
			var v := vertices[idx]
			# Apply noise deformation
			var noise_offset := rng.randf_range(-0.15, 0.15)
			v = v * (1.0 + noise_offset)
			# Scale and position
			v = Vector3(v.x * scale.x, v.y * scale.y + center_y, v.z * scale.z)
			# Flatten bottom
			if v.y < 0.1:
				v.y = 0.0
			st.add_vertex(v)
	
	st.generate_normals()
	return st.commit()


static func _get_midpoint(vertices: Array[Vector3], i1: int, i2: int, cache: Dictionary) -> int:
	var key := mini(i1, i2) * 10000 + maxi(i1, i2)
	if cache.has(key):
		return cache[key]
	
	var mid := ((vertices[i1] + vertices[i2]) * 0.5).normalized()
	vertices.append(mid)
	var idx := vertices.size() - 1
	cache[key] = idx
	return idx


static func _generate_fern(height: float, color: Color, rng: RandomNumberGenerator, lod_level: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var frond_count := 5 if lod_level < 2 else 3
	
	for i in range(frond_count):
		var angle := (float(i) / frond_count) * TAU + rng.randf_range(-0.3, 0.3)
		var frond_length := height * rng.randf_range(0.8, 1.2)
		var droop := rng.randf_range(0.2, 0.4)
		
		var base := Vector3(0, height * 0.1, 0)
		var tip := Vector3(cos(angle) * frond_length, height * 0.3 - droop * frond_length, sin(angle) * frond_length)
		
		var width := 0.15
		var perp := Vector3(-sin(angle), 0, cos(angle)) * width
		
		var shade := rng.randf_range(0.9, 1.1)
		st.set_color(color * shade)
		
		st.add_vertex(base)
		st.add_vertex(base + perp * 0.5)
		st.add_vertex(tip)
		
		st.add_vertex(base)
		st.add_vertex(tip)
		st.add_vertex(base - perp * 0.5)
	
	st.generate_normals()
	return st.commit()


static func _generate_small_mushroom(height: float, color: Color, rng: RandomNumberGenerator, lod_level: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var mushroom_count := rng.randi_range(1, 4)
	var segments := 6 if lod_level < 2 else 4
	
	for m in range(mushroom_count):
		var offset := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		var mush_height := height * rng.randf_range(0.3, 0.8)
		var cap_radius := mush_height * 0.4
		var stem_radius := mush_height * 0.1
		
		var stem_color := color.lightened(0.4)
		var cap_color := color
		
		# Stem
		var angle_step := TAU / segments
		for i in range(segments):
			var a1 := i * angle_step
			var a2 := (i + 1) * angle_step
			
			var x1 := cos(a1) * stem_radius
			var z1 := sin(a1) * stem_radius
			var x2 := cos(a2) * stem_radius
			var z2 := sin(a2) * stem_radius
			
			st.set_color(stem_color)
			st.add_vertex(offset + Vector3(x1, 0, z1))
			st.add_vertex(offset + Vector3(x2, 0, z2))
			st.add_vertex(offset + Vector3(x2, mush_height * 0.7, z2))
			
			st.add_vertex(offset + Vector3(x1, 0, z1))
			st.add_vertex(offset + Vector3(x2, mush_height * 0.7, z2))
			st.add_vertex(offset + Vector3(x1, mush_height * 0.7, z1))
		
		# Cap
		for i in range(segments):
			var a1 := i * angle_step
			var a2 := (i + 1) * angle_step
			
			var x1 := cos(a1) * cap_radius
			var z1 := sin(a1) * cap_radius
			var x2 := cos(a2) * cap_radius
			var z2 := sin(a2) * cap_radius
			
			var shade := rng.randf_range(0.9, 1.1)
			st.set_color(cap_color * shade)
			
			# Top
			st.add_vertex(offset + Vector3(0, mush_height, 0))
			st.add_vertex(offset + Vector3(x1, mush_height * 0.65, z1))
			st.add_vertex(offset + Vector3(x2, mush_height * 0.65, z2))
	
	st.generate_normals()
	return st.commit()


static func _generate_grass_clump(height: float, color: Color, rng: RandomNumberGenerator, lod_level: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var blade_count := 8 if lod_level < 2 else 4
	
	for i in range(blade_count):
		var angle := rng.randf() * TAU
		var offset := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var blade_height := height * rng.randf_range(0.6, 1.0)
		var lean := rng.randf_range(0.1, 0.3)
		
		var tip := offset + Vector3(cos(angle) * lean, blade_height, sin(angle) * lean)
		var width := 0.05
		var perp := Vector3(-sin(angle), 0, cos(angle)) * width
		
		var shade := rng.randf_range(0.85, 1.15)
		st.set_color(color * shade)
		
		st.add_vertex(offset - perp)
		st.add_vertex(offset + perp)
		st.add_vertex(tip)
	
	st.generate_normals()
	return st.commit()


static func _add_billboard_quad(st: SurfaceTool, center: Vector3, width: float, height: float, color: Color) -> void:
	var half_w := width * 0.5
	var half_h := height * 0.5
	
	st.set_color(color)
	st.add_vertex(center + Vector3(-half_w, -half_h, 0))
	st.add_vertex(center + Vector3(half_w, -half_h, 0))
	st.add_vertex(center + Vector3(half_w, half_h, 0))
	
	st.add_vertex(center + Vector3(-half_w, -half_h, 0))
	st.add_vertex(center + Vector3(half_w, half_h, 0))
	st.add_vertex(center + Vector3(-half_w, half_h, 0))
