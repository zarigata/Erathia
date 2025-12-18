@tool
extends EditorScript
## Run this script in the Godot editor to generate placeholder resource icons
## Editor -> Run Script (or Ctrl+Shift+X)

func _run() -> void:
	var icons: Dictionary = {
		"stone": Color(0.5, 0.5, 0.5),      # Gray
		"dirt": Color(0.4, 0.3, 0.2),       # Brown
		"iron_ore": Color(0.6, 0.4, 0.3),   # Rusty orange
		"wood": Color(0.6, 0.45, 0.3),      # Light brown
		"rare_crystal": Color(0.6, 0.2, 0.8) # Purple
	}
	
	var base_path := "res://_assets/icons/resources/"
	
	for resource_name in icons.keys():
		var color: Color = icons[resource_name]
		var img := _create_icon(color)
		var path := base_path + resource_name + ".png"
		img.save_png(path)
		print("Generated: ", path)
	
	print("All icons generated!")


func _create_icon(base_color: Color) -> Image:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	
	# Fill with base color
	img.fill(base_color)
	
	# Add border (darker)
	var border_color := base_color.darkened(0.3)
	for x in range(size):
		img.set_pixel(x, 0, border_color)
		img.set_pixel(x, size - 1, border_color)
	for y in range(size):
		img.set_pixel(0, y, border_color)
		img.set_pixel(size - 1, y, border_color)
	
	# Add highlight (top-left corner, lighter)
	var highlight_color := base_color.lightened(0.2)
	for x in range(1, size - 1):
		img.set_pixel(x, 1, highlight_color)
	for y in range(1, size - 1):
		img.set_pixel(1, y, highlight_color)
	
	# Add shadow (bottom-right corner, darker)
	var shadow_color := base_color.darkened(0.2)
	for x in range(1, size - 1):
		img.set_pixel(x, size - 2, shadow_color)
	for y in range(1, size - 1):
		img.set_pixel(size - 2, y, shadow_color)
	
	return img
