class_name FoundationGenerator
extends RefCounted

const FOUNDATION_HEIGHT: float = 0.5
const BEVEL_SIZE: float = 0.1

const WOOD_COLORS: Array[Color] = [
	Color(0.45, 0.3, 0.18),
	Color(0.5, 0.33, 0.2),
	Color(0.4, 0.27, 0.15)
]

const STONE_COLORS: Array[Color] = [
	Color(0.5, 0.48, 0.45),
	Color(0.55, 0.52, 0.48),
	Color(0.45, 0.45, 0.42)
]


static func generate_foundation(size: Vector2, material_type: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, rng)
	
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.5
	
	var half_x := size.x / 2.0
	var half_z := size.y / 2.0
	
	if lod_level <= 1:
		_generate_detailed_foundation(st, half_x, half_z, base_color, noise, material_type)
	else:
		_generate_simple_foundation(st, half_x, half_z, base_color)
	
	st.generate_normals()
	return st.commit()


static func _get_base_color(material_type: int, rng: RandomNumberGenerator) -> Color:
	match material_type:
		BuildPieceData.MaterialType.WOOD:
			return WOOD_COLORS[rng.randi() % WOOD_COLORS.size()]
		BuildPieceData.MaterialType.STONE:
			return STONE_COLORS[rng.randi() % STONE_COLORS.size()]
		BuildPieceData.MaterialType.METAL:
			return Color(0.4, 0.4, 0.45)
		_:
			return Color(0.5, 0.5, 0.5)


static func _generate_detailed_foundation(st: SurfaceTool, half_x: float, half_z: float, 
		base_color: Color, noise: FastNoiseLite, material_type: int) -> void:
	
	var inner_x := half_x - BEVEL_SIZE
	var inner_z := half_z - BEVEL_SIZE
	var bevel_height := FOUNDATION_HEIGHT - BEVEL_SIZE
	
	# Top surface with texture variation
	var segments := 4
	var seg_x := (inner_x * 2) / segments
	var seg_z := (inner_z * 2) / segments
	
	for ix in range(segments):
		for iz in range(segments):
			var x0 := -inner_x + ix * seg_x
			var x1 := x0 + seg_x
			var z0 := -inner_z + iz * seg_z
			var z1 := z0 + seg_z
			
			var color_var := noise.get_noise_2d(ix * 15.0, iz * 15.0) * 0.06
			var color := Color(
				clampf(base_color.r + color_var, 0.0, 1.0),
				clampf(base_color.g + color_var, 0.0, 1.0),
				clampf(base_color.b + color_var, 0.0, 1.0)
			)
			
			st.set_color(color)
			_add_quad(st, Vector3(x0, FOUNDATION_HEIGHT, z0), Vector3(x1, FOUNDATION_HEIGHT, z0),
					Vector3(x1, FOUNDATION_HEIGHT, z1), Vector3(x0, FOUNDATION_HEIGHT, z1))
	
	# Beveled edges - top
	st.set_color(base_color.darkened(0.05))
	# Front bevel
	_add_quad(st, Vector3(-inner_x, FOUNDATION_HEIGHT, -inner_z), Vector3(inner_x, FOUNDATION_HEIGHT, -inner_z),
			Vector3(half_x, bevel_height, -half_z), Vector3(-half_x, bevel_height, -half_z))
	# Back bevel
	_add_quad(st, Vector3(inner_x, FOUNDATION_HEIGHT, inner_z), Vector3(-inner_x, FOUNDATION_HEIGHT, inner_z),
			Vector3(-half_x, bevel_height, half_z), Vector3(half_x, bevel_height, half_z))
	# Left bevel
	_add_quad(st, Vector3(-inner_x, FOUNDATION_HEIGHT, inner_z), Vector3(-inner_x, FOUNDATION_HEIGHT, -inner_z),
			Vector3(-half_x, bevel_height, -half_z), Vector3(-half_x, bevel_height, half_z))
	# Right bevel
	_add_quad(st, Vector3(inner_x, FOUNDATION_HEIGHT, -inner_z), Vector3(inner_x, FOUNDATION_HEIGHT, inner_z),
			Vector3(half_x, bevel_height, half_z), Vector3(half_x, bevel_height, -half_z))
	
	# Corner bevels
	st.set_color(base_color.darkened(0.08))
	# Front-left corner
	st.add_vertex(Vector3(-inner_x, FOUNDATION_HEIGHT, -inner_z))
	st.add_vertex(Vector3(-half_x, bevel_height, -half_z))
	st.add_vertex(Vector3(-half_x, bevel_height, -inner_z))
	st.add_vertex(Vector3(-inner_x, FOUNDATION_HEIGHT, -inner_z))
	st.add_vertex(Vector3(-inner_x, bevel_height, -half_z))
	st.add_vertex(Vector3(-half_x, bevel_height, -half_z))
	# Front-right corner
	st.add_vertex(Vector3(inner_x, FOUNDATION_HEIGHT, -inner_z))
	st.add_vertex(Vector3(half_x, bevel_height, -inner_z))
	st.add_vertex(Vector3(half_x, bevel_height, -half_z))
	st.add_vertex(Vector3(inner_x, FOUNDATION_HEIGHT, -inner_z))
	st.add_vertex(Vector3(half_x, bevel_height, -half_z))
	st.add_vertex(Vector3(inner_x, bevel_height, -half_z))
	# Back-left corner
	st.add_vertex(Vector3(-inner_x, FOUNDATION_HEIGHT, inner_z))
	st.add_vertex(Vector3(-half_x, bevel_height, inner_z))
	st.add_vertex(Vector3(-half_x, bevel_height, half_z))
	st.add_vertex(Vector3(-inner_x, FOUNDATION_HEIGHT, inner_z))
	st.add_vertex(Vector3(-half_x, bevel_height, half_z))
	st.add_vertex(Vector3(-inner_x, bevel_height, half_z))
	# Back-right corner
	st.add_vertex(Vector3(inner_x, FOUNDATION_HEIGHT, inner_z))
	st.add_vertex(Vector3(half_x, bevel_height, half_z))
	st.add_vertex(Vector3(half_x, bevel_height, inner_z))
	st.add_vertex(Vector3(inner_x, FOUNDATION_HEIGHT, inner_z))
	st.add_vertex(Vector3(inner_x, bevel_height, half_z))
	st.add_vertex(Vector3(half_x, bevel_height, half_z))
	
	# Side faces
	st.set_color(base_color.darkened(0.15))
	# Front
	_add_quad(st, Vector3(-half_x, 0, -half_z), Vector3(-half_x, bevel_height, -half_z),
			Vector3(half_x, bevel_height, -half_z), Vector3(half_x, 0, -half_z))
	# Back
	_add_quad(st, Vector3(half_x, 0, half_z), Vector3(half_x, bevel_height, half_z),
			Vector3(-half_x, bevel_height, half_z), Vector3(-half_x, 0, half_z))
	# Left
	_add_quad(st, Vector3(-half_x, 0, half_z), Vector3(-half_x, bevel_height, half_z),
			Vector3(-half_x, bevel_height, -half_z), Vector3(-half_x, 0, -half_z))
	# Right
	_add_quad(st, Vector3(half_x, 0, -half_z), Vector3(half_x, bevel_height, -half_z),
			Vector3(half_x, bevel_height, half_z), Vector3(half_x, 0, half_z))
	
	# Bottom
	st.set_color(base_color.darkened(0.3))
	_add_quad(st, Vector3(-half_x, 0, half_z), Vector3(-half_x, 0, -half_z),
			Vector3(half_x, 0, -half_z), Vector3(half_x, 0, half_z))


