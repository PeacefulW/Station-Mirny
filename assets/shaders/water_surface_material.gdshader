shader_type canvas_item;

// Full-chunk water fill. On shoreline chunks the fill is clipped by the same
// terrain-edge native mask that drives the shore band, so the visible water
// contour and the packed-shore strip share one organic silhouette. Without a
// mask the fill is either fully hidden (no water in the chunk) or full-rect
// (deep water far from any shore).

uniform sampler2D water_albedo : repeat_enable, filter_linear;
uniform float water_world_scale_px = 1024.0;
uniform sampler2D land_mask : filter_linear, repeat_disable;
uniform float land_mask_enabled = 0.0;
uniform vec2 land_mask_uv_offset = vec2(0.0, 0.0);
uniform vec2 land_mask_uv_scale = vec2(1.0, 1.0);
uniform float land_threshold_low = 0.16;
uniform float land_threshold_high = 0.34;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	vec3 albedo = texture(water_albedo, world_pos / water_world_scale_px).rgb;
	float water_alpha = mask.a;
	if (land_mask_enabled > 0.5) {
		vec2 mask_uv = UV * land_mask_uv_scale + land_mask_uv_offset;
		float solid = smoothstep(land_threshold_low, land_threshold_high, texture(land_mask, mask_uv).r);
		water_alpha *= 1.0 - solid;
	}
	COLOR = vec4(albedo, water_alpha);
}
