extends CanvasLayer
class_name LoadingScreen
## Loading Screen UI
##
## Full-screen overlay that displays during world initialization.
## Shows progress through stages with visual feedback.

# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var background: ColorRect = $Background
@onready var center_container: CenterContainer = $CenterContainer
@onready var main_panel: PanelContainer = $CenterContainer/MainPanel
@onready var title_label: Label = $CenterContainer/MainPanel/VBoxContainer/TitleLabel
@onready var progress_bar: ProgressBar = $CenterContainer/MainPanel/VBoxContainer/ProgressBar
@onready var stage_label: Label = $CenterContainer/MainPanel/VBoxContainer/StageLabel
@onready var status_label: Label = $CenterContainer/MainPanel/VBoxContainer/StatusLabel
@onready var attempt_label: Label = $CenterContainer/MainPanel/VBoxContainer/AttemptLabel
@onready var seed_label: Label = $CenterContainer/MainPanel/VBoxContainer/SeedLabel
@onready var error_panel: PanelContainer = $CenterContainer/MainPanel/VBoxContainer/ErrorPanel
@onready var error_label: Label = $CenterContainer/MainPanel/VBoxContainer/ErrorPanel/ErrorLabel

# Stage indicators
@onready var stage_map: Label = $CenterContainer/MainPanel/VBoxContainer/StageContainer/StageMap
@onready var stage_terrain: Label = $CenterContainer/MainPanel/VBoxContainer/StageContainer/StageTerrain
@onready var stage_vegetation: Label = $CenterContainer/MainPanel/VBoxContainer/StageContainer/StageVegetation
@onready var stage_validate: Label = $CenterContainer/MainPanel/VBoxContainer/StageContainer/StageValidate

# =============================================================================
# CONSTANTS
# =============================================================================

const COLOR_PENDING := Color(0.5, 0.5, 0.5)
const COLOR_IN_PROGRESS := Color(1.0, 0.8, 0.2)
const COLOR_COMPLETE := Color(0.2, 0.8, 0.2)
const COLOR_FAILED := Color(0.8, 0.2, 0.2)

# =============================================================================
# STATE
# =============================================================================

var _world_init_manager: Node = null

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100  # Above everything else
	
	# Start hidden
	visible = false
	
	# Hide error panel initially
	if error_panel:
		error_panel.visible = false
	
	# Connect to WorldInitManager when it's available
	call_deferred("_connect_to_init_manager")


func _connect_to_init_manager() -> void:
	_world_init_manager = get_node_or_null("/root/WorldInitManager")
	if _world_init_manager:
		_world_init_manager.initialization_started.connect(_on_initialization_started)
		_world_init_manager.stage_completed.connect(_on_stage_completed)
		_world_init_manager.initialization_complete.connect(_on_initialization_complete)
		_world_init_manager.initialization_failed.connect(_on_initialization_failed)
		print("[LoadingScreen] Connected to WorldInitManager")
	else:
		push_warning("[LoadingScreen] WorldInitManager not found")

# =============================================================================
# PUBLIC API
# =============================================================================

## Show the loading screen
func show_loading() -> void:
	visible = true
	
	# Reset UI state
	if progress_bar:
		progress_bar.value = 0
	
	if error_panel:
		error_panel.visible = false
	
	_reset_stage_indicators()
	_update_seed_display()
	
	# Ensure mouse is visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Hide the loading screen
func hide_loading() -> void:
	visible = false


## Update progress display
func update_progress(progress: float, stage_name: String, status_text: String = "") -> void:
	if progress_bar:
		progress_bar.value = progress * 100.0
	
	if stage_label:
		stage_label.text = stage_name
	
	if status_label and status_text != "":
		status_label.text = status_text
	
	_update_stage_indicators(stage_name)


## Update attempt counter display
func update_attempt(current: int, max_attempts: int) -> void:
	if attempt_label:
		if current > 1:
			attempt_label.text = "Attempt %d/%d" % [current, max_attempts]
			attempt_label.visible = true
		else:
			attempt_label.visible = false


## Show error message
func show_error(message: String) -> void:
	if error_panel:
		error_panel.visible = true
	if error_label:
		error_label.text = "Error: %s\nPlease restart the game." % message

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_initialization_started() -> void:
	show_loading()
	
	if _world_init_manager:
		update_attempt(_world_init_manager.get_current_attempt(), _world_init_manager.get_max_attempts())


