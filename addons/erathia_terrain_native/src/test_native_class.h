#ifndef NATIVE_TERRAIN_TEST_H
#define NATIVE_TERRAIN_TEST_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/rendering_device.hpp>

namespace godot {

class NativeTerrainTest : public Node {
    GDCLASS(NativeTerrainTest, Node)

private:
    int test_value;
    RenderingDevice* rendering_device;

protected:
    static void _bind_methods();

public:
    NativeTerrainTest();
    ~NativeTerrainTest();

    void set_test_value(int p_value);
    int get_test_value() const;
    
    bool check_gpu_available();
    String get_gpu_device_name();
    
    void _ready() override;
};

} // namespace godot

#endif // NATIVE_TERRAIN_TEST_H
