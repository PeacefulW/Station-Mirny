---
title: Архитектура выравнивания ownership и разделения соседних гор (Mountain Ownership Alignment and Separation Architecture)
doc_type: design_proposal
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-04-22
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - mountain_generation.md
  - MOUNTAIN_GENERATION_ARCHITECTURE.md
---

# Архитектура выравнивания ownership и разделения соседних гор

> Это `design proposal`, а не `source of truth`.
> Документ не заменяет `mountain_generation.md`.
> Он описывает узкий amendment-путь поверх текущего approved mountain contract:
> только три изменения — `owner-aware base boundary`, `peak-oriented owner candidates`
> и `top-2 dominance + neutral saddle`.
>
> Перед реализацией обновить approved spec
> `docs/02_system_specs/world/mountain_generation.md`,
> зафиксировать acceptance tests и bump `world_version`.

## 0. TL;DR

Текущий approved mountain contract уже умеет:

- детерминированный `mountain_id`
- roof / cover presentation
- excavation + cavity visibility
- persistence of `worldgen_settings.mountains`

Но у него остается визуально и топологически неприятный дефект:
две логически разные горы могут выглядеть как один сваренный массив.

Причина не одна, а три:

1. `base presentation mismatch`:
   базовый atlas/shape solve может продолжать силуэт через любой соседний
   mountain-like tile, даже если сосед уже принадлежит другому `mountain_id`
2. `weak owner birth`:
   owner-candidate может родиться слишком низко, почти на outer edge / foot-band,
   и тем самым искусственно порезать один массив на несколько owners
3. `nearest-only resolve`:
   спорные тайлы между двумя горами насильно достаются одному ближайшему anchor,
   вместо того чтобы уходить в нейтральную saddle / separation zone

Рекомендуемое узкое исправление — только три шага:

- `base atlas` должен читать границы по `same mountain_id`, а не по
  "любой горный сосед = продолжаем массу"
- owner-candidates должны рождаться из сильной части массива
  (`peak-oriented`), а не из случайной точки на слабом склоне
- ownership должен сравнивать минимум двух лучших кандидатов;
  при неуверенном победителе тайл уходит в `neutral saddle`

Ключевой смысл amendment:

- не переписывать reveal / cavity / persistence
- не вводить whole-world merge или global connected-components
- не добавлять новые packet fields
- не плодить новые runtime owners
- исправить именно `ownership semantics` и `base presentation alignment`

## 1. Почему нужен отдельный amendment

Текущий approved `mountain_generation.md` уже описывает рабочую V1-систему,
и этот документ не спорит с ее фундаментом.

Он фиксирует остаточный класс дефектов, который проявляется так:

- игрок видит один слитный wall blob, но на самом деле это уже две разные
  горы с разным поведением
- шов особенно заметен там, где roof / cover уже owner-aware, а base silhouette
  еще воспринимает соседний mountain tile как продолжение той же массы
- при неудачном расположении anchor-cells один массив режется на несколько
  `mountain_id`, хотя визуально и геометрически separation еще не возникла

Практический UX-результат текущего дефекта:

- соседние горы ощущаются не как две естественные горы рядом,
  а как одна неаккуратно надрезанная масса
- пользователь крутит settings, но проблема не исчезает принципиально,
  а лишь становится реже или чаще
- reveal / cavity-система остается формально корректной, но выглядит грязно,
  потому что base и ownership говорят о разных границах

Этот amendment сознательно узкий.
Он не пересобирает весь mountain pipeline, а только дожимает три слабых места,
которые и создают ощущение "сваренных гор".

## 2. Цели дизайна (Design Goals)

- Сделать так, чтобы разные `mountain_id` визуально не выглядели как один
  непрерывный wall mass.
- Оставить текущую V1 cover / cavity / opening architecture без переделки.
- Сохранить `bounded native worldgen` и не вносить глобальный prepass.
- Не вводить новый save shape, новые packet fields или новый runtime owner.
- Оставить детерминизм:
  `world_seed + world_version + worldgen_settings` дают один и тот же результат.
- Сохранить seam-stability across chunk boundaries.
- Исправить семантику ownership, а не лечить симптом только визуальным шейдером.

## 3. Вне scope (Out of Scope)

Этот документ специально не трогает:

- `MountainCavityCache`
- reveal / cover visibility lifecycle
- opening derivation
- persistence shape of `world.json`
- `ChunkDiffV0`
- subsurface and `z != 0`
- новую terrain class для saddle / foothill neutral band
- erosion simulation
- whole-world merge of mountain families
- новую пользовательскую настройку worldgen

