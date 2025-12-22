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
const MAX_GRASS_INSTANCES: int = 100000  # Reduced for performance

# LOD distances (in meters)
const LOD_DISTANCES: Array[float] = [64.0, 128.0, 256.0, 512.0]

# Visibility ranges
const VISIBILITY_RANGES: Dictionary = {
	VegetationManager.VegetationType.TREE: 512.0,
	VegetationManager.VegetationType.BUSH: 256.0,
	VegetationManager.VegetationType.ROCK_SMALL: 192.0,
	VegetationManager.VegetationType.ROCK_MEDIUM: 384.0,
	VegetationManager.VegetationType.GRASS_TUFT: 64.0  # Reduced from 96m for performance
}

const MAX_GRASS_DENSITY: float = 0.15

# =============================================================================
# EXPORTS
# =============================================================================

@export var enabled: bool = true
@export var streaming_radius: int = 6  # Further reduced for performance and to avoid overdraw
@export var debug_logging: bool = false

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
var _chunk_biomes: Dictionary[Vector3i, int] = {}  # Vector3i -> biome_id captured from chunk_generated
var _origin_fix_reloaded: bool = false

# Player reference for streaming
var _player: Node3D

# Processing state
var _is_processing: bool = false
var _chunks_per_frame: int = 2  # Lower to reduce per-frame load and FPS spikes
var _chunk_log_budget: int = 10  # limit noisy chunk_generated logging to reduce FPS impact

var _connection_verified: bool = false
var _connection_attempts: int = 0
var _debug_last_placements: Dictionary = {}
var _biome_query_counts: Dictionary = {}
var _last_connection_status: Dictionary = {}

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
	
	# Initialize placement sampler with WorldSeedManager seed
	var seed_value: int = 12345
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if seed_manager:
		seed_value = seed_manager.get_world_seed()
	_placement_sampler = PlacementSampler.new(seed_value)
	
	# Setup MultiMesh instances
	_setup_multimesh_instances()
	
	# Find player
	call_deferred("_find_player")
	
	# Connect to terrain signals if available
	call_deferred("_connect_terrain_signals")
	
	# Retry connection after 1s if first attempt fails
	get_tree().create_timer(1.0).timeout.connect(func ():
		if not _verify_signal_connection():
			if debug_logging:
				print("[VegetationInstancer] Retrying terrain signal connection after delay")
			_connect_terrain_signals()
	)
	
	# Schedule vegetation spawn verification a few seconds after start
	get_tree().create_timer(5.0).timeout.connect(_verify_vegetation_spawning)
	
	if debug_logging:
		var generator_name := _terrain.generator.get_class() if _terrain and _terrain.generator else "null"
		print("[VegetationInstancer] Initialized with terrain: %s | generator: %s" % [_terrain.name, generator_name])


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
	# Try to connect to BiomeGenerator's chunk_generated signal (deferred-safe)
	if not _terrain:
		push_warning("[VegetationInstancer] Cannot connect terrain signals: no terrain")
		return
	
	var generator := _terrain.generator
	if not generator:
		if debug_logging:
			print("[VegetationInstancer] Terrain has no generator yet; will retry")
		return
	
	if not generator.has_signal("chunk_generated"):
		push_warning("[VegetationInstancer] Generator has no chunk_generated signal, using polling fallback")
		return
	
	if generator.is_connected("chunk_generated", Callable(self, "_on_chunk_generated")):
		if debug_logging:
			print("[VegetationInstancer] chunk_generated already connected")
		return
	
	var err: Error = generator.chunk_generated.connect(_on_chunk_generated)
	if err == OK and debug_logging:
		print("[VegetationInstancer] Connected to chunk_generated signal")
	elif err != OK:
		push_warning("[VegetationInstancer] Failed to connect chunk_generated: %s" % err)
	
	_connection_attempts += 1
	_connection_verified = _verify_signal_connection()
	if _connection_verified and not _origin_fix_reloaded:
		_origin_fix_reloaded = true
		reload_vegetation()
	if debug_logging:
		print("[VegetationInstancer] Connection attempt #%d -> verified=%s" % [_connection_attempts, str(_connection_verified)])


