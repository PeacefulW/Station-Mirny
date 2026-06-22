shader_type canvas_item;
render_mode blend_mix;

// Качание дерева от ОБЩИХ wind-глобалей (тех же, что трава: их пишет WindRuntime).
// Основание стоит (UV.y=1, локальный y=0), крона гнётся (UV.y=0, верх). Размах —
// доля высоты дерева; сила ветра управляет темпом/прижимом, не растягивает.
// Один материал на дерево и его тень-силуэт (тень наследует тот же сдвиг).

global uniform float wind_time;
global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform vec2 wind_gust_scroll_px;

uniform float sway_fraction = 0.11;
uniform float lean_fraction = 0.06;
uniform float gust_field_scale_px = 460.0;
uniform float gust_field_anisotropy = 2.4;

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
	vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vec2 dir = normalize(wind_direction + vec2(0.0001, 0.0));
	vec2 across = vec2(-dir.y, dir.x);
	vec2 gust_pos = world_pos - wind_gust_scroll_px;
	vec2 gust_uv = vec2(
		dot(gust_pos, dir) / max(gust_field_scale_px, 1.0),
		dot(gust_pos, across) / max(gust_field_scale_px * gust_field_anisotropy, 1.0)
	);
	float gust = smoothstep(0.4, 0.8, gradient_noise(gust_uv));
	float phase = hash12(floor(world_pos / 110.0)) * 6.28318530718;
	float primary = sin(wind_time * 0.55 + phase);
	float secondary = sin(wind_time * 0.95 + phase * 1.7);
	float gate = smoothstep(0.0, 0.12, wind_strength);
	float osc = (gust * (0.55 + primary * 0.5) + primary * 0.12 + secondary * 0.06) * sway_fraction;
	float lean = lean_fraction * smoothstep(0.30, 1.0, wind_strength) * sign(wind_direction.x + 0.0001);
	float weight = clamp(1.0 - UV.y, 0.0, 1.0);
	weight *= weight;
	float amount = (osc + lean) * gate * weight;
	// Высота над основанием в локальных px = -VERTEX.y (основание в локальном y=0).
	VERTEX.x += (-VERTEX.y) * amount;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = c * COLOR;
}
