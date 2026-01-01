extends Node

## GDExtension Verification Script
## Run this scene to verify that the Erathia Terrain Native extension loads correctly

func _ready():
	print("\n" + "=".repeat(60))
	print("GDEXTENSION VERIFICATION TEST")
	print("=".repeat(60) + "\n")
	
	verify_extension_loaded()
	verify_native_terrain_test()
	verify_native_terrain_generator()
	verify_native_vegetation_dispatcher()
	
	print("\n" + "=".repeat(60))
	print("VERIFICATION COMPLETE")
	print("=".repeat(60) + "\n")

func verify_extension_loaded():
	print("--- Extension Loading Check ---")
	
	var classes_to_check = [
		"NativeTerrainTest",
		"NativeTerrainGenerator", 
		"NativeVegetationDispatcher"
	]
	
	var all_loaded = true
	for class_name in classes_to_check:
		if ClassDB.class_exists(class_name):
			print("✓ %s class registered" % class_name)
		else:
			print("✗ %s class NOT found" % class_name)
			all_loaded = false
	
	if all_loaded:
		print("✓ All extension classes loaded successfully\n")
	else:
		push_error("✗ Some extension classes failed to load\n")

func verify_native_terrain_test():
	print("--- NativeTerrainTest Verification ---")
	
	if not ClassDB.class_exists("NativeTerrainTest"):
		push_error("✗ NativeTerrainTest class not available")
		return
	
	var test_instance = NativeTerrainTest.new()
	
	if not test_instance:
		push_error("✗ Failed to instantiate NativeTerrainTest")
		return
	
	print("✓ NativeTerrainTest instantiated")
	
	# Test property access
	test_instance.test_value = 100
	var value = test_instance.get_test_value()
	if value == 100:
		print("✓ Property access works (value: %d)" % value)
	else:
		push_warning("✗ Property access issue (expected 100, got %d)" % value)
	
	# Test GPU availability
	var gpu_available = test_instance.check_gpu_available()
	print("  GPU Available: %s" % str(gpu_available))
	
	if gpu_available:
		var gpu_name = test_instance.get_gpu_device_name()
		print("  GPU Device: %s" % gpu_name)
	
	test_instance.free()
	print("✓ NativeTerrainTest verification complete\n")

func verify_native_terrain_generator():
	print("--- NativeTerrainGenerator Verification ---")
	
	if not ClassDB.class_exists("NativeTerrainGenerator"):
		push_error("✗ NativeTerrainGenerator class not available")
		return
	
	var generator = NativeTerrainGenerator.new()
	
	if not generator:
		push_error("✗ Failed to instantiate NativeTerrainGenerator")
		return
	
	print("✓ NativeTerrainGenerator instantiated")
	
	# Check GPU initialization
	var gpu_available = generator.is_gpu_available()
	print("  GPU Available: %s" % str(gpu_available))
	
	if gpu_available:
		var status = generator.get_gpu_status_message()
		print("  GPU Status: %s" % status)
	
	generator.free()
	print("✓ NativeTerrainGenerator verification complete\n")

func verify_native_vegetation_dispatcher():
	print("--- NativeVegetationDispatcher Verification ---")
	
	if not ClassDB.class_exists("NativeVegetationDispatcher"):
		push_error("✗ NativeVegetationDispatcher class not available")
		return
	
	var dispatcher = NativeVegetationDispatcher.new()
	
	if not dispatcher:
		push_error("✗ Failed to instantiate NativeVegetationDispatcher")
		return
	
	print("✓ NativeVegetationDispatcher instantiated")
	
	# Test GPU initialization
	var gpu_init = dispatcher.initialize_gpu()
	print("  GPU Initialization: %s" % ("Success" if gpu_init else "Failed"))
	
	# Test cache configuration
	var default_max = dispatcher.get_max_cache_entries()
	print("  Default cache entries: %d" % default_max)
	
	dispatcher.set_max_cache_entries(100)
	var new_max = dispatcher.get_max_cache_entries()
	if new_max == 100:
		print("✓ Cache configuration works")
	else:
		push_warning("✗ Cache configuration issue")
	
	# Test telemetry
	var total_calls = dispatcher.get_total_placement_calls()
	print("  Total placement calls: %d" % total_calls)
	
	dispatcher.free()
	print("✓ NativeVegetationDispatcher verification complete\n")
