shader_type canvas_item;
render_mode blend_mix;

uniform float atlas_columns = 4.0;
uniform float atlas_rows = 4.0;
uniform float atlas_frame_count = 16.0;
uniform float wind_time = 0.0;
uniform float wind_speed = 0.85;
uniform vec2 wind_direction = vec2(1.0, -0.15);
uniform float wind_strength_px = 2.6;
uniform float gust_strength = 0.18;
uniform float alpha_cutoff = 0.02;

varying vec4 instance_data;

void vertex() {
	instance_data = COLOR;
	float wind_phase = instance_data.b * 6.28318530718;
	float blade_weight = smoothstep(0.05, 1.0, UV.y);
	float t = wind_time * wind_speed;
	float primary = sin(t * 0.92 + wind_phase);
	float flutter = sin(t * 1.45 + wind_phase * 1.73 + UV.y * 1.30);
	float gust = sin(t * 0.28 + wind_phase * 0.41);
	float sway = (primary * 0.58 + flutter * 0.13 + gust * gust_strength) * wind_strength_px;
	VERTEX += normalize(wind_direction) * sway * blade_weight * blade_weight;
}

void fragment() {
	float frame_index = floor(clamp(instance_data.r * 255.0 + 0.5, 0.0, atlas_frame_count - 1.0));
	float frame_x = mod(frame_index, atlas_columns);
	float frame_y = floor(frame_index / atlas_columns);
	vec2 atlas_cell_size = vec2(1.0 / atlas_columns, 1.0 / atlas_rows);
	vec2 atlas_sample_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 atlas_uv = (vec2(frame_x, frame_y) + atlas_sample_uv) * atlas_cell_size;
	vec4 atlas_color = texture(TEXTURE, atlas_uv);
	if (atlas_color.a <= alpha_cutoff) {
		discard;
	}
	float tint = clamp(instance_data.g, 0.0, 1.35);
	COLOR = vec4(atlas_color.rgb * tint, atlas_color.a * instance_data.a);
}
