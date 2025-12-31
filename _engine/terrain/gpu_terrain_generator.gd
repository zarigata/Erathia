@tool
extends VoxelGeneratorScript
class_name GPUTerrainGenerator

signal chunk_generated(origin: Vector3i, biome_id: int)

var _gpu_dispatcher: BiomeMapGPUDispatcher
var _world_seed: int = 0
var _biome_map_image: Image
var _last_generation_time_us: int = 0
var _chunks_generated: int = 0
var _total_generation_time_us: int = 0
var debug_logging: bool = false

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
	if not _gpu_dispatcher:
		print_rich("[color=red][GPUTerrainGenerator] GPU dispatcher is null[/color]")
		return false
	if not _gpu_dispatcher.is_ready():
		print_rich("[color=red][GPUTerrainGenerator] GPU dispatcher not ready (check shader compilation)[/color]")
		return false
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		print_rich("[color=red][GPUTerrainGenerator] RenderingDevice unavailable[/color]")
		return false
	if rd.get_device_name() == "":
		print_rich("[color=red][GPUTerrainGenerator] GPU device name empty (driver issue?)[/color]")
		return false
	return true


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


func update_biome_texture(image: Image) -> void:
	## Update the GPU biome map texture and cache the image for sampling.
	## Ensures GPU dispatcher receives latest biome map produced by BiomeMapGeneratorGPU.
	if image == null:
		push_warning("[GPUTerrainGenerator] update_biome_texture called with null image")
		return
	
	_biome_map_image = image
	if _gpu_dispatcher:
		_gpu_dispatcher.set_biome_map_texture(image)


func update_seed(new_seed: int) -> void:
	_world_seed = new_seed
	if _gpu_dispatcher:
		_gpu_dispatcher.clear_cache()


func get_gpu_dispatcher() -> BiomeMapGPUDispatcher:
	"""Expose the internal GPU dispatcher for consumers needing GPU SDF textures."""
	return _gpu_dispatcher


func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES)


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if not is_gpu_available():
		return
	
	if debug_logging:
		print_rich("[color=cyan][GPUTerrainGenerator] Generating chunk at %s (LOD %d)[/color]" % [origin, lod])
	var start_time := Time.get_ticks_usec()
	var textures := _gpu_dispatcher.generate_chunk_sdf(origin, _world_seed)
	if textures.is_empty() or not textures.has("sdf") or not textures.has("material"):
		print_rich("[color=red][GPUTerrainGenerator] Texture generation failed for chunk %s[/color]" % origin)
		push_error("[GPUTerrainGenerator] Failed to generate textures for chunk %s" % origin)
		return

	var max_wait := 100
	var waited := 0
	while not _gpu_dispatcher.is_chunk_ready(origin) and waited < max_wait:
		OS.delay_msec(1)
		waited += 1
	
	if waited >= max_wait and debug_logging:
		print_rich("[color=yellow][GPUTerrainGenerator] Chunk %s generation timeout after %dms[/color]" % [origin, max_wait])
	if not _gpu_dispatcher.write_to_voxel_buffer(origin, out_buffer):
		push_error("[GPUTerrainGenerator] Failed to write chunk %s to VoxelBuffer" % origin)
		return
	
	if lod == 0:
		var biome_id := _sample_biome_at_chunk(origin)
		chunk_generated.emit(origin, biome_id)
	
	_last_generation_time_us = Time.get_ticks_usec() - start_time
	_total_generation_time_us += _last_generation_time_us
	_chunks_generated += 1
	if debug_logging:
		print_rich("[color=green][GPUTerrainGenerator] Chunk %s generated in %.2fms[/color]" % [origin, _last_generation_time_us / 1000.0])


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


func get_last_generation_time_ms() -> float:
	return _last_generation_time_us / 1000.0


func get_chunks_generated() -> int:
	return _chunks_generated


func get_average_generation_time_ms() -> float:
	if _chunks_generated == 0:
		return 0.0
	return float(_total_generation_time_us) / float(_chunks_generated) / 1000.0


func has_biome_texture() -> bool:
	return _biome_map_image != null


func get_gpu_status() -> Dictionary:
	return {
		"available": is_gpu_available(),
		"dispatcher_ready": _gpu_dispatcher != null and _gpu_dispatcher.is_ready(),
		"chunks_generated": _chunks_generated,
		"avg_time_ms": get_average_generation_time_ms(),
		"last_time_ms": get_last_generation_time_ms()
	}
