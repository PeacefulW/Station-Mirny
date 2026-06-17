shader_type canvas_item;
render_mode blend_mix;

// Контактные тени-пятна под пучками травы. Плоский мягкий тёмный эллипс у
// корня; рисуется ниже всей лесенки травы, «прижимая» куст к земле.
// Буфер native: transform 2D + color, где color.a = базовая прозрачность.

uniform vec3 shadow_color = vec3(0.04, 0.03, 0.02);

varying vec4 instance_data;

void vertex() {
	instance_data = COLOR;
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = (1.0 - smoothstep(0.35, 1.0, r)) * instance_data.a;
	if (a <= 0.002) {
		discard;
	}
	COLOR = vec4(shadow_color, a);
}
