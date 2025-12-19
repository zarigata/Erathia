class_name BuildPieceData
extends Resource

enum Category {
	WALL,
	FLOOR,
	ROOF,
	DOOR,
	FOUNDATION,
	STAIRS
}

enum MaterialType {
	WOOD,
	STONE,
	METAL,
	FACTION_SPECIFIC
}

enum SnapType {
	EDGE,
	CORNER,
	SURFACE,
	DOOR_FRAME
}

@export_group("Metadata")
@export var piece_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var category: Category = Category.WALL

@export_group("Material")
@export var material_type: MaterialType = MaterialType.WOOD

@export_group("Crafting")
@export var tier: int = 0
@export var resource_costs: Dictionary = {}

@export_group("Faction")
@export var faction_id: int = -1
@export var required_reputation: int = 0

@export_group("Physical Properties")
@export var dimensions: Vector3 = Vector3(4.0, 3.0, 0.3)
@export var structural_weight: float = 1.0

@export_group("Mesh Generation")
@export var seed_base: int = 0
@export var lod_levels: int = 4

@export_group("Snap Points")
@export var snap_points: Array[Dictionary] = []


func add_snap_point(offset: Vector3, normal: Vector3, type: SnapType, compatible_types: Array[int] = []) -> void:
	snap_points.append({
		"offset": offset,
		"normal": normal,
		"type": type,
		"compatible_types": compatible_types
	})


func get_snap_points_by_type(type: SnapType) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point in snap_points:
		if point.get("type", -1) == type:
			result.append(point)
	return result


func get_total_resource_cost() -> int:
	var total: int = 0
	for resource_type in resource_costs:
		total += resource_costs[resource_type]
	return total


func _to_string() -> String:
	return "BuildPieceData<%s, Tier %d, %s>" % [piece_id, tier, Category.keys()[category]]
