#include "native_vegetation_dispatcher.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/rd_shader_source.hpp>
#include <godot_cpp/classes/rd_shader_spirv.hpp>
#include <godot_cpp/classes/rd_uniform.hpp>
#include <godot_cpp/classes/rd_sampler_state.hpp>
#include <godot_cpp/classes/rd_texture_format.hpp>

#include <cmath>
#include <cstring>

using namespace godot;

NativeVegetationDispatcher::NativeVegetationDispatcher() {
    rd = nullptr;
    gpu_initialized = false;
    max_cache_entries = DEFAULT_MAX_CACHE_ENTRIES;
    total_placement_time_us = 0;
    last_placement_time_us = 0;
    placement_call_count = 0;
    terrain_dispatcher = nullptr;
    cached_sampler_linear = RID();
    transform_shader = RID();
    transform_pipeline = RID();
    
    cache_mutex.instantiate();
    
    RenderingServer* rs = RenderingServer::get_singleton();
    if (rs) {
        rd = rs->create_local_rendering_device();
        if (!rd) {
            UtilityFunctions::push_warning("NativeVegetationDispatcher: Failed to create local RenderingDevice");
        }
    }
}

NativeVegetationDispatcher::~NativeVegetationDispatcher() {
    cleanup_gpu();
    
    if (rd) {
        memdelete(rd);
        rd = nullptr;
    }
}

bool NativeVegetationDispatcher::initialize_gpu() {
    if (gpu_initialized) {
        return true;
    }
    
    if (!rd) {
        UtilityFunctions::push_warning("NativeVegetationDispatcher: RenderingDevice not available");
        return false;
    }
    
    String shader_path = "res://_engine/terrain/vegetation_placement.compute";
    Ref<FileAccess> file = FileAccess::open(shader_path, FileAccess::READ);
    
    if (!file.is_valid()) {
        UtilityFunctions::push_warning("NativeVegetationDispatcher: Failed to load shader file: " + shader_path);
        return false;
    }
    
    String shader_source = file->get_as_text();
    file->close();
    
    Ref<RDShaderSource> shader_src;
    shader_src.instantiate();
    shader_src->set_stage_source(RenderingDevice::SHADER_STAGE_COMPUTE, shader_source);
    shader_src->set_language(RenderingDevice::SHADER_LANGUAGE_GLSL);
    
    Ref<RDShaderSPIRV> spirv = rd->shader_compile_spirv_from_source(shader_src);
    
    if (!spirv.is_valid() || spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE) != "") {
        String error = spirv.is_valid() ? spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE) : "Invalid SPIRV";
        UtilityFunctions::push_warning("NativeVegetationDispatcher: Shader compilation failed: " + error);
        return false;
    }
    
    shader = rd->shader_create_from_spirv(spirv);
    
    if (!shader.is_valid()) {
        UtilityFunctions::push_warning("NativeVegetationDispatcher: Failed to create shader");
        return false;
    }
    
    pipeline = rd->compute_pipeline_create(shader);
    
    if (!pipeline.is_valid()) {
        UtilityFunctions::push_warning("NativeVegetationDispatcher: Failed to create compute pipeline");
        rd->free_rid(shader);
        shader = RID();
        return false;
    }
    
    // Create cached sampler for reuse
    Ref<RDSamplerState> sampler_state;
    sampler_state.instantiate();
    sampler_state->set_min_filter(RenderingDevice::SAMPLER_FILTER_LINEAR);
    sampler_state->set_mag_filter(RenderingDevice::SAMPLER_FILTER_LINEAR);
    cached_sampler_linear = rd->sampler_create(sampler_state);
    
    // Load and compile transform shader
    String transform_shader_path = "res://_engine/terrain/transform_placement.compute";
    Ref<FileAccess> transform_file = FileAccess::open(transform_shader_path, FileAccess::READ);
    
    if (transform_file.is_valid()) {
        String transform_shader_source = transform_file->get_as_text();
        transform_file->close();
        
        Ref<RDShaderSource> transform_shader_src;
        transform_shader_src.instantiate();
        transform_shader_src->set_stage_source(RenderingDevice::SHADER_STAGE_COMPUTE, transform_shader_source);
        transform_shader_src->set_language(RenderingDevice::SHADER_LANGUAGE_GLSL);
        
        Ref<RDShaderSPIRV> transform_spirv = rd->shader_compile_spirv_from_source(transform_shader_src);
        
        if (transform_spirv.is_valid() && transform_spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE) == "") {
            transform_shader = rd->shader_create_from_spirv(transform_spirv);
            
            if (transform_shader.is_valid()) {
                transform_pipeline = rd->compute_pipeline_create(transform_shader);
                
                if (transform_pipeline.is_valid()) {
                    UtilityFunctions::print("NativeVegetationDispatcher: Transform shader initialized successfully");
                } else {
                    UtilityFunctions::push_warning("NativeVegetationDispatcher: Failed to create transform pipeline");
                }
            } else {
                UtilityFunctions::push_warning("NativeVegetationDispatcher: Failed to create transform shader");
            }
        } else {
            String error = transform_spirv.is_valid() ? transform_spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE) : "Invalid SPIRV";
            UtilityFunctions::push_warning("NativeVegetationDispatcher: Transform shader compilation failed: " + error);
        }
    } else {
        UtilityFunctions::push_warning("NativeVegetationDispatcher: Transform shader file not found: " + transform_shader_path);
    }
    
    gpu_initialized = true;
    UtilityFunctions::print("NativeVegetationDispatcher: GPU initialized successfully");
    return true;
}