func _on_stage_completed(stage_name: String, progress: float) -> void:
	if not _world_init_manager:
		return
	
	var total_progress: float = _world_init_manager.get_total_progress()
	update_progress(total_progress, stage_name, _get_status_text(stage_name, progress))
	update_attempt(_world_init_manager.get_current_attempt(), _world_init_manager.get_max_attempts())


func _on_initialization_complete() -> void:
	if progress_bar:
		progress_bar.value = 100
	
	if stage_label:
		stage_label.text = "Complete!"
	
	if status_label:
		status_label.text = "World ready. Starting game..."
	
	_set_all_stages_complete()
	
	# Brief delay before hiding
	await get_tree().create_timer(0.5).timeout
	hide_loading()


func _on_initialization_failed(reason: String) -> void:
	show_error(reason)
	
	if stage_label:
		stage_label.text = "Initialization Failed"
	
	if status_label:
		status_label.text = reason

# =============================================================================
# HELPERS
# =============================================================================

func _update_seed_display() -> void:
	if not seed_label:
		return
	
	var seed_manager = get_node_or_null("/root/WorldSeedManager")
	if seed_manager and seed_manager.has_method("get_world_seed"):
		var world_seed: int = seed_manager.call("get_world_seed")
		seed_label.text = "World Seed: %d" % world_seed
	else:
		seed_label.text = "World Seed: N/A"


func _get_status_text(stage_name: String, progress: float) -> String:
	var percent := int(progress * 100)
	
	match stage_name:
		"Generating World Map":
			return "Creating biome map... %d%%" % percent
		"Loading Biomes":
			return "Initializing biome data... %d%%" % percent
		"Warming Terrain":
			return "Generating terrain chunks... %d%%" % percent
		"Spawning Vegetation":
			return "Placing trees and plants... %d%%" % percent
		"Validating World":
			return "Verifying world integrity... %d%%" % percent
		# New pipeline phases
		"Continental Shape":
			return "Generating landmasses and ocean boundaries..."
		"Climate Zones":
			return "Computing temperature and moisture..."
		"Biome Placement":
			return "Assigning biomes based on climate..."
		"Height Map":
			return "Creating mountains, plains, and coastlines..."
		"Terrain Blending":
			return "Smoothing terrain transitions..."
		"Water Bodies":
			return "Filling oceans, lakes, and rivers..."
		"Material Assignment":
			return "Texturing terrain surfaces..."
		"Vegetation Prep":
			return "Preparing vegetation spawn points..."
		"Initializing Terrain":
			return "Creating voxel terrain system..."
		"Generating Chunks":
			return "Building initial terrain chunks..."
		"Finding Spawn":
			return "Locating safe spawn position..."
		"Complete":
			return "World ready! Starting game..."
		_:
			return "%d%%" % percent


func _reset_stage_indicators() -> void:
	if stage_map:
		stage_map.modulate = COLOR_PENDING
	if stage_terrain:
		stage_terrain.modulate = COLOR_PENDING
	if stage_vegetation:
		stage_vegetation.modulate = COLOR_PENDING
	if stage_validate:
		stage_validate.modulate = COLOR_PENDING


func _update_stage_indicators(current_stage: String) -> void:
	# Reset all to pending
	_reset_stage_indicators()
	
	match current_stage:
		"Generating World Map", "Loading Biomes":
			if stage_map:
				stage_map.modulate = COLOR_IN_PROGRESS
		"Warming Terrain":
			if stage_map:
				stage_map.modulate = COLOR_COMPLETE
			if stage_terrain:
				stage_terrain.modulate = COLOR_IN_PROGRESS
		"Spawning Vegetation":
			if stage_map:
				stage_map.modulate = COLOR_COMPLETE
			if stage_terrain:
				stage_terrain.modulate = COLOR_COMPLETE
			if stage_vegetation:
				stage_vegetation.modulate = COLOR_IN_PROGRESS
		"Validating World":
			if stage_map:
				stage_map.modulate = COLOR_COMPLETE
			if stage_terrain:
				stage_terrain.modulate = COLOR_COMPLETE
			if stage_vegetation:
				stage_vegetation.modulate = COLOR_COMPLETE
			if stage_validate:
				stage_validate.modulate = COLOR_IN_PROGRESS


func _set_all_stages_complete() -> void:
	if stage_map:
		stage_map.modulate = COLOR_COMPLETE
	if stage_terrain:
		stage_terrain.modulate = COLOR_COMPLETE
	if stage_vegetation:
		stage_vegetation.modulate = COLOR_COMPLETE
	if stage_validate:
		stage_validate.modulate = COLOR_COMPLETE
