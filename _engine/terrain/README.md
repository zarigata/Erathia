# Terrain Generation System

## Generator: ore_generator.gd

- **Type:** VoxelGeneratorScript (wraps basic_generator.tres)
- **Terrain Style:** Flat plains with gentle hills + procedural ore veins
- **Channels Used:** SDF (terrain shape) + WEIGHTS (material IDs)

### Base Terrain (basic_generator.tres)
- **Noise Frequency:** 0.005 (large features)
- **Hill Amplitude:** 20-30 meters
- **Base Height:** -10 to -20 meters

### Ore Vein Generation
- **Noise Type:** Simplex (FastNoiseLite)
- **Frequency:** 0.02 (~50m wide vein clusters)
- **Threshold:** 0.6 (higher = sparser veins)
- **Min Depth:** 5m below surface
- **Seed:** 67890 (different from terrain)

### Material IDs (WEIGHT Channel)

| ID | Material | Color (RGB) | Usage |
|----|----------|-------------|-------|
| 0 | Air | N/A | Above surface (SDF > 0) |
| 1 | Dirt | (0.4, 0.35, 0.25) | Surface layer (-2 < SDF < 0) |
| 2 | Stone | (0.5, 0.5, 0.5) | Underground base (SDF < -2) |
| 3 | Iron Ore | (0.6, 0.4, 0.2) | Ore veins (noise > 0.6, depth > 5m) |

### Exposed Parameters
```gdscript
@export var ore_frequency: float = 0.02
@export var ore_threshold: float = 0.6
@export var ore_material_id: int = 3
@export var min_ore_depth: float = 5.0
```

## Mesher: VoxelMesherTransvoxel

- **Output:** Smooth triangular meshes
- **Visual Style:** Flat-shaded low-poly (via shader)
- **Material Support:** Reads WEIGHT channel for material IDs

## Shader: terrain_flat_shading.gdshader

- **Flat Shading:** Per-triangle normal recalculation
- **Multi-Material:** Reads material ID from vertex color (COLOR.r)
- **Uniforms:** dirt_color, stone_color, iron_ore_color, roughness

## LOD Configuration

| LOD Level | Distance Range | Detail Level |
|-----------|----------------|--------------|
| 0 | 0-32m | Highest |
| 1 | 32-64m | High |
| 2 | 64-128m | Medium |
| 3 | 128-256m | Low |
| 4 | 256-512m | Lowest |

## File Structure

```
_engine/terrain/
├── basic_generator.tres          # Base noise terrain (SDF only)
├── ore_generator.gd              # Main generator with ore veins
├── terrain_material.tres         # ShaderMaterial reference
├── terrain_flat_shading.gdshader # Multi-material flat shader
└── README.md                     # This file
```

## Future Enhancements

- Add biome-specific noise variations
- Add more ore types (copper, gold, etc.)
- Add cave systems (SDF subtraction)
- Convert to VoxelGeneratorGraph for visual editing