void NativeVegetationDispatcher::cleanup_gpu() {
    if (cached_sampler_linear.is_valid()) {
        rd->free_rid(cached_sampler_linear);
        cached_sampler_linear = RID();
    }
    
    if (transform_pipeline.is_valid()) {
        rd->free_rid(transform_pipeline);
        transform_pipeline = RID();
    }
    
    if (transform_shader.is_valid()) {
        rd->free_rid(transform_shader);
        transform_shader = RID();
    }
    
    if (pipeline.is_valid()) {
        rd->free_rid(pipeline);
        pipeline = RID();
    }
    
    if (shader.is_valid()) {
        rd->free_rid(shader);
        shader = RID();
    }
    
    cache_mutex->lock();
    for (auto& chunk_pair : buffer_cache) {
        for (auto& type_pair : chunk_pair.second) {
            if (type_pair.second.is_valid()) {
                rd->free_rid(type_pair.second);
            }
        }
    }
    for (auto& chunk_pair : transform_buffer_cache) {
        for (auto& type_pair : chunk_pair.second) {
            if (type_pair.second.is_valid()) {
                rd->free_rid(type_pair.second);
            }
        }
    }
    buffer_cache.clear();
    transform_buffer_cache.clear();
    placement_cache.clear();
    lru_list.clear();
    lru_map.clear();
    cache_mutex->unlock();
    
    gpu_initialized = false;
}

void NativeVegetationDispatcher::update_lru_access(const Vector3i& chunk, int type) {
    ChunkTypePair key{chunk, type};
    
    auto it = lru_map.find(key);
    if (it != lru_map.end()) {
        lru_list.erase(it->second);
    }
    
    lru_list.push_front(key);
    lru_map[key] = lru_list.begin();
}

