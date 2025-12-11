# Etheria Voxel Terrain System

## Architecture Overview

**Current State**: Volumetric Terrain (SDF + Surface Nets).

```mermaid
graph TD
    A[TerrainManager] --> B[3D Chunk Grid]
    B --> C[3D Density Generation (SDF)]
    C --> D[Surface Nets Meshing]
    D --> E[Smooth Terrain Mesh]
```

## Core Components

### TerrainManager (`_engine/terrain/terrain_manager.gd`)
- Manages 3D grid of chunks (`Vector3i`).
- Handles volumetric sphere modification (Digging/Building in 3D).

### Chunk (`_engine/terrain/chunk.gd`)
- **Data**: `PackedFloat32Array` (18x18x18) storing signed distance (density).
- **Meshing**: **Surface Nets Algorithm**.
  - Pass 1: Identifies "Net Vertices" (center of mass of surface crossings) for each cell.
  - Pass 2: Connects Net Vertices to form smooth quads around active edges.
- **Visuals**: Uses `terrain_material.tres` (Triplanar).

## Surface Nets Implementation Details (CRITICAL)

The current implementation is based on **mikolalysenko's canonical Surface Nets**.
**Source**: [https://github.com/mikolalysenko/isosurface](https://github.com/mikolalysenko/isosurface)

### 1. The Edge Table (`CUBE_EDGES`)
**WARNING**: Do not reorder the `CUBE_EDGES` array. The algorithm relies on the first 3 edges being axis-aligned from Corner 0.
- Index 0: `(0, 1)` -> X-Axis from Corner 0
- Index 1: `(0, 2)` -> Y-Axis from Corner 0
- Index 2: `(0, 4)` -> Z-Axis from Corner 0

This is required because the Face Generation loop iterates `axis` from 0 to 2 and checks `edge_mask & (1 << axis)`.

### 2. Winding Order & Back-Face Culling
To prevent "holes" or "dark squares" (inverted normals), the winding order of vertices (1-2-3 vs 1-3-2) must be correct.
The correct logic uses the **mask of Corner 0**:

```gdscript
# mask & 1 checks if Corner 0 (local 0,0,0) is Air (Inside) vs Solid (Outside)
if mask & 1:
    # Corner 0 is "Inside" -> Winding A
    indices.append_array([i0, i1, i2, i2, i1, i3])
else:
    # Corner 0 is "Outside" -> Winding B (Flipped)
    indices.append_array([i0, i2, i1, i1, i2, i3])
```
*Note: Do not try to flip based on "current cell density". Use the corner mask.*

### 3. Analytic Normals
We do NOT use `SurfaceTool.generate_normals()` because it produces faceted/triangular artifacts on low-poly meshes.
Instead, we calculate the exact **Gradient** of the noise function:
```gdscript
Vector3(
    -(h(x+e) - h(x))/e, 
    1.0, 
    -(h(z+e) - h(z))/e
).normalized()
```
This guarantees theoretically perfect smoothness.

## Capabilities
- **Horizontal Mining**: Tunnels and caves are fully supported.
- **Smooth Terrain**: No blocky artifacts; terrain approximates the noise surface smoothly.
- **Deformation**: Sphere-based modification updates the density field.

## Known Limitations
- **LOD**: No Level of Detail system yet (only naive chunks).
