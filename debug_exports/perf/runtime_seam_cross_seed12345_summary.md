# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_seam_cross_seed12345.log`
- Lines: `31955`
- Errors: `1`
- Warnings: `17`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `167816.40 ms`
- `Startup.start_to_loading_screen_visible_ms`: `19.78 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `27066.80 ms`

## Frame summary
- Avg: `28.00 ms`
- P99: `113.40 ms`
- Hitches: `102`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`
- Latest catch-up status: `[CodexValidation] catch-up status: blocker=topology stalled_intervals=2 streaming_truth_idle=true redraw_idle=true load_queue=0 load_queue_preview=[] redraw=0 staged_chunk=no staged_data=0 gen_task_id=-1 gen_coord=(999999, 999999) topology_ready=false native_topology=false native_dirty=false dirty=true build_in_progress=true`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 14.0 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 13.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 11.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 14.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 15.0 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 12.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 15.0 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 12.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 13.1 ms (budget 8.0 ms)`
- `WARNING: [Boot] native flora empty for (2, 2) — GDScript flora fallback in worker`
- `WARNING: [WorldPerf] WARNING: ChunkManager.try_harvest_at_world took 2.44 ms (contract: 2.0 ms)`
- `WARNING: [WorldPerf] WARNING: ChunkManager.try_harvest_at_world took 4.37 ms (contract: 2.0 ms)`
- `WARNING: [WorldPerf] WARNING: ChunkManager._on_mountain_tile_changed took 0.58 ms (contract: 0.5 ms)`
- `WARNING: [WorldPerf] WARNING: ChunkManager.try_harvest_at_world took 6.74 ms (contract: 2.0 ms)`
- `WARNING: [WorldPerf] WARNING: MountainRoofSystem._process_cover_step (1, 0) took 2.14 ms (contract: 2.0 ms)`
- `WARNING: [WorldPerf] WARNING: MountainRoofSystem._process_cover_step (1, 0) took 2.05 ms (contract: 2.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] Topology.runtime.scan: 3.42 ms`
- `[WorldPerf] FrameBudgetDispatcher.topology.chunk_manager.topology_rebuild: 3.54 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 3.04 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.70 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 6.39 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 10.23 ms`
- `[WorldPerf] Topology.runtime.scan: 5.37 ms`
- `[WorldPerf] FrameBudgetDispatcher.topology.chunk_manager.topology_rebuild: 5.56 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.65 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 4.68 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 7.93 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 13.74 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 5.15 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.49 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 6.46 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 4.68 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 20.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 5.01 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 7.11 ms`

## Recent CodexValidation lines
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
- `[CodexValidation] route start: preset=seam_cross waypoints=6`
- `[CodexValidation] reached waypoint 1/6 at (8192.0, 0.0)`
- `[CodexValidation] reached waypoint 2/6 at (8192.0, 8192.0)`
- `[CodexValidation] reached waypoint 3/6 at (253952.0, 8192.0)`
- `[CodexValidation] reached waypoint 4/6 at (253952.0, -8192.0)`
- `[CodexValidation] reached waypoint 5/6 at (8192.0, -8192.0)`
- `[CodexValidation] reached waypoint 6/6 at (0.0, 0.0)`
- `[CodexValidation] route complete: preset=seam_cross reached=6/6 draining_background_work=true`
- `[CodexValidation] waiting for world catch-up: preset=seam_cross reached=6/6`
- `[CodexValidation] catch-up status: blocker=topology stalled_intervals=0 streaming_truth_idle=true redraw_idle=true load_queue=0 load_queue_preview=[] redraw=0 staged_chunk=no staged_data=0 gen_task_id=-1 gen_coord=(999999, 999999) topology_ready=false native_topology=false native_dirty=false dirty=true build_in_progress=true`
- `[CodexValidation] catch-up status: blocker=topology stalled_intervals=1 streaming_truth_idle=true redraw_idle=true load_queue=0 load_queue_preview=[] redraw=0 staged_chunk=no staged_data=0 gen_task_id=-1 gen_coord=(999999, 999999) topology_ready=false native_topology=false native_dirty=false dirty=true build_in_progress=true`
- `[CodexValidation] catch-up status: blocker=topology stalled_intervals=2 streaming_truth_idle=true redraw_idle=true load_queue=0 load_queue_preview=[] redraw=0 staged_chunk=no staged_data=0 gen_task_id=-1 gen_coord=(999999, 999999) topology_ready=false native_topology=false native_dirty=false dirty=true build_in_progress=true`
- `[CodexValidation] route drain complete; preset=seam_cross reached=6/6 redraw_backlog=false`