void NativeVegetationDispatcher::evict_lru_entry() {
    if (lru_list.empty()) {
        return;
    }
    
    ChunkTypePair oldest = lru_list.back();
    lru_list.pop_back();
    lru_map.erase(oldest);
    
    placement_cache[oldest.chunk].erase(oldest.type);
    if (placement_cache[oldest.chunk].empty()) {
        placement_cache.erase(oldest.chunk);
    }
    
    auto buffer_it = buffer_cache.find(oldest.chunk);
    if (buffer_it != buffer_cache.end()) {
        auto type_it = buffer_it->second.find(oldest.type);
        if (type_it != buffer_it->second.end()) {
            if (type_it->second.is_valid()) {
                rd->free_rid(type_it->second);
            }
            buffer_it->second.erase(type_it);
            if (buffer_it->second.empty()) {
                buffer_cache.erase(buffer_it);
            }
        }
    }
    
    auto transform_it = transform_buffer_cache.find(oldest.chunk);
    if (transform_it != transform_buffer_cache.end()) {
        auto type_it = transform_it->second.find(oldest.type);
        if (type_it != transform_it->second.end()) {
            if (type_it->second.is_valid()) {
                rd->free_rid(type_it->second);
            }
            transform_it->second.erase(type_it);
            if (transform_it->second.empty()) {
                transform_buffer_cache.erase(transform_it);
            }
        }
    }
}

Array NativeVegetationDispatcher::decode_placements(const PackedByteArray& buffer_data) {
    Array result;
    
    if (buffer_data.size() < 4) {
        return result;
    }
    
    const uint8_t* data = buffer_data.ptr();
    uint32_t placement_count;
    memcpy(&placement_count, data, sizeof(uint32_t));
    
    if (placement_count > MAX_PLACEMENTS) {
        placement_count = MAX_PLACEMENTS;
    }
    
    size_t offset = 4;
    const size_t stride = sizeof(PlacementData);
    
    for (uint32_t i = 0; i < placement_count; i++) {
        if (offset + stride > buffer_data.size()) {
            break;
        }
        
        PlacementData pd;
        memcpy(&pd, data + offset, stride);
        offset += stride;
        
        Dictionary placement;
        placement["position"] = pd.position;
        placement["normal"] = pd.normal;
        placement["variant_index"] = pd.variant_index;
        placement["instance_seed"] = pd.instance_seed;
        placement["scale"] = pd.scale;
        placement["rotation_y"] = pd.rotation_y;
        
        result.push_back(placement);
    }
    
    return result;
}