В первом amendment-шаге достаточно использовать текущие packet surfaces
и текущий settings surface.

## 4. Law 0 / boundary classification for this amendment

| Question | Answer |
|---|---|
| Canonical, runtime overlay, or visual only? | Это изменение canonical world output. Меняются ownership boundaries, mountain atlas decisions, а местами и сам `mountain_id` result. |
| Save/load required? | Новая save shape не нужна. Но нужен `world_version` bump, потому что canonical output меняется. |
| Deterministic? | Да. Все новые правила должны оставаться pure `f(seed, world_version, coord, settings)`. |
| C++ compute or main-thread apply? | Owner-candidate solve, dominance compare, saddle resolve и atlas decisions остаются в native `WorldCore`. |
| Dirty unit | `32 x 32` chunk для генерации; никакой runtime dirty-unit сверх существующих V1 путей не добавляется. |
| Single owner | `WorldCore` остается единственным owner base mountain output. |
| 10x / 100x scale path | Допустимо, пока весь solve остается bounded local compute по anchor-neighborhood и tile-neighborhood. |
| Whole-world prepass? | Запрещен. |
| Hidden GDScript fallback? | Запрещен. |
| New packet fields? | Не нужны для first amendment. Используются существующие `terrain_ids`, `terrain_atlas_indices`, `mountain_id_per_tile`, `mountain_flags`, `mountain_atlas_indices`. |

## 5. Current root causes

### 5.1. Base layer still thinks in generic mountain adjacency

Даже если ownership уже разделил горы на `A` и `B`, базовый shape solve может
все еще мыслить так:

- "сосед elevated / mountain-like"
- значит это продолжение того же wall blob

Это неверная логика для мира, где `mountain_id` уже существует как
каноническая идентичность массы.

### 5.2. Owner may be born on a weak slope

Когда owner-candidate допускается уже возле `t_edge`, weak outer shoulder
может стать "центром" горы.
Это слишком низкий уровень сигнала для такой важной семантики.

Итог:
случайный weak anchor начинает владеть куском массы,
который визуально должен принадлежать более сильному peak family.

### 5.3. Nearest-only ownership is too crude

В спорной зоне между двумя горами nearest-only solve насильно приклеивает тайл
к одному из owners, даже если dominance почти равна.
Так рождаются ugly seams без natural saddle.

## 6. Amendment A - Owner-aware base boundary

### 6.1. Проблема

Roof / cover и `mountain_id` уже говорят:
"это другая гора".

Но base atlas / silhouette местами может говорить:
"неважно, что owner другой — сосед тоже mountain, значит продолжаем стену".

Это и создает расхождение между:

- `terrain silhouette`
- `mountain ownership boundary`

### 6.2. Новый контракт

Для mountain presentation на base layer сосед считается
"той же самой массой" только если:

- у него `mountain_id > 0`
- и его `mountain_id == current mountain_id`

Недостаточно проверки:

- `neighbor elevation >= t_edge`
- или `neighbor terrain is mountain-like`

То есть базовый atlas больше не должен решать по правилу
"любой mountain neighbor = continue shape".

Он должен решать по правилу:

- `same owner` -> contiguous mass
- `different owner` -> boundary
- `owner = 0` -> boundary

### 6.3. Что это значит practically

Если у тайла `mountain_id = A`, а у восточного соседа `mountain_id = B`,
то для base atlas это уже граница.
Нельзя рисовать непрерывную стену, как будто это один и тот же массив.

Иначе игрок видит:

- один общий blob внизу
- две разные горы в ownership / roof semantics

Это и есть тот визуальный бред, который надо убрать.

### 6.4. Scope of application

Правило owner-aware boundary применяется к любому base presentation solve,
который формирует silhouette mountain mass:

- `TERRAIN_MOUNTAIN_WALL`
- `TERRAIN_MOUNTAIN_FOOT`, если foot использует mountain atlas logic
- любые будущие derived mountain-face variants

Если в конкретном path foot-band рисуется не mountain-atlas-логикой,
тогда минимум `wall` presentation обязан стать owner-aware.

### 6.5. Implementation shape

Вместо generic "mountain neighbor mask" generator должен строить
`same-owner adjacency mask` для mountain tiles.

Нужный practical contract:

```text
same_owner(tile, neighbor) =
    tile.mountain_id > 0
    and neighbor.mountain_id == tile.mountain_id
```

Далее:

- `terrain_atlas_indices` для mountain base tiles derive-ятся из
  `same-owner adjacency`
- `mountain_atlas_indices` для roof используют тот же boundary principle
- base и roof обязаны читать один и тот же final owner map

Это не требует нового packet field.
Меняется только canonical way of deriving atlas indices.

### 6.6. Performance class

Это почти бесплатный amendment.

Почему:
atlas decision уже существует.
Мы не добавляем новый runtime system —
мы только заменяем условие соседства:

- было: `neighbor is mountain-like`
- стало: `neighbor has same mountain_id`

Класс работы не меняется:
тот же native per-chunk solve, тот же bounded tile-neighborhood.

### 6.7. Acceptance targets

- [ ] разные `mountain_id` не рисуются на base layer как один непрерывный wall blob
- [ ] если `A` и `B` касаются через owner boundary, base atlas показывает boundary, а не continuous face
- [ ] roof и base используют один и тот же ownership boundary
- [ ] chunk seam не ломает owner-aware silhouette

## 7. Amendment B - Peak-oriented owner candidates

### 7.1. Проблема

Сейчас weak point на outer slope может стать owner-candidate,
если она проходит слишком низкий owner threshold.

Это приводит к тому, что owner рождается не из "сердца" горы,
а из случайного места на слабой внешней поверхности.

### 7.2. Новый контракт

`owner-candidate` больше не равен
"любая jitter point, где elevation >= t_edge".

Вместо этого:

- каждая anchor-cell может породить не более одного owner-candidate
- owner-candidate должен находиться в сильной части массива
- owner-candidate должен быть peak-oriented, а не edge-oriented

Практический смысл:

- weak foothill не должен порождать owner
- outer shoulder не должен случайно отрезать кусок у большой соседней горы
- owner должен ощущаться как носитель настоящей peak identity

### 7.3. Candidate threshold

В first amendment owner-candidate threshold поднимается
значительно выше `t_edge`.

Целевой контракт:

- `t_owner_peak` должен быть ближе к `t_wall`, чем к `t_edge`
- по умолчанию допустимо требование `sample_elevation(candidate) >= t_wall`
- отдельный user-facing setting для этого не нужен в первой итерации

Это осознанно сдвигает owner birth в более сильную часть mountain field.

### 7.4. Local peak validation

Недостаточно просто поднять threshold.
Нужно еще проверить, что candidate действительно похож на локальный peak.

Для этого каждая anchor-cell работает так:

1. deterministic jitter point выбирает базовый центр поиска
2. внутри маленького fixed window вокруг нее выполняется bounded search
3. выбирается strongest local point
4. эта точка проходит local maximum validation
5. если suitable peak не найден, anchor-cell не порождает owner вообще

### 7.5. Recommended bounded algorithm

Пример допустимой формы:

```text
for anchor-cell (ax, ay):
    p0 = deterministic_jitter_point(ax, ay)
    best = argmax elevation within fixed search window around p0
    if elevation(best) < t_owner_peak:
        no owner candidate
    else if not local_maximum(best, fixed validate window):
        no owner candidate
    else:
        owner_candidate = best
```

Рекомендуемые guardrails для first implementation:

- `peak_search_radius` небольшой и фиксированный
- `peak_validate_radius` еще меньше
- search and validation windows не зависят от loaded chunks
- никаких global ridge traversals
- никаких connected-components
- никакого "поиска настоящей вершины всей горы"

### 7.6. Why this is enough for first amendment

Нам не нужно находить "идеальную геологическую вершину".
Нужно только убрать самый гнилой случай:

- owner появился на слабом краю
- и начал резать массив там, где не должен

Bounded local-peak validation решает именно это,
не разрушая performance contract.

### 7.7. Determinism and seam stability

Детерминизм сохраняется, если:

- jitter origin детерминирован от `(seed, ax, ay, world_version)`
- search / validation windows фиксированы
- sampling использует те же world coordinates и wrap-safe X, что и current field

Seam stability across chunk boundaries сохраняется, потому что owner-candidate
по-прежнему определяется в мировой системе координат, а не из состояния
загруженного чанка.

### 7.8. Performance class

Это умеренное удорожание native generation, но безопасное.

Цена добавляется на coarse anchor lattice, а не на каждый runtime frame.

То есть:

- не `per-frame`
- не `per-loaded-world`
- не `GDScript`
- не `global`

А просто:
еще один bounded fixed-window solve на anchor-cell.

### 7.9. Acceptance targets

