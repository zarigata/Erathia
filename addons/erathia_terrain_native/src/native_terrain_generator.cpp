#include "native_terrain_generator.h"
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/rd_shader_file.hpp>
#include <godot_cpp/classes/rd_shader_source.hpp>
#include <godot_cpp/classes/rd_shader_spirv.hpp>
#include <godot_cpp/classes/rd_uniform.hpp>
#include <godot_cpp/classes/rd_sampler_state.hpp>
#include <godot_cpp/classes/rd_texture_format.hpp>
#include <godot_cpp/classes/rd_texture_view.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/core/class_db.hpp>

NativeTerrainGenerator::NativeTerrainGenerator() {
    rd = nullptr;
    world_seed = 0;
    chunk_size = 32;
    world_size = 16000.0f;
    sea_level = 0.0f;
    blend_dist = 0.2f;
    gpu_initialized = false;
    gpu_status_message = "Not initialized";
    player_position = Vector3(0, 0, 0);  // Initialize player position
    
    cache_mutex.instantiate();
    queue_mutex.instantiate();
    
    // Async GPU infrastructure initialization
    readback_thread_running = false;
    frame_gpu_budget_us = 8000;  // 8ms budget
    current_frame_gpu_time_us = 0;
    chunks_dispatched_this_frame = 0;
    chunks_completed_this_frame = 0;
    total_gpu_time_us = 0;
    total_chunks_generated = 0;
    
    // Initialize GPU immediately to ensure availability checks work
    initialize_gpu();
    
    // Start background readback thread
    start_readback_thread();
}

NativeTerrainGenerator::~NativeTerrainGenerator() {
    stop_readback_thread();
    cleanup_gpu();
}

bool NativeTerrainGenerator::initialize_gpu() {
    if (gpu_initialized) {
        return true;
    }

    RenderingServer *rs = RenderingServer::get_singleton();
    if (!rs) {
        gpu_status_message = "RenderingServer not available";
        UtilityFunctions::printerr("[NativeTerrainGenerator] RenderingServer not available");
        return false;
    }

    rd = rs->create_local_rendering_device();
    if (!rd) {
        gpu_status_message = "Failed to create RenderingDevice (compatibility renderer or headless mode?)";
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create RenderingDevice");
        return false;
    }

    // Compile biome map shader first
    if (!compile_biome_map_shader()) {
        return false;
    }
    
    // Compile SDF shader
    if (!compile_sdf_shader()) {
        return false;
    }

    gpu_initialized = true;
    gpu_status_message = "GPU initialized successfully (biome map + SDF pipelines)";
    UtilityFunctions::print("[NativeTerrainGenerator] GPU initialized successfully with both pipelines");
    return true;
}

void NativeTerrainGenerator::cleanup_gpu() {
    if (!rd) {
        return;
    }

    // Free all in-flight chunk textures and fences
    queue_mutex->lock();
    for (auto& pair : chunk_gpu_states) {
        if (pair.second.sdf_texture.is_valid()) {
            rd->free_rid(pair.second.sdf_texture);
        }
        if (pair.second.material_texture.is_valid()) {
            rd->free_rid(pair.second.material_texture);
        }
        if (pair.second.fence.is_valid()) {
            rd->free_rid(pair.second.fence);
        }
    }
    chunk_gpu_states.clear();
    queue_mutex->unlock();

    cache_mutex->lock();
    Array keys = sdf_cache.keys();
    for (int i = 0; i < keys.size(); i++) {
        Dictionary textures = sdf_cache[keys[i]];
        if (textures.has("sdf")) {
            RID sdf_rid = textures["sdf"];
            if (sdf_rid.is_valid()) {
                rd->free_rid(sdf_rid);
            }
        }
        if (textures.has("material")) {
            RID mat_rid = textures["material"];
            if (mat_rid.is_valid()) {
                rd->free_rid(mat_rid);
            }
        }
    }
    sdf_cache.clear();
    cache_mutex->unlock();

    // Free all tracked samplers
    for (size_t i = 0; i < sampler_rids.size(); i++) {
        if (sampler_rids[i].is_valid()) {
            rd->free_rid(sampler_rids[i]);
        }
    }
    sampler_rids.clear();
    
    if (cached_sampler.is_valid()) {
        rd->free_rid(cached_sampler);
        cached_sampler = RID();
    }

    if (sdf_pipeline.is_valid()) {
        rd->free_rid(sdf_pipeline);
        sdf_pipeline = RID();
    }
    if (sdf_shader.is_valid()) {
        rd->free_rid(sdf_shader);
        sdf_shader = RID();
    }
    
    if (biome_map_pipeline.is_valid()) {
        rd->free_rid(biome_map_pipeline);
        biome_map_pipeline = RID();
    }
    if (biome_map_shader.is_valid()) {
        rd->free_rid(biome_map_shader);
        biome_map_shader = RID();
    }
    
    if (biome_map_texture.is_valid()) {
        rd->free_rid(biome_map_texture);
        biome_map_texture = RID();
    }

    rd = nullptr;
    gpu_initialized = false;
    gpu_status_message = "GPU cleaned up";
}

