class_name TerrainManager
extends Node3D

const VIEW_DISTANCE_XZ = 12 # Chunks (12 * 16 = 192 blocks each direction)
const VIEW_DISTANCE_Y = 4
const UNLOAD_DISTANCE_XZ = 14 # Unload chunks beyond this distance
const CHUNK_SIZE = 16 # Must match Chunk.CHUNK_SIZE
const CHUNKS_PER_FRAME = 6 # Limit chunk generation per frame for performance

var noise: FastNoiseLite
var chunks: Dictionary = {} # Vector3i -> Chunk
var player: Node3D
var biome_manager: BiomeManager
var _chunks_to_generate: Array[Vector3i] = []
var _last_player_chunk: Vector3i = Vector3i.ZERO

func _ready():
	biome_manager = BiomeManager.new()
	
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.01

func _process(_delta: float) -> void:
	if not player:
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			player = players[0]
		return
		
	var player_pos: Vector3 = player.global_position
	var player_chunk: Vector3i = Vector3i(
		int(floor(player_pos.x / CHUNK_SIZE)),
		int(floor(player_pos.y / CHUNK_SIZE)),
		int(floor(player_pos.z / CHUNK_SIZE))
	)
	
	# Only update chunk list when player moves to new chunk
	if player_chunk != _last_player_chunk:
		_last_player_chunk = player_chunk
		_queue_chunks_around(player_chunk)
		_unload_far_chunks(player_chunk)
	
	# Generate queued chunks (limited per frame)
	_process_chunk_queue()

func _queue_chunks_around(center_chunk: Vector3i) -> void:
	# Build list of chunks sorted by distance (closest first)
	var needed_chunks: Array[Vector3i] = []
	
	for x in range(center_chunk.x - VIEW_DISTANCE_XZ, center_chunk.x + VIEW_DISTANCE_XZ + 1):
		for z in range(center_chunk.z - VIEW_DISTANCE_XZ, center_chunk.z + VIEW_DISTANCE_XZ + 1):
			for y in range(center_chunk.y - VIEW_DISTANCE_Y, center_chunk.y + VIEW_DISTANCE_Y + 1):
				if y < -4 or y > 8:
					continue
				
				var chunk_pos := Vector3i(x, y, z)
				if not chunks.has(chunk_pos) and not _chunks_to_generate.has(chunk_pos):
					needed_chunks.append(chunk_pos)
	
	# Sort by distance to player (prioritize closer chunks)
	needed_chunks.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var dist_a := (Vector3(a) - Vector3(center_chunk)).length_squared()
		var dist_b := (Vector3(b) - Vector3(center_chunk)).length_squared()
		return dist_a < dist_b
	)
	
	_chunks_to_generate.append_array(needed_chunks)

func _process_chunk_queue() -> void:
	var generated := 0
	while generated < CHUNKS_PER_FRAME and _chunks_to_generate.size() > 0:
		var chunk_pos: Vector3i = _chunks_to_generate.pop_front()
		if not chunks.has(chunk_pos):
			_spawn_chunk(chunk_pos)
			generated += 1

func _unload_far_chunks(center_chunk: Vector3i) -> void:
	var chunks_to_remove: Array[Vector3i] = []
	
	for chunk_pos: Vector3i in chunks.keys():
		var dx := absi(chunk_pos.x - center_chunk.x)
		var dy := absi(chunk_pos.y - center_chunk.y)
		var dz := absi(chunk_pos.z - center_chunk.z)
		
		if dx > UNLOAD_DISTANCE_XZ or dz > UNLOAD_DISTANCE_XZ or dy > VIEW_DISTANCE_Y + 2:
			chunks_to_remove.append(chunk_pos)
	
	for chunk_pos in chunks_to_remove:
		var chunk: Chunk = chunks[chunk_pos]
		chunks.erase(chunk_pos)
		chunk.queue_free()

func _spawn_chunk(pos: Vector3i):
	var chunk = Chunk.new(noise, pos, biome_manager)
	add_child(chunk)
	chunk.global_position = Vector3(pos.x * CHUNK_SIZE, pos.y * CHUNK_SIZE, pos.z * CHUNK_SIZE)
	chunk.generate_chunk()
	chunks[pos] = chunk

func modify_terrain(global_pos: Vector3, amount: float):
	var radius = 2.5
	var min_chunk = Vector3i(
		int(floor((global_pos.x - radius) / CHUNK_SIZE)),
		int(floor((global_pos.y - radius) / CHUNK_SIZE)),
		int(floor((global_pos.z - radius) / CHUNK_SIZE))
	)
	var max_chunk = Vector3i(
		int(floor((global_pos.x + radius) / CHUNK_SIZE)),
		int(floor((global_pos.y + radius) / CHUNK_SIZE)),
		int(floor((global_pos.z + radius) / CHUNK_SIZE))
	)
	
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			for z in range(min_chunk.z, max_chunk.z + 1):
				var cpos = Vector3i(x, y, z)
				if chunks.has(cpos):
					var local_pos = global_pos - chunks[cpos].global_position
					chunks[cpos].modify_sphere(local_pos, radius, amount)

func get_material_at(global_pos: Vector3) -> int:
	var chunk_pos = Vector3i(
		int(floor(global_pos.x / CHUNK_SIZE)),
		int(floor(global_pos.y / CHUNK_SIZE)),
		int(floor(global_pos.z / CHUNK_SIZE))
	)
	
	if chunks.has(chunk_pos):
		# Convert to local 0-based coords
		var local_pos = global_pos - chunks[chunk_pos].global_position
		# The Chunk internal storage expects 0-based index for access methods?
		# Actually _get_material expects buffered index (0..DATA_SIZE).
		# Local pos 0,0,0 corresponds to buffer index 1,1,1 due to padding
		var bx = int(local_pos.x) + 1
		var by = int(local_pos.y) + 1
		var bz = int(local_pos.z) + 1
		
		# We need to expose _get_material as public or make a public wrapper
		# For now, let's assume we can access it or duplicate logic.
		# Ideally Chunk should have `get_material_local(vec3)`.
		# Let's fix Chunk first or do direct access if GDScript allows (it does).
		return chunks[chunk_pos]._get_material(bx, by, bz)
	
	return MiningSystem.MaterialID.AIR

func smooth_terrain(global_pos: Vector3, radius: float):
	var chunk_pos = Vector3i(
		int(floor(global_pos.x / CHUNK_SIZE)),
		int(floor(global_pos.y / CHUNK_SIZE)),
		int(floor(global_pos.z / CHUNK_SIZE))
	)
	
	# For smoothing, we mostly care about the center chunk for now
	if chunks.has(chunk_pos):
		var local_pos = global_pos - chunks[chunk_pos].global_position
		TerrainEditSystem.smooth_terrain(chunks[chunk_pos], local_pos, radius)

func flatten_terrain(global_pos: Vector3, radius: float, target_height: float):
	var chunk_pos = Vector3i(
		int(floor(global_pos.x / CHUNK_SIZE)),
		int(floor(global_pos.y / CHUNK_SIZE)),
		int(floor(global_pos.z / CHUNK_SIZE))
	)
	
	if chunks.has(chunk_pos):
		var local_pos = global_pos - chunks[chunk_pos].global_position
		TerrainEditSystem.flatten_terrain(chunks[chunk_pos], local_pos, radius, target_height)
