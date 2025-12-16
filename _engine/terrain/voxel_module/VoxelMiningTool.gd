class_name VoxelMiningTool
extends Node3D
## Mining tool using VoxelTool for terrain deformation with visual feedback.
## Requires VoxelLodTerrain in the scene (godot_voxel module).
## Gracefully disables itself if godot_voxel is not available.

@export var max_reach: float = 6.0
@export var dig_radius: float = 2.0
@export var build_radius: float = 2.0
@export var dig_strength: float = 3.0
@export var build_strength: float = 3.0
@export var mining_cooldown: float = 0.15

@export_group("Visual Feedback")
@export var show_particles: bool = true
@export var particle_count: int = 12
@export var hit_marker_duration: float = 0.1

var _camera: Camera3D
var _voxel_terrain: Node  # Use Node to avoid type errors when module missing
var _cooldown_timer: float = 0.0
var _voxel_available: bool = false

var current_tool: int = 0  # 0=Pickaxe, 1=Shovel, 2=Hoe
var current_tier: int = 1  # Tool tier for power calculation

# Visual feedback nodes
var _hit_particles: GPUParticles3D
var _hit_marker: MeshInstance3D

signal terrain_modified(position: Vector3, is_digging: bool)
signal hit_nothing()
signal material_mined(position: Vector3)


func _ready() -> void:
	call_deferred("_find_references")
	_setup_visual_feedback()


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func _find_references() -> void:
	# Check if godot_voxel module is available
	_voxel_available = ClassDB.class_exists("VoxelLodTerrain")
	if not _voxel_available:
		print("VoxelMiningTool: godot_voxel module not available, disabling.")
		return
	
	# Find camera
	var parent: Node = get_parent()
	while parent != null:
		if parent is CharacterBody3D:
			_camera = parent.get_node_or_null("Camera3D") as Camera3D
			break
		if parent is Camera3D:
			_camera = parent as Camera3D
			break
		parent = parent.get_parent()
	
	if _camera == null:
		push_warning("VoxelMiningTool: Could not find Camera3D!")
	
	# Find VoxelLodTerrain (use find_child without type cast)
	var root: Node = get_tree().root
	_voxel_terrain = root.find_child("VoxelTerrain", true, false)
	if _voxel_terrain == null:
		_voxel_terrain = root.find_child("VoxelLodTerrain", true, false)
	
	if _voxel_terrain == null:
		print("VoxelMiningTool: No VoxelLodTerrain found, using fallback.")
		_voxel_available = false
	else:
		print("VoxelMiningTool: Found VoxelLodTerrain, voxel mining enabled.")


func _setup_visual_feedback() -> void:
	# Create hit marker (small sphere that appears on hit)
	_hit_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	_hit_marker.mesh = sphere
	
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.8)
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(1.0, 0.6, 0.1)
	marker_mat.emission_energy_multiplier = 2.0
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hit_marker.material_override = marker_mat
	_hit_marker.visible = false
	add_child(_hit_marker)
	
	# Create particle system for mining feedback
	_hit_particles = GPUParticles3D.new()
	_hit_particles.emitting = false
	_hit_particles.one_shot = true
	_hit_particles.explosiveness = 0.9
	_hit_particles.amount = particle_count
	_hit_particles.lifetime = 0.5
	
	var particle_mat := ParticleProcessMaterial.new()
	particle_mat.direction = Vector3(0, 1, 0)
	particle_mat.spread = 45.0
	particle_mat.initial_velocity_min = 2.0
	particle_mat.initial_velocity_max = 5.0
	particle_mat.gravity = Vector3(0, -15, 0)
	particle_mat.scale_min = 0.05
	particle_mat.scale_max = 0.15
	particle_mat.color = Color(0.6, 0.5, 0.3)
	_hit_particles.process_material = particle_mat
	
	# Simple cube mesh for particles
	var particle_mesh := BoxMesh.new()
	particle_mesh.size = Vector3(0.1, 0.1, 0.1)
	_hit_particles.draw_pass_1 = particle_mesh
	
	add_child(_hit_particles)


func _input(event: InputEvent) -> void:
	# Only process when mouse is captured and voxel module available
	if not _voxel_available:
		return
	
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	
	if _voxel_terrain == null:
		return
	
	if _cooldown_timer > 0.0:
		return
	
	# Tool switching
	if event.is_action_pressed("equip_1"):
		current_tool = 0  # Pickaxe
	elif event.is_action_pressed("equip_2"):
		current_tool = 1  # Shovel
	elif event.is_action_pressed("equip_3"):
		current_tool = 2  # Hoe
	
	# Primary action (dig)
	if event.is_action_pressed("attack"):
		_perform_mining(true)
		_cooldown_timer = mining_cooldown
	
	# Secondary action (build)
	elif event.is_action_pressed("use"):
		_perform_mining(false)
		_cooldown_timer = mining_cooldown


