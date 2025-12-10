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
