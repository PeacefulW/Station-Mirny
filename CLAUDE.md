# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"Станция Мирный" (Station Mirny) — 2D top-down survival base-builder built in Godot 4.6 with GDScript and GDExtension (C++). Russian is the primary development language for comments, docs, and UI text; English is used for code identifiers.

## Build and Run

- Open project in Godot 4.6+ editor
- Run via F5 (entry scene: `res://scenes/ui/main_menu.tscn`)
- GDExtension native build: `cd gdextension && scons` (requires SCons + C++ toolchain)
- No automated test framework; validation scripts live in `tools/` and are run manually from the editor

## Governance — Required Reading

This project has a doc-driven governance model. **Read docs before code.**

Claude Code project settings in `.claude/settings.json` default to `plan` mode and run guard hooks. Treat hook feedback as part of the project workflow, not as optional advice.

Reading order for every task:
1. `AGENTS.md` — agent discipline rules (scope, forbidden behaviors, closure report format)
2. `docs/00_governance/WORKFLOW.md` — task execution procedure
3. `docs/00_governance/PUBLIC_API.md` — which functions to call (if not listed, don't call it)
4. `docs/02_system_specs/world/DATA_CONTRACTS.md` — data layers, owners, invariants (for world tasks)
5. The relevant feature spec, then code

Document precedence when conflicts arise: `ENGINEERING_STANDARDS.md` > `PERFORMANCE_CONTRACTS.md` > ADRs > system specs > GDD > content bible > execution docs. Full rules: `docs/00_governance/DOCUMENT_PRECEDENCE.md`.

## Architecture

### Autoloads (singletons, load order in project.godot)

`EventBus` — global signal bus for inter-system communication. All cross-system events go through here.
`GameManager` — input setup, game-over state.
`TimeManager` — day/night cycle, seasons, time scale.
`BiomeRegistry`, `FloraDecorRegistry`, `WorldFeatureRegistry`, `ItemRegistry` — data-driven registries. Content accessed by namespaced string IDs (`"base:iron_ore"`), never by `load()` paths.
`WorldGenerator` — world seed and generation orchestration.
`SaveManager` — save/load orchestration. Multi-file JSON per slot under `user://saves`. Delegates to `SaveCollectors`/`SaveAppliers`/`SaveIO`.
`Localization` — wrapper over `tr()` with named args: `Localization.t("KEY", {"arg": val})`.
`SettingsManager` — user settings persistence.
`FrameBudgetDispatcher` — central per-frame budget (6ms total) for background systems. Priority order: streaming > topology > visual > spawn.
`WorldPerfMonitor` — runtime performance tracking.
`PlayerAuthority` — player state authority.

### Core Directories

```
core/autoloads/      — singleton scripts (registered in project.godot)
core/systems/        — game systems: world/, building/, power/, survival/, crafting/, commands/, daylight/, lighting/, state_machine/, game_stats.gd
core/entities/       — entity scripts: components/, player/, structures/, items/, fauna/, factories/, recipes/, resources/
core/runtime/        — runtime budget/dirty queue infrastructure
core/debug/          — debug utilities
data/                — Resource (.tres) definitions: balance/, biomes/, buildings/, items/, recipes/, etc.
scenes/              — scene files: world/ (GameWorld), ui/ (menus, HUD, panels), player/
locale/              — translations: ru/, en/ (.po files)
gdextension/         — C++ native code (SCons build, station_mirny.gdextension)
docs/                — canonical documentation (see docs/README.md for full index)
tools/               — validation scripts, asset generators
```

### Mandatory Architectural Patterns

1. **Command Pattern** for world mutations — all state-changing actions (build, mine, craft, pickup) go through `CommandExecutor.execute()` as command objects with `execute()`/`undo()`. Located in `core/systems/commands/`.

2. **Compute -> Apply** two-phase — heavy operations split into pure-data compute (can be deferred/threaded) and bounded main-thread apply. Never mix computation with scene-tree mutation.

3. **Data-driven registries** — gameplay content defined as `.tres` Resources with stable IDs. All lookups via registry autoloads, never `load("res://data/...")`.

4. **Deterministic hashing** — visual/content variation by world position uses deterministic hash (`_hash32_xy()` in `chunk.gd`: `(tile_x * 374761393 + tile_y * 668265263 + seed * 1442695041) & _HASH32_MASK`), never `randf()`/`randi()`.

5. **EventBus** — systems emit domain events instead of direct coupling. UI subscribes/dispatches but doesn't own game-state mutation.

6. **Dirty queue + budget** — heavy runtime work uses: `event -> dirty queue -> per-frame budgeted processing -> eventual completion`. No full rebuilds in interactive paths.

### Components (core/entities/components/)

Reusable cross-entity behaviors: `HealthComponent`, `InventoryComponent`, `EquipmentComponent`, `NoiseComponent`, `PowerSourceComponent`, `PowerConsumerComponent`.

## Code Conventions

- GDScript naming: `snake_case` files/vars/funcs, `PascalCase` classes, `UPPER_SNAKE_CASE` constants, `_private_name` for private members
- Signals: past tense (`building_placed`, `item_crafted`)
- Booleans: `is_`, `has_`, `can_` prefixes
- Explicit typing on every variable, parameter, and return value
- Script order: class_name > extends > docs > signals > enums > constants > exports > public vars > private vars > Godot builtins > public methods > private methods
- No user-facing text in code — use `Localization.t("KEY")` with keys from `locale/` .po files
- Localization key families: `UI_*`, `ITEM_*`, `BUILD_*`, `FAUNA_*`, `FLORA_*`, `RECIPE_*`, `LORE_*`, `TUTORIAL_*`, `SYSTEM_*` (suffix `_DESC` for descriptions)
- Data resources store localization keys (`display_name_key`), not translated text
- Commit style: `feat(system):`, `fix(system):`, `refactor(system):`, `docs:`, `data(scope):`

## Performance Rules

- Interactive operations (mine tile, place building) must stay under 2ms synchronous
- Background work budget: 6ms/frame total via `FrameBudgetDispatcher`
- Forbidden in interactive path: full chunk redraw, full topology rebuild, mass `add_child`/`queue_free`/`set_cell`/`clear`, loop over all loaded chunks
- If one tile changes, update only a local dirty region, never a full system
- Use `WorldPerfProbe` for instrumentation on runtime-sensitive paths

## Save/Load

- Save version: 4. Files per slot: `meta.json`, `player.json`, `world.json`, `time.json`, `buildings.json`
- Persistent systems define what belongs in save state vs. generated/base data
- Runtime diffs, not full state — base data is regenerated from seed
- Serialize as data, not implicit scene state

## Task Completion

Every completed task requires a closure report (format in `AGENTS.md` and `docs/00_governance/WORKFLOW.md`). Update `DATA_CONTRACTS.md` and `PUBLIC_API.md` if data layers or API surfaces changed.

Useful project commands:
- `/mirny-plan` — scoped plan-mode analysis before implementation
- `/mirny-spec` — create or refine a feature spec before code
- `/mirny-fix-prompt` — convert a vague bug into a bounded implementation prompt
- `/mirny-closure` — prepare closure report with verification evidence
- `/mirny-resume` — resume the active epic from `.claude/agent-memory/active-epic.md`

## Skills (`.claude/skills/`)

The project includes custom skills that enforce workflow discipline. Use them:

**Workflow discipline:**
- **`verification-before-completion`** — activates before writing a closure report. Requires running a concrete verification command (grep, file read, validation script) for each acceptance test before marking it "passed." Never write "passed" without evidence.
- **`brainstorming`** — activates when the user proposes a new feature or asks "как лучше сделать...". Guides a structured exploration phase (understand intent → map to architecture → explore alternatives → identify risks → produce design brief) BEFORE creating a formal spec.
- **`persistent-tasks`** — activates when working on multi-iteration features or resuming previous work. Maintains `.claude/agent-memory/active-epic.md` with iteration status, acceptance test progress, and blockers. Read this file at session start to know where things were left off.
- **`mirny-task-router`** — broad routing for Station Mirny requests; delegates to the right specialist skill.
- **`bugfix-prompt-smith`** — converts a vague bug report into a narrow, contract-aware implementation prompt following WORKFLOW.md.
- **`playtest-triage`** — converts raw playtest notes into prioritized actionable tasks with root cause and routing hints.

**Performance & architecture:**
- **`frame-budget-guardian`** — enforces frame-budget discipline; blocks proposals that risk full rebuilds or interactive-path violations.
- **`world-perf-doctor`** — diagnoses hitchy world interactions: mining, building placement, chunk seam redraws, topology churn.
- **`loading-lag-hunter`** — diagnoses long boot, loading-screen drag, streaming spikes, and first-playable delays.
- **`save-load-regression-guard`** — guards save/load boundaries and runtime diff ownership; catches restore regressions.

**Content & lore:**
- **`content-pipeline-author`** — adds/changes items, buildings, recipes, flora, POIs through registry/data/localization/mod path.
- **`balance-simulator`** — reasons about balance, progression pacing, resource pressure, expedition cost, and strategic tradeoffs.
- **`lore-bible-architect`** — expands or reorganizes lore while preserving locked canon.
- **`faction-voice-keeper`** — maintains distinct voice, ideology, and terminology for factions and diegetic text.
- **`poi-story-seeder`** — generates place-based story hooks, ruin history, and environmental storytelling for locations.

**UI & copy:**
- **`ui-experience-composer`** — shapes UI work as game-feel, readability, and atmosphere.
- **`ui-copy-tone-keeper`** — keeps player-facing copy consistent with tone and the localization-ready UI model.
- **`localization-pipeline-keeper`** — enforces the localization pipeline when a task adds or changes player-facing text.

**Experience contracts:**
- **`sanctuary-contrast-guardian`** — enforces the non-negotiable inside-safe / outside-hostile contrast.

## Agents (`.claude/agents/`)

Specialized subagents for specific tasks: `impl-planner` (feature planning), `arch-check` (architecture validation), `gdscript-review` (code review), `perf-audit` (performance analysis), `data-validator`, `docs-reviewer`, `loc-audit`, `save-audit`, `signal-tracer`, `worldgen-debug`.
