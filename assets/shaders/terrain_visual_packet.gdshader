shader_type canvas_item;

const int MODE_ALBEDO = 0;
const int MODE_ZONE = 1;
const int MODE_COVERAGE = 2;
const int MODE_HEIGHT = 3;
const int MODE_NORMAL = 4;
const int MODE_MATERIAL_UV = 5;
const int MODE_LIT_PREVIEW = 6;

const int SOURCE_PROCEDURAL = 0;
const int SOURCE_IMAGE = 1;
const int SOURCE_FLAT = 2;

const int KIND_STRATIFIED_ROCK = 0;
const int KIND_ROUGH_STONE = 1;
const int KIND_CRACKED_DRY_EARTH = 2;
const int KIND_PACKED_DIRT = 3;

uniform sampler2D zone_texture : repeat_disable, filter_nearest;
uniform sampler2D coverage_top_texture : repeat_disable, filter_nearest;
uniform sampler2D coverage_edge_texture : repeat_disable, filter_nearest;
uniform sampler2D coverage_face_texture : repeat_disable, filter_nearest;
uniform sampler2D coverage_back_texture : repeat_disable, filter_nearest;
uniform sampler2D height_texture : repeat_disable, filter_nearest;
uniform sampler2D normal_texture : repeat_disable, filter_nearest;
uniform sampler2D material_u_texture : repeat_disable, filter_nearest;
uniform sampler2D material_v_texture : repeat_disable, filter_nearest;

uniform int debug_mode = 0;
uniform vec2 packet_pixel_size = vec2(1.0, 1.0);

uniform vec4 top_color : source_color = vec4(0.60, 0.58, 0.52, 1.0);
uniform vec4 edge_color : source_color = vec4(0.40, 0.38, 0.34, 1.0);
uniform vec4 face_color : source_color = vec4(0.34, 0.32, 0.29, 1.0);
uniform vec4 back_color : source_color = vec4(0.22, 0.20, 0.18, 1.0);
uniform vec4 base_color : source_color = vec4(0.31, 0.24, 0.15, 1.0);

uniform int top_source = 0;
uniform int top_kind = 1;
uniform vec4 top_flat_color : source_color = vec4(0.60, 0.58, 0.52, 1.0);
uniform vec4 top_color_a : source_color = vec4(0.31, 0.28, 0.23, 1.0);
uniform vec4 top_color_b : source_color = vec4(0.55, 0.48, 0.38, 1.0);
uniform vec4 top_highlight_color : source_color = vec4(0.72, 0.67, 0.55, 1.0);
uniform vec4 top_params = vec4(1.35, 1.22, 0.34, 0.30);
uniform vec4 top_params2 = vec4(0.68, 0.35, 0.85, 0.75);
uniform int top_seed = 11;
uniform sampler2D top_image_albedo : repeat_enable, filter_nearest;

uniform int edge_source = 0;
uniform int edge_kind = 0;
uniform vec4 edge_flat_color : source_color = vec4(0.40, 0.38, 0.34, 1.0);
uniform vec4 edge_color_a : source_color = vec4(0.20, 0.18, 0.16, 1.0);
uniform vec4 edge_color_b : source_color = vec4(0.43, 0.37, 0.31, 1.0);
uniform vec4 edge_highlight_color : source_color = vec4(0.67, 0.60, 0.48, 1.0);
uniform vec4 edge_params = vec4(1.25, 1.26, 0.45, 0.55);
uniform vec4 edge_params2 = vec4(0.60, 0.72, 0.80, 0.75);
uniform int edge_seed = 23;
uniform sampler2D edge_image_albedo : repeat_enable, filter_nearest;

uniform int face_source = 0;
uniform int face_kind = 0;
uniform vec4 face_flat_color : source_color = vec4(0.34, 0.32, 0.29, 1.0);
uniform vec4 face_color_a : source_color = vec4(0.15, 0.14, 0.12, 1.0);
uniform vec4 face_color_b : source_color = vec4(0.37, 0.32, 0.27, 1.0);
uniform vec4 face_highlight_color : source_color = vec4(0.67, 0.60, 0.48, 1.0);
uniform vec4 face_params = vec4(1.25, 1.26, 0.45, 0.55);
uniform vec4 face_params2 = vec4(0.60, 0.72, 0.80, 0.75);
uniform int face_seed = 23;
uniform sampler2D face_image_albedo : repeat_enable, filter_nearest;

