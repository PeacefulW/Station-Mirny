shader_type canvas_item;
render_mode blend_mix;

// Контактные тени-пятна под пучками травы. Плоский мягкий тёмный эллипс у
// корня; рисуется ниже всей лесенки травы, «прижимая» куст к земле.
// Буфер native: transform 2D + color, где color.a = базовая прозрачность.

uniform vec3 shadow_color = vec3(0.04, 0.03, 0.02);
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
}

void fragment() {
	if (page_slot_active < 0.5) {
		discard;
	}
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = (1.0 - smoothstep(0.35, 1.0, r)) * instance_data.a;
	if (a <= 0.002) {
		discard;
	}
	COLOR = vec4(shadow_color, a);
}
