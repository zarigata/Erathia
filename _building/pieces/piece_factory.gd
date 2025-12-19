class_name PieceFactory
extends RefCounted

## Use 3D mesh files instead of procedural generation
## Set to false to revert to procedural generators
static var USE_3D_MESHES: bool = true

static var _mesh_cache: Dictionary = {}
static var _material_cache: Dictionary = {}

## Mesh file paths for each category
const MESH_PATHS: Dictionary = {
	"wall": "res://_building/meshes/wall_mesh.tres",
	"floor": "res://_building/meshes/floor_mesh.tres",
	"foundation": "res://_building/meshes/foundation_mesh.tres",
	"door": "res://_building/meshes/door_mesh.tres",
	"stairs": "res://_building/meshes/stairs_mesh.tres",
	"roof": "res://_building/meshes/roof_mesh.tres",
}

## Material file paths
const MATERIAL_PATHS: Dictionary = {
	BuildPieceData.MaterialType.WOOD: "res://_building/meshes/materials/wood_material.tres",
	BuildPieceData.MaterialType.STONE: "res://_building/meshes/materials/stone_material.tres",
	BuildPieceData.MaterialType.METAL: "res://_building/meshes/materials/metal_material.tres",
}


static func create_piece(piece_id: String, material_variant: int = 0) -> BuildPiece:
	var database: Node = PieceDatabase
	if not database:
		database = load("res://_building/pieces/piece_database.gd").new()
		database._initialize_database()
	
	var piece_data: BuildPieceData = database.get_piece_data(piece_id)
	if not piece_data:
		push_error("PieceFactory: Unknown piece_id '%s'" % piece_id)
		return null
	
	var piece := BuildPiece.new()
	piece.piece_data = piece_data
	piece.current_material_variant = material_variant
	
	var mesh: Mesh
	if USE_3D_MESHES:
		mesh = _load_mesh_for_category(piece_data)
	else:
		mesh = _get_or_generate_mesh(piece_data, material_variant, 0)
	
	piece.set_mesh(mesh)
	
	# Apply material based on piece material type
	if USE_3D_MESHES:
		var material := _get_material_for_type(piece_data.material_type)
		if material:
			piece.set_material_override(material)
	
	var collision := _generate_collision(piece_data)
	piece.set_collision(collision)
	
	return piece


static func create_preview_piece(piece_id: String) -> BuildPiece:
	var piece := create_piece(piece_id, 0)
	if piece:
		piece.preview_mode(true)
	return piece


## Load a mesh file for the given piece category
static func _load_mesh_for_category(piece_data: BuildPieceData) -> Mesh:
	var category_key := _get_category_key(piece_data.category)
	
	# Check cache first
	if _mesh_cache.has(category_key):
		return _mesh_cache[category_key]
	
	# Load mesh from file
	var mesh_path: String = MESH_PATHS.get(category_key, "")
	if mesh_path.is_empty():
		push_warning("PieceFactory: No mesh path for category '%s', using fallback" % category_key)
		return _create_fallback_mesh(piece_data)
	
	if not ResourceLoader.exists(mesh_path):
		push_warning("PieceFactory: Mesh file not found: %s, using fallback" % mesh_path)
		return _create_fallback_mesh(piece_data)
	
	var mesh: Mesh = load(mesh_path)
	if mesh:
		_mesh_cache[category_key] = mesh
		return mesh
	
	return _create_fallback_mesh(piece_data)


## Get category key string from enum
static func _get_category_key(category: int) -> String:
	match category:
		BuildPieceData.Category.WALL:
			return "wall"
		BuildPieceData.Category.FLOOR:
			return "floor"
		BuildPieceData.Category.FOUNDATION:
			return "foundation"
		BuildPieceData.Category.DOOR:
			return "door"
		BuildPieceData.Category.STAIRS:
			return "stairs"
		BuildPieceData.Category.ROOF:
			return "roof"
	return "wall"


## Create a simple box mesh as fallback
static func _create_fallback_mesh(piece_data: BuildPieceData) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = piece_data.dimensions
	return mesh


## Get material for the given material type
static func _get_material_for_type(material_type: int) -> Material:
	# Check cache
	if _material_cache.has(material_type):
		return _material_cache[material_type]
	
	# Load material
	var material_path: String = MATERIAL_PATHS.get(material_type, "")
	if material_path.is_empty():
		return _create_fallback_material(material_type)
	
	if not ResourceLoader.exists(material_path):
		return _create_fallback_material(material_type)
	
	var material: Material = load(material_path)
	if material:
		_material_cache[material_type] = material
		return material
	
	return _create_fallback_material(material_type)


