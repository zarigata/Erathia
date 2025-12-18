extends Node3D

## Main scene initialization script
## Handles terrain system setup and TerrainEditSystem initialization

@export var terrain_path: NodePath = "VoxelLodTerrain"

var _terrain: VoxelLodTerrain


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as VoxelLodTerrain
	
	if _terrain:
		# Initialize TerrainEditSystem with the terrain reference
		if TerrainEditSystem:
			TerrainEditSystem.set_terrain(_terrain)
			print("[MainTerrainInit] TerrainEditSystem initialized with terrain")
		else:
			push_warning("[MainTerrainInit] TerrainEditSystem autoload not found")
	else:
		push_warning("[MainTerrainInit] VoxelLodTerrain not found at path: ", terrain_path)
