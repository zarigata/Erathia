class_name DebugOverlay
extends VBoxContainer

var _fps_label: Label
var _draw_calls_label: Label
var _memory_label: Label
var _driver_label: Label

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_fps_label = Label.new()
	_draw_calls_label = Label.new()
	_memory_label = Label.new()
	_driver_label = Label.new()
	
	add_child(_fps_label)
	add_child(_draw_calls_label)
	add_child(_memory_label)
	add_child(_driver_label)
	
	# Initial static info
	var video_adapter = RenderingServer.get_video_adapter_name()
	var driver_name = OS.get_name() + " / " + RenderingServer.get_video_adapter_api_version()
	_driver_label.text = "GPU: " + video_adapter + "\nAPI: " + driver_name

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		var tree = get_tree()
		tree.debug_collisions_hint = not tree.debug_collisions_hint
		# Force reload to apply debug shapes? Usually requires SceneTree reload or specific flag usage in Godot 4.
		# Note: debug_collisions_hint usually works for new shapes or if scene reloads.
		# For runtime toggle, we might need:
		# get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME # (Different thing)
		# Actually, tree.debug_collisions_hint is mainly for Editor.
		# Runtime: Control -> Debug -> Visible Collision Shapes.
		# Correct way often involves SceneTree.debug_collisions_hint and maybe creating meshes.
		# Let's try the standard property first.
		print("Hitbox Toggle: ", tree.debug_collisions_hint)

func _process(delta):
	_fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
	
	# Memory
	var mem = OS.get_static_memory_usage()
	_memory_label.text = "RAM: " + String.humanize_size(mem)
	
	# Draw Calls (3D)
	var dc = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_draw_calls_label.text = "Draw Calls: " + str(dc)
