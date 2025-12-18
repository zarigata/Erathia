extends Node
# Note: This script is registered as an autoload singleton named "BiomeManager" in project.godot
# Do not add class_name as it would conflict with the autoload singleton name
## BiomeManager Singleton
##
## Central biome database providing comprehensive biome properties, faction interactions,
## and zone effects for the Erathia world system.
##
## Integration Points:
## - MapGenerator: Uses biome enum, should query BiomeManager for properties
## - TerrainEditSystem: Can query material lists for terrain generation
## - Future WeatherSystem: Will query weather profiles
## - Future SpawningSystem: Will use danger ratings and difficulty calculator
## - Future FactionManager: Will query allowed factions and zone effects
##
## Usage Example:
## var danger = BiomeManager.get_danger_rating(MapGenerator.Biome.VOLCANIC)
## var difficulty = BiomeManager.calculate_difficulty(biome_id, player_level, faction_id, rep, affinity)

# =============================================================================
# BIOME DATABASE
# =============================================================================

## Comprehensive biome properties dictionary
## Each biome entry contains:
## - display_name: Human-readable name
## - height_curve: Min/max elevation ranges
## - base_materials: Primary terrain materials
## - danger_rating: Base difficulty (0.5-4.0)
## - allowed_factions: Faction IDs that can claim this biome
## - weather_profiles: Weather types available
## - temperature: Climate value (-1.0 cold to 1.0 hot)
## - humidity: Moisture level (0.0 dry to 1.0 wet)
## - vegetation_density: Plant spawn density (0.0-1.0)
## - ore_richness: Resource abundance multiplier
const BIOME_DATA: Dictionary = {
	MapGenerator.Biome.PLAINS: {
		"display_name": "Plains",
		"height_curve": {"min": 0, "max": 50},
		"base_materials": ["grass", "dirt", "stone"],
		"danger_rating": 1.0,
		"allowed_factions": [MapGenerator.Faction.CASTLE],
		"weather_profiles": ["clear", "rain"],
		"temperature": 0.5,
		"humidity": 0.5,
		"vegetation_density": 0.6,
		"ore_richness": 1.0
	},
	MapGenerator.Biome.FOREST: {
		"display_name": "Forest",
		"height_curve": {"min": 10, "max": 80},
		"base_materials": ["grass", "dirt", "stone", "moss"],
		"danger_rating": 1.2,
		"allowed_factions": [MapGenerator.Faction.RAMPART, MapGenerator.Faction.DUNGEON],
		"weather_profiles": ["rain", "fog"],
		"temperature": 0.4,
		"humidity": 0.7,
		"vegetation_density": 0.9,
		"ore_richness": 0.8
	},
	MapGenerator.Biome.DESERT: {
		"display_name": "Desert",
		"height_curve": {"min": -20, "max": 100},
		"base_materials": ["sand", "sandstone", "clay"],
		"danger_rating": 1.5,
		"allowed_factions": [MapGenerator.Faction.INFERNO, MapGenerator.Faction.STRONGHOLD],
		"weather_profiles": ["sandstorm", "clear"],
		"temperature": 0.9,
		"humidity": 0.1,
		"vegetation_density": 0.1,
		"ore_richness": 1.2
	},
	MapGenerator.Biome.SWAMP: {
		"display_name": "Swamp",
		"height_curve": {"min": -30, "max": 30},
		"base_materials": ["mud", "peat", "clay", "moss"],
		"danger_rating": 1.5,
		"allowed_factions": [MapGenerator.Faction.NECROPOLIS, MapGenerator.Faction.FORTRESS],
		"weather_profiles": ["rain", "fog"],
		"temperature": 0.5,
		"humidity": 0.9,
		"vegetation_density": 0.7,
		"ore_richness": 0.6
	},
	MapGenerator.Biome.TUNDRA: {
		"display_name": "Tundra",
		"height_curve": {"min": 20, "max": 120},
		"base_materials": ["permafrost", "snow", "ice", "stone"],
		"danger_rating": 2.0,
		"allowed_factions": [MapGenerator.Faction.NECROPOLIS],
		"weather_profiles": ["snow", "blizzard"],
		"temperature": 0.1,
		"humidity": 0.3,
		"vegetation_density": 0.15,
		"ore_richness": 1.0
	},
	MapGenerator.Biome.JUNGLE: {
		"display_name": "Jungle",
		"height_curve": {"min": 0, "max": 90},
		"base_materials": ["mud", "dirt", "stone", "vines"],
		"danger_rating": 1.8,
		"allowed_factions": [MapGenerator.Faction.FORTRESS],
		"weather_profiles": ["rain", "storm"],
		"temperature": 0.8,
		"humidity": 0.9,
		"vegetation_density": 1.0,
		"ore_richness": 0.9
	},
	MapGenerator.Biome.SAVANNA: {
		"display_name": "Savanna",
		"height_curve": {"min": 5, "max": 60},
		"base_materials": ["dry_grass", "dirt", "clay"],
		"danger_rating": 1.3,
		"allowed_factions": [MapGenerator.Faction.STRONGHOLD],
		"weather_profiles": ["clear", "dry"],
		"temperature": 0.7,
		"humidity": 0.3,
		"vegetation_density": 0.4,
		"ore_richness": 1.1
	},
	MapGenerator.Biome.MOUNTAIN: {
		"display_name": "Mountain",
		"height_curve": {"min": 80, "max": 300},
		"base_materials": ["stone", "granite", "slate", "snow"],
		"danger_rating": 2.0,
		"allowed_factions": [MapGenerator.Faction.TOWER, MapGenerator.Faction.DUNGEON],
		"weather_profiles": ["snow", "wind"],
		"temperature": 0.2,
		"humidity": 0.4,
		"vegetation_density": 0.2,
		"ore_richness": 1.8
	},
	MapGenerator.Biome.BEACH: {
		"display_name": "Beach",
		"height_curve": {"min": -5, "max": 15},
		"base_materials": ["sand", "gravel", "shells"],
		"danger_rating": 0.8,
		"allowed_factions": [MapGenerator.Faction.CASTLE],
		"weather_profiles": ["clear", "rain"],
		"temperature": 0.6,
		"humidity": 0.6,
		"vegetation_density": 0.3,
		"ore_richness": 0.5
	},
	MapGenerator.Biome.DEEP_OCEAN: {
		"display_name": "Deep Ocean",
		"height_curve": {"min": -200, "max": -50},
		"base_materials": ["sand", "coral", "stone"],
		"danger_rating": 2.5,
		"allowed_factions": [],
		"weather_profiles": ["storm", "clear"],
		"temperature": 0.5,
		"humidity": 1.0,
		"vegetation_density": 0.4,
		"ore_richness": 0.7
	},
	MapGenerator.Biome.ICE_SPIRES: {
		"display_name": "Ice Spires",
		"height_curve": {"min": 100, "max": 350},
		"base_materials": ["ice", "frozen_stone", "snow", "crystal"],
		"danger_rating": 3.0,
		"allowed_factions": [MapGenerator.Faction.TOWER],
		"weather_profiles": ["blizzard", "ice_storm"],
		"temperature": 0.0,
		"humidity": 0.2,
		"vegetation_density": 0.0,
		"ore_richness": 1.5
	},
	MapGenerator.Biome.VOLCANIC: {
		"display_name": "Volcanic Ashlands",
		"height_curve": {"min": -50, "max": 200},
		"base_materials": ["obsidian", "ash", "lava_rock", "basalt"],
		"danger_rating": 3.5,
		"allowed_factions": [MapGenerator.Faction.INFERNO],
		"weather_profiles": ["ash_storm", "heat_wave"],
		"temperature": 1.0,
		"humidity": 0.1,
		"vegetation_density": 0.05,
		"ore_richness": 2.0
	},
	MapGenerator.Biome.MUSHROOM: {
		"display_name": "Mushroom Grotto",
		"height_curve": {"min": -40, "max": 70},
		"base_materials": ["mycelium", "spore_dirt", "fungal_stone"],
		"danger_rating": 2.2,
		"allowed_factions": [MapGenerator.Faction.DUNGEON],
		"weather_profiles": ["spore_fog", "rain"],
		"temperature": 0.4,
		"humidity": 0.8,
		"vegetation_density": 0.85,
		"ore_richness": 1.3
	}
}

