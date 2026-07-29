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
uniform sampler2D rock_top_normal_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_foothill_albedo_tex : repeat_enable, filter_linear_mipmap;

uniform bool temporary_disable_terrain_normals = true;
uniform float top_world_scale_px = 384.0;
uniform float face_world_scale_px = 224.0;
uniform float macro_world_scale_px = 896.0;
uniform float modulation_strength = 0.12;
uniform float modulation_contrast = 1.08;
uniform float back_rim_darkening = 0.94;
uniform float organic_overlay_strength = 0.0;
uniform float detail_world_scale_px = 540.0;
uniform float soil_field_scale_px = 2400.0;
uniform float grass_field_scale_px = 2400.0;
uniform float grass_coverage = 0.55;
uniform float grass_dissolve = 0.30;
uniform float orange_field_scale_px = 1450.0;
uniform float orange_coverage = 0.30;
uniform float rock_field_scale_px = 1050.0;
uniform float rock_coverage = 0.26;
// Visual-only extra rock islets on bare ground. Decoupled from rock_coverage so
// it drives ONLY color + normal, never grass_density (the placement field
// mirrored in grass_scatter.cpp). More visible rock, zero placement impact, no
// WORLD_VERSION bump. See plains_ground_field_composition.md Iteration 4.
uniform float rock_visual_coverage = 0.26;
uniform float macro_drift_scale_px = 4600.0;
uniform float macro_drift_strength = 0.16;
// Macro-mass coverage field (very long wavelength) and procedural paths:
// see docs/02_system_specs/world/plains_ground_field_composition.md. These two
// fields modulate grass_density across large regions and along sinuous trails;
// their math is mirrored 1:1 in gdextension/src/grass_scatter.cpp (field-mirror
// law) so placed grass/trees stay coherent with the painted ground.
uniform float macro_mass_scale_px = 7000.0;
uniform float macro_mass_strength = 0.34;
uniform float path_scale_px = 2600.0;
uniform float path_width = 0.06;
uniform float path_warp_px = 700.0;
uniform float path_strength = 0.85;
// Transition scree: gravel/pebbles concentrated on the open<->grass seam (and a
// few scattered stones on open dirt). Visual-only, reuses the rock textures;
// does not touch the density field or placement, so no C++ mirror is needed.
uniform float scree_field_scale_px = 640.0;
uniform float scree_density = 0.45;
uniform float scree_strength = 0.9;
uniform float scree_open_amount = 0.25;
// Ecotone edge mottling: high-frequency break-up of the grass<->bare boundary,
// applied ONLY inside the transition band, so the edge interfingers (grass
// tongues, dirt bays, stranded clumps) like the reference instead of a smooth
// fade. Visual-only (texture ladder + scree); placement keeps smooth grass_density.
uniform float edge_mottle_strength = 0.22;
uniform float edge_mottle_scale_px = 150.0;
// Cosmetic ground shading (ADR-0005: visual only, NOT gameplay light). Hybrid:
// a constant ambient-AO form field + a day-only sun-directional component. The
// sun model is fed by WorldStreamer from WorldVisualLightingProfile (the single
// sun source) — no second lighting curve.
uniform float shade_scale_px = 3500.0;
uniform float shade_ambient_strength = 0.13;
uniform float shade_relief_px = 520.0;
uniform float shade_directional_gain = 3.2;
uniform float shade_dir_strength = 0.16;
uniform float ground_sun_angle_deg = -152.525483;
uniform float ground_sun_day = 1.0;
// Developer-only exact zone view. The lab toggles this on the shared ground
// material; mode 2 renders the same classification into a 1 px probe and
// encodes its zone id in alpha. Zero is the production default.
uniform int debug_zone_mode = 0;
uniform vec2 debug_world_offset = vec2(0.0);

varying vec2 world_pos;

