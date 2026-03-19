# Sprint 01 Baseline (Day 1)

> Заполнить фактическими числами в конце Day 1.

## Environment
- Engine: Godot 4.x
- Scene: `res://scenes/ui/world_creation_screen.tscn` -> `res://scenes/world/game_world.tscn`
- Build: локальный debug

## Metrics

| Metric | Baseline value | How measured | Target by Day 14 |
|---|---:|---|---:|
| Time to playable (sec) | TBD | От нажатия Start до контроля игрока | <= baseline |
| FPS near spawn (avg) | TBD | 30 сек в стартовой зоне | >= baseline |
| Save time (sec) | TBD | `save_game()` в дефолт-слот | <= baseline |
| Load time (sec) | TBD | `load_game()` того же слота | <= baseline |
| Runtime errors (count/5min) | TBD | Лог во время smoke run | 0 P0 |

## Smoke scenarios

| ID | Scenario | Expected |
|---|---|---|
| SM-01 | Создать мир и войти в игру | Игрок управляется, без крит. ошибок |
| SM-02 | Собрать ресурсы | Предметы добавляются в инвентарь |
| SM-03 | Поставить и снести стену | События/ресурсы корректно обновляются |
| SM-04 | Убить врага | Враг умирает, лут/события корректны |
| SM-05 | Save -> Load | Позиция/время/постройки восстановлены |

## Current known issues (Day 1)
- TBD
