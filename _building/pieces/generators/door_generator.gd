class_name DoorGenerator
extends RefCounted

const DOOR_HEIGHT: float = 2.5
const DOOR_WIDTH: float = 1.2
const DOOR_THICKNESS: float = 0.1
const FRAME_WIDTH: float = 0.15
const FRAME_DEPTH: float = 0.2

enum DoorStyle {
	SIMPLE,
	REINFORCED,
	ORNATE,
	FACTION_GATE
}

const WOOD_COLORS: Array[Color] = [
	Color(0.4, 0.25, 0.15),
	Color(0.45, 0.28, 0.17),
	Color(0.35, 0.22, 0.12)
]

const METAL_BAND_COLOR: Color = Color(0.25, 0.25, 0.28)
const METAL_HANDLE_COLOR: Color = Color(0.5, 0.45, 0.3)

const FACTION_COLORS: Dictionary = {
	0: Color(0.8, 0.75, 0.7),
	1: Color(0.2, 0.15, 0.15),
	2: Color(0.3, 0.4, 0.25),
	3: Color(0.25, 0.25, 0.3),
	4: Color(0.4, 0.35, 0.5),
	5: Color(0.5, 0.4, 0.3),
	6: Color(0.35, 0.38, 0.32),
	7: Color(0.45, 0.5, 0.55),
}


