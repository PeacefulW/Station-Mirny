shader_type canvas_item;
render_mode blend_mix;

// This field is drawn after world objects but before UI. The screen copy is the
// already-lit world, so a generic PointLight2D can restore exactly the colour
// and relief that it contributed below the field without the field knowing the
// light's identity.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D live_mask_texture : filter_linear, repeat_disable;
uniform sampler2D closed_roof_mask_texture : filter_linear, repeat_disable;
uniform sampler2D sky_exposure_texture : filter_linear, repeat_disable;
uniform sampler2D reveal_selector_texture : filter_nearest, repeat_disable;
// The tile selector names the displayed component. The all-components dug
// guard keeps the one-tile organic fringe from inheriting a neighbouring
// foreign cavity when C-V crosses a tile boundary.
uniform sampler2D any_cutout_halo_texture : filter_nearest, repeat_disable;
// Same already-uploaded texture, rebound with linear filtering only for a
// conservative facade broad phase. It is never a second mask upload.
uniform sampler2D any_cutout_broad_texture : filter_linear, repeat_disable;

uniform vec2 chunk_origin_world = vec2(0.0);
uniform vec2 chunk_size_world = vec2(1024.0);
uniform vec2 mask_origin_world = vec2(0.0);
uniform vec2 mask_size_world = vec2(2048.0);
uniform vec2 selector_origin_world = vec2(0.0);
uniform vec2 selector_size_world = vec2(2048.0);
uniform float mask_sample_step_px = 8.0;
uniform float facade_height_px = 72.0;

// Day-reference cave floor. CanvasModulate can only lower this further, so the
// field never turns a darker night/overcast exterior into a brighter cave.
uniform float deep_cave_ambient_floor : hint_range(0.0, 1.0) = 0.12;
uniform vec3 deep_cave_color : source_color = vec3(0.055, 0.070, 0.110);
uniform float deep_darkness_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float darkness_ramp_gamma : hint_range(1.0, 3.0) = 1.35;
uniform float point_light_restore_gain : hint_range(0.0, 2.0) = 1.20;


float rect_inside(vec2 uv) {
	return step(0.0, uv.x) * step(0.0, uv.y)
			* step(uv.x, 1.0) * step(uv.y, 1.0);
}


vec2 world_to_mask_uv(vec2 world_px) {
	return (world_px - mask_origin_world) / max(mask_size_world, vec2(0.001));
}


vec2 world_to_selector_uv(vec2 world_px) {
	return (world_px - selector_origin_world) / max(selector_size_world, vec2(0.001));
}


float sample_closed(vec2 world_px) {
	vec2 uv = world_to_mask_uv(world_px);
	return smoothstep(0.42, 0.58, texture(closed_roof_mask_texture, uv).r)
			* rect_inside(uv);
}


float sample_live(vec2 world_px) {
	vec2 uv = world_to_mask_uv(world_px);
	return smoothstep(0.42, 0.58, texture(live_mask_texture, uv).r)
			* rect_inside(uv);
}


float sample_dug(vec2 world_px) {
	return sample_closed(world_px) * (1.0 - sample_live(world_px));
}


float sample_component_exact(vec2 world_px) {
	vec2 uv = world_to_selector_uv(world_px);
	float code = floor(texture(reveal_selector_texture, uv).r * 255.0 + 0.5);
	return step(127.5, code) * rect_inside(uv);
}


float sample_any_cutout_exact(vec2 world_px) {
	vec2 uv = world_to_selector_uv(world_px);
	float code = floor(texture(any_cutout_halo_texture, uv).r * 255.0 + 0.5);
	return step(127.5, code) * rect_inside(uv);
}


vec2 sample_active_foreign_exact_pair(vec2 world_px) {
	float active = sample_component_exact(world_px);
	float any_cutout = sample_any_cutout_exact(world_px);
	return vec2(active, any_cutout * (1.0 - active));
}


