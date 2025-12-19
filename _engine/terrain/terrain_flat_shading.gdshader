shader_type spatial;

// Material colors (index 0=air, 1=dirt, 2=stone, 3=iron_ore, 4=sand, 5=snow, 6=grass)
uniform vec3 dirt_color : source_color = vec3(0.4, 0.35, 0.25);
uniform vec3 stone_color : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 iron_ore_color : source_color = vec3(0.6, 0.4, 0.2);
uniform vec3 air_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 sand_color : source_color = vec3(0.85, 0.75, 0.55);
uniform vec3 snow_color : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 grass_color : source_color = vec3(0.35, 0.55, 0.25);

// Per-material roughness and metallic
uniform float dirt_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float stone_roughness : hint_range(0.0, 1.0) = 0.8;
uniform float ore_roughness : hint_range(0.0, 1.0) = 0.6;
uniform float ore_metallic : hint_range(0.0, 1.0) = 0.4;
uniform float sand_roughness : hint_range(0.0, 1.0) = 0.95;
uniform float snow_roughness : hint_range(0.0, 1.0) = 0.7;
uniform float grass_roughness : hint_range(0.0, 1.0) = 0.85;

// Procedural noise scales per material
uniform float dirt_noise_scale : hint_range(0.01, 2.0) = 0.5;
uniform float stone_noise_scale : hint_range(0.01, 2.0) = 0.3;
uniform float ore_noise_scale : hint_range(0.01, 2.0) = 0.2;
uniform float sand_noise_scale : hint_range(0.01, 2.0) = 0.4;
uniform float snow_noise_scale : hint_range(0.01, 2.0) = 0.15;
uniform float grass_noise_scale : hint_range(0.01, 2.0) = 0.6;

// Global parameters
uniform float blend_sharpness : hint_range(0.1, 10.0) = 2.0;
uniform float ambient_occlusion_strength : hint_range(0.0, 1.0) = 0.2;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.15;

// Minimum ambient lighting to prevent complete darkness
uniform float min_ambient_light : hint_range(0.0, 1.0) = 0.25;
uniform vec3 ambient_color : source_color = vec3(0.6, 0.65, 0.75);

// Height-based variation
uniform float height_variation_strength : hint_range(0.0, 1.0) = 0.05;

// Ore emissive glow
uniform float ore_emissive_strength : hint_range(0.0, 1.0) = 0.05;
uniform vec3 ore_emissive_color : source_color = vec3(0.8, 0.4, 0.1);

// Blending parameters
uniform float dirt_stone_blend_depth : hint_range(0.5, 5.0) = 2.0;
uniform float ore_blend_sharpness : hint_range(1.0, 10.0) = 4.0;

// Varying for world position and texture data
varying vec3 world_position;
varying vec3 world_normal;
varying float v_material_index;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    
    // Single texture mode: CUSTOM1.x contains the material index directly
    v_material_index = CUSTOM1.x;
}

// Hash function for pseudo-random values
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// 2D noise function (value noise)
float noise_2d(vec2 uv) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    
    // Four corners
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    // Smooth interpolation
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// 3D noise function
float noise_3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    
    // Smooth interpolation
    vec3 u = f * f * (3.0 - 2.0 * f);
    
    // 8 corners of cube
    float n000 = hash(i.xy + i.z * 17.0);
    float n100 = hash(i.xy + vec2(1.0, 0.0) + i.z * 17.0);
    float n010 = hash(i.xy + vec2(0.0, 1.0) + i.z * 17.0);
    float n110 = hash(i.xy + vec2(1.0, 1.0) + i.z * 17.0);
    float n001 = hash(i.xy + (i.z + 1.0) * 17.0);
    float n101 = hash(i.xy + vec2(1.0, 0.0) + (i.z + 1.0) * 17.0);
    float n011 = hash(i.xy + vec2(0.0, 1.0) + (i.z + 1.0) * 17.0);
    float n111 = hash(i.xy + vec2(1.0, 1.0) + (i.z + 1.0) * 17.0);
    
    // Trilinear interpolation
    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    
    return mix(nxy0, nxy1, u.z);
}