static func generate_door(style: int, material_type: int, faction_id: int, seed_value: int, lod_level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_color := _get_base_color(material_type, faction_id, rng)
	
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.8
	
	_generate_door_frame(st, base_color.darkened(0.2))
	
	match style:
		DoorStyle.SIMPLE:
			_generate_simple_door(st, base_color, noise, lod_level)
		DoorStyle.REINFORCED:
			_generate_reinforced_door(st, base_color, noise, lod_level)
		DoorStyle.ORNATE:
			_generate_ornate_door(st, base_color, noise, lod_level)
		DoorStyle.FACTION_GATE:
			_generate_faction_gate(st, base_color, noise, lod_level, faction_id)
	
	st.generate_normals()
	return st.commit()


static func _get_base_color(material_type: int, faction_id: int, rng: RandomNumberGenerator) -> Color:
	match material_type:
		BuildPieceData.MaterialType.WOOD:
			return WOOD_COLORS[rng.randi() % WOOD_COLORS.size()]
		BuildPieceData.MaterialType.STONE:
			return Color(0.45, 0.45, 0.48)
		BuildPieceData.MaterialType.METAL:
			return Color(0.35, 0.35, 0.4)
		BuildPieceData.MaterialType.FACTION_SPECIFIC:
			if FACTION_COLORS.has(faction_id):
				return FACTION_COLORS[faction_id]
			return Color(0.5, 0.5, 0.5)
	return Color(0.5, 0.5, 0.5)


static func _generate_door_frame(st: SurfaceTool, frame_color: Color) -> void:
	var half_width := DOOR_WIDTH / 2.0 + FRAME_WIDTH
	var half_depth := FRAME_DEPTH / 2.0
	
	st.set_color(frame_color)
	
	var lx0 := -half_width
	var lx1 := -DOOR_WIDTH / 2.0
	_add_box(st, Vector3(lx0, 0, -half_depth), Vector3(lx1, DOOR_HEIGHT + FRAME_WIDTH, half_depth), frame_color)
	
	var rx0 := DOOR_WIDTH / 2.0
	var rx1 := half_width
	_add_box(st, Vector3(rx0, 0, -half_depth), Vector3(rx1, DOOR_HEIGHT + FRAME_WIDTH, half_depth), frame_color)
	
	_add_box(st, Vector3(-half_width, DOOR_HEIGHT, -half_depth), 
			Vector3(half_width, DOOR_HEIGHT + FRAME_WIDTH, half_depth), frame_color)


static func _generate_simple_door(st: SurfaceTool, base_color: Color, noise: FastNoiseLite, lod_level: int) -> void:
	var half_width := DOOR_WIDTH / 2.0
	var half_thickness := DOOR_THICKNESS / 2.0
	
	if lod_level <= 1:
		var plank_count := 4
		var plank_height := DOOR_HEIGHT / plank_count
		
		for i in range(plank_count):
			var y0 := i * plank_height
			var y1 := y0 + plank_height
			
			var color_var := noise.get_noise_2d(i * 10.0, 0) * 0.08
			var color := Color(
				clampf(base_color.r + color_var, 0.0, 1.0),
				clampf(base_color.g + color_var, 0.0, 1.0),
				clampf(base_color.b + color_var, 0.0, 1.0)
			)
			if i % 2 == 0:
				color = color.darkened(0.05)
			
			st.set_color(color)
			_add_quad(st, Vector3(-half_width, y0, half_thickness), Vector3(half_width, y0, half_thickness),
					Vector3(half_width, y1, half_thickness), Vector3(-half_width, y1, half_thickness))
			_add_quad(st, Vector3(half_width, y0, -half_thickness), Vector3(-half_width, y0, -half_thickness),
					Vector3(-half_width, y1, -half_thickness), Vector3(half_width, y1, -half_thickness))
		
		st.set_color(base_color.darkened(0.15))
		_add_quad(st, Vector3(-half_width, 0, -half_thickness), Vector3(-half_width, 0, half_thickness),
				Vector3(-half_width, DOOR_HEIGHT, half_thickness), Vector3(-half_width, DOOR_HEIGHT, -half_thickness))
		_add_quad(st, Vector3(half_width, 0, half_thickness), Vector3(half_width, 0, -half_thickness),
				Vector3(half_width, DOOR_HEIGHT, -half_thickness), Vector3(half_width, DOOR_HEIGHT, half_thickness))
		_add_quad(st, Vector3(-half_width, DOOR_HEIGHT, half_thickness), Vector3(half_width, DOOR_HEIGHT, half_thickness),
				Vector3(half_width, DOOR_HEIGHT, -half_thickness), Vector3(-half_width, DOOR_HEIGHT, -half_thickness))
	else:
		_generate_door_box(st, half_width, half_thickness, base_color)
	
	_add_handle(st, Vector3(half_width * 0.6, DOOR_HEIGHT * 0.45, half_thickness))


static func _generate_reinforced_door(st: SurfaceTool, base_color: Color, noise: FastNoiseLite, lod_level: int) -> void:
	var half_width := DOOR_WIDTH / 2.0
	var half_thickness := DOOR_THICKNESS / 2.0
	
	_generate_door_box(st, half_width, half_thickness, base_color)
	
	st.set_color(METAL_BAND_COLOR)
	var band_height := 0.08
	var band_positions := [0.2, 0.5, 0.8]
	
	for band_y in band_positions:
		var y: float = band_y * DOOR_HEIGHT
		_add_quad(st, Vector3(-half_width, y - band_height/2, half_thickness + 0.01),
				Vector3(half_width, y - band_height/2, half_thickness + 0.01),
				Vector3(half_width, y + band_height/2, half_thickness + 0.01),
				Vector3(-half_width, y + band_height/2, half_thickness + 0.01))
	
	var vert_x := [-half_width * 0.6, half_width * 0.6]
	for vx in vert_x:
		_add_quad(st, Vector3(vx - 0.03, 0.1, half_thickness + 0.01),
				Vector3(vx + 0.03, 0.1, half_thickness + 0.01),
				Vector3(vx + 0.03, DOOR_HEIGHT - 0.1, half_thickness + 0.01),
				Vector3(vx - 0.03, DOOR_HEIGHT - 0.1, half_thickness + 0.01))
	
	_add_handle(st, Vector3(half_width * 0.6, DOOR_HEIGHT * 0.45, half_thickness))


static func _generate_ornate_door(st: SurfaceTool, base_color: Color, noise: FastNoiseLite, lod_level: int) -> void:
	var half_width := DOOR_WIDTH / 2.0
	var half_thickness := DOOR_THICKNESS / 2.0
	
	_generate_door_box(st, half_width, half_thickness, base_color)
	
	st.set_color(base_color.lightened(0.1))
	var panel_inset := 0.15
	var panel_y_start := 0.3
	var panel_y_end := DOOR_HEIGHT - 0.3
	var panel_height := (panel_y_end - panel_y_start) / 2 - 0.1
	
	for i in range(2):
		var py := panel_y_start + i * (panel_height + 0.2)
		_add_quad(st, Vector3(-half_width + panel_inset, py, half_thickness + 0.02),
				Vector3(half_width - panel_inset, py, half_thickness + 0.02),
				Vector3(half_width - panel_inset, py + panel_height, half_thickness + 0.02),
				Vector3(-half_width + panel_inset, py + panel_height, half_thickness + 0.02))
	
	st.set_color(METAL_HANDLE_COLOR)
	_add_handle(st, Vector3(half_width * 0.6, DOOR_HEIGHT * 0.45, half_thickness))
	
	var hinge_y := [0.3, DOOR_HEIGHT - 0.3]
	for hy in hinge_y:
		_add_box(st, Vector3(-half_width - 0.02, hy - 0.08, half_thickness),
				Vector3(-half_width + 0.02, hy + 0.08, half_thickness + 0.05), METAL_BAND_COLOR)


static func _generate_faction_gate(st: SurfaceTool, base_color: Color, noise: FastNoiseLite, lod_level: int, faction_id: int) -> void:
	var half_width := DOOR_WIDTH / 2.0
	var half_thickness := DOOR_THICKNESS / 2.0
	
	_generate_door_box(st, half_width, half_thickness, base_color)
	
	var symbol_color := base_color.lightened(0.3)
	st.set_color(symbol_color)
	
	var cx := 0.0
	var cy := DOOR_HEIGHT * 0.55
	var symbol_size := 0.25
	
	match faction_id:
		0:  # Castle - cross
			_add_quad(st, Vector3(cx - 0.05, cy - symbol_size, half_thickness + 0.02),
					Vector3(cx + 0.05, cy - symbol_size, half_thickness + 0.02),
					Vector3(cx + 0.05, cy + symbol_size, half_thickness + 0.02),
					Vector3(cx - 0.05, cy + symbol_size, half_thickness + 0.02))
			_add_quad(st, Vector3(cx - symbol_size, cy - 0.05, half_thickness + 0.02),
					Vector3(cx + symbol_size, cy - 0.05, half_thickness + 0.02),
					Vector3(cx + symbol_size, cy + 0.05, half_thickness + 0.02),
					Vector3(cx - symbol_size, cy + 0.05, half_thickness + 0.02))
		1:  # Inferno - horns (two triangles)
			st.add_vertex(Vector3(cx - symbol_size, cy - symbol_size * 0.5, half_thickness + 0.02))
			st.add_vertex(Vector3(cx - symbol_size * 0.3, cy + symbol_size, half_thickness + 0.02))
			st.add_vertex(Vector3(cx - symbol_size * 0.5, cy - symbol_size * 0.3, half_thickness + 0.02))
			st.add_vertex(Vector3(cx + symbol_size, cy - symbol_size * 0.5, half_thickness + 0.02))
			st.add_vertex(Vector3(cx + symbol_size * 0.5, cy - symbol_size * 0.3, half_thickness + 0.02))
			st.add_vertex(Vector3(cx + symbol_size * 0.3, cy + symbol_size, half_thickness + 0.02))
		2:  # Rampart - leaf
			st.add_vertex(Vector3(cx, cy + symbol_size, half_thickness + 0.02))
			st.add_vertex(Vector3(cx - symbol_size * 0.6, cy, half_thickness + 0.02))
			st.add_vertex(Vector3(cx, cy - symbol_size * 0.3, half_thickness + 0.02))
			st.add_vertex(Vector3(cx, cy + symbol_size, half_thickness + 0.02))
			st.add_vertex(Vector3(cx, cy - symbol_size * 0.3, half_thickness + 0.02))
			st.add_vertex(Vector3(cx + symbol_size * 0.6, cy, half_thickness + 0.02))
		_:  # Default - diamond
			st.add_vertex(Vector3(cx, cy + symbol_size, half_thickness + 0.02))
			st.add_vertex(Vector3(cx - symbol_size, cy, half_thickness + 0.02))
			st.add_vertex(Vector3(cx, cy - symbol_size, half_thickness + 0.02))
			st.add_vertex(Vector3(cx, cy - symbol_size, half_thickness + 0.02))
			st.add_vertex(Vector3(cx + symbol_size, cy, half_thickness + 0.02))
			st.add_vertex(Vector3(cx, cy + symbol_size, half_thickness + 0.02))
	
	_add_handle(st, Vector3(half_width * 0.6, DOOR_HEIGHT * 0.45, half_thickness))


static func _generate_door_box(st: SurfaceTool, half_width: float, half_thickness: float, color: Color) -> void:
	st.set_color(color)
	_add_quad(st, Vector3(-half_width, 0, half_thickness), Vector3(half_width, 0, half_thickness),
			Vector3(half_width, DOOR_HEIGHT, half_thickness), Vector3(-half_width, DOOR_HEIGHT, half_thickness))
	_add_quad(st, Vector3(half_width, 0, -half_thickness), Vector3(-half_width, 0, -half_thickness),
			Vector3(-half_width, DOOR_HEIGHT, -half_thickness), Vector3(half_width, DOOR_HEIGHT, -half_thickness))
	st.set_color(color.darkened(0.15))
	_add_quad(st, Vector3(-half_width, 0, -half_thickness), Vector3(-half_width, 0, half_thickness),
			Vector3(-half_width, DOOR_HEIGHT, half_thickness), Vector3(-half_width, DOOR_HEIGHT, -half_thickness))
	_add_quad(st, Vector3(half_width, 0, half_thickness), Vector3(half_width, 0, -half_thickness),
			Vector3(half_width, DOOR_HEIGHT, -half_thickness), Vector3(half_width, DOOR_HEIGHT, half_thickness))
	_add_quad(st, Vector3(-half_width, DOOR_HEIGHT, half_thickness), Vector3(half_width, DOOR_HEIGHT, half_thickness),
			Vector3(half_width, DOOR_HEIGHT, -half_thickness), Vector3(-half_width, DOOR_HEIGHT, -half_thickness))


static func _add_handle(st: SurfaceTool, pos: Vector3) -> void:
	st.set_color(METAL_HANDLE_COLOR)
	var handle_size := 0.05
	_add_quad(st, Vector3(pos.x - handle_size, pos.y - handle_size, pos.z + 0.02),
			Vector3(pos.x + handle_size, pos.y - handle_size, pos.z + 0.02),
			Vector3(pos.x + handle_size, pos.y + handle_size, pos.z + 0.02),
			Vector3(pos.x - handle_size, pos.y + handle_size, pos.z + 0.02))


static func _add_box(st: SurfaceTool, min_pos: Vector3, max_pos: Vector3, color: Color) -> void:
	st.set_color(color)
	_add_quad(st, Vector3(min_pos.x, min_pos.y, max_pos.z), Vector3(max_pos.x, min_pos.y, max_pos.z),
			Vector3(max_pos.x, max_pos.y, max_pos.z), Vector3(min_pos.x, max_pos.y, max_pos.z))
	_add_quad(st, Vector3(max_pos.x, min_pos.y, min_pos.z), Vector3(min_pos.x, min_pos.y, min_pos.z),
			Vector3(min_pos.x, max_pos.y, min_pos.z), Vector3(max_pos.x, max_pos.y, min_pos.z))
	st.set_color(color.darkened(0.1))
	_add_quad(st, Vector3(min_pos.x, min_pos.y, min_pos.z), Vector3(min_pos.x, min_pos.y, max_pos.z),
			Vector3(min_pos.x, max_pos.y, max_pos.z), Vector3(min_pos.x, max_pos.y, min_pos.z))
	_add_quad(st, Vector3(max_pos.x, min_pos.y, max_pos.z), Vector3(max_pos.x, min_pos.y, min_pos.z),
			Vector3(max_pos.x, max_pos.y, min_pos.z), Vector3(max_pos.x, max_pos.y, max_pos.z))
	st.set_color(color.darkened(0.05))
	_add_quad(st, Vector3(min_pos.x, max_pos.y, max_pos.z), Vector3(max_pos.x, max_pos.y, max_pos.z),
			Vector3(max_pos.x, max_pos.y, min_pos.z), Vector3(min_pos.x, max_pos.y, min_pos.z))
	st.set_color(color.darkened(0.2))
	_add_quad(st, Vector3(min_pos.x, min_pos.y, min_pos.z), Vector3(max_pos.x, min_pos.y, min_pos.z),
			Vector3(max_pos.x, min_pos.y, max_pos.z), Vector3(min_pos.x, min_pos.y, max_pos.z))


static func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)


static func generate_collision_shape() -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(DOOR_WIDTH + FRAME_WIDTH * 2, DOOR_HEIGHT + FRAME_WIDTH, FRAME_DEPTH)
	return shape
