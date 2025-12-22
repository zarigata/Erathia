extends Node
class_name BiomeMapGenerator

signal map_generated(texture: Image)

const MAP_SIZE: int = 2048
const WORLD_SIZE: float = 16000.0
const BIOME_COUNT: int = 20
const CELL_SCALE: float = 800.0
const JITTER: float = 0.3

@export var auto_generate_on_ready: bool = true
@export var debug_save_path: String = "user://biome_gpu_map.png"
@export_range(400.0, 2000.0, 50.0) var cell_scale_override: float = CELL_SCALE
@export_range(0.0, 1.0, 0.05) var jitter_override: float = JITTER

var _regenerate_now := false
@export var regenerate_now := false:
	set = _set_regenerate_now, get = _get_regenerate_now

var _rd: RenderingDevice
var _shader: RID = RID()
var _pipeline: RID = RID()
var _output_texture: RID = RID()
var _output_format: RDTextureFormat
var _uniform_set: RID = RID()
var _current_seed: int = 0
var _compute_available: bool = false
var _init_warning_emitted: bool = false

func _ready() -> void:
	_initialize_device()
	var seed_manager := get_node_or_null("/root/WorldSeedManager")
	if seed_manager:
		seed_manager.seed_changed.connect(_on_seed_changed)
		if auto_generate_on_ready and _compute_available:
			call_deferred("generate_map", seed_manager.get_world_seed())
	elif auto_generate_on_ready and not _compute_available:
		push_warning("[BiomeMapGenerator] Compute unavailable; skipping auto generate")
	elif auto_generate_on_ready:
		push_warning("[BiomeMapGenerator] WorldSeedManager not found; manual generation only.")

func _exit_tree() -> void:
	if _rd:
		if _uniform_set.is_valid():
			_rd.free_rid(_uniform_set)
		if _output_texture.is_valid():
			_rd.free_rid(_output_texture)
		if _pipeline.is_valid():
			_rd.free_rid(_pipeline)
		if _shader.is_valid():
			_rd.free_rid(_shader)
		_rd.free()

func _initialize_device() -> void:
	if _compute_available:
		return
	if not ResourceLoader.exists("res://_engine/terrain/biome_map.compute"):
		if not _init_warning_emitted:
			push_warning("[BiomeMapGenerator] biome_map.compute missing; GPU biome map generation disabled")
			_init_warning_emitted = true
		return

	_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		push_error("[BiomeMapGenerator] Failed to create RenderingDevice")
		return

	var shader_file := load("res://_engine/terrain/biome_map.compute") as RDShaderFile
	if not shader_file:
		push_warning("[BiomeMapGenerator] Failed to load biome_map.compute; compute disabled")
		_rd.free()
		_rd = null
		return

	var shader_spirv := shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(shader_spirv)
	if not _shader.is_valid():
		push_warning("[BiomeMapGenerator] Shader compilation failed for biome_map.compute; compute disabled")
		_rd.free()
		_rd = null
		return
	
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		push_warning("[BiomeMapGenerator] Failed to create compute pipeline; compute disabled")
		_rd.free()
		_rd = null
		return

	_output_format = RDTextureFormat.new()
	_output_format.width = MAP_SIZE
	_output_format.height = MAP_SIZE
	_output_format.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	_output_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	_output_texture = _rd.texture_create(_output_format, RDTextureView.new())
	if not _output_texture.is_valid():
		push_warning("[BiomeMapGenerator] Failed to create output texture; compute disabled")
		_rd.free()
		_rd = null
		return

	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 1
	uniform.add_id(_output_texture)

	_uniform_set = _rd.uniform_set_create([uniform], _shader, 0)
	if not _uniform_set.is_valid():
		push_warning("[BiomeMapGenerator] Failed to create uniform set; compute disabled")
		_rd.free()
		_rd = null
		return
	
	_compute_available = true
	print("[BiomeMapGenerator] Initialized GPU compute pipeline")

func generate_map(seed: int) -> void:
	if not _compute_available or not _rd or not _pipeline.is_valid() or not _uniform_set.is_valid():
		if not _init_warning_emitted:
			push_warning("[BiomeMapGenerator] Compute unavailable; cannot generate map")
			_init_warning_emitted = true
		return

	_current_seed = seed
	var cell_scale := cell_scale_override
	var jitter := jitter_override

	var push_constants := PackedByteArray()
	push_constants.resize(20)
	push_constants.encode_s32(0, BIOME_COUNT)
	push_constants.encode_float(4, WORLD_SIZE)
	push_constants.encode_float(8, cell_scale)
	push_constants.encode_float(12, jitter)
	push_constants.encode_u32(16, seed)

	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, push_constants, 20)
	_rd.compute_list_dispatch(compute_list, MAP_SIZE / 8, MAP_SIZE / 8, 1)
	_rd.compute_list_end()

	var start_time := Time.get_ticks_msec()
	_rd.submit()
	_rd.sync()
	var elapsed_ms := float(Time.get_ticks_msec() - start_time)

	var byte_data := _rd.texture_get_data(_output_texture, 0)
	if byte_data.is_empty():
		push_error("[BiomeMapGenerator] Failed to read back texture data")
		return

	var output_image := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	for y in range(MAP_SIZE):
		for x in range(MAP_SIZE):
			var pixel_offset := (y * MAP_SIZE + x) * 8
			var biome_norm := byte_data.decode_float(pixel_offset)
			var dist_edge := byte_data.decode_float(pixel_offset + 4)

			var biome_byte := clampi(int(biome_norm * 255.0), 0, 255)
			var dist_byte := clampi(int(dist_edge * 255.0), 0, 255)
			output_image.set_pixel(x, y, Color8(biome_byte, dist_byte, 0))

	var save_path := debug_save_path
	output_image.save_png(save_path)
	map_generated.emit(output_image)

	print("[BiomeMapGenerator] Generating %dx%d biome map (seed=%d, cells=%.0f)" % [MAP_SIZE, MAP_SIZE, seed, WORLD_SIZE / cell_scale])
	print("[BiomeMapGenerator] Dispatching %dx%d workgroups" % [MAP_SIZE / 8, MAP_SIZE / 8])
	print("[BiomeMapGenerator] Map generated in %.2fms, saved to: %s" % [elapsed_ms, save_path])

func _on_seed_changed(new_seed: int) -> void:
	print("[BiomeMapGenerator] Regenerating map with seed: %d" % new_seed)
	generate_map(new_seed)

func _set_regenerate_now(value: bool) -> void:
	if value and _rd:
		generate_map(_current_seed)
	_regenerate_now = false

func _get_regenerate_now() -> bool:
	return _regenerate_now
