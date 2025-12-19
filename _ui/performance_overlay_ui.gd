extends CanvasLayer
## Performance Overlay UI
##
## Displays real-time performance metrics and FPS graph.
## Toggle with F9 key.

@onready var panel: PanelContainer = $Panel
@onready var fps_label: Label = $Panel/VBoxContainer/FPSLabel
@onready var frame_time_label: Label = $Panel/VBoxContainer/FrameTimeLabel
@onready var memory_label: Label = $Panel/VBoxContainer/MemoryLabel
@onready var draw_calls_label: Label = $Panel/VBoxContainer/DrawCallsLabel
@onready var position_label: Label = $Panel/VBoxContainer/PositionLabel
@onready var biome_label: Label = $Panel/VBoxContainer/BiomeLabel
@onready var seed_label: Label = $Panel/VBoxContainer/SeedLabel
@onready var vsync_label: Label = $Panel/VBoxContainer/VSyncLabel
@onready var vegetation_label: Label = $Panel/VBoxContainer/VegetationLabel
@onready var fps_graph: Control = $Panel/VBoxContainer/FPSGraph

# New world init status labels (optional - may not exist in scene)
@onready var terrain_status_label: Label = $Panel/VBoxContainer/TerrainStatusLabel if has_node("Panel/VBoxContainer/TerrainStatusLabel") else null
@onready var init_stage_label: Label = $Panel/VBoxContainer/InitStageLabel if has_node("Panel/VBoxContainer/InitStageLabel") else null
@onready var biome_blending_label: Label = $Panel/VBoxContainer/BiomeBlendingLabel if has_node("Panel/VBoxContainer/BiomeBlendingLabel") else null

var _visible: bool = false
var _world_init_manager: Node = null
var _biome_generator: BiomeAwareGenerator = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 99
	
	# Add to group for discovery by debug_settings
	add_to_group("performance_overlay_ui")
	
	panel.visible = false
	
	# Connect to PerformanceOverlay signals
	if PerformanceOverlay:
		PerformanceOverlay.metrics_updated.connect(_on_metrics_updated)
	
	# Find WorldInitManager
	call_deferred("_find_world_init_manager")


func _find_world_init_manager() -> void:
	_world_init_manager = get_node_or_null("/root/WorldInitManager")
	
	# Find BiomeAwareGenerator from terrain
	var root := get_tree().current_scene
	if root:
		var terrain := root.get_node_or_null("VoxelLodTerrain") as VoxelLodTerrain
		if terrain and terrain.generator:
			_biome_generator = terrain.generator as BiomeAwareGenerator


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_performance_overlay"):
		_toggle_overlay()
		get_viewport().set_input_as_handled()


func _toggle_overlay() -> void:
	_visible = not _visible
	panel.visible = _visible


func _on_metrics_updated(data: Dictionary) -> void:
	if not _visible:
		return
	
	# Update labels
	var fps: float = data.get("fps", 0.0)
	var fps_color := _get_fps_color(fps)
	fps_label.text = "FPS: %d" % int(fps)
	fps_label.modulate = fps_color
	
	var frame_time: float = data.get("frame_time", 0.0)
	frame_time_label.text = "Frame: %.2f ms" % frame_time
	
	var memory_static: float = data.get("memory_static", 0.0)
	var memory_video: float = data.get("memory_video", 0.0)
	memory_label.text = "Memory: %.1f MB (VRAM: %.1f MB)" % [memory_static, memory_video]
	
	var draw_calls: float = data.get("draw_calls", 0.0)
	draw_calls_label.text = "Draw Calls: %d" % int(draw_calls)
	
	var pos: Vector3 = data.get("player_position", Vector3.ZERO)
	position_label.text = "Pos: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]
	
	var biome: String = data.get("biome", "Unknown")
	biome_label.text = "Biome: %s" % biome
	
	# World seed
	var world_seed: String = data.get("world_seed", "N/A")
	if seed_label:
		seed_label.text = "Seed: %s" % world_seed
	
	# VSync and rendering status
	var vsync_status: String = data.get("vsync_status", "Unknown")
	var rendering_method: String = data.get("rendering_method", "forward_plus")
	if vsync_label:
		vsync_label.text = "VSync: %s | Renderer: %s" % [vsync_status, rendering_method]
	
	# Vegetation stats
	var veg_stats: Dictionary = data.get("vegetation_stats", {})
	var veg_total: int = veg_stats.get("total_instances", 0)
	var veg_trees: int = veg_stats.get("tree_count", 0)
	var veg_grass: int = veg_stats.get("grass_count", 0)
	if vegetation_label:
		vegetation_label.text = "Vegetation: %d (Trees: %d, Grass: %d)" % [veg_total, veg_trees, veg_grass]
	
	# Trigger graph redraw only if enabled
	var show_graph: bool = data.get("show_graph", true)
	if show_graph and fps_graph:
		fps_graph.visible = true
		fps_graph.queue_redraw()
	elif fps_graph:
		fps_graph.visible = false
	
	# Update terrain/world init status
	_update_terrain_status()
	_update_init_stage()
	_update_biome_blending_status()


func _update_terrain_status() -> void:
	if not terrain_status_label:
		return
	
	var status_text := "Terrain: "
	var status_color := Color.WHITE
	
	if _world_init_manager:
		var stage: int = _world_init_manager.current_stage
		match stage:
			0:  # IDLE
				status_text += "Idle"
				status_color = Color.GRAY
			1, 2, 3, 4, 5:  # Generating stages
				status_text += "Generating"
				status_color = Color.YELLOW
			6:  # COMPLETE
				status_text += "Ready"
				status_color = Color.LIME
			7:  # FAILED
				status_text += "Failed"
				status_color = Color.RED
			_:
				status_text += "Unknown"
	else:
		status_text += "Ready"
		status_color = Color.LIME
	
	terrain_status_label.text = status_text
	terrain_status_label.modulate = status_color


func _update_init_stage() -> void:
	if not init_stage_label:
		return
	
	if _world_init_manager and _world_init_manager.is_initializing:
		var stage_name: String = _world_init_manager.get_stage_name()
		var progress: float = _world_init_manager.get_total_progress()
		init_stage_label.text = "Init: %s (%.0f%%)" % [stage_name, progress * 100]
		init_stage_label.visible = true
	else:
		init_stage_label.visible = false


func _update_biome_blending_status() -> void:
	if not biome_blending_label:
		return
	
	if _biome_generator:
		var strength: float = _biome_generator.height_modulation_strength
		var status := "Disabled" if strength <= 0.0 else "Enabled (%.0f%%)" % (strength * 100)
		var color := Color.GRAY if strength <= 0.0 else Color.LIME
		biome_blending_label.text = "Biome Blending: %s" % status
		biome_blending_label.modulate = color
	else:
		biome_blending_label.text = "Biome Blending: N/A"
		biome_blending_label.modulate = Color.GRAY


## Apply settings from debug settings panel
func apply_settings(settings: Dictionary) -> void:
	var show_graph: bool = settings.get("overlay_show_graph", true)
	if fps_graph:
		fps_graph.visible = show_graph


func _get_fps_color(fps: float) -> Color:
	if fps >= 60.0:
		return Color.LIME
	elif fps >= 30.0:
		return Color.YELLOW
	else:
		return Color.RED
