class_name TerrainEditSystem
extends Node

# Operations
enum OperationType {
	ADD = 0,
	SUBTRACT = 1,
	SMOOTH = 2,
	FLATTEN = 3
}

# Brush Shapes
enum BrushShape {
	SPHERE = 0,
	CUBE = 1
}

static func smooth_terrain(chunk: Chunk, local_center: Vector3, radius: float, strength: float = 0.5):
	# Smoothing averages the density of the target voxel with its neighbors
	# This implementation is a simplified version operating directly on the chunk's density data
	
	var r_int = ceil(radius)
	var min_box = (local_center - Vector3(r_int, r_int, r_int)).floor()
	var max_box = (local_center + Vector3(r_int, r_int, r_int)).ceil()
	
	var radius_sq = radius * radius
	var modified = false
	
	# We need to read from the current state and write to a buffer or applied directly
	# For simplicity/speed in GDScript, we'll do a simple blur pass
	
	# NOTE: Real smoothing should probably sample neighbors from adjacent chunks too.
	# For now, we clamp to chunk bounds.
	
	var data_size = Chunk.DATA_SIZE
	
	for z in range(max(0, min_box.z), min(data_size, max_box.z)):
		for y in range(max(0, min_box.y), min(data_size, max_box.y)):
			for x in range(max(0, min_box.x), min(data_size, max_box.x)):
				var current_pos = Vector3(x, y, z)
				
				# Check if inside brush
				if current_pos.distance_squared_to(local_center + Vector3(1,1,1)) > radius_sq:
					continue
					
				var idx = x + (y * data_size) + (z * data_size * data_size)
				var current_val = chunk.density_data[idx]
				
				# Calculate average of neighbors
				var avg = 0.0
				var count = 0
				
				# 3x3x3 kernel
				for kz in range(-1, 2):
					for ky in range(-1, 2):
						for kx in range(-1, 2):
							var nx = x + kx
							var ny = y + ky
							var nz = z + kz
							
							if nx >= 0 and nx < data_size and ny >= 0 and ny < data_size and nz >= 0 and nz < data_size:
								var n_idx = nx + (ny * data_size) + (nz * data_size * data_size)
								avg += chunk.density_data[n_idx]
								count += 1
				
				if count > 0:
					avg /= float(count)
					var new_val = lerp(current_val, avg, strength)
					
					# Build logic: Only modifying density, not material for now
					chunk.density_data[idx] = new_val
					modified = true

	if modified:
		chunk.schedule_mesh_update()

static func flatten_terrain(chunk: Chunk, local_center: Vector3, radius: float, target_height: float, strength: float = 0.5):
	var r_int = ceil(radius)
	var min_box = (local_center - Vector3(r_int, r_int, r_int)).floor()
	var max_box = (local_center + Vector3(r_int, r_int, r_int)).ceil()
	
	var radius_sq = radius * radius
	var modified = false
	var data_size = Chunk.DATA_SIZE
	
	# Global height target needs to be converted to local density target logic if possible
	# But in isosurface, surface is where density = 0.
	# So "flattening" usually means pushing density towards (y - target_local_y)
	
	var chunk_origin_y = chunk.chunk_position.y * Chunk.CHUNK_SIZE
	
	for z in range(max(0, min_box.z), min(data_size, max_box.z)):
		for y in range(max(0, min_box.y), min(data_size, max_box.y)):
			for x in range(max(0, min_box.x), min(data_size, max_box.x)):
				var current_pos = Vector3(x, y, z)
				
				# Check if inside brush
				if current_pos.distance_squared_to(local_center + Vector3(1,1,1)) > radius_sq:
					continue
				
				var idx = x + (y * data_size) + (z * data_size * data_size)
				
				# Calculate target density based on height
				# Global Y for this voxel
				var global_y = chunk_origin_y + (y - 1)
				
				# If we want the surface at target_height:
				# Density should be 0 at target_height.
				# Density > 0 below target_height (solid).
				# Density < 0 above target_height (air).
				
				var target_density = target_height - global_y
				
				# Lerp towards target
				chunk.density_data[idx] = lerp(chunk.density_data[idx], target_density, strength)
				modified = true

	if modified:
		chunk.schedule_mesh_update()
