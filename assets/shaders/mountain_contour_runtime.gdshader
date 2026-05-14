shader_type canvas_item;

uniform sampler2D top_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D face_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D base_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D top_modulation_tex : repeat_enable, filter_linear;
uniform sampler2D face_modulation_tex : repeat_enable, filter_linear;
uniform sampler2D top_normal_tex : repeat_enable, filter_linear;
uniform sampler2D face_normal_tex : repeat_enable, filter_linear;
uniform sampler2D edge_profile_lut : repeat_disable, filter_linear;
uniform sampler2D height_profile_lut : repeat_disable, filter_linear;

uniform vec4 top_tint : source_color = vec4(0.44, 0.35, 0.25, 1.0);
uniform vec4 face_tint : source_color = vec4(0.24, 0.18, 0.14, 1.0);
uniform vec4 edge_tint : source_color = vec4(0.29, 0.22, 0.17, 1.0);
uniform vec4 base_tint : source_color = vec4(0.72, 0.55, 0.35, 1.0);

uniform float surface_zone = 0.0;
uniform float top_world_scale_px = 224.0;
uniform float face_world_scale_px = 112.0;
uniform float macro_world_scale_px = 448.0;
uniform float texture_scale = 1.0;
uniform float south_height_px = 32.0;
uniform float side_height_px = 0.0;
uniform float rim_width_px = 8.0;
uniform bool mountain_outline_enabled = true;
uniform float mountain_outline_width_px = 3.0;
uniform float normal_strength = 8.0;
uniform float normal_detail_strength = 4.0;
uniform float edge_debris = 0.8;
uniform float edge_color_strength = 0.35;

varying vec2 world_pos;
varying vec2 contour_edge_uv;
varying vec4 contour_attr;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	contour_edge_uv = UV;
	contour_attr = COLOR;
}

vec3 unpack_normal(vec3 packed_normal) {
	return normalize(packed_normal * 2.0 - 1.0);
}

vec3 blend_normals(vec3 shape_normal, vec3 material_normal) {
	return normalize(vec3(
		shape_normal.xy * 0.65 + material_normal.xy,
		max(0.001, shape_normal.z * material_normal.z)
	));
}

float safe_scale(float scale_px) {
	return max(1.0, scale_px * max(0.01, texture_scale));
}

vec3 sample_top_normal(vec2 top_uv, vec2 macro_uv) {
	vec3 primary = unpack_normal(texture(top_normal_tex, top_uv).rgb);
	vec3 detail = unpack_normal(texture(top_normal_tex, macro_uv + vec2(0.37, 0.19)).rgb);
	return normalize(mix(primary, detail, clamp(normal_detail_strength / 16.0, 0.0, 1.0) * 0.35));
}

vec3 sample_face_normal(vec2 face_uv, vec2 macro_uv) {
	vec3 primary = unpack_normal(texture(face_normal_tex, face_uv).rgb);
	vec3 detail = unpack_normal(texture(face_normal_tex, macro_uv + vec2(0.11, 0.47)).rgb);
	return normalize(mix(primary, detail, clamp(normal_detail_strength / 16.0, 0.0, 1.0) * 0.35));
}

void fragment() {
	float edge_u = contour_edge_uv.x;
	float edge_v = contour_edge_uv.y;
	float signed_distance = contour_attr.r * 2.0 - 1.0;
	float face_depth_px = contour_attr.g * 128.0;
	float facade_side = contour_attr.b * 4.0;
	float material_zone = floor(contour_attr.a * 8.0 + 0.5);
	float depth_norm = clamp(face_depth_px / max(1.0, south_height_px + side_height_px + mountain_outline_width_px), 0.0, 1.0);
	float edge_profile = texture(edge_profile_lut, vec2(clamp(edge_v, 0.0, 1.0), 0.5)).r;
	float height_profile = texture(height_profile_lut, vec2(depth_norm, 0.5)).r;

	vec2 top_uv = world_pos / safe_scale(top_world_scale_px);
	vec2 face_uv = vec2(edge_u * 64.0 + facade_side * 23.0, face_depth_px) / safe_scale(face_world_scale_px);
	vec2 macro_uv = world_pos / safe_scale(macro_world_scale_px);

	vec3 top_albedo = texture(top_albedo_tex, top_uv).rgb;
	vec3 face_albedo = texture(face_albedo_tex, face_uv).rgb;
	vec3 base_albedo = texture(base_albedo_tex, macro_uv).rgb;
	float top_breakup = texture(top_modulation_tex, top_uv * 1.13 + vec2(0.17, 0.29)).r;
	float face_breakup = texture(face_modulation_tex, face_uv * vec2(0.8, 1.25) + vec2(0.41, 0.23)).r;
	float debris = smoothstep(0.54, 0.95, max(top_breakup, face_breakup)) * edge_debris * edge_profile * (1.0 - abs(signed_distance));

	vec3 color = top_albedo;
	vec3 material_normal = sample_top_normal(top_uv, macro_uv);
	if (material_zone > 0.5 && material_zone < 1.5) {
		color = face_albedo;
		color *= mix(0.74, 1.08, face_breakup);
		color *= mix(0.78, 1.0, height_profile);
		material_normal = sample_face_normal(face_uv, macro_uv);
	} else if (material_zone >= 1.5 && material_zone < 2.5) {
		color = mix(top_albedo, face_albedo, 0.52);
		color = mix(color, face_albedo * 0.72, edge_color_strength * (0.35 + edge_profile * 0.45));
		color *= mix(0.9, 1.08, top_breakup);
		material_normal = normalize(mix(sample_top_normal(top_uv, macro_uv), sample_face_normal(face_uv, macro_uv), 0.4));
	} else if (material_zone >= 2.5) {
		float outline_alpha = mountain_outline_enabled ? 1.0 : 0.0;
		color = mix(face_albedo * 0.34, face_albedo * 0.16, outline_alpha);
		color *= mix(0.72, 0.92, clamp(mountain_outline_width_px / 16.0, 0.0, 1.0));
		material_normal = sample_face_normal(face_uv, macro_uv);
	} else {
		color *= mix(0.94, 1.10, top_breakup);
		color = mix(color, face_albedo, debris * 0.12);
	}

	vec3 shape_normal = normalize(vec3(
		(edge_profile - 0.5) * max(0.05, edge_color_strength),
		(height_profile - 0.5) * clamp((south_height_px + side_height_px + rim_width_px) / 256.0, 0.05, 0.7),
		1.0
	));
	vec3 final_normal = blend_normals(shape_normal, material_normal);
	final_normal = normalize(mix(vec3(0.0, 0.0, 1.0), final_normal, clamp(normal_strength / 16.0, 0.0, 1.0)));

	COLOR = vec4(color, 1.0);
	NORMAL_MAP = final_normal * 0.5 + 0.5;
}
