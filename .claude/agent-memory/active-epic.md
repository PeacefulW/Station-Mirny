# Epic: In-Game Chunk Debug Overlay

**Spec**: docs/02_system_specs/world/chunk_debug_overlay_spec.md
**Started**: 2026-04-10
**Current iteration**: 2
**Total iterations**: 2

## Documentation debt

- [x] DATA_CONTRACTS.md - add Chunk Debug Overlay Snapshot and Runtime Diagnostic Timeline Buffer contracts.
- [x] PUBLIC_API.md - add read-only diagnostic entrypoints `ChunkManager.get_chunk_debug_overlay_snapshot()` and `WorldPerfMonitor.get_debug_snapshot()`.
- [x] Localization files - add fixed overlay chrome keys for Russian and English.
- [x] DATA_CONTRACTS.md / PUBLIC_API.md - document debug-only F11 overlay log artifact `user://debug/f11_chunk_overlay.log`.
- **Deadline**: after iteration 2
- **Status**: complete; runtime/visual/log acceptance still requires manual in-game validation.

## Iterations

### Iteration 1 - Operational F11 chunk debug overlay

**Status**: completed_static_verification_pending_manual_runtime_check
**Started**: 2026-04-10
**Completed**: 2026-04-10

#### Проверки приёмки (Acceptance tests)

- [x] `assert(GameWorldDebug handles KEY_F11 and toggles WorldChunkDebugOverlay)` - static grep: `KEY_F11`, `toggle_overlay`, `cycle_mode`, and `WorldChunkDebugOverlayScript` are wired.
- [x] `assert(ChunkManager.get_chunk_debug_overlay_snapshot() exists and returns chunks, queue_rows, metrics, radii, player_chunk, active_z)` - static grep confirms function and required keys.
- [x] `assert(WorldRuntimeDiagnosticLog.get_timeline_snapshot() exists and returns bounded structured events with Russian summary and technical record)` - static grep confirms bounded ring fields and structured event fields.
- [x] `assert(WorldPerfMonitor.get_debug_snapshot() exists and exposes fps/frame/world/chunk/visual metrics)` - static grep confirms function and HUD metric keys.
- [x] `assert(WorldChunkDebugOverlay draws only bounded snapshot data and does not call chunk mutation APIs)` - static grep returned no forbidden mutation/perf-steal calls.
- [x] `assert(queue output is grouped or capped and reports hidden_count)` - static grep confirms queue row cap/group helpers and `queue_hidden_count`.
- [x] `assert(timeline dedupe updates repeat_count instead of appending identical entries inside cooldown)` - static grep confirms `EVENT_DEDUPE_COOLDOWN_MS`, dedupe index, and `repeat_count`.
- [ ] Manual human verification: run `res://scenes/world/game_world.tscn`, press F11, walk across chunk borders, and confirm the overlay shows chunk grid, factual load/unload radii, chunk states, queue, timeline, and top metrics without becoming a wall of text.

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - confirmed `Chunk Debug Overlay Snapshot`, `Runtime Diagnostic Timeline Buffer`, `WorldChunkDebugOverlay`, and `get_chunk_debug_overlay_snapshot`.
- [x] Grep PUBLIC_API.md for changed names - confirmed `ChunkManager.get_chunk_debug_overlay_snapshot()`, `WorldPerfMonitor.get_debug_snapshot()`, and `WorldRuntimeDiagnosticLog.get_timeline_snapshot()`.
- [x] Documentation debt section reviewed - required updates completed in this iteration.

#### Files touched

- `docs/02_system_specs/world/chunk_debug_overlay_spec.md` - new feature spec.
- `.claude/agent-memory/active-epic.md` - active epic tracker.
- `core/debug/world_chunk_debug_overlay.gd` - new F11 overlay presentation node.
- `core/debug/world_runtime_diagnostic_log.gd` - bounded structured timeline buffer and code-term glossary additions.
- `core/autoloads/world_perf_monitor.gd` - read-only frame/perf debug snapshot.
- `core/systems/world/chunk_manager.gd` - bounded chunk/queue snapshot and lifecycle diagnostic hooks.
- `scenes/world/game_world_debug.gd` - F11 toggle and Shift+F11 mode cycle wiring.
- `locale/ru/messages.po` - Russian overlay chrome localization keys.
- `locale/en/messages.po` - English overlay chrome localization keys.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - new diagnostic layer contracts.
- `docs/00_governance/PUBLIC_API.md` - read-only diagnostic API entries.

#### Отчёт о выполнении (Closure Report)

Static implementation complete. Runtime scene check in headless mode still crashes in the pre-existing `WorldGenerator._worker_compute_world_pre_pass` path (`Cannot call method 'lock' on a null value`), so visual/runtime overlay validation remains manual in-game verification.

#### Blockers

- Manual in-game verification remains pending.
- Headless scene check is not a valid pass/fail signal for this overlay until the separate world prepass worker crash is addressed.

### Iteration 2 - F11 overlay session log

**Status**: completed_static_verification_pending_manual_runtime_check
**Started**: 2026-04-10
**Completed**: 2026-04-10

#### Проверки приёмки (Acceptance tests)

- [x] `assert(WorldChunkDebugOverlay.LOG_PATH == "user://debug/f11_chunk_overlay.log")` - static grep confirms the constant.
- [x] `assert(set_overlay_visible(true) opens/resets the log once per game process and set_overlay_visible(false) closes it)` - static grep confirms `_ensure_log_file()` on open, `_close_log_file()` on close, and `_log_reset_for_session`.
- [x] `assert(_write_log_snapshot() serializes metrics, queue_rows, timeline_events, and chunks from the existing snapshot)` - static grep confirms the log uses `_snapshot` sections and does not call new world APIs.
- [x] `assert(log writing is throttled and uses the bounded snapshot)` - static grep confirms `LOG_INTERVAL_SEC` and existing snapshot cadence.
- [ ] Manual human verification: start the game, press F11, walk across chunk borders, close F11, and confirm `user://debug/f11_chunk_overlay.log` contains snapshots only for the visible interval and is overwritten after a fresh game process starts.

#### Doc check

- [x] Grep DATA_CONTRACTS.md for `F11 Chunk Debug Overlay Log File` and `f11_chunk_overlay.log` - confirmed.
- [x] Grep PUBLIC_API.md for `user://debug/f11_chunk_overlay.log` - confirmed.
- [x] Documentation debt section reviewed - required updates completed in this iteration.

#### Files touched

- `core/debug/world_chunk_debug_overlay.gd` - log path, open/close lifecycle, throttled snapshot serialization.
- `docs/02_system_specs/world/chunk_debug_overlay_spec.md` - iteration 2 spec and acceptance tests.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - debug log artifact contract.
- `docs/00_governance/PUBLIC_API.md` - debug artifact documentation and forbidden writes.
- `.claude/agent-memory/active-epic.md` - tracker update.

#### Отчёт о выполнении (Closure Report)

Static implementation complete. Runtime file creation and visual/log contents require manual in-game verification because the existing headless scene check still crashes in `WorldGenerator._worker_compute_world_pre_pass`.

#### Blockers

- Manual in-game verification remains pending.
- Headless scene check is not a valid pass/fail signal for this overlay until the separate world prepass worker crash is addressed.
