extends Node

var pieces: Dictionary = {}


func _ready() -> void:
	_initialize_database()


func _initialize_database() -> void:
	# Tier 0 - Hand crafted
	_add_piece(_create_thatch_wall())
	_add_piece(_create_dirt_floor())
	_add_piece(_create_thatch_roof())
	_add_piece(_create_simple_door())
	_add_piece(_create_ladder())
	
	# Tier 1 - Workbench (Wood)
	_add_piece(_create_wood_wall())
	_add_piece(_create_wood_floor())
	_add_piece(_create_wood_roof())
	_add_piece(_create_wood_door())
	_add_piece(_create_wood_foundation())
	_add_piece(_create_wood_stairs())
	
	# Tier 1 - Wood Angled Walls
	_add_piece(_create_wood_wall_45())
	_add_piece(_create_wood_wall_corner_inner())
	_add_piece(_create_wood_wall_corner_outer())
	
	# Tier 1 - Wood Roof Variants
	_add_piece(_create_wood_roof_shallow())
	_add_piece(_create_wood_roof_steep())
	
	# Tier 1 - Wood Stair Variants
	_add_piece(_create_wood_stairs_quarter())
	_add_piece(_create_wood_stairs_half())
	_add_piece(_create_wood_ramp())
	
	# Tier 1 - Workbench (Stone)
	_add_piece(_create_stone_wall())
	_add_piece(_create_stone_floor())
	_add_piece(_create_stone_roof())
	_add_piece(_create_reinforced_door())
	_add_piece(_create_stone_foundation())
	_add_piece(_create_stone_stairs())
	
	# Tier 1 - Stone Angled Walls
	_add_piece(_create_stone_wall_45())
	_add_piece(_create_stone_wall_corner_inner())
	_add_piece(_create_stone_wall_corner_outer())
	
	# Tier 1 - Stone Roof Variants
	_add_piece(_create_stone_roof_hip())
	
	# Tier 1 - Stone Stair Variants
	_add_piece(_create_stone_stairs_quarter())
	_add_piece(_create_stone_stairs_half())
	_add_piece(_create_stone_ramp())
	
	# Tier 2 - Arcane Forge
	_add_piece(_create_metal_wall())
	_add_piece(_create_polished_floor())
	_add_piece(_create_slate_roof())
	_add_piece(_create_ornate_door())
	_add_piece(_create_reinforced_foundation())
	_add_piece(_create_spiral_stairs())
	
	# Tier 3 - Faction specific
	_add_faction_pieces()


func _add_piece(data: BuildPieceData) -> void:
	pieces[data.piece_id] = data


func get_piece_data(piece_id: String) -> BuildPieceData:
	return pieces.get(piece_id, null)


func get_pieces_by_tier(tier: int) -> Array[BuildPieceData]:
	var result: Array[BuildPieceData] = []
	for piece_id in pieces:
		var data: BuildPieceData = pieces[piece_id]
		if data.tier == tier:
			result.append(data)
	return result


func get_pieces_by_faction(faction_id: int) -> Array[BuildPieceData]:
	var result: Array[BuildPieceData] = []
	for piece_id in pieces:
		var data: BuildPieceData = pieces[piece_id]
		if data.faction_id == faction_id:
			result.append(data)
	return result


func get_pieces_by_category(category: int) -> Array[BuildPieceData]:
	var result: Array[BuildPieceData] = []
	for piece_id in pieces:
		var data: BuildPieceData = pieces[piece_id]
		if data.category == category:
			result.append(data)
	return result


func can_craft_piece(piece_id: String, inventory: Node) -> bool:
	var data := get_piece_data(piece_id)
	if not data:
		return false
	if inventory and inventory.has_method("has_building_resources"):
		return inventory.has_building_resources(data)
	return false


func get_all_piece_ids() -> Array[String]:
	var result: Array[String] = []
	for piece_id in pieces:
		result.append(piece_id)
	return result


# === Tier 0 Pieces ===

