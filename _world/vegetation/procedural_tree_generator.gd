extends RefCounted
class_name ProceduralTreeGenerator

## Procedural Tree Generator
##
## Generates unique trees using L-system inspired branching algorithms.
## Each biome has distinct tree styles:
## - Forest: Oak, Birch with full canopies
## - Jungle: Tall, strong trees with dense foliage
## - Tundra/Ice: Pine trees, long and thin
## - Volcanic: Charcoal dead trees without leaves
## - Swamp: Willow-like drooping trees
## - Desert: Sparse cacti or dead trees

# =============================================================================
# TREE STYLE DEFINITIONS
# =============================================================================

enum TreeStyle {
	OAK,           # Round canopy, medium height
	BIRCH,         # Tall thin trunk, small canopy
	PINE,          # Conical shape, evergreen
	PALM,          # Tropical, fronds at top
	WILLOW,        # Drooping branches
	DEAD,          # No leaves, charcoal
	JUNGLE_GIANT,  # Very tall, thick trunk, dense leaves
	ACACIA,        # Flat top canopy
	MUSHROOM_TREE, # Giant mushroom shape
}

# Biome to tree style mapping
const BIOME_TREE_STYLES: Dictionary = {
	MapGenerator.Biome.PLAINS: [TreeStyle.OAK],
	MapGenerator.Biome.FOREST: [TreeStyle.OAK, TreeStyle.BIRCH, TreeStyle.PINE],
	MapGenerator.Biome.DESERT: [TreeStyle.DEAD],
	MapGenerator.Biome.SWAMP: [TreeStyle.WILLOW, TreeStyle.DEAD],
	MapGenerator.Biome.TUNDRA: [TreeStyle.PINE, TreeStyle.DEAD],
	MapGenerator.Biome.JUNGLE: [TreeStyle.JUNGLE_GIANT, TreeStyle.PALM],
	MapGenerator.Biome.SAVANNA: [TreeStyle.ACACIA],
	MapGenerator.Biome.MOUNTAIN: [TreeStyle.PINE, TreeStyle.DEAD],
	MapGenerator.Biome.BEACH: [TreeStyle.PALM],
	MapGenerator.Biome.DEEP_OCEAN: [],
	MapGenerator.Biome.ICE_SPIRES: [TreeStyle.PINE],
	MapGenerator.Biome.VOLCANIC: [TreeStyle.DEAD],
	MapGenerator.Biome.MUSHROOM: [TreeStyle.MUSHROOM_TREE],
}

# =============================================================================
# TREE PARAMETERS
# =============================================================================

class TreeParams:
	var trunk_height: float = 5.0
	var trunk_radius: float = 0.3
	var trunk_taper: float = 0.7  # How much trunk narrows at top
	var branch_levels: int = 3
	var branches_per_level: int = 4
	var branch_angle: float = 45.0
	var branch_length_factor: float = 0.6
	var branch_radius_factor: float = 0.5
	var leaf_density: float = 1.0
	var leaf_size: float = 1.0
	var trunk_color: Color = Color(0.4, 0.3, 0.2)
	var leaf_color: Color = Color(0.2, 0.5, 0.2)
	var has_leaves: bool = true
	var droop_factor: float = 0.0  # For willow-style trees
	var canopy_shape: int = 0  # 0=sphere, 1=cone, 2=flat, 3=mushroom

# =============================================================================
# GENERATION
# =============================================================================

var _rng: RandomNumberGenerator


func _init() -> void:
	_rng = RandomNumberGenerator.new()


func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func generate_tree_mesh(style: TreeStyle, seed_value: int, lod: int = 0) -> ArrayMesh:
	_rng.seed = seed_value
	
	var params: TreeParams = _get_params_for_style(style)
	
	# Add random variation
	params.trunk_height *= _rng.randf_range(0.8, 1.2)
	params.trunk_radius *= _rng.randf_range(0.9, 1.1)
	params.branch_angle += _rng.randf_range(-10, 10)
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate trunk
	_generate_trunk(st, params, lod)
	
	# Generate branches
	if lod < 2 and params.branch_levels > 0:
		_generate_branches(st, params, lod)
	
	# Generate leaves/canopy
	if params.has_leaves and lod < 3:
		_generate_canopy(st, params, lod)
	
	st.generate_normals()
	var mesh := st.commit()
	
	# Add material that uses vertex colors
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mesh.surface_set_material(0, material)
	
	return mesh


func get_tree_style_for_biome(biome: int, seed_value: int) -> TreeStyle:
	var styles: Array = BIOME_TREE_STYLES.get(biome, [TreeStyle.OAK])
	if styles.is_empty():
		return TreeStyle.OAK
	
	_rng.seed = seed_value
	return styles[_rng.randi() % styles.size()] as TreeStyle


