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
// Gravel relief: discrete lit micro-stones on open soil and paths. A jittered
// grid, NOT fbm — fbm produces regions without an edge, which is exactly why
// the scree above reads as dirt grain instead of stones. Each cell holds at
// most one stone with an analytic dome height, its own sun-directional shading
// and a contact shadow, so the ground gains volume with no normal map (terrain
// normals are inert) and not one placed instance.
// Visual-only: reads grass_density_visual / path_open / rock_region_visual and
// writes only top_color, so it stays outside the field-mirror law.
// See docs/02_system_specs/world/plains_ground_gravel_relief.md
uniform float gravel_cell_px = 30.0;
uniform float gravel_coverage = 0.55;
uniform float gravel_size_min = 0.20;
uniform float gravel_size_max = 0.54;
// Above 1.0 skews the calibre toward small stones, so a few large ones stand
// out of many fine ones instead of one uniform bumpy field.
uniform float gravel_size_bias = 1.4;
uniform float gravel_elongation = 1.6;
uniform float gravel_ambient_strength = 0.22;
uniform float gravel_relief_strength = 0.55;
uniform float gravel_shadow_strength = 0.45;
uniform float gravel_shadow_offset_px = 2.2;
uniform float gravel_tint = 0.35;
uniform float gravel_grass_start = 0.06;
uniform float gravel_grass_end = 0.26;
uniform float gravel_path_amount = 1.0;
uniform float gravel_rock_suppress = 0.80;
uniform float gravel_lod_fade_start_px = 5.0;
uniform float gravel_lod_fade_end_px = 11.0;
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
// Transient wet-ground presentation. Amount/rain default to zero, so dry
// worlds preserve the previous material exactly. All fields are world-space
// and reuse already-computed organic terrain signals below.
uniform float wet_ground_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wet_ground_rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float wet_ground_basin_contrast = 1.50;
uniform float wet_ground_grass_floor : hint_range(0.0, 1.0) = 0.32;
uniform float wet_ground_puddle_threshold : hint_range(0.0, 1.0) = 0.56;
uniform float wet_ground_darkening : hint_range(0.0, 1.0) = 0.32;
uniform float wet_ground_desaturation : hint_range(0.0, 1.0) = 0.22;
uniform vec4 wet_ground_puddle_tint : source_color = vec4(0.12, 0.19, 0.21, 1.0);
uniform float wet_ground_puddle_opacity : hint_range(0.0, 1.0) = 0.48;
uniform float wet_ground_impact_cell_px = 72.0;
uniform float wet_ground_impact_ring_width_px = 1.45;
uniform float wet_ground_impact_lifetime_seconds = 0.78;
uniform float wet_ground_impact_density : hint_range(0.0, 1.0) = 0.52;
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

			// --- gravel relief: lit micro-stones on open soil and paths ---
			// Sits above scree (which stays sub-object grain) and below the tone
			// drift + cosmetic shading, so the large masses modulate the stones
			// together with the soil under them instead of leaving them as a
			// separately lit layer floating on top.
			float gravel_open = 1.0 - smoothstep(gravel_grass_start, gravel_grass_end, grass_density_visual);
			float gravel_path = clamp((1.0 - path_open) * gravel_path_amount, 0.0, 1.0);
			float gravel_band = max(gravel_open, gravel_path);
			gravel_band *= 1.0 - clamp(rock_region_visual * gravel_rock_suppress, 0.0, 1.0);

			// One world unit measured in screen pixels. A 5..14 px stone drops
			// below one screen pixel as the camera pulls back, and a procedural
			// field has no mipmap to converge into, so it must be faded out
			// explicitly instead of shimmering. Derivatives are taken outside
			// the branch below: they require uniform control flow.
			float gravel_world_px = fwidth(world_pos.x) + fwidth(world_pos.y);
			float gravel_lod = 1.0 - smoothstep(gravel_lod_fade_start_px, gravel_lod_fade_end_px, gravel_world_px);
			float gravel_weight = clamp(gravel_band * gravel_lod, 0.0, 1.0);

			if (gravel_weight > 0.004) {
				float gravel_cell = max(gravel_cell_px, 4.0);
				vec2 gravel_base_cell = floor(world_pos / gravel_cell);
				// Direction TOWARD the sun. Its negation is the baked shadow
				// direction shared by every tree and rock asset, so there is
				// exactly one sun in frame.
				vec2 gravel_sun = vec2(cos(radians(ground_sun_angle_deg)), sin(radians(ground_sun_angle_deg)));
				float gravel_edge = max(gravel_world_px, 0.35);

				float stone_cover = 0.0;
				float stone_height = 0.0;
				vec2 stone_grad = vec2(0.0);
				float stone_id = 0.0;
				float stone_shadow = 0.0;

				for (int gy = -1; gy <= 1; gy++) {
					for (int gx = -1; gx <= 1; gx++) {
						vec2 gcell = gravel_base_cell + vec2(float(gx), float(gy));
						// An empty cell costs one hash and nothing else.
						if (hash12(gcell + vec2(3.7, 11.3)) > gravel_coverage) {
							continue;
						}
						// Jitter stays inside the middle half of the cell, so a
						// stone can never reach past the 3x3 walk above.
						vec2 gjit = vec2(
							hash12(gcell + vec2(19.1, 5.9)),
							hash12(gcell + vec2(-7.3, 27.7))
						);
						vec2 gcentre = (gcell + vec2(0.25) + gjit * 0.5) * gravel_cell;
						float gradius = mix(
							gravel_size_min,
							gravel_size_max,
							pow(hash12(gcell + vec2(41.9, -13.1)), max(gravel_size_bias, 0.05))
						) * gravel_cell;
						// Stones are not discs: a per-cell heading plus a squash
						// on the cross axis gives elongated pebbles.
						float gang = hash12(gcell + vec2(8.3, 63.1)) * 6.2831853;
						vec2 gaxis = vec2(cos(gang), sin(gang));
						vec2 gperp = vec2(-gaxis.y, gaxis.x);
						float gsquash = mix(1.0, max(gravel_elongation, 1.0), hash12(gcell + vec2(-31.7, 4.4)));

						vec2 gd = world_pos - gcentre;
						vec2 gdl = vec2(dot(gd, gaxis), dot(gd, gperp) * gsquash);
						float gdist = length(gdl);
						float gcover = 1.0 - smoothstep(gradius - gravel_edge, gradius, gdist);
						if (gcover > 0.0) {
							// Keep the widest coverage so overlapping stones
							// never let a sliver of soil through their union.
							stone_cover = max(stone_cover, gcover);
							float gt2 = clamp((gdist * gdist) / max(gradius * gradius, 0.001), 0.0, 1.0);
							float gh = sqrt(max(1.0 - gt2, 0.0));
							if (gh >= stone_height) {
								stone_height = gh;
								// Analytic dome gradient, rotated back into world
								// space. Falls out of values already computed, so
								// it costs no extra sample.
								vec2 grad_local = -gdl / max(gradius * gradius * max(gh, 0.12), 0.001);
								stone_grad = grad_local.x * gaxis + grad_local.y * gperp * gsquash;
								stone_id = hash12(gcell + vec2(77.7, 12.9));
							}
						}

						// Contact shadow: the same silhouette pushed away from
						// the sun, softened toward its rim.
						vec2 gds = world_pos - (gcentre - gravel_sun * gravel_shadow_offset_px);
						vec2 gdsl = vec2(dot(gds, gaxis), dot(gds, gperp) * gsquash);
						stone_shadow = max(
							stone_shadow,
							1.0 - smoothstep(gradius * 0.55, gradius * 1.05, length(gdsl))
						);
					}
				}

				// Contact shadow first, and only where no stone covers this
				// fragment: a stone must never wear its neighbour's shadow.
				// Day-only, like every other directional term here.
				float gravel_day = clamp(ground_sun_day, 0.0, 1.0);
				float shadow_here = stone_shadow * (1.0 - stone_cover) * gravel_shadow_strength * gravel_weight * gravel_day;
				top_color *= 1.0 - shadow_here * 0.55;

				if (stone_cover > 0.0) {
					// Ambient form survives the night (the rim of a dome is
					// always darker than its crown); the directional term fades
					// with daylight, mirroring the cosmetic shading model.
					float gravel_ambient = mix(1.0 - gravel_ambient_strength, 1.0, stone_height);
					float gravel_lambert = dot(normalize(stone_grad + vec2(1e-5, 1e-5)), -gravel_sun);
					float gravel_lit = gravel_ambient * (
						1.0 + gravel_lambert * gravel_relief_strength * stone_height * gravel_day
					);
					vec3 stone_color = mix(
						top_color,
						rock_color * mix(0.88, 1.12, stone_id),
						clamp(gravel_tint, 0.0, 1.0)
					) * gravel_lit;
					top_color = mix(top_color, stone_color, stone_cover * gravel_weight);
				}
			}

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

			// --- rain skin: broad wet soil, sparse puddles, analytic impacts ---
			// No new noise field is sampled here. Soil, macro tone and the ambient
			// form field already describe stable low areas at three useful scales.
			if (wet_ground_amount > 0.001) {
				float wet_amount = clamp(wet_ground_amount, 0.0, 1.0);
				float basin_source = clamp(
					(1.0 - soil_field) * 0.48
						+ (1.0 - shade_a) * 0.34
						+ (1.0 - top_macro) * 0.18
						+ (1.0 - path_open) * 0.10,
					0.0,
					1.0
				);
				float basin = remap_contrast(
					basin_source,
					max(wet_ground_basin_contrast, 0.1)
				);
				float wet_patch = smoothstep(0.24, 0.72, basin);
				float grass_response = mix(
					1.0,
					clamp(wet_ground_grass_floor, 0.0, 1.0),
					smoothstep(0.18, 0.72, grass_density_visual)
				);
				float wet_mask = wet_amount
					* mix(0.30, 1.0, wet_patch)
					* grass_response
					* (1.0 - rock_region_visual * 0.24);
				float wet_luma = luma(top_color);
				top_color = mix(
					top_color,
					vec3(wet_luma),
					clamp(wet_ground_desaturation, 0.0, 1.0) * wet_mask
				);
				top_color *= 1.0 - clamp(wet_ground_darkening, 0.0, 1.0) * wet_mask;

				float bare_surface = (1.0 - smoothstep(0.08, 0.38, grass_density_visual))
					* (1.0 - rock_region_visual * 0.92);
				float puddle_start = clamp(wet_ground_puddle_threshold, 0.0, 0.95);
				float puddle_shape = smoothstep(
					puddle_start,
					min(puddle_start + 0.15, 1.0),
					basin
				);
				float puddle = wet_amount * puddle_shape * bare_surface;
				float puddle_mix = clamp(
					puddle * wet_ground_puddle_opacity,
					0.0,
					1.0
				);
				top_color = mix(top_color, wet_ground_puddle_tint.rgb, puddle_mix);
				float puddle_edge = smoothstep(
					max(puddle_start - 0.035, 0.0),
					puddle_start + 0.02,
					basin
				) * (1.0 - smoothstep(
					puddle_start + 0.07,
					min(puddle_start + 0.16, 1.0),
					basin
				)) * wet_amount * bare_surface;
				vec3 cold_silver = mix(
					wet_ground_puddle_tint.rgb,
					vec3(0.78, 0.84, 0.85),
					0.48
				);
				top_color = mix(
					top_color,
					cold_silver,
					puddle_edge * wet_ground_puddle_opacity * 0.22
				);

				float rain_now = clamp(wet_ground_rain_intensity, 0.0, 1.0);
				float impact_surface = max(puddle, wet_mask * 0.34) * bare_surface;
				// Reuse the existing procedural-detail derivative and LOD. Rings
				// lose their readable contour earlier than stones, so their fade
				// begins before the gravel cutoff; far zoom skips every hash and
				// distance operation for the whole draw.
				float impact_lod_start = max(gravel_lod_fade_start_px * 0.45, 1.0);
				float impact_lod = gravel_lod * (1.0 - smoothstep(
					impact_lod_start,
					max(gravel_lod_fade_start_px, impact_lod_start + 0.1),
					gravel_world_px
				));
				if (rain_now > 0.002 && impact_surface > 0.002 && impact_lod > 0.004) {
					float impact_cell = max(wet_ground_impact_cell_px, 24.0);
					vec2 impact_id = floor(world_pos / impact_cell);
					float impact_presence = step(
						1.0 - clamp(wet_ground_impact_density * rain_now, 0.0, 1.0),
						hash12(impact_id + vec2(23.7, -41.1))
					);
					vec2 impact_jitter = vec2(
						hash12(impact_id + vec2(5.3, 17.9)),
						hash12(impact_id + vec2(-31.7, 9.1))
					);
					vec2 impact_center = (
						impact_id + vec2(0.25) + impact_jitter * 0.50
					) * impact_cell;
					float impact_phase = fract(
						TIME / max(wet_ground_impact_lifetime_seconds, 0.05)
							+ hash12(impact_id + vec2(71.3, 2.7))
					);
					float impact_radius = mix(
						impact_cell * 0.025,
						impact_cell * 0.18,
						impact_phase
					);
					float impact_distance = length(world_pos - impact_center);
					float impact_edge = max(
						wet_ground_impact_ring_width_px,
						gravel_world_px * 0.65
					);
					float impact_ring = 1.0 - smoothstep(
						impact_edge,
						impact_edge + max(gravel_world_px, 0.35),
						abs(impact_distance - impact_radius)
					);
					float impact_fade = smoothstep(0.0, 0.08, impact_phase)
						* (1.0 - smoothstep(0.55, 1.0, impact_phase));
					float impact_alpha = impact_ring
						* impact_presence
						* impact_fade
						* rain_now
						* impact_surface
						* impact_lod
						* min(wet_ground_puddle_opacity * 1.65, 0.68);
					top_color = mix(top_color, cold_silver, impact_alpha);
				}
			}

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
