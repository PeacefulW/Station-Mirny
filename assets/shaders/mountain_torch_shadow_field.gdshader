shader_type canvas_item;
render_mode blend_mix, unshaded;

// Mountain torch shadow field — docs/02_system_specs/world/world_dynamic_lighting_2d.md
// Iteration 2 (redesign). World-space occlusion darkening that replaces the per-chunk
// LightOccluder2D geometry ChunkView used to rebuild on every dig. For each fragment
// inside the torch pool it marches a straight line toward the torch through the
// (stitched) mountain solid mask; where solid rock lies on that line the fragment is
// dark — dug pocket floor behind a wall, ground around a corner, and the wall FACADE
// itself where the torch has no line of sight to its foot.
//
// Two surfaces, one occlusion source:
//   - OPEN ground: occlusion is line of sight from the fragment to the torch.
//   - FACADE (solid with an open foot within facade_height to the south): occlusion is
//     line of sight from the wall FOOT to the torch, so the floor shadow climbs the
//     wall — a facade around a corner falls dark like the floor below it.
//   - ROOF (solid, no open foot in reach): left alone; the mountain sprite already
//     draws it dark (no torch acceptance). The field never lightens, only darkens.
//
// Why a shader field instead of engine occluders:
//   - No CPU geometry rebuild on digging: the solid mask is already uploaded for the
//     mountain sprite, so this pass is free of the marching-squares / node-churn spike.
//   - Samples the SMOOTHED mask (mask_to_top-style smoothstep), so the shadow edge
//     follows the silhouette instead of showing tile-quantized square/step bands.
//   - blend_mix (NOT blend_mul): a multiply pass under the Daylight CanvasModulate would
//     have its white "no-op" multiplier tinted dark by night and would darken all ground.
//     With blend_mix, alpha == 0 outside the shadow is a true no-op at any ambient.
//
// Presentation only (ADR-0005 / ADR-0007 layer 4): not a gameplay visibility authority,
// not saved.

// Compile-time UPPER bound on march samples (constant so the Compatibility backend can
// unroll). The march uses a WORLD-CONSTANT step (`march_step_px`) and breaks once it
// reaches the torch, so effective samples = min(MARCH_MAX, d / march_step_px). A fixed
// fraction of d would grow the step with distance and skip thin walls near the pool edge
// (a 1-tile / 64 px dug wall could fall between two samples). Invariant:
// MARCH_MAX * march_step_px must be >= torch_radius_px so the whole pool is covered.
const int MARCH_MAX = 64;
// Upper bound on the southward foot search for a facade fragment
// (facade_height / facade_foot_step_px). Kept separate from the ray-march step:
// a coarse 10 px search quantizes wall self-occlusion into visible ribbed bands.
const int FACADE_MAX = 32;

// Set every frame by WorldViewOverlay._process (do not write these here).
uniform vec2 view_world_origin = vec2(0.0);
uniform vec2 view_world_size = vec2(1920.0, 1080.0);

// Stitched mountain solid mask around the player (blit from mountain_solid_halo).
uniform sampler2D mountain_mask : filter_linear, repeat_disable;
uniform vec2 mask_origin_px = vec2(0.0);      // world px of mask texel (0,0)
uniform vec2 mask_size_px = vec2(1.0, 1.0);   // world px the whole mask covers
// Solid cutoff mirrors the mountain sprite's mask_to_top smoothstep band so the
// shadow silhouette lines up with the visible rock silhouette.
uniform float mask_threshold_low = 0.40;
uniform float mask_threshold_high = 0.58;
// South wall-strip height (mirrors the mountain sprite's facade_height_px material set),
// used to find a facade fragment's open foot and to tell facade from roof.
uniform float facade_height_px = 72.0;

uniform vec2 torch_world_pos = vec2(0.0);
uniform float torch_radius_px = 563.0;
// World-space distance between march samples. Must stay below the thinnest solid
// feature the shadow needs to catch (a 1-tile dug wall is 64 px). Matching the mask
// resolution (~8-10 px) also keeps the umbra edge from aliasing into stair teeth.
uniform float march_step_px = 10.0;
// Fine southward search step used only to find a facade fragment's open foot.
uniform float facade_foot_step_px = 4.0;
// Push the chosen foot slightly into open ground; otherwise a smoothed mask crossing
// can leave the origin on the rock edge and front-lit walls self-shadow in bands.
uniform float foot_open_bias_px = 6.0;
// 0 = torch off (whole pass is a no-op), 1 = enabled torch at normal energy.
uniform float torch_strength = 0.0;

