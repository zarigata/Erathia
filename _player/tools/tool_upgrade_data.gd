extends Resource
class_name ToolUpgradeData

# Upgrade tier data structure
class TierData:
	var tier_level: int
	var stamina_cost: float
	var durability: int
	var box_radius: float
	var cooldown: float
	var display_name: String
	
	func _init(p_tier: int, p_stamina: float, p_durability: int, p_radius: float, p_cooldown: float, p_name: String) -> void:
		tier_level = p_tier
		stamina_cost = p_stamina
		durability = p_durability
		box_radius = p_radius
		cooldown = p_cooldown
		display_name = p_name


# Pickaxe upgrade path
static var PICKAXE_TIERS: Array[TierData] = [
	TierData.new(ToolConstants.ToolTier.HAND, 15.0, 50, 0.5, 0.8, "Bare Hands"),
	TierData.new(ToolConstants.ToolTier.STONE, 10.0, 100, 1.0, 0.5, "Stone Pickaxe"),
	TierData.new(ToolConstants.ToolTier.IRON, 8.0, 200, 1.0, 0.4, "Iron Pickaxe"),
	TierData.new(ToolConstants.ToolTier.STEEL, 6.0, 400, 1.5, 0.3, "Steel Pickaxe"),
	TierData.new(ToolConstants.ToolTier.MAGIC, 4.0, 800, 2.0, 0.2, "Magic Pickaxe"),
]

# Upgrade requirements (material_id: amount)
static var UPGRADE_REQUIREMENTS: Dictionary = {
	ToolConstants.ToolTier.STONE: {
		ToolConstants.MaterialID.STONE: 10,
	},
	ToolConstants.ToolTier.IRON: {
		ToolConstants.MaterialID.STONE: 5,
		ToolConstants.MaterialID.IRON_ORE: 15,
	},
	ToolConstants.ToolTier.STEEL: {
		ToolConstants.MaterialID.IRON_ORE: 10,
		ToolConstants.MaterialID.RARE_CRYSTAL: 5,
	},
	ToolConstants.ToolTier.MAGIC: {
		ToolConstants.MaterialID.RARE_CRYSTAL: 20,
	},
}


static func get_tier_data(tier: int) -> TierData:
	for data in PICKAXE_TIERS:
		if data.tier_level == tier:
			return data
	return null


static func get_next_tier(current_tier: int) -> int:
	for i in range(PICKAXE_TIERS.size() - 1):
		if PICKAXE_TIERS[i].tier_level == current_tier:
			return PICKAXE_TIERS[i + 1].tier_level
	return -1  # Max tier reached


static func get_upgrade_requirements(current_tier: int) -> Dictionary:
	var next_tier := get_next_tier(current_tier)
	if next_tier < 0:
		return {}
	
	if UPGRADE_REQUIREMENTS.has(next_tier):
		return UPGRADE_REQUIREMENTS[next_tier]
	return {}


static func can_upgrade(current_tier: int, inventory: Dictionary) -> bool:
	var requirements := get_upgrade_requirements(current_tier)
	if requirements.is_empty():
		return false
	
	for material_id in requirements:
		var required_amount: int = requirements[material_id]
		var has_amount: int = inventory.get(material_id, 0)
		if has_amount < required_amount:
			return false
	
	return true


static func apply_tier_to_pickaxe(pickaxe: Pickaxe, tier: int) -> void:
	var data := get_tier_data(tier)
	if data == null:
		push_warning("[ToolUpgradeData] No tier data for tier %d" % tier)
		return
	
	pickaxe.tool_tier = data.tier_level
	pickaxe.stamina_cost_per_use = data.stamina_cost
	pickaxe.durability_max = data.durability
	pickaxe.current_durability = data.durability
	pickaxe.box_radius = data.box_radius
	pickaxe.cooldown_duration = data.cooldown
	pickaxe.name = data.display_name
