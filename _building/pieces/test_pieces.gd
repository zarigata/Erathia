extends Node3D

@onready var piece_name_label: Label = $UI/InfoPanel/VBoxContainer/PieceNameLabel
@onready var tier_label: Label = $UI/InfoPanel/VBoxContainer/TierLabel
@onready var category_label: Label = $UI/InfoPanel/VBoxContainer/CategoryLabel
@onready var costs_label: Label = $UI/InfoPanel/VBoxContainer/CostsLabel

var _piece_ids: Array[String] = []
var _current_piece_index: int = 0
var _current_material_variant: int = 0
var _current_piece: BuildPiece = null
var _snap_visualizer: SnapPointVisualizer = null
var _show_snap_points: bool = false
var _database: Node = null


func _ready() -> void:
	_database = load("res://_building/pieces/piece_database.gd").new()
	_database._initialize_database()
	add_child(_database)
	
	_piece_ids = _database.get_all_piece_ids()
	_piece_ids.sort()
	
	if _piece_ids.size() > 0:
		_spawn_piece(_piece_ids[0])
	
	_update_ui()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q:
				_previous_piece()
			KEY_E:
				_next_piece()
			KEY_1:
				_set_material_variant(0)
			KEY_2:
				_set_material_variant(1)
			KEY_3:
				_set_material_variant(2)
			KEY_4:
				_set_material_variant(3)
			KEY_R:
				_rotate_piece()
			KEY_SPACE:
				_toggle_snap_points()


func _previous_piece() -> void:
	if _piece_ids.is_empty():
		return
	_current_piece_index = (_current_piece_index - 1 + _piece_ids.size()) % _piece_ids.size()
	_spawn_piece(_piece_ids[_current_piece_index])
	_update_ui()


func _next_piece() -> void:
	if _piece_ids.is_empty():
		return
	_current_piece_index = (_current_piece_index + 1) % _piece_ids.size()
	_spawn_piece(_piece_ids[_current_piece_index])
	_update_ui()


func _set_material_variant(variant: int) -> void:
	_current_material_variant = variant
	if _current_piece:
		_current_piece.set_material_variant(variant)
	_spawn_piece(_piece_ids[_current_piece_index])
	_update_ui()


func _rotate_piece() -> void:
	if _current_piece:
		_current_piece.rotation.y += PI / 4.0


func _toggle_snap_points() -> void:
	_show_snap_points = not _show_snap_points
	if _snap_visualizer:
		_snap_visualizer.set_visible_snap_points(_show_snap_points)


func _spawn_piece(piece_id: String) -> void:
	if _current_piece:
		_current_piece.queue_free()
		_current_piece = null
	
	if _snap_visualizer:
		_snap_visualizer.queue_free()
		_snap_visualizer = null
	
	_current_piece = PieceFactory.create_piece(piece_id, _current_material_variant)
	if _current_piece:
		add_child(_current_piece)
		_current_piece.position = Vector3.ZERO
		
		_snap_visualizer = SnapPointVisualizer.new()
		_current_piece.add_child(_snap_visualizer)
		_snap_visualizer.set_visible_snap_points(_show_snap_points)


func _update_ui() -> void:
	if _piece_ids.is_empty():
		piece_name_label.text = "Piece: None"
		tier_label.text = "Tier: N/A"
		category_label.text = "Category: N/A"
		costs_label.text = "Costs: N/A"
		return
	
	var piece_id := _piece_ids[_current_piece_index]
	var piece_data: BuildPieceData = _database.get_piece_data(piece_id)
	
	if not piece_data:
		piece_name_label.text = "Piece: %s (no data)" % piece_id
		return
	
	piece_name_label.text = "Piece: %s" % piece_data.display_name
	tier_label.text = "Tier: %d" % piece_data.tier
	
	var category_names := ["WALL", "FLOOR", "ROOF", "DOOR", "FOUNDATION", "STAIRS"]
	var cat_index := piece_data.category as int
	if cat_index >= 0 and cat_index < category_names.size():
		category_label.text = "Category: %s" % category_names[cat_index]
	else:
		category_label.text = "Category: UNKNOWN"
	
	var costs_text := "Costs: "
	var cost_parts: Array[String] = []
	for resource_type in piece_data.resource_costs:
		var amount: int = piece_data.resource_costs[resource_type]
		cost_parts.append("%s x%d" % [resource_type, amount])
	
	if cost_parts.is_empty():
		costs_text += "None"
	else:
		costs_text += ", ".join(cost_parts)
	
	costs_label.text = costs_text