// Fractal Brownian Motion for richer noise
float fbm(vec3 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise_3d(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

// Triplanar mapping function
vec3 triplanar_mapping(vec3 world_pos, vec3 normal, float scale) {
    // Blend weights based on normal direction
    vec3 blend = abs(normal);
    blend = pow(blend, vec3(blend_sharpness));
    blend /= (blend.x + blend.y + blend.z);
    
    // Sample noise from three planes
    float noise_xy = noise_2d(world_pos.xy * scale);
    float noise_xz = noise_2d(world_pos.xz * scale);
    float noise_yz = noise_2d(world_pos.yz * scale);
    
    // Blend based on normal
    float blended_noise = noise_xy * blend.z + noise_xz * blend.y + noise_yz * blend.x;
    
    return vec3(blended_noise);
}

// Get procedural detail for each material type
float get_material_noise(vec3 world_pos, vec3 normal, int material_id) {
    float noise_scale;
    int octaves;
    
    if (material_id == 1) {
        // Dirt: fine grain pattern
        noise_scale = dirt_noise_scale;
        octaves = 3;
    } else if (material_id == 2) {
        // Stone: medium chunky pattern
        noise_scale = stone_noise_scale;
        octaves = 4;
    } else if (material_id == 3) {
        // Ore: metallic vein pattern
        noise_scale = ore_noise_scale;
        octaves = 2;
    } else {
        return 0.0;
    }
    
    return fbm(world_pos * noise_scale, octaves);
}

// Approximate ambient occlusion from vertex normal
float calculate_ao(vec3 normal) {
    // Surfaces facing down get more AO (crevices), but with minimum light
    float ao = 1.0 - max(0.0, -normal.y) * ambient_occlusion_strength;
    // Ensure minimum ambient lighting is always present
    ao = max(ao, min_ambient_light);
    return ao;
}

void fragment() {
    // Flat shading: recalculate normal per-triangle
    vec3 flat_normal = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
    NORMAL = flat_normal;
    
    // Get material index - try from CUSTOM1, fallback to position-based
    int material_id = int(floor(v_material_index + 0.5));
    
    // If material index is 0 or invalid, calculate from world position
    // This provides a fallback for when material data isn't properly passed
    if (material_id <= 0 || material_id > 6) {
        // Calculate biome from world position using simple noise-like function
        float dist = length(world_position.xz);
        float height = world_position.y;
        
        // Ocean at edges
        if (dist > 6000.0) {
            material_id = 4; // Sand (ocean floor)
        } else if (dist > 5500.0) {
            material_id = 4; // Sand (beach)
        } else if (height > 60.0) {
            material_id = 5; // Snow (mountain tops)
        } else if (height > 40.0) {
            material_id = 2; // Stone (mountains)
        } else if (height < 5.0) {
            material_id = 1; // Dirt (low areas)
        } else {
            material_id = 6; // Grass (normal terrain)
        }
    }
    
    // Clamp to valid range (0-6)
    material_id = clamp(material_id, 0, 6);
    
    // For blending, check if we're at a boundary using derivatives
    float mat_dx = dFdx(v_material_index);
    float mat_dy = dFdy(v_material_index);
    float mat_gradient = length(vec2(mat_dx, mat_dy));
    
    // Only blend at real material boundaries (gradient indicates different materials)
    bool at_boundary = mat_gradient > 0.3;
    
    // Get blend factor for transitions
    float blend_factor = fract(v_material_index);
    
    // Determine the two materials being blended
    int mat_low = int(floor(v_material_index));
    int mat_high = mat_low + 1;
    
    // Clamp material IDs to valid range (0-6)
    mat_low = clamp(mat_low, 0, 6);
    mat_high = clamp(mat_high, 0, 6);
    
    // Base colors for each material
    vec3 colors[7];
    colors[0] = air_color;
    colors[1] = dirt_color;
    colors[2] = stone_color;
    colors[3] = iron_ore_color;
    colors[4] = sand_color;
    colors[5] = snow_color;
    colors[6] = grass_color;
    
    // Roughness for each material
    float roughness_vals[7];
    roughness_vals[0] = dirt_roughness;
    roughness_vals[1] = dirt_roughness;
    roughness_vals[2] = stone_roughness;
    roughness_vals[3] = ore_roughness;
    roughness_vals[4] = sand_roughness;
    roughness_vals[5] = snow_roughness;
    roughness_vals[6] = grass_roughness;
    
    // Metallic for each material
    float metallic_vals[7];
    metallic_vals[0] = 0.0;
    metallic_vals[1] = 0.0;
    metallic_vals[2] = 0.0;
    metallic_vals[3] = ore_metallic;
    metallic_vals[4] = 0.0;
    metallic_vals[5] = 0.0;
    metallic_vals[6] = 0.0;
    
    // Noise scales for each material
    float noise_scales[7];
    noise_scales[0] = dirt_noise_scale;
    noise_scales[1] = dirt_noise_scale;
    noise_scales[2] = stone_noise_scale;
    noise_scales[3] = ore_noise_scale;
    noise_scales[4] = sand_noise_scale;
    noise_scales[5] = snow_noise_scale;
    noise_scales[6] = grass_noise_scale;
    
    // Calculate blended properties
    vec3 base_color;
    float mat_roughness;
    float mat_metallic;
    float noise_scale;
    
    if (at_boundary && mat_low != mat_high) {
        // Smooth blend between two materials at boundary
        // Use smoothstep for nicer transition
        float smooth_blend = smoothstep(0.0, 1.0, blend_factor);
        
        base_color = mix(colors[mat_low], colors[mat_high], smooth_blend);
        mat_roughness = mix(roughness_vals[mat_low], roughness_vals[mat_high], smooth_blend);
        mat_metallic = mix(metallic_vals[mat_low], metallic_vals[mat_high], smooth_blend);
        noise_scale = mix(noise_scales[mat_low], noise_scales[mat_high], smooth_blend);
    } else {
        // Single material - no blending needed
        base_color = colors[material_id];
        mat_roughness = roughness_vals[material_id];
        mat_metallic = metallic_vals[material_id];
        noise_scale = noise_scales[material_id];
    }
    
    // Apply procedural noise for visual detail
    float noise_value = fbm(world_position * noise_scale, 3);
    vec3 noise_color_offset = vec3(noise_value - 0.5) * noise_intensity * 2.0;
    
    // Height-based color variation (darker at depth, lighter at surface)
    float height_factor = clamp(world_position.y / 50.0, -1.0, 1.0);
    vec3 height_offset = vec3(height_factor * height_variation_strength);
    
    // Combine color with noise and height variation
    vec3 final_color = base_color + noise_color_offset + height_offset;
    final_color = clamp(final_color, vec3(0.0), vec3(1.0));
    
    // Apply ambient occlusion with minimum ambient contribution
    float ao = calculate_ao(flat_normal);
    final_color *= ao;
    
    // Add subtle ambient contribution to prevent complete darkness
    vec3 ambient_contribution = ambient_color * min_ambient_light * 0.3;
    final_color = final_color + ambient_contribution * (1.0 - ao);
    final_color = clamp(final_color, vec3(0.0), vec3(1.0));
    
    // Output
    ALBEDO = final_color;
    ROUGHNESS = mat_roughness;
    METALLIC = mat_metallic;
    
    // Ore emissive glow - check if ore is present
    float ore_presence = 0.0;
    if (at_boundary && (mat_low == 3 || mat_high == 3)) {
        // Blended ore
        if (mat_low == 3) ore_presence = 1.0 - blend_factor;
        if (mat_high == 3) ore_presence = blend_factor;
        ore_presence = smoothstep(0.0, 1.0, ore_presence);
    } else if (material_id == 3) {
        ore_presence = 1.0;
    }
    
    if (ore_presence > 0.01) {
        EMISSION = ore_emissive_color * ore_emissive_strength * ore_presence;
    }
}
