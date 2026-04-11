---
title: Reachable Structure Coverage After Pre-pass Migration
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-04-09
depends_on:
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - native_chunk_generation_spec.md
  - natural_world_constructive_runtime_spec.md
related_docs:
  - world_lab_spec.md
  - ../../04_execution/world_generation_rollout.md
---

# Feature: Reachable Structure Coverage After Pre-pass Migration

## Design Intent

После перевода runtime и native path на одну authoritative `WorldPrePass` truth мир должен:

- сохранять один источник правды для ridges / rivers / floodplains / mountain mass;
- сохранять native/script parity;
- оставлять воду и горы реально находимыми в обычной surface exploration, а не только на крайних широтах;
- не лечиться seed-specific threshold hacks или возвратом legacy band logic.

Эта спека не про новый world model.
Она про исправление coverage/regression после миграции, когда сильнейшие видимые river/mountain окна оказываются слишком далеко от spawn-facing центра мира.

## Audit Summary

На текущем checkout подтверждено:

- `ChunkGenerator` больше не использует legacy `sample_structure()` как active runtime truth;
- current native local parity proof around spawn passes;
- current structure-visibility proof still finds visible `WATER` and `ROCK`, то есть они не исчезли полностью;
- однако proof for seed `12345` находит strongest visible river/mountain windows у extreme latitude bands (`y ~= -4064`, `y ~= -3648`), а не рядом с temperate central bands.

Из кода подтверждены две вероятные причины coverage collapse:

1. `WorldComputeContext._derive_river_strength_from_prepass()` и native mirror почти не учитывают proximity:
   - `river_strength` в основном равен функции от `river_width`;
   - бонус за river core срабатывает только при `river_distance <= 0.001`;
   - после bilinear pre-pass sampling это слишком жёсткое условие для consumer semantics.

2. `WorldPrePass` системно тянет hydrology и mountain seeding к global extremes:
   - `_resolve_base_accumulation()` даёт cold cells glacial melt bonus;
   - `_resolve_downstream_transfer()` уменьшает evaporation in cold bands;
   - `_resolve_spine_selection_score()` выбирает global top candidates по `height + ruggedness` без latitude / regional distribution guard;
   - `_compute_mountain_mass_grid()` дополнительно сжимает massif signal до terrain-stage.

Итог:

- проблема выглядит не как “native path всё сломал”;
- проблема выглядит как “после миграции authoritative truth стала честной, и выяснилось, что сама pre-pass truth + consumer handoff дают poor reachable coverage”.

## Non-Goals

- не возвращать legacy directed-band sampling;
- не вводить второй parallel structure pipeline;
- не добавлять reroll/remediation loop по seed;
- не менять `ChunkManager`, save/load, mining, topology, reveal, presentation, кроме proof hooks;
- не расширять canonical terrain enum.

## Data Contracts - affected

### Affected layer: World Pre-pass

- Что меняется:
  - распределение river extraction / ridge seed selection / mountain mass semantics может быть перебалансировано, чтобы structures не коллапсировали в extreme latitude bands.
- Инварианты:
  - `WorldPrePass` остаётся единственным authoritative source of truth для large-scale structures;
  - same seed -> same pre-pass snapshot;
  - rebalance не вводит seed-specific overrides;
  - rebalance не требует post-hoc remediation pass.

### Affected layer: Structure Context

- Что меняется:
  - `river_strength` semantics должны стать continuous function of width + proximity, а не почти pure-width signal с near-zero equality gate.
- Инварианты:
  - `WorldComputeContext.sample_structure_context()` и native mirror возвращают одинаковую structure semantics;
  - runtime consumers не читают raw pre-pass arrays напрямую вместо curated context.

### Affected layer: World (canonical terrain)

- Что меняется:
  - terrain placement должен снова делать `WATER` / `SAND` / `ROCK` discoverable inside central exploration bands for agreed proof seeds.
- Что не меняется:
  - `GROUND / ROCK / WATER / SAND` остаются canonical surface terrain classes;
  - spawn safety and land guarantee semantics не меняются.

### Affected layer: Native Chunk Authoritative Inputs / parity

- Что меняется:
  - если меняется meaning of `river_strength`, `mountain_mass`, river/bank/mountain thresholds, native mirror must be updated in the same iteration.
- Инварианты:
  - script/native parity remains mandatory after every rebalance step.

## Iterations

### Iteration 1 - Coverage Proof Harness

Цель: сделать regression measurable, а не субъективной.

Что делается:

- расширить sanctioned proof tooling (`WorldPreviewProofDriver` and/or `WorldLab`) так, чтобы он умел:
  - считать coarse latitudinal band stats;
  - печатать `authoritative river`, `authoritative mountain`, `visible water`, `visible sand`, `visible rock`;
  - печатать nearest-from-spawn distance для visible and authoritative structure hits;
  - отдельно показывать script/native parity status для этих proof seeds.

Acceptance tests:

