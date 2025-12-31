extends Resource
class_name VegetationPositionData

## Stores prebaked vegetation positions for a biome/type/seed combination.
## Exists to allow ResourceSaver/Loader to serialize position arrays to user://.
## Loader and prebaker rely on this resource to exchange position data.

@export var positions: Array[Vector3] = []
@export var biome_id: int = 0
@export var type_name: String = ""
@export var world_seed: int = 0
