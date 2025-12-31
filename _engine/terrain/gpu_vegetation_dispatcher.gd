extends RefCounted
class_name GPUVegetationDispatcher
## GPUVegetationDispatcher
##
## Executes vegetation_placement.compute to generate vegetation placements fully on GPU.
## Caches placements per chunk and exposes a ready/fallback check for CPU mode.

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _placement_cache: Dictionary = {}  # Vector3i -> Dictionary(veg_type -> Array[Dictionary])
var _mutex: Mutex = Mutex.new()
var _terrain_dispatcher: BiomeMapGPUDispatcher
var _last_placement_time_us: int = 0
var _total_placement_time_us: int = 0
var _placement_call_count: int = 0
var _timing_per_type: Dictionary = {}

const MAX_PLACEMENTS: int = 4096
const CHUNK_SIZE: int = 32


func _init() -> void:
	_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		push_error("[GPUVegetationDispatcher] Failed to create RenderingDevice")
		return
	
	var shader_src := FileAccess.get_file_as_string("res://_engine/terrain/vegetation_placement.compute")
	if shader_src.is_empty():
		push_error("[GPUVegetationDispatcher] Failed to read vegetation_placement.compute")
		return
	
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, shader_src)
	
	var spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(src)
	if not spirv:
		push_error("[GPUVegetationDispatcher] Shader compile returned null SPIR-V")
		return
	
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		push_error("[GPUVegetationDispatcher] Failed to create compute pipeline")


func set_terrain_dispatcher(dispatcher: BiomeMapGPUDispatcher) -> void:
	_terrain_dispatcher = dispatcher


func is_ready() -> bool:
	if not _rd:
		return false
	if not _shader.is_valid() or not _pipeline.is_valid():
		return false
	var list := _rd.compute_list_begin()
	if list == 0:
		return false
	_rd.compute_list_end()
	return true


func clear_cache() -> void:
	_mutex.lock()
	_placement_cache.clear()
	_mutex.unlock()


func is_chunk_ready(chunk_origin: Vector3i, veg_type: int = -1) -> bool:
	_mutex.lock()
	var ready := false
	if _placement_cache.has(chunk_origin):
		if veg_type == -1:
			ready = true
		else:
			var per_chunk: Dictionary = _placement_cache.get(chunk_origin, {})
			ready = per_chunk.has(veg_type)
	_mutex.unlock()
	return ready


