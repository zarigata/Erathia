class_name MiningSystem
extends Node

# Material IDs
enum MaterialID {
	AIR = 0,
	DIRT = 1,
	GRASS = 2,
	STONE = 3,
	SAND = 4,
	SNOW = 5,
	IRON_ORE = 6,
	COAL_ORE = 7
}

# Tool Tiers
enum ToolTier {
	HAND = 0,
	WOOD = 1,
	STONE = 2,
	STEEL = 3,
	DIAMOND = 4
}

# Tool Types
enum ToolType {
	NONE = 0,
	PICKAXE = 1,
	SHOVEL = 2,
	HOE = 3,
	STAFF = 4
}

# Material Hardness (Higher = Harder to dig)
const MATERIAL_PROPERTIES = {
	MaterialID.AIR: { "hardness": 0.0, "tool": ToolType.NONE },
	MaterialID.DIRT: { "hardness": 10.0, "tool": ToolType.SHOVEL },
	MaterialID.GRASS: { "hardness": 12.0, "tool": ToolType.SHOVEL },
	MaterialID.STONE: { "hardness": 50.0, "tool": ToolType.PICKAXE },
	MaterialID.SAND: { "hardness": 8.0, "tool": ToolType.SHOVEL },
	MaterialID.SNOW: { "hardness": 5.0, "tool": ToolType.SHOVEL },
	MaterialID.IRON_ORE: { "hardness": 80.0, "tool": ToolType.PICKAXE },
	MaterialID.COAL_ORE: { "hardness": 60.0, "tool": ToolType.PICKAXE }
}

# Tool Power (Effectiveness Multiplier)
const TOOL_POWER = {
	ToolTier.HAND: 1.0,
	ToolTier.WOOD: 2.0,
	ToolTier.STONE: 4.0,
	ToolTier.STEEL: 8.0,
	ToolTier.DIAMOND: 16.0
}

# Loot Tables (Material ID -> Item Name)
# This is a placeholder for a real item system
const LOOT_TABLE = {
	MaterialID.DIRT: "Dirt Clump",
	MaterialID.GRASS: "Dirt Clump", # Grass drops dirt
	MaterialID.STONE: "Stone Rubble",
	MaterialID.SAND: "Sand Pile",
	MaterialID.SNOW: "Snowball",
	MaterialID.IRON_ORE: "Raw Iron",
	MaterialID.COAL_ORE: "Coal"
}

static func get_material_hardness(mat_id: int) -> float:
	if MATERIAL_PROPERTIES.has(mat_id):
		return MATERIAL_PROPERTIES[mat_id].hardness
	return 1.0

static func get_preferred_tool(mat_id: int) -> int:
	if MATERIAL_PROPERTIES.has(mat_id):
		return MATERIAL_PROPERTIES[mat_id].tool
	return ToolType.NONE

static func get_tool_power(tier: int) -> float:
	if TOOL_POWER.has(tier):
		return TOOL_POWER[tier]
	return 1.0

static func get_loot_item(mat_id: int) -> String:
	if LOOT_TABLE.has(mat_id):
		return LOOT_TABLE[mat_id]
	return ""
