extends Node
## RendererFallback - runtime renderer selection guard
##
## Ensures AMD low-performance setups can switch to Mobile renderer early in startup.
## Reads GameSettings graphics.performance_level and graphics.enable_amd_mobile_fallback to
## avoid forcing mobile on other hardware. Runs as autoload before main scene loads.
##
## Behavior:
## - Detects GPU vendor/name via RenderingDevice.
## - If vendor contains "amd" (case-insensitive) AND performance_level is "low" or "auto"
##   AND enable_amd_mobile_fallback is true, the renderer is switched to "mobile".
## - If already on mobile or conditions not met, no change is made.
## - Emits a warning log when a switch occurs for visibility and optional reload handling.

const FALLBACK_VENDOR_KEY: String = "amd"
const PERFORMANCE_KEY: String = "graphics.performance_level"
const FALLBACK_ENABLED_KEY: String = "graphics.enable_amd_mobile_fallback"

func _ready() -> void:
	# Disable AccessKit accessibility bridge to avoid crashes on some drivers (wd null).
	OS.set_environment("GODOT_DISABLE_ACCESSIBILITY", "1")
	_apply_renderer_fallback()


func _apply_renderer_fallback() -> void:
	var settings_performance: String = ""
	var fallback_enabled: bool = true
	if GameSettings:
		var perf_value: Variant = GameSettings.get_setting(PERFORMANCE_KEY)
		if typeof(perf_value) == TYPE_STRING:
			settings_performance = (perf_value as String).to_lower()
		var enabled_value: Variant = GameSettings.get_setting(FALLBACK_ENABLED_KEY)
		if typeof(enabled_value) == TYPE_BOOL:
			fallback_enabled = enabled_value
	
	if not fallback_enabled:
		return
	if settings_performance != "" and settings_performance != "low" and settings_performance != "auto":
		return
	
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return
	var vendor_name: String = ""
	if rd.has_method("get_device_name"):
		vendor_name = rd.get_device_name()
	if rd.has_method("get_device_vendor") and vendor_name == "":
		vendor_name = rd.get_device_vendor()
	var vendor_lower: String = vendor_name.to_lower()
	if vendor_lower == "" or not vendor_lower.contains(FALLBACK_VENDOR_KEY):
		return
	
	var current_renderer: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")
	if current_renderer == "mobile":
		return
	
	ProjectSettings.set_setting("rendering/renderer/rendering_method", "mobile")
	ProjectSettings.set_setting("rendering/renderer/rendering_method.mobile", "mobile")
	push_warning("[RendererFallback] AMD GPU detected (%s); switching renderer to Mobile for stability/performance." % vendor_name)
	# Optional: developer can reload scene manually if needed; we avoid forced reload to prevent interrupting startup.
