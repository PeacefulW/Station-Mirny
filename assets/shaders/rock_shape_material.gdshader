shader_type canvas_item;

uniform sampler2D shape_normal_atlas : filter_nearest;
uniform sampler2D top_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D face_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D top_modulation : repeat_enable, filter_linear;
uniform sampler2D face_modulation : repeat_enable, filter_linear;
uniform sampler2D top_normal_tex : repeat_enable, filter_linear;
uniform sampler2D face_normal_tex : repeat_enable, filter_linear;

uniform vec4 top_dark_color : source_color = vec4(0.30, 0.24, 0.20, 1.0);
uniform vec4 top_light_color : source_color = vec4(0.49, 0.41, 0.34, 1.0);
uniform vec4 face_dark_color : source_color = vec4(0.22, 0.18, 0.16, 1.0);
uniform vec4 face_light_color : source_color = vec4(0.39, 0.33, 0.28, 1.0);
uniform vec4 dust_color : source_color = vec4(0.62, 0.53, 0.42, 1.0);

uniform float top_world_scale_px = 224.0;
uniform float face_world_scale_px = 112.0;
uniform float macro_world_scale_px = 448.0;
uniform float dust_strength = 0.0;
uniform float top_contrast = 1.12;
uniform float face_contrast = 1.22;
uniform float back_rim_darkening = 1.0;
uniform float top_albedo_blend = 1.0;
uniform float face_albedo_blend = 1.0;
uniform float top_albedo_chroma_strength = 0.0;
uniform float face_albedo_chroma_strength = 0.0;
uniform float top_albedo_luma_strength = 0.0;
uniform float face_albedo_luma_strength = 0.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec3 unpack_normal(vec3 packed_normal) {
	return normalize(packed_normal * 2.0 - 1.0);
}

vec3 blend_normals(vec3 base_normal, vec3 detail_normal) {
	return normalize(vec3(base_normal.xy + detail_normal.xy, max(0.001, base_normal.z * detail_normal.z)));
}

float remap_contrast(float value, float amount) {
	return clamp((value - 0.5) * amount + 0.5, 0.0, 1.0);
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
		vec2 top_uv_secondary = vec2(-world_pos.y, world_pos.x) / (top_world_scale_px * 1.73);
		vec2 face_uv = vec2(world_pos.x / face_world_scale_px, world_pos.y / (face_world_scale_px * 0.62));
		vec2 macro_uv = world_pos / macro_world_scale_px;
		vec2 macro_uv_secondary = vec2(world_pos.y, world_pos.x) / (macro_world_scale_px * 1.37);

		float top_micro = texture(top_modulation, top_uv).r;
		float top_secondary = texture(face_modulation, top_uv_secondary + vec2(0.41, 0.23)).r;
		float top_macro = texture(top_modulation, macro_uv + vec2(0.17, 0.31)).r;
		float top_macro_secondary = texture(face_modulation, macro_uv_secondary + vec2(0.73, 0.29)).r;
		float top_value = remap_contrast(
			top_micro * 0.42 +
			top_secondary * 0.18 +
			top_macro * 0.24 +
			top_macro_secondary * 0.16,
			top_contrast
		);

		float face_micro = texture(face_modulation, face_uv).r;
		float face_macro = texture(face_modulation, macro_uv * vec2(0.8, 1.2) + vec2(0.73, 0.29)).r;
		float face_value = remap_contrast(mix(face_micro, face_macro, 0.28), face_contrast);

		vec3 top_albedo = texture(top_albedo_tex, top_uv).rgb;
		vec3 top_color = mix(
			vec3(1.0),
			top_albedo,
			top_albedo_blend
		);
		float dust = smoothstep(0.62, 0.92, max(top_macro, top_macro_secondary)) * dust_strength;
		top_color = mix(top_color, dust_color.rgb, dust);
		top_color *= mix(0.995, 1.005, top_micro * 0.65 + top_secondary * 0.35);

		vec3 face_albedo = texture(face_albedo_tex, face_uv).rgb;
		vec3 face_color = mix(
			vec3(1.0),
			face_albedo,
			face_albedo_blend
		);
		float face_wear = smoothstep(0.75, 1.0, face_micro) * dust_strength * 0.65;
		face_color = mix(face_color, dust_color.rgb * 0.82, face_wear);
		face_color *= mix(0.995, 1.005, face_macro);

		vec3 back_color = mix(top_color * back_rim_darkening, face_color, 0.25);
		vec3 final_color = (
			top_color * top_mask +
			face_color * face_mask +
			back_color * back_mask
		) / total_mask;

		vec3 shape_normal = unpack_normal(texture(shape_normal_atlas, UV).rgb);
		vec3 top_normal = unpack_normal(texture(top_normal_tex, top_uv).rgb);
		vec3 top_normal_secondary = unpack_normal(texture(face_normal_tex, top_uv_secondary + vec2(0.41, 0.23)).rgb);
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
