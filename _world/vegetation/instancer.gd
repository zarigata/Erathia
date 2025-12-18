extends Node
class_name VegetationInstancer
## Vegetation Instancer
##
## Attaches to VoxelLodTerrain as a child node.
## Creates and manages MultiMeshInstance3D nodes for vegetation rendering.
## Connects to terrain chunk generation signals to trigger vegetation placement.

# =============================================================================
# CONSTANTS
# =============================================================================

const CHUNK_SIZE: int = 32
const MAX_TREE_INSTANCES: int = 50000
const MAX_BUSH_INSTANCES: int = 100000
const MAX_ROCK_INSTANCES: int = 30000
const MAX_GRASS_INSTANCES: int = 150000

# LOD distances (in meters)
const LOD_DISTANCES: Array[float] = [64.0, 128.0, 256.0, 512.0]

# Visibility ranges
const VISIBILITY_RANGES: Dictionary = {
	VegetationManager.VegetationType.TREE: 512.0,
	VegetationManager.VegetationType.BUSH: 256.0,
	VegetationManager.VegetationType.ROCK_SMALL: 192.0,
	VegetationManager.VegetationType.ROCK_MEDIUM: 384.0,
	VegetationManager.VegetationType.GRASS_TUFT: 128.0
}

# =============================================================================
# EXPORTS
# =============================================================================

@export var enabled: bool = true
@export var streaming_radius: int = 8  # Chunks around player to populate
@export var world_seed: int = 12345

# =============================================================================
# STATE
# =============================================================================

var _terrain: VoxelLodTerrain
var _placement_sampler: PlacementSampler

# MultiMesh containers per vegetation type and variant
# Nested dictionary: _multimesh_instances[veg_type][variant] -> MultiMeshInstance3D
var _multimesh_instances: Dictionary = {}

# Chunk tracking
var _populated_chunks: Dictionary = {}  # Vector3i -> bool
var _chunk_instance_indices: Dictionary = {}  # Vector3i -> Array of {type, variant, index}
var _pending_chunks: Array[Vector3i] = []
var _terrain_ready_chunks: Dictionary = {}  # Vector3i -> bool (chunks with LOD0 terrain ready)
var _deferred_chunks: Array[Vector3i] = []  # Chunks waiting for terrain to be ready

# Player reference for streaming
var _player: Node3D

# Processing state
var _is_processing: bool = false
var _chunks_per_frame: int = 1

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	if not enabled:
		return
	
	# Get terrain parent
	_terrain = get_parent() as VoxelLodTerrain
	if not _terrain:
		push_warning("[VegetationInstancer] Parent is not VoxelLodTerrain")
		return
	
	# Initialize placement sampler
	_placement_sampler = PlacementSampler.new(world_seed)
	
	# Setup MultiMesh instances
	_setup_multimesh_instances()
	
	# Find player
	call_deferred("_find_player")
	
	# Connect to terrain signals if available
	_connect_terrain_signals()
	
	print("[VegetationInstancer] Initialized with terrain: %s" % _terrain.name)


