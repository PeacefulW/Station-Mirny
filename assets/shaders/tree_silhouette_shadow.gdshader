shader_type canvas_item;
render_mode blend_mix;

// Силуэт-тень дерева: та же атлас-текстура, но вершинный сдвиг «кладёт» силуэт на
// землю по направлению от солнца (крона уезжает по shadow_dir с сжатием,
// основание стоит), фрагмент — тёмный по альфе. Один материал на shadow-слой.
// Контракт: docs/02_system_specs/world/plains_trees_presentation.md

uniform float atlas_columns = 4.0;
uniform float atlas_rows = 4.0;
uniform float atlas_frame_count = 16.0;
uniform vec2 shadow_dir = vec2(0.62, 0.58);
uniform float shadow_foreshorten = 0.5;
uniform float shadow_opacity = 0.30;

varying vec4 instance_data;

void vertex() {
	instance_data = COLOR;
	// h: 0 у основания (низ кадра), ~0.9 у кроны (верх кадра).
	float h = clamp(UV.y, 0.0, 1.0);
	float tree_height_px = length(MODEL_MATRIX[1].xy);
	vec2 dir = normalize(shadow_dir + vec2(0.0001, 0.0));
	mat2 model_2x2 = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
	float det = model_2x2[0].x * model_2x2[1].y - model_2x2[1].x * model_2x2[0].y;
	float safe_det = abs(det) > 0.000001 ? det : 0.000001;
	mat2 inv_model_2x2 = mat2(
		vec2(model_2x2[1].y, -model_2x2[0].y),
		vec2(-model_2x2[1].x, model_2x2[0].x)
	) / safe_det;
	// Уложить вертикаль на землю по shadow_dir: вверх (0,-1) -> dir*foreshorten.
	vec2 world_offset = h * tree_height_px * (dir * shadow_foreshorten + vec2(0.0, 1.0));
	VERTEX += inv_model_2x2 * world_offset;
}

void fragment() {
	float frame_index = floor(clamp(instance_data.r * 255.0 + 0.5, 0.0, atlas_frame_count - 1.0));
	float frame_x = mod(frame_index, atlas_columns);
	float frame_y = floor(frame_index / atlas_columns);
	vec2 atlas_cell_size = vec2(1.0 / atlas_columns, 1.0 / atlas_rows);
	vec2 atlas_sample_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 atlas_uv = (vec2(frame_x, frame_y) + atlas_sample_uv) * atlas_cell_size;
	float a = texture(TEXTURE, atlas_uv).a;
	COLOR = vec4(0.05, 0.035, 0.02, a * shadow_opacity);
}
