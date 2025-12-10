class_name TerrainManager
extends Node3D

const VIEW_DISTANCE = 4 # Chunks
const CHUNK_SIZE = 32

var noise: FastNoiseLite
var chunks = {}
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
		# Just look for any node in "Player" group
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			player = players[0]
		return
		
	var player_pos = player.global_position
	var player_chunk_x = int(player_pos.x / CHUNK_SIZE)
	var player_chunk_z = int(player_pos.z / CHUNK_SIZE)
	
	_update_chunks(Vector2i(player_chunk_x, player_chunk_z))

func _update_chunks(center_chunk: Vector2i):
	for x in range(center_chunk.x - VIEW_DISTANCE, center_chunk.x + VIEW_DISTANCE + 1):
		for z in range(center_chunk.y - VIEW_DISTANCE, center_chunk.y + VIEW_DISTANCE + 1):
			var chunk_pos = Vector2i(x, z)
			if not chunks.has(chunk_pos):
				_spawn_chunk(chunk_pos)

	# TODO: Unload far chunks

func _spawn_chunk(pos: Vector2i):
	var chunk = Chunk.new(noise, pos, biome_manager)
	add_child(chunk)
	chunk.global_position = Vector3(pos.x * CHUNK_SIZE, 0, pos.y * CHUNK_SIZE)
	chunk.generate_chunk()
	chunks[pos] = chunk

func modify_terrain(global_pos: Vector3, amount: float):
	var chunk_x = int(floor(global_pos.x / CHUNK_SIZE))
	var chunk_z = int(floor(global_pos.z / CHUNK_SIZE))
	var chunk_pos = Vector2i(chunk_x, chunk_z)
	
	if chunks.has(chunk_pos):
		var chunk = chunks[chunk_pos]
		# Calculate local within chunk
		# Careful with negative coordinates floor
		var local_x = int(floor(global_pos.x)) - (chunk_x * CHUNK_SIZE)
		var local_z = int(floor(global_pos.z)) - (chunk_z * CHUNK_SIZE)
		
		# Clamp to chunk bounds (0 to CHUNK_SIZE-1) interactions
		if local_x >= 0 and local_x < CHUNK_SIZE and local_z >= 0 and local_z < CHUNK_SIZE:
			chunk.modify_height(local_x, local_z, amount)
