shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(0.0, 0.4, 0.8, 0.3);
uniform float amount : hint_range(0.0, 5.0) = 0.05;
uniform float speed : hint_range(0.0, 10.0) = 1.0;
uniform float vignete_intensity : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// Wobble effect
	uv.x += sin(uv.y * 10.0 + TIME * speed) * amount * 0.01;
	uv.y += cos(uv.x * 10.0 + TIME * speed) * amount * 0.01;
	
	vec4 screen_col = texture(screen_texture, uv);
	
	// Vignette
	vec2 center_dist = UV - vec2(0.5);
	float vignette = 1.0 - dot(center_dist, center_dist) * vignete_intensity * 2.0;
	
	// Mix color with screen
	vec3 final_color = mix(screen_col.rgb, color.rgb, color.a);
	final_color *= vignette; // Apply vignette
	
	COLOR = vec4(final_color, 1.0);
}
