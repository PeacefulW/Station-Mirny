---
title: S1 Deterministic Baseline Manifest
doc_type: performance_evidence
status: accepted
owner: engineering+design
source_of_truth: false
version: 1.0
last_updated: 2026-07-22
related_docs:
  - ../../../docs/00_governance/SEAMLESS_WORLD_STREAMING_TASK.md
  - ../../../docs/02_system_specs/ui/performance_flight_recorder.md
---

# S1 — детерминированный baseline

## Состояние

Runtime-оптимизации не выполнялись. Конфигурация, детерминизм, оконный F4 route
и visual matrix подтверждены. Пользователь принял S1 2026-07-22; статус
`accepted`.

## Измерительный стенд

| Поле | Значение |
|---|---|
| Scene | `res://scenes/dev/mountain_runtime_dig_dev_scene.tscn` |
| Probe ID | `s1_mountain_runtime_baseline_v1` |
| Runtime | настоящий `world_runtime_v0`, без presentation-подмен |
| Git runtime baseline | `121331d878d1985969dd8822c8d2f388f7996eb8` |
| World seed | `131071` |
| World version | `63` |
| Worldgen signature | `b797f4120400f757a08bf5a14e6a6c09721e51fd` |
| Initial time | day 1, 09:00, paused |
| Weather | `core:clear`, fixed dev regime |
| Initial camera zoom | `1.0` |
| Allowed zoom range | `0.2..3.0`, step `0.1` |
| Player forward speed | `320 px/s` |
| Mountain target tile | `(2104, 464)` |
| Initial stand tile | `(2103, 465)` |

Probe всегда вызывает новый мир с default mountain/foundation/lake resources,
которые использует экран создания игры. Save slot и состояние предыдущей игры
не читаются. Сцена затем выполняет свой dev-only scan и телепорт к одной и той
же runtime-горе.

## Целевая конфигурация S1

| Поле | Значение |
|---|---|
| Godot | `4.7.stable.official.5b4e0cb0f` |
| Build | debug |
| Renderer | Forward+, D3D12 |
| Base viewport | `1280x720`, canvas-items stretch |
| Acceptance window | windowed `1792x1008`; размер во время сравнительных прогонов не менять |
| VSync / display | on / `1920x1080 @ 60 Hz` |
| CPU | AMD Ryzen 5 2600, 6C/12T |
| GPU | NVIDIA GeForce GTX 1060 6GB, driver `32.0.15.8142` |
| RAM / OS | 32 GiB / Windows 10 Education 10.0.19045 x64 |

## Автоматические доказательства

Команды выполнялись headless, поэтому они подтверждают runtime contract, но не
являются доказательством оконных FPS/GPU timings или визуала.

```powershell
& '.\Godot_v4.7-stable_win64_console.exe' --headless --path . `
  --script res://tools/mountain_runtime_dig_dev_scene_smoke_test.gd

& '.\Godot_v4.7-stable_win64_console.exe' --headless --path . `
  --script res://tools/mountain_runtime_dig_dev_scene_determinism_test.gd
```

Результат 2026-07-22:

- runtime spawn, native mountain masks и копание: `OK`
- два независимых экземпляра: одинаковые probe config, worldgen signature,
  mountain tile и stand tile
- наблюдавшийся первый headless scene-ready: `3198.707..4011.063 ms`
- повторный warm-cache scene-ready: `1862.311..1924.897 ms`

Это `scene-ready`, а не честное время загрузки обычной новой игры: показатель
включает dev scan и телепорт к горе, но не включает время до входа в `_ready()`.
Оба процесса завершились с code `0`; текущие тестовые раннеры при завершении
Godot также печатают предупреждения об оставшихся ObjectDB/resource instances.

## Ручной F4-маршрут S1-MOUNTAIN-SOUTH-01

Codex не управляет окном и вводом. Прогон выполняет пользователь.

1. Открыть `mountain_runtime_dig_dev_scene.tscn` в Godot и запустить текущую
   сцену через `F6`. Сразу после появления игрового окна, не дожидаясь probe
   `READY`, включить `F4`: эта же сессия обязана записать старт, spawn,
   dev-телепорт, подготовку и последующее непрерывное движение.
2. Дождаться строки HUD `S1 probe ... ready ...`; проверить seed `131071` и
   prefix worldgen `b797f412`.
3. Не менять размер окна, VSync и графические настройки.
4. Сделать `F2` у стартовой горы при 09:00 и zoom `1.0`.
5. Восемь раз прокрутить колесо вниз до zoom `0.2`, подождать 2 секунды и
   сделать второй `F2`.
6. Не выключая уже запущенный `F4`, двигаться в основном на юг клавишей `S`
   80 секунд на максимальной обычной скорости. Препятствия обходить короткими
   `A/D`, после чего продолжать на юг. Не останавливаться для ожидания streaming и не
   менять zoom.
7. Остановиться без ожидания catch-up, сразу сделать `F2`, затем выключить
   `F4`. В trace ожидается не менее `20 000 px` фактического пути; иначе прогон
   повторяется.
8. Записать абсолютный путь к `user://performance_captures/<session_id>/` и
   передать его Codex для summary.

Route shape проверяется без изменения capture:

```powershell
& '.\tools\agent\Test-S1MountainCapture.ps1' `
  -CaptureDirectory '<absolute performance_captures session directory>'
```

Analyzer возвращает code `0` только при общей длительности 80–120.5 секунд,
наличии фиксированной горы в trace, минимум 60 секундах после установки zoom
0.2, движении на юг от 20 000 px без учета dev-телепорта, наличии F2 bookmark,
Forward+/D3D12 и VSync 60 Hz. Probe ID, 09:00 и визуальную полноту
дополнительно подтверждает screenshot HUD.

Отдельный visual pass начинается с нового запуска той же сцены:

1. `F2`: day / mountain / torch off.
2. `N`, подождать стабилизацию света; `F2`: night / mountain / torch off.
3. `F`; `F2`: night / mountain / torch on.
4. Вкопаться в гору штатным `E`, не менее чем на шесть тайлов; `F2`: cave /
   torch on. Затем `F`; `F2`: cave / torch off.
5. Для plains/dense objects используются начало, путь и endpoint основного F4
   прогона; скриншоты считаются reference только после выбора пользователем.

## Предварительные числовые пороги для S8

Пороги фиксируют целевой опыт, а не объявляют текущий baseline успешным:

| Метрика | Предлагаемый gate |
|---|---|
| Average FPS при VSync | `>= 59.5` после warm-up |
| Frame time P95 | `<= 16.67 ms` |
| Frame time P99 | `<= 20.0 ms` |
| Max ordinary frame | `<= 33.3 ms`; любой не-tainted frame `>= 50 ms` — fail |
| Viewport CPU P95 | `<= 12.0 ms` |
| Viewport GPU P95 | `<= 12.0 ms` |
| Visible missing/unready terrain or required object layers | всегда `0` |
| Queue drain после остановки | до steady state за `<= 2.0 s` |
| Working-set growth | после warm plateau не более `+10%` за 10 минут пути |
| Zoom round-trip | `0` новых generation/load/unload requests из-за одного zoom |

F2-синхронизация, автоматические recorder screenshots, первый запуск shader
pipeline и время до probe-ready исключаются только там, где recorder помечает
кадр как tainted/startup. Player-visible streaming hitch исключать нельзя.

## Closure artifacts

- основной capture: `S01_BASELINE_CAPTURE_20260722_225301_036.md`
- visual references: `S01_VISUAL_MATRIX_2026-07-22.md`
- candidate report: `S01_CLOSURE_REPORT_2026-07-22.md`
