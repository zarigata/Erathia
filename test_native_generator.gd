extends Node3D

@onready var terrain: VoxelLodTerrain = $VoxelLodTerrain

func _ready():
	# Create bridge generator
	var generator = NativeVoxelGeneratorBridge.new()
	
	# Configure generator
	generator.set_world_seed(12345)
	generator.set_chunk_size(32)
	generator.set_world_size(4096.0)
	generator.set_sea_level(0.0)
	generator.set_blend_dist(100.0)
	
	# Initialize GPU
	if generator.initialize_gpu():
		print("✓ GPU initialized")
		print("Status: ", generator.get_gpu_status())
	else:
		push_error("✗ GPU initialization failed")
		return
	
	# Assign to terrain
	terrain.generator = generator
	terrain.view_distance = 512
	terrain.lod_count = 5
	
	print("✓ NativeVoxelGeneratorBridge assigned to VoxelLodTerrain")
