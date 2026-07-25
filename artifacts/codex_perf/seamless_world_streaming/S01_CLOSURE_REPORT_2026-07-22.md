---
title: S1 Candidate Closure Report
doc_type: closure_report
status: accepted
owner: engineering+design
source_of_truth: false
version: 1.0
last_updated: 2026-07-22
related_docs:
  - S01_BASELINE_MANIFEST_2026-07-22.md
  - S01_BASELINE_CAPTURE_20260722_225301_036.md
  - S01_VISUAL_MATRIX_2026-07-22.md
  - S01_COMPLETION_AUDIT_2026-07-22.md
  - ../../../docs/00_governance/SEAMLESS_WORLD_STREAMING_TASK.md
---

# S1 candidate closure

## Итог

S1 готов как candidate для ручной приемки. Никаких streaming/performance
исправлений не выполнялось. Создан детерминированный стенд, воспроизводимый
маршрут, baseline trace, числовой summary и долговечная visual reference matrix.

Baseline честно показывает исходную проблему:

- черные непрогруженные области видны во всех 13 manual frames основного F4
- clean zoom-0.2 route: `50.561 FPS`, frame P95/P99 `24.313/26.698 ms`
- GPU P95 `23.183 ms`, CPU P95 `4.328 ms`
- visibility wait до `50`, object upload queue до `92` на route
- post-run кадр остается неполным примерно через 5 секунд после остановки
- observed memory: VRAM `1.3→1.6 GiB`, RAM peak `418.8 MiB`

Torch, night lighting, digging and cave/tunnel lighting зафиксированы отдельной
on/off матрицей и работают в baseline.

## Evidence map

| Gate | Evidence |
|---|---|
| Fixed world | determinism test, signature `b797f412...`, target `(2104,464)` |
| Runtime parity | dev scene инстанцирует настоящий `world_runtime_v0` |
| Cold start | window HUD probe-ready `3603 ms`; headless `3199..4011 ms` |
| Continuous route | capture `20260722_225301_036`, validator code `0` |
| Performance/queues/memory | `S01_BASELINE_CAPTURE_20260722_225301_036.md` |
| Visual/function parity baseline | `S01_VISUAL_MATRIX_2026-07-22.md` + selected PNG/JSON |
| S8 thresholds | `S01_BASELINE_MANIFEST_2026-07-22.md` |
| No runtime optimization | S1-owned implementation change ограничен dev probe; production streaming code не менялся |

## Reproducible route

`S1-MOUNTAIN-SOUTH-01`: fixed seed `131071`, fixed mountain, window
`1792x1008`, Forward+/D3D12, VSync 60 Hz; установить zoom `0.2` и двигаться на
юг с максимальной обычной скоростью. Gate: минимум 60 секунд и 20 000 px после
settle zoom. Offline validator дополнительно проверяет checkpoint, renderer и
направление.

## Candidate decision

Для `accepted` требуется только явное решение пользователя, что:

1. маршрут соответствует реальному runtime-тесту;
2. selected day/night/mountain/cave/torch screenshots верно фиксируют текущий
   визуал и функционал;
3. зафиксированные численные S8 gates подходят как критерии будущей работы.

Пользователь принял S1 2026-07-22. S2 разрешен только как отдельная новая
`/goal`; никакая работа S2 в рамках этого closure не выполнялась.

## Final verification

- `mountain_runtime_dig_dev_scene_determinism_test.gd`: exit `0`
- `mountain_runtime_dig_dev_scene_smoke_test.gd`: exit `0`
- `Test-S1MountainCapture.ps1`: exit `0`
- SHA-256 selected PNG source/copy comparison: `7/7` match
- `git diff --check`: clean

Оба Godot headless runner после успешного exit `0` печатают известные
предупреждения об оставшихся ObjectDB/resource instances; они не скрыты и не
используются как доказательство чистого shutdown.