uniform int back_source = 0;
uniform int back_kind = 0;
uniform vec4 back_flat_color : source_color = vec4(0.22, 0.20, 0.18, 1.0);
uniform vec4 back_color_a : source_color = vec4(0.14, 0.13, 0.12, 1.0);
uniform vec4 back_color_b : source_color = vec4(0.34, 0.30, 0.25, 1.0);
uniform vec4 back_highlight_color : source_color = vec4(0.54, 0.49, 0.40, 1.0);
uniform vec4 back_params = vec4(1.25, 1.26, 0.45, 0.55);
uniform vec4 back_params2 = vec4(0.60, 0.72, 0.80, 0.70);
uniform int back_seed = 29;
uniform sampler2D back_image_albedo : repeat_enable, filter_nearest;

uniform int base_source = 0;
uniform int base_kind = 3;
uniform vec4 base_flat_color : source_color = vec4(0.31, 0.24, 0.15, 1.0);
uniform vec4 base_color_a : source_color = vec4(0.49, 0.29, 0.12, 1.0);
uniform vec4 base_color_b : source_color = vec4(0.69, 0.45, 0.20, 1.0);
uniform vec4 base_highlight_color : source_color = vec4(0.82, 0.60, 0.34, 1.0);
uniform vec4 base_params = vec4(1.00, 0.90, 0.12, 0.20);
uniform vec4 base_params2 = vec4(0.50, 0.10, 0.45, 0.60);
uniform int base_seed = 31;
uniform sampler2D base_image_albedo : repeat_enable, filter_nearest;

uniform vec3 light_direction = vec3(-0.35, -0.50, 0.90);
uniform float lit_preview_strength : hint_range(0.0, 1.0) = 0.45;

float byte_value(sampler2D packet_texture, vec2 uv) {
	return floor(texture(packet_texture, uv).r * 255.0 + 0.5);
}

float q16_value(sampler2D packet_texture, vec2 uv) {
	vec2 packed_value = texture(packet_texture, uv).rg;
	float lo = floor(packed_value.r * 255.0 + 0.5);
	float hi = floor(packed_value.g * 255.0 + 0.5);
	return (lo + hi * 256.0) / 65535.0;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.13, 9.41);
		amplitude *= 0.5;
	}
	return value;
}

float crack_mask(vec2 p, float amount) {
	float ridge = 1.0 - abs(value_noise(p) - 0.5) * 2.0;
	float threshold = mix(0.94, 0.72, amount);
	return smoothstep(threshold, 1.0, ridge);
}

float layer_value(int kind, vec2 uv, vec2 p, float grain, float crack_amount, float seed) {
	if (kind == KIND_ROUGH_STONE) {
		float broad = fbm(p * 0.55);
		float fine = fbm(p * 3.1 + vec2(seed * 0.37, 4.2));
		float pits = crack_mask(p * 1.7 + vec2(5.1, seed), crack_amount);
		return clamp(mix(broad, fine, grain * 0.72) - pits * crack_amount * 0.28, 0.0, 1.0);
	}
	if (kind == KIND_CRACKED_DRY_EARTH) {
		float packed = fbm(p * 0.72 + vec2(seed, 2.0));
		float cracks = crack_mask(p * 2.8 + vec2(1.7, seed * 0.23), max(crack_amount, 0.35));
		float plates = smoothstep(0.24, 0.82, packed);
		return clamp(plates - cracks * 0.50, 0.0, 1.0);
	}
	if (kind == KIND_PACKED_DIRT) {
		float broad = fbm(p * 0.42 + vec2(seed * 0.11, 0.0));
		float grains = fbm(p * 4.8 + vec2(6.0, seed * 0.19));
		return clamp(mix(broad, grains, grain * 0.38), 0.0, 1.0);
	}

	float warp = fbm(vec2(uv.x * 8.0, uv.y * 2.0) + vec2(seed * 0.31, 0.0));
	float bands = sin((uv.y * 38.0 + warp * 4.0 + seed * 0.17) * max(0.25, grain + 0.55));
	float fine = fbm(p * vec2(1.15, 3.4) + vec2(0.0, seed));
	return clamp(mix(bands * 0.5 + 0.5, fine, 0.28), 0.0, 1.0);
}

