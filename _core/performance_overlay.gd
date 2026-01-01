extends Node
## Performance Overlay Singleton
##
## Tracks engine metrics and exposes them for the performance UI.
## Registered as autoload "PerformanceOverlay" in project.godot

signal metrics_updated(data: Dictionary)

# FPS history for graph
var fps_history: Array[float] = []
const FPS_HISTORY_SIZE: int = 120  # 2 seconds at 60fps

# Spike detection
var spike_log: Array[Dictionary] = []
const SPIKE_THRESHOLD_MS: float = 33.0  # Below 30fps
const MAX_SPIKE_LOG: int = 100

# Update rate
var _update_timer: float = 0.0
var _update_interval: float = 0.1  # Configurable via settings
const UPDATE_INTERVAL: float = 0.1  # 10 updates per second (default)

# Graph visibility
var _show_graph: bool = true

# Cached metrics
var _current_metrics: Dictionary = {}
const CPU_BUDGET_MS: float = 16.67  # 60 FPS target
const GPU_COMPUTE_BUDGET_MS: float = 5.0  # Max 5ms for compute
const TERRAIN_GEN_BUDGET_MS: float = 3.0
const VEGETATION_BUDGET_MS: float = 2.0
var _gpu_compute_time_ms: float = 0.0
var _terrain_generation_time_ms: float = 0.0
var _vegetation_spawning_time_ms: float = 0.0
var _cpu_logic_time_ms: float = 0.0
var _gpu_render_time_ms: float = 0.0
var _performance_warnings: Array[String] = []
var _cpu_budget_ms: float = CPU_BUDGET_MS
var _gpu_compute_budget_ms: float = GPU_COMPUTE_BUDGET_MS
var _terrain_budget_ms: float = TERRAIN_GEN_BUDGET_MS
var _vegetation_budget_ms: float = VEGETATION_BUDGET_MS
var _warn_on_budget_exceed: bool = true
var _show_gpu_metrics: bool = true

# CSV export
var _csv_export_timer: float = 0.0
var _csv_export_interval: float = 5.0
var _csv_file_path: String = "user://perf_log.csv"
var _csv_initialized: bool = false
var _last_csv_export_ms: int = 0


func _ready() -> void:
	# Initialize FPS history with zeros
	for i in range(FPS_HISTORY_SIZE):
		fps_history.append(60.0)


func _process(delta: float) -> void:
	# Always track FPS for history
	var fps := Engine.get_frames_per_second()
	fps_history.append(fps)
	if fps_history.size() > FPS_HISTORY_SIZE:
		fps_history.pop_front()
	
	# Check for spikes
	var frame_time_ms := delta * 1000.0
	if frame_time_ms > SPIKE_THRESHOLD_MS:
		_log_spike(frame_time_ms)
	
	# Update metrics at interval
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	
	_update_timer = _update_interval
	_update_metrics()
	_csv_export_timer += delta
	if _csv_export_timer >= _csv_export_interval:
		_csv_export_timer = 0.0
		_export_metrics_to_csv()


func _update_metrics() -> void:
	var fps := Engine.get_frames_per_second()
	
	# FPS target indicator color
	var fps_status := "green"  # >60 FPS
	if fps < 30:
		fps_status = "red"
	elif fps < 60:
		fps_status = "yellow"
	
	# Get VSync status
	var vsync_mode := DisplayServer.window_get_vsync_mode()
	var vsync_status := "Unknown"
	match vsync_mode:
		DisplayServer.VSYNC_DISABLED:
			vsync_status = "Disabled"
		DisplayServer.VSYNC_ENABLED:
			vsync_status = "Enabled"
		DisplayServer.VSYNC_ADAPTIVE:
			vsync_status = "Adaptive"
		DisplayServer.VSYNC_MAILBOX:
			vsync_status = "Mailbox"
	
	_performance_warnings.clear()
	_collect_gpu_metrics()
	_compute_frame_breakdown()
	_check_performance_budgets()
	
	# Get async GPU telemetry if available
	var async_gpu_stats := _get_async_gpu_telemetry()
	
	_current_metrics = {
		"fps": fps,
		"fps_status": fps_status,
		"frame_time": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_time": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,  # MB
		"memory_static_max": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,  # MB (available static memory)
		"memory_video": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,  # MB (video memory)
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects_drawn": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"vertices": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"player_position": _get_player_position(),
		"biome": _get_current_biome(),
		"biome_color": _get_biome_color(),
		"biome_transition": _is_near_biome_boundary(),
		"world_seed": _get_world_seed(),
		"vsync_status": vsync_status,
		"rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"),
		"vegetation_stats": _get_vegetation_stats(),
		"fps_history": fps_history.duplicate(),
		"show_graph": _show_graph,
		"gpu_compute_time": _gpu_compute_time_ms,
		"terrain_generation_time": _terrain_generation_time_ms,
		"vegetation_spawning_time": _vegetation_spawning_time_ms,
		"cpu_logic_time": _cpu_logic_time_ms,
		"gpu_render_time": _gpu_render_time_ms,
		"performance_warnings": _performance_warnings.duplicate(),
		"gpu_memory_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"gpu_memory_max_mb": _get_gpu_memory_max(),
		"workload_distribution": _calculate_workload_distribution(),
		"async_gpu_stats": async_gpu_stats
	}
	
	metrics_updated.emit(_current_metrics)