Array NativeVegetationDispatcher::generate_placements(
    Vector3i chunk_origin,
    int veg_type,
    float density,
    float grid_spacing,
    float noise_frequency,
    float slope_max,
    Dictionary height_range,
    int world_seed,
    RID biome_map_texture,
    bool cpu_fallback
) {
    if (!gpu_initialized) {
        if (!initialize_gpu()) {
            return Array();
        }
    }
    
    cache_mutex->lock();
    auto chunk_it = placement_cache.find(chunk_origin);
    if (chunk_it != placement_cache.end()) {
        auto type_it = chunk_it->second.find(veg_type);
        if (type_it != chunk_it->second.end()) {
            update_lru_access(chunk_origin, veg_type);
            Array cached = type_it->second;
            cache_mutex->unlock();
            return cached;
        }
    }
    cache_mutex->unlock();
    
    if (!biome_map_texture.is_valid()) {
        UtilityFunctions::push_warning("NativeVegetationDispatcher: Invalid biome map texture");
        return Array();
    }
    
    RID terrain_sdf_texture;
    if (terrain_dispatcher) {
        terrain_sdf_texture = terrain_dispatcher->call("get_sdf_texture_for_chunk", chunk_origin);
    }
    
    if (!terrain_sdf_texture.is_valid()) {
        return Array();
    }
    
    int grid_steps = static_cast<int>(std::ceil(CHUNK_SIZE / grid_spacing));
    int workgroups = static_cast<int>(std::ceil(grid_steps / 8.0));
    
    int buffer_size = 4 + (MAX_PLACEMENTS * sizeof(PlacementData));
    PackedByteArray initial_data;
    initial_data.resize(buffer_size);
    memset(initial_data.ptrw(), 0, buffer_size);
    
    RID storage_buffer = rd->storage_buffer_create(buffer_size, initial_data);
    
    Array uniforms;
    
    {
        Ref<RDUniform> uniform;
        uniform.instantiate();
        uniform->set_uniform_type(RenderingDevice::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE);
        uniform->set_binding(0);
        uniform->add_id(cached_sampler_linear);
        uniform->add_id(terrain_sdf_texture);
        uniforms.push_back(uniform);
    }
    
    {
        Ref<RDUniform> uniform;
        uniform.instantiate();
        uniform->set_uniform_type(RenderingDevice::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE);
        uniform->set_binding(1);
        uniform->add_id(cached_sampler_linear);
        uniform->add_id(biome_map_texture);
        uniforms.push_back(uniform);
    }
    
    {
        Ref<RDUniform> uniform;
        uniform.instantiate();
        uniform->set_uniform_type(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER);
        uniform->set_binding(2);
        uniform->add_id(storage_buffer);
        uniforms.push_back(uniform);
    }
    
    RID uniform_set = rd->uniform_set_create(uniforms, shader, 0);
    
    if (!uniform_set.is_valid()) {
        UtilityFunctions::push_warning("NativeVegetationDispatcher: Failed to create uniform set");
        rd->free_rid(storage_buffer);
        return Array();
    }
    
    PackedByteArray push_constants;
    push_constants.resize(56);
    uint8_t* pc_data = push_constants.ptrw();
    size_t pc_offset = 0;
    
    // Convert chunk_origin ints to floats for shader (Comment 1 fix)
    float chunk_x = static_cast<float>(chunk_origin.x);
    float chunk_y = static_cast<float>(chunk_origin.y);
    float chunk_z = static_cast<float>(chunk_origin.z);
    
    memcpy(pc_data + pc_offset, &chunk_x, sizeof(float));
    pc_offset += sizeof(float);
    memcpy(pc_data + pc_offset, &chunk_y, sizeof(float));
    pc_offset += sizeof(float);
    memcpy(pc_data + pc_offset, &chunk_z, sizeof(float));
    pc_offset += sizeof(float);
    memcpy(pc_data + pc_offset, &grid_spacing, sizeof(float));
    pc_offset += sizeof(float);
    
    int chunk_size = CHUNK_SIZE;
    memcpy(pc_data + pc_offset, &chunk_size, sizeof(int));
    pc_offset += sizeof(int);
    memcpy(pc_data + pc_offset, &grid_steps, sizeof(int));
    pc_offset += sizeof(int);
    uint32_t seed_u32 = static_cast<uint32_t>(world_seed);
    memcpy(pc_data + pc_offset, &seed_u32, sizeof(uint32_t));
    pc_offset += sizeof(uint32_t);
    memcpy(pc_data + pc_offset, &veg_type, sizeof(int));
    pc_offset += sizeof(int);
    
    memcpy(pc_data + pc_offset, &density, sizeof(float));
    pc_offset += sizeof(float);
    memcpy(pc_data + pc_offset, &noise_frequency, sizeof(float));
    pc_offset += sizeof(float);
    memcpy(pc_data + pc_offset, &slope_max, sizeof(float));
    pc_offset += sizeof(float);
    
    // Comment 4 fix: Align defaults with GDScript dispatcher
    float height_min = height_range.get("min", -100.0f);
    float height_max = height_range.get("max", 500.0f);
    memcpy(pc_data + pc_offset, &height_min, sizeof(float));
    pc_offset += sizeof(float);
    memcpy(pc_data + pc_offset, &height_max, sizeof(float));
    pc_offset += sizeof(float);
    
    uint64_t start_time = Time::get_singleton()->get_ticks_usec();
    
    int64_t compute_list = rd->compute_list_begin();
    rd->compute_list_bind_compute_pipeline(compute_list, pipeline);
    rd->compute_list_bind_uniform_set(compute_list, uniform_set, 0);
    rd->compute_list_set_push_constant(compute_list, push_constants, push_constants.size());
    rd->compute_list_dispatch(compute_list, workgroups, 1, workgroups);
    rd->compute_list_end();
    
    rd->submit();
    rd->sync();
    
    uint64_t end_time = Time::get_singleton()->get_ticks_usec();
    uint64_t elapsed_us = end_time - start_time;
    
    last_placement_time_us = elapsed_us;
    total_placement_time_us += elapsed_us;
    placement_call_count++;
    
    if (!timing_per_type.has(veg_type)) {
        Dictionary type_stats;
        type_stats["total_ms"] = 0.0;
        type_stats["count"] = 0;
        type_stats["avg_ms"] = 0.0;
        timing_per_type[veg_type] = type_stats;
    }
    
    Dictionary type_stats = timing_per_type[veg_type];
    double total_ms = type_stats["total_ms"];
    int count = type_stats["count"];
    
    total_ms += elapsed_us / 1000.0;
    count++;
    
    type_stats["total_ms"] = total_ms;
    type_stats["count"] = count;
    type_stats["avg_ms"] = total_ms / count;
    timing_per_type[veg_type] = type_stats;
    
    // GPU-only mode optimization: skip CPU readback when cpu_fallback is false
    Array placements;
    
    cache_mutex->lock();
    
    // Always cache the buffer RID for GPU path
    buffer_cache[chunk_origin][veg_type] = storage_buffer;
    
    // Only perform CPU readback if cpu_fallback is true
    if (cpu_fallback) {
        PackedByteArray buffer_data = rd->buffer_get_data(storage_buffer);
        placements = decode_placements(buffer_data);
        placement_cache[chunk_origin][veg_type] = placements;
    } else {
        // GPU-only mode: cache empty array to signal GPU mode
        placement_cache[chunk_origin][veg_type] = Array();
    }
    
    update_lru_access(chunk_origin, veg_type);
    
    int cache_size = 0;
    for (const auto& chunk_pair : placement_cache) {
        cache_size += chunk_pair.second.size();
    }
    
    while (cache_size > max_cache_entries) {
        evict_lru_entry();
        cache_size--;
    }
    
    cache_mutex->unlock();
    
    rd->free_rid(uniform_set);
    
    return placements;
}

