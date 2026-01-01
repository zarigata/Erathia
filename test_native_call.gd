extends Node

func _ready():
	print("=== Native Extension Test ===")
	
	# Test 1: Access node from scene tree
	var native_test = $NativeTerrainTest
	if native_test:
		print("✓ NativeTerrainTest node found in scene tree")
		print("  Initial test_value: ", native_test.test_value)
		
		# Test 2: Modify property
		native_test.test_value = 100
		print("  Modified test_value: ", native_test.get_test_value())
		
		# Test 3: GPU availability check
		var gpu_available = native_test.check_gpu_available()
		print("  GPU Available: ", gpu_available)
		
		# Test 4: Get GPU device name
		var gpu_name = native_test.get_gpu_device_name()
		print("  GPU Device: ", gpu_name)
	else:
		print("✗ ERROR: NativeTerrainTest node not found!")
	
	# Test 5: Create instance dynamically
	print("\n=== Dynamic Instance Test ===")
	var dynamic_test = NativeTerrainTest.new()
	if dynamic_test:
		print("✓ NativeTerrainTest instance created dynamically")
		print("  Initial value: ", dynamic_test.test_value)
		
		dynamic_test.test_value = 200
		print("  Modified value: ", dynamic_test.get_test_value())
		
		print("  GPU Check: ", dynamic_test.check_gpu_available())
		print("  GPU Device: ", dynamic_test.get_gpu_device_name())
		
		dynamic_test.free()
		print("✓ Dynamic instance freed successfully")
	else:
		print("✗ ERROR: Could not create NativeTerrainTest instance!")
	
	print("\n=== All Tests Complete ===")