func _setup_multimesh_instances() -> void:
	# Create MultiMeshInstance3D for each vegetation type AND variant
	# Collect all unique variants from all biome rules
	var type_variants: Dictionary = {}  # veg_type -> Array of variant names
	
	for veg_type in VegetationManager.VegetationType.values():
		type_variants[veg_type] = []
		_multimesh_instances[veg_type] = {}
	
	# Gather all variants from all biome rules
	for biome_id in VegetationManager.BIOME_VEGETATION_RULES.keys():
		var rules: Dictionary = VegetationManager.BIOME_VEGETATION_RULES[biome_id]
		var types_array: Array = rules.get("types", [])
		for type_data: Dictionary in types_array:
			var veg_type: int = type_data.get("type", 0)
			var variants: Array = type_data.get("variants", ["default"])
			for variant: String in variants:
				if variant not in type_variants[veg_type]:
					type_variants[veg_type].append(variant)
	
	# Ensure each type has at least a "default" variant
	for veg_type in type_variants.keys():
		if type_variants[veg_type].is_empty():
			type_variants[veg_type].append("default")
	
	# Create MultiMeshInstance3D for each type+variant combination
	for veg_type in VegetationManager.VegetationType.values():
		var variants: Array = type_variants[veg_type]
		var instance_count_per_variant := _get_max_instances_for_type(veg_type) / maxi(variants.size(), 1)
		
		for variant: String in variants:
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "VegetationMM_%d_%s" % [veg_type, variant]
			
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.instance_count = instance_count_per_variant
			mm.visible_instance_count = 0
			
			# Set shadow casting based on type
			match veg_type:
				VegetationManager.VegetationType.GRASS_TUFT:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			
			mmi.multimesh = mm
			
			# Set visibility range
			var vis_range: float = VISIBILITY_RANGES.get(veg_type, 256.0)
			mmi.visibility_range_begin = 0.0
			mmi.visibility_range_end = vis_range
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			
			add_child(mmi)
			_multimesh_instances[veg_type][variant] = mmi


func _get_max_instances_for_type(veg_type: int) -> int:
	match veg_type:
		VegetationManager.VegetationType.TREE:
			return MAX_TREE_INSTANCES
		VegetationManager.VegetationType.BUSH:
			return MAX_BUSH_INSTANCES
		VegetationManager.VegetationType.ROCK_SMALL:
			return MAX_ROCK_INSTANCES
		VegetationManager.VegetationType.ROCK_MEDIUM:
			return MAX_ROCK_INSTANCES / 2
		VegetationManager.VegetationType.GRASS_TUFT:
			return MAX_GRASS_INSTANCES
		_:
			return MAX_BUSH_INSTANCES


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D
	else:
		# Fallback: find by path
		var root := get_tree().current_scene
		if root:
			_player = root.get_node_or_null("Player") as Node3D


func _connect_terrain_signals() -> void:
	# Try to connect to BiomeGenerator's chunk_generated signal
	if _terrain.generator:
		if _terrain.generator.has_signal("chunk_generated"):
			_terrain.generator.chunk_generated.connect(_on_chunk_generated)
			print("[VegetationInstancer] Connected to chunk_generated signal")
		else:
			print("[VegetationInstancer] Generator has no chunk_generated signal, using polling")


# =============================================================================
# PROCESS
# =============================================================================

func _process(delta: float) -> void:
	if not enabled or not _terrain:
		return
	
	# Update streaming based on player position
	if _player:
		_update_streaming()
	
	# Process pending chunks
	_process_pending_chunks()


func _update_streaming() -> void:
	if not _player:
		return
	
	var player_pos: Vector3 = _player.global_position
	var player_chunk: Vector3i = Vector3i(
		int(player_pos.x / CHUNK_SIZE) * CHUNK_SIZE,
		0,  # We only care about XZ for vegetation
		int(player_pos.z / CHUNK_SIZE) * CHUNK_SIZE
	)
	
	# Queue chunks within streaming radius
	for dx: int in range(-streaming_radius, streaming_radius + 1):
		for dz: int in range(-streaming_radius, streaming_radius + 1):
			var chunk_origin: Vector3i = Vector3i(
				player_chunk.x + dx * CHUNK_SIZE,
				0,
				player_chunk.z + dz * CHUNK_SIZE
			)
			
			if not _populated_chunks.has(chunk_origin) and not chunk_origin in _pending_chunks:
				_pending_chunks.append(chunk_origin)
	
	# Unload distant chunks
	var chunks_to_unload: Array[Vector3i] = []
	for chunk_origin: Vector3i in _populated_chunks.keys():
		var chunk_center := Vector3(chunk_origin.x + CHUNK_SIZE * 0.5, player_pos.y, chunk_origin.z + CHUNK_SIZE * 0.5)
		var distance := chunk_center.distance_to(player_pos)
		if distance > (streaming_radius + 2) * CHUNK_SIZE:
			chunks_to_unload.append(chunk_origin)
	
	for chunk_origin in chunks_to_unload:
		_unload_chunk(chunk_origin)


