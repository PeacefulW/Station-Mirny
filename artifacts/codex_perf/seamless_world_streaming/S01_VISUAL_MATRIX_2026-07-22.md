---
title: S1 Visual Reference Matrix
doc_type: visual_evidence
status: accepted
owner: engineering+design
source_of_truth: false
version: 1.0
last_updated: 2026-07-22
related_docs:
  - S01_BASELINE_CAPTURE_20260722_225301_036.md
  - S01_BASELINE_MANIFEST_2026-07-22.md
---

# S1 visual reference matrix

Все кадры сняты пользователем на probe `s1_mountain_runtime_baseline_v1`, seed
`131071`, worldgen prefix `b797f412`. Выбранные PNG и sidecar JSON скопированы
из `user://performance_captures/` в `S01_reference_images/`, чтобы recorder
retention не удалил baseline.

| Сценарий | Файл | Зафиксированное состояние |
|---|---|---|
| Day, plains + dense objects, zoom 0.2 | `day_plains_dense_zoom_0_2.png` | дневная палитра, трава, деревья, камни и тени; полный кадр в выбранный момент |
| Streaming failure, zoom 0.2 | `streaming_missing_chunks_zoom_0_2.png` | несколько крупных черных непрогруженных прямоугольников внутри viewport |
| Day, mountain close-up | `day_mountain_close.png` | гора/фут, ground и тени при 09:00 |
| Night, torch off | `night_mountain_torch_off.png` | 00:00, сцена почти полностью темная |
| Night, torch on | `night_mountain_torch_on.png` | теплый радиальный свет игрока освещает ground и край горы |
| Cave/tunnel, torch on | `cave_torch_on.png` | выкопано 6 единиц scrap; факел освещает узкий тоннель и cavity contour |
| Cave/tunnel, torch off | `cave_torch_off.png` | тот же тоннель без факела снова практически полностью темный |

## Functional conclusion

Torch toggle и cave lighting в baseline работают: пары on/off сделаны в одной
probe, с одинаковой позицией и разницей в четыре секунды. Копание также
сработало — HUD меняется с `Скрап ...: 0` на `6`, позиция игрока смещается внутрь
выкопанного прохода.

Это reference текущего визуала и функционала, который нельзя ухудшать на S2-S8.
Черные streaming holes, напротив, являются зафиксированным дефектом, а не
целевым визуалом.