RID NativeTerrainGenerator::create_3d_texture(RenderingDevice::DataFormat format) {
    Ref<RDTextureFormat> tex_format;
    tex_format.instantiate();
    tex_format->set_format(format);
    tex_format->set_width(chunk_size);
    tex_format->set_height(chunk_size);
    tex_format->set_depth(chunk_size);
    tex_format->set_texture_type(RenderingDevice::TEXTURE_TYPE_3D);
    tex_format->set_usage_bits(
        RenderingDevice::TEXTURE_USAGE_STORAGE_BIT |
        RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT |
        RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT
    );

    PackedByteArray empty_data;
    int bytes_per_pixel = (format == RenderingDevice::DATA_FORMAT_R32_SFLOAT) ? 4 : 4;
    empty_data.resize(chunk_size * chunk_size * chunk_size * bytes_per_pixel);
    empty_data.fill(0);

    TypedArray<PackedByteArray> data_array;
    data_array.push_back(empty_data);

    return rd->texture_create(tex_format, Ref<RDTextureView>(), data_array);
}

RID NativeTerrainGenerator::get_or_create_sampler() {
    if (cached_sampler.is_valid()) {
        return cached_sampler;
    }
    
    Ref<RDSamplerState> sampler_state;
    sampler_state.instantiate();
    sampler_state->set_min_filter(RenderingDevice::SAMPLER_FILTER_LINEAR);
    sampler_state->set_mag_filter(RenderingDevice::SAMPLER_FILTER_LINEAR);
    sampler_state->set_repeat_u(RenderingDevice::SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE);
    sampler_state->set_repeat_v(RenderingDevice::SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE);
    
    cached_sampler = rd->sampler_create(sampler_state);
    return cached_sampler;
}

Dictionary NativeTerrainGenerator::create_sampler_uniform(int binding, RID texture) {
    RID sampler = get_or_create_sampler();

    Ref<RDUniform> uniform;
    uniform.instantiate();
    uniform->set_uniform_type(RenderingDevice::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE);
    uniform->set_binding(binding);
    uniform->add_id(sampler);
    uniform->add_id(texture);

    Dictionary result;
    result["uniform"] = uniform;
    return result;
}

Dictionary NativeTerrainGenerator::create_image_uniform(int binding, RID texture) {
    Ref<RDUniform> uniform;
    uniform.instantiate();
    uniform->set_uniform_type(RenderingDevice::UNIFORM_TYPE_IMAGE);
    uniform->set_binding(binding);
    uniform->add_id(texture);

    Dictionary result;
    result["uniform"] = uniform;
    return result;
}

bool NativeTerrainGenerator::compile_biome_map_shader() {
    String shader_path = "res://_engine/terrain/biome_map.compute";
    if (!FileAccess::file_exists(shader_path)) {
        gpu_status_message = "Biome map shader file not found: " + shader_path;
        UtilityFunctions::printerr("[NativeTerrainGenerator] Biome map shader file not found: ", shader_path);
        return false;
    }

    String shader_source = FileAccess::get_file_as_string(shader_path);
    if (shader_source.is_empty()) {
        gpu_status_message = "Failed to read biome map shader file: " + shader_path;
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to read biome map shader file");
        return false;
    }

    Ref<RDShaderSource> shader_src;
    shader_src.instantiate();
    shader_src->set_stage_source(RenderingDevice::SHADER_STAGE_COMPUTE, shader_source);
    shader_src->set_language(RenderingDevice::SHADER_LANGUAGE_GLSL);
    
    Ref<RDShaderSPIRV> shader_spirv = rd->shader_compile_spirv_from_source(shader_src);

    if (!shader_spirv.is_valid() || shader_spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE) != "") {
        gpu_status_message = "Biome map shader compilation failed: " + shader_spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE);
        UtilityFunctions::printerr("[NativeTerrainGenerator] Biome map shader compilation failed: ", 
            shader_spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE));
        return false;
    }

    biome_map_shader = rd->shader_create_from_spirv(shader_spirv);
    if (!biome_map_shader.is_valid()) {
        gpu_status_message = "Failed to create biome map shader from SPIRV";
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create biome map shader from SPIRV");
        return false;
    }

    biome_map_pipeline = rd->compute_pipeline_create(biome_map_shader);
    if (!biome_map_pipeline.is_valid()) {
        gpu_status_message = "Failed to create biome map compute pipeline";
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create biome map compute pipeline");
        return false;
    }

    UtilityFunctions::print("[NativeTerrainGenerator] Biome map shader compiled successfully");
    return true;
}

bool NativeTerrainGenerator::compile_sdf_shader() {
    String shader_path = "res://_engine/terrain/biome_gpu_sdf.compute";
    if (!FileAccess::file_exists(shader_path)) {
        gpu_status_message = "SDF shader file not found: " + shader_path;
        UtilityFunctions::printerr("[NativeTerrainGenerator] SDF shader file not found: ", shader_path);
        return false;
    }

    String shader_source = FileAccess::get_file_as_string(shader_path);
    if (shader_source.is_empty()) {
        gpu_status_message = "Failed to read SDF shader file: " + shader_path;
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to read SDF shader file");
        return false;
    }

    Ref<RDShaderSource> shader_src;
    shader_src.instantiate();
    shader_src->set_stage_source(RenderingDevice::SHADER_STAGE_COMPUTE, shader_source);
    shader_src->set_language(RenderingDevice::SHADER_LANGUAGE_GLSL);
    
    Ref<RDShaderSPIRV> shader_spirv = rd->shader_compile_spirv_from_source(shader_src);

    if (!shader_spirv.is_valid() || shader_spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE) != "") {
        gpu_status_message = "SDF shader compilation failed: " + shader_spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE);
        UtilityFunctions::printerr("[NativeTerrainGenerator] SDF shader compilation failed: ", 
            shader_spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE));
        return false;
    }

    sdf_shader = rd->shader_create_from_spirv(shader_spirv);
    if (!sdf_shader.is_valid()) {
        gpu_status_message = "Failed to create SDF shader from SPIRV";
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create SDF shader from SPIRV");
        return false;
    }

    sdf_pipeline = rd->compute_pipeline_create(sdf_shader);
    if (!sdf_pipeline.is_valid()) {
        gpu_status_message = "Failed to create SDF compute pipeline";
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create SDF compute pipeline");
        return false;
    }

    UtilityFunctions::print("[NativeTerrainGenerator] SDF shader compiled successfully");
    return true;
}