# =============================================================================
# FACTION RIVALRY SYSTEM
# =============================================================================

## Faction rivalry pairs - each faction has one primary rival
const FACTION_RIVALS: Dictionary = {
	MapGenerator.Faction.CASTLE: MapGenerator.Faction.INFERNO,
	MapGenerator.Faction.INFERNO: MapGenerator.Faction.CASTLE,
	MapGenerator.Faction.RAMPART: MapGenerator.Faction.NECROPOLIS,
	MapGenerator.Faction.NECROPOLIS: MapGenerator.Faction.RAMPART,
	MapGenerator.Faction.TOWER: MapGenerator.Faction.DUNGEON,
	MapGenerator.Faction.DUNGEON: MapGenerator.Faction.TOWER,
	MapGenerator.Faction.STRONGHOLD: MapGenerator.Faction.FORTRESS,
	MapGenerator.Faction.FORTRESS: MapGenerator.Faction.STRONGHOLD
}

## Home biomes for each faction (primary territory)
const FACTION_HOME_BIOMES: Dictionary = {
	MapGenerator.Faction.CASTLE: MapGenerator.Biome.PLAINS,
	MapGenerator.Faction.RAMPART: MapGenerator.Biome.FOREST,
	MapGenerator.Faction.TOWER: MapGenerator.Biome.ICE_SPIRES,
	MapGenerator.Faction.INFERNO: MapGenerator.Biome.VOLCANIC,
	MapGenerator.Faction.NECROPOLIS: MapGenerator.Biome.SWAMP,
	MapGenerator.Faction.DUNGEON: MapGenerator.Biome.MUSHROOM,
	MapGenerator.Faction.STRONGHOLD: MapGenerator.Biome.SAVANNA,
	MapGenerator.Faction.FORTRESS: MapGenerator.Biome.JUNGLE
}

