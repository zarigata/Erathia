extends Control
## Debug Settings Panel
##
## Configuration panel for debug tools.
## Toggle with F10 key or 'settings' console command.

signal settings_changed()

@onready var panel: PanelContainer = $Panel
@onready var console_font_size: SpinBox = $Panel/TabContainer/Console/VBoxContainer/FontSizeContainer/FontSizeSpinBox
@onready var console_history_length: SpinBox = $Panel/TabContainer/Console/VBoxContainer/HistoryLengthContainer/HistoryLengthSpinBox
@onready var console_autocomplete: CheckBox = $Panel/TabContainer/Console/VBoxContainer/AutocompleteCheck
@onready var overlay_update_rate: SpinBox = $Panel/TabContainer/Performance/VBoxContainer/UpdateRateContainer/UpdateRateSpinBox
@onready var overlay_show_graph: CheckBox = $Panel/TabContainer/Performance/VBoxContainer/ShowGraphCheck
@onready var overlay_show_gpu_metrics: CheckBox = $Panel/TabContainer/Performance/VBoxContainer/ShowGPUMetricsCheck
@onready var overlay_show_breakdown: CheckBox = $Panel/TabContainer/Performance/VBoxContainer/ShowBreakdownCheck
@onready var cpu_budget_spin: SpinBox = $Panel/TabContainer/Performance/VBoxContainer/CPUBudgetContainer/CPUBudgetSpinBox
@onready var gpu_compute_budget_spin: SpinBox = $Panel/TabContainer/Performance/VBoxContainer/GPUComputeBudgetContainer/GPUComputeBudgetSpinBox
@onready var warn_budget_check: CheckBox = $Panel/TabContainer/Performance/VBoxContainer/WarnBudgetCheck
@onready var xray_label_distance: SpinBox = $Panel/TabContainer/XRay/VBoxContainer/LabelDistanceContainer/LabelDistanceSpinBox
@onready var xray_transparency: Slider = $Panel/TabContainer/XRay/VBoxContainer/TransparencyContainer/TransparencySlider

var _visible: bool = false
var _settings: Dictionary = {}

const SETTINGS_PATH: String = "user://debug_settings.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	
	_load_settings()
	_apply_settings_to_ui()
	_apply_settings_to_tools()
	
	# Register settings command with DevConsole
	if DevConsole:
		DevConsole.register_command("settings", _cmd_settings, "Open/close debug settings panel")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_settings"):
		_toggle_panel()
		get_viewport().set_input_as_handled()


func _toggle_panel() -> void:
	_visible = not _visible
	panel.visible = _visible
	
	if _visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	
	if err != OK:
		# Use defaults
		_settings = {
			"console_font_size": 14,
			"console_history_length": 50,
			"console_autocomplete": true,
			"overlay_update_rate": 0.1,
			"overlay_show_graph": true,
			"performance_show_gpu_metrics": true,
			"performance_show_breakdown": false,
			"performance_cpu_budget_ms": 16.67,
			"performance_gpu_compute_budget_ms": 5.0,
			"performance_warn_on_budget_exceed": true,
			"xray_label_distance": 50.0,
			"xray_transparency": 0.3
		}
		return
	
	_settings = {
		"console_font_size": config.get_value("console", "font_size", 14),
		"console_history_length": config.get_value("console", "history_length", 50),
		"console_autocomplete": config.get_value("console", "autocomplete", true),
		"overlay_update_rate": config.get_value("performance", "update_rate", 0.1),
		"overlay_show_graph": config.get_value("performance", "show_graph", true),
		"performance_show_gpu_metrics": config.get_value("performance", "show_gpu_metrics", true),
		"performance_show_breakdown": config.get_value("performance", "show_breakdown", false),
		"performance_cpu_budget_ms": config.get_value("performance", "cpu_budget_ms", 16.67),
		"performance_gpu_compute_budget_ms": config.get_value("performance", "gpu_compute_budget_ms", 5.0),
		"performance_warn_on_budget_exceed": config.get_value("performance", "warn_budget_exceed", true),
		"xray_label_distance": config.get_value("xray", "label_distance", 50.0),
		"xray_transparency": config.get_value("xray", "transparency", 0.3)
	}


func _save_settings() -> void:
	var config := ConfigFile.new()
	
	config.set_value("console", "font_size", _settings.console_font_size)
	config.set_value("console", "history_length", _settings.console_history_length)
	config.set_value("console", "autocomplete", _settings.console_autocomplete)
	config.set_value("performance", "update_rate", _settings.overlay_update_rate)
	config.set_value("performance", "show_graph", _settings.overlay_show_graph)
	config.set_value("performance", "show_gpu_metrics", _settings.performance_show_gpu_metrics)
	config.set_value("performance", "show_breakdown", _settings.performance_show_breakdown)
	config.set_value("performance", "cpu_budget_ms", _settings.performance_cpu_budget_ms)
	config.set_value("performance", "gpu_compute_budget_ms", _settings.performance_gpu_compute_budget_ms)
	config.set_value("performance", "warn_budget_exceed", _settings.performance_warn_on_budget_exceed)
	config.set_value("xray", "label_distance", _settings.xray_label_distance)
	config.set_value("xray", "transparency", _settings.xray_transparency)
	
	config.save(SETTINGS_PATH)


