shader_type canvas_item;
render_mode blend_mix;

// Бегущие тени облаков на земле. Полноэкранный мировой shadow pass:
// крупные мягкие следы облаков живут в broken-light диапазоне: пик в cloudy,
// спад к overcast, где свет становится диффузным и отдельных теней нет.
// Дрейф — по wind_* global uniforms. При ясном/пасмурном небе слой пуст.
// Презентация (ADR-0007 layer 4); живёт под Daylight.
//
// Важно: слой НЕ рисует цветное пятно облака. Он читает уже отрисованную
// поверхность через screen_texture и возвращает затемнённую версию этой же
// картинки, как обычная Godot-тень от объектов.
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
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float cloud_scale_px = 6400.0;
uniform float cloud_shadow_opacity = 0.55;
uniform float cloud_shadow_darkening = 0.38;
uniform float cloud_drift_px_per_s = 9.0;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;

float weather_smoothstep(float edge0, float edge1, float value) {
	float t = clamp((value - edge0) / (edge1 - edge0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

float broken_cloud_strength(float cover) {
	return weather_smoothstep(0.15, 0.40, cover) * (1.0 - weather_smoothstep(0.62, 0.88, cover));
}

float cloud_field(vec2 w) {
	// Крупный footprint кучевых облаков с лёгкой внутренней мягкостью. Форма
	// почти не меняет площадь во время перехода; силу ведёт broken opacity.
	vec2 base = w / cloud_scale_px;
	float a = texture(cloud_noise, base).r;
	float b = texture(cloud_noise, base * 2.1 + vec2(0.31, 0.17)).r;
	float c = texture(cloud_noise, base * 4.3 + vec2(0.11, 0.53)).r;
	return a * 0.74 + b * 0.21 + c * 0.05;
}

void fragment() {
	float broken = broken_cloud_strength(clamp(cloud_cover, 0.0, 1.0));
	if (broken < 0.01) {
		COLOR = vec4(0.0);
	} else {
		vec2 world_pos = view_world_origin + UV * view_world_size;
		// Облака плывут по ветру плюс собственный медленный ход.
		vec2 drift = wind_gust_scroll_px * 0.4
			+ vec2(wind_time * cloud_drift_px_per_s, wind_time * cloud_drift_px_per_s * 0.4);
		float field = cloud_field(world_pos - drift);
		float threshold = 0.50;
		float shadow = smoothstep(threshold - 0.16, threshold + 0.28, field) * broken;
		if (shadow <= 0.003) {
			COLOR = vec4(0.0);
		} else {
			vec3 src = texture(screen_texture, SCREEN_UV).rgb;
			vec3 shadowed = src * (1.0 - cloud_shadow_darkening);
			COLOR = vec4(shadowed, shadow * cloud_shadow_opacity);
		}
	}
}