func _process_pending_chunks() -> void:
	if _pending_chunks.is_empty() or _is_processing:
		return
	
	_is_processing = true
	
	# Process a few chunks per frame
	for _i in range(mini(_chunks_per_frame, _pending_chunks.size())):
		if _pending_chunks.is_empty():
			break
		
		var chunk_origin: Vector3i = _pending_chunks.pop_front()
		_populate_chunk(chunk_origin)
	
	_is_processing = false


# =============================================================================
# CHUNK POPULATION
# =============================================================================

func _on_chunk_generated(chunk_origin: Vector3i, biome_id: int) -> void:
	# Mark this chunk as terrain-ready (LOD 0 generated)
	_terrain_ready_chunks[chunk_origin] = true
	
	# If this chunk was deferred, move it to pending
	var deferred_idx := _deferred_chunks.find(chunk_origin)
	if deferred_idx >= 0:
		_deferred_chunks.remove_at(deferred_idx)
		if not _populated_chunks.has(chunk_origin) and not chunk_origin in _pending_chunks:
			_pending_chunks.append(chunk_origin)
		return
	
	# Queue for population if not already populated
	if not _populated_chunks.has(chunk_origin) and not chunk_origin in _pending_chunks:
		_pending_chunks.append(chunk_origin)


func _populate_chunk(chunk_origin: Vector3i) -> void:
	if _populated_chunks.has(chunk_origin):
		return
	
	# Comment 3: Check if terrain is ready for this chunk
	# If we have the chunk_generated signal connected and this chunk hasn't been signaled yet,
	# defer population until terrain is ready
	if _terrain and _terrain.generator and _terrain.generator.has_signal("chunk_generated"):
		if not _terrain_ready_chunks.has(chunk_origin):
			# Terrain not ready yet - defer this chunk
			if not chunk_origin in _deferred_chunks:
				_deferred_chunks.append(chunk_origin)
			return
	
	# Get biome at chunk center
	var chunk_center := Vector3(chunk_origin.x + CHUNK_SIZE * 0.5, 0, chunk_origin.z + CHUNK_SIZE * 0.5)
	var biome_id := _get_biome_at_position(chunk_center)
	
	# Get vegetation rules for biome
	var rules := VegetationManager.get_biome_rules(biome_id)
	
	# Sample placements
	var placements := _placement_sampler.sample_chunk(
		chunk_origin,
		CHUNK_SIZE,
		biome_id,
		_terrain,
		rules
	)
	
	# Comment 3: If placement yields zero results and terrain might not be ready,
	# requeue the chunk for a later attempt instead of marking as populated
	if placements.is_empty():
		# Check if this could be due to missing surface data
		# If biome has vegetation types but we got zero placements, terrain may not be ready
		var biome_types: Array = rules.get("types", [])
		if not biome_types.is_empty() and not _terrain_ready_chunks.has(chunk_origin):
			# Terrain not confirmed ready and biome should have vegetation - defer
			if not chunk_origin in _deferred_chunks:
				_deferred_chunks.append(chunk_origin)
			return
	
	# Add instances to MultiMeshes
	for placement: Dictionary in placements:
		_add_instance(placement, chunk_origin)
	
	_populated_chunks[chunk_origin] = true
	
	if placements.size() > 0:
		VegetationManager.vegetation_populated.emit(chunk_origin, placements.size())


