---
title: Архитектура идентичности и разделения гор (Mountain Identity and Separation Architecture)
doc_type: design_proposal
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-04-21
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - mountain_generation.md
  - terrain_hybrid_presentation.md
  - MOUNTAIN_GENERATION_ARCHITECTURE.md
---

# Архитектура идентичности и разделения гор (Mountain Identity and Separation Architecture)

> Это `design proposal`, а не `source of truth`.
> Перед реализацией обновить approved spec
> `docs/02_system_specs/world/mountain_generation.md`,
> зафиксировать acceptance tests и bump `world_version`.

## 0. TL;DR

Текущий контракт генерации позволяет одному непрерывному горному силуэту
получать несколько разных `mountain_id`, которые стыкуются вплотную. Это
создает визуально неестественные "сваренные" горы: логически они разные, а
геометрически стоят edge-to-edge без естественной седловины.

Рекомендуемый целевой контракт:

- `mountain_id` означает `цельный горный массив (single mountain mass)`, а не
  просто ближайший anchor внутри общего elevated blob
- разные горы могут быть близко, но не могут иметь общий orthogonal edge
- если между двумя peak-доминами нет естественной `седловина (saddle band)` или
  нейтральная `разделяющая полоса (separation band)`, то это одна гора
- base presentation и roof presentation должны читать один и тот же финальный
  ownership result
- исправление не должно превращаться в искусственные carveout-круги или
  пост-фактум раздвигание уже сгенерированных гор

## 1. Проблема

По текущему поведению одна большая elevated area может быть разрезана на
несколько `mountain_id` по nearest-anchor логике. Это корректно для
"независимости соседних гор" только в узком техническом смысле, но плохо
совпадает с визуальным ожиданием игрока.

Наблюдаемый дефект состоит из двух частей:

- `ownership problem`:
  один общий silhouette получает несколько разных owners без обязательного
  natural gap между ними
- `presentation mismatch`:
  base terrain ориентируется на `elevation >= t_edge`, а roof / cover
  ориентируется на `mountain_id`, из-за чего шов между разными горами
  выглядит особенно грязно

Итог:

- игрок видит не две естественные горы рядом, а одну некрасиво надрезанную
  массу
- пользовательские mountain settings могут менять частоту дефекта, но не
  убирают его принципиально

## 2. Цели дизайна (Design Goals)

- Сохранить `естественную генерацию (natural generation)` без искусственных
  кругов, квадратов и ручных carveout around spawn.
- Разрешить `близкие горы (close mountains)`, но запретить их прямой стык
  `edge-to-edge`.
- Сделать `mountain_id` визуально и топологически осмысленным, чтобы одна
  гора ощущалась одной горой.
- Не ломать `детерминизм (determinism)`:
  один и тот же `world_seed + world_version + settings` должен давать один и
  тот же результат.
- Оставить генерацию локальной и bounded:
  без whole-world prepass и без runtime-global connected-components solve.
- Не переносить тяжелую worldgen-логику в GDScript.

## 3. Вне scope (Out of Scope)

Этот дизайн не решает:

- spawn selection / стартовую позицию игрока
- cave reveal rules и текущую cavity/opening логику как отдельную задачу
- полную замену mountain elevation field на erosion simulation
- новые terrain biomes за пределами проблемы идентичности и separation
- ретро-миграцию старых save без `world_version` bump

## 4. Рекомендуемый контракт (Recommended Contract)

### 4.1. Определение горы

`Гора (mountain mass)` это цельный канонический массив, у которого:

- есть один доминирующий peak family / crest identity
- есть внутренняя пространственная связность
- нет необходимости пересекать нейтральную separation band, чтобы оставаться
  "внутри той же горы"

Практический смысл:

- если два peak influence region срастаются без естественной saddle zone, это
  одна гора
- если между ними существует узкая, но реальная natural separation band, это
  две разные горы

### 4.2. Правило разделения

Для двух разных `mountain_id` обязательны все пункты:

- нет общего orthogonal edge
- нет общего diagonal seam, который base layer визуально интерпретирует как
  единый сплошной wall mass
- между owners существует `разделяющая полоса (separation band)` не уже
  `2..4` тайлов

