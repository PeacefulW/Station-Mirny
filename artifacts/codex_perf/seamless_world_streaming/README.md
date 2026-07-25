---
title: Seamless World Streaming Proof Artifacts
doc_type: artifact_index
status: active
owner: engineering+design
source_of_truth: false
version: 1.0
last_updated: 2026-07-22
related_docs:
  - ../../../docs/00_governance/SEAMLESS_WORLD_STREAMING_TASK.md
---

# Артефакты бесшовного стриминга

Этот каталог хранит небольшие доказательства для подцелей S1-S8:

- summary Markdown/JSON
- manifest запуска
- выбранные пользователем reference screenshots
- before/after таблицы

Raw F4 captures по умолчанию остаются в
`user://performance_captures/<session_id>/` и не копируются в Git автоматически.

## Именование

```text
S01_<kind>_<yyyy-mm-dd>.<ext>
S02_<kind>_<yyyy-mm-dd>.<ext>
...
S08_<kind>_<yyyy-mm-dd>.<ext>
```

Каждый summary должен указывать:

- Git revision и dirty-state
- build type, renderer, resolution и hardware
- seed и route id
- F4 capture path/id
- cold start, FPS/frame-time, GPU/CPU и queue metrics
- manual acceptance: pending / accepted / rejected

Большие PNG-серии, raw traces и бинарные профили добавляются только по прямому
решению пользователя.

## S1

- `S01_BASELINE_MANIFEST_2026-07-22.md` — детерминированная probe-конфигурация,
  ручной F4-маршрут, автоматические contract checks и незакрытые доказательства
- `S01_BASELINE_CAPTURE_20260722_225301_036.md` — принятый F4 route baseline,
  performance/queue/memory summary и visual failure evidence
- `S01_EXCLUDED_CAPTURE_20260722_211613_807.md` — историческая F4-запись
  исходной проблемы; исключена из приемки из-за несовпадения probe-конфигурации
- `S01_COMPLETION_AUDIT_2026-07-22.md` — requirement-by-requirement статус и
  точный оставшийся manual gate
- `S01_VISUAL_MATRIX_2026-07-22.md` — выбранные day/night/mountain/cave/torch
  reference captures и functional conclusion
- `S01_CLOSURE_REPORT_2026-07-22.md` — candidate closure и evidence map для
  ручной приемки S1
- `../../../tools/agent/Test-S1MountainCapture.ps1` — read-only validator
  длительности, пути, zoom, стартовой точки и recorder environment

## S2

- `S02_CLOSURE_REPORT_2026-07-22.md` — candidate closure, automatic mountain
  probe evidence, measured diagnostic cost и manual acceptance gate
- `../../../tools/agent/Test-S2MountainReadinessCapture.ps1` — read-only
  validator S1 route shape, F2/F4 readiness schema, concrete reasons и timing