func generate_placements(
	chunk_origin: Vector3i,
	veg_type: int,
	density: float,
	grid_spacing: float,
	noise_frequency: float,
	slope_max: float,
	height_range: Dictionary,
	world_seed: int,
	biome_map_texture: RID
) -> Array[Dictionary]:
	var grid_steps: int = int(ceil(float(CHUNK_SIZE) / max(grid_spacing, 0.001)))
	var workgroups: int = int(ceil(float(grid_steps) / 8.0))
	workgroups = maxi(workgroups, 1)
	# Cache check (per chunk + vegetation type)
	_mutex.lock()
	if _placement_cache.has(chunk_origin):
		var per_chunk: Dictionary = _placement_cache.get(chunk_origin, {})
		if per_chunk.has(veg_type):
			var cached: Array[Dictionary] = per_chunk[veg_type]
			_mutex.unlock()
			return cached
	_mutex.unlock()
	
	if not _terrain_dispatcher:
		push_warning("[GPUVegetationDispatcher] Missing terrain dispatcher reference")
		return []
	
	var terrain_sdf := _terrain_dispatcher.get_sdf_texture_for_chunk(chunk_origin)
	if not terrain_sdf.is_valid():
		return []
	
	if not biome_map_texture.is_valid():
		return []
	
	# Create output buffer (std430 vec3 aligns to 16 bytes -> stride 48 per PlacementData)
	var buffer_bytes := PackedByteArray()
	buffer_bytes.resize(4 + MAX_PLACEMENTS * 48)
	var buffer := _rd.storage_buffer_create(buffer_bytes.size(), buffer_bytes)
	
	var uniform_sdf := RDUniform.new()
	uniform_sdf.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform_sdf.binding = 0
	uniform_sdf.add_id(terrain_sdf)
	
	var uniform_biome := RDUniform.new()
	uniform_biome.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform_biome.binding = 1
	uniform_biome.add_id(biome_map_texture)
	
	var uniform_out := RDUniform.new()
	uniform_out.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_out.binding = 2
	uniform_out.add_id(buffer)
	
	var uniform_set := _rd.uniform_set_create([uniform_sdf, uniform_biome, uniform_out], _shader, 0)
	
	var push_pc := PackedByteArray()
	push_pc.resize(14 * 4)
	push_pc.encode_float(0, chunk_origin.x)
	push_pc.encode_float(4, chunk_origin.y)
	push_pc.encode_float(8, chunk_origin.z)
	push_pc.encode_float(12, grid_spacing)
	push_pc.encode_s32(16, CHUNK_SIZE)
	push_pc.encode_s32(20, grid_steps)
	push_pc.encode_u32(24, int(world_seed))
	push_pc.encode_s32(28, veg_type)
	push_pc.encode_float(32, density)
	push_pc.encode_float(36, noise_frequency)
	push_pc.encode_float(40, slope_max)
	push_pc.encode_float(44, height_range.get("min", -100.0))
	push_pc.encode_float(48, height_range.get("max", 500.0))
	# padding at 52-55 unused to keep alignment (std430 already explicit)
	
	var start_time := Time.get_ticks_usec()
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, push_pc, push_pc.size())
	_rd.compute_list_dispatch(compute_list, workgroups, 1, workgroups)
	_rd.compute_list_end()
	_rd.submit()
	
	# Wait for completion (synchronous for now)
	_rd.sync()
	var end_time := Time.get_ticks_usec()
	_last_placement_time_us = end_time - start_time
	_total_placement_time_us += _last_placement_time_us
	_placement_call_count += 1
	if not _timing_per_type.has(veg_type):
		_timing_per_type[veg_type] = {"total_us": 0, "count": 0}
	var entry: Dictionary = _timing_per_type[veg_type]
	entry.total_us = int(entry.get("total_us", 0)) + _last_placement_time_us
	entry.count = int(entry.get("count", 0)) + 1
	_timing_per_type[veg_type] = entry
	
	# Read back buffer
	var data := _rd.buffer_get_data(buffer)
	if data.is_empty():
		return []
	
	# Decode placements
	var placements: Array[Dictionary] = []
	var placement_count := data.decode_u32(0)
	placement_count = min(placement_count, MAX_PLACEMENTS)
	
	var cursor := 4
	for _i in range(placement_count):
		if cursor + 48 > data.size():
			break
		
		var pos_x := data.decode_float(cursor); cursor += 4
		var pos_y := data.decode_float(cursor); cursor += 4
		var pos_z := data.decode_float(cursor); cursor += 4
		cursor += 4 # padding for vec3 std430
		var n_x := data.decode_float(cursor); cursor += 4
		var n_y := data.decode_float(cursor); cursor += 4
		var n_z := data.decode_float(cursor); cursor += 4
		cursor += 4 # padding for vec3 std430
		var variant_index := data.decode_u32(cursor); cursor += 4
		var instance_seed := data.decode_u32(cursor); cursor += 4
		var scale := data.decode_float(cursor); cursor += 4
		var rot_y := data.decode_float(cursor); cursor += 4
		
		# Skip potential padding to align next struct
		cursor = 4 + (_i + 1) * 48
		
		placements.append({
			"position": Vector3(pos_x, pos_y, pos_z),
			"normal": Vector3(n_x, n_y, n_z),
			"variant_index": int(variant_index),
			"instance_seed": int(instance_seed),
			"scale": scale,
			"rotation_y": rot_y
		})
	
	# Store in cache keyed by chunk and vegetation type
	_mutex.lock()
	if not _placement_cache.has(chunk_origin):
		_placement_cache[chunk_origin] = {}
	var per_chunk: Dictionary = _placement_cache.get(chunk_origin, {})
	per_chunk[veg_type] = placements
	_placement_cache[chunk_origin] = per_chunk
	_mutex.unlock()
	
	return placements


func get_last_placement_time_ms() -> float:
	return _last_placement_time_us / 1000.0


func get_average_placement_time_ms() -> float:
	if _placement_call_count == 0:
		return 0.0
	return float(_total_placement_time_us) / float(_placement_call_count) / 1000.0


func get_total_placement_calls() -> int:
	return _placement_call_count


func get_timing_per_type_ms() -> Dictionary:
	var result := {}
	for key in _timing_per_type.keys():
		var entry: Dictionary = _timing_per_type[key]
		var count: int = entry.get("count", 0)
		var total_us: int = entry.get("total_us", 0)
		var avg_ms := 0.0
		if count > 0:
			avg_ms = float(total_us) / float(count) / 1000.0
		result[key] = {
			"avg_ms": avg_ms,
			"total_ms": float(total_us) / 1000.0,
			"count": count
		}
	return result


func reset_timing_stats() -> void:
	_last_placement_time_us = 0
	_total_placement_time_us = 0
	_placement_call_count = 0
	_timing_per_type.clear()
