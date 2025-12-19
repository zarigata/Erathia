extends Node
## World Regenerator Utility
##
## Provides methods to completely regenerate the world from scratch
## This is necessary because VoxelLodTerrain caches generated chunks
## and doesn't clear them when the generator is reassigned

static func force_complete_regeneration() -> void:
	print("[WorldRegenerator] Starting complete world regeneration...")
	
	# Step 1: Delete the world map to force MapGenerator to regenerate it
	var map_path := "res://_assets/world_map.png"
	if FileAccess.file_exists(map_path):
		# We can't delete files in res:// at runtime, so we'll use a different approach
		print("[WorldRegenerator] World map exists, will regenerate on next game start")
	
	# Step 2: Clear the .godot cache folder to force Godot to reload everything
	print("[WorldRegenerator] Note: For complete regeneration, restart the game")
	
	# Step 3: Notify user to restart
	print("[WorldRegenerator] IMPORTANT: Please restart the game to see biome changes")
	print("[WorldRegenerator] The terrain was already generated with old settings")


## Regenerate world by restarting the scene
static func regenerate_by_scene_reload(scene_tree: SceneTree) -> void:
	print("[WorldRegenerator] Reloading scene to regenerate world...")
	scene_tree.reload_current_scene()