# =============================================================================
# ZONE EFFECTS DATABASE
# =============================================================================

## Native buffs when a faction is in their home biome
const NATIVE_BUFFS: Dictionary = {
	MapGenerator.Faction.CASTLE: {
		"hp_regen_rate": 1.5,
		"morale_bonus": 20,
		"holy_magic_cost": 0.5,
		"movement_speed": 1.1,
		"defense_bonus": 10
	},
	MapGenerator.Faction.RAMPART: {
		"hp_regen_rate": 1.8,
		"morale_bonus": 15,
		"nature_magic_cost": 0.5,
		"movement_speed": 1.2,
		"stealth_bonus": 25
	},
	MapGenerator.Faction.TOWER: {
		"hp_regen_rate": 1.3,
		"morale_bonus": 15,
		"arcane_magic_cost": 0.4,
		"spell_power": 1.3,
		"mana_regen": 1.5
	},
	MapGenerator.Faction.INFERNO: {
		"hp_regen_rate": 1.4,
		"morale_bonus": 25,
		"fire_magic_cost": 0.4,
		"damage_bonus": 15,
		"fear_aura": 10
	},
	MapGenerator.Faction.NECROPOLIS: {
		"hp_regen_rate": 2.0,
		"morale_bonus": 10,
		"death_magic_cost": 0.4,
		"undead_summon_bonus": 20,
		"life_drain": 1.2
	},
	MapGenerator.Faction.DUNGEON: {
		"hp_regen_rate": 1.4,
		"morale_bonus": 15,
		"dark_magic_cost": 0.5,
		"trap_damage": 1.5,
		"ambush_bonus": 30
	},
	MapGenerator.Faction.STRONGHOLD: {
		"hp_regen_rate": 1.6,
		"morale_bonus": 30,
		"physical_damage": 1.2,
		"movement_speed": 1.15,
		"rage_buildup": 1.3
	},
	MapGenerator.Faction.FORTRESS: {
		"hp_regen_rate": 1.5,
		"morale_bonus": 20,
		"poison_resistance": 50,
		"defense_bonus": 20,
		"fortification_speed": 1.5
	}
}

