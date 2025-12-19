class_name WallGenerator
extends RefCounted

const WALL_HEIGHT: float = 3.0
const WALL_THICKNESS: float = 0.3
const WALL_WIDTH: float = 4.0

const WOOD_COLORS: Array[Color] = [
	Color(0.4, 0.25, 0.15),
	Color(0.45, 0.28, 0.17),
	Color(0.35, 0.22, 0.12)
]

const STONE_COLORS: Array[Color] = [
	Color(0.5, 0.5, 0.5),
	Color(0.55, 0.53, 0.52),
	Color(0.45, 0.45, 0.47)
]

const FACTION_COLORS: Dictionary = {
	0: Color(0.9, 0.9, 0.95),   # Castle - white stone
	1: Color(0.15, 0.1, 0.12),  # Inferno - obsidian
	2: Color(0.3, 0.45, 0.25),  # Rampart - living wood
	3: Color(0.2, 0.2, 0.25),   # Necropolis - dark stone
	4: Color(0.6, 0.55, 0.4),   # Tower - arcane stone
	5: Color(0.5, 0.35, 0.2),   # Stronghold - rough stone
	6: Color(0.4, 0.5, 0.55),   # Fortress - swamp stone
	7: Color(0.3, 0.35, 0.5),   # Conflux - elemental
}


static func generate_wall(material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	var has_window := rng.randf() < 0.3 and lod_level == 0
	
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.5
	
	var half_width := WALL_WIDTH / 2.0
	var half_thickness := WALL_THICKNESS / 2.0
	
	if lod_level <= 1:
		_generate_detailed_wall(st, half_width, half_thickness, base_color, noise, rng, has_window, material_type)
	else:
		_generate_simple_wall(st, half_width, half_thickness, base_color)
	
	st.generate_normals()
	return st.commit()


static func _get_base_color(material_type: int, faction_id: int, rng: RandomNumberGenerator) -> Color:
	match material_type:
		BuildPieceData.MaterialType.WOOD:
			return WOOD_COLORS[rng.randi() % WOOD_COLORS.size()]
		BuildPieceData.MaterialType.STONE:
			return STONE_COLORS[rng.randi() % STONE_COLORS.size()]
		BuildPieceData.MaterialType.METAL:
			return Color(0.4, 0.4, 0.45)
		BuildPieceData.MaterialType.FACTION_SPECIFIC:
			if FACTION_COLORS.has(faction_id):
				return FACTION_COLORS[faction_id]
			return Color(0.5, 0.5, 0.5)
	return Color(0.5, 0.5, 0.5)


static func _generate_detailed_wall(st: SurfaceTool, half_width: float, half_thickness: float, 
		base_color: Color, noise: FastNoiseLite, rng: RandomNumberGenerator, 
		has_window: bool, material_type: int) -> void:
	
	var segments_x := 8
	var segments_y := 6
	var seg_width := WALL_WIDTH / segments_x
	var seg_height := WALL_HEIGHT / segments_y
	
	var window_min_x := 2
	var window_max_x := 5
	var window_min_y := 2
	var window_max_y := 4
	
	# Front face
	for ix in range(segments_x):
		for iy in range(segments_y):
			var is_window := has_window and ix >= window_min_x and ix <= window_max_x and iy >= window_min_y and iy <= window_max_y
			if is_window:
				continue
			
			var x0 := -half_width + ix * seg_width
			var x1 := x0 + seg_width
			var y0 := iy * seg_height
			var y1 := y0 + seg_height
			var z := half_thickness
			
			var color_var := noise.get_noise_2d(ix * 10.0, iy * 10.0) * 0.1
			var color := Color(
				clampf(base_color.r + color_var, 0.0, 1.0),
				clampf(base_color.g + color_var, 0.0, 1.0),
				clampf(base_color.b + color_var, 0.0, 1.0)
			)
			
			if material_type == BuildPieceData.MaterialType.WOOD:
				var plank_line := (iy % 2 == 0)
				if plank_line:
					color = color.darkened(0.1)
			
			st.set_color(color)
			_add_quad(st, Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z))
	
	# Back face
	for ix in range(segments_x):
		for iy in range(segments_y):
			var is_window := has_window and ix >= window_min_x and ix <= window_max_x and iy >= window_min_y and iy <= window_max_y
			if is_window:
				continue
			
			var x0 := -half_width + ix * seg_width
			var x1 := x0 + seg_width
			var y0 := iy * seg_height
			var y1 := y0 + seg_height
			var z := -half_thickness
			
			var color_var := noise.get_noise_2d(ix * 10.0 + 100, iy * 10.0) * 0.1
			var color := Color(
				clampf(base_color.r + color_var, 0.0, 1.0),
				clampf(base_color.g + color_var, 0.0, 1.0),
				clampf(base_color.b + color_var, 0.0, 1.0)
			)
			
			st.set_color(color)
			_add_quad(st, Vector3(x1, y0, z), Vector3(x0, y0, z), Vector3(x0, y1, z), Vector3(x1, y1, z))
	
	# Side faces
	st.set_color(base_color.darkened(0.15))
	_add_quad(st, Vector3(-half_width, 0, -half_thickness), Vector3(-half_width, 0, half_thickness),
			Vector3(-half_width, WALL_HEIGHT, half_thickness), Vector3(-half_width, WALL_HEIGHT, -half_thickness))
	_add_quad(st, Vector3(half_width, 0, half_thickness), Vector3(half_width, 0, -half_thickness),
			Vector3(half_width, WALL_HEIGHT, -half_thickness), Vector3(half_width, WALL_HEIGHT, half_thickness))
	
	# Top face
	st.set_color(base_color.darkened(0.05))
	_add_quad(st, Vector3(-half_width, WALL_HEIGHT, half_thickness), Vector3(half_width, WALL_HEIGHT, half_thickness),
			Vector3(half_width, WALL_HEIGHT, -half_thickness), Vector3(-half_width, WALL_HEIGHT, -half_thickness))
	
	# Bottom face
	st.set_color(base_color.darkened(0.2))
	_add_quad(st, Vector3(-half_width, 0, -half_thickness), Vector3(half_width, 0, -half_thickness),
			Vector3(half_width, 0, half_thickness), Vector3(-half_width, 0, half_thickness))
	
	# Window frame if present
	if has_window:
		var frame_color := base_color.darkened(0.3)
		st.set_color(frame_color)
		
		var wx0 := -half_width + window_min_x * seg_width
		var wx1 := -half_width + (window_max_x + 1) * seg_width
		var wy0 := window_min_y * seg_height
		var wy1 := (window_max_y + 1) * seg_height
		
		# Window inner walls
		_add_quad(st, Vector3(wx0, wy0, half_thickness), Vector3(wx0, wy0, -half_thickness),
				Vector3(wx0, wy1, -half_thickness), Vector3(wx0, wy1, half_thickness))
		_add_quad(st, Vector3(wx1, wy0, -half_thickness), Vector3(wx1, wy0, half_thickness),
				Vector3(wx1, wy1, half_thickness), Vector3(wx1, wy1, -half_thickness))
		_add_quad(st, Vector3(wx0, wy0, -half_thickness), Vector3(wx0, wy0, half_thickness),
				Vector3(wx1, wy0, half_thickness), Vector3(wx1, wy0, -half_thickness))
		_add_quad(st, Vector3(wx0, wy1, half_thickness), Vector3(wx0, wy1, -half_thickness),
				Vector3(wx1, wy1, -half_thickness), Vector3(wx1, wy1, half_thickness))