func _create_thatch_wall() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "thatch_wall"
	data.display_name = "Thatch Wall"
	data.description = "A simple wall made of thatch and sticks."
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 0
	data.resource_costs = {"wood": 5}
	data.dimensions = Vector3(4.0, 3.0, 0.3)
	data.structural_weight = 0.5
	data.seed_base = 1000
	_add_wall_snap_points(data)
	return data


func _create_dirt_floor() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "dirt_floor"
	data.display_name = "Dirt Floor"
	data.description = "Packed dirt floor tile."
	data.category = BuildPieceData.Category.FLOOR
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 0
	data.resource_costs = {"dirt": 10}
	data.dimensions = Vector3(4.0, 0.2, 4.0)
	data.structural_weight = 0.3
	data.seed_base = 1100
	_add_floor_snap_points(data)
	return data


func _create_thatch_roof() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "thatch_roof"
	data.display_name = "Thatch Roof"
	data.description = "A simple thatched roof."
	data.category = BuildPieceData.Category.ROOF
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 0
	data.resource_costs = {"wood": 8}
	data.dimensions = Vector3(5.0, 2.0, 5.0)
	data.structural_weight = 0.4
	data.seed_base = 1200
	return data


func _create_simple_door() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "simple_door"
	data.display_name = "Simple Door"
	data.description = "A basic wooden door."
	data.category = BuildPieceData.Category.DOOR
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 0
	data.resource_costs = {"wood": 3}
	data.dimensions = Vector3(1.5, 2.65, 0.2)
	data.structural_weight = 0.2
	data.seed_base = 1300
	_add_door_snap_points(data)
	return data


func _create_ladder() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "ladder"
	data.display_name = "Ladder"
	data.description = "A simple wooden ladder."
	data.category = BuildPieceData.Category.STAIRS
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 0
	data.resource_costs = {"wood": 5}
	data.dimensions = Vector3(0.6, 3.0, 0.2)
	data.structural_weight = 0.1
	data.seed_base = 1400
	_add_stair_snap_points(data)
	return data


# === Tier 1 Wood Pieces ===

func _create_wood_wall() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_wall"
	data.display_name = "Wood Wall"
	data.description = "A sturdy wooden plank wall."
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 10, "stone": 5}
	data.dimensions = Vector3(4.0, 3.0, 0.3)
	data.structural_weight = 1.0
	data.seed_base = 2000
	_add_wall_snap_points(data)
	return data


func _create_wood_floor() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_floor"
	data.display_name = "Wood Floor"
	data.description = "Wooden plank flooring."
	data.category = BuildPieceData.Category.FLOOR
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 8}
	data.dimensions = Vector3(4.0, 0.2, 4.0)
	data.structural_weight = 0.8
	data.seed_base = 2100
	_add_floor_snap_points(data)
	return data


func _create_wood_roof() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_roof"
	data.display_name = "Wood Shingle Roof"
	data.description = "A roof with wooden shingles."
	data.category = BuildPieceData.Category.ROOF
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 12}
	data.dimensions = Vector3(5.0, 2.5, 5.0)
	data.structural_weight = 0.9
	data.seed_base = 2200
	return data


func _create_wood_door() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_door"
	data.display_name = "Wood Door"
	data.description = "A solid wooden door."
	data.category = BuildPieceData.Category.DOOR
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 6}
	data.dimensions = Vector3(1.5, 2.65, 0.2)
	data.structural_weight = 0.3
	data.seed_base = 2300
	_add_door_snap_points(data)
	return data


func _create_wood_foundation() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_foundation"
	data.display_name = "Wood Foundation"
	data.description = "A wooden foundation for building."
	data.category = BuildPieceData.Category.FOUNDATION
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 20}
	data.dimensions = Vector3(4.0, 0.5, 4.0)
	data.structural_weight = 2.0
	data.seed_base = 2400
	_add_foundation_snap_points(data)
	return data


