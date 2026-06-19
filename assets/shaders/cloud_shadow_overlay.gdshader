shader_type canvas_item;
render_mode blend_mix;

// Бегущие тени облаков на земле. Полноэкранный мировой слой (как пыль):
// мягкие тёмные пятна, плотность и охват растут с cloud_cover (от
// WeatherRuntime), дрейф — по wind_* global uniforms. При ясном небе пусто.
// Презентация (ADR-0007 layer 4); живёт под Daylight.
//
// Поле берётся из БЕСШОВНОЙ шумовой текстуры с аппаратным повтором и мип-
// фильтрацией. Это устраняет сеточные артефакты точности, которые даёт
// ручной fract()-хеш на больших мировых координатах (тени locked к миру,
// поэтому world_pos большой) — текстура wrap'ается аппаратно на полной
// точности в пределах тайла.

global uniform vec2 wind_gust_scroll_px;
global uniform float wind_time;

uniform vec2 view_world_origin = vec2(0.0);
uniform vec2 view_world_size = vec2(1920.0, 1080.0);
uniform float cloud_cover = 0.0;
uniform vec3 cloud_shadow_color = vec3(0.10, 0.12, 0.18);
uniform float cloud_scale_px = 1700.0;
uniform float cloud_shadow_opacity = 0.62;
uniform float cloud_drift_px_per_s = 9.0;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;

float cloud_field(vec2 w) {
	// Многомасштабное поле с упором в МЕЛКИЕ детали: много дробных пятен, а не
	// одно низкочастотное на весь экран (иначе изолиния тени ползёт стеной
	// поперёк вида при смене порога во время перехода погоды).
	vec2 base = w / cloud_scale_px;
	float a = texture(cloud_noise, base).r;
	float b = texture(cloud_noise, base * 2.1 + vec2(0.31, 0.17)).r;
	float c = texture(cloud_noise, base * 4.3 + vec2(0.11, 0.53)).r;
	return a * 0.5 + b * 0.32 + c * 0.18;
}

void fragment() {
	if (cloud_cover < 0.02) {
		COLOR = vec4(0.0);
	} else {
		vec2 world_pos = view_world_origin + UV * view_world_size;
		// Облака плывут по ветру плюс собственный медленный ход.
		vec2 drift = wind_gust_scroll_px * 0.4
			+ vec2(wind_time * cloud_drift_px_per_s, wind_time * cloud_drift_px_per_s * 0.4);
		float field = cloud_field(world_pos - drift);
		// Узкий ход порога -> форма теней почти не меняется при переходе;
		// проявление ведёт ПРОЗРАЧНОСТЬ (cover_op), а не рост площади.
		float threshold = mix(0.62, 0.44, cloud_cover);
		float cover_op = smoothstep(0.02, 0.55, cloud_cover);
		float shadow = smoothstep(threshold - 0.13, threshold + 0.2, field) * cover_op;
		if (shadow <= 0.003) {
			COLOR = vec4(0.0);
		} else {
			COLOR = vec4(cloud_shadow_color, shadow * cloud_shadow_opacity);
		}
	}
}
