@tool
extends VoxelGeneratorScript
class_name OreGenerator

## Ore Generator - Wraps base terrain generator and adds 3D ore vein noise
## Writes terrain shape to SDF channel and material IDs to INDICES channel with weights

# Ore generation parameters
@export var ore_frequency: float = 0.02:
	set(value):
		ore_frequency = value
		if _ore_noise:
			_ore_noise.frequency = ore_frequency
@export var ore_threshold: float = 0.6
@export var ore_material_id: int = 3
@export var min_ore_depth: float = 5.0

# Material IDs
const MAT_AIR: int = 0
const MAT_DIRT: int = 1
const MAT_STONE: int = 2
const MAT_IRON_ORE: int = 3

# Dirt layer thickness (SDF units)
const DIRT_LAYER_THICKNESS: float = 2.0

# Base generator resource
var _base_generator: VoxelGeneratorNoise

# Ore vein noise
var _ore_noise: FastNoiseLite


func _init() -> void:
	# Load the base terrain generator
	_base_generator = preload("res://_engine/terrain/basic_generator.tres")
	
	# Configure ore vein noise
	_ore_noise = FastNoiseLite.new()
	_ore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ore_noise.seed = 67890
	_ore_noise.frequency = ore_frequency
	_ore_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_ore_noise.fractal_octaves = 2
	_ore_noise.fractal_lacunarity = 2.0
	_ore_noise.fractal_gain = 0.5


func _get_used_channels_mask() -> int:
	# We write to SDF (terrain shape) and INDICES (material IDs)
	# Single texture mode uses 8-bit INDICES channel
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES)


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var block_size := out_buffer.get_size()
	var lod_scale := 1 << lod
	
	# First pass: Generate base terrain SDF using the base generator
	_base_generator.generate_block(out_buffer, origin, lod)
	
	# Second pass: Add material IDs based on SDF values and ore noise
	# Shader will handle smooth blending based on world position
	for z in range(block_size.z):
		for y in range(block_size.y):
			for x in range(block_size.x):
				# Calculate world position
				var world_x: float = origin.x + x * lod_scale
				var world_y: float = origin.y + y * lod_scale
				var world_z: float = origin.z + z * lod_scale
				
				# Get SDF value (negative = solid, positive = air)
				var sdf: float = out_buffer.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
				
				# Determine material based on SDF and position
				var material_id: int = MAT_AIR
				
				if sdf <= 0.0:
					# Solid voxel - determine material type
					if sdf > -DIRT_LAYER_THICKNESS:
						# Surface layer = dirt
						material_id = MAT_DIRT
					else:
						# Underground = stone by default
						material_id = MAT_STONE
						
						# Check for ore vein
						# Only generate ore below minimum depth from surface
						if sdf < -(min_ore_depth + DIRT_LAYER_THICKNESS):
							var ore_noise_value: float = _ore_noise.get_noise_3d(world_x, world_y, world_z)
							# Noise returns -1 to 1, normalize to 0-1 range
							ore_noise_value = (ore_noise_value + 1.0) * 0.5
							
							if ore_noise_value > ore_threshold:
								material_id = ore_material_id
				
				# Write material ID to INDICES channel (8-bit for Single mode)
				out_buffer.set_voxel(material_id, x, y, z, VoxelBuffer.CHANNEL_INDICES)
