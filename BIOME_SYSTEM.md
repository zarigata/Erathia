# Erathia Biome System

## Overview

The biome system generates a Valheim-style world with diverse biomes, smooth transitions, and procedural vegetation. The world is a circular landmass surrounded by ocean with internal lakes and varied terrain.

## Biome Types

### Primary Biomes (0-12)

| ID | Biome | Base Height | Description |
|----|-------|-------------|-------------|
| 0 | PLAINS | 10m | Flat grasslands with flowers and scattered trees |
| 1 | FOREST | 20m | Dense woodlands with oak, birch, and pine trees |
| 2 | DESERT | 15m | Hot sandy terrain with cacti and dead trees |
| 3 | SWAMP | 3m | Low-lying wetlands with willow trees and murky water |
| 4 | TUNDRA | 40m | Cold frozen plains with sparse vegetation |
| 5 | JUNGLE | 8m | Tropical rainforest - **only spawns near water** |
| 6 | SAVANNA | 12m | Dry grasslands with acacia trees |
| 7 | MOUNTAIN | 120m | High rocky peaks with pine trees |
| 8 | BEACH | 2m | Coastal zones with **palm trees and coconuts** |
| 9 | DEEP_OCEAN | -50m | Underwater zones with no vegetation |
| 10 | ICE_SPIRES | 150m | Frozen mountain peaks with ice formations |
| 11 | VOLCANIC | 100m | Volcanic regions with charred trees and obsidian |
| 12 | MUSHROOM | 30m | Magical zones with giant mushrooms |

### Transition Biomes (13-19)

These biomes handle slopes between different height biomes, enforcing a **maximum 35-degree slope** to prevent vertical cliffs.

| ID | Biome | Purpose |
|----|-------|---------|
| 13 | SLOPE_PLAINS | Grassy hillsides between plains and higher terrain |
| 14 | SLOPE_FOREST | Forested slopes connecting forest to mountains |
| 15 | SLOPE_MOUNTAIN | Rocky mountain slopes |
| 16 | SLOPE_SNOW | Snowy slopes near ice/tundra biomes |
| 17 | SLOPE_VOLCANIC | Ashen slopes around volcanoes |
| 18 | CLIFF_COASTAL | Coastal transitions from beach to highlands |
| 19 | SLOPE_DESERT | Sandy dune slopes in desert regions |

## Key Features

### Maximum Slope Limit (35 Degrees)

All terrain transitions are limited to a maximum slope of 35 degrees (gradient ≈ 0.7). This means:
- No vertical cliffs between biomes
- Natural-looking hillsides and mountain slopes
- Buffer zones automatically sized based on height difference

**Formula:** `buffer_width = height_difference / tan(35°)`

Example: Mountain (120m) to Plains (10m) = 110m difference → 157m buffer zone

### Larger Biomes

Biomes are scaled 2x larger than default noise frequency for more expansive regions. This creates:
- Larger continuous biome areas
- More room for settlements and exploration
- Natural-feeling world layout

### Jungle Near Water Only

Jungle biomes only spawn within 200m of water (ocean or lakes). This creates realistic tropical coastlines and prevents jungle from appearing in landlocked areas.

### Enhanced Beach Biome

Beach biomes feature:
- **Palm trees** (12% density)
- **Coconut piles** as bush variants
- **Shells and driftwood** as small rocks
- **Beach grass** ground cover

Beaches appear:
- Along the ring ocean edge (82-88% of world radius)
- Around internal lakes (continent noise < 0.38)

## World Structure

```
         Ring Ocean (90%+ radius)
              ↓
    ┌─────────────────────────────┐
    │      Beach (82-88%)         │
    │  ┌───────────────────────┐  │
    │  │    Land Biomes        │  │
    │  │  ┌─────────────────┐  │  │
    │  │  │  Internal Lake  │  │  │
    │  │  │    (Beach)      │  │  │
    │  │  └─────────────────┘  │  │
    │  │                       │  │
    │  │  Mountains/Ice Spires │  │
    │  │  with Transition      │  │
    │  │  Slopes               │  │
    │  └───────────────────────┘  │
    └─────────────────────────────┘
              ↑
         World Center (0,0)
```

## Vegetation by Biome

### Beach Vegetation
- Palm trees (procedural with fronds)
- Coconut piles
- Driftwood
- Shells
- Beach grass

### Mountain/Ice Spires Vegetation
- Pine trees (procedural conical)
- Ice rocks
- Frost stones
- Alpine bushes

### Volcanic Vegetation
- Charred/dead trees
- Obsidian rocks
- Ash bushes

### Jungle Vegetation
- Giant jungle trees (tall with dense canopy)
- Tropical palms
- Ferns
- Tropical bushes

## Technical Details

### Files Modified

- `_world/map_generator.gd` - Biome enum with transition biomes
- `_engine/terrain/biome_world_generator.gd` - Height generation with slope limits
- `_world/vegetation/vegetation_manager.gd` - Vegetation rules per biome
- `_world/vegetation/procedural_tree_generator.gd` - Tree mesh generation

### Slope Calculation

```gdscript
# Calculate required buffer zone width for 35-degree max slope
var height_diff = abs(biome_a_height - biome_b_height)
var required_buffer = height_diff / 0.7  # tan(35°) ≈ 0.7

# Transition factor (0 at boundary, 1 in biome center)
var transition_factor = clamp(distance_to_boundary / required_buffer, 0, 1)
transition_factor = smoothstep(0, 1, transition_factor)

# Final height interpolation
var final_height = lerp(boundary_height, biome_height, transition_factor)
```

### Biome Determination Priority

1. Ring ocean (>90% radius) → DEEP_OCEAN
2. Ring beach (82-88% radius) → BEACH
3. Internal ocean (continent < 0.25) → DEEP_OCEAN
4. Internal beach (continent < 0.38) → BEACH
5. Temperature + moisture + mountain noise → Primary biomes

## Future Considerations

- **Cliff biomes** may be added for specific areas that can exceed 35-degree limit
- **Cave entrances** in mountain slopes
- **River biomes** connecting lakes to ocean
- **Faction-specific biome modifications**
