class_name PlayerInteraction
extends RayCast3D

@export var crosshair: Control
@export var prompt_label: Label

var current_interactable: Interactable

func _ready():
	enabled = true
	exclude_parent = true
	target_position = Vector3(0, 0, -3.0) # 3 meters reach
	collision_mask = 2 # Ensure this matches your Interactable collision layer
	
	# Try to find crosshair if not set
	if not crosshair:
		crosshair = get_tree().root.find_child("Crosshair", true, false)

func _process(_delta):
	var collider = get_collider()
	
	# Resolve the Interactable component
	# Sometimes the collider IS the interactable, sometimes it's a child or parent
	# We'll look for an Interactable child on the collider, or assume collider is Interactable
	var interactable: Interactable = null
	
	if is_colliding() and collider:
		if collider is Interactable:
			interactable = collider
		else:
			# Look for Interactable child
			for child in collider.get_children():
				if child is Interactable:
					interactable = child
					break
			# Or look for Interactable parent (if collider is just a StaticBody child)
			if not interactable and collider.get_parent() is Interactable:
				interactable = collider.get_parent()
	
	# State Change Logic
	if current_interactable != interactable:
		if current_interactable:
			current_interactable.unfocus()
			_update_crosshair(false)
		
		current_interactable = interactable
		
		if current_interactable:
			current_interactable.focus()
			_update_crosshair(true)
	
	# Input Logic
	if current_interactable and Input.is_action_just_pressed("interact"):
		current_interactable.interact()
		print("Interacted with: " + current_interactable.name)

func _update_crosshair(active: bool):
	if not crosshair: return
	
	if active:
		crosshair.modulate = Color(1, 1, 0) # Yellow on active
		crosshair.scale = Vector2(1.2, 1.2)
	else:
		crosshair.modulate = Color(1, 1, 1) # White normal
		crosshair.scale = Vector2(1, 1)
