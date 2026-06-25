shader_type canvas_item;
render_mode blend_mix, unshaded;

// Cloud Occlusion: видимые дрейфующие тучки-тени на земле (стиль Factorio).
// Мировой слой над визуалом мира, под HUD. Тянет грунт к холодной диффузной
// тьме там, где густо облако. Глобальный пасмурный мрак — у DaylightSystem.
//
// Поле — из БЕСШОВНОЙ шумовой текстуры (repeat + мипмапы): нет сеточных
// артефактов точности ручного fract()-хеша на больших мировых координатах.

global uniform vec2 wind_gust_scroll_px;

uniform vec2 view_world_origin = vec2(0.0);
uniform vec2 view_world_size = vec2(1920.0, 1080.0);
uniform float cloud_cover = 0.0;
uniform float cloud_occlusion = 0.0;
// Доля прямого солнца (0 ночью .. 1 днём): тень бывает только пока есть солнце.
uniform float sun_presence = 1.0;
// Тень дымчато-холодная серо-синяя, не угольно-чёрная.
uniform vec3 shadow_color = vec3(0.035, 0.045, 0.085);
uniform float shadow_opacity = 1.0;
// Масштаб одной тучки: КРУПНЫЕ блобы разных форм (тень от облака не бывает с
// человека) — при низком % их мало и между ними много солнца, к пасмурному
// сливаются.
uniform float cloud_scale_px = 4500.0;
// Дрейф МЕДЛЕННЫЙ и собственный (не gust-гребёнка травы): облака плывут
// величаво. От длины дня не зависит (wind копится в реальном времени).
uniform float cloud_scroll_scale = 0.13;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;

float weather_smoothstep(float edge0, float edge1, float value) {
	float t = clamp((value - edge0) / max(edge1 - edge0, 0.0001), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

float cloud_field(vec2 world_pos) {
	// Доминирует КРУПНАЯ форма (целое облако), средние/мелкие октавы лишь рвут
	// край в дымчатые клочья — блоб остаётся большим и цельным.
	vec2 base = world_pos / max(cloud_scale_px, 1.0);
	float a = texture(cloud_noise, base).r;
	float b = texture(cloud_noise, base * 2.1 + vec2(0.27, 0.13)).r;
	float c = texture(cloud_noise, base * 4.3 + vec2(0.61, 0.42)).r;
	return a * 0.70 + b * 0.22 + c * 0.08;
}

void fragment() {
	float cover = clamp(cloud_cover, 0.0, 1.0);
	// Низкий % -> редкие отдельные тучки; рост % опускает порог -> облака
	// крупнеют и сливаются в сплошную пасмурность.
	float coverage = weather_smoothstep(0.06, 1.0, cover);
	// Слой почти не гаснет: смыкание тучек И ЕСТЬ пасмурный мрак (плюс глобальный
	// солнце-димминг сверху). Лёгкий спад лишь у самого верха, чтоб не в уголь.
	float overcast_fade = 1.0 - weather_smoothstep(0.95, 1.0, cover) * 0.3;
	if (coverage <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 world_pos = view_world_origin + UV * view_world_size;
		vec2 drift = wind_gust_scroll_px * cloud_scroll_scale;
		float field = cloud_field(world_pos - drift);
		// Высокий порог при низком % -> только редкие пики поля = мало больших
		// блобов с широкими солнечными промежутками. Падает -> растут и СЛИВАЮТСЯ.
		float threshold = mix(0.78, 0.14, coverage);
		float edge = mix(0.08, 0.14, coverage);
		float patch = weather_smoothstep(threshold - edge, threshold + edge, field);
		float peak = mix(0.42, 0.58, coverage);
		float alpha = clamp(patch * peak * overcast_fade * shadow_opacity * sun_presence, 0.0, 0.66);
		COLOR = vec4(shadow_color, alpha);
	}
}
