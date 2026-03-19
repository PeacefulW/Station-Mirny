# Sprint 01 Backlog Board

> Статусы: `Todo` -> `In Progress` -> `Review` -> `Done` (или `Blocked`)

## Todo

| ID | Priority | Task | Estimate (h) | Risk | Dependencies | DoD (short) |
|---|---|---|---:|---|---|---|
| S1-01 | P0 | Day 1: setup + baseline + risks | 8 | Medium | - | Все артефакты дня созданы |
| S1-02 | P0 | Refactor SaveManager -> modules | 8 | High | S1-01 | save/load smoke pass |
| S1-03 | P0 | Refactor BuildingSystem -> services | 8 | High | S1-01 | indoor/build smoke pass |
| S1-04 | P0 | Player balance resource (remove hardcoded numbers) | 6 | Medium | S1-01 | параметры читаются из `.tres` |
| S1-05 | P0 | Crafting v1 (1->1) + recipe data | 8 | Medium | S1-04 | работает хотя бы 1 рецепт |
| S1-06 | P1 | Craft UI v1 | 6 | Medium | S1-05 | крафт из UI + feedback |
| S1-07 | P0 | Mid-sprint smoke and bugfix day | 8 | Medium | S1-02..S1-06 | все smoke green |
| S1-08 | P1 | Power consumers v1 | 8 | Medium | S1-03 | дефицит реально отключает потребителей |
| S1-09 | P1 | Life support v1 (power->O2 coupling) | 8 | High | S1-08 | база «без питания» чувствуется в геймплее |
| S1-10 | P2 | Airlock v0 | 6 | Medium | S1-09 | двухдверная логика + таймер |
| S1-11 | P2 | UX polish (HUD/Craft/Power hints) | 6 | Low | S1-06 | понятный user feedback |
| S1-12 | P0 | Docs update (status/progress) | 6 | Low | all feature tasks | README/progress актуальны |
| S1-13 | P1 | Hardening/perf | 8 | Medium | all feature tasks | baseline не ухудшен |
| S1-14 | P0 | Sprint review + next backlog | 4 | Low | all | review файл + Sprint 02 draft |

## In Progress
- _(empty)_

## Review
- _(empty)_

## Done
- _(empty)_

## Blocked
- _(empty)_

---

## Notes
- Любая задача без чёткого DoD не переводится в `In Progress`.
- Любая задача, расширяющая scope, требует явного trade-off (что снимаем вместо неё).
