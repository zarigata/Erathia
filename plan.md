# ETHERIA: The Ultimate Open-World RPG
## ENGINE + WORLD PLAN (UPDATED)

> [!NOTE]
> **Codename:** Valheim × Minecraft × HoMM × Skyrim Fusion  
> **Engine:** Godot 4.3+ / 4.4 (Stable)  
> **Dev Style:** AI-First via Google Antigravity + MCP (minimal manual clicking)  
> **Terrain:** Smooth voxel SDF terrain (GDVoxelTerrain) with full mining & deformation  
> **World:** Very large but finite (Valheim-style scale, not infinite)

---

## Table of Contents

1. [Engine, AI & Tooling Decisions](#0-engine-ai--tooling-decisions)
2. [World Scale, Voxel Terrain & Mining](#1-world-scale-voxel-terrain--mining)
3. [Biomes, Factions & Non-Radial Difficulty](#2-biomes-factions--non-radial-difficulty)
4. [Settlements, Player Empire & RPG Layer](#3-settlements-player-empire--rpg-layer)
5. [Combat & Encounters](#4-combat--encounters)
6. [AI Companions, Voice & LLM](#5-ai-companions-voice--llm)
7. [Lua Modding & Steam Workshop](#6-lua-modding--steam-workshop)
8. [LLM Quests & Faction Stories](#7-llm-quests--faction-stories)
9. [Roadmap to Steam Release](#8-roadmap-to-steam-release)

---

## 0. ENGINE, AI & TOOLING DECISIONS

### 0.1 Engine Choice: Godot + MCP

#### Why Godot over Unity given Antigravity + MCP:

| Factor | Details |
|--------|---------|
| **Open Source** | Godot is fully open-source (MIT) → no license surprises as the project scales |
| **Voxel Plugins** | Strong free voxel plugins available |
| **MCP Tooling** | MCP servers exist that let AI agents control Godot |

#### Voxel Plugins:
- **Zylann/godot_voxel** — Blocky + smooth terrain, LOD, instancing
- **JorisAR/GDVoxelTerrain** — Smooth SDF terrain (octree + surface nets, good LOD)

#### MCP Tooling:
- **Godot MCP / GDAI MCP** — MCP servers that let AI agents (Antigravity, Cursor, VSCode, etc.) create scenes, scripts, run projects, and manage assets from outside the editor

> [!IMPORTANT]
> **DECISION:** Use **Godot 4.3+ or 4.4** + **Godot MCP server** so Google Antigravity can drive the project almost hands‑free.

---

### 0.2 Project Layout (for AI Agents)

Directory layout optimised for MCP/agents:

```text
res://
├── _core/          # GameManager, SaveManager, EventBus, Time, Weather
├── _engine/        # Voxel, worldgen, pathfinding, ECS-style systems
├── _player/        # Player controller, camera, tools, stats
├── _world/         # Biomes, Factions, Regions, POI, Dungeons
├── _building/      # Build pieces, snap system, integrity
├── _rpg/           # Skills, perks, combat, crafting, loot
├── _ai/            # LLM bridge, companions, NPC brains, behavior trees
├── _mods/          # Lua runtime, mod loader, public APIs
├── _ui/            # HUD, menus, dialogue, map
└── _assets/        # Models, textures, sounds, VFX
```

> [!TIP]
> **AI Agent Instruction Example:**  
> `"Create res://_world/biomes/biome_manager.gd implementing the biome lookup interface"`

---

### 0.3 Core Tech Stack

| System | Primary Choice | Backup/Alternative |
|--------|---------------|-------------------|
| **Voxel Terrain** | GDVoxelTerrain (smooth SDF terrain, octree, LOD) | godot_voxel (foliage instancing, alternative terrain types) |
| **Tree/Vegetation** | L-system based generator | treegen (external reference) |
| **AI/LLM** | Local: Ollama / llama.cpp via HTTP bridge | Cloud: Gemini / ChatGPT (player settings controlled) |
| **Voice STT** | Local Whisper.cpp | External services |
| **Voice TTS** | Coqui TTS (FOSS) | Other local TTS |
| **Modding** | Lua GDExtension / LuaAPI | Sandboxed Lua states per mod |

---

## 1. WORLD SCALE, VOXEL TERRAIN & MINING

### 1.1 World Scale

> [!NOTE]
> **World Type:** Finite world (not infinite)

| Parameter | Value |
|-----------|-------|
| **Playable Area** | 16 km × 16 km |
| **Min Height** | -200 m (deep caves) |
| **Max Height** | +800 m (mountain peaks) |
| **Terrain Chunks** | 64×64×128 voxel regions |
| **Streaming Radius** | 8–12 chunks around the player |

---

### 1.2 Terrain Engine (GDVoxelTerrain Setup)

#### SDF-Based Smooth Terrain:
- Store terrain in an **octree SDF** (density function)
- Mesh terrain via **surface nets** with multiple LODs

#### Configuration:

| Setting | Value |
|---------|-------|
| **Voxel Resolution** | 1 voxel = 1 meter |
| **LOD Distances** | 32m, 64m, 128m, 256m, 512m |
| **Collision** | Per-chunk generation |
| **NavMesh** | Per-chunk generation |

---

### 1.3 Mining & Terrain Deformation

> [!IMPORTANT]
> The terrain is **fully editable** by the player and some NPC actions.

#### Tool Archetypes:

##### Pickaxe
| Property | Details |
|----------|---------|
| **Primary Targets** | Stone, ore, metal |
| **Operation** | Subtract SDF sphere/capsule from solid terrain |
| **Hardness Tiers** | `dirt < stone < ore < rare crystal` |

##### Shovel
| Property | Details |
|----------|---------|
| **Primary Targets** | Dirt, sand, gravel, snow, shallow clay |
| **Operation** | Subtract or move terrain in smaller, faster operations (flatten, dig trenches) |

##### Hoe / Terraforming Staff (Mid/Late Game)
| Property | Details |
|----------|---------|
| **Flatten/Smooth** | Tool for building areas |
| **Raise/Lower** | Area brush with cost (stamina, mana, or building resource) |

---
#### 3.2 Tiered Crafting System & Tech Tree (Phase 4.5)

Crafting progresses from basic survival to high-fantasy faction technology. The highest tier allows mixing powerful Faction Magic.

| **Tier** | **Station** | **Requirements** | **Capabilities** |
| :--- | :--- | :--- | :--- |
| **Tier 0** | **Hand / Pocket** | None | Survival Basics: Torch, Rope, Rough Axe (Stone), Bandages. |
| **Tier 1** | **Workbench** | Wood, Iron Ingots, Leather | Standard Operations: Iron Tools, Leather Armor, Furniture, Chests. |
| **Tier 2** | **Arcane Forge** | Steel, Silver, Gems | Advanced Gear: Steel Plate, Silver Weapons (Anti-monster), Magic Staves. |
| **Tier 3** | **Union Station** | **Faction Cores** (see below) | **Global/Ultimate:** Faction-specific "Super Items". Requires *Faction Cores*. |

> [!IMPORTANT]
> **The Union Station (Super Crafting Table):**
> This is a unique, global late-game station.
> *   **Mechanic:** It has slots for **Faction Cores**.
> *   **Unlocking Cores:** You gain a Faction's Core only by reaching **"Exalted"** status dealing with them.
> *   **Power-Ups:** Inserting a *Necropolis Core* allows crafting generic items with *Vampirism*. Inserting an *Inferno Core* allows crafting *Magma Boots*. Inserting BOTH allows crafting a *Vampiric Flame Sword*.

---


#### Core Systems:

##### `TerrainEditSystem`
```gdscript
# Responsibilities:
# - Applies edit operations (Add, Subtract, Smooth) to SDF based on a brush
# - Queues mesh rebuild for affected chunks
# - Updates collisions
```

##### `MiningSystem`
```gdscript
# Responsibilities:
# - Converts SDF density changes into resource drops:
#   - Stone, dirt, sand, gravel
#   - Ore veins: iron, copper, silver, rare essence
# - Uses voxel metadata (material IDs) to determine loot table
```

#### Performance Considerations:
- **Batched edits:** Combine edits per frame
- **Multi-threaded:** Meshing & collider generation

> [!TIP]
> Your "big axes and shovels" are explicitly supported here: every hit deforms the world and can yield resources.

---

## 2. BIOMES, FACTIONS & NON-RADIAL DIFFICULTY

### 2.1 Biome List (13+ Base Biomes)

```text
PLAINS, FOREST, DESERT, SWAMP, TUNDRA, JUNGLE, SAVANNA, MOUNTAIN,
BEACH, DEEP_OCEAN, ICE_SPIRES, VOLCANIC, MUSHROOM
```

#### Each Biome Defines:

| Property | Description |
|----------|-------------|
| **Height Curve** | Coast → inland → mountains |
| **Base Materials** | Textures, vegetation |
| **Base Danger Rating** | 0.5–4.0 |
| **Allowed Factions** | Who can own it |
| **Weather Profiles** | Rain, snow, storms |

---

### 2.2 Biome Placement (Valheim-style layering WITHOUT edge difficulty)

#### Large-Scale Noise Layers:
1. **Continentalness** — Land vs ocean
2. **Altitude/Erosion** — Mountains vs lowlands
3. **Temperature** — Cold vs hot
4. **Humidity** — Wet vs dry

#### Valheim-Style Gradient (NOT difficulty-based):

| Location | Biomes |
|----------|--------|
| **Coasts** | More BEACH, SWAMP, low FOREST |
| **Inland** | FOREST, PLAINS, SAVANNA, MOUNTAIN |
| **Poles/High Altitudes** | TUNDRA, ICE_SPIRES |
| **Fault Lines/Rare Spots** | VOLCANIC |

> [!CAUTION]
> **IMPORTANT:** Difficulty is NOT based on distance from center. The gradient is visual/environmental, not a hard "outer ring = hellzone" rule.

---

### 2.3 Faction-Biome Binding

> [!IMPORTANT]
> **Key Rule:** A faction is 100% tied to the biome(s) it owns. No conquest outside those biome types (for now).

#### Generation Steps:

##### Step 1: Biome Pass
- For each chunk, compute biome according to noise + altitude

##### Step 2: Faction Suitability Pass
Each faction has a list of allowed biomes (Based on HoMM3 Archetypes):

| Faction | Allowed Biomes | Notes |
|---------|----------------|-------|
| **Castle** (Humans/Angels) | PLAINS, MEADOWS, COAST | Classic medieval kingdom vibe. |
| **Rampart** (Elves/Dragons) | FOREST, ROLLING_HILLS | Mortal enemy of Necropolis. |
| **Tower** (Mages/Titans) | MOUNTAIN (Snowy), ICE_SPIRES | High altitude, snowy peaks. |
| **Inferno** (Demons) | VOLCANIC, ASHLANDS | Hellscapes. |
| **Necropolis** (Undead) | DEADLANDS, CURSED_WASTELANDS | No magic works here; Undead amplified. |
| **Dungeon** (Warlocks) | DEEP_CAVES, MUSHROOM_CRYSTAL | Subterranean biomes. |
| **Stronghold** (Barbarians) | SAVANNA, BADLANDS, ROCKY_CRAGS | Rough terrain, primitive strength. |
| **Fortress** (Beastmasters) | SWAMP, JUNGLE | Dense, wet, defensive terrain. |

Candidate "region centers" (towns, villages, castles) are chosen based on:
- Flatness / proximity to water
- Access to local resources (wood, ore, farmland)

##### Step 3: Faction Claim Pass
When a region is selected for a faction:
- Mark a radius (e.g., 500–1500m) as owned territory of that faction
- Biome variant is switched from neutral to faction variant:
  - Color grading, banners, building kits
  - Extra plants/resources specific to that faction

##### Unclaimed Biome Areas:
- Same biome, but:
  - No castles/towns
  - Weaker or "untamed" monsters
  - More opportunity for player settlement

### 2.4 Deep Reputation & Diplomacy

> [!NOTE]
> Reputation is **Non-Exclusive**. You can befriend multiple factions if you play your cards right ("Double Agent").

#### 1. Independent Tracks (0–100)
Every faction has its own 0-100 meter for the player.
*   **0-20 (Hostile):** Kill on Sight. Gates closed. No quests.
*   **20-40 (Cold):** Tolerated. Allowed in outer villages. High prices.
*   **40-60 (Neutral):** Standard access. Normal trade. Basic quests.
*   **60-80 (Friendly):** Access to inner keeps. Better prices. Military support.
*   **80-100 (Exalted):** **Grant Faction Core** (for Crafting). Can command local armies.

#### 2. Balancing Act (The "Diplomat" Game)
*   **Cross-Faction Quests:** Some quests help Faction A without hurting Faction B (e.g., "Kill neutral monsters threatening the border").
*   **Secret Ops:** Stealth missions to help a faction without being seen (preserves rep with the victim).
*   **Consequences:** If Rep drops below 10, they send assassins. If Rep is >80, they send gifts/resources daily.

### 2.4 Dynamic Difficulty & Affinity System

> [!NOTE]
> Difficulty is dynamically calculated based on **Player Level**, **Faction Affinity**, and **Biome Rules**.

```
Difficulty = (BiomeDanger + PlayerLevelScaling) × FactionHostility × MagicZoneModifier
```

#### 1. Player Level & Progression
- Difficulty scales with the player's level.
- Higher level players trigger tougher enemy spawns and smarter AI.

#### 2. Faction Affinity (Tools & Equipment)
- **Tools determine power:** Some magic/tools are exclusive to certain factions.
- **Affinity:** Player's equipment (clothes, wands, weapons) affects their power in specific biomes.
  - *Example:* Using Nature magic items in a Necropolis zone is ineffective.

#### 3. Biome-Faction Interaction Matrix (The "Zone" System)

Every biome has **Intrinsic properties** that buff its native faction and strictly punish its **Rival Faction**. Magic rules change drastically per zone.

| **Faction Pair** | **Native Faction vs Rival** | **Biome A (Home)** | **Biome B (Rival Home)** | **Magic/Environmental Rule** |
| :--- | :--- | :--- | :--- | :--- |
| **Castle vs Inferno** | **Castle** (Angels) vs **Inferno** (Demons) | **PLAINS/GRASS** | **VOLCANIC/ASHLANDS** | **Sacred Ground vs Hellscape**<br>• *Holy Light:* Castle units regen HP/Morale in Plains. Demons take DOT (Smite).<br>• *Sulfur Fumes:* Inferno units move fast in Lava. Castle units suffer Stamina drain & "Terror" debuff. |
| **Rampart vs Necropolis** | **Rampart** (Elves) vs **Necropolis** (Undead) | **FOREST/GROVE** | **DEADLANDS** | **Life vs Anti-Life**<br>• *Life Force:* Nature magic amp. Undead decay (take damage) simply by standing on grass.<br>• *Void Zone:* No normal magic regen. Necromancy is 200% effective. Living units cannot heal. |
| **Tower vs Dungeon** | **Tower** (Mages) vs **Dungeon** (Warlocks) | **SNOW/PEAKS** | **DEEP_CAVES** | **Altitude vs Depths**<br>• *Thin Air:* Air Magic cost -50%. Projectiles fly further. Dungeon units (dark-dwellers) blinded by sun glare.<br>• *Echoing Dark:* Earth/Dark magic amp. Tower units (rely on sight) suffer 50% Range/Accuracy penalty. |
| **Stronghold vs Fortress** | **Stronghold** (Orcs) vs **Fortress** (Lizardmen) | **ROUGH/BADLANDS** | **SWAMP/JUNGLE** | **Might vs Disease**<br>• *Anti-Magic Field:* Magic costs 200% Mana. Physical Strength +50%. Fortress units (reliant on defense) have Armor stripped.<br>• *Plague Bog:* Disease clouds. Fortress units invisible in fog. Stronghold units sink (Move Spd -50%). |

> [!IMPORTANT]
> **Exclusive Tools & Affinity:**
> *   **Angel Wings (Castle):** Fly over lava (Inferno).
> *   **Elven Cloak (Rampart):** Invisible in Forest.
> *   **Shackles of War (Stronghold):** Prevents enemy retreat; suppresses all Magic in radius.
> *   **Gas Mask / Plague Doctor Set (Neutral/Tower):** Required to survive in Necropolis/Swamp for long periods.
> *   **Magma Boots (Inferno):** Walk on Lava.

> [!TIP]
> **Tactical Layer:** You must drag a Necropolis army *into* the Forest to weaken them, or lure Elves *into* the Deadlands to crush them.

#### BiomeDanger (0.5–4.0):

| Biome | Danger Rating |
|-------|---------------|
| PLAINS | 1.0 |
| FOREST | 1.2 |
| SWAMP | 1.5 |
| MOUNTAIN | 2.0 |
| VOLCANIC / ICE_SPIRES | 3.0–4.0 |

#### FactionPower (0.7–1.5):

| Settlement Type | Power Rating |
|-----------------|--------------|
| Small villages | ~0.8 |
| Developed kingdom/empire capital | 1.4–1.5 |

#### LocalEvents:

| Event | Modifier |
|-------|----------|
| Raid active | +0.3 |
| World boss nearby | +0.5 |
| Peace festival | -0.2 |

> [!TIP]
> **Result:** You can have "easy" zones at the edges (calm plains near ocean). A nearby volcanic fortress might be extremely hard even if it's close to the starting area.

---

## 3. SETTLEMENTS, PLAYER EMPIRE & RPG LAYER

### 3.1 Player Settlements → Empire

Player can place a **Settlement Stone** to found a village.

#### Settlement Progression:
```
Camp → Village → Town → City → Capital
```

#### Systems:

| System | Effect |
|--------|--------|
| **Housing** | Attracts NPCs |
| **Jobs** | Farmer, miner, guard, crafter |
| **Taxes/Production** | Empower player as lord/king/emperor |

#### Faction Reactions:
- Factions react based on territory overlap + reputation
- Building on faction land while hated = raids/attacks
- As emperor you can have vassal factions later (future feature)

---

### 3.2 Skyrim-Style Skills & Perks (Usage-based)

#### 5 Skill Categories:
```
Combat, Magic, Stealth, Crafting, Survival
```

Fully integrated with mining & building.

#### XP Sources:
Skills like Mining, Woodcutting, Building gain XP from:
- Terrain edits
- Resource gathering
- Successful structures

#### Perk Tree Benefits:
- Faster mining, bigger terrain brushes
- Cheaper building resources
- Stronger faction influence

---

## 4. COMBAT & ENCOUNTERS

### Combat Mechanics:

| Type | Details |
|------|---------|
| **Melee** | Light/heavy attacks, block, parry; stamina-based |
| **Ranged** | Bow physics, spells with aim + travel time |

### AI Types:

| Category | Examples |
|----------|----------|
| **Wildlife** | Neutral, shy, aggressive variants |
| **Hostiles** | Bandits, faction soldiers, bosses |

> [!NOTE]
> **Spawn Logic:** Uses difficulty score per region, NOT distance from center.

---

## 5. AI COMPANIONS, VOICE & LLM

### 5.1 Companion Design

Each companion has:

| Property | Options |
|----------|---------|
| **Archetype** | Tank, ranger, mage, support, crafter |
| **Personality Profile** | Traits like "sarcastic", "loyal", "greedy", "scholar" |

---

### 5.2 Command System (Low GPU, Clear Behavior)

> [!NOTE]
> Commands are separated from free chat. Commands use a cheap, rule-based parser.

#### Command Mapping:

| Voice/Text Command | Action |
|--------------------|--------|
| "Follow me" | `FOLLOW` |
| "Wait here" / "Stay" | `WAIT` |
| "Gather wood" | `GATHER_RESOURCE(WOOD)` |
| "Mine stone" | `GATHER_RESOURCE(STONE)` |
| "Guard this area" | `GUARD_RADIUS` |
| "Go home" | `RETURN_TO_SETTLEMENT` |

#### Implementation Flow:
```
STT → Raw Text → Keyword/Intent Parser → Action
```

- **No need to call LLM** if a direct command is detected
- Companion executes using:
  - Pathfinding (NavMesh3D)
  - Tools to mine wood/stone using the same `TerrainEditSystem`

#### Free Chat (LLM):
Trigger when:
- Player talks without clear command keywords
- Player explicitly opens "talk" mode

LLM prompt includes:
- Companion personality
- Recent events (combat, crafting, story beats)
- Current quest context

---

### 5.3 Event Reactions

Companions react to:
- Player low health
- Big enemy defeated
- Entering new biome/faction territory
- Long mining/crafting sessions ("We've been down here for hours…")

---

### 5.4 Voice & Local/Cloud Settings

| Setting | Options |
|---------|---------|
| **Voice Chat** | ON / OFF |
| **STT** | Local Whisper / External |
| **LLM** | Local only / Local + Cloud (Gemini/GPT) / Cloud disabled |
| **Companion Voices** | Text-only / Synthetic local voice |

> [!IMPORTANT]
> All LLM logic MUST work with local-only if user wants. Cloud is optional.

---

## 6. LUA MODDING & STEAM WORKSHOP

### 6.1 Lua Modding Architecture

Use **Lua GDExtension** or **LuaAPI** to create sandboxed Lua states.

#### Mod Loader:
- Each mod = folder in `res://_mods/` with `mod.lua` manifest

#### Example Mod API:

```lua
-- Example mod API
function on_mod_loaded(api)
    api.register_biome("CRYSTAL_FOREST", {...})
    api.register_item("crystal_pickaxe", {...})
    api.register_enemy("crystal_golem", {...})
end
```

#### Available Hooks:

| Category | Capabilities |
|----------|-------------|
| **World Generation** | Add new biomes, POIs, enemy spawn tables |
| **RPG** | Add items, recipes, perks |
| **UI** | Add simple panels, HUD widgets |
| **NPCs** | Add simple scripted NPCs, dialogue templates |

---

### 6.2 Steam Workshop Integration (Later Phase)

#### "Mods" Menu Features:
- Browse local mods
- Sync with Steam Workshop (subscribe/unsubscribe)
- Auto-load all enabled mods on boot

#### API Versioning:
```gdscript
const MOD_API_VERSION = 1  # Avoids breaking older mods
```

---

## 7. LLM QUESTS & FACTION STORIES

### Quest System Design:

| Type | Description |
|------|-------------|
| **Hard-coded Questlines** | Ensure game is fun without any LLM |
| **Optional LLM-driven Quests** | Enhanced narrative experience |

### LLM Quest Templates:
- Fetch, defend, escort, explore, diplomacy, trade

### LLM Fills:
- Names, flavor text, alternative branches

### Faction Capabilities:
- Request resources, alliances, duels, tasks based on real game state

---

## 8. ROADMAP TO STEAM RELEASE

### Milestone 1: Foundation
| Component | Deliverable |
|-----------|-------------|
| World | Basic terrain generation |
| Gameplay | Mining, building |
| Enemies | Simple enemy types |
| Content | 3 biomes, 1 faction |

---

### Milestone 2: Core Game
| Component | Deliverable |
|-----------|-------------|
| Settlements | Full settlement system |
| Companions | Companion AI system |
| Content | 6+ biomes, 3+ factions |
| RPG | Core RPG mechanics |

---

### Milestone 3: Steam Release
| Component | Deliverable |
|-----------|-------------|
| NPCs | LLM dialogue (optional) |
| Modding | Lua modding v1 |
| Release | Steam release (paid) |

---

### Post Launch
| Phase | Focus |
|-------|-------|
| **Expansion** | Expand biomes/factions |
| **Polish** | Refine AI systems |
| **Multiplayer** | Add co-op |
| **Depth** | Deepen empire mechanics |
| **Monetization** | Raise price incrementally as features grow (Rust-style model) |

---

## Quick Reference for AI Agents

### File Path Conventions:
```text
res://_core/       → Core systems (GameManager, SaveManager, EventBus)
res://_engine/     → Voxel and world generation
res://_player/     → Player controller and tools
res://_world/      → Biomes and factions
res://_building/   → Build system
res://_rpg/        → Skills and combat
res://_ai/         → Companion AI and LLM
res://_mods/       → Mod system
res://_ui/         → User interface
res://_assets/     → Art and audio assets
```

### Key Systems to Implement:

| Priority | System | Entry Point |
|----------|--------|-------------|
| 1 | Terrain Generation | `res://_engine/terrain/` |
| 2 | Player Controller | `res://_player/player.gd` |
| 3 | Mining System | `res://_engine/mining/` |
| 4 | Biome Manager | `res://_world/biomes/` |
| 5 | Building System | `res://_building/` |
| 6 | Combat System | `res://_rpg/combat/` |
| 7 | Companion AI | `res://_ai/companions/` |
| 8 | Mod Loader | `res://_mods/` |

---

> [!NOTE]
> **Document Version:** Updated for AI-First Development  
> **Last Modified:** December 2024  
> **Target Engine:** Godot 4.3+ / 4.4