static func _generate_simple_wall(st: SurfaceTool, half_width: float, half_thickness: float, base_color: Color) -> void:
	st.set_color(base_color)
	
	# Front
	_add_quad(st, Vector3(-half_width, 0, half_thickness), Vector3(half_width, 0, half_thickness),
			Vector3(half_width, WALL_HEIGHT, half_thickness), Vector3(-half_width, WALL_HEIGHT, half_thickness))
	# Back
	_add_quad(st, Vector3(half_width, 0, -half_thickness), Vector3(-half_width, 0, -half_thickness),
			Vector3(-half_width, WALL_HEIGHT, -half_thickness), Vector3(half_width, WALL_HEIGHT, -half_thickness))
	# Left
	st.set_color(base_color.darkened(0.15))
	_add_quad(st, Vector3(-half_width, 0, -half_thickness), Vector3(-half_width, 0, half_thickness),
			Vector3(-half_width, WALL_HEIGHT, half_thickness), Vector3(-half_width, WALL_HEIGHT, -half_thickness))
	# Right
	_add_quad(st, Vector3(half_width, 0, half_thickness), Vector3(half_width, 0, -half_thickness),
			Vector3(half_width, WALL_HEIGHT, -half_thickness), Vector3(half_width, WALL_HEIGHT, half_thickness))
	# Top
	st.set_color(base_color.darkened(0.05))
	_add_quad(st, Vector3(-half_width, WALL_HEIGHT, half_thickness), Vector3(half_width, WALL_HEIGHT, half_thickness),
			Vector3(half_width, WALL_HEIGHT, -half_thickness), Vector3(-half_width, WALL_HEIGHT, -half_thickness))
	# Bottom
	st.set_color(base_color.darkened(0.2))
	_add_quad(st, Vector3(-half_width, 0, -half_thickness), Vector3(half_width, 0, -half_thickness),
			Vector3(half_width, 0, half_thickness), Vector3(-half_width, 0, half_thickness))


