shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(0.0, 0.4, 0.8, 0.3);
uniform float amount : hint_range(0.0, 5.0) = 1.0; // Increased default for visibility
uniform float speed : hint_range(0.0, 10.0) = 2.0;
uniform float vignete_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float aberration : hint_range(0.0, 10.0) = 0.0; // Chromatic Aberration strength

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// Wobble effect
	vec2 offset = vec2(
		sin(uv.y * 10.0 + TIME * speed),
		cos(uv.x * 10.0 + TIME * speed)
	) * amount * 0.01;
	
	uv += offset;
	
	// Chromatic Aberration
	// Offset Red and Blue channels apart based on distance from center * aberration
	vec2 dist_from_center = uv - vec2(0.5);
	vec2 aber_offset = dist_from_center * aberration * 0.02;
	
	float r = texture(screen_texture, uv - aber_offset).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv + aber_offset).b;
	
	vec3 screen_col = vec3(r, g, b);
	
	// Vignette
	vec2 center_dist = UV - vec2(0.5);
	float vignette = 1.0 - dot(center_dist, center_dist) * vignete_intensity * 2.0;
	
	// Mix color with screen
	vec3 final_color = mix(screen_col, color.rgb, color.a);
	final_color *= vignette; // Apply vignette
	
	COLOR = vec4(final_color, 1.0);
}