## Debuffs applied to rival factions in enemy home territory
const RIVAL_DEBUFFS: Dictionary = {
	MapGenerator.Faction.CASTLE: {  # Debuffs for Castle units in Inferno territory
		"damage_over_time": 5,
		"debuff_name": "Hellfire Burn",
		"movement_penalty": 0.8,
		"holy_magic_cost": 1.5,
		"morale_penalty": -15
	},
	MapGenerator.Faction.INFERNO: {  # Debuffs for Inferno units in Castle territory
		"damage_over_time": 5,
		"debuff_name": "Holy Smite",
		"movement_penalty": 0.8,
		"fire_magic_cost": 1.5,
		"morale_penalty": -20
	},
	MapGenerator.Faction.RAMPART: {  # Debuffs for Rampart units in Necropolis territory
		"damage_over_time": 3,
		"debuff_name": "Death Blight",
		"movement_penalty": 0.85,
		"nature_magic_cost": 1.4,
		"healing_reduction": 0.5
	},
	MapGenerator.Faction.NECROPOLIS: {  # Debuffs for Necropolis units in Rampart territory
		"damage_over_time": 4,
		"debuff_name": "Nature's Wrath",
		"movement_penalty": 0.85,
		"death_magic_cost": 1.4,
		"summon_duration_penalty": 0.6
	},
	MapGenerator.Faction.TOWER: {  # Debuffs for Tower units in Dungeon territory
		"damage_over_time": 2,
		"debuff_name": "Shadow Corruption",
		"accuracy_penalty": 0.8,
		"arcane_magic_cost": 1.3,
		"spell_disruption_chance": 15
	},
	MapGenerator.Faction.DUNGEON: {  # Debuffs for Dungeon units in Tower territory
		"damage_over_time": 3,
		"debuff_name": "Arcane Purge",
		"accuracy_penalty": 0.85,
		"dark_magic_cost": 1.4,
		"stealth_penalty": -30
	},
	MapGenerator.Faction.STRONGHOLD: {  # Debuffs for Stronghold units in Fortress territory
		"damage_over_time": 4,
		"debuff_name": "Toxic Miasma",
		"movement_penalty": 0.75,
		"stamina_drain": 1.3,
		"attack_speed_penalty": 0.85
	},
	MapGenerator.Faction.FORTRESS: {  # Debuffs for Fortress units in Stronghold territory
		"damage_over_time": 2,
		"debuff_name": "Berserker Pressure",
		"movement_penalty": 0.9,
		"defense_penalty": -15,
		"morale_penalty": -10
	}
}

## Magic type modifiers per faction-biome combination
const MAGIC_MODIFIERS: Dictionary = {
	"holy": {
		MapGenerator.Biome.PLAINS: 0.8,
		MapGenerator.Biome.VOLCANIC: 1.5,
		MapGenerator.Biome.SWAMP: 1.2
	},
	"fire": {
		MapGenerator.Biome.VOLCANIC: 0.6,
		MapGenerator.Biome.ICE_SPIRES: 1.4,
		MapGenerator.Biome.PLAINS: 1.1
	},
	"nature": {
		MapGenerator.Biome.FOREST: 0.6,
		MapGenerator.Biome.JUNGLE: 0.7,
		MapGenerator.Biome.VOLCANIC: 1.5,
		MapGenerator.Biome.DESERT: 1.3
	},
	"death": {
		MapGenerator.Biome.SWAMP: 0.6,
		MapGenerator.Biome.TUNDRA: 0.7,
		MapGenerator.Biome.FOREST: 1.3,
		MapGenerator.Biome.PLAINS: 1.2
	},
	"arcane": {
		MapGenerator.Biome.ICE_SPIRES: 0.6,
		MapGenerator.Biome.MOUNTAIN: 0.8,
		MapGenerator.Biome.MUSHROOM: 1.2
	},
	"dark": {
		MapGenerator.Biome.MUSHROOM: 0.6,
		MapGenerator.Biome.MOUNTAIN: 0.8,
		MapGenerator.Biome.ICE_SPIRES: 1.3,
		MapGenerator.Biome.PLAINS: 1.2
	},
	"physical": {
		MapGenerator.Biome.SAVANNA: 0.85,
		MapGenerator.Biome.MOUNTAIN: 1.1,
		MapGenerator.Biome.SWAMP: 1.2
	},
	"poison": {
		MapGenerator.Biome.JUNGLE: 0.7,
		MapGenerator.Biome.SWAMP: 0.8,
		MapGenerator.Biome.ICE_SPIRES: 1.4,
		MapGenerator.Biome.DESERT: 1.2
	}
}