bool NativeVegetationDispatcher::is_chunk_ready(Vector3i chunk_origin, int veg_type) {
    cache_mutex->lock();
    bool ready = false;
    
    auto chunk_it = placement_cache.find(chunk_origin);
    if (chunk_it != placement_cache.end()) {
        ready = chunk_it->second.find(veg_type) != chunk_it->second.end();
    }
    
    cache_mutex->unlock();
    return ready;
}

bool NativeVegetationDispatcher::is_gpu_ready(Vector3i chunk_origin, int veg_type) {
    cache_mutex->lock();
    bool ready = false;
    
    // Check if both placement buffer and transform buffer exist
    auto buffer_it = buffer_cache.find(chunk_origin);
    if (buffer_it != buffer_cache.end()) {
        auto type_it = buffer_it->second.find(veg_type);
        if (type_it != buffer_it->second.end() && type_it->second.is_valid()) {
            auto transform_it = transform_buffer_cache.find(chunk_origin);
            if (transform_it != transform_buffer_cache.end()) {
                auto transform_type_it = transform_it->second.find(veg_type);
                ready = transform_type_it != transform_it->second.end() && transform_type_it->second.is_valid();
            }
        }
    }
    
    cache_mutex->unlock();
    return ready;
}

void NativeVegetationDispatcher::clear_cache() {
    cache_mutex->lock();
    
    for (auto& chunk_pair : buffer_cache) {
        for (auto& type_pair : chunk_pair.second) {
            if (type_pair.second.is_valid()) {
                rd->free_rid(type_pair.second);
            }
        }
    }
    
    for (auto& chunk_pair : transform_buffer_cache) {
        for (auto& type_pair : chunk_pair.second) {
            if (type_pair.second.is_valid()) {
                rd->free_rid(type_pair.second);
            }
        }
    }
    
    placement_cache.clear();
    buffer_cache.clear();
    transform_buffer_cache.clear();
    lru_list.clear();
    lru_map.clear();
    
    cache_mutex->unlock();
}

