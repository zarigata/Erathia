extends Node
## SnapSystem Singleton - Manages building placement with snap point detection
## Autoload: SnapSystem
##
## Mouse Mode Coordination:
## - BuildUI controls mouse visibility based on browser panel state
## - SnapSystem keeps mouse captured during preview placement
## - When browser opens: mouse becomes visible for UI interaction
## - When browser closes: mouse captures for camera control

# Build mode states
enum BuildMode { IDLE, PREVIEW, PLACING }

# Snap mode states
enum SnapMode { NONE, SNAP_POINT, GRID }

# Signals
signal build_mode_changed(mode: BuildMode)
signal piece_placed(piece: BuildPiece, position: Vector3)
signal piece_selection_changed(piece_id: String)
signal preview_validity_changed(is_valid: bool)

# Configuration
@export_group("Snap Detection")
@export var snap_detection_radius: float = 1.0
@export var snap_alignment_threshold: float = 0.3
@export var grid_size: float = 1.0
@export var preview_raycast_distance: float = 20.0
@export var collision_check_enabled: bool = true

# State variables
var current_mode: BuildMode = BuildMode.IDLE
var current_snap_mode: SnapMode = SnapMode.NONE
var selected_piece_id: String = ""
var preview_piece: BuildPiece = null
var preview_rotation: float = 0.0
var preview_position: Vector3 = Vector3.ZERO
var preview_is_valid: bool = false
var nearby_placed_pieces: Array[BuildPiece] = []
var active_snap_point: Dictionary = {}

# Internal state
var _last_validity: bool = false
var _preview_container: Node3D = null
var _placed_pieces_container: Node3D = null
var _infinite_building_active: bool = false
var _tool_manager: Node = null

# Default piece for quick build mode entry
const DEFAULT_PIECE_ID: String = "wood_wall"


func _ready() -> void:
	_setup_containers()
	
	# Connect to DevConsole cheat signals
	if DevConsole:
		DevConsole.cheat_toggled.connect(_on_cheat_toggled)
	
	# Get reference to player's ToolManager (deferred to ensure player is ready)
	call_deferred("_setup_tool_manager_reference")


func _setup_tool_manager_reference() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_node("ToolManager"):
		_tool_manager = player.get_node("ToolManager")


func _on_cheat_toggled(cheat_name: String, enabled: bool) -> void:
	if cheat_name == "infinite_build":
		_infinite_building_active = enabled


func _setup_containers() -> void:
	_preview_container = Node3D.new()
	_preview_container.name = "PreviewContainer"
	add_child(_preview_container)
	
	_placed_pieces_container = Node3D.new()
	_placed_pieces_container.name = "PlacedPieces"
	add_child(_placed_pieces_container)


func _process(delta: float) -> void:
	if current_mode != BuildMode.PREVIEW:
		return
	
	_update_preview_position()
	_update_preview_validity()


func _unhandled_input(event: InputEvent) -> void:
	# Toggle build mode
	if event.is_action_pressed("build_mode_toggle"):
		if current_mode == BuildMode.IDLE:
			enter_build_mode(DEFAULT_PIECE_ID)
		else:
			# Check if BuildUI browser is visible - if so, let BuildUI handle the toggle
			var build_ui := get_node_or_null("/root/BuildUI")
			if build_ui and build_ui.is_browser_visible():
				return  # Let BuildUI handle browser toggle
			exit_build_mode()
		get_viewport().set_input_as_handled()
		return
	
	# Only handle other inputs in PREVIEW mode
	if current_mode != BuildMode.PREVIEW:
		return
	
	# Place piece
	if event.is_action_pressed("build_place"):
		confirm_placement()
		get_viewport().set_input_as_handled()
		return
	
	# Cancel build mode
	if event.is_action_pressed("build_cancel"):
		exit_build_mode()
		get_viewport().set_input_as_handled()
		return
	
	# Rotate preview clockwise
	if event.is_action_pressed("build_rotate_cw"):
		rotate_preview(1)
		get_viewport().set_input_as_handled()
		return
	
	# Rotate preview counter-clockwise
	if event.is_action_pressed("build_rotate_ccw"):
		rotate_preview(-1)
		get_viewport().set_input_as_handled()
		return


# ============================================================================
# BUILD MODE MANAGEMENT
# ============================================================================