func _verify_signal_connection() -> bool:
	if not _terrain or not _terrain.generator:
		if debug_logging:
			print("[VegetationInstancer] _verify_signal_connection: terrain/generator missing")
		return false
	var generator := _terrain.generator
	var connected := generator.is_connected("chunk_generated", Callable(self, "_on_chunk_generated"))
	if debug_logging:
		var signals := generator.get_signal_list()
		print("[VegetationInstancer] Verify connection -> connected=%s | generator=%s | signals=%s" % [str(connected), generator.get_class(), signals])
	return connected


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
	# Normalize to XZ only (Y=0) for vegetation - we don't care about vertical chunks
	var veg_chunk := Vector3i(chunk_origin.x, 0, chunk_origin.z)
	
	# Debug logging
	if debug_logging and _chunk_log_budget > 0:
		print("[VegetationInstancer] chunk_generated: raw=%s, normalized=%s, biome=%d" % [chunk_origin, veg_chunk, biome_id])
		_chunk_log_budget -= 1
	
	# Mark this chunk as terrain-ready (LOD 0 generated)
	_terrain_ready_chunks[veg_chunk] = true
	_chunk_biomes[veg_chunk] = biome_id
	
	# If this chunk was deferred, move it to pending
	var deferred_idx := _deferred_chunks.find(veg_chunk)
	if deferred_idx >= 0:
		_deferred_chunks.remove_at(deferred_idx)
		if not _populated_chunks.has(veg_chunk) and not veg_chunk in _pending_chunks:
			_pending_chunks.append(veg_chunk)
		return
	
	# Queue for population if not already populated
	if not _populated_chunks.has(veg_chunk) and not veg_chunk in _pending_chunks:
		_pending_chunks.append(veg_chunk)


func _populate_chunk(chunk_origin: Vector3i) -> void:
	if _populated_chunks.has(chunk_origin):
		return
	
	if not _terrain:
		if debug_logging:
			push_warning("[VegetationInstancer] No terrain available for chunk %s" % chunk_origin)
		return
	
	# Use cached biome from generator; fall back to sampling if missing
	var biome_id: int = int(_chunk_biomes.get(chunk_origin, -1))
	if biome_id == -1:
		var chunk_center := Vector3(chunk_origin.x + CHUNK_SIZE * 0.5, 0, chunk_origin.z + CHUNK_SIZE * 0.5)
		biome_id = _get_biome_at_position(chunk_center)
	if biome_id == -1:
		if debug_logging:
			push_warning("[VegetationInstancer] Biome id null for chunk %s" % chunk_origin)
		return
	
	# Debug logging
	if debug_logging:
		print("[VegetationInstancer] Populating chunk: origin=%s, biome_id=%d" % [chunk_origin, biome_id])
	
	# Get vegetation rules for biome
	var rules := VegetationManager.get_biome_rules(biome_id)
	if rules.is_empty():
		if debug_logging:
			print("[VegetationInstancer] No rules for biome %d, skipping chunk %s" % [biome_id, chunk_origin])
		return
	
	# Sample placements
	var placements := _placement_sampler.sample_chunk(
		chunk_origin,
		CHUNK_SIZE,
		biome_id,
		_terrain,
		rules
	)
	
	if _terrain and not _terrain.has_method("get_voxel_tool") and debug_logging:
		push_warning("[VegetationInstancer] Terrain has no get_voxel_tool; placements may be empty")
	
	# If placement yields zero results and terrain might not be ready,
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
		if debug_logging and biome_types.is_empty():
			print("[VegetationInstancer] Warning: Biome %d has no vegetation rules" % biome_id)
	
	# Add instances to MultiMeshes
	for placement: Dictionary in placements:
		_add_instance(placement, chunk_origin)
	
	_populated_chunks[chunk_origin] = true
	
	if placements.size() > 0:
		VegetationManager.vegetation_populated.emit(chunk_origin, placements.size())
		if debug_logging:
			var counts := _summarize_placements(placements)
			_debug_last_placements[chunk_origin] = counts
			print("[VegetationInstancer] Chunk %s populated: %s" % [chunk_origin, str(counts)])


func _summarize_placements(placements: Array) -> Dictionary:
	var summary := {
		"total": placements.size(),
		"by_type": {}
	}
	for placement in placements:
		var t: int = placement.get("type", -1)
		summary["by_type"][t] = summary["by_type"].get(t, 0) + 1
	return summary


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
	_chunk_biomes.erase(chunk_origin)
	
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
		if not mesh:
			# Fallback: use simple placeholder mesh
			mesh = _create_placeholder_mesh(veg_type)
			if debug_logging:
				push_warning("[VegetationInstancer] Using fallback mesh for type %d variant %s" % [veg_type, variant])
		if mesh:
			mm.mesh = mesh
			if debug_logging:
				print("[VegetationInstancer] Assigned mesh for type %d variant %s biome %d seed %d" % [veg_type, variant, biome_id, instance_seed])
	
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


