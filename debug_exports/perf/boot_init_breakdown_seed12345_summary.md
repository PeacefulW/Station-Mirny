# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_init_breakdown_seed12345.log`
- Lines: `20174`
- Errors: `1`
- Warnings: `11`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `138226.07 ms`
- `Startup.start_to_loading_screen_visible_ms`: `18.36 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `22470.29 ms`

## Frame summary
- Avg: `6.90 ms`
- P99: `6.90 ms`
- Hitches: `0`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [Boot] apply step for (0, -1) took 13.7 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 0) took 13.6 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 0) took 13.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 0) took 13.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (0, 1) took 10.0 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, -1) took 10.4 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, -1) took 14.8 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (1, 1) took 13.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] apply step for (63, 1) took 14.2 ms (budget 8.0 ms)`
- `WARNING: [Boot] native flora empty for (2, 2) — GDScript flora fallback in worker`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 22245.00 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 22274.92 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 22314.15 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 6.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.34 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.53 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 22355.95 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 22340.04 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -1)@z0: 22356.47 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -2)@z0: 22381.24 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 8.00 ms`
- `[WorldPerf] scheduler.visual_queue_depth.full_near: 2.00 ms`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 2.49 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 2.69 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 22278.64 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, -2)@z0: 22428.59 ms`
- `[WorldPerf] scheduler.visual_tasks_processed: 4.00 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 22470.29 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=6.9 ms, p99=6.9 ms, hitches=0`
- `[WorldPerf] Frame budget: dispatcher=3.8ms streaming=0.0ms streaming_load=0.0ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=76.9ms spawn=0.0ms total=80.8ms/6.0ms`
- `[WorldPerf] Boot detail: compute=0.0ms apply=0.0ms redraw=0.0ms topology=0.0ms shadow=0.0ms milestones=1 other=0.0ms | peaks: compute=0.0ms apply=0.0ms redraw=0.0ms topology=0.0ms shadow=0.0ms milestones=0.0ms stream_load=0.0ms stream_redraw=0.0ms`
- `[WorldPerf] Observability: Shadow.stale_age_ms=21835.2ms, Startup.boot_complete=0.0ms, Startup.startup_bubble_ready_to_boot_complete_ms=22470.3ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
