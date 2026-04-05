# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_seed12345_postfix5.log`
- Lines: `15257`
- Errors: `1`
- Warnings: `10`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `28018.21 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.64 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `16650.59 ms`

## Frame summary
- Avg: `6.90 ms`
- P99: `6.90 ms`
- Hitches: `0`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, 0) took 8.1 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, -1) took 8.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 10.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 9.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 9.9 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 9.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 8.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 13.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] native flora empty for (2, 2) — GDScript flora fallback in worker`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] FrameBudgetDispatcher.total: 4.37 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 16168.70 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, 2)@z0: 16080.47 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 16097.64 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -2)@z0: 16216.49 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 16073.39 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 16029.34 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 0)@z0: 16253.50 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 6.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.34 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 3.43 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, 2)@z0: 16230.24 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 16072.05 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 16135.36 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 16198.74 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 16154.83 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.27 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.58 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, -2)@z0: 16273.33 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 2.00 ms`
- `[WorldPerf] Shadow.stale_age_ms: 16630.66 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 16650.59 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
