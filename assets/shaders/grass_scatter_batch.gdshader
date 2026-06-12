shader_type canvas_item;
render_mode blend_mix;

// Общий шейдер пучков травы (рантайм-чанки и dev-сцена). Источник ветра — wind_* global uniforms,
// которые пишет WindRuntime (один писатель, ноль per-frame рассылок).
// Порывы — скроллящееся апериодичное поле gradient noise (та же семья шума,
// что поля ground_hybrid_material.gdshader): синус-фронты дают периодичную
// «зебру» на дальнем зуме и запрещены спекой.
// Контракт: docs/02_system_specs/world/wind_and_grass_scatter_presentation.md (v0.4)

global uniform float wind_time;
global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform vec2 wind_gust_scroll_px;

uniform float atlas_columns = 4.0;
uniform float atlas_rows = 4.0;
uniform float atlas_frame_count = 16.0;
// Размах колебаний верхушки как ДОЛЯ высоты пучка. Сила ветра колебательный
// размах не умножает — она управляет темпом (wind_time / wind_gust_scroll_px).
uniform float wind_sway_fraction = 0.085;
// Штормовой прижим: статический наклон по ветру, растёт с силой от
// storm_lean_start до авторского предела-доли высоты. Не множитель колебаний.
uniform float storm_lean_fraction = 0.35;
uniform float storm_lean_start = 0.45;
uniform float gust_field_scale_px = 420.0;
uniform float gust_field_anisotropy = 2.6;
uniform float gust_contrast_low = 0.42;
uniform float gust_contrast_high = 0.80;
uniform float alpha_cutoff = 0.02;
// Диагностика проб: 1.0 — рисовать значение gust-поля яркостью вместо травы.
uniform float debug_gust_view = 0.0;

varying vec4 instance_data;
varying float gust_value;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 random_gradient(vec2 p) {
	vec2 h = vec2(hash12(p), hash12(p + vec2(17.31, -41.77))) * 2.0 - 1.0;
	return normalize(h + vec2(0.001, -0.001));
}

float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(random_gradient(i), f);
	float b = dot(random_gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(random_gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(random_gradient(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return clamp(mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.42 * 0.5 + 0.5, 0.0, 1.0);
}

void vertex() {
	instance_data = COLOR;
	vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vec2 dir = normalize(wind_direction + vec2(0.0001, 0.0));
	vec2 across = vec2(-dir.y, dir.x);
	// Анизотропное поле порывов: сжато вдоль ветра, растянуто поперёк —
	// фронты читаются как вытянутые волны, бегущие по ветру. Скролл —
	// аккумулированный offset от WindRuntime, не dir * t (рвётся при дрейфе).
	vec2 gust_pos = world_pos - wind_gust_scroll_px;
	vec2 gust_uv = vec2(
		dot(gust_pos, dir) / max(gust_field_scale_px, 1.0),
		dot(gust_pos, across) / max(gust_field_scale_px * gust_field_anisotropy, 1.0)
	);
	float gust = smoothstep(gust_contrast_low, gust_contrast_high, gradient_noise(gust_uv));
	gust_value = gust;
	float wind_phase = instance_data.b * 6.28318530718;
	float primary = sin(wind_time * 0.92 + wind_phase);
	float flutter = sin(wind_time * 1.45 + wind_phase * 1.73 + UV.y * 1.30);
	float blade_weight = smoothstep(0.05, 1.0, UV.y);
	// Трепет масштабируется самим порывом: вне фронта трава почти неподвижна,
	// иначе фоновое колебание топит фронты и порывы перестают читаться.
	float ambient = primary * 0.07 + flutter * 0.05;
	float gust_sway = gust * (0.85 + primary * 0.30 + flutter * 0.18);
	// Сила ветра НЕ умножает колебательный размах (это «растягивало» траву в
	// волосы) — она ускоряет темп в WindRuntime и добавляет ограниченный
	// прижим storm_lean. Прижим «дышит»: трава ходит туда-сюда вокруг
	// прижатой позы в пределах его же ограниченной доли. Гейт глушит штиль.
	float amplitude_gate = smoothstep(0.0, 0.15, wind_strength);
	float storm_wobble = sin(wind_time * 2.3 + wind_phase * 1.31) * 0.22
		+ sin(wind_time * 3.7 + wind_phase) * 0.10;
	float storm_lean = storm_lean_fraction
		* smoothstep(storm_lean_start, 1.0, wind_strength)
		* (1.0 + storm_wobble);
	float oscillation = (gust_sway + ambient) * wind_sway_fraction;
	float sway_fraction = (oscillation + storm_lean) * amplitude_gate;
	// VERTEX живёт в пространстве квада ДО инстанс-трансформа: «пиксельное»
	// смещение здесь умножалось бы на размер пучка (источник растяжения).
	// Считаем мировое смещение в долях высоты пучка и заводим его обратно
	// в локальные координаты инверсией 2x2-части модели.
	mat2 model_2x2 = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
	float det = model_2x2[0].x * model_2x2[1].y - model_2x2[1].x * model_2x2[0].y;
	float safe_det = abs(det) > 0.000001 ? det : 0.000001;
	mat2 inv_model_2x2 = mat2(
		vec2(model_2x2[1].y, -model_2x2[0].y),
		vec2(-model_2x2[1].x, model_2x2[0].x)
	) / safe_det;
	float tuft_height_px = length(MODEL_MATRIX[1].xy);
	vec2 world_offset = dir * sway_fraction * tuft_height_px * blade_weight * blade_weight;
	VERTEX += inv_model_2x2 * world_offset;
}

void fragment() {
	if (debug_gust_view > 0.5) {
		COLOR = vec4(gust_value, gust_value, gust_value, 1.0);
	} else {
	float frame_index = floor(clamp(instance_data.r * 255.0 + 0.5, 0.0, atlas_frame_count - 1.0));
	float frame_x = mod(frame_index, atlas_columns);
	float frame_y = floor(frame_index / atlas_columns);
	vec2 atlas_cell_size = vec2(1.0 / atlas_columns, 1.0 / atlas_rows);
	vec2 atlas_sample_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 atlas_uv = (vec2(frame_x, frame_y) + atlas_sample_uv) * atlas_cell_size;
	vec4 atlas_color = texture(TEXTURE, atlas_uv);
	if (atlas_color.a <= alpha_cutoff) {
		discard;
	}
	float tint = clamp(instance_data.g, 0.0, 1.35);
	COLOR = vec4(atlas_color.rgb * tint, atlas_color.a * instance_data.a);
	}
}
