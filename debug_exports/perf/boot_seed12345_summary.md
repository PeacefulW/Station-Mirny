# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_seed12345.log`
- Lines: `24552`
- Errors: `1`
- Warnings: `11`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `168914.07 ms`
- `Startup.start_to_loading_screen_visible_ms`: `16.21 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `29586.29 ms`

## Frame summary
- Avg: `7.00 ms`
- P99: `8.60 ms`
- Hitches: `0`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, -1) took 16.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 0) took 14.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 14.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 14.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 12.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 10.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 14.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 11.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 12.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] native flora empty for (2, 2) — GDScript flora fallback in worker`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 10.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.48 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.73 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 2)@z0: 29272.90 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 29348.24 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 29263.04 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 29361.96 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 29418.61 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 5.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.67 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.92 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 29292.63 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -1)@z0: 29424.57 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 29396.89 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 3.32 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.58 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 29386.19 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, -2)@z0: 29520.76 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 29586.29 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
