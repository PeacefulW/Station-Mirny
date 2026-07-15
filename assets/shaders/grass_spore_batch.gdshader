shader_type canvas_item;
render_mode blend_add;

// Светящиеся споры над оранжевым биополем: редкие дрейфующие мошки. Дрейф —
// по тем же wind_* global uniforms, что и трава (один источник ветра), плюс
// лёгкое кружение и мерцание. Аддитивное свечение.
// Буфер native: transform 2D + color = (phase, drift_seed, 0, alpha).

global uniform float wind_time;
global uniform vec2 wind_direction;
global uniform float wind_strength;

// Холодная биолюминесценция: на рыжем поле оранжевые споры тонут, а бирюзово
// -голубое свечение резко контрастирует и читается как чужой споровый дрейф.
uniform vec3 spore_color = vec3(0.50, 0.95, 0.92);
uniform float drift_px = 30.0;
uniform float bob_px = 11.0;
uniform int page_slot_mask = -1;
uniform float page_origin_x = 0.0;
uniform float page_slot_width_px = 1024.0;

varying vec4 instance_data;
varying float page_slot_active;

float is_page_slot_active(vec2 instance_world_origin) {
	if (page_slot_mask == -1) {
		return 1.0;
	}
	float slot_value = floor(
		(instance_world_origin.x - page_origin_x) / max(page_slot_width_px, 1.0)
	);
	if (slot_value < 0.0 || slot_value >= 32.0) {
		return 0.0;
	}
	uint slot_index = uint(slot_value);
	uint active_bits = uint(page_slot_mask);
	return (active_bits & (uint(1) << slot_index)) != uint(0) ? 1.0 : 0.0;
}

void vertex() {
	instance_data = COLOR;
	vec2 instance_world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	page_slot_active = is_page_slot_active(instance_world_origin);
	float phase = instance_data.r * 6.28318530718;
	float seed = instance_data.g;
	vec2 dir = normalize(wind_direction + vec2(0.0001, 0.0));
	float t = wind_time * (0.4 + seed * 0.6);
	vec2 drift = dir * (sin(t + phase) * 0.5 + 0.5) * drift_px * (0.45 + wind_strength * 0.8);
	drift += vec2(sin(t * 1.3 + phase), cos(t * 0.9 + phase * 1.7)) * bob_px;
	// VERTEX в пространстве квада до инстанс-трансформа. Спора — квадрат с
	// однородным масштабом без поворота, поэтому мировой сдвиг переводится в
	// локальный делением на размер споры.
	float spore_size = max(length(MODEL_MATRIX[0].xy), 0.001);
	VERTEX += drift / spore_size;
}

void fragment() {
	if (page_slot_active < 0.5) {
		discard;
	}
	float r = length(UV - vec2(0.5)) * 2.0;
	// Яркое ядро + мягкое гало: ядро пробивает дневной фон, гало читается ночью.
	float core = 1.0 - smoothstep(0.0, 0.45, r);
	float halo = 1.0 - smoothstep(0.0, 1.0, r);
	float glow = core * 1.4 + halo * halo * 0.6;
	float flicker = 0.6 + 0.4 * sin(wind_time * 3.0 + instance_data.r * 12.0);
	float a = glow * flicker * instance_data.a;
	if (a <= 0.002) {
		discard;
	}
	COLOR = vec4(spore_color * a, clamp(a, 0.0, 1.0));
}
