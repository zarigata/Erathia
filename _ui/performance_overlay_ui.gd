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
@onready var gpu_compute_label: Label = $Panel/VBoxContainer/GPUComputeLabel if has_node("Panel/VBoxContainer/GPUComputeLabel") else null
@onready var terrain_gen_label: Label = $Panel/VBoxContainer/TerrainGenLabel if has_node("Panel/VBoxContainer/TerrainGenLabel") else null
@onready var vegetation_spawn_label: Label = $Panel/VBoxContainer/VegetationSpawnLabel if has_node("Panel/VBoxContainer/VegetationSpawnLabel") else null
@onready var workload_label: Label = $Panel/VBoxContainer/WorkloadLabel if has_node("Panel/VBoxContainer/WorkloadLabel") else null
@onready var warnings_label: Label = $Panel/VBoxContainer/WarningsLabel if has_node("Panel/VBoxContainer/WarningsLabel") else null
@onready var csv_status_label: Label = $Panel/VBoxContainer/CSVStatusLabel if has_node("Panel/VBoxContainer/CSVStatusLabel") else null

# New world init status labels (optional - may not exist in scene)
@onready var terrain_status_label: Label = $Panel/VBoxContainer/TerrainStatusLabel if has_node("Panel/VBoxContainer/TerrainStatusLabel") else null
@onready var init_stage_label: Label = $Panel/VBoxContainer/InitStageLabel if has_node("Panel/VBoxContainer/InitStageLabel") else null
@onready var biome_blending_label: Label = $Panel/VBoxContainer/BiomeBlendingLabel if has_node("Panel/VBoxContainer/BiomeBlendingLabel") else null

var _visible: bool = false
var _world_init_manager: Node = null
var _biome_generator: BiomeAwareGenerator = null
var _show_gpu_metrics: bool = true


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
	
	# GPU compute metrics (guarded by setting)
	if not _show_gpu_metrics:
		if gpu_compute_label:
			gpu_compute_label.visible = false
		if terrain_gen_label:
			terrain_gen_label.visible = false
		if vegetation_spawn_label:
			vegetation_spawn_label.visible = false
		if workload_label:
			workload_label.visible = false
		if warnings_label:
			warnings_label.visible = false
	else:
		if gpu_compute_label:
			gpu_compute_label.visible = true
			var gpu_compute_time: float = data.get("gpu_compute_time", 0.0)
			gpu_compute_label.text = "GPU Compute: %.2f ms" % gpu_compute_time
			gpu_compute_label.modulate = _get_timing_color(gpu_compute_time, 5.0)
		
		if terrain_gen_label:
			terrain_gen_label.visible = true
			var terrain_gen_time: float = data.get("terrain_generation_time", 0.0)
			terrain_gen_label.text = "Terrain Gen: %.2f ms" % terrain_gen_time
			terrain_gen_label.modulate = _get_timing_color(terrain_gen_time, 3.0)
		
		if vegetation_spawn_label:
			vegetation_spawn_label.visible = true
			var veg_spawn_time: float = data.get("vegetation_spawning_time", 0.0)
			vegetation_spawn_label.text = "Vegetation: %.2f ms" % veg_spawn_time
			vegetation_spawn_label.modulate = _get_timing_color(veg_spawn_time, 2.0)
		
		# Workload distribution
		if workload_label:
			var workload: Dictionary = data.get("workload_distribution", {})
			if workload.is_empty():
				workload_label.visible = false
			else:
				workload_label.visible = true
				var cpu_pct := workload.get("cpu", 0.0) * 100.0
				var compute_pct := workload.get("gpu_compute", 0.0) * 100.0
				var render_pct := workload.get("gpu_render", 0.0) * 100.0
				workload_label.text = "Workload: CPU %.0f%% | Compute %.0f%% | Render %.0f%%" % [cpu_pct, compute_pct, render_pct]
		
		# Performance warnings
		if warnings_label:
			warnings_label.visible = true
			var warnings: Array = data.get("performance_warnings", [])
			if warnings.is_empty():
				warnings_label.text = "Performance: OK"
				warnings_label.modulate = Color.LIME
			else:
				warnings_label.text = "⚠ " + warnings[0]
				warnings_label.modulate = Color.YELLOW
	
	# Update terrain/world init status
	_update_terrain_status()
	_update_init_stage()
	_update_biome_blending_status()
	_update_csv_status()


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


func _update_csv_status() -> void:
	if not csv_status_label or not PerformanceOverlay:
		return
	var elapsed := PerformanceOverlay.get_last_export_elapsed_sec()
	if elapsed < 0.0:
		csv_status_label.text = "CSV: pending first export"
		csv_status_label.modulate = Color.YELLOW
	else:
		csv_status_label.text = "CSV: last export %.1fs ago (%s)" % [
			elapsed,
			PerformanceOverlay.get_csv_file_path()
		]
		csv_status_label.modulate = Color.LIME if elapsed <= 6.0 else Color.YELLOW


## Apply settings from debug settings panel
func apply_settings(settings: Dictionary) -> void:
	var show_graph: bool = settings.get("overlay_show_graph", true)
	_show_gpu_metrics = settings.get("performance_show_gpu_metrics", true)
	if fps_graph:
		fps_graph.visible = show_graph
	
	# Ensure GPU labels reflect setting immediately
	if gpu_compute_label:
		gpu_compute_label.visible = _show_gpu_metrics
	if terrain_gen_label:
		terrain_gen_label.visible = _show_gpu_metrics
	if vegetation_spawn_label:
		vegetation_spawn_label.visible = _show_gpu_metrics
	if workload_label:
		workload_label.visible = _show_gpu_metrics
	if warnings_label:
		warnings_label.visible = _show_gpu_metrics


func _get_fps_color(fps: float) -> Color:
	if fps >= 60.0:
		return Color.LIME
	elif fps >= 30.0:
		return Color.YELLOW
	else:
		return Color.RED


func _get_timing_color(time_ms: float, budget_ms: float) -> Color:
	if time_ms <= budget_ms * 0.5:
		return Color.LIME
	elif time_ms <= budget_ms:
		return Color.YELLOW
	else:
		return Color.RED
