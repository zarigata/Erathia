class_name TerrainManager
extends Node3D

const VIEW_DISTANCE_XZ = 2 # Chunks
const VIEW_DISTANCE_Y = 2
const CHUNK_SIZE = 16 # Must match Chunk.CHUNK_SIZE

var noise: FastNoiseLite
var chunks = {} # Vector3i -> Chunk
var player: Node3D
var biome_manager: BiomeManager

func _ready():
	biome_manager = BiomeManager.new()
	
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.01

func _process(delta):
	if not player:
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			player = players[0]
		return
		
	var player_pos = player.global_position
	var player_chunk = Vector3i(
		int(floor(player_pos.x / CHUNK_SIZE)),
		int(floor(player_pos.y / CHUNK_SIZE)),
		int(floor(player_pos.z / CHUNK_SIZE))
	)
	
	_update_chunks(player_chunk)

func _update_chunks(center_chunk: Vector3i):
	for x in range(center_chunk.x - VIEW_DISTANCE_XZ, center_chunk.x + VIEW_DISTANCE_XZ + 1):
		for z in range(center_chunk.z - VIEW_DISTANCE_XZ, center_chunk.z + VIEW_DISTANCE_XZ + 1):
			for y in range(center_chunk.y - VIEW_DISTANCE_Y, center_chunk.y + VIEW_DISTANCE_Y + 1):
				if y < -4 or y > 8: continue
				
				var chunk_pos = Vector3i(x, y, z)
				if not chunks.has(chunk_pos):
					_spawn_chunk(chunk_pos)

	# TODO: Unload far chunks

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
					chunks[cpos].modify_sphere(global_pos - chunks[cpos].global_position, radius, amount)
