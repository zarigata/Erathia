#include "test_native_class.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

NativeTerrainTest::NativeTerrainTest() {
    test_value = 42;
    rendering_device = nullptr;
}

NativeTerrainTest::~NativeTerrainTest() {
}

void NativeTerrainTest::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_test_value", "value"), &NativeTerrainTest::set_test_value);
    ClassDB::bind_method(D_METHOD("get_test_value"), &NativeTerrainTest::get_test_value);
    ClassDB::bind_method(D_METHOD("check_gpu_available"), &NativeTerrainTest::check_gpu_available);
    ClassDB::bind_method(D_METHOD("get_gpu_device_name"), &NativeTerrainTest::get_gpu_device_name);
    
    ADD_PROPERTY(PropertyInfo(Variant::INT, "test_value"), "set_test_value", "get_test_value");
}

void NativeTerrainTest::set_test_value(int p_value) {
    test_value = p_value;
}

int NativeTerrainTest::get_test_value() const {
    return test_value;
}

bool NativeTerrainTest::check_gpu_available() {
    rendering_device = RenderingServer::get_singleton()->get_rendering_device();
    return rendering_device != nullptr;
}

String NativeTerrainTest::get_gpu_device_name() {
    if (!rendering_device) {
        rendering_device = RenderingServer::get_singleton()->get_rendering_device();
    }
    
    if (rendering_device) {
        return rendering_device->get_device_name();
    }
    
    return "No GPU device available";
}

void NativeTerrainTest::_ready() {
    UtilityFunctions::print("[NativeTerrainTest] C++ GDExtension loaded successfully!");
    UtilityFunctions::print("[NativeTerrainTest] GPU Available: ", check_gpu_available());
    UtilityFunctions::print("[NativeTerrainTest] GPU Device: ", get_gpu_device_name());
}