func _export_metrics_to_csv() -> void:
	var file: FileAccess = null
	var header := [
		"timestamp",
		"fps",
		"frame_time",
		"physics_time",
		"memory_static",
		"memory_video",
		"gpu_compute_time",
		"terrain_generation_time",
		"vegetation_spawning_time",
		"cpu_logic_time",
		"gpu_render_time",
		"draw_calls",
		"objects_drawn",
		"vertices",
		"workload_cpu_percent",
		"workload_gpu_compute_percent",
		"workload_gpu_render_percent"
	]
	var now_str := str(Time.get_unix_time_from_system())
	var workload := _calculate_workload_distribution()
	var row := [
		now_str,
		str(_current_metrics.get("fps", 0.0)),
		str(_current_metrics.get("frame_time", 0.0)),
		str(_current_metrics.get("physics_time", 0.0)),
		str(_current_metrics.get("memory_static", 0.0)),
		str(_current_metrics.get("memory_video", 0.0)),
		str(_gpu_compute_time_ms),
		str(_terrain_generation_time_ms),
		str(_vegetation_spawning_time_ms),
		str(_cpu_logic_time_ms),
		str(_gpu_render_time_ms),
		str(_current_metrics.get("draw_calls", 0)),
		str(_current_metrics.get("objects_drawn", 0)),
		str(_current_metrics.get("vertices", 0)),
		str(workload.get("cpu", 0.0)),
		str(workload.get("gpu_compute", 0.0)),
		str(workload.get("gpu_render", 0.0))
	]
	
	if not FileAccess.file_exists(_csv_file_path):
		file = FileAccess.open(_csv_file_path, FileAccess.WRITE_READ)
		if file == null:
			push_warning("Failed to open CSV file for writing: %s" % _csv_file_path)
			return
		file.store_csv_line(header)
		_csv_initialized = true
	else:
		file = FileAccess.open(_csv_file_path, FileAccess.READ_WRITE)
		if file == null:
			push_warning("Failed to open CSV file for appending: %s" % _csv_file_path)
			return
		file.seek_end()
	
	file.store_csv_line(row)
	file.flush()
	file.close()
	_last_csv_export_ms = Time.get_ticks_msec()


func export_metrics_now() -> String:
	_export_metrics_to_csv()
	return _csv_file_path


func get_csv_file_path() -> String:
	return _csv_file_path


func get_last_export_elapsed_sec() -> float:
	if _last_csv_export_ms <= 0:
		return -1.0
	return float(Time.get_ticks_msec() - _last_csv_export_ms) / 1000.0


## Apply settings from debug settings panel
func apply_settings(settings: Dictionary) -> void:
	_update_interval = settings.get("overlay_update_rate", UPDATE_INTERVAL)
	_show_graph = settings.get("overlay_show_graph", true)
	_show_gpu_metrics = settings.get("performance_show_gpu_metrics", true)


func set_performance_budgets(budgets: Dictionary) -> void:
	_cpu_budget_ms = budgets.get("cpu_budget_ms", CPU_BUDGET_MS)
	_gpu_compute_budget_ms = budgets.get("gpu_compute_budget_ms", GPU_COMPUTE_BUDGET_MS)
	_terrain_budget_ms = budgets.get("terrain_budget_ms", TERRAIN_GEN_BUDGET_MS)
	_vegetation_budget_ms = budgets.get("vegetation_budget_ms", VEGETATION_BUDGET_MS)
	_warn_on_budget_exceed = budgets.get("warn_enabled", true)