void NativeTerrainGenerator::generate_biome_map_if_needed() {
    if (biome_map_texture.is_valid()) {
        return; // Already generated
    }

    if (!gpu_initialized || !rd || !biome_map_pipeline.is_valid()) {
        UtilityFunctions::push_warning("[NativeTerrainGenerator] Cannot generate biome map: GPU not initialized");
        return;
    }

    // Create biome map texture (2D, RG32F format)
    int map_size = 2048; // 2K resolution biome map
    Ref<RDTextureFormat> tex_format;
    tex_format.instantiate();
    tex_format->set_format(RenderingDevice::DATA_FORMAT_R32G32_SFLOAT);
    tex_format->set_width(map_size);
    tex_format->set_height(map_size);
    tex_format->set_texture_type(RenderingDevice::TEXTURE_TYPE_2D);
    tex_format->set_usage_bits(
        RenderingDevice::TEXTURE_USAGE_STORAGE_BIT |
        RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT |
        RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT
    );

    PackedByteArray empty_data;
    empty_data.resize(map_size * map_size * 8); // RG32F = 8 bytes per pixel
    empty_data.fill(0);

    TypedArray<PackedByteArray> data_array;
    data_array.push_back(empty_data);

    biome_map_texture = rd->texture_create(tex_format, Ref<RDTextureView>(), data_array);
    if (!biome_map_texture.is_valid()) {
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create biome map texture");
        return;
    }

    // Create uniform for output image
    TypedArray<RDUniform> uniforms;
    Dictionary img_dict = create_image_uniform(1, biome_map_texture);
    uniforms.push_back(img_dict["uniform"]);

    RID uniform_set = rd->uniform_set_create(uniforms, biome_map_shader, 0);
    if (!uniform_set.is_valid()) {
        rd->free_rid(biome_map_texture);
        biome_map_texture = RID();
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create biome map uniform set");
        return;
    }

    // Push constants: biome_count, world_size, cell_scale, jitter, seed
    PackedFloat32Array push_constants;
    push_constants.push_back(17.0f); // biome_count
    push_constants.push_back(world_size);
    push_constants.push_back(2000.0f); // cell_scale (2km cells)
    push_constants.push_back(0.8f); // jitter
    push_constants.push_back(static_cast<float>(world_seed));

    PackedByteArray push_constant_bytes = push_constants.to_byte_array();

    // Dispatch biome map generation
    int64_t compute_list = rd->compute_list_begin();
    rd->compute_list_bind_compute_pipeline(compute_list, biome_map_pipeline);
    rd->compute_list_bind_uniform_set(compute_list, uniform_set, 0);
    rd->compute_list_set_push_constant(compute_list, push_constant_bytes, push_constant_bytes.size());
    
    int workgroups = map_size / 8; // local_size_x = 8, local_size_y = 8
    rd->compute_list_dispatch(compute_list, workgroups, workgroups, 1);
    rd->compute_list_end();
    
    // COMMENT 2 FIX: Use barrier() to ensure GPU work completes
    rd->submit();
    rd->barrier(RenderingDevice::BARRIER_MASK_TRANSFER);

    rd->free_rid(uniform_set);

    UtilityFunctions::print("[NativeTerrainGenerator] Biome map generated (", map_size, "x", map_size, ")");
}

