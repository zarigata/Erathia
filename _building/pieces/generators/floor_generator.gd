class_name FloorGenerator
extends RefCounted

const FLOOR_THICKNESS: float = 0.2
const FLOOR_SIZE: float = 4.0

const WOOD_COLORS: Array[Color] = [
	Color(0.45, 0.3, 0.18),
	Color(0.5, 0.33, 0.2),
	Color(0.4, 0.27, 0.15)
]

const STONE_COLORS: Array[Color] = [
	Color(0.55, 0.53, 0.5),
	Color(0.5, 0.5, 0.52),
	Color(0.48, 0.48, 0.5)
]

const FACTION_COLORS: Dictionary = {
	0: Color(0.85, 0.85, 0.9),   # Castle - polished marble
	1: Color(0.2, 0.15, 0.15),   # Inferno - dark volcanic
	2: Color(0.35, 0.5, 0.3),    # Rampart - mossy stone
	3: Color(0.7, 0.68, 0.6),    # Necropolis - bone tiles
	4: Color(0.5, 0.5, 0.6),     # Tower - runic stone
	5: Color(0.55, 0.45, 0.35),  # Stronghold - packed earth
	6: Color(0.4, 0.45, 0.4),    # Fortress - swamp wood
	7: Color(0.45, 0.5, 0.55),   # Conflux - crystal
}


