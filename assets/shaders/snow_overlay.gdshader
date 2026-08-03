shader_type canvas_item;
render_mode blend_mix;

// View-bounded procedural snow. Flake placement is presentation-only and lives
// entirely in this one shader pass; WeatherRuntime supplies only intensity.
// Mirrors rain_overlay.gdshader: the bounded cell hash keeps every hash input
// small so large world coordinates cannot quantize the field into a grid.
//
// Snow differs from rain in behaviour, not structure: flakes are round rather
// than streaked, fall an order of magnitude slower, and drift sideways far more
// with wind, so the same wind that slants rain visibly carries snow across.

global uniform float wind_strength;
global uniform vec2 wind_direction;
global uniform vec2 wind_gust_scroll_px;

uniform vec2 view_world_origin = vec2(0.0);
uniform vec2 view_world_size = vec2(1920.0, 1080.0);
uniform float snow_intensity = 0.0;
uniform float snow_time_seconds = 0.0;
uniform vec4 snow_color : source_color = vec4(0.93, 0.95, 0.98, 0.85);

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float snow_layer(
	vec2 world_pos,
	float cell_size,
	float repeat_cells,
	float fall_speed,
	float wind_scroll_scale,
	float sway_amplitude,
	float sway_rate,
	float seed,
	float density,
	float radius
) {
	// Wrap before grid division and hashing, exactly like the rain pass.
	float period_px = cell_size * repeat_cells;
	vec2 wrapped_world = mod(world_pos, vec2(period_px));
	vec2 wrapped_wind = mod(wind_gust_scroll_px * wind_scroll_scale, vec2(period_px));
	float wrapped_fall = mod(snow_time_seconds * fall_speed, period_px);
	vec2 advected = mod(
		wrapped_world - wrapped_wind - vec2(0.0, wrapped_fall),
		vec2(period_px)
	);
	vec2 grid = advected / cell_size;
	vec2 cell = floor(grid);
	vec2 f = fract(grid);
	float presence = step(1.0 - density, hash21(cell + vec2(seed, seed * 1.73)));
	float center_x = mix(0.16, 0.84, hash21(cell + vec2(seed * 2.11, 7.31)));
	float center_y = mix(0.16, 0.84, hash21(cell + vec2(3.17, seed * 4.07)));
	// Per-flake phase so neighbours never sway in lockstep.
	float phase = hash21(cell + vec2(seed * 5.31, 1.97)) * 6.2831853;
	float sway = sin(snow_time_seconds * sway_rate + phase) * sway_amplitude;
	float dx = abs(fract(f.x - sway) - center_x);
	dx = min(dx, 1.0 - dx);
	float dy = abs(f.y - center_y);
	dy = min(dy, 1.0 - dy);
	float dist = length(vec2(dx, dy));
	float flake = 1.0 - smoothstep(radius * 0.45, radius, dist);
	return flake * presence;
}

void fragment() {
	float intensity = clamp(snow_intensity, 0.0, 1.0);
	if (intensity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 world_pos = view_world_origin + UV * view_world_size;
		float density = mix(0.05, 0.42, pow(intensity, 0.70));
		float wind_x = normalize(wind_direction + vec2(0.0001, 0.0)).x;
		float lateral = wind_x * clamp(wind_strength, 0.0, 1.0);
		float radius_scale = mix(0.85, 1.20, intensity);
		float near_snow = snow_layer(
			world_pos,
			56.0,
			251.0,
			62.0,
			2.60,
			0.055 + 0.075 * abs(lateral),
			1.15,
			13.0,
			density,
			0.115 * radius_scale
		);
		float far_snow = snow_layer(
			world_pos,
			84.0,
			257.0,
			41.0,
			1.70,
			0.040 + 0.055 * abs(lateral),
			0.83,
			53.0,
			density * 0.78,
			0.080 * radius_scale
		);
		float snow = clamp(max(near_snow, far_snow * 0.72), 0.0, 1.0);
		float alpha = snow * snow_color.a * mix(0.28, 1.0, sqrt(intensity));
		COLOR = vec4(snow_color.rgb, alpha);
	}
}
