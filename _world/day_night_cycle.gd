class_name DayNightCycle
extends DirectionalLight3D

@export var day_length: float = 60.0 # Seconds for a full day
@export var start_time: float = 0.3 # 0.0 - 1.0 (0.3 is morning)

var time: float = 0.0

func _ready():
	time = start_time * day_length
	_update_sun_position()

func _process(delta):
	time += delta
	if time > day_length:
		time -= day_length
	
	_update_sun_position()

func _update_sun_position():
	# Map time (0 to day_length) to rotation (-90 to 270 degrees)
	# Noon (0.5) should be -90 deg X (straight down)
	# Just rotating around X axis
	var progress = time / day_length
	var angle = progress * 360.0 - 90.0 # Start at -90 (sunrise-ish if rotated right)
	
	rotation_degrees.x = angle