Полоса не обязана быть "чистой травой". Она может быть:

- plains
- rocky foothill
- saddle / low crest shoulder

Но она не должна принадлежать ни одной из соседних гор как обычный
`mountain_id`-owned wall mass.

### 4.3. Правило слияния

Если два peak-кандидата не удается разделить естественной separation band,
генератор не должен насильно делать из них разные горы. В этом случае
они обязаны коллапсировать в один `mountain_id`.

Иначе проект получает именно тот дефект, который уже наблюдается:
один общий массив, разрезанный логически, но не геометрически.

## 5. Рекомендуемая форма генератора (Recommended Generator Shape)

### 5.1. Поле elevation остается основой

Базовый `elevation/ridge field` остается канонической основой формы гор.
Этот дизайн не требует переписывать всю macro-form generation.

Внутри текущего подхода меняется не столько само поле, сколько семантика
ownership поверх него.

### 5.2. Peak candidates должны рождаться из сильных локальных максимумов

Текущая проблема во многом усугубляется тем, что owner anchors могут
квалифицироваться уже на outer edge / foot-band.

Новый контракт:

- `owner peak candidate` может существовать только в зоне сильного горного
  сигнала
- порог owner-кандидата должен быть существенно выше `t_edge`
- owner peak не должен рождаться из случайной точки на слабом внешнем склоне

Практически это означает:

- использовать `peak threshold` ближе к `t_wall` или выше него
- дополнительно проверять `local maximum` внутри bounded neighborhood
- при необходимости хранить не "любую anchor jitter point", а "лучшую peak
  point внутри anchor-cell"

### 5.3. Ownership должен быть score-based, а не nearest-anchor-only

Тайлу недостаточно знать "какой owner ближе". Он должен знать "какой peak
действительно доминирует эту точку".

Рекомендуемая форма:

```text
dominance_score =
    peak_strength
    - distance_falloff
    + ridge_alignment_bias
    - basin_or_shadow_penalty
```

Смысл формулы:

- сильный peak может контролировать большее плечо
- слабый peak не должен просто по случайной близости отрезать кусок у более
  крупной горы
- ridge / crest continuity важнее голой метрики расстояния

Точная математическая форма может быть уточнена позже. Важно не число, а
контракт:

- ownership решается по `dominance`, а не по "кто ближе на сетке"

### 5.4. Ambiguous tiles должны уходить в saddle / separation band

Если для тайла:

- лучший и второй кандидат слишком близки по score
- локальная форма говорит о седловине
- нет уверенного ownership winner

то тайл не должен доставаться ни одной из двух гор.

Он уходит в `нейтральную зону (neutral saddle / separation band)`.

Это ключевой механизм, который предотвращает ugly edge-to-edge contact без
искусственного carveout.

### 5.5. Separation band должна быть канонической частью worldgen

Separation band не должна быть чисто visual post-process трюком.

Она должна существовать в canonical output как часть генерации:

- либо как `mountain_id = 0` и обычный neutral terrain
- либо как future dedicated foothill / saddle terrain class

Для первого шага достаточно более простого контракта:

- neutral separation tiles имеют `mountain_id = 0`
- они не участвуют в roof ownership
- они не считаются частью interior mountain shell

Это уже убирает склейку логически разных гор.

## 6. Правило согласования presentation (Render Alignment Rule)

Base layer и roof layer обязаны использовать одну и ту же финальную
ownership boundary.

Это означает:

- base mountain silhouette не должен определяться только по `elevation >= t_edge`
- если тайл попал в neutral separation band, base layer не должен рисовать его
  так, будто он продолжает обе соседние горы одновременно
- roof adjacency и base adjacency должны опираться на общий resolved owner map

Иначе даже хороший ownership solve будет визуально испорчен mismatch-ом между:

- `terrain silhouette`
- `mountain_id silhouette`

## 7. Как это должно ощущаться игроку (Player-facing Result)

Игрок должен видеть:

- либо одну большую сложную гору
- либо две горы рядом, но с понятной natural saddle / foothill полосой между
  ними

Игрок не должен видеть:

