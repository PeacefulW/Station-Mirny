# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/boot_redraw_apply_seed12345.log`
- Lines: `279`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `25160.69 ms`
- `Startup.start_to_loading_screen_visible_ms`: `12.83 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `15440.55 ms`

## Frame summary
- Avg: `6.90 ms`
- P99: `7.40 ms`
- Hitches: `0`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `957.13 ms`
- `WorldPrePass.compute.flow_accumulation`: `802.53 ms`
- `WorldPrePass.compute.flow_directions`: `641.47 ms`
- `WorldPrePass.compute.lake_aware_fill`: `546.22 ms`
- `WorldPrePass.compute.slope_grid`: `391.28 ms`
- `WorldPrePass.compute.spine_seeds`: `374.77 ms`
- `WorldPrePass.compute.erosion_proxy`: `308.99 ms`
- `WorldPrePass.compute.sample_height_grid`: `161.40 ms`
- `WorldPrePass.compute.ridge_graph`: `43.26 ms`
- `WorldPrePass.compute.continentalness`: `38.58 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.46 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.40 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `540.93 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `28.26 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.82 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=6.9 ms, p99=7.4 ms, hitches=0`
- `[WorldPerf] Frame budget: dispatcher=5.3ms streaming=0.0ms streaming_load=0.0ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=5.2ms spawn=0.0ms total=10.6ms/6.0ms`
- `[WorldPerf] Boot detail: compute=0.0ms apply=0.0ms redraw=0.0ms topology=0.0ms shadow=0.0ms milestones=1 other=0.0ms | peaks: compute=0.0ms apply=0.0ms redraw=0.0ms topology=0.0ms shadow=0.0ms milestones=0.0ms stream_load=0.1ms stream_redraw=0.0ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, -2)@z0: 14803.60 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=true state=full_ready phase=done first_pass=true full_ready=true issues=healthy ages(first=-ms full=-ms border=-ms apply=27958ms converge=27958ms) queues(fast=0 urgent=0 near=0 full_near=11 full_far=0) requests(load=false staged=false generating=false) scheduler(step=36.66ms exhausted=true)`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 37.02 ms`
- `[WorldPerf] FrameBudgetDispatcher.total: 37.18 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 14752.57 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, 2)@z0: 15030.40 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, -2)@z0: 14993.34 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 0)@z0: 15108.85 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 15094.85 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 15105.84 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -1)@z0: 15153.26 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 0)@z0: 15260.75 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, -2)@z0: 15178.99 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 15117.68 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, 2)@z0: 15083.07 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 15118.63 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 15071.56 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 2)@z0: 15053.41 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 15062.73 ms`
- `[WorldPerf] Startup.startup_bubble_ready_to_boot_complete_ms: 15440.55 ms`

## Recent CodexValidation lines
- `[CodexValidation] boot proof complete; quitting`
