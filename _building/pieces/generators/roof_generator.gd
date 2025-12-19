class_name RoofGenerator
extends RefCounted

const ROOF_SLOPE: float = 0.5
const ROOF_OVERHANG: float = 0.5
const ROOF_THICKNESS: float = 0.15

enum RoofType {
	FLAT,
	GABLED,
	HIPPED,
	CONICAL
}

enum RoofSlope {
	FLAT,      # 0°
	SHALLOW,   # 15°
	MEDIUM,    # 30°
	STEEP      # 45°
}

const SLOPE_ANGLES: Dictionary = {
	RoofSlope.FLAT: 0.0,
	RoofSlope.SHALLOW: 0.27,   # tan(15°) ≈ 0.27
	RoofSlope.MEDIUM: 0.58,    # tan(30°) ≈ 0.58
	RoofSlope.STEEP: 1.0       # tan(45°) = 1.0
}

const WOOD_COLORS: Array[Color] = [
	Color(0.35, 0.22, 0.12),
	Color(0.4, 0.25, 0.14),
	Color(0.3, 0.2, 0.1)
]

const STONE_COLORS: Array[Color] = [
	Color(0.4, 0.4, 0.45),
	Color(0.45, 0.43, 0.48),
	Color(0.38, 0.38, 0.42)
]

const THATCH_COLOR: Color = Color(0.6, 0.5, 0.3)

const FACTION_COLORS: Dictionary = {
	0: Color(0.7, 0.2, 0.2),    # Castle - red tiles
	1: Color(0.15, 0.1, 0.1),   # Inferno - black obsidian
	2: Color(0.25, 0.4, 0.2),   # Rampart - living thatch
	3: Color(0.3, 0.3, 0.35),   # Necropolis - dark slate
	4: Color(0.4, 0.45, 0.6),   # Tower - blue tiles
	5: Color(0.5, 0.4, 0.3),    # Stronghold - hide/leather
	6: Color(0.35, 0.4, 0.35),  # Fortress - swamp reed
	7: Color(0.5, 0.55, 0.6),   # Conflux - crystal
}