func _get_params_for_style(style: TreeStyle) -> TreeParams:
	var p := TreeParams.new()
	
	match style:
		TreeStyle.OAK:
			p.trunk_height = 6.0
			p.trunk_radius = 0.4
			p.branch_levels = 3
			p.branches_per_level = 5
			p.branch_angle = 50.0
			p.leaf_density = 1.2
			p.leaf_size = 2.5
			p.canopy_shape = 0  # Sphere
			p.trunk_color = Color(0.35, 0.25, 0.15)
			p.leaf_color = Color(0.25, 0.45, 0.2)
			
		TreeStyle.BIRCH:
			p.trunk_height = 8.0
			p.trunk_radius = 0.25
			p.trunk_taper = 0.8
			p.branch_levels = 2
			p.branches_per_level = 4
			p.branch_angle = 35.0
			p.leaf_density = 0.8
			p.leaf_size = 1.8
			p.canopy_shape = 0
			p.trunk_color = Color(0.9, 0.9, 0.85)
			p.leaf_color = Color(0.3, 0.5, 0.2)
			
		TreeStyle.PINE:
			p.trunk_height = 10.0
			p.trunk_radius = 0.3
			p.trunk_taper = 0.6
			p.branch_levels = 5
			p.branches_per_level = 6
			p.branch_angle = 70.0
			p.branch_length_factor = 0.4
			p.leaf_density = 1.5
			p.leaf_size = 1.2
			p.canopy_shape = 1  # Cone
			p.trunk_color = Color(0.3, 0.2, 0.1)
			p.leaf_color = Color(0.15, 0.35, 0.15)
			
		TreeStyle.PALM:
			p.trunk_height = 7.0
			p.trunk_radius = 0.35
			p.trunk_taper = 0.9
			p.branch_levels = 1
			p.branches_per_level = 8
			p.branch_angle = 30.0
			p.branch_length_factor = 1.2
			p.leaf_density = 0.6
			p.leaf_size = 3.0
			p.droop_factor = 0.5
			p.canopy_shape = 2  # Flat top
			p.trunk_color = Color(0.5, 0.4, 0.3)
			p.leaf_color = Color(0.2, 0.5, 0.15)
			
		TreeStyle.WILLOW:
			p.trunk_height = 5.0
			p.trunk_radius = 0.5
			p.branch_levels = 2
			p.branches_per_level = 8
			p.branch_angle = 80.0
			p.branch_length_factor = 0.8
			p.leaf_density = 1.0
			p.leaf_size = 0.8
			p.droop_factor = 0.9
			p.canopy_shape = 0
			p.trunk_color = Color(0.3, 0.25, 0.2)
			p.leaf_color = Color(0.35, 0.5, 0.25)
			
		TreeStyle.DEAD:
			p.trunk_height = 5.0
			p.trunk_radius = 0.3
			p.trunk_taper = 0.5
			p.branch_levels = 3
			p.branches_per_level = 3
			p.branch_angle = 40.0
			p.branch_length_factor = 0.5
			p.has_leaves = false
			p.trunk_color = Color(0.15, 0.1, 0.08)  # Charcoal
			
		TreeStyle.JUNGLE_GIANT:
			p.trunk_height = 15.0
			p.trunk_radius = 0.8
			p.trunk_taper = 0.75
			p.branch_levels = 4
			p.branches_per_level = 6
			p.branch_angle = 55.0
			p.branch_length_factor = 0.7
			p.leaf_density = 2.0
			p.leaf_size = 3.5
			p.canopy_shape = 0
			p.trunk_color = Color(0.25, 0.2, 0.15)
			p.leaf_color = Color(0.15, 0.45, 0.1)
			
		TreeStyle.ACACIA:
			p.trunk_height = 6.0
			p.trunk_radius = 0.35
			p.trunk_taper = 0.65
			p.branch_levels = 2
			p.branches_per_level = 5
			p.branch_angle = 85.0
			p.branch_length_factor = 0.9
			p.leaf_density = 0.7
			p.leaf_size = 4.0
			p.canopy_shape = 2  # Flat
			p.trunk_color = Color(0.4, 0.3, 0.2)
			p.leaf_color = Color(0.35, 0.45, 0.2)
			
		TreeStyle.MUSHROOM_TREE:
			p.trunk_height = 8.0
			p.trunk_radius = 0.6
			p.trunk_taper = 0.85
			p.branch_levels = 0
			p.leaf_density = 1.0
			p.leaf_size = 5.0
			p.canopy_shape = 3  # Mushroom cap
			p.trunk_color = Color(0.8, 0.75, 0.7)
			p.leaf_color = Color(0.7, 0.2, 0.3)  # Red cap
	
	return p


# =============================================================================
# MESH GENERATION
# =============================================================================