Dictionary NativeTerrainGenerator::generate_chunk_sdf(Vector3i chunk_origin) {
    if (!gpu_initialized || !rd || !sdf_pipeline.is_valid()) {
        UtilityFunctions::printerr("[NativeTerrainGenerator] GPU not initialized");
        return Dictionary();
    }
    
    // Generate biome map if not already done
    generate_biome_map_if_needed();

    cache_mutex->lock();
    if (sdf_cache.has(chunk_origin)) {
        Dictionary cached = sdf_cache[chunk_origin];
        cache_mutex->unlock();
        return cached;
    }
    cache_mutex->unlock();

    RID sdf_texture = create_3d_texture(RenderingDevice::DATA_FORMAT_R32_SFLOAT);
    if (!sdf_texture.is_valid()) {
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create SDF texture");
        return Dictionary();
    }

    RID material_texture = create_3d_texture(RenderingDevice::DATA_FORMAT_R32_UINT);
    if (!material_texture.is_valid()) {
        rd->free_rid(sdf_texture);
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create material texture");
        return Dictionary();
    }

    TypedArray<RDUniform> uniforms;
    
    if (biome_map_texture.is_valid()) {
        Dictionary sampler_dict = create_sampler_uniform(0, biome_map_texture);
        uniforms.push_back(sampler_dict["uniform"]);
    } else {
        UtilityFunctions::push_warning("[NativeTerrainGenerator] Biome map texture not available");
        return Dictionary();
    }

    Dictionary sdf_dict = create_image_uniform(1, sdf_texture);
    uniforms.push_back(sdf_dict["uniform"]);

    Dictionary mat_dict = create_image_uniform(2, material_texture);
    uniforms.push_back(mat_dict["uniform"]);

    RID uniform_set = rd->uniform_set_create(uniforms, sdf_shader, 0);
    if (!uniform_set.is_valid()) {
        rd->free_rid(sdf_texture);
        rd->free_rid(material_texture);
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create uniform set");
        return Dictionary();
    }

    PackedFloat32Array push_constants;
    push_constants.push_back(static_cast<float>(chunk_origin.x));
    push_constants.push_back(static_cast<float>(chunk_origin.y));
    push_constants.push_back(static_cast<float>(chunk_origin.z));
    push_constants.push_back(world_size);
    push_constants.push_back(sea_level);
    push_constants.push_back(blend_dist);
    push_constants.push_back(static_cast<float>(chunk_size));
    push_constants.push_back(static_cast<float>(world_seed));

    PackedByteArray push_constant_bytes = push_constants.to_byte_array();

    int64_t compute_list = rd->compute_list_begin();
    rd->compute_list_bind_compute_pipeline(compute_list, sdf_pipeline);
    rd->compute_list_bind_uniform_set(compute_list, uniform_set, 0);
    rd->compute_list_set_push_constant(compute_list, push_constant_bytes, push_constant_bytes.size());
    
    int workgroups = chunk_size / 4;
    rd->compute_list_dispatch(compute_list, workgroups, workgroups, workgroups);
    rd->compute_list_end();
    
    // COMMENT 1 FIX: Submit GPU work without blocking
    // Background thread will use barrier() to check completion
    rd->submit();
    
    rd->free_rid(uniform_set);
    
    // COMMENT 1 FIX: Store GPU state for async completion tracking
    // Background thread will mark gpu_complete after barrier()
    queue_mutex->lock();
    ChunkGPUState state;
    state.sdf_texture = sdf_texture;
    state.material_texture = material_texture;
    state.fence = RID();  // Not using fences - Godot 4.5 doesn't support them
    state.dispatch_time_us = Time::get_singleton()->get_ticks_usec();
    state.completion_time_us = 0;  // Will be set when GPU work completes
    state.gpu_complete = false;  // Will be set true by background thread after barrier()
    state.cpu_readback_complete = false;
    state.physics_needed = false;  // Will be set to true by physics requests or LOD 0
    state.lod = 0;  // Default LOD, will be updated by dispatch_chunk_async
    
    chunk_gpu_states[chunk_origin] = state;
    queue_mutex->unlock();

    // COMMENT 2 FIX: Do NOT cache until fence completes
    // Return empty dictionary - caller must poll get_chunk_gpu_textures() for readiness
    Dictionary result;
    result["sdf"] = sdf_texture;
    result["material"] = material_texture;
    result["ready"] = false;  // Not ready until fence completes

    return result;
}

void NativeTerrainGenerator::write_gpu_data_to_buffer_bulk(zylann::voxel::VoxelBuffer &voxel_buffer, RID sdf_texture, RID material_texture, int chunk_size) {
    if (!rd) {
        UtilityFunctions::printerr("[NativeTerrainGenerator] Invalid RenderingDevice");
        return;
    }

    // Read GPU textures to CPU
    PackedByteArray sdf_data = rd->texture_get_data(sdf_texture, 0);
    PackedByteArray mat_data = rd->texture_get_data(material_texture, 0);

    int total_voxels = chunk_size * chunk_size * chunk_size;
    int expected_size = total_voxels * 4;

    if (sdf_data.size() < expected_size || mat_data.size() < expected_size) {
        UtilityFunctions::printerr("[NativeTerrainGenerator] Data size mismatch in buffer write");
        return;
    }

    // BULK TRANSFER: Use VoxelBuffer API for direct bulk memory write
    const int CHANNEL_SDF = zylann::voxel::VoxelBuffer::CHANNEL_SDF;
    const int CHANNEL_INDICES = zylann::voxel::VoxelBuffer::CHANNEL_INDICES;
    
    // Clear channels first
    voxel_buffer.clear_channel_f(CHANNEL_SDF, 1.0f);
    voxel_buffer.clear_channel(CHANNEL_INDICES, 0);
    
    // Write data using voxel_cpp API
    const uint8_t* sdf_ptr = sdf_data.ptr();
    const uint8_t* mat_ptr = mat_data.ptr();
    
    for (int z = 0; z < chunk_size; z++) {
        for (int y = 0; y < chunk_size; y++) {
            for (int x = 0; x < chunk_size; x++) {
                int idx = (z * chunk_size * chunk_size + y * chunk_size + x) * 4;
                float sdf_value;
                std::memcpy(&sdf_value, &sdf_ptr[idx], sizeof(float));
                uint32_t mat_value;
                std::memcpy(&mat_value, &mat_ptr[idx], sizeof(uint32_t));
                voxel_buffer.set_voxel_f(sdf_value, x, y, z, CHANNEL_SDF);
                voxel_buffer.set_voxel(mat_value, x, y, z, CHANNEL_INDICES);
            }
        }
    }
}


int NativeTerrainGenerator::sample_biome_at_chunk(Vector3i chunk_origin) {
    Vector3i center = chunk_origin + Vector3i(chunk_size / 2, chunk_size / 2, chunk_size / 2);
    
    float norm_x = static_cast<float>(center.x) / world_size;
    float norm_z = static_cast<float>(center.z) / world_size;
    
    int biome_id = static_cast<int>((norm_x + norm_z) * 10.0f) % 17;
    
    return biome_id;
}