## Environmental hazards per biome
const ENVIRONMENTAL_HAZARDS: Dictionary = {
	MapGenerator.Biome.VOLCANIC: [
		{"type": "lava_pool", "damage": 20, "radius": 5.0, "frequency": 0.3},
		{"type": "ash_cloud", "damage": 2, "radius": 15.0, "frequency": 0.5},
		{"type": "eruption", "damage": 50, "radius": 30.0, "frequency": 0.05}
	],
	MapGenerator.Biome.SWAMP: [
		{"type": "poison_cloud", "damage": 3, "radius": 8.0, "frequency": 0.4},
		{"type": "quicksand", "damage": 0, "radius": 4.0, "frequency": 0.2, "effect": "slow"},
		{"type": "disease_spore", "damage": 1, "radius": 10.0, "frequency": 0.3, "effect": "dot"}
	],
	MapGenerator.Biome.ICE_SPIRES: [
		{"type": "ice_spike", "damage": 15, "radius": 3.0, "frequency": 0.25},
		{"type": "blizzard_zone", "damage": 5, "radius": 20.0, "frequency": 0.4, "effect": "slow"},
		{"type": "avalanche", "damage": 40, "radius": 25.0, "frequency": 0.08}
	],
	MapGenerator.Biome.DESERT: [
		{"type": "sandstorm", "damage": 2, "radius": 30.0, "frequency": 0.35, "effect": "blind"},
		{"type": "heat_exhaustion", "damage": 3, "radius": 0.0, "frequency": 1.0, "effect": "stamina_drain"},
		{"type": "quicksand", "damage": 0, "radius": 5.0, "frequency": 0.15, "effect": "slow"}
	],
	MapGenerator.Biome.JUNGLE: [
		{"type": "poison_plant", "damage": 5, "radius": 2.0, "frequency": 0.4},
		{"type": "carnivorous_vine", "damage": 8, "radius": 3.0, "frequency": 0.2, "effect": "root"},
		{"type": "disease_insect", "damage": 2, "radius": 1.0, "frequency": 0.5, "effect": "dot"}
	],
	MapGenerator.Biome.MUSHROOM: [
		{"type": "spore_cloud", "damage": 4, "radius": 10.0, "frequency": 0.5, "effect": "confuse"},
		{"type": "toxic_mushroom", "damage": 10, "radius": 2.0, "frequency": 0.3},
		{"type": "hallucinogenic_gas", "damage": 0, "radius": 8.0, "frequency": 0.2, "effect": "hallucinate"}
	],
	MapGenerator.Biome.MOUNTAIN: [
		{"type": "rockslide", "damage": 25, "radius": 15.0, "frequency": 0.1},
		{"type": "thin_air", "damage": 1, "radius": 0.0, "frequency": 1.0, "effect": "stamina_drain"},
		{"type": "lightning_strike", "damage": 35, "radius": 5.0, "frequency": 0.05}
	],
	MapGenerator.Biome.DEEP_OCEAN: [
		{"type": "crushing_pressure", "damage": 10, "radius": 0.0, "frequency": 1.0},
		{"type": "whirlpool", "damage": 5, "radius": 20.0, "frequency": 0.15, "effect": "pull"},
		{"type": "predator_zone", "damage": 0, "radius": 50.0, "frequency": 0.3, "effect": "spawn_enemy"}
	],
	MapGenerator.Biome.TUNDRA: [
		{"type": "frostbite", "damage": 3, "radius": 0.0, "frequency": 0.8, "effect": "slow"},
		{"type": "ice_crack", "damage": 20, "radius": 4.0, "frequency": 0.1},
		{"type": "whiteout", "damage": 0, "radius": 40.0, "frequency": 0.25, "effect": "blind"}
	]
}