static func _generate_simple_foundation(st: SurfaceTool, half_x: float, half_z: float, base_color: Color) -> void:
	st.set_color(base_color)
	# Top
	_add_quad(st, Vector3(-half_x, FOUNDATION_HEIGHT, -half_z), Vector3(half_x, FOUNDATION_HEIGHT, -half_z),
			Vector3(half_x, FOUNDATION_HEIGHT, half_z), Vector3(-half_x, FOUNDATION_HEIGHT, half_z))
	# Bottom
	st.set_color(base_color.darkened(0.3))
	_add_quad(st, Vector3(-half_x, 0, half_z), Vector3(-half_x, 0, -half_z),
			Vector3(half_x, 0, -half_z), Vector3(half_x, 0, half_z))
	# Sides
	st.set_color(base_color.darkened(0.15))
	_add_quad(st, Vector3(-half_x, 0, -half_z), Vector3(-half_x, FOUNDATION_HEIGHT, -half_z),
			Vector3(half_x, FOUNDATION_HEIGHT, -half_z), Vector3(half_x, 0, -half_z))
	_add_quad(st, Vector3(half_x, 0, half_z), Vector3(half_x, FOUNDATION_HEIGHT, half_z),
			Vector3(-half_x, FOUNDATION_HEIGHT, half_z), Vector3(-half_x, 0, half_z))
	_add_quad(st, Vector3(-half_x, 0, half_z), Vector3(-half_x, FOUNDATION_HEIGHT, half_z),
			Vector3(-half_x, FOUNDATION_HEIGHT, -half_z), Vector3(-half_x, 0, -half_z))
	_add_quad(st, Vector3(half_x, 0, -half_z), Vector3(half_x, FOUNDATION_HEIGHT, -half_z),
			Vector3(half_x, FOUNDATION_HEIGHT, half_z), Vector3(half_x, 0, half_z))


static func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)


static func generate_collision_shape(size: Vector2, height: float) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, height, size.y)
	return shape