func _generate_trunk(st: SurfaceTool, params: TreeParams, _lod: int) -> void:
	var segments: int = 8
	var height_segments: int = 4
	
	for h in range(height_segments + 1):
		var t: float = float(h) / height_segments
		var y: float = t * params.trunk_height
		var radius: float = params.trunk_radius * lerpf(1.0, params.trunk_taper, t)
		
		for i in range(segments):
			var angle: float = float(i) / segments * TAU
			var next_angle: float = float(i + 1) / segments * TAU
			
			var x1: float = cos(angle) * radius
			var z1: float = sin(angle) * radius
			var x2: float = cos(next_angle) * radius
			var z2: float = sin(next_angle) * radius
			
			st.set_color(params.trunk_color)
			
			if h < height_segments:
				var next_t: float = float(h + 1) / height_segments
				var next_y: float = next_t * params.trunk_height
				var next_radius: float = params.trunk_radius * lerpf(1.0, params.trunk_taper, next_t)
				
				var nx1: float = cos(angle) * next_radius
				var nz1: float = sin(angle) * next_radius
				var nx2: float = cos(next_angle) * next_radius
				var nz2: float = sin(next_angle) * next_radius
				
				# Triangle 1
				st.add_vertex(Vector3(x1, y, z1))
				st.add_vertex(Vector3(x2, y, z2))
				st.add_vertex(Vector3(nx2, next_y, nz2))
				
				# Triangle 2
				st.add_vertex(Vector3(x1, y, z1))
				st.add_vertex(Vector3(nx2, next_y, nz2))
				st.add_vertex(Vector3(nx1, next_y, nz1))


func _generate_branches(st: SurfaceTool, params: TreeParams, _lod: int) -> void:
	var start_height: float = params.trunk_height * 0.5
	var height_step: float = (params.trunk_height - start_height) / maxf(params.branch_levels, 1)
	
	for level in range(params.branch_levels):
		var branch_y: float = start_height + level * height_step
		var branch_radius: float = params.trunk_radius * pow(params.branch_radius_factor, level + 1)
		var branch_length: float = params.trunk_height * 0.3 * pow(params.branch_length_factor, level)
		
		for b in range(params.branches_per_level):
			var base_angle: float = float(b) / params.branches_per_level * TAU
			base_angle += _rng.randf() * 0.5  # Random offset
			
			var pitch: float = deg_to_rad(90 - params.branch_angle + _rng.randf_range(-10, 10))
			
			# Apply droop for willow-style trees
			if params.droop_factor > 0:
				pitch -= params.droop_factor * 0.5
			
			var dir := Vector3(
				cos(base_angle) * cos(pitch),
				sin(pitch),
				sin(base_angle) * cos(pitch)
			).normalized()
			
			var start_pos := Vector3(0, branch_y, 0)
			var end_pos: Vector3 = start_pos + dir * branch_length
			
			# Apply droop curve
			if params.droop_factor > 0:
				end_pos.y -= branch_length * params.droop_factor * 0.5
			
			_add_branch_segment(st, start_pos, end_pos, branch_radius, params.trunk_color)


func _add_branch_segment(st: SurfaceTool, start: Vector3, end: Vector3, radius: float, color: Color) -> void:
	var dir: Vector3 = (end - start).normalized()
	var perp: Vector3 = dir.cross(Vector3.UP).normalized()
	if perp.length_squared() < 0.01:
		perp = dir.cross(Vector3.RIGHT).normalized()
	var perp2: Vector3 = dir.cross(perp).normalized()
	
	var segments: int = 4
	st.set_color(color)
	
	for i in range(segments):
		var angle: float = float(i) / segments * TAU
		var next_angle: float = float(i + 1) / segments * TAU
		
		var offset1: Vector3 = (perp * cos(angle) + perp2 * sin(angle)) * radius
		var offset2: Vector3 = (perp * cos(next_angle) + perp2 * sin(next_angle)) * radius
		
		var end_radius: float = radius * 0.5
		var end_offset1: Vector3 = (perp * cos(angle) + perp2 * sin(angle)) * end_radius
		var end_offset2: Vector3 = (perp * cos(next_angle) + perp2 * sin(next_angle)) * end_radius
		
		# Triangle 1
		st.add_vertex(start + offset1)
		st.add_vertex(start + offset2)
		st.add_vertex(end + end_offset2)
		
		# Triangle 2
		st.add_vertex(start + offset1)
		st.add_vertex(end + end_offset2)
		st.add_vertex(end + end_offset1)


