extends Node
class_name VegetationDebug
## Vegetation Debug Visualization
##
## Provides debug visualization for vegetation placement zones,
## density heatmaps, and instance statistics.

# =============================================================================
# CONSTANTS
# =============================================================================

const DEBUG_SPHERE_RADIUS: float = 0.5
const GRID_CELL_SIZE: float = 4.0
const HEATMAP_COLORS: Array[Color] = [
	Color(0.0, 0.0, 1.0, 0.3),  # Blue - low density
	Color(0.0, 1.0, 1.0, 0.3),  # Cyan
	Color(0.0, 1.0, 0.0, 0.3),  # Green
	Color(1.0, 1.0, 0.0, 0.3),  # Yellow
	Color(1.0, 0.5, 0.0, 0.3),  # Orange
	Color(1.0, 0.0, 0.0, 0.3)   # Red - high density
]

# =============================================================================
# STATE
# =============================================================================

var _debug_meshes: Array[MeshInstance3D] = []
var _debug_labels: Array[Label3D] = []
var _is_showing_zones: bool = false
var _is_showing_heatmap: bool = false

var _player: Node3D
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 1.0

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	call_deferred("_find_player")


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D


# =============================================================================
# PROCESS
# =============================================================================

func _process(delta: float) -> void:
	if not _is_showing_zones and not _is_showing_heatmap:
		return
	
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_debug_visualization()


# =============================================================================
# PUBLIC API
# =============================================================================

## Toggle zone visualization
func toggle_zones() -> void:
	_is_showing_zones = not _is_showing_zones
	if _is_showing_zones:
		_update_debug_visualization()
	else:
		_clear_debug_meshes()
	print("[VegetationDebug] Zone visualization: %s" % ("ON" if _is_showing_zones else "OFF"))


## Toggle density heatmap
func toggle_heatmap() -> void:
	_is_showing_heatmap = not _is_showing_heatmap
	if _is_showing_heatmap:
		_update_debug_visualization()
	else:
		_clear_debug_meshes()
	print("[VegetationDebug] Heatmap visualization: %s" % ("ON" if _is_showing_heatmap else "OFF"))


## Show vegetation statistics
func show_stats() -> void:
	VegetationManager.print_stats()


## Get formatted stats string
func get_stats_string() -> String:
	var stats := VegetationManager.get_stats()
	return "Vegetation: %d (T:%d B:%d R:%d G:%d)" % [
		stats["total_instances"],
		stats["tree_count"],
		stats["bush_count"],
		stats["rock_count"],
		stats["grass_count"]
	]


# =============================================================================
# VISUALIZATION
# =============================================================================

func _update_debug_visualization() -> void:
	if not _player:
		_find_player()
		return
	
	_clear_debug_meshes()
	
	var player_pos := _player.global_position
	var view_radius := 64.0
	
	if _is_showing_zones:
		_draw_placement_zones(player_pos, view_radius)
	
	if _is_showing_heatmap:
		_draw_density_heatmap(player_pos, view_radius)


func _draw_placement_zones(center: Vector3, radius: float) -> void:
	# Draw grid showing where vegetation can be placed
	var grid_steps := int(radius * 2 / GRID_CELL_SIZE)
	var start_x := center.x - radius
	var start_z := center.z - radius
	
	for gx in range(grid_steps):
		for gz in range(grid_steps):
			var world_x := start_x + gx * GRID_CELL_SIZE
			var world_z := start_z + gz * GRID_CELL_SIZE
			var world_pos := Vector3(world_x, center.y, world_z)
			
			# Get biome at position
			var biome_name := BiomeManager.get_biome_at_position(world_pos)
			var biome_id := _get_biome_id_from_name(biome_name)
			var rules := VegetationManager.get_biome_rules(biome_id)
			var veg_types: Array = rules.get("types", [])
			
			if veg_types.is_empty():
				continue
			
			# Calculate total density
			var total_density := 0.0
			for veg_type_data: Dictionary in veg_types:
				total_density += VegetationManager.get_effective_density(biome_id, veg_type_data)
			
			# Create debug marker
			var color := _get_density_color(total_density)
			_create_debug_marker(world_pos, color, GRID_CELL_SIZE * 0.4)


func _draw_density_heatmap(center: Vector3, radius: float) -> void:
	var grid_steps := int(radius * 2 / GRID_CELL_SIZE)
	var start_x := center.x - radius
	var start_z := center.z - radius
	
	for gx in range(grid_steps):
		for gz in range(grid_steps):
			var world_x := start_x + gx * GRID_CELL_SIZE
			var world_z := start_z + gz * GRID_CELL_SIZE
			var world_pos := Vector3(world_x, center.y, world_z)
			
			# Get vegetation density from BiomeManager
			var biome_name := BiomeManager.get_biome_at_position(world_pos)
			var biome_id := _get_biome_id_from_name(biome_name)
			var density := BiomeManager.get_vegetation_density(biome_id)
			
			var color := _get_density_color(density)
			_create_debug_quad(world_pos, color, GRID_CELL_SIZE)


func _create_debug_marker(position: Vector3, color: Color, size: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2
	sphere.radial_segments = 8
	sphere.rings = 4
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = material
	
	mesh_instance.mesh = sphere
	mesh_instance.global_position = position
	
	add_child(mesh_instance)
	_debug_meshes.append(mesh_instance)


func _create_debug_quad(position: Vector3, color: Color, size: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(size, size)
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	
	mesh_instance.mesh = quad
	mesh_instance.global_position = position + Vector3(0, 0.1, 0)  # Slight offset above ground
	
	add_child(mesh_instance)
	_debug_meshes.append(mesh_instance)


func _clear_debug_meshes() -> void:
	for mesh: MeshInstance3D in _debug_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_debug_meshes.clear()
	
	for label: Label3D in _debug_labels:
		if is_instance_valid(label):
			label.queue_free()
	_debug_labels.clear()


func _get_density_color(density: float) -> Color:
	# Map density (0-1) to color gradient
	var index := int(clampf(density, 0.0, 1.0) * (HEATMAP_COLORS.size() - 1))
	return HEATMAP_COLORS[index]


func _get_biome_id_from_name(biome_name: String) -> int:
	# Convert biome name back to ID
	for biome_id in MapGenerator.Biome.values():
		if BiomeManager.get_biome_name(biome_id) == biome_name:
			return biome_id
	return MapGenerator.Biome.PLAINS
