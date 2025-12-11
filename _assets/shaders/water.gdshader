shader_type spatial;

uniform vec3 albedo : source_color = vec3(0.0, 0.3, 0.5);
uniform vec3 albedo2 : source_color = vec3(0.0, 0.5, 0.7);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;
uniform float wave_direction = 1.0;
uniform float wave_direction2 = 1.0;
uniform float time_scale : hint_range(0.0, 0.2, 0.005) = 0.025;
uniform float noise_scale = 10.0;
uniform float height_scale = 0.15;

uniform vec4 color_deep : source_color = vec4(0.0, 0.1, 0.4, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.0, 0.6, 0.8, 1.0);
uniform float beers_law = 2.0;
uniform float depth_offset = -0.75;

uniform sampler2D wave;
uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;
uniform sampler2D depth_texture : hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture;

// Foam properties
uniform float edge_scale = 0.1;
uniform float near = 1.0;
uniform float far = 100.0;
uniform vec3 edge_color : source_color = vec3(1.0, 1.0, 1.0);

varying float height;
varying vec3 world_pos;

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height = texture(wave, world_pos.xz / noise_scale + TIME * time_scale).r;
	VERTEX.y += height * height_scale;
}

void fragment() {
	float depth_texture_raw = texture(depth_texture, SCREEN_UV).r;
	// Convert depth texture to linear depth
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_texture_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	
	// Depth Fade
	float depth = texture(depth_texture, SCREEN_UV).r;
	depth = depth * 2.0 - 1.0;
	depth = PROJECTION_MATRIX[3][2] / (depth + PROJECTION_MATRIX[2][2]);
	depth = depth + VERTEX.z;
	depth = exp(-depth * beers_law);
	depth = clamp(depth, 0.0, 1.0);
	
	float depth_blend = exp((linear_depth - FRAGCOORD.z + depth_offset) * -beers_law);
	depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
	float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

	// Normal Mapping
	vec2 time = (TIME * wave_direction) * time_scale * vec2(1.0, 0.0);
	vec2 time2 = (TIME * wave_direction2) * time_scale * vec2(0.0, 1.0);
	vec3 normal_blend = mix(texture(texture_normal, world_pos.xz / noise_scale + time).rgb, texture(texture_normal2, world_pos.xz / noise_scale + time2).rgb, 0.5);
	
	// Albedo
	vec3 color = mix(albedo, albedo2, height);
	color = mix(color, color_deep.rgb, depth_blend_power);
	
	// Foam - edge detection
	float z_depth = linear_depth;
	float z_pos = -VERTEX.z;
	float diff = z_depth - z_pos;
	
	// Add foam near shores
	if (diff < edge_scale) {
		color = mix(edge_color, color, diff / edge_scale);
	}
	
	ALBEDO = clamp(color + depth_blend_power * 0.1, vec3(0.0), vec3(1.0));
	METALLIC = metallic;
	ROUGHNESS = roughness;
	NORMAL_MAP = normal_blend;
	
	// Fresnel
	float fresnel_term = fresnel(5.0, NORMAL, VIEW);
	ALBEDO += fresnel_term * 0.1;
	ALPHA = mix(color_shallow.a, color_deep.a, depth_blend_power);
	ALPHA = clamp(ALPHA + depth_blend * 0.5, 0.0, 1.0);
}