func _collect_gpu_metrics() -> void:
	if not _show_gpu_metrics:
		_gpu_compute_time_ms = 0.0
		_terrain_generation_time_ms = 0.0
		_vegetation_spawning_time_ms = 0.0
		return

	_gpu_compute_time_ms = 0.0
	_terrain_generation_time_ms = 0.0
	_vegetation_spawning_time_ms = 0.0
	
	var terrain_gen = _get_gpu_terrain_generator()
	if terrain_gen:
		# Support async GPU telemetry from NativeTerrainGenerator
		if terrain_gen.has_method("get_telemetry"):
			var stats = terrain_gen.get_telemetry()
			_terrain_generation_time_ms = stats.get("average_gpu_time_ms", 0.0)
			_gpu_compute_time_ms = stats.get("current_frame_gpu_time_ms", 0.0)
		elif terrain_gen.has_method("get_last_generation_time_ms"):
			_terrain_generation_time_ms = terrain_gen.get_last_generation_time_ms()
	
	var biome_dispatcher := _get_biome_gpu_dispatcher()
	if biome_dispatcher:
		if biome_dispatcher.has_method("get_last_compute_time_ms"):
			_gpu_compute_time_ms += biome_dispatcher.get_last_compute_time_ms()
	
	var vegetation_dispatcher = _get_vegetation_gpu_dispatcher()
	if vegetation_dispatcher:
		if vegetation_dispatcher.has_method("get_last_placement_time_ms"):
			_vegetation_spawning_time_ms = vegetation_dispatcher.get_last_placement_time_ms()
			_gpu_compute_time_ms += _vegetation_spawning_time_ms


func _compute_frame_breakdown() -> void:
	var fps := Engine.get_frames_per_second()
	var total_frame_ms := 0.0
	if fps > 0.0:
		total_frame_ms = 1000.0 / fps
	else:
		total_frame_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_cpu_logic_time_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_gpu_render_time_ms = max(total_frame_ms - _cpu_logic_time_ms - _gpu_compute_time_ms, 0.0)


func _check_performance_budgets() -> void:
	if not _warn_on_budget_exceed:
		return
	if _cpu_logic_time_ms > _cpu_budget_ms:
		_performance_warnings.append("CPU logic exceeds budget")
	if _gpu_compute_time_ms > _gpu_compute_budget_ms:
		_performance_warnings.append("GPU compute exceeds budget")
	if _terrain_generation_time_ms > _terrain_budget_ms:
		_performance_warnings.append("Terrain generation slow")
	if _vegetation_spawning_time_ms > _vegetation_budget_ms:
		_performance_warnings.append("Vegetation spawning slow")


func _get_player_position() -> Vector3:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0].global_position
	
	# Fallback
	var root := get_tree().current_scene
	if root:
		var player := root.get_node_or_null("Player")
		if player:
			return player.global_position
	
	return Vector3.ZERO


func _get_current_biome() -> String:
	var pos := _get_player_position()
	if BiomeManager and BiomeManager.has_method("get_biome_at_position"):
		return BiomeManager.get_biome_at_position(pos)
	return "Unknown"


## Get biome color for current position
func _get_biome_color() -> Color:
	var pos := _get_player_position()
	var biome_id := _get_biome_id_at_position(pos)
	if MapGenerator:
		var mg := MapGenerator.new()
		if mg.has_method("get_biome_color"):
			var color: Color = mg.get_biome_color(biome_id)
			mg.free()
			return color
		mg.free()
	# Fallback colors based on biome ID
	var fallback_colors := {
		0: Color(0.4, 0.7, 0.3),   # PLAINS - green
		1: Color(0.2, 0.5, 0.2),   # FOREST - dark green
		2: Color(0.9, 0.8, 0.5),   # DESERT - tan
		3: Color(0.3, 0.4, 0.3),   # SWAMP - murky green
		4: Color(0.7, 0.8, 0.9),   # TUNDRA - light blue
		5: Color(0.1, 0.6, 0.2),   # JUNGLE - bright green
		6: Color(0.8, 0.7, 0.4),   # SAVANNA - golden
		7: Color(0.5, 0.5, 0.5),   # MOUNTAIN - gray
		8: Color(0.9, 0.85, 0.7),  # BEACH - sand
		9: Color(0.1, 0.2, 0.5),   # DEEP_OCEAN - dark blue
		10: Color(0.8, 0.9, 1.0),  # ICE_SPIRES - ice blue
		11: Color(0.3, 0.1, 0.1),  # VOLCANIC - dark red
		12: Color(0.6, 0.3, 0.6),  # MUSHROOM - purple
	}
	return fallback_colors.get(biome_id, Color.WHITE)


## Get biome ID at position
func _get_biome_id_at_position(pos: Vector3) -> int:
	if BiomeManager and BiomeManager.has_method("get_biome_id_at_position"):
		return BiomeManager.get_biome_id_at_position(pos)
	# Fallback: try to get from biome name
	var biome_name := _get_current_biome()
	var biome_names := ["Plains", "Forest", "Desert", "Swamp", "Tundra", "Jungle", 
		"Savanna", "Mountain", "Beach", "Deep Ocean", "Ice Spires", "Volcanic", "Mushroom"]
	for i in range(biome_names.size()):
		if biome_name == biome_names[i]:
			return i
	return 0


