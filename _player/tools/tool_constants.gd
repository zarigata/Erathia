extends Node
# Note: This script is registered as an autoload singleton "ToolConstants" in project.godot
# Do not use class_name as it conflicts with the autoload name

# Material IDs (from smooth_surface.tres)
enum MaterialID {
	AIR = 0,
	DIRT = 1,
	STONE = 2,
	IRON_ORE = 3,
	RARE_CRYSTAL = 4,
}

# Material hardness levels
enum Hardness {
	NONE = 0,      # Air - cannot be mined
	SOFT = 1,      # Dirt, grass
	MEDIUM = 2,    # Stone, rock
	HARD = 3,      # Ores
	VERY_HARD = 4, # Rare crystals, gems
}

# Tool tier levels
enum ToolTier {
	HAND = 0,
	STONE = 1,
	IRON = 2,
	STEEL = 3,
	MAGIC = 4,
}

# Material ID to hardness mapping
const MATERIAL_HARDNESS: Dictionary = {
	MaterialID.AIR: Hardness.NONE,
	MaterialID.DIRT: Hardness.SOFT,
	MaterialID.STONE: Hardness.MEDIUM,
	MaterialID.IRON_ORE: Hardness.HARD,
	MaterialID.RARE_CRYSTAL: Hardness.VERY_HARD,
}

# Minimum tool tier required to mine each hardness level
const HARDNESS_TIER_REQUIREMENTS: Dictionary = {
	Hardness.NONE: ToolTier.HAND,      # Can't mine air anyway
	Hardness.SOFT: ToolTier.HAND,      # Dirt can be mined by hand
	Hardness.MEDIUM: ToolTier.STONE,   # Stone requires stone pickaxe
	Hardness.HARD: ToolTier.IRON,      # Ores require iron pickaxe
	Hardness.VERY_HARD: ToolTier.STEEL, # Rare crystals require steel
}

# Tool tier names for display
const TIER_NAMES: Dictionary = {
	ToolTier.HAND: "Hand",
	ToolTier.STONE: "Stone",
	ToolTier.IRON: "Iron",
	ToolTier.STEEL: "Steel",
	ToolTier.MAGIC: "Magic",
}

# Material names for display
const MATERIAL_NAMES: Dictionary = {
	MaterialID.AIR: "Air",
	MaterialID.DIRT: "Dirt",
	MaterialID.STONE: "Stone",
	MaterialID.IRON_ORE: "Iron Ore",
	MaterialID.RARE_CRYSTAL: "Rare Crystal",
}


func get_material_hardness(material_id: int) -> int:
	if MATERIAL_HARDNESS.has(material_id):
		return MATERIAL_HARDNESS[material_id]
	return Hardness.MEDIUM  # Default to medium for unknown materials


func get_required_tier(hardness: int) -> int:
	if HARDNESS_TIER_REQUIREMENTS.has(hardness):
		return HARDNESS_TIER_REQUIREMENTS[hardness]
	return ToolTier.STONE  # Default requirement


func can_mine_material(p_tool_tier: int, material_id: int) -> bool:
	var hardness := get_material_hardness(material_id)
	var required_tier := get_required_tier(hardness)
	return p_tool_tier >= required_tier


func get_tier_name(tier: int) -> String:
	if TIER_NAMES.has(tier):
		return TIER_NAMES[tier]
	return "Unknown"


func get_material_name(material_id: int) -> String:
	if MATERIAL_NAMES.has(material_id):
		return MATERIAL_NAMES[material_id]
	return "Unknown"
