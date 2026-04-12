# Epic: Hydrology Pre-pass Review Closure

**Spec**: docs/water_system_review_2026-04-11.md
**Started**: 2026-04-12
**Current iteration**: 2
**Total iterations**: 2

## Documentation debt

- [ ] DATA_CONTRACTS.md - keep the World Pre-pass native-helper list and lake-mask invariants aligned with the implemented kernels and widened lake id range.
- [ ] PUBLIC_API.md - grep proof required before claiming `not required` for the remaining hydrology perf closure.
- **Deadline**: after iteration 2
- **Status**: pending

## Iterations

### Iteration 1 - Close fully unaddressed review items

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [x] native lake record extraction path added with GDS fallback
- [x] channel sampling unified for height/temperature/moisture/ruggedness
- [x] lake mask widened beyond byte range and overflow guard updated
- [x] full hydrology generation overrides saved and restored with backward-safe fallback
- [x] thermal smoothing no longer duplicates the grid each iteration
- [x] native floodplain strength path added

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed hydrology names - completed
- [x] Grep PUBLIC_API.md for changed hydrology names - completed
- [x] Documentation debt section reviewed - partially complete, final review deferred to iteration 2

#### Files touched

- `core/systems/world/world_pre_pass.gd` - native lake/floodplain paths, unified channel caches, widened lake mask, thermal ping-pong
- `gdextension/src/world_prepass_kernels.h` - native kernel declarations for lake/floodplain work
- `gdextension/src/world_prepass_kernels.cpp` - native lake record extraction and floodplain strength implementation
- `core/autoloads/save_collectors.gd` - full hydrology generation payload save
- `core/autoloads/save_appliers.gd` - full hydrology generation payload restore
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - pre-pass helper and save/load invariant update

#### Отчёт о выполнении (Closure Report)

Pending in session history on 2026-04-12.

#### Blockers

- none

---

### Iteration 2 - Close remaining partial review items

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [x] tuned-only floodplain/erosion regression no longer depends on the old GDS heap propagation path
- [x] `slope_grid` and `rain_shadow` have native helper paths with validated GDS fallback boundaries
- [x] `flow_directions` fallback no longer depends on the old two-pass unresolved plateau sweep
- [x] DATA_CONTRACTS.md reflects the final native-helper set and current lake-mask invariant
- [x] PUBLIC_API.md grep check recorded for changed names

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names
- [x] Grep PUBLIC_API.md for changed names
- [x] Documentation debt section reviewed

#### Files touched

- `.claude/agent-memory/active-epic.md` - tracker updated for review-closure iteration
- `core/systems/world/world_pre_pass.gd` - native slope/rain/deposition wiring and single-pass plateau fallback
- `gdextension/src/world_prepass_kernels.h` - declarations for deposition/slope/rain kernels
- `gdextension/src/world_prepass_kernels.cpp` - implementations for deposition/slope/rain kernels
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - final native-helper list and widened lake-mask invariant

#### Отчёт о выполнении (Closure Report)

Pending current session handoff.

#### Blockers

- none