## Create a simple placeholder mesh when mesh generation fails
func _create_placeholder_mesh(veg_type: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	match veg_type:
		VegetationManager.VegetationType.TREE:
			# Simple cylinder trunk + cone canopy
			_generate_simple_tree(st)
		VegetationManager.VegetationType.BUSH:
			# Simple sphere
			_generate_simple_sphere(st, 0.5, Color(0.3, 0.5, 0.2))
		VegetationManager.VegetationType.ROCK_SMALL, VegetationManager.VegetationType.ROCK_MEDIUM:
			# Simple box
			_generate_simple_box(st, 0.5, Color(0.5, 0.5, 0.5))
		VegetationManager.VegetationType.GRASS_TUFT:
			# Simple crossed quads
			_generate_simple_grass(st)
		_:
			# Fallback cube
			_generate_simple_box(st, 0.3, Color(1.0, 0.0, 1.0))
	
	st.generate_normals()
	return st.commit()


func _generate_simple_tree(st: SurfaceTool) -> void:
	var trunk_color := Color(0.4, 0.25, 0.15)
	var canopy_color := Color(0.2, 0.5, 0.15)
	var trunk_height := 2.0
	var trunk_radius := 0.15
	var canopy_radius := 1.0
	var canopy_height := 2.5
	var segments := 6
	
	# Trunk (cylinder)
	var angle_step := TAU / segments
	for i in range(segments):
		var a1 := i * angle_step
		var a2 := (i + 1) * angle_step
		var x1 := cos(a1) * trunk_radius
		var z1 := sin(a1) * trunk_radius
		var x2 := cos(a2) * trunk_radius
		var z2 := sin(a2) * trunk_radius
		
		st.set_color(trunk_color)
		st.add_vertex(Vector3(x1, 0, z1))
		st.add_vertex(Vector3(x2, 0, z2))
		st.add_vertex(Vector3(x2, trunk_height, z2))
		
		st.add_vertex(Vector3(x1, 0, z1))
		st.add_vertex(Vector3(x2, trunk_height, z2))
		st.add_vertex(Vector3(x1, trunk_height, z1))
	
	# Canopy (cone)
	for i in range(segments):
		var a1 := i * angle_step
		var a2 := (i + 1) * angle_step
		var x1 := cos(a1) * canopy_radius
		var z1 := sin(a1) * canopy_radius
		var x2 := cos(a2) * canopy_radius
		var z2 := sin(a2) * canopy_radius
		
		st.set_color(canopy_color)
		st.add_vertex(Vector3(x1, trunk_height, z1))
		st.add_vertex(Vector3(x2, trunk_height, z2))
		st.add_vertex(Vector3(0, trunk_height + canopy_height, 0))


func _generate_simple_sphere(st: SurfaceTool, radius: float, color: Color) -> void:
	var segments := 6
	var rings := 4
	
	for i in range(segments):
		for j in range(rings):
			var theta1 := (float(i) / segments) * TAU
			var theta2 := (float(i + 1) / segments) * TAU
			var phi1 := (float(j) / rings) * PI
			var phi2 := (float(j + 1) / rings) * PI
			
			var p1 := Vector3(sin(phi1) * cos(theta1), cos(phi1), sin(phi1) * sin(theta1)) * radius
			var p2 := Vector3(sin(phi1) * cos(theta2), cos(phi1), sin(phi1) * sin(theta2)) * radius
			var p3 := Vector3(sin(phi2) * cos(theta2), cos(phi2), sin(phi2) * sin(theta2)) * radius
			var p4 := Vector3(sin(phi2) * cos(theta1), cos(phi2), sin(phi2) * sin(theta1)) * radius
			
			# Offset to ground level
			p1.y += radius
			p2.y += radius
			p3.y += radius
			p4.y += radius
			
			st.set_color(color)
			st.add_vertex(p1)
			st.add_vertex(p2)
			st.add_vertex(p3)
			
			st.add_vertex(p1)
			st.add_vertex(p3)
			st.add_vertex(p4)


func _generate_simple_box(st: SurfaceTool, size: float, color: Color) -> void:
	var half := size * 0.5
	var verts := [
		Vector3(-half, 0, -half), Vector3(half, 0, -half),
		Vector3(half, size, -half), Vector3(-half, size, -half),
		Vector3(-half, 0, half), Vector3(half, 0, half),
		Vector3(half, size, half), Vector3(-half, size, half)
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [3, 2, 6, 7],
		[4, 5, 1, 0], [1, 5, 6, 2], [4, 0, 3, 7]
	]
	
	st.set_color(color)
	for face in faces:
		st.add_vertex(verts[face[0]])
		st.add_vertex(verts[face[1]])
		st.add_vertex(verts[face[2]])
		st.add_vertex(verts[face[0]])
		st.add_vertex(verts[face[2]])
		st.add_vertex(verts[face[3]])


func _generate_simple_grass(st: SurfaceTool) -> void:
	var color := Color(0.35, 0.55, 0.2)
	var height := 0.4
	var width := 0.3
	
	# Two crossed quads
	for rot in [0.0, PI / 2.0]:
		var cos_r := cos(rot)
		var sin_r := sin(rot)
		var half_w := width * 0.5
		var offset := Vector3(cos_r * half_w, 0, sin_r * half_w)
		
		st.set_color(color.darkened(0.2))
		st.add_vertex(-offset)
		st.add_vertex(offset)
		st.set_color(color.lightened(0.1))
		st.add_vertex(offset + Vector3(0, height, 0))
		
		st.set_color(color.darkened(0.2))
		st.add_vertex(-offset)
		st.set_color(color.lightened(0.1))
		st.add_vertex(offset + Vector3(0, height, 0))
		st.add_vertex(-offset + Vector3(0, height, 0))


func _get_biome_at_position(world_pos: Vector3) -> int:
	# Try BiomeManager first
	if BiomeManager:
		var biome_name := BiomeManager.get_biome_at_position(world_pos)
		# Convert name back to ID (simplified)
		for biome_id in MapGenerator.Biome.values():
			if BiomeManager.get_biome_name(biome_id) == biome_name:
				_biome_query_counts[biome_id] = _biome_query_counts.get(biome_id, 0) + 1
				return biome_id
	
	# Fallback to PLAINS
	_biome_query_counts[MapGenerator.Biome.PLAINS] = _biome_query_counts.get(MapGenerator.Biome.PLAINS, 0) + 1
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


func get_connection_status() -> Dictionary:
	return {
		"connected": _verify_signal_connection(),
		"attempts": _connection_attempts,
		"terrain": _terrain.name if _terrain else "none",
		"generator": _terrain.generator.get_class() if _terrain and _terrain.generator else "none"
	}


func trigger_test_signal(chunk_origin: Vector3i, biome_id: int) -> void:
	_on_chunk_generated(chunk_origin, biome_id)


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


func _verify_vegetation_spawning() -> void:
	if not _player or not _terrain:
		if debug_logging:
			print("[VegetationInstancer] Spawn verification skipped (missing player/terrain)")
		return
	
	var results: Array[String] = []
	var player_chunk := Vector3i(int(_player.global_position.x / CHUNK_SIZE) * CHUNK_SIZE, 0, int(_player.global_position.z / CHUNK_SIZE) * CHUNK_SIZE)
	var offsets := [
		Vector3i.ZERO,
		Vector3i(CHUNK_SIZE, 0, 0),
		Vector3i(-CHUNK_SIZE, 0, 0),
		Vector3i(0, 0, CHUNK_SIZE),
		Vector3i(0, 0, -CHUNK_SIZE)
	]
	
	for off in offsets:
		var co: Vector3i = player_chunk + off
		var count := 0
		if _chunk_instance_indices.has(co):
			count = _chunk_instance_indices[co].size()
		results.append("%s -> %d" % [co, count])
	
	print("[VegetationInstancer] Spawn verification around player: %s" % ", ".join(results))


## Set enabled state
func set_enabled(value: bool) -> void:
	enabled = value
	for veg_type: int in _multimesh_instances.keys():
		var type_variants: Dictionary = _multimesh_instances[veg_type]
		for variant: String in type_variants.keys():
			var mmi: MultiMeshInstance3D = type_variants[variant]
			if mmi:
				mmi.visible = value