func _create_wood_stairs() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_stairs"
	data.display_name = "Wood Stairs"
	data.description = "Wooden staircase."
	data.category = BuildPieceData.Category.STAIRS
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 15}
	data.dimensions = Vector3(1.2, 3.0, 2.4)
	data.structural_weight = 0.6
	data.seed_base = 2500
	_add_stair_snap_points(data)
	return data


# === Tier 1 Wood Angled Walls ===

func _create_wood_wall_45() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_wall_45"
	data.display_name = "Wood Wall (45°)"
	data.description = "A wooden wall angled at 45 degrees."
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 10, "stone": 5}
	data.dimensions = Vector3(4.0, 3.0, 0.3)
	data.structural_weight = 1.0
	data.seed_base = 2010
	_add_angled_wall_snap_points(data, 45.0)
	return data


func _create_wood_wall_corner_inner() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_wall_corner_inner"
	data.display_name = "Wood Corner (Inner)"
	data.description = "An inner corner piece for wooden walls."
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 6, "stone": 3}
	data.dimensions = Vector3(0.6, 3.0, 0.6)
	data.structural_weight = 0.8
	data.seed_base = 2020
	_add_corner_snap_points(data, true)
	return data


func _create_wood_wall_corner_outer() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_wall_corner_outer"
	data.display_name = "Wood Corner (Outer)"
	data.description = "An outer corner piece for wooden walls."
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 6, "stone": 3}
	data.dimensions = Vector3(0.6, 3.0, 0.6)
	data.structural_weight = 0.8
	data.seed_base = 2030
	_add_corner_snap_points(data, false)
	return data


# === Tier 1 Wood Roof Variants ===

func _create_wood_roof_shallow() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_roof_shallow"
	data.display_name = "Wood Roof (Shallow)"
	data.description = "A wooden roof with a shallow 15° slope."
	data.category = BuildPieceData.Category.ROOF
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 12}
	data.dimensions = Vector3(5.0, 1.5, 5.0)
	data.structural_weight = 0.9
	data.seed_base = 2210
	return data


func _create_wood_roof_steep() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_roof_steep"
	data.display_name = "Wood Roof (Steep)"
	data.description = "A wooden roof with a steep 45° slope."
	data.category = BuildPieceData.Category.ROOF
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 14}
	data.dimensions = Vector3(5.0, 3.5, 5.0)
	data.structural_weight = 1.0
	data.seed_base = 2220
	return data


# === Tier 1 Wood Stair Variants ===

func _create_wood_stairs_quarter() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_stairs_quarter"
	data.display_name = "Wood Stairs (Quarter-Turn)"
	data.description = "Wooden stairs with a 90° turn and landing."
	data.category = BuildPieceData.Category.STAIRS
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 20}
	data.dimensions = Vector3(2.4, 3.0, 2.4)
	data.structural_weight = 0.8
	data.seed_base = 2510
	_add_stair_snap_points(data)
	return data


func _create_wood_stairs_half() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_stairs_half"
	data.display_name = "Wood Stairs (Half-Landing)"
	data.description = "Wooden stairs with a 180° turn and half-landing."
	data.category = BuildPieceData.Category.STAIRS
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 25}
	data.dimensions = Vector3(2.4, 3.0, 3.6)
	data.structural_weight = 1.0
	data.seed_base = 2520
	_add_stair_snap_points(data)
	return data


func _create_wood_ramp() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "wood_ramp"
	data.display_name = "Wood Ramp"
	data.description = "A smooth wooden ramp (no steps)."
	data.category = BuildPieceData.Category.STAIRS
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 12}
	data.dimensions = Vector3(1.2, 1.0, 3.0)
	data.structural_weight = 0.5
	data.seed_base = 2530
	_add_ramp_snap_points(data)
	return data


# === Tier 1 Stone Pieces ===

func _create_stone_wall() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_wall"
	data.display_name = "Stone Wall"
	data.description = "A solid stone block wall."
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 15, "iron_ore": 3}
	data.dimensions = Vector3(4.0, 3.0, 0.3)
	data.structural_weight = 1.5
	data.seed_base = 3000
	_add_wall_snap_points(data)
	return data


