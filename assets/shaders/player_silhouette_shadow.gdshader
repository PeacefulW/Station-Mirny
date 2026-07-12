shader_type canvas_item;
render_mode blend_mix, unshaded;

// Player silhouette shadow (V1): the animated frame is LAID DOWN onto the ground
// away from the sun (like the tree shadows) — its height is projected ALONG
// shadow_dir instead of being squashed flat, so it reads as an elongated
// person-shaped shadow rather than a flat strip. It pivots at the per-frame feet
// contact line and is re-grounded to one fixed ground line each frame.
//
// contact_uv_y: per-frame baked feet line (frame_contact_uv); ground_uv_y: fixed
// ground line; shadow_projection: how far the figure height lays out (length).
// Contract: docs/02_system_specs/progression/player_sun_shadow_v0.md

uniform vec2 shadow_dir = vec2(0.70710678, 0.70710678);
uniform float shadow_projection = 0.7;
uniform float shadow_opacity = 0.0;
uniform float sprite_height_px = 256.0;
uniform float contact_uv_y = 0.773;
uniform float ground_uv_y = 0.773;
uniform vec4 shadow_color : source_color = vec4(0.045, 0.036, 0.026, 1.0);

void vertex() {
	float contact_vy = (contact_uv_y - 0.5) * sprite_height_px;
	float ground_vy = (ground_uv_y - 0.5) * sprite_height_px;
	// Signed height above the feet contact line. SIGNED (not clamped): the whole
	// transform stays affine in VERTEX, so the interior feet line of the 4-vertex
	// quad lands EXACTLY on the ground line every frame (zero wander). Transparent
	// padding below the feet lays out the other way — invisible.
	float height_above = contact_vy - VERTEX.y;
	vec2 dir = normalize(shadow_dir + vec2(0.0001, 0.0001));
	// Lay the figure down onto the ground along shadow_dir, anchored at the feet:
	// drop the vertical extent and re-project it as length on the ground plane.
	VERTEX.x += height_above * dir.x * shadow_projection;
	VERTEX.y = contact_vy + height_above * dir.y * shadow_projection;
	// Re-ground: pin the per-frame contact onto the fixed ground line.
	VERTEX.y += ground_vy - contact_vy;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float alpha = source.a * shadow_opacity;
	COLOR = vec4(shadow_color.rgb, alpha);
}
