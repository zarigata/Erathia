# Erathia Terrain Native

C++ GDExtension for GPU-accelerated terrain generation in Godot 4.4+.

## Prerequisites

- **CMake** 3.20+
- **C++17 Compiler**:
  - Windows: Visual Studio 2022 (MSVC)
  - Linux: GCC 9+ or Clang 10+
  - macOS: Xcode 12+ (Apple Clang)
- **Git** (for submodules)

## Build Instructions

### First-Time Setup

```bash
cd addons/erathia_terrain_native
git submodule update --init --recursive
```

### Windows

```batch
build_windows.bat
```

### Linux

```bash
./build_linux.sh
```

### macOS

```bash
./build_macos.sh
```

## Verification

1. Open Godot project
2. Check **Project → Project Settings → Plugins** for "Erathia Terrain Native"
3. Create a test scene with `NativeTerrainTest` node
4. Run the scene and check console output:
   ```
   [NativeTerrainTest] C++ GDExtension loaded successfully!
   [NativeTerrainTest] GPU Available: true
   [NativeTerrainTest] GPU Device: NVIDIA GeForce RTX 3080
   ```

## Troubleshooting

### "Entry symbol not found"
- Verify `erathia_terrain_library_init` matches in `.gdextension` and `register_types.cpp` 

### "Library not loaded"
- Check binary exists in `bin/` directory
- Verify platform/architecture matches your system

### "GPU not available"
- Ensure Godot is using Forward+ renderer (not Compatibility)
- Check GPU drivers are up to date
