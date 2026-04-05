# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_far_loop_postfix2_seed12345.log`
- Lines: `40625`
- Errors: `1`
- Warnings: `13`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `29602.43 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.18 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `16744.32 ms`

## Frame summary
- Avg: `14.50 ms`
- P99: `31.70 ms`
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
- `WARNING: [Boot] apply step for (0, 0) took 8.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 11.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 9.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 8.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 10.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 8.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 9.5 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 9.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 10.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] native flora empty for (2, 2) — GDScript flora fallback in worker`
- `WARNING: [WorldPerf] WARNING: ChunkManager.try_harvest_at_world took 2.80 ms (contract: 2.0 ms)`
- `WARNING: [WorldPerf] WARNING: ChunkManager.try_harvest_at_world took 2.89 ms (contract: 2.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] scheduler.visual_tasks_processed: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 22.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 355.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 11.15 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 15.04 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.85 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 5.63 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 22.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 355.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 9.40 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 10.14 ms`
- `[WorldPerf] FrameBudgetDispatcher.topology.chunk_manager.topology_rebuild: 2.50 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.74 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.78 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.74 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 22.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 355.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 8.78 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 11.46 ms`

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
