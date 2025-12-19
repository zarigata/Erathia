# Terrain Regeneration Guide

## The Problem

The terrain appears **uniform gray with no biome variation or vegetation** because:

1. **VoxelLodTerrain caches generated chunks** - Once terrain chunks are generated, they are cached in memory
2. **Biome height modulation was enabled AFTER terrain generation** - The terrain was generated with `height_modulation_strength = 0.0`, then we changed it to `0.25`
3. **Simply reassigning the generator doesn't clear the cache** - VoxelLodTerrain keeps the old cached chunks even when you reassign the generator

## The Root Cause

When the game first starts:
1. VoxelLodTerrain generates terrain chunks using BiomeAwareGenerator
2. At that moment, `height_modulation_strength = 0.0` (disabled)
3. Chunks are generated as uniform terrain and cached
4. We then enabled `height_modulation_strength = 0.25`
5. But the cached chunks remain unchanged

## The Solution

To see biome variation and vegetation, you need to **force complete terrain regeneration** by reloading the scene.

### Method 1: Use Dev Console (Recommended)

1. Press **`** (backtick/tilde key) to open the dev console
2. Type: `regenerate_world`
3. Press Enter
4. The scene will reload with a new seed and regenerated terrain

### Method 2: Restart the Game

Simply close and restart the game. The terrain will regenerate on startup.

### Method 3: Delete World Map (Nuclear Option)

1. Navigate to `_assets/world_map.png`
2. Delete the file
3. Restart the game
4. MapGenerator will create a new world map
5. Terrain will generate with the new biome data

## What You Should See After Regeneration

With `height_modulation_strength = 0.25` enabled, you should see:

- **Height variation** - Mountains higher than plains, oceans lower
- **Biome-specific materials**:
  - Sand in deserts and beaches
  - Snow in tundra and ice spires
  - Grass/dirt in plains and forests
  - Stone in mountains
- **Vegetation** - Trees, bushes, rocks, and grass spawning based on biome
- **Smooth biome transitions** - 15-meter blend zones at biome boundaries

## Technical Details

### Why Toggling Visibility Doesn't Work

```gdscript
# This DOESN'T clear cached chunks:
terrain.visible = false
terrain.generator = null
await get_tree().process_frame
terrain.generator = biome_generator
terrain.visible = true
```

VoxelLodTerrain's internal chunk cache persists even when the node is disabled.

### Why Scene Reload Works

```gdscript
# This DOES clear everything:
get_tree().reload_current_scene()
```

Reloading the scene destroys the VoxelLodTerrain node completely, clearing all cached chunks. When the scene loads again, terrain generates from scratch with the new settings.

## Adjusting Biome Strength

You can adjust biome height variation at runtime:

1. Open dev console (`)
2. Type: `set_biome_strength 0.5` (range: 0.0-1.0)
3. Type: `regenerate_world` to apply changes

**Recommended values:**
- `0.0` - Disabled (uniform terrain)
- `0.1-0.2` - Subtle variation
- `0.25` - Medium variation (default)
- `0.3-0.4` - Strong variation
- `0.5+` - Extreme variation (may cause artifacts)

## Settings UI

You can also adjust biome settings in the Settings menu:
1. Open inventory (Tab)
2. Click Settings button
3. Go to Graphics tab
4. Adjust "Biome Height Variation" slider
5. Close settings
6. Use dev console: `regenerate_world` to apply

## Future Improvements

To make terrain regeneration automatic in future sessions:

1. **Add a "Regenerate World" button** in the main menu
2. **Detect when biome settings change** and prompt user to regenerate
3. **Implement streaming regeneration** that gradually replaces old chunks
4. **Use VoxelLodTerrain.cache_generated_blocks** with manual cache clearing

## Dev Console Commands

Useful commands for world generation:

- `regenerate_world` - Generate new seed and reload scene
- `set_biome_strength <0.0-1.0>` - Adjust height modulation
- `world_status` - Show current world state
- `validate_world` - Check terrain and vegetation
- `veg_stats` - Show vegetation instance counts
- `show_seed` - Display current world seed
- `set_seed <number>` - Set specific seed

## Why This Happened

The world initialization system we implemented works correctly for:
- ✅ Loading screen with progress tracking
- ✅ Staged initialization pipeline
- ✅ Chunk pre-warming
- ✅ Vegetation spawning
- ✅ Validation checks

However, it doesn't account for the fact that **terrain was already generated before we enabled biome features**. The initialization system runs on every game start, but VoxelLodTerrain's cache persists across the initialization stages.

## Conclusion

**To see biome variation and vegetation RIGHT NOW:**

1. Press **`** to open dev console
2. Type: **`regenerate_world`**
3. Press **Enter**
4. Wait for scene to reload

The terrain will regenerate with proper biome height variation, materials, and vegetation!
