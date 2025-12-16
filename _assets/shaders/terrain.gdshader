shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================
// PROCEDURAL TERRAIN SHADER
// ============================================
// Features:
// - Triplanar mapping (no texture stretching on slopes)
// - Height-based material blending (beach, grass, rock, snow)
// - Slope-based snow avoidance (snow only on flat surfaces)
// - Procedural noise variation (breaks up repetition)
// - Biome color tinting support
// ============================================

// Height thresholds
uniform float beach_max_height : hint_range(0.0, 20.0) = 8.0;
uniform float grass_max_height : hint_range(10.0, 80.0) = 45.0;
uniform float rock_max_height : hint_range(20.0, 100.0) = 70.0;
uniform float snow_min_height : hint_range(30.0, 120.0) = 65.0;

// Slope thresholds
uniform float snow_slope_threshold : hint_range(0.0, 1.0) = 0.7;  // dot with UP (1 = flat, 0 = vertical)
uniform float cliff_slope_threshold : hint_range(0.0, 1.0) = 0.5;

// Base colors
uniform vec3 sand_color : source_color = vec3(0.85, 0.75, 0.55);
uniform vec3 grass_color : source_color = vec3(0.25, 0.55, 0.15);
uniform vec3 grass_dark_color : source_color = vec3(0.15, 0.4, 0.1);
uniform vec3 rock_color : source_color = vec3(0.4, 0.38, 0.35);
uniform vec3 rock_dark_color : source_color = vec3(0.3, 0.28, 0.25);
uniform vec3 snow_color : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 dirt_color : source_color = vec3(0.45, 0.32, 0.18);

// Triplanar scale
uniform float triplanar_scale : hint_range(0.01, 2.0) = 0.25;

// Noise parameters
uniform float noise_scale : hint_range(0.001, 0.5) = 0.05;
uniform float color_variation : hint_range(0.0, 0.5) = 0.15;
uniform float detail_noise_scale : hint_range(0.1, 5.0) = 1.5;

// Material properties
uniform float rock_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float grass_roughness : hint_range(0.0, 1.0) = 0.95;
uniform float snow_roughness : hint_range(0.0, 1.0) = 0.7;

varying vec3 world_pos;
varying vec3 world_normal;

// ============================================
// NOISE FUNCTIONS
// ============================================