func enter_build_mode(piece_id: String) -> void:
	# Validate piece exists in database
	var piece_db := get_node_or_null("/root/PieceDatabase")
	if not piece_db:
		push_error("SnapSystem: PieceDatabase not available")
		return
	
	var piece_data: BuildPieceData = piece_db.get_piece_data(piece_id)
	if not piece_data:
		push_error("SnapSystem: Unknown piece_id '%s'" % piece_id)
		return
	
	# Set state
	current_mode = BuildMode.PREVIEW
	selected_piece_id = piece_id
	preview_rotation = 0.0
	
	# Create preview piece
	preview_piece = PieceFactory.create_preview_piece(piece_id)
	if preview_piece:
		_preview_container.add_child(preview_piece)
		preview_piece.preview_mode(true)
	
	# Notify tool manager to enter build mode
	if _tool_manager and _tool_manager.has_method("enter_build_mode"):
		_tool_manager.enter_build_mode()
	
	# Emit signals
	build_mode_changed.emit(BuildMode.PREVIEW)
	piece_selection_changed.emit(piece_id)


func exit_build_mode() -> void:
	# Notify tool manager to exit build mode first
	if _tool_manager and _tool_manager.has_method("exit_build_mode"):
		_tool_manager.exit_build_mode()
	
	current_mode = BuildMode.IDLE
	
	# Destroy preview piece
	if preview_piece:
		preview_piece.queue_free()
		preview_piece = null
	
	# Clear state
	selected_piece_id = ""
	active_snap_point = {}
	nearby_placed_pieces.clear()
	preview_is_valid = false
	_last_validity = false
	
	# Emit signal
	build_mode_changed.emit(BuildMode.IDLE)


func change_selected_piece(piece_id: String) -> void:
	if current_mode != BuildMode.PREVIEW:
		return
	
	# Validate piece exists
	var piece_db := get_node_or_null("/root/PieceDatabase")
	if not piece_db:
		return
	
	var piece_data: BuildPieceData = piece_db.get_piece_data(piece_id)
	if not piece_data:
		push_error("SnapSystem: Unknown piece_id '%s'" % piece_id)
		return
	
	# Destroy current preview
	if preview_piece:
		preview_piece.queue_free()
		preview_piece = null
	
	# Create new preview
	selected_piece_id = piece_id
	preview_rotation = 0.0
	
	preview_piece = PieceFactory.create_preview_piece(piece_id)
	if preview_piece:
		_preview_container.add_child(preview_piece)
		preview_piece.preview_mode(true)
	
	# Emit signal
	piece_selection_changed.emit(piece_id)


# ============================================================================
# PREVIEW UPDATE LOOP
# ============================================================================

func _update_preview_position() -> void:
	if not preview_piece:
		return
	
	# Get camera
	var camera := get_viewport().get_camera_3d()
	if not camera:
		active_snap_point = {}
		preview_is_valid = false
		preview_piece.visible = false
		return
	
	# Raycast from camera center
	var hit: VoxelRaycastResult = null
	if TerrainEditSystem:
		hit = TerrainEditSystem.raycast_from_camera(camera, preview_raycast_distance)
	
	if not hit:
		active_snap_point = {}
		preview_is_valid = false
		preview_piece.visible = false
		return
	
	preview_piece.visible = true
	var cursor_position: Vector3 = Vector3(hit.position)
	
	# Find nearby placed pieces
	_update_nearby_pieces(cursor_position)
	
	# Attempt snap point alignment
	var snap_data := _find_best_snap_point(cursor_position)
	
	if not snap_data.is_empty():
		# Snap to snap point
		current_snap_mode = SnapMode.SNAP_POINT
		active_snap_point = snap_data
		preview_position = snap_data.get("aligned_position", cursor_position)
		# Optionally align rotation to snap normal
		var snap_rotation: float = snap_data.get("aligned_rotation", preview_rotation)
		if snap_data.has("aligned_rotation"):
			preview_rotation = snap_rotation
	else:
		# Fallback to grid snapping
		current_snap_mode = SnapMode.GRID
		active_snap_point = {}
		
		# Snap X and Z to grid, keep Y at terrain surface
		var snapped_x: float = floor(cursor_position.x / grid_size) * grid_size + grid_size * 0.5
		var snapped_z: float = floor(cursor_position.z / grid_size) * grid_size + grid_size * 0.5
		preview_position = Vector3(snapped_x, cursor_position.y, snapped_z)
	
	# Update preview piece transform
	preview_piece.global_position = preview_position
	preview_piece.rotation.y = preview_rotation


func _update_nearby_pieces(cursor_position: Vector3) -> void:
	nearby_placed_pieces.clear()
	
	# Query all placed pieces
	var placed_pieces := get_tree().get_nodes_in_group("placed_pieces")
	var search_radius: float = snap_detection_radius * 3.0
	
	for node in placed_pieces:
		if node is BuildPiece:
			var piece := node as BuildPiece
			var distance: float = piece.global_position.distance_to(cursor_position)
			if distance <= search_radius:
				nearby_placed_pieces.append(piece)