func _generate_canopy(st: SurfaceTool, params: TreeParams, lod: int) -> void:
	var canopy_center := Vector3(0, params.trunk_height, 0)
	var canopy_radius: float = params.leaf_size
	
	st.set_color(params.leaf_color)
	
	match params.canopy_shape:
		0:  # Sphere
			_generate_sphere_canopy(st, canopy_center, canopy_radius, lod)
		1:  # Cone (pine)
			_generate_cone_canopy(st, canopy_center, canopy_radius, params, lod)
		2:  # Flat (acacia)
			_generate_flat_canopy(st, canopy_center, canopy_radius, params, lod)
		3:  # Mushroom cap
			_generate_mushroom_canopy(st, canopy_center, canopy_radius, params, lod)


func _generate_sphere_canopy(st: SurfaceTool, center: Vector3, radius: float, lod: int) -> void:
	var detail: int = 8 - lod * 2
	detail = maxi(detail, 4)
	
	for lat in range(detail):
		var theta1: float = float(lat) / detail * PI
		var theta2: float = float(lat + 1) / detail * PI
		
		for lon in range(detail * 2):
			var phi1: float = float(lon) / (detail * 2) * TAU
			var phi2: float = float(lon + 1) / (detail * 2) * TAU
			
			var p1 := center + Vector3(
				sin(theta1) * cos(phi1),
				cos(theta1),
				sin(theta1) * sin(phi1)
			) * radius
			
			var p2 := center + Vector3(
				sin(theta1) * cos(phi2),
				cos(theta1),
				sin(theta1) * sin(phi2)
			) * radius
			
			var p3 := center + Vector3(
				sin(theta2) * cos(phi2),
				cos(theta2),
				sin(theta2) * sin(phi2)
			) * radius
			
			var p4 := center + Vector3(
				sin(theta2) * cos(phi1),
				cos(theta2),
				sin(theta2) * sin(phi1)
			) * radius
			
			st.add_vertex(p1)
			st.add_vertex(p2)
			st.add_vertex(p3)
			
			st.add_vertex(p1)
			st.add_vertex(p3)
			st.add_vertex(p4)


func _generate_cone_canopy(st: SurfaceTool, center: Vector3, radius: float, params: TreeParams, lod: int) -> void:
	var cone_height: float = params.trunk_height * 0.7
	var layers: int = 4 - lod
	layers = maxi(layers, 2)
	
	for layer in range(layers):
		var t: float = float(layer) / layers
		var layer_y: float = center.y - params.trunk_height * 0.3 + t * cone_height
		var layer_radius: float = radius * (1.0 - t * 0.8)
		
		_add_disk(st, Vector3(0, layer_y, 0), layer_radius, 8 - lod * 2)


func _generate_flat_canopy(st: SurfaceTool, center: Vector3, radius: float, _params: TreeParams, lod: int) -> void:
	var thickness: float = radius * 0.3
	
	# Top disk
	_add_disk(st, center + Vector3(0, thickness * 0.5, 0), radius, 12 - lod * 3)
	
	# Bottom disk
	_add_disk(st, center - Vector3(0, thickness * 0.5, 0), radius * 0.9, 12 - lod * 3)


func _generate_mushroom_canopy(st: SurfaceTool, center: Vector3, radius: float, _params: TreeParams, lod: int) -> void:
	var segments: int = 12 - lod * 3
	segments = maxi(segments, 6)
	
	# Mushroom cap - dome on top, concave underneath
	for lat in range(segments / 2):
		var theta1: float = float(lat) / (segments / 2) * PI * 0.5
		var theta2: float = float(lat + 1) / (segments / 2) * PI * 0.5
		
		for lon in range(segments):
			var phi1: float = float(lon) / segments * TAU
			var phi2: float = float(lon + 1) / segments * TAU
			
			var r1: float = radius * cos(theta1)
			var r2: float = radius * cos(theta2)
			var y1: float = center.y + radius * 0.3 * sin(theta1)
			var y2: float = center.y + radius * 0.3 * sin(theta2)
			
			var p1 := Vector3(r1 * cos(phi1), y1, r1 * sin(phi1))
			var p2 := Vector3(r1 * cos(phi2), y1, r1 * sin(phi2))
			var p3 := Vector3(r2 * cos(phi2), y2, r2 * sin(phi2))
			var p4 := Vector3(r2 * cos(phi1), y2, r2 * sin(phi1))
			
			st.add_vertex(p1)
			st.add_vertex(p2)
			st.add_vertex(p3)
			
			st.add_vertex(p1)
			st.add_vertex(p3)
			st.add_vertex(p4)


func _add_disk(st: SurfaceTool, center: Vector3, radius: float, segments: int) -> void:
	segments = maxi(segments, 4)
	
	for i in range(segments):
		var angle1: float = float(i) / segments * TAU
		var angle2: float = float(i + 1) / segments * TAU
		
		var p1: Vector3 = center
		var p2: Vector3 = center + Vector3(cos(angle1) * radius, 0, sin(angle1) * radius)
		var p3: Vector3 = center + Vector3(cos(angle2) * radius, 0, sin(angle2) * radius)
		
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p3)
