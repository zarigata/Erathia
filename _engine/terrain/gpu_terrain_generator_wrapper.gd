extends VoxelGeneratorScript
## GPU Terrain Generator Wrapper
##
## Bridges CPU-side generator hooks with an optional GPU-based terrain shader generator.
## Falls back gracefully when the GPU path is unavailable so CPU terrain can still run.
## Emits chunk_generated for biome tagging so vegetation and other systems can subscribe.

signal chunk_generated(origin: Vector3i, biome_id: int)

const MAT_AIR: int = 0
const MAT_DIRT: int = 1
const MAT_STONE: int = 2
const MAT_IRON_ORE: int = 3
const MAT_SAND: int = 4
const MAT_SNOW: int = 5
const MAT_GRASS: int = 6

const WORLD_SIZE: float = 16000.0
const MAP_SIZE: float = 2048.0
const HALF_WORLD: float = WORLD_SIZE * 0.5
const WORLD_TO_MAP: float = WORLD_SIZE / MAP_SIZE # 7.8125

var _shader_generator: Resource = null
var _biome_map_image: Image = null
var _biome_mutex: Mutex = Mutex.new()
var _emission_count: int = 0
var _world_seed: int = 0


func _init() -> void:
	_load_shader_generator()
	_load_initial_biome_map()


func _load_shader_generator() -> void:
	if not ClassDB.class_exists("VoxelGeneratorShader"):
		push_warning("[GPUWrapper] VoxelGeneratorShader class not available; GPU path disabled.")
		return
	if not ResourceLoader.exists("res://_engine/terrain/biome_gpu_generator.tres"):
		push_warning("[GPUWrapper] biome_gpu_generator.tres missing; GPU path disabled.")
		return
	var loaded := ResourceLoader.load("res://_engine/terrain/biome_gpu_generator.tres")
	if loaded is Resource:
		_shader_generator = loaded
	else:
		_shader_generator = null
		push_warning("[GPUWrapper] Failed to load biome_gpu_generator.tres; GPU path disabled.")


func _load_initial_biome_map() -> void:
	var image: Image = null
	
	# Prefer user override image if present
	var user_image := Image.new()
	if user_image.load("user://world_map.png") == OK:
		image = user_image
	else:
		# Use imported texture (export-safe) and grab its image
		var tex := ResourceLoader.load("res://_assets/world_map.png") as Texture2D
		if tex:
			image = tex.get_image()
	
	if image and image.is_compressed():
		image.decompress()
	
	_biome_map_image = image


func is_gpu_available() -> bool:
	if _shader_generator == null:
		return false
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	return rd != null


func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES)


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if _shader_generator:
		_shader_generator.generate_block(out_buffer, origin, lod)
	if lod != 0:
		return
	var biome_id: int = _sample_biome_at_center(origin, out_buffer.get_size(), lod)
	chunk_generated.emit(origin, biome_id)
	if _emission_count < 10:
		_emission_count += 1
		print("[GPUWrapper] chunk_generated #%d origin=%s biome=%d" % [_emission_count, origin, biome_id])


func _sample_biome_at_center(origin: Vector3i, block_size: Vector3i, lod: int) -> int:
	_biome_mutex.lock()
	var image: Image = _biome_map_image
	_biome_mutex.unlock()
	if image == null:
		return 0
	if image.is_compressed():
		image.decompress()
	var lod_scale: int = 1 << lod
	var center := Vector3(
		origin.x + float(block_size.x * lod_scale) * 0.5,
		origin.y + float(block_size.y * lod_scale) * 0.5,
		origin.z + float(block_size.z * lod_scale) * 0.5
	)
	var px: int = int(clamp((center.x + HALF_WORLD) / WORLD_TO_MAP, 0.0, MAP_SIZE - 1.0))
	var py: int = int(clamp((center.z + HALF_WORLD) / WORLD_TO_MAP, 0.0, MAP_SIZE - 1.0))
	_biome_mutex.lock()
	var color := image.get_pixel(px, py)
	_biome_mutex.unlock()
	return int(color.r * 255.0)


func update_biome_texture(texture: Image) -> void:
	if texture == null:
		return
	_biome_mutex.lock()
	var copy := texture.duplicate()
	if copy.is_compressed():
		copy.decompress()
	_biome_map_image = copy
	var image_texture := ImageTexture.create_from_image(copy)
	if _shader_generator:
		_shader_generator.set("shader_parameters/biome_map", image_texture)
	_biome_mutex.unlock()


func update_seed(new_seed: int) -> void:
	_world_seed = new_seed
	# VoxelGeneratorShader uniforms are baked in the resource; keeping seed for parity.
