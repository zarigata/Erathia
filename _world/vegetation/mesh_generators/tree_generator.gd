extends RefCounted
class_name TreeGenerator
## Procedural Tree Mesh Generator
##
## Generates low-poly tree meshes using simple procedural geometry.
## Supports biome-specific variants (oak, pine, palm, dead, mushroom, etc.)

# =============================================================================
# CONSTANTS
# =============================================================================

const MIN_HEIGHT: float = 3.0
const MAX_HEIGHT: float = 15.0

# Tree type definitions per biome
const BIOME_TREE_VARIANTS: Dictionary = {
	MapGenerator.Biome.PLAINS: ["oak"],
	MapGenerator.Biome.FOREST: ["oak", "birch", "pine"],
	MapGenerator.Biome.DESERT: [],  # No trees
	MapGenerator.Biome.SWAMP: ["willow", "dead"],
	MapGenerator.Biome.TUNDRA: ["dead_pine"],
	MapGenerator.Biome.JUNGLE: ["palm", "tropical"],
	MapGenerator.Biome.SAVANNA: ["acacia"],
	MapGenerator.Biome.MOUNTAIN: ["pine"],
	MapGenerator.Biome.BEACH: ["palm"],
	MapGenerator.Biome.DEEP_OCEAN: [],  # No trees
	MapGenerator.Biome.ICE_SPIRES: [],  # No trees
	MapGenerator.Biome.VOLCANIC: ["charred"],
	MapGenerator.Biome.MUSHROOM: ["giant_mushroom"]
}

# Colors for different tree types
const TREE_COLORS: Dictionary = {
	"oak": {
		"trunk": Color(0.4, 0.25, 0.15),
		"leaves": Color(0.2, 0.5, 0.15)
	},
	"birch": {
		"trunk": Color(0.9, 0.88, 0.85),
		"leaves": Color(0.3, 0.55, 0.2)
	},
	"pine": {
		"trunk": Color(0.35, 0.2, 0.1),
		"leaves": Color(0.1, 0.35, 0.15)
	},
	"dead_pine": {
		"trunk": Color(0.3, 0.25, 0.2),
		"leaves": Color(0.25, 0.22, 0.18)
	},
	"willow": {
		"trunk": Color(0.35, 0.25, 0.15),
		"leaves": Color(0.25, 0.45, 0.2)
	},
	"dead": {
		"trunk": Color(0.25, 0.2, 0.15),
		"leaves": Color(0.0, 0.0, 0.0)  # No leaves
	},
	"palm": {
		"trunk": Color(0.5, 0.35, 0.2),
		"leaves": Color(0.15, 0.5, 0.1)
	},
	"tropical": {
		"trunk": Color(0.4, 0.3, 0.15),
		"leaves": Color(0.1, 0.55, 0.15)
	},
	"acacia": {
		"trunk": Color(0.45, 0.3, 0.15),
		"leaves": Color(0.35, 0.5, 0.15)
	},
	"charred": {
		"trunk": Color(0.1, 0.08, 0.05),
		"leaves": Color(0.0, 0.0, 0.0)  # No leaves
	},
	"giant_mushroom": {
		"trunk": Color(0.85, 0.8, 0.75),
		"leaves": Color(0.6, 0.2, 0.5)  # Purple cap
	}
}

# =============================================================================
# PUBLIC API
# =============================================================================

## Returns array of tree variant names for a biome
static func get_tree_variants(biome_id: int) -> Array[String]:
	var variants: Array[String] = []
	if BIOME_TREE_VARIANTS.has(biome_id):
		for v in BIOME_TREE_VARIANTS[biome_id]:
			variants.append(v)
	return variants


