extends Node
## World Seed Manager Singleton
##
## Manages the global world seed for all procedural generation systems.
## Generates a random seed on game start and provides it to all generators.
## Registered as autoload "WorldSeedManager" in project.godot

# =============================================================================
# SIGNALS
# =============================================================================

signal seed_changed(new_seed: int)

# =============================================================================
# STATE
# =============================================================================

var _world_seed: int = 0
var _initialized: bool = false

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	if not _initialized:
		regenerate_seed()
	print("[WorldSeedManager] Initialized with seed: %d" % _world_seed)


# =============================================================================
# PUBLIC API
# =============================================================================

## Get the current world seed
func get_world_seed() -> int:
	return _world_seed


## Set a specific world seed (for debugging or loading saves)
func set_world_seed(seed_value: int) -> void:
	if seed_value == _world_seed:
		return
	
	_world_seed = seed_value
	_initialized = true
	print("[WorldSeedManager] Seed set to: %d" % _world_seed)
	seed_changed.emit(_world_seed)


## Generate a new random seed
func regenerate_seed() -> void:
	# Use current time and random for seed generation
	randomize()
	_world_seed = randi() % 999999999
	_initialized = true
	print("[WorldSeedManager] Generated new seed: %d" % _world_seed)
	seed_changed.emit(_world_seed)


## Get seed as a formatted string for display
func get_seed_string() -> String:
	return str(_world_seed)
