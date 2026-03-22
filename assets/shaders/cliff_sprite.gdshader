shader_type canvas_item;

// Текстуры камня (бесшовные)
uniform sampler2D tex_top : repeat_enable, filter_linear;
uniform sampler2D tex_wall : repeat_enable, filter_linear;
uniform float texture_scale = 4.0;
uniform vec2 world_offset = vec2(0.0, 0.0);

void fragment() {
    vec4 mask = texture(TEXTURE, UV);
    float zone = mask.r;
    float alpha = mask.a;

    if (alpha < 0.01) { discard; }

    // Мировые UV для бесшовного тайлинга
    vec2 sprite_size = vec2(128.0, 128.0);
    vec2 world_uv = (world_offset + UV * sprite_size) / (512.0 / texture_scale);

    vec3 final_color;

    if (zone > 0.65) {
        // Кромка (lip) — осветлённая текстура верхушки
        final_color = texture(tex_top, world_uv).rgb * 1.35;
    } else if (zone > 0.4) {
        // Верхушка — текстура камня
        final_color = texture(tex_top, world_uv).rgb;
    } else if (zone > 0.1) {
        // Стенка — текстура + вертикальное затемнение
        vec3 wall_col = texture(tex_wall, world_uv).rgb;
        wall_col *= mix(0.85, 0.45, UV.y);
        final_color = wall_col;
    } else {
        // Тень
        final_color = vec3(0.04, 0.03, 0.05);
    }

    COLOR = vec4(final_color, alpha);
}