// C-V carries the final organic edge at 8 px/sample. Component ownership stays
// binary at tile resolution, but an AA/curved C-V fringe can enter an adjacent
// tile. Borrow from the guarded 3x3 neighbourhood only when the current tile is
// neither active nor owned by another excavated component.
vec2 sample_guarded_active_foreign_pair(vec2 world_px) {
	vec2 center_owners = sample_active_foreign_exact_pair(world_px);
	if (center_owners.x > 0.5 || center_owners.y > 0.5) {
		return center_owners;
	}
	vec2 selector_texel_world = selector_size_world
			/ max(vec2(textureSize(reveal_selector_texture, 0)), vec2(1.0));
	vec2 fringe_owners = vec2(0.0);
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(
		world_px + vec2(selector_texel_world.x, 0.0)
	));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(
		world_px - vec2(selector_texel_world.x, 0.0)
	));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(
		world_px + vec2(0.0, selector_texel_world.y)
	));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(
		world_px - vec2(0.0, selector_texel_world.y)
	));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(
		world_px + selector_texel_world
	));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(
		world_px - selector_texel_world
	));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(
		world_px + vec2(selector_texel_world.x, -selector_texel_world.y)
	));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(
		world_px + vec2(-selector_texel_world.x, selector_texel_world.y)
	));
	return fringe_owners;
}


float sample_any_cutout_broad(vec2 world_px) {
	vec2 uv = world_to_selector_uv(world_px);
	vec2 selector_size = max(vec2(textureSize(any_cutout_broad_texture, 0)), vec2(1.0));
	vec2 selector_texel = 1.0 / selector_size;
	vec2 safe_uv = clamp(uv, vec2(0.0), vec2(1.0) - selector_texel * 0.001);
	vec2 cell_center = (floor(safe_uv * selector_size) + vec2(0.5)) * selector_texel;
	// Four bilinear intersection probes conservatively cover the facade search
	// stencil. False positives are harmless because full-resolution C-V remains
	// the final proof before any pixel is darkened.
	float broad = texture(
		any_cutout_broad_texture,
		cell_center + selector_texel * vec2(-0.5, -0.5)
	).r;
	broad = max(broad, texture(
		any_cutout_broad_texture,
		cell_center + selector_texel * vec2(0.5, -0.5)
	).r);
	broad = max(broad, texture(
		any_cutout_broad_texture,
		cell_center + selector_texel * vec2(-0.5, 1.5)
	).r);
	broad = max(broad, texture(
		any_cutout_broad_texture,
		cell_center + selector_texel * vec2(0.5, 1.5)
	).r);
	return step(0.001, broad) * rect_inside(uv);
}


float sample_exposure(vec2 world_px) {
	vec2 uv = world_to_mask_uv(world_px);
	return texture(sky_exposure_texture, uv).r * rect_inside(uv);
}


// The construction ROOF intentionally omits C's original south structural
// facade so the real mouth remains visible from outside. Reconstruct only that
// same geometric band from C and intersect it with C-V; this is the persistent
// closed-roof visibility window, not an authored entrance shadow.
float sample_closed_mouth_coverage(vec2 world_px, float floor_dug) {
	if (floor_dug <= 0.001) {
		return 0.0;
	}
	float closed_here = sample_closed(world_px);
	if (closed_here < 0.5) {
		return 0.0;
	}
	float wall_samples = max(facade_height_px / max(mask_sample_step_px, 0.001), 1.0);
	int probe_count = int(min(ceil(wall_samples) + 2.0, 16.0));
	float edge_distance = -1.0;
	float previous = closed_here;
	for (int step_index = 1; step_index <= 16; step_index++) {
		if (step_index > probe_count) {
			break;
		}
		float current = sample_closed(
			world_px + vec2(0.0, float(step_index) * mask_sample_step_px)
		);
		if (current < 0.5 && previous >= 0.5) {
			float crossing = (previous - 0.5) / max(previous - current, 0.0001);
			edge_distance = float(step_index - 1) + clamp(crossing, 0.0, 1.0);
			break;
		}
		previous = current;
	}
	if (edge_distance < 0.0) {
		return 0.0;
	}
	float base_fade = smoothstep(-0.50, 0.15, edge_distance);
	float top_fade = 1.0 - smoothstep(
		wall_samples - 1.65,
		wall_samples + 1.65,
		edge_distance
	);
	return floor_dug * base_fade * top_fade;
}


