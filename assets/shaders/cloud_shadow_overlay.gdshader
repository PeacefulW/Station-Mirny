shader_type canvas_item;
render_mode blend_mix;

// Бегущие тени облаков на земле. Полноэкранный мировой слой (как пыль):
// мягкие тёмные fbm-пятна, плотность и охват растут с cloud_cover (от
// WeatherRuntime), дрейф — по wind_* global uniforms. При ясном небе пусто.
// Презентация (ADR-0007 layer 4); живёт под Daylight.

global uniform vec2 wind_gust_scroll_px;
global uniform float wind_time;

uniform vec2 view_world_origin = vec2(0.0);
uniform vec2 view_world_size = vec2(1920.0, 1080.0);
uniform float cloud_cover = 0.0;
uniform vec3 cloud_shadow_color = vec3(0.10, 0.12, 0.18);
uniform float cloud_scale_px = 1400.0;
uniform float cloud_shadow_opacity = 0.66;
uniform float cloud_drift_px_per_s = 9.0;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.6;
	for (int i = 0; i < 3; i++) {
		v += value_noise(p) * amp;
		p = p * 2.05 + vec2(7.7, -3.1);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	if (cloud_cover < 0.02) {
		COLOR = vec4(0.0);
	} else {
		vec2 world_pos = view_world_origin + UV * view_world_size;
		// Облака плывут по ветру плюс собственный медленный ход.
		vec2 drift = wind_gust_scroll_px * 0.55
			+ vec2(wind_time * cloud_drift_px_per_s, wind_time * cloud_drift_px_per_s * 0.4);
		vec2 p = (world_pos - drift) / max(cloud_scale_px, 1.0);
		float field = fbm(p) * 0.7 + fbm(p * 2.3 + vec2(31.0, 17.0)) * 0.3;
		// Гуще облачность -> ниже порог -> больше и плотнее теней.
		float threshold = mix(0.74, 0.28, cloud_cover);
		float shadow = smoothstep(threshold - 0.12, threshold + 0.18, field) * cloud_cover;
		if (shadow <= 0.003) {
			COLOR = vec4(0.0);
		} else {
			COLOR = vec4(cloud_shadow_color, shadow * cloud_shadow_opacity);
		}
	}
}
