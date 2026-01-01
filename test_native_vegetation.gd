extends Node

var native_dispatcher: NativeVegetationDispatcher
var test_results: Dictionary = {}

func _ready():
	print("=== Native Vegetation Dispatcher Test ===")
	
	if not ClassDB.class_exists("NativeVegetationDispatcher"):
		push_error("NativeVegetationDispatcher class not found! Extension may not be loaded.")
		return
	
	native_dispatcher = NativeVegetationDispatcher.new()
	
	if not native_dispatcher:
		push_error("Failed to instantiate NativeVegetationDispatcher")
		return
	
	print("✓ NativeVegetationDispatcher instantiated successfully")
	
	test_gpu_initialization()
	test_cache_configuration()
	test_placement_generation()
	test_cache_behavior()
	test_telemetry()
	
	print_test_summary()

func test_gpu_initialization():
	print("\n--- Test: GPU Initialization ---")
	
	var success = native_dispatcher.initialize_gpu()
	test_results["gpu_init"] = success
	
	if success:
		print("✓ GPU initialized successfully")
	else:
		push_warning("✗ GPU initialization failed")

func test_cache_configuration():
	print("\n--- Test: Cache Configuration ---")
	
	var default_max = native_dispatcher.get_max_cache_entries()
	print("Default max cache entries: %d" % default_max)
	
	native_dispatcher.set_max_cache_entries(100)
	var new_max = native_dispatcher.get_max_cache_entries()
	
	test_results["cache_config"] = (new_max == 100)
	
	if new_max == 100:
		print("✓ Cache configuration works correctly")
	else:
		push_warning("✗ Cache configuration failed")

func test_placement_generation():
	print("\n--- Test: Placement Generation ---")
	
	var chunk_origin = Vector3i(0, 0, 0)
	var veg_type = 0
	var density = 0.5
	var grid_spacing = 4.0
	var noise_frequency = 0.1
	var slope_max = 45.0
	var height_range = {"min": 0.0, "max": 100.0}
	var world_seed = 12345
	
	var biome_map_texture = RID()
	
	print("Note: This test requires valid terrain SDF and biome map textures")
	print("Expected to return empty array without proper setup")
	
	var placements = native_dispatcher.generate_placements(
		chunk_origin,
		veg_type,
		density,
		grid_spacing,
		noise_frequency,
		slope_max,
		height_range,
		world_seed,
		biome_map_texture
	)
	
	print("Placements returned: %d" % placements.size())
	
	if placements.size() > 0:
		print("✓ Placement generation returned data")
		print("Sample placement: %s" % str(placements[0]))
		test_results["placement_gen"] = true
	else:
		print("⚠ Placement generation returned empty (expected without terrain data)")
		test_results["placement_gen"] = false

func test_cache_behavior():
	print("\n--- Test: Cache Behavior ---")
	
	var chunk = Vector3i(10, 0, 10)
	var type = 1
	
	var is_ready_before = native_dispatcher.is_chunk_ready(chunk, type)
	print("Chunk ready before generation: %s" % is_ready_before)
	
	var cache_size_before = native_dispatcher.get_cache_size()
	print("Cache size before: %d" % cache_size_before)
	
	native_dispatcher.clear_cache()
	var cache_size_after_clear = native_dispatcher.get_cache_size()
	print("Cache size after clear: %d" % cache_size_after_clear)
	
	test_results["cache_clear"] = (cache_size_after_clear == 0)
	
	if cache_size_after_clear == 0:
		print("✓ Cache clear works correctly")
	else:
		push_warning("✗ Cache clear failed")

func test_telemetry():
	print("\n--- Test: Telemetry ---")
	
	var total_calls = native_dispatcher.get_total_placement_calls()
	var avg_time = native_dispatcher.get_average_placement_time_ms()
	var last_time = native_dispatcher.get_last_placement_time_ms()
	var timing_per_type = native_dispatcher.get_timing_per_type_ms()
	
	print("Total placement calls: %d" % total_calls)
	print("Average time: %.3f ms" % avg_time)
	print("Last time: %.3f ms" % last_time)
	print("Timing per type: %s" % str(timing_per_type))
	
	native_dispatcher.reset_timing_stats()
	var calls_after_reset = native_dispatcher.get_total_placement_calls()
	
	test_results["telemetry_reset"] = (calls_after_reset == 0)
	
	if calls_after_reset == 0:
		print("✓ Telemetry reset works correctly")
	else:
		push_warning("✗ Telemetry reset failed")

func print_test_summary():
	print("\n=== Test Summary ===")
	var passed = 0
	var total = test_results.size()
	
	for test_name in test_results:
		var result = test_results[test_name]
		var status = "✓ PASS" if result else "✗ FAIL"
		print("%s: %s" % [test_name, status])
		if result:
			passed += 1
	
	print("\nResults: %d/%d tests passed" % [passed, total])
	
	if passed == total:
		print("🎉 All tests passed!")
	else:
		print("⚠ Some tests failed or require proper terrain setup")