func _create_stone_floor() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_floor"
	data.display_name = "Stone Floor"
	data.description = "Stone tile flooring."
	data.category = BuildPieceData.Category.FLOOR
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 12}
	data.dimensions = Vector3(4.0, 0.2, 4.0)
	data.structural_weight = 1.2
	data.seed_base = 3100
	_add_floor_snap_points(data)
	return data


func _create_stone_roof() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_roof"
	data.display_name = "Stone Roof"
	data.description = "A roof with stone tiles."
	data.category = BuildPieceData.Category.ROOF
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 15}
	data.dimensions = Vector3(5.0, 2.5, 5.0)
	data.structural_weight = 1.4
	data.seed_base = 3200
	return data


func _create_reinforced_door() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "reinforced_door"
	data.display_name = "Reinforced Door"
	data.description = "A wooden door reinforced with metal bands."
	data.category = BuildPieceData.Category.DOOR
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 1
	data.resource_costs = {"wood": 5, "iron_ore": 3}
	data.dimensions = Vector3(1.5, 2.65, 0.2)
	data.structural_weight = 0.5
	data.seed_base = 3300
	_add_door_snap_points(data)
	return data


func _create_stone_foundation() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_foundation"
	data.display_name = "Stone Foundation"
	data.description = "A solid stone foundation."
	data.category = BuildPieceData.Category.FOUNDATION
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 25}
	data.dimensions = Vector3(4.0, 0.5, 4.0)
	data.structural_weight = 3.0
	data.seed_base = 3400
	_add_foundation_snap_points(data)
	return data


func _create_stone_stairs() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_stairs"
	data.display_name = "Stone Stairs"
	data.description = "Stone staircase."
	data.category = BuildPieceData.Category.STAIRS
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 20}
	data.dimensions = Vector3(1.2, 3.0, 2.4)
	data.structural_weight = 1.0
	data.seed_base = 3500
	_add_stair_snap_points(data)
	return data


# === Tier 1 Stone Angled Walls ===

func _create_stone_wall_45() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_wall_45"
	data.display_name = "Stone Wall (45°)"
	data.description = "A stone wall angled at 45 degrees."
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 15, "iron_ore": 3}
	data.dimensions = Vector3(4.0, 3.0, 0.3)
	data.structural_weight = 1.5
	data.seed_base = 3010
	_add_angled_wall_snap_points(data, 45.0)
	return data


func _create_stone_wall_corner_inner() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_wall_corner_inner"
	data.display_name = "Stone Corner (Inner)"
	data.description = "An inner corner piece for stone walls."
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 10, "iron_ore": 2}
	data.dimensions = Vector3(0.6, 3.0, 0.6)
	data.structural_weight = 1.2
	data.seed_base = 3020
	_add_corner_snap_points(data, true)
	return data


func _create_stone_wall_corner_outer() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_wall_corner_outer"
	data.display_name = "Stone Corner (Outer)"
	data.description = "An outer corner piece for stone walls."
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 10, "iron_ore": 2}
	data.dimensions = Vector3(0.6, 3.0, 0.6)
	data.structural_weight = 1.2
	data.seed_base = 3030
	_add_corner_snap_points(data, false)
	return data


# === Tier 1 Stone Roof Variants ===

func _create_stone_roof_hip() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_roof_hip"
	data.display_name = "Stone Hip Roof"
	data.description = "A four-sided sloped stone roof."
	data.category = BuildPieceData.Category.ROOF
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 18}
	data.dimensions = Vector3(5.0, 2.5, 5.0)
	data.structural_weight = 1.5
	data.seed_base = 3210
	return data


# === Tier 1 Stone Stair Variants ===

