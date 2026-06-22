shader_type canvas_item;
render_mode blend_mix;

// Батч-шейдер деревьев: атлас-сэмплинг как у world_decor_atlas_batch, но ветер —
// от ОБЩИХ глобальных wind-униформ (их пишет WindRuntime один раз/кадр, ноль
// per-material broadcast — в отличие от локального wind_strength_px декора).
// Крона гнётся (вес по UV.y), основание стоит; смещение считается в долях высоты
// дерева и заводится обратно инверсией 2x2 instance-трансформа (без растяжения).
// Контракт: docs/02_system_specs/world/plains_trees_presentation.md

uniform float atlas_columns = 4.0;
uniform float atlas_rows = 4.0;
uniform float atlas_frame_count = 16.0;

global uniform float wind_time;
global uniform vec2 wind_direction;
global uniform float wind_strength;

uniform float sway_fraction = 0.09;

varying vec4 instance_data;

void vertex() {
	instance_data = COLOR;
	float phase = instance_data.b * 6.28318530718;
	float primary = sin(wind_time * 0.55 + phase);
	float secondary = sin(wind_time * 0.95 + phase * 1.7);
	float gate = smoothstep(0.0, 0.12, wind_strength);
	float osc = (primary * 0.7 + secondary * 0.3) * sway_fraction;
	// Вес кроны: PNG-верх (крона) на UV.y=1, основание на UV.y=0 → вес = UV.y^2.
	float weight = clamp(UV.y, 0.0, 1.0);
	weight *= weight;
	float amount = osc * gate * weight;
	mat2 model_2x2 = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
	float det = model_2x2[0].x * model_2x2[1].y - model_2x2[1].x * model_2x2[0].y;
	float safe_det = abs(det) > 0.000001 ? det : 0.000001;
	mat2 inv_model_2x2 = mat2(
		vec2(model_2x2[1].y, -model_2x2[0].y),
		vec2(-model_2x2[1].x, model_2x2[0].x)
	) / safe_det;
	float tree_height_px = length(MODEL_MATRIX[1].xy);
	vec2 dir = normalize(wind_direction + vec2(0.0001, 0.0));
	vec2 world_offset = dir * amount * tree_height_px;
	VERTEX += inv_model_2x2 * world_offset;
}

void fragment() {
	float frame_index = floor(clamp(instance_data.r * 255.0 + 0.5, 0.0, atlas_frame_count - 1.0));
	float frame_x = mod(frame_index, atlas_columns);
	float frame_y = floor(frame_index / atlas_columns);
	vec2 atlas_cell_size = vec2(1.0 / atlas_columns, 1.0 / atlas_rows);
	vec2 atlas_sample_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 atlas_uv = (vec2(frame_x, frame_y) + atlas_sample_uv) * atlas_cell_size;
	vec4 atlas_color = texture(TEXTURE, atlas_uv);
	float tint = clamp(instance_data.g, 0.0, 1.0);
	COLOR = atlas_color * vec4(tint, tint, tint, instance_data.a);
}
