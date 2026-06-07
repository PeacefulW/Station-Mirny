shader_type canvas_item;
render_mode blend_mix;

uniform float shadow_angle_rad = 0.0;
uniform float shadow_length_px = 0.0;
uniform float shadow_opacity = 0.0;
uniform float shadow_softness_px = 24.0;

void vertex() {
	float cos_a = cos(shadow_angle_rad);
	float sin_a = sin(shadow_angle_rad);
	vec2 rotated = vec2(
		VERTEX.x * cos_a - VERTEX.y * sin_a,
		VERTEX.x * sin_a + VERTEX.y * cos_a
	);
	VERTEX = rotated + vec2(cos_a, sin_a) * shadow_length_px;
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - vec2(1.0);
	float ellipse_distance = dot(centered_uv, centered_uv);
	float softness = clamp(shadow_softness_px / 128.0, 0.04, 0.45);
	float alpha = 1.0 - smoothstep(1.0 - softness, 1.0, ellipse_distance);
	COLOR = vec4(0.025, 0.019, 0.014, COLOR.a * shadow_opacity * alpha);
}