func _create_stone_stairs_quarter() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_stairs_quarter"
	data.display_name = "Stone Stairs (Quarter-Turn)"
	data.description = "Stone stairs with a 90° turn and landing."
	data.category = BuildPieceData.Category.STAIRS
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 25}
	data.dimensions = Vector3(2.4, 3.0, 2.4)
	data.structural_weight = 1.2
	data.seed_base = 3510
	_add_stair_snap_points(data)
	return data


func _create_stone_stairs_half() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_stairs_half"
	data.display_name = "Stone Stairs (Half-Landing)"
	data.description = "Stone stairs with a 180° turn and half-landing."
	data.category = BuildPieceData.Category.STAIRS
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 30}
	data.dimensions = Vector3(2.4, 3.0, 3.6)
	data.structural_weight = 1.5
	data.seed_base = 3520
	_add_stair_snap_points(data)
	return data


func _create_stone_ramp() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "stone_ramp"
	data.display_name = "Stone Ramp"
	data.description = "A smooth stone ramp (no steps)."
	data.category = BuildPieceData.Category.STAIRS
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 1
	data.resource_costs = {"stone": 15}
	data.dimensions = Vector3(1.2, 1.0, 3.0)
	data.structural_weight = 0.8
	data.seed_base = 3530
	_add_ramp_snap_points(data)
	return data


# === Tier 2 Pieces ===

func _create_metal_wall() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "metal_wall"
	data.display_name = "Reinforced Wall"
	data.description = "A stone wall reinforced with metal."
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.METAL
	data.tier = 2
	data.resource_costs = {"stone": 10, "iron_ore": 8, "rare_crystal": 1}
	data.dimensions = Vector3(4.0, 3.0, 0.3)
	data.structural_weight = 2.0
	data.seed_base = 4000
	_add_wall_snap_points(data)
	return data


func _create_polished_floor() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "polished_floor"
	data.display_name = "Polished Floor"
	data.description = "Polished stone flooring."
	data.category = BuildPieceData.Category.FLOOR
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 2
	data.resource_costs = {"stone": 8, "iron_ore": 5}
	data.dimensions = Vector3(4.0, 0.2, 4.0)
	data.structural_weight = 1.5
	data.seed_base = 4100
	_add_floor_snap_points(data)
	return data


func _create_slate_roof() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "slate_roof"
	data.display_name = "Slate Roof"
	data.description = "A roof with slate tiles."
	data.category = BuildPieceData.Category.ROOF
	data.material_type = BuildPieceData.MaterialType.METAL
	data.tier = 2
	data.resource_costs = {"iron_ore": 10}
	data.dimensions = Vector3(5.0, 2.5, 5.0)
	data.structural_weight = 1.8
	data.seed_base = 4200
	return data


func _create_ornate_door() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "ornate_door"
	data.display_name = "Ornate Door"
	data.description = "An ornately decorated door."
	data.category = BuildPieceData.Category.DOOR
	data.material_type = BuildPieceData.MaterialType.WOOD
	data.tier = 2
	data.resource_costs = {"wood": 5, "iron_ore": 5, "rare_crystal": 1}
	data.dimensions = Vector3(1.5, 2.65, 0.2)
	data.structural_weight = 0.6
	data.seed_base = 4300
	_add_door_snap_points(data)
	return data


func _create_reinforced_foundation() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "reinforced_foundation"
	data.display_name = "Reinforced Foundation"
	data.description = "A metal-reinforced stone foundation."
	data.category = BuildPieceData.Category.FOUNDATION
	data.material_type = BuildPieceData.MaterialType.METAL
	data.tier = 2
	data.resource_costs = {"stone": 20, "iron_ore": 10}
	data.dimensions = Vector3(4.0, 0.5, 4.0)
	data.structural_weight = 4.0
	data.seed_base = 4400
	_add_foundation_snap_points(data)
	return data


func _create_spiral_stairs() -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "spiral_stairs"
	data.display_name = "Spiral Stairs"
	data.description = "Elegant spiral staircase."
	data.category = BuildPieceData.Category.STAIRS
	data.material_type = BuildPieceData.MaterialType.STONE
	data.tier = 2
	data.resource_costs = {"stone": 15, "iron_ore": 8}
	data.dimensions = Vector3(2.0, 3.0, 2.0)
	data.structural_weight = 1.2
	data.seed_base = 4500
	_add_stair_snap_points(data)
	return data


