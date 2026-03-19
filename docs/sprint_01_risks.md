# Sprint 01 Risk Register

| ID | Risk | Probability | Impact | Mitigation | Owner | Checkpoint |
|---|---|---|---|---|---|---|
| R1 | Рефактор SaveManager ломает совместимость сейвов | Medium | High | Сделать миграционный слой ключей + отдельный smoke save/load каждый день | Dev | Day 2/7/14 |
| R2 | Разделение BuildingSystem ломает indoor flood-fill | Medium | High | Выделить indoor solver и прогнать 3 сценария (замкнуто/дырка/2 комнаты) | Dev | Day 3/7 |
| R3 | Крафт v1 конфликтует с инвентарём | Medium | Medium | Сначала unit-like проверки add/remove, затем UI слой | Dev | Day 5/6 |
| R4 | Новые фичи замедляют мир/чанки | Medium | Medium | Снять baseline Day 1 и сравнить Day 13 | Dev | Day 1/13 |
| R5 | Scope creep (добавление «ещё одной фичи») | High | High | Freeze scope + явный trade-off в backlog | PM/Dev | Daily |
| R6 | Разный стиль данных/ключей JSON | Medium | Medium | Ввести соглашение ключей и проверить при review | Dev | Day 2 |

## Escalation Rule
Если риск становится `High + High`, задача переводится в `Blocked`, делается mitigation first.
