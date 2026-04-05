# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_far_loop_postfix3_seed12345.log`
- Lines: `40194`
- Errors: `1`
- Warnings: `11`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `25559.25 ms`
- `Startup.start_to_loading_screen_visible_ms`: `12.78 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `16165.24 ms`

## Frame summary
- Avg: `13.60 ms`
- P99: `32.40 ms`
- Hitches: `19`

## Runtime validation
- Route preset: `far_loop`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`
- Latest catch-up status: `[CodexValidation] catch-up status: blocker=topology stalled_intervals=0 streaming_truth_idle=true redraw_idle=true load_queue=0 load_queue_preview=[] redraw=0 staged_chunk=no staged_data=0 gen_task_id=-1 gen_coord=(999999, 999999) topology_ready=false native_topology=false native_dirty=false dirty=true build_in_progress=true`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 8.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 10.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 8.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 8.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 8.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 8.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 8.5 ms (budget 8.0 ms)`
- `WARNING: [Boot] native flora empty for (2, 2) — GDScript flora fallback in worker`
- `WARNING: [WorldPerf] WARNING: ChunkManager.try_harvest_at_world took 2.47 ms (contract: 2.0 ms)`
- `WARNING: [WorldPerf] WARNING: ChunkManager.try_harvest_at_world took 2.80 ms (contract: 2.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 21.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 355.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 8.46 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 12.21 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.68 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.78 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.80 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 21.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 355.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 9.78 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 10.42 ms`
- `[WorldPerf] FrameBudgetDispatcher.topology.chunk_manager.topology_rebuild: 2.41 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.70 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.65 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.70 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 21.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 355.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 8.51 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 11.09 ms`

## Recent CodexValidation lines
- `[CodexValidation] built validation room`
- `[CodexValidation] removed validation room wall (5, 4)`
- `[CodexValidation] re-placed validation room wall (5, 4)`
- `[CodexValidation] destroyed validation room wall (4, 5)`
- `[CodexValidation] room validation complete`
- `[CodexValidation] placed validation battery (8, 4)`
- `[CodexValidation] removed validation battery (8, 4)`
- `[CodexValidation] power validation complete`
- `[CodexValidation] mined entry tile (63, 0)`
- `[CodexValidation] mined interior tile (64, 0)`
- `[CodexValidation] mined deeper tile (65, 0)`
- `[CodexValidation] moved player back to exterior tile (62, 0)`
- `[CodexValidation] mining + persistence validation complete`
- `[CodexValidation] route start: preset=far_loop waypoints=6`
- `[CodexValidation] reached waypoint 1/6 at (49152.0, 0.0)`
- `[CodexValidation] reached waypoint 2/6 at (49152.0, 32768.0)`
- `[CodexValidation] reached waypoint 3/6 at (221184.0, 32768.0)`
- `[CodexValidation] reached waypoint 4/6 at (221184.0, -32768.0)`
- `[CodexValidation] reached waypoint 5/6 at (0.0, -32768.0)`
- `[CodexValidation] reached waypoint 6/6 at (0.0, 0.0)`
- `[CodexValidation] route complete: preset=far_loop reached=6/6 draining_background_work=true`
- `[CodexValidation] waiting for world catch-up: preset=far_loop reached=6/6`
- `[CodexValidation] catch-up status: blocker=topology stalled_intervals=0 streaming_truth_idle=true redraw_idle=true load_queue=0 load_queue_preview=[] redraw=0 staged_chunk=no staged_data=0 gen_task_id=-1 gen_coord=(999999, 999999) topology_ready=false native_topology=false native_dirty=false dirty=true build_in_progress=true`
- `[CodexValidation] route drain complete; preset=far_loop reached=6/6 redraw_backlog=false`
