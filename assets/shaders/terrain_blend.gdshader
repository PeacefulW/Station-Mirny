shader_type canvas_item;

// Текстуры биомов (бесшовные, 512×512)
uniform sampler2D tex_plains : repeat_enable, filter_linear;
uniform sampler2D tex_rock : repeat_enable, filter_linear;
uniform sampler2D tex_shore : repeat_enable, filter_linear;

// Карта типов (64×64, R канал = тип земли, nearest — без артефактов на стыках)
uniform sampler2D terrain_map : filter_nearest;

// Крыша горы (64×64, R=1 = крыша, R=0 = нет)
uniform sampler2D roof_map : filter_nearest;
// Прозрачность крыши (0 = скрыта, 1 = видна)
uniform float roof_opacity = 1.0;

// Масштаб текстур
uniform float texture_scale = 6.0;

// Размер и позиция чанка
uniform vec2 chunk_world_size = vec2(768.0, 768.0);
uniform vec2 chunk_world_offset = vec2(0.0, 0.0);

// Ручное сглаживание terrain_map (bilinear с клампом к границам чанка)
float sample_terrain_smooth(vec2 uv) {
    vec2 map_size = vec2(64.0);
    vec2 texel = uv * map_size - 0.5;
    vec2 f = fract(texel);
    vec2 base = (floor(texel) + 0.5) / map_size;
    vec2 px = vec2(1.0) / map_size;

    // Клампим UV к границам чанка (не семплируем за край)
    vec2 uv00 = clamp(base, vec2(0.0), vec2(1.0) - px);
    vec2 uv10 = clamp(base + vec2(px.x, 0.0), vec2(0.0), vec2(1.0) - px);
    vec2 uv01 = clamp(base + vec2(0.0, px.y), vec2(0.0), vec2(1.0) - px);
    vec2 uv11 = clamp(base + px, vec2(0.0), vec2(1.0) - px);

    float t00 = texture(terrain_map, uv00).r;
    float t10 = texture(terrain_map, uv10).r;
    float t01 = texture(terrain_map, uv01).r;
    float t11 = texture(terrain_map, uv11).r;

    return mix(mix(t00, t10, f.x), mix(t01, t11, f.x), f.y);
}