NativeTerrainGenerator::Result NativeTerrainGenerator::generate_block(VoxelQueryData input) {
    Result result;
    result.max_lod_hint = false;
    
    if (!gpu_initialized) {
        if (!initialize_gpu()) {
            UtilityFunctions::printerr("[NativeTerrainGenerator] GPU initialization failed");
            return result;
        }
    }

    Vector3i origin_in_voxels = input.origin_in_voxels;
    int lod = input.lod;
    zylann::voxel::VoxelBuffer &out_buffer = input.voxel_buffer;

    // Check cache first
    String cache_key = String("{0}_{1}_{2}_{3}").format(Array::make(origin_in_voxels.x, origin_in_voxels.y, origin_in_voxels.z, lod));
    
    cache_mutex->lock();
    if (sdf_cache.has(cache_key)) {
        Dictionary cached = sdf_cache[cache_key];
        if (cached.has("sdf_data") && cached.has("mat_data")) {
            PackedByteArray sdf_data = cached["sdf_data"];
            PackedByteArray mat_data = cached["mat_data"];
            cache_mutex->unlock();
            
            const int CHANNEL_SDF = zylann::voxel::VoxelBuffer::CHANNEL_SDF;
            const int CHANNEL_INDICES = zylann::voxel::VoxelBuffer::CHANNEL_INDICES;
            
            // Write cached data to buffer
            const uint8_t* sdf_ptr = sdf_data.ptr();
            const uint8_t* mat_ptr = mat_data.ptr();
            
            for (int z = 0; z < chunk_size; z++) {
                for (int y = 0; y < chunk_size; y++) {
                    for (int x = 0; x < chunk_size; x++) {
                        int idx = (z * chunk_size * chunk_size + y * chunk_size + x) * 4;
                        float sdf_value;
                        std::memcpy(&sdf_value, &sdf_ptr[idx], sizeof(float));
                        uint32_t mat_value;
                        std::memcpy(&mat_value, &mat_ptr[idx], sizeof(uint32_t));
                        out_buffer.set_voxel_f(sdf_value, x, y, z, CHANNEL_SDF);
                        out_buffer.set_voxel(mat_value, x, y, z, CHANNEL_INDICES);
                    }
                }
            }
            result.max_lod_hint = true;
            return result;
        }
    }
    cache_mutex->unlock();
    
    // Async GPU path: enqueue request
    if (lod > 0) {
        enqueue_chunk_request(origin_in_voxels, lod, player_position);
        return result;
    }
    
    // LOD 0: synchronous generation
    Dictionary gpu_result = generate_chunk_sdf(origin_in_voxels);
    if (gpu_result.has("sdf_texture") && gpu_result.has("material_texture")) {
        RID sdf_tex = gpu_result["sdf_texture"];
        RID mat_tex = gpu_result["material_texture"];
        
        write_gpu_data_to_buffer_bulk(out_buffer, sdf_tex, mat_tex, chunk_size);
        
        // Cache for future requests
        cache_mutex->lock();
        PackedByteArray sdf_data = rd->texture_get_data(sdf_tex, 0);
        PackedByteArray mat_data = rd->texture_get_data(mat_tex, 0);
        Dictionary cache_entry;
        cache_entry["sdf_data"] = sdf_data;
        cache_entry["mat_data"] = mat_data;
        sdf_cache[cache_key] = cache_entry;
        cache_mutex->unlock();
        
        result.max_lod_hint = true;
        return result;
    }
    
    return result;
}


int NativeTerrainGenerator::get_used_channels_mask() const {
    // CHANNEL_SDF = 1, CHANNEL_INDICES = 3
    return (1 << 1) | (1 << 3);
}

void NativeTerrainGenerator::set_world_seed(int seed) {
    world_seed = seed;
}

int NativeTerrainGenerator::get_world_seed() const {
    return world_seed;
}

void NativeTerrainGenerator::set_chunk_size(int size) {
    chunk_size = size;
}

int NativeTerrainGenerator::get_chunk_size() const {
    return chunk_size;
}

void NativeTerrainGenerator::set_world_size(float size) {
    world_size = size;
}

float NativeTerrainGenerator::get_world_size() const {
    return world_size;
}

void NativeTerrainGenerator::set_sea_level(float level) {
    sea_level = level;
}

float NativeTerrainGenerator::get_sea_level() const {
    return sea_level;
}

void NativeTerrainGenerator::set_blend_dist(float dist) {
    blend_dist = dist;
}

float NativeTerrainGenerator::get_blend_dist() const {
    return blend_dist;
}