func _find_best_snap_point(cursor_position: Vector3) -> Dictionary:
	if not preview_piece or nearby_placed_pieces.is_empty():
		return {}
	
	# Get preview piece's snap points in world space
	var preview_snaps: Array[Dictionary] = preview_piece.get_snap_point_data()
	if preview_snaps.is_empty():
		return {}
	
	var best_snap: Dictionary = {}
	var best_score: float = INF
	
	for placed_piece in nearby_placed_pieces:
		var placed_snaps: Array[Dictionary] = placed_piece.get_snap_point_data()
		
		for preview_snap in preview_snaps:
			var preview_type: int = preview_snap.get("type", BuildPieceData.SnapType.EDGE)
			var preview_compatible: Array = preview_snap.get("compatible_types", [])
			
			for placed_snap in placed_snaps:
				var placed_type: int = placed_snap.get("type", BuildPieceData.SnapType.EDGE)
				var placed_compatible: Array = placed_snap.get("compatible_types", [])
				
				# Check type compatibility (either direction)
				var is_compatible: bool = false
				if preview_compatible.has(placed_type) or placed_compatible.has(preview_type):
					is_compatible = true
				# Also allow same-type connections
				if preview_type == placed_type:
					is_compatible = true
				
				if not is_compatible:
					continue
				
				# Calculate distance between snap points
				var preview_world_pos: Vector3 = preview_snap.get("position", Vector3.ZERO)
				var placed_world_pos: Vector3 = placed_snap.get("position", Vector3.ZERO)
				
				# We need to calculate where the preview piece would be if this snap aligned
				# The preview snap point should align with the placed snap point
				var preview_local_offset: Vector3 = preview_world_pos - preview_piece.global_position
				var aligned_position: Vector3 = placed_world_pos - preview_local_offset
				
				# Distance from cursor to aligned position
				var distance: float = cursor_position.distance_to(aligned_position)
				
				if distance > snap_detection_radius:
					continue
				
				# Calculate alignment score (lower is better)
				# Factor in normal alignment - normals should be opposite for good connection
				var preview_normal: Vector3 = preview_snap.get("normal", Vector3.UP)
				var placed_normal: Vector3 = placed_snap.get("normal", Vector3.UP)
				var normal_alignment: float = preview_normal.dot(placed_normal)
				
				# Ideal alignment is -1 (opposite normals), penalize positive alignment
				var alignment_penalty: float = (normal_alignment + 1.0) * 0.5  # 0 when opposite, 1 when same
				var score: float = distance + alignment_penalty * snap_detection_radius
				
				if score < best_score:
					best_score = score
					best_snap = {
						"position": placed_world_pos,
						"normal": placed_normal,
						"type": placed_type,
						"aligned_position": aligned_position,
						"preview_snap": preview_snap,
						"placed_snap": placed_snap,
						"placed_piece": placed_piece
					}
					
					# Calculate aligned rotation based on snap normals
					if placed_normal.length_squared() > 0.01 and preview_normal.length_squared() > 0.01:
						var target_normal: Vector3 = -placed_normal  # Preview should face opposite
						target_normal.y = 0.0
						if target_normal.length_squared() > 0.01:
							target_normal = target_normal.normalized()
							best_snap["aligned_rotation"] = atan2(target_normal.x, target_normal.z)
	
	# Only return if score is good enough
	# Distance is already gated by snap_detection_radius above, so only check alignment threshold
	if best_score <= snap_alignment_threshold:
		return best_snap
	
	return {}


# ============================================================================
# PLACEMENT VALIDATION
# ============================================================================

func _update_preview_validity() -> void:
	if not preview_piece:
		preview_is_valid = false
		return
	
	preview_is_valid = _validate_placement()
	
	# Update preview material
	preview_piece.set_preview_valid(preview_is_valid)
	
	# Emit signal if validity changed
	if preview_is_valid != _last_validity:
		_last_validity = preview_is_valid
		preview_validity_changed.emit(preview_is_valid)


func _validate_placement() -> bool:
	if not preview_piece or not preview_piece.piece_data:
		return false
	
	# Resource check
	if not _check_resources():
		return false
	
	# Collision check
	if collision_check_enabled and not _check_collision():
		return false
	
	# Terrain support check
	if not _check_terrain_support():
		return false
	
	# Structural integrity check (placeholder for future)
	if not _check_structural_integrity():
		return false
	
	return true


func _check_resources() -> bool:
	# Bypass resource check when infinite building is active
	if _infinite_building_active:
		return true
	
	if not Inventory:
		return true  # Allow placement if no inventory system
	
	if not preview_piece or not preview_piece.piece_data:
		return false
	
	return Inventory.has_building_resources(preview_piece.piece_data)