## Check if player is near a biome boundary
func _is_near_biome_boundary() -> bool:
	var pos := _get_player_position()
	var center_biome := _get_biome_id_at_position(pos)
	var check_distance := 50.0
	
	# Sample 4 directions
	var offsets := [
		Vector3(check_distance, 0, 0),
		Vector3(-check_distance, 0, 0),
		Vector3(0, 0, check_distance),
		Vector3(0, 0, -check_distance)
	]
	
	for offset in offsets:
		var sample_biome := _get_biome_id_at_position(pos + offset)
		if sample_biome != center_biome:
			return true
	
	return false


func _log_spike(frame_time_ms: float) -> void:
	var spike := {
		"timestamp": Time.get_ticks_msec(),
		"frame_time_ms": frame_time_ms,
		"position": _get_player_position(),
		"fps": Engine.get_frames_per_second()
	}
	
	spike_log.append(spike)
	if spike_log.size() > MAX_SPIKE_LOG:
		spike_log.pop_front()


## Get current metrics dictionary
func get_metrics() -> Dictionary:
	return _current_metrics.duplicate()


## Get FPS history array
func get_fps_history() -> Array[float]:
	return fps_history.duplicate()


## Get spike log
func get_spike_log() -> Array[Dictionary]:
	return spike_log.duplicate()


## Clear spike log
func clear_spike_log() -> void:
	spike_log.clear()


## Get average FPS over history
func get_average_fps() -> float:
	if fps_history.is_empty():
		return 0.0
	
	var total := 0.0
	for fps in fps_history:
		total += fps
	return total / fps_history.size()


## Get minimum FPS in history
func get_min_fps() -> float:
	if fps_history.is_empty():
		return 0.0
	
	var min_fps := fps_history[0]
	for fps in fps_history:
		if fps < min_fps:
			min_fps = fps
	return min_fps


## Get maximum FPS in history
func get_max_fps() -> float:
	if fps_history.is_empty():
		return 0.0
	
	var max_fps := fps_history[0]
	for fps in fps_history:
		if fps > max_fps:
			max_fps = fps
	return max_fps


func _get_world_seed() -> String:
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if seed_manager:
		return str(seed_manager.get_world_seed())
	return "N/A"


func _get_vegetation_stats() -> Dictionary:
	if VegetationManager:
		return VegetationManager.get_stats()
	return {"total_instances": 0, "tree_count": 0, "bush_count": 0, "rock_count": 0, "grass_count": 0}


func _get_gpu_memory_max() -> float:
	var rd := RenderingServer.get_rendering_device()
	if rd:
		return Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0 * 2.0
	return 0.0


func _calculate_workload_distribution() -> Dictionary:
	var total := _cpu_logic_time_ms + _gpu_compute_time_ms + _gpu_render_time_ms
	if total <= 0.0:
		return {"cpu": 0.33, "gpu_compute": 0.33, "gpu_render": 0.34}
	return {
		"cpu": _cpu_logic_time_ms / total,
		"gpu_compute": _gpu_compute_time_ms / total,
		"gpu_render": _gpu_render_time_ms / total
	}


func get_gpu_compute_time() -> float:
	return _gpu_compute_time_ms


func get_terrain_generation_time() -> float:
	return _terrain_generation_time_ms


func get_vegetation_spawning_time() -> float:
	return _vegetation_spawning_time_ms


func get_performance_warnings() -> Array[String]:
	return _performance_warnings.duplicate()


func _get_gpu_terrain_generator():
	var terrain := get_tree().current_scene.get_node_or_null("VoxelLodTerrain")
	if terrain and terrain.generator:
		# Support both GPUTerrainGenerator and NativeTerrainGenerator
		return terrain.generator
	return null


func _get_biome_gpu_dispatcher() -> BiomeMapGPUDispatcher:
	var gen = _get_gpu_terrain_generator()
	if gen and gen.has_method("get_gpu_dispatcher"):
		return gen.get_gpu_dispatcher()
	return null


func _get_vegetation_gpu_dispatcher():
	var terrain := get_tree().current_scene.get_node_or_null("VoxelLodTerrain")
	if terrain:
		var veg_instancer := terrain.get_node_or_null("VegetationInstancer")
		if veg_instancer and veg_instancer.has_method("get_gpu_dispatcher"):
			return veg_instancer.get_gpu_dispatcher()
	return null


## Get async GPU telemetry from NativeTerrainGenerator
func _get_async_gpu_telemetry() -> Dictionary:
	var terrain_gen = _get_gpu_terrain_generator()
	if terrain_gen and terrain_gen.has_method("get_telemetry"):
		return terrain_gen.get_telemetry()
	return {
		"chunks_dispatched_this_frame": 0,
		"chunks_completed_this_frame": 0,
		"total_chunks_generated": 0,
		"average_gpu_time_ms": 0.0,
		"queue_size": 0,
		"in_flight_chunks": 0,
		"cached_chunks": 0,
		"current_frame_gpu_time_ms": 0.0,
		"frame_budget_ms": 8.0
	}
