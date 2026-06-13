shader_type canvas_item;

// Plains ground: one world-space material composes the whole walkable surface.
// A continuous grass-density field G runs the texture ladder
//   dirty soil -> gritty dry ground -> transition wisps -> sparse -> medium ->
//   dense grass -> orange biofield cores,
// with sparse rocky patches breaking through where grass is thin.
//
// Hard rules learned the painful way:
// - every field is an aperiodic function of world_pos (hash fbm), never a
//   repeat-sampled texture: texture-driven fields repeat on the texture period
//   grid and read as wallpaper from far away;
// - there is NO per-chunk state here, so chunk seams cannot exist;
// - band edges are dissolved by per-pixel strand luma, so transitions read as
//   thinning grass fibers instead of airbrushed gradients;
// - repeat textures only carry grain and are mipmapped (far zoom converges to
//   their mean instead of aliasing noise).

uniform sampler2D shape_normal_atlas : filter_nearest;
uniform sampler2D top_albedo_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D face_albedo_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D top_modulation : repeat_enable, filter_linear_mipmap;
uniform sampler2D face_modulation : repeat_enable, filter_linear_mipmap;
uniform sampler2D top_normal_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D face_normal_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D dirty_albedo_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_transition_albedo_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_sparse_albedo_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_medium_albedo_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_dense_albedo_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D orange_biofield_albedo_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_normal_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_top_albedo_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_foothill_albedo_tex : repeat_enable, filter_linear_mipmap;

