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


func _update_metrics() -> void:
	_current_metrics = {
		"fps": Engine.get_frames_per_second(),
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
		"fps_history": fps_history.duplicate(),
		"show_graph": _show_graph
	}
	
	metrics_updated.emit(_current_metrics)


## Apply settings from debug settings panel
func apply_settings(settings: Dictionary) -> void:
	_update_interval = settings.get("overlay_update_rate", UPDATE_INTERVAL)
	_show_graph = settings.get("overlay_show_graph", true)


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