# === Tier 3 Faction Pieces ===

func _add_faction_pieces() -> void:
	var factions := [
		{"id": 0, "name": "Castle", "color_name": "marble"},
		{"id": 1, "name": "Inferno", "color_name": "obsidian"},
		{"id": 2, "name": "Rampart", "color_name": "living_wood"},
		{"id": 3, "name": "Necropolis", "color_name": "bone"},
		{"id": 4, "name": "Tower", "color_name": "runic"},
		{"id": 5, "name": "Stronghold", "color_name": "rough"},
		{"id": 6, "name": "Fortress", "color_name": "swamp"},
		{"id": 7, "name": "Conflux", "color_name": "crystal"},
	]
	
	for faction in factions:
		_add_piece(_create_faction_wall(faction.id, faction.name, faction.color_name))
		_add_piece(_create_faction_floor(faction.id, faction.name, faction.color_name))
		_add_piece(_create_faction_door(faction.id, faction.name, faction.color_name))


func _create_faction_wall(faction_id: int, faction_name: String, color_name: String) -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "%s_wall" % color_name
	data.display_name = "%s Wall" % faction_name
	data.description = "A wall bearing the mark of %s." % faction_name
	data.category = BuildPieceData.Category.WALL
	data.material_type = BuildPieceData.MaterialType.FACTION_SPECIFIC
	data.tier = 3
	data.faction_id = faction_id
	data.required_reputation = 80
	data.resource_costs = {"faction_core": 1, "stone": 20}
	data.dimensions = Vector3(4.0, 3.0, 0.3)
	data.structural_weight = 2.5
	data.seed_base = 5000 + faction_id * 100
	_add_wall_snap_points(data)
	return data


func _create_faction_floor(faction_id: int, faction_name: String, color_name: String) -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "%s_floor" % color_name
	data.display_name = "%s Floor" % faction_name
	data.description = "Flooring in the style of %s." % faction_name
	data.category = BuildPieceData.Category.FLOOR
	data.material_type = BuildPieceData.MaterialType.FACTION_SPECIFIC
	data.tier = 3
	data.faction_id = faction_id
	data.required_reputation = 80
	data.resource_costs = {"faction_core": 1, "stone": 15}
	data.dimensions = Vector3(4.0, 0.2, 4.0)
	data.structural_weight = 2.0
	data.seed_base = 5010 + faction_id * 100
	_add_floor_snap_points(data)
	return data


func _create_faction_door(faction_id: int, faction_name: String, color_name: String) -> BuildPieceData:
	var data := BuildPieceData.new()
	data.piece_id = "%s_gate" % color_name
	data.display_name = "%s Gate" % faction_name
	data.description = "A grand gate of %s." % faction_name
	data.category = BuildPieceData.Category.DOOR
	data.material_type = BuildPieceData.MaterialType.FACTION_SPECIFIC
	data.tier = 3
	data.faction_id = faction_id
	data.required_reputation = 80
	data.resource_costs = {"faction_core": 1, "iron_ore": 10}
	data.dimensions = Vector3(1.5, 2.65, 0.2)
	data.structural_weight = 1.0
	data.seed_base = 5020 + faction_id * 100
	_add_door_snap_points(data)
	return data


# === Snap Point Helpers ===