RID NativeVegetationDispatcher::get_placement_buffer_rid(Vector3i chunk_origin, int veg_type) {
    cache_mutex->lock();
    
    auto chunk_it = buffer_cache.find(chunk_origin);
    if (chunk_it != buffer_cache.end()) {
        auto type_it = chunk_it->second.find(veg_type);
        if (type_it != chunk_it->second.end()) {
            RID buffer = type_it->second;
            cache_mutex->unlock();
            return buffer;
        }
    }
    
    cache_mutex->unlock();
    return RID();
}

int NativeVegetationDispatcher::get_placement_count(Vector3i chunk_origin, int veg_type) {
    RID buffer = get_placement_buffer_rid(chunk_origin, veg_type);
    
    if (!buffer.is_valid()) {
        return 0;
    }
    
    PackedByteArray count_data = rd->buffer_get_data(buffer, 0, 4);
    
    if (count_data.size() < 4) {
        return 0;
    }
    
    uint32_t count;
    memcpy(&count, count_data.ptr(), sizeof(uint32_t));
    
    return static_cast<int>(count);
}

RID NativeVegetationDispatcher::get_transform_buffer_rid(Vector3i chunk_origin, int veg_type) {
    cache_mutex->lock();
    
    // Check if transform buffer already exists
    auto chunk_it = transform_buffer_cache.find(chunk_origin);
    if (chunk_it != transform_buffer_cache.end()) {
        auto type_it = chunk_it->second.find(veg_type);
        if (type_it != chunk_it->second.end()) {
            RID buffer = type_it->second;
            cache_mutex->unlock();
            return buffer;
        }
    }
    
    cache_mutex->unlock();
    
    // Get placement buffer
    RID placement_buffer = get_placement_buffer_rid(chunk_origin, veg_type);
    if (!placement_buffer.is_valid()) {
        return RID();
    }
    
    // Read placement count (minimal readback)
    PackedByteArray count_data = rd->buffer_get_data(placement_buffer, 0, 4);
    if (count_data.size() < 4) {
        return RID();
    }
    
    uint32_t placement_count;
    memcpy(&placement_count, count_data.ptr(), sizeof(uint32_t));
    
    if (placement_count == 0 || placement_count > MAX_PLACEMENTS) {
        return RID();
    }
    
    // Use GPU compute shader for transform generation if available
    if (transform_pipeline.is_valid()) {
        // Create output transform buffer (12 floats per instance)
        size_t transform_buffer_size = placement_count * 12 * sizeof(float);
        PackedByteArray initial_transform_data;
        initial_transform_data.resize(transform_buffer_size);
        memset(initial_transform_data.ptrw(), 0, transform_buffer_size);
        
        RID transform_buffer = rd->storage_buffer_create(transform_buffer_size, initial_transform_data);
        
        if (!transform_buffer.is_valid()) {
            UtilityFunctions::push_warning("NativeVegetationDispatcher: Failed to create transform buffer");
            return RID();
        }
        
        // Create uniform set for transform shader
        Array uniforms;
        
        // Binding 0: Input placement buffer (readonly)
        {
            Ref<RDUniform> uniform;
            uniform.instantiate();
            uniform->set_uniform_type(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER);
            uniform->set_binding(0);
            uniform->add_id(placement_buffer);
            uniforms.push_back(uniform);
        }
        
        // Binding 1: Output transform buffer (writeonly)
        {
            Ref<RDUniform> uniform;
            uniform.instantiate();
            uniform->set_uniform_type(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER);
            uniform->set_binding(1);
            uniform->add_id(transform_buffer);
            uniforms.push_back(uniform);
        }
        
        RID uniform_set = rd->uniform_set_create(uniforms, transform_shader, 0);
        
        if (!uniform_set.is_valid()) {
            UtilityFunctions::push_warning("NativeVegetationDispatcher: Failed to create transform uniform set");
            rd->free_rid(transform_buffer);
            return RID();
        }
        
        // Push constants: instance count
        PackedByteArray push_constants;
        push_constants.resize(16);  // uint + padding
        uint8_t* pc_data = push_constants.ptrw();
        memcpy(pc_data, &placement_count, sizeof(uint32_t));
        
        // Dispatch compute shader
        int workgroups = static_cast<int>(std::ceil(placement_count / 64.0));
        
        int64_t compute_list = rd->compute_list_begin();
        rd->compute_list_bind_compute_pipeline(compute_list, transform_pipeline);
        rd->compute_list_bind_uniform_set(compute_list, uniform_set, 0);
        rd->compute_list_set_push_constant(compute_list, push_constants, push_constants.size());
        rd->compute_list_dispatch(compute_list, workgroups, 1, 1);
        rd->compute_list_end();
        
        rd->submit();
        rd->sync();
        
        rd->free_rid(uniform_set);
        
        // Cache the transform buffer
        cache_mutex->lock();
        transform_buffer_cache[chunk_origin][veg_type] = transform_buffer;
        cache_mutex->unlock();
        
        return transform_buffer;
    }
    
    // CPU fallback path (original implementation)
    size_t placement_data_size = placement_count * sizeof(PlacementData);
    PackedByteArray placement_data = rd->buffer_get_data(placement_buffer, 4, placement_data_size);
    
    if (placement_data.size() < placement_data_size) {
        return RID();
    }
    
    size_t transform_buffer_size = placement_count * 12 * sizeof(float);
    PackedByteArray transform_data;
    transform_data.resize(transform_buffer_size);
    
    const PlacementData* placements = reinterpret_cast<const PlacementData*>(placement_data.ptr());
    float* transforms = reinterpret_cast<float*>(transform_data.ptrw());
    
    for (uint32_t i = 0; i < placement_count; i++) {
        const PlacementData& pd = placements[i];
        
        float cos_y = std::cos(pd.rotation_y);
        float sin_y = std::sin(pd.rotation_y);
        float scale = pd.scale;
        
        // Row 0: X basis (rotated and scaled)
        transforms[i * 12 + 0] = cos_y * scale;
        transforms[i * 12 + 1] = 0.0f;
        transforms[i * 12 + 2] = sin_y * scale;
        transforms[i * 12 + 3] = pd.position.x;
        
        // Row 1: Y basis (up, scaled)
        transforms[i * 12 + 4] = 0.0f;
        transforms[i * 12 + 5] = scale;
        transforms[i * 12 + 6] = 0.0f;
        transforms[i * 12 + 7] = pd.position.y;
        
        // Row 2: Z basis (rotated and scaled)
        transforms[i * 12 + 8] = -sin_y * scale;
        transforms[i * 12 + 9] = 0.0f;
        transforms[i * 12 + 10] = cos_y * scale;
        transforms[i * 12 + 11] = pd.position.z;
    }
    
    RID transform_buffer = rd->storage_buffer_create(transform_buffer_size, transform_data);
    
    if (!transform_buffer.is_valid()) {
        UtilityFunctions::push_warning("NativeVegetationDispatcher: Failed to create transform buffer");
        return RID();
    }
    
    cache_mutex->lock();
    transform_buffer_cache[chunk_origin][veg_type] = transform_buffer;
    cache_mutex->unlock();
    
    return transform_buffer;
}