void fragment() {
	// Parent red modulation carries one shared reveal scalar to every unit-white
	// chunk sprite. COLOR is replaced below, so this does not tint the field.
	float reveal_blend = clamp(COLOR.r, 0.0, 1.0);
	vec2 world_px = chunk_origin_world + UV * chunk_size_world;

	float floor_dug = sample_dug(world_px);
	float floor_coverage = 0.0;
	if (floor_dug > 0.001 && reveal_blend > 0.001) {
		vec2 floor_owners = sample_guarded_active_foreign_pair(world_px);
		floor_coverage = floor_dug * floor_owners.x
				* (1.0 - step(0.5, floor_owners.y));
	}
	float revealed_coverage = floor_coverage;
	float revealed_exposure = sample_exposure(world_px);

	// BASE(V)'s internal south-facing facade is still solid, so it is not part
	// of C-V itself. Find its first organic south edge, interpolate the crossing,
	// then borrow ownership/exposure from just inside the dug foot. Interpolating
	// one edge distance avoids the repeated 8 px contour bands produced by taking
	// the maximum of ten independent foot samples.
	float live_here = sample_live(world_px);
	float nearby_cutout = 0.0;
	if (reveal_blend > 0.001 && live_here > 0.001 && floor_coverage < 0.999) {
		nearby_cutout = sample_any_cutout_broad(world_px);
	}
	if (nearby_cutout > 0.5) {
		float facade_edge_distance = -1.0;
		float previous_dug = sample_dug(world_px);
		for (int step_index = 1; step_index <= 10; step_index++) {
			float distance_px = float(step_index) * max(mask_sample_step_px, 0.001);
			vec2 foot_world = world_px + vec2(0.0, distance_px);
			float current_dug = sample_dug(foot_world);
			if (facade_edge_distance < 0.0 && previous_dug < 0.5 && current_dug >= 0.5) {
				float crossing = (0.5 - previous_dug)
						/ max(current_dug - previous_dug, 0.0001);
				facade_edge_distance = (
					float(step_index - 1) + clamp(crossing, 0.0, 1.0)
				) * max(mask_sample_step_px, 0.001);
			}
			previous_dug = current_dug;
		}
		if (facade_edge_distance >= 0.0) {
			vec2 owned_foot_world = world_px + vec2(
				0.0,
				facade_edge_distance + mask_sample_step_px * 1.5
			);
			float owned_foot_dug = sample_dug(owned_foot_world);
			vec2 foot_owners = sample_guarded_active_foreign_pair(owned_foot_world);
			float within_facade = 1.0 - smoothstep(
				max(facade_height_px - mask_sample_step_px * 1.5, 0.0),
				facade_height_px + mask_sample_step_px * 1.5,
				facade_edge_distance
			);
			float facade_coverage = live_here * within_facade
					* smoothstep(0.02, 0.20, owned_foot_dug) * foot_owners.x
					* (1.0 - step(0.5, foot_owners.y));
			if (facade_coverage > revealed_coverage) {
				revealed_coverage = facade_coverage;
				revealed_exposure = sample_exposure(owned_foot_world);
			}
		}
	}

	float closed_mouth_coverage = sample_closed_mouth_coverage(world_px, floor_dug);
	float revealed_weight = revealed_coverage * reveal_blend;
	float coverage = closed_mouth_coverage;
	float exposure = sample_exposure(world_px);
	if (revealed_weight > coverage) {
		coverage = revealed_weight;
		exposure = revealed_exposure;
	}

	float natural_darkness_linear = smoothstep(0.04, 0.96, 1.0 - exposure);
	float natural_darkness = pow(natural_darkness_linear, darkness_ramp_gamma);
	float field_alpha = clamp(
		coverage * natural_darkness * deep_darkness_opacity,
		0.0,
		1.0
	);
	if (field_alpha <= 0.0001) {
		discard;
	}

	vec3 scene_color = texture(screen_texture, SCREEN_UV).rgb;
	vec3 authored_floor = deep_cave_color * (deep_cave_ambient_floor / 0.12);
	vec3 cave_floor = min(scene_color, authored_floor);
	COLOR = vec4(cave_floor, field_alpha);
}


void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		// DirectionalLight2D is open-sky sunlight and must not enter the cavity.
		LIGHT = vec4(0.0);
	} else {
		// LIGHT_COLOR already contains PointLight2D texture falloff. Restore the
		// pre-field world only where that generic local-light contribution exists.
		vec3 scene_color = texture(screen_texture, SCREEN_UV).rgb;
		vec3 restore = max(scene_color - COLOR.rgb, vec3(0.0));
		float local_light_weight = clamp(
			LIGHT_COLOR.a * LIGHT_ENERGY * point_light_restore_gain,
			0.0,
			1.0
		);
		SHADOW_MODULATE = vec4(1.0);
		LIGHT = vec4(restore, local_light_weight);
	}
}