func _perform_mining(is_digging: bool) -> void:
	if _camera == null or _voxel_terrain == null or not _voxel_available:
		return
	
	# Get VoxelTool for terrain modification (dynamic call)
	var voxel_tool = _voxel_terrain.get_voxel_tool()
	voxel_tool.channel = 1  # CHANNEL_SDF = 1
	
	# Raycast from camera center
	var ray_origin: Vector3 = _camera.global_position
	var ray_dir: Vector3 = -_camera.global_transform.basis.z
	
	# Use VoxelTool raycast for precise terrain hit
	var result = voxel_tool.raycast(ray_origin, ray_dir, max_reach)
	
	if result == null:
		hit_nothing.emit()
		return
	
	var hit_pos: Vector3 = Vector3(result.position)
	var hit_prev: Vector3 = Vector3(result.previous_position)
	
	# Calculate edit position
	var edit_pos: Vector3
	if is_digging:
		edit_pos = hit_pos
	else:
		edit_pos = hit_prev
	
	# Show visual feedback
	_show_hit_feedback(edit_pos, is_digging)
	
	# Perform terrain edit
	var radius: float = dig_radius if is_digging else build_radius
	var strength: float = dig_strength if is_digging else build_strength
	
	# VoxelTool mode constants: MODE_ADD = 0, MODE_REMOVE = 1
	const MODE_ADD: int = 0
	const MODE_REMOVE: int = 1
	
	# Tool-specific behavior
	match current_tool:
		0:  # Pickaxe - sphere dig
			voxel_tool.mode = MODE_REMOVE if is_digging else MODE_ADD
			voxel_tool.do_sphere(edit_pos, radius)
		
		1:  # Shovel - larger, softer dig
			voxel_tool.mode = MODE_REMOVE if is_digging else MODE_ADD
			voxel_tool.do_sphere(edit_pos, radius * 1.3)
		
		2:  # Hoe - smoothing/flattening
			voxel_tool.smooth_sphere(edit_pos, radius * 1.5, strength)
	
	terrain_modified.emit(edit_pos, is_digging)
	
	if is_digging:
		material_mined.emit(edit_pos)
		_collect_material(edit_pos)


func _show_hit_feedback(pos: Vector3, is_digging: bool) -> void:
	if not show_particles:
		return
	
	# Position and show hit marker
	_hit_marker.global_position = pos
	_hit_marker.visible = true
	
	# Change color based on action
	var mat: StandardMaterial3D = _hit_marker.material_override as StandardMaterial3D
	if is_digging:
		mat.albedo_color = Color(1.0, 0.5, 0.2, 0.8)
		mat.emission = Color(1.0, 0.3, 0.1)
	else:
		mat.albedo_color = Color(0.2, 1.0, 0.5, 0.8)
		mat.emission = Color(0.1, 1.0, 0.3)
	
	# Emit particles
	_hit_particles.global_position = pos
	_hit_particles.emitting = true
	
	# Hide marker after duration
	get_tree().create_timer(hit_marker_duration).timeout.connect(
		func(): _hit_marker.visible = false
	)


func _collect_material(pos: Vector3) -> void:
	# Simplified loot collection - integrate with your inventory system
	var loot_items: Array[String] = ["Stone", "Dirt Clump", "Sand Pile"]
	var item: String = loot_items[randi() % loot_items.size()]
	
	if InventoryManager.has_method("add_item"):
		var remainder: int = InventoryManager.add_item(item, 1)
		if remainder == 0:
			print("Collected: ", item)


## Raycast terrain and return hit info
func raycast_terrain() -> Dictionary:
	if _camera == null or _voxel_terrain == null or not _voxel_available:
		return {}
	
	var voxel_tool = _voxel_terrain.get_voxel_tool()
	var ray_origin: Vector3 = _camera.global_position
	var ray_dir: Vector3 = -_camera.global_transform.basis.z
	
	var result = voxel_tool.raycast(ray_origin, ray_dir, max_reach)
	
	if result == null:
		return {}
	
	return {
		"position": Vector3(result.position),
		"previous_position": Vector3(result.previous_position),
		"distance": result.distance
	}


## Check if voxel module is available
func is_voxel_available() -> bool:
	return _voxel_available