void NativeVegetationDispatcher::set_terrain_dispatcher(Object* dispatcher) {
    terrain_dispatcher = dispatcher;
}

Object* NativeVegetationDispatcher::get_terrain_dispatcher() const {
    return terrain_dispatcher;
}

void NativeVegetationDispatcher::set_max_cache_entries(int count) {
    max_cache_entries = count;
}

int NativeVegetationDispatcher::get_max_cache_entries() const {
    return max_cache_entries;
}

int NativeVegetationDispatcher::get_cache_size() const {
    cache_mutex->lock();
    int size = 0;
    for (const auto& chunk_pair : placement_cache) {
        size += chunk_pair.second.size();
    }
    cache_mutex->unlock();
    return size;
}

float NativeVegetationDispatcher::get_last_placement_time_ms() const {
    return static_cast<float>(last_placement_time_us.load()) / 1000.0f;
}

float NativeVegetationDispatcher::get_average_placement_time_ms() const {
    if (placement_call_count == 0) {
        return 0.0f;
    }
    
    return static_cast<float>(total_placement_time_us.load()) / 1000.0f / placement_call_count.load();
}

Dictionary NativeVegetationDispatcher::get_timing_per_type_ms() const {
    return timing_per_type;
}

int NativeVegetationDispatcher::get_total_placement_calls() const {
    return placement_call_count.load();
}

