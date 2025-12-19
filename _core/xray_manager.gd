extends Node
## X-Ray Vision Manager
##
## Handles terrain transparency and node inspection for debug visualization.
## Managed as child of DevConsole singleton.

var _terrain_node: Node = null
var _original_material: Material = null
var _xray_material: StandardMaterial3D = null
var _is_active: bool = false

# Node inspector child
var node_inspector: Node3D = null


func _ready() -> void:
	_create_xray_material()
	_setup_node_inspector()


var _xray_transparency: float = 0.3


func _create_xray_material() -> void:
	_xray_material = StandardMaterial3D.new()
	_xray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_xray_material.albedo_color = Color(0.3, 0.5, 0.8, _xray_transparency)
	_xray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_xray_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _setup_node_inspector() -> void:
	var inspector_script := load("res://_core/node_inspector.gd")
	if inspector_script:
		node_inspector = inspector_script.new()
		node_inspector.name = "NodeInspector"
		add_child(node_inspector)


func _find_terrain() -> Node:
	if _terrain_node and is_instance_valid(_terrain_node):
		return _terrain_node
	
	var terrain_nodes := get_tree().get_nodes_in_group("terrain")
	if terrain_nodes.size() > 0:
		_terrain_node = terrain_nodes[0]
		return _terrain_node
	
	# Fallback: search for VoxelTerrain
	var root := get_tree().current_scene
	if root:
		for child in root.get_children():
			if child.get_class() == "VoxelTerrain" or child.get_class() == "VoxelLodTerrain":
				_terrain_node = child
				return _terrain_node
	
	return null


func enable_xray() -> void:
	if _is_active:
		return
	
	_is_active = true
	
	var terrain := _find_terrain()
	if terrain:
		# Store original material if possible
		if terrain.has_method("get_mesher"):
			var mesher = terrain.get_mesher()
			if mesher and mesher.has_method("get_material"):
				_original_material = mesher.get_material()
			if mesher and mesher.has_method("set_material"):
				mesher.set_material(_xray_material)
		
		# Alternative: set material override on terrain node
		if terrain is GeometryInstance3D:
			_original_material = terrain.material_override
			terrain.material_override = _xray_material
	
	# Enable node inspector
	if node_inspector:
		node_inspector.set_active(true)


func disable_xray() -> void:
	if not _is_active:
		return
	
	_is_active = false
	
	var terrain := _find_terrain()
	if terrain:
		# Restore original material
		if terrain.has_method("get_mesher"):
			var mesher = terrain.get_mesher()
			if mesher and mesher.has_method("set_material"):
				mesher.set_material(_original_material)
		
		if terrain is GeometryInstance3D:
			terrain.material_override = _original_material
	
	# Disable node inspector
	if node_inspector:
		node_inspector.set_active(false)


func is_active() -> bool:
	return _is_active


## Get information about node at world position via raycast
func get_node_info_at_position(pos: Vector3) -> Dictionary:
	var info := {
		"name": "",
		"type": "",
		"distance": 0.0,
		"biome": "Unknown",
		"material_id": -1
	}
	
	# Query biome if available
	if BiomeManager and BiomeManager.has_method("get_biome_at_position"):
		info["biome"] = BiomeManager.get_biome_at_position(pos)
	
	return info


## Apply settings from debug settings panel
func apply_settings(settings: Dictionary) -> void:
	# Update x-ray transparency
	_xray_transparency = settings.get("xray_transparency", 0.3)
	if _xray_material:
		var color := _xray_material.albedo_color
		_xray_material.albedo_color = Color(color.r, color.g, color.b, _xray_transparency)
	
	# Update node inspector settings
	var label_distance: float = settings.get("xray_label_distance", 50.0)
	if node_inspector and node_inspector.has_method("apply_settings"):
		node_inspector.apply_settings(settings)