static func generate_roof(roof_type: int, material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 1.0
	
	match roof_type:
		RoofType.FLAT:
			_generate_flat_roof(st, base_color, noise, lod_level)
		RoofType.GABLED:
			_generate_gabled_roof(st, base_color, noise, lod_level, material_type)
		RoofType.HIPPED:
			_generate_hipped_roof(st, base_color, noise, lod_level)
		RoofType.CONICAL:
			_generate_conical_roof(st, base_color, noise, lod_level)
	
	st.generate_normals()
	return st.commit()


static func _get_base_color(material_type: int, faction_id: int, rng: RandomNumberGenerator) -> Color:
	match material_type:
		BuildPieceData.MaterialType.WOOD:
			if rng.randf() < 0.3:  # Thatch variant for tier 0
				return THATCH_COLOR
			return WOOD_COLORS[rng.randi() % WOOD_COLORS.size()]
		BuildPieceData.MaterialType.STONE:
			return STONE_COLORS[rng.randi() % STONE_COLORS.size()]
		BuildPieceData.MaterialType.METAL:
			return Color(0.5, 0.5, 0.55)
		BuildPieceData.MaterialType.FACTION_SPECIFIC:
			if FACTION_COLORS.has(faction_id):
				return FACTION_COLORS[faction_id]
			return Color(0.5, 0.5, 0.5)
	return Color(0.5, 0.5, 0.5)


static func _generate_flat_roof(st: SurfaceTool, base_color: Color, noise: FastNoiseLite, lod_level: int) -> void:
	var half_size := 2.0 + ROOF_OVERHANG
	var slope := 0.02  # 2% drainage slope
	
	if lod_level <= 1:
		var segments := 4
		var seg_size := (half_size * 2) / segments
		
		for ix in range(segments):
			for iz in range(segments):
				var x0 := -half_size + ix * seg_size
				var x1 := x0 + seg_size
				var z0 := -half_size + iz * seg_size
				var z1 := z0 + seg_size
				
				var h0 := ROOF_THICKNESS + (z0 + half_size) * slope
				var h1 := ROOF_THICKNESS + (z1 + half_size) * slope
				
				var color_var := noise.get_noise_2d(ix * 20.0, iz * 20.0) * 0.06
				var color := Color(
					clampf(base_color.r + color_var, 0.0, 1.0),
					clampf(base_color.g + color_var, 0.0, 1.0),
					clampf(base_color.b + color_var, 0.0, 1.0)
				)
				
				st.set_color(color)
				_add_quad(st, Vector3(x0, h0, z0), Vector3(x1, h0, z0), Vector3(x1, h1, z1), Vector3(x0, h1, z1))
		
		# Bottom
		st.set_color(base_color.darkened(0.3))
		_add_quad(st, Vector3(-half_size, 0, half_size), Vector3(half_size, 0, half_size),
				Vector3(half_size, 0, -half_size), Vector3(-half_size, 0, -half_size))
		
		# Edges
		st.set_color(base_color.darkened(0.15))
		var h_front := ROOF_THICKNESS
		var h_back := ROOF_THICKNESS + (half_size * 2) * slope
		_add_quad(st, Vector3(-half_size, 0, -half_size), Vector3(-half_size, h_front, -half_size),
				Vector3(half_size, h_front, -half_size), Vector3(half_size, 0, -half_size))
		_add_quad(st, Vector3(half_size, 0, half_size), Vector3(half_size, h_back, half_size),
				Vector3(-half_size, h_back, half_size), Vector3(-half_size, 0, half_size))
		_add_quad(st, Vector3(-half_size, 0, half_size), Vector3(-half_size, h_back, half_size),
				Vector3(-half_size, h_front, -half_size), Vector3(-half_size, 0, -half_size))
		_add_quad(st, Vector3(half_size, 0, -half_size), Vector3(half_size, h_front, -half_size),
				Vector3(half_size, h_back, half_size), Vector3(half_size, 0, half_size))
	else:
		st.set_color(base_color)
		_add_quad(st, Vector3(-half_size, ROOF_THICKNESS, -half_size), Vector3(half_size, ROOF_THICKNESS, -half_size),
				Vector3(half_size, ROOF_THICKNESS, half_size), Vector3(-half_size, ROOF_THICKNESS, half_size))


static func _generate_gabled_roof(st: SurfaceTool, base_color: Color, noise: FastNoiseLite, 
		lod_level: int, material_type: int) -> void:
	var half_width := 2.0 + ROOF_OVERHANG
	var half_depth := 2.0 + ROOF_OVERHANG
	var ridge_height := half_width * ROOF_SLOPE + ROOF_THICKNESS
	
	if lod_level <= 1:
		var segments := 6
		var seg_width := (half_width * 2) / segments
		
		# Left slope
		for i in range(segments):
			var x0 := -half_width + i * seg_width
			var x1 := x0 + seg_width
			var y0 := absf(x0) * ROOF_SLOPE + ROOF_THICKNESS
			var y1 := absf(x1) * ROOF_SLOPE + ROOF_THICKNESS
			if x1 > 0:
				y1 = (half_width - x1) * ROOF_SLOPE + ROOF_THICKNESS if x1 < half_width else ROOF_THICKNESS
			if x0 < 0:
				y0 = (half_width + x0) * ROOF_SLOPE + ROOF_THICKNESS if x0 > -half_width else ROOF_THICKNESS
			
			var color_var := noise.get_noise_2d(i * 15.0, 0) * 0.08
			var color := Color(
				clampf(base_color.r + color_var, 0.0, 1.0),
				clampf(base_color.g + color_var, 0.0, 1.0),
				clampf(base_color.b + color_var, 0.0, 1.0)
			)
			
			# Shingle pattern for wood
			if material_type == BuildPieceData.MaterialType.WOOD and i % 2 == 0:
				color = color.darkened(0.05)
			
			st.set_color(color)
			
			if x0 < 0 and x1 <= 0:
				# Left side of roof
				_add_quad(st, Vector3(x0, y0, -half_depth), Vector3(x1, y1, -half_depth),
						Vector3(x1, y1, half_depth), Vector3(x0, y0, half_depth))
			elif x0 >= 0 and x1 > 0:
				# Right side of roof
				_add_quad(st, Vector3(x0, y0, -half_depth), Vector3(x1, y1, -half_depth),
						Vector3(x1, y1, half_depth), Vector3(x0, y0, half_depth))
			elif x0 < 0 and x1 > 0:
				# Ridge crossing
				_add_quad(st, Vector3(x0, y0, -half_depth), Vector3(0, ridge_height, -half_depth),
						Vector3(0, ridge_height, half_depth), Vector3(x0, y0, half_depth))
				_add_quad(st, Vector3(0, ridge_height, -half_depth), Vector3(x1, y1, -half_depth),
						Vector3(x1, y1, half_depth), Vector3(0, ridge_height, half_depth))
		
		# Gable ends (triangles)
		st.set_color(base_color.darkened(0.1))
		# Front gable
		st.add_vertex(Vector3(-half_width, ROOF_THICKNESS, -half_depth))
		st.add_vertex(Vector3(0, ridge_height, -half_depth))
		st.add_vertex(Vector3(half_width, ROOF_THICKNESS, -half_depth))
		# Back gable
		st.add_vertex(Vector3(half_width, ROOF_THICKNESS, half_depth))
		st.add_vertex(Vector3(0, ridge_height, half_depth))
		st.add_vertex(Vector3(-half_width, ROOF_THICKNESS, half_depth))
	else:
		# Simple LOD
		st.set_color(base_color)
		# Left slope
		_add_quad(st, Vector3(-half_width, ROOF_THICKNESS, -half_depth), Vector3(0, ridge_height, -half_depth),
				Vector3(0, ridge_height, half_depth), Vector3(-half_width, ROOF_THICKNESS, half_depth))
		# Right slope
		_add_quad(st, Vector3(0, ridge_height, -half_depth), Vector3(half_width, ROOF_THICKNESS, -half_depth),
				Vector3(half_width, ROOF_THICKNESS, half_depth), Vector3(0, ridge_height, half_depth))
		# Gables
		st.set_color(base_color.darkened(0.1))
		st.add_vertex(Vector3(-half_width, ROOF_THICKNESS, -half_depth))
		st.add_vertex(Vector3(0, ridge_height, -half_depth))
		st.add_vertex(Vector3(half_width, ROOF_THICKNESS, -half_depth))
		st.add_vertex(Vector3(half_width, ROOF_THICKNESS, half_depth))
		st.add_vertex(Vector3(0, ridge_height, half_depth))
		st.add_vertex(Vector3(-half_width, ROOF_THICKNESS, half_depth))


static func _generate_hipped_roof(st: SurfaceTool, base_color: Color, noise: FastNoiseLite, lod_level: int) -> void:
	var half_size := 2.0 + ROOF_OVERHANG
	var peak_height := half_size * ROOF_SLOPE + ROOF_THICKNESS
	
	st.set_color(base_color)
	
	# Four triangular faces meeting at center peak
	# Front
	st.add_vertex(Vector3(-half_size, ROOF_THICKNESS, -half_size))
	st.add_vertex(Vector3(0, peak_height, 0))
	st.add_vertex(Vector3(half_size, ROOF_THICKNESS, -half_size))
	
	# Right
	st.set_color(base_color.darkened(0.05))
	st.add_vertex(Vector3(half_size, ROOF_THICKNESS, -half_size))
	st.add_vertex(Vector3(0, peak_height, 0))
	st.add_vertex(Vector3(half_size, ROOF_THICKNESS, half_size))
	
	# Back
	st.set_color(base_color.darkened(0.1))
	st.add_vertex(Vector3(half_size, ROOF_THICKNESS, half_size))
	st.add_vertex(Vector3(0, peak_height, 0))
	st.add_vertex(Vector3(-half_size, ROOF_THICKNESS, half_size))
	
	# Left
	st.set_color(base_color.darkened(0.15))
	st.add_vertex(Vector3(-half_size, ROOF_THICKNESS, half_size))
	st.add_vertex(Vector3(0, peak_height, 0))
	st.add_vertex(Vector3(-half_size, ROOF_THICKNESS, -half_size))


static func _generate_conical_roof(st: SurfaceTool, base_color: Color, noise: FastNoiseLite, lod_level: int) -> void:
	var radius := 2.0 + ROOF_OVERHANG
	var height := radius * ROOF_SLOPE * 1.5 + ROOF_THICKNESS
	var segments := 12 if lod_level <= 1 else 6
	
	var apex := Vector3(0, height, 0)
	
	for i in range(segments):
		var angle0 := (float(i) / segments) * TAU
		var angle1 := (float(i + 1) / segments) * TAU
		
		var x0 := cos(angle0) * radius
		var z0 := sin(angle0) * radius
		var x1 := cos(angle1) * radius
		var z1 := sin(angle1) * radius
		
		var color_var := noise.get_noise_2d(i * 20.0, 0) * 0.08
		var color := Color(
			clampf(base_color.r + color_var, 0.0, 1.0),
			clampf(base_color.g + color_var, 0.0, 1.0),
			clampf(base_color.b + color_var, 0.0, 1.0)
		)
		
		st.set_color(color)
		st.add_vertex(Vector3(x0, ROOF_THICKNESS, z0))
		st.add_vertex(apex)
		st.add_vertex(Vector3(x1, ROOF_THICKNESS, z1))


static func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)


