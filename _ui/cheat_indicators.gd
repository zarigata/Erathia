extends CanvasLayer
## Cheat Indicators UI
##
## Displays badges for active cheats in the top-left corner.
## Automatically shows/hides based on DevConsole cheat states.

@onready var container: HBoxContainer = $Container

var _badges: Dictionary = {}  # cheat_name -> Control

const BADGE_COLORS: Dictionary = {
	"god": Color(1.0, 0.8, 0.0),      # Gold
	"fly": Color(0.3, 0.7, 1.0),      # Sky blue
	"xray": Color(0.0, 1.0, 0.8),     # Cyan
	"noclip": Color(1.0, 0.5, 0.0),   # Orange
	"speed": Color(0.0, 1.0, 0.3),    # Green
	"infinite_build": Color(1.0, 0.85, 0.0),  # Bright gold
	"infinite_craft": Color(1.0, 0.85, 0.0)   # Bright gold
}

const BADGE_LABELS: Dictionary = {
	"infinite_build": "∞ BUILD",
	"infinite_craft": "∞ CRAFT"
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 98
	
	# Connect to DevConsole signals
	if DevConsole:
		DevConsole.cheat_toggled.connect(_on_cheat_toggled)
	
	# Hide initially
	container.visible = false


func _on_cheat_toggled(cheat_name: String, enabled: bool) -> void:
	# For speed cheat, only show badge when multiplier > 1.0
	if cheat_name == "speed":
		if enabled and DevConsole and DevConsole.speed_multiplier > 1.0:
			_show_badge(cheat_name)
		else:
			_hide_badge(cheat_name)
	elif enabled:
		_show_badge(cheat_name)
	else:
		_hide_badge(cheat_name)
	
	# Update container visibility
	container.visible = _badges.size() > 0


func _show_badge(cheat_name: String) -> void:
	if _badges.has(cheat_name):
		return
	
	var badge := _create_badge(cheat_name)
	container.add_child(badge)
	_badges[cheat_name] = badge
	
	# Start pulse animation
	_start_pulse_animation(badge)


func _hide_badge(cheat_name: String) -> void:
	if not _badges.has(cheat_name):
		return
	
	var badge: Control = _badges[cheat_name]
	badge.queue_free()
	_badges.erase(cheat_name)


func _create_badge(cheat_name: String) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = cheat_name + "_badge"
	
	# Create stylebox
	var style := StyleBoxFlat.new()
	var color: Color = BADGE_COLORS.get(cheat_name, Color.WHITE)
	style.bg_color = Color(color.r, color.g, color.b, 0.3)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	badge.add_theme_stylebox_override("panel", style)
	
	# Create label
	var label := Label.new()
	label.text = BADGE_LABELS.get(cheat_name, cheat_name.to_upper())
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	badge.add_child(label)
	
	return badge


func _start_pulse_animation(badge: Control) -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(badge, "modulate:a", 0.6, 0.5)
	tween.tween_property(badge, "modulate:a", 1.0, 0.5)