func _check_collision() -> bool:
	if not preview_piece or not preview_piece.collision_shape:
		return true
	
	var shape: Shape3D = preview_piece.collision_shape.shape
	if not shape:
		return true
	
	# Get physics space
	var space_state := get_viewport().get_world_3d().direct_space_state
	if not space_state:
		return true
	
	# Create query parameters
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(
		Basis.from_euler(Vector3(0, preview_rotation, 0)),
		preview_position
	)
	# Collision mask: detect terrain and other pieces (layers 1 and 2)
	query.collision_mask = 0b11
	query.exclude = []
	
	# Add preview piece's static body to exclusion if it exists
	if preview_piece.static_body:
		query.exclude.append(preview_piece.static_body.get_rid())
	
	# Check for intersections
	var results := space_state.intersect_shape(query, 1)
	
	# If any collision detected, placement is invalid
	return results.is_empty()


func _check_terrain_support() -> bool:
	if not preview_piece or not preview_piece.piece_data:
		return true
	
	# Some categories don't need ground support
	var category: int = preview_piece.piece_data.category
	if category == BuildPieceData.Category.ROOF:
		return true  # Roofs can float (attached to walls)
	
	# For snap point placements, assume structural support from connected piece
	if current_snap_mode == SnapMode.SNAP_POINT and not active_snap_point.is_empty():
		return true
	
	# For grid placements, check terrain below
	if not TerrainEditSystem:
		return true
	
	# Raycast downward from piece center
	var piece_height: float = preview_piece.piece_data.dimensions.y if preview_piece.piece_data else 2.0
	var ray_origin: Vector3 = preview_position + Vector3(0, piece_height * 0.5, 0)
	var hit := TerrainEditSystem.raycast(ray_origin, Vector3.DOWN, piece_height + 2.0)
	
	# Must have terrain within reasonable distance
	return hit != null


func _check_structural_integrity() -> bool:
	# Placeholder for structural integrity system
	# Hook for future implementation
	if has_node("/root/StructuralIntegrity"):
		var integrity_system := get_node("/root/StructuralIntegrity")
		if integrity_system.has_method("check_support"):
			return integrity_system.check_support(preview_piece, preview_position)
	
	return true


# ============================================================================
# PIECE PLACEMENT
# ============================================================================

func confirm_placement() -> bool:
	# Guard clauses
	if current_mode != BuildMode.PREVIEW:
		return false
	
	if not preview_is_valid:
		return false
	
	if not preview_piece:
		return false
	
	# Get piece ID
	var piece_id: String = preview_piece.piece_data.piece_id if preview_piece.piece_data else selected_piece_id
	
	# Create real piece
	var placed_piece: BuildPiece = PieceFactory.create_piece(piece_id, 0)
	if not placed_piece:
		push_error("SnapSystem: Failed to create piece '%s'" % piece_id)
		return false
	
	# Set transform
	placed_piece.global_position = preview_position
	placed_piece.rotation.y = preview_rotation
	
	# Place piece (consumes resources)
	var inventory_ref: Node = Inventory if Inventory else null
	if not placed_piece.place(preview_position, preview_rotation, inventory_ref):
		placed_piece.queue_free()
		return false
	
	# Add to scene
	_placed_pieces_container.add_child(placed_piece)
	placed_piece.add_to_group("placed_pieces")
	
	# Emit signal
	piece_placed.emit(placed_piece, preview_position)
	
	# Reset preview state but stay in build mode for continuous building
	active_snap_point = {}
	
	return true


# ============================================================================
# ROTATION CONTROL
# ============================================================================

func rotate_preview(direction: int) -> void:
	if current_mode != BuildMode.PREVIEW:
		return
	
	# Rotate by 90 degrees
	preview_rotation += direction * PI / 2.0
	
	# Normalize to 0-2π range
	preview_rotation = fmod(preview_rotation, TAU)
	if preview_rotation < 0:
		preview_rotation += TAU
	
	# Immediately update preview piece
	if preview_piece:
		preview_piece.rotation.y = preview_rotation


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

func is_in_build_mode() -> bool:
	return current_mode != BuildMode.IDLE


func get_current_mode() -> BuildMode:
	return current_mode


func get_current_snap_mode() -> SnapMode:
	return current_snap_mode


func get_selected_piece_id() -> String:
	return selected_piece_id


func get_preview_position() -> Vector3:
	return preview_position


func get_preview_rotation() -> float:
	return preview_rotation


func is_preview_valid() -> bool:
	return preview_is_valid


func get_placed_pieces_count() -> int:
	return get_tree().get_nodes_in_group("placed_pieces").size()


func get_all_placed_pieces() -> Array[BuildPiece]:
	var pieces: Array[BuildPiece] = []
	for node in get_tree().get_nodes_in_group("placed_pieces"):
		if node is BuildPiece:
			pieces.append(node)
	return pieces
