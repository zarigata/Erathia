extends Node

func _ready() -> void:
	print("AutoTest: Waiting to enter build mode...")
	await get_tree().create_timer(2.0).timeout
	if SnapSystem:
		print("AutoTest: Entering build mode...")
		SnapSystem.enter_build_mode("wood_wall")
	else:
		push_error("AutoTest: SnapSystem not found!")