uniform float top_world_scale_px = 384.0;
uniform float face_world_scale_px = 224.0;
uniform float macro_world_scale_px = 896.0;
uniform float modulation_strength = 0.12;
uniform float modulation_contrast = 1.08;
uniform float back_rim_darkening = 0.94;
uniform float organic_overlay_strength = 0.0;
uniform float detail_world_scale_px = 540.0;
uniform float soil_field_scale_px = 1500.0;
uniform float grass_field_scale_px = 2400.0;
uniform float grass_coverage = 0.55;
uniform float grass_dissolve = 0.30;
uniform float orange_field_scale_px = 1450.0;
uniform float orange_coverage = 0.30;
uniform float rock_field_scale_px = 1050.0;
uniform float rock_coverage = 0.26;
uniform float macro_drift_scale_px = 5200.0;
uniform float macro_drift_strength = 0.08;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float remap_contrast(float value, float amount) {
	return clamp((value - 0.5) * amount + 0.5, 0.0, 1.0);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 unpack_normal(vec3 packed_normal) {
	return normalize(packed_normal * 2.0 - 1.0);
}

vec3 blend_normals(vec3 base_normal, vec3 detail_normal) {
	return normalize(vec3(base_normal.xy + detail_normal.xy, max(0.001, base_normal.z * detail_normal.z)));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Gradient (Perlin-style) noise, NOT value noise: value noise is near-linear
// inside each lattice cell, so a thresholded region grows straight polygon
// edges with corners on the lattice. Gradient noise keeps isolines curved.
vec2 random_gradient(vec2 p) {
	vec2 h = vec2(hash12(p), hash12(p + vec2(17.31, -41.77))) * 2.0 - 1.0;
	return normalize(h + vec2(0.001, -0.001));
}

float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(random_gradient(i), f);
	float b = dot(random_gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(random_gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(random_gradient(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	// 1.42: stretch raw gradient-noise spread (~±0.7) to roughly value-noise
	// spread so the field actually reaches the bare/dense extremes.
	return clamp(mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.42 * 0.5 + 0.5, 0.0, 1.0);
}

float fbm3(vec2 p) {
	float v = 0.0;
	float amp = 0.56;
	float total = 0.0;
	for (int i = 0; i < 3; i++) {
		v += gradient_noise(p) * amp;
		total += amp;
		p = p * 2.07 + vec2(17.1, -9.4);
		amp *= 0.48;
	}
	return v / max(total, 0.0001);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float amp = 0.60;
	float total = 0.0;
	for (int i = 0; i < 2; i++) {
		v += gradient_noise(p) * amp;
		total += amp;
		p = p * 2.11 + vec2(-13.7, 21.3);
		amp *= 0.50;
	}
	return v / max(total, 0.0001);
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

		// Aperiodic macro breakup (a repeat texture lookup here would tile).
		float top_macro = fbm2(world_pos / macro_world_scale_px + vec2(0.11, 0.53));
		float face_macro = fbm2(world_pos / macro_world_scale_px * vec2(0.84, 1.16) + vec2(0.23, 0.61));

		vec3 top_albedo = mix(
			texture(top_albedo_tex, top_uv).rgb,
			texture(top_albedo_tex, top_uv_secondary).rgb,
			0.42
		);
		float top_micro = texture(top_modulation, top_uv).r;
		float top_breakup = remap_contrast(mix(top_micro, top_macro, 0.34), modulation_contrast);
		float top_brightness = mix(1.0 - modulation_strength, 1.0 + modulation_strength, top_breakup);
		vec3 top_color = top_albedo * top_brightness;

		float grass_total = 0.0;
		float organic_strength = clamp(organic_overlay_strength, 0.0, 1.0);
		if (organic_strength > 0.001) {
			// --- aperiodic world fields ---
			// Two-scale warp: broad swing bends region shapes, fine jitter
			// breaks any residual straight stretch of an isoline.
			vec2 warp = vec2(
				fbm2(world_pos / 1800.0 + vec2(11.7, -4.3)),
				fbm2(world_pos / 1650.0 + vec2(-7.9, 23.1))
			) - vec2(0.5);
			vec2 jitter = vec2(
				fbm2(world_pos / 420.0 + vec2(53.0, 19.0)),
				fbm2(world_pos / 390.0 + vec2(-22.0, 67.0))
			) - vec2(0.5);
			vec2 organic_pos = world_pos + warp * 660.0 + jitter * 170.0;

			float soil_field = fbm2(organic_pos / max(soil_field_scale_px, 1.0) + vec2(31.0, 5.0));
			float grass_field = remap_contrast(
				fbm3(organic_pos / max(grass_field_scale_px, 1.0) + vec2(4.7, 13.9)),
				2.10
			);
			grass_field = clamp(grass_field + (grass_coverage - 0.5) * 0.9, 0.0, 1.0);
			float orange_field = remap_contrast(
				fbm3(organic_pos / max(orange_field_scale_px, 1.0) + vec2(-27.3, 8.1)),
				1.30
			);
			float rock_field = fbm3(organic_pos / max(rock_field_scale_px, 1.0) + vec2(15.5, -31.7));

			// --- base soil: soft dirt <-> gritty dry ground ---
			// Gravel is warmed and biased toward the dirt side: raw
			// dry_ground_top mips average to a cold grey that reads as dead
			// grey continents at far zoom.
			vec2 detail_uv = world_pos / max(detail_world_scale_px, 1.0);
			vec3 dirty_color = texture(dirty_albedo_tex, detail_uv * 0.74 + vec2(0.19, 0.41)).rgb;
			vec3 gravel_color = top_color * vec3(1.06, 0.99, 0.90);
			float soil_mix = smoothstep(0.42, 0.80, soil_field);
			top_color = mix(dirty_color * top_brightness, gravel_color, soil_mix);

			// --- sparse rocky patches, strongest where grass is thin ---
			vec3 rock_color = mix(
				texture(rock_top_albedo_tex, detail_uv * 1.12 + vec2(0.07, 0.61)).rgb,
				texture(rock_foothill_albedo_tex, detail_uv * 0.86 + vec2(0.43, 0.13)).rgb,
				smoothstep(0.4, 0.6, fbm2(organic_pos / 820.0 + vec2(9.0, 47.0)))
			);
			float rock_threshold = mix(0.86, 0.52, clamp(rock_coverage, 0.0, 1.0));
			// Wide band + per-pixel crumble by the rock grain itself: the patch
			// edge falls apart into pebbles instead of a razor isoline.
			float rock_crumble = (smoothstep(0.30, 0.74, luma(rock_color)) - 0.5) * 0.18;
			float rock_region = smoothstep(rock_threshold - 0.24, rock_threshold + 0.24, rock_field + rock_crumble);
			rock_region *= 1.0 - smoothstep(0.30, 0.62, grass_field) * 0.78;
			float rock_rim = smoothstep(0.02, 0.30, rock_region) * (1.0 - smoothstep(0.45, 0.95, rock_region));
			top_color = mix(top_color, top_color * 0.90, rock_rim * 0.4);
			top_color = mix(top_color, rock_color * mix(0.94, 1.05, top_breakup), rock_region * 0.92);

			// --- grass ladder with strand-level dissolve ---
			vec3 transition_color = texture(grass_transition_albedo_tex, detail_uv + vec2(0.31, -0.17)).rgb;
			vec3 sparse_color = texture(grass_sparse_albedo_tex, detail_uv).rgb;
			vec3 medium_color = texture(grass_medium_albedo_tex, detail_uv * 1.17 + vec2(0.21, -0.09)).rgb;
			vec3 dense_color = texture(grass_dense_albedo_tex, detail_uv * 0.91 + vec2(-0.13, 0.18)).rgb;
			// Contrast-boosted fiber mask: raw luma swings only a few percent,
			// which made the dissolve cosmetic and left band edges as hard
			// texture butt-joints. This term must rival the band width so
			// every transition grows/thins strand by strand.
			float strand_detail = smoothstep(0.30, 0.70, luma(sparse_color)) - 0.5;
			float grass_density = clamp(
				grass_field
					+ strand_detail * grass_dissolve
					+ (top_breakup - 0.5) * 0.10,
				0.0,
				1.0
			);
			grass_density *= 1.0 - rock_region * 0.85;

			// Пороги травяной лестницы сдвинуты вниз так, чтобы зона, где
			// native ставит пучки (grass_density ~0.30+), уже была плотным
			// травяным ковром: пучки врастают в землю, а не торчат из голого
			// грунта. Пучки сэмплят то же grass_density, поля синхронны.
			vec3 grass_color = top_color;
			grass_color = mix(grass_color, transition_color, smoothstep(0.12, 0.30, grass_density));
			grass_color = mix(grass_color, sparse_color, smoothstep(0.26, 0.44, grass_density));
			grass_color = mix(grass_color, medium_color, smoothstep(0.40, 0.58, grass_density));
			grass_color = mix(grass_color, dense_color, smoothstep(0.56, 0.78, grass_density));

			// --- orange biofield cores inside healthy grass ---
			vec3 orange_color = texture(orange_biofield_albedo_tex, detail_uv * 0.84 + vec2(0.33, 0.12)).rgb;
			float orange_threshold = mix(0.88, 0.50, clamp(orange_coverage, 0.0, 1.0));
			float orange_region = smoothstep(orange_threshold - 0.22, orange_threshold + 0.22, orange_field + strand_detail * 0.16);
			orange_region *= smoothstep(0.44, 0.80, grass_density);
			grass_color = mix(grass_color, orange_color, orange_region * 0.92);

			grass_total = smoothstep(0.20, 0.55, grass_density);
			top_color = mix(top_color, grass_color, organic_strength);
			top_color *= 0.965 + top_breakup * 0.07;

			// --- large aperiodic tone drift: keeps far zoom alive, no grid ---
			if (macro_drift_strength > 0.001 && macro_drift_scale_px > 1.0) {
				// Mostly-warm drift: the cool pole stays nearly neutral so wide
				// gravel areas never collapse into cold grey fields.
				float drift = fbm2(world_pos / macro_drift_scale_px + vec2(3.1, -8.7));
				float drift_brightness = mix(1.0 - macro_drift_strength, 1.0 + macro_drift_strength, drift);
				vec3 warm_tint = vec3(1.0 + macro_drift_strength * 0.40, 1.0, 1.0 - macro_drift_strength * 0.50);
				vec3 cool_tint = vec3(1.0 - macro_drift_strength * 0.15, 1.0, 1.0 + macro_drift_strength * 0.10);
				top_color *= drift_brightness * mix(cool_tint, warm_tint, drift);
			}
		}

		vec3 face_albedo = texture(face_albedo_tex, face_uv).rgb;
		float face_micro = texture(face_modulation, face_uv).r;
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
		if (organic_strength > 0.001 && grass_total > 0.001) {
			vec2 detail_uv = world_pos / max(detail_world_scale_px, 1.0);
			vec3 grass_normal = unpack_normal(texture(grass_normal_tex, detail_uv * 0.92 + vec2(0.11, 0.37)).rgb);
			float grass_normal_mix = grass_total * 0.55;
			top_normal = normalize(mix(top_normal, grass_normal, grass_normal_mix));
			top_normal_secondary = normalize(mix(top_normal_secondary, grass_normal, grass_normal_mix * 0.72));
		}
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