vec4 procedural_material(
		int kind,
		vec2 material_uv,
		float depth,
		vec4 color_a,
		vec4 color_b,
		vec4 highlight_color,
		vec4 params,
		vec4 params2,
		int seed
) {
	float scale = max(params.x, 0.01);
	float contrast = max(params.y, 0.0);
	float crack_amount = clamp(params.z, 0.0, 1.0);
	float wear = clamp(params.w, 0.0, 1.0);
	float grain = clamp(params2.x, 0.0, 1.0);
	float edge_darkening = clamp(params2.y, 0.0, 1.0);
	float modulation_strength = clamp(params2.w, 0.0, 1.0);

	vec2 uv = fract(material_uv);
	float seed_value = float(seed);
	vec2 p = uv * scale * 9.0 + vec2(seed_value * 0.071, seed_value * 0.137);
	float layer = layer_value(kind, uv, p, grain, crack_amount, seed_value);
	layer = clamp((layer - 0.5) * contrast + 0.5, 0.0, 1.0);
	layer = mix(0.5, layer, modulation_strength);

	vec3 color = mix(color_a.rgb, color_b.rgb, layer);
	float cracks = crack_mask(p * 1.45 + vec2(seed_value * 0.41, 3.3), crack_amount);
	color *= 1.0 - cracks * crack_amount * 0.42;

	float wear_mask = smoothstep(0.58, 0.96, fbm(p * 2.25 + vec2(11.0, seed_value * 0.13)));
	color = mix(color, highlight_color.rgb, wear_mask * wear * 0.48);
	color *= 1.0 - smoothstep(0.35, 1.0, depth) * edge_darkening * 0.35;
	return vec4(clamp(color, vec3(0.0), vec3(1.0)), color_a.a);
}

vec4 material_from_values(
		int source,
		int kind,
		vec2 material_uv,
		float depth,
		vec4 flat_color_value,
		vec4 color_a,
		vec4 color_b,
		vec4 highlight_color,
		vec4 params,
		vec4 params2,
		int seed,
		vec4 image_color
) {
	if (source == SOURCE_IMAGE) {
		return image_color;
	}
	if (source == SOURCE_FLAT) {
		return flat_color_value;
	}
	return procedural_material(
			kind,
			material_uv,
			depth,
			color_a,
			color_b,
			highlight_color,
			params,
			params2,
			seed
	);
}

vec4 top_material(vec2 material_uv) {
	return material_from_values(
			top_source,
			top_kind,
			material_uv,
			0.0,
			top_flat_color,
			top_color_a,
			top_color_b,
			top_highlight_color,
			top_params,
			top_params2,
			top_seed,
			texture(top_image_albedo, fract(material_uv))
	);
}

vec4 edge_material(vec2 material_uv) {
	return material_from_values(
			edge_source,
			edge_kind,
			material_uv,
			material_uv.y,
			edge_flat_color,
			edge_color_a,
			edge_color_b,
			edge_highlight_color,
			edge_params,
			edge_params2,
			edge_seed,
			texture(edge_image_albedo, fract(material_uv))
	);
}

vec4 face_material(vec2 material_uv) {
	return material_from_values(
			face_source,
			face_kind,
			material_uv,
			material_uv.y,
			face_flat_color,
			face_color_a,
			face_color_b,
			face_highlight_color,
			face_params,
			face_params2,
			face_seed,
			texture(face_image_albedo, fract(material_uv))
	);
}

vec4 back_material(vec2 material_uv) {
	return material_from_values(
			back_source,
			back_kind,
			material_uv,
			material_uv.y,
			back_flat_color,
			back_color_a,
			back_color_b,
			back_highlight_color,
			back_params,
			back_params2,
			back_seed,
			texture(back_image_albedo, fract(material_uv))
	);
}

