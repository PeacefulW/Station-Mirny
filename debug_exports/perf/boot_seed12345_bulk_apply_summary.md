# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_seed12345_bulk_apply.log`
- Lines: `276`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `25961.52 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.48 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `15077.45 ms`

## Frame summary
- Avg: `7.30 ms`
- P99: `17.00 ms`
- Hitches: `2`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `951.15 ms`
- `WorldPrePass.compute.flow_accumulation`: `820.42 ms`
- `WorldPrePass.compute.flow_directions`: `658.23 ms`
- `WorldPrePass.compute.lake_aware_fill`: `550.88 ms`
- `WorldPrePass.compute.spine_seeds`: `410.63 ms`
- `WorldPrePass.compute.slope_grid`: `400.74 ms`
- `WorldPrePass.compute.erosion_proxy`: `298.83 ms`
- `WorldPrePass.compute.sample_height_grid`: `157.43 ms`
- `WorldPrePass.compute.ridge_graph`: `42.80 ms`
- `WorldPrePass.compute.continentalness`: `37.38 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `24.16 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.45 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `545.30 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.02 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.82 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] Boot detail: compute=0.0ms apply=0.0ms redraw=0.0ms topology=0.0ms shadow=0.0ms milestones=1 other=0.0ms | peaks: compute=0.0ms apply=0.0ms redraw=0.0ms topology=0.0ms shadow=0.0ms milestones=0.0ms stream_load=0.0ms stream_redraw=0.0ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=true state=full_ready phase=done first_pass=true full_ready=true issues=healthy ages(first=-ms full=-ms border=-ms apply=28265ms converge=28265ms) queues(fast=0 urgent=0 near=0 full_near=14 full_far=0) requests(load=false staged=false generating=false) scheduler(step=30.63ms exhausted=true)`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 32.21 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 32.38 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=7.3 ms, p99=17.0 ms, hitches=2`
- `[WorldPerf] Frame budget: dispatcher=5.6ms streaming=0.0ms streaming_load=0.0ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=5.5ms spawn=0.0ms total=11.2ms/6.0ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, -2)@z0: 14563.35 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 14481.74 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 14413.75 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, -2)@z0: 14788.89 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, 2)@z0: 14743.59 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, 2)@z0: 14633.74 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 14709.04 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 0)@z0: 14923.64 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 14661.13 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 2)@z0: 14654.82 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 14786.29 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 14646.56 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 0)@z0: 14939.50 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 14859.74 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 14851.18 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -2)@z0: 14900.52 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 15077.45 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