// Simple hash function
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Value noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);  // Smoothstep
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion (multi-octave noise)
float fbm(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// 3D noise for volumetric effects
float noise3d(vec3 p) {
    return noise(p.xz + p.y * 17.3);
}

// ============================================
// TRIPLANAR MAPPING
// ============================================

vec3 triplanar_color(vec3 pos, vec3 normal, vec3 base_color, float variation_amount) {
    // Blend weights based on normal direction
    vec3 blend = abs(normal);
    blend = normalize(max(blend, 0.00001));
    float b = (blend.x + blend.y + blend.z);
    blend /= b;
    
    // Sample noise on each axis
    float noise_xy = fbm(pos.xy * triplanar_scale, 3);
    float noise_xz = fbm(pos.xz * triplanar_scale, 3);
    float noise_yz = fbm(pos.yz * triplanar_scale, 3);
    
    // Blend the noise samples
    float final_noise = noise_xy * blend.z + noise_xz * blend.y + noise_yz * blend.x;
    
    // Apply color variation
    vec3 varied_color = base_color + (final_noise - 0.5) * variation_amount;
    return clamp(varied_color, 0.0, 1.0);
}

// ============================================
// VERTEX SHADER
// ============================================

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// ============================================
// FRAGMENT SHADER
// ============================================

void fragment() {
    float height = world_pos.y;
    vec3 normal = normalize(world_normal);
    
    // Calculate slope (dot product with UP)
    float slope = dot(normal, vec3(0.0, 1.0, 0.0));
    
    // Detail noise for breaking up patterns
    float detail = fbm(world_pos.xz * detail_noise_scale, 2);
    float micro_detail = noise(world_pos.xz * 10.0);
    
    // ========================================
    // MATERIAL SELECTION
    // ========================================
    
    vec3 final_color;
    float final_roughness;
    
    // Beach/Sand (low altitude)
    if (height < beach_max_height) {
        float sand_mix = smoothstep(0.0, beach_max_height, height);
        vec3 sand = triplanar_color(world_pos, normal, sand_color, color_variation * 0.5);
        vec3 wet_sand = sand * 0.7;  // Darker near water
        final_color = mix(wet_sand, sand, sand_mix);
        final_roughness = 0.9;
    }
    // Grass zone
    else if (height < grass_max_height) {
        float grass_blend = smoothstep(beach_max_height, beach_max_height + 5.0, height);
        
        // Mix grass with dirt based on noise
        vec3 grass = triplanar_color(world_pos, normal, grass_color, color_variation);
        vec3 grass_dark = triplanar_color(world_pos, normal, grass_dark_color, color_variation * 0.8);
        vec3 dirt = triplanar_color(world_pos, normal, dirt_color, color_variation * 0.6);
        
        // Grass patches
        float grass_pattern = fbm(world_pos.xz * 0.15, 4);
        vec3 grass_mixed = mix(grass_dark, grass, grass_pattern);
        
        // Dirt patches in grass
        float dirt_pattern = smoothstep(0.3, 0.35, noise(world_pos.xz * 0.08));
        grass_mixed = mix(grass_mixed, dirt, dirt_pattern * 0.4);
        
        // Blend from sand to grass
        vec3 sand = triplanar_color(world_pos, normal, sand_color, color_variation * 0.5);
        final_color = mix(sand, grass_mixed, grass_blend);
        final_roughness = grass_roughness;
        
        // Steep slopes get rock
        if (slope < cliff_slope_threshold) {
            vec3 rock = triplanar_color(world_pos, normal, rock_color, color_variation);
            float rock_blend = smoothstep(cliff_slope_threshold, cliff_slope_threshold - 0.2, slope);
            final_color = mix(final_color, rock, rock_blend);
            final_roughness = mix(final_roughness, rock_roughness, rock_blend);
        }
    }
    // Rock/Mountain zone
    else if (height < rock_max_height) {
        float rock_blend = smoothstep(grass_max_height, grass_max_height + 10.0, height);
        
        vec3 rock = triplanar_color(world_pos, normal, rock_color, color_variation * 0.7);
        vec3 rock_d = triplanar_color(world_pos, normal, rock_dark_color, color_variation * 0.5);
        
        // Rock layering
        float layer_pattern = noise(world_pos.xz * 0.3 + height * 0.1);
        vec3 rock_mixed = mix(rock_d, rock, layer_pattern);
        
        // Grass remnants on flat areas
        vec3 grass = triplanar_color(world_pos, normal, grass_color, color_variation);
        if (slope > 0.8) {
            float grass_patch = smoothstep(0.55, 0.65, noise(world_pos.xz * 0.2));
            rock_mixed = mix(rock_mixed, grass * 0.8, grass_patch * 0.5);
        }
        
        vec3 grass_base = triplanar_color(world_pos, normal, grass_color, color_variation);
        final_color = mix(grass_base, rock_mixed, rock_blend);
        final_roughness = rock_roughness;
    }
    // Snow zone (only on flat surfaces!)
    else {
        float snow_blend = smoothstep(snow_min_height, snow_min_height + 10.0, height);
        
        vec3 rock = triplanar_color(world_pos, normal, rock_color, color_variation * 0.5);
        vec3 snow = triplanar_color(world_pos, normal, snow_color, color_variation * 0.2);
        
        // Snow sparkle effect
        float sparkle = step(0.98, noise(world_pos.xz * 50.0)) * 0.3;
        snow += sparkle;
        
        // Apply snow only on flat surfaces
        if (slope > snow_slope_threshold) {
            // Snow accumulation based on flatness
            float snow_amount = smoothstep(snow_slope_threshold, 1.0, slope);
            snow_amount *= snow_blend;
            
            // Add some noise to snow edge
            float snow_edge_noise = noise(world_pos.xz * 2.0) * 0.2;
            snow_amount = clamp(snow_amount + snow_edge_noise - 0.1, 0.0, 1.0);
            
            final_color = mix(rock, snow, snow_amount);
            final_roughness = mix(rock_roughness, snow_roughness, snow_amount);
        } else {
            // Steep areas stay rocky
            vec3 rock_d = triplanar_color(world_pos, normal, rock_dark_color, color_variation);
            float rock_pattern = noise(world_pos.xz * 0.4);
            final_color = mix(rock_d, rock, rock_pattern);
            final_roughness = rock_roughness;
        }
    }
    
    // ========================================
    // FINAL OUTPUT
    // ========================================
    
    ALBEDO = final_color;
    ROUGHNESS = final_roughness;
    METALLIC = 0.0;
    
    // Do not override NORMAL. 
    // Godot automatically interpolates the Vertex Normal (smooth) and passes it to the fragment shader in View Space.
    // Overriding it with World Space normal causes incorrect lighting (faceted/flat look).
}
