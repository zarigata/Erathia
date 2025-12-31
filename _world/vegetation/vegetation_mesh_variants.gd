extends Resource
class_name VegetationMeshVariants

## Stores prebaked mesh variants for a biome/type/seed combination.
## Allows ResourceSaver/Loader to serialize mesh arrays to user:// cache.
## Each element is an ArrayMesh representing a unique variant at LOD0.

@export var meshes: Array[ArrayMesh] = []
@export var biome_id: int = 0
@export var type_name: String = ""
@export var world_seed: int = 0