void fragment() {
    vec2 chunk_uv = UV;
    vec2 px = vec2(1.0) / vec2(64.0);

    // Мировые координаты → UV для бесшовного тайлинга
    vec2 world_pos = chunk_world_offset + chunk_uv * chunk_world_size;
    vec2 tex_uv = world_pos / (512.0 / texture_scale);

    // Тип земли (сглаженный, без стыков между чанками)
    float terrain_type = sample_terrain_smooth(chunk_uv);

    // Семплировать текстуры
    vec4 plains_color = texture(tex_plains, tex_uv);
    vec4 rock_color = texture(tex_rock, tex_uv);
    vec4 shore_color = texture(tex_shore, tex_uv);

    // Веса смешивания
    float w_plains = smoothstep(0.0, 0.15, 1.0 - abs(terrain_type - 0.0) * 4.0);
    float w_rock = smoothstep(0.0, 0.15, 1.0 - abs(terrain_type - 0.25) * 4.0);
    float w_shore = smoothstep(0.0, 0.15, 1.0 - abs(terrain_type - 0.75) * 4.0);
    float w_grass = smoothstep(0.0, 0.15, 1.0 - abs(terrain_type - 1.0) * 4.0);
    float w_water = smoothstep(0.35, 0.5, terrain_type) * smoothstep(0.65, 0.5, terrain_type);

    // Нормализация
    float total = w_plains + w_rock + w_shore + w_grass + w_water + 0.001;
    w_plains /= total; w_rock /= total; w_shore /= total;
    w_grass /= total; w_water /= total;

    // Смешивание земли
    vec4 ground_color = plains_color * (w_plains + w_grass)
                      + rock_color * w_rock
                      + shore_color * w_shore;

    // Анимированная вода
    float water_time = TIME * 0.5;
    vec4 water_color = vec4(0.12, 0.22, 0.28, 1.0);
    float wave = sin(world_pos.x * 0.05 + water_time) * cos(world_pos.y * 0.04 + water_time * 0.7);
    water_color.rgb += vec3(0.03) * wave;

    // Финальный цвет
    COLOR = ground_color * (1.0 - w_water) + water_color * w_water;

    // === БЕРЕГ ВОДЫ: обрыв-тень ===
    // Резкие значения (nearest) для определения границ
    float raw_type = texture(terrain_map, chunk_uv).r;
    float raw_up = texture(terrain_map, clamp(chunk_uv + vec2(0, -px.y), vec2(0.0), vec2(1.0))).r;

    float is_water = step(0.4, raw_type) * step(raw_type, 0.6);
    float up_not_water = 1.0 - step(0.4, raw_up) * step(raw_up, 0.6);
    float water_shadow = is_water * up_not_water;
    float dist_from_top = fract(chunk_uv.y * 64.0);
    water_shadow *= smoothstep(0.4, 0.0, dist_from_top);
    COLOR.rgb = mix(COLOR.rgb, shore_color.rgb * 0.35, water_shadow * 0.65);

    // === КРАЙ СКАЛЫ: южная боковая грань ===
    float is_not_rock = 1.0 - step(0.15, raw_type) * step(raw_type, 0.35);
    float is_flat = is_not_rock * (1.0 - is_water);
    float above_is_rock = step(0.15, raw_up) * step(raw_up, 0.35);
    float south_face = is_flat * above_is_rock;

    float face_dist = fract(chunk_uv.y * 64.0);
    float face_gradient = smoothstep(0.45, 0.0, face_dist);
    vec3 rock_face_color = rock_color.rgb * 0.4;
    COLOR.rgb = mix(COLOR.rgb, rock_face_color, south_face * face_gradient * 0.85);

    // Блик на краю
    float edge_highlight = south_face * smoothstep(0.06, 0.0, face_dist);
    COLOR.rgb += vec3(0.06) * edge_highlight;

    // === КРАЙ СКАЛЫ: левая грань (слабая) ===
    float raw_left = texture(terrain_map, clamp(chunk_uv + vec2(-px.x, 0), vec2(0.0), vec2(1.0))).r;
    float current_rock = step(0.15, raw_type) * step(raw_type, 0.35);
    float left_flat = 1.0 - step(0.15, raw_left) * step(raw_left, 0.35);
    left_flat *= 1.0 - step(0.4, raw_left) * step(raw_left, 0.6);
    float left_face = current_rock * left_flat;
    float left_dist = fract(chunk_uv.x * 64.0);
    float left_gradient = smoothstep(0.25, 0.0, left_dist);
    COLOR.rgb = mix(COLOR.rgb, rock_face_color, left_face * left_gradient * 0.4);

    // === КРЫША ГОРЫ ===
    float roof = texture(roof_map, chunk_uv).r;
    if (roof > 0.01) {
        vec4 roof_color = texture(tex_rock, tex_uv) * 0.85;
        // Край крыши — тень
        float roof_edge = smoothstep(0.3, 0.5, roof) * smoothstep(0.7, 0.5, roof);
        roof_color.rgb -= vec3(0.12) * roof_edge;
        float actual_opacity = roof * roof_opacity;
        COLOR = mix(COLOR, roof_color, actual_opacity);
    }

    // === FOG OF WAR: невыкопанный камень внутри горы ===
    // Когда крыша скрыта (roof_opacity < 1) и тайл = ROCK → чёрный
    float is_rock_raw = step(0.15, raw_type) * step(raw_type, 0.35);
    float fog = is_rock_raw * (1.0 - roof_opacity) * roof;
    COLOR.rgb = mix(COLOR.rgb, vec3(0.03, 0.02, 0.02), fog);
}
