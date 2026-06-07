shader_type canvas_item;
render_mode blend_mix;

uniform float shadow_angle_rad = 0.0;
uniform float shadow_length_px = 0.0;
uniform float shadow_opacity = 0.0;
uniform float shadow_softness_px = 24.0;

varying vec4 instance_data;

void vertex() {
	instance_data = COLOR;
	float cos_a = cos(shadow_angle_rad);
	float sin_a = sin(shadow_angle_rad);
	float shadow_scale = max(instance_data.r * 4.0, 0.1);
	vec2 inverse_size = max(instance_data.gb, vec2(0.001));
	VERTEX += vec2(cos_a, sin_a) * shadow_length_px * shadow_scale * inverse_size;
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - vec2(1.0);
	float ellipse_distance = dot(centered_uv, centered_uv);
	float softness = clamp(shadow_softness_px / 128.0, 0.04, 0.45);
	float alpha = 1.0 - smoothstep(1.0 - softness, 1.0, ellipse_distance);
	COLOR = vec4(0.105, 0.082, 0.052, instance_data.a * shadow_opacity * alpha);
}
