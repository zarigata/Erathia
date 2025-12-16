shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec3 u_color0 : source_color = vec3(0.02, 0.05, 0.12);
uniform vec3 u_color1 : source_color = vec3(0.08, 0.20, 0.55);
uniform vec3 u_color2 : source_color = vec3(0.85, 0.78, 0.55);
uniform vec3 u_color3 : source_color = vec3(0.35, 0.65, 0.25);
uniform vec3 u_color4 : source_color = vec3(0.12, 0.45, 0.16);
uniform vec3 u_color5 : source_color = vec3(0.18, 0.30, 0.12);
uniform vec3 u_color6 : source_color = vec3(0.88, 0.82, 0.55);
uniform vec3 u_color7 : source_color = vec3(0.55, 0.70, 0.20);
uniform vec3 u_color8 : source_color = vec3(0.05, 0.45, 0.18);
uniform vec3 u_color9 : source_color = vec3(0.85, 0.90, 0.95);
uniform vec3 u_color10 : source_color = vec3(0.40, 0.40, 0.40);
uniform vec3 u_color11 : source_color = vec3(0.92, 0.96, 1.00);
uniform vec3 u_color12 : source_color = vec3(0.25, 0.18, 0.18);
uniform vec3 u_color13 : source_color = vec3(0.45, 0.20, 0.55);

uniform float u_variation: float = 0.08;
uniform float u_noise_scale: float = 0.02;

varying float v_biome_index;

vec4 decode_8bit_vec4(uint i) {
	return vec4(
		float(i & uint(0xff)),
		float((i >> uint(8)) & uint(0xff)),
		float((i >> uint(16)) & uint(0xff)),
		float((i >> uint(24)) & uint(0xff)));
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

vec3 biome_color(float idx) {
	int i = int(clamp(idx, 0.0, 13.0));
	if (i == 0) return u_color0;
	if (i == 1) return u_color1;
	if (i == 2) return u_color2;
	if (i == 3) return u_color3;
	if (i == 4) return u_color4;
	if (i == 5) return u_color5;
	if (i == 6) return u_color6;
	if (i == 7) return u_color7;
	if (i == 8) return u_color8;
	if (i == 9) return u_color9;
	if (i == 10) return u_color10;
	if (i == 11) return u_color11;
	if (i == 12) return u_color12;
	return u_color13;
}

void vertex() {
	// CUSTOM1.x contains packed indices, CUSTOM1.y contains packed weights
	// Transvoxel packs 4 texture indices as bytes in CUSTOM1.x
	uint packed_indices = floatBitsToUint(CUSTOM1.x);
	vec4 indices = decode_8bit_vec4(packed_indices);
	// Use the first index (most dominant texture)
	v_biome_index = indices.x;
}

void fragment() {
	vec3 col = biome_color(v_biome_index);
	float n = hash3(floor(WORLD_POSITION.xyz * (1.0 / max(u_noise_scale, 0.0001))));
	col *= 1.0 + (n - 0.5) * 2.0 * u_variation;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
