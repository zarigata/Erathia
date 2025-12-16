# Migrating to godot_voxel Engine

This document explains how to switch from the custom chunk-based terrain to the Zylann godot_voxel module.

## Step 1: Use the godot_voxel Editor

Instead of the Steam Godot, run the custom build with godot_voxel:

```
temp_download\godot_voxel_editor\godot.windows.editor.x86_64.exe
```

Open the project with this executable.

## Step 2: Remove .gdignore

The voxel files are in `_engine/terrain/voxel_module/` with a `.gdignore` file that prevents standard Godot from loading them. When using the godot_voxel editor:

1. Delete `_engine/terrain/voxel_module/.gdignore`
2. Reimport the project (Project > Reload Current Project)

## Step 3: Use the New Scenes

### Main Game Scene
Use `_engine/terrain/voxel_module/MainGameVoxel.tscn` instead of `MainGame.tscn`:
- Contains `VoxelLodTerrain` instead of custom `TerrainManager`
- Uses the same biome/height generation logic
- Supports proper VoxelTool mining

### Player Scene (Optional)
Use `_player/player_voxel.tscn` for a player with `VoxelMiningTool`:
- Uses VoxelTool.raycast for precise terrain hits
- Uses VoxelTool.do_sphere for terrain deformation
- Includes visual feedback (particles, hit markers)

## Voxel Module Files (in `_engine/terrain/voxel_module/`)

### Terrain Generation
- `voxel_terrain_generator.gd` - VoxelGeneratorScript using your BiomeManager logic
- `VoxelTerrain.tscn` - VoxelLodTerrain scene with Transvoxel mesher

### Mining Tool
- `VoxelMiningTool.gd` - Mining with VoxelTool and visual feedback

### Scenes
- `MainGameVoxel.tscn` - Main game using VoxelLodTerrain

**Note:** These files are ignored by standard Godot via `.gdignore` to prevent parse errors.

## Features

### Terrain Generation (Preserved)
- Continental noise with domain warping
- Beach/ocean/mountain biomes
- Smooth height transitions
- Enhanced mountain peaks at high erosion

### Mining (New)
- VoxelTool.raycast for precise hit detection
- VoxelTool.do_sphere for terrain deformation
- Visual feedback:
  - Hit marker (glowing sphere)
  - Particle effects on dig/build
  - Color-coded (orange=dig, green=build)

### Controls
- **Left Click**: Dig terrain
- **Right Click**: Build terrain
- **1**: Pickaxe (sphere dig)
- **2**: Shovel (larger dig)
- **3**: Hoe (smoothing)

## Troubleshooting

### "VoxelGeneratorScript not found"
Make sure you're using the godot_voxel editor, not the Steam version.

### Terrain not generating
Check that `VoxelTerrain` node exists and has the generator script assigned.

### Mining not working
Ensure `VoxelMiningTool` is a child of `Camera3D` and collision is enabled on VoxelLodTerrain.
