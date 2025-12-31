extends Node

## VegetationCacheManager
## ----------------------
## Utility singleton for managing vegetation prebake caches.
## Provides operations to clear, list, and size caches stored under user://veg_cache/.

const CACHE_ROOT: String = "user://veg_cache"


func clear_cache(world_seed: int) -> void:
	var dir_path := "%s/%d" % [CACHE_ROOT, world_seed]
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	_recursive_remove(dir_path)


func clear_all_caches() -> void:
	if DirAccess.dir_exists_absolute(CACHE_ROOT):
		_recursive_remove(CACHE_ROOT)


func get_cache_size(world_seed: int) -> int:
	var dir_path := "%s/%d" % [CACHE_ROOT, world_seed]
	if not DirAccess.dir_exists_absolute(dir_path):
		return 0
	var total: int = 0
	var stack: Array[String] = []
	stack.append(dir_path)
	while not stack.is_empty():
		var current: String = stack.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name == "." or name == "..":
				name = dir.get_next()
				continue
			var full := "%s/%s" % [current, name]
			if dir.current_is_dir():
				stack.append(full)
			else:
				var fa := FileAccess.open(full, FileAccess.READ)
				if fa:
					total += fa.get_length()
			name = dir.get_next()
		dir.list_dir_end()
	return total


func list_cached_seeds() -> Array[int]:
	var seeds: Array[int] = []
	if not DirAccess.dir_exists_absolute(CACHE_ROOT):
		return seeds
	var dir := DirAccess.open(CACHE_ROOT)
	if dir == null:
		return seeds
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		if dir.current_is_dir():
			var seed := int(name.to_int())
			seeds.append(seed)
		name = dir.get_next()
	dir.list_dir_end()
	return seeds


func _recursive_remove(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var full_path := "%s/%s" % [path, file_name]
		if dir.current_is_dir():
			_recursive_remove(full_path)
		else:
			DirAccess.remove_absolute(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
