class_name DayNightCycle
extends DirectionalLight3D

# Config
@export var time_scale: float = 60.0 # 1.0 = real time, 60.0 = 1 game hour per real minute
@export var use_real_time: bool = false

# Internal
var current_time: float = 0.0 # Seconds since midnight (0 - 86400)
const SECONDS_IN_DAY = 86400.0

func _ready():
	if use_real_time:
		_sync_to_real_time()
	else:
		current_time = 12.0 * 3600.0 # Start at Noon
	_update_sun_position()

func _process(delta):
	if use_real_time:
		_sync_to_real_time()
	else:
		current_time += delta * time_scale
		if current_time > SECONDS_IN_DAY:
			current_time -= SECONDS_IN_DAY
	
	_update_sun_position()

func _sync_to_real_time():
	var time_dict = Time.get_time_dict_from_system()
	var hours = time_dict["hour"]
	var minutes = time_dict["minute"]
	var seconds = time_dict["second"]
	current_time = hours * 3600.0 + minutes * 60.0 + seconds

func _update_sun_position():
	# Map current_time (0 - 86400) to rotation (-90 to 270 degrees)
	# Noon (12:00 = 43200s) should be -90 deg X (straight down)
	
	var progress = current_time / SECONDS_IN_DAY
	# 0.0 (Midnight) -> Start
	# 0.5 (Noon) -> Overhead
	
	# If progress is 0.0 (midnight), we want sun at bottom (90 deg)
	# If progress is 0.25 (6 AM), we want sun at horizon (0 deg)
	# If progress is 0.5 (Noon), we want sun at top (-90 deg)
	
	# If progress is 0.5 (Noon), we want sun at top (-90 deg)
	
	# Adjust so 6AM is sunrise (0 deg), Noon is -90.
	# formula: angle = (progress * 360) + offset
	# Noon (0.5) -> 180 + offset = -90 => offset = -270
	
	# Let's align it simply:
	# Midnight (0.0) = 90 deg (Bottom)
	# Noon (0.5) = -90 deg (Top)
	
	rotation_degrees.x = (progress * 360.0) - 270.0
