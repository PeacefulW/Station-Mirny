shader_type canvas_item;
render_mode blend_mix;

// Летящая пыль как визуальный спидометр ветра. Полноэкранный слой над миром:
// плотность, длина стриков и яркость пыли растут с wind_strength, скролл —
// по тем же wind_* global uniforms, что трава (один источник ветра). При
// штиле пыль исчезает. Мировая привязка через view_world_* — пыль живёт в
// мире и дрейфует по ветру, а не липнет к экрану.

global uniform float wind_strength;
global uniform vec2 wind_direction;
global uniform vec2 wind_gust_scroll_px;

uniform vec2 view_world_origin = vec2(0.0);
uniform vec2 view_world_size = vec2(1920.0, 1080.0);
uniform vec3 dust_color = vec3(0.72, 0.58, 0.40);
uniform float dust_cell_px = 40.0;
uniform float dust_opacity = 0.72;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float strength = clamp(wind_strength, 0.0, 1.0);
	float gate = smoothstep(0.06, 0.42, strength);
	if (gate < 0.01) {
		COLOR = vec4(0.0);
	} else {
		vec2 world_pos = view_world_origin + UV * view_world_size;
		vec2 dir = normalize(wind_direction + vec2(0.0001, 0.0));
		// Пыль летит чуть быстрее травяных порывов — читается как поток.
		vec2 scrolled = world_pos - wind_gust_scroll_px * 1.35;
		float streak_len = mix(8.0, 54.0, strength);
		float density = mix(0.05, 0.42, strength);
		float dust = 0.0;
		// Стрик: несколько проб вверх по ветру, хвост гаснет -> motion-blur.
		const int STREAK = 5;
		for (int i = 0; i < STREAK; i++) {
			float k = float(i) / float(STREAK - 1);
			vec2 sp = scrolled + dir * k * streak_len;
			vec2 cell = floor(sp / dust_cell_px);
			vec2 f = fract(sp / dust_cell_px);
			float present = step(hash21(cell), density);
			vec2 pt = vec2(hash21(cell + vec2(1.3, 0.0)), hash21(cell + vec2(0.0, 7.7)));
			float d = length(f - pt);
			float mote = smoothstep(0.14, 0.0, d) * present;
			dust += mote * (1.0 - k * 0.85);
		}
		dust = clamp(dust, 0.0, 1.0) * gate;
		COLOR = vec4(dust_color, dust * dust_opacity);
	}
}
