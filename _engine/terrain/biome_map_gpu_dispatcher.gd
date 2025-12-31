extends Node
class_name BiomeMapGPUDispatcher

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _biome_map_texture: RID
var _sdf_cache: Dictionary = {}  # Vector3i -> {sdf: RID, material: RID}
var _mutex: Mutex = Mutex.new()
var _last_compute_time_us: int = 0
var _total_compute_time_us: int = 0
var _compute_call_count: int = 0

const CHUNK_SIZE: int = 32

func _init() -> void:
	print_rich("[color=cyan][BiomeMapGPUDispatcher] Initializing GPU dispatcher...[/color]")
	_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		print_rich("[color=red][BiomeMapGPUDispatcher] Failed to create local RenderingDevice[/color]")
		push_error("[BiomeMapGPUDispatcher] Failed to create RenderingDevice")
		return
	
	var shader_source := FileAccess.get_file_as_string("res://_engine/terrain/biome_gpu_sdf.compute")
	if shader_source.is_empty():
		print_rich("[color=red][BiomeMapGPUDispatcher] Failed to read biome_gpu_sdf.compute[/color]")
		push_error("[BiomeMapGPUDispatcher] Failed to read biome_gpu_sdf.compute")
		return
	print_rich("[color=cyan][BiomeMapGPUDispatcher] Shader source loaded (%d bytes)[/color]" % shader_source.length())
	var shader_source_obj := RDShaderSource.new()
	shader_source_obj.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	shader_source_obj.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, shader_source)
	var shader_spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(shader_source_obj)
	if not shader_spirv:
		print_rich("[color=red][BiomeMapGPUDispatcher] Shader compilation failed - check biome_gpu_sdf.compute syntax[/color]")
		push_error("[BiomeMapGPUDispatcher] Shader compile returned null SPIR-V")
		return
	_shader = _rd.shader_create_from_spirv(shader_spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		print_rich("[color=red][BiomeMapGPUDispatcher] Compute pipeline creation failed[/color]")
		push_error("[BiomeMapGPUDispatcher] Failed to create compute pipeline")
	else:
		print_rich("[color=green][BiomeMapGPUDispatcher] Initialization complete[/color]")


func set_biome_map_texture(texture: Image) -> void:
	if not _rd:
		return
	var img := texture
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var expected_size := img.get_width() * img.get_height() * 4
	if data.size() != expected_size:
		# Force rebuild as RGBA8 buffer
		img.convert(Image.FORMAT_RGBA8)
		data = img.get_data()
	var format := RDTextureFormat.new()
	format.width = img.get_width()
	format.height = img.get_height()
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	format.mipmaps = 1
	
	_biome_map_texture = _rd.texture_create(format, RDTextureView.new(), [data])


func generate_chunk_sdf(chunk_origin: Vector3i, world_seed: int) -> Dictionary:
	if not _rd:
		print_rich("[color=red][BiomeMapGPUDispatcher] RenderingDevice invalid[/color]")
		return {}
	if not _pipeline.is_valid():
		print_rich("[color=red][BiomeMapGPUDispatcher] Pipeline invalid[/color]")
		return {}
	if not _biome_map_texture.is_valid():
		print_rich("[color=red][BiomeMapGPUDispatcher] Biome map texture invalid[/color]")
		return {}
	
	_mutex.lock()
	if _sdf_cache.has(chunk_origin):
		var cached: Dictionary = _sdf_cache[chunk_origin] as Dictionary
		_mutex.unlock()
		return cached
	
	var sdf_format := RDTextureFormat.new()
	sdf_format.width = CHUNK_SIZE
	sdf_format.height = CHUNK_SIZE
	sdf_format.depth = CHUNK_SIZE
	sdf_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	sdf_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	sdf_format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	var sdf_texture := _rd.texture_create(sdf_format, RDTextureView.new(), [])

	var material_format := RDTextureFormat.new()
	material_format.width = CHUNK_SIZE
	material_format.height = CHUNK_SIZE
	material_format.depth = CHUNK_SIZE
	material_format.format = RenderingDevice.DATA_FORMAT_R32_UINT
	material_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	material_format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	var material_texture := _rd.texture_create(material_format, RDTextureView.new(), [])
	
	var uniform_biome := RDUniform.new()
	uniform_biome.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform_biome.binding = 0
	uniform_biome.add_id(_biome_map_texture)
	
	var uniform_sdf := RDUniform.new()
	uniform_sdf.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_sdf.binding = 1
	uniform_sdf.add_id(sdf_texture)
	
	var uniform_material := RDUniform.new()
	uniform_material.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_material.binding = 2
	uniform_material.add_id(material_texture)
	
	var uniform_set := _rd.uniform_set_create([uniform_biome, uniform_sdf, uniform_material], _shader, 0)
	
	var push_constant := PackedFloat32Array([
		chunk_origin.x, chunk_origin.y, chunk_origin.z,
		16000.0,
		0.0,
		0.2,
		CHUNK_SIZE,
		float(world_seed)
	])
	
	var start_time := Time.get_ticks_usec()
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	_rd.compute_list_dispatch(compute_list, 8, 8, 8)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	var end_time := Time.get_ticks_usec()
	_last_compute_time_us = end_time - start_time
	_total_compute_time_us += _last_compute_time_us
	_compute_call_count += 1
	
	_sdf_cache[chunk_origin] = {"sdf": sdf_texture, "material": material_texture}
	_mutex.unlock()
	
	return _sdf_cache[chunk_origin]


func is_chunk_ready(chunk_origin: Vector3i) -> bool:
	return _sdf_cache.has(chunk_origin)


func get_biome_map_texture() -> RID:
	"""Expose biome map texture RID for consumers needing sampling."""
	return _biome_map_texture


func get_sdf_texture_for_chunk(chunk_origin: Vector3i) -> RID:
	"""Return cached SDF texture RID for the given chunk, or invalid RID if missing."""
	_mutex.lock()
	if _sdf_cache.has(chunk_origin):
		var entry: Dictionary = _sdf_cache[chunk_origin]
		var rid: RID = entry.get("sdf", RID())
		_mutex.unlock()
		return rid
	_mutex.unlock()
	return RID()


func write_to_voxel_buffer(chunk_origin: Vector3i, out_buffer: VoxelBuffer) -> bool:
	if not _rd or not _sdf_cache.has(chunk_origin):
		return false
	var textures: Dictionary = _sdf_cache[chunk_origin]
	if not textures.has("sdf") or not textures.has("material"):
		return false

	var sdf_data := _rd.texture_get_data(textures.sdf, 0)
	var mat_data := _rd.texture_get_data(textures.material, 0)
	if sdf_data.is_empty() or mat_data.is_empty():
		return false

	for z in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				var idx := (z * CHUNK_SIZE * CHUNK_SIZE + y * CHUNK_SIZE + x) * 4
				var sdf := sdf_data.decode_float(idx)
				var mat := mat_data.decode_u32(idx)
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
				out_buffer.set_voxel(int(mat), x, y, z, VoxelBuffer.CHANNEL_INDICES)
	return true


func clear_cache() -> void:
	_mutex.lock()
	for entry in _sdf_cache.values():
		if entry is Dictionary:
			if entry.has("sdf"):
				_rd.free_rid(entry.sdf)
			if entry.has("material"):
				_rd.free_rid(entry.material)
	_sdf_cache.clear()
	_mutex.unlock()


func is_ready() -> bool:
	return _rd != null and _pipeline.is_valid() and _shader.is_valid()


func get_last_compute_time_ms() -> float:
	return _last_compute_time_us / 1000.0


func get_average_compute_time_ms() -> float:
	if _compute_call_count == 0:
		return 0.0
	return float(_total_compute_time_us) / float(_compute_call_count) / 1000.0


func get_total_chunks_generated() -> int:
	return _compute_call_count


func reset_timing_stats() -> void:
	_last_compute_time_us = 0
	_total_compute_time_us = 0
	_compute_call_count = 0
