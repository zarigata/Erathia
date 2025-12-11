class_name UnderwaterDecorator
extends Node

# Simple decorator that spawns props on chunks
# This is a placeholder for a more complex biome system

static func decorate_chunk(chunk: Node3D, local_pos: Vector3, global_pos: Vector3, density: float):
	# Chance to spawn something
	var rng = randf()
	if rng > 0.95: # 5% chance per voxel? Too high for voxels. 
		# This should probably be called per-surface-voxel or scatter approach
		pass

# Better approach: Call this for specific surface points found during mesh generation
# But for now, let's just make a function that Chunks can call after generating mesh
# or during mesh generation when they detect a surface face.

static func spawn_starfish(parent: Node3D, pos: Vector3):
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.5, 0.1, 0.5)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.0) # Orange
	mesh.material = mat
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	parent.add_child(mesh_instance)

static func spawn_seaweed(parent: Node3D, pos: Vector3):
	var mesh_instance = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.1
	mesh.bottom_radius = 0.1
	mesh.height = 1.5
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.8, 0.2) # Green
	mesh.material = mat
	mesh_instance.mesh = mesh
	mesh_instance.position = pos + Vector3(0, 0.75, 0)
	parent.add_child(mesh_instance)