func _add_wall_snap_points(data: BuildPieceData) -> void:
	var half_width := data.dimensions.x / 2.0
	var height := data.dimensions.y
	
	# Side edges - connect to other walls horizontally
	data.add_snap_point(Vector3(-half_width, height / 2, 0), Vector3(-1, 0, 0), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	data.add_snap_point(Vector3(half_width, height / 2, 0), Vector3(1, 0, 0), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	
	# Top surface - connect to roof or upper floor
	data.add_snap_point(Vector3(0, height, 0), Vector3(0, 1, 0), 
			BuildPieceData.SnapType.SURFACE, [BuildPieceData.SnapType.SURFACE, BuildPieceData.SnapType.FLOOR_EDGE])
	
	# Bottom - attaches to floor edges (WALL_BOTTOM connects to FLOOR_EDGE)
	data.add_snap_point(Vector3(0, 0, 0), Vector3(0, -1, 0), 
			BuildPieceData.SnapType.WALL_BOTTOM, [BuildPieceData.SnapType.FLOOR_EDGE, BuildPieceData.SnapType.SURFACE])


func _add_floor_snap_points(data: BuildPieceData) -> void:
	var half_size := data.dimensions.x / 2.0
	var floor_height := data.dimensions.y  # Floor thickness
	
	# Side edges - for connecting floors horizontally
	data.add_snap_point(Vector3(-half_size, 0, 0), Vector3(-1, 0, 0), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	data.add_snap_point(Vector3(half_size, 0, 0), Vector3(1, 0, 0), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	data.add_snap_point(Vector3(0, 0, -half_size), Vector3(0, 0, -1), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	data.add_snap_point(Vector3(0, 0, half_size), Vector3(0, 0, 1), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	
	# Floor edges where walls can attach (on top surface at edges)
	# These have upward-pointing normals and are positioned at the top of the floor
	data.add_snap_point(Vector3(-half_size, floor_height, 0), Vector3(-1, 0, 0), 
			BuildPieceData.SnapType.FLOOR_EDGE, [BuildPieceData.SnapType.WALL_BOTTOM])
	data.add_snap_point(Vector3(half_size, floor_height, 0), Vector3(1, 0, 0), 
			BuildPieceData.SnapType.FLOOR_EDGE, [BuildPieceData.SnapType.WALL_BOTTOM])
	data.add_snap_point(Vector3(0, floor_height, -half_size), Vector3(0, 0, -1), 
			BuildPieceData.SnapType.FLOOR_EDGE, [BuildPieceData.SnapType.WALL_BOTTOM])
	data.add_snap_point(Vector3(0, floor_height, half_size), Vector3(0, 0, 1), 
			BuildPieceData.SnapType.FLOOR_EDGE, [BuildPieceData.SnapType.WALL_BOTTOM])
	
	# Corners for diagonal connections
	data.add_snap_point(Vector3(-half_size, 0, -half_size), Vector3(-1, 0, -1).normalized(), 
			BuildPieceData.SnapType.CORNER, [BuildPieceData.SnapType.CORNER])
	data.add_snap_point(Vector3(half_size, 0, -half_size), Vector3(1, 0, -1).normalized(), 
			BuildPieceData.SnapType.CORNER, [BuildPieceData.SnapType.CORNER])
	data.add_snap_point(Vector3(-half_size, 0, half_size), Vector3(-1, 0, 1).normalized(), 
			BuildPieceData.SnapType.CORNER, [BuildPieceData.SnapType.CORNER])
	data.add_snap_point(Vector3(half_size, 0, half_size), Vector3(1, 0, 1).normalized(), 
			BuildPieceData.SnapType.CORNER, [BuildPieceData.SnapType.CORNER])


func _add_door_snap_points(data: BuildPieceData) -> void:
	data.add_snap_point(Vector3(0, 0, 0), Vector3(0, -1, 0), 
			BuildPieceData.SnapType.DOOR_FRAME, [BuildPieceData.SnapType.SURFACE])


func _add_foundation_snap_points(data: BuildPieceData) -> void:
	var half_size := data.dimensions.x / 2.0
	var height := data.dimensions.y
	
	data.add_snap_point(Vector3(0, height, 0), Vector3(0, 1, 0), 
			BuildPieceData.SnapType.SURFACE, [BuildPieceData.SnapType.SURFACE])
	data.add_snap_point(Vector3(-half_size, height, 0), Vector3(-1, 0, 0), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	data.add_snap_point(Vector3(half_size, height, 0), Vector3(1, 0, 0), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	data.add_snap_point(Vector3(0, height, -half_size), Vector3(0, 0, -1), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	data.add_snap_point(Vector3(0, height, half_size), Vector3(0, 0, 1), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])


func _add_stair_snap_points(data: BuildPieceData) -> void:
	var height := data.dimensions.y
	
	data.add_snap_point(Vector3(0, 0, 0), Vector3(0, -1, 0), 
			BuildPieceData.SnapType.SURFACE, [BuildPieceData.SnapType.SURFACE])
	data.add_snap_point(Vector3(0, height, 0), Vector3(0, 1, 0), 
			BuildPieceData.SnapType.SURFACE, [BuildPieceData.SnapType.SURFACE])


func _add_angled_wall_snap_points(data: BuildPieceData, angle: float) -> void:
	var half_width := data.dimensions.x / 2.0
	var height := data.dimensions.y
	var angle_rad := deg_to_rad(angle)
	var cos_a := cos(angle_rad)
	var sin_a := sin(angle_rad)
	
	# Transform snap point positions based on angle
	var left_pos := Vector3(-half_width * cos_a, height / 2, -half_width * sin_a)
	var right_pos := Vector3(half_width * cos_a, height / 2, half_width * sin_a)
	var left_normal := Vector3(-cos_a, 0, -sin_a).normalized()
	var right_normal := Vector3(cos_a, 0, sin_a).normalized()
	
	data.add_snap_point(left_pos, left_normal, 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	data.add_snap_point(right_pos, right_normal, 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	data.add_snap_point(Vector3(0, height, 0), Vector3(0, 1, 0), 
			BuildPieceData.SnapType.SURFACE, [BuildPieceData.SnapType.SURFACE])
	data.add_snap_point(Vector3(0, 0, 0), Vector3(0, -1, 0), 
			BuildPieceData.SnapType.SURFACE, [BuildPieceData.SnapType.SURFACE])


func _add_corner_snap_points(data: BuildPieceData, is_inner: bool) -> void:
	var height := data.dimensions.y
	var size := data.dimensions.x
	
	if is_inner:
		# Inner corner: snap points facing outward on both edges
		data.add_snap_point(Vector3(size, height / 2, 0), Vector3(1, 0, 0), 
				BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
		data.add_snap_point(Vector3(0, height / 2, size), Vector3(0, 0, 1), 
				BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	else:
		# Outer corner: snap points facing inward on both edges
		data.add_snap_point(Vector3(-size, height / 2, 0), Vector3(-1, 0, 0), 
				BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
		data.add_snap_point(Vector3(0, height / 2, -size), Vector3(0, 0, -1), 
				BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
	
	# Top and bottom snap points
	data.add_snap_point(Vector3(0, height, 0), Vector3(0, 1, 0), 
			BuildPieceData.SnapType.SURFACE, [BuildPieceData.SnapType.SURFACE])
	data.add_snap_point(Vector3(0, 0, 0), Vector3(0, -1, 0), 
			BuildPieceData.SnapType.SURFACE, [BuildPieceData.SnapType.SURFACE])


func _add_ramp_snap_points(data: BuildPieceData) -> void:
	var height := data.dimensions.y
	var length := data.dimensions.z
	
	# Bottom snap: flat surface connection
	data.add_snap_point(Vector3(0, 0, 0), Vector3(0, -1, 0), 
			BuildPieceData.SnapType.SURFACE, [BuildPieceData.SnapType.SURFACE])
	# Top snap: elevated surface connection
	data.add_snap_point(Vector3(0, height, length), Vector3(0, 1, 0), 
			BuildPieceData.SnapType.SURFACE, [BuildPieceData.SnapType.SURFACE])
	# Front snap at top
	data.add_snap_point(Vector3(0, height / 2, length), Vector3(0, 0, 1), 
			BuildPieceData.SnapType.EDGE, [BuildPieceData.SnapType.EDGE])
