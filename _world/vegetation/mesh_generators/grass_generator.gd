extends RefCounted
class_name GrassGenerator
## Procedural Grass Tuft Generator
##
## Generates grass tuft meshes (billboard quads or simple geometry).

# =============================================================================
# CONSTANTS
# =============================================================================

const MIN_HEIGHT: float = 0.2
const MAX_HEIGHT: float = 0.6

# Grass colors per biome
const BIOME_GRASS_COLORS: Dictionary = {
	MapGenerator.Biome.PLAINS: [Color(0.35, 0.55, 0.2), Color(0.4, 0.6, 0.25)],
	MapGenerator.Biome.FOREST: [Color(0.25, 0.45, 0.15), Color(0.3, 0.5, 0.2)],
	MapGenerator.Biome.DESERT: [Color(0.6, 0.55, 0.35), Color(0.55, 0.5, 0.3)],
	MapGenerator.Biome.SWAMP: [Color(0.3, 0.4, 0.2), Color(0.25, 0.35, 0.18)],
	MapGenerator.Biome.TUNDRA: [Color(0.45, 0.5, 0.4), Color(0.5, 0.52, 0.45)],
	MapGenerator.Biome.JUNGLE: [Color(0.2, 0.5, 0.15), Color(0.15, 0.55, 0.1)],
	MapGenerator.Biome.SAVANNA: [Color(0.6, 0.55, 0.3), Color(0.65, 0.58, 0.35)],
	MapGenerator.Biome.MOUNTAIN: [Color(0.4, 0.45, 0.3), Color(0.35, 0.4, 0.28)],
	MapGenerator.Biome.BEACH: [Color(0.5, 0.55, 0.35), Color(0.55, 0.58, 0.4)],
	MapGenerator.Biome.DEEP_OCEAN: [],  # No grass
	MapGenerator.Biome.ICE_SPIRES: [],  # No grass
	MapGenerator.Biome.VOLCANIC: [Color(0.25, 0.22, 0.18)],  # Ash-covered
	MapGenerator.Biome.MUSHROOM: [Color(0.45, 0.35, 0.5), Color(0.5, 0.4, 0.55)]
}

# =============================================================================
# PUBLIC API
# =============================================================================

## Check if biome has grass
static func has_grass(biome_id: int) -> bool:
	var colors: Array = BIOME_GRASS_COLORS.get(biome_id, [])
	return colors.size() > 0


## Get grass color for a biome
static func get_grass_color(biome_id: int, seed_value: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var colors: Array = BIOME_GRASS_COLORS.get(biome_id, [Color(0.4, 0.5, 0.25)])
	if colors.is_empty():
		return Color(0.4, 0.5, 0.25)
	return colors[rng.randi() % colors.size()]


## Generate a grass tuft mesh
static func generate_grass_tuft(biome_id: int, seed_value: int, lod_level: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var height := rng.randf_range(MIN_HEIGHT, MAX_HEIGHT)
	var color := get_grass_color(biome_id, seed_value)
	
	# At high LOD, use simple billboard
	if lod_level >= 2:
		return _generate_billboard(height, color, rng)
	
	return _generate_grass_blades(height, color, rng, lod_level)


## Generate a billboard quad for distant grass
static func generate_billboard(biome_id: int, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var height := rng.randf_range(MIN_HEIGHT, MAX_HEIGHT)
	var color := get_grass_color(biome_id, seed_value)
	
	return _generate_billboard(height, color, rng)


# =============================================================================
# MESH GENERATION HELPERS
# =============================================================================

static func _generate_grass_blades(height: float, color: Color, rng: RandomNumberGenerator, lod_level: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var blade_count := 6 if lod_level == 0 else 4
	var spread := 0.15
	
	for i in range(blade_count):
		var offset := Vector3(
			rng.randf_range(-spread, spread),
			0,
			rng.randf_range(-spread, spread)
		)
		
		var blade_height := height * rng.randf_range(0.7, 1.3)
		var lean_angle := rng.randf() * TAU
		var lean_amount := rng.randf_range(0.05, 0.15)
		
		var tip := offset + Vector3(
			cos(lean_angle) * lean_amount,
			blade_height,
			sin(lean_angle) * lean_amount
		)
		
		var width := 0.03
		var perp := Vector3(-sin(lean_angle), 0, cos(lean_angle)) * width
		
		var shade := rng.randf_range(0.85, 1.15)
		var blade_color := color * shade
		
		# Base darker
		st.set_color(blade_color.darkened(0.2))
		st.add_vertex(offset - perp)
		st.add_vertex(offset + perp)
		
		# Tip lighter
		st.set_color(blade_color.lightened(0.1))
		st.add_vertex(tip)
	
	st.generate_normals()
	return st.commit()


static func _generate_billboard(height: float, color: Color, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var width := height * 0.8
	
	# Two crossed quads
	_add_billboard_quad(st, Vector3.ZERO, width, height, color, 0.0)
	_add_billboard_quad(st, Vector3.ZERO, width, height, color, PI / 2.0)
	
	st.generate_normals()
	return st.commit()


static func _add_billboard_quad(st: SurfaceTool, center: Vector3, width: float, height: float, color: Color, rotation: float) -> void:
	var half_w := width * 0.5
	var cos_r := cos(rotation)
	var sin_r := sin(rotation)
	
	var offset_x := Vector3(cos_r * half_w, 0, sin_r * half_w)
	
	var bl := center - offset_x
	var br := center + offset_x
	var tl := center - offset_x + Vector3(0, height, 0)
	var tr := center + offset_x + Vector3(0, height, 0)
	
	# Bottom darker
	st.set_color(color.darkened(0.2))
	st.add_vertex(bl)
	st.add_vertex(br)
	
	# Top lighter
	st.set_color(color.lightened(0.1))
	st.add_vertex(tr)
	
	st.set_color(color.darkened(0.2))
	st.add_vertex(bl)
	
	st.set_color(color.lightened(0.1))
	st.add_vertex(tr)
	st.add_vertex(tl)
