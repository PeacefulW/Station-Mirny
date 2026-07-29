shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D anchor_lut : filter_nearest, repeat_disable;
uniform float atlas_columns = 1.0;
uniform float atlas_rows = 1.0;
uniform float atlas_frame_count = 1.0;
uniform vec2 frame_texel_size = vec2(0.0013020833);
uniform vec2 shadow_direction = vec2(0.887216, 0.461354);
uniform float shadow_length_scale = 1.0;
uniform float shadow_opacity = 0.0;
uniform vec2 output_uv_min = vec2(-0.10, -0.50);
uniform vec2 output_uv_max = vec2(1.70, 1.10);

varying vec4 instance_data;

void vertex() {
	instance_data = COLOR;
}

vec2 frame_uv(vec2 local_uv, float frame_index) {
	float safe_index = clamp(floor(frame_index + 0.5), 0.0, atlas_frame_count - 1.0);
	vec2 cell = vec2(mod(safe_index, atlas_columns), floor(safe_index / atlas_columns));
	vec2 half_texel = frame_texel_size * 0.5;
	return (cell + clamp(local_uv, half_texel, vec2(1.0) - half_texel)) / vec2(atlas_columns, atlas_rows);
}

void fragment() {
	float frame_index = floor(clamp(instance_data.r, 0.0, 1.0) * 255.0 + 0.5);
	float lut_u = (frame_index + 0.5) / max(atlas_frame_count, 1.0);
	vec2 anchor = texture(anchor_lut, vec2(lut_u, 0.5)).rg;
	vec2 output_point = mix(output_uv_min, output_uv_max, UV);
	vec2 direction = normalize(shadow_direction);
	vec2 delta = output_point - anchor;
	float forward_distance = dot(delta, direction);
	// Stretch only the projected side; the caster/root side stays glued to anchor.
	if (forward_distance > 0.0) {
		float safe_scale = max(shadow_length_scale, 0.001);
		delta -= direction * forward_distance * (1.0 - 1.0 / safe_scale);
	}
	vec2 source_uv = anchor + delta;
	if (any(lessThan(source_uv, vec2(0.0))) || any(greaterThan(source_uv, vec2(1.0)))) {
		discard;
	}
	vec4 shadow = texture(TEXTURE, frame_uv(source_uv, frame_index));
	float length_factor = clamp((shadow_length_scale - 1.0) / 0.85, 0.0, 1.0);
	float softness_texels = mix(0.75, 7.0, length_factor);
	vec2 perpendicular = vec2(-direction.y, direction.x);
	vec2 blur_offset = perpendicular * frame_texel_size * softness_texels;
	vec2 positive_uv = source_uv + blur_offset;
	vec2 negative_uv = source_uv - blur_offset;
	float positive_alpha = 0.0;
	float negative_alpha = 0.0;
	if (!any(lessThan(positive_uv, vec2(0.0))) && !any(greaterThan(positive_uv, vec2(1.0)))) {
		positive_alpha = texture(TEXTURE, frame_uv(positive_uv, frame_index)).a;
	}
	if (!any(lessThan(negative_uv, vec2(0.0))) && !any(greaterThan(negative_uv, vec2(1.0)))) {
		negative_alpha = texture(TEXTURE, frame_uv(negative_uv, frame_index)).a;
	}
	float softened_alpha = (
		shadow.a * 0.50
		+ positive_alpha * 0.25
		+ negative_alpha * 0.25
	);
	shadow.a = softened_alpha * clamp(shadow_opacity, 0.0, 1.0) * clamp(instance_data.a, 0.0, 1.0);
	COLOR = shadow;
}