- два отдельных mountain behavior region, которые впритык сварены в один wall
  blob
- искусственные круглые вырезы
- ситуации, где настройки гор меняют не характер мира, а ломают саму
  топологическую вменяемость горных масс

## 8. Производительность (Performance Class)

Это изменение остается `boot-time work` и `native chunk generation`.

Контракт производительности:

- никаких whole-world passes
- никаких runtime connected-components across loaded world
- никаких GDScript loops по chunk tiles для ownership resolve
- bounded neighborhood lookup на tile
- bounded peak-cell search на tile
- optional local maximum check внутри маленького fixed window

Ожидаемая цена относительно current implementation:

- `top-2 candidate score compare` вместо одного nearest compare
- дополнительный ambiguity / margin test
- возможно один local-peak precheck на candidate

Это умеренное удорожание native worldgen и допустимо, пока остается локальным
и pure per chunk.

## 9. Влияние на данные и версионирование (Data and Versioning Impact)

Поскольку это меняет canonical world output, обязательны:

- bump `world_version`
- обновление approved spec `mountain_generation.md`
- проверка `packet_schemas.md` и `save_and_persistence.md` на актуальность

Необязательны на первом шаге:

- новый save payload shape
- новый runtime overlay owner
- новые persisted mountain metadata tables

В простейшем варианте меняется только канонический результат генерации для
существующих packet fields.

## 10. Почему не стоит лечить это иначе (Rejected Approaches)

### 10.1. Только tuning settings

Подкрутка `density`, `continuity`, `scale`, `anchor_cell_size` может снизить
частоту дефекта, но не меняет сам контракт. Значит баг останется возможным.

### 10.2. Post-process "раздвинь горы"

Если сначала сгенерировать склеенные горы, а потом попытаться mechanically
раздвинуть их erosion / mask pass-ом, получится хрупкий и менее детерминированный
pipeline. Причина дефекта сидит на уровне ownership semantics, там и надо
исправлять.

### 10.3. Чисто visual fix

Если оставить current ownership и только сгладить atlas / seam rendering,
логическая проблема останется. Игрок продолжит иметь две разные горы, которые
физически стоят как один объект.

### 10.4. Жесткий искусственный carveout

Это решает совсем другую задачу и производит неестественный мир. Для
разделения соседних гор такой подход неприемлем.

## 11. Acceptance Targets для будущей спеки

Будущая approved spec должна требовать минимум следующее:

- [ ] любые два разных `mountain_id` не имеют общего orthogonal edge
- [ ] base presentation не рисует разные горы как один непрерывный wall blob
- [ ] если separation band не сформировалась естественно, конфликтующие peak
      regions коллапсируют в один `mountain_id`
- [ ] `mountain_id` остается стабильным across chunk seams
- [ ] одинаковый `seed + world_version + settings` дает идентичный результат
- [ ] пользовательские mountain settings меняют плотность и форму гор, но не
      позволяют zero-gap adjacency между разными горами
- [ ] worldgen остается bounded native compute без global prepass

## 12. Suggested Iteration Path

### Iteration 1: Contract + Spec

- обновить `mountain_generation.md`
- зафиксировать новый смысл `mountain_id`
- зафиксировать separation invariants и render alignment rule

### Iteration 2: Native ownership solve

- поднять owner threshold до peak-oriented logic
- перейти с nearest-anchor на dominance scoring
- ввести ambiguity-to-saddle behavior

### Iteration 3: Presentation alignment

- привести base atlas и roof atlas к одному ownership boundary
- убрать визуальное склеивание разных mountains

### Iteration 4: Tuning + proof

- подобрать default settings
- сделать static / screenshot / debug acceptance harness, который ловит
  zero-gap adjacency

## 13. Open Questions

- Нужен ли отдельный terrain id для `saddle / foothill neutral band`, или
  первого шага достаточно с `mountain_id = 0` на существующем neutral terrain?
- Должна ли separation band быть всегда non-walkable, или допустимы редкие
  walkable low-saddle переходы между соседними горами?
- Нужно ли в будущем хранить explicit debug output для `dominance margin`, чтобы
  удобнее ловить пограничные cases при тюнинге?
