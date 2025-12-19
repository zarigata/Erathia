@tool
extends EditorScript

const ICON_SIZE: int = 128
const OUTPUT_PATH: String = "res://_assets/icons/building/"


func _run() -> void:
	print("=== Generating Building Piece Icons ===")
	
	var dir := DirAccess.open("res://")
	if not dir:
		push_error("Failed to open res:// directory")
		return
	
	# Ensure output directory exists
	if not dir.dir_exists(OUTPUT_PATH):
		dir.make_dir_recursive(OUTPUT_PATH)
	
	# Get piece database
	var database: Node = load("res://_building/pieces/piece_database.gd").new()
	database._initialize_database()
	
	var piece_ids: Array = database.get_all_piece_ids()
	print("Found %d pieces to generate icons for" % piece_ids.size())
	
	for piece_id in piece_ids:
		_generate_icon_for_piece(database, piece_id)
	
	print("=== Icon Generation Complete ===")


func _generate_icon_for_piece(database: Node, piece_id: String) -> void:
	var piece_data: BuildPieceData = database.get_piece_data(piece_id)
	if not piece_data:
		push_warning("Could not find piece data for: %s" % piece_id)
		return
	
	# Create a SubViewport for rendering
	var viewport := SubViewport.new()
	viewport.size = Vector2i(ICON_SIZE, ICON_SIZE)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	# Create camera
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	camera.position = Vector3(3, 3, 3)
	camera.look_at(Vector3.ZERO)
	viewport.add_child(camera)
	
	# Create lighting
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.light_energy = 1.2
	viewport.add_child(light)
	
	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.45)
	env.ambient_light_energy = 0.5
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	ambient.environment = env
	viewport.add_child(ambient)
	
	# Create piece mesh
	var piece := PieceFactory.create_piece(piece_id, 0)
	if piece:
		viewport.add_child(piece)
	else:
		push_warning("Could not create piece: %s" % piece_id)
		viewport.queue_free()
		return
	
	# Add viewport to scene tree temporarily
	EditorInterface.get_editor_main_screen().add_child(viewport)
	
	# Wait for render
	await EditorInterface.get_editor_main_screen().get_tree().process_frame
	await EditorInterface.get_editor_main_screen().get_tree().process_frame
	
	# Capture image
	var image := viewport.get_texture().get_image()
	
	# Save to file
	var output_file := OUTPUT_PATH + piece_id + ".png"
	var error := image.save_png(output_file)
	
	if error == OK:
		print("Generated icon: %s" % output_file)
	else:
		push_error("Failed to save icon: %s (error %d)" % [output_file, error])
	
	# Cleanup
	viewport.queue_free()