void vertex() {
	world_pos = (
		(MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy
		+ debug_world_offset
	);
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

// Procedural paths as distance-to-warped iso-contour of a low-frequency field.
// Returns "openness" in [0,1]: 1 = open ground, ->0 inside a trail. Kept to two
// fbm calls so the C++ mirror can evaluate it per-candidate. Mirrored 1:1 in
// grass_scatter::sample_path.
float sample_path(vec2 wp, float scale, float width, float warp_px, float strength) {
	float wn = fbm2(wp / max(scale * 0.5, 1.0) + vec2(71.3, -19.7));
	float ang = wn * 6.2831853;
	vec2 ppos = wp + vec2(cos(ang), sin(ang)) * warp_px;
	float s = fbm2(ppos / max(scale, 1.0) + vec2(13.1, 47.9));
	float d = abs(s - 0.5);
	float path = 1.0 - smoothstep(width, width * 2.0, d);
	return clamp(1.0 - path * strength, 0.0, 1.0);
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
		float rock_normal_mask = 0.0;
		float debug_zone_id = 0.0;
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
			// Macro-mass: one very long wavelength fbm biases coverage up/down
			// across large regions -> bare clearings vs dense pockets. Biofield
			// follows automatically because orange_region is gated by density.
			float macro_mass = fbm2(world_pos / max(macro_mass_scale_px, 1.0) + vec2(91.7, -53.3));
			float macro_bias = (macro_mass - 0.5) * 2.0 * macro_mass_strength;
			grass_field = clamp(grass_field + (grass_coverage - 0.5) * 0.9 + macro_bias, 0.0, 1.0);
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
			// Visual-only region: extra islets on bare ground for color + normal
			// ONLY. Never feeds grass_density, so no C++ mirror, no version bump.
			float rock_visual_threshold = mix(0.86, 0.52, clamp(rock_visual_coverage, 0.0, 1.0));
			float rock_region_visual = smoothstep(rock_visual_threshold - 0.24, rock_visual_threshold + 0.24, rock_field + rock_crumble);
			rock_region_visual *= 1.0 - smoothstep(0.30, 0.62, grass_field) * 0.78;
			rock_region_visual = max(rock_region_visual, rock_region);
			float rock_rim = smoothstep(0.02, 0.30, rock_region_visual) * (1.0 - smoothstep(0.45, 0.95, rock_region_visual));
			top_color = mix(top_color, top_color * 0.90, rock_rim * 0.4);
			top_color = mix(top_color, rock_color * mix(0.94, 1.05, top_breakup), rock_region_visual * 0.92);
			rock_normal_mask = max(rock_normal_mask, rock_region_visual * 0.85);

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

			// Paths: thin grass along sinuous trails so soil/gravel shows through.
			float path_open = sample_path(world_pos, path_scale_px, path_width, path_warp_px, path_strength);
			grass_density *= path_open;

			// Ragged ecotone: a fine field breaks the grass/bare edge ONLY in the
			// transition band -> interfingered boundary (grass tongues + dirt bays +
			// stranded clumps) like the reference, not a smooth fade. Visual-only:
			// the texture ladder/scree read grass_density_visual; tuft/tree placement
			// still reads grass_density (no field-mirror change, no version bump).
			float edge_w = 1.0 - clamp(abs(grass_density - 0.28) / 0.26, 0.0, 1.0);
			float edge_fbm = fbm2(world_pos / max(edge_mottle_scale_px, 1.0) + vec2(37.0, 71.0));
			float grass_density_visual = clamp(grass_density + (edge_fbm - 0.5) * edge_mottle_strength * edge_w, 0.0, 1.0);

			// Пороги травяной лестницы сдвинуты вниз так, чтобы зона, где
			// native ставит пучки (grass_density ~0.30+), уже была плотным
			// травяным ковром: пучки врастают в землю, а не торчат из голого
			// грунта. Пучки сэмплят то же grass_density, поля синхронны.
			vec3 grass_color = top_color;
			grass_color = mix(grass_color, transition_color, smoothstep(0.12, 0.30, grass_density_visual));
			grass_color = mix(grass_color, sparse_color, smoothstep(0.26, 0.44, grass_density_visual));
			grass_color = mix(grass_color, medium_color, smoothstep(0.40, 0.58, grass_density_visual));
			grass_color = mix(grass_color, dense_color, smoothstep(0.56, 0.78, grass_density_visual));

			// --- orange biofield cores inside healthy grass ---
			vec3 orange_color = texture(orange_biofield_albedo_tex, detail_uv * 0.84 + vec2(0.33, 0.12)).rgb;
			float orange_threshold = mix(0.88, 0.50, clamp(orange_coverage, 0.0, 1.0));
			float orange_region = smoothstep(orange_threshold - 0.22, orange_threshold + 0.22, orange_field + strand_detail * 0.16);
			orange_region *= smoothstep(0.44, 0.80, grass_density);
			grass_color = mix(grass_color, orange_color, orange_region * 0.92);

			grass_total = smoothstep(0.20, 0.55, grass_density);
			top_color = mix(top_color, grass_color, organic_strength);
			top_color *= 0.965 + top_breakup * 0.07;

			// --- transition scree: gravel on the open<->grass seam ---
			// Peaks where grass_density is mid (the seam), plus a faint amount on
			// open dirt. Broken into pebbles by a mid-frequency field and the rock
			// grain luma so it reads as scattered stones, not a flat wash.
			float scree_seam = smoothstep(0.06, 0.22, grass_density_visual) * (1.0 - smoothstep(0.32, 0.54, grass_density_visual));
			float scree_open = (1.0 - smoothstep(0.04, 0.14, grass_density_visual)) * scree_open_amount;
			float scree_band = max(scree_seam, scree_open);
			float scree_field = fbm2(world_pos / max(scree_field_scale_px, 1.0) + vec2(61.7, 28.3));
			float scree_threshold = mix(0.74, 0.40, clamp(scree_density, 0.0, 1.0));
			float scree_grain = smoothstep(0.40, 0.78, luma(rock_color));
			float scree = scree_band
				* smoothstep(scree_threshold - 0.16, scree_threshold + 0.16, scree_field)
				* (0.5 + 0.5 * scree_grain);
			top_color = mix(top_color, rock_color * 0.96, clamp(scree * scree_strength, 0.0, 1.0));
			rock_normal_mask = max(rock_normal_mask, clamp(scree * scree_strength, 0.0, 1.0) * 0.70);

			// --- large aperiodic tone drift: keeps far zoom alive, no grid ---
			if (macro_drift_strength > 0.001 && macro_drift_scale_px > 1.0) {
				// Expand the naturally narrow fbm range into broad readable
				// soil/dust masses. Weight the tint toward open ground so the
				// macro pattern does not repaint dense grass as one flat wash.
				float drift = fbm2(world_pos / macro_drift_scale_px + vec2(3.1, -8.7));
				float drift_shape = smoothstep(0.32, 0.68, drift);
				float drift_brightness = mix(
					1.0 - macro_drift_strength,
					1.0 + macro_drift_strength,
					drift_shape
				);
				vec3 warm_tint = vec3(
					1.0 + macro_drift_strength * 0.40,
					1.0,
					1.0 - macro_drift_strength * 0.50
				);
				vec3 cool_tint = vec3(
					1.0 - macro_drift_strength * 0.15,
					1.0,
					1.0 + macro_drift_strength * 0.10
				);
				vec3 drift_tint = (
					drift_brightness
					* mix(cool_tint, warm_tint, drift_shape)
				);
				float open_ground_weight = mix(1.0, 0.38, grass_total);
				top_color *= mix(vec3(1.0), drift_tint, open_ground_weight);
			}

			// --- cosmetic large-scale shading (ADR-0005: visual only) ---
			// Ambient AO form (always on) sculpts large masses; a day-only
			// sun-directional component brightens sun-facing slopes and darkens
			// away-facing ones, faded by daylight via ground_sun_day.
			float shade_a = fbm2(world_pos / max(shade_scale_px, 1.0) + vec2(5.9, 21.7));
			float ambient_ao = mix(1.0 - shade_ambient_strength, 1.0 + shade_ambient_strength * 0.35, shade_a);
			vec2 sun_dir = vec2(cos(radians(ground_sun_angle_deg)), sin(radians(ground_sun_angle_deg)));
			float shade_b = fbm2((world_pos + sun_dir * shade_relief_px) / max(shade_scale_px, 1.0) + vec2(5.9, 21.7));
			float sun_slope = clamp(0.5 + (shade_b - shade_a) * shade_directional_gain, 0.0, 1.0);
			float directional = mix(1.0 - shade_dir_strength, 1.0 + shade_dir_strength * 0.6, sun_slope);
			top_color *= ambient_ao * mix(1.0, directional, clamp(ground_sun_day, 0.0, 1.0));

			if (debug_zone_mode > 0) {
				// This classification intentionally lives beside the real field
				// values: the lab never reimplements shader zones in GDScript.
				vec3 zone_color = mix(
					vec3(0.20, 0.11, 0.06),
					vec3(0.46, 0.31, 0.17),
					step(0.5, soil_mix)
				);
				debug_zone_id = step(0.5, soil_mix);
				if (grass_density_visual >= 0.12) {
					zone_color = vec3(0.62, 0.56, 0.20);
					debug_zone_id = 2.0;
				}
				if (grass_density_visual >= 0.26) {
					zone_color = vec3(0.39, 0.55, 0.18);
					debug_zone_id = 3.0;
				}
				if (grass_density_visual >= 0.40) {
					zone_color = vec3(0.20, 0.48, 0.16);
					debug_zone_id = 4.0;
				}
				if (grass_density_visual >= 0.56) {
					zone_color = vec3(0.08, 0.34, 0.13);
					debug_zone_id = 5.0;
				}
				if (path_open < 0.72) {
					zone_color = vec3(0.16, 0.66, 0.78);
					debug_zone_id = 6.0;
				}
				if (scree > 0.15) {
					zone_color = vec3(0.48, 0.42, 0.56);
					debug_zone_id = 7.0;
				}
				if (rock_region_visual > 0.22) {
					zone_color = vec3(0.34, 0.38, 0.40);
					debug_zone_id = 8.0;
				}
				if (orange_region > 0.20) {
					zone_color = vec3(1.0, 0.36, 0.08);
					debug_zone_id = 9.0;
				}
				top_color = zone_color;
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

		float output_alpha = mask.a;
		if (debug_zone_mode == 2) {
			output_alpha = (debug_zone_id + 1.0) / 16.0;
		}
		COLOR = vec4(final_color, output_alpha);
		if (temporary_disable_terrain_normals) {
			NORMAL_MAP = vec3(0.5, 0.5, 1.0);
		} else {
			vec3 shape_normal = unpack_normal(texture(shape_normal_atlas, UV).rgb);
			vec3 top_normal = unpack_normal(texture(top_normal_tex, top_uv).rgb);
			vec3 top_normal_secondary = unpack_normal(texture(top_normal_tex, top_uv_secondary).rgb);
			if (organic_strength > 0.001) {
				vec2 detail_uv = world_pos / max(detail_world_scale_px, 1.0);
				if (rock_normal_mask > 0.001) {
					vec3 rock_normal = unpack_normal(texture(rock_top_normal_tex, detail_uv * 1.12 + vec2(0.07, 0.61)).rgb);
					float rock_normal_mix = clamp(rock_normal_mask, 0.0, 0.90);
					top_normal = normalize(mix(top_normal, rock_normal, rock_normal_mix));
					top_normal_secondary = normalize(mix(top_normal_secondary, rock_normal, rock_normal_mix * 0.86));
				}
				if (grass_total > 0.001) {
					vec3 grass_normal = unpack_normal(texture(grass_normal_tex, detail_uv * 0.92 + vec2(0.11, 0.37)).rgb);
					float grass_normal_mix = grass_total * 0.55;
					top_normal = normalize(mix(top_normal, grass_normal, grass_normal_mix));
					top_normal_secondary = normalize(mix(top_normal_secondary, grass_normal, grass_normal_mix * 0.72));
				}
			}
			vec3 face_normal = unpack_normal(texture(face_normal_tex, face_uv).rgb);
			vec3 detail_normal = normalize(
				normalize(top_normal + top_normal_secondary) * top_mask +
				face_normal * face_mask +
				normalize(top_normal + top_normal_secondary) * back_mask
			);
			vec3 final_normal = blend_normals(shape_normal, detail_normal);
			NORMAL_MAP = final_normal * 0.5 + 0.5;
		}
	}
}