void NativeTerrainGenerator::set_biome_map_texture(Ref<Image> texture) {
    if (!texture.is_valid()) {
        UtilityFunctions::push_warning("[NativeTerrainGenerator] Invalid biome map texture provided");
        return;
    }

    if (!rd) {
        if (!initialize_gpu()) {
            UtilityFunctions::printerr("[NativeTerrainGenerator] Cannot set biome map: GPU not initialized");
            return;
        }
    }

    Ref<Image> processed_texture = texture->duplicate();
    
    if (processed_texture->is_compressed()) {
        processed_texture->decompress();
    }

    // CRITICAL: Preserve RG32F format for biome_id (R) and dist_edge (G) channels
    // The compute shader expects: R=biome_id (0-1), G=dist_edge (0-1)
    // Do NOT convert to RGBA8 as it drops the float precision needed for dist_edge
    RenderingDevice::DataFormat gpu_format;
    Image::Format target_format;
    
    // Check if the image is already in a compatible float format
    if (processed_texture->get_format() == Image::FORMAT_RGF || 
        processed_texture->get_format() == Image::FORMAT_RGBAF) {
        // Already in float format, use RG32F
        target_format = Image::FORMAT_RGF;
        gpu_format = RenderingDevice::DATA_FORMAT_R32G32_SFLOAT;
    } else {
        // Convert to RGF to preserve the two-channel float data
        target_format = Image::FORMAT_RGF;
        gpu_format = RenderingDevice::DATA_FORMAT_R32G32_SFLOAT;
    }
    
    if (processed_texture->get_format() != target_format) {
        processed_texture->convert(target_format);
    }

    Ref<RDTextureFormat> tex_format;
    tex_format.instantiate();
    tex_format->set_format(gpu_format);
    tex_format->set_width(processed_texture->get_width());
    tex_format->set_height(processed_texture->get_height());
    tex_format->set_texture_type(RenderingDevice::TEXTURE_TYPE_2D);
    tex_format->set_usage_bits(
        RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT |
        RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT
    );

    TypedArray<PackedByteArray> data_array;
    data_array.push_back(processed_texture->get_data());

    if (biome_map_texture.is_valid()) {
        rd->free_rid(biome_map_texture);
    }

    biome_map_texture = rd->texture_create(tex_format, Ref<RDTextureView>(), data_array);
    
    if (biome_map_texture.is_valid()) {
        UtilityFunctions::print("[NativeTerrainGenerator] Biome map texture set successfully (", 
            processed_texture->get_width(), "x", processed_texture->get_height(), ") in RG32F format");
    } else {
        UtilityFunctions::printerr("[NativeTerrainGenerator] Failed to create biome map texture");
    }
}

bool NativeTerrainGenerator::is_gpu_available() const {
    return gpu_initialized && rd != nullptr && sdf_pipeline.is_valid() && biome_map_pipeline.is_valid();
}

String NativeTerrainGenerator::get_gpu_status() const {
    return gpu_status_message;
}

void NativeTerrainGenerator::_notification(int p_what) {
    if (p_what == NOTIFICATION_PREDELETE) {
        cleanup_gpu();
    }
}

// Async GPU Methods Implementation

bool NativeTerrainGenerator::poll_gpu_completion(Vector3i origin) {
    // COMMENT 1 FIX: Check gpu_complete flag set by background thread
    // Background thread uses barrier() to ensure GPU work is done before setting flag
    queue_mutex->lock();
    
    auto it = chunk_gpu_states.find(origin);
    if (it == chunk_gpu_states.end()) {
        queue_mutex->unlock();
        return false;
    }
    
    bool complete = it->second.gpu_complete;
    queue_mutex->unlock();
    return complete;
}

void NativeTerrainGenerator::enqueue_chunk_request(Vector3i origin, int lod, Vector3 player_pos) {
    queue_mutex->lock();
    
    // COMMENT 4 FIX: Use real player position for priority calculation
    // Update internal player position if provided
    if (player_pos != Vector3(0, 0, 0)) {
        player_position = player_pos;
    }
    
    // Calculate priority (distance from player)
    Vector3 chunk_center = Vector3(origin.x + chunk_size/2, origin.y + chunk_size/2, origin.z + chunk_size/2);
    float distance = chunk_center.distance_to(player_position);
    
    ChunkRequest request;
    request.origin = origin;
    request.lod = lod;
    request.priority = distance;  // Lower distance = higher priority
    request.request_time_us = Time::get_singleton()->get_ticks_usec();
    
    chunk_request_queue.push(request);
    
    queue_mutex->unlock();
}

void NativeTerrainGenerator::process_chunk_queue(float delta) {
    reset_frame_budget();
    chunks_dispatched_this_frame = 0;
    chunks_completed_this_frame = 0;
    
    // COMMENT 3 FIX: Poll all in-flight chunks first to get accurate GPU time measurements
    std::vector<Vector3i> to_check;
    queue_mutex->lock();
    for (auto& pair : chunk_gpu_states) {
        to_check.push_back(pair.first);
    }
    queue_mutex->unlock();
    
    for (Vector3i origin : to_check) {
        if (poll_gpu_completion(origin)) {
            // COMMENT 3 FIX: Add measured GPU time to current frame budget
            queue_mutex->lock();
            auto it = chunk_gpu_states.find(origin);
            if (it != chunk_gpu_states.end() && it->second.completion_time_us > 0) {
                uint64_t measured_time = it->second.completion_time_us - it->second.dispatch_time_us;
                current_frame_gpu_time_us += measured_time;
            }
            queue_mutex->unlock();
        }
    }
    
    // COMMENT 3 FIX: Dispatch new chunks only if measured GPU time is under budget
    queue_mutex->lock();
    
    while (!chunk_request_queue.empty() && current_frame_gpu_time_us < frame_gpu_budget_us) {
        ChunkRequest request = chunk_request_queue.top();
        chunk_request_queue.pop();
        
        // Skip if already in cache or being processed
        cache_mutex->lock();
        bool in_cache = sdf_cache.has(request.origin);
        cache_mutex->unlock();
        
        if (in_cache || chunk_gpu_states.find(request.origin) != chunk_gpu_states.end()) {
            continue;
        }
        
        queue_mutex->unlock();
        dispatch_chunk_async(request.origin, request.lod);
        queue_mutex->lock();
        
        chunks_dispatched_this_frame++;
        
        // COMMENT 3 FIX: Use measured average GPU time for budget estimation
        // Only dispatch if we have headroom based on actual measurements
        uint64_t avg_measured_time = total_chunks_generated > 0 
            ? total_gpu_time_us / total_chunks_generated 
            : 2000;  // 2ms conservative default
        current_frame_gpu_time_us += avg_measured_time;
    }
    
    queue_mutex->unlock();
}

