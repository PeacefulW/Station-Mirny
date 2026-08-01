---
title: Art Direction
doc_type: content_bible
status: approved
owner: design
source_of_truth: true
version: 1.1
last_updated: 2026-08-01
related_docs:
  - ../lore/canon.md
  - ../../02_system_specs/progression/player_visual_presentation_v1.md
---

# Art Direction

## Core visual contrast

The main contrast is:
- outside: cold, muted, hostile, spore-heavy, industrially wounded
- inside the base: warmer, safer, more controlled, more human

## Style direction

Target direction:
- painted, volume-rich 2D
- strong environmental atmosphere
- terrain and architecture readable at gameplay scale

## Palette logic

- exterior: muted oranges, grays, dirty greens, desaturated hostile tones
- interior: warm controlled artificial light
- alien/precursor phenomena may introduce accent colors for mystery and danger

## Asset pipeline direction

Two broad asset families are expected:
- terrain/tiles for surfaces and architecture
- volume-rich objects/creatures/equipment, potentially derived from a 3D-to-2D workflow

### Directional turntable atlas contract

Любой объект, который запекается по кругу в directional atlas — персонаж,
транспорт, существо или оборудование, — использует один экранный контракт:

- `direction_index = 0` — объект смотрит строго на экранный север (`Vector2.UP`);
- строки идут по часовой стрелке, если смотреть на готовый спрайт на экране;
- при 16 направлениях шаг равен `22.5°`, cardinal rows: север `0`, восток `4`,
  юг `8`, запад `12`;
- metadata обязана явно хранить `direction_zero = screen_north` и
  `direction_order = clockwise`;
- знак Blender yaw не считается частью контракта: его измеряют cardinal probe
  конкретной модели, чтобы готовые строки действительно смотрели N/E/S/W;
- runtime consumer индексирует строки тем же экранным соглашением и не вводит
  собственный offset или обратный порядок.

Для циклических клипов endpoint-дубликат исходной анимации не включается в
атлас. Фазы берутся равномерно на полуинтервале `[cycle_start, cycle_end)`, а
bake обязан численно проверить переход последнего кадра к первому. Произвольно
обрезанный fragment нельзя объявлять loop без доказанного бесшовного endpoint.

## Acceptance criteria

- the player can immediately feel “outside bad, inside safe”
- alien life and precursor technology look meaningfully distinct
- readability is preserved despite atmospheric mood
