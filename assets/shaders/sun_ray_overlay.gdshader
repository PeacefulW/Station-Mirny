shader_type canvas_item;
render_mode blend_add;

// Rare cloudy sun-ray accents. These are visual shafts in direct-sun breaks,
// not gameplay light; they fade before overcast.

global uniform vec2 wind_gust_scroll_px;
global uniform float wind_time;

uniform vec2 view_world_origin = vec2(0.0);
uniform vec2 view_world_size = vec2(1920.0, 1080.0);
uniform float cloud_cover = 0.0;
uniform vec3 sun_ray_color = vec3(1.0, 0.82, 0.48);
uniform float sun_ray_opacity = 0.20;
uniform float ray_spacing_px = 920.0;
uniform sampler2D ray_noise : repeat_enable, filter_linear_mipmap;

float weather_smoothstep(float edge0, float edge1, float value) {
	float t = clamp((value - edge0) / (edge1 - edge0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

float broken_cloud_strength(float cover) {
	return weather_smoothstep(0.15, 0.40, cover) * (1.0 - weather_smoothstep(0.62, 0.88, cover));
}

float sun_ray_strength(float cover) {
	return broken_cloud_strength(cover) * (1.0 - weather_smoothstep(0.56, 0.70, cover));
}

void fragment() {
	float strength = sun_ray_strength(clamp(cloud_cover, 0.0, 1.0));
	if (strength < 0.01) {
		COLOR = vec4(0.0);
	} else {
		vec2 world_pos = view_world_origin + UV * view_world_size;
		vec2 drift = wind_gust_scroll_px * 0.16 + vec2(wind_time * 5.0, wind_time * 2.0);
		vec2 p = world_pos - drift;
		vec2 ray_axis = normalize(vec2(0.58, -0.82));
		vec2 ray_perp = vec2(-ray_axis.y, ray_axis.x);
		float across = dot(p, ray_perp);
		float band_wave = 0.5 + 0.5 * sin(across / ray_spacing_px * 6.2831853);
		float band = pow(weather_smoothstep(0.76, 1.0, band_wave), 1.25);
		float rare_patch = weather_smoothstep(0.54, 0.78, texture(ray_noise, p / 4300.0).r);
		float soft_break = weather_smoothstep(0.24, 0.72, texture(ray_noise, p / 1500.0 + vec2(0.19, 0.41)).r);
		float ray = band * rare_patch * soft_break;
		COLOR = vec4(sun_ray_color, ray * strength * sun_ray_opacity);
	}
}