func _unload_chunk(chunk_origin: Vector3i) -> void:
	# Remove instances for this chunk from MultiMeshes
	if not _chunk_instance_indices.has(chunk_origin):
		_populated_chunks.erase(chunk_origin)
		return
	
	var chunk_instances: Array = _chunk_instance_indices[chunk_origin]
	if chunk_instances.is_empty():
		_chunk_instance_indices.erase(chunk_origin)
		_populated_chunks.erase(chunk_origin)
		return
	
	# Group instances by type+variant for efficient removal
	var instances_to_remove: Dictionary = {}  # "type_variant" -> Array of indices
	for instance_data: Dictionary in chunk_instances:
		var veg_type: int = instance_data.get("type", 0)
		var variant: String = instance_data.get("variant", "default")
		var key := "%d_%s" % [veg_type, variant]
		if not instances_to_remove.has(key):
			instances_to_remove[key] = {"type": veg_type, "variant": variant, "indices": []}
		instances_to_remove[key]["indices"].append(instance_data.get("index", -1))
	
	# For each type+variant, rebuild the MultiMesh excluding removed indices
	for key: String in instances_to_remove.keys():
		var data: Dictionary = instances_to_remove[key]
		var veg_type: int = data["type"]
		var variant: String = data["variant"]
		var indices_to_remove: Array = data["indices"]
		
		_rebuild_multimesh_excluding_indices(veg_type, variant, indices_to_remove, chunk_origin)
	
	# Clear tracking for this chunk
	_chunk_instance_indices.erase(chunk_origin)
	_populated_chunks.erase(chunk_origin)
	_terrain_ready_chunks.erase(chunk_origin)
	
	# Also clear from VegetationManager
	VegetationManager.unload_chunk(chunk_origin)


func _rebuild_multimesh_excluding_indices(veg_type: int, variant: String, indices_to_remove: Array, removed_chunk: Vector3i) -> void:
	var type_variants: Dictionary = _multimesh_instances.get(veg_type, {})
	var mmi: MultiMeshInstance3D = type_variants.get(variant)
	if not mmi or not mmi.multimesh:
		return
	
	var mm := mmi.multimesh
	var old_visible_count := mm.visible_instance_count
	
	if old_visible_count == 0:
		return
	
	# Create set of indices to remove for O(1) lookup
	var remove_set: Dictionary = {}
	for idx: int in indices_to_remove:
		remove_set[idx] = true
	
	# Collect transforms to keep
	var kept_transforms: Array[Transform3D] = []
	var old_to_new_index: Dictionary = {}  # old_index -> new_index
	
	for i in range(old_visible_count):
		if not remove_set.has(i):
			old_to_new_index[i] = kept_transforms.size()
			kept_transforms.append(mm.get_instance_transform(i))
	
	# Rebuild MultiMesh with kept transforms
	for i in range(kept_transforms.size()):
		mm.set_instance_transform(i, kept_transforms[i])
	
	mm.visible_instance_count = kept_transforms.size()
	
	# Update indices in _chunk_instance_indices for all OTHER chunks
	for chunk_origin: Vector3i in _chunk_instance_indices.keys():
		if chunk_origin == removed_chunk:
			continue
		
		var chunk_instances: Array = _chunk_instance_indices[chunk_origin]
		for instance_data: Dictionary in chunk_instances:
			if instance_data.get("type") == veg_type and instance_data.get("variant") == variant:
				var old_idx: int = instance_data.get("index", -1)
				if old_to_new_index.has(old_idx):
					instance_data["index"] = old_to_new_index[old_idx]