vec4 base_material(vec2 material_uv) {
	return material_from_values(
			base_source,
			base_kind,
			material_uv,
			0.0,
			base_flat_color,
			base_color_a,
			base_color_b,
			base_highlight_color,
			base_params,
			base_params2,
			base_seed,
			texture(base_image_albedo, fract(material_uv))
	);
}

vec4 zone_debug_color(float zone_id, float alpha) {
	if (zone_id < 0.5) {
		return vec4(0.0, 0.0, 0.0, 0.0);
	}
	if (zone_id < 1.5) {
		return vec4(0.72, 0.70, 0.62, alpha);
	}
	if (zone_id < 2.5) {
		return vec4(0.98, 0.74, 0.30, alpha);
	}
	if (zone_id < 3.5) {
		return vec4(0.42, 0.62, 0.96, alpha);
	}
	return vec4(0.54, 0.44, 0.70, alpha);
}

vec4 blended_albedo(vec2 material_uv, float top, float edge, float face, float back) {
	float surface_alpha = clamp(max(max(top, edge), max(face, back)), 0.0, 1.0);
	float base = clamp(1.0 - surface_alpha, 0.0, 1.0);
	vec4 top_sample = top_material(material_uv);
	vec4 edge_sample = edge_material(material_uv);
	vec4 face_sample = face_material(material_uv);
	vec4 back_sample = back_material(material_uv);
	vec4 base_sample = base_material(material_uv);
	float top_weight = top * top_sample.a;
	float edge_weight = edge * edge_sample.a;
	float face_weight = face * face_sample.a;
	float back_weight = back * back_sample.a;
	float base_weight = base * base_sample.a;
	float total_weight = max(top_weight + edge_weight + face_weight + back_weight + base_weight, 0.001);
	vec3 mixed_color = (
			top_sample.rgb * top_weight +
			edge_sample.rgb * edge_weight +
			face_sample.rgb * face_weight +
			back_sample.rgb * back_weight +
			base_sample.rgb * base_weight
	) / total_weight;
	return vec4(clamp(mixed_color, vec3(0.0), vec3(1.0)), clamp(total_weight, 0.0, 1.0));
}

void fragment() {
	vec2 uv = clamp(UV, vec2(0.0), vec2(1.0));
	float zone_id = byte_value(zone_texture, uv);
	float top = texture(coverage_top_texture, uv).r;
	float edge = texture(coverage_edge_texture, uv).r;
	float face = texture(coverage_face_texture, uv).r;
	float back = texture(coverage_back_texture, uv).r;
	float surface_alpha = clamp(max(max(top, edge), max(face, back)), 0.0, 1.0);
	float height_value = q16_value(height_texture, uv);
	vec3 packed_normal = texture(normal_texture, uv).rgb;
	vec3 solved_normal = normalize(packed_normal * 2.0 - 1.0);
	float material_u = q16_value(material_u_texture, uv);
	float material_v = q16_value(material_v_texture, uv);
	vec2 material_uv = vec2(material_u, material_v);
	vec4 albedo = blended_albedo(material_uv, top, edge, face, back);

	if (debug_mode == MODE_ZONE) {
		COLOR = zone_debug_color(zone_id, surface_alpha);
	} else if (debug_mode == MODE_COVERAGE) {
		COLOR = vec4(top, edge, face, surface_alpha);
	} else if (debug_mode == MODE_HEIGHT) {
		COLOR = vec4(vec3(height_value), surface_alpha);
	} else if (debug_mode == MODE_NORMAL) {
		COLOR = vec4(packed_normal, surface_alpha);
	} else if (debug_mode == MODE_MATERIAL_UV) {
		COLOR = vec4(material_u, material_v, 0.0, surface_alpha);
	} else if (debug_mode == MODE_LIT_PREVIEW) {
		float shade = dot(solved_normal, normalize(light_direction)) * 0.5 + 0.5;
		vec3 lit_color = albedo.rgb * mix(1.0, shade, lit_preview_strength);
		COLOR = vec4(lit_color, albedo.a);
	} else {
		COLOR = albedo;
	}
	NORMAL_MAP = packed_normal;
}
