extends VoxelGenerator
class_name NativeVoxelGeneratorBridge

## GDScript bridge that connects NativeTerrainGenerator (C++) to VoxelLodTerrain
## This allows the native GPU-accelerated generator to work with godot_voxel

var native_generator: NativeTerrainGenerator

func _init():
	native_generator = NativeTerrainGenerator.new()

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	if native_generator:
		native_generator.generate_block(out_buffer, origin_in_voxels, lod)

func _get_used_channels_mask() -> int:
	if native_generator:
		return native_generator.get_used_channels_mask()
	return 0

# Configuration methods
func set_world_seed(seed: int) -> void:
	if native_generator:
		native_generator.set_world_seed(seed)

func set_chunk_size(size: int) -> void:
	if native_generator:
		native_generator.set_chunk_size(size)

func set_world_size(size: float) -> void:
	if native_generator:
		native_generator.set_world_size(size)

func set_sea_level(level: float) -> void:
	if native_generator:
		native_generator.set_sea_level(level)

func set_blend_dist(dist: float) -> void:
	if native_generator:
		native_generator.set_blend_dist(dist)

func initialize_gpu() -> bool:
	if native_generator:
		return native_generator.initialize_gpu()
	return false

func get_gpu_status() -> String:
	if native_generator:
		return native_generator.get_gpu_status()
	return "No native generator"

func set_player_position(position: Vector3) -> void:
	if native_generator:
		native_generator.set_player_position(position)
