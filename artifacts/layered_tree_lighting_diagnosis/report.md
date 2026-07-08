# Layered Tree Lighting Diagnosis

All captures use the same tree asset, same position, wind frozen, season 0, and normal maps disabled.

| Case | Avg luma | vs raw | Meaning |
|---|---:|---:|---|
| `00_raw_textures_no_light` | 0.2370 | 1.000 | Texture layers only: no tree shader, no CanvasModulate, no DirectionalLight2D. |
| `00b_before_legacy_double_multiply_simulated` | 0.0781 | 0.330 | Simulated old shader bug: sampled tree color multiplied by itself, matching the pre-fix darkening. |
| `01_runtime_shader_no_light` | 0.2370 | 1.000 | Runtime layered shaders only, with wind frozen and season 0. |
| `02_canvas_day_only` | 0.2012 | 0.849 | Daylight CanvasModulate day ambient only. |
| `03_canvas_dawn_only` | 0.1216 | 0.513 | Daylight CanvasModulate dawn ambient only. |
| `04_canvas_dusk_only` | 0.1340 | 0.565 | Daylight CanvasModulate dusk ambient only. |
| `05_canvas_night_only` | 0.0078 | 0.033 | Daylight CanvasModulate night ambient only. |
| `06_canvas_overcast_day_only` | 0.1408 | 0.594 | Day ambient multiplied by full overcast weather tint. |
| `07_canvas_day_plus_sun` | 0.3020 | 1.274 | Day ambient plus runtime DirectionalLight2D sun. |
| `08_canvas_dawn_plus_sun` | 0.1765 | 0.745 | Dawn ambient plus low warm sun. |
| `09_raw_canvas_day_plus_sun` | 0.3020 | 1.274 | Raw texture layers under day ambient plus sun; isolates shader from Light2D. |

## Files

- `00_raw_textures_no_light`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/00_raw_textures_no_light.png`
- `00b_before_legacy_double_multiply_simulated`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/00b_before_legacy_double_multiply_simulated.png`
- `01_runtime_shader_no_light`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/01_runtime_shader_no_light.png`
- `02_canvas_day_only`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/02_canvas_day_only.png`
- `03_canvas_dawn_only`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/03_canvas_dawn_only.png`
- `04_canvas_dusk_only`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/04_canvas_dusk_only.png`
- `05_canvas_night_only`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/05_canvas_night_only.png`
- `06_canvas_overcast_day_only`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/06_canvas_overcast_day_only.png`
- `07_canvas_day_plus_sun`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/07_canvas_day_plus_sun.png`
- `08_canvas_dawn_plus_sun`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/08_canvas_dawn_plus_sun.png`
- `09_raw_canvas_day_plus_sun`: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/layered_tree_lighting_diagnosis/09_raw_canvas_day_plus_sun.png`