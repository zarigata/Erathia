#ifndef NATIVE_VEGETATION_DISPATCHER_H
#define NATIVE_VEGETATION_DISPATCHER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/classes/mutex.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <godot_cpp/variant/rid.hpp>

#include <unordered_map>
#include <list>
#include <atomic>
#include <memory>

namespace godot {

struct PlacementData {
    Vector3 position;
    float _padding1;
    Vector3 normal;
    float _padding2;
    uint32_t variant_index;
    uint32_t instance_seed;
    float scale;
    float rotation_y;
};

struct Vector3iHash {
    std::size_t operator()(const Vector3i& v) const {
        std::size_t h1 = std::hash<int>{}(v.x);
        std::size_t h2 = std::hash<int>{}(v.y);
        std::size_t h3 = std::hash<int>{}(v.z);
        return h1 ^ (h2 << 1) ^ (h3 << 2);
    }
};

struct ChunkTypePair {
    Vector3i chunk;
    int type;
    
    bool operator==(const ChunkTypePair& other) const {
        return chunk == other.chunk && type == other.type;
    }
};

struct ChunkTypePairHash {
    std::size_t operator()(const ChunkTypePair& p) const {
        Vector3iHash vh;
        return vh(p.chunk) ^ (std::hash<int>{}(p.type) << 1);
    }
};

class NativeVegetationDispatcher : public RefCounted {
    GDCLASS(NativeVegetationDispatcher, RefCounted)

private:
    RenderingDevice* rd;
    RID shader;
    RID pipeline;
    RID transform_shader;
    RID transform_pipeline;
    RID cached_sampler_linear;
    
    std::unordered_map<Vector3i, std::unordered_map<int, Array>, Vector3iHash> placement_cache;
    std::unordered_map<Vector3i, std::unordered_map<int, RID>, Vector3iHash> buffer_cache;
    std::unordered_map<Vector3i, std::unordered_map<int, RID>, Vector3iHash> transform_buffer_cache;
    
    std::list<ChunkTypePair> lru_list;
    std::unordered_map<ChunkTypePair, std::list<ChunkTypePair>::iterator, ChunkTypePairHash> lru_map;
    
    Ref<Mutex> cache_mutex;
    
    std::atomic<uint64_t> total_placement_time_us;
    std::atomic<uint64_t> last_placement_time_us;
    std::atomic<int> placement_call_count;
    Dictionary timing_per_type;
    
    int max_cache_entries;
    bool gpu_initialized;
    
    Object* terrain_dispatcher;
    
    void evict_lru_entry();
    void update_lru_access(const Vector3i& chunk, int type);
    Array decode_placements(const PackedByteArray& buffer_data);

protected:
    static void _bind_methods();

public:
    static constexpr int MAX_PLACEMENTS = 4096;
    static constexpr int CHUNK_SIZE = 32;
    static constexpr int DEFAULT_MAX_CACHE_ENTRIES = 500;
    
    NativeVegetationDispatcher();
    ~NativeVegetationDispatcher();
    
    bool initialize_gpu();
    void cleanup_gpu();
    
    Array generate_placements(
        Vector3i chunk_origin,
        int veg_type,
        float density,
        float grid_spacing,
        float noise_frequency,
        float slope_max,
        Dictionary height_range,
        int world_seed,
        RID biome_map_texture,
        bool cpu_fallback = true
    );
    
    bool is_chunk_ready(Vector3i chunk_origin, int veg_type);
    bool is_gpu_ready(Vector3i chunk_origin, int veg_type);
    void clear_cache();
    
    RID get_placement_buffer_rid(Vector3i chunk_origin, int veg_type);
    int get_placement_count(Vector3i chunk_origin, int veg_type);
    RID get_transform_buffer_rid(Vector3i chunk_origin, int veg_type);
    
    void set_terrain_dispatcher(Object* dispatcher);
    Object* get_terrain_dispatcher() const;
    
    void set_max_cache_entries(int count);
    int get_max_cache_entries() const;
    int get_cache_size() const;
    
    float get_last_placement_time_ms() const;
    float get_average_placement_time_ms() const;
    Dictionary get_timing_per_type_ms() const;
    int get_total_placement_calls() const;
    void reset_timing_stats();
};

}

#endif // NATIVE_VEGETATION_DISPATCHER_H
