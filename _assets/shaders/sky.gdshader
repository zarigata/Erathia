shader_type sky;

// Day Colors
uniform vec3 day_top_color : source_color = vec3(0.35, 0.65, 0.85);
uniform vec3 day_horizon_color : source_color = vec3(0.6, 0.75, 0.9);

// Night Colors
uniform vec3 night_top_color : source_color = vec3(0.02, 0.0, 0.04);
uniform vec3 night_horizon_color : source_color = vec3(0.1, 0.0, 0.2);

// Horizon
uniform float horizon_blur : hint_range(0.0, 1.0) = 0.05;

// Sun
uniform vec3 sun_color : source_color = vec3(10.0, 8.0, 1.0);
uniform float sun_size : hint_range(0.01, 1.0) = 0.04;
uniform float sun_blur : hint_range(0.01, 10.0) = 0.01;

// Clouds
uniform sampler2D cloud_noise;
uniform vec3 cloud_color_day : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_color_night : source_color = vec3(0.1, 0.1, 0.1);
uniform float cloud_scale = 0.4;
uniform float cloud_speed = 0.01;
uniform float cloud_threshold = 0.4;

// Stars
uniform float star_intensity : hint_range(0.0, 5.0) = 1.0;
uniform float star_scale : hint_range(0.0, 1000.0) = 100.0;

// random function for stars
float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void sky() {
	vec3 dir = EYEDIR;
	
	// 1. Calculate Day/Night Factor based on Sun Height (LIGHT0_DIRECTION.y)
	// We assume the main light is the sun.
	float sun_height = LIGHT0_DIRECTION.y;
	float day_factor = clamp(sun_height * 2.5 + 0.5, 0.0, 1.0); // Transitions nicely around horizon
	
	// 2. Base Sky Gradient
	vec3 day_grad = mix(day_horizon_color, day_top_color, clamp(dir.y, 0.0, 1.0));
	vec3 night_grad = mix(night_horizon_color, night_top_color, clamp(dir.y, 0.0, 1.0));
	vec3 sky_color = mix(night_grad, day_grad, day_factor);
	
	// 3. Stars (Night only)
	if (day_factor < 0.9) {
		vec2 star_uv = dir.xz / (dir.y + 1.2); // Simple projection
		if (dir.y <= 0.0) star_uv = dir.xz; // Fix for below horizon
		
		float star_val = random(floor(star_uv * star_scale));
		if (star_val > 0.99) {
			float brightness = (star_val - 0.99) * 100.0 * star_intensity;
			// Twinkle
			brightness *= (0.8 + 0.2 * sin(TIME * 5.0 + star_val * 100.0));
			// Fade out during day
			brightness *= (1.0 - day_factor);
			sky_color += vec3(brightness);
		}
	}

	// 4. Clouds (Procedural)
	if (dir.y > 0.0) {
		vec2 sky_uv = (dir.xz / (dir.y + 0.15)) * cloud_scale + TIME * cloud_speed;
		float noise_val = texture(cloud_noise, sky_uv).r;
		
		float cloud_alpha = smoothstep(cloud_threshold - 0.1, cloud_threshold + 0.1, noise_val);
		cloud_alpha = clamp(cloud_alpha * 2.0, 0.0, 1.0); // Boost density
		
		// Cloud Color adapts to time
		vec3 cloud_col = mix(cloud_color_night, cloud_color_day, day_factor);
		
		// Fade near horizon
		cloud_alpha *= clamp(dir.y * 2.5, 0.0, 1.0);

		sky_color = mix(sky_color, cloud_col, cloud_alpha);
	}
	
	// 5. Sun Disk
	float sun_angle = acos(dot(LIGHT0_DIRECTION, dir));
	if (sun_angle < sun_size) {
		float sun_mask = 1.0 - smoothstep(sun_size - sun_blur, sun_size, sun_angle);
		sky_color += sun_color * sun_mask * day_factor; // Sun fades at night (optional, or keep it as moon)
	}

	COLOR = sky_color;
}
