shader_type canvas_item;

uniform sampler2D shape_normal_atlas : filter_nearest;
uniform sampler2D top_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D face_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D top_modulation : repeat_enable, filter_linear;
uniform sampler2D face_modulation : repeat_enable, filter_linear;
uniform sampler2D top_normal_tex : repeat_enable, filter_linear;
uniform sampler2D face_normal_tex : repeat_enable, filter_linear;

uniform float top_world_scale_px = 384.0;
uniform float face_world_scale_px = 224.0;
uniform float macro_world_scale_px = 896.0;
uniform float modulation_strength = 0.12;
uniform float modulation_contrast = 1.08;
uniform float back_rim_darkening = 0.94;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float remap_contrast(float value, float amount) {
	return clamp((value - 0.5) * amount + 0.5, 0.0, 1.0);
}

vec3 unpack_normal(vec3 packed_normal) {
	return normalize(packed_normal * 2.0 - 1.0);
}

vec3 blend_normals(vec3 base_normal, vec3 detail_normal) {
	return normalize(vec3(base_normal.xy + detail_normal.xy, max(0.001, base_normal.z * detail_normal.z)));
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	if (mask.a < 0.01) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	} else {
		float top_mask = smoothstep(0.02, 0.2, mask.r);
		float face_mask = smoothstep(0.02, 0.2, mask.g);
		float back_mask = smoothstep(0.02, 0.2, mask.b);
		float total_mask = max(top_mask + face_mask + back_mask, 0.001);

		vec2 top_uv = world_pos / top_world_scale_px;
		vec2 top_uv_secondary = vec2(-world_pos.y, world_pos.x) / (top_world_scale_px * 1.73) + vec2(0.37, 0.19);
		vec2 face_uv = vec2(world_pos.x / face_world_scale_px, world_pos.y / (face_world_scale_px * 0.72));
		vec2 macro_uv = vec2(world_pos.y, world_pos.x) / macro_world_scale_px + vec2(0.11, 0.53);

		vec3 top_albedo = mix(
			texture(top_albedo_tex, top_uv).rgb,
			texture(top_albedo_tex, top_uv_secondary).rgb,
			0.28
		);
		float top_micro = texture(top_modulation, top_uv).r;
		float top_macro = texture(top_modulation, macro_uv).r;
		float top_breakup = remap_contrast(mix(top_micro, top_macro, 0.34), modulation_contrast);
		float top_brightness = mix(1.0 - modulation_strength, 1.0 + modulation_strength, top_breakup);
		vec3 top_color = top_albedo * top_brightness;

		vec3 face_albedo = texture(face_albedo_tex, face_uv).rgb;
		float face_micro = texture(face_modulation, face_uv).r;
		float face_macro = texture(face_modulation, macro_uv * vec2(0.84, 1.16) + vec2(0.23, 0.61)).r;
		float face_breakup = remap_contrast(mix(face_micro, face_macro, 0.34), modulation_contrast);
		float face_brightness = mix(1.0 - modulation_strength, 1.0 + modulation_strength, face_breakup);
		vec3 face_color = face_albedo * face_brightness;

		vec3 back_color = mix(top_color * back_rim_darkening, face_color, 0.22);
		vec3 final_color = (
			top_color * top_mask +
			face_color * face_mask +
			back_color * back_mask
		) / total_mask;

		vec3 shape_normal = unpack_normal(texture(shape_normal_atlas, UV).rgb);
		vec3 top_normal = unpack_normal(texture(top_normal_tex, top_uv).rgb);
		vec3 top_normal_secondary = unpack_normal(texture(top_normal_tex, top_uv_secondary).rgb);
		vec3 face_normal = unpack_normal(texture(face_normal_tex, face_uv).rgb);
		vec3 detail_normal = normalize(
			normalize(top_normal + top_normal_secondary) * top_mask +
			face_normal * face_mask +
			normalize(top_normal + top_normal_secondary) * back_mask
		);
		vec3 final_normal = blend_normals(shape_normal, detail_normal);

		COLOR = vec4(final_color, mask.a);
		NORMAL_MAP = final_normal * 0.5 + 0.5;
	}
}
