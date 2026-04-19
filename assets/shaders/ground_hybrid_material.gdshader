shader_type canvas_item;

uniform sampler2D ground_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D ground_modulation_tex : repeat_enable, filter_linear;

uniform float ground_world_scale_px = 384.0;
uniform float macro_world_scale_px = 896.0;
uniform float modulation_strength = 0.12;
uniform float modulation_contrast = 1.08;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float remap_contrast(float value, float amount) {
	return clamp((value - 0.5) * amount + 0.5, 0.0, 1.0);
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (source.a < 0.01) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		vec2 base_uv = world_pos / ground_world_scale_px;
		vec2 secondary_uv = vec2(-world_pos.y, world_pos.x) / (ground_world_scale_px * 1.73) + vec2(0.37, 0.19);
		vec2 macro_uv = vec2(world_pos.y, world_pos.x) / macro_world_scale_px + vec2(0.11, 0.53);

		vec3 albedo_a = texture(ground_albedo_tex, base_uv).rgb;
		vec3 albedo_b = texture(ground_albedo_tex, secondary_uv).rgb;
		vec3 albedo = mix(albedo_a, albedo_b, 0.28);

		float micro = texture(ground_modulation_tex, base_uv).r;
		float macro = texture(ground_modulation_tex, macro_uv).r;
		float breakup = remap_contrast(mix(micro, macro, 0.34), modulation_contrast);
		float brightness = mix(1.0 - modulation_strength, 1.0 + modulation_strength, breakup);

		COLOR = vec4(albedo * brightness, source.a);
	}
}