## Create a simple material as fallback
static func _create_fallback_material(material_type: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	match material_type:
		BuildPieceData.MaterialType.WOOD:
			mat.albedo_color = Color(0.4, 0.28, 0.18)
		BuildPieceData.MaterialType.STONE:
			mat.albedo_color = Color(0.5, 0.5, 0.52)
		BuildPieceData.MaterialType.METAL:
			mat.albedo_color = Color(0.45, 0.45, 0.5)
			mat.metallic = 0.6
		_:
			mat.albedo_color = Color(0.5, 0.5, 0.5)
	mat.roughness = 0.8
	_material_cache[material_type] = mat
	return mat


## Legacy: Get or generate mesh using procedural generators
static func _get_or_generate_mesh(piece_data: BuildPieceData, material_variant: int, lod_level: int) -> ArrayMesh:
	var cache_key := "%s_%d_%d_%d" % [piece_data.piece_id, material_variant, piece_data.seed_base, lod_level]
	
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
	
	var mesh := _generate_mesh(piece_data, lod_level)
	_mesh_cache[cache_key] = mesh
	return mesh


static func _generate_mesh(piece_data: BuildPieceData, lod_level: int) -> ArrayMesh:
	var material_type := piece_data.material_type
	var faction_id := piece_data.faction_id
	var seed_value := piece_data.seed_base
	var piece_id := piece_data.piece_id
	
	match piece_data.category:
		BuildPieceData.Category.WALL:
			# Check for angled walls
			if piece_id.ends_with("_45"):
				return WallGenerator.generate_angled_wall(45.0, material_type, faction_id, seed_value, lod_level)
			elif piece_id.ends_with("_corner_inner"):
				return WallGenerator.generate_corner_wall(true, material_type, faction_id, seed_value, lod_level)
			elif piece_id.ends_with("_corner_outer"):
				return WallGenerator.generate_corner_wall(false, material_type, faction_id, seed_value, lod_level)
			return WallGenerator.generate_wall(material_type, faction_id, seed_value, lod_level)
		BuildPieceData.Category.FLOOR:
			return FloorGenerator.generate_floor(material_type, faction_id, seed_value, lod_level)
		BuildPieceData.Category.ROOF:
			var roof_type := _get_roof_type_for_piece(piece_data)
			var roof_slope := _get_roof_slope_for_piece(piece_data)
			if roof_slope != RoofGenerator.RoofSlope.MEDIUM:
				return RoofGenerator.generate_sloped_roof(roof_type, roof_slope, material_type, faction_id, seed_value, lod_level)
			return RoofGenerator.generate_roof(roof_type, material_type, faction_id, seed_value, lod_level)
		BuildPieceData.Category.DOOR:
			var door_style := _get_door_style_for_piece(piece_data)
			return DoorGenerator.generate_door(door_style, material_type, faction_id, seed_value, lod_level)
		BuildPieceData.Category.FOUNDATION:
			return FoundationGenerator.generate_foundation(Vector2(piece_data.dimensions.x, piece_data.dimensions.z), 
					material_type, seed_value, lod_level)
		BuildPieceData.Category.STAIRS:
			# Check for stair variants
			if piece_id.ends_with("_quarter"):
				return StairGenerator.generate_quarter_turn_stairs(material_type, faction_id, seed_value, lod_level)
			elif piece_id.ends_with("_half"):
				return StairGenerator.generate_half_landing_stairs(material_type, faction_id, seed_value, lod_level)
			elif piece_id.ends_with("_ramp"):
				return StairGenerator.generate_ramp(piece_data.dimensions.z, piece_data.dimensions.y, 
						piece_data.dimensions.x, material_type, faction_id, seed_value, lod_level)
			elif piece_id == "ladder":
				return StairGenerator.generate_stairs(10, material_type, faction_id, seed_value, lod_level)
			elif piece_id == "spiral_stairs":
				return StairGenerator.generate_spiral_stairs(material_type, faction_id, seed_value, lod_level)
			return StairGenerator.generate_stairs(8, material_type, faction_id, seed_value, lod_level)
	
	push_error("PieceFactory: Unknown category for piece '%s'" % piece_data.piece_id)
	return ArrayMesh.new()


static func _get_roof_type_for_piece(piece_data: BuildPieceData) -> int:
	if piece_data.piece_id.contains("thatch"):
		return RoofGenerator.RoofType.GABLED
	elif piece_data.piece_id.contains("flat"):
		return RoofGenerator.RoofType.FLAT
	elif piece_data.piece_id.contains("hip"):
		return RoofGenerator.RoofType.HIPPED
	elif piece_data.tier >= 2:
		return RoofGenerator.RoofType.HIPPED
	return RoofGenerator.RoofType.GABLED


static func _get_roof_slope_for_piece(piece_data: BuildPieceData) -> int:
	if piece_data.piece_id.contains("shallow"):
		return RoofGenerator.RoofSlope.SHALLOW
	elif piece_data.piece_id.contains("steep"):
		return RoofGenerator.RoofSlope.STEEP
	elif piece_data.piece_id.contains("flat"):
		return RoofGenerator.RoofSlope.FLAT
	return RoofGenerator.RoofSlope.MEDIUM


static func _get_door_style_for_piece(piece_data: BuildPieceData) -> int:
	match piece_data.tier:
		0:
			return DoorGenerator.DoorStyle.SIMPLE
		1:
			if piece_data.piece_id.contains("reinforced"):
				return DoorGenerator.DoorStyle.REINFORCED
			return DoorGenerator.DoorStyle.SIMPLE
		2:
			return DoorGenerator.DoorStyle.ORNATE
		3:
			return DoorGenerator.DoorStyle.FACTION_GATE
	return DoorGenerator.DoorStyle.SIMPLE


static func _generate_collision(piece_data: BuildPieceData) -> Shape3D:
	var piece_id := piece_data.piece_id
	
	match piece_data.category:
		BuildPieceData.Category.WALL:
			# Check for angled walls
			if piece_id.ends_with("_45"):
				return WallGenerator.generate_angled_collision_shape(45.0, piece_data.dimensions)
			elif piece_id.ends_with("_corner_inner"):
				return WallGenerator.generate_corner_collision_shape(true)
			elif piece_id.ends_with("_corner_outer"):
				return WallGenerator.generate_corner_collision_shape(false)
			return WallGenerator.generate_collision_shape(piece_data.dimensions)
		BuildPieceData.Category.FLOOR:
			return FloorGenerator.generate_collision_shape(piece_data.dimensions.x, piece_data.dimensions.y)
		BuildPieceData.Category.ROOF:
			var roof_type := _get_roof_type_for_piece(piece_data)
			var roof_slope := _get_roof_slope_for_piece(piece_data)
			if roof_slope != RoofGenerator.RoofSlope.MEDIUM:
				return RoofGenerator.generate_sloped_collision_shape(roof_type, roof_slope)
			return RoofGenerator.generate_collision_shape(roof_type)
		BuildPieceData.Category.DOOR:
			return DoorGenerator.generate_collision_shape()
		BuildPieceData.Category.FOUNDATION:
			return FoundationGenerator.generate_collision_shape(
					Vector2(piece_data.dimensions.x, piece_data.dimensions.z), piece_data.dimensions.y)
		BuildPieceData.Category.STAIRS:
			# Check for stair variants
			if piece_id.ends_with("_quarter"):
				return StairGenerator.generate_quarter_turn_collision_shape()
			elif piece_id.ends_with("_half"):
				return StairGenerator.generate_half_landing_collision_shape()
			elif piece_id.ends_with("_ramp"):
				return StairGenerator.generate_ramp_collision_shape(
						piece_data.dimensions.z, piece_data.dimensions.y, piece_data.dimensions.x)
			return StairGenerator.generate_collision_shape(piece_data.dimensions)
	
	var fallback := BoxShape3D.new()
	fallback.size = piece_data.dimensions
	return fallback


static func clear_cache() -> void:
	_mesh_cache.clear()
	_material_cache.clear()


static func get_cache_size() -> int:
	return _mesh_cache.size() + _material_cache.size()


## Toggle between 3D mesh files and procedural generation
## Call this to switch modes at runtime for testing
static func set_use_3d_meshes(enabled: bool) -> void:
	USE_3D_MESHES = enabled
	clear_cache()  # Clear cache when switching modes