func _apply_settings_to_ui() -> void:
	if console_font_size:
		console_font_size.value = _settings.console_font_size
	if console_history_length:
		console_history_length.value = _settings.console_history_length
	if console_autocomplete:
		console_autocomplete.button_pressed = _settings.console_autocomplete
	if overlay_update_rate:
		overlay_update_rate.value = _settings.overlay_update_rate
	if overlay_show_graph:
		overlay_show_graph.button_pressed = _settings.overlay_show_graph
	if overlay_show_gpu_metrics:
		overlay_show_gpu_metrics.button_pressed = _settings.performance_show_gpu_metrics
	if overlay_show_breakdown:
		overlay_show_breakdown.button_pressed = _settings.performance_show_breakdown
	if cpu_budget_spin:
		cpu_budget_spin.value = _settings.performance_cpu_budget_ms
	if gpu_compute_budget_spin:
		gpu_compute_budget_spin.value = _settings.performance_gpu_compute_budget_ms
	if warn_budget_check:
		warn_budget_check.button_pressed = _settings.performance_warn_on_budget_exceed
	if xray_label_distance:
		xray_label_distance.value = _settings.xray_label_distance
	if xray_transparency:
		xray_transparency.value = _settings.xray_transparency


func get_setting(key: String) -> Variant:
	return _settings.get(key, null)


func _on_font_size_changed(value: float) -> void:
	_settings.console_font_size = int(value)
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_history_length_changed(value: float) -> void:
	_settings.console_history_length = int(value)
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_autocomplete_toggled(toggled_on: bool) -> void:
	_settings.console_autocomplete = toggled_on
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_update_rate_changed(value: float) -> void:
	_settings.overlay_update_rate = value
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_show_graph_toggled(toggled_on: bool) -> void:
	_settings.overlay_show_graph = toggled_on
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_show_gpu_metrics_toggled(toggled_on: bool) -> void:
	_settings.performance_show_gpu_metrics = toggled_on
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_show_breakdown_toggled(toggled_on: bool) -> void:
	_settings.performance_show_breakdown = toggled_on
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_cpu_budget_changed(value: float) -> void:
	_settings.performance_cpu_budget_ms = value
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_gpu_compute_budget_changed(value: float) -> void:
	_settings.performance_gpu_compute_budget_ms = value
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_warn_budget_toggled(toggled_on: bool) -> void:
	_settings.performance_warn_on_budget_exceed = toggled_on
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_label_distance_changed(value: float) -> void:
	_settings.xray_label_distance = value
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_transparency_changed(value: float) -> void:
	_settings.xray_transparency = value
	_save_settings()
	_apply_settings_to_tools()
	settings_changed.emit()


func _on_close_pressed() -> void:
	_toggle_panel()


## Toggle panel visibility (public for console command)
func toggle_panel() -> void:
	_toggle_panel()


## Console command handler
func _cmd_settings(args: Array[String]) -> String:
	_toggle_panel()
	return "Debug settings panel: %s" % ("opened" if _visible else "closed")


## Apply current settings to all debug tools
func _apply_settings_to_tools() -> void:
	# Apply to DevConsoleUI
	var console_ui := _find_dev_console_ui()
	if console_ui:
		console_ui.apply_settings(_settings)
	
	# Apply to PerformanceOverlay
	if PerformanceOverlay:
		PerformanceOverlay.apply_settings(_settings)
		if PerformanceOverlay.has_method("set_performance_budgets"):
			PerformanceOverlay.set_performance_budgets({
				"cpu_budget_ms": _settings.get("performance_cpu_budget_ms", 16.67),
				"gpu_compute_budget_ms": _settings.get("performance_gpu_compute_budget_ms", 5.0),
				"warn_enabled": _settings.get("performance_warn_on_budget_exceed", true),
				"terrain_budget_ms": PerformanceOverlay.TERRAIN_GEN_BUDGET_MS if PerformanceOverlay.has_method("set_performance_budgets") else 3.0,
				"vegetation_budget_ms": PerformanceOverlay.VEGETATION_BUDGET_MS if PerformanceOverlay.has_method("set_performance_budgets") else 2.0
			})
	
	# Apply to PerformanceOverlayUI
	var perf_ui := _find_performance_overlay_ui()
	if perf_ui:
		perf_ui.apply_settings(_settings)
	
	# Apply to FPS Graph
	var fps_graph := _find_fps_graph()
	if fps_graph and fps_graph.has_method("set_show_breakdown"):
		fps_graph.set_show_breakdown(_settings.get("performance_show_breakdown", false))
	
	# Apply to XRayManager and NodeInspector
	if DevConsole and DevConsole.xray_manager:
		DevConsole.xray_manager.apply_settings(_settings)


func _find_dev_console_ui() -> Node:
	var nodes := get_tree().get_nodes_in_group("dev_console_ui")
	if nodes.size() > 0:
		return nodes[0]
	# Fallback: search by class
	for node in get_tree().root.get_children():
		if node.has_method("apply_settings") and node.name.contains("Console"):
			return node
	return null


func _find_performance_overlay_ui() -> Node:
	var nodes := get_tree().get_nodes_in_group("performance_overlay_ui")
	if nodes.size() > 0:
		return nodes[0]
	# Fallback: search by class
	for node in get_tree().root.get_children():
		if node.has_method("apply_settings") and node.name.contains("Performance"):
			return node
	return null


func _find_fps_graph() -> Node:
	var perf_ui := _find_performance_overlay_ui()
	if perf_ui and perf_ui.has_node("Panel/VBoxContainer/FPSGraph"):
		return perf_ui.get_node("Panel/VBoxContainer/FPSGraph")
	return null