// Near-black night ground; the occluded floor reads as "not in the torch pool".
uniform vec3 shadow_color = vec3(0.0, 0.0, 0.0);
uniform float shadow_opacity = 0.85;
// Fraction of the radius where the shadow starts to dissolve, so it fades with the
// light pool instead of ending on a hard ring.
uniform float pool_edge_fade = 0.80;

// 0 = open ground, 1 = solid mountain roof/rock at this world position.
float mask_solid(vec2 world_px) {
	vec2 uv = (world_px - mask_origin_px) / max(mask_size_px, vec2(1.0));
	// Outside the stitched window there is no known blocker -> treat as open.
	float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
	float m = texture(mountain_mask, clamp(uv, vec2(0.0), vec2(1.0))).r;
	return inside * smoothstep(mask_threshold_low, mask_threshold_high, m);
}

// Visibility along the straight line from `origin` (open ground) to the torch.
// World-constant step + early break -> reliable across the whole pool. We sample a
// small cross-section and accumulate transmittance instead of a hard max blocker:
// thick rock still reaches zero, but silhouettes/penumbra do not alias into a
// binary jagged saw.
float line_visibility(vec2 origin, vec2 torch, float dist) {
	vec2 dir = (torch - origin) / max(dist, 0.001);
	vec2 side = vec2(-dir.y, dir.x);
	float visibility = 1.0;
	for (int i = 1; i <= MARCH_MAX; i++) {
		float march_dist = float(i) * march_step_px;
		if (march_dist >= dist) {
			break;
		}
		float t = march_dist / max(dist, 0.001);
		float spread = mix(2.0, 12.0, t);
		vec2 center = origin + dir * march_dist;
		float solid = mask_solid(center) * 0.50
			+ mask_solid(center + side * spread) * 0.25
			+ mask_solid(center - side * spread) * 0.25;
		visibility *= 1.0 - clamp(solid * 0.86, 0.0, 0.96);
	}
	return clamp(visibility, 0.0, 1.0);
}

void fragment() {
	// return is forbidden in Godot fragment()/vertex(); branch with a default alpha.
	float alpha = 0.0;
	if (torch_strength > 0.001) {
		vec2 world_px = view_world_origin + UV * view_world_size;
		float d_frag = distance(world_px, torch_world_pos);
		if (d_frag <= torch_radius_px) {
			float self_solid = mask_solid(world_px);
			// Choose the occlusion ORIGIN (must be open ground):
			//  - open fragment      -> itself;
			//  - facade fragment    -> its open foot to the south (shadow climbs the wall);
			//  - roof fragment      -> none (leave dark rock to the sprite).
			vec2 origin = world_px;
			float evaluate = 1.0;
			if (self_solid >= 0.5) {
				evaluate = 0.0;
				float previous_solid = self_solid;
				float previous_south = 0.0;
				for (int j = 1; j <= FACADE_MAX; j++) {
					float south = float(j) * facade_foot_step_px;
					if (south > facade_height_px) {
						break;  // deep interior -> roof, not a facade
					}
					vec2 foot = world_px + vec2(0.0, south);
					float current_solid = mask_solid(foot);
					if (current_solid < 0.5 && previous_solid >= 0.5) {
						float cross = clamp(
							(previous_solid - 0.5) / max(previous_solid - current_solid, 0.0001),
							0.0,
							1.0
						);
						float foot_south = mix(previous_south, south, cross) + foot_open_bias_px;
						origin = world_px + vec2(0.0, foot_south);
						evaluate = 1.0;
						break;
					}
					previous_solid = current_solid;
					previous_south = south;
				}
			}
			if (evaluate > 0.5) {
				float d_origin = distance(origin, torch_world_pos);
				float visibility = line_visibility(origin, torch_world_pos, d_origin);
				float pool = 1.0 - smoothstep(torch_radius_px * pool_edge_fade, torch_radius_px, d_frag);
				alpha = (1.0 - visibility) * pool * torch_strength * shadow_opacity;
			}
		}
	}
	COLOR = vec4(shadow_color, clamp(alpha, 0.0, 1.0));
}