- [ ] weak outer slope больше не порождает owner-candidate
- [ ] owner birth происходит в сильной части массива
- [ ] уменьшено число случаев, где один визуальный massif режется на несколько owners без natural gap
- [ ] deterministic output сохраняется
- [ ] seam stability across chunk boundaries сохраняется

## 8. Amendment C - Top-2 dominance + neutral saddle

### 8.1. Проблема

Даже хороший peak-candidate solve не спасает полностью,
если ownership tile resolve остается nearest-only.

Спорный тайл между двумя peaks может быть:

- почти одинаково "близок"
- почти одинаково "логичен" для обеих гор

Если его все равно насильно выдать одной стороне,
мы снова получим ugly seam или zero-gap adjacency.

### 8.2. Новый контракт

Ownership resolve для elevated tile больше не является
"выбери одного ближайшего owner и закончи".

Он обязан:

- рассматривать минимум двух лучших кандидатов
- уметь определить случай неуверенного победителя
- в случае ambiguity не отдавать тайл ни одному owner

Такой тайл становится `neutral saddle`.

### 8.3. First-pass dominance score

Для first amendment не нужен сложный ridge-family solver.

Достаточно bounded score, который учитывает два фактора:

- `peak strength`
- `distance to candidate`

Минимально достаточная форма:

```text
dominance_score(candidate, tile) =
    peak_strength_weight * candidate_peak_elevation
    - distance_weight * chebyshev_distance(tile, candidate_position)
```

Важно здесь не точное число, а сам контракт:

- сильный peak имеет право контролировать большее плечо
- слабый peak не должен выигрывать только из-за случайной близости на outer slope

Допустимо, что в первой реализации `ridge_alignment_bias` отсутствует.
Если later tuning покажет, что одной силы + distance мало,
это можно добавить отдельным amendment-ом.
В этот документ это сознательно не входит.

### 8.4. Top-2 compare

Для каждого elevated tile:

1. собрать bounded local owner-candidates
2. посчитать score для каждого
3. выбрать `best` и `second_best`
4. проверить dominance margin

Результат:

- если `best` уверенно выигрывает -> тайл принадлежит `best.mountain_id`
- если победитель неуверенный -> тайл становится `neutral saddle`

### 8.5. Ambiguity rule

Тайл считается ambiguous, если:

- `best_score - second_score < dominance_margin`
- или `best_score` слишком слабый сам по себе
- или после локального zero-gap guardrail две разные горы все равно
  касаются orthogonal edge-to-edge

В этих случаях тайл не выдается ни одной горе.

### 8.6. Neutral saddle output

В first amendment neutral saddle intentionally simple:

- `mountain_id = 0`
- `mountain_flags = 0`
- terrain остается на existing neutral ground path
- saddle не участвует в roof ownership
- saddle не участвует в cavity ownership

Это специально скромный первый шаг.
Отдельная terrain class вроде `TERRAIN_MOUNTAIN_SADDLE`
может быть добавлена позже, но сейчас не нужна.

Ключевой смысл:
между двумя горами появляется нейтральная полоса,
вместо того чтобы они клеились edge-to-edge.

### 8.7. Zero-gap guardrail

Чтобы зафиксировать player-facing invariant,
первый amendment может использовать локальный enforcement rule:

- если после initial resolve два orthogonal neighbor tiles имеют
  разные non-zero `mountain_id`
- lower-confidence tile demotes to `neutral saddle`

Это не whole-world post-process.
Это локальный bounded guardrail на tile-neighborhood,
который можно применять в том же native solve.

Target invariant:

- разные `mountain_id` не имеют общего orthogonal edge

Для first amendment не надо обещать hard guarantee в `2..4` tiles.
Достаточно сначала запретить zero-gap adjacency и получить обычно
`1..2` tile natural separation.
Более широкая band — отдельная tuning topic, не обязательная в этой итерации.

### 8.8. Why saddle is better than forced split

Forced split говорит:
"тайл спорный, но все равно приклеим к одному owner".

Neutral saddle говорит:
"тайл спорный, значит он не часть ни одной из двух гор".

Именно это и убирает ощущение искусственно разрезанного blob.

### 8.9. Performance class

Это остается bounded native chunk generation.

Новая цена относительно current nearest-only solve:

- нужно хранить не только best, но и second-best candidate
- нужен margin test
- optional zero-gap local demotion rule

Это умеренное удорожание per-tile solve,
но по-прежнему не требует:

- global prepass
- runtime flood-fill
- GDScript loops over chunk tiles
- loaded-world reconciliation

