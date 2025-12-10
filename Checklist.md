
---

## ✅ Updated `checklist.md`

```markdown
# ETHERIA: ULTIMATE DEVELOPMENT CHECKLIST (UPDATED)

> **Goal:** Build a Valheim/Minecraft/HoMM/Skyrim fusion with full terrain mining, faction-bound biomes, AI companions and Lua modding — ready for Steam.

---

## PHASE 0 — FOUNDATION & ANTIGRAVITY + MCP

### 0.1 Godot + MCP Setup

- [ ] Install **Godot 4.3+ or 4.4 Stable**.
- [ ] Create project: `Etheria`.
- [ ] Setup folders as described in `plan.md` ( _core, _world, _ai, etc.).
- [ ] Initialize Git + `.gitignore` for Godot.
- [ ] Add LFS for `.blend`, `.png`, `.tga`, `.wav`, `.tscn`.

**MCP:**

- [ ] Install **Godot MCP server / GDAI MCP**.:contentReference[oaicite:16]{index=16}  
- [ ] Register MCP server in **Google Antigravity**.
- [ ] Test from Antigravity:
  - [ ] “Create scene `MainGame.tscn`”.
  - [ ] “Run project”.
  - [ ] “Create script `_world/biomes/biome_manager.gd`”.

---

## PHASE 1 — VOXEL WORLD & MINING

### 1.1 Voxel Engine Integration

- [ ] Add `GDVoxelTerrain` plugin to project (build if needed).:contentReference[oaicite:17]{index=17}  
- [ ] Create `MainGame.tscn`:
  - [ ] Add `WorldRoot` node.
  - [ ] Add `VoxelWorld` (custom node wrapping GDVoxelTerrain).
- [ ] Configure:
  - [ ] Chunk size = 64×64×128.
  - [ ] World scale = 1 unit = 1 meter.
  - [ ] LOD distances (32, 64, 128, 256, 512 meters).
  - [ ] Enable collision and basic navmesh generation.

### 1.2 Material & Shader Setup

- [ ] Create `terrain_material.tres`:
  - [ ] Triplanar shader (avoids stretching).
  - [ ] Material IDs for: dirt, grass, rock, sand, snow, clay, gravel, mud.
- [ ] Hook **biome parameters** (temperature, humidity, faction color tint) into shader uniforms.

### 1.3 Mining & Terrain Edit System

- [ ] Create `_engine/terrain_edit_system.gd`:
  - [ ] Support brush types: SPHERE, BOX, SMOOTH.
  - [ ] Operations: ADD, SUBTRACT, SMOOTH.
  - [ ] Queue mesh + collider update for changed chunks.
- [ ] Add `_engine/mining_system.gd`:
  - [ ] Map material IDs → loot tables (stone, ore, dirt, etc.).
  - [ ] Define mining hardness & hit counts by tool tier.
- [ ] Connect editor:
  - [ ] In `Player.gd`, connect pickaxe/shovel hits to `TerrainEditSystem`.
  - [ ] Implement:
    - [ ] Pickaxe = subtract stone/ore, bigger hardness.
    - [ ] Shovel = subtract dirt/sand/snow quickly.
    - [ ] Hoe/Staff (later) = raise/flatten/smooth ground.

---

## PHASE 2 — BIOMES, FACTIONS & DIFFICULTY

### 2.1 Biome Manager

- [ ] Create `_world/biomes/biome_manager.gd`:
  - [ ] Generate 4D noise maps (continentalness, altitude, temperature, humidity).
  - [ ] Implement `get_biome_at(global_pos)` returning biome ID.
  - [ ] Implement `get_biome_params(biome_id)` returning:
    - [ ] Materials.
    - [ ] Vegetation configs.
    - [ ] Base danger rating.
    - [ ] Weather profile.
    - [ ] Allowed factions.

### 2.2 Biome Generation Flow

- [ ] In `VoxelWorld`, for each chunk:
  - [ ] Sample large-scale noise & altitude.
  - [ ] Assign biome.
  - [ ] Apply appropriate height curves (coasts, inland, mountains).
- [ ] Ensure:
  - [ ] Coasts: BEACH/SWAMP.
  - [ ] Inland: PLAINS/FOREST/SAVANNA.
  - [ ] High altitude: MOUNTAIN, ICE_SPIRES.
  - [ ] Special: VOLCANIC in rare hot spots.

### 2.3 Faction-Biome Ownership

- [ ] Create `_world/factions/faction_data.gd`:
  - [ ] Define factions: Sandborn, Marshfolk, Frostkin, etc.
  - [ ] For each faction:
    - [ ] Allowed biomes.
    - [ ] Color, banner, architecture kit.
    - [ ] Personality (for LLM).
- [ ] Create `_world/factions/faction_manager.gd`:
  - [ ] Scan biome map for candidate region centers.
  - [ ] For each faction:
    - [ ] Claim regions in allowed biomes.
    - [ ] Mark tiles as **owned territory**.
    - [ ] Assign “neutral” vs “owned” biome variant IDs.
- [ ] Ensure:
  - [ ] Factions **never own tiles outside their allowed biome list**.
  - [ ] Some biome regions remain unclaimed → player playground.

### 2.4 Non-Radial Difficulty System

- [ ] Create `_world/difficulty_manager.gd`:
  - [ ] Read biome danger rating.
  - [ ] Read local faction power level.
  - [ ] Read active events (raid, boss, festival).
  - [ ] Compute difficulty score.
- [ ] Hook difficulty to:
  - [ ] Enemy spawn tables (HP, levels, group sizes).
  - [ ] Loot quality.
- [ ] Confirm:
  - [ ] No logic depends on “distance from world center”.

---

## PHASE 3 — FLORA, TREES & PROPS

### 3.1 Tree/Vegetation Generator

- [ ] Implement `TreeGenerator.gd` (inspired by `treegen`):
  - [ ] Procedural branch L-system or fractal generator.
  - [ ] Leaf clusters via MultiMesh / instancing.
  - [ ] Export to Mesh resources for runtime instancing.
- [ ] Pre-generate tree families:
  - [ ] Oak, Pine, Birch, Palm, Willow, Jungle trees, Mushrooms.
- [ ] Create scatter profiles per biome:
  - [ ] Max density, steepness constraints.
  - [ ] Variation by faction ownership (e.g. faction-themed lanterns).

---

## PHASE 4 — PLAYER CONTROLLER & TOOLS

### 4.1 Movement & Camera

- [ ] Implement `Player.gd`:
  - [ ] States: idle, walk, run, jump, fall, crouch, swim.
  - [ ] Stamina for running & jumping.
- [ ] Camera:
  - [ ] 3rd person default, 1st person toggle.
  - [ ] Smooth camera collision, zoom, and pivot.

### 4.2 Tool & Interaction System

- [ ] Item system:
  - [ ] Define types: weapon, tool, consumable, building piece.
- [ ] Tools:
  - [ ] Axe – interacts with tree instances.
  - [ ] Pickaxe – calls `MiningSystem` (stone/ore).
  - [ ] Shovel – calls `MiningSystem` (dirt/sand).
  - [ ] Hammer – enters building mode.
- [ ] Interaction:
  - [ ] Raycast from camera.
  - [ ] Contextual prompts: “E – Mine”, “E – Chop”, “E – Talk”.

---

## PHASE 5 — BUILDING SYSTEM

- [ ] Implement `BuildSystem.gd`:
  - [ ] Grid snapping (0.5m) and rotation snapping (15/45/90 degrees).
  - [ ] Placement validity (support, blocking terrain).
- [ ] Structural integrity:
  - [ ] Compute support from ground and pillars.
  - [ ] Color-coded piece preview (blue/green/yellow/red).
  - [ ] Collapse logic if support below threshold.
- [ ] Basic building pieces:
  - [ ] Wooden floors/walls/roofs.
  - [ ] Stone foundations/pillars.
  - [ ] Doors, windows, torches.

---

## PHASE 6 — SETTLEMENTS & EMPIRE

### 6.1 Player Settlements

- [ ] Implement `SettlementStone` item and node.
- [ ] Territory radius defined (e.g. 100m).
- [ ] `SettlementManager.gd`:
  - [ ] Tracks houses, jobs, population, prosperity.
  - [ ] Handles NPC attraction based on:
    - [ ] Available beds, food, security, player reputation.

### 6.2 NPC Jobs & Simulation

- [ ] Job types:
  - [ ] Farmer, Miner, Lumberjack, Guard, Crafter, Trader.
- [ ] Daily simulation:
  - [ ] Work, rest, social, events.
- [ ] Offline simulation:
  - [ ] When player is far, run simplified simulation tick (production, events).

---

## PHASE 7 — RPG, SKILLS & COMBAT

### 7.1 Stats & Skills

- [ ] Implement `StatsManager` (HP, Stamina, Mana).
- [ ] Implement `SkillManager` with use-based leveling:
  - [ ] Mining gains XP from valid terrain edits.
  - [ ] Woodcutting from tree chops.
  - [ ] Building from placed/structurally sound pieces.
- [ ] Perk trees:
  - [ ] UI graph for perks (nodes, connections).
  - [ ] Mining perks: faster mining, bigger brush, detect ore.
  - [ ] Building perks: cheaper cost, stronger structures.

### 7.2 Combat

- [ ] Hitbox/hurtbox system.
- [ ] Melee attacks with combo animations.
- [ ] Bow physics with projectile arcs.
- [ ] Basic spell system (projectile / AoE / buff).
- [ ] Enemy AI with states:
  - [ ] Idle, patrol, investigate, chase, attack, flee.

---

## PHASE 8 — COMPANIONS, VOICE & LLM

### 8.1 Companion Core

- [ ] `Companion.gd`:
  - [ ] Follows player, keeps formation.
  - [ ] Basic combat behavior.
- [ ] Implement **command flags**:
  - [ ] FOLLOW, WAIT, GATHER_WOOD, GATHER_STONE, GUARD, RETURN_HOME.

### 8.2 Voice Command Pipeline

- [ ] Integrate local STT (Whisper or similar) via GDExtension or external process.
- [ ] Build `VoiceCommandParser.gd`:
  - [ ] Maps phrases → command flags.
  - [ ] Only uses LLM when no direct command is matched (for free chat).
- [ ] Player settings:
  - [ ] Voice Commands: ON/OFF.
  - [ ] Push-to-talk key.
  - [ ] Microphone device selection.

### 8.3 LLM Integration

- [ ] Implement `_ai/llm_bridge.gd`:
  - [ ] Supports local LLM (Ollama / llama.cpp) via HTTP.
  - [ ] Optional remote LLM (Gemini, GPT) via API keys.
- [ ] Build prompt templates:
  - [ ] For companions (personality + local context).
  - [ ] For faction leaders (diplomacy, quests).
- [ ] NPC memory:
  - [ ] Simple key-value store, later upgrade to vector DB if needed.

---

## PHASE 9 — LUA MODDING & WORKSHOP

### 9.1 Lua Runtime

- [ ] Install **Lua GDExtension / LuaAPI** addon.:contentReference[oaicite:18]{index=18}  
- [ ] Create `_mods/mod_loader.gd`:
  - [ ] Hot-load all mods in `_mods/`.
  - [ ] Create isolated Lua state per mod.
- [ ] Define Mod API in Lua:
  - [ ] `register_item`, `register_enemy`, `register_biome`, `register_quest`, etc.
- [ ] Example mod:
  - [ ] Adds new mining tool and new ore.

### 9.2 Steam Workshop (Later)

- [ ] Integrate Steamworks SDK.
- [ ] Link `_mods` with Workshop items.
- [ ] UI for:
  - [ ] Enabling/disabling mods.
  - [ ] Sorting/load order.

---

## PHASE 10 — UI, POLISH, PERFORMANCE & SHIP

### 10.1 UI

- [ ] HUD:
  - [ ] Health, Stamina, Mana, Hunger.
  - [ ] Hotbar 1–8.
  - [ ] Compass with POI markers.
- [ ] Menus:
  - [ ] Inventory / character (Skyrim-style with tabs).
  - [ ] Skills & perks screen.
  - [ ] Map (world + local).

### 10.2 Polish

- [ ] Biome-based ambience & music.
- [ ] VFX for mining, spells, hits.
- [ ] Day/night with smooth lighting changes.

### 10.3 Optimization

- [ ] Threaded meshing & terrain edits.
- [ ] MultiMesh for grass/trees.
- [ ] Occlusion culling / portal systems where relevant.
- [ ] Profiling passes (GPU & CPU).

### 10.4 Build & Steam

- [ ] Export presets for Windows (and Linux if desired).
- [ ] Basic launcher / settings.
- [ ] Steam integration:
  - [ ] Achievements.
  - [ ] Cloud saves (optional).
  - [ ] Workshop (when ready).
- [ ] Prepare marketing assets:
  - [ ] Trailer showing mining, biomes, companions, big battles.
  - [ ] Steam page text: “single-player, AI-powered companions, moddable, voxel RPG”.

---

> This checklist should be treated as a **living document**. Whenever you or the AI add a new system, extend the relevant PHASE with concrete tasks instead of leaving it “implicit”.
