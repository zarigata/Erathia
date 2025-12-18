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
@onready var fps_graph: Control = $Panel/VBoxContainer/FPSGraph

var _visible: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 99
	
	# Add to group for discovery by debug_settings
	add_to_group("performance_overlay_ui")
	
	panel.visible = false
	
	# Connect to PerformanceOverlay signals
	if PerformanceOverlay:
		PerformanceOverlay.metrics_updated.connect(_on_metrics_updated)


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
	
	# Trigger graph redraw only if enabled
	var show_graph: bool = data.get("show_graph", true)
	if show_graph and fps_graph:
		fps_graph.visible = true
		fps_graph.queue_redraw()
	elif fps_graph:
		fps_graph.visible = false


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