- [ ] headless proof для fixed seed `12345` пишет band table и nearest distances в log artifact;
- [ ] proof явно отличает `authoritative structure exists` от `terrain consumer made it visible`;
- [ ] proof fail-fast'ит, если native/script terrain counts расходятся beyond agreed tolerance;
- [ ] proof artifact сохраняется в `debug_exports/world_previews/`.

Файлы, которые будут затронуты:

- `core/debug/world_preview_proof_driver.gd`
- `scenes/ui/world_lab.gd` при необходимости
- `docs/02_system_specs/world/reachable_structure_coverage_spec.md`

Файлы, которые не должны быть затронуты:

- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- save/load, mining, topology, reveal, presentation runtime paths

### Iteration 2 - River Coverage Rebalance

Цель: перестать терять river semantics на tile consumer level и уменьшить polar-only hydrology bias.

Что делается:

- переписать `WorldComputeContext._derive_river_strength_from_prepass()` и native mirror на continuous proximity-aware function;
- использовать `river_distance` как полноценную часть river semantic strength, а не только `<= 0.001` core gate;
- rebalance `WorldPrePass` hydrology source terms так, чтобы cold-band glacial melt больше не монополизировал river extraction:
  - `_resolve_base_accumulation()`
  - `_resolve_downstream_transfer()`
  - при необходимости `prepass_river_accumulation_threshold` / related balance knobs;
- сохранить one-truth contract: terrain still follows pre-pass, not a separate water override.

Acceptance tests:

- [ ] `river_strength` meaning is identical in GDScript and C++ for the same `river_width` / `river_distance`;
- [ ] fixed-seed coverage proof показывает non-zero visible `WATER` or `SAND` inside central 50% latitude span on agreed proof seeds;
- [ ] nearest visible river-facing tile from spawn improves versus the pre-fix proof baseline for seed `12345`;
- [ ] native/script parity proof still passes after the river rebalance.

Файлы, которые будут затронуты:

- `core/systems/world/world_compute_context.gd`
- `core/systems/world/world_pre_pass.gd`
- `core/systems/world/surface_terrain_resolver.gd` при необходимости
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres` при необходимости
- `gdextension/src/chunk_generator.cpp`
- `gdextension/src/chunk_generator.h` при необходимости

Файлы, которые не должны быть затронуты:

- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- unrelated gameplay systems

### Iteration 3 - Mountain Coverage Rebalance

Цель: перестать делать mountains visible only at global extreme ridge maxima.

Что делается:

- rebalance ridge seed distribution so a few global maxima do not monopolize the whole world:
  - `_resolve_spine_selection_score()`
  - seed distribution guard or equivalent deterministic regional quota;
- redefine `mountain_mass` as a broader massif-fill signal instead of a double-attenuated near-core-only scalar;
- update mountain terrain consumer weights/thresholds in both script and native mirrors so moderate but real massif zones survive to `ROCK`;
- сохранить spawn safety guarantees and no-dual-truth rule.

Acceptance tests:

- [ ] fixed-seed coverage proof показывает non-zero visible `ROCK` inside central 50% latitude span on agreed proof seeds;
- [ ] nearest visible rock tile from spawn improves versus the pre-fix proof baseline for seed `12345`;
- [ ] authoritative mountain tiles and visible rock tiles no longer collapse almost entirely into extreme latitude bands;
- [ ] native/script parity proof still passes after the mountain rebalance.

Файлы, которые будут затронуты:

- `core/systems/world/world_pre_pass.gd`
- `core/systems/world/surface_terrain_resolver.gd`
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres` при необходимости
- `gdextension/src/chunk_generator.cpp`
- `gdextension/src/chunk_generator.h` при необходимости
- `core/debug/world_preview_proof_driver.gd` при необходимости

Файлы, которые не должны быть затронуты:

- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- save/load, mining, topology, reveal systems

## Required Contract And API Updates

- `DATA_CONTRACTS.md`: да, если меняется documented meaning of:
  - `World Pre-pass` hydrology / ridge distribution invariants;
  - `WorldComputeContext.sample_structure_context()` fields;
  - `World` terrain placement coverage invariants.
- `PUBLIC_API.md`: да, если меняется documented semantic meaning of:
  - `WorldComputeContext.sample_structure_context()`;
  - native chunk generation parity/read semantics.

## Proof Artifacts Required For Completion

Для каждой implementation iteration из этой спеки обязательны:

- fixed seed(s);
- headless proof log in `debug_exports/world_previews/`;
- explicit script/native parity result;
- explicit band table for central vs extreme latitude coverage;
- nearest visible `WATER` / `ROCK` distances from spawn;
- exported preview PNGs for at least one river window and one mountain window.

Нельзя закрывать эту работу формулировками:

- “вода снова иногда встречается”
- “горы вроде бы вернулись”
- “по коду должно быть лучше”

## Out Of Scope

- biome schema redesign;
- flora/decor rebalance outside what is strictly needed for terrain proof;
- chunk streaming, redraw, topology, shadow, or save/load refactors;
- new world types, new terrain enums, or new map projections.
