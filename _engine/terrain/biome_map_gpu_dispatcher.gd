extends Node
class_name BiomeMapGPUDispatcher

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _biome_map_texture: RID
var _sdf_cache: Dictionary = {}
var _mutex: Mutex = Mutex.new()

const CHUNK_SIZE: int = 32

func _init() -> void:
	_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		push_error("[BiomeMapGPUDispatcher] Failed to create RenderingDevice")
		return
	
	var shader_file := load("res://_engine/terrain/biome_gpu_sdf.compute") as RDShaderFile
	if not shader_file:
		push_error("[BiomeMapGPUDispatcher] Failed to load biome_gpu_sdf.compute")
		return
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(shader_spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		push_error("[BiomeMapGPUDispatcher] Failed to create compute pipeline")


func set_biome_map_texture(texture: Image) -> void:
	if not _rd:
		return
	var format := RDTextureFormat.new()
	format.width = texture.get_width()
	format.height = texture.get_height()
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	
	_biome_map_texture = _rd.texture_create(format, RDTextureView.new(), [texture.get_data()])


func generate_chunk_sdf(chunk_origin: Vector3i, world_seed: int) -> RID:
	if not _rd or not _pipeline.is_valid() or not _biome_map_texture.is_valid():
		return RID()
	
	_mutex.lock()
	if _sdf_cache.has(chunk_origin):
		var cached_rid: RID = _sdf_cache[chunk_origin]
		_mutex.unlock()
		return cached_rid
	
	var format := RDTextureFormat.new()
	format.width = CHUNK_SIZE
	format.height = CHUNK_SIZE
	format.depth = CHUNK_SIZE
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	var sdf_texture := _rd.texture_create(format, RDTextureView.new(), [])
	
	var uniform_biome := RDUniform.new()
	uniform_biome.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform_biome.binding = 0
	uniform_biome.add_id(_biome_map_texture)
	
	var uniform_sdf := RDUniform.new()
	uniform_sdf.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_sdf.binding = 1
	uniform_sdf.add_id(sdf_texture)
	
	var uniform_set := _rd.uniform_set_create([uniform_biome, uniform_sdf], _shader, 0)
	
	var push_constant := PackedFloat32Array([
		chunk_origin.x, chunk_origin.y, chunk_origin.z,
		16000.0,
		0.0,
		0.2,
		CHUNK_SIZE,
		float(world_seed)
	])
	
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	_rd.compute_list_dispatch(compute_list, 8, 8, 8)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	
	_sdf_cache[chunk_origin] = sdf_texture
	_mutex.unlock()
	
	return sdf_texture


func read_sdf_value(sdf_texture: RID, local_pos: Vector3i) -> float:
	if not _rd:
		return 0.0
	var data := _rd.texture_get_data(sdf_texture, 0)
	var index := (local_pos.z * CHUNK_SIZE * CHUNK_SIZE + local_pos.y * CHUNK_SIZE + local_pos.x) * 4
	return data.decode_float(index)


func read_sdf_bulk(sdf_texture: RID) -> PackedByteArray:
	if not _rd:
		return PackedByteArray()
	return _rd.texture_get_data(sdf_texture, 0)


func clear_cache() -> void:
	_mutex.lock()
	for rid in _sdf_cache.values():
		_rd.free_rid(rid)
	_sdf_cache.clear()
	_mutex.unlock()


func is_ready() -> bool:
	return _rd != null and _pipeline.is_valid() and _shader.is_valid()
