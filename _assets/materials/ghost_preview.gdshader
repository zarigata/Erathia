shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

uniform vec4 valid_color : source_color = vec4(0.3, 1.0, 0.4, 0.6);
uniform vec4 invalid_color : source_color = vec4(1.0, 0.3, 0.3, 0.6);
uniform bool is_valid = true;
uniform float fresnel_power : hint_range(0.0, 5.0) = 2.0;
uniform float grid_scale : hint_range(0.0, 10.0) = 4.0;

void fragment() {
	vec4 base_color = is_valid ? valid_color : invalid_color;
	
	// Fresnel rim lighting
	float fresnel = pow(1.0 - dot(NORMAL, VIEW), fresnel_power);
	
	// Optional grid pattern
	vec2 grid_uv = UV * grid_scale;
	float grid = step(0.9, fract(grid_uv.x)) + step(0.9, fract(grid_uv.y));
	grid = clamp(grid, 0.0, 1.0);
	
	ALBEDO = base_color.rgb + vec3(fresnel * 0.3) + vec3(grid * 0.2);
	ALPHA = base_color.a + fresnel * 0.2;
	EMISSION = base_color.rgb * 0.5;
}