static func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)


static func _rotate_y(p: Vector3, cos_a: float, sin_a: float) -> Vector3:
	return Vector3(p.x * cos_a - p.z * sin_a, p.y, p.x * sin_a + p.z * cos_a)


static func generate_collision_shape(dimensions: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = dimensions
	return shape


# ============================================================================
# ANGLED WALL GENERATION
# ============================================================================

static func generate_angled_wall(angle: float, material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	
	var half_width := WALL_WIDTH / 2.0
	var half_thickness := WALL_THICKNESS / 2.0
	
	# Calculate rotated corners based on angle
	var angle_rad := deg_to_rad(angle)
	var cos_a := cos(angle_rad)
	var sin_a := sin(angle_rad)
	
	# Generate wall with rotation applied
	if lod_level <= 1:
		_generate_angled_wall_detailed(st, half_width, half_thickness, base_color, cos_a, sin_a)
	else:
		_generate_angled_wall_simple(st, half_width, half_thickness, base_color, cos_a, sin_a)
	
	st.generate_normals()
	return st.commit()


static func _generate_angled_wall_detailed(st: SurfaceTool, half_width: float, half_thickness: float, 
		base_color: Color, cos_a: float, sin_a: float) -> void:
	
	# Front face
	st.set_color(base_color)
	var v0: Vector3 = _rotate_y(Vector3(-half_width, 0, half_thickness), cos_a, sin_a)
	var v1: Vector3 = _rotate_y(Vector3(half_width, 0, half_thickness), cos_a, sin_a)
	var v2: Vector3 = _rotate_y(Vector3(half_width, WALL_HEIGHT, half_thickness), cos_a, sin_a)
	var v3: Vector3 = _rotate_y(Vector3(-half_width, WALL_HEIGHT, half_thickness), cos_a, sin_a)
	_add_quad(st, v0, v1, v2, v3)
	
	# Back face
	st.set_color(base_color.darkened(0.05))
	v0 = _rotate_y(Vector3(half_width, 0, -half_thickness), cos_a, sin_a)
	v1 = _rotate_y(Vector3(-half_width, 0, -half_thickness), cos_a, sin_a)
	v2 = _rotate_y(Vector3(-half_width, WALL_HEIGHT, -half_thickness), cos_a, sin_a)
	v3 = _rotate_y(Vector3(half_width, WALL_HEIGHT, -half_thickness), cos_a, sin_a)
	_add_quad(st, v0, v1, v2, v3)
	
	# Side faces
	st.set_color(base_color.darkened(0.15))
	v0 = _rotate_y(Vector3(-half_width, 0, -half_thickness), cos_a, sin_a)
	v1 = _rotate_y(Vector3(-half_width, 0, half_thickness), cos_a, sin_a)
	v2 = _rotate_y(Vector3(-half_width, WALL_HEIGHT, half_thickness), cos_a, sin_a)
	v3 = _rotate_y(Vector3(-half_width, WALL_HEIGHT, -half_thickness), cos_a, sin_a)
	_add_quad(st, v0, v1, v2, v3)
	
	v0 = _rotate_y(Vector3(half_width, 0, half_thickness), cos_a, sin_a)
	v1 = _rotate_y(Vector3(half_width, 0, -half_thickness), cos_a, sin_a)
	v2 = _rotate_y(Vector3(half_width, WALL_HEIGHT, -half_thickness), cos_a, sin_a)
	v3 = _rotate_y(Vector3(half_width, WALL_HEIGHT, half_thickness), cos_a, sin_a)
	_add_quad(st, v0, v1, v2, v3)
	
	# Top face
	st.set_color(base_color.darkened(0.05))
	v0 = _rotate_y(Vector3(-half_width, WALL_HEIGHT, half_thickness), cos_a, sin_a)
	v1 = _rotate_y(Vector3(half_width, WALL_HEIGHT, half_thickness), cos_a, sin_a)
	v2 = _rotate_y(Vector3(half_width, WALL_HEIGHT, -half_thickness), cos_a, sin_a)
	v3 = _rotate_y(Vector3(-half_width, WALL_HEIGHT, -half_thickness), cos_a, sin_a)
	_add_quad(st, v0, v1, v2, v3)
	
	# Bottom face
	st.set_color(base_color.darkened(0.2))
	v0 = _rotate_y(Vector3(-half_width, 0, -half_thickness), cos_a, sin_a)
	v1 = _rotate_y(Vector3(half_width, 0, -half_thickness), cos_a, sin_a)
	v2 = _rotate_y(Vector3(half_width, 0, half_thickness), cos_a, sin_a)
	v3 = _rotate_y(Vector3(-half_width, 0, half_thickness), cos_a, sin_a)
	_add_quad(st, v0, v1, v2, v3)


static func _generate_angled_wall_simple(st: SurfaceTool, half_width: float, half_thickness: float, 
		base_color: Color, cos_a: float, sin_a: float) -> void:
	_generate_angled_wall_detailed(st, half_width, half_thickness, base_color, cos_a, sin_a)


# ============================================================================
# CORNER WALL GENERATION
# ============================================================================

static func generate_corner_wall(is_inner: bool, material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	
	var half_thickness := WALL_THICKNESS / 2.0
	var corner_size := WALL_THICKNESS * 2.0  # Size of corner piece
	
	if is_inner:
		_generate_inner_corner(st, corner_size, half_thickness, base_color)
	else:
		_generate_outer_corner(st, corner_size, half_thickness, base_color)
	
	st.generate_normals()
	return st.commit()


static func _generate_inner_corner(st: SurfaceTool, corner_size: float, half_thickness: float, base_color: Color) -> void:
	# Inner corner: L-shaped piece that fills the inside of a 90° corner
	var size := corner_size
	
	# Vertical post
	st.set_color(base_color)
	
	# Front face (Z+)
	_add_quad(st, Vector3(-half_thickness, 0, size), Vector3(size, 0, size),
			Vector3(size, WALL_HEIGHT, size), Vector3(-half_thickness, WALL_HEIGHT, size))
	
	# Right face (X+)
	_add_quad(st, Vector3(size, 0, size), Vector3(size, 0, -half_thickness),
			Vector3(size, WALL_HEIGHT, -half_thickness), Vector3(size, WALL_HEIGHT, size))
	
	# Inner faces
	st.set_color(base_color.darkened(0.1))
	_add_quad(st, Vector3(-half_thickness, 0, -half_thickness), Vector3(-half_thickness, 0, size),
			Vector3(-half_thickness, WALL_HEIGHT, size), Vector3(-half_thickness, WALL_HEIGHT, -half_thickness))
	
	_add_quad(st, Vector3(size, 0, -half_thickness), Vector3(-half_thickness, 0, -half_thickness),
			Vector3(-half_thickness, WALL_HEIGHT, -half_thickness), Vector3(size, WALL_HEIGHT, -half_thickness))
	
	# Top
	st.set_color(base_color.darkened(0.05))
	_add_quad(st, Vector3(-half_thickness, WALL_HEIGHT, -half_thickness), Vector3(-half_thickness, WALL_HEIGHT, size),
			Vector3(size, WALL_HEIGHT, size), Vector3(size, WALL_HEIGHT, -half_thickness))
	
	# Bottom
	st.set_color(base_color.darkened(0.2))
	_add_quad(st, Vector3(-half_thickness, 0, size), Vector3(-half_thickness, 0, -half_thickness),
			Vector3(size, 0, -half_thickness), Vector3(size, 0, size))


static func _generate_outer_corner(st: SurfaceTool, corner_size: float, half_thickness: float, base_color: Color) -> void:
	# Outer corner: Beveled corner piece for outside of 90° corner
	var size := corner_size
	
	st.set_color(base_color)
	
	# Front face (Z+)
	_add_quad(st, Vector3(-size, 0, half_thickness), Vector3(half_thickness, 0, half_thickness),
			Vector3(half_thickness, WALL_HEIGHT, half_thickness), Vector3(-size, WALL_HEIGHT, half_thickness))
	
	# Right face (X+)
	_add_quad(st, Vector3(half_thickness, 0, half_thickness), Vector3(half_thickness, 0, -size),
			Vector3(half_thickness, WALL_HEIGHT, -size), Vector3(half_thickness, WALL_HEIGHT, half_thickness))
	
	# Back faces
	st.set_color(base_color.darkened(0.1))
	_add_quad(st, Vector3(half_thickness, 0, -size), Vector3(-size, 0, -size),
			Vector3(-size, WALL_HEIGHT, -size), Vector3(half_thickness, WALL_HEIGHT, -size))
	
	_add_quad(st, Vector3(-size, 0, -size), Vector3(-size, 0, half_thickness),
			Vector3(-size, WALL_HEIGHT, half_thickness), Vector3(-size, WALL_HEIGHT, -size))
	
	# Diagonal bevel face
	st.set_color(base_color.darkened(0.05))
	_add_quad(st, Vector3(-size, 0, -size), Vector3(half_thickness, 0, -size),
			Vector3(half_thickness, WALL_HEIGHT, -size), Vector3(-size, WALL_HEIGHT, -size))
	
	# Top
	st.set_color(base_color.darkened(0.05))
	st.add_vertex(Vector3(-size, WALL_HEIGHT, half_thickness))
	st.add_vertex(Vector3(half_thickness, WALL_HEIGHT, half_thickness))
	st.add_vertex(Vector3(half_thickness, WALL_HEIGHT, -size))
	st.add_vertex(Vector3(-size, WALL_HEIGHT, half_thickness))
	st.add_vertex(Vector3(half_thickness, WALL_HEIGHT, -size))
	st.add_vertex(Vector3(-size, WALL_HEIGHT, -size))
	
	# Bottom
	st.set_color(base_color.darkened(0.2))
	st.add_vertex(Vector3(-size, 0, half_thickness))
	st.add_vertex(Vector3(-size, 0, -size))
	st.add_vertex(Vector3(half_thickness, 0, -size))
	st.add_vertex(Vector3(-size, 0, half_thickness))
	st.add_vertex(Vector3(half_thickness, 0, -size))
	st.add_vertex(Vector3(half_thickness, 0, half_thickness))


static func generate_angled_collision_shape(angle: float, dimensions: Vector3) -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	var half := dimensions / 2.0
	var angle_rad := deg_to_rad(angle)
	var cos_a := cos(angle_rad)
	var sin_a := sin(angle_rad)
	
	var points := PackedVector3Array([
		_rotate_y(Vector3(-half.x, 0, -half.z), cos_a, sin_a),
		_rotate_y(Vector3(half.x, 0, -half.z), cos_a, sin_a),
		_rotate_y(Vector3(half.x, 0, half.z), cos_a, sin_a),
		_rotate_y(Vector3(-half.x, 0, half.z), cos_a, sin_a),
		_rotate_y(Vector3(-half.x, half.y, -half.z), cos_a, sin_a),
		_rotate_y(Vector3(half.x, half.y, -half.z), cos_a, sin_a),
		_rotate_y(Vector3(half.x, half.y, half.z), cos_a, sin_a),
		_rotate_y(Vector3(-half.x, half.y, half.z), cos_a, sin_a),
	])
	shape.points = points
	return shape


static func generate_corner_collision_shape(is_inner: bool) -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	var half_thickness := WALL_THICKNESS / 2.0
	var corner_size := WALL_THICKNESS * 2.0
	
	var points: PackedVector3Array
	if is_inner:
		points = PackedVector3Array([
			Vector3(-half_thickness, 0, -half_thickness),
			Vector3(corner_size, 0, -half_thickness),
			Vector3(corner_size, 0, corner_size),
			Vector3(-half_thickness, 0, corner_size),
			Vector3(-half_thickness, WALL_HEIGHT, -half_thickness),
			Vector3(corner_size, WALL_HEIGHT, -half_thickness),
			Vector3(corner_size, WALL_HEIGHT, corner_size),
			Vector3(-half_thickness, WALL_HEIGHT, corner_size),
		])
	else:
		points = PackedVector3Array([
			Vector3(-corner_size, 0, -corner_size),
			Vector3(half_thickness, 0, -corner_size),
			Vector3(half_thickness, 0, half_thickness),
			Vector3(-corner_size, 0, half_thickness),
			Vector3(-corner_size, WALL_HEIGHT, -corner_size),
			Vector3(half_thickness, WALL_HEIGHT, -corner_size),
			Vector3(half_thickness, WALL_HEIGHT, half_thickness),
			Vector3(-corner_size, WALL_HEIGHT, half_thickness),
		])
	shape.points = points
	return shape