void NativeTerrainGenerator::dispatch_chunk_async(Vector3i origin, int lod) {
    // This is essentially generate_chunk_sdf but without cache check
    generate_chunk_sdf(origin);
    
    // Update LOD and physics_needed flag
    queue_mutex->lock();
    auto it = chunk_gpu_states.find(origin);
    if (it != chunk_gpu_states.end()) {
        it->second.lod = lod;
        // Only LOD 0 needs physics collision data
        it->second.physics_needed = (lod == 0);
    }
    queue_mutex->unlock();
}

void NativeTerrainGenerator::start_readback_thread() {
    if (readback_thread.is_valid() && readback_thread->is_started()) {
        return;
    }
    
    readback_thread_running = true;
    readback_thread.instantiate();
    readback_thread->start(callable_mp(this, &NativeTerrainGenerator::readback_worker_loop));
}

void NativeTerrainGenerator::readback_worker_loop() {
    while (readback_thread_running) {
        // COMMENT 1 FIX: Use barrier() in background thread to mark GPU completion
        // This avoids stalling the main thread while still ensuring GPU work is done
        std::vector<Vector3i> to_complete;
        std::vector<Vector3i> to_readback;
        
        queue_mutex->lock();
        for (auto& pair : chunk_gpu_states) {
            if (!pair.second.gpu_complete) {
                // Chunk needs GPU completion check
                to_complete.push_back(pair.first);
            } else if (!pair.second.cpu_readback_complete) {
                // GPU complete, needs CPU readback
                to_readback.push_back(pair.first);
            }
        }
        queue_mutex->unlock();
        
        // COMMENT 1 FIX: Use barrier() in background thread only (not main thread)
        // This ensures GPU work is complete before marking chunks ready
        if (!to_complete.empty() && rd) {
            rd->barrier(RenderingDevice::BARRIER_MASK_TRANSFER);
            
            // Mark all pending chunks as GPU complete
            queue_mutex->lock();
            for (Vector3i origin : to_complete) {
                auto it = chunk_gpu_states.find(origin);
                if (it != chunk_gpu_states.end() && !it->second.gpu_complete) {
                    it->second.gpu_complete = true;
                    it->second.completion_time_us = Time::get_singleton()->get_ticks_usec();
                    uint64_t measured_time = it->second.completion_time_us - it->second.dispatch_time_us;
                    total_gpu_time_us += measured_time;
                    total_chunks_generated++;
                    
                    // Add to readback queue
                    to_readback.push_back(origin);
                }
            }
            queue_mutex->unlock();
        }
        
        // COMMENT 2 FIX: Perform readback only for physics-needed (LOD 0) chunks
        for (Vector3i origin : to_readback) {
            queue_mutex->lock();
            auto it = chunk_gpu_states.find(origin);
            if (it == chunk_gpu_states.end()) {
                queue_mutex->unlock();
                continue;
            }
            
            // COMMENT 2 FIX: Check physics_needed flag - skip readback for non-physics LODs
            bool needs_physics = it->second.physics_needed;
            RID sdf_tex = it->second.sdf_texture;
            RID mat_tex = it->second.material_texture;
            queue_mutex->unlock();
            
            PackedByteArray sdf_data;
            PackedByteArray mat_data;
            
            // COMMENT 2 FIX: Only perform CPU readback if physics is needed (LOD 0)
            if (needs_physics) {
                sdf_data = rd->texture_get_data(sdf_tex, 0);
                mat_data = rd->texture_get_data(mat_tex, 0);
            }
            
            // COMMENT 2 FIX: Move to cache - store CPU data only if physics_needed
            queue_mutex->lock();
            it = chunk_gpu_states.find(origin);
            if (it != chunk_gpu_states.end()) {
                it->second.sdf_data = sdf_data;
                it->second.mat_data = mat_data;
                it->second.cpu_readback_complete = needs_physics;  // Only complete if we did readback
                
                cache_mutex->lock();
                Dictionary cache_entry;
                cache_entry["sdf"] = it->second.sdf_texture;
                cache_entry["material"] = it->second.material_texture;
                cache_entry["gpu_complete"] = true;  // GPU work is complete
                
                // COMMENT 2 FIX: Only store CPU data if physics was needed
                if (needs_physics && !sdf_data.is_empty() && !mat_data.is_empty()) {
                    cache_entry["sdf_data"] = sdf_data;
                    cache_entry["mat_data"] = mat_data;
                }
                
                sdf_cache[origin] = cache_entry;
                cache_mutex->unlock();
                
                chunk_gpu_states.erase(it);
            }
            queue_mutex->unlock();
        }
        
        // Sleep to avoid busy-waiting
        OS *os = OS::get_singleton();
        if (os) {
            os->delay_usec(1000);  // 1ms sleep
        }
    }
}

void NativeTerrainGenerator::stop_readback_thread() {
    readback_thread_running = false;
    if (readback_thread.is_valid() && readback_thread->is_started()) {
        readback_thread->wait_to_finish();
    }
}

Dictionary NativeTerrainGenerator::get_telemetry() const {
    Dictionary stats;
    stats["chunks_dispatched_this_frame"] = chunks_dispatched_this_frame.load();
    stats["chunks_completed_this_frame"] = chunks_completed_this_frame.load();
    stats["total_chunks_generated"] = total_chunks_generated.load();
    stats["average_gpu_time_ms"] = total_chunks_generated > 0 
        ? (float)total_gpu_time_us / (float)total_chunks_generated / 1000.0f 
        : 0.0f;
    stats["queue_size"] = (int)chunk_request_queue.size();
    stats["in_flight_chunks"] = (int)chunk_gpu_states.size();
    
    cache_mutex->lock();
    stats["cached_chunks"] = sdf_cache.size();
    cache_mutex->unlock();
    
    stats["current_frame_gpu_time_ms"] = (float)current_frame_gpu_time_us / 1000.0f;
    stats["frame_budget_ms"] = (float)frame_gpu_budget_us / 1000.0f;
    return stats;
}