static func generate_floor(material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.8
	
	var half_size := FLOOR_SIZE / 2.0
	
	if lod_level <= 1:
		_generate_detailed_floor(st, half_size, base_color, noise, rng, material_type, faction_id)
	else:
		_generate_simple_floor(st, half_size, base_color)
	
	st.generate_normals()
	return st.commit()


static func _get_base_color(material_type: int, faction_id: int, rng: RandomNumberGenerator) -> Color:
	match material_type:
		BuildPieceData.MaterialType.WOOD:
			return WOOD_COLORS[rng.randi() % WOOD_COLORS.size()]
		BuildPieceData.MaterialType.STONE:
			return STONE_COLORS[rng.randi() % STONE_COLORS.size()]
		BuildPieceData.MaterialType.METAL:
			return Color(0.45, 0.45, 0.5)
		BuildPieceData.MaterialType.FACTION_SPECIFIC:
			if FACTION_COLORS.has(faction_id):
				return FACTION_COLORS[faction_id]
			return Color(0.5, 0.5, 0.5)
	return Color(0.5, 0.5, 0.5)


static func _generate_detailed_floor(st: SurfaceTool, half_size: float, base_color: Color, 
		noise: FastNoiseLite, rng: RandomNumberGenerator, material_type: int, faction_id: int) -> void:
	
	var segments := 8
	var seg_size := FLOOR_SIZE / segments
	var height_var := 0.05
	
	# Top face with detail
	for ix in range(segments):
		for iz in range(segments):
			var x0 := -half_size + ix * seg_size
			var x1 := x0 + seg_size
			var z0 := -half_size + iz * seg_size
			var z1 := z0 + seg_size
			
			var h00 := noise.get_noise_2d(x0 * 5, z0 * 5) * height_var
			var h10 := noise.get_noise_2d(x1 * 5, z0 * 5) * height_var
			var h11 := noise.get_noise_2d(x1 * 5, z1 * 5) * height_var
			var h01 := noise.get_noise_2d(x0 * 5, z1 * 5) * height_var
			
			var color_var := noise.get_noise_2d(ix * 15.0, iz * 15.0) * 0.08
			var color := Color(
				clampf(base_color.r + color_var, 0.0, 1.0),
				clampf(base_color.g + color_var, 0.0, 1.0),
				clampf(base_color.b + color_var, 0.0, 1.0)
			)
			
			# Wood plank pattern
			if material_type == BuildPieceData.MaterialType.WOOD:
				var plank_index := iz % 2
				if plank_index == 0:
					color = color.darkened(0.08)
				# Plank seams
				if iz > 0 and iz % 2 == 0:
					color = color.darkened(0.15)
			
			# Stone tile pattern
			if material_type == BuildPieceData.MaterialType.STONE:
				var is_grout := (ix % 2 == 0 and iz % 2 == 0)
				if is_grout:
					color = color.darkened(0.12)
			
			# Faction-specific patterns
			if material_type == BuildPieceData.MaterialType.FACTION_SPECIFIC:
				if faction_id == 4:  # Tower - runic pattern
					var runic := sin(float(ix + iz) * 1.5) > 0.7
					if runic:
						color = color.lightened(0.2)
				elif faction_id == 3:  # Necropolis - cracked bone
					var crack := noise.get_noise_2d(ix * 30.0, iz * 30.0) > 0.6
					if crack:
						color = color.darkened(0.25)
			
			st.set_color(color)
			_add_quad(st, 
				Vector3(x0, FLOOR_THICKNESS + h00, z0),
				Vector3(x1, FLOOR_THICKNESS + h10, z0),
				Vector3(x1, FLOOR_THICKNESS + h11, z1),
				Vector3(x0, FLOOR_THICKNESS + h01, z1))
	
	# Bottom face
	st.set_color(base_color.darkened(0.3))
	_add_quad(st,
		Vector3(-half_size, 0, half_size),
		Vector3(half_size, 0, half_size),
		Vector3(half_size, 0, -half_size),
		Vector3(-half_size, 0, -half_size))
	
	# Side faces
	st.set_color(base_color.darkened(0.15))
	# Front
	_add_quad(st, Vector3(-half_size, 0, half_size), Vector3(-half_size, FLOOR_THICKNESS, half_size),
			Vector3(half_size, FLOOR_THICKNESS, half_size), Vector3(half_size, 0, half_size))
	# Back
	_add_quad(st, Vector3(half_size, 0, -half_size), Vector3(half_size, FLOOR_THICKNESS, -half_size),
			Vector3(-half_size, FLOOR_THICKNESS, -half_size), Vector3(-half_size, 0, -half_size))
	# Left
	_add_quad(st, Vector3(-half_size, 0, -half_size), Vector3(-half_size, FLOOR_THICKNESS, -half_size),
			Vector3(-half_size, FLOOR_THICKNESS, half_size), Vector3(-half_size, 0, half_size))
	# Right
	_add_quad(st, Vector3(half_size, 0, half_size), Vector3(half_size, FLOOR_THICKNESS, half_size),
			Vector3(half_size, FLOOR_THICKNESS, -half_size), Vector3(half_size, 0, -half_size))


static func _generate_simple_floor(st: SurfaceTool, half_size: float, base_color: Color) -> void:
	# Top
	st.set_color(base_color)
	_add_quad(st, Vector3(-half_size, FLOOR_THICKNESS, -half_size), Vector3(half_size, FLOOR_THICKNESS, -half_size),
			Vector3(half_size, FLOOR_THICKNESS, half_size), Vector3(-half_size, FLOOR_THICKNESS, half_size))
	# Bottom
	st.set_color(base_color.darkened(0.3))
	_add_quad(st, Vector3(-half_size, 0, half_size), Vector3(half_size, 0, half_size),
			Vector3(half_size, 0, -half_size), Vector3(-half_size, 0, -half_size))
	# Sides
	st.set_color(base_color.darkened(0.15))
	_add_quad(st, Vector3(-half_size, 0, half_size), Vector3(-half_size, FLOOR_THICKNESS, half_size),
			Vector3(half_size, FLOOR_THICKNESS, half_size), Vector3(half_size, 0, half_size))
	_add_quad(st, Vector3(half_size, 0, -half_size), Vector3(half_size, FLOOR_THICKNESS, -half_size),
			Vector3(-half_size, FLOOR_THICKNESS, -half_size), Vector3(-half_size, 0, -half_size))
	_add_quad(st, Vector3(-half_size, 0, -half_size), Vector3(-half_size, FLOOR_THICKNESS, -half_size),
			Vector3(-half_size, FLOOR_THICKNESS, half_size), Vector3(-half_size, 0, half_size))
	_add_quad(st, Vector3(half_size, 0, half_size), Vector3(half_size, FLOOR_THICKNESS, half_size),
			Vector3(half_size, FLOOR_THICKNESS, -half_size), Vector3(half_size, 0, -half_size))


static func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)


static func generate_collision_shape(size: float, thickness: float) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, thickness, size)
	return shape