void NativeVegetationDispatcher::reset_timing_stats() {
    total_placement_time_us = 0;
    last_placement_time_us = 0;
    placement_call_count = 0;
    timing_per_type.clear();
}

void NativeVegetationDispatcher::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize_gpu"), &NativeVegetationDispatcher::initialize_gpu);
    ClassDB::bind_method(D_METHOD("cleanup_gpu"), &NativeVegetationDispatcher::cleanup_gpu);
    
    ClassDB::bind_method(D_METHOD("generate_placements", "chunk_origin", "veg_type", "density", "grid_spacing", "noise_frequency", "slope_max", "height_range", "world_seed", "biome_map_texture", "cpu_fallback"), 
        &NativeVegetationDispatcher::generate_placements, DEFVAL(true));
    
    ClassDB::bind_method(D_METHOD("is_chunk_ready", "chunk_origin", "veg_type"), &NativeVegetationDispatcher::is_chunk_ready);
    ClassDB::bind_method(D_METHOD("is_gpu_ready", "chunk_origin", "veg_type"), &NativeVegetationDispatcher::is_gpu_ready);
    ClassDB::bind_method(D_METHOD("clear_cache"), &NativeVegetationDispatcher::clear_cache);
    
    ClassDB::bind_method(D_METHOD("get_placement_buffer_rid", "chunk_origin", "veg_type"), &NativeVegetationDispatcher::get_placement_buffer_rid);
    ClassDB::bind_method(D_METHOD("get_placement_count", "chunk_origin", "veg_type"), &NativeVegetationDispatcher::get_placement_count);
    ClassDB::bind_method(D_METHOD("get_transform_buffer_rid", "chunk_origin", "veg_type"), &NativeVegetationDispatcher::get_transform_buffer_rid);
    
    ClassDB::bind_method(D_METHOD("set_terrain_dispatcher", "dispatcher"), &NativeVegetationDispatcher::set_terrain_dispatcher);
    ClassDB::bind_method(D_METHOD("get_terrain_dispatcher"), &NativeVegetationDispatcher::get_terrain_dispatcher);
    
    ClassDB::bind_method(D_METHOD("set_max_cache_entries", "count"), &NativeVegetationDispatcher::set_max_cache_entries);
    ClassDB::bind_method(D_METHOD("get_max_cache_entries"), &NativeVegetationDispatcher::get_max_cache_entries);
    ClassDB::bind_method(D_METHOD("get_cache_size"), &NativeVegetationDispatcher::get_cache_size);
    
    ClassDB::bind_method(D_METHOD("get_last_placement_time_ms"), &NativeVegetationDispatcher::get_last_placement_time_ms);
    ClassDB::bind_method(D_METHOD("get_average_placement_time_ms"), &NativeVegetationDispatcher::get_average_placement_time_ms);
    ClassDB::bind_method(D_METHOD("get_timing_per_type_ms"), &NativeVegetationDispatcher::get_timing_per_type_ms);
    ClassDB::bind_method(D_METHOD("get_total_placement_calls"), &NativeVegetationDispatcher::get_total_placement_calls);
    ClassDB::bind_method(D_METHOD("reset_timing_stats"), &NativeVegetationDispatcher::reset_timing_stats);
    
    ADD_PROPERTY(PropertyInfo(Variant::INT, "max_cache_entries"), "set_max_cache_entries", "get_max_cache_entries");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "terrain_dispatcher"), "set_terrain_dispatcher", "get_terrain_dispatcher");
}
