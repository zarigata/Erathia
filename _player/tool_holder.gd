class_name ToolHolder
extends Node3D
## Manages equipped tool visuals and animations.
## Attach this to the camera or player to show tools in first-person view.

signal tool_changed(tool_type: int)

enum ToolType { HAND, PICKAXE, SHOVEL }

@export var current_tool: ToolType = ToolType.HAND

# Tool mesh instances
var pickaxe_mesh: MeshInstance3D
var shovel_mesh: MeshInstance3D
var current_mesh: MeshInstance3D

# Animation state
var swing_progress: float = 0.0
var is_swinging: bool = false
const SWING_DURATION: float = 0.3

func _ready():
	_create_tool_meshes()
	_update_visible_tool()

func _process(delta):
	# Handle tool switching
	if Input.is_action_just_pressed("equip_1"):
		equip_tool(ToolType.PICKAXE)
	elif Input.is_action_just_pressed("equip_2"):
		equip_tool(ToolType.SHOVEL)
	elif Input.is_action_just_pressed("equip_3"):
		equip_tool(ToolType.HAND)
	
	# Handle swing animation
	if is_swinging:
		swing_progress += delta / SWING_DURATION
		if swing_progress >= 1.0:
			swing_progress = 0.0
			is_swinging = false
			_reset_tool_position()
		else:
			_animate_swing()
	
	# Start swing on attack
	if Input.is_action_just_pressed("attack") and not is_swinging:
		is_swinging = true
		swing_progress = 0.0

func equip_tool(tool_type: ToolType):
	if current_tool == tool_type:
		return
	current_tool = tool_type
	_update_visible_tool()
	tool_changed.emit(tool_type)

func _update_visible_tool():
	# Hide all
	if pickaxe_mesh:
		pickaxe_mesh.visible = false
	if shovel_mesh:
		shovel_mesh.visible = false
	
	# Show current
	match current_tool:
		ToolType.PICKAXE:
			current_mesh = pickaxe_mesh
		ToolType.SHOVEL:
			current_mesh = shovel_mesh
		ToolType.HAND:
			current_mesh = null
	
	if current_mesh:
		current_mesh.visible = true

func _create_tool_meshes():
	# Create pickaxe
	pickaxe_mesh = _create_pickaxe()
	pickaxe_mesh.visible = false
	add_child(pickaxe_mesh)
	
	# Create shovel
	shovel_mesh = _create_shovel()
	shovel_mesh.visible = false
	add_child(shovel_mesh)

func _create_pickaxe() -> MeshInstance3D:
	var holder = MeshInstance3D.new()
	holder.position = Vector3(0.3, -0.2, -0.5)  # Right side, below center, forward
	holder.rotation_degrees = Vector3(0, -15, -30)
	
	# Handle (cylinder)
	var handle_mesh = CylinderMesh.new()
	handle_mesh.top_radius = 0.02
	handle_mesh.bottom_radius = 0.025
	handle_mesh.height = 0.6
	
	var handle = MeshInstance3D.new()
	handle.mesh = handle_mesh
	handle.position = Vector3(0, -0.3, 0)
	
	# Handle material (wood brown)
	var handle_mat = StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.45, 0.3, 0.15)
	handle.material_override = handle_mat
	holder.add_child(handle)
	
	# Head (pickaxe shape - box rotated)
	var head_mesh = BoxMesh.new()
	head_mesh.size = Vector3(0.3, 0.06, 0.06)
	
	var head = MeshInstance3D.new()
	head.mesh = head_mesh
	head.position = Vector3(0, 0, 0)
	
	# Head material (iron gray)
	var head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.5, 0.5, 0.55)
	head_mat.metallic = 0.7
	head.material_override = head_mat
	holder.add_child(head)
	
	# Pickaxe points (two prisms)
	var point_mesh = PrismMesh.new()
	point_mesh.size = Vector3(0.04, 0.15, 0.04)
	
	var left_point = MeshInstance3D.new()
	left_point.mesh = point_mesh
	left_point.position = Vector3(-0.2, 0, 0)
	left_point.rotation_degrees = Vector3(0, 0, 90)
	left_point.material_override = head_mat
	holder.add_child(left_point)
	
	var right_point = MeshInstance3D.new()
	right_point.mesh = point_mesh
	right_point.position = Vector3(0.2, 0, 0)
	right_point.rotation_degrees = Vector3(0, 0, -90)
	right_point.material_override = head_mat
	holder.add_child(right_point)
	
	return holder

func _create_shovel() -> MeshInstance3D:
	var holder = MeshInstance3D.new()
	holder.position = Vector3(0.3, -0.2, -0.5)
	holder.rotation_degrees = Vector3(0, -15, -30)
	
	# Handle (cylinder)
	var handle_mesh = CylinderMesh.new()
	handle_mesh.top_radius = 0.02
	handle_mesh.bottom_radius = 0.02
	handle_mesh.height = 0.7
	
	var handle = MeshInstance3D.new()
	handle.mesh = handle_mesh
	handle.position = Vector3(0, -0.35, 0)
	
	# Handle material (wood)
	var handle_mat = StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.5, 0.35, 0.2)
	handle.material_override = handle_mat
	holder.add_child(handle)
	
	# Blade (box, slightly wider)
	var blade_mesh = BoxMesh.new()
	blade_mesh.size = Vector3(0.12, 0.2, 0.02)
	
	var blade = MeshInstance3D.new()
	blade.mesh = blade_mesh
	blade.position = Vector3(0, 0.1, 0)
	blade.rotation_degrees = Vector3(15, 0, 0)  # Slight angle
	
	# Blade material (metal)
	var blade_mat = StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.45, 0.45, 0.5)
	blade_mat.metallic = 0.6
	blade.material_override = blade_mat
	holder.add_child(blade)
	
	return holder

func _animate_swing():
	if not current_mesh:
		return
	
	# Simple swing arc
	var swing_angle = sin(swing_progress * PI) * 45.0
	current_mesh.rotation_degrees.x = -swing_angle
	current_mesh.position.y = -0.2 - sin(swing_progress * PI) * 0.1

func _reset_tool_position():
	if not current_mesh:
		return
	current_mesh.rotation_degrees = Vector3(0, -15, -30)
	current_mesh.position = Vector3(0.3, -0.2, -0.5)
