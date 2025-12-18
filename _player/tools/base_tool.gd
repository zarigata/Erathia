extends Node3D
class_name BaseTool

# Tool properties
@export_group("Tool Properties")
@export var tool_tier: int = ToolConstants.ToolTier.STONE
@export var stamina_cost_per_use: float = 10.0
@export var cooldown_duration: float = 0.5
@export var durability_max: int = 100

# State variables
var current_durability: int
var cooldown_timer: float = 0.0
var is_equipped: bool = false
var player: CharacterBody3D = null

# Signals
signal tool_used(position: Vector3, success: bool)
signal tool_broken()
signal cooldown_started()
signal cooldown_ended()
signal tool_use_failed(reason: String)


func _ready() -> void:
	current_durability = durability_max


func _process(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			cooldown_timer = 0.0
			_on_cooldown_complete()
			cooldown_ended.emit()


func set_player(p: CharacterBody3D) -> void:
	player = p


func equip() -> void:
	is_equipped = true
	visible = true


func unequip() -> void:
	is_equipped = false
	visible = false


func is_on_cooldown() -> bool:
	return cooldown_timer > 0.0


func get_cooldown_progress() -> float:
	if cooldown_duration <= 0.0:
		return 1.0
	return 1.0 - (cooldown_timer / cooldown_duration)


func is_broken() -> bool:
	return current_durability <= 0


func get_durability_percent() -> float:
	if durability_max <= 0:
		return 0.0
	return float(current_durability) / float(durability_max)


func _start_cooldown() -> void:
	cooldown_timer = cooldown_duration
	cooldown_started.emit()


func _reduce_durability(amount: int = 1) -> void:
	current_durability -= amount
	if current_durability <= 0:
		current_durability = 0
		tool_broken.emit()


func _has_stamina() -> bool:
	if player == null:
		return false
	return player.get_stamina() >= stamina_cost_per_use


func _consume_player_stamina() -> bool:
	if player == null:
		return false
	return player.consume_stamina(stamina_cost_per_use)


# Virtual methods to be overridden by subclasses
func _can_use() -> bool:
	if is_on_cooldown():
		return false
	if is_broken():
		return false
	if not _has_stamina():
		return false
	return true


func _use(_hit_result: VoxelRaycastResult) -> bool:
	push_warning("[BaseTool] _use() called on base class - override in subclass")
	return false


func _on_cooldown_complete() -> void:
	pass


# Public API for tool usage
func use(hit_result: VoxelRaycastResult) -> bool:
	if not _can_use():
		if is_on_cooldown():
			var remaining := snappedf(cooldown_timer, 0.1)
			print("[BaseTool] Cooldown active: %.1fs remaining" % remaining)
			tool_use_failed.emit("Cooldown (%.1fs)" % remaining)
		elif is_broken():
			print("[BaseTool] Tool is broken (durability: %d/%d)" % [current_durability, durability_max])
			tool_use_failed.emit("Tool broken")
		elif not _has_stamina():
			var current: float = player.get_stamina() if player else 0.0
			print("[BaseTool] Not enough stamina: %.1f/%.1f needed" % [current, stamina_cost_per_use])
			tool_use_failed.emit("Need %.0f stamina" % stamina_cost_per_use)
		return false
	
	return _use(hit_result)
