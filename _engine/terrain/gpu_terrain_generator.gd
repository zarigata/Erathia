@tool
extends VoxelGeneratorScript
class_name GPUTerrainGenerator

signal chunk_generated(origin: Vector3i, biome_id: int)

var _gpu_dispatcher: BiomeMapGPUDispatcher
var _world_seed: int = 0
var _biome_map_image: Image

const MAT_AIR: int = 0
const MAT_DIRT: int = 1
const MAT_STONE: int = 2
const MAT_IRON_ORE: int = 3
const MAT_SAND: int = 4
const MAT_SNOW: int = 5
const MAT_GRASS: int = 6

const CHUNK_SIZE: int = 32


func _init() -> void:
	_gpu_dispatcher = BiomeMapGPUDispatcher.new()
	_load_biome_map()


func is_gpu_available() -> bool:
	return _gpu_dispatcher != null and _gpu_dispatcher.is_ready()


func _load_biome_map() -> void:
	var map_path := "user://world_map.png"
	if not FileAccess.file_exists(map_path):
		map_path = "res://_assets/world_map.png"
	
	if FileAccess.file_exists(map_path):
		_biome_map_image = Image.load_from_file(map_path)
		_gpu_dispatcher.set_biome_map_texture(_biome_map_image)
		print("[GPUTerrainGenerator] Biome map loaded from %s" % map_path)
	else:
		push_warning("[GPUTerrainGenerator] Biome map not found; GPU generation disabled")


func update_seed(new_seed: int) -> void:
	_world_seed = new_seed
	if _gpu_dispatcher:
		_gpu_dispatcher.clear_cache()


func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES)


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if not is_gpu_available():
		return
	
	var block_size := out_buffer.get_size()
	var sdf_texture := _gpu_dispatcher.generate_chunk_sdf(origin, _world_seed)
	if not sdf_texture.is_valid():
		push_error("[GPUTerrainGenerator] Failed to generate SDF texture for chunk %s" % origin)
		return
	
	var sdf_data := _gpu_dispatcher.read_sdf_bulk(sdf_texture)
	if sdf_data.is_empty():
		push_error("[GPUTerrainGenerator] Empty SDF data for chunk %s" % origin)
		return
	
	for z in range(block_size.z):
		for y in range(block_size.y):
			for x in range(block_size.x):
				var index := (z * CHUNK_SIZE * CHUNK_SIZE + y * CHUNK_SIZE + x) * 4
				var sdf := sdf_data.decode_float(index)
				
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
				
				var material_id := MAT_STONE if sdf < 0.0 else MAT_AIR
				if sdf > -4.0 and sdf < 0.0:
					material_id = MAT_DIRT
				elif sdf <= -10.0:
					var ore_noise := randf()
					if ore_noise > 0.98:
						material_id = MAT_IRON_ORE
				
				out_buffer.set_voxel(material_id, x, y, z, VoxelBuffer.CHANNEL_INDICES)
	
	if lod == 0:
		var biome_id := _sample_biome_at_chunk(origin)
		chunk_generated.emit(origin, biome_id)


func _sample_biome_at_chunk(origin: Vector3i) -> int:
	if not _biome_map_image:
		return 0
	
	var center_x := origin.x + float(CHUNK_SIZE) * 0.5
	var center_z := origin.z + float(CHUNK_SIZE) * 0.5
	var pixel_x := int((center_x + 8000.0) / 7.8125)
	var pixel_y := int((center_z + 8000.0) / 7.8125)
	pixel_x = clampi(pixel_x, 0, _biome_map_image.get_width() - 1)
	pixel_y = clampi(pixel_y, 0, _biome_map_image.get_height() - 1)
	
	return int(_biome_map_image.get_pixel(pixel_x, pixel_y).r8)