# =============================================================================
# BASIC QUERY METHODS
# =============================================================================

## Returns full biome properties dictionary
func get_biome_data(biome_id: int) -> Dictionary:
	if BIOME_DATA.has(biome_id):
		return BIOME_DATA[biome_id].duplicate(true)
	push_warning("[BiomeManager] Unknown biome ID: %d" % biome_id)
	return {}


## Returns human-readable biome name
func get_biome_name(biome_id: int) -> String:
	var data := get_biome_data(biome_id)
	return data.get("display_name", "Unknown")


## Returns base danger rating (0.5-4.0)
func get_danger_rating(biome_id: int) -> float:
	var data := get_biome_data(biome_id)
	return data.get("danger_rating", 1.0)


## Returns array of faction IDs allowed in this biome
func get_allowed_factions(biome_id: int) -> Array:
	var data := get_biome_data(biome_id)
	return data.get("allowed_factions", [])


## Checks if a faction can claim territory in this biome
func is_faction_allowed(biome_id: int, faction_id: int) -> bool:
	var allowed := get_allowed_factions(biome_id)
	return faction_id in allowed


# =============================================================================
# ADVANCED QUERY METHODS
# =============================================================================

## Returns array of weather types for this biome
func get_weather_for_biome(biome_id: int) -> Array:
	var data := get_biome_data(biome_id)
	return data.get("weather_profiles", ["clear"])


## Returns vegetation spawn density (0.0-1.0)
func get_vegetation_density(biome_id: int) -> float:
	var data := get_biome_data(biome_id)
	return data.get("vegetation_density", 0.5)


## Returns resource abundance multiplier
func get_ore_richness(biome_id: int) -> float:
	var data := get_biome_data(biome_id)
	return data.get("ore_richness", 1.0)


## Returns min/max elevation dictionary
func get_height_range(biome_id: int) -> Dictionary:
	var data := get_biome_data(biome_id)
	return data.get("height_curve", {"min": 0, "max": 100})


## Returns temperature value (-1.0 cold to 1.0 hot)
func get_temperature(biome_id: int) -> float:
	var data := get_biome_data(biome_id)
	return data.get("temperature", 0.5)


## Returns humidity value (0.0 dry to 1.0 wet)
func get_humidity(biome_id: int) -> float:
	var data := get_biome_data(biome_id)
	return data.get("humidity", 0.5)


## Returns array of base material names for terrain generation
func get_base_materials(biome_id: int) -> Array:
	var data := get_biome_data(biome_id)
	return data.get("base_materials", ["stone"])


# =============================================================================
# DYNAMIC DIFFICULTY CALCULATOR
# =============================================================================