func _add_instance(placement: Dictionary, chunk_origin: Vector3i) -> void:
	var veg_type: int = placement.get("type", VegetationManager.VegetationType.BUSH)
	var variant: String = placement.get("variant", "default")
	var biome_id: int = placement.get("biome_id", MapGenerator.Biome.PLAINS)
	var transform: Transform3D = placement.get("transform", Transform3D.IDENTITY)
	var position: Vector3 = placement.get("position", Vector3.ZERO)
	var instance_seed: int = placement.get("seed", 0)
	
	# Get the variant-specific MultiMeshInstance3D
	var type_variants: Dictionary = _multimesh_instances.get(veg_type, {})
	var mmi: MultiMeshInstance3D = type_variants.get(variant)
	
	# Fallback to "default" variant if specific variant not found
	if not mmi and type_variants.has("default"):
		mmi = type_variants["default"]
		variant = "default"
	
	# Fallback to first available variant if still not found
	if not mmi and not type_variants.is_empty():
		variant = type_variants.keys()[0]
		mmi = type_variants[variant]
	
	if not mmi:
		return
	
	var mm := mmi.multimesh
	if not mm:
		return
	
	# Get or set mesh for this specific variant
	if mm.mesh == null:
		var mesh := VegetationManager.get_mesh_for_type(veg_type, biome_id, variant, instance_seed, 0)
		if mesh:
			mm.mesh = mesh
	
	# Add instance
	var visible_count := mm.visible_instance_count
	if visible_count >= mm.instance_count:
		# Resize if needed (double the size)
		var new_count := mm.instance_count * 2
		mm.instance_count = new_count
		push_warning("[VegetationInstancer] Resized MultiMesh for type %d variant %s to %d instances" % [veg_type, variant, new_count])
	
	mm.set_instance_transform(visible_count, transform)
	mm.visible_instance_count = visible_count + 1
	
	# Track instance index for chunk unloading (Comment 2 fix)
	if not _chunk_instance_indices.has(chunk_origin):
		_chunk_instance_indices[chunk_origin] = []
	_chunk_instance_indices[chunk_origin].append({
		"type": veg_type,
		"variant": variant,
		"index": visible_count
	})
	
	# Register with VegetationManager
	VegetationManager.register_instance_position(position, chunk_origin, veg_type, transform)


func _get_biome_at_position(world_pos: Vector3) -> int:
	# Try BiomeManager first
	if BiomeManager:
		var biome_name := BiomeManager.get_biome_at_position(world_pos)
		# Convert name back to ID (simplified)
		for biome_id in MapGenerator.Biome.values():
			if BiomeManager.get_biome_name(biome_id) == biome_name:
				return biome_id
	
	# Fallback to PLAINS
	return MapGenerator.Biome.PLAINS


# =============================================================================
# PUBLIC API
# =============================================================================

## Force repopulation of all chunks
func reload_vegetation() -> void:
	# Clear all MultiMeshes (now nested by type+variant)
	for veg_type: int in _multimesh_instances.keys():
		var type_variants: Dictionary = _multimesh_instances[veg_type]
		for variant: String in type_variants.keys():
			var mmi: MultiMeshInstance3D = type_variants[variant]
			if mmi and mmi.multimesh:
				mmi.multimesh.visible_instance_count = 0
	
	# Clear tracking
	_populated_chunks.clear()
	_pending_chunks.clear()
	_chunk_instance_indices.clear()
	_terrain_ready_chunks.clear()
	_deferred_chunks.clear()
	
	# Re-queue chunks around player
	if _player:
		_update_streaming()
	
	print("[VegetationInstancer] Vegetation reload triggered")


## Get instance count for a vegetation type (sum of all variants)
func get_instance_count(veg_type: int) -> int:
	var type_variants: Dictionary = _multimesh_instances.get(veg_type, {})
	var total := 0
	for variant: String in type_variants.keys():
		var mmi: MultiMeshInstance3D = type_variants[variant]
		if mmi and mmi.multimesh:
			total += mmi.multimesh.visible_instance_count
	return total


## Get total instance count
func get_total_instance_count() -> int:
	var total := 0
	for veg_type: int in _multimesh_instances.keys():
		total += get_instance_count(veg_type)
	return total


## Toggle visibility for a vegetation type (all variants)
func set_type_visible(veg_type: int, vis: bool) -> void:
	var type_variants: Dictionary = _multimesh_instances.get(veg_type, {})
	for variant: String in type_variants.keys():
		var mmi: MultiMeshInstance3D = type_variants[variant]
		if mmi:
			mmi.visible = vis


## Set enabled state
func set_enabled(value: bool) -> void:
	enabled = value
	for veg_type: int in _multimesh_instances.keys():
		var type_variants: Dictionary = _multimesh_instances[veg_type]
		for variant: String in type_variants.keys():
			var mmi: MultiMeshInstance3D = type_variants[variant]
			if mmi:
				mmi.visible = value
