shader_type canvas_item;
render_mode blend_mix;

// View-bounded procedural rain. Drop placement is presentation-only and lives
// entirely in this one shader pass; WeatherRuntime supplies only intensity.
// The bounded cell hash avoids precision artifacts at large world coordinates.

global uniform float wind_strength;
global uniform vec2 wind_direction;
global uniform vec2 wind_gust_scroll_px;

uniform vec2 view_world_origin = vec2(0.0);
uniform vec2 view_world_size = vec2(1920.0, 1080.0);
uniform float rain_intensity = 0.0;
uniform float rain_time_seconds = 0.0;
uniform vec4 rain_color : source_color = vec4(0.66, 0.78, 0.90, 0.72);

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float rain_layer(
	vec2 world_pos,
	float cell_size,
	float repeat_cells,
	float fall_speed,
	float wind_scroll_scale,
	float seed,
	float density,
	float half_length,
	float half_width,
	float shear
) {
	// Wrap positions before grid division and hashing. This keeps every hash
	// input small even when the camera or accumulated wind is far from origin.
	float period_px = cell_size * repeat_cells;
	vec2 wrapped_world = mod(world_pos, vec2(period_px));
	vec2 wrapped_wind = mod(wind_gust_scroll_px * wind_scroll_scale, vec2(period_px));
	float wrapped_fall = mod(rain_time_seconds * fall_speed, period_px);
	vec2 advected = mod(
		wrapped_world - wrapped_wind - vec2(0.0, wrapped_fall),
		vec2(period_px)
	);
	vec2 grid = advected / cell_size;
	vec2 cell = floor(grid);
	vec2 f = fract(grid);
	float presence = step(1.0 - density, hash21(cell + vec2(seed, seed * 1.73)));
	float center_x = mix(0.12, 0.88, hash21(cell + vec2(seed * 2.11, 7.31)));
	float center_y = mix(0.16, 0.84, hash21(cell + vec2(3.17, seed * 4.07)));
	float streak_x = fract(f.x - shear * (f.y - center_y));
	float dx = abs(streak_x - center_x);
	dx = min(dx, 1.0 - dx);
	float dy = abs(f.y - center_y);
	dy = min(dy, 1.0 - dy);
	float across = 1.0 - smoothstep(half_width * 0.35, half_width, dx);
	float along = 1.0 - smoothstep(half_length * 0.55, half_length, dy);
	return across * along * presence;
}

void fragment() {
	float intensity = clamp(rain_intensity, 0.0, 1.0);
	if (intensity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 world_pos = view_world_origin + UV * view_world_size;
		float density = mix(0.045, 0.46, pow(intensity, 0.72));
		float wind_x = normalize(wind_direction + vec2(0.0001, 0.0)).x;
		float shear = wind_x * clamp(wind_strength, 0.0, 1.0) * 0.34;
		float length_scale = mix(0.72, 1.28, intensity);
		float near_rain = rain_layer(
			world_pos,
			48.0,
			251.0,
			753.0,
			1.45,
			11.0,
			density,
			0.22 * length_scale,
			0.018,
			shear
		);
		float far_rain = rain_layer(
			world_pos,
			72.0,
			257.0,
			1156.5,
			0.92,
			47.0,
			density * 0.72,
			0.16 * length_scale,
			0.012,
			shear * 0.82
		);
		float rain = clamp(max(near_rain, far_rain * 0.78), 0.0, 1.0);
		float alpha = rain * rain_color.a * mix(0.22, 1.0, sqrt(intensity));
		COLOR = vec4(rain_color.rgb, alpha);
	}
}