void NativeTerrainGenerator::reset_frame_budget() {
    current_frame_gpu_time_us = 0;
}

void NativeTerrainGenerator::set_player_position(Vector3 position) {
    player_position = position;
}

Vector3 NativeTerrainGenerator::get_player_position() const {
    return player_position;
}

Dictionary NativeTerrainGenerator::get_chunk_gpu_textures(Vector3i origin) const {
    Dictionary result;
    
    // COMMENT 3 FIX: GPU mesher interface - non-blocking GPU texture path
    // Returns GPU textures after fence completion, bypassing CPU readback for rendering
    
    // Check cache first (with proper locking)
    cache_mutex->lock();
    if (sdf_cache.has(origin)) {
        Dictionary cached = sdf_cache[origin];
        // Only report ready if GPU work is complete (fence checked)
        if (cached.has("sdf") && cached.has("material") && cached.has("gpu_complete")) {
            bool gpu_complete = cached["gpu_complete"];
            if (gpu_complete) {
                result["sdf"] = cached["sdf"];
                result["material"] = cached["material"];
                result["ready"] = true;
                result["has_cpu_data"] = cached.has("sdf_data") && cached.has("mat_data");
                cache_mutex->unlock();
                return result;
            }
        }
    }
    cache_mutex->unlock();
    
    // Check in-flight chunks - gpu_complete flag set by fence polling
    queue_mutex->lock();
    auto it = chunk_gpu_states.find(origin);
    if (it != chunk_gpu_states.end()) {
        // Only return ready=true if fence is complete
        if (it->second.gpu_complete) {
            result["sdf"] = it->second.sdf_texture;
            result["material"] = it->second.material_texture;
            result["ready"] = true;
            result["has_cpu_data"] = it->second.cpu_readback_complete;
        } else {
            result["ready"] = false;
        }
    } else {
        result["ready"] = false;
    }
    queue_mutex->unlock();
    
    return result;
}

void NativeTerrainGenerator::_bind_methods() {
    // Note: generate_block and get_used_channels_mask are VoxelGenerator overrides, not bound to GDScript
    
    ClassDB::bind_method(D_METHOD("initialize_gpu"), &NativeTerrainGenerator::initialize_gpu);
    ClassDB::bind_method(D_METHOD("set_world_seed", "seed"), &NativeTerrainGenerator::set_world_seed);
    ClassDB::bind_method(D_METHOD("get_world_seed"), &NativeTerrainGenerator::get_world_seed);
    ClassDB::bind_method(D_METHOD("set_chunk_size", "size"), &NativeTerrainGenerator::set_chunk_size);
    ClassDB::bind_method(D_METHOD("get_chunk_size"), &NativeTerrainGenerator::get_chunk_size);
    ClassDB::bind_method(D_METHOD("set_world_size", "size"), &NativeTerrainGenerator::set_world_size);
    ClassDB::bind_method(D_METHOD("get_world_size"), &NativeTerrainGenerator::get_world_size);
    ClassDB::bind_method(D_METHOD("set_sea_level", "level"), &NativeTerrainGenerator::set_sea_level);
    ClassDB::bind_method(D_METHOD("get_sea_level"), &NativeTerrainGenerator::get_sea_level);
    ClassDB::bind_method(D_METHOD("set_blend_dist", "dist"), &NativeTerrainGenerator::set_blend_dist);
    ClassDB::bind_method(D_METHOD("get_blend_dist"), &NativeTerrainGenerator::get_blend_dist);
    ClassDB::bind_method(D_METHOD("set_biome_map_texture", "texture"), &NativeTerrainGenerator::set_biome_map_texture);
    ClassDB::bind_method(D_METHOD("is_gpu_available"), &NativeTerrainGenerator::is_gpu_available);
    ClassDB::bind_method(D_METHOD("get_gpu_status"), &NativeTerrainGenerator::get_gpu_status);
    
    // Async GPU methods
    ClassDB::bind_method(D_METHOD("process_chunk_queue", "delta"), &NativeTerrainGenerator::process_chunk_queue);
    ClassDB::bind_method(D_METHOD("get_telemetry"), &NativeTerrainGenerator::get_telemetry);
    ClassDB::bind_method(D_METHOD("enqueue_chunk_request", "origin", "lod", "player_position"), &NativeTerrainGenerator::enqueue_chunk_request);
    ClassDB::bind_method(D_METHOD("set_player_position", "position"), &NativeTerrainGenerator::set_player_position);
    ClassDB::bind_method(D_METHOD("get_player_position"), &NativeTerrainGenerator::get_player_position);
    ClassDB::bind_method(D_METHOD("get_chunk_gpu_textures", "origin"), &NativeTerrainGenerator::get_chunk_gpu_textures);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "world_seed"), "set_world_seed", "get_world_seed");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "chunk_size"), "set_chunk_size", "get_chunk_size");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "world_size"), "set_world_size", "get_world_size");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "sea_level"), "set_sea_level", "get_sea_level");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "blend_dist"), "set_blend_dist", "get_blend_dist");

    ADD_SIGNAL(MethodInfo("chunk_generated", 
        PropertyInfo(Variant::VECTOR3I, "origin"), 
        PropertyInfo(Variant::INT, "biome_id")));
}