static func generate_collision_shape(roof_type: int) -> Shape3D:
	match roof_type:
		RoofType.FLAT:
			var shape := BoxShape3D.new()
			shape.size = Vector3(4.0 + ROOF_OVERHANG * 2, ROOF_THICKNESS, 4.0 + ROOF_OVERHANG * 2)
			return shape
		RoofType.CONICAL:
			var shape := CylinderShape3D.new()
			shape.radius = 2.0 + ROOF_OVERHANG
			shape.height = (2.0 + ROOF_OVERHANG) * ROOF_SLOPE * 1.5
			return shape
		_:
			var shape := ConvexPolygonShape3D.new()
			var half_size := 2.0 + ROOF_OVERHANG
			var peak := half_size * ROOF_SLOPE + ROOF_THICKNESS
			shape.points = PackedVector3Array([
				Vector3(-half_size, 0, -half_size),
				Vector3(half_size, 0, -half_size),
				Vector3(half_size, 0, half_size),
				Vector3(-half_size, 0, half_size),
				Vector3(0, peak, 0)
			])
			return shape


# ============================================================================
# SLOPED ROOF GENERATION
# ============================================================================

static func generate_sloped_roof(roof_type: int, slope: int, material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	var slope_factor: float = SLOPE_ANGLES.get(slope, ROOF_SLOPE)
	
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 1.0
	
	match roof_type:
		RoofType.GABLED:
			_generate_sloped_gabled_roof(st, base_color, noise, lod_level, material_type, slope_factor)
		RoofType.HIPPED:
			_generate_sloped_hipped_roof(st, base_color, noise, lod_level, slope_factor)
		_:
			_generate_gabled_roof(st, base_color, noise, lod_level, material_type)
	
	st.generate_normals()
	return st.commit()


static func _generate_sloped_gabled_roof(st: SurfaceTool, base_color: Color, noise: FastNoiseLite, 
		lod_level: int, material_type: int, slope_factor: float) -> void:
	var half_width := 2.0 + ROOF_OVERHANG
	var half_depth := 2.0 + ROOF_OVERHANG
	var ridge_height := half_width * slope_factor + ROOF_THICKNESS
	
	st.set_color(base_color)
	# Left slope
	_add_quad(st, Vector3(-half_width, ROOF_THICKNESS, -half_depth), Vector3(0, ridge_height, -half_depth),
			Vector3(0, ridge_height, half_depth), Vector3(-half_width, ROOF_THICKNESS, half_depth))
	# Right slope
	_add_quad(st, Vector3(0, ridge_height, -half_depth), Vector3(half_width, ROOF_THICKNESS, -half_depth),
			Vector3(half_width, ROOF_THICKNESS, half_depth), Vector3(0, ridge_height, half_depth))
	# Gables
	st.set_color(base_color.darkened(0.1))
	st.add_vertex(Vector3(-half_width, ROOF_THICKNESS, -half_depth))
	st.add_vertex(Vector3(0, ridge_height, -half_depth))
	st.add_vertex(Vector3(half_width, ROOF_THICKNESS, -half_depth))
	st.add_vertex(Vector3(half_width, ROOF_THICKNESS, half_depth))
	st.add_vertex(Vector3(0, ridge_height, half_depth))
	st.add_vertex(Vector3(-half_width, ROOF_THICKNESS, half_depth))


static func _generate_sloped_hipped_roof(st: SurfaceTool, base_color: Color, noise: FastNoiseLite, 
		lod_level: int, slope_factor: float) -> void:
	var half_size := 2.0 + ROOF_OVERHANG
	var peak_height := half_size * slope_factor + ROOF_THICKNESS
	
	st.set_color(base_color)
	
	# Four triangular faces meeting at center peak
	# Front
	st.add_vertex(Vector3(-half_size, ROOF_THICKNESS, -half_size))
	st.add_vertex(Vector3(0, peak_height, 0))
	st.add_vertex(Vector3(half_size, ROOF_THICKNESS, -half_size))
	
	# Right
	st.set_color(base_color.darkened(0.05))
	st.add_vertex(Vector3(half_size, ROOF_THICKNESS, -half_size))
	st.add_vertex(Vector3(0, peak_height, 0))
	st.add_vertex(Vector3(half_size, ROOF_THICKNESS, half_size))
	
	# Back
	st.set_color(base_color.darkened(0.1))
	st.add_vertex(Vector3(half_size, ROOF_THICKNESS, half_size))
	st.add_vertex(Vector3(0, peak_height, 0))
	st.add_vertex(Vector3(-half_size, ROOF_THICKNESS, half_size))
	
	# Left
	st.set_color(base_color.darkened(0.15))
	st.add_vertex(Vector3(-half_size, ROOF_THICKNESS, half_size))
	st.add_vertex(Vector3(0, peak_height, 0))
	st.add_vertex(Vector3(-half_size, ROOF_THICKNESS, -half_size))


static func generate_sloped_collision_shape(roof_type: int, slope: int) -> Shape3D:
	var slope_factor: float = SLOPE_ANGLES.get(slope, ROOF_SLOPE)
	var half_size := 2.0 + ROOF_OVERHANG
	var peak := half_size * slope_factor + ROOF_THICKNESS
	
	var shape := ConvexPolygonShape3D.new()
	match roof_type:
		RoofType.GABLED:
			shape.points = PackedVector3Array([
				Vector3(-half_size, 0, -half_size),
				Vector3(half_size, 0, -half_size),
				Vector3(half_size, 0, half_size),
				Vector3(-half_size, 0, half_size),
				Vector3(0, peak, -half_size),
				Vector3(0, peak, half_size)
			])
		_:
			shape.points = PackedVector3Array([
				Vector3(-half_size, 0, -half_size),
				Vector3(half_size, 0, -half_size),
				Vector3(half_size, 0, half_size),
				Vector3(-half_size, 0, half_size),
				Vector3(0, peak, 0)
			])
	return shape