## Calculates dynamic difficulty based on multiple factors
## Formula: Difficulty = (BiomeDanger + PlayerLevelScaling) × FactionHostility × MagicZoneModifier
##
## Parameters:
## - biome_id: Current biome
## - player_level: Player's current level
## - faction_id: Faction controlling this area (or UNCLAIMED)
## - player_faction_rep: Player's reputation with the controlling faction (-1.0 to 1.0)
## - player_equipment_affinity: Equipment magic type affinity (faction ID or -1 for neutral)
##
## Returns: Final difficulty score (typically 0.5 to 10.0+)
func calculate_difficulty(
	biome_id: int,
	player_level: int,
	faction_id: int,
	player_faction_rep: float = 0.0,
	player_equipment_affinity: int = -1
) -> float:
	# Step 1: Get base biome danger
	var biome_danger := get_danger_rating(biome_id)
	
	# Step 2: Apply player level scaling (0.1 per level)
	var level_scaling := player_level * 0.1
	var base_difficulty := biome_danger + level_scaling
	
	# Step 3: Calculate faction hostility (0.7 to 1.5 range)
	var faction_hostility := 1.0
	if faction_id != MapGenerator.Faction.UNCLAIMED:
		# Reputation affects hostility: -1.0 rep = 1.5x, +1.0 rep = 0.7x
		faction_hostility = 1.1 - (player_faction_rep * 0.4)
		faction_hostility = clampf(faction_hostility, 0.7, 1.5)
	
	# Step 4: Calculate magic zone modifier
	var magic_modifier := 1.0
	if player_equipment_affinity >= 0:
		# Check if player's equipment affinity is disadvantaged in this biome
		var home_biome: int = FACTION_HOME_BIOMES.get(player_equipment_affinity, -1)
		if home_biome >= 0 and home_biome != biome_id:
			# Not in home biome - check for rival territory
			var rival: int = FACTION_RIVALS.get(player_equipment_affinity, -1)
			var rival_home: int = FACTION_HOME_BIOMES.get(rival, -1)
			if biome_id == rival_home:
				magic_modifier = 1.3  # In rival territory
			else:
				magic_modifier = 1.1  # In neutral territory
		elif home_biome == biome_id:
			magic_modifier = 0.85  # In home territory
	
	# Final calculation
	var final_difficulty := base_difficulty * faction_hostility * magic_modifier
	return final_difficulty


# =============================================================================
# FACTION ZONE EFFECT QUERIES
# =============================================================================

## Returns native buffs for a faction in their home biome
## Returns empty dict if not in home biome
func get_native_buffs(faction_id: int, biome_id: int) -> Dictionary:
	if faction_id == MapGenerator.Faction.UNCLAIMED:
		return {}
	
	var home_biome: int = FACTION_HOME_BIOMES.get(faction_id, -1)
	if biome_id == home_biome and NATIVE_BUFFS.has(faction_id):
		return NATIVE_BUFFS[faction_id].duplicate(true)
	
	return {}


## Returns debuffs for a faction when in rival's home territory
## Returns empty dict if not in rival territory
func get_rival_debuffs(faction_id: int, biome_id: int) -> Dictionary:
	if faction_id == MapGenerator.Faction.UNCLAIMED:
		return {}
	
	var rival: int = FACTION_RIVALS.get(faction_id, -1)
	if rival < 0:
		return {}
	
	var rival_home: int = FACTION_HOME_BIOMES.get(rival, -1)
	if biome_id == rival_home and RIVAL_DEBUFFS.has(faction_id):
		return RIVAL_DEBUFFS[faction_id].duplicate(true)
	
	return {}


## Returns magic cost/effectiveness modifier for a magic type in a biome
## Values < 1.0 = more effective, > 1.0 = less effective
##
## Parameters:
## - faction_id: The faction using the magic (applies home/rival biome adjustments)
## - biome_id: Current biome
## - magic_type: Type of magic (holy, fire, nature, death, arcane, dark, physical, poison)
##
## Faction adjustments:
## - Home biome: 0.85x modifier (15% bonus)
## - Rival's home biome: 1.25x modifier (25% penalty)
## - Neutral territory: No adjustment
func get_magic_modifier(faction_id: int, biome_id: int, magic_type: String) -> float:
	var magic_type_lower := magic_type.to_lower()
	
	# Get base biome modifier for this magic type
	var base_modifier := 1.0
	if MAGIC_MODIFIERS.has(magic_type_lower):
		var biome_modifiers: Dictionary = MAGIC_MODIFIERS[magic_type_lower]
		base_modifier = biome_modifiers.get(biome_id, 1.0)
	
	# Apply faction-specific adjustments
	if faction_id != MapGenerator.Faction.UNCLAIMED and FACTION_HOME_BIOMES.has(faction_id):
		var home_biome: int = FACTION_HOME_BIOMES[faction_id]
		
		if biome_id == home_biome:
			# Home biome bonus: 15% more effective
			base_modifier *= 0.85
		else:
			# Check if in rival's home territory
			var rival: int = FACTION_RIVALS.get(faction_id, -1)
			if rival >= 0:
				var rival_home: int = FACTION_HOME_BIOMES.get(rival, -1)
				if biome_id == rival_home:
					# Rival territory penalty: 25% less effective
					base_modifier *= 1.25
	
	return base_modifier


