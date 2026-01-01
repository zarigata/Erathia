extends Control
## FPS Graph Control
##
## Draws a line graph of FPS history.

const GRAPH_HEIGHT: float = 60.0
const MAX_FPS: float = 120.0
const MIN_FPS: float = 0.0

var _fps_history: Array[float] = []
var _show_breakdown: bool = false
var _breakdown_data: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(200, GRAPH_HEIGHT)


func _draw() -> void:
	# Get FPS history from PerformanceOverlay
	if PerformanceOverlay:
		_fps_history = PerformanceOverlay.get_fps_history()
		_breakdown_data = PerformanceOverlay.get_metrics().get("workload_distribution", {})
	
	if _fps_history.is_empty():
		return
	
	var rect := get_rect()
	var width := rect.size.x
	var height := rect.size.y
	
	# Draw background
	draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0.1, 0.1, 0.1, 0.8))
	
	# Draw reference lines
	var line_60 := height - (60.0 / MAX_FPS) * height
	var line_30 := height - (30.0 / MAX_FPS) * height
	
	draw_line(Vector2(0, line_60), Vector2(width, line_60), Color(0.0, 0.5, 0.0, 0.5), 1.0)
	draw_line(Vector2(0, line_30), Vector2(width, line_30), Color(0.5, 0.5, 0.0, 0.5), 1.0)
	
	# Draw FPS graph
	if _fps_history.size() < 2:
		return
	
	var point_spacing := width / float(_fps_history.size() - 1)
	var points: PackedVector2Array = []
	var colors: PackedColorArray = []
	
	for i in range(_fps_history.size()):
		var fps := _fps_history[i]
		var x := i * point_spacing
		var y := height - (clampf(fps, MIN_FPS, MAX_FPS) / MAX_FPS) * height
		points.append(Vector2(x, y))
		colors.append(_get_fps_color(fps))
	
	# Draw line segments with colors
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], colors[i], 2.0, true)
	
	# Draw current FPS text
	if not _fps_history.is_empty():
		var current_fps := _fps_history[-1]
		var avg_fps := _get_average()
		var min_fps := _get_min()
		
		draw_string(
			ThemeDB.fallback_font,
			Vector2(4, 12),
			"Cur: %d" % int(current_fps),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			10,
			_get_fps_color(current_fps)
		)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(4, 24),
			"Avg: %d" % int(avg_fps),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			10,
			Color.WHITE
		)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(4, 36),
			"Min: %d" % int(min_fps),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			10,
			_get_fps_color(min_fps)
		)
	
	if _show_breakdown and PerformanceOverlay:
		_draw_frame_breakdown()


func _get_fps_color(fps: float) -> Color:
	if fps >= 60.0:
		return Color.LIME
	elif fps >= 30.0:
		return Color.YELLOW
	else:
		return Color.RED


func _get_average() -> float:
	if _fps_history.is_empty():
		return 0.0
	var total := 0.0
	for fps in _fps_history:
		total += fps
	return total / _fps_history.size()


func _get_min() -> float:
	if _fps_history.is_empty():
		return 0.0
	var min_val := _fps_history[0]
	for fps in _fps_history:
		if fps < min_val:
			min_val = fps
	return min_val


func set_show_breakdown(enabled: bool) -> void:
	_show_breakdown = enabled
	queue_redraw()


func _draw_frame_breakdown() -> void:
	var rect := get_rect()
	var breakdown_height := 20.0
	var y_offset := rect.size.y - breakdown_height - 5.0
	
	var workload := _breakdown_data
	var cpu_pct: float = workload.get("cpu", 0.33)
	var compute_pct: float = workload.get("gpu_compute", 0.33)
	var render_pct: float = workload.get("gpu_render", 0.34)
	
	var width := rect.size.x
	var cpu_width: float = width * cpu_pct
	var compute_width: float = width * compute_pct
	var render_width: float = width * render_pct
	
	draw_rect(Rect2(0, y_offset, cpu_width, breakdown_height), Color(0.8, 0.3, 0.3, 0.8))
	draw_rect(Rect2(cpu_width, y_offset, compute_width, breakdown_height), Color(0.3, 0.8, 0.3, 0.8))
	draw_rect(Rect2(cpu_width + compute_width, y_offset, render_width, breakdown_height), Color(0.3, 0.3, 0.8, 0.8))
	
	draw_string(ThemeDB.fallback_font, Vector2(5, y_offset + 14), "CPU", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(cpu_width + 5, y_offset + 14), "Compute", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(cpu_width + compute_width + 5, y_offset + 14), "Render", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
