shader_type canvas_item;
render_mode blend_mix;

uniform float atlas_columns = 8.0;
uniform float atlas_rows = 4.0;
uniform float atlas_frame_count = 32.0;
uniform float wind_time = 0.0;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_strength_px = 0.0;

void vertex() {
	float wind_phase = COLOR.b * 6.28318530718;
	float sway = sin(wind_time + wind_phase) * wind_strength_px;
	VERTEX += normalize(wind_direction) * sway * UV.y;
}

void fragment() {
	vec4 instance_data = COLOR;
	float frame_index = floor(clamp(instance_data.r * 255.0 + 0.5, 0.0, atlas_frame_count - 1.0));
	float frame_x = mod(frame_index, atlas_columns);
	float frame_y = floor(frame_index / atlas_columns);
	vec2 atlas_cell_size = vec2(1.0 / atlas_columns, 1.0 / atlas_rows);
	vec2 atlas_uv = (vec2(frame_x, frame_y) + UV) * atlas_cell_size;
	vec4 atlas_color = texture(TEXTURE, atlas_uv);
	float tint = clamp(instance_data.g, 0.0, 1.0);
	COLOR = atlas_color * vec4(tint, tint, tint, instance_data.a);
}
