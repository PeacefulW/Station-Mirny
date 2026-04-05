# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_seed12345_postfix.log`
- Lines: `15341`
- Errors: `1`
- Warnings: `11`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `30498.63 ms`
- `Startup.start_to_loading_screen_visible_ms`: `12.83 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `16722.52 ms`

## Frame summary
- Avg: `6.90 ms`
- P99: `6.90 ms`
- Hitches: `0`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 9.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 11.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 11.5 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 13.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 8.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 9.1 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 14.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 12.3 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 11.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] native flora empty for (2, 2) — GDScript flora fallback in worker`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 2)@z0: 16238.50 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, 2)@z0: 16271.65 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 16349.23 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -2)@z0: 16393.51 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 16295.01 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 0)@z0: 16418.23 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 16265.21 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 7.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.33 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.41 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, 2)@z0: 16407.23 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 16237.90 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 16319.13 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 16263.61 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 16373.33 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 16338.91 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.24 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.32 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, -2)@z0: 16438.97 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 3.00 ms`
- `[WorldPerf] Shadow.stale_age_ms: 16703.38 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 16722.52 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
