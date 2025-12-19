class_name StairGenerator
extends RefCounted

const STEP_HEIGHT: float = 0.375
const STEP_DEPTH: float = 0.3
const STAIR_WIDTH: float = 1.2
const TOTAL_HEIGHT: float = 3.0

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

const FACTION_COLORS: Dictionary = {
	0: Color(0.85, 0.85, 0.9),
	1: Color(0.2, 0.15, 0.15),
	2: Color(0.35, 0.5, 0.3),
	3: Color(0.7, 0.68, 0.6),
	4: Color(0.5, 0.5, 0.6),
	5: Color(0.55, 0.45, 0.35),
	6: Color(0.4, 0.45, 0.4),
	7: Color(0.45, 0.5, 0.55),
}


static func generate_stairs(step_count: int, material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.8
	
	var half_width := STAIR_WIDTH / 2.0
	var step_height := TOTAL_HEIGHT / step_count
	var total_depth := step_count * STEP_DEPTH
	
	if lod_level <= 1:
		_generate_detailed_stairs(st, step_count, half_width, step_height, base_color, noise)
	else:
		_generate_simple_stairs(st, step_count, half_width, step_height, base_color)
	
	st.generate_normals()
	return st.commit()


static func generate_spiral_stairs(material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	
	var step_count := 12
	var radius := 1.0
	var inner_radius := 0.15
	var step_height := TOTAL_HEIGHT / step_count
	var angle_per_step := TAU / step_count
	
	for i in range(step_count):
		var angle0 := i * angle_per_step
		var angle1 := (i + 1) * angle_per_step
		var y := i * step_height
		
		var color := base_color
		if i % 2 == 0:
			color = color.darkened(0.05)
		
		st.set_color(color)
		
		var inner0 := Vector3(cos(angle0) * inner_radius, y + step_height, sin(angle0) * inner_radius)
		var inner1 := Vector3(cos(angle1) * inner_radius, y + step_height, sin(angle1) * inner_radius)
		var outer0 := Vector3(cos(angle0) * radius, y + step_height, sin(angle0) * radius)
		var outer1 := Vector3(cos(angle1) * radius, y + step_height, sin(angle1) * radius)
		
		# Top surface
		st.add_vertex(inner0)
		st.add_vertex(outer0)
		st.add_vertex(outer1)
		st.add_vertex(inner0)
		st.add_vertex(outer1)
		st.add_vertex(inner1)
		
		# Front face (riser)
		st.set_color(color.darkened(0.1))
		var inner0_bottom := Vector3(inner0.x, y, inner0.z)
		var outer0_bottom := Vector3(outer0.x, y, outer0.z)
		st.add_vertex(inner0_bottom)
		st.add_vertex(inner0)
		st.add_vertex(outer0)
		st.add_vertex(inner0_bottom)
		st.add_vertex(outer0)
		st.add_vertex(outer0_bottom)
	
	# Central pole
	st.set_color(base_color.darkened(0.2))
	var pole_segments := 8
	for i in range(pole_segments):
		var angle0 := (float(i) / pole_segments) * TAU
		var angle1 := (float(i + 1) / pole_segments) * TAU
		var x0 := cos(angle0) * inner_radius
		var z0 := sin(angle0) * inner_radius
		var x1 := cos(angle1) * inner_radius
		var z1 := sin(angle1) * inner_radius
		
		_add_quad(st, Vector3(x0, 0, z0), Vector3(x1, 0, z1),
				Vector3(x1, TOTAL_HEIGHT, z1), Vector3(x0, TOTAL_HEIGHT, z0))
	
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


static func _generate_detailed_stairs(st: SurfaceTool, step_count: int, half_width: float, 
		step_height: float, base_color: Color, noise: FastNoiseLite) -> void:
	
	for i in range(step_count):
		var y := i * step_height
		var z := i * STEP_DEPTH
		
		var color_var := noise.get_noise_2d(i * 10.0, 0) * 0.06
		var color := Color(
			clampf(base_color.r + color_var, 0.0, 1.0),
			clampf(base_color.g + color_var, 0.0, 1.0),
			clampf(base_color.b + color_var, 0.0, 1.0)
		)
		
		# Step top (tread)
		st.set_color(color)
		_add_quad(st, Vector3(-half_width, y + step_height, z), Vector3(half_width, y + step_height, z),
				Vector3(half_width, y + step_height, z + STEP_DEPTH), Vector3(-half_width, y + step_height, z + STEP_DEPTH))
		
		# Step front (riser)
		st.set_color(color.darkened(0.1))
		_add_quad(st, Vector3(-half_width, y, z), Vector3(-half_width, y + step_height, z),
				Vector3(half_width, y + step_height, z), Vector3(half_width, y, z))
	
	# Side panels
	var total_depth := step_count * STEP_DEPTH
	st.set_color(base_color.darkened(0.15))
	
	# Left side - stringer
	for i in range(step_count):
		var y := i * step_height
		var z := i * STEP_DEPTH
		
		# Vertical part
		_add_quad(st, Vector3(-half_width, y, z), Vector3(-half_width, y, z + STEP_DEPTH),
				Vector3(-half_width, y + step_height, z + STEP_DEPTH), Vector3(-half_width, y + step_height, z))
		# Horizontal part under step
		if i > 0:
			_add_quad(st, Vector3(-half_width, y, z - STEP_DEPTH), Vector3(-half_width, y, z),
					Vector3(-half_width, y, z), Vector3(-half_width, y, z - STEP_DEPTH))
	
	# Right side - stringer
	for i in range(step_count):
		var y := i * step_height
		var z := i * STEP_DEPTH
		
		_add_quad(st, Vector3(half_width, y, z + STEP_DEPTH), Vector3(half_width, y, z),
				Vector3(half_width, y + step_height, z), Vector3(half_width, y + step_height, z + STEP_DEPTH))


static func _generate_simple_stairs(st: SurfaceTool, step_count: int, half_width: float, 
		step_height: float, base_color: Color) -> void:
	
	var total_depth := step_count * STEP_DEPTH
	
	# Simplified as a ramp-like shape
	st.set_color(base_color)
	_add_quad(st, Vector3(-half_width, 0, 0), Vector3(half_width, 0, 0),
			Vector3(half_width, TOTAL_HEIGHT, total_depth), Vector3(-half_width, TOTAL_HEIGHT, total_depth))
	
	# Sides
	st.set_color(base_color.darkened(0.15))
	st.add_vertex(Vector3(-half_width, 0, 0))
	st.add_vertex(Vector3(-half_width, TOTAL_HEIGHT, total_depth))
	st.add_vertex(Vector3(-half_width, 0, total_depth))
	
	st.add_vertex(Vector3(half_width, 0, 0))
	st.add_vertex(Vector3(half_width, 0, total_depth))
	st.add_vertex(Vector3(half_width, TOTAL_HEIGHT, total_depth))


static func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)


static func generate_collision_shape(dimensions: Vector3) -> Shape3D:
	var shape := BoxShape3D.new()
	shape.size = dimensions
	return shape


# ============================================================================
# QUARTER-TURN STAIRS
# ============================================================================

static func generate_quarter_turn_stairs(material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	
	var steps_per_run := 4
	var step_height := TOTAL_HEIGHT / 8.0  # 8 steps total
	var half_width := STAIR_WIDTH / 2.0
	
	# First run (4 steps going +Z)
	for i in range(steps_per_run):
		var y := i * step_height
		var z := i * STEP_DEPTH
		
		var color := base_color if i % 2 == 0 else base_color.darkened(0.05)
		st.set_color(color)
		
		# Step top
		_add_quad(st, Vector3(-half_width, y + step_height, z), Vector3(half_width, y + step_height, z),
				Vector3(half_width, y + step_height, z + STEP_DEPTH), Vector3(-half_width, y + step_height, z + STEP_DEPTH))
		
		# Step front
		st.set_color(color.darkened(0.1))
		_add_quad(st, Vector3(-half_width, y, z), Vector3(-half_width, y + step_height, z),
				Vector3(half_width, y + step_height, z), Vector3(half_width, y, z))
	
	# Landing platform at turn
	var landing_y := steps_per_run * step_height
	var landing_z := steps_per_run * STEP_DEPTH
	st.set_color(base_color.darkened(0.02))
	_add_quad(st, Vector3(-half_width, landing_y, landing_z), Vector3(half_width + STEP_DEPTH, landing_y, landing_z),
			Vector3(half_width + STEP_DEPTH, landing_y, landing_z + STAIR_WIDTH), Vector3(-half_width, landing_y, landing_z + STAIR_WIDTH))
	
	# Second run (4 steps going +X, rotated 90°)
	for i in range(steps_per_run):
		var y := landing_y + i * step_height
		var x := half_width + i * STEP_DEPTH
		
		var color := base_color if i % 2 == 0 else base_color.darkened(0.05)
		st.set_color(color)
		
		# Step top
		_add_quad(st, Vector3(x, y + step_height, landing_z), Vector3(x + STEP_DEPTH, y + step_height, landing_z),
				Vector3(x + STEP_DEPTH, y + step_height, landing_z + STAIR_WIDTH), Vector3(x, y + step_height, landing_z + STAIR_WIDTH))
		
		# Step front
		st.set_color(color.darkened(0.1))
		_add_quad(st, Vector3(x, y, landing_z), Vector3(x, y + step_height, landing_z),
				Vector3(x, y + step_height, landing_z + STAIR_WIDTH), Vector3(x, y, landing_z + STAIR_WIDTH))
	
	st.generate_normals()
	return st.commit()


# ============================================================================
# HALF-LANDING STAIRS (180° turn)
# ============================================================================

static func generate_half_landing_stairs(material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	
	var steps_per_run := 6
	var step_height := TOTAL_HEIGHT / 12.0  # 12 steps total
	var half_width := STAIR_WIDTH / 2.0
	var run_depth := steps_per_run * STEP_DEPTH
	
	# First run (6 steps going +Z)
	for i in range(steps_per_run):
		var y := i * step_height
		var z := i * STEP_DEPTH
		
		var color := base_color if i % 2 == 0 else base_color.darkened(0.05)
		st.set_color(color)
		
		_add_quad(st, Vector3(-half_width, y + step_height, z), Vector3(half_width, y + step_height, z),
				Vector3(half_width, y + step_height, z + STEP_DEPTH), Vector3(-half_width, y + step_height, z + STEP_DEPTH))
		
		st.set_color(color.darkened(0.1))
		_add_quad(st, Vector3(-half_width, y, z), Vector3(-half_width, y + step_height, z),
				Vector3(half_width, y + step_height, z), Vector3(half_width, y, z))
	
	# Half-landing platform
	var landing_y := steps_per_run * step_height
	var landing_width := STAIR_WIDTH * 2.0
	st.set_color(base_color.darkened(0.02))
	_add_quad(st, Vector3(-half_width - STAIR_WIDTH, landing_y, run_depth), Vector3(half_width, landing_y, run_depth),
			Vector3(half_width, landing_y, run_depth + STAIR_WIDTH), Vector3(-half_width - STAIR_WIDTH, landing_y, run_depth + STAIR_WIDTH))
	
	# Second run (6 steps going -Z, offset to the left)
	var second_run_x := -half_width - STAIR_WIDTH
	for i in range(steps_per_run):
		var y := landing_y + i * step_height
		var z := run_depth + STAIR_WIDTH - i * STEP_DEPTH
		
		var color := base_color if i % 2 == 0 else base_color.darkened(0.05)
		st.set_color(color)
		
		_add_quad(st, Vector3(second_run_x, y + step_height, z), Vector3(second_run_x + STAIR_WIDTH, y + step_height, z),
				Vector3(second_run_x + STAIR_WIDTH, y + step_height, z - STEP_DEPTH), Vector3(second_run_x, y + step_height, z - STEP_DEPTH))
		
		st.set_color(color.darkened(0.1))
		_add_quad(st, Vector3(second_run_x, y, z), Vector3(second_run_x, y + step_height, z),
				Vector3(second_run_x + STAIR_WIDTH, y + step_height, z), Vector3(second_run_x + STAIR_WIDTH, y, z))
	
	st.generate_normals()
	return st.commit()


# ============================================================================
# RAMP GENERATION
# ============================================================================

static func generate_ramp(length: float, height: float, width: float, material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	var half_width := width / 2.0
	
	# Top surface (inclined plane)
	st.set_color(base_color)
	_add_quad(st, Vector3(-half_width, 0, 0), Vector3(half_width, 0, 0),
			Vector3(half_width, height, length), Vector3(-half_width, height, length))
	
	# Bottom surface
	st.set_color(base_color.darkened(0.2))
	_add_quad(st, Vector3(-half_width, 0, length), Vector3(half_width, 0, length),
			Vector3(half_width, 0, 0), Vector3(-half_width, 0, 0))
	
	# Left side
	st.set_color(base_color.darkened(0.1))
	st.add_vertex(Vector3(-half_width, 0, 0))
	st.add_vertex(Vector3(-half_width, height, length))
	st.add_vertex(Vector3(-half_width, 0, length))
	
	# Right side
	st.add_vertex(Vector3(half_width, 0, 0))
	st.add_vertex(Vector3(half_width, 0, length))
	st.add_vertex(Vector3(half_width, height, length))
	
	# Front face (at top)
	st.set_color(base_color.darkened(0.05))
	_add_quad(st, Vector3(-half_width, 0, length), Vector3(-half_width, height, length),
			Vector3(half_width, height, length), Vector3(half_width, 0, length))
	
	st.generate_normals()
	return st.commit()


static func generate_ramp_collision_shape(length: float, height: float, width: float) -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	var half_width := width / 2.0
	
	shape.points = PackedVector3Array([
		Vector3(-half_width, 0, 0),
		Vector3(half_width, 0, 0),
		Vector3(half_width, 0, length),
		Vector3(-half_width, 0, length),
		Vector3(-half_width, height, length),
		Vector3(half_width, height, length),
	])
	return shape


static func generate_quarter_turn_collision_shape() -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	var half_width := STAIR_WIDTH / 2.0
	var steps_per_run := 4
	var landing_z := steps_per_run * STEP_DEPTH
	var landing_y := TOTAL_HEIGHT / 2.0
	
	shape.points = PackedVector3Array([
		Vector3(-half_width, 0, 0),
		Vector3(half_width, 0, 0),
		Vector3(half_width, landing_y, landing_z),
		Vector3(-half_width, landing_y, landing_z),
		Vector3(half_width + steps_per_run * STEP_DEPTH, TOTAL_HEIGHT, landing_z),
		Vector3(half_width + steps_per_run * STEP_DEPTH, TOTAL_HEIGHT, landing_z + STAIR_WIDTH),
		Vector3(-half_width, landing_y, landing_z + STAIR_WIDTH),
	])
	return shape


static func generate_half_landing_collision_shape() -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	var half_width := STAIR_WIDTH / 2.0
	var steps_per_run := 6
	var run_depth := steps_per_run * STEP_DEPTH
	var landing_y := TOTAL_HEIGHT / 2.0
	
	shape.points = PackedVector3Array([
		Vector3(-half_width, 0, 0),
		Vector3(half_width, 0, 0),
		Vector3(half_width, landing_y, run_depth),
		Vector3(-half_width - STAIR_WIDTH, landing_y, run_depth),
		Vector3(-half_width - STAIR_WIDTH, TOTAL_HEIGHT, 0),
		Vector3(-half_width, TOTAL_HEIGHT, 0),
	])
	return shape