## Generate a tree mesh for the given biome and variant
static func generate_tree(biome_id: int, variant: String, seed_value: int, lod_level: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Determine tree parameters based on variant
	var height := rng.randf_range(MIN_HEIGHT, MAX_HEIGHT)
	var trunk_radius := height * 0.05
	var canopy_radius := height * 0.3
	
	# Adjust for specific variants
	match variant:
		"pine", "dead_pine":
			height = rng.randf_range(6.0, 12.0)
			trunk_radius = height * 0.04
			canopy_radius = height * 0.25
		"palm":
			height = rng.randf_range(5.0, 10.0)
			trunk_radius = height * 0.03
			canopy_radius = height * 0.35
		"acacia":
			height = rng.randf_range(4.0, 8.0)
			trunk_radius = height * 0.06
			canopy_radius = height * 0.5
		"giant_mushroom":
			height = rng.randf_range(4.0, 10.0)
			trunk_radius = height * 0.08
			canopy_radius = height * 0.4
		"willow":
			height = rng.randf_range(5.0, 9.0)
			trunk_radius = height * 0.05
			canopy_radius = height * 0.4
	
	# Get colors
	var colors: Dictionary = TREE_COLORS.get(variant, TREE_COLORS["oak"])
	var trunk_color: Color = colors["trunk"]
	var leaves_color: Color = colors["leaves"]
	
	# LOD adjustments
	var trunk_segments := 6
	var canopy_segments := 8
	match lod_level:
		1:
			trunk_segments = 4
			canopy_segments = 6
		2:
			trunk_segments = 3
			canopy_segments = 4
		3:
			trunk_segments = 3
			canopy_segments = 3
	
	# Generate mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate trunk
	_generate_trunk(st, height, trunk_radius, trunk_segments, trunk_color, variant, rng)
	
	# Generate canopy (unless dead/charred)
	if variant != "dead" and variant != "charred":
		_generate_canopy(st, height, canopy_radius, canopy_segments, leaves_color, variant, rng)
	
	st.generate_normals()
	var mesh := st.commit()
	
	# Validate mesh was generated successfully
	if mesh == null or mesh.get_surface_count() == 0:
		push_warning("[TreeGenerator] Failed to generate mesh for variant %s, using fallback" % variant)
		return _fallback_tree_mesh()
	
	return mesh


## Generate a simple fallback tree mesh
static func _fallback_tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var trunk_color := Color(0.4, 0.25, 0.15)
	var canopy_color := Color(0.2, 0.5, 0.15)
	var height := 5.0
	var trunk_radius := 0.2
	var canopy_radius := 1.5
	var segments := 4
	
	# Simple trunk
	var angle_step := TAU / segments
	for i in range(segments):
		var a1 := i * angle_step
		var a2 := (i + 1) * angle_step
		var x1 := cos(a1) * trunk_radius
		var z1 := sin(a1) * trunk_radius
		var x2 := cos(a2) * trunk_radius
		var z2 := sin(a2) * trunk_radius
		
		st.set_color(trunk_color)
		st.add_vertex(Vector3(x1, 0, z1))
		st.add_vertex(Vector3(x2, 0, z2))
		st.add_vertex(Vector3(x2, height * 0.5, z2))
		
		st.add_vertex(Vector3(x1, 0, z1))
		st.add_vertex(Vector3(x2, height * 0.5, z2))
		st.add_vertex(Vector3(x1, height * 0.5, z1))
	
	# Simple cone canopy
	for i in range(segments):
		var a1 := i * angle_step
		var a2 := (i + 1) * angle_step
		var x1 := cos(a1) * canopy_radius
		var z1 := sin(a1) * canopy_radius
		var x2 := cos(a2) * canopy_radius
		var z2 := sin(a2) * canopy_radius
		
		st.set_color(canopy_color)
		st.add_vertex(Vector3(x1, height * 0.5, z1))
		st.add_vertex(Vector3(x2, height * 0.5, z2))
		st.add_vertex(Vector3(0, height, 0))
	
	st.generate_normals()
	return st.commit()


## Generate a billboard mesh for distant trees
static func generate_billboard(biome_id: int, variant: String, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var colors: Dictionary = TREE_COLORS.get(variant, TREE_COLORS["oak"])
	var leaves_color: Color = colors["leaves"]
	var trunk_color: Color = colors["trunk"]
	
	# Blend trunk and leaves for billboard
	var billboard_color := trunk_color.lerp(leaves_color, 0.7)
	
	var height := rng.randf_range(MIN_HEIGHT, MAX_HEIGHT)
	var width := height * 0.6
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Two crossed quads
	_add_billboard_quad(st, Vector3.ZERO, width, height, billboard_color, 0.0)
	_add_billboard_quad(st, Vector3.ZERO, width, height, billboard_color, PI / 2.0)
	
	st.generate_normals()
	return st.commit()


# =============================================================================
# MESH GENERATION HELPERS
# =============================================================================

static func _generate_trunk(st: SurfaceTool, height: float, radius: float, segments: int, color: Color, variant: String, rng: RandomNumberGenerator) -> void:
	var trunk_height := height * 0.4
	if variant == "palm":
		trunk_height = height * 0.7
	elif variant == "pine" or variant == "dead_pine":
		trunk_height = height * 0.8
	elif variant == "giant_mushroom":
		trunk_height = height * 0.6
	
	# Generate cylinder for trunk
	var angle_step := TAU / segments
	
	for i in range(segments):
		var angle1 := i * angle_step
		var angle2 := (i + 1) * angle_step
		
		var x1 := cos(angle1) * radius
		var z1 := sin(angle1) * radius
		var x2 := cos(angle2) * radius
		var z2 := sin(angle2) * radius
		
		# Add slight variation
		var wobble := rng.randf_range(0.9, 1.1)
		
		# Bottom triangle
		st.set_color(color.darkened(0.1))
		st.add_vertex(Vector3(x1 * wobble, 0, z1 * wobble))
		st.add_vertex(Vector3(x2 * wobble, 0, z2 * wobble))
		st.set_color(color)
		st.add_vertex(Vector3(x2 * 0.8, trunk_height, z2 * 0.8))
		
		# Top triangle
		st.set_color(color.darkened(0.1))
		st.add_vertex(Vector3(x1 * wobble, 0, z1 * wobble))
		st.set_color(color)
		st.add_vertex(Vector3(x2 * 0.8, trunk_height, z2 * 0.8))
		st.add_vertex(Vector3(x1 * 0.8, trunk_height, z1 * 0.8))


static func _generate_canopy(st: SurfaceTool, height: float, radius: float, segments: int, color: Color, variant: String, rng: RandomNumberGenerator) -> void:
	var trunk_height := height * 0.4
	if variant == "palm":
		trunk_height = height * 0.7
	elif variant == "pine" or variant == "dead_pine":
		trunk_height = height * 0.8
	elif variant == "giant_mushroom":
		trunk_height = height * 0.6
	
	match variant:
		"pine", "dead_pine":
			_generate_cone_canopy(st, trunk_height, height, radius, segments, color, rng)
		"palm":
			_generate_palm_fronds(st, trunk_height, radius, segments, color, rng)
		"acacia":
			_generate_flat_canopy(st, trunk_height, radius, segments, color, rng)
		"giant_mushroom":
			_generate_mushroom_cap(st, trunk_height, radius, segments, color, rng)
		"willow":
			_generate_drooping_canopy(st, trunk_height, height, radius, segments, color, rng)
		_:
			_generate_sphere_canopy(st, trunk_height, height, radius, segments, color, rng)


static func _generate_sphere_canopy(st: SurfaceTool, base_y: float, total_height: float, radius: float, segments: int, color: Color, rng: RandomNumberGenerator) -> void:
	var center_y := base_y + (total_height - base_y) * 0.5
	var v_segments := maxi(segments / 2, 3)
	
	for i in range(segments):
		for j in range(v_segments):
			var theta1 := (float(i) / segments) * TAU
			var theta2 := (float(i + 1) / segments) * TAU
			var phi1 := (float(j) / v_segments) * PI
			var phi2 := (float(j + 1) / v_segments) * PI
			
			var wobble := rng.randf_range(0.85, 1.15)
			
			var p1 := _sphere_point(theta1, phi1, radius * wobble) + Vector3(0, center_y, 0)
			var p2 := _sphere_point(theta2, phi1, radius * wobble) + Vector3(0, center_y, 0)
			var p3 := _sphere_point(theta2, phi2, radius * wobble) + Vector3(0, center_y, 0)
			var p4 := _sphere_point(theta1, phi2, radius * wobble) + Vector3(0, center_y, 0)
			
			var shade := rng.randf_range(0.9, 1.1)
			var c := color * shade
			
			st.set_color(c)
			st.add_vertex(p1)
			st.add_vertex(p2)
			st.add_vertex(p3)
			
			st.add_vertex(p1)
			st.add_vertex(p3)
			st.add_vertex(p4)


static func _generate_cone_canopy(st: SurfaceTool, base_y: float, total_height: float, radius: float, segments: int, color: Color, rng: RandomNumberGenerator) -> void:
	var layers := 3
	var layer_height := (total_height - base_y) / layers
	
	for layer in range(layers):
		var layer_base := base_y + layer * layer_height * 0.7
		var layer_radius := radius * (1.0 - float(layer) / layers * 0.3)
		var layer_top := layer_base + layer_height
		
		# Generate cone for this layer
		var angle_step := TAU / segments
		for i in range(segments):
			var angle1 := i * angle_step
			var angle2 := (i + 1) * angle_step
			
			var x1 := cos(angle1) * layer_radius
			var z1 := sin(angle1) * layer_radius
			var x2 := cos(angle2) * layer_radius
			var z2 := sin(angle2) * layer_radius
			
			var shade := rng.randf_range(0.85, 1.1)
			st.set_color(color * shade)
			
			# Triangle to apex
			st.add_vertex(Vector3(x1, layer_base, z1))
			st.add_vertex(Vector3(x2, layer_base, z2))
			st.add_vertex(Vector3(0, layer_top, 0))


static func _generate_palm_fronds(st: SurfaceTool, base_y: float, radius: float, segments: int, color: Color, rng: RandomNumberGenerator) -> void:
	var frond_count := 6
	var frond_length := radius * 1.5
	
	for i in range(frond_count):
		var angle := (float(i) / frond_count) * TAU + rng.randf_range(-0.2, 0.2)
		var droop := rng.randf_range(0.3, 0.5)
		
		var start := Vector3(0, base_y, 0)
		var mid := Vector3(cos(angle) * frond_length * 0.5, base_y + 0.3, sin(angle) * frond_length * 0.5)
		var end := Vector3(cos(angle) * frond_length, base_y - droop, sin(angle) * frond_length)
		
		var width := 0.3
		var perp := Vector3(-sin(angle), 0, cos(angle)) * width
		
		st.set_color(color)
		st.add_vertex(start)
		st.add_vertex(mid + perp)
		st.add_vertex(mid - perp)
		
		st.add_vertex(mid + perp)
		st.add_vertex(end)
		st.add_vertex(mid - perp)


static func _generate_flat_canopy(st: SurfaceTool, base_y: float, radius: float, segments: int, color: Color, rng: RandomNumberGenerator) -> void:
	var center := Vector3(0, base_y + 0.5, 0)
	var angle_step := TAU / segments
	
	for i in range(segments):
		var angle1 := i * angle_step
		var angle2 := (i + 1) * angle_step
		
		var wobble := rng.randf_range(0.9, 1.1)
		var x1 := cos(angle1) * radius * wobble
		var z1 := sin(angle1) * radius * wobble
		var x2 := cos(angle2) * radius * wobble
		var z2 := sin(angle2) * radius * wobble
		
		var shade := rng.randf_range(0.9, 1.1)
		st.set_color(color * shade)
		
		# Top face
		st.add_vertex(center)
		st.add_vertex(Vector3(x1, base_y + 0.3, z1))
		st.add_vertex(Vector3(x2, base_y + 0.3, z2))
		
		# Bottom face
		st.add_vertex(center + Vector3(0, -0.4, 0))
		st.add_vertex(Vector3(x2, base_y - 0.1, z2))
		st.add_vertex(Vector3(x1, base_y - 0.1, z1))


static func _generate_mushroom_cap(st: SurfaceTool, base_y: float, radius: float, segments: int, color: Color, rng: RandomNumberGenerator) -> void:
	var cap_height := radius * 0.5
	var center := Vector3(0, base_y + cap_height * 0.5, 0)
	var angle_step := TAU / segments
	
	for i in range(segments):
		var angle1 := i * angle_step
		var angle2 := (i + 1) * angle_step
		
		var x1 := cos(angle1) * radius
		var z1 := sin(angle1) * radius
		var x2 := cos(angle2) * radius
		var z2 := sin(angle2) * radius
		
		var shade := rng.randf_range(0.9, 1.1)
		st.set_color(color * shade)
		
		# Top dome
		st.add_vertex(Vector3(0, base_y + cap_height, 0))
		st.add_vertex(Vector3(x1, base_y, z1))
		st.add_vertex(Vector3(x2, base_y, z2))
		
		# Underside (lighter)
		st.set_color(color.lightened(0.3) * shade)
		st.add_vertex(Vector3(0, base_y - 0.2, 0))
		st.add_vertex(Vector3(x2 * 0.9, base_y, z2 * 0.9))
		st.add_vertex(Vector3(x1 * 0.9, base_y, z1 * 0.9))


static func _generate_drooping_canopy(st: SurfaceTool, base_y: float, total_height: float, radius: float, segments: int, color: Color, rng: RandomNumberGenerator) -> void:
	# Main canopy sphere
	_generate_sphere_canopy(st, base_y, total_height, radius * 0.7, segments, color, rng)
	
	# Drooping branches
	var branch_count := 8
	for i in range(branch_count):
		var angle := (float(i) / branch_count) * TAU
		var start_y := base_y + (total_height - base_y) * 0.3
		var droop := rng.randf_range(1.5, 2.5)
		
		var start := Vector3(cos(angle) * radius * 0.5, start_y, sin(angle) * radius * 0.5)
		var end := Vector3(cos(angle) * radius, start_y - droop, sin(angle) * radius)
		
		var width := 0.15
		var perp := Vector3(-sin(angle), 0, cos(angle)) * width
		
		st.set_color(color.darkened(0.1))
		st.add_vertex(start + perp)
		st.add_vertex(start - perp)
		st.add_vertex(end)


static func _sphere_point(theta: float, phi: float, radius: float) -> Vector3:
	return Vector3(
		sin(phi) * cos(theta) * radius,
		cos(phi) * radius,
		sin(phi) * sin(theta) * radius
	)


static func _add_billboard_quad(st: SurfaceTool, center: Vector3, width: float, height: float, color: Color, rotation: float) -> void:
	var half_w := width * 0.5
	var cos_r := cos(rotation)
	var sin_r := sin(rotation)
	
	var offset_x := Vector3(cos_r * half_w, 0, sin_r * half_w)
	
	var bl := center - offset_x
	var br := center + offset_x
	var tl := center - offset_x + Vector3(0, height, 0)
	var tr := center + offset_x + Vector3(0, height, 0)
	
	st.set_color(color)
	st.add_vertex(bl)
	st.add_vertex(br)
	st.add_vertex(tr)
	
	st.add_vertex(bl)
	st.add_vertex(tr)
	st.add_vertex(tl)
