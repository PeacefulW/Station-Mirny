# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_far_loop_postfix7_seed12345.log`
- Lines: `39472`
- Errors: `1`
- Warnings: `13`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `29893.02 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.79 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `18438.79 ms`

## Frame summary
- Avg: `13.80 ms`
- P99: `25.00 ms`
- Hitches: `4`

## Runtime validation
- Route preset: `far_loop`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`
- Latest catch-up status: `[CodexValidation] catch-up status: blocker=topology stalled_intervals=0 streaming_truth_idle=true redraw_idle=true load_queue=0 load_queue_preview=[] redraw=0 staged_chunk=no staged_data=0 gen_task_id=-1 gen_coord=(999999, 999999) topology_ready=false native_topology=false native_dirty=false dirty=true build_in_progress=true`

## WorldPrePass phases
- `WorldPrePass.compute.river_extraction`: `1984.92 ms`
- `WorldPrePass.compute.lake_aware_fill`: `1654.87 ms`
- `WorldPrePass.compute.continentalness`: `1596.39 ms`
- `WorldPrePass.compute.rain_shadow`: `1017.96 ms`
- `WorldPrePass.compute.flow_accumulation`: `829.57 ms`
- `WorldPrePass.compute.flow_directions`: `660.29 ms`
- `WorldPrePass.compute.spine_seeds`: `433.72 ms`
- `WorldPrePass.compute.slope_grid`: `405.94 ms`
- `WorldPrePass.compute.erosion_proxy`: `307.45 ms`
- `WorldPrePass.compute.sample_height_grid`: `156.97 ms`
- `WorldPrePass.compute.ridge_strength_grid`: `68.13 ms`
- `WorldPrePass.compute.ridge_graph`: `43.02 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.river_extraction.distance_propagation`: `1968.72 ms`
- `WorldPrePass.compute.continentalness.distance_propagation`: `1560.76 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `1100.65 ms`
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `553.00 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `30.61 ms`
- `WorldPrePass.compute.river_extraction.seed_river_sources`: `15.96 ms`
- `WorldPrePass.compute.continentalness.normalize_output`: `2.94 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 8.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 8.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 13.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 11.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 10.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 9.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 13.0 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 10.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 10.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] native flora empty for (2, 2) — GDScript flora fallback in worker`
- `WARNING: [WorldPerf] WARNING: ChunkManager.try_harvest_at_world took 2.57 ms (contract: 2.0 ms)`
- `WARNING: [WorldPerf] WARNING: ChunkManager.try_harvest_at_world took 3.56 ms (contract: 2.0 ms)`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 23.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 350.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 9.11 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 12.92 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.73 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.71 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.57 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 23.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 350.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 8.54 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 9.26 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.10 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 2.82 ms`
- `[WorldPerf] ChunkManager.streaming_redraw_step.terrain: 5.43 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 4.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.terrain_near: 23.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_far: 350.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 11.47 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 13.61 ms`

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
