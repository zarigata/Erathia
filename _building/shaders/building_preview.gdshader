shader_type spatial;
render_mode unshaded, depth_draw_always, cull_disabled;

uniform vec3 valid_color : source_color = vec3(0.2, 0.9, 0.3);
uniform vec3 invalid_color : source_color = vec3(0.9, 0.2, 0.2);
uniform float alpha : hint_range(0.0, 1.0) = 0.6;
uniform float grid_scale : hint_range(0.1, 10.0) = 2.0;
uniform float grid_line_width : hint_range(0.01, 0.5) = 0.08;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.0;
uniform bool is_valid = true;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid_pattern(vec3 pos, float scale, float line_width) {
	vec3 grid = abs(fract(pos * scale - 0.5) - 0.5);
	vec3 lines = smoothstep(line_width, line_width * 0.5, grid);
	return max(max(lines.x, lines.y), lines.z);
}

void fragment() {
	// Choose color based on validity
	vec3 base_color = is_valid ? valid_color : invalid_color;
	
	// Fresnel effect for edge glow (X-ray skeleton look)
	float fresnel = pow(1.0 - abs(dot(world_normal, VIEW)), fresnel_power);
	
	// Grid pattern
	float grid = grid_pattern(world_pos, grid_scale, grid_line_width);
	
	// Pulse animation
	float pulse = sin(TIME * pulse_speed) * 0.15 + 0.85;
	
	// Combine effects
	float edge_intensity = fresnel * 0.6 + 0.4;
	float pattern_intensity = mix(0.3, 1.0, grid);
	
	// Final color with grid and fresnel
	ALBEDO = base_color * edge_intensity * pulse;
	ALPHA = alpha * pattern_intensity * pulse;
	
	// Add emission for glow effect
	EMISSION = base_color * fresnel * 0.5 * pulse;
}