### 8.10. Acceptance targets

- [ ] разные `mountain_id` не имеют общего orthogonal edge
- [ ] спорные тайлы между двумя peaks уходят в neutral saddle, а не force-attach-ятся к одному owner
- [ ] zero-gap adjacency между разными mountains не воспроизводится на acceptance seeds
- [ ] ownership остается deterministic
- [ ] no whole-world prepass or global connected-components solve appears

## 9. Data and versioning impact

### 9.1. Packet shape

First amendment не требует новых packet fields.

Используются существующие fields:

- `terrain_ids`
- `terrain_atlas_indices`
- `mountain_id_per_tile`
- `mountain_flags`
- `mountain_atlas_indices`

Меняется не shape, а canonical output этих fields.

### 9.2. Save shape

`world.json` shape менять не нужно.
`chunks/*.json` shape менять не нужно.

### 9.3. world_version

Поскольку меняется canonical world output, обязателен `world_version` bump.

Причины:

- ownership boundaries меняются
- часть `mountain_id_per_tile` меняется
- часть `terrain_ids` / `terrain_atlas_indices` меняется
- roof/base alignment меняет deterministic atlas output

Это не optimization-only task.
Это semantic change of generator output.

## 10. Recommended implementation order

### Iteration 1 - Owner-aware base boundary

Самый дешевый и самый безопасный шаг.

Цель:
сначала добиться, чтобы base и roof перестали противоречить друг другу.

Ожидаемый результат:
даже без изменения owner birth часть ugly welded look уже исчезает.

### Iteration 2 - Peak-oriented owner candidates

Цель:
убрать рождение owners на слабом краю массива.

Ожидаемый результат:
уменьшить число artificial splits еще до tile-level dominance solve.

### Iteration 3 - Top-2 dominance + neutral saddle

Цель:
починить именно спорную зону между двумя peaks.

Ожидаемый результат:
исчезают zero-gap adjacency и nearest-only seams.

Такой порядок важен, потому что он дает:

- быстрый визуальный выигрыш сначала
- потом более корректный owner birth
- потом окончательный resolve спорных зон

И при этом не требует одной гигантской risky rewrite.

## 11. Explicit non-goals for the first implementation task

В первом task на основе этого документа не нужно:

- вводить новый terrain id для saddle
- добавлять ridge-family graph merge
- делать global collapse of close peaks into one family
- переписывать cavity / reveal
- менять save schema
- менять packet schema
- заводить новые UI sliders

Это все может обсуждаться позже только если трех правок окажется недостаточно.

## 12. Rejected approaches

### 12.1. Only tuning density / scale / continuity

Это не меняет contract.
Значит defect останется возможным.

### 12.2. Pure visual seam smoothing

Если логика owner остается старой,
визуальный smoothing только маскирует symptom.

### 12.3. Whole-world connected-components merge

Слишком дорого и противоречит local infinite-world architecture.

### 12.4. Hard carveout bands between mountains

Слишком искусственно.
Мир начнет выглядеть как генератор с ножницами, а не естественный рельеф.

### 12.5. Immediate peak-family graph solver

Слишком большой скачок сложности для first amendment.
Три правки из этого документа должны быть проверены раньше.

## 13. Acceptance targets for the future spec amendment

Будущая approved spec amendment должна минимум требовать:

- [ ] base atlas reads `same-owner adjacency` for mountain silhouette
- [ ] owner-candidate birth no longer happens from weak edge-level points
- [ ] ownership resolve uses `top-2 dominance`, not pure nearest-only
- [ ] ambiguous ownership tiles demote to `neutral saddle`
- [ ] different non-zero `mountain_id` do not share orthogonal edge
- [ ] no new packet fields are introduced for the first amendment
- [ ] save shape remains unchanged
- [ ] `world_version` bump is included in the same implementation task
- [ ] current cavity / reveal contract remains intact
- [ ] work stays in native bounded chunk generation

## 14. Final recommendation

This amendment should be treated as the narrow next step after current
`mountain_generation.md`, not as a new parallel architecture.

Recommended decision:

- approve this document as a focused design proposal
- amend `mountain_generation.md` rather than replacing it
- land the change in three ordered iterations
- delete broader / noisier alternative proposals that try to solve
  mountains, reveal, ownership, topology, and family merge all at once

The purpose of this document is discipline:

- one problem class
- three precise fixes
- same current architecture
- no extra fantasy systems
- no performance betrayal

*Конец документа.*
