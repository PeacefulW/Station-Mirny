uniform sampler2D height_shadow_mask : filter_linear, repeat_disable;
uniform float height_shadow_caster_height = 1.0;
uniform float height_shadow_receiver_height = 1.0;
uniform float height_shadow_height_fade = 0.14;
uniform float height_shadow_strength = 0.0;
uniform vec3 height_shadow_tint = vec3(0.32, 0.34, 0.40);

vec3 apply_world_height_shadow(vec3 base_color, vec2 screen_uv) {
	if (height_shadow_strength <= 0.0001) {
		return base_color;
	}
	float height_delta = height_shadow_caster_height - height_shadow_receiver_height;
	float height_gate = smoothstep(
		0.0,
		max(height_shadow_height_fade, 0.0001),
		height_delta
	);
	float mask_alpha = texture(height_shadow_mask, screen_uv).a;
	float receive_amount = clamp(mask_alpha * height_shadow_strength * height_gate, 0.0, 1.0);
	return mix(base_color, base_color * height_shadow_tint, receive_amount);
}