## Checks if two factions are rivals
func is_rival_faction(faction_a: int, faction_b: int) -> bool:
	if faction_a == MapGenerator.Faction.UNCLAIMED or faction_b == MapGenerator.Faction.UNCLAIMED:
		return false
	return FACTION_RIVALS.get(faction_a, -1) == faction_b


## Returns array of environmental hazard dictionaries for a biome
func get_environmental_hazards(biome_id: int) -> Array:
	if ENVIRONMENTAL_HAZARDS.has(biome_id):
		return ENVIRONMENTAL_HAZARDS[biome_id].duplicate(true)
	return []


## Returns the home biome for a faction
func get_faction_home_biome(faction_id: int) -> int:
	return FACTION_HOME_BIOMES.get(faction_id, -1)


## Returns the rival faction for a given faction
func get_rival_faction(faction_id: int) -> int:
	return FACTION_RIVALS.get(faction_id, -1)


## Checks if a faction is in their home biome
func is_home_biome(faction_id: int, biome_id: int) -> bool:
	return FACTION_HOME_BIOMES.get(faction_id, -1) == biome_id


## Checks if a faction is in their rival's home biome
func is_rival_territory(faction_id: int, biome_id: int) -> bool:
	var rival: int = FACTION_RIVALS.get(faction_id, -1)
	if rival < 0:
		return false
	var rival_home_biome: int = FACTION_HOME_BIOMES.get(rival, -1)
	return rival_home_biome == biome_id


# =============================================================================
# UTILITY METHODS
# =============================================================================

## Returns all biome IDs
func get_all_biome_ids() -> Array:
	return BIOME_DATA.keys()


## Returns all faction IDs (excluding UNCLAIMED)
func get_all_faction_ids() -> Array:
	return [
		MapGenerator.Faction.CASTLE,
		MapGenerator.Faction.RAMPART,
		MapGenerator.Faction.TOWER,
		MapGenerator.Faction.INFERNO,
		MapGenerator.Faction.NECROPOLIS,
		MapGenerator.Faction.DUNGEON,
		MapGenerator.Faction.STRONGHOLD,
		MapGenerator.Faction.FORTRESS
	]


## Debug: Prints all biome data to console
func debug_print_biomes() -> void:
	print("[BiomeManager] === BIOME DATABASE ===")
	for biome_id in BIOME_DATA.keys():
		var data: Dictionary = BIOME_DATA[biome_id]
		print("  %s (ID: %d):" % [data.display_name, biome_id])
		print("    Danger: %.1f | Temp: %.1f | Humidity: %.1f" % [
			data.danger_rating, data.temperature, data.humidity
		])
		print("    Materials: %s" % str(data.base_materials))
		print("    Weather: %s" % str(data.weather_profiles))


## Debug: Prints faction rivalry matrix
func debug_print_rivalries() -> void:
	print("[BiomeManager] === FACTION RIVALRIES ===")
	for faction_id: int in get_all_faction_ids():
		var faction_name: String = MapGenerator.Faction.keys()[faction_id]
		var rival_id: int = FACTION_RIVALS.get(faction_id, -1)
		var rival_name: String = "None" if rival_id < 0 else MapGenerator.Faction.keys()[rival_id]
		var home_biome: int = FACTION_HOME_BIOMES.get(faction_id, -1)
		var home_name := "None" if home_biome < 0 else get_biome_name(home_biome)
		print("  %s: Rival=%s, Home=%s" % [faction_name, rival_name, home_name])